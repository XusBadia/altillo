import AppKit
import Observation

/// What's playing right now. Phase 1 covers Music and Spotify through AppleScript; other apps arrive with the
/// MediaRemote adapter in phase 5 (PLAN §5.6). STUB: implemented by the modules work. Keep this API.
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

    private(set) var track: Track?
    private(set) var artwork: NSImage?

    func start() {}
    func stop() {}
    func playPause() {}
    func next() {}
    func previous() {}
}
