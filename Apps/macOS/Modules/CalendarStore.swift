import EventKit
import Foundation
import Observation

/// The calendar module's data: what is left of today (or, once today is over, what tomorrow opens with).
///
/// Nothing runs unless the module is on screen. `start()` / `stop()` are reference counted, because SwiftUI inserts
/// the new view before it removes the old one when the notch reopens on the same tab.
@MainActor
@Observable
final class CalendarStore {
    struct Event: Identifiable, Sendable {
        let id: String
        var title: String
        var start: Date
        var end: Date
        var calendarColorHex: UInt32
        var location: String?
        /// Meet/Zoom/Teams link found in the event, if any.
        var conferenceURL: URL?
        var isAllDay: Bool

        /// Already started but not finished yet.
        func isRunning(at now: Date = .now) -> Bool { start <= now && end > now }
    }

    enum Access: Sendable { case unknown, granted, denied }

    private(set) var access: Access = .unknown
    /// Today's remaining events, soonest first.
    private(set) var events: [Event] = []
    var next: Event? { events.first }
    /// True when `events` are tomorrow's because today has nothing left.
    private(set) var isTomorrow = false
    /// Set while the very first refresh is in flight, so the view can stay quiet instead of saying "nothing left".
    private(set) var hasLoaded = false

    /// How often we re-ask EventKit while visible. Countdowns are shown in minutes, so half a minute is plenty and
    /// costs a couple of milliseconds off the main actor.
    static let refreshInterval: Duration = .seconds(30)

    private let calendars = CalendarSource()
    private var viewers = 0
    private var loop: Task<Void, Never>?
    private var changeObserver: NSObjectProtocol?

    init() {
        access = Self.access(for: EKEventStore.authorizationStatus(for: .event))
    }

    /// Called by the view when the module appears.
    func start() {
        viewers += 1
        guard viewers == 1 else { return }
        switch access {
        case .granted: begin()
        case .unknown: Task { await requestAccess() }
        case .denied: break
        }
    }

    /// Called by the view when the module goes away. Cancels the loop: hidden means zero work.
    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        loop?.cancel()
        loop = nil
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
            self.changeObserver = nil
        }
    }

    /// Asks for calendar access once, the first time the module is opened.
    func requestAccess() async {
        let granted = await calendars.requestFullAccess()
        // The system is the source of truth. A `false` with the status still `notDetermined` means macOS never
        // asked (no calendar database, a restriction, a session that can't show the dialog): saying "you said no"
        // there would be a lie the user couldn't act on, so the module stays on its invitation and can retry.
        access = granted ? .granted : Self.access(for: EKEventStore.authorizationStatus(for: .event))
        guard access == .granted, viewers > 0, loop == nil else { return }
        begin()
    }

    // MARK: - Refreshing

    private func begin() {
        guard loop == nil else { return }
        // EventKit posts this when anything changes anywhere (including other devices syncing).
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    /// Refreshes out of band (an EventKit change); the periodic loop keeps its own rhythm.
    private func refreshNow() {
        Task { await refresh() }
    }

    private func refresh() async {
        let day = await calendars.fetch(now: .now)
        guard !Task.isCancelled else { return }
        events = day.events
        isTomorrow = day.isTomorrow
        hasLoaded = true
    }

    static func access(for status: EKAuthorizationStatus) -> Access {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .unknown
        default: .denied
        }
    }
}

// MARK: - EventKit

/// Owns the one `EKEventStore`. It is not `Sendable`, so it never leaves this actor: only plain `Event` values do.
private actor CalendarSource {
    private let store = EKEventStore()

    func requestFullAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// What is left of today, or tomorrow's events when today is done.
    func fetch(now: Date, calendar: Calendar = .current) -> CalendarDay {
        // The store caches; resetting makes sure we see what the change notification told us about.
        store.reset()
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday)
        else { return CalendarDay(events: [], isTomorrow: false) }

        let predicate = store.predicateForEvents(withStart: now, end: endOfTomorrow, calendars: nil)
        let all = store.events(matching: predicate)
            .filter { $0.status != .canceled && !isDeclined($0) }
            .map(Self.event(from:))
            .filter { $0.end > now }

        let today = CalendarMapping.sorted(all.filter { $0.start < startOfTomorrow })
        if !today.isEmpty { return CalendarDay(events: today, isTomorrow: false) }
        let tomorrow = CalendarMapping.sorted(all.filter { $0.start >= startOfTomorrow })
        return CalendarDay(events: tomorrow, isTomorrow: !tomorrow.isEmpty)
    }

    /// Events you already said no to are noise.
    private func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    static func event(from ek: EKEvent) -> CalendarStore.Event {
        let start = ek.startDate ?? .now
        // Recurring events share one identifier, so the start time makes the id unique.
        let identifier = "\(ek.eventIdentifier ?? ek.title ?? "event")@\(start.timeIntervalSinceReferenceDate)"
        let title = (ek.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let location = ek.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CalendarStore.Event(
            id: identifier,
            title: title.isEmpty ? String(localized: "Untitled") : title,
            start: start,
            end: ek.endDate ?? start,
            calendarColorHex: CalendarMapping.hex(of: ek.calendar?.cgColor),
            location: location?.isEmpty == false ? location : nil,
            conferenceURL: MeetingLink.find(url: ek.url, location: ek.location, notes: ek.notes),
            isAllDay: ek.isAllDay
        )
    }

}

/// Turning EventKit's world into ours. Free functions so they can be tested without a calendar database.
enum CalendarMapping {
    /// All-day events first (they frame the day), then by start time, then by title so the order never wobbles.
    static func sorted(_ events: [CalendarStore.Event]) -> [CalendarStore.Event] {
        events.sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.title.localizedCompare(rhs.title) == .orderedAscending
        }
    }

    /// `0xRRGGBB` for the calendar's colour, falling back to the kraft tone when there is none.
    static func hex(of color: CGColor?) -> UInt32 {
        guard let color,
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: sRGB, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3
        else { return 0xC9A7_7C }
        let channel = { (value: CGFloat) in UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return channel(components[0]) << 16 | channel(components[1]) << 8 | channel(components[2])
    }
}

/// A day's worth of events plus whether they are tomorrow's.
struct CalendarDay: Sendable {
    var events: [CalendarStore.Event]
    var isTomorrow: Bool
}

// MARK: - Sample data

extension CalendarStore.Event {
    /// Shown in the `openCalendar` design scenario when there is no real agenda to draw (no access, or a free day).
    static func samples(now: Date = .now) -> [CalendarStore.Event] {
        let calendar = Calendar.current
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        }
        let first = now.addingTimeInterval(12 * 60)
        return [
            CalendarStore.Event(
                id: "sample-1",
                title: String(localized: "Notch design with Marta"),
                start: first,
                end: first.addingTimeInterval(45 * 60),
                calendarColorHex: 0xF267_4A,
                location: "Google Meet",
                conferenceURL: URL(string: "https://meet.google.com/abc-defg-hij"),
                isAllDay: false
            ),
            CalendarStore.Event(
                id: "sample-2",
                title: String(localized: "Weekly review"),
                start: at(17, 0),
                end: at(17, 30),
                calendarColorHex: 0x86B6_D9,
                location: String(localized: "Big room"),
                conferenceURL: nil,
                isAllDay: false
            ),
            CalendarStore.Event(
                id: "sample-3",
                title: String(localized: "Dinner with Alex"),
                start: at(21, 0),
                end: at(22, 30),
                calendarColorHex: 0x9DB8_8A,
                location: String(localized: "Home"),
                conferenceURL: nil,
                isAllDay: false
            ),
        ]
    }
}
