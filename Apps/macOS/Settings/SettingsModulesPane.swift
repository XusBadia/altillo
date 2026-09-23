import SwiftUI

/// Which sections the open notch shows, in what order, and what sits in the ears beside it. Everything here changes
/// the notch live; the same things (and more directly) can be done in the notch itself, in edit mode.
struct SettingsModulesPane: View {
    @Bindable var settings: AltilloSettings
    /// Keeps what a preset replaced, for its Undo.
    @State private var session = NotchEditSession()

    private var disabled: [NotchModule] {
        NotchModule.allCases.filter { !settings.isEnabled($0) }
    }

    var body: some View {
        SettingsPane(
            title: "Sections",
            subtitle: "Choose what goes up there, and in what order. Drag to reorder the tabs."
        ) {
            List {
                Section {
                    SettingsPresetsRow(settings: settings, session: session)
                } header: {
                    SettingsListHeader("Start from")
                }

                Section {
                    SettingsEarsRow(settings: settings, session: session)
                } header: {
                    SettingsListHeader("Ears")
                }

                Section {
                    ForEach(settings.modules) { module in
                        SettingsModuleRow(module: module, settings: settings)
                    }
                    .onMove { settings.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    SettingsListHeader("Up there")
                } footer: {
                    Text("The shelf can't be turned off: it's what the app does.")
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
                        SettingsListHeader("Put away")
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

// MARK: - Presets

/// Minimal, Developer, Everything, and the way into the notch's own edit mode. Applying one offers Undo for a moment.
private struct SettingsPresetsRow: View {
    @Bindable var settings: AltilloSettings
    let session: NotchEditSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(NotchPreset.allCases) { preset in
                    SettingsStarterButton(preset: preset, isSelected: settings.matchingPreset == preset) {
                        withAnimation(.easeOut(duration: 0.15)) { _ = session.apply(preset, in: settings) }
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Customize in the Notch…") {
                    NotificationCenter.default.post(name: .altilloCustomizeNotch, object: nil)
                }
                .help("Opens the notch in edit mode: drag the tabs and the ears right where they are.")
                if let preset = session.justApplied {
                    Button("Undo \(preset.title)") {
                        withAnimation(.easeOut(duration: 0.15)) { _ = session.undo(in: settings) }
                    }
                    .keyboardShortcut("z", modifiers: .command)
                    .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .task(id: session.justApplied) {
            guard session.justApplied != nil else { return }
            try? await Task.sleep(for: DesvanEdit.undoOffer)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { session.justApplied = nil }
        }
    }
}

private struct SettingsStarterButton: View {
    let preset: NotchPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(preset.title)
                        .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                    }
                }
                HStack(spacing: 3) {
                    ForEach(preset.modules) { module in
                        Image(systemName: module.symbol).font(.system(size: 8.5, weight: .semibold))
                    }
                }
                .opacity(0.75)
            }
            .foregroundStyle(isSelected ? Desvan.Palette.bulbInk : Desvan.Palette.paper)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                shape.fill(isSelected ? Desvan.Palette.bulb : Desvan.Palette.plank.opacity(0.7))
                    .overlay { shape.strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(preset.explanation)
        .accessibilityLabel(preset.title)
        .accessibilityHint(preset.explanation)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Ears

/// What each ear shows, and whether they show all the time. A small resting notch above previews it live.
private struct SettingsEarsRow: View {
    @Bindable var settings: AltilloSettings
    let session: NotchEditSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsEarsPreview(leftEar: settings.leftEar, rightEar: settings.rightEar,
                                visibility: settings.earsVisibility)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    label(Text(EarSide.left.title))
                    earPicker(.left)
                }
                GridRow {
                    label(Text(EarSide.right.title))
                    earPicker(.right)
                }
                GridRow {
                    label(Text("Show them"))
                    Picker(selection: visibility) {
                        ForEach(EarsVisibility.allCases) { visibility in
                            Text(visibility.title).tag(visibility)
                        }
                    } label: {
                        Text("Show them")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            Text("Usage and agents arrive with their sections. The same ear twice isn't possible: they swap.")
                .settingsHint()
        }
        .padding(.vertical, 6)
    }

    private var visibility: Binding<EarsVisibility> {
        Binding(get: { settings.earsVisibility }, set: { _ = session.setVisibility($0, in: settings) })
    }

    private func earPicker(_ side: EarSide) -> some View {
        Picker(selection: Binding(
            get: { session.ear(side, in: settings) },
            set: { _ = session.assign($0, to: side, in: settings) }
        )) {
            ForEach(EarContent.allCases) { content in
                Label(content.isAvailable ? content.title : String(localized: "\(content.title) (coming soon)"),
                      systemImage: content.symbol)
                    .tag(content)
                    .selectionDisabled(!content.isAvailable)
            }
        } label: {
            Text(side.title)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private func label(_ text: Text) -> some View {
        text
            .font(.system(size: 12.5))
            .foregroundStyle(Desvan.Palette.paper)
            .gridColumnAlignment(.trailing)
    }
}

private struct SettingsListHeader: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

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
                        Text("always")
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
                .help(module.isAlwaysOn ? "The shelf is always there: it's what the app does." : "")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
