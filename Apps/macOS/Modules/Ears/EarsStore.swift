import AppKit
import EventKit
import Foundation
import Observation

/// What the ears beside the resting notch have to say (PLAN §4, "Orejas").
///
/// Only the sources the chosen ears need ever run, and all of them are event-driven (PLAN §1.5):
/// - **Shelf**: read straight from the model, nothing to watch.
/// - **Next event**: EventKit, only if calendar access is already granted (this store never asks for it). One timer
///   asleep until the next moment the ear's text changes, plus EventKit changes, waking, clock and day changes.
/// - **Music**: `NowPlayingStore`'s background listening, shared with the contextual ear and the new-song alert so
///   playback is only ever listened to once: the system's Now Playing stream for any app (Safari, Podcasts, VLC…),
///   or Music's and Spotify's own broadcasts when the store has fallen back to AppleScript. No polling either way.
/// - **AI usage**: `UsageStore`'s latest numbers (its own 5-minute rhythm), nothing extra.
/// - **Agents**: `AgentHub`'s sessions (hook events and session files), nothing extra.
/// - **What matters now** (`.automatic`): `NotchActivityLogic` over the sources above, only for sections that are on.
///
/// Ears set to nothing cost nothing.
@MainActor
@Observable
final class EarsStore {
    /// The event the next-event ear talks about, if there is one worth mentioning.
    private(set) var nextEvent: EarEvent?
    /// "Now" as of the last boundary. Bumped by the timer so the next-event text re-renders exactly when it changes.
    private(set) var clock = Date.now

    private var watchesCalendar = false

    @ObservationIgnored private var eventStore: EKEventStore?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var calendarObservers: [NSObjectProtocol] = []

    /// Injected so tests can control "now" and the events without EventKit.
    @ObservationIgnored var now: () -> Date = { .now }
    @ObservationIgnored var fetchEvents: (() -> [EarEvent])?
    @ObservationIgnored var hasCalendarAccess: () -> Bool = { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Starts or stops the (event-driven) calendar source the chosen ears need. Idempotent; calling it again also
    /// picks up calendar access granted in the meantime (the coordinator calls it whenever access changes). The
    /// music source lives in `NowPlayingStore` (`EarsLogic.watchesPlayback`).
    func update(left: EarContent, right: EarContent, modules: [NotchModule]) {
        setCalendar(watching: EarsLogic.watchesCalendar(left: left, right: right, modules: modules))
    }

    /// Whether the resting notch grows ears right now.
    func showsEars(for model: NotchModel) -> Bool {
        let settings = model.settings
        return EarsLogic.showsEars(left: settings.leftEar, right: settings.rightEar,
                                   visibility: settings.earsVisibility) { content in
            hasActivity(content, in: model)
        }
    }

    /// Whether an ear showing `content` has something to say right now.
    func hasActivity(_ content: EarContent, in model: NotchModel) -> Bool {
        switch content {
        case .none: false
        case .agents: model.settings.isEnabled(.agents) && AgentsLogic.counts(model.agentHub.sessions).active > 0
        case .usage: model.usage.primary != nil
        case .shelf: !model.shelf.isEmpty
        case .nextEvent: nextEvent != nil
        case .nowPlaying: model.nowPlaying.isPlaying
        case .automatic: model.contextualActivity != .rest
        }
    }

    /// What the next-event ear reads right now ("10:30", "in 12 min", "now").
    var nextEventLabel: EarsLogic.EventLabel? {
        guard let nextEvent else { return nil }
        return EarsLogic.label(for: nextEvent, now: clock)
    }

    // MARK: - Calendar

    private func setCalendar(watching: Bool) {
        if watching {
            if !watchesCalendar {
                watchesCalendar = true
                observeCalendar()
            }
            // Always re-read: access may have just been granted from the Calendar section.
            recomputeEvent()
        } else if watchesCalendar {
            watchesCalendar = false
            stopObservingCalendar()
            timerTask?.cancel()
            timerTask = nil
            nextEvent = nil
            eventStore = nil
        }
    }

    private func recomputeEvent() {
        timerTask?.cancel()
        timerTask = nil
        guard watchesCalendar else { return }
        let moment = now()
        clock = moment
        let events: [EarEvent]
        if let fetchEvents {
            events = fetchEvents()
        } else if hasCalendarAccess() {
            let store = eventStore ?? EKEventStore()
            eventStore = store
            events = Self.fetchUpcoming(store: store, now: moment, hiding: AltilloSettings.shared.calendarHiddenIDs)
        } else {
            events = []
        }
        let event = EarsLogic.relevantEvent(in: events, now: moment)
        if event != nextEvent { nextEvent = event }
        guard let boundary = EarsLogic.nextBoundary(for: event, now: moment) else { return }
        let delay = max(0.05, boundary.timeIntervalSince(moment))
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.recomputeEvent()
        }
    }

    private func observeCalendar() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let recompute: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.recomputeEvent() }
        }
        calendarObservers = [
            center.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main, using: recompute),
            center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: recompute),
            center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: recompute),
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: recompute),
        ]
    }

    private func stopObservingCalendar() {
        calendarObservers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        calendarObservers.removeAll()
    }

    /// Today's remaining events (and anything in the next hour), free of EventKit for the pure logic.
    private static func fetchUpcoming(store: EKEventStore, now: Date, hiding hidden: Set<String>) -> [EarEvent] {
        store.reset()
        let start = now.addingTimeInterval(-EarsLogic.nowGrace)
        let end = max(Calendar.current.startOfDay(for: now).addingTimeInterval(36 * 3600), now + 3600)
        return CalendarVisibility.events(in: store, from: start, to: end, hiding: hidden)
            .filter { event in
                event.status != .canceled
                    && !(event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false)
            }
            .map { event in
                EarEvent(title: event.title ?? "", start: event.startDate ?? now,
                         end: event.endDate ?? now, isAllDay: event.isAllDay)
            }
    }
}

// MARK: - Plain data

/// What the next-event ear needs from an event, free of EventKit so tests can build it by hand.
struct EarEvent: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
}

// MARK: - Logic (pure, testable)

enum EarsLogic {
    /// Under an hour away, the ear counts down ("in 12 min") instead of giving the time.
    static let countdownWindow: TimeInterval = 60 * 60
    /// For the first minutes of an event the ear says "now" (late for a call?); then it moves on to the next one.
    static let nowGrace: TimeInterval = 5 * 60

    enum EventLabel: Equatable, Sendable {
        /// More than an hour away: its start time.
        case at(Date)
        /// Under an hour away: whole minutes left, rounded up (so "in 1 min" until it starts).
        case countdown(minutes: Int)
        /// It has just started.
        case now
    }

    /// The calendar is read for a next-event ear, or for the contextual one while the calendar section is on.
    static func watchesCalendar(left: EarContent, right: EarContent, modules: [NotchModule]) -> Bool {
        let chosen: Set<EarContent> = [left, right]
        return chosen.contains(.nextEvent) || (chosen.contains(.automatic) && modules.contains(.calendar))
    }

    /// The players are listened to for a music ear, or for the contextual one while Now playing is on.
    static func watchesPlayback(left: EarContent, right: EarContent, modules: [NotchModule]) -> Bool {
        let chosen: Set<EarContent> = [left, right]
        return chosen.contains(.nowPlaying) || (chosen.contains(.automatic) && modules.contains(.nowPlaying))
    }

    /// Whether the resting notch grows ears: with `.always`, as soon as an ear is chosen; with `.withActivity`,
    /// only while a chosen ear has something to say. An ear that isn't available yet never counts.
    static func showsEars(left: EarContent, right: EarContent, visibility: EarsVisibility,
                          hasActivity: (EarContent) -> Bool) -> Bool {
        let chosen = [left, right].filter { $0 != .none && $0.isAvailable }
        switch visibility {
        case .always: return !chosen.isEmpty
        case .withActivity: return chosen.contains(where: hasActivity)
        }
    }

    /// The event worth an ear: the soonest timed one that starts later today (or within the hour, across midnight),
    /// or one that started less than `nowGrace` ago. All-day events are not something to be on time for.
    static func relevantEvent(in events: [EarEvent], now: Date, calendar: Calendar = .current) -> EarEvent? {
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return events
            .filter { !$0.isAllDay && $0.end > now }
            .filter { $0.start > now - nowGrace }
            .filter { $0.start < endOfToday || $0.start.timeIntervalSince(now) < countdownWindow }
            .min { $0.start < $1.start }
    }

    static func label(for event: EarEvent, now: Date) -> EventLabel {
        let remaining = event.start.timeIntervalSince(now)
        if remaining <= 0 { return .now }
        if remaining >= countdownWindow { return .at(event.start) }
        return .countdown(minutes: Int((remaining / 60).rounded(.up)))
    }

    /// The next moment the ear must change: when the countdown starts, each time its minute ticks over, and when
    /// "now" gives way to the next event. `nil` with no event (EventKit changes and a new day re-check).
    static func nextBoundary(for event: EarEvent?, now: Date) -> Date? {
        guard let event else { return nil }
        let remaining = event.start.timeIntervalSince(now)
        if remaining <= 0 { return event.start + nowGrace }
        if remaining >= countdownWindow { return event.start - countdownWindow }
        // Whole minutes are rounded up, so the text changes each time `remaining` crosses a multiple of 60 s.
        let intoMinute = remaining.truncatingRemainder(dividingBy: 60)
        return now + (intoMinute == 0 ? 60 : intoMinute)
    }

    /// The ear's text. Short on purpose: an ear is 50 pt wide.
    static func text(for label: EventLabel) -> String {
        switch label {
        case let .at(date): date.formatted(date: .omitted, time: .shortened)
        case let .countdown(minutes): String(localized: "in \(minutes) min")
        case .now: String(localized: "now")
        }
    }

    /// The tightest version, for when "in 12 min" doesn't fit beside the glyph.
    static func compactText(for label: EventLabel) -> String {
        switch label {
        case let .at(date): date.formatted(date: .omitted, time: .shortened)
        case let .countdown(minutes): String(localized: "\(minutes) min")
        case .now: String(localized: "now")
        }
    }

    /// A player's "Player State": `true` playing, `false` paused or stopped, `nil` for anything unrecognised (which
    /// leaves the ear as it was).
    static func isPlaying(playerState: String?) -> Bool? {
        switch playerState {
        case "Playing": true
        case "Paused", "Stopped": false
        default: nil
        }
    }
}
