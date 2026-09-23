import AltilloDesign
import AppKit
import SwiftUI

/// The "Sonando" tab: the record sleeve, what it is, how far in you are and the three buttons that matter.
///
/// Music and Spotify only, through AppleScript. Every other player (browsers, podcast apps, VLC…) arrives with the
/// `mediaremote-adapter` behind `NowPlayingProvider` in phase 5 (PLAN §5.6).
struct DesvanNowPlayingView: View {
    let model: NotchModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: NowPlayingStore { model.nowPlaying }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { store.start() }
            .onDisappear { store.stop() }
    }

    /// Real playback whenever there is any; the design scenario falls back to a sample so the look can be reviewed
    /// with nothing open.
    private var track: NowPlayingStore.Track? {
        if let track = store.track { return track }
        if model.scenario == .openNowPlaying { return .sample }
        return nil
    }

    @ViewBuilder
    private var content: some View {
        if store.access == .denied {
            DesvanModuleNotice(
                symbol: "hand.raised.slash",
                title: "I'm not allowed to ask",
                message: "Altillo needs permission to talk to Music and Spotify. Turn it on in System Settings › Privacy & Security › Automation.",
                actionTitle: "Open Settings"
            ) {
                PrivacySettings.automation.open()
            }
        } else if let track {
            player(track)
        } else if store.runningPlayers.isEmpty {
            DesvanModuleNotice(
                symbol: "music.note",
                title: "Nothing playing up here",
                message: "Open Music or Spotify and it'll show up."
            )
        } else {
            let players = store.runningPlayers.map(\.appName).joined(separator: String(localized: " and "))
            DesvanModuleNotice(
                symbol: "pause.circle",
                title: "All quiet",
                message: store.runningPlayers.count == 1
                    ? "\(players) is open, but nothing is playing."
                    : "\(players) are open, but nothing is playing."
            )
        }
    }

    private func player(_ track: NowPlayingStore.Track) -> some View {
        HStack(spacing: 12) {
            DesvanArtwork(image: store.artwork, isPlaying: track.isPlaying)
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(track.artist.isEmpty ? track.appName : track.artist)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Desvan.Palette.paperSecondary)
                            .lineLimit(1)
                        if let album = track.album, !album.isEmpty {
                            Text("·").foregroundStyle(Desvan.Palette.paperTertiary)
                            Text(album)
                                .font(.system(size: 11))
                                .foregroundStyle(Desvan.Palette.paperTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                progress(track)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            controls(track)
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .frame(maxHeight: .infinity)
        .padding(.vertical, 8)
        .desvanCard(radius: 13)
    }

    /// The groove: elapsed over duration, carried forward at 1 Hz between the store's two-second polls.
    @ViewBuilder
    private func progress(_ track: NowPlayingStore.Track) -> some View {
        if track.isPlaying && !reduceMotion {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                groove(track, at: context.date)
            }
        } else {
            groove(track, at: .now)
        }
    }

    private func groove(_ track: NowPlayingStore.Track, at date: Date) -> some View {
        let elapsed = store.track == nil ? track.elapsed : store.elapsed(at: date)
        let fraction: Double = {
            guard let elapsed, let duration = track.duration, duration > 0 else { return 0 }
            return min(max(elapsed / duration, 0), 1)
        }()
        return HStack(spacing: 7) {
            DesvanGroove(fraction: fraction)
            Text(DesvanTrackFormat.position(elapsed: elapsed, duration: track.duration))
                .font(Desvan.Typeface.figure(10.5, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .monospacedDigit()
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("At \(DesvanTrackFormat.spokenPosition(elapsed: elapsed, duration: track.duration))")
    }

    private func controls(_ track: NowPlayingStore.Track) -> some View {
        HStack(spacing: 4) {
            Button { store.previous() } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 11))
            }
            .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 26))
            .help("Previous")
            .accessibilityLabel("Previous")

            Button { store.playPause() } label: {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 12)
            }
            .buttonStyle(DesvanButtonStyle(kind: .primary, height: 28))
            .help(track.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(track.isPlaying ? "Pause" : "Play")

            Button { store.next() } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 11))
            }
            .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 26))
            .help("Next")
            .accessibilityLabel("Next")
        }
        .disabled(store.track == nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(track.appName) controls")
    }
}

// MARK: - Pieces

/// The sleeve: the album cover in a shallow wooden tray, or a record when there is no artwork.
private struct DesvanArtwork: View {
    let image: NSImage?
    let isPlaying: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
            } else {
                shape
                    .fill(Desvan.Palette.woodRaised)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Desvan.Palette.paperTertiary)
                    }
            }
        }
        .frame(width: 66, height: 66)
        .clipShape(shape)
        .overlay {
            // A lit top edge and a dark bottom one: the sleeve is leaning on the shelf.
            shape.strokeBorder(
                LinearGradient(
                    colors: [Desvan.Palette.paper.opacity(0.22), .black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.75
            )
        }
        .shadow(color: .black.opacity(0.55), radius: 6, y: 3)
        .shadow(color: Desvan.Palette.bulb.opacity(isPlaying ? 0.16 : 0), radius: 10)
        .accessibilityHidden(true)
    }
}

/// A groove cut into the plank, filled in amber up to where you are.
private struct DesvanGroove: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Desvan.Palette.plank)
                    .overlay(alignment: .top) {
                        Capsule().fill(.black.opacity(0.35)).frame(height: 2).padding(.horizontal, 2)
                    }
                Capsule()
                    .fill(LinearGradient(
                        colors: [Desvan.Palette.bulb, Desvan.Palette.bulb.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
                    .shadow(color: Desvan.Palette.bulb.opacity(0.35), radius: 3)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

// MARK: - Words

enum DesvanTrackFormat {
    /// "1:02 / 3:45", or just the elapsed time when the player won't say how long the track is.
    static func position(elapsed: TimeInterval?, duration: TimeInterval?) -> String {
        guard let elapsed else { return duration.map(clock) ?? "" }
        guard let duration, duration > 0 else { return clock(elapsed) }
        return String(localized: "\(clock(elapsed)) / \(clock(duration))")
    }

    static func spokenPosition(elapsed: TimeInterval?, duration: TimeInterval?) -> String {
        guard let elapsed else { return String(localized: "the start") }
        guard let duration, duration > 0 else { return spoken(elapsed) }
        return String(localized: "\(spoken(elapsed)) of \(spoken(duration))")
    }

    /// "3:45" or "1:02:30".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// "3 min 45 s", for VoiceOver: "1:02" would be read as a date.
    static func spoken(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let secs = total % 60
        if minutes == 0 { return String(localized: "\(secs) s") }
        return secs == 0 ? String(localized: "\(minutes) min") : String(localized: "\(minutes) min \(secs) s")
    }
}
