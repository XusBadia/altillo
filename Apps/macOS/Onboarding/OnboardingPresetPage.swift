import SwiftUI

/// Page 2: the three starting points (PLAN §4) as cards, each with a small live picture of what it puts up there:
/// the ears beside the notch and the sections in the open notch. Picking one applies it at once.
struct OnboardingPresetPage: View {
    let flow: OnboardingFlow
    let eyebrow: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeader(
                eyebrow: eyebrow,
                title: "Pick a starting point",
                subtitle: "Choose what lives up there. Each one sets the sections of the open notch and what sits beside it."
            )

            HStack(alignment: .top, spacing: 12) {
                ForEach(NotchPreset.allCases) { preset in
                    OnboardingPresetCard(preset: preset, isSelected: flow.settings.matchingPreset == preset) {
                        withAnimation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion)) {
                            flow.settings.apply(preset)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.kraft)
                    .accessibilityHidden(true)
                Text(footnote)
                    .font(.system(size: 12))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .padding(.top, 18)
    }

    private var footnote: String {
        if flow.settings.matchingPreset == nil {
            return String(localized: "Nothing picked: your sections stay as they are. You can change everything later: right-click the notch.")
        }
        return String(localized: "You can change everything later: right-click the notch.")
    }
}

private struct OnboardingPresetCard: View {
    let preset: NotchPreset
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                OnboardingPresetPreview(preset: preset)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(preset.title)
                            .font(Desvan.Typeface.display(16, weight: 650))
                            .foregroundStyle(Desvan.Palette.paper)
                        Spacer(minLength: 4)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isSelected ? Desvan.Palette.bulb : Desvan.Palette.paper.opacity(0.25))
                            .accessibilityHidden(true)
                    }
                    Text(preset.explanation)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                    Text(sectionCount)
                        .font(Desvan.Typeface.figure(11, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                }
                .padding(.horizontal, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .desvanCard(radius: 16, fill: isHovering && !isSelected ? Desvan.Palette.woodRaised : Desvan.Palette.wood,
                        glow: isSelected ? Desvan.Palette.bulb : nil)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(preset.title))
        .accessibilityValue(Text(preset.explanation))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var sectionCount: String {
        let count = preset.modules.count
        return count == 1 ? String(localized: "1 section") : String(localized: "\(count) sections")
    }
}

/// A small picture of the top of the screen with this preset: the notch with its ears, and the open notch's tab
/// strip hanging from it, the first section on its brass plaque.
struct OnboardingPresetPreview: View {
    let preset: NotchPreset
    private static let maxIcons = 7

    var body: some View {
        // Seven fit; beyond that the last slot says how many more.
        let modules = preset.modules
        let shown = modules.count <= Self.maxIcons ? modules : Array(modules.prefix(Self.maxIcons - 1))
        let more = modules.count - shown.count
        let icon: CGFloat = 11
        ZStack(alignment: .top) {
            // The screen: warm dusk behind the menu bar.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x3A2E24), Color(hex: 0x241D17)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    Rectangle().fill(Desvan.Palette.paper.opacity(0.07)).frame(height: 11)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.75)
                }

            VStack(spacing: 7) {
                // The resting notch and its ears.
                HStack(spacing: 0) {
                    ear(preset.leftEar)
                    Spacer(minLength: 34)
                    ear(preset.rightEar)
                }
                .frame(width: 96, height: 12)

                // The open notch's sections.
                HStack(spacing: 2) {
                    ForEach(Array(shown.enumerated()), id: \.element) { index, module in
                        Image(systemName: module.symbol)
                            .font(.system(size: icon, weight: .semibold))
                            .foregroundStyle(index == 0 ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
                            .frame(width: icon + 6, height: icon + 8)
                            .background {
                                if index == 0 { DesvanTabPlaque(cornerRadius: 4) }
                            }
                    }
                    if more > 0 {
                        Text(verbatim: "+\(more)")
                            .font(Desvan.Typeface.figure(10, weight: .semibold))
                            .foregroundStyle(Desvan.Palette.paperTertiary)
                            .frame(height: icon + 8)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 1)
            .padding(.bottom, 8)
            .background {
                UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous)
                    .fill(Color.black)
                    .overlay(alignment: .top) {
                        DesvanBulbGlow(intensity: 0.1, radius: 60, originY: 14)
                    }
            }
        }
        .frame(height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func ear(_ content: EarContent) -> some View {
        if content == .none {
            Color.clear.frame(width: 12, height: 12)
        } else {
            Image(systemName: content.symbol)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(content == .automatic ? Desvan.Palette.bulb : Desvan.Palette.paper)
                .frame(width: 12, height: 12)
        }
    }
}
