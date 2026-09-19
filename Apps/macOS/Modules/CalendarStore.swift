import Foundation
import Observation

/// The calendar module's data. STUB: implemented with EventKit by the modules work. Keep this API.
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
    }

    enum Access: Sendable { case unknown, granted, denied }

    private(set) var access: Access = .unknown
    /// Today's remaining events, soonest first.
    private(set) var events: [Event] = []
    var next: Event? { events.first }

    func start() {}
    func stop() {}
    func requestAccess() async {}
}
