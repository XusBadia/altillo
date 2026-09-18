import AltilloCore
import AltilloDesign
import SwiftUI

// Faces that stay close to the notch: ears, hint, peek and drag-armed.

/// Left ear, notch body (kept clear), right ear.
private struct MatrizEarBand<Leading: View, Trailing: View>: View {
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

/// Figure for the ears: Doto 13 bold, lit.
private func earFigure(_ value: Int, color: Color = Matriz.Palette.phosphor) -> some View {
    FlipCounter(value: value, font: Matriz.Fonts.doto(14, weight: 800), color: color)
}

// MARK: - Ears

struct MatrizEars: View {
    let model: NotchModel
    let chrome: NotchChrome

    private var showsUsage: Bool { model.scenario == .idleWithEars }

    var body: some View {
        MatrizEarBand(chrome: chrome, earWidth: NotchChrome.earWidth) {
            if showsUsage { UsageEarM(usage: model.demo.primaryUsage) }
        } trailing: {
            if !model.shelf.isEmpty { ShelfEarM(count: model.shelf.count) }
        }
    }
}

/// Dial glyph + session figure. Amber past 80 %, critical past 95 %.
struct UsageEarM: View {
    let usage: ProviderUsage

    var body: some View {
        let used = usage.session.used
        HStack(spacing: 5) {
            DotGlyph(Glyph7.dial, pitch: 2, dot: 1.6, color: Matriz.Palette.phosphor2)
            earFigure(Int((used * 100).rounded()), color: Matriz.Palette.usage(used))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(usage.agent.name), \(Int((used * 100).rounded())) por ciento de la sesión")
    }
}

/// Box glyph + how many things wait upstairs. The count flips like a scoreboard when something lands.
struct ShelfEarM: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            DotGlyph(Glyph7.box, pitch: 2, dot: 1.6, color: Matriz.Palette.phosphor2)
            earFigure(count)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(NotchFormat.things(count)) en el altillo")
    }
}

/// An agent waits: a breathing red LED and the number of agents waiting.
struct WaitingEarM: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            BreathingLED(size: 6)
            earFigure(count)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) agente esperando")
    }
}

// MARK: - Hint

/// Hovering with nothing to report: the brand and the three modules, quietly. No instructions.
struct MatrizHint: View {
    let chrome: NotchChrome

    var body: some View {
        if chrome.hasNotch {
            MatrizEarBand(chrome: chrome, earWidth: NotchChrome.earWidth) {
                DotGlyph(Glyph7.roof, pitch: 2, dot: 1.6, color: Matriz.Palette.phosphor2)
            } trailing: {
                modules
            }
        } else {
            HStack(spacing: 12) {
                DotGlyph(Glyph7.roof, pitch: 2, dot: 1.6, color: Matriz.Palette.phosphor2)
                modules
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var modules: some View {
        HStack(spacing: 6) {
            DotGlyph(Glyph7.box, pitch: 1.5, dot: 1.2, color: Matriz.Palette.phosphor3)
            DotGlyph(Glyph7.dial, pitch: 1.5, dot: 1.2, color: Matriz.Palette.phosphor3)
            DotGlyph(Glyph7.agent, pitch: 1.5, dot: 1.2, color: Matriz.Palette.phosphor3)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Peek

/// A black sign that grows under the notch; its line lights up left to right like a station board.
struct MatrizPeek: View {
    let model: NotchModel
    let chrome: NotchChrome
    let kind: PeekKind

    var body: some View {
        if chrome.hasNotch {
            VStack(spacing: 0) {
                MatrizEarBand(chrome: chrome, earWidth: 72) { leadingEar } trailing: { trailingEar }
                line
                    .frame(height: NotchChrome.peekLineHeight - 6)
                    .padding(.horizontal, chrome.topRadius + 18)
                    .modifier(ScanReveal(horizontal: true, delay: 0.06))
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 10) {
                leadingEar
                line
            }
            .padding(.horizontal, chrome.topRadius + 14)
            .frame(maxHeight: .infinity)
            .modifier(ScanReveal(horizontal: true))
        }
    }

    // MARK: Ears

    @ViewBuilder
    private var leadingEar: some View {
        switch kind {
        case .hint:
            EmptyView()
        case .shelf:
            ShelfEarM(count: model.shelf.count)
        case .usageAlert:
            let usage = model.demo.primaryUsage
            HStack(spacing: 6) {
                DotRing(value: usage.session.used, pace: nil, segments: 16, dot: 2)
                    .frame(width: 17, height: 17)
                earFigure(Int((usage.session.used * 100).rounded()), color: Matriz.Palette.usage(usage.session.used))
            }
        case .agentWaiting:
            WaitingEarM(count: model.demo.agents.count { $0.phase.needsUser })
        }
    }

    @ViewBuilder
    private var trailingEar: some View {
        switch kind {
        case .hint:
            EmptyView()
        case .shelf:
            if let last = model.shelf.map(\.addedAt).max() { ago(last) }
        case .usageAlert:
            ago(model.demo.usageUpdatedAt)
        case .agentWaiting:
            if let agent = model.demo.waitingAgent { ago(agent.lastActivity) }
        }
    }

    private func ago(_ date: Date) -> some View {
        Text(NotchFormat.ago(date).uppercased())
            .matrizLabel()
            .foregroundStyle(Matriz.Palette.phosphor3)
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: Line

    @ViewBuilder
    private var line: some View {
        switch kind {
        case .hint: EmptyView()
        case .shelf: shelfLine
        case .usageAlert: usageLine
        case .agentWaiting: agentLine
        }
    }

    private func tag(_ text: String, color: Color = Matriz.Palette.phosphor2, glows: Bool = false) -> some View {
        Text(text).matrizLabel().foregroundStyle(color).ledGlow(2.5, opacity: 0.6, isOn: glows).fixedSize()
    }

    private var shelfLine: some View {
        HStack(spacing: 10) {
            tag("ALTILLO")
            Text("\(NotchFormat.things(model.shelf.count)) esperando a que las bajes")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Matriz.Palette.phosphor)
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                ForEach(model.shelf.suffix(4)) { item in
                    ShelfThumbnail(item: item, side: 18, compact: true)
                        .overlay(RoundedRectangle(cornerRadius: 4.5, style: .continuous).strokeBorder(Matriz.Palette.hairline, lineWidth: 1))
                }
            }
        }
        .lineLimit(1)
    }

    private var usageLine: some View {
        let usage = model.demo.primaryUsage
        let color = Matriz.Palette.usage(usage.session.used)
        let delta = usage.session.paceDelta()
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            tag(usage.agent.name.uppercased())
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int((usage.session.used * 100).rounded()))")
                    .font(Matriz.Fonts.doto(16, weight: 800))
                    .foregroundStyle(color)
                    .ledGlow(2, opacity: 0.5)
                Text("%").matrizLabel().foregroundStyle(color)
            }
            .fixedSize()
            Text("reinicia en \(NotchFormat.countdown(to: usage.session.resetsAt))")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Matriz.Palette.phosphor)
                .monospacedDigit()
            Spacer(minLength: 8)
            if delta > 0.05 {
                tag("↗ +\(Int((delta * 100).rounded())) PTS", color: Matriz.Palette.amber)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var agentLine: some View {
        if let agent = model.demo.waitingAgent {
            let command = agent.request.map { $0.command.split(separator: " ").prefix(2).joined(separator: " ") } ?? "algo"
            let code = Text(command).font(.system(size: 11.5, weight: .medium, design: .monospaced)).foregroundStyle(Matriz.Palette.phosphor)
            let project = Text(agent.project).foregroundStyle(Matriz.Palette.phosphor).fontWeight(.semibold)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                tag("ESPERA", color: Matriz.Palette.signal, glows: true)
                Text("\(agent.agent.name) quiere ejecutar \(code) en \(project)")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Matriz.Palette.phosphor2)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
        }
    }
}

// MARK: - Drag armed

/// A drag is in progress somewhere: under the notch, dot chevrons fall in cascade towards "SUELTA AQUÍ".
struct MatrizDragArmed: View {
    let chrome: NotchChrome

    var body: some View {
        VStack(spacing: 0) {
            if chrome.hasNotch { Color.clear.frame(height: chrome.bandHeight) }
            HStack(spacing: 10) {
                ChevronCascade()
                Text("SUELTA AQUÍ")
                    .matrizLabel()
                    .foregroundStyle(Matriz.Palette.signal)
                    .ledGlow(3, opacity: 0.7)
                    .fixedSize()
                ChevronCascade()
            }
            .frame(maxHeight: .infinity)
            .padding(.bottom, chrome.hasNotch ? 2 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Suelta aquí para guardarlo en el altillo")
    }
}

/// Three dot chevrons lighting one after another downwards, 90 ms per step.
private struct ChevronCascade: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.09)) { timeline in
            let step = reduceMotion ? 2 : Int(timeline.date.timeIntervalSinceReferenceDate / 0.09) % 6
            VStack(spacing: 1) {
                ForEach(0..<3) { index in
                    let distance = step - index
                    let level: Double = reduceMotion ? 0.8 : (distance == 0 ? 1 : distance == 1 ? 0.6 : 0.3)
                    DotGlyph(Glyph7.chevronDown, pitch: 2.4, dot: 2, color: Matriz.Palette.signal.opacity(level))
                        .ledGlow(2, opacity: 0.6, isOn: distance == 0)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
