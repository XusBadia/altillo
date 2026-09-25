import SwiftUI

// Small pieces every page of the welcome shares, in Desván's voice: wood, paper, the bulb as light.

/// A page's title block: a kraft eyebrow ("Step 2 of 5"), the title in SF Pro Rounded and one warm sentence.
struct OnboardingHeader: View {
    let eyebrow: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(verbatim: eyebrow.uppercased())
                .font(Desvan.Typeface.rounded(10.5, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(Desvan.Palette.kraft)
                .accessibilityHidden(true)
            Text(title)
                .font(Desvan.Typeface.display(24, weight: 700))
                .foregroundStyle(Desvan.Palette.paper)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}

/// Where you are in the welcome: one small bar per page, the current one lit by the bulb, the ones behind in kraft.
struct OnboardingProgress: View {
    let steps: [OnboardingStep]
    let current: OnboardingStep
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(steps) { step in
                let isCurrent = step == current
                Capsule()
                    .fill(fill(for: step))
                    .frame(width: isCurrent ? 26 : 12, height: 5)
                    .shadow(color: Desvan.Palette.bulb.opacity(isCurrent ? 0.6 : 0), radius: 5)
            }
        }
        .animation(Desvan.Motion.pick(Desvan.Motion.section, reduceMotion: reduceMotion), value: current)
        .animation(Desvan.Motion.pick(Desvan.Motion.section, reduceMotion: reduceMotion), value: steps)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(OnboardingText.position(of: current, in: steps)))
    }

    private func fill(for step: OnboardingStep) -> Color {
        if step == current { return Desvan.Palette.bulb }
        return step.rawValue < current.rawValue ? Desvan.Palette.kraft.opacity(0.75) : Desvan.Palette.paper.opacity(0.14)
    }
}

enum OnboardingText {
    /// "Step 2 of 5". A page that no longer applies (the search came back empty while it was on screen) counts
    /// where it would have been.
    static func position(of step: OnboardingStep, in steps: [OnboardingStep]) -> String {
        let index = steps.firstIndex(of: step) ?? steps.lastIndex { $0.rawValue < step.rawValue } ?? 0
        return String(localized: "Step \(index + 1) of \(steps.count)")
    }
}

/// A key as printed on a keyboard: a small raised cap of paper-on-wood.
struct OnboardingKeycap: View {
    let label: String

    var body: some View {
        Text(verbatim: label)
            .font(Desvan.Typeface.rounded(12, weight: .semibold))
            .foregroundStyle(Desvan.Palette.paper)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 22)
            .background {
                let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
                shape.fill(LinearGradient(colors: [Color(hex: 0x3B3026), Color(hex: 0x2B231B)],
                                          startPoint: .top, endPoint: .bottom))
                    .overlay { shape.strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.75) }
                    .shadow(color: .black.opacity(0.6), radius: 0, y: 1.5)
            }
    }
}

/// A symbol on a small warm tile, the icon of a row.
struct OnboardingSymbolTile: View {
    let symbol: String
    var tint: Color = Desvan.Palette.kraft
    var size: CGFloat = 32

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                shape.fill(tint.opacity(0.12))
                    .overlay { shape.strokeBorder(tint.opacity(0.22), lineWidth: 0.75) }
            }
            .accessibilityHidden(true)
    }
}

/// "Allowed", "Installed": a quiet sage confirmation with a check.
struct OnboardingDoneLabel: View {
    let text: LocalizedStringKey

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(Desvan.Typeface.rounded(12, weight: .semibold))
            .foregroundStyle(Desvan.Palette.done)
            .labelStyle(.titleAndIcon)
            .fixedSize()
    }
}
