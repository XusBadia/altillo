import AppKit

/// The name and icon of the app a track comes from, looked up once per app.
@MainActor
enum NowPlayingSourceApp {
    private static var names: [String: String] = [:]
    private static var icons: [String: NSImage] = [:]

    /// "Safari", "Google Chrome", "Podcasts"… Music and Spotify keep their fixed English names.
    static func name(for bundleID: String) -> String {
        if let player = MusicPlayer(rawValue: bundleID) { return player.appName }
        if let cached = names[bundleID] { return cached }
        let name = lookUpName(bundleID) ?? fallbackName(for: bundleID)
        names[bundleID] = name
        return name
    }

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }

    /// Without the app on disk: the last word of its identifier, capitalised ("com.colliderli.iina" → "Iina").
    static func fallbackName(for bundleID: String) -> String {
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return last.isEmpty ? bundleID : last.prefix(1).uppercased() + last.dropFirst()
    }

    private static func lookUpName(_ bundleID: String) -> String? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName, !name.isEmpty {
            return name
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let display = FileManager.default.displayName(atPath: url.path)
        return display.hasSuffix(".app") ? String(display.dropLast(4)) : display
    }
}
