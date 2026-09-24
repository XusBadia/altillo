import SwiftUI

/// How wide the notch opens. The notch redraws while the slider moves.
struct SettingsSizePane: View {
    @Bindable var settings: AltilloSettings

    var body: some View {
        SettingsPane(
            title: "Size",
            subtitle: "How wide the shelf opens. The narrower it is, the less of the screen it covers."
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Width when open")
                                    .font(Desvan.Typeface.rounded(13, weight: .medium))
                                    .foregroundStyle(Desvan.Palette.paper)
                                Spacer()
                                Text("\(Int(settings.openWidth.rounded())) pt")
                                    .font(Desvan.Typeface.figure(13))
                                    .foregroundStyle(Desvan.Palette.bulb)
                            }

                            Slider(
                                value: $settings.openWidth,
                                in: AltilloSettings.widthRange,
                                step: 5
                            ) {
                                Text("Width when open")
                            } minimumValueLabel: {
                                Text("Narrow").settingsHint()
                            } maximumValueLabel: {
                                Text("Wide").settingsHint()
                            }
                            .labelsHidden()

                            HStack(spacing: 8) {
                                ForEach(AltilloSettings.widthPresets, id: \.name) { preset in
                                    SettingsPresetButton(
                                        name: preset.name,
                                        value: preset.value,
                                        isSelected: abs(settings.openWidth - preset.value) < 0.5
                                    ) {
                                        settings.openWidth = preset.value
                                    }
                                }
                            }
                        }
                    }

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Preview")
                                .font(Desvan.Typeface.rounded(11, weight: .semibold))
                                .foregroundStyle(Desvan.Palette.paperTertiary)
                                .textCase(.uppercase)
                            SettingsNotchPreview(width: settings.openWidth, modules: settings.modules)
                            SettingsEarsPreview(leftEar: settings.leftEar, rightEar: settings.rightEar,
                                                visibility: settings.earsVisibility)
                            Text("The open shelf over the menu bar at half its size, and the notch at rest with its ears.")
                                .settingsHint()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            // Never clipped, whatever the text size: it scrolls instead.
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct SettingsPresetButton: View {
    let name: String
    let value: Double
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(verbatim: name)
                    .font(Desvan.Typeface.rounded(12, weight: .semibold))
                Text("\(Int(value)) pt")
                    .font(Desvan.Typeface.figure(11, weight: .medium))
                    .opacity(0.75)
            }
            .foregroundStyle(isSelected ? Desvan.Palette.bulbInk : Desvan.Palette.paper)
            .frame(maxWidth: .infinity, minHeight: 40)
            .padding(.vertical, 4)
            .background {
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                shape.fill(isSelected ? Desvan.Palette.bulb : Desvan.Palette.plank.opacity(0.7))
                    .overlay { shape.strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(Int(value)) points")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A half-scale silhouette of the open notch on a toy screen, with the tabs in their order (the first one lit, as
/// the notch opens on it). Enough to judge the width before touching the real thing.
struct SettingsNotchPreview: View {
    let width: Double
    let modules: [NotchModule]

    private let scale = 0.5

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(
                colors: [Desvan.Palette.plank.opacity(0.55), Desvan.Palette.wood],
                startPoint: .top,
                endPoint: .bottom
            ))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 1)
            }
            .frame(height: 150)
            .overlay(alignment: .top) { menuBar }
            .overlay(alignment: .top) { notch }
            .accessibilityHidden(true)
    }

    /// The menu bar the notch sits on: a few crumbs of a title and some icons.
    private var menuBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(Desvan.Palette.paperTertiary).frame(width: 14, height: 3)
                }
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { _ in
                    Circle().fill(Desvan.Palette.paperTertiary).frame(width: 3.5, height: 3.5)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
    }

    private var notch: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Desvan.Palette.notch)
            // Half the open shelf's height: band, air, the plank with its things and the margin under it.
            .frame(width: width * scale, height: 104)
            .overlay(alignment: .top) {
                HStack(spacing: 8) {
                    ForEach(modules) { module in
                        Image(systemName: module.symbol)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(
                                module == modules.first ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary
                            )
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.3, bounce: 0.15), value: modules)
                .padding(.top, 10)
            }
            .overlay(alignment: .bottom) {
                // The plank, with a couple of things left on it.
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Desvan.Palette.plank)
                        .frame(height: 64)
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Desvan.Palette.paper.opacity(0.55))
                                .frame(width: 30, height: 36)
                        }
                    }
                    .padding(.bottom, 18)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .animation(.easeOut(duration: 0.12), value: width)
    }
}

/// The notch at rest on a strip of menu bar, with what each ear shows (sample figures: three things on the shelf,
/// an event at 10:30, music playing). Follows the settings live.
struct SettingsEarsPreview: View {
    let leftEar: EarContent
    let rightEar: EarContent
    let visibility: EarsVisibility

    private static let notchWidth: CGFloat = 120
    private static let earWidth: CGFloat = 48

    var body: some View {
        let hasEars = leftEar != .none || rightEar != .none
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LinearGradient(colors: [Desvan.Palette.plank.opacity(0.55), Desvan.Palette.wood],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 1)
            }
            .frame(height: 40)
            .overlay(alignment: .top) {
                HStack(spacing: 0) {
                    ear(leftEar).frame(width: hasEars ? Self.earWidth : 0)
                    Color.clear.frame(width: Self.notchWidth)
                    ear(rightEar).frame(width: hasEars ? Self.earWidth : 0)
                }
                .frame(height: 24)
                .background {
                    UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9, style: .continuous)
                        .fill(Desvan.Palette.notch)
                }
                .clipped()
            }
            .overlay(alignment: .bottomTrailing) {
                Text(visibility == .always ? "Always" : "When there's something")
                    .font(Desvan.Typeface.rounded(11, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .padding(6)
            }
            .animation(.spring(duration: 0.3, bounce: 0.15), value: [leftEar, rightEar])
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ears: \(leftEar.title) on the left, \(rightEar.title) on the right")
    }

    @ViewBuilder
    private func ear(_ content: EarContent) -> some View {
        Group {
            switch content {
            case .none:
                EmptyView()
            case .shelf:
                HStack(spacing: 3) {
                    DesvanHouseMark(size: 11)
                    Text(verbatim: "3").font(Desvan.Typeface.figure(11, weight: .medium))
                }
            case .nextEvent:
                HStack(spacing: 2) {
                    Image(systemName: "calendar").font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                    Text(verbatim: "10:30").font(Desvan.Typeface.figure(11, weight: .medium))
                }
            case .nowPlaying:
                HStack(alignment: .bottom, spacing: 1.5) {
                    ForEach([0.45, 0.9, 0.6, 0.75], id: \.self) { level in
                        Capsule().fill(Desvan.Palette.bulb).frame(width: 2, height: 10 * level)
                    }
                }
                .frame(height: 10, alignment: .bottom)
            case .usage, .agents:
                Image(systemName: content.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            }
        }
        .foregroundStyle(Desvan.Palette.paper)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}
