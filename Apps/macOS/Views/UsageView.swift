import AltilloDesign
import SwiftUI

/// The AI usage tab: one card per provider with the 5-hour session (ring) and the weekly window (bar),
/// countdowns to each reset and a pace indicator.
struct UsageView: View {
    let demo: DemoContent

    var body: some View {
        HStack(spacing: 10) {
            ForEach(demo.usage) { usage in
                ProviderUsageCard(usage: usage)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct ProviderUsageCard: View {
    let usage: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)
            session
                .padding(.bottom, 12)
            Rectangle()
                .fill(Tokens.Palette.hairline)
                .frame(height: 0.5)
                .padding(.bottom, 10)
            weekly
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .altilloCard(radius: Tokens.Radius.large)
    }

    private var header: some View {
        HStack(spacing: 8) {
            AgentGlyph(agent: usage.agent, size: 18)
            Text(usage.agent.name)
                .font(Tokens.Typography.title)
                .foregroundStyle(Tokens.Palette.text)
            Text(usage.plan)
                .font(Tokens.Typography.micro)
                .foregroundStyle(Tokens.Palette.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(Tokens.Palette.hairlineStrong, lineWidth: 0.5))
            Spacer(minLength: 0)
        }
    }

    private var session: some View {
        let window = usage.session
        let level = UsageLevel(fraction: window.used)
        return HStack(spacing: 14) {
            UsageRing(value: window.used, lineWidth: 5, pace: window.expectedPace()) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int((window.used * 100).rounded()))")
                        .font(Tokens.Typography.figure(16))
                    Text("%")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tokens.Palette.textSecondary)
                }
                .foregroundStyle(level == .normal ? Tokens.Palette.text : level.tint)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Sesión · 5 h")
                Text("Se reinicia en \(NotchFormat.countdown(to: window.resetsAt))")
                    .font(Tokens.Typography.bodyEmphasis)
                    .foregroundStyle(Tokens.Palette.text)
                    .monospacedDigit()
                PaceLabel(delta: window.paceDelta())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var weekly: some View {
        let window = usage.weekly
        let level = UsageLevel(fraction: window.used)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Semana")
                Spacer()
                Text(NotchFormat.percent(window.used))
                    .font(Tokens.Typography.numeric(11.5, weight: .semibold))
                    .foregroundStyle(level == .normal ? Tokens.Palette.text : level.tint)
            }
            UsageBar(value: window.used, pace: window.expectedPace())
            HStack {
                Text("Se reinicia en \(NotchFormat.countdown(to: window.resetsAt))")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Palette.textTertiary)
                    .monospacedDigit()
                Spacer()
                PaceLabel(delta: window.paceDelta(), compact: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Tiny uppercase label over a metric.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Tokens.Typography.micro)
            .tracking(0.6)
            .foregroundStyle(Tokens.Palette.textTertiary)
    }
}

/// How the current burn compares with an even pace across the window.
struct PaceLabel: View {
    let delta: Double
    var compact = false

    var body: some View {
        let points = Int((abs(delta) * 100).rounded())
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .bold))
            Text(compact ? shortText(points) : longText(points))
                .monospacedDigit()
        }
        .font(Tokens.Typography.caption)
        .foregroundStyle(color)
    }

    private var symbol: String {
        if delta > 0.05 { return "arrow.up.right" }
        if delta < -0.05 { return "arrow.down.right" }
        return "equal"
    }

    private var color: Color {
        if delta > 0.05 { return Tokens.Palette.warning }
        if delta < -0.05 { return Tokens.Palette.success.opacity(0.9) }
        return Tokens.Palette.textSecondary
    }

    private func longText(_ points: Int) -> String {
        if delta > 0.05 { return "\(points) pts por encima del ritmo" }
        if delta < -0.05 { return "\(points) pts de margen" }
        return "Al ritmo"
    }

    private func shortText(_ points: Int) -> String {
        if delta > 0.05 { return "+\(points) pts" }
        if delta < -0.05 { return "Con margen" }
        return "Al ritmo"
    }
}
