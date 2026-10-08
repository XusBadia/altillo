import AltilloDesign
import AppKit
import SwiftUI

/// One resting ear (`EarItem`): a glyph and, beside it, what's going on in words: when and what the next event is,
/// which song, which agent, which provider. Built to `EarMetrics`' sizes, so the silhouette fits it exactly; titles
/// are cut at `EarMetrics.titleWidth`.
struct DesvanEarItemView: View {
    let item: EarItem
    let model: NotchModel

    var body: some View {
        content
            .help(NotchActivityLogic.earHelp(for: item, now: model.ears.clock))
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case let .agentRequest(request):
            HStack(spacing: EarMetrics.spacing) {
                DesvanKnockingHand(size: 13)
                    .frame(width: EarMetrics.Glyph.hand)
                title(request.agentName, color: Desvan.Palette.bulb)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NotchActivityLogic.accessibilityLabel(for: .agentRequest(request), now: .now))
        case let .agents(counts):
            HStack(spacing: EarMetrics.spacing) {
                Group {
                    if counts.waiting > 0 { DesvanKnockingHand(size: 12.5) } else { DesvanWorkingDots(dot: 3.5) }
                }
                .frame(width: EarMetrics.Glyph.dots)
                Text(verbatim: EarMetrics.agentsText(counts))
                    .font(Desvan.Typeface.figure(EarMetrics.TextSize.title, weight: .medium))
                    .foregroundStyle(counts.waiting > 0 ? Desvan.Palette.bulb : Desvan.Palette.paper)
                    .lineLimit(1)
                    .fixedSize()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AgentsLogic.earAccessibilityLabel(counts))
        case let .event(event, label):
            DesvanEventEar(event: event, label: label)
        case let .playback(playback):
            HStack(spacing: EarMetrics.spacing) {
                DesvanEarSleeve(artwork: model.nowPlaying.artwork)
                let name = playback.title.isEmpty ? playback.appName : playback.title
                if !name.isEmpty { title(name, color: Desvan.Palette.paper) }
                DesvanEqualiser(isPlaying: true, height: 11)
                    .frame(width: EarMetrics.Glyph.equaliser)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NotchActivityLogic.accessibilityLabel(for: .playback(playback), now: .now))
        case let .usage(usage, isStale):
            HStack(spacing: EarMetrics.spacing) {
                DesvanRing(value: usage.fraction, lineWidth: 2.4)
                    .frame(width: EarMetrics.Glyph.ring, height: EarMetrics.Glyph.ring)
                Text(verbatim: EarMetrics.percentText(usage.fraction))
                    .font(Desvan.Typeface.figure(EarMetrics.TextSize.figure, weight: .medium))
                    .foregroundStyle(Desvan.usageTint(usage.fraction))
                    .contentTransition(.numericText(value: usage.fraction))
                if !usage.providerName.isEmpty { name(usage.providerName) }
            }
            .opacity(isStale ? 0.55 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NotchActivityLogic.accessibilityLabel(for: .usage(usage), now: .now))
        case let .timer(timer):
            HStack(spacing: EarMetrics.spacing) {
                DesvanTimerEar(signal: timer)
                if !timer.label.isEmpty { name(timer.label) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NotchActivityLogic.accessibilityLabel(for: .timer(timer), now: .now))
        case let .shelf(count):
            DesvanShelfCount(count: count)
        case let .quiet(content):
            Group {
                if content == .shelf {
                    // Nobody home: the house with its light off.
                    DesvanHouseMark(size: 13, lit: 0, outline: Desvan.Palette.paperTertiary)
                } else {
                    DesvanEarGlyph(symbol: content.symbol)
                }
            }
            .frame(width: EarMetrics.Glyph.quiet)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(content.title)
        }
    }

    private func title(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(Desvan.Typeface.rounded(EarMetrics.TextSize.title, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: EarMetrics.titleWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func name(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Desvan.Typeface.rounded(EarMetrics.TextSize.name, weight: .regular))
            .foregroundStyle(Desvan.Palette.paperSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: EarMetrics.nameWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Which view is showing: a new song or a minute ticking by updates in place, a new kind of thing swaps.
    enum Kind: Hashable {
        case agentRequest, agents, event, playback, usage, timer, shelf, quiet

        init(_ item: EarItem) {
            switch item {
            case .agentRequest: self = .agentRequest
            case .agents: self = .agents
            case .event: self = .event
            case .playback: self = .playback
            case .usage: self = .usage
            case .timer: self = .timer
            case .shelf: self = .shelf
            case .quiet: self = .quiet
            }
        }
    }
}

/// The event ear: the calendar, when ("12 min", "13:30", "now", lit under the hour) and what, cut short.
struct DesvanEventEar: View {
    let event: EarEvent
    let label: EarsLogic.EventLabel

    var body: some View {
        let soon: Bool = if case .at = label { false } else { true }
        HStack(spacing: EarMetrics.spacing) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .frame(width: EarMetrics.Glyph.calendar)
            Text(verbatim: EarMetrics.eventText(for: label, hasTitle: !event.title.isEmpty))
                .font(Desvan.Typeface.figure(EarMetrics.TextSize.figure, weight: .medium))
                .foregroundStyle(soon ? Desvan.Palette.bulb : Desvan.Palette.paper)
                .lineLimit(1)
                .fixedSize()
            if !event.title.isEmpty {
                Text(verbatim: event.title)
                    .font(Desvan.Typeface.rounded(EarMetrics.TextSize.title, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: EarMetrics.titleWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NotchActivityLogic.eventAccessibilityLabel(event, label: label))
    }
}

/// The song's sleeve at ear size, or a note until (or unless) the artwork is known.
struct DesvanEarSleeve: View {
    let artwork: NSImage?

    private static let side = EarMetrics.Glyph.sleeve

    var body: some View {
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
                    .transition(.opacity)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .animation(.easeInOut(duration: 0.2), value: artwork != nil)
    }
}
