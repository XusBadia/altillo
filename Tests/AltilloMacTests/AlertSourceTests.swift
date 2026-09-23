import Foundation
import Testing
@testable import Altillo

/// The two live alert sources' plain logic: which event gets a five-minute peek, what its trailing figure says,
/// and when a "now playing" notification is actually a new song worth interrupting for.
struct AlertSourceTests {
    private func event(
        _ title: String,
        start: Date,
        minutes: Double = 30,
        allDay: Bool = false,
        alreadyAlerted: Bool = false
    ) -> CalendarAlertEvent {
        CalendarAlertEvent(
            identifier: alreadyAlerted ? "alerted-\(title)" : title,
            title: title,
            start: start,
            end: start.addingTimeInterval(minutes * 60),
            isAllDay: allDay,
            location: nil,
            conferenceURL: nil,
            attendeeNames: []
        )
    }

    // MARK: - CalendarAlertScheduling.nextAlert

    @Test func picksTheSoonestFutureEventFiveMinutesBeforeItStarts() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let soon = event("Standup", start: now.addingTimeInterval(20 * 60))
        let later = event("Review", start: now.addingTimeInterval(3 * 60 * 60))
        let result = CalendarAlertScheduling.nextAlert(events: [later, soon], now: now, alreadyAlerted: [])
        #expect(result?.event.title == "Standup")
        #expect(result?.fireDate == soon.start.addingTimeInterval(-5 * 60))
    }

    @Test func allDayEventsAreNeverAlertedAbout() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let allDay = event("Birthday", start: now.addingTimeInterval(60 * 60), allDay: true)
        #expect(CalendarAlertScheduling.nextAlert(events: [allDay], now: now, alreadyAlerted: []) == nil)
    }

    @Test func anEventAlreadyAlertedIsSkippedInFavourOfTheNextOne() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let done = event("Standup", start: now.addingTimeInterval(60), alreadyAlerted: true)
        let next = event("Review", start: now.addingTimeInterval(30 * 60))
        let result = CalendarAlertScheduling.nextAlert(
            events: [done, next], now: now, alreadyAlerted: [done.identifier]
        )
        #expect(result?.event.title == "Review")
    }

    @Test func anEventStartingWithinFiveMinutesFiresRightAway() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let soon = event("Standup", start: now.addingTimeInterval(90)) // 1.5 min out: the -5min mark is in the past
        let result = CalendarAlertScheduling.nextAlert(events: [soon], now: now, alreadyAlerted: [])
        #expect(result?.fireDate == now)
    }

    @Test func eventsLongerThanTwelveHoursAreSkipped() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let offsite = event("Offsite", start: now.addingTimeInterval(3_600), minutes: 13 * 60)
        #expect(CalendarAlertScheduling.nextAlert(events: [offsite], now: now, alreadyAlerted: []) == nil)
    }

    @Test func eventsAlreadyStartedAreNeverPicked() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let running = event("Standup", start: now.addingTimeInterval(-60))
        #expect(CalendarAlertScheduling.nextAlert(events: [running], now: now, alreadyAlerted: []) == nil)
    }

    @Test func nothingComesBackWhenThereIsNothingLeftToAlert() {
        #expect(CalendarAlertScheduling.nextAlert(events: [], now: .now, alreadyAlerted: []) == nil)
    }

    // MARK: - CalendarAlertBuilder

    @Test func trailingCountsDownInWholeMinutesAndSaysNowAtTheEnd() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let fiveOut = event("Standup", start: now.addingTimeInterval(5 * 60))
        let almost = event("Standup", start: now.addingTimeInterval(20))
        let started = event("Standup", start: now.addingTimeInterval(-30))
        #expect(CalendarAlertBuilder.trailing(for: fiveOut, now: now) == "in 5 min")
        #expect(CalendarAlertBuilder.trailing(for: almost, now: now) == "now")
        #expect(CalendarAlertBuilder.trailing(for: started, now: now) == "now")
    }

    @Test func detailPrefersTheLocationOverAttendees() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var withLocation = event("Standup", start: now)
        withLocation.location = "Big room"
        withLocation.attendeeNames = ["Ana", "Luis"]
        #expect(CalendarAlertBuilder.detail(for: withLocation) == "Big room")
    }

    @Test func detailFallsBackToTheFirstTwoAttendees() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var withAttendees = event("Standup", start: now)
        withAttendees.attendeeNames = ["Ana", "Luis"]
        #expect(CalendarAlertBuilder.detail(for: withAttendees) == "with Ana and Luis")
    }

    @Test func detailIsNilWithNeitherLocationNorAttendees() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(CalendarAlertBuilder.detail(for: event("Standup", start: now)) == nil)
    }

    @Test func aConferenceLinkSwapsTheCalendarSymbolForAVideoOne() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var withLink = event("Standup", start: now.addingTimeInterval(300))
        withLink.conferenceURL = URL(string: "https://meet.google.com/abc-defg-hij")
        #expect(CalendarAlertBuilder.alert(for: withLink, now: now).symbol == "video")
        #expect(CalendarAlertBuilder.alert(for: event("Standup", start: now.addingTimeInterval(300)), now: now).symbol == "calendar")
    }

    // MARK: - NowPlayingAlertDedupe

    private let satie = NowPlayingAlertDedupe.TrackIdentity(id: "1", name: "Gymnopédie No. 1", artist: "Erik Satie")
    private let massiveAttack = NowPlayingAlertDedupe.TrackIdentity(id: "2", name: "Teardrop", artist: "Massive Attack")

    @Test func theFirstPlayingNotificationSincEnablingOnlySetsTheBaseline() {
        let decision = NowPlayingAlertDedupe.decide(state: "Playing", identity: satie, lastAlerted: nil)
        #expect(!decision.shouldAlert)
        #expect(decision.lastAlerted == satie)
    }

    @Test func pausingAndResumingTheSameSongNeverAlerts() {
        let paused = NowPlayingAlertDedupe.decide(state: "Paused", identity: satie, lastAlerted: satie)
        #expect(!paused.shouldAlert)
        #expect(paused.lastAlerted == satie)
        let resumed = NowPlayingAlertDedupe.decide(state: "Playing", identity: satie, lastAlerted: paused.lastAlerted)
        #expect(!resumed.shouldAlert)
    }

    @Test func aNewSongAfterTheBaselineAlerts() {
        let decision = NowPlayingAlertDedupe.decide(state: "Playing", identity: massiveAttack, lastAlerted: satie)
        #expect(decision.shouldAlert)
        #expect(decision.lastAlerted == massiveAttack)
    }

    @Test func aStoppedPlayerNeverAlertsAndKeepsTheBaseline() {
        let decision = NowPlayingAlertDedupe.decide(state: "Stopped", identity: nil, lastAlerted: satie)
        #expect(!decision.shouldAlert)
        #expect(decision.lastAlerted == satie)
    }

    @Test func aPlayingNotificationWithoutAnIdentityIsIgnored() {
        let decision = NowPlayingAlertDedupe.decide(state: "Playing", identity: nil, lastAlerted: satie)
        #expect(!decision.shouldAlert)
        #expect(decision.lastAlerted == satie)
    }

    @Test func identitiesWithoutAMatchingIDStillCompareByNameAndArtist() {
        let first = NowPlayingAlertDedupe.TrackIdentity(id: nil, name: "Radio", artist: "Directo")
        let second = NowPlayingAlertDedupe.TrackIdentity(id: nil, name: "Radio", artist: "Directo")
        #expect(first == second)
        let decision = NowPlayingAlertDedupe.decide(state: "Playing", identity: second, lastAlerted: first)
        #expect(!decision.shouldAlert)
    }
}
