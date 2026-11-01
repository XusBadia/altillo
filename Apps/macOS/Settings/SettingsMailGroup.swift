import AltilloMail
import AppKit
import SwiftUI

struct SettingsMailGroup: View {
    @Bindable var settings: AltilloSettings
    var store: MailStore?
    @State private var installer = MailRuleInstaller()
    @State private var needsAccountBeforeSwitching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroupHeading(title: "Mail accounts", detail: "Connect your account to read recent mail directly in Altillo.")
            if let native = store?.native { accounts(native) }
            SettingsCardDivider()
            Picker("Mail source", selection: Binding(get: { settings.mailConnectionMode }, set: { mode in
                if mode == .direct, settings.mailConnectionMode == .appleMail, store?.native?.accounts.isEmpty != false {
                    needsAccountBeforeSwitching = true
                } else {
                    needsAccountBeforeSwitching = false
                    settings.mailConnectionMode = mode
                }
            })) {
                Text("Connected accounts").tag(MailConnectionMode.direct)
                Text("Apple Mail compatibility").tag(MailConnectionMode.appleMail)
            }
            .pickerStyle(.menu)
            if needsAccountBeforeSwitching {
                Text("Connect an account above before switching from Apple Mail.").settingsHint()
            }
            if settings.mailConnectionMode == .appleMail {
                Text("Apple Mail is your current source. Connected accounts stay ready until you choose to switch.").settingsHint()
                legacySetup
            } else {
                Text("Recent inbox messages stay in memory while this Mac is unlocked. Locking, sleeping or disabling Mail clears them. Credentials stay in Keychain.").settingsHint()
                Text("Altillo connects directly to your provider. Reading here does not mark mail as read, and content is never sent to Ask.").settingsHint()
            }
            SettingsCardDivider()
            SettingsToggleRow("Show new-mail glances", isOn: $settings.alertsForMail)
            Text("Only new messages show a glance. Loading your existing inbox is silent.").settingsHint()
            Text("Glance filters").settingsRowTitle()
            Text("These filters choose which new messages show a glance. Your connected inbox still shows all recent messages.").settingsHint()
            TextField("Allowed sender addresses", text: $settings.mailAllowedSenders)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Allowed sender addresses")
            TextField("Allowed Mail account names", text: $settings.mailAllowedAccounts)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Allowed Mail account names")
            if let problem = store?.problem { Text(problem).settingsHint() }
            if settings.mailConnectionMode == .appleMail {
                if let problem = installer.problem { Text(problem).settingsHint() }
                HStack {
                    Button("Check script files") { Task { await installer.refresh() } }
                    Button("Clear recent messages") { store?.clear() }
                }
                .disabled(installer.isWorking)
                Button("Remove Altillo's Mail connection") {
                    settings.setEnabled(.mail, false)
                    store?.stop()
                    Task { await installer.uninstall() }
                }
                .disabled(installer.isWorking)
            } else if settings.isEnabled(.mail) {
                Button("Pause mail") { settings.setEnabled(.mail, false) }
            }
        }
        .padding(16)
        .task {
            store?.native?.loadAccounts()
            await installer.refresh()
        }
    }

    @ViewBuilder private func accounts(_ native: NativeMailController) -> some View {
        if native.accounts.isEmpty {
            Text("Add Google or Microsoft to see your inbox here. Apple Mail can stay closed.").settingsHint()
        } else {
            ForEach(native.accounts) { account in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: account.address).settingsRowTitle().lineLimit(1)
                        Text(stateTitle(native.states[account.id] ?? .paused)).settingsHint()
                    }
                    Spacer(minLength: 4)
                    if native.states[account.id] == .reconnect || native.states[account.id] == .denied || native.states[account.id] == .offline {
                        Button("Reconnect") { Task { await native.connect(account.service, replacing: account) } }
                    }
                    Button("Disconnect") { Task { await native.disconnect(account) } }
                }
                .disabled(native.isConnecting)
            }
            Text("Disconnecting removes this account and its credentials from Altillo. You can manage the provider's own permissions on its account website.").settingsHint()
        }
        if native.isConnecting {
            HStack {
                ProgressView().controlSize(.small)
                Text("Connecting your account…").settingsHint()
                Button("Cancel") { native.cancelConnection() }
            }
        } else if !native.availableServices.isEmpty {
            HStack {
                if native.availableServices.contains(.google) {
                    Button("Connect Google") { Task { await add(.google, to: native) } }
                }
                if native.availableServices.contains(.microsoft) {
                    Button("Connect Microsoft") { Task { await add(.microsoft, to: native) } }
                }
            }
            Text("Your provider opens its own sign-in screen. Altillo requests read access only.").settingsHint()
        } else {
            Text("Account connection isn't available in this build yet.").settingsHint()
        }
        if let problem = native.problem { Text(problem).settingsHint() }
        if settings.mailConnectionMode == .direct, !native.accounts.isEmpty, !settings.isEnabled(.mail) {
            Button("Resume mail") { settings.setEnabled(.mail, true) }
        }
    }

    private func add(_ service: NativeMailService, to native: NativeMailController) async {
        if await native.connect(service), settings.mailConnectionMode == .direct {
            settings.setEnabled(.mail, true)
        }
    }

    private var legacySetup: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(legacyStatus).settingsRowTitle()
            Text("Mail must stay open and receive messages. Altillo does not sign in to your email account.").settingsHint()
            if installer.status == .manualRemovalRequired {
                Text("After removing the rule, use Show scripts to remove Altillo Mail.scpt and Altillo Mail Bridge.scpt. Leave other scripts untouched.")
                    .settingsHint()
            } else {
                Text("1. Prepare the scripts. 2. In Mail Settings → Rules, add a rule named Altillo Mail for Every Message with Run AppleScript → Altillo Mail. 3. Choose Don't Apply for previous messages.")
                    .settingsHint()
            }
            HStack(spacing: 10) {
                Button("Prepare Mail scripts") { Task { await installer.prepare() } }
                Button("Show scripts") { installer.revealScripts() }
                Button("Open Apple Mail") { installer.openMailSettings() }
            }
            .disabled(installer.isWorking)
            if installer.isWorking { ProgressView().controlSize(.small) }
        }
    }

    private var legacyStatus: String {
        if installer.status == .prepared, store?.enabled == true, store?.lastReceivedAt != nil {
            return String(localized: "Apple Mail delivered a new message to Altillo.")
        }
        return installer.status.title
    }

    private func stateTitle(_ state: NativeMailController.ConnectionState) -> String {
        switch state {
        case .paused: String(localized: "Paused")
        case .connecting: String(localized: "Connecting…")
        case .connected: String(localized: "Connected")
        case .refreshing: String(localized: "Refreshing…")
        case .offline: String(localized: "Offline")
        case .reconnect: String(localized: "Reconnect this account")
        case .denied: String(localized: "Access is blocked")
        case .throttled: String(localized: "Waiting for your mail provider")
        }
    }
}
