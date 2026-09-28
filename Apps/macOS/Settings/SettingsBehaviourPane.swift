import SwiftUI

/// How Altillo behaves: how it opens, whether it starts with you, and what the shelf does with what you leave in it.
struct SettingsBehaviourPane: View {
    @Bindable var settings: AltilloSettings
    let hasHardwareNotch: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reveal: Animation { SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion) }

    var body: some View {
        SettingsPane(
            title: "Behaviour",
            subtitle: "How Altillo opens, what it tells you on its own, and what the shelf does while you're not looking."
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    openingCard
                    screensCard
                    askCard
                    glancesCard
                    shelfCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Cards

    private var openingCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsGroupHeading(title: "Opening")
                SettingsCardDivider()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Open the shelf").settingsRowTitle()
                        Spacer(minLength: 12)
                        Picker(selection: $settings.opensOnHover) {
                            Text("On hover").tag(true)
                            Text("On click").tag(false)
                        } label: {
                            Text("Open the shelf")
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                        .horizontalRadioGroupLayout()
                        .controlSize(.small)
                        .fixedSize()
                        .help("Choose whether Altillo opens after a short hover or only after a click")
                    }
                    Text("On hover, the shelf opens after you rest the pointer on Altillo for a moment.")
                        .settingsHint()
                }

                SettingsCardDivider()

                VStack(alignment: .leading, spacing: 8) {
                    SettingsToggleRow("Open Altillo at login", isOn: $settings.launchAtLogin)
                        .help("Start Altillo automatically when you sign in to this Mac")

                    if let problem = settings.launchAtLoginProblem {
                        SettingsNotice(symbol: "exclamationmark.triangle.fill",
                                       message: LocalizedStringKey(problem),
                                       tone: .warning)
                            .transition(.settingsReveal)
                    }
                }
                .animation(reveal, value: settings.launchAtLoginProblem)

                SettingsCardDivider()

                SettingsToggleRow(
                    "Tap on the trackpad",
                    detail: "A light tap when you swipe between sections or something lands on the shelf.",
                    isOn: $settings.hapticsEnabled
                )
                .help("Use a light trackpad tap for section changes and shelf landings")
            }
        }
    }

    private var screensCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsGroupHeading(title: "Screens")
                SettingsCardDivider()

                BehaviourMenuRow(title: "Show Altillo on", hint: displayModeHint, selection: $settings.displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .help(displayModeHint)

                SettingsCardDivider()

                BehaviourMenuRow(title: "Over a full-screen app", hint: fullScreenHint,
                                 selection: $settings.fullScreenBehaviour) {
                    ForEach(FullScreenBehaviour.allCases) { behaviour in
                        Text(behaviour.title).tag(behaviour)
                    }
                }
                .help(fullScreenHint)
            }
            .animation(reveal, value: settings.displayMode)
            .animation(reveal, value: settings.fullScreenBehaviour)
        }
    }

    private var askCard: some View {
        let askIsOn = settings.isEnabled(.assistant)
        return SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsGroupHeading(title: "Ask")
                SettingsCardDivider()

                VStack(alignment: .leading, spacing: 8) {
                    BehaviourMenuRow(
                        title: "Shortcut to ask",
                        hint: askIsOn
                            ? "Opens Altillo on Ask from any app, ready to type. Press it again to close."
                            : "Turn on Ask in Sections to use a shortcut.",
                        selection: $settings.assistantHotKey
                    ) {
                        ForEach(AssistantHotKey.allCases) { key in
                            Text(key.title).tag(key)
                        }
                    }
                    .disabled(!askIsOn)
                    .help(askIsOn
                        ? "Choose the global keyboard shortcut that opens Ask"
                        : "Turn on Ask in Sections to use a shortcut")

                    if let problem = settings.assistantHotKeyProblem {
                        SettingsNotice(symbol: "exclamationmark.triangle.fill",
                                       message: LocalizedStringKey(problem),
                                       tone: .warning)
                            .transition(.settingsReveal)
                    }
                }
                .animation(reveal, value: settings.assistantHotKeyProblem)

                SettingsCardDivider()

                SettingsToggleRow("Let Ask search the web", detail: webSearchHint, isOn: $settings.assistantWebSearch)
                    .disabled(!askIsOn)
                    .opacity(askIsOn ? 1 : 0.55)
                    .help(webSearchHint)
            }
            .animation(reveal, value: askIsOn)
            .animation(reveal, value: settings.assistantWebSearch)
        }
    }

    private var glancesCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsGroupHeading(
                    title: "Automatic glances",
                    detail: """
                            Altillo expands a little for a few seconds and goes back on its own. Hover over it \
                            to keep it; click to open.
                            """
                )
                SettingsCardDivider()

                SettingsToggleRow("Five minutes before an event", isOn: $settings.alertsForCalendar)
                    .disabled(!settings.isEnabled(.calendar))
                    .opacity(settings.isEnabled(.calendar) ? 1 : 0.55)
                    .help("Show a short glance five minutes before a timed event")

                SettingsRowDivider(leading: 0)
                    .padding(.vertical, 8)

                SettingsToggleRow("When a new song starts", isOn: $settings.alertsForNowPlaying)
                    .disabled(!settings.isEnabled(.nowPlaying))
                    .opacity(settings.isEnabled(.nowPlaying) ? 1 : 0.55)
                    .help("Show a short glance when the track changes")
            }
        }
    }

    private var shelfCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsGroupHeading(title: "Shelf")
                SettingsCardDivider()

                BehaviourMenuRow(
                    title: "Clear the shelf on its own",
                    hint: """
                          Altillo takes off the shelf anything that's been there longer than you choose. \
                          Your original files are never touched.
                          """,
                    selection: $settings.shelfExpiry
                ) {
                    ForEach(ShelfExpiry.allCases) { expiry in
                        Text(expiry.title).tag(expiry)
                    }
                }
                .help("Choose when Altillo removes old shelf references; original files are never deleted")

                SettingsCardDivider()

                SettingsToggleRow(
                    "Show the hint when the shelf is empty",
                    detail: "It's the line that reminds you that you can drop files up here.",
                    isOn: $settings.showHintOnEmptyShelf
                )
                .help("Show the drop-files reminder when the shelf is empty")
            }
        }
    }

    // MARK: - Hints

    private var displayModeHint: LocalizedStringKey {
        switch settings.displayMode {
        case .notch:
            hasHardwareNotch
                ? "Uses the display with the hardware notch."
                : "No hardware notch found, so Altillo uses the display with the menu bar."
        case .main: "Uses the display with the menu bar."
        case .all: "Altillo appears on every screen. It opens on the one you're using."
        case .cursor: "Altillo moves to whichever screen the pointer is on."
        }
    }

    /// Honest about what leaves the Mac, in both states.
    private var webSearchHint: LocalizedStringKey {
        if settings.assistantWebSearch {
            """
            For live things like scores, news or prices, Ask writes a short search from your question and sends it \
            to DuckDuckGo (Bing if DuckDuckGo is busy), then reads the top pages it finds; for the weather, only the \
            place goes to Open-Meteo. No cookies, no account. Answers that used the web show a globe with their \
            sources.
            """
        } else {
            """
            Nothing leaves this Mac. When a question needs something live, Ask offers to search the web for that \
            question only, and you decide.
            """
        }
    }

    private var fullScreenHint: LocalizedStringKey {
        switch settings.fullScreenBehaviour {
        case .show: "Altillo behaves the same over videos, games and presentations."
        case .dragOnly: "Out of sight while you watch or present, but it still takes files you drag up to it."
        case .hide: "Out of sight entirely. The Ask shortcut still opens it."
        }
    }
}

/// A setting chosen from a menu: its title on the leading edge, the menu on the trailing one, what it does under both.
private struct BehaviourMenuRow<Selection: Hashable, Options: View>: View {
    let title: LocalizedStringKey
    let hint: LocalizedStringKey
    @Binding var selection: Selection
    @ViewBuilder var options: Options

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                Text(title).settingsRowTitle()
                Spacer(minLength: 12)
                Picker(selection: $selection) {
                    options
                } label: {
                    Text(title)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
            Text(hint)
                .settingsHint()
        }
    }
}
