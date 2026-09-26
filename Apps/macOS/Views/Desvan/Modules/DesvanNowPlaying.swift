import AltilloDesign
import AppKit
import SwiftUI

/// The "Sonando" tab: the record sleeve, what it is, how far in you are and the three buttons that matter.
///
/// Any app that plays (Safari, Chrome, Podcasts, TV, VLC, IINA, Spotify, Music…) through the system's Now Playing;
/// Music and Spotify through AppleScript when that isn't available (`NowPlayingStore`, PLAN §5.6). The groove can be
/// scrubbed whenever the track has a known length.
struct DesvanNowPlayingView: View {
    let model: NotchModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the pointer is while scrubbing the groove (0…1), `nil` otherwise.
    @State private var scrubFraction: Double?

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
        if demo == .empty { return nil }
        if let track = store.track { return track }
        if model.scenario == .openNowPlaying { return .sample }
        return nil
    }

    /// `-demoNowPlaying` in the design scenario (DEBUG builds).
    private var demo: DesvanDebug.NowPlayingDemo? {
        model.scenario == .openNowPlaying ? DesvanDebug.nowPlayingDemo : nil
    }

    /// The playing app's icon on the sleeve: the real one, or Music's for the sample in the design scenario.
    private var appIcon: NSImage? {
        if store.track != nil { return store.sourceIcon }
        guard demo == .icon || demo == .needle else { return nil }
        return NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app")
    }

    @ViewBuilder
    private var content: some View {
        if store.source == .appleScript && store.access == .denied {
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
        } else if store.source == .universal {
            DesvanModuleNotice(
                symbol: "music.note",
                title: "Nothing playing up here",
                message: "Play music, a podcast or a video in any app and it'll show up."
            )
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

    /// The sleeve beside a column: what it is on top, the groove in the middle, the buttons at the bottom. The
    /// card's 24 pt inset around the 132 pt sleeve fills the module's 180 pt exactly; the column spans the sleeve.
    private func player(_ track: NowPlayingStore.Track) -> some View {
        HStack(spacing: 18) {
            DesvanArtwork(image: store.artwork, appIcon: appIcon,
                          appName: track.appName, isPlaying: track.isPlaying)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(track.artist.isEmpty ? track.appName : track.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(Desvan.Palette.paperSecondary)
                            .lineLimit(1)
                        if let album = track.album, !album.isEmpty {
                            Text("·").foregroundStyle(Desvan.Palette.paperTertiary)
                            Text(album)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Desvan.Palette.paperTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                Spacer(minLength: 8)
                progress(track)
                Spacer(minLength: 8)
                controls(track)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .desvanCard(radius: 16)
    }

    /// The groove: elapsed over duration, carried forward at 1 Hz between updates. Still while scrubbing.
    @ViewBuilder
    private func progress(_ track: NowPlayingStore.Track) -> some View {
        if track.isPlaying && !reduceMotion && scrubFraction == nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                groove(track, at: context.date)
            }
        } else {
            groove(track, at: .now)
        }
    }

    private func groove(_ track: NowPlayingStore.Track, at date: Date) -> some View {
        let live = store.track == nil ? track.elapsed : store.elapsed(at: date)
        // While scrubbing, the numbers follow the pointer.
        let elapsed = scrubFraction.flatMap { NowPlayingSeek.position(fraction: $0, duration: track.duration) } ?? live
        let fraction: Double = {
            guard let elapsed, let duration = track.duration, duration > 0 else { return 0 }
            return min(max(elapsed / duration, 0), 1)
        }()
        let canSeek = store.track != nil && store.canSeek
        return HStack(spacing: 8) {
            DesvanGroove(fraction: fraction, isScrubbing: scrubFraction != nil || demo == .needle,
                         onScrub: canSeek ? { scrubFraction = $0 } : nil,
                         onCommit: canSeek ? { commitScrub(to: $0, duration: track.duration) } : nil)
            Text(DesvanTrackFormat.position(elapsed: elapsed, duration: track.duration))
                .font(Desvan.Typeface.figure(12.5, weight: .medium))
                .foregroundStyle(scrubFraction == nil ? Desvan.Palette.paperTertiary : Desvan.Palette.paper)
                .monospacedDigit()
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("At \(DesvanTrackFormat.spokenPosition(elapsed: elapsed, duration: track.duration))")
        .accessibilityAdjustableAction { direction in
            guard canSeek, let current = live else { return }
            switch direction {
            case .increment: store.seek(to: current + 10)
            case .decrement: store.seek(to: current - 10)
            @unknown default: break
            }
        }
    }

    private func commitScrub(to fraction: Double, duration: TimeInterval?) {
        scrubFraction = nil
        guard let position = NowPlayingSeek.position(fraction: fraction, duration: duration) else { return }
        store.seek(to: position)
    }

    private func controls(_ track: NowPlayingStore.Track) -> some View {
        HStack(spacing: 6) {
            Button { store.previous() } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 16))
            }
            .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 32))
            .help("Previous")
            .accessibilityLabel("Previous")

            Button { store.playPause() } label: {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18)
            }
            .buttonStyle(DesvanButtonStyle(kind: .primary, height: 36))
            .help(track.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(track.isPlaying ? "Pause" : "Play")

            Button { store.next() } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 16))
            }
            .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 32))
            .help("Next")
            .accessibilityLabel("Next")
        }
        .disabled(store.track == nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(track.appName) controls")
    }
}

// MARK: - Pieces

/// The sleeve: the album cover in a shallow wooden tray, or a record when there is no artwork. The app playing it
/// sits in the corner, like a sticker on the sleeve.
private struct DesvanArtwork: View {
    let image: NSImage?
    let appIcon: NSImage?
    let appName: String
    let isPlaying: Bool

    static let side: CGFloat = 132

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(Desvan.Palette.paperTertiary)
                    }
            }
        }
        .frame(width: Self.side, height: Self.side)
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
        .shadow(color: .black.opacity(0.55), radius: 10, y: 4)
        .shadow(color: Desvan.Palette.bulb.opacity(isPlaying ? 0.16 : 0), radius: 16)
        .overlay(alignment: .bottomTrailing) {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .offset(x: 7, y: 7)
                    .help(appName)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A groove cut into the plank, filled in amber up to where you are. With `onScrub`, it can be dragged or clicked
/// to jump: the pointer target is taller than the groove it draws.
private struct DesvanGroove: View {
    let fraction: Double
    var isScrubbing = false
    var onScrub: ((Double) -> Void)?
    var onCommit: ((Double) -> Void)?

    @State private var isHovering = false

    var body: some View {
        GeometryReader { proxy in
            groove(width: proxy.size.width)
                .frame(height: 7)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(scrub(width: proxy.size.width), including: onScrub == nil ? .none : .all)
                .onHover { isHovering = $0 && onScrub != nil }
        }
        .frame(height: 28)
        .accessibilityHidden(true)
    }

    private func scrub(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in onScrub?(NowPlayingSeek.fraction(x: value.location.x, width: width)) }
            .onEnded { value in onCommit?(NowPlayingSeek.fraction(x: value.location.x, width: width)) }
    }

    private func groove(width: CGFloat) -> some View {
        let clamped = min(max(fraction, 0), 1)
        let lifted = isHovering || isScrubbing
        return ZStack(alignment: .leading) {
                Capsule()
                    .fill(Desvan.Palette.plank)
                    .overlay(alignment: .top) {
                        Capsule().fill(.black.opacity(0.35)).frame(height: 2.5).padding(.horizontal, 2)
                    }
                Capsule()
                    .fill(LinearGradient(
                        colors: [Desvan.Palette.bulb, Desvan.Palette.bulb.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: max(7, width * clamped))
                    .shadow(color: Desvan.Palette.bulb.opacity(0.35), radius: 3)
                if lifted {
                    // The needle: where a click lands, or where the drag is.
                    Circle()
                        .fill(Desvan.Palette.paper)
                        .frame(width: 13, height: 13)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                        .offset(x: max(0, width * clamped - 6.5))
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: lifted)
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
