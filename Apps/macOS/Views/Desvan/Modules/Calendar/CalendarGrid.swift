import AppKit
import Foundation

// The month view's plain logic: which days a month grid shows, which events land on each day, what the user hid,
// and where the selection goes. No EventKit and no SwiftUI here, so all of it is tested with fixed calendars.

// MARK: - Month

/// A month of the user's calendar, independent of time zones: the grid is built from it with a `Calendar`.
struct CalendarMonth: Hashable, Comparable, Sendable {
    let year: Int
    /// 1…12 (Gregorian); whatever the calendar's months are otherwise.
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(containing date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1)
    }

    /// Midnight of its first day.
    func firstDay(in calendar: Calendar) -> Date {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
        return calendar.startOfDay(for: date)
    }

    func adding(_ months: Int, in calendar: Calendar) -> CalendarMonth {
        let date = calendar.date(byAdding: .month, value: months, to: firstDay(in: calendar)) ?? firstDay(in: calendar)
        return CalendarMonth(containing: date, calendar: calendar)
    }

    func contains(_ date: Date, in calendar: Calendar) -> Bool {
        CalendarMonth(containing: date, calendar: calendar) == self
    }

    static func < (lhs: CalendarMonth, rhs: CalendarMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

// MARK: - Grid

/// The days a month grid shows, row by row: the tail of the previous month, the month itself and the head of the
/// next one, starting on the user's first weekday.
struct CalendarGrid: Equatable, Sendable {
    let month: CalendarMonth
    /// Midnight of every day shown, seven per row.
    let days: [Date]
    /// Days borrowed from the previous month before the 1st.
    let leading: Int
    let daysInMonth: Int

    var rows: Int { days.count / 7 }
    /// Rows the month itself needs (4, 5 or 6), whatever `minimumRows` padded it to.
    var naturalRows: Int { (leading + daysInMonth + 6) / 7 }
    /// Everything the grid covers: from the first cell's midnight to the midnight after the last one.
    let interval: DateInterval

    /// - Parameter minimumRows: rows to draw at least, padding with the next month's days (six covers every month,
    ///   which is what EventKit is asked for; the notch draws five or six). Pass 0 for just the rows the month needs.
    init(month: CalendarMonth, calendar: Calendar, minimumRows: Int = 6) {
        self.month = month
        let first = month.firstDay(in: calendar)
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        self.leading = leading
        self.daysInMonth = daysInMonth
        let rows = max((leading + daysInMonth + 6) / 7, minimumRows)
        let days = (0..<(rows * 7)).map { index in
            let date = calendar.date(byAdding: .day, value: index - leading, to: first) ?? first
            return calendar.startOfDay(for: date)
        }
        self.days = days
        let end = calendar.date(byAdding: .day, value: 1, to: days[days.count - 1]) ?? days[days.count - 1]
        interval = DateInterval(start: days[0], end: end)
    }

    /// True for the month's own days (not the borrowed ones at either end).
    func isInMonth(_ index: Int) -> Bool {
        index >= leading && index < leading + daysInMonth
    }

    func index(of day: Date, calendar: Calendar) -> Int? {
        let start = calendar.startOfDay(for: day)
        return days.firstIndex(of: start)
    }

    /// One or two letters per weekday, starting on the user's first weekday and in their language.
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    /// Full weekday names in the same order, for VoiceOver and tooltips.
    static func weekdayNames(calendar: Calendar) -> [String] {
        let symbols = calendar.standaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
}

// MARK: - Filter

/// What the user chose not to see (Settings › Sections › Calendar): whole calendars, and all-day events.
struct CalendarFilter: Equatable, Sendable {
    var hiddenCalendarIDs: Set<String> = []
    var showsAllDay = true

    func allows(_ event: CalendarStore.Event) -> Bool {
        if !showsAllDay, event.isAllDay { return false }
        return !hiddenCalendarIDs.contains(event.calendarID)
    }

    func apply(_ events: [CalendarStore.Event]) -> [CalendarStore.Event] {
        events.filter(allows)
    }
}

// MARK: - Days

enum CalendarBuckets {
    /// Each day's events (keyed by the day's midnight), in agenda order. An event lands on every day it touches:
    /// a trip from Monday to Wednesday marks three days, a party from 22:00 to 01:00 marks two. An event that ends
    /// exactly at midnight doesn't spill into the next day, and a zero-length one (a reminder-like event) still
    /// marks its own day.
    static func bucket(
        _ events: [CalendarStore.Event], days: [Date], calendar: Calendar
    ) -> [Date: [CalendarStore.Event]] {
        guard !days.isEmpty else { return [:] }
        let ends = days.indices.map { index in
            index + 1 < days.count
                ? days[index + 1]
                : (calendar.date(byAdding: .day, value: 1, to: days[index]) ?? days[index])
        }
        var result: [Date: [CalendarStore.Event]] = [:]
        for event in events {
            for (index, day) in days.enumerated() where touches(event, from: day, to: ends[index]) {
                result[day, default: []].append(event)
            }
        }
        return result.mapValues(CalendarMapping.sorted)
    }

    static func touches(_ event: CalendarStore.Event, from start: Date, to end: Date) -> Bool {
        if event.end <= event.start { return event.start >= start && event.start < end }
        return event.start < end && event.end > start
    }

    /// Up to three calendar colours for a day's dots, one per event in agenda order.
    static func dots(for events: [CalendarStore.Event], limit: Int = 3) -> [UInt32] {
        events.prefix(limit).map(\.calendarColorHex)
    }
}

// MARK: - Browsing

/// Which month the grid shows and which day is picked. The selection always lives in the month on screen: walking
/// off either end of it turns the page.
struct CalendarBrowser: Equatable, Sendable {
    private(set) var month: CalendarMonth
    private(set) var selected: Date

    init(today: Date, calendar: Calendar) {
        let day = calendar.startOfDay(for: today)
        selected = day
        month = CalendarMonth(containing: day, calendar: calendar)
    }

    enum Step: Sendable {
        case previousDay, nextDay, previousWeek, nextWeek

        var days: Int {
            switch self {
            case .previousDay: -1
            case .nextDay: 1
            case .previousWeek: -7
            case .nextWeek: 7
            }
        }
    }

    /// Arrows: a day sideways, a week up or down.
    mutating func move(_ step: Step, calendar: Calendar) {
        let day = calendar.date(byAdding: .day, value: step.days, to: selected) ?? selected
        select(day, calendar: calendar)
    }

    /// Picks a day (a click on a borrowed day turns the page to its month).
    mutating func select(_ day: Date, calendar: Calendar) {
        selected = calendar.startOfDay(for: day)
        month = CalendarMonth(containing: selected, calendar: calendar)
    }

    /// ⌘← / ⌘→ and the header's arrows: the same day of the other month, or its last day if that one is shorter
    /// (31 January → 28 February).
    mutating func turnPage(by months: Int, calendar: Calendar) {
        let target = month.adding(months, in: calendar)
        let first = target.firstDay(in: calendar)
        let wanted = calendar.component(.day, from: selected)
        let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        let day = calendar.date(byAdding: .day, value: min(wanted, length) - 1, to: first) ?? first
        selected = calendar.startOfDay(for: day)
        month = target
    }

    mutating func goToToday(_ today: Date, calendar: Calendar) {
        select(today, calendar: calendar)
    }

    func isShowingToday(_ today: Date, calendar: Calendar) -> Bool {
        calendar.isDate(selected, inSameDayAs: today)
    }
}

// MARK: - Calendar.app

/// Opens things in Calendar.app. `ical://ekevent/<id>?method=show&options=more` selects the event and opens its
/// details; repeating events also need the occurrence's start (in UTC, or in floating local time when the event is
/// all-day), otherwise Calendar jumps to the first one of the series.
enum CalendarAppLink {
    static let bundleIdentifier = "com.apple.iCal"

    static func url(for event: CalendarStore.Event) -> URL? {
        guard let identifier = event.itemIdentifier, !identifier.isEmpty,
              let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        var path = encoded
        if event.isRecurring {
            path = "\(occurrenceStamp(event.start, allDay: event.isAllDay))/\(encoded)"
        }
        return URL(string: "ical://ekevent/\(path)?method=show&options=more")
    }

    /// `20260924T083000Z`, or `20260924T000000` (no zone) for an all-day occurrence.
    static func occurrenceStamp(_ date: Date, allDay: Bool, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = allDay ? timeZone : TimeZone(identifier: "UTC") ?? timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(
            format: "%04d%02d%02dT%02d%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
        return allDay ? stamp : stamp + "Z"
    }

    /// The event itself when we know it; Calendar.app otherwise (it has no public way to jump to a date).
    @MainActor
    static func open(_ event: CalendarStore.Event?) {
        if let event, let url = url(for: event), NSWorkspace.shared.open(url) { return }
        openApp()
    }

    @MainActor
    static func openApp() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
