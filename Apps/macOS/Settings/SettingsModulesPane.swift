import AltilloCore
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
            ScrollViewReader { proxy in
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

                if settings.isEnabled(.calendar) {
                    Section {
                        SettingsCalendarGroup(settings: settings)
                            .id(Self.calendarAnchor)
                    } header: {
                        SettingsListHeader("Calendar")
                    }
                }

                if settings.isEnabled(.usage) {
                    Section {
                        SettingsUsageGroup(settings: settings, store: UsageStore.live)
                            .id(Self.usageAnchor)
                    } header: {
                        SettingsListHeader("Usage")
                    }
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
            .onAppear {
                // `-settingsSection calendar|usage` (with `-settingsTab modules`) opens scrolled to that group.
                if let anchor = UserDefaults.standard.string(forKey: "settingsSection"),
                   [Self.calendarAnchor, Self.usageAnchor].contains(anchor) {
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
            }
        }
    }

    private static let calendarAnchor = "calendar"
    private static let usageAnchor = "usage"
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
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                    }
                }
                HStack(spacing: 3) {
                    ForEach(preset.modules) { module in
                        Image(systemName: module.symbol).font(.system(size: 11, weight: .semibold))
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
            Text("Agents arrive with their section. The same ear twice isn't possible: they swap.")
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .accessibilityHidden(true)
            } else {
                Color.clear.frame(width: 13, height: 1)
            }

            Image(systemName: module.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(settings.isEnabled(module) ? Desvan.Palette.bulb : Desvan.Palette.paperTertiary)
                .frame(width: 30, height: 30)
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
                            .font(Desvan.Typeface.rounded(11, weight: .semibold))
                            .foregroundStyle(Desvan.Palette.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Desvan.Palette.kraft))
                    }
                }
                Text(module.explanation)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Calendar

/// The calendar section's own settings: its layout, all-day events and which calendars show. Calendars are listed
/// by account, only once Altillo can see them; before that, the way to let it.
private struct SettingsCalendarGroup: View {
    @Bindable var settings: AltilloSettings
    @State private var directory = CalendarDirectory()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    label("Layout")
                    Picker(selection: $settings.calendarStyle) {
                        ForEach(CalendarStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    } label: {
                        Text("Layout")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    Toggle(isOn: $settings.calendarShowsAllDay) {
                        Text("Show all-day events")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Desvan.Palette.paper)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Text("Right-click the calendar in the notch to switch layout from there.")
                .settingsHint()

            calendars
        }
        .padding(.vertical, 6)
        .onAppear { directory.start() }
        .onDisappear { directory.stop() }
    }

    @ViewBuilder
    private var calendars: some View {
        switch directory.access {
        case .granted:
            if directory.accounts.isEmpty {
                if directory.hasLoaded {
                    Text("There are no calendars on this Mac yet.")
                        .settingsHint()
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Calendars")
                        .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                    ForEach(directory.accounts) { account in
                        SettingsCalendarAccount(account: account, settings: settings)
                    }
                    Text("Hidden calendars leave the grid and the agenda. Nothing changes in Calendar itself.")
                        .settingsHint()
                }
            }
        case .unknown:
            access(
                "Altillo can't see your calendars yet. Events never leave your Mac.",
                button: "Give Access…"
            ) {
                Task { await directory.requestAccess() }
            }
        case .denied:
            access(
                "Altillo isn't allowed to see your calendars. You can change that in System Settings.",
                button: "Open Privacy Settings…"
            ) {
                PrivacySettings.calendars.open()
            }
        }
    }

    private func access(_ message: LocalizedStringKey, button: LocalizedStringKey,
                        action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Desvan.Palette.bulb)
            Text(message)
                .settingsHint()
            Spacer(minLength: 8)
            Button(button, action: action)
                .controlSize(.small)
        }
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Desvan.Palette.paper)
            .gridColumnAlignment(.trailing)
    }
}

/// One account (iCloud, Google, On My Mac…) and a checkbox per calendar, with its colour.
private struct SettingsCalendarAccount: View {
    let account: CalendarAccount
    @Bindable var settings: AltilloSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(account.title)
                .font(Desvan.Typeface.rounded(11, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .textCase(.uppercase)
            ForEach(account.calendars) { calendar in
                Toggle(isOn: shows(calendar)) {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(hex: calendar.colorHex))
                            .overlay {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(.black.opacity(0.3), lineWidth: 0.5)
                            }
                            .frame(width: 11, height: 11)
                            .accessibilityHidden(true)
                        Text(calendar.title)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Desvan.Palette.paper)
                            .lineLimit(1)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(.leading, 2)
    }

    private func shows(_ calendar: CalendarInfo) -> Binding<Bool> {
        Binding(
            get: { !settings.calendarHiddenIDs.contains(calendar.id) },
            set: { shows in
                if shows {
                    settings.calendarHiddenIDs.remove(calendar.id)
                } else {
                    settings.calendarHiddenIDs.insert(calendar.id)
                }
            }
        )
    }
}

// MARK: - Usage

/// The usage section's own settings: which providers it reads (with how each one is doing), when it peeks, and
/// whether an OpenUsage-compatible app fills in the providers Altillo doesn't read itself.
private struct SettingsUsageGroup: View {
    @Bindable var settings: AltilloSettings
    /// The running app's store; nil only in previews.
    let store: UsageStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            providers
            alerts
            openUsage
        }
        .padding(.vertical, 6)
        .onAppear { store?.refreshIfOlder(than: 60) }
    }

    // MARK: Providers

    @ViewBuilder
    private var providers: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Providers")
                    .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                Spacer(minLength: 8)
                if let store {
                    Button(store.isRefreshing ? "Checking…" : "Check Again") { store.refreshNow() }
                        .controlSize(.small)
                        .disabled(store.isRefreshing)
                }
            }
            let entries = store?.entries ?? []
            if entries.isEmpty {
                Text(store?.hasChecked == true
                     ? "Neither Claude Code nor Codex is set up on this Mac yet. Sign in to one and it shows up here."
                     : "Looking for your AI tools…")
                    .settingsHint()
            } else {
                ForEach(entries) { entry in
                    SettingsUsageProviderRow(entry: entry, settings: settings)
                }
                Text("Altillo reads the sign-in your tools already have. It never signs in, refreshes or changes anything, and your numbers never leave this Mac.")
                    .settingsHint()
            }
        }
    }

    // MARK: Alerts

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $settings.alertsForUsage) {
                Text("Peek when a limit runs high")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paper)
            }
            .toggleStyle(.checkbox)
            HStack(spacing: 12) {
                Text("At")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                ForEach(AltilloSettings.usageAlertThresholdChoices, id: \.self) { level in
                    Toggle(isOn: threshold(level)) {
                        Text("\(level)%")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Desvan.Palette.paper)
                            .monospacedDigit()
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityLabel(String(localized: "Peek at \(level)% used"))
                }
            }
            .padding(.leading, 20)
            .disabled(!settings.alertsForUsage)
            Toggle(isOn: $settings.usageAlertsWhenRefilled) {
                Text("And when it refills")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paper)
            }
            .toggleStyle(.checkbox)
            .padding(.leading, 20)
            .disabled(!settings.alertsForUsage)
            Text("A limit used up, or one running out before it refills, always peeks while this is on. Each one peeks once per window.")
                .settingsHint()
        }
    }

    private func threshold(_ level: Int) -> Binding<Bool> {
        Binding(
            get: { settings.usageAlertThresholds.contains(level) },
            set: { settings.setUsageAlertThreshold(level, enabled: $0) }
        )
    }

    // MARK: OpenUsage

    private var openUsage: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $settings.usageShowsOpenUsageSource) {
                Text("Also read an app compatible with OpenUsage")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paper)
            }
            .toggleStyle(.checkbox)
            Text("Only for providers Altillo doesn't read itself, and only if that app is running on this Mac.")
                .settingsHint()
                .padding(.leading, 20)

            Toggle(isOn: legacyExport) {
                Text("Also send them to the current iPhone app")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paper)
            }
            .toggleStyle(.checkbox)
            .disabled(!OpenUsageMobilePublisher.hasContainerEntitlement)
            .padding(.top, 6)
            if OpenUsageMobilePublisher.hasContainerEntitlement {
                Text("Writes the numbers to iCloud in the format the iPhone app from before Altillo reads, so you can retire the old bridge.")
                    .settingsHint()
                    .padding(.leading, 20)
            } else {
                Text("Available in release builds signed for iCloud.")
                    .settingsHint()
                    .padding(.leading, 20)
            }
        }
    }

    /// `OpenUsageMobilePublisher` reads this key itself on every publish.
    private var legacyExport: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.object(forKey: OpenUsageMobilePublisher.enabledKey) as? Bool ?? true },
            set: { UserDefaults.standard.set($0, forKey: OpenUsageMobilePublisher.enabledKey) }
        )
    }
}

/// One provider: its mark, its name, how it's doing ("Connected · Max 20x", "Sign-in expired: open Claude Code
/// once") and the switch that puts it in the notch.
private struct SettingsUsageProviderRow: View {
    let entry: UsageStore.Entry
    @Bindable var settings: AltilloSettings

    private var isOn: Binding<Bool> {
        Binding(
            get: { settings.isUsageProviderEnabled(entry.id) },
            set: { settings.setUsageProvider(entry.id, enabled: $0) }
        )
    }

    private var hasProblem: Bool { !entry.isAvailable || entry.usage?.problem != nil }

    var body: some View {
        HStack(spacing: 10) {
            AgentGlyph(provider: entry.id, name: entry.displayName, size: 24)
                .opacity(entry.isAvailable ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .font(Desvan.Typeface.rounded(13, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                HStack(spacing: 4) {
                    if hasProblem {
                        Image(systemName: entry.isAvailable ? "exclamationmark.triangle.fill" : "person.crop.circle.badge.questionmark")
                            .font(.system(size: 10.5, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    Text(UsageText.status(for: entry))
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                }
                .foregroundStyle(entry.isAvailable && entry.usage?.problem != nil
                                 ? Desvan.Palette.warning : Desvan.Palette.paperSecondary)
                .help(help)
            }
            Spacer(minLength: 8)
            Toggle(entry.displayName, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var help: String {
        guard entry.isAvailable else {
            return UsageText.sentence(for: .notSignedIn, provider: entry.id, displayName: entry.displayName)
        }
        guard let usage = entry.usage, let problem = usage.problem else { return "" }
        let sentence = UsageText.sentence(for: problem, provider: entry.id, displayName: entry.displayName)
        return usage.problemDetail.map { "\(sentence) \($0)" } ?? sentence
    }
}
