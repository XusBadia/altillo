import SwiftUI

/// Which sections the open notch shows, and in what order. Everything here changes the notch live.
struct SettingsModulesPane: View {
    @Bindable var settings: AltilloSettings

    private var disabled: [NotchModule] {
        NotchModule.allCases.filter { !settings.isEnabled($0) }
    }

    var body: some View {
        SettingsPane(
            title: "Secciones",
            subtitle: "Elige qué hay en el altillo y en qué orden. Arrastra para cambiar el orden de las pestañas."
        ) {
            List {
                Section {
                    ForEach(settings.modules) { module in
                        SettingsModuleRow(module: module, settings: settings)
                    }
                    .onMove { settings.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    SettingsListHeader("En el altillo")
                } footer: {
                    Text("El altillo no se puede desactivar: es lo que hace la app.")
                        .settingsHint()
                        .padding(.leading, 2)
                        .padding(.bottom, 4)
                }

                if !disabled.isEmpty {
                    Section {
                        ForEach(disabled) { module in
                            SettingsModuleRow(module: module, settings: settings)
                        }
                    } header: {
                        SettingsListHeader("Guardadas")
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 40)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }
}

private struct SettingsListHeader: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Desvan.Typeface.rounded(11, weight: .semibold))
            .foregroundStyle(Desvan.Palette.paperTertiary)
            .textCase(.uppercase)
            .padding(.top, 2)
    }
}

/// One module: its icon on kraft, its name, what it does, and the switch that puts it in the notch.
struct SettingsModuleRow: View {
    let module: NotchModule
    @Bindable var settings: AltilloSettings

    private var isOn: Binding<Bool> {
        Binding(
            get: { settings.isEnabled(module) },
            set: {
                settings.setEnabled(module, $0)
                if module == .drawer, !$0 { MenuBarDrawerStore.shared.setEnabled(false) }
            }
        )
    }

    var body: some View {
        HStack(spacing: 11) {
            if settings.isEnabled(module) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .accessibilityHidden(true)
            } else {
                Color.clear.frame(width: 11, height: 1)
            }

            Image(systemName: module.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(settings.isEnabled(module) ? Desvan.Palette.bulb : Desvan.Palette.paperTertiary)
                .frame(width: 26, height: 26)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                    shape.fill(Desvan.Palette.plank.opacity(settings.isEnabled(module) ? 0.9 : 0.45))
                        .overlay { shape.strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
                }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(module.title)
                        .font(Desvan.Typeface.rounded(13, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                    if module.isAlwaysOn {
                        Text("siempre")
                            .font(Desvan.Typeface.rounded(9.5, weight: .semibold))
                            .foregroundStyle(Desvan.Palette.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Desvan.Palette.kraft))
                    }
                }
                Text(module.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Toggle(module.title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(module.isAlwaysOn)
                .help(module.isAlwaysOn ? "El altillo siempre está: es lo que hace la app." : "")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
