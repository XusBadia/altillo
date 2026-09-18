import AltilloCore
import AltilloDesign
import SwiftUI

// Faces that stay close to the notch: ears (idle), peek and the drag-armed tab.

/// The band beside the hardware notch: a left ear, the notch body (kept clear), a right ear.
private struct FluidoEarBand<Leading: View, Trailing: View>: View {
    let chrome: FluidoChrome
    var earWidth: CGFloat = FluidoChrome.earWidth
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(width: earWidth).padding(.leading, chrome.topRadius)
            Color.clear.frame(width: chrome.clearWidth)
            trailing.frame(width: earWidth).padding(.trailing, chrome.topRadius)
        }
        .frame(height: chrome.bandHeight)
    }
}

// MARK: - Ears

struct FluidoEarsFace: View {
    let model: NotchModel
    let chrome: FluidoChrome

    private var showsUsage: Bool { model.scenario == .idleWithEars }

    var body: some View {
        if chrome.hasNotch {
            FluidoEarBand(chrome: chrome) {
                if showsUsage { UsageEarFigure(usage: model.demo.primaryUsage) }
            } trailing: {
                if !model.shelf.isEmpty { ShelfEarFigure(count: model.shelf.count) }
            }
        } else {
            HStack(spacing: 14) {
                if showsUsage { UsageEarFigure(usage: model.demo.primaryUsage) }
                if !model.shelf.isEmpty { ShelfEarFigure(count: model.shelf.count) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Session usage as a mini gradient ring plus the figure in SF Compressed.
struct UsageEarFigure: View {
    let usage: ProviderUsage

    var body: some View {
        let used = usage.session.used
        HStack(spacing: 5) {
            FluidoRing(value: used, light: .usage(used), lineWidth: 2.4, comet: false)
                .frame(width: 14, height: 14)
            Text("\(Int((used * 100).rounded()))")
                .font(Fluido.Typography.earFigure)
                .foregroundStyle(UsageLevel(fraction: used) == .normal ? Fluido.Palette.text : Fluido.Palette.warning)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(usage.agent.name): \(NotchFormat.percent(used)) de la sesión")
    }
}

/// How many things wait in the shelf: the tray in the shelf's light and the count in SF Compressed.
struct ShelfEarFigure: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Fluido.Light.shelf.linear(.top, .bottom))
            Text("\(count)")
                .font(Fluido.Typography.earFigure)
                .foregroundStyle(Fluido.Palette.text)
                .contentTransition(.numericText(value: Double(count)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(NotchFormat.things(count)) en el altillo")
    }
}

// MARK: - Peek

struct FluidoPeekFace: View {
    let model: NotchModel
    let chrome: FluidoChrome
    let kind: PeekKind

    var body: some View {
        if kind == .hint {
            FluidoHintFace(chrome: chrome)
        } else if chrome.hasNotch {
            VStack(spacing: 0) {
                FluidoEarBand(chrome: chrome, earWidth: 64) { leadingEar } trailing: { trailingEar }
                line
                    .frame(height: FluidoChrome.peekLineHeight - 8)
                    .padding(.horizontal, chrome.topRadius + 18)
                Spacer(minLength: 0)
            }
        } else {
            line
                .padding(.horizontal, chrome.topRadius + 16)
                .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var leadingEar: some View {
        switch kind {
        case .hint: EmptyView()
        case .shelf:
            Image(systemName: "tray.full.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Fluido.Light.shelf.linear(.top, .bottom))
        case .usageAlert, .agentWaiting:
            AgentGlyph(agent: kind == .usageAlert ? model.demo.primaryUsage.agent : (model.demo.waitingAgent?.agent ?? .claude), size: 16)
        }
    }

    @ViewBuilder
    private var trailingEar: some View {
        switch kind {
        case .hint: EmptyView()
        case .shelf:
            Text("\(model.shelf.count)")
                .font(Fluido.Typography.earFigure)
                .foregroundStyle(Fluido.Palette.text)
        case .usageAlert:
            let used = model.demo.primaryUsage.session.used
            FluidoRing(value: used, light: .usage(used), lineWidth: 2.4, comet: false)
                .frame(width: 15, height: 15)
        case .agentWaiting:
            LightDot(light: .agents, size: 7, breathes: true)
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

    private var shelfLine: some View {
        HStack(spacing: 9) {
            ThumbnailStack(items: Array(model.shelf.suffix(3)), side: 18)
            Text(NotchFormat.things(model.shelf.count))
                .font(Fluido.Typography.peekKey)
                .foregroundStyle(Fluido.Palette.text)
            if let last = model.shelf.map(\.addedAt).max() {
                Text("· la última \(NotchFormat.ago(last))")
                    .font(Fluido.Typography.peek)
                    .foregroundStyle(Fluido.Palette.textSecondary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }

    /// "Claude · 85 % · 1 h 11 min"
    private var usageLine: some View {
        let usage = model.demo.primaryUsage
        let level = UsageLevel(fraction: usage.session.used)
        return HStack(spacing: 7) {
            Text(usage.agent.name)
                .font(Fluido.Typography.peek)
                .foregroundStyle(Fluido.Palette.text)
            separator
            Text(NotchFormat.percent(usage.session.used))
                .font(Fluido.Typography.peekKey)
                .foregroundStyle(level == .normal ? Fluido.Palette.text : Fluido.Palette.warning)
            separator
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9.5, weight: .bold))
                Text(NotchFormat.countdown(to: usage.session.resetsAt))
                    .font(.system(size: 12.5, weight: .medium).width(.condensed).monospacedDigit())
            }
            .foregroundStyle(Fluido.Palette.textSecondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// "Claude te necesita · git push"
    @ViewBuilder
    private var agentLine: some View {
        if let agent = model.demo.waitingAgent {
            HStack(spacing: 8) {
                Text("\(agent.agent.name) te necesita")
                    .font(Fluido.Typography.peekKey)
                    .foregroundStyle(Fluido.Palette.text)
                separator
                if let request = agent.request {
                    Text(request.command.split(separator: " ").prefix(2).joined(separator: " "))
                        .font(Fluido.Typography.code)
                        .foregroundStyle(Fluido.Palette.text)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .fluidoGlass(Capsule(), light: .agents, tint: 0.55, interactive: false)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
        }
    }

    private var separator: some View {
        Circle().fill(Fluido.Palette.textTertiary).frame(width: 2.5, height: 2.5)
    }
}

/// Hovering with nothing to report: the notch grows a touch and shows what lives inside. No instructions.
struct FluidoHintFace: View {
    let chrome: FluidoChrome

    var body: some View {
        if chrome.hasNotch {
            FluidoEarBand(chrome: chrome) {
                glyph(.shelf)
            } trailing: {
                HStack(spacing: 10) { glyph(.usage); glyph(.agents) }
            }
        } else {
            HStack(spacing: 14) {
                ForEach(NotchTab.allCases) { glyph($0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func glyph(_ tab: NotchTab) -> some View {
        Image(systemName: tab.fluidoSymbol)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tab.fluidoLight.linear(.top, .bottom))
            .opacity(0.6)
            .accessibilityHidden(true)
    }
}

// MARK: - Drag armed

/// A drag is happening somewhere: the notch drips down a little, lit amber from below. "Suelta".
struct FluidoDragArmedFace: View {
    let chrome: FluidoChrome

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if chrome.hasNotch { Color.clear.frame(height: chrome.bandHeight) }
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .heavy))
                    .symbolEffect(.bounce.down.byLayer, options: .repeat(.periodic(delay: 1.2)), isActive: !reduceMotion)
                Text("Suelta")
                    .font(.system(size: 13, weight: .semibold).width(.expanded))
            }
            .foregroundStyle(Fluido.Light.shelf.linear(.leading, .trailing))
            .shadow(color: Fluido.Light.shelf.mid.opacity(0.6), radius: 8)
            .frame(maxHeight: .infinity)
            .padding(.bottom, chrome.hasNotch ? 3 : 0)
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            // Warm light pooling in the drop.
            Ellipse()
                .fill(Fluido.Light.shelf.linear(.leading, .trailing))
                .frame(width: chrome.size.width * 0.7, height: 34)
                .blur(radius: 18)
                .opacity(0.32)
                .offset(y: 24)
        }
    }
}

extension Fluido.Light {
    /// The ring's light for a usage figure: the AI light, warming up as it fills (the aurora shifts hue as it rises).
    static func usage(_ fraction: Double) -> Fluido.Light {
        switch UsageLevel(fraction: fraction) {
        case .normal: .ai
        case .warning: Fluido.Light(from: Fluido.Light.ai.from, to: Fluido.Palette.warning)
        case .critical: Fluido.Light(from: Fluido.Palette.warning, to: Fluido.Palette.critical)
        }
    }
}
