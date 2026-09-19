import SwiftUI

/// How wide the notch opens. The notch redraws while the slider moves.
struct SettingsSizePane: View {
    @Bindable var settings: AltilloSettings

    var body: some View {
        SettingsPane(
            title: "Tamaño",
            subtitle: "Cuánto se abre el altillo. Cuanto más estrecho, menos tapa la pantalla."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Ancho del altillo abierto")
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
                            Text("Ancho del altillo abierto")
                        } minimumValueLabel: {
                            Text("Estrecho").settingsHint()
                        } maximumValueLabel: {
                            Text("Ancho").settingsHint()
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
                        Text("Vista previa")
                            .font(Desvan.Typeface.rounded(11, weight: .semibold))
                            .foregroundStyle(Desvan.Palette.paperTertiary)
                            .textCase(.uppercase)
                        SettingsNotchPreview(width: settings.openWidth, modules: settings.modules)
                        Text("El altillo abierto sobre la barra de menús, a la mitad de su tamaño.")
                            .settingsHint()
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
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
                Text(name)
                    .font(Desvan.Typeface.rounded(12, weight: .semibold))
                Text("\(Int(value)) pt")
                    .font(Desvan.Typeface.figure(9.5, weight: .medium))
                    .opacity(0.7)
            }
            .foregroundStyle(isSelected ? Desvan.Palette.bulbInk : Desvan.Palette.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                shape.fill(isSelected ? Desvan.Palette.bulb : Desvan.Palette.plank.opacity(0.7))
                    .overlay { shape.strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(Int(value)) puntos")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A half-scale silhouette of the open notch on a toy screen, with the tabs in their order.
/// Enough to judge the width before touching the real thing.
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
            .frame(width: width * scale, height: 66)
            .overlay(alignment: .top) {
                HStack(spacing: 8) {
                    ForEach(modules) { module in
                        Image(systemName: module.symbol)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(
                                module == modules.first ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary
                            )
                    }
                }
                .padding(.top, 10)
            }
            .overlay(alignment: .bottom) {
                // The plank, with a couple of things left on it.
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Desvan.Palette.plank)
                        .frame(height: 18)
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Desvan.Palette.paper.opacity(0.55))
                                .frame(width: 9, height: 11)
                        }
                    }
                    .padding(.bottom, 5)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .animation(.easeOut(duration: 0.12), value: width)
    }
}
