import AltilloDesign
import AppKit
import SwiftUI

/// The left ear set to "What matters now": whatever `NotchActivity` puts first. An agent knocking, the countdown to
/// an event about to start, the sleeve of the song playing (or a note while its artwork isn't known), the session
/// ring. When it all goes quiet (music paused, the player closed, the section turned off) the ear goes back to
/// resting. Tapping it opens the section it's about; the coordinator reads the tap, this view only draws.
struct DesvanContextualEar: View {
    let model: NotchModel
    var style: DesvanEarContent.Style = .live

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Edit mode's slot shows what the choice is, not what happens to be going on.
        let activity = style == .preview ? NotchActivity.rest : model.contextualActivity
        ZStack {
            content(for: activity)
                .id(Kind(activity))
                .transition(.contentSwap(shift: 3, reduceMotion: reduceMotion))
        }
        .animation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion), value: Kind(activity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NotchActivityLogic.accessibilityLabel(for: activity, now: model.ears.clock))
        .accessibilityHint(NotchActivityLogic.accessibilityHint(for: activity) ?? "")
        .accessibilityAddTraits(activity.module == nil ? [] : .isButton)
        .accessibilityAction {
            if let module = activity.module { model.actions.openFromIndicator(module) }
        }
    }

    @ViewBuilder
    private func content(for activity: NotchActivity) -> some View {
        switch activity {
        case .agentRequest:
            DesvanKnockingHand(size: 13)
        case let .imminentEvent(event):
            DesvanNextEventEar(label: EarsLogic.label(for: event, now: model.ears.clock), title: event.title)
        case .playback:
            DesvanPlaybackEar(artwork: model.nowPlaying.artwork)
        case let .usage(usage):
            HStack(spacing: 5) {
                DesvanRing(value: usage.fraction, lineWidth: 2.4)
                    .frame(width: 14, height: 14)
                Text("\(Int((usage.fraction * 100).rounded()))")
                    .font(Desvan.Typeface.figure(13, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paper)
            }
        case .rest:
            if style != .live { DesvanEarGlyph(symbol: EarContent.automatic.symbol) }
        }
    }

    /// Which view is showing: a new song or a minute ticking by updates in place, a new kind of thing swaps.
    private enum Kind: Hashable {
        case agent, event, playback, usage, rest

        init(_ activity: NotchActivity) {
            switch activity {
            case .agentRequest: self = .agent
            case .imminentEvent: self = .event
            case .playback: self = .playback
            case .usage: self = .usage
            case .rest: self = .rest
            }
        }
    }
}

/// The song playing: its sleeve, small, beside the equaliser. A note stands in until (or unless) the artwork is known:
/// off screen it is only fetched if Altillo may already talk to the player.
struct DesvanPlaybackEar: View {
    let artwork: NSImage?

    private static let side: CGFloat = 18

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: Self.side, height: Self.side)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.5)
                        }
                        .transition(.opacity)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.bulb)
                        .frame(width: Self.side, height: Self.side)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: artwork != nil)
            DesvanEqualiser(isPlaying: true, height: 11)
        }
        .fixedSize()
    }
}
