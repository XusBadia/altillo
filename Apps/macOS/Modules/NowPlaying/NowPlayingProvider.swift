import Foundation

/// Where "what's playing" comes from (PLAN §5.6).
///
/// Two providers sit behind `NowPlayingStore`:
/// - **Universal** (`MediaRemoteNowPlayingProvider`): the system's own Now Playing, the one Control Center shows, so
///   any app works: Safari, Chrome, YouTube, Podcasts, TV, VLC, IINA, Spotify, Music… It streams changes as they
///   happen; nothing polls.
/// - **AppleScript** (built into the store): Music and Spotify only, through their broadcasts and scripting
///   dictionaries. Used when the universal provider isn't there or breaks ("si se rompe, se desactiva solo").
@MainActor
protocol NowPlayingProvider: AnyObject {
    /// Starts streaming. `handler` gets every new state (`nil`: nothing is playing anywhere) and, once, `.failed`
    /// when the provider gives up for good. Idempotent.
    func start(_ handler: @escaping @MainActor (NowPlayingProviderEvent) -> Void)
    /// Stops streaming: no process, no observers. Idempotent.
    func stop()
    /// Sends a command to whatever app is playing.
    func perform(_ command: NowPlayingCommand)
}

enum NowPlayingProviderEvent: Sendable, Equatable {
    case changed(NowPlayingSnapshot?)
    /// The provider stopped working and won't come back on its own this session.
    case failed
}

enum NowPlayingCommand: Sendable, Equatable {
    case playPause
    case next
    case previous
    /// Seconds from the start of the track.
    case seek(TimeInterval)
}

/// What the universal provider knows about the app playing right now.
struct NowPlayingSnapshot: Sendable, Equatable {
    /// The app that owns the session (for web content, the browser rather than its WebKit helper).
    var bundleID: String
    var title: String
    var artist: String
    var album: String?
    var duration: TimeInterval?
    /// Elapsed seconds at `timestamp`.
    var elapsed: TimeInterval?
    var timestamp: Date?
    /// 1 at normal speed; podcasts at 1.5× say 1.5.
    var rate: Double
    var isPlaying: Bool
    var artwork: Data?

    init(bundleID: String, title: String, artist: String = "", album: String? = nil,
         duration: TimeInterval? = nil, elapsed: TimeInterval? = nil, timestamp: Date? = nil,
         rate: Double = 1, isPlaying: Bool, artwork: Data? = nil) {
        self.bundleID = bundleID
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.rate = rate
        self.isPlaying = isPlaying
        self.artwork = artwork
    }

    /// Elapsed seconds at `now`, carried forward from `timestamp` while playing and clamped to the duration.
    func elapsed(at now: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        guard isPlaying, let timestamp else { return NowPlayingSeek.clamp(elapsed, duration: duration) }
        let carried = elapsed + max(0, now.timeIntervalSince(timestamp)) * rate
        return NowPlayingSeek.clamp(carried, duration: duration)
    }
}

// MARK: - Seek math (pure, testable)

enum NowPlayingSeek {
    /// A position inside the track: never negative, never past the end when the end is known.
    static func clamp(_ seconds: TimeInterval, duration: TimeInterval?) -> TimeInterval {
        let floor = max(0, seconds)
        guard let duration, duration > 0 else { return floor }
        return min(floor, duration)
    }

    /// The fraction of the track a point on the groove stands for (0…1).
    static func fraction(x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }

    /// Where a scrub to `fraction` lands, or `nil` when the track has no known length (live radio, streams).
    static func position(fraction: Double, duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration > 0, fraction.isFinite else { return nil }
        return min(max(fraction, 0), 1) * duration
    }

    /// The adapter wants whole microseconds.
    static func micros(_ seconds: TimeInterval) -> Int64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int64((seconds * 1_000_000).rounded())
    }

    /// Elapsed time carried forward from a sample, at `rate`, while playing.
    static func elapsed(sample: TimeInterval, sampledAt: Date, now: Date, rate: Double, isPlaying: Bool,
                        duration: TimeInterval?) -> TimeInterval {
        guard isPlaying else { return clamp(sample, duration: duration) }
        return clamp(sample + max(0, now.timeIntervalSince(sampledAt)) * rate, duration: duration)
    }
}

// MARK: - Choosing a provider (pure, testable)

enum NowPlayingProviderChoice {
    /// Which provider feeds the store.
    enum Source: Sendable, Equatable {
        case universal
        case appleScript
    }

    /// The universal provider when it exists (the helper is bundled and not given up on), else AppleScript.
    static func source(universalAvailable: Bool, universalFailed: Bool) -> Source {
        universalAvailable && !universalFailed ? .universal : .appleScript
    }

    /// How long Music or Spotify may say "Playing" while the universal stream reports nothing at all before it is
    /// considered blocked (the way macOS 15.4 blocked MediaRemote for third-party apps).
    static let blockedAfter: TimeInterval = 5

    /// The universal stream looks blocked when a player has been broadcasting "Playing" for `blockedAfter` and the
    /// stream still hasn't reported a single track since it started.
    static func looksBlocked(universalHasReported: Bool, playerPlayingSince: Date?, now: Date) -> Bool {
        guard !universalHasReported, let since = playerPlayingSince else { return false }
        return now.timeIntervalSince(since) >= blockedAfter
    }

    /// The helper may crash; it is restarted with a growing pause, and given up on after `maxFailures` in
    /// `failureWindow` (then the store falls back to AppleScript for the rest of the session).
    static let maxFailures = 3
    static let failureWindow: TimeInterval = 5 * 60

    /// When to relaunch after the helper stopped on its own, or `nil` to give up. `failures` includes this one.
    static func restartDelay(failures: [Date], now: Date) -> Duration? {
        let recent = failures.filter { now.timeIntervalSince($0) < failureWindow }
        guard recent.count < maxFailures else { return nil }
        return .seconds(1 << min(max(recent.count - 1, 0), 4))
    }
}
