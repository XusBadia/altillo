import AltilloCore
import SwiftUI

/// Which sections the open notch shows, in what order, and what sits in the ears beside it. Everything here changes
/// the notch live; the same things (and more directly) can be done in the notch itself, in edit mode.
struct SettingsModulesPane: View {
    @Bindable var settings: AltilloSettings
    let hasHardwareNotch: Bool
    /// Keeps what a preset replaced, for its Undo.
    @State private var session = NotchEditSession()

    private var disabled: [NotchModule] {
        NotchModule.allCases.filter { !settings.isEnabled($0) }
    }

    var body: some View {
        SettingsPane(
            title: "Sections",
            subtitle: "Choose what Altillo shows while it's closed and when you open it."
        ) {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            SettingsGroupHeading(
                                title: "While Altillo is closed",
                                detail: hasHardwareNotch
                                    ? "On this display, the indicators sit beside the hardware notch."
                                    : "On this display, the indicators sit inside Altillo's small island."
                            )
                            SettingsCardDivider()
                            SettingsEarsRow(settings: settings, session: session,
                                            hasHardwareNotch: hasHardwareNotch)
                        }
                    }

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            SettingsGroupHeading(
                                title: "Sections in Altillo",
                                detail: "Drag a row to change the order. Shelf always stays first."
                            )
                            SettingsCardDivider()
                            VStack(spacing: 0) {
                                ForEach(settings.modules) { module in
                                    SettingsModuleRow(module: module, settings: settings)
                                        .draggable(module.rawValue)
                                        .dropDestination(for: String.self) { identifiers, _ in
                                            _ = reorder(identifiers.first, before: module)
                                        }
                                    if module != settings.modules.last { SettingsRowDivider() }
                                }
                            }
                        }
                    }

                    if settings.isEnabled(.calendar) {
                        SettingsOptionsCard(
                            title: "Calendar",
                            detail: "Layout, all-day events and visible calendars.",
                            symbol: NotchModule.calendar.symbol
                        ) {
                            SettingsCalendarGroup(settings: settings)
                        }
                        .id(Self.calendarAnchor)
                    }

                    if settings.isEnabled(.usage) {
                        SettingsOptionsCard(
                            title: "Usage",
                            detail: "Providers, limits and alerts.",
                            symbol: NotchModule.usage.symbol
                        ) {
                            SettingsUsageGroup(settings: settings, store: UsageStore.live)
                        }
                        .id(Self.usageAnchor)
                    }

                    // Always here, even with the agents section put away: hooks Altillo installed must stay one
                    // click from removal.
                    SettingsOptionsCard(
                        title: "Agents",
                        detail: "Connections, replies and permission timing.",
                        symbol: NotchModule.agents.symbol
                    ) {
                        SettingsAgentsGroup(settings: settings)
                    }
                    .id(Self.agentsAnchor)

                    if !disabled.isEmpty {
                        SettingsCard {
                            VStack(alignment: .leading, spacing: 0) {
                                SettingsGroupHeading(
                                    title: "More sections",
                                    detail: "Turn one on to add it to the end of Altillo."
                                )
                                SettingsCardDivider()
                                VStack(spacing: 0) {
                                    ForEach(disabled) { module in
                                        SettingsModuleRow(module: module, settings: settings)
                                        if module != disabled.last { SettingsRowDivider() }
                                    }
                                }
                            }
                        }
                    }

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            SettingsGroupHeading(
                                title: "Start with a layout",
                                detail: "Reset to a simple starting point, then make it yours. You can undo it right away."
                            )
                            SettingsCardDivider()
                            SettingsPresetsRow(settings: settings, session: session)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .scrollBounceBehavior(.basedOnSize)
            .task {
                // `-settingsSection calendar|usage|agents` (with `-settingsTab modules`) opens scrolled to that group.
                // Once more after the rows above have measured themselves, or it stops short.
                if let anchor = UserDefaults.standard.string(forKey: "settingsSection"),
                   [Self.calendarAnchor, Self.usageAnchor, Self.agentsAnchor].contains(anchor) {
                    proxy.scrollTo(anchor, anchor: .top)
                    try? await Task.sleep(for: .milliseconds(400))
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
            }
        }
    }

    private func reorder(_ rawValue: String?, before target: NotchModule) -> Bool {
        guard let rawValue, let dragged = NotchModule(rawValue: rawValue),
              dragged != target,
              !dragged.isAlwaysOn,
              let source = settings.modules.firstIndex(of: dragged),
              let destination = settings.modules.firstIndex(of: target)
        else { return false }
        settings.move(
            fromOffsets: IndexSet(integer: source),
            toOffset: destination > source ? destination + 1 : destination
        )
        return true
    }

    private static let calendarAnchor = "calendar"
    private static let usageAnchor = "usage"
    private static let agentsAnchor = "agents"
}

private struct SettingsGroupHeading: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Desvan.Typeface.rounded(13, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paper)
            Text(detail).settingsHint()
        }
    }
}

private struct SettingsCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Desvan.Palette.hairline)
            .frame(height: 0.75)
            .padding(.vertical, 10)
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Desvan.Palette.hairline)
            .frame(height: 0.75)
            .padding(.leading, 52)
    }
}

private struct SettingsOptionsCard<Content: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    @ViewBuilder var content: Content
    @State private var isExpanded = false

    var body: some View {
        SettingsCard {
            DisclosureGroup(isExpanded: $isExpanded) {
                SettingsCardDivider()
                content
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Desvan.Palette.bulb)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Desvan.Palette.plank.opacity(0.85)))
                    SettingsGroupHeading(title: title, detail: detail)
                }
                .contentShape(Rectangle())
            }
            .tint(Desvan.Palette.paperSecondary)
            .help(isExpanded ? "Hide these options" : "Show these options")
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
                Button("Customize Altillo…") {
                    NotificationCenter.default.post(name: .altilloCustomizeNotch, object: nil)
                }
                .help("Opens Altillo in edit mode so you can drag sections and side indicators directly.")
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
    let hasHardwareNotch: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsEarsPreview(leftEar: settings.leftEar, rightEar: settings.rightEar,
                                visibility: settings.earsVisibility, hasHardwareNotch: hasHardwareNotch)
            HStack(alignment: .top, spacing: 10) {
                sidePicker(.left, title: "Left side", symbol: "arrow.left")
                sidePicker(.right, title: "Right side", symbol: "arrow.right")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Visibility")
                    .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                Picker(selection: visibility) {
                    Text("When active").tag(EarsVisibility.withActivity)
                    Text("Always visible").tag(EarsVisibility.always)
                } label: {
                    Text("Visibility")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(visibilityExplanation)
                    .settingsHint()
            }
            Text("Tip: What matters now can temporarily show music, an urgent event or an agent that needs you. Choosing the same item twice swaps the two sides.")
                .settingsHint()
        }
    }

    private var visibility: Binding<EarsVisibility> {
        Binding(get: { settings.earsVisibility }, set: { _ = session.setVisibility($0, in: settings) })
    }

    private func sidePicker(_ side: EarSide, title: LocalizedStringKey, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperSecondary)
            earPicker(side)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(earExplanation(session.ear(side, in: settings)))
                .settingsHint()
                .frame(minHeight: 28, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Desvan.Palette.plank.opacity(0.55))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
        }
        .help(side == .left
            ? "This appears on the left side of Altillo while it is closed."
            : "This appears on the right side of Altillo while it is closed.")
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
        .help("Choose what this side shows while Altillo is closed")
    }

    private var visibilityExplanation: LocalizedStringKey {
        switch settings.earsVisibility {
        case .withActivity: "The sides stay hidden until a selected item has current information."
        case .always: "The sides remain visible; inactive items stay dim."
        }
    }

    private func earExplanation(_ content: EarContent) -> LocalizedStringKey {
        switch content {
        case .none: "This side stays empty."
        case .automatic: "Shows the most relevant activity from your enabled sections."
        case .shelf: "Shows the number of shelf items; inactive when the shelf is empty."
        case .nextEvent: "Shows the next timed event today; all-day events don't appear here."
        case .nowPlaying: "Shows an equaliser while music, a podcast or a video is playing."
        case .usage: "Shows the AI limit that is closest to running out."
        case .agents: "Shows active agents and requests that need your attention."
        }
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
        .help(module.explanation)
        .contextMenu {
            if settings.isEnabled(module), !module.isAlwaysOn {
                if let index = settings.modules.firstIndex(of: module), index > 1 {
                    Button("Move Earlier", systemImage: "arrow.up") {
                        settings.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                    }
                }
                if let index = settings.modules.firstIndex(of: module), index < settings.modules.count - 1 {
                    Button("Move Later", systemImage: "arrow.down") {
                        settings.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                    }
                }
            }
        }
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
            Text("Right-click Altillo while Calendar is open to switch layout from there.")
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

/// The usage section's own settings: which providers it reads (with how each one is doing) and when it peeks.
/// Altillo reads every provider itself; the list scales to many of them by showing only the ones set up on this
/// Mac, each with its switch (on until switched off), and folding the rest into "Not set up on this Mac" with one
/// line on how to set each up.
private struct SettingsUsageGroup: View {
    @Bindable var settings: AltilloSettings
    /// The running app's store; nil only in previews.
    let store: UsageStore?

    @State private var showsNotSetUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            providers
            alerts
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
            let setUp = store?.setUpEntries ?? []
            let notSetUp = store?.notSetUpEntries ?? []
            if setUp.isEmpty {
                Text(store?.hasChecked == true
                     ? "None of the AI tools Altillo reads is set up on this Mac yet. Set one up and it shows up here."
                     : "Looking for your AI tools…")
                    .settingsHint()
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(setUp) { entry in
                        SettingsUsageProviderRow(entry: entry, settings: settings)
                    }
                }
            }
            if !notSetUp.isEmpty {
                notSetUpList(notSetUp)
            }
            if !setUp.isEmpty || !notSetUp.isEmpty {
                Text("Altillo reads the sign-in or key your tools already have on this Mac. It never signs in, refreshes or changes anything, and your numbers never leave this Mac.")
                    .settingsHint()
            }
        }
    }

    /// The providers Altillo can read that aren't set up here, folded away: each with how to set it up.
    private func notSetUpList(_ entries: [UsageStore.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) {
                    showsNotSetUp.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .rotationEffect(.degrees(showsNotSetUp ? 90 : 0))
                        .accessibilityHidden(true)
                    Text("Not set up on this Mac")
                        .font(.system(size: 12, weight: .medium))
                    Text(verbatim: "\(entries.count)")
                        .font(Desvan.Typeface.rounded(11, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .frame(height: 15)
                        .background(Capsule().fill(Desvan.Palette.woodRaised))
                }
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(showsNotSetUp ? "Expanded" : "Collapsed"))
            if showsNotSetUp {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(entries) { entry in
                        SettingsUsageSetupRow(entry: entry)
                    }
                }
                .padding(.leading, 14)
                .transition(.opacity)
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
        HStack(spacing: 9) {
            AgentGlyph(provider: entry.id, name: entry.displayName, size: 20)
                .opacity(entry.isAvailable ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.displayName)
                    .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if hasProblem {
                        Image(systemName: entry.isAvailable ? "exclamationmark.triangle.fill" : "person.crop.circle.badge.questionmark")
                            .font(.system(size: 10.5, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    Text(UsageText.status(for: entry))
                        .font(.system(size: 11))
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
        .padding(.vertical, 1)
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

/// A provider Altillo can read that isn't set up on this Mac: its mark, dimmed, its name and how to set it up (a
/// collector's hint may put a command in `backticks`; it shows in monospace).
private struct SettingsUsageSetupRow: View {
    let entry: UsageStore.Entry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AgentGlyph(provider: entry.id, name: entry.displayName, size: 16)
                .opacity(0.55)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.displayName)
                    .font(Desvan.Typeface.rounded(12, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .lineLimit(1)
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var hint: AttributedString {
        let text = entry.setupHint.isEmpty
            ? String(localized: "Set it up on this Mac and it shows up here.")
            : UsageText.setupHint(for: entry.id, fallback: entry.setupHint)
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
