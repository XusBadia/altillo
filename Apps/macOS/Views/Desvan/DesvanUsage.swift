import AltilloDesign
import SwiftUI

/// The usage tab: one compact wood card per provider. The session ring with its figure in New York, when it
/// refills, the pace in italics ("vas 9 puntos por delante del ritmo") and the weekly bar with a notch where an even
/// pace would be.
struct DesvanUsageView: View {
    let demo: DemoContent

    var body: some View {
        HStack(spacing: 8) {
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
            session
            Spacer(minLength: 6)
            weekly
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .desvanCard()
    }

    private var session: some View {
        let window = usage.session
        let used = window.used
        return HStack(spacing: 11) {
            DesvanRing(value: used, lineWidth: 4, pace: window.expectedPace()) {
                HStack(alignment: .firstTextBaseline, spacing: 0.5) {
                    Text("\(Int((used * 100).rounded()))")
                        .font(Desvan.Typeface.figure(17, weight: .semibold))
                        .contentTransition(.numericText(value: used))
                    Text("%")
                        .font(Desvan.Typeface.figure(8, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                }
                .foregroundStyle(Desvan.Palette.paper)
                .offset(x: 1)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    AgentGlyph(agent: usage.agent, size: 14)
                    Text(usage.agent.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                    Text(usage.plan)
                        .font(Desvan.Typeface.rounded(9.5, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .padding(.horizontal, 6)
                        .frame(height: 15)
                        .background(Capsule().fill(Desvan.Palette.woodRaised))
                        .overlay(Capsule().strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.5))
                    Spacer(minLength: 4)
                    Text("5 h")
                        .font(Desvan.Typeface.rounded(10, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                        .help("Sesión de 5 h")
                }
                Text("se repone en \(NotchFormat.countdown(to: window.resetsAt))")
                    .font(Desvan.Typeface.rounded(11.5, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paper.opacity(0.85))
                    .monospacedDigit()
                DesvanPace(delta: window.paceDelta())
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// One line: the week's bar, its figure and when it refills.
    private var weekly: some View {
        let window = usage.weekly
        return HStack(spacing: 8) {
            Text("Semana")
                .font(Desvan.Typeface.rounded(10, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperTertiary)
            DesvanBar(value: window.used, pace: window.expectedPace())
            Text(NotchFormat.percent(window.used))
                .font(Desvan.Typeface.figure(12, weight: .medium))
                .foregroundStyle(Desvan.usageTint(window.used))
                .monospacedDigit()
            Text(NotchFormat.countdown(to: window.resetsAt))
                .font(Desvan.Typeface.rounded(10, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .help("Semana: se repone en \(NotchFormat.countdown(to: window.resetsAt)) · \(DesvanPace.shortText(delta: window.paceDelta()))")
        .accessibilityElement(children: .combine)
    }
}

/// The pace, in New York italic: "vas 9 puntos por delante del ritmo" / "vas con 12 de margen" / "vas a buen ritmo".
private struct DesvanPace: View {
    let delta: Double

    var body: some View {
        let points = Int((abs(delta) * 100).rounded())
        Text(longText(points))
            .font(.system(size: 11.5, weight: .regular, design: .serif).italic())
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

    static func shortText(delta: Double) -> String {
        let points = Int((abs(delta) * 100).rounded())
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
                        .frame(width: 6, height: 3.5)
                    Rectangle()
                        .fill(Desvan.Palette.paper)
                        .frame(width: 1.5, height: 7)
                }
                .shadow(color: .black.opacity(0.7), radius: 0.75)
                .offset(x: x - 3, y: -2.5)
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
