import AVFoundation
import Foundation
import Testing
@testable import Altillo

/// Everything the now playing module does before it ever touches a player: building the script, reading the answer
/// and writing the clock.
struct NowPlayingModuleTests {
    private let separator = MusicPlayerScripts.separator

    private func line(_ fields: [String]) -> String {
        fields.joined(separator: separator)
    }

    @Test func readsAMusicAnswer() throws {
        let output = line(["playing", "Gymnopédie No. 1", "Erik Satie", "Trois Gymnopédies", "212.0", "74.5", "8412", ""])
        let snapshot = try #require(MusicPlayerScripts.parse(output))
        #expect(snapshot.isPlaying)
        #expect(snapshot.title == "Gymnopédie No. 1")
        #expect(snapshot.artist == "Erik Satie")
        #expect(snapshot.album == "Trois Gymnopédies")
        #expect(snapshot.duration == 212)
        #expect(snapshot.elapsed == 74.5)
        #expect(snapshot.trackID == "8412")
        #expect(snapshot.artworkURL == nil)
    }

    @Test func readsASpotifyAnswerWithItsArtwork() throws {
        let output = line([
            "paused", "Teardrop", "Massive Attack", "Mezzanine", "330.4", "12.0",
            "spotify:track:abc", "https://i.scdn.co/image/abc",
        ])
        let snapshot = try #require(MusicPlayerScripts.parse(output))
        #expect(!snapshot.isPlaying)
        #expect(snapshot.artworkURL?.host() == "i.scdn.co")
    }

    @Test func aStoppedPlayerSaysNothing() {
        #expect(MusicPlayerScripts.parse("") == nil)
        #expect(MusicPlayerScripts.parse("algo raro") == nil)
    }

    @Test func aTracklessAnswerIsIgnored() {
        #expect(MusicPlayerScripts.parse(line(["playing", "  ", "", "", "0", "0", "x", ""])) == nil)
    }

    @Test func appleScriptDecimalsSurviveAnySpanishMac() {
        // AppleScript writes reals with the user's separator, and long ones in scientific notation.
        #expect(MusicPlayerScripts.number("212,5") == 212.5)
        #expect(MusicPlayerScripts.number("212.5") == 212.5)
        #expect(MusicPlayerScripts.number("2,125E+2") == 212.5)
        #expect(MusicPlayerScripts.number(" 7 ") == 7)
        #expect(MusicPlayerScripts.number("") == nil)
    }

    @Test func aZeroDurationIsNoDuration() throws {
        let snapshot = try #require(MusicPlayerScripts.parse(line(["playing", "Radio", "Directo", "", "0", "0", "r", ""])))
        #expect(snapshot.duration == nil)
        #expect(snapshot.album == nil)
    }

    @Test func theScriptsNeverLaunchAnAppByName() {
        // `application id` talks to a running app; `application "Music"` would start it.
        for player in MusicPlayer.allCases {
            let script = MusicPlayerScripts.status(for: player)
            #expect(script.contains("application id \"\(player.bundleID)\""))
            #expect(!script.contains("application \"Music\""))
            #expect(!script.contains("application \"Spotify\""))
        }
    }

    /// Regression guard: `set st to …` does not compile inside a `tell application id "com.apple.Music"` block
    /// ("Expected expression but found st"), because AppleScript resolves every token against the app's dictionary
    /// first. Long, prefixed names stay clear of it.
    @Test func scriptVariablesAreTooLongToClashWithAnAppDictionary() {
        let scripts = MusicPlayer.allCases.map { MusicPlayerScripts.status(for: $0) }
            + [MusicPlayerScripts.musicArtwork(writingTo: "/tmp/a.dat")]
        for script in scripts {
            for line in script.split(separator: "\n") {
                let words = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
                // `set eof theFile to 0` sets a property, not a variable.
                guard words.first == "set", words.count > 1, words[1] != "eof" else { continue }
                let name = String(words[1])
                #expect(name.hasPrefix("the"), "la variable \(name) es demasiado corta para un bloque tell")
            }
        }
    }

    @Test func spotifyDurationsAreTurnedIntoSeconds() {
        #expect(MusicPlayerScripts.status(for: .spotify).contains("/ 1000"))
        #expect(!MusicPlayerScripts.status(for: .music).contains("/ 1000"))
    }

    @Test func theArtworkScriptEscapesThePath() {
        let script = MusicPlayerScripts.musicArtwork(writingTo: "/tmp/con \"comillas\"/a.dat")
        #expect(script.contains("\\\"comillas\\\""))
    }

    @Test func osascriptFailuresAreRecognisedByTheirAppleEventCode() {
        #expect(AppleScriptRunner.failure(status: 1, stderr: "execution error: … (-1743)") == .notAuthorised)
        #expect(AppleScriptRunner.failure(status: 1, stderr: "execution error: … (-600)") == .notRunning)
        #expect(AppleScriptRunner.failure(status: 1, stderr: "syntax error") == .failed("syntax error"))
    }

    @Test func theClockReadsLikeAPlayer() {
        #expect(DesvanTrackFormat.clock(0) == "0:00")
        #expect(DesvanTrackFormat.clock(62) == "1:02")
        #expect(DesvanTrackFormat.clock(3_754) == "1:02:34")
        #expect(DesvanTrackFormat.position(elapsed: 62, duration: 225) == "1:02 / 3:45")
        #expect(DesvanTrackFormat.position(elapsed: 62, duration: nil) == "1:02")
    }

    @Test func voiceOverHearsMinutesAndSecondsInsteadOfATime() {
        #expect(DesvanTrackFormat.spoken(62) == "1 min 2 s")
        #expect(DesvanTrackFormat.spoken(120) == "2 min")
        #expect(DesvanTrackFormat.spoken(9) == "9 s")
        #expect(DesvanTrackFormat.spokenPosition(elapsed: nil, duration: 200) == "el principio")
    }

    @MainActor
    @Test func elapsedIsCarriedForwardOnlyWhilePlaying() async {
        let store = NowPlayingStore()
        // Nothing playing: nothing to carry.
        #expect(store.elapsed() == nil)
    }

    @MainActor
    @Test func cameraPermissionMapsLikeTheCalendarOne() {
        #expect(MirrorStore.access(for: .authorized) == .granted)
        #expect(MirrorStore.access(for: .notDetermined) == .unknown)
        #expect(MirrorStore.access(for: .denied) == .denied)
        #expect(MirrorStore.access(for: .restricted) == .denied)
    }

    @MainActor
    @Test func aHiddenMirrorNeverRuns() {
        let store = MirrorStore()
        #expect(!store.isRunning)
        store.stop()
        #expect(!store.isRunning)
    }
}
