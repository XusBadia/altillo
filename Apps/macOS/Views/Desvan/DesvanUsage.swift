import AltilloDesign
import SwiftUI

/// The usage tab: one compact wood card per provider. The session ring with its figure, when it
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

    /// The card measures itself and drops what it can't hold: the plan chip and the window length first, then the
    /// long sentences. The notch can be as narrow as 440 pt, which leaves ~190 pt per provider.
    @State private var width: CGFloat = 0
    private var density: Density {
        if width <= 0 || width >= 278 { return .full }
        return width >= 216 ? .medium : .compact
    }

    private enum Density { case full, medium, compact }

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
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
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
                        .lineLimit(1)
                    if density != .compact {
                        Text(usage.plan)
                            .font(Desvan.Typeface.rounded(9.5, weight: .semibold))
                            .foregroundStyle(Desvan.Palette.paperSecondary)
                            .padding(.horizontal, 6)
                            .frame(height: 15)
                            .background(Capsule().fill(Desvan.Palette.woodRaised))
                            .overlay(Capsule().strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.5))
                            .fixedSize()
                        Spacer(minLength: 4)
                        Text("5 h")
                            .font(Desvan.Typeface.rounded(10, weight: .semibold))
                            .foregroundStyle(Desvan.Palette.paperTertiary)
                            .help("5-hour session")
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                Text(density == .compact
                     ? "in \(NotchFormat.countdown(to: window.resetsAt))"
                     : "refills in \(NotchFormat.countdown(to: window.resetsAt))")
                    .font(Desvan.Typeface.rounded(11.5, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paper.opacity(0.85))
                    .monospacedDigit()
                    .lineLimit(1)
                    .help("\(usage.plan) · refills in \(NotchFormat.countdown(to: window.resetsAt))")
                DesvanPace(delta: window.paceDelta(), long: density == .full)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// One line: the week's bar, its figure and when it refills.
    private var weekly: some View {
        let window = usage.weekly
        return HStack(spacing: 8) {
            if density != .compact {
                Text("Week")
                    .font(Desvan.Typeface.rounded(10, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .fixedSize()
            }
            DesvanBar(value: window.used, pace: window.expectedPace())
            Text(NotchFormat.percent(window.used))
                .font(Desvan.Typeface.figure(12, weight: .medium))
                .foregroundStyle(Desvan.usageTint(window.used))
                .monospacedDigit()
                .fixedSize()
            if density == .full {
                Text(NotchFormat.countdown(to: window.resetsAt))
                    .font(Desvan.Typeface.rounded(10, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .help("Week: refills in \(NotchFormat.countdown(to: window.resetsAt)) · \(DesvanPace.shortText(delta: window.paceDelta()))")
        .accessibilityElement(children: .combine)
    }
}

/// The pace, in SF Pro Rounded italic: "9 points ahead of pace" / "12 points of room to spare" / "right on pace".
private struct DesvanPace: View {
    let delta: Double
    /// The whole sentence, or the short form when the card is narrow.
    var long = true

    var body: some View {
        let points = Int((abs(delta) * 100).rounded())
        Text(verbatim: long ? longText(points) : Self.shortText(delta: delta))
            .font(.system(size: 11.5, weight: .medium, design: .rounded).italic())
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(1)
            .help(longText(Int((abs(delta) * 100).rounded())))
    }

    private var color: Color {
        if delta > 0.05 { return Desvan.Palette.warning }
        if delta < -0.05 { return Desvan.Palette.done }
        return Desvan.Palette.paperSecondary
    }

    private func longText(_ points: Int) -> String {
        if delta > 0.05 { return String(localized: "\(points) points ahead of pace") }
        if delta < -0.05 { return String(localized: "\(points) points of room to spare") }
        return String(localized: "right on pace")
    }

    static func shortText(delta: Double) -> String {
        let points = Int((abs(delta) * 100).rounded())
        if delta > 0.05 { return String(localized: "\(points) ahead") }
        if delta < -0.05 { return String(localized: "room to spare") }
        return String(localized: "on pace")
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
