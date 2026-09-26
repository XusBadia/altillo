import AppKit
import Observation

/// What's playing right now, from any app (PLAN §5.6).
///
/// Two providers, one at a time (`NowPlayingProviderChoice`):
/// - **Universal** (`NowPlayingProvider`, normally `MediaRemoteNowPlayingProvider`): the system's Now Playing, so
///   Safari, Chrome, Podcasts, TV, VLC, IINA, Spotify, Music… all show up, with artwork, position and controls. It
///   streams changes; nothing polls. It runs only while something wants playback (the section on screen, an ear,
///   the new-song alert) and is stopped the moment nothing does.
/// - **AppleScript** (Music and Spotify only), the fallback when the universal one isn't bundled or breaks:
///   - on screen (`start()`/`stop()`): an AppleScript poll every 2 s at most, only while one of the two apps is open;
///   - off screen (`watchInBackground(_:)`, `watchForAlerts(_:)`): the distributed notifications Music and Spotify
///     post on every change. AppleScript only runs once per new track (for its artwork) or after waking, and only
///     if the user already allowed it: the permission is checked without ever showing the dialog.
///
/// The players' broadcasts are listened to in both modes: they cost nothing, fill in the first instant before the
/// universal stream reports, and tell when the universal stream has gone blind (Music playing, stream silent), in
/// which case it is switched off for the session and AppleScript takes over.
@MainActor
@Observable
final class NowPlayingStore {
    struct Track: Sendable, Equatable {
        var title: String
        var artist: String
        var album: String?
        var duration: TimeInterval?
        var elapsed: TimeInterval?
        var isPlaying: Bool
        /// Bundle identifier of the app playing it.
        var appBundleID: String
        var appName: String
        /// Playback speed (1 normally), so the groove keeps pace with a podcast at 1.5×.
        var rate: Double = 1
    }

    enum Access: Sendable { case unknown, granted, denied }

    typealias Source = NowPlayingProviderChoice.Source

    private(set) var track: Track? {
        didSet {
            guard track != oldValue else { return }
            onTrackChange?(track)
        }
    }
    private(set) var artwork: NSImage?
    /// Apple Events permission (AppleScript mode). `.denied` stops the loop: the dialog is asked for once, never in
    /// a cycle.
    private(set) var access: Access = .unknown
    /// When `track.elapsed` was read, so the progress bar can keep moving between updates.
    private(set) var sampledAt = Date.now
    /// Music and/or Spotify, as far as `NSWorkspace` knows.
    private(set) var runningPlayers: [MusicPlayer] = []
    /// Which provider feeds the store right now.
    private(set) var source: Source

    /// True while a player says it is playing (paused and stopped are not).
    var isPlaying: Bool { track?.isPlaying ?? false }

    /// Something is listening right now (the section, the ears, the alerts), so `track` is current rather than
    /// what was heard last time. Ask reads it only then, and never starts listening just to answer.
    var isListening: Bool { viewers > 0 || !backgroundReasons.isEmpty }

    /// The icon of the app playing the track.
    var sourceIcon: NSImage? {
        track.flatMap { NowPlayingSourceApp.icon(for: $0.appBundleID) }
    }

    /// Whether the groove can be scrubbed: a real track of known length.
    var canSeek: Bool { (track?.duration ?? 0) > 0 }

    /// What the contextual ear needs, while something actually plays.
    var playbackSignal: PlaybackSignal? {
        guard let track, track.isPlaying else { return nil }
        return PlaybackSignal(title: track.title, artist: track.artist, appName: track.appName)
    }

    /// The ceiling asked for in PLAN §5.6: never more often than this, and only while visible (AppleScript mode).
    static let pollInterval: Duration = .seconds(2)

    /// The store the app runs on (the first one made, the notch's). The new-song alert finds it here.
    private(set) static weak var primary: NowPlayingStore?

    /// Called whenever `track` changes (the new-song alert).
    @ObservationIgnored var onTrackChange: ((Track?) -> Void)?

    /// Checks the Apple Events permission without ever asking. Injected by tests.
    @ObservationIgnored var permission: @Sendable (MusicPlayer) async -> AutomationPermission.Status = {
        await AutomationPermission.status(for: $0.bundleID)
    }

    @ObservationIgnored private let universal: (any NowPlayingProvider)?
    @ObservationIgnored private var universalFailed = false
    /// The universal stream's latest word (`nil`: nothing is playing anywhere).
    @ObservationIgnored private var universalSnapshot: NowPlayingSnapshot?
    /// Whether the stream has reported any track since it started (the blind-stream check).
    @ObservationIgnored private var universalHasReported = false
    @ObservationIgnored private var universalRunning = false
    /// Since when a player has been broadcasting "Playing", for the blind-stream check.
    @ObservationIgnored private var playerPlayingSince: Date?
    @ObservationIgnored private var blindCheck: Task<Void, Never>?

    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var backgroundReasons: Set<BackgroundReason> = []
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var resyncTask: Task<Void, Never>?
    /// `bundleID#title#artist#album` of the artwork we already have, so it is fetched once per track. Built the
    /// same way from a poll, a broadcast and the stream, so opening the section doesn't fetch it again.
    @ObservationIgnored private var artworkKey: String?
    /// Polled first and preferred when both play: the app that last started playing.
    @ObservationIgnored private var preferred: MusicPlayer?
    /// What each player last said, from its broadcasts or a poll. Missing: stopped, quit or never heard from.
    @ObservationIgnored private var states: [MusicPlayer: PlayerState] = [:]
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var broadcastObservers: [NSObjectProtocol] = []

    private enum BackgroundReason: Hashable { case ears, alerts }

    /// The app's store: the universal provider when it is bundled (never inside the unit-test host, where the
    /// tests drive the players by hand and whatever the Mac is playing must not leak in).
    convenience init() {
        let environment = ProcessInfo.processInfo.environment
        let isTestHost = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
            .contains { environment[$0] != nil }
        let paths = isTestHost ? nil : MediaRemoteNowPlayingProvider.bundledPaths()
        self.init(universal: paths.map { MediaRemoteNowPlayingProvider(paths: $0) })
    }

    init(universal: (any NowPlayingProvider)?) {
        self.universal = universal
        self.source = NowPlayingProviderChoice.source(universalAvailable: universal != nil, universalFailed: false)
        if Self.primary == nil { Self.primary = self }
    }

    // MARK: - Who wants playback

    /// Called by the view when the module appears.
    func start() {
        viewers += 1
        guard viewers == 1 else { return }
        activate()
        if source == .appleScript {
            if access == .denied {
                // Refused earlier: look again (silently) in case it was allowed in System Settings since.
                recheckDeniedAccess()
            }
            beginLoop()
        }
    }

    /// Called by the view when the module goes away. The sources keep running only if an ear or the alert wants
    /// them.
    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        loop?.cancel()
        loop = nil
        guard backgroundReasons.isEmpty else {
            refreshDisplay()
            return
        }
        // The last track stays for the next opening (the stream or the poll corrects it at once); nothing else
        // reads it while nobody listens.
        deactivate(forget: false)
    }

    /// Listens while the section is off screen, for the ears. Idempotent. Off (and nothing else listening), it
    /// forgets what it heard: a disabled source never leaves a song behind.
    func watchInBackground(_ watching: Bool) {
        setBackground(.ears, watching)
    }

    /// Listens for the new-song alert. Idempotent.
    func watchForAlerts(_ watching: Bool) {
        setBackground(.alerts, watching)
    }

    private func setBackground(_ reason: BackgroundReason, _ watching: Bool) {
        let before = backgroundReasons
        if watching { backgroundReasons.insert(reason) } else { backgroundReasons.remove(reason) }
        guard backgroundReasons.isEmpty != before.isEmpty else { return }
        if watching {
            activate()
            resync()
        } else if viewers == 0 {
            deactivate(forget: true)
        }
    }

    /// Everything that runs while playback is wanted: the running-apps watch, the players' broadcasts and, when
    /// it's the source, the universal stream. Idempotent.
    private func activate() {
        observeWorkspace()
        refreshRunningPlayers()
        observeBroadcasts()
        startUniversal()
    }

    /// Nothing wants playback: no process, no observers and, with `forget`, no song left behind.
    private func deactivate(forget: Bool) {
        stopUniversal()
        stopObservingBroadcasts()
        resyncTask?.cancel()
        resyncTask = nil
        artworkTask?.cancel()
        artworkTask = nil
        blindCheck?.cancel()
        blindCheck = nil
        playerPlayingSince = nil
        stopObservingWorkspace()
        guard forget else { return }
        states = [:]
        clear()
    }

    /// The on-screen AppleScript poll decides what's shown (only in AppleScript mode).
    private var polls: Bool { source == .appleScript && viewers > 0 }

    // MARK: - Universal provider

    private func startUniversal() {
        guard source == .universal, !universalRunning, let universal else { return }
        universalRunning = true
        universalHasReported = false
        universal.start { [weak self] event in self?.receive(event) }
    }

    private func stopUniversal() {
        guard universalRunning else { return }
        universalRunning = false
        universal?.stop()
        universalSnapshot = nil
        universalHasReported = false
    }

    /// An event from the universal provider. Internal (not private) so tests can drive it with a fake.
    func receive(_ event: NowPlayingProviderEvent) {
        switch event {
        case let .changed(snapshot):
            guard universalRunning else { return }
            universalSnapshot = snapshot
            if snapshot != nil {
                universalHasReported = true
                blindCheck?.cancel()
                blindCheck = nil
            }
            refreshDisplay()
        case .failed:
            fallBackToAppleScript()
        }
    }

    /// The universal provider broke: AppleScript for the rest of the session ("si se rompe, se desactiva solo").
    private func fallBackToAppleScript() {
        guard source == .universal else { return }
        stopUniversal()
        universalFailed = true
        source = NowPlayingProviderChoice.source(universalAvailable: universal != nil, universalFailed: true)
        blindCheck?.cancel()
        blindCheck = nil
        if viewers > 0 {
            if access == .denied { recheckDeniedAccess() }
            beginLoop()
        }
        resync()
    }

    /// A player broadcasts "Playing" but the stream has never said a word: give it `blockedAfter`, then give up
    /// on it (MediaRemote refusing us looks exactly like this).
    private func scheduleBlindCheck() {
        guard source == .universal, universalRunning, !universalHasReported, blindCheck == nil else { return }
        blindCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NowPlayingProviderChoice.blockedAfter))
            guard !Task.isCancelled, let self else { return }
            self.blindCheck = nil
            if NowPlayingProviderChoice.looksBlocked(universalHasReported: self.universalHasReported,
                                                     playerPlayingSince: self.playerPlayingSince, now: .now) {
                self.fallBackToAppleScript()
            }
        }
    }

    // MARK: - Controls

    func playPause() {
        // The button has to answer instantly; the next update confirms it.
        if var current = track {
            current.elapsed = elapsed()
            current.isPlaying.toggle()
            track = current
            sampledAt = .now
        }
        perform(.playPause)
    }

    func next() { perform(.next) }
    func previous() { perform(.previous) }

    /// Jumps to `seconds` into the track (the groove, scrubbed).
    func seek(to seconds: TimeInterval) {
        guard var current = track, canSeek else { return }
        let target = NowPlayingSeek.clamp(seconds, duration: current.duration)
        current.elapsed = target
        track = current
        sampledAt = .now
        perform(.seek(target))
    }

    /// Elapsed time, carried forward from the last sample (at the track's rate) so the bar moves between updates.
    func elapsed(at now: Date = .now) -> TimeInterval? {
        guard let track, let sampled = track.elapsed else { return nil }
        return NowPlayingSeek.elapsed(sample: sampled, sampledAt: sampledAt, now: now, rate: track.rate,
                                      isPlaying: track.isPlaying, duration: track.duration)
    }

    private func perform(_ command: NowPlayingCommand) {
        // The stream's track: the system's own commands reach any app.
        if source == .universal, universalSnapshot != nil, let universal {
            universal.perform(command)
            return
        }
        let target = track.flatMap { MusicPlayer(rawValue: $0.appBundleID) } ?? preferred ?? runningPlayers.first
        guard let target, access != .denied else { return }
        let script: String = switch command {
        case .playPause: MusicPlayerScripts.command(.playPause, for: target)
        case .next: MusicPlayerScripts.command(.next, for: target)
        case .previous: MusicPlayerScripts.command(.previous, for: target)
        case let .seek(seconds): MusicPlayerScripts.seek(to: seconds, for: target)
        }
        Task { [weak self] in
            _ = try? await AppleScriptRunner.run(script)
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, self.polls else { return }
            await self.poll()
        }
    }

    // MARK: - What's shown

    /// Shows the stream's track when there is one, else what the players' broadcasts add up to. On screen in
    /// AppleScript mode the poll decides instead.
    private func refreshDisplay() {
        if source == .universal, let snapshot = universalSnapshot {
            show(snapshot)
            return
        }
        guard !polls else { return }
        applyStates()
    }

    private func show(_ snapshot: NowPlayingSnapshot) {
        let now = Date.now
        let fresh = NowPlayingMapping.track(from: snapshot, appName: NowPlayingSourceApp.name(for: snapshot.bundleID),
                                            now: now)
        if fresh != track {
            track = fresh
            sampledAt = now
        }
        let key = [snapshot.bundleID, snapshot.title, snapshot.artist, snapshot.album ?? ""].joined(separator: "#")
        if let data = snapshot.artwork {
            // The stream re-sends the same bytes after a pause or a seek: decode them only when the track changes
            // or the artwork arrives late.
            guard key != artworkKey || artwork == nil else { return }
            artworkKey = key
            artworkTask?.cancel()
            artwork = NSImage(data: data)
            return
        }
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        // No artwork from the system: Music and Spotify can still give theirs, if Altillo may already ask them.
        if let player = MusicPlayer(rawValue: snapshot.bundleID) {
            fetchArtwork(for: player, url: nil, onlyIfAllowed: true)
        }
    }

    // MARK: - Broadcasts

    /// A player's broadcast. Internal (not private) so tests can drive it without the real players.
    func receive(state: String?, track info: NowPlayingLogic.BroadcastTrack?, from player: MusicPlayer) {
        let previous = states[player]
        let next = NowPlayingLogic.next(after: previous, state: state, track: info)
        guard next != previous else { return }
        states[player] = next
        if next?.isPlaying == true, previous?.isPlaying != true { preferred = player }
        if states.values.contains(where: \.isPlaying) {
            if playerPlayingSince == nil { playerPlayingSince = .now }
            scheduleBlindCheck()
        } else {
            playerPlayingSince = nil
        }
        if polls {
            // On screen the poll is the truth: ask now instead of waiting up to two seconds.
            restartLoop()
        } else {
            refreshDisplay()
        }
    }

    private func observeBroadcasts() {
        guard broadcastObservers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        for player in MusicPlayer.allCases {
            broadcastObservers.append(distributed.addObserver(
                forName: player.broadcastName, object: nil, queue: .main
            ) { [weak self] notification in
                // Everything usable is pulled out of the `Any` userInfo here, and only Sendable values cross over.
                let info = notification.userInfo ?? [:]
                let state = info["Player State"] as? String
                let track = NowPlayingLogic.track(from: info)
                MainActor.assumeIsolated { self?.receive(state: state, track: track, from: player) }
            })
        }
        // Broadcasts sent while asleep are lost: look again on waking.
        broadcastObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.resync() } })
    }

    private func stopObservingBroadcasts() {
        broadcastObservers.forEach {
            DistributedNotificationCenter.default().removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        broadcastObservers.removeAll()
    }

    /// The track the players' last words add up to. Never while the poll decides.
    private func applyStates() {
        guard !polls else { return }
        guard let (player, state) = NowPlayingLogic.current(states, preferred: preferred) else {
            clear()
            return
        }
        let fresh = Track(
            title: state.title,
            artist: state.artist,
            album: state.album,
            duration: state.duration,
            elapsed: state.elapsed,
            isPlaying: state.isPlaying,
            appBundleID: player.bundleID,
            appName: player.appName
        )
        if fresh != track {
            track = fresh
            sampledAt = .now
        }
        // The one still playing when another pauses becomes the one to keep once everything is paused.
        if state.isPlaying { preferred = player }
        let key = Self.artworkKey(player: player, title: state.title, artist: state.artist, album: state.album)
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        fetchArtwork(for: player, url: state.artworkURL, onlyIfAllowed: true)
    }

    /// Catches up after starting to listen or waking: players that quit are forgotten, and in AppleScript mode the
    /// ones Altillo may already talk to are asked once (never the others: that would show the permission dialog out
    /// of nowhere). The universal stream needs no catching up: it reports its state as soon as it starts.
    private func resync() {
        refreshRunningPlayers()
        states = states.filter { runningPlayers.contains($0.key) }
        if polls {
            restartLoop()
            return
        }
        refreshDisplay()
        guard source == .appleScript, !runningPlayers.isEmpty, access != .denied else { return }
        resyncTask?.cancel()
        let players = runningPlayers
        resyncTask = Task { [weak self] in
            for player in players {
                guard let self, !Task.isCancelled else { return }
                let permission = await self.permission(player)
                guard permission == .granted, !Task.isCancelled else {
                    if permission == .denied { self.access = .denied }
                    continue
                }
                guard let output = try? await AppleScriptRunner.run(MusicPlayerScripts.status(for: player)),
                      !Task.isCancelled
                else { continue }
                self.access = .granted
                self.record(MusicPlayerScripts.parse(output), from: player)
            }
            self?.refreshDisplay()
        }
    }

    private func record(_ snapshot: PlayerSnapshot?, from player: MusicPlayer) {
        let previous = states[player]
        states[player] = snapshot.map(PlayerState.init)
        if snapshot?.isPlaying == true, previous?.isPlaying != true { preferred = player }
    }

    // MARK: - Polling (AppleScript mode, on screen)

    private func beginLoop() {
        guard loop == nil, polls, access != .denied, !runningPlayers.isEmpty else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func restartLoop() {
        loop?.cancel()
        loop = nil
        beginLoop()
    }

    private func poll() async {
        // The app that last played goes first: with only one player open this is a single `osascript` per tick.
        var order = runningPlayers
        if let preferred, let index = order.firstIndex(of: preferred) {
            order.insert(order.remove(at: index), at: 0)
        }
        var fallback: (MusicPlayer, PlayerSnapshot)?

        for player in order {
            let output: String
            do {
                output = try await AppleScriptRunner.run(MusicPlayerScripts.status(for: player))
            } catch AppleScriptRunner.Failure.notAuthorised {
                // Asked and refused. Stop: a loop here would re-open the dialog every two seconds.
                access = .denied
                loop?.cancel()
                loop = nil
                return
            } catch AppleScriptRunner.Failure.notRunning {
                states[player] = nil
                continue
            } catch {
                continue
            }
            guard polls else { return }
            if access != .granted { access = .granted }
            let snapshot = MusicPlayerScripts.parse(output)
            record(snapshot, from: player)
            guard let snapshot else { continue }
            if snapshot.isPlaying {
                apply(snapshot, from: player)
                return
            }
            if fallback == nil { fallback = (player, snapshot) }
        }

        if let (player, snapshot) = fallback {
            apply(snapshot, from: player)
        } else {
            clear()
        }
    }

    private func apply(_ snapshot: PlayerSnapshot, from player: MusicPlayer) {
        preferred = player
        track = Track(
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            duration: snapshot.duration,
            elapsed: snapshot.elapsed,
            isPlaying: snapshot.isPlaying,
            appBundleID: player.bundleID,
            appName: player.appName
        )
        sampledAt = .now

        let key = Self.artworkKey(player: player, title: snapshot.title, artist: snapshot.artist, album: snapshot.album)
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        fetchArtwork(for: player, url: snapshot.artworkURL, onlyIfAllowed: false)
    }

    private func clear() {
        track = nil
        artwork = nil
        artworkKey = nil
    }

    // MARK: - Artwork (AppleScript)

    private static func artworkKey(player: MusicPlayer, title: String, artist: String, album: String?) -> String {
        [player.bundleID, title, artist, album ?? ""].joined(separator: "#")
    }

    /// `onlyIfAllowed`: off screen, the artwork is a nicety: no dialog for it. Spotify's URL comes with a poll; from
    /// a broadcast it takes one `osascript`, once per track.
    private func fetchArtwork(for player: MusicPlayer, url: URL?, onlyIfAllowed: Bool) {
        artworkTask?.cancel()
        let key = artworkKey
        let permission = permission
        artworkTask = Task { [weak self] in
            if onlyIfAllowed {
                let status = await permission(player)
                guard status == .granted else {
                    if status == .denied { self?.access = .denied }
                    return
                }
            }
            let data: Data?
            switch player {
            case .spotify:
                var url = url
                if url == nil, let output = try? await AppleScriptRunner.run(MusicPlayerScripts.status(for: player)) {
                    url = MusicPlayerScripts.parse(output)?.artworkURL
                }
                data = await Self.download(url)
            case .music:
                data = await Self.musicArtwork()
            }
            guard !Task.isCancelled, let data, let image = NSImage(data: data) else { return }
            guard let self, self.artworkKey == key else { return }
            self.artwork = image
        }
    }

    nonisolated private static func download(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        return try? await URLSession.shared.data(for: request).0
    }

    /// Music keeps artwork inside its library, so the script spills it into a temporary file we then read.
    nonisolated private static func musicArtwork() async -> Data? {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("altillo-artwork.dat").path(percentEncoded: false)
        guard let written = try? await AppleScriptRunner.run(MusicPlayerScripts.musicArtwork(writingTo: path)),
              !written.isEmpty
        else { return nil }
        let url = URL(fileURLWithPath: written)
        let data = try? Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        return data
    }

    // MARK: - Permission

    private func recheckDeniedAccess() {
        let players = runningPlayers
        let permission = permission
        Task { [weak self] in
            for player in players {
                guard await permission(player) == .granted else { continue }
                guard let self else { return }
                self.access = .granted
                self.beginLoop()
                return
            }
        }
    }

    // MARK: - Who is running

    private func observeWorkspace() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.runningPlayersChanged() }
            })
        }
    }

    private func stopObservingWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers = []
    }

    private func runningPlayersChanged() {
        let before = runningPlayers
        refreshRunningPlayers()
        guard before != runningPlayers else { return }
        // A player that quit said its last word: forget it (it rarely broadcasts "Stopped" on the way out).
        states = states.filter { runningPlayers.contains($0.key) }
        if !states.values.contains(where: \.isPlaying) { playerPlayingSince = nil }
        if polls {
            if runningPlayers.isEmpty {
                loop?.cancel()
                loop = nil
                artworkTask?.cancel()
                clear()
            } else {
                beginLoop()
            }
        } else {
            refreshDisplay()
        }
    }

    private func refreshRunningPlayers() {
        let open = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        runningPlayers = MusicPlayer.allCases.filter { open.contains($0.bundleID) }
    }

    /// Tests: which players are open, without `NSWorkspace`.
    func setRunningPlayersForTesting(_ players: [MusicPlayer]) {
        runningPlayers = players
        states = states.filter { players.contains($0.key) }
        refreshDisplay()
    }
}

// MARK: - Mapping (pure, testable)

enum NowPlayingMapping {
    /// The store's track for a stream snapshot, with the elapsed time brought up to `now`.
    static func track(from snapshot: NowPlayingSnapshot, appName: String, now: Date) -> NowPlayingStore.Track {
        NowPlayingStore.Track(
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            duration: snapshot.duration,
            elapsed: snapshot.elapsed(at: now),
            isPlaying: snapshot.isPlaying,
            appBundleID: snapshot.bundleID,
            appName: appName,
            rate: snapshot.rate
        )
    }
}

// MARK: - Player state

/// What one player last said, from a broadcast or a poll.
struct PlayerState: Equatable, Sendable {
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String?
    var duration: TimeInterval?
    var elapsed: TimeInterval?
    var artworkURL: URL?

    init(isPlaying: Bool, title: String, artist: String, album: String? = nil, duration: TimeInterval? = nil,
         elapsed: TimeInterval? = nil, artworkURL: URL? = nil) {
        self.isPlaying = isPlaying
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.artworkURL = artworkURL
    }

    init(_ snapshot: PlayerSnapshot) {
        self.init(isPlaying: snapshot.isPlaying, title: snapshot.title, artist: snapshot.artist, album: snapshot.album,
                  duration: snapshot.duration, elapsed: snapshot.elapsed, artworkURL: snapshot.artworkURL)
    }
}

extension MusicPlayer {
    /// The state-change broadcast each player posts (the one their own widgets listen to).
    var broadcastName: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }
}

// MARK: - Logic (pure, testable)

enum NowPlayingLogic {
    /// The track a broadcast describes, free of `Notification` so tests can build it by hand.
    struct BroadcastTrack: Equatable, Sendable {
        var title: String
        var artist: String
        var album: String?
        var duration: TimeInterval?
        var elapsed: TimeInterval?
    }

    /// The track in a broadcast's userInfo, or `nil` without a name. Every key is optional: Music sends
    /// "Total Time" in ms and no position; Spotify "Duration" in ms and "Playback Position" in seconds.
    nonisolated static func track(from info: [AnyHashable: Any]) -> BroadcastTrack? {
        guard let name = (info["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }
        func text(_ key: String) -> String? {
            let value = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        func number(_ key: String) -> Double? { (info[key] as? NSNumber)?.doubleValue }
        let milliseconds = number("Total Time") ?? number("Duration")
        return BroadcastTrack(
            title: name,
            artist: text("Artist") ?? "",
            album: text("Album"),
            duration: milliseconds.flatMap { $0 > 0 ? $0 / 1000 : nil },
            elapsed: number("Playback Position").map { max(0, $0) }
        )
    }

    /// A player's state after a broadcast. "Stopped" forgets it; "Playing"/"Paused" take the new track, or flip the
    /// known one when the broadcast carries none; anything unrecognised leaves it as it was.
    static func next(after previous: PlayerState?, state: String?, track: BroadcastTrack?) -> PlayerState? {
        guard let playing = EarsLogic.isPlaying(playerState: state) else { return previous }
        if state == "Stopped" { return nil }
        guard let track else {
            guard var previous else { return nil }
            previous.isPlaying = playing
            return previous
        }
        // The same song keeps the artwork URL a poll found for it.
        let sameSong = previous.map { $0.title == track.title && $0.artist == track.artist && $0.album == track.album }
        return PlayerState(
            isPlaying: playing,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration ?? (sameSong == true ? previous?.duration : nil),
            elapsed: track.elapsed,
            artworkURL: sameSong == true ? previous?.artworkURL : nil
        )
    }

    /// The player worth showing: one that plays (the preferred one if both do), else a paused one (the preferred
    /// one first). `nil` when every player is stopped, quit or silent.
    static func current(_ states: [MusicPlayer: PlayerState], preferred: MusicPlayer?) -> (MusicPlayer, PlayerState)? {
        let order = MusicPlayer.allCases.sorted { lhs, rhs in lhs == preferred && rhs != preferred }
        let known = order.compactMap { player in states[player].map { (player, $0) } }
        return known.first { $0.1.isPlaying } ?? known.first
    }
}

// MARK: - Sample data

extension NowPlayingStore.Track {
    /// Shown in the `openNowPlaying` design scenario when nothing is actually playing.
    static let sample = NowPlayingStore.Track(
        title: "Gymnopédie No. 1",
        artist: "Erik Satie",
        album: "Trois Gymnopédies",
        duration: 212,
        elapsed: 74,
        isPlaying: true,
        appBundleID: MusicPlayer.music.bundleID,
        appName: MusicPlayer.music.appName
    )
}
