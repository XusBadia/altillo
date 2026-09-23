import AppKit
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController`. Only starts the updater when a feed URL and public
/// key are baked into Info.plist (`SUFeedURL` / `SUPublicEDKey`, set via the `ALTILLO_SPARKLE_FEED_URL`
/// / `ALTILLO_SPARKLE_PUBLIC_KEY` build settings — empty by default in `Config/Shared.xcconfig`, filled
/// in by `Config/Local.xcconfig` or `script/release.sh`). A fork building with neither configured still
/// compiles and links against Sparkle; it just never starts an updater, so update checks are
/// unavailable everywhere in the UI (see `isConfigured`). See `docs/release.md` for the one-time setup.
@MainActor
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController?

    /// Whether Sparkle is configured at all (feed URL + public key both present in Info.plist). `false`
    /// means the app was built without release signing (the normal state for a fork or a Debug build
    /// with no `Config/Local.xcconfig` Sparkle keys) — callers should disable update UI and explain why.
    let isConfigured: Bool

    private init() {
        let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !feedURL.isEmpty, !publicKey.isEmpty else {
            isConfigured = false
            controller = nil
            return
        }
        isConfigured = true
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Whether a check can be started right now — always `false` when `isConfigured` is `false`, and
    /// also `false` while a check or update is already in progress.
    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    /// Whether Sparkle checks for updates on its own schedule (persisted by Sparkle itself). Reading or
    /// writing this when `isConfigured` is `false` is a harmless no-op.
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Opens Sparkle's "checking for updates" / update-available window. Altillo is an `LSUIElement`
    /// menu-bar app with no Dock icon and no regular windows, so the window needs an explicit activation
    /// first — without it, it can open behind whatever app currently has focus.
    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
