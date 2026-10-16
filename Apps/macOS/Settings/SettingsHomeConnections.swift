import AltilloHome
import SwiftUI

/// Where a home's devices can come from, honestly (docs/casa-v2.md §4): a state and what to do, never a switch that
/// pretends. Home Assistant is the one real connection; the rest go through it, or through Shortcuts.
struct SettingsHomeConnections: View {
    let store: HomeStore
    /// "Set Up…" on the Home Assistant row: the Connect section's sign-in.
    let setUp: () -> Void

    @State private var confirmsDisconnect = false

    /// Integration guides on home-assistant.io.
    enum Guide {
        static let hue = URL(string: "https://www.home-assistant.io/integrations/hue/")!
        /// Google Home shares its Matter devices with HA (multi-admin).
        static let googleHome = URL(string: "https://www.home-assistant.io/integrations/matter/#sharing-a-device-from-another-platform-with-home-assistant")!
        static let alexa = URL(string: "https://www.home-assistant.io/integrations/alexa_devices/")!
        static let matter = URL(string: "https://www.home-assistant.io/integrations/matter/")!
        static let tuya = URL(string: "https://www.home-assistant.io/integrations/tuya/")!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSubheading("Connections")
            SettingsWell {
                homeAssistant
                SettingsRowDivider(leading: 40)
                SettingsHomeConnectionRow(symbol: "homekit", title: "Apple Home",
                                          detail: "Runs scenes through Shortcuts. The Mac can't read Home's state.") {
                    SettingsBadge(text: String(localized: "Coming soon"), tone: .neutral)
                        .help("Adding a Home shortcut as a tile comes in a later version. Meanwhile, the Shortcuts section runs it.")
                }
                SettingsRowDivider(leading: 40)
                SettingsHomeConnectionRow(symbol: "lightbulb.2.fill", title: "Philips Hue",
                                          detail: "Through Home Assistant today; direct pairing later.") {
                    guide(Guide.hue)
                }
                SettingsRowDivider(leading: 40)
                SettingsHomeConnectionRow(symbol: "house.and.flag.fill", title: "Google Home",
                                          detail: "Through Home Assistant.") {
                    guide(Guide.googleHome)
                }
                SettingsRowDivider(leading: 40)
                SettingsHomeConnectionRow(symbol: "speaker.wave.2.fill", title: "Alexa",
                                          detail: "Through Home Assistant.") {
                    guide(Guide.alexa)
                }
                SettingsRowDivider(leading: 40)
                SettingsHomeConnectionRow(symbol: "dot.radiowaves.left.and.right", title: "Matter",
                                          detail: "Through Home Assistant.") {
                    guide(Guide.matter)
                }
                SettingsRowDivider(leading: 40)
                SettingsHomeConnectionRow(symbol: "powerplug.fill", title: "Tuya", detail: "Through Home Assistant.") {
                    guide(Guide.tuya)
                }
            }
            Text("Altillo reads and controls your home through Home Assistant. Whatever Home Assistant has, Altillo can show.")
                .settingsHint()
        }
        .confirmationDialog("Disconnect from Home Assistant?", isPresented: $confirmsDisconnect) {
            Button("Disconnect", role: .destructive) { store.forget() }
        } message: {
            Text("Altillo forgets the token, your favourites and the doorbell. Nothing changes in Home Assistant.")
        }
    }

    private var homeAssistant: some View {
        SettingsHomeConnectionRow(symbol: "house.fill", title: "Home Assistant", detail: haDetail) {
            if store.isConnected {
                SettingsBadge(text: String(localized: "Connected"), symbol: "checkmark", tone: .good)
                Button("Disconnect…") { confirmsDisconnect = true }
                    .controlSize(.small)
            } else if store.settings.homeServer != nil {
                SettingsBadge(text: String(localized: "Not connected"), tone: .warning)
            } else {
                Button("Set Up…", action: setUp)
                    .controlSize(.small)
                    .disabled(store.isConnecting)
            }
        }
    }

    private var haDetail: LocalizedStringKey {
        store.isConnected ? "Lights, plugs, blinds, scenes and sensors, live." : "Not set up yet."
    }

    private func guide(_ url: URL) -> some View {
        Link(destination: url) {
            Text("Guide")
                .font(.system(size: 11.5, weight: .medium))
        }
        .help(Text(verbatim: url.absoluteString))
    }
}

private struct SettingsHomeConnectionRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let detail: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    init(symbol: String, title: String, detail: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Desvan.Palette.bulb)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                // Brand names stay as they are in every language.
                Text(verbatim: title).settingsRowTitle()
                Text(detail).settingsHint()
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) { trailing }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}
