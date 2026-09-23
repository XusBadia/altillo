import AppKit
import EventKit
import Foundation

/// Peeks five minutes before a calendar event starts (PLAN §5.6: "un aviso 5 min antes").
///
/// Never requests calendar access: only `CalendarStore` does that, the first time the user opens the Calendar
/// module. If access isn't granted yet this source stays quiet, and re-checks the next time EventKit reports a
/// change, the Mac wakes, the clock jumps, a new day starts, or `update(enabled:)` is called again.
///
/// Exactly one timer is ever pending — a `Task` asleep until the next fire date — never a poll loop (PLAN §1.5).
@MainActor
final class CalendarAlertSource {
    private let post: (NotchAlert) -> Void
    private let store: EKEventStore
    private var enabled = false
    private var timerTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    /// Events already peeked about, so a recompute (a new event added nearby, a clock change…) never repeats one.
    /// Keyed by `CalendarAlertEvent.identifier` (event identifier + start date, so a moved occurrence counts as new).
    private var alertedKeys: Set<String> = []

    /// Injected so tests can control "now" without waiting on a real clock.
    var now: () -> Date = { .now }
    /// Injected so tests can hand over a fixed list of events instead of asking EventKit.
    var fetchEvents: () -> [CalendarAlertEvent] = { [] }

    init(post: @escaping (NotchAlert) -> Void, store: EKEventStore = EKEventStore()) {
        self.post = post
        self.store = store
        fetchEvents = { [weak self] in
            guard let self else { return [] }
            return Self.fetchUpcomingEvents(store: self.store, now: self.now())
        }
    }

    /// Starts or stops watching. Idempotent: calling it again with the same value changes nothing (recomputation
    /// happens on its own through the observers below, not by re-calling this).
    func update(enabled: Bool) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled
        if enabled {
            observeIfNeeded()
            recompute()
        } else {
            cancelTimer()
            stopObserving()
        }
    }

    /// Calendar access may have just been granted (from the Calendar section): look again for the next event.
    func accessMayHaveChanged() {
        guard enabled else { return }
        recompute()
    }

    // MARK: - Scheduling

    private func recompute() {
        cancelTimer()
        guard enabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let moment = now()
        guard let next = CalendarAlertScheduling.nextAlert(
            events: fetchEvents(), now: moment, alreadyAlerted: alertedKeys
        ) else { return }
        let delay = max(0, next.fireDate.timeIntervalSince(moment))
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.fire(next.event)
        }
    }

    private func fire(_ event: CalendarAlertEvent) {
        guard enabled else { return }
        alertedKeys.insert(event.identifier)
        post(CalendarAlertBuilder.alert(for: event, now: now()))
        // The next one in line, if there is one.
        recompute()
    }

    private func cancelTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Watching for changes

    private func observeIfNeeded() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        // EventKit posts this on any change anywhere, including other devices syncing.
        observers.append(center.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.recompute() } })
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.recompute() } })
        observers.append(center.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.recompute() } })
        observers.append(center.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.recompute() } })
    }

    private func stopObserving() {
        let center = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.forEach {
            center.removeObserver($0)
            workspaceCenter.removeObserver($0)
        }
        observers.removeAll()
    }

    // MARK: - EventKit

    /// What's coming up in the next couple of days, mapped to the plain struct the scheduler works with.
    /// `store.reset()` first so a change notification's fetch never sees stale cached objects.
    private static func fetchUpcomingEvents(
        store: EKEventStore, now: Date, calendar: Calendar = .current
    ) -> [CalendarAlertEvent] {
        store.reset()
        guard let horizon = calendar.date(byAdding: .hour, value: 48, to: now) else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: horizon, calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled && !isDeclined($0) }
            .map(makeAlertEvent(from:))
    }

    /// Events you already said no to are noise (same check as `CalendarStore`).
    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    private static func makeAlertEvent(from ek: EKEvent) -> CalendarAlertEvent {
        let start = ek.startDate ?? .now
        // Recurring events share one identifier, so the start time makes the key unique per occurrence.
        let identifier = "\(ek.eventIdentifier ?? ek.title ?? "event")@\(start.timeIntervalSinceReferenceDate)"
        let title = (ek.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let location = ek.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attendeeNames = (ek.attendees ?? [])
            .filter { !$0.isCurrentUser && $0.participantType == .person }
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return CalendarAlertEvent(
            identifier: identifier,
            title: title.isEmpty ? String(localized: "Untitled") : title,
            start: start,
            end: ek.endDate ?? start,
            isAllDay: ek.isAllDay,
            location: location?.isEmpty == false ? location : nil,
            conferenceURL: MeetingLink.find(url: ek.url, location: ek.location, notes: ek.notes),
            attendeeNames: Array(attendeeNames.prefix(2))
        )
    }
}

// MARK: - Plain data

/// What the scheduler needs from an event, free of EventKit so it can be built by hand in tests.
struct CalendarAlertEvent: Sendable, Equatable {
    /// Event identifier + start date: unique per occurrence, so a moved recurring event counts as a new one.
    var identifier: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var conferenceURL: URL?
    /// Up to two attendees other than the user, for the "with Ana and Luis" detail line.
    var attendeeNames: [String]
}

// MARK: - Scheduling (pure, testable)

enum CalendarAlertScheduling {
    /// PLAN §5.6: the peek fires five minutes before the event starts.
    static let leadTime: TimeInterval = 5 * 60
    /// Longer events (offsites, conferences) are not the kind of thing a 5-minute peek is for.
    static let maxDuration: TimeInterval = 12 * 60 * 60

    /// The next event worth a peek, and when to show it — five minutes before it starts, or right away if that
    /// moment has already passed (e.g. Altillo just launched, or a change notification arrived late).
    static func nextAlert(
        events: [CalendarAlertEvent], now: Date, alreadyAlerted: Set<String>
    ) -> (fireDate: Date, event: CalendarAlertEvent)? {
        let candidate = events
            .filter { !$0.isAllDay }
            .filter { $0.start > now }
            .filter { $0.end.timeIntervalSince($0.start) <= maxDuration }
            .filter { !alreadyAlerted.contains($0.identifier) }
            .min { $0.start < $1.start }
        guard let candidate else { return nil }
        let fireDate = candidate.start.addingTimeInterval(-leadTime)
        return (max(fireDate, now), candidate)
    }
}

// MARK: - Building the alert (pure, testable)

enum CalendarAlertBuilder {
    static func alert(for event: CalendarAlertEvent, now: Date) -> NotchAlert {
        NotchAlert(
            source: .calendar,
            symbol: event.conferenceURL != nil ? "video" : "calendar",
            title: event.title,
            detail: detail(for: event),
            trailing: trailing(for: event, now: now),
            isUrgent: true,
            module: .calendar,
            duration: .seconds(8)
        )
    }

    /// The location if there is one, otherwise up to two attendees ("with Ana and Luis").
    static func detail(for event: CalendarAlertEvent) -> String? {
        if let location = event.location { return location }
        guard !event.attendeeNames.isEmpty else { return nil }
        let joined = ListFormatter.localizedString(byJoining: event.attendeeNames)
        return String(localized: "with \(joined)")
    }

    /// "now" once the event has started (or is about to, within a minute), otherwise "in N min".
    static func trailing(for event: CalendarAlertEvent, now: Date) -> String {
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        return minutes > 0 ? String(localized: "in \(minutes) min") : String(localized: "now")
    }
}
