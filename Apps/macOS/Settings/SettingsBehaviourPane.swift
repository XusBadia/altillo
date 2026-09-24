import SwiftUI

/// How Altillo behaves: how it opens, whether it starts with you, and what the shelf does with what you leave in it.
struct SettingsBehaviourPane: View {
    @Bindable var settings: AltilloSettings

    var body: some View {
        SettingsPane(
            title: "Behaviour",
            subtitle: "How the notch opens, what it tells you on its own, and what the shelf does while you're not looking."
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker(selection: $settings.opensOnHover) {
                                Text("On hover").tag(true)
                                Text("On click").tag(false)
                            } label: {
                                Text("Open the shelf")
                                    .font(Desvan.Typeface.rounded(13, weight: .medium))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .pickerStyle(.radioGroup)

                            Text("On hover, the shelf only opens if you rest a moment on the notch.")
                                .settingsHint()
                        }
                    }

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Screens")
                                .font(Desvan.Typeface.rounded(13, weight: .medium))
                                .foregroundStyle(Desvan.Palette.paper)

                            Picker(selection: $settings.displayMode) {
                                ForEach(DisplayMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            } label: {
                                Text("Show the notch on")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .pickerStyle(.menu)
                            .fixedSize()

                            Text(displayModeHint)
                                .settingsHint()

                            Divider().overlay(Desvan.Palette.hairline)

                            Picker(selection: $settings.fullScreenBehaviour) {
                                ForEach(FullScreenBehaviour.allCases) { behaviour in
                                    Text(behaviour.title).tag(behaviour)
                                }
                            } label: {
                                Text("Over a full-screen app")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .pickerStyle(.menu)
                            .fixedSize()

                            Text(fullScreenHint)
                                .settingsHint()
                        }
                    }

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $settings.launchAtLogin) {
                                Text("Open Altillo at login")
                                    .font(Desvan.Typeface.rounded(13, weight: .medium))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)

                            if let problem = settings.launchAtLoginProblem {
                                Label(problem, systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Desvan.Palette.warning)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Divider().overlay(Desvan.Palette.hairline)

                            Toggle(isOn: $settings.showHintOnEmptyShelf) {
                                Text("Show the hint when the shelf is empty")
                                    .font(Desvan.Typeface.rounded(13, weight: .medium))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)

                            Text("It's the line that reminds you that you can drop files up here.")
                                .settingsHint()
                        }
                    }

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker(selection: $settings.assistantHotKey) {
                                ForEach(AssistantHotKey.allCases) { key in
                                    Text(key.title).tag(key)
                                }
                            } label: {
                                Text("Shortcut to ask")
                                    .font(Desvan.Typeface.rounded(13, weight: .medium))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .pickerStyle(.menu)
                            .fixedSize()
                            .disabled(!settings.isEnabled(.assistant))

                            if let problem = settings.assistantHotKeyProblem {
                                Label(problem, systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Desvan.Palette.warning)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if settings.isEnabled(.assistant) {
                                Text("Opens the notch on Ask from any app, ready to type. Press it again to close.")
                                    .settingsHint()
                            } else {
                                Text("Turn on Ask in Sections to use a shortcut.")
                                    .settingsHint()
                            }

                            Divider().overlay(Desvan.Palette.hairline)

                            Toggle(isOn: $settings.assistantWebSearch) {
                                Text("Let Ask search the web")
                                    .font(Desvan.Typeface.rounded(13, weight: .medium))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(!settings.isEnabled(.assistant))

                            Text(webSearchHint)
                                .settingsHint()

                            Divider().overlay(Desvan.Palette.hairline)

                            Toggle(isOn: $settings.hapticsEnabled) {
                                Text("Tap on the trackpad")
                                    .font(Desvan.Typeface.rounded(13, weight: .medium))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)

                            Text("A light tap when you swipe between sections or something lands on the shelf.")
                                .settingsHint()
                        }
                    }

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Glance from the notch")
                                .font(Desvan.Typeface.rounded(13, weight: .medium))
                                .foregroundStyle(Desvan.Palette.paper)

                            Toggle(isOn: $settings.alertsForCalendar) {
                                Text("Five minutes before an event")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(!settings.isEnabled(.calendar))

                            Toggle(isOn: $settings.alertsForNowPlaying) {
                                Text("When a new song starts")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(!settings.isEnabled(.nowPlaying))

                            Text("""
                                 The notch grows a little for a few seconds and goes back on its own. Hover over it \
                                 to keep it; click to open.
                                 """)
                                .settingsHint()
                        }
                    }

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker(selection: $settings.shelfExpiry) {
                                ForEach(ShelfExpiry.allCases) { expiry in
                                    Text(expiry.title).tag(expiry)
                                }
                            } label: {
                                Text("Clear the shelf on its own")
                                    .font(Desvan.Typeface.rounded(13, weight: .medium))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .pickerStyle(.menu)
                            .fixedSize()

                            Text("""
                                 Altillo takes off the shelf anything that's been there longer than you choose. \
                                 Your original files are never touched.
                                 """)
                                .settingsHint()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var displayModeHint: LocalizedStringKey {
        switch settings.displayMode {
        case .notch: "On a Mac without a notch, it's the screen with the menu bar."
        case .main: "Only the screen with the menu bar, even if another one has a notch."
        case .all: "Each screen gets its own notch. It opens on the one you're using."
        case .cursor: "The notch moves to whichever screen the pointer is on."
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
        case .show: "The notch behaves the same over videos, games and presentations."
        case .dragOnly: "Out of sight while you watch or present, but it still takes files you drag up to it."
        case .hide: "Out of sight entirely. The Ask shortcut still opens it."
        }
    }
}
