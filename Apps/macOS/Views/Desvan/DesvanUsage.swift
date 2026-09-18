import AltilloDesign
import SwiftUI

/// The usage tab: one wood card per provider. The session ring with its figure in New York, the pace in italics
/// ("vas 9 puntos por delante del ritmo") and the weekly bar with a notch where an even pace would be.
struct DesvanUsageView: View {
    let demo: DemoContent

    var body: some View {
        HStack(spacing: 10) {
            ForEach(demo.usage) { usage in
                DesvanUsageCard(usage: usage)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct DesvanUsageCard: View {
    let usage: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 10)
            session
                .padding(.bottom, 11)
            Rectangle()
                .fill(Desvan.Palette.hairline)
                .frame(height: 1)
                .padding(.bottom, 9)
            weekly
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .desvanCard()
    }

    private var header: some View {
        HStack(spacing: 8) {
            AgentGlyph(agent: usage.agent, size: 18)
            Text(usage.agent.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paper)
            Text(usage.plan)
                .font(Desvan.Typeface.rounded(10, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .padding(.horizontal, 7)
                .frame(height: 17)
                .background(Capsule().fill(Desvan.Palette.woodRaised))
                .overlay(Capsule().strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.5))
            Spacer(minLength: 0)
        }
    }

    private var session: some View {
        let window = usage.session
        let used = window.used
        return HStack(spacing: 14) {
            DesvanRing(value: used, lineWidth: 5, pace: window.expectedPace()) {
                HStack(alignment: .firstTextBaseline, spacing: 0.5) {
                    Text("\(Int((used * 100).rounded()))")
                        .font(Desvan.Typeface.figure(24, weight: .semibold))
                        .contentTransition(.numericText(value: used))
                    Text("%")
                        .font(Desvan.Typeface.figure(10, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                }
                .foregroundStyle(Desvan.Palette.paper)
                .offset(x: 1)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 3) {
                Text("Sesión de 5 h")
                    .font(Desvan.Typeface.rounded(10.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                Text("se repone en \(NotchFormat.countdown(to: window.resetsAt))")
                    .font(Desvan.Typeface.rounded(12, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paper)
                    .monospacedDigit()
                DesvanPace(delta: window.paceDelta())
                    .padding(.top, 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var weekly: some View {
        let window = usage.weekly
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Semana")
                    .font(Desvan.Typeface.rounded(10.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                Spacer()
                Text(NotchFormat.percent(window.used))
                    .font(Desvan.Typeface.figure(13, weight: .medium))
                    .foregroundStyle(Desvan.usageTint(window.used))
            }
            DesvanBar(value: window.used, pace: window.expectedPace())
            HStack {
                Text("se repone en \(NotchFormat.countdown(to: window.resetsAt))")
                    .font(Desvan.Typeface.rounded(11, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .monospacedDigit()
                Spacer()
                DesvanPace(delta: window.paceDelta(), compact: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The pace, in New York italic: "vas 9 puntos por delante del ritmo" / "vas con 12 de margen" / "vas a buen ritmo".
private struct DesvanPace: View {
    let delta: Double
    var compact = false

    var body: some View {
        let points = Int((abs(delta) * 100).rounded())
        Text(compact ? shortText(points) : longText(points))
            .font(.system(size: compact ? 11.5 : 12, weight: .regular, design: .serif).italic())
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var color: Color {
        if delta > 0.05 { return Desvan.Palette.warning }
        if delta < -0.05 { return Desvan.Palette.done }
        return Desvan.Palette.paperSecondary
    }

    private func longText(_ points: Int) -> String {
        if delta > 0.05 { return "vas \(points) puntos por delante del ritmo" }
        if delta < -0.05 { return "vas con \(points) puntos de margen" }
        return "vas a buen ritmo"
    }

    private func shortText(_ points: Int) -> String {
        if delta > 0.05 { return "\(points) por delante" }
        if delta < -0.05 { return "con margen" }
        return "a buen ritmo"
    }
}

/// Weekly bar on a plank-coloured track, with a small notch above it marking an even pace.
private struct DesvanBar: View {
    let value: Double
    let pace: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clamped = min(max(value, 0), 1)
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Desvan.Palette.plank)
                    .overlay(alignment: .top) {
                        Capsule().fill(.black.opacity(0.35)).frame(height: 2).padding(.horizontal, 2)
                    }
                Capsule()
                    .fill(LinearGradient(
                        colors: [Desvan.usageTint(clamped), Desvan.usageTint(clamped).opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: max(6, width * clamped))
                // The notch: where an even pace would be.
                let x = width * min(max(pace, 0), 1)
                VStack(spacing: 0) {
                    Triangle()
                        .fill(Desvan.Palette.paper)
                        .frame(width: 7, height: 4)
                    Rectangle()
                        .fill(Desvan.Palette.paper)
                        .frame(width: 1.5, height: 8)
                }
                .shadow(color: .black.opacity(0.7), radius: 0.75)
                .offset(x: x - 3.5, y: -3)
            }
        }
        .frame(height: 6)
        .animation(Desvan.Motion.pick(Desvan.Motion.settle, reduceMotion: reduceMotion), value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}
