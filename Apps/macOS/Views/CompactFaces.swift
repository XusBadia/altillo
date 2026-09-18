import AltilloCore
import AltilloDesign
import SwiftUI

// Faces that stay close to the notch: ears (idle), peek and the drag-armed tab.

/// The band beside the hardware notch: a left ear, the notch body (kept clear), a right ear.
struct EarBand<Leading: View, Trailing: View>: View {
    let chrome: NotchChrome
    var earWidth: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: earWidth, alignment: .center)
                .padding(.leading, chrome.topRadius)
            Color.clear.frame(width: chrome.clearWidth)
            trailing
                .frame(width: earWidth, alignment: .center)
                .padding(.trailing, chrome.topRadius)
        }
        .frame(height: chrome.bandHeight)
    }
}

// MARK: - Ears

struct EarsFace: View {
    let model: NotchModel
    let chrome: NotchChrome

    private var isScenario: Bool { model.scenario == .idleWithEars }

    var body: some View {
        EarBand(chrome: chrome, earWidth: NotchChrome.earWidth) {
            if isScenario {
                UsageEar(usage: model.demo.primaryUsage)
            }
        } trailing: {
            if !model.shelf.isEmpty {
                ShelfCountEar(count: model.shelf.count)
            }
        }
    }
}

/// Left ear: session usage of the primary provider as a tiny ring plus the figure.
struct UsageEar: View {
    let usage: ProviderUsage

    var body: some View {
        let level = UsageLevel(fraction: usage.session.used)
        HStack(spacing: 5) {
            UsageRing(value: usage.session.used, lineWidth: 2.2)
                .frame(width: 13, height: 13)
            Text("\(Int((usage.session.used * 100).rounded()))")
                .font(Tokens.Typography.numeric(11, weight: .semibold))
                .foregroundStyle(level == .normal ? Tokens.Palette.text : level.tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(usage.agent.name): \(NotchFormat.percent(usage.session.used)) de la sesión")
    }
}

/// Right ear: how many things wait in the shelf.
struct ShelfCountEar: View {
    let count: Int
    @Environment(\.altilloAccent) private var accent

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Tokens.Palette.textSecondary)
            Text("\(count)")
                .font(Tokens.Typography.numeric(11, weight: .semibold))
                .foregroundStyle(accent)
                .contentTransition(.numericText(value: Double(count)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(NotchFormat.things(count)) en el altillo")
    }
}

// MARK: - Peek

/// Hover with nothing to report: the notch grows a touch and shows what's inside, without instructions.
struct HintFace: View {
    let chrome: NotchChrome

    private let symbols = ["tray", "gauge.with.needle", "terminal"]

    var body: some View {
        if chrome.hasNotch {
            EarBand(chrome: chrome, earWidth: NotchChrome.earWidth) {
                icon(symbols[0])
            } trailing: {
                HStack(spacing: 10) { icon(symbols[1]); icon(symbols[2]) }
            }
        } else {
            HStack(spacing: 14) {
                ForEach(symbols, id: \.self, content: icon)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Tokens.Palette.textSecondary)
            .accessibilityHidden(true)
    }
}

struct PeekFace: View {
    let model: NotchModel
    let chrome: NotchChrome
    let kind: PeekKind

    @Environment(\.altilloAccent) private var accent

    var body: some View {
        if kind == .hint {
            HintFace(chrome: chrome)
        } else if chrome.hasNotch {
            VStack(spacing: 0) {
                EarBand(chrome: chrome, earWidth: NotchChrome.peekEarWidth) { leadingEar } trailing: { trailingEar }
                line
                    .frame(height: NotchChrome.peekLineHeight - 6)
                    .padding(.horizontal, chrome.topRadius + 16)
                Spacer(minLength: 0)
            }
        } else {
            line
                .padding(.horizontal, chrome.topRadius + 14)
                .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var leadingEar: some View {
        switch kind {
        case .hint:
            EmptyView()
        case .shelf:
            Image(systemName: model.shelf.isEmpty ? "tray" : "tray.full.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Tokens.Palette.textSecondary)
        case .usageAlert:
            UsageRing(value: model.demo.primaryUsage.session.used, lineWidth: 2.2)
                .frame(width: 14, height: 14)
        case .agentWaiting:
            if let agent = model.demo.waitingAgent { AgentGlyph(agent: agent.agent, size: 15) }
        }
    }

    @ViewBuilder
    private var trailingEar: some View {
        switch kind {
        case .hint:
            EmptyView()
        case .shelf:
            if !model.shelf.isEmpty {
                Text("\(model.shelf.count)")
                    .font(Tokens.Typography.numeric(11.5, weight: .semibold))
                    .foregroundStyle(accent)
            }
        case .usageAlert:
            let used = model.demo.primaryUsage.session.used
            Text(NotchFormat.percent(used))
                .font(Tokens.Typography.numeric(11.5, weight: .semibold))
                .foregroundStyle(UsageLevel(fraction: used).tint)
        case .agentWaiting:
            PulseDot(color: Tokens.Palette.warning, size: 6)
        }
    }

    @ViewBuilder
    private var line: some View {
        switch kind {
        case .hint: EmptyView()
        case .shelf: shelfLine
        case .usageAlert: usageLine
        case .agentWaiting: agentLine
        }
    }

    @ViewBuilder
    private var shelfLine: some View {
        if model.shelf.isEmpty {
            HStack(spacing: 7) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(accent)
                Text("Arrastra aquí lo que quieras guardar")
                    .font(Tokens.Typography.bodyEmphasis)
                    .foregroundStyle(Tokens.Palette.textSecondary)
            }
        } else {
            HStack(spacing: 9) {
                ThumbnailStack(items: Array(model.shelf.suffix(3)))
                Text("\(NotchFormat.things(model.shelf.count)) en el altillo")
                    .font(Tokens.Typography.bodyEmphasis)
                    .foregroundStyle(Tokens.Palette.text)
                Spacer(minLength: 8)
                if let last = model.shelf.map(\.addedAt).max() {
                    Text("la última \(NotchFormat.ago(last))")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Palette.textTertiary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var usageLine: some View {
        let usage = model.demo.primaryUsage
        return HStack(spacing: 8) {
            AgentGlyph(agent: usage.agent, size: 16)
            let percent = Text(NotchFormat.percent(usage.session.used))
                .foregroundStyle(UsageLevel(fraction: usage.session.used).tint)
            Text("\(usage.agent.name) · \(percent) de la sesión")
                .foregroundStyle(Tokens.Palette.text)
                .font(Tokens.Typography.bodyEmphasis)
                .monospacedDigit()
            Spacer(minLength: 8)
            Text("se reinicia en \(NotchFormat.countdown(to: usage.session.resetsAt))")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Palette.textTertiary)
                .monospacedDigit()
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var agentLine: some View {
        if let agent = model.demo.waitingAgent {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.Palette.warning)
                let project = Text(agent.project).foregroundStyle(Tokens.Palette.text).fontWeight(.semibold)
                Text("\(agent.agent.name) espera permiso en \(project)")
                    .foregroundStyle(Tokens.Palette.textSecondary)
                    .font(Tokens.Typography.bodyEmphasis)
                Spacer(minLength: 8)
                Text(NotchFormat.ago(agent.lastActivity))
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Palette.textTertiary)
                    .monospacedDigit()
            }
            .lineLimit(1)
        }
    }
}

/// Up to a few thumbnails overlapping like an avatar stack, newest on top, each cut out with a black ring.
struct ThumbnailStack: View {
    let items: [ShelfItem]
    var side: CGFloat = 20

    var body: some View {
        HStack(spacing: -side * 0.38) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ShelfThumbnail(item: item, side: side, compact: true)
                    .padding(1.5)
                    .background {
                        RoundedRectangle(cornerRadius: side * 0.24 + 1.5, style: .continuous).fill(.black)
                    }
                    .zIndex(Double(index))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Drag armed

struct DragArmedFace: View {
    let chrome: NotchChrome
    @Environment(\.altilloAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: chrome.bandHeight)
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .symbolEffect(.bounce.down.byLayer, options: .repeat(.periodic(delay: 1.4)), isActive: !reduceMotion)
                Text("Suelta aquí")
                    .font(Tokens.Typography.label)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(accent)
            .frame(maxHeight: .infinity)
            .padding(.bottom, chrome.hasNotch ? 4 : 0)
        }
        .background(alignment: .bottom) {
            // A warm glow rising from the lip of the tab.
            Ellipse()
                .fill(accent.opacity(0.28))
                .frame(width: chrome.size.width * 0.8, height: 36)
                .blur(radius: 16)
                .offset(y: 22)
        }
    }
}
