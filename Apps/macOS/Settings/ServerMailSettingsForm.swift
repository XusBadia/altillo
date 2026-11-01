import AltilloMail
import AppKit
import SwiftUI

struct ServerMailSettingsForm: View {
    let native: NativeMailController
    let service: NativeMailService
    var replacing: NativeMailAccount?
    var onConnected: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var imapHost = ""
    @State private var imapPort = "993"
    @State private var smtpHost = ""
    @State private var smtpPort = "587"
    @State private var smtpSecurity: NativeMailSMTPSecurity = .startTLS
    @State private var saveSentCopy = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(service == .icloud ? String(localized: "Connect iCloud Mail") : String(localized: "Connect IMAP and SMTP"))
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                field("Email address", text: $address)
                field("Account name", text: $displayName)
                field("Login username", text: $username)
                VStack(alignment: .leading, spacing: 4) {
                    let title = service == .icloud ? String(localized: "App-specific password") : String(localized: "Password or app password")
                    Text(title).font(.caption)
                    SecureField(title, text: $password).labelsHidden().accessibilityLabel(Text(title))
                }
                if service == .icloud {
                    Text("Use an app-specific password from your Apple Account. Your normal Apple Account password won't work here.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Link("Create an app-specific password", destination: URL(string: "https://account.apple.com/")!)
                    Text("iCloud's incoming and outgoing servers are configured for you. For a custom domain, use your iCloud login as the username.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack {
                        field("IMAP server", text: $imapHost)
                        field("IMAP port", text: $imapPort).frame(width: 90)
                    }
                    HStack {
                        field("SMTP server", text: $smtpHost)
                        field("SMTP port", text: $smtpPort).frame(width: 90)
                    }
                    Picker("Outgoing encryption", selection: $smtpSecurity) {
                        Text("STARTTLS (usually 587)").tag(NativeMailSMTPSecurity.startTLS)
                        Text("TLS (usually 465)").tag(NativeMailSMTPSecurity.implicitTLS)
                    }
                    Text("Incoming mail always uses TLS. Outgoing mail requires TLS or STARTTLS. Use Google or Microsoft sign-in for those providers.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Save a copy in Sent using IMAP", isOn: $saveSentCopy)
                Text("Turn this off if your outgoing server already saves sent messages.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .textFieldStyle(.roundedBorder)
            .disabled(native.isConnecting)
            if let problem = native.problem { Text(problem).font(.caption).foregroundStyle(.secondary) }
            HStack {
                if native.isConnecting { ProgressView().controlSize(.small); Text("Checking incoming and outgoing mail…").font(.caption) }
                Spacer()
                Button("Cancel") { native.cancelConnection(); password = ""; dismiss() }
                Button("Connect") { Task { await connect() } }
                    .disabled(native.isConnecting || address.isEmpty || password.isEmpty || service == .imap && (imapHost.isEmpty || smtpHost.isEmpty))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 490)
        .task {
            guard let replacing else { return }
            address = replacing.address
            displayName = replacing.displayName
            guard let config = await native.serverConfiguration(for: replacing) else { return }
            username = config.username; imapHost = config.imapHost; imapPort = String(config.imapPort)
            smtpHost = config.smtpHost; smtpPort = String(config.smtpPort); smtpSecurity = config.smtpSecurity
            saveSentCopy = config.saveSentCopy
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in clearPassword() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .init("com.apple.screenIsLocked"))) { _ in clearPassword() }
        .onDisappear { password = ""; if native.isConnecting { native.cancelConnection() } }
    }

    private func clearPassword() { password = ""; native.cancelConnection() }

    private func field(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            TextField(title, text: text).labelsHidden().accessibilityLabel(Text(title))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func connect() async {
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuration: NativeMailServerConfiguration
        if service == .icloud {
            var cloud = NativeMailServerConfiguration.icloud(address: cleanAddress, username: cleanUsername.isEmpty ? cleanAddress : cleanUsername)
            cloud.displayName = displayName
            cloud.saveSentCopy = saveSentCopy
            configuration = cloud
        } else {
            configuration = .init(address: cleanAddress, username: cleanUsername.isEmpty ? cleanAddress : cleanUsername,
                displayName: displayName, imapHost: imapHost.trimmingCharacters(in: .whitespacesAndNewlines), imapPort: Int(imapPort) ?? 0,
                smtpHost: smtpHost.trimmingCharacters(in: .whitespacesAndNewlines), smtpPort: Int(smtpPort) ?? 0,
                smtpSecurity: smtpSecurity, saveSentCopy: saveSentCopy)
        }
        let credential = password
        password = ""
        if await native.connectServer(configuration: configuration, password: credential, service: service, replacing: replacing) {
            onConnected()
            dismiss()
        }
    }
}
