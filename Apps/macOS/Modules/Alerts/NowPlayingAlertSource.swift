import Foundation

/// Peeks when a new song starts in Music or Spotify.
///
/// Purely event-driven: both apps broadcast a distributed notification on every state change (the same one their
/// own menu bar extras and widgets listen to), so there is no polling, no AppleScript and no permission prompt —
/// just two observers that sit idle until something plays (PLAN §1.5).
///
/// Keys are documented behaviour of `com.apple.Music.playerInfo` (formerly iTunes') and
/// `com.spotify.client.PlaybackStateChanged`, unverified against a live process in this environment (neither app
/// was running); `identity(from:)` treats every key as optional and never assumes one is present.
@MainActor
final class NowPlayingAlertSource {
    private let post: (NotchAlert) -> Void
    private var enabled = false
    private var observers: [NSObjectProtocol] = []
    /// What we last alerted about. `nil` right after enabling, so the song already playing at that moment sets the
    /// baseline instead of triggering a peek — only a change afterwards counts as "new".
    private var lastAlerted: NowPlayingAlertDedupe.TrackIdentity?

    /// The two players' state-change broadcasts (PLAN §5.6: Music and Spotify today, MediaRemote later).
    private static let notificationNames: [Notification.Name] = [
        Notification.Name("com.apple.Music.playerInfo"),
        Notification.Name("com.spotify.client.PlaybackStateChanged"),
    ]

    init(post: @escaping (NotchAlert) -> Void) {
        self.post = post
    }

    /// Starts or stops watching. Idempotent.
    func update(enabled: Bool) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled
        if enabled {
            lastAlerted = nil
            observe()
        } else {
            stopObserving()
        }
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers = Self.notificationNames.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                // `Notification`'s userInfo carries `Any`, so everything usable is pulled out of it here, still
                // outside actor isolation, and only the plain Sendable result crosses into the MainActor call.
                let state = notification.userInfo?["Player State"] as? String
                let identity = Self.identity(from: notification.userInfo ?? [:])
                MainActor.assumeIsolated { self?.handle(state: state, identity: identity) }
            }
        }
    }

    private func stopObserving() {
        let center = DistributedNotificationCenter.default()
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    private func handle(state: String?, identity: NowPlayingAlertDedupe.TrackIdentity?) {
        guard enabled else { return }
        let decision = NowPlayingAlertDedupe.decide(state: state, identity: identity, lastAlerted: lastAlerted)
        lastAlerted = decision.lastAlerted
        guard decision.shouldAlert, let identity else { return }
        post(NotchAlert(
            source: .nowPlaying,
            symbol: "music.note",
            title: identity.name,
            detail: identity.artist.isEmpty ? nil : identity.artist,
            trailing: nil,
            isUrgent: false,
            module: .nowPlaying,
            duration: .seconds(3)
        ))
    }

    /// The track's identity from a player's userInfo, or `nil` when the essentials (a name) are missing. Nonisolated
    /// so it can run right inside the (not actor-isolated) notification closure, before the hop to `handle`.
    private nonisolated static func identity(from userInfo: [AnyHashable: Any]) -> NowPlayingAlertDedupe.TrackIdentity? {
        guard let rawName = userInfo["Name"] as? String else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let artist = (userInfo["Artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let id = (userInfo["Track ID"] as? String)
            ?? (userInfo["Track ID"] as? NSNumber)?.stringValue
            ?? (userInfo["PersistentID"] as? String)
        return NowPlayingAlertDedupe.TrackIdentity(id: id, name: name, artist: artist)
    }
}

// MARK: - Dedupe (pure, testable)

enum NowPlayingAlertDedupe {
    /// Identifies a track well enough to tell "still this song" from "a new one started". `id` (a stable database
    /// or Spotify URI) wins when both notifications carry it; otherwise name + artist is the next best thing.
    struct TrackIdentity: Sendable, Equatable {
        var id: String?
        var name: String
        var artist: String
    }

    struct Decision: Equatable {
        var shouldAlert: Bool
        var lastAlerted: TrackIdentity?
    }

    /// What a state-change notification should do, given what was last alerted.
    ///
    /// - Anything other than "Playing" (paused, stopped, or a state we don't recognise) never alerts, and leaves
    ///   `lastAlerted` untouched — pausing keeps the current song as the baseline, so resuming it stays quiet.
    /// - A "Playing" notification without a usable identity (missing "Name") is ignored the same way.
    /// - The first "Playing" identity we see (`lastAlerted == nil`, e.g. right after enabling) only sets the
    ///   baseline; it never alerts on its own.
    /// - Otherwise: alerts exactly when the identity differs from what was last alerted.
    static func decide(state: String?, identity: TrackIdentity?, lastAlerted: TrackIdentity?) -> Decision {
        guard state == "Playing", let identity else { return Decision(shouldAlert: false, lastAlerted: lastAlerted) }
        guard let lastAlerted else { return Decision(shouldAlert: false, lastAlerted: identity) }
        guard identity != lastAlerted else { return Decision(shouldAlert: false, lastAlerted: lastAlerted) }
        return Decision(shouldAlert: true, lastAlerted: identity)
    }
}
