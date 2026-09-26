import AppKit
import Foundation
import Testing
@testable import Altillo

/// The universal Now Playing provider: reading the adapter's stream, mapping it onto the store's track, the seek
/// math, and choosing (and giving up on) a provider.
struct NowPlayingProviderTests {
    // MARK: - Fixtures (the shape `mediaremote-adapter stream --micros` prints)

    /// Safari playing a YouTube video: full state, web content attributed to its parent app.
    static let safariFull = """
    {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.WebKit.GPU",\
    "parentApplicationBundleIdentifier":"com.apple.Safari","processIdentifier":4242,"playing":true,\
    "title":"Lo-fi beats to study to","artist":"Chilled Cow","durationMicros":7200000000,\
    "elapsedTimeMicros":61500000,"timestampEpochMicros":1790000000000000,"playbackRate":1,\
    "mediaType":"kMRMediaRemoteNowPlayingInfoTypeVideo"}}
    """

    /// Podcasts at 1.5×, with a tiny PNG as artwork.
    static let podcastsFull = """
    {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.podcasts","processIdentifier":77,\
    "playing":true,"title":"Episode 12","artist":"The Show","album":"The Show","durationMicros":3600000000,\
    "elapsedTimeMicros":0,"timestampEpochMicros":1790000000000000,"playbackRate":1.5,\
    "artworkMimeType":"image/png","artworkData":"\(pngBase64)"}}
    """

    static let paused = """
    {"type":"data","diff":true,"payload":{"playing":false,"playbackRate":0,"elapsedTimeMicros":90000000,\
    "timestampEpochMicros":1790000030000000}}
    """

    static let nothing = #"{"type":"data","diff":false,"payload":{}}"#

    /// A 1×1 PNG.
    static let pngBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    // MARK: - Parsing

    @Test func aFullStateBecomesASnapshotNamedAfterTheBrowser() throws {
        var stream = MediaRemoteAdapterStream()
        let consumed = stream.consume(line: Self.safariFull)
        let snapshot = try #require(consumed ?? nil)
        #expect(snapshot.bundleID == "com.apple.Safari", "the WebKit helper's parent is the app worth naming")
        #expect(snapshot.title == "Lo-fi beats to study to")
        #expect(snapshot.artist == "Chilled Cow")
        #expect(snapshot.album == nil)
        #expect(snapshot.duration == 7200)
        #expect(snapshot.elapsed == 61.5)
        #expect(snapshot.timestamp == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(snapshot.isPlaying)
        #expect(snapshot.rate == 1)
        #expect(snapshot.artwork == nil)
    }

    @Test func theArtworkIsDecodedOnce() throws {
        var stream = MediaRemoteAdapterStream()
        let consumed = stream.consume(line: Self.podcastsFull)
        let snapshot = try #require(consumed ?? nil)
        let artwork = try #require(snapshot.artwork)
        #expect(NSImage(data: artwork) != nil)
        #expect(snapshot.rate == 1.5)
        #expect(snapshot.bundleID == "com.apple.podcasts")
        if case .data? = stream.state["artworkData"] {} else { Issue.record("artwork kept as bytes, not base64") }
    }

    @Test func aDiffUpdatesOnlyWhatChanged() throws {
        var stream = MediaRemoteAdapterStream()
        _ = stream.consume(line: Self.podcastsFull)
        let consumed = stream.consume(line: Self.paused)
        let snapshot = try #require(consumed ?? nil)
        #expect(!snapshot.isPlaying)
        #expect(snapshot.title == "Episode 12", "the title carries over from the full state")
        #expect(snapshot.elapsed == 90)
        #expect(snapshot.rate == 1, "a paused player's rate of 0 means nothing")
        #expect(snapshot.artwork != nil, "the artwork stays until it changes")
    }

    @Test func aNullInADiffRemovesTheKey() throws {
        var stream = MediaRemoteAdapterStream()
        _ = stream.consume(line: Self.podcastsFull)
        let line = #"{"type":"data","diff":true,"payload":{"album":null,"artworkData":null,"artworkMimeType":null}}"#
        let consumed = stream.consume(line: line)
        let snapshot = try #require(consumed ?? nil)
        #expect(snapshot.album == nil)
        #expect(snapshot.artwork == nil)
    }

    @Test func anEmptyPayloadMeansNothingIsPlaying() throws {
        var stream = MediaRemoteAdapterStream()
        _ = stream.consume(line: Self.safariFull)
        let result = stream.consume(line: Self.nothing)
        #expect(result == .some(nil))
        #expect(stream.state.isEmpty)
    }

    @Test func aNewFullStateReplacesTheOldOne() throws {
        var stream = MediaRemoteAdapterStream()
        _ = stream.consume(line: Self.podcastsFull)
        let consumed = stream.consume(line: Self.safariFull)
        let snapshot = try #require(consumed ?? nil)
        #expect(snapshot.album == nil, "nothing leaks over from the podcast")
        #expect(snapshot.artwork == nil)
    }

    @Test func linesThatAreNotDataLeaveTheStateAlone() throws {
        var stream = MediaRemoteAdapterStream()
        _ = stream.consume(line: Self.safariFull)
        for line in ["", "Failed to initialize MediaRemote Framework", #"{"type":"log","payload":{}}"#, "{not json"] {
            let result = stream.consume(line: line)
            #expect(result == nil, "\(line) is not a data message")
        }
        #expect(MediaRemoteAdapterStream.snapshot(from: stream.state)?.title == "Lo-fi beats to study to")
    }

    @Test func withoutTheEssentialsThereIsNoTrack() {
        var stream = MediaRemoteAdapterStream()
        let noTitle = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"org.videolan.vlc","playing":true,"title":"  "}}"#
        let noTitleResult = stream.consume(line: noTitle)
        #expect(noTitleResult == .some(nil))
        let noApp = #"{"type":"data","diff":false,"payload":{"playing":true,"title":"Song"}}"#
        let noAppResult = stream.consume(line: noApp)
        #expect(noAppResult == .some(nil))
        let noFlag = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.colliderli.iina","title":"Film"}}"#
        let noFlagResult = stream.consume(line: noFlag)
        #expect(noFlagResult == .some(nil))
    }

    @Test func plainSecondsAreReadTooWhenMicrosAreMissing() throws {
        let line = """
        {"type":"data","diff":false,"payload":{"bundleIdentifier":"org.videolan.vlc","playing":false,\
        "title":"Film","duration":5400.5,"elapsedTime":12}}
        """
        var stream = MediaRemoteAdapterStream()
        let consumed = stream.consume(line: line)
        let snapshot = try #require(consumed ?? nil)
        #expect(snapshot.duration == 5400.5)
        #expect(snapshot.elapsed == 12)
    }

    /// A real capture from macOS 27.0 (26A428): a silent test session played, paused, seeked to 2:00, resumed and
    /// skipped, driven through the adapter's own `send`/`seek`.
    @Test func aRealMacOS27StreamReplaysIntoTheRightStates() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "macos27-stream", withExtension: "jsonl"))
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 10)
        var stream = MediaRemoteAdapterStream()
        var states: [NowPlayingSnapshot?] = []
        for line in lines {
            let consumed = stream.consume(line: line)
            let state = try #require(consumed, "every line is a data message")
            states.append(state)
        }
        #expect(states[0] == nil, "nothing playing when the stream starts")
        let started = try #require(states[1])
        #expect(started.bundleID == "dev.altillo.livecheck")
        #expect(started.title == "Altillo live check")
        #expect(started.artist == "Fake Artist")
        #expect(started.album == "Fake Album")
        #expect(started.duration == 300)
        #expect(started.isPlaying)
        #expect(started.artwork == nil, "the artwork comes a moment later")
        let withArtwork = try #require(states[2]?.artwork)
        #expect(NSImage(data: withArtwork) != nil, "a real JPEG")
        #expect(states[3]?.isPlaying == false)
        #expect(states[5]?.elapsed == 120, "the seek lands at 2:00")
        #expect(states[5]?.artwork != nil, "diffs keep the artwork")
        #expect(states[6]?.isPlaying == true)
        let skipped = try #require(states[8])
        #expect(skipped.title == "Altillo live check 2")
        #expect(skipped.artwork == nil, "a new track starts without the old sleeve")
        #expect(states[9]?.artwork != nil)
    }

    @Test func linesSplitAcrossChunksAreJoined() {
        var splitter = LineSplitter()
        let bytes = Data((Self.nothing + "\n" + Self.safariFull + "\n").utf8)
        let cut = bytes.count / 2
        let first = splitter.append(bytes.prefix(cut))
        let second = splitter.append(bytes.suffix(from: cut))
        #expect((first + second) == [Self.nothing, Self.safariFull])
        // A multi-byte character cut in half survives.
        let accented = Data("Gymnopédie\n".utf8)
        var other = LineSplitter()
        let index = accented.firstIndex(of: 0xC3)! + 1
        #expect(other.append(accented.prefix(upTo: index)).isEmpty)
        #expect(other.append(accented.suffix(from: index)) == ["Gymnopédie"])
    }

    // MARK: - Mapping onto the store's track

    @Test func aSnapshotMapsOntoTheStoresTrackWithTheElapsedTimeBroughtUpToNow() throws {
        var stream = MediaRemoteAdapterStream()
        let consumed = stream.consume(line: Self.podcastsFull)
        let snapshot = try #require(consumed ?? nil)
        let now = Date(timeIntervalSince1970: 1_790_000_010)
        let track = NowPlayingMapping.track(from: snapshot, appName: "Podcasts", now: now)
        #expect(track.title == "Episode 12")
        #expect(track.appBundleID == "com.apple.podcasts")
        #expect(track.appName == "Podcasts")
        #expect(track.elapsed == 15, "10 s at 1.5×")
        #expect(track.rate == 1.5)
        #expect(track.duration == 3600)
    }

    @MainActor
    @Test func appNamesComeFromTheSystemOrTheIdentifier() {
        #expect(NowPlayingSourceApp.name(for: "com.apple.Music") == "Music")
        #expect(NowPlayingSourceApp.name(for: "com.spotify.client") == "Spotify")
        #expect(NowPlayingSourceApp.fallbackName(for: "com.colliderli.iina") == "Iina")
        #expect(NowPlayingSourceApp.name(for: "com.example.not-installed-player") == "Not-installed-player")
        #expect(NowPlayingSourceApp.name(for: "com.apple.Safari") == "Safari")
        #expect(NowPlayingSourceApp.icon(for: "com.apple.Safari") != nil, "the sleeve's app sticker")
        #expect(NowPlayingSourceApp.icon(for: "com.example.not-installed-player") == nil)
    }

    // MARK: - Seek math

    @Test func scrubbingMapsThePointerOntoTheTrack() {
        #expect(NowPlayingSeek.fraction(x: 50, width: 200) == 0.25)
        #expect(NowPlayingSeek.fraction(x: -10, width: 200) == 0)
        #expect(NowPlayingSeek.fraction(x: 260, width: 200) == 1)
        #expect(NowPlayingSeek.fraction(x: 10, width: 0) == 0)
        #expect(NowPlayingSeek.position(fraction: 0.25, duration: 200) == 50)
        #expect(NowPlayingSeek.position(fraction: 1.4, duration: 200) == 200)
        #expect(NowPlayingSeek.position(fraction: 0.5, duration: nil) == nil, "live streams can't be scrubbed")
        #expect(NowPlayingSeek.position(fraction: 0.5, duration: 0) == nil)
        #expect(NowPlayingSeek.position(fraction: .nan, duration: 200) == nil)
    }

    @Test func positionsAreClampedAndSentInMicroseconds() {
        #expect(NowPlayingSeek.clamp(-3, duration: 100) == 0)
        #expect(NowPlayingSeek.clamp(130, duration: 100) == 100)
        #expect(NowPlayingSeek.clamp(130, duration: nil) == 130)
        #expect(NowPlayingSeek.micros(61.5) == 61_500_000)
        #expect(NowPlayingSeek.micros(-1) == 0)
        #expect(NowPlayingSeek.micros(.infinity) == 0)
    }

    @Test func elapsedTimeMovesAtTheTracksRateOnlyWhilePlaying() {
        let sampled = Date(timeIntervalSince1970: 1_000)
        let later = sampled.addingTimeInterval(10)
        #expect(NowPlayingSeek.elapsed(sample: 20, sampledAt: sampled, now: later, rate: 1, isPlaying: true,
                                       duration: 200) == 30)
        #expect(NowPlayingSeek.elapsed(sample: 20, sampledAt: sampled, now: later, rate: 2, isPlaying: true,
                                       duration: 200) == 40)
        #expect(NowPlayingSeek.elapsed(sample: 20, sampledAt: sampled, now: later, rate: 1, isPlaying: false,
                                       duration: 200) == 20)
        #expect(NowPlayingSeek.elapsed(sample: 195, sampledAt: sampled, now: later, rate: 1, isPlaying: true,
                                       duration: 200) == 200, "never past the end")
        let snapshot = NowPlayingSnapshot(bundleID: "x", title: "t", duration: 100, elapsed: 10, timestamp: sampled,
                                          rate: 1, isPlaying: true)
        #expect(snapshot.elapsed(at: later) == 20)
        #expect(snapshot.elapsed(at: sampled.addingTimeInterval(-5)) == 10, "a clock skew never runs it backwards")
    }

    // MARK: - Commands

    @MainActor
    @Test func commandsUseMediaRemotesIDs() {
        let paths = MediaRemoteNowPlayingProvider.Paths(
            perl: URL(fileURLWithPath: "/usr/bin/perl"),
            script: URL(fileURLWithPath: "/A.app/F/MediaRemoteAdapter.framework/Resources/mediaremote-adapter.pl"),
            framework: URL(fileURLWithPath: "/A.app/F/MediaRemoteAdapter.framework")
        )
        #expect(MediaRemoteNowPlayingProvider.commandArguments(.playPause, paths: paths).suffix(2) == ["send", "2"])
        #expect(MediaRemoteNowPlayingProvider.commandArguments(.next, paths: paths).suffix(2) == ["send", "4"])
        #expect(MediaRemoteNowPlayingProvider.commandArguments(.previous, paths: paths).suffix(2) == ["send", "5"])
        #expect(MediaRemoteNowPlayingProvider.commandArguments(.seek(61.5), paths: paths).suffix(2)
            == ["seek", "61500000"])
        let stream = MediaRemoteNowPlayingProvider.streamArguments(paths)
        #expect(stream.prefix(3) == [paths.script.path, paths.framework.path, "stream"])
        #expect(stream.contains("--micros"))
    }

    @Test func theAppleScriptFallbackSeeksWithADotWhateverTheLocale() {
        let script = MusicPlayerScripts.seek(to: 61.5, for: .spotify)
        #expect(script == #"tell application id "com.spotify.client" to set player position to 61.50"#)
        #expect(MusicPlayerScripts.seek(to: -4, for: .music).hasSuffix("to 0.00"))
    }

    @MainActor
    @Test func theHelperShipsInsideTheApp() throws {
        // The unit tests run inside Altillo.app, so this is the real bundle layout.
        let paths = try #require(MediaRemoteNowPlayingProvider.bundledPaths())
        #expect(paths.perl.path == "/usr/bin/perl")
        #expect(FileManager.default.fileExists(atPath: paths.script.path))
        #expect(paths.framework.lastPathComponent == "MediaRemoteAdapter.framework")
        #expect(MediaRemoteNowPlayingProvider.bundledPaths(in: Bundle(for: BundleToken.self)) == nil,
                "a bundle without it finds nothing")
    }

    // MARK: - Choosing a provider

    @Test func theUniversalProviderIsPreferredUntilItFails() {
        #expect(NowPlayingProviderChoice.source(universalAvailable: true, universalFailed: false) == .universal)
        #expect(NowPlayingProviderChoice.source(universalAvailable: true, universalFailed: true) == .appleScript)
        #expect(NowPlayingProviderChoice.source(universalAvailable: false, universalFailed: false) == .appleScript)
    }

    @Test func aCrashingHelperIsRestartedThenGivenUpOn() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(NowPlayingProviderChoice.restartDelay(failures: [now], now: now) == .seconds(1))
        #expect(NowPlayingProviderChoice.restartDelay(failures: [now - 10, now], now: now) == .seconds(2))
        #expect(NowPlayingProviderChoice.restartDelay(failures: [now - 20, now - 10, now], now: now) == nil)
        #expect(NowPlayingProviderChoice.restartDelay(failures: [now - 900, now - 600, now], now: now) == .seconds(1),
                "old crashes are forgiven")
    }

    @Test func aSilentStreamWhileMusicPlaysLooksBlocked() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(NowPlayingProviderChoice.looksBlocked(universalHasReported: false, playerPlayingSince: now - 6,
                                                      now: now))
        #expect(!NowPlayingProviderChoice.looksBlocked(universalHasReported: false, playerPlayingSince: now - 2,
                                                       now: now), "give it a moment")
        #expect(!NowPlayingProviderChoice.looksBlocked(universalHasReported: true, playerPlayingSince: now - 60,
                                                       now: now), "it has reported: it works")
        #expect(!NowPlayingProviderChoice.looksBlocked(universalHasReported: false, playerPlayingSince: nil, now: now))
    }
}

private final class BundleToken {}

// MARK: - The store with a fake universal provider

@MainActor
final class FakeNowPlayingProvider: NowPlayingProvider {
    private(set) var isRunning = false
    private(set) var starts = 0
    private(set) var commands: [NowPlayingCommand] = []
    private var handler: (@MainActor (NowPlayingProviderEvent) -> Void)?

    func start(_ handler: @escaping @MainActor (NowPlayingProviderEvent) -> Void) {
        self.handler = handler
        guard !isRunning else { return }
        isRunning = true
        starts += 1
    }

    func stop() { isRunning = false }
    func perform(_ command: NowPlayingCommand) { commands.append(command) }
    func send(_ event: NowPlayingProviderEvent) { handler?(event) }
}

@MainActor
struct NowPlayingStoreProviderTests {
    private let chrome = NowPlayingSnapshot(bundleID: "com.google.Chrome", title: "Talk", artist: "Channel",
                                            duration: 600, elapsed: 30, timestamp: .now, isPlaying: true)

    private func makeStore() -> (NowPlayingStore, FakeNowPlayingProvider) {
        let fake = FakeNowPlayingProvider()
        let store = NowPlayingStore(universal: fake)
        store.permission = { _ in .undetermined }
        return (store, fake)
    }

    @Test func theStreamOnlyRunsWhileSomethingWantsPlayback() {
        let (store, fake) = makeStore()
        #expect(store.source == .universal)
        #expect(!fake.isRunning, "nothing asked: no helper")
        store.start()
        #expect(fake.isRunning)
        store.stop()
        #expect(!fake.isRunning, "section closed, no ear, no alert: the helper goes")
        store.watchInBackground(true)
        store.watchForAlerts(true)
        #expect(fake.isRunning)
        store.watchInBackground(false)
        #expect(fake.isRunning, "the alert still wants it")
        store.watchForAlerts(false)
        #expect(!fake.isRunning)
    }

    @Test func anyAppShowsUpWithItsNameAndFeedsTheEar() {
        let (store, fake) = makeStore()
        store.watchInBackground(true)
        fake.send(.changed(chrome))
        #expect(store.track?.title == "Talk")
        #expect(store.track?.appBundleID == "com.google.Chrome")
        #expect(store.isPlaying)
        #expect(store.playbackSignal?.title == "Talk")
        #expect(store.canSeek)
        fake.send(.changed(nil))
        #expect(store.track == nil, "nothing playing anywhere")
    }

    @Test func controlsGoToTheStreamsAppAndSeekIsClamped() {
        let (store, fake) = makeStore()
        store.watchInBackground(true)
        fake.send(.changed(chrome))
        store.playPause()
        #expect(store.isPlaying == false, "the button answers before the app does")
        store.next()
        store.previous()
        store.seek(to: 900)
        #expect(fake.commands == [.playPause, .next, .previous, .seek(600)])
        #expect(store.elapsed() == 600)
    }

    @Test func theBroadcastsFillInUntilTheStreamSpeaks() {
        let (store, fake) = makeStore()
        store.watchInBackground(true)
        store.receive(state: "Playing", track: .init(title: "Teardrop", artist: "Massive Attack"), from: .spotify)
        #expect(store.track?.appName == "Spotify")
        fake.send(.changed(chrome))
        #expect(store.track?.appName != "Spotify", "the system's Now Playing wins once it reports")
        #expect(store.track?.title == "Talk")
    }

    @Test func aFailedProviderFallsBackToAppleScriptForGood() {
        let (store, fake) = makeStore()
        store.watchInBackground(true)
        fake.send(.changed(chrome))
        fake.send(.failed)
        #expect(store.source == .appleScript)
        #expect(!fake.isRunning)
        store.receive(state: "Playing", track: .init(title: "Teardrop", artist: ""), from: .music)
        #expect(store.track?.appName == "Music", "Music and Spotify keep working through their broadcasts")
        fake.send(.changed(chrome))
        #expect(store.track?.appName == "Music", "a stale event from the dead provider is ignored")
        store.watchInBackground(false)
        store.watchInBackground(true)
        #expect(fake.starts == 1, "never restarted this session")
    }

    @Test func withoutAUniversalProviderItIsAppleScriptFromTheStart() {
        let store = NowPlayingStore(universal: nil)
        #expect(store.source == .appleScript)
    }

    @Test func theNewSongAlertReadsTheStore() {
        let (store, fake) = makeStore()
        var posted: [String] = []
        let alerts = NowPlayingAlertSource(store: store) { posted.append($0.title) }
        alerts.update(enabled: true)
        #expect(fake.isRunning, "enabling the alert starts listening")
        fake.send(.changed(chrome))
        #expect(posted.isEmpty, "the first song sets the baseline")
        var next = chrome
        next.title = "Another talk"
        fake.send(.changed(next))
        #expect(posted == ["Another talk"])
        next.isPlaying = false
        fake.send(.changed(next))
        next.isPlaying = true
        fake.send(.changed(next))
        #expect(posted == ["Another talk"], "pausing and resuming isn't a new song")
        alerts.update(enabled: false)
        #expect(!fake.isRunning)
        #expect(store.onTrackChange == nil)
    }

    @Test func theAlertTellsApartTheSameSongInAnotherApp() {
        let safari = NowPlayingStore.Track(title: "Song", artist: "A", isPlaying: true,
                                           appBundleID: "com.apple.Safari", appName: "Safari")
        var music = safari
        music.appBundleID = "com.apple.Music"
        let first = NowPlayingAlertDedupe.input(from: safari)
        let second = NowPlayingAlertDedupe.input(from: music)
        #expect(first.state == "Playing")
        #expect(first.identity != second.identity)
        #expect(NowPlayingAlertDedupe.input(from: nil).identity == nil)
    }
}
