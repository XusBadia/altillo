import AltilloDesign
import SwiftUI

// MARK: - Ring with a comet head

/// Usage ring: a gradient stroke that fills clockwise from 12 o'clock and ends in a **comet head** (a bright, blurred
/// point). The gradient spans only the filled arc, so the head is always the hottest colour.
struct FluidoRing<Label: View>: View {
    var value: Double
    var light: Fluido.Light
    var lineWidth: CGFloat = 6
    var comet = true
    /// Fraction of the window already elapsed, drawn as a tick on the track.
    var pace: Double?
    @ViewBuilder var label: Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(value, 0), 1) }

    var body: some View {
        let arc = max(clamped, 0.001)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: arc)
                .stroke(
                    AngularGradient(
                        stops: [.init(color: light.from, location: 0), .init(color: light.to, location: 1)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * arc)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if comet {
                cometHead(arc)
            }
            if let pace {
                GeometryReader { proxy in
                    let radius = min(proxy.size.width, proxy.size.height) / 2
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 1.5, height: lineWidth + 3)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(360 * min(max(pace, 0), 1)))
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
            label
        }
        .padding(lineWidth / 2)
        .animation(reduceMotion ? Fluido.Motion.reduced : .spring(duration: 0.6, bounce: 0.15), value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }

    private func cometHead(_ arc: Double) -> some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            ZStack {
                // Tail: the last stretch of the arc glowing.
                Circle()
                    .trim(from: max(0, arc - 0.12), to: arc)
                    .stroke(light.to, style: StrokeStyle(lineWidth: lineWidth * 1.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .blur(radius: lineWidth * 0.9)
                    .opacity(0.8)
                // Head.
                ZStack {
                    Circle().fill(light.to).frame(width: lineWidth * 2.6).blur(radius: lineWidth * 0.8)
                    Circle().fill(Color.white).frame(width: lineWidth * 0.62)
                        .shadow(color: .white, radius: 2)
                }
                .offset(y: -radius)
                .rotationEffect(.degrees(360 * arc))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .blendMode(.plusLighter)
        }
    }
}

extension FluidoRing where Label == EmptyView {
    init(value: Double, light: Fluido.Light, lineWidth: CGFloat = 6, comet: Bool = true, pace: Double? = nil) {
        self.init(value: value, light: light, lineWidth: lineWidth, comet: comet, pace: pace) { EmptyView() }
    }
}

// MARK: - Aurora

/// A 3×3 mesh of the module's light at 16 %, behind a ring. It drifts when the value changes (never on a loop), and
/// its hue shifts as the value rises.
struct Aurora: View {
    var value: Double
    var light: Fluido.Light

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let v = Float(min(max(value, 0), 1))
        let a = light.from, b = light.to, c = light.mid
        // The centre point wanders with the value; corners stay pinned so the mesh never folds.
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5 + 0.1 * v, 0], [1, 0],
            [0, 0.5 - 0.12 * v], [0.35 + 0.3 * v, 0.62 - 0.25 * v], [1, 0.4 + 0.2 * v],
            [0, 1], [0.6 - 0.2 * v, 1], [1, 1],
        ]
        MeshGradient(
            width: 3,
            height: 3,
            points: points,
            colors: [
                .clear, a.opacity(0.7), .clear,
                b.opacity(0.8), c, a.opacity(0.9),
                .clear, b.opacity(0.7), .clear,
            ]
        )
        .blur(radius: 18)
        .mask(RadialGradient(colors: [.white, .white.opacity(0.4), .clear], center: .center, startRadius: 4, endRadius: 80))
        .opacity(reduceTransparency ? 0 : 0.6)
        .animation(reduceMotion ? nil : .smooth(duration: 1.6), value: value)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Usage tab

struct FluidoUsageView: View {
    let demo: DemoContent

    var body: some View {
        HStack(spacing: 10) {
            ForEach(demo.usage) { usage in
                FluidoProviderCard(usage: usage)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct FluidoProviderCard: View {
    let usage: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                ring
                session
            }
            Spacer(minLength: 10)
            weekly
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .topLeading) {
            Aurora(value: usage.session.used, light: .usage(usage.session.used))
                .frame(width: 190, height: 170)
                .offset(x: -40, y: -34)
        }
        .clipShape(RoundedRectangle(cornerRadius: Fluido.Radius.card, style: .continuous))
        .inkWell()
    }

    private var ring: some View {
        let window = usage.session
        return FluidoRing(value: window.used, light: .usage(window.used), lineWidth: 7, pace: window.expectedPace()) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int((window.used * 100).rounded()))")
                    .font(Fluido.Typography.ringFigure)
                    .foregroundStyle(Fluido.Palette.text)
                Text("%")
                    .font(.system(size: 11, weight: .bold).width(.expanded))
                    .foregroundStyle(Fluido.Palette.textSecondary)
            }
        }
        .frame(width: 92, height: 92)
    }

    private var session: some View {
        let window = usage.session
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                AgentGlyph(agent: usage.agent, size: 16)
                Text(usage.agent.name)
                    .font(Fluido.Typography.title)
                    .foregroundStyle(Fluido.Palette.text)
                Text(usage.plan)
                    .font(Fluido.Typography.micro)
                    .foregroundStyle(Fluido.Palette.textSecondary)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .overlay(Capsule().strokeBorder(Fluido.Palette.hairlineStrong, lineWidth: 0.75))
            }
            .padding(.bottom, 10)
            Text("Sesión")
                .font(Fluido.Typography.micro)
                .foregroundStyle(Fluido.Palette.textTertiary)
                .padding(.bottom, 2)
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Fluido.Palette.textTertiary)
                Text(NotchFormat.countdown(to: window.resetsAt))
                    .font(.system(size: 15, weight: .semibold).width(.condensed).monospacedDigit())
                    .foregroundStyle(Fluido.Palette.text)
            }
            .padding(.bottom, 3)
            FluidoPace(delta: window.paceDelta())
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var weekly: some View {
        let window = usage.weekly
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Semana")
                    .font(Fluido.Typography.micro)
                    .foregroundStyle(Fluido.Palette.textTertiary)
                Spacer(minLength: 0)
                Text(NotchFormat.countdown(to: window.resetsAt))
                    .font(Fluido.Typography.countdown)
                    .foregroundStyle(Fluido.Palette.textTertiary)
                Text(NotchFormat.percent(window.used))
                    .font(Fluido.Typography.earFigure)
                    .foregroundStyle(Fluido.Palette.text)
            }
            FluidoBar(value: window.used, light: .usage(window.used), pace: window.expectedPace())
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// Thin gradient bar with a comet head and a pace tick.
struct FluidoBar: View {
    var value: Double
    var light: Fluido.Light
    var pace: Double?
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fill = max(height, width * min(max(value, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(light.linear(.leading, .trailing))
                    .frame(width: fill)
                // Comet head.
                Circle()
                    .fill(light.to)
                    .frame(width: height * 3, height: height * 3)
                    .blur(radius: height * 0.9)
                    .offset(x: fill - height * 2)
                    .blendMode(.plusLighter)
                Circle()
                    .fill(Color.white)
                    .frame(width: height * 0.7, height: height * 0.7)
                    .offset(x: fill - height * 0.85)
                if let pace {
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 1.5, height: height + 5)
                        .offset(x: width * min(max(pace, 0), 1) - 0.75)
                }
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}

/// How the burn compares with an even pace across the window.
struct FluidoPace: View {
    let delta: Double

    var body: some View {
        let points = Int((abs(delta) * 100).rounded())
        HStack(spacing: 3) {
            Image(systemName: delta > 0.05 ? "arrow.up.right" : (delta < -0.05 ? "arrow.down.right" : "equal"))
                .font(.system(size: 8.5, weight: .heavy))
            Text(text(points))
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium).width(.condensed))
        .foregroundStyle(delta > 0.05 ? Fluido.Palette.warning : Fluido.Palette.textSecondary)
    }

    private func text(_ points: Int) -> String {
        if delta > 0.05 { return "\(points) pts sobre el ritmo" }
        if delta < -0.05 { return "\(points) pts de margen" }
        return "Al ritmo"
    }
}
