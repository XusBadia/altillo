import Foundation

/// Finds the "join this meeting" link inside a calendar event.
///
/// Organisers put it anywhere: the event's own URL, the location field or halfway down the notes. We look in all
/// three, prefer a known provider (Meet, Zoom, Teams, Webex…) and fall back to the first plain https link.
enum MeetingLink {
    /// Video-call providers we can name in the UI. Matched on the host, never on the whole string.
    enum Provider: String, CaseIterable, Sendable {
        case meet = "Meet"
        case zoom = "Zoom"
        case teams = "Teams"
        case webex = "Webex"
        case whereby = "Whereby"
        case jitsi = "Jitsi"
        case chime = "Chime"
        case around = "Around"
        case discord = "Discord"
        case slack = "Slack"

        /// Host suffixes that identify the provider (`meet.google.com`, `something.zoom.us`…).
        var hosts: [String] {
            switch self {
            case .meet: ["meet.google.com"]
            case .zoom: ["zoom.us", "zoomgov.com"]
            case .teams: ["teams.microsoft.com", "teams.live.com"]
            case .webex: ["webex.com"]
            case .whereby: ["whereby.com"]
            case .jitsi: ["meet.jit.si", "jitsi.net"]
            case .chime: ["chime.aws"]
            case .around: ["around.co"]
            case .discord: ["discord.gg", "discord.com"]
            case .slack: ["slack.com"]
            }
        }
    }

    /// The link to join, if there is one. `url` (the event's own URL field) wins over the location, and the
    /// location over the notes; a known provider always wins over a plain link.
    static func find(url: URL? = nil, location: String? = nil, notes: String? = nil) -> URL? {
        var candidates: [URL] = []
        if let url, isWeb(url) { candidates.append(url) }
        candidates += links(in: location)
        candidates += links(in: notes)
        if let known = candidates.first(where: { provider(for: $0) != nil }) { return known }
        return candidates.first
    }

    /// Which provider a link belongs to, for the button's tooltip ("Unirse por Zoom").
    static func provider(for url: URL) -> Provider? {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return nil }
        return Provider.allCases.first { provider in
            provider.hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }

    private static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Every http(s) link in a free-text field, in the order they appear.
    private static func links(in text: String?) -> [URL] {
        guard let text, !text.isEmpty, let detector = Self.detector else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap { match in
            guard let url = match.url, isWeb(url) else { return nil }
            return url
        }
    }

    /// Built once: `NSDataDetector` is expensive to create and this runs on every refresh.
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
}
