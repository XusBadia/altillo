import AppKit
import EventKit
import Foundation
import Observation

/// The calendar module's data: what is left of today (or, once today is over, what tomorrow opens with) and, for
/// the month view, every event of the month on screen, bucketed by day.
///
/// Nothing runs unless the module is on screen. `start()` / `stop()` are reference counted, because SwiftUI inserts
/// the new view before it removes the old one when the notch reopens on the same tab. While visible it asks
/// EventKit once per month shown (cached), re-asks when EventKit says something changed, when the day turns, the
/// clock or the time zone changes and after sleep, and refreshes today's countdowns every half minute.
@MainActor
@Observable
final class CalendarStore {
    struct Event: Identifiable, Hashable, Sendable {
        let id: String
        var title: String
        var start: Date
        var end: Date
        var calendarColorHex: UInt32
        var location: String?
        /// Meet/Zoom/Teams link found in the event, if any.
        var conferenceURL: URL?
        var isAllDay: Bool
        /// `EKCalendar.calendarIdentifier`, for the calendars the user hid.
        var calendarID: String = ""
        /// `EKCalendarItem.calendarItemIdentifier`, to open the event in Calendar.app.
        var itemIdentifier: String?
        /// Part of a repeating series: Calendar.app needs the occurrence's date to show the right one.
        var isRecurring = false

        /// Already started but not finished yet.
        func isRunning(at now: Date = .now) -> Bool { start <= now && end > now }
    }

    enum Access: Sendable { case unknown, granted, denied }

    private(set) var access: Access = .unknown
    /// Today's remaining events, soonest first (hidden calendars and, if the user said so, all-day events left out).
    private(set) var events: [Event] = []
    var next: Event? { events.first }
    /// True when `events` are tomorrow's because today has nothing left.
    private(set) var isTomorrow = false
    /// Set while the very first refresh is in flight, so the view can stay quiet instead of saying "nothing left".
    private(set) var hasLoaded = false
    /// Midnight of today. Moves when the day turns, so the grid's lit day follows.
    private(set) var today: Date

    /// What the user chose not to see. The view keeps it in step with Settings; changing it re-filters what is
    /// already loaded, without asking EventKit again.
    var filter = CalendarFilter() {
        didSet { if filter != oldValue { applyFilter() } }
    }

    /// The `openCalendar` design scenario: months with nothing real in them show sample events instead.
    var showsSamples = false {
        didSet { if showsSamples != oldValue { rebuildDays() } }
    }

    // MARK: Month

    /// The month the grid is showing, set by the view.
    private(set) var displayedMonth: CalendarMonth?
    /// `displayedMonth`'s days (keyed by midnight), filtered and in agenda order.
    private(set) var days: [Date: [Event]] = [:]
    /// Months whose events arrived at least once (the grid stays quiet about "no events" until then).
    private(set) var loadedMonths: Set<CalendarMonth> = []

    /// How often we re-ask EventKit about today while visible. Countdowns are shown in minutes, so half a minute is
    /// plenty and costs a couple of milliseconds off the main actor.
    static let refreshInterval: Duration = .seconds(30)
    /// Months kept in memory for flicking back and forth.
    static let cachedMonths = 6

    let calendar: Calendar
    private let source = CalendarSource()
    private var viewers = 0
    private var loop: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// Everything from now to the end of tomorrow, unfiltered.
    private var upcoming: [Event] = []
    /// Unfiltered events of each cached month's whole grid (leading and trailing days included).
    private var monthEvents: [CalendarMonth: [Event]] = [:]
    /// Cached months that may be out of date (EventKit changed, or we weren't watching).
    private var staleMonths: Set<CalendarMonth> = []
    /// Months being asked for, and in which generation.
    private var loading: [CalendarMonth: Int] = [:]
    /// Bumped whenever everything cached must be asked for again; late answers from an older one are dropped.
    private var generation = 0

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        today = calendar.startOfDay(for: .now)
        access = Self.access(for: EKEventStore.authorizationStatus(for: .event))
    }

    /// Called by the view when the module appears.
    func start() {
        viewers += 1
        guard viewers == 1 else { return }
        // Access may have been granted (in Settings) or taken away since last time.
        let status = Self.access(for: EKEventStore.authorizationStatus(for: .event))
        if status != .unknown { access = status }
        switch access {
        case .granted: begin()
        case .unknown: Task { await requestAccess() }
        case .denied: break
        }
    }

    /// Called by the view when the module goes away. Cancels the loop and the observers: hidden means zero work.
    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        loop?.cancel()
        loop = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        // Nobody watched EventKit in the meantime: whatever is cached gets checked again next time.
        staleMonths.formUnion(monthEvents.keys)
        loading.removeAll()
    }

    /// Asks for calendar access once, the first time the module is opened.
    func requestAccess() async {
        let granted = await source.requestFullAccess()
        // The system is the source of truth. A `false` with the status still `notDetermined` means macOS never
        // asked (no calendar database, a restriction, a session that can't show the dialog): saying "you said no"
        // there would be a lie the user couldn't act on, so the module stays on its invitation and can retry.
        access = granted ? .granted : Self.access(for: EKEventStore.authorizationStatus(for: .event))
        guard access == .granted, viewers > 0, loop == nil else { return }
        begin()
    }

    /// The grid moved to `month`. Shows what is cached at once and asks EventKit only if it has to.
    func display(_ month: CalendarMonth) {
        guard month != displayedMonth else { return }
        displayedMonth = month
        rebuildDays()
        loadIfNeeded(month)
    }

    /// A day's events on the grid (only for days of the displayed month's grid).
    func events(on day: Date) -> [Event] {
        days[calendar.startOfDay(for: day)] ?? []
    }

    // MARK: - Refreshing

    private func begin() {
        guard loop == nil else { return }
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let changed: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.invalidate() }
        }
        observers = [
            // EventKit posts this when anything changes anywhere (including other devices syncing).
            (center, center.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main, using: changed)),
            (center, center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: changed)),
            (center, center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: changed)),
            (center, center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main,
                                        using: changed)),
            (workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main,
                                              using: changed)),
        ]
        invalidate()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled, let self else { return }
                // A missed midnight (the notch stayed open through it) is caught here too.
                if self.calendar.startOfDay(for: .now) != self.today {
                    self.invalidate()
                } else {
                    await self.refreshUpcoming()
                }
            }
        }
    }

    /// Something changed: today moves if it has to, everything cached is asked for again and the month on screen
    /// first.
    private func invalidate() {
        guard viewers > 0, access == .granted else { return }
        generation += 1
        today = calendar.startOfDay(for: .now)
        staleMonths.formUnion(monthEvents.keys)
        loading.removeAll()
        Task { await refreshUpcoming() }
        // Only the month on screen is worth asking for now; the others wait until they are shown again.
        if let displayedMonth { loadIfNeeded(displayedMonth) }
    }

    private func refreshUpcoming() async {
        let generation = generation
        let fetched = await source.fetch(
            in: DateInterval(start: .now, end: calendar.date(byAdding: .day, value: 2, to: today) ?? .now),
            generation: generation
        )
        guard !Task.isCancelled, generation == self.generation else { return }
        upcoming = fetched
        applyAgenda()
        hasLoaded = true
    }

    private func loadIfNeeded(_ month: CalendarMonth) {
        guard viewers > 0, access == .granted else { return }
        guard monthEvents[month] == nil || staleMonths.contains(month), loading[month] != generation else { return }
        let generation = generation
        loading[month] = generation
        let interval = CalendarGrid(month: month, calendar: calendar).interval
        Task {
            let fetched = await source.fetch(in: interval, generation: generation)
            guard generation == self.generation else { return }
            loading[month] = nil
            monthEvents[month] = fetched
            staleMonths.remove(month)
            loadedMonths.insert(month)
            trimCache()
            if month == displayedMonth { rebuildDays() }
        }
    }

    /// Keeps the months closest to the one on screen.
    private func trimCache() {
        guard monthEvents.count > Self.cachedMonths, let displayedMonth else { return }
        let distance = { (month: CalendarMonth) in
            abs((month.year - displayedMonth.year) * 12 + month.month - displayedMonth.month)
        }
        for month in monthEvents.keys.sorted(by: { distance($0) > distance($1) }).prefix(monthEvents.count - Self.cachedMonths) {
            monthEvents[month] = nil
            staleMonths.remove(month)
        }
    }

    private func applyFilter() {
        applyAgenda()
        rebuildDays()
    }

    private func applyAgenda() {
        let day = CalendarMapping.agenda(from: filter.apply(upcoming), now: .now, calendar: calendar)
        events = day.events
        isTomorrow = day.isTomorrow
    }

    private func rebuildDays() {
        guard let displayedMonth else {
            days = [:]
            return
        }
        let grid = CalendarGrid(month: displayedMonth, calendar: calendar)
        var raw = monthEvents[displayedMonth] ?? []
        if showsSamples, raw.isEmpty {
            raw = Event.samples(for: grid, today: today, calendar: calendar)
        }
        days = CalendarBuckets.bucket(filter.apply(raw), days: grid.days, calendar: calendar)
    }

    static func access(for status: EKAuthorizationStatus) -> Access {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .unknown
        default: .denied
        }
    }
}

// MARK: - Calendars (Settings)

/// One of the user's calendars, as Settings lists it.
struct CalendarInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let colorHex: UInt32
}

/// An account (iCloud, Google, On My Mac…) and its calendars.
struct CalendarAccount: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    var calendars: [CalendarInfo]
}

/// The calendars Settings offers to hide, grouped by account. Watches EventKit only while the pane is on screen.
@MainActor
@Observable
final class CalendarDirectory {
    private(set) var access: CalendarStore.Access
    private(set) var accounts: [CalendarAccount] = []
    private(set) var hasLoaded = false

    private let source = CalendarSource()
    private var observer: NSObjectProtocol?

    init() {
        access = CalendarStore.access(for: EKEventStore.authorizationStatus(for: .event))
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.reload() }
        }
        Task { await reload() }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func reload() async {
        access = CalendarStore.access(for: EKEventStore.authorizationStatus(for: .event))
        guard access == .granted else {
            accounts = []
            hasLoaded = true
            return
        }
        accounts = await source.accounts()
        hasLoaded = true
    }

    /// The same question the notch asks the first time. Only ever from a button the user pressed.
    func requestAccess() async {
        _ = await source.requestFullAccess()
        await reload()
    }
}

// MARK: - EventKit

/// Owns one `EKEventStore`. It is not `Sendable`, so it never leaves this actor: only plain values do.
private actor CalendarSource {
    private let store = EKEventStore()
    private var resetGeneration = -1

    func requestFullAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Every event touching `interval`, cancelled and declined ones left out (hidden calendars are filtered later,
    /// so changing that setting never needs EventKit).
    func fetch(in interval: DateInterval, generation: Int) -> [CalendarStore.Event] {
        // The store caches; resetting once per generation makes sure we see what the change notification told us
        // about.
        if generation != resetGeneration {
            store.reset()
            resetGeneration = generation
        }
        guard interval.duration > 0 else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled && !isDeclined($0) }
            .map(Self.event(from:))
    }

    func accounts() -> [CalendarAccount] {
        var accounts: [String: CalendarAccount] = [:]
        for calendar in store.calendars(for: .event) {
            let source = calendar.source
            let id = source?.sourceIdentifier ?? "local"
            let title = source?.title ?? String(localized: "On My Mac")
            let info = CalendarInfo(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                colorHex: CalendarMapping.hex(of: calendar.cgColor)
            )
            accounts[id, default: CalendarAccount(id: id, title: title, calendars: [])].calendars.append(info)
        }
        return accounts.values
            .map { account in
                var account = account
                account.calendars.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                return account
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
            isAllDay: ek.isAllDay,
            calendarID: ek.calendar?.calendarIdentifier ?? "",
            itemIdentifier: ek.calendarItemIdentifier,
            isRecurring: ek.hasRecurrenceRules || ek.isDetached
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

    /// What is left of today or, when today is done, tomorrow's events.
    static func agenda(from events: [CalendarStore.Event], now: Date, calendar: Calendar) -> CalendarDay {
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday)
        else { return CalendarDay(events: [], isTomorrow: false) }
        let live = events.filter { $0.end > now && $0.start < endOfTomorrow }
        let today = sorted(live.filter { $0.start < startOfTomorrow })
        if !today.isEmpty { return CalendarDay(events: today, isTomorrow: false) }
        let tomorrow = sorted(live.filter { $0.start >= startOfTomorrow })
        return CalendarDay(events: tomorrow, isTomorrow: !tomorrow.isEmpty)
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
                isAllDay: false,
                calendarID: "sample-work"
            ),
            CalendarStore.Event(
                id: "sample-2",
                title: String(localized: "Weekly review"),
                start: at(17, 0),
                end: at(17, 30),
                calendarColorHex: 0x86B6_D9,
                location: String(localized: "Big room"),
                conferenceURL: nil,
                isAllDay: false,
                calendarID: "sample-team"
            ),
            CalendarStore.Event(
                id: "sample-3",
                title: String(localized: "Dinner with Alex"),
                start: at(21, 0),
                end: at(22, 30),
                calendarColorHex: 0x9DB8_8A,
                location: String(localized: "Home"),
                conferenceURL: nil,
                isAllDay: false,
                calendarID: "sample-home"
            ),
        ]
    }

    /// A believable month for the design scenario: a weekly rhythm, a trip, a release day and today's samples.
    static func samples(for grid: CalendarGrid, today: Date, calendar: Calendar) -> [CalendarStore.Event] {
        let now = Date.now
        var events: [CalendarStore.Event] = []
        func add(_ title: String, _ day: Date, _ hour: Int, _ minute: Int, minutes: Double, color: UInt32,
                 calendarID: String, link: String? = nil, location: String? = nil) {
            let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            events.append(CalendarStore.Event(
                id: "sample-\(title)-\(day.timeIntervalSinceReferenceDate)",
                title: title,
                start: start,
                end: start.addingTimeInterval(minutes * 60),
                calendarColorHex: color,
                location: location,
                conferenceURL: link.flatMap(URL.init(string:)),
                isAllDay: false,
                calendarID: calendarID
            ))
        }
        for day in grid.days {
            let weekday = calendar.component(.weekday, from: day)
            let date = calendar.component(.day, from: day)
            if calendar.isDate(day, inSameDayAs: today) {
                add(String(localized: "Stand-up"), day, 9, 30, minutes: 15, color: 0x86B6_D9, calendarID: "sample-team",
                    link: "https://meet.google.com/std-upup-now")
                events += samples(now: now).filter { calendar.isDate($0.start, inSameDayAs: day) }
                continue
            }
            switch weekday {
            case 2: add(String(localized: "Planning"), day, 10, 0, minutes: 60, color: 0x86B6_D9,
                        calendarID: "sample-team", link: "https://zoom.us/j/123456789")
            case 4: add(String(localized: "1:1 with Marta"), day, 12, 0, minutes: 30, color: 0xF267_4A,
                        calendarID: "sample-work", link: "https://meet.google.com/abc-defg-hij")
            case 6: add(String(localized: "Weekly review"), day, 17, 0, minutes: 30, color: 0x86B6_D9,
                        calendarID: "sample-team", location: String(localized: "Big room"))
            default: break
            }
            if [3, 11, 19, 27].contains(date) {
                add(String(localized: "Climbing"), day, 19, 0, minutes: 90, color: 0x9DB8_8A, calendarID: "sample-home")
            }
            if date == 15 {
                add(String(localized: "Dentist"), day, 16, 30, minutes: 45, color: 0xEE9F_B5, calendarID: "sample-home",
                    location: String(localized: "Clínica Sol"))
            }
        }
        // A three-day trip and a release day, all-day.
        let first = grid.month.firstDay(in: calendar)
        if let tripStart = calendar.date(byAdding: .day, value: 7, to: first),
           let tripEnd = calendar.date(byAdding: .day, value: 10, to: first) {
            events.append(CalendarStore.Event(
                id: "sample-trip", title: String(localized: "Lisbon"), start: tripStart, end: tripEnd,
                calendarColorHex: 0xB7A3_E0, location: nil, conferenceURL: nil, isAllDay: true,
                calendarID: "sample-home"
            ))
        }
        if let release = calendar.date(byAdding: .day, value: 21, to: first),
           let after = calendar.date(byAdding: .day, value: 1, to: release) {
            events.append(CalendarStore.Event(
                id: "sample-release", title: String(localized: "Altillo 1.0"), start: release, end: after,
                calendarColorHex: 0xE8B3_3A, location: nil, conferenceURL: nil, isAllDay: true,
                calendarID: "sample-work"
            ))
        }
        return events
    }
}
