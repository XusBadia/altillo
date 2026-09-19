import AppKit
import Observation

/// What's playing right now. Phase 1 covers Music and Spotify through AppleScript; other apps arrive with the
/// MediaRemote adapter in phase 5 (PLAN §5.6).
///
/// Nothing runs unless the module is on screen *and* one of the two apps is open: `NSWorkspace` tells us when they
/// launch and quit, so a closed Music means a cancelled poll loop, not a timer firing into the void.
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
    }

    enum Access: Sendable { case unknown, granted, denied }

    private(set) var track: Track?
    private(set) var artwork: NSImage?
    /// Apple Events permission. `.denied` stops the loop: the dialog is asked for once, never in a cycle.
    private(set) var access: Access = .unknown
    /// When `track.elapsed` was read, so the progress bar can keep moving between polls.
    private(set) var sampledAt = Date.now
    /// Music and/or Spotify, as far as `NSWorkspace` knows.
    private(set) var runningPlayers: [MusicPlayer] = []

    /// The ceiling asked for in PLAN §5.6: never more often than this, and only while visible.
    static let pollInterval: Duration = .seconds(2)

    private var viewers = 0
    private var loop: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    /// `bundleID#trackID` of the artwork we already have, so it is fetched once per track and not every 2 s.
    private var artworkKey: String?
    /// Polled first: the app that last reported playing.
    private var preferred: MusicPlayer?
    private var observers: [NSObjectProtocol] = []

    /// Called by the view when the module appears.
    func start() {
        viewers += 1
        guard viewers == 1 else { return }
        observeWorkspace()
        refreshRunningPlayers()
        beginLoop()
    }

    /// Called by the view when the module goes away: no processes, no timers, nothing.
    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        loop?.cancel()
        loop = nil
        artworkTask?.cancel()
        artworkTask = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers = []
    }

    // MARK: - Controls

    func playPause() {
        // The button has to answer instantly; the next poll confirms it 250 ms later.
        if var current = track {
            current.isPlaying.toggle()
            track = current
            sampledAt = .now
        }
        send(.playPause)
    }

    func next() { send(.next) }
    func previous() { send(.previous) }

    /// Elapsed time, carried forward from the last sample so the bar moves smoothly at 1 Hz between polls.
    func elapsed(at now: Date = .now) -> TimeInterval? {
        guard let track, let sampled = track.elapsed else { return nil }
        guard track.isPlaying else { return sampled }
        let carried = sampled + now.timeIntervalSince(sampledAt)
        guard let duration = track.duration else { return carried }
        return min(carried, duration)
    }

    private func send(_ command: MusicPlayerScripts.Command) {
        let target = track.flatMap { MusicPlayer(rawValue: $0.appBundleID) } ?? preferred ?? runningPlayers.first
        guard let target, access != .denied else { return }
        Task { [weak self] in
            _ = try? await AppleScriptRunner.run(MusicPlayerScripts.command(command, for: target))
            try? await Task.sleep(for: .milliseconds(250))
            await self?.poll()
        }
    }

    // MARK: - Polling

    private func beginLoop() {
        guard loop == nil, viewers > 0, access != .denied, !runningPlayers.isEmpty else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
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
            } catch {
                continue
            }
            if access != .granted { access = .granted }
            guard let snapshot = MusicPlayerScripts.parse(output) else { continue }
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

        let key = "\(player.bundleID)#\(snapshot.trackID)"
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        fetchArtwork(for: snapshot, from: player)
    }

    private func clear() {
        track = nil
        artwork = nil
        artworkKey = nil
    }

    // MARK: - Artwork

    private func fetchArtwork(for snapshot: PlayerSnapshot, from player: MusicPlayer) {
        artworkTask?.cancel()
        let key = artworkKey
        artworkTask = Task { [weak self] in
            let data: Data?
            switch player {
            case .spotify:
                data = await Self.download(snapshot.artworkURL)
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

    // MARK: - Who is running

    private func observeWorkspace() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.runningPlayersChanged() }
            })
        }
    }

    private func runningPlayersChanged() {
        let before = runningPlayers
        refreshRunningPlayers()
        guard before != runningPlayers else { return }
        if runningPlayers.isEmpty {
            loop?.cancel()
            loop = nil
            artworkTask?.cancel()
            clear()
        } else {
            beginLoop()
        }
    }

    private func refreshRunningPlayers() {
        let open = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        runningPlayers = MusicPlayer.allCases.filter { open.contains($0.bundleID) }
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
