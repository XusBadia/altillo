import EventKit
import Foundation

/// The calendars the user wants Altillo to look at (Settings › Sections › Calendar). Every EventKit query in the
/// app goes through here so a hidden calendar never shows up in an ear, an alert or an answer.
enum CalendarVisibility {
    /// The calendars to query, or nil for "all of them" (nothing hidden). An empty array means every calendar is
    /// hidden: callers must then return no events rather than pass it to EventKit, which treats it as "all".
    static func calendars(in store: EKEventStore, hiding hidden: Set<String>) -> [EKCalendar]? {
        guard !hidden.isEmpty else { return nil }
        return store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
    }

    /// Events between two dates in the visible calendars.
    static func events(in store: EKEventStore, from start: Date, to end: Date, hiding hidden: Set<String>) -> [EKEvent] {
        let calendars = calendars(in: store, hiding: hidden)
        if let calendars, calendars.isEmpty { return [] }
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars))
    }
}
