import Foundation

/// The two players Altillo can talk to today. Full support for every player (Safari, browsers, podcast apps…)
/// arrives with the `mediaremote-adapter` behind `NowPlayingProvider` in phase 5 (PLAN §5.6); until then these are
/// the only two with a stable, public scripting dictionary.
enum MusicPlayer: String, CaseIterable, Identifiable, Sendable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    var id: Self { self }
    var bundleID: String { rawValue }

    var appName: String {
        switch self {
        case .music: "Música"
        case .spotify: "Spotify"
        }
    }
}

/// What a player told us in one poll.
struct PlayerSnapshot: Sendable, Equatable {
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String?
    /// Seconds. Spotify reports milliseconds; the script divides before we ever see it.
    var duration: TimeInterval?
    var elapsed: TimeInterval?
    /// Identifies the track so the artwork is only fetched when it actually changes.
    var trackID: String
    /// Spotify hands us a URL; Music has to write the bytes to a file instead.
    var artworkURL: URL?
}

/// The AppleScript we send and the parsing of what comes back.
///
/// Fields are joined with U+001E (record separator): a character no song title contains, unlike a tab or a newline.
enum MusicPlayerScripts {
    static let separator = "\u{1E}"

    enum Command: String, Sendable {
        case playPause = "playpause"
        case next = "next track"
        case previous = "previous track"
    }

    /// Asks a player what it is doing. Returns "" when it is stopped.
    ///
    /// Variable names are deliberately long: inside a `tell application` block AppleScript resolves every token
    /// against the app's dictionary first, and short ones collide with its terminology (`st` fails to compile
    /// against Music with "Expected expression"). Verified with `osacompile` against Music's real dictionary.
    static func status(for player: MusicPlayer) -> String {
        switch player {
        case .music:
            """
            set theSep to (character id 30)
            tell application id "com.apple.Music"
            \tif player state is stopped then
            \t\treturn ""
            \tend if
            \tset theState to "paused"
            \tif player state is playing then set theState to "playing"
            \tset theTrack to current track
            \tset thePosition to "0"
            \ttry
            \t\tset thePosition to (player position) as text
            \tend try
            \tset theAlbum to ""
            \ttry
            \t\tset theAlbum to (album of theTrack) as text
            \tend try
            \treturn theState & theSep & (name of theTrack) & theSep & (artist of theTrack) & theSep & theAlbum & theSep & ((duration of theTrack) as text) & theSep & thePosition & theSep & ((database id of theTrack) as text) & theSep & ""
            end tell
            """
        case .spotify:
            """
            set theSep to (character id 30)
            tell application id "com.spotify.client"
            \tif player state is stopped then
            \t\treturn ""
            \tend if
            \tset theState to "paused"
            \tif player state is playing then set theState to "playing"
            \tset theTrack to current track
            \tset thePosition to "0"
            \ttry
            \t\tset thePosition to (player position) as text
            \tend try
            \tset theAlbum to ""
            \ttry
            \t\tset theAlbum to (album of theTrack) as text
            \tend try
            \tset theArtwork to ""
            \ttry
            \t\tset theArtwork to (artwork url of theTrack) as text
            \tend try
            \treturn theState & theSep & (name of theTrack) & theSep & (artist of theTrack) & theSep & theAlbum & theSep & (((duration of theTrack) / 1000) as text) & theSep & thePosition & theSep & (id of theTrack) & theSep & theArtwork
            end tell
            """
        }
    }

    /// Music keeps its artwork as raw bytes inside the library, so the script has to spill it into a file we can
    /// read. Returns the path, or "" when the track has no artwork.
    static func musicArtwork(writingTo path: String) -> String {
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        set thePath to "\(escaped)"
        set theData to missing value
        tell application id "com.apple.Music"
        \tif player state is stopped then
        \t\treturn ""
        \tend if
        \tset theTrack to current track
        \tif (count of artworks of theTrack) is 0 then
        \t\treturn ""
        \tend if
        \tset theData to (raw data of artwork 1 of theTrack)
        end tell
        try
        \tset theFile to (open for access (POSIX file thePath) with write permission)
        \tset eof theFile to 0
        \twrite theData to theFile
        \tclose access theFile
        on error
        \ttry
        \t\tclose access (POSIX file thePath)
        \tend try
        \treturn ""
        end try
        return thePath
        """
    }

    static func command(_ command: Command, for player: MusicPlayer) -> String {
        """
        tell application id "\(player.bundleID)" to \(command.rawValue)
        """
    }

    /// Reads one status line. `nil` when the player is stopped or said something we can't use.
    static func parse(_ output: String) -> PlayerSnapshot? {
        let fields = output.components(separatedBy: separator)
        guard fields.count >= 7 else { return nil }
        let title = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let album = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let artwork = fields.count > 7 ? fields[7].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return PlayerSnapshot(
            isPlaying: fields[0].hasPrefix("playing"),
            title: title,
            artist: fields[2].trimmingCharacters(in: .whitespacesAndNewlines),
            album: album.isEmpty ? nil : album,
            duration: number(fields[4]).flatMap { $0 > 0 ? $0 : nil },
            elapsed: number(fields[5]).map { max(0, $0) },
            trackID: fields[6].trimmingCharacters(in: .whitespacesAndNewlines),
            artworkURL: artwork.isEmpty ? nil : URL(string: artwork)
        )
    }

    /// AppleScript writes reals with the *user's* decimal separator, and sometimes in scientific notation
    /// ("2,17E+2"). Both have to survive the trip.
    static func number(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }
}
