import AppKit
import SwiftUI

struct SettingsMailGroup: View {
    @Bindable var settings: AltilloSettings
    var store: MailStore?
    @State private var installer = MailRuleInstaller()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroupHeading(title: "Apple Mail", detail: "Mail must stay open and receive messages. Altillo does not sign in to your email account.")
            SettingsToggleRow("Show new-mail glances", isOn: $settings.alertsForMail)
            Text("Messages stay in memory for five minutes. Codes and sign-in links are never saved to history or sent to Ask.")
                .settingsHint()
            SettingsCardDivider()
            setup
            SettingsCardDivider()
            Text("Message filters").settingsRowTitle()
            Text("Leave these empty for all new messages. Separate exact addresses or account names with commas.").settingsHint()
            TextField("Allowed sender addresses", text: $settings.mailAllowedSenders)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Allowed sender addresses")
            TextField("Allowed Mail account names", text: $settings.mailAllowedAccounts)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Allowed Mail account names")
            if let problem = store?.problem { Text(problem).settingsHint() }
            if let problem = installer.problem { Text(problem).settingsHint() }
            HStack {
                Button("Check Mail rule") { Task { await installer.refresh() } }
                Button("Clear recent messages") { store?.clear() }
            }
            .disabled(installer.isWorking)
            Text("Disabling this section stops reception and clears its messages. Remove the Mail rule below to disconnect completely.")
                .settingsHint()
            Button("Remove Altillo's Mail connection") {
                settings.setEnabled(.mail, false)
                store?.stop()
                Task { await installer.uninstall() }
            }
            .disabled(installer.isWorking)
        }
        .padding(16)
        .task { await installer.refresh() }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(status).settingsRowTitle()
            Text("1. Prepare the scripts. 2. In Mail Settings → Rules, add a rule named Altillo Mail for Every Message with Run AppleScript → Altillo Mail. 3. Choose Don't Apply for previous messages.")
                .settingsHint()
            Text("Use the filters below to choose senders and accounts. The Mail rule delivers new messages to Altillo on this Mac.").settingsHint()
            HStack(spacing: 10) {
                Button("Prepare Mail scripts") { Task { await installer.prepare() } }
                Button("Show scripts") { installer.revealScripts() }
                Button("Open Apple Mail") { installer.openMailSettings() }
            }
            .disabled(installer.isWorking)
            if installer.isWorking { ProgressView().controlSize(.small) }
        }
    }

    private var status: String { installer.status.title }
}
