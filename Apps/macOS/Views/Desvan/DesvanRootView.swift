import AltilloCore
import AltilloDesign
import AppKit
import SwiftUI

/// Prototype of direction B, «Desván» (docs/design/direcciones.md): the attic at home, lit by a warm bulb.
///
/// Same contract as `NotchRootView`: the pure black silhouette is drawn top-centred in the fixed panel
/// (`NotchLayout.panelSize`), morphs between faces (each laid out at its final size and clipped by the shape) and reports its drawn size to
/// `model.visibleShapeSize` for hit-testing. The personality lives inside: the bulb's light, wood, paper and kraft.
struct DesvanRootView: View {
    let model: NotchModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = MotionMemory()
    /// Extra light for 120 ms when something is saved (the bulb flickers).
    @State private var flicker = 0.0

    var body: some View {
        let chrome = Desvan.chrome(for: model)
        let from = motion.advance(to: chrome)
        let shape = NotchShape(topCornerRadius: chrome.topRadius, bottomCornerRadius: chrome.bottomRadius)

        ZStack(alignment: .top) {
            // Shadow on its own layer so the clipped content can't cut it.
            shape
                .fill(Desvan.Palette.notch)
                .shadow(color: .black.opacity(chrome.showsShadow ? 0.55 : 0), radius: 18, y: 10)
                .shadow(color: .black.opacity(chrome.showsShadow ? 0.25 : 0), radius: 3, y: 1)

            // Each face is laid out at its final size, pinned to the top centre, and the growing (or shrinking)
            // silhouette clips it: the shape reveals the face instead of squeezing it.
            Color.clear
                .overlay(alignment: .top) {
                    ZStack(alignment: .top) {
                        DesvanFaceView(model: model, chrome: chrome, flicker: flicker)
                            .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
                            .id(chrome.face)
                            .transition(Desvan.Motion.face(chrome.face, reduceMotion: reduceMotion))
                    }
                }
                .clipShape(shape)
        }
        // The silhouette's size is animated here, one axis at a time, so each picks its own spring (the grown one
        // overshoots, the shrunk one never does) and a peek can grow sideways before it drops. The size is
        // interpolated frame by frame, so the shadow, the clip and the pinned face always agree mid-flight.
        .modifier(SilhouetteLength(axis: .vertical, length: chrome.size.height))
        .transaction(value: chrome.size.height) { transaction in
            animate(&transaction, axis: .vertical, from: from, to: chrome)
        }
        .modifier(SilhouetteLength(axis: .horizontal, length: chrome.size.width))
        .transaction(value: chrome.size.width) { transaction in
            animate(&transaction, axis: .horizontal, from: from, to: chrome)
        }
        .contentShape(shape)
        .onChange(of: chrome.size, initial: true) { _, size in
            // Hit-testing follows the shape the notch is heading for.
            model.visibleShapeSize = size
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .environment(\.altilloAccent, Desvan.Palette.bulb)
        .tint(Desvan.Palette.bulb)
        .task {
            // Wood, kraft and cardboard are generated once, off the main thread, before the notch first opens.
            await Task.detached(priority: .utility) { DesvanTexture.prewarm() }.value
        }
        .task(id: model.scenario) {
            applyScenarioDemoState()
            await DesvanDebug.clock.run(for: model.scenario)
        }
        .task {
            // `-customizeOnLaunch YES` opens the notch in edit mode once, to review it without a right-click.
            guard DesvanEdit.customizeOnLaunch, !DesvanEdit.didCustomizeOnLaunch else { return }
            DesvanEdit.didCustomizeOnLaunch = true
            try? await Task.sleep(for: .milliseconds(1200))
            // Rebuilt before it fired (the screens settling at launch): let the next root view do it.
            guard !Task.isCancelled else { DesvanEdit.didCustomizeOnLaunch = false; return }
            model.actions.beginEditing()
        }
        .onChange(of: model.shelf.count) { old, new in
            guard new > old else { return }
            Task { await flickerBulb() }
        }
        .onChange(of: DesvanDebug.clock.tick) {
            if DesvanDebug.demoMotion == .landing { Task { await flickerBulb() } }
        }
    }

    /// Desván's own springs for the silhouette, replacing whatever animation the state change came with. Only the
    /// transaction that resizes an axis is touched: hovers and presses inside keep their own quick animations.
    private func animate(_ transaction: inout Transaction, axis: Axis, from: NotchChrome, to: NotchChrome) {
        guard transaction.animation != nil else { return }
        let length = { (chrome: NotchChrome) in axis == .horizontal ? chrome.size.width : chrome.size.height }
        let panel = axis == .horizontal ? NotchLayout.panelSize.width : NotchLayout.panelSize.height - 30
        transaction.animation = Desvan.Motion.silhouette(
            axis,
            from: (from.face, length(from)),
            to: (to.face, length(to)),
            limit: panel,
            reduceMotion: reduceMotion
        )
    }

    /// The bulb flickers when something is saved: as the thing hits the plank, the light jumps (+4 %), dips and
    /// catches again, then settles (≈ 120 ms of flicker, like a filament shaken on its wires).
    private func flickerBulb() async {
        guard !reduceMotion else { return }
        try? await Task.sleep(for: .milliseconds(230)) // the thing lands
        withAnimation(.linear(duration: 0.015)) { flicker = 0.05 }
        try? await Task.sleep(for: .milliseconds(50))
        withAnimation(.linear(duration: 0.015)) { flicker = -0.03 }
        try? await Task.sleep(for: .milliseconds(35))
        withAnimation(.linear(duration: 0.015)) { flicker = 0.04 }
        try? await Task.sleep(for: .milliseconds(50))
        withAnimation(.easeIn(duration: 0.3)) { flicker = 0 }
    }

    /// A pre-selected tile so the review screenshot shows the selection style, and `-demoShelfCount` fills the
    /// shelf with copies of the samples to review how the row scrolls.
    private func applyScenarioDemoState() {
        guard model.scenario != nil else { return }
        if let wanted = DesvanDebug.demoShelfCount, !model.shelf.isEmpty, model.shelf.count < wanted {
            let samples = model.shelf
            var filled = samples
            while filled.count < wanted {
                let sample = samples[filled.count % samples.count]
                filled.append(ShelfItem(
                    kind: sample.kind,
                    displayName: sample.displayName,
                    addedAt: sample.addedAt.addingTimeInterval(-Double(filled.count) * 60)
                ))
            }
            model.shelf = filled
        }
        guard model.scenario == .openShelf, model.selection.isEmpty, model.shelf.count > 1 else { return }
        model.selection = [model.shelf[1].id]
    }

    /// Remembers the chrome the silhouette is coming from, to pick each axis's spring (not observed: no re-render).
    private final class MotionMemory {
        private var previous: NotchChrome?
        private var current: NotchChrome?

        /// Records `chrome` as the one being drawn and returns the one drawn before it. Evaluating the same chrome
        /// again (the body runs for other reasons too) keeps returning the same predecessor.
        func advance(to chrome: NotchChrome) -> NotchChrome {
            if chrome != current {
                previous = current
                current = chrome
            }
            return previous ?? chrome
        }
    }
}

/// Animates one side of the silhouette's frame. The length itself is interpolated (not the laid-out result), so the
/// shape, its shadow, its clip and the face pinned inside are re-laid out together on every frame of the spring.
/// Nothing runs at rest.
private struct SilhouetteLength: ViewModifier, Animatable {
    let axis: Axis
    var length: CGFloat

    nonisolated var animatableData: CGFloat {
        get { length }
        set { length = newValue }
    }

    func body(content: Content) -> some View {
        switch axis {
        case .horizontal: content.frame(width: max(0, length))
        case .vertical: content.frame(height: max(0, length))
        }
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

/// The resting notch with ears: whatever the user put in each one (Settings › Sections or edit mode). While ears
/// only show with activity, a quiet one stays empty; when they always show, a quiet one keeps its glyph, unlit.
private struct DesvanEarsFace: View {
    let model: NotchModel
    let chrome: NotchChrome

    var body: some View {
        EarBand(chrome: chrome, earWidth: NotchChrome.earWidth) {
            if model.scenario == .idleWithEars {
                DesvanUsageEar(usage: model.demo.primaryUsage)
            } else if model.scenario?.isAgentWaitingEars == true {
                // What the contextual ear shows for a knocking agent (`DesvanContextualEar`).
                DesvanKnockingHand(size: 13)
            } else if model.scenario == nil, model.ears.contextualFallbackSide(for: model) == .left {
                DesvanContextualEar(model: model, style: restingStyle)
            } else if model.scenario == nil {
                DesvanEarContent(content: model.settings.leftEar, model: model, style: restingStyle)
            }
        } trailing: {
            if model.scenario?.isAgentWaitingEars == true {
                DesvanAgentsEar(counts: AgentsLogic.counts(model.demo.agents))
            } else if model.scenario != nil {
                // Design review: the shelf's sample count.
                if !model.shelf.isEmpty { DesvanShelfCount(count: model.shelf.count) }
            } else if model.ears.contextualFallbackSide(for: model) == .right {
                DesvanContextualEar(model: model, style: restingStyle)
            } else {
                DesvanEarContent(content: model.settings.rightEar, model: model, style: restingStyle)
            }
        }
    }

    private var restingStyle: DesvanEarContent.Style {
        model.settings.earsVisibility == .always ? .resting : .live
    }
}

/// What one ear shows. `.live` renders only what has something to say; `.resting` (ears always visible) keeps a
/// dim stand-in for a quiet ear; `.preview` (edit mode's slots) also draws the ears that aren't available yet.
struct DesvanEarContent: View {
    enum Style { case live, resting, preview }

    let content: EarContent
    let model: NotchModel
    var style: Style = .live

    var body: some View {
        let ears = model.ears
        let active = ears.hasActivity(content, in: model)
        Group {
            switch content {
            case .none:
                EmptyView()
            case .automatic:
                DesvanContextualEar(model: model, style: style)
            case .shelf:
                if active {
                    DesvanShelfCount(count: model.shelf.count)
                } else if style != .live {
                    // Nobody home: the house with its light off.
                    DesvanHouseMark(size: 13, lit: 0, outline: Desvan.Palette.paperTertiary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("The shelf is empty")
                }
            case .nextEvent:
                if let label = ears.nextEventLabel {
                    DesvanNextEventEar(label: label, title: ears.nextEvent?.title ?? "")
                } else if style != .live {
                    DesvanEarGlyph(symbol: "calendar")
                        .accessibilityLabel("No more events today")
                }
            case .nowPlaying:
                if active || style != .live {
                    DesvanEqualiser(isPlaying: active)
                        .opacity(active ? 1 : 0.4)
                }
            case .usage:
                if style != .preview, let usage = model.usage.primary {
                    DesvanUsageEar(usage: usage)
                } else if style != .live {
                    DesvanEarGlyph(symbol: content.symbol)
                        .accessibilityLabel("No AI usage yet")
                }
            case .agents:
                if active, style != .preview {
                    DesvanAgentsEar(counts: AgentsLogic.counts(model.agentHub.sessions))
                } else if style != .live {
                    DesvanEarGlyph(symbol: content.symbol)
                        .accessibilityLabel("No agents working")
                }
            }
        }
        .transition(.opacity)
        .help(helpText)
    }

    private var helpText: String {
        switch content {
        case .none: String(localized: "This side is empty")
        case .automatic: NotchActivityLogic.accessibilityLabel(for: model.contextualActivity, now: .now)
        case .shelf: model.shelf.isEmpty
            ? String(localized: "The shelf is empty")
            : String(localized: "\(model.shelf.count) items on the shelf")
        case .nextEvent: model.ears.nextEvent?.title ?? String(localized: "No more timed events today")
        case .nowPlaying: model.nowPlaying.track?.title ?? String(localized: "Nothing is playing")
        case .usage: String(localized: "AI usage")
        case .agents: String(localized: "Active agents and requests")
        }
    }
}

/// A quiet ear's stand-in: its glyph, unlit.
struct DesvanEarGlyph: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Desvan.Palette.paperTertiary)
    }
}

/// The next event: a calendar glyph and its time ("10:30"), or a countdown under the hour ("in 12 min").
/// `EarsStore` wakes up exactly when the text changes; nothing ticks in between.
struct DesvanNextEventEar: View {
    let label: EarsLogic.EventLabel
    let title: String

    var body: some View {
        // Under the hour it lights up: time to get ready.
        let soon: Bool = if case .at = label { false } else { true }
        ViewThatFits(in: .horizontal) {
            row(EarsLogic.text(for: label), glyph: true)
            row(EarsLogic.compactText(for: label), glyph: true)
            row(EarsLogic.compactText(for: label), glyph: false)
        }
        .foregroundStyle(soon ? Desvan.Palette.bulb : Desvan.Palette.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func row(_ text: String, glyph: Bool) -> some View {
        HStack(spacing: 3) {
            if glyph {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
            }
            Text(verbatim: text)
                .font(Desvan.Typeface.figure(12, weight: .medium))
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var accessibilityText: String {
        let name = title.isEmpty ? String(localized: "Next event") : title
        switch label {
        case let .at(date): return String(localized: "\(name) at \(date.formatted(date: .omitted, time: .shortened))")
        case let .countdown(minutes): return String(localized: "\(name) in \(minutes) minutes")
        case .now: return String(localized: "\(name) is starting now")
        }
    }
}

/// Four little bars dancing while music plays. Still (and low) when paused, and still with Reduce Motion.
struct DesvanEqualiser: View {
    var isPlaying: Bool
    var height: CGFloat = 13

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Each bar's resting height and its own rhythm, so they never march in step.
    private static let bars: [(rest: CGFloat, period: Double)] = [(0.45, 0.62), (0.9, 0.48), (0.6, 0.7), (0.75, 0.54)]

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.8) {
            ForEach(Self.bars.indices, id: \.self) { index in
                bar(index)
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPlaying ? "Music playing" : "Music paused")
    }

    @ViewBuilder
    private func bar(_ index: Int) -> some View {
        let spec = Self.bars[index]
        let capsule = Capsule().fill(Desvan.Palette.bulb)
        if isPlaying, !reduceMotion {
            capsule
                .frame(width: 2.4)
                .keyframeAnimator(initialValue: spec.rest, repeating: true) { content, level in
                    content.frame(height: max(2.4, height * level))
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(1, duration: spec.period * 0.5)
                        CubicKeyframe(0.25, duration: spec.period * 0.5)
                        CubicKeyframe(spec.rest, duration: spec.period * 0.4)
                    }
                }
        } else {
            // Paused: the bars stand at rest, a little lower, so it still reads as music.
            capsule.frame(width: 2.4, height: max(2.4, height * spec.rest * (isPlaying ? 1 : 0.7)))
        }
    }
}

/// The usage ear: a tiny ring and the figure of the provider's fullest limit (session or week), in SF Pro Rounded.
/// Paper while calm, mustard from 80 %, tomato from 95 %; dimmer when the numbers are stale.
struct DesvanUsageEar: View {
    let usage: ProviderUsage

    var body: some View {
        if let window = usage.headline {
            let used = window.used
            HStack(spacing: 5) {
                DesvanRing(value: used, lineWidth: 2.4)
                    .frame(width: 14, height: 14)
                Text("\(Int((min(max(used, 0), 1) * 100).rounded()))")
                    .font(Desvan.Typeface.figure(13, weight: .medium))
                    .foregroundStyle(Desvan.usageTint(used))
                    .contentTransition(.numericText(value: used))
            }
            .opacity(usage.isStale(limit: UsageStore.staleAfter) ? 0.55 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(usage.displayName): \(NotchFormat.percent(used)) of \(UsageText.phrase(for: window)) used"
            )
        }
    }
}

/// Right ear: the house with its light on and how many things wait upstairs, in SF Pro Rounded.
struct DesvanShelfCount: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            DesvanHouseMark(size: 13)
            Text("\(count)")
                .font(Desvan.Typeface.figure(13, weight: .medium))
                .foregroundStyle(Desvan.Palette.paper)
                .contentTransition(.numericText(value: Double(count)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(NotchFormat.things(count)) on the shelf")
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
                .animation(Desvan.Motion.pick(.easeInOut(duration: 0.4), reduceMotion: reduceMotion),
                           value: UsageLevel(fraction: clamped))
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

/// "Toc, toc": a hand that knocks twice, a few times in a row when it appears, then only now and then. Between
/// knocks nothing animates, so a session that waits for hours costs no frames. Still with Reduce Motion.
struct DesvanKnockingHand: View {
    var size: CGFloat = 11
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var knocks = 0

    var body: some View {
        let hand = Image(systemName: "hand.raised.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Desvan.Palette.bulb)
            .shadow(color: Desvan.Palette.bulb.opacity(0.6), radius: 4)
        if reduceMotion {
            hand
        } else {
            hand.keyframeAnimator(initialValue: Knock(), trigger: knocks) { content, knock in
                content
                    .rotationEffect(.degrees(knock.angle), anchor: .bottom)
                    .offset(x: knock.jolt)
            } keyframes: { _ in
                // Two taps: the hand swings at the door (±12°) and jolts forward a point on each tap, so it still
                // reads at 1×.
                KeyframeTrack(\.angle) {
                    CubicKeyframe(-12, duration: 0.09)
                    CubicKeyframe(4, duration: 0.1)
                    CubicKeyframe(-12, duration: 0.09)
                    CubicKeyframe(0, duration: 0.42)
                }
                KeyframeTrack(\.jolt) {
                    CubicKeyframe(-1, duration: 0.09)
                    CubicKeyframe(0.3, duration: 0.1)
                    CubicKeyframe(-1, duration: 0.09)
                    CubicKeyframe(0, duration: 0.42)
                }
            }
            .task { await PeriodicNudge.run { knocks += 1 } }
        }
    }

    private struct Knock {
        var angle = 0.0
        var jolt = 0.0
    }
}

/// The rhythm of a looping nudge that shouldn't loop forever: three beats 3 s apart when it appears, then one
/// every 30 s for as long as the view is on screen (the task is cancelled when it goes away).
enum PeriodicNudge {
    static let eager: [Duration] = [.milliseconds(400), .seconds(3), .seconds(3)]
    static let lazy: Duration = .seconds(30)

    @MainActor
    static func run(eager: [Duration] = eager, every lazy: Duration = lazy, _ beat: @MainActor () -> Void) async {
        for delay in eager {
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            beat()
        }
        while (try? await Task.sleep(for: lazy)) != nil {
            beat()
        }
    }
}

// MARK: - Peek

/// A peek arrives in two beats: the shape grows sideways out of the notch with the ears, then drops and its line
/// comes into focus under the notch. A newer alert replacing the current one crossfades its line and figure.
private struct DesvanPeekFace: View {
    let model: NotchModel
    let chrome: NotchChrome
    let kind: PeekKind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False for the first instant of the peek, until the silhouette has dropped far enough to show the line.
    @State private var lineInFocus = false

    var body: some View {
        if kind == .hint {
            DesvanHintFace(model: model, chrome: chrome)
        } else if chrome.hasNotch {
            VStack(spacing: 0) {
                EarBand(chrome: chrome, earWidth: NotchChrome.peekEarWidth) { leadingEar } trailing: { trailingEar }
                ZStack {
                    line
                        .id(model.alert?.id)
                        .transition(.contentSwap(shift: 3, reduceMotion: reduceMotion))
                }
                .frame(height: NotchChrome.peekLineHeight - 6)
                .padding(.horizontal, chrome.topRadius + 16)
                .modifier(DesvanLineArrival(inFocus: lineInFocus))
                Spacer(minLength: 0)
            }
            .onAppear(perform: bringLineIntoFocus)
        } else {
            // The island has no camera to dodge: one centred row.
            ZStack {
                HStack(spacing: 9) {
                    leadingEar
                    line
                }
                .padding(.horizontal, chrome.topRadius + 14)
                .id(model.alert?.id)
                .transition(.contentSwap(shift: 3, reduceMotion: reduceMotion))
            }
            .modifier(DesvanLineArrival(inFocus: lineInFocus))
            .frame(maxHeight: .infinity)
            .onAppear(perform: bringLineIntoFocus)
        }
    }

    private func bringLineIntoFocus() {
        withAnimation(Desvan.Motion.pick(Desvan.Motion.focusIn.delay(0.1), reduceMotion: reduceMotion)) {
            lineInFocus = true
        }
    }

    @ViewBuilder
    private var leadingEar: some View {
        switch kind {
        case .hint: EmptyView()
        case .shelf: DesvanHouseMark(size: 13)
        case .usageAlert: DesvanAlertSymbol(alert: Self.demoUsageAlert)
        case .agentWaiting: if let alert = Self.demoAgentAlert { DesvanAgentAlertSymbol(alert: alert) }
        case .alert:
            if let alert = model.alert {
                if alert.agent != nil {
                    DesvanAgentAlertSymbol(alert: alert)
                } else {
                    DesvanAlertSymbol(alert: alert)
                }
            }
        }
    }

    @ViewBuilder
    private var trailingEar: some View {
        switch kind {
        case .hint: EmptyView()
        case .shelf:
            if !model.shelf.isEmpty { DesvanShelfCount(count: model.shelf.count) }
        case .usageAlert:
            if let trailing = Self.demoUsageAlert.trailing { DesvanAlertFigure(text: trailing) }
        case .agentWaiting:
            if let context = Self.demoAgentAlert?.agent { DesvanAgentAlertFigure(context: context) }
        case .alert:
            ZStack {
                if let context = model.alert?.agent, model.alert?.trailing == nil {
                    DesvanAgentAlertFigure(context: context)
                        .id(model.alert?.id)
                        .transition(.contentSwap(shift: 3, reduceMotion: reduceMotion))
                } else if let trailing = model.alert?.trailing {
                    DesvanAlertFigure(text: trailing)
                        .id(model.alert?.id)
                        .transition(.contentSwap(shift: 3, reduceMotion: reduceMotion))
                }
            }
        }
    }

    @ViewBuilder
    private var line: some View {
        switch kind {
        case .hint: EmptyView()
        case .shelf: shelfLine
        case .usageAlert: DesvanAlertLine(alert: Self.demoUsageAlert, showsTrailing: !chrome.hasNotch)
        case .agentWaiting:
            if let alert = Self.demoAgentAlert { DesvanAgentAlertLine(alert: alert, showsAgent: !chrome.hasNotch) }
        case .alert:
            if let alert = model.alert {
                if alert.agent != nil {
                    DesvanAgentAlertLine(alert: alert, showsAgent: !chrome.hasNotch)
                } else {
                    DesvanAlertLine(alert: alert, showsTrailing: !chrome.hasNotch)
                }
            }
        }
    }

    private static let sentence = Font.system(size: 12.5, weight: .regular)
    private static let datum = Desvan.Typeface.figure(13.5, weight: .medium)

    @ViewBuilder
    private var shelfLine: some View {
        if model.shelf.isEmpty {
            Text("The shelf is empty")
                .font(Self.sentence)
                .foregroundStyle(Desvan.Palette.paperSecondary)
        } else {
            HStack(spacing: 9) {
                ThumbnailStack(items: Array(model.shelf.suffix(3)))
                Text("\(Text(NotchFormat.things(model.shelf.count)).font(Self.datum.italic())) waiting up there")
                    .font(Self.sentence)
                    .foregroundStyle(Desvan.Palette.paper)
                Spacer(minLength: 8)
                if let last = model.shelf.map(\.addedAt).max() {
                    Text("last one, \(NotchFormat.ago(last))")
                        .font(Desvan.Typeface.rounded(11, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                        .monospacedDigit()
                }
            }
        }
    }

    /// "Peek: usage alert" shows the very peek a real usage alert makes (`UsageAlertPresenter`), with sample numbers.
    private static let demoUsageAlert = DemoContent.sample.usageAlert

    /// "Peek: agent waiting" shows the very peek a real permission request makes (`AgentAlerts`), with sample data.
    private static let demoAgentAlert = DemoContent.sample.agentAlert
}

/// The peek's line sharpening in once the silhouette has dropped: out of focus and a touch high until then.
private struct DesvanLineArrival: ViewModifier {
    let inFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(inFocus ? 1 : 0)
        } else {
            content
                .opacity(inFocus ? 1 : 0)
                .blur(radius: inFocus ? 0 : 5)
                .offset(y: inFocus ? 0 : -3)
        }
    }
}

/// Hovering with nothing to report: the house with its window lit and the logotype. No instructions. The contextual
/// ear, when it has something, keeps its place on the left so it can still be clicked.
private struct DesvanHintFace: View {
    let model: NotchModel
    let chrome: NotchChrome

    var body: some View {
        if chrome.hasNotch {
            EarBand(chrome: chrome, earWidth: NotchChrome.earWidth) {
                leading
            } trailing: {
                wordmark
            }
        } else {
            HStack(spacing: 7) {
                leading
                wordmark
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var leading: some View {
        if model.settings.leftEar == .automatic, model.contextualActivity != .rest {
            DesvanContextualEar(model: model)
        } else {
            DesvanHouseMark(size: 13)
        }
    }

    private var wordmark: some View {
        Text(verbatim: "altillo")
            .font(Desvan.Typeface.display(13.5, weight: 600))
            .foregroundStyle(Desvan.Palette.paper.opacity(0.9))
            .fixedSize()
            .accessibilityLabel(Text(verbatim: "Altillo"))
    }
}

// MARK: - Drag armed

/// A drag is in progress: the bulb hanging under the notch lights up as the pointer comes closer
/// (`model.dragProximity`), and a warm "Put it up ↑".
private struct DesvanDragArmedFace: View {
    let model: NotchModel
    let chrome: NotchChrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let near = proximity
        Group {
            if chrome.hasNotch {
                VStack(spacing: 0) {
                    Color.clear.frame(height: chrome.bandHeight)
                    HStack(alignment: .top, spacing: 9) {
                        // The bulb hangs from the notch on a short cord.
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(LinearGradient(colors: [Desvan.Palette.paper.opacity(0.1), Desvan.Palette.paper.opacity(0.4)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: 1, height: 3)
                            DesvanBulbGlyph(size: 17, lit: 0.12 + 0.88 * near)
                        }
                        label(near: near)
                            .padding(.top, 8)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            } else {
                // The island: one centred row.
                HStack(spacing: 8) {
                    DesvanBulbGlyph(size: 15, lit: 0.12 + 0.88 * near)
                        .offset(y: 1)
                    label(near: near)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            // The bulb's light spills from under the notch: faint far away, warm and wide right at the notch.
            DesvanBulbGlow(
                intensity: 0.05 + 0.25 * near,
                radius: 70 + 70 * near,
                originY: chrome.hasNotch ? chrome.bandHeight + 10 : chrome.size.height / 2
            )
        }
        .animation(Desvan.Motion.pick(.easeOut(duration: 0.18), reduceMotion: reduceMotion), value: near)
    }

    private func label(near: Double) -> some View {
        HStack(spacing: 3) {
            Text("Put it up")
            Image(systemName: "arrow.up")
                .font(.system(size: 11.5, weight: .bold))
                .symbolEffect(.bounce.up.byLayer, options: .repeat(.periodic(delay: 1.4)), isActive: !reduceMotion)
        }
        .font(Desvan.Typeface.rounded(13, weight: .semibold))
        .foregroundStyle(Desvan.Palette.bulb.mix(with: Desvan.Palette.paper, by: 0.35 * (1 - near)))
        .shadow(color: Desvan.Palette.bulb.opacity(0.5 * near), radius: 6)
    }

    /// 0 far … 1 at the notch. Frozen at a telling value in design scenarios; `-demoMotion approach` sweeps it.
    private var proximity: Double {
        guard model.scenario != nil else { return model.dragProximity }
        if DesvanDebug.demoMotion == .approach { return DesvanDebug.clock.phase ? 1 : 0.05 }
        return 0.75
    }
}
