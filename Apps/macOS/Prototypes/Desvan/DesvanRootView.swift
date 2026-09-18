import AltilloCore
import AltilloDesign
import AppKit
import SwiftUI

/// Prototype of direction B, «Desván» (docs/design/direcciones.md): the attic at home, lit by a warm bulb.
///
/// Same contract as `NotchRootView`: the pure black silhouette is drawn top-centred in the fixed 760×320 panel,
/// morphs between faces (each laid out at its final size and clipped by the shape) and reports its drawn size to
/// `model.visibleShapeSize` for hit-testing. The personality lives inside: the bulb's light, wood, paper and kraft.
struct DesvanRootView: View {
    let model: NotchModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = MotionMemory()
    /// Extra light for 120 ms when something is saved (the bulb flickers).
    @State private var flicker = 0.0

    var body: some View {
        let chrome = Desvan.chrome(for: model)
        let shape = NotchShape(topCornerRadius: chrome.topRadius, bottomCornerRadius: chrome.bottomRadius)

        ZStack(alignment: .top) {
            // Shadow on its own layer so the clipped content can't cut it.
            shape
                .fill(Desvan.Palette.notch)
                .shadow(color: .black.opacity(chrome.showsShadow ? 0.55 : 0), radius: 18, y: 10)
                .shadow(color: .black.opacity(chrome.showsShadow ? 0.25 : 0), radius: 3, y: 1)

            ZStack(alignment: .top) {
                DesvanFaceView(model: model, chrome: chrome, flicker: flicker)
                    .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
                    .id(chrome.face)
                    .transition(.contentSwap(shift: max(4, chrome.size.height * 0.02), reduceMotion: reduceMotion))
            }
            .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(width: chrome.size.width, height: chrome.size.height)
        .contentShape(shape)
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            model.visibleShapeSize = size
            motion.lastArea = size.width * size.height
        }
        .transaction { transaction in
            // Desván's own springs: opening settles with a little weight, closing never bounces.
            // With Reduce Motion the shape still changes size, but as a short fade-like ease.
            guard transaction.animation != nil else { return }
            if reduceMotion {
                transaction.animation = Desvan.Motion.fade
            } else {
                let grows = chrome.size.width * chrome.size.height >= motion.lastArea
                transaction.animation = grows ? Desvan.Motion.open : Desvan.Motion.close
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .environment(\.altilloAccent, Desvan.Palette.bulb)
        .tint(Desvan.Palette.bulb)
        .task(id: model.scenario) { applyScenarioDemoState() }
        .onChange(of: model.shelf.count) { old, new in
            guard new > old else { return }
            Task { await flickerBulb() }
        }
    }

    /// The bulb flickers once (+4 %, 120 ms) when something is saved.
    private func flickerBulb() async {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.04)) { flicker = 0.04 }
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.easeIn(duration: 0.25)) { flicker = 0 }
    }

    /// A pre-selected tile so the review screenshot shows the selection style.
    private func applyScenarioDemoState() {
        guard model.scenario == .openShelf, model.selection.isEmpty, model.shelf.count > 1 else { return }
        model.selection = [model.shelf[1].id]
    }

    /// Remembers the last drawn area to pick the opening or closing spring (not observed: no re-render).
    private final class MotionMemory {
        var lastArea: CGFloat = 0
    }
}

/// Picks the content for a face and lays the bulb's light over it.
private struct DesvanFaceView: View {
    let model: NotchModel
    let chrome: NotchChrome
    let flicker: Double

    var body: some View {
        switch chrome.face {
        case .rest:
            Color.clear
        case .ears:
            DesvanEarsFace(model: model, chrome: chrome)
        case let .peek(kind):
            DesvanPeekFace(model: model, chrome: chrome, kind: kind)
                .background {
                    if kind != .hint {
                        // Very faint light from under the notch.
                        DesvanBulbGlow(intensity: 0.12 + flicker, radius: 150, originY: chrome.hasNotch ? chrome.bandHeight - 6 : 0)
                    }
                }
        case .dragArmed:
            DesvanDragArmedFace(model: model, chrome: chrome)
        case .expanded:
            DesvanExpandedFace(model: model, chrome: chrome, flicker: flicker)
        }
    }
}

// MARK: - Ears

private struct DesvanEarsFace: View {
    let model: NotchModel
    let chrome: NotchChrome

    var body: some View {
        EarBand(chrome: chrome, earWidth: NotchChrome.earWidth) {
            if model.scenario == .idleWithEars {
                DesvanUsageEar(usage: model.demo.primaryUsage)
            }
        } trailing: {
            if model.demo.waitingAgent != nil, model.scenario == nil {
                DesvanKnockingHand(size: 11)
            } else if !model.shelf.isEmpty {
                DesvanShelfCountTag(count: model.shelf.count)
            }
        }
    }
}

/// Left ear: a tiny ring and the session figure in New York.
struct DesvanUsageEar: View {
    let usage: ProviderUsage

    var body: some View {
        let used = usage.session.used
        HStack(spacing: 5) {
            DesvanRing(value: used, lineWidth: 2.2)
                .frame(width: 12, height: 12)
            Text("\(Int((used * 100).rounded()))")
                .font(Desvan.Typeface.figure(13, weight: .medium))
                .foregroundStyle(Desvan.Palette.paper)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(usage.agent.name): \(NotchFormat.percent(used)) de la sesión")
    }
}

/// Right ear: a tiny kraft tag with how many things wait upstairs.
struct DesvanShelfCountTag: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(Desvan.Typeface.figure(11.5, weight: .semibold))
            .foregroundStyle(Desvan.Palette.ink)
            .contentTransition(.numericText(value: Double(count)))
            .padding(.leading, 9)
            .padding(.trailing, 5)
            .frame(height: 14)
            .background {
                DesvanSideTagShape(peak: 5, radius: 2)
                    .fill(Desvan.Palette.kraft)
                    .overlay(alignment: .leading) {
                        Circle().fill(.black.opacity(0.9)).frame(width: 2.5, height: 2.5).padding(.leading, 3.5)
                    }
            }
            .rotationEffect(.degrees(-4))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(NotchFormat.things(count)) en el altillo")
    }
}

/// Usage ring with rounded ends. Paper while calm; mustard from 80 % (with a 400 ms fade), tomato from 95 %.
struct DesvanRing<Label: View>: View {
    var value: Double
    var lineWidth: CGFloat
    var pace: Double?
    @ViewBuilder var label: Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clamped = min(max(value, 0), 1)
        let tint = Desvan.usageTint(clamped)
        ZStack {
            Circle().stroke(Desvan.Palette.paper.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(clamped, 0.001))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(UsageLevel(fraction: clamped) == .normal ? 0 : 0.35), radius: lineWidth)
                .animation(.easeInOut(duration: 0.4), value: UsageLevel(fraction: clamped))
            if let pace {
                GeometryReader { proxy in
                    let radius = min(proxy.size.width, proxy.size.height) / 2
                    Capsule()
                        .fill(Desvan.Palette.paper)
                        .frame(width: 1.5, height: lineWidth + 3)
                        .shadow(color: .black.opacity(0.8), radius: 0.75)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(360 * min(max(pace, 0), 1)))
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
            label
        }
        .padding(lineWidth / 2)
        .animation(Desvan.Motion.pick(Desvan.Motion.settle, reduceMotion: reduceMotion), value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }
}

extension DesvanRing where Label == EmptyView {
    init(value: Double, lineWidth: CGFloat, pace: Double? = nil) {
        self.init(value: value, lineWidth: lineWidth, pace: pace) { EmptyView() }
    }
}

/// "Toc, toc": a hand that knocks twice every 3 s. Still with Reduce Motion.
struct DesvanKnockingHand: View {
    var size: CGFloat = 11
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let hand = Image(systemName: "hand.raised.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Desvan.Palette.bulb)
            .shadow(color: Desvan.Palette.bulb.opacity(0.6), radius: 4)
        if reduceMotion {
            hand
        } else {
            hand.keyframeAnimator(initialValue: 0.0, repeating: true) { content, angle in
                content.rotationEffect(.degrees(angle), anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0, duration: 2.3)
                    CubicKeyframe(-12, duration: 0.09)
                    CubicKeyframe(4, duration: 0.1)
                    CubicKeyframe(-12, duration: 0.09)
                    CubicKeyframe(0, duration: 0.42)
                }
            }
        }
    }
}

// MARK: - Peek

private struct DesvanPeekFace: View {
    let model: NotchModel
    let chrome: NotchChrome
    let kind: PeekKind

    var body: some View {
        if kind == .hint {
            DesvanHintFace(chrome: chrome)
        } else if chrome.hasNotch {
            VStack(spacing: 0) {
                EarBand(chrome: chrome, earWidth: NotchChrome.peekEarWidth) { leadingEar } trailing: { trailingEar }
                line
                    .frame(height: NotchChrome.peekLineHeight - 6)
                    .padding(.horizontal, chrome.topRadius + 16)
                Spacer(minLength: 0)
            }
        } else {
            // The island has no camera to dodge: one centred row.
            HStack(spacing: 9) {
                leadingEar
                line
            }
            .padding(.horizontal, chrome.topRadius + 14)
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var leadingEar: some View {
        switch kind {
        case .hint: EmptyView()
        case .shelf: DesvanHouseMark(size: 13)
        case .usageAlert: AgentGlyph(agent: model.demo.primaryUsage.agent, size: 15)
        case .agentWaiting: DesvanKnockingHand(size: 12)
        }
    }

    @ViewBuilder
    private var trailingEar: some View {
        switch kind {
        case .hint: EmptyView()
        case .shelf:
            if !model.shelf.isEmpty { DesvanShelfCountTag(count: model.shelf.count) }
        case .usageAlert:
            // The alert itself: burning faster than the window allows.
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                Text("rápido").font(Desvan.Typeface.rounded(11.5, weight: .semibold))
            }
            .foregroundStyle(Desvan.Palette.warning)
        case .agentWaiting:
            if let agent = model.demo.waitingAgent { AgentGlyph(agent: agent.agent, size: 15) }
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

    private static let sentence = Font.system(size: 12.5, weight: .regular)
    private static let datum = Desvan.Typeface.figure(13.5, weight: .medium)

    @ViewBuilder
    private var shelfLine: some View {
        if model.shelf.isEmpty {
            Text("El altillo está vacío")
                .font(Self.sentence)
                .foregroundStyle(Desvan.Palette.paperSecondary)
        } else {
            HStack(spacing: 9) {
                ThumbnailStack(items: Array(model.shelf.suffix(3)))
                Text("\(Text(NotchFormat.things(model.shelf.count)).font(Self.datum.italic())) esperando arriba")
                    .font(Self.sentence)
                    .foregroundStyle(Desvan.Palette.paper)
                Spacer(minLength: 8)
                if let last = model.shelf.map(\.addedAt).max() {
                    Text("la última, \(NotchFormat.ago(last))")
                        .font(Desvan.Typeface.rounded(11, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var usageLine: some View {
        let usage = model.demo.primaryUsage
        let used = usage.session.used
        let figure = Text(NotchFormat.percent(used))
            .font(Self.datum.italic())
            .foregroundStyle(Desvan.usageTint(used))
        return HStack(spacing: 0) {
            Text("\(usage.agent.name) va por el \(figure) de la sesión")
                .font(Self.sentence)
                .foregroundStyle(Desvan.Palette.paper)
            Spacer(minLength: 10)
            Text("se repone en \(NotchFormat.countdown(to: usage.session.resetsAt))")
                .font(Desvan.Typeface.rounded(11, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .monospacedDigit()
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var agentLine: some View {
        if let agent = model.demo.waitingAgent {
            HStack(spacing: 5) {
                Text("Toc, toc:")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.bulb)
                Text("\(agent.agent.name) quiere hacer")
                    .font(Self.sentence)
                    .foregroundStyle(Desvan.Palette.paper)
                if let request = agent.request {
                    Text(request.command.split(separator: " ").prefix(2).joined(separator: " "))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Desvan.Palette.paper)
                        .padding(.horizontal, 6)
                        .frame(height: 19)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Desvan.Palette.woodRaised))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.5))
                }
                Text("en \(Text(agent.project).font(Self.datum.italic()))")
                    .font(Self.sentence)
                    .foregroundStyle(Desvan.Palette.paper)
                Spacer(minLength: 8)
                Text(NotchFormat.ago(agent.lastActivity))
                    .font(Desvan.Typeface.rounded(11, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .monospacedDigit()
            }
            .lineLimit(1)
        }
    }
}

/// Hovering with nothing to report: the house with its window lit and the logotype. No instructions.
private struct DesvanHintFace: View {
    let chrome: NotchChrome

    var body: some View {
        if chrome.hasNotch {
            EarBand(chrome: chrome, earWidth: NotchChrome.earWidth) {
                DesvanHouseMark(size: 13)
            } trailing: {
                wordmark
            }
        } else {
            HStack(spacing: 7) {
                DesvanHouseMark(size: 13)
                wordmark
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var wordmark: some View {
        Text("altillo")
            .font(Desvan.Typeface.fraunces(13.5, weight: 600))
            .foregroundStyle(Desvan.Palette.paper.opacity(0.9))
            .fixedSize()
            .accessibilityLabel("Altillo")
    }
}

// MARK: - Drag armed

/// A drag is in progress: the bulb lights up as the pointer comes closer, and a warm "Súbelo ↑".
private struct DesvanDragArmedFace: View {
    let model: NotchModel
    let chrome: NotchChrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: model.scenario != nil)) { _ in
            let near = proximity
            content(near: near)
        }
    }

    private func content(near: Double) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: chrome.hasNotch ? chrome.bandHeight : 0)
            HStack(alignment: .top, spacing: 8) {
                // The bulb hangs from the notch on a short cord.
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Desvan.Palette.paper.opacity(0.35))
                        .frame(width: 1, height: chrome.hasNotch ? 5 : 3)
                    DesvanBulbGlyph(size: 17, lit: 0.3 + 0.7 * near)
                }
                HStack(spacing: 3) {
                    Text("Súbelo")
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10.5, weight: .bold))
                        .symbolEffect(.bounce.up.byLayer, options: .repeat(.periodic(delay: 1.4)), isActive: !reduceMotion)
                }
                .font(Desvan.Typeface.rounded(13, weight: .semibold))
                .foregroundStyle(Desvan.Palette.bulb)
                .padding(.top, chrome.hasNotch ? 8 : 6)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background {
            DesvanBulbGlow(
                // On bare black the bulb needs a little more to read as light than it does on wood.
                intensity: 0.08 + 0.16 * near,
                radius: 80 + 50 * near,
                originY: chrome.hasNotch ? chrome.bandHeight : 0
            )
        }
    }

    /// 0 far … 1 at the notch. Frozen at a telling value in design scenarios.
    private var proximity: Double {
        if model.scenario != nil { return 0.75 }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return 0 }
        let top = CGPoint(x: screen.frame.midX, y: screen.frame.maxY)
        let distance = hypot(mouse.x - top.x, mouse.y - top.y)
        return min(max(1 - (distance - 40) / 460, 0), 1)
    }
}
