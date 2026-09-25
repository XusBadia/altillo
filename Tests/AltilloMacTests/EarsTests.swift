import Foundation
import Testing
@testable import Altillo
import AltilloCore

/// The ears beside the resting notch: when they show, what the next-event ear reads and when it must change, and
/// how the players' broadcasts are read.
@MainActor
struct EarsTests {
    private static func makeDefaults(_ name: String = #function) -> UserDefaults {
        TestDefaultsJanitor.purgeStale()
        let suite = "me.badia.altillo.tests.ears.\(name.replacingOccurrences(of: "()", with: ""))-\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(_ title: String = "Standup", in minutes: Double, lasting: Double = 30,
                       allDay: Bool = false) -> EarEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return EarEvent(title: title, start: start, end: start.addingTimeInterval(lasting * 60), isAllDay: allDay)
    }

    // MARK: - Visibility

    @Test func withActivityOnlyShowsWhileAChosenEarHasSomethingToSay() {
        let quiet = EarsLogic.showsEars(left: .none, right: .shelf, visibility: .withActivity) { _ in false }
        #expect(!quiet)
        let busy = EarsLogic.showsEars(left: .none, right: .shelf, visibility: .withActivity) { $0 == .shelf }
        #expect(busy)
        // Activity in something that isn't in an ear doesn't count.
        let elsewhere = EarsLogic.showsEars(left: .none, right: .shelf, visibility: .withActivity) { $0 == .nowPlaying }
        #expect(!elsewhere)
    }

    @Test func alwaysShowsAsSoonAsAnEarIsChosen() {
        #expect(EarsLogic.showsEars(left: .nextEvent, right: .none, visibility: .always) { _ in false })
        #expect(!EarsLogic.showsEars(left: .none, right: .none, visibility: .always) { _ in true })
    }

    @Test func agentsGrowEarsLikeAnyOtherSource() {
        #expect(EarsLogic.showsEars(left: .none, right: .agents, visibility: .always) { _ in false })
        #expect(EarsLogic.showsEars(left: .none, right: .agents, visibility: .withActivity) { $0 == .agents })
        #expect(!EarsLogic.showsEars(left: .none, right: .agents, visibility: .withActivity) { _ in false })
    }

    @Test func theStoreShowsEarsForThingsOnTheShelfOnlyWhenTheShelfIsChosen() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        let model = NotchModel(settings: settings)
        settings.leftEar = .none
        settings.rightEar = .shelf
        settings.earsVisibility = .withActivity
        #expect(!model.ears.showsEars(for: model), "an empty shelf has nothing to say")
        model.shelf = [ShelfItem(kind: .text("hello"), displayName: "hello")]
        #expect(model.ears.showsEars(for: model))
        settings.rightEar = .nowPlaying
        #expect(!model.ears.showsEars(for: model), "the shelf isn't in an ear any more")
        settings.earsVisibility = .always
        #expect(model.ears.showsEars(for: model))
    }

    @Test func musicStartingAndStoppingTogglesTheMusicEar() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        let model = NotchModel(settings: settings)
        settings.leftEar = .nowPlaying
        settings.rightEar = .none
        model.nowPlaying.permission = { _ in .undetermined }
        let song = NowPlayingLogic.BroadcastTrack(title: "Teardrop", artist: "Massive Attack")
        #expect(!model.ears.showsEars(for: model))
        model.nowPlaying.receive(state: "Playing", track: song, from: .music)
        #expect(model.nowPlaying.isPlaying)
        #expect(model.ears.showsEars(for: model))
        model.nowPlaying.receive(state: "Paused", track: song, from: .spotify)
        #expect(model.nowPlaying.isPlaying, "Spotify pausing doesn't stop Music")
        model.nowPlaying.receive(state: "Stopped", track: nil, from: .music)
        #expect(!model.ears.showsEars(for: model))
    }

    // MARK: - Now playing parsing

    @Test func playerStatesAreReadStrictly() {
        #expect(EarsLogic.isPlaying(playerState: "Playing") == true)
        #expect(EarsLogic.isPlaying(playerState: "Paused") == false)
        #expect(EarsLogic.isPlaying(playerState: "Stopped") == false)
        #expect(EarsLogic.isPlaying(playerState: nil) == nil)
        #expect(EarsLogic.isPlaying(playerState: "Buffering") == nil, "unknown states leave the ear as it was")
    }

    @Test func anUnknownStateDoesNotStopTheEqualiser() {
        let store = NowPlayingStore()
        store.permission = { _ in .undetermined }
        store.receive(state: "Playing", track: .init(title: "Teardrop", artist: ""), from: .spotify)
        store.receive(state: nil, track: nil, from: .spotify)
        #expect(store.isPlaying)
    }

    // MARK: - Next event: which one

    @Test func theSoonestTimedEventLaterTodayWins() {
        let events = [event("Review", in: 180), event("Standup", in: 20), event("Holiday", in: 10, allDay: true)]
        #expect(EarsLogic.relevantEvent(in: events, now: now)?.title == "Standup")
    }

    @Test func anEventThatJustStartedStaysForTheGraceThenMovesOn() {
        let started = event("Standup", in: -3)
        let next = event("Review", in: 60)
        #expect(EarsLogic.relevantEvent(in: [started, next], now: now)?.title == "Standup")
        let longAgo = event("Standup", in: -6)
        #expect(EarsLogic.relevantEvent(in: [longAgo, next], now: now)?.title == "Review")
    }

    @Test func tomorrowIsOnlyMentionedWithinTheHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let lateTonight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 23, minute: 30))!
        let justAfterMidnight = EarEvent(title: "Deploy", start: lateTonight + 45 * 60,
                                         end: lateTonight + 75 * 60, isAllDay: false)
        let tomorrowMorning = EarEvent(title: "Standup", start: lateTonight + 10 * 3600,
                                       end: lateTonight + 10.5 * 3600, isAllDay: false)
        #expect(EarsLogic.relevantEvent(in: [justAfterMidnight], now: lateTonight, calendar: calendar)?.title == "Deploy")
        #expect(EarsLogic.relevantEvent(in: [tomorrowMorning], now: lateTonight, calendar: calendar) == nil)
    }

    // MARK: - Next event: text

    @Test func farEventsGiveTheirTimeAndNearOnesCountDown() {
        let far = event(in: 90)
        #expect(EarsLogic.label(for: far, now: now) == .at(far.start))
        #expect(EarsLogic.label(for: event(in: 12), now: now) == .countdown(minutes: 12))
        // Minutes round up: 11 min 30 s is still "in 12 min", and the last seconds are "in 1 min".
        #expect(EarsLogic.label(for: event(in: 11.5), now: now) == .countdown(minutes: 12))
        #expect(EarsLogic.label(for: event(in: 0.2), now: now) == .countdown(minutes: 1))
        #expect(EarsLogic.label(for: event(in: 0), now: now) == .now)
        #expect(EarsLogic.label(for: event(in: -2), now: now) == .now)
        #expect(EarsLogic.label(for: event(in: 60), now: now) == .at(now + 3600), "exactly an hour away: the time")
    }

    @Test func theTextIsShortEnoughForAnEar() {
        #expect(EarsLogic.text(for: .countdown(minutes: 12)) == "in 12 min")
        #expect(EarsLogic.compactText(for: .countdown(minutes: 12)) == "12 min")
        #expect(EarsLogic.text(for: .now) == "now")
    }

    // MARK: - Next event: timer boundaries

    @Test func aFarEventWakesTheEarWhenTheCountdownStarts() {
        let far = event(in: 90)
        #expect(EarsLogic.nextBoundary(for: far, now: now) == far.start - 3600)
    }

    @Test func duringTheCountdownTheEarWakesEachTimeTheMinuteTicksOver() {
        // 11 min 30 s left reads "in 12 min" until 11 min left: 30 s from now.
        #expect(EarsLogic.nextBoundary(for: event(in: 11.5), now: now) == now + 30)
        // Exactly 12 min left reads "in 12 min" for a whole minute.
        #expect(EarsLogic.nextBoundary(for: event(in: 12), now: now) == now + 60)
    }

    @Test func aStartedEventWakesTheEarWhenItsGraceEnds() {
        let started = event(in: -2)
        #expect(EarsLogic.nextBoundary(for: started, now: now) == started.start + EarsLogic.nowGrace)
    }

    @Test func noEventMeansNoTimer() {
        #expect(EarsLogic.nextBoundary(for: nil, now: now) == nil)
    }

    @Test func theStoreFollowsInjectedEventsAndOnlyWatchesWhenChosen() {
        let store = EarsStore()
        let upcoming = event("Standup", in: 20)
        store.now = { self.now }
        store.fetchEvents = { [upcoming] }
        store.update(left: .none, right: .shelf, modules: NotchModule.allCases)
        #expect(store.nextEvent == nil, "nothing runs for ears that don't show the next event")
        store.update(left: .nextEvent, right: .shelf, modules: [.shelf])
        #expect(store.nextEvent == upcoming)
        #expect(store.nextEventLabel == .countdown(minutes: 20))
        store.update(left: .none, right: .shelf, modules: NotchModule.allCases)
        #expect(store.nextEvent == nil, "turning the ear off drops the event and its timer")
    }
}
