import CoreGraphics
import Foundation
import Testing
@testable import Altillo
import AltilloCore

/// The contextual left ear: one priority order for everything that could fill it, only real and enabled sources,
/// the music source behind it (broadcasts, both players, pausing, quitting) and what VoiceOver hears.
@MainActor
struct ContextualActivityTests {
    private static func makeDefaults(_ name: String = #function) -> UserDefaults {
        TestDefaultsJanitor.purgeStale()
        let suite = "me.badia.altillo.tests.activity.\(name.replacingOccurrences(of: "()", with: ""))-\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let everything = Set(NotchModule.allCases)
    private let agent = AgentRequestSignal(agentName: "Claude", project: "altillo")
    private let song = PlaybackSignal(title: "Teardrop", artist: "Massive Attack", appName: "Spotify")
    private let usage = UsageSignal(providerName: "Claude", fraction: 0.42)

    private func event(_ title: String = "Standup", in minutes: Double, allDay: Bool = false) -> EarEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return EarEvent(title: title, start: start, end: start.addingTimeInterval(30 * 60), isAllDay: allDay)
    }

    private func allInputs(eventIn minutes: Double = 5) -> NotchActivityInputs {
        NotchActivityInputs(agentRequest: agent, nextEvent: event(in: minutes), playback: song, usage: usage)
    }

    /// A model whose players and calendar are driven by hand, with the contextual ear on the left.
    private func makeModel(modules: [NotchModule] = NotchModule.allCases, events: [EarEvent] = []) -> NotchModel {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        settings.modules = modules
        settings.leftEar = .automatic
        settings.rightEar = .shelf
        settings.earsVisibility = .withActivity
        let model = NotchModel(settings: settings)
        model.nowPlaying.permission = { _ in .undetermined }
        model.ears.now = { self.now }
        model.ears.fetchEvents = { events }
        model.ears.update(left: settings.leftEar, right: settings.rightEar, modules: settings.modules)
        return model
    }

    // MARK: - Priority

    @Test func anAgentAskingBeatsEverythingElse() {
        #expect(NotchActivityLogic.resolve(allInputs(), enabled: everything, now: now) == .agentRequest(agent))
    }

    @Test func eachLevelTakesOverWhenTheOneAboveIsQuiet() {
        var inputs = allInputs()
        inputs.agentRequest = nil
        #expect(NotchActivityLogic.resolve(inputs, enabled: everything, now: now) == .imminentEvent(event(in: 5)))
        inputs.nextEvent = nil
        #expect(NotchActivityLogic.resolve(inputs, enabled: everything, now: now) == .playback(song))
        inputs.playback = nil
        #expect(NotchActivityLogic.resolve(inputs, enabled: everything, now: now) == .usage(usage))
        inputs.usage = nil
        #expect(NotchActivityLogic.resolve(inputs, enabled: everything, now: now) == .rest)
    }

    @Test func anEventThatIsNotImminentYetLeavesTheMusicPlaying() {
        var inputs = allInputs(eventIn: 40)
        inputs.agentRequest = nil
        #expect(NotchActivityLogic.resolve(inputs, enabled: everything, now: now) == .playback(song))
    }

    @Test func onlySectionsThatAreOnTakePart() {
        let inputs = allInputs()
        #expect(NotchActivityLogic.resolve(inputs, enabled: everything.subtracting([.agents]), now: now)
            == .imminentEvent(event(in: 5)))
        #expect(NotchActivityLogic.resolve(inputs, enabled: [.shelf, .nowPlaying, .usage], now: now) == .playback(song))
        #expect(NotchActivityLogic.resolve(inputs, enabled: [.shelf, .usage], now: now) == .usage(usage))
        #expect(NotchActivityLogic.resolve(inputs, enabled: [.shelf, .assistant, .mirror], now: now) == .rest)
    }

    @Test func theMirrorNeverTakesPartAndItsCameraStaysOff() {
        let model = makeModel()
        model.nowPlaying.receive(state: "Playing", track: .init(title: "Teardrop", artist: ""), from: .spotify)
        #expect(model.contextualActivity.module == .nowPlaying)
        #expect(NotchActivityLogic.resolve(allInputs(), enabled: [.mirror], now: now) == .rest)
        #expect(!model.mirror.isRunning, "working out what matters never starts the camera")
    }

    @Test func imminenceHasAWindowAndAGrace() {
        #expect(NotchActivityLogic.isImminent(event(in: 15), now: now))
        #expect(!NotchActivityLogic.isImminent(event(in: 16), now: now))
        #expect(NotchActivityLogic.isImminent(event(in: -4), now: now), "just started: still worth the ear")
        #expect(!NotchActivityLogic.isImminent(event(in: -6), now: now))
        #expect(!NotchActivityLogic.isImminent(event(in: 5, allDay: true), now: now))
    }

    // MARK: - The model

    @Test func designScenariosNeverFeedTheEar() {
        let model = makeModel()
        model.nowPlaying.receive(state: "Playing", track: .init(title: "Teardrop", artist: ""), from: .spotify)
        model.scenario = .openNowPlaying
        #expect(model.contextualActivity == .rest)
        model.scenario = nil
        #expect(model.contextualActivity.module == .nowPlaying)
    }

    @Test func pausingGivesTheEarBackToWhatWasThere() {
        let model = makeModel(events: [event(in: 40)])
        #expect(model.contextualActivity == .rest)
        #expect(!model.ears.showsEars(for: model))
        model.nowPlaying.receive(state: "Playing", track: .init(title: "Teardrop", artist: "Massive Attack"), from: .spotify)
        #expect(model.contextualActivity == .playback(song))
        #expect(model.ears.showsEars(for: model))
        model.nowPlaying.receive(state: "Paused", track: nil, from: .spotify)
        #expect(model.contextualActivity == .rest)
        #expect(!model.ears.showsEars(for: model))
        model.nowPlaying.receive(state: "Playing", track: nil, from: .spotify)
        #expect(model.contextualActivity == .playback(song), "resuming brings the same song back")
    }

    @Test func anImminentEventOutranksTheMusicAndLeavesItBehind() {
        let model = makeModel(events: [event(in: 10)])
        model.nowPlaying.receive(state: "Playing", track: .init(title: "Teardrop", artist: "Massive Attack"), from: .spotify)
        #expect(model.contextualActivity == .imminentEvent(event(in: 10)))
        model.settings.modules.removeAll { $0 == .calendar }
        model.ears.update(left: .automatic, right: .shelf, modules: model.settings.modules)
        #expect(model.contextualActivity == .playback(song))
    }

    @Test func aNewSongUpdatesTheEarInPlace() {
        let model = makeModel()
        model.nowPlaying.receive(state: "Playing", track: .init(title: "Teardrop", artist: "Massive Attack"), from: .spotify)
        model.nowPlaying.receive(state: "Playing", track: .init(title: "Angel", artist: "Massive Attack"), from: .spotify)
        #expect(model.contextualActivity == .playback(PlaybackSignal(title: "Angel", artist: "Massive Attack",
                                                                     appName: "Spotify")))
    }

    @Test func turningNowPlayingOffOrClosingThePlayerQuietsTheEar() {
        let model = makeModel()
        model.nowPlaying.receive(state: "Playing", track: .init(title: "Teardrop", artist: ""), from: .music)
        model.settings.modules.removeAll { $0 == .nowPlaying }
        #expect(model.contextualActivity == .rest, "a section that's off doesn't take part")
        model.settings.modules.append(.nowPlaying)
        #expect(model.contextualActivity.module == .nowPlaying)
        model.nowPlaying.setRunningPlayersForTesting([])
        #expect(model.contextualActivity == .rest, "a player that quit said its last word")
    }

    @Test func turningTheBackgroundListeningOffForgetsTheSong() {
        let store = NowPlayingStore()
        store.permission = { _ in .undetermined }
        store.receive(state: "Playing", track: .init(title: "Teardrop", artist: ""), from: .music)
        store.watchInBackground(true)
        store.watchInBackground(false)
        #expect(store.track == nil)
        #expect(store.playbackSignal == nil)
    }

    @Test func withBothPlayersOpenTheOneThatStartedLastWins() {
        let store = NowPlayingStore()
        store.permission = { _ in .undetermined }
        store.receive(state: "Playing", track: .init(title: "Gymnopédie No. 1", artist: "Erik Satie"), from: .music)
        store.receive(state: "Playing", track: .init(title: "Teardrop", artist: "Massive Attack"), from: .spotify)
        #expect(store.track?.appName == "Spotify")
        store.receive(state: "Paused", track: nil, from: .spotify)
        #expect(store.track?.appName == "Music", "the other player is still playing")
        #expect(store.isPlaying)
        store.receive(state: "Paused", track: nil, from: .music)
        #expect(store.track?.appName == "Music", "all paused: the last one heard stays, paused")
        #expect(!store.isPlaying)
    }

    @Test func aDeniedPermissionStillShowsTheMusicWithoutScripting() async {
        let store = NowPlayingStore()
        store.permission = { _ in .denied }
        store.receive(state: "Playing", track: .init(title: "Teardrop", artist: ""), from: .spotify)
        #expect(store.isPlaying, "the broadcast alone is enough for the ear")
        #expect(store.artwork == nil)
        // The artwork check runs off the main actor: give it a moment to report back.
        for _ in 0..<50 where store.access != .denied { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(store.access == .denied, "and the section learns it may not ask, without a dialog")
    }

    // MARK: - Which sources run

    @Test func sourcesOnlyRunForEarsAndSectionsThatNeedThem() {
        #expect(EarsLogic.watchesPlayback(left: .automatic, right: .shelf, modules: [.shelf, .nowPlaying]))
        #expect(!EarsLogic.watchesPlayback(left: .automatic, right: .shelf, modules: [.shelf]))
        #expect(EarsLogic.watchesPlayback(left: .none, right: .nowPlaying, modules: [.shelf]), "a chosen music ear")
        #expect(EarsLogic.watchesPlayback(left: .nextEvent, right: .shelf, modules: NotchModule.allCases),
                "an enabled Now Playing section stays ready before it is opened")
        #expect(EarsLogic.watchesCalendar(left: .automatic, right: .shelf, modules: [.calendar]))
        #expect(!EarsLogic.watchesCalendar(left: .automatic, right: .shelf, modules: [.shelf, .nowPlaying]))
    }

    @Test func theContextualEarOnlyGrowsEarsWhenSomethingMatters() {
        #expect(!EarsLogic.showsEars(left: .automatic, right: .none, visibility: .withActivity) { _ in false })
        #expect(EarsLogic.showsEars(left: .automatic, right: .none, visibility: .withActivity) { $0 == .automatic })
        #expect(EarsLogic.showsEars(left: .automatic, right: .none, visibility: .always) { _ in false })
    }

    @Test func theShelfCountStaysOnTheRight() {
        let model = makeModel()
        model.shelf = [ShelfItem(kind: .text("hello"), displayName: "hello")]
        model.nowPlaying.receive(state: "Playing", track: .init(title: "Teardrop", artist: ""), from: .spotify)
        #expect(model.settings.rightEar == .shelf)
        #expect(model.ears.hasActivity(.shelf, in: model))
        #expect(model.ears.hasActivity(.automatic, in: model))
    }

    @Test func unrelatedActivityDoesNotReplaceExplicitFixedEars() {
        let model = makeModel()
        model.settings.leftEar = .nextEvent
        model.settings.rightEar = .shelf
        model.ears.update(left: .nextEvent, right: .shelf, modules: model.settings.modules)

        model.nowPlaying.receive(state: "Playing", track: .init(title: "Teardrop", artist: "Massive Attack"),
                                 from: .spotify)
        #expect(!model.ears.showsEars(for: model),
                "an unrelated activity must not replace the explicitly selected next-event ear")

        model.shelf = [ShelfItem(kind: .text("hello"), displayName: "hello")]
        #expect(model.ears.showsEars(for: model), "the selected shelf indicator still shows its own activity")

        model.settings.leftEar = .none
        #expect(model.ears.showsEars(for: model), "Nothing remains an explicit empty side")
    }

    // MARK: - Broadcasts

    @Test func broadcastsAreReadFromBothPlayers() throws {
        let music = try #require(NowPlayingLogic.track(from: [
            "Name": " Gymnopédie No. 1 ", "Artist": "Erik Satie", "Album": "", "Total Time": NSNumber(value: 212_000),
        ]))
        #expect(music.title == "Gymnopédie No. 1")
        #expect(music.album == nil)
        #expect(music.duration == 212)
        let spotify = try #require(NowPlayingLogic.track(from: [
            "Name": "Teardrop", "Artist": "Massive Attack", "Duration": NSNumber(value: 330_400),
            "Playback Position": NSNumber(value: 12.5),
        ]))
        #expect(spotify.duration == 330.4)
        #expect(spotify.elapsed == 12.5)
        #expect(NowPlayingLogic.track(from: ["Artist": "Nobody"]) == nil)
    }

    @Test func broadcastStatesMoveThePlayerAlong() {
        let song = NowPlayingLogic.BroadcastTrack(title: "Teardrop", artist: "Massive Attack")
        let playing = NowPlayingLogic.next(after: nil, state: "Playing", track: song)
        #expect(playing?.isPlaying == true)
        #expect(NowPlayingLogic.next(after: playing, state: "Paused", track: nil)?.isPlaying == false)
        #expect(NowPlayingLogic.next(after: playing, state: "Stopped", track: song) == nil)
        #expect(NowPlayingLogic.next(after: playing, state: "Buffering", track: nil) == playing)
        #expect(NowPlayingLogic.next(after: nil, state: "Paused", track: nil) == nil)
    }

    @Test func thePreferredPlayerWinsOnlyAmongEquals() {
        let playing = PlayerState(isPlaying: true, title: "A", artist: "")
        let paused = PlayerState(isPlaying: false, title: "B", artist: "")
        #expect(NowPlayingLogic.current([.music: playing, .spotify: paused], preferred: .spotify)?.0 == .music)
        #expect(NowPlayingLogic.current([.music: playing, .spotify: playing], preferred: .spotify)?.0 == .spotify)
        #expect(NowPlayingLogic.current([.music: paused, .spotify: paused], preferred: .spotify)?.0 == .spotify)
        #expect(NowPlayingLogic.current([:], preferred: .music) == nil)
    }

    @Test func thePermissionIsReadWithoutAsking() {
        #expect(AutomationPermission.status(for: OSStatus(0)) == .granted)
        #expect(AutomationPermission.status(for: OSStatus(-1743)) == .denied)
        #expect(AutomationPermission.status(for: OSStatus(-1744)) == .undetermined)
        #expect(AutomationPermission.status(for: OSStatus(-600)) == .unavailable)
    }

    // MARK: - Tapping

    @Test func onlyTheLeftEarCountsAsTheIndicator() {
        // An ears shape 300 pt wide centred at x = 500, with a 185 pt camera gap.
        let shape = CGRect(x: 350, y: 800, width: 300, height: 32)
        #expect(NotchActivityLogic.isOnLeftEar(CGPoint(x: 370, y: 810), shape: shape, clearWidth: 185))
        #expect(!NotchActivityLogic.isOnLeftEar(CGPoint(x: 450, y: 810), shape: shape, clearWidth: 185), "the camera")
        #expect(!NotchActivityLogic.isOnLeftEar(CGPoint(x: 630, y: 810), shape: shape, clearWidth: 185), "the shelf")
        #expect(!NotchActivityLogic.isOnLeftEar(CGPoint(x: 340, y: 810), shape: shape, clearWidth: 185), "outside")
    }

    @Test func eachActivityOpensItsOwnSection() {
        #expect(NotchActivity.agentRequest(agent).module == .agents)
        #expect(NotchActivity.imminentEvent(event(in: 5)).module == .calendar)
        #expect(NotchActivity.playback(song).module == .nowPlaying)
        #expect(NotchActivity.usage(usage).module == .usage)
        #expect(NotchActivity.rest.module == nil)
    }

    // MARK: - Accessibility

    @Test func voiceOverHearsWhatTheEarShows() {
        #expect(NotchActivityLogic.accessibilityLabel(for: .playback(song), now: now)
            == "Now playing: Teardrop by Massive Attack")
        let untitled = PlaybackSignal(title: "", artist: "", appName: "Music")
        #expect(NotchActivityLogic.accessibilityLabel(for: .playback(untitled), now: now) == "Now playing: Music")
        #expect(NotchActivityLogic.accessibilityLabel(for: .imminentEvent(event(in: 5)), now: now)
            == "Standup in 5 minutes")
        #expect(NotchActivityLogic.accessibilityLabel(for: .imminentEvent(event(in: -1)), now: now)
            == "Standup is starting now")
        #expect(NotchActivityLogic.accessibilityLabel(for: .agentRequest(agent), now: now)
            == "Claude is waiting for you in altillo")
        #expect(NotchActivityLogic.accessibilityLabel(for: .usage(usage), now: now).hasPrefix("Claude: "))
        #expect(NotchActivityLogic.accessibilityLabel(for: .rest, now: now) == "Nothing going on")
    }

    @Test func voiceOverIsToldWhereTheEarLeads() {
        #expect(NotchActivityLogic.accessibilityHint(for: .playback(song)) == "Opens Now playing")
        #expect(NotchActivityLogic.accessibilityHint(for: .imminentEvent(event(in: 5))) == "Opens Calendar")
        #expect(NotchActivityLogic.accessibilityHint(for: .rest) == nil, "resting, it isn't a button")
    }
}
