import AltilloCore
import AppKit
import SwiftUI

/// One selected account per provider; replacing it clears the previous identity's readings and history.
struct UsageAccountSettings: View {
    let store: UsageStore?
    @State private var manager = UsageAccountManager.shared
    @AppStorage("usageSignInBrowser") private var browser = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Sign-in browser").font(.system(size: 11.5))
                Spacer(minLength: 8)
                Picker("Sign-in browser", selection: $browser) {
                    Text("System default").tag("system")
                    if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil {
                        Text(verbatim: "Google Chrome").tag("chrome")
                    }
                }
                .labelsHidden().frame(width: 155).controlSize(.small)
                .disabled(manager.connecting != nil)
            }
            ForEach([UsageProviderID.claude, .codex], id: \.self) { provider in
                row(provider)
            }
            Text("Connect in your browser. Altillo keeps its own session in this Mac’s Keychain; your CLI sessions stay separate.")
                .settingsHint()
            if let message = manager.errorMessage {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Desvan.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .task {
            if browser == "chrome", NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") == nil {
                browser = "system"
            }
            await manager.restore()
        }
    }

    private func row(_ provider: UsageProviderID) -> some View {
        let name = provider == .claude ? "Claude" : "Codex"
        let account = manager.accounts[provider]
        let entry = store?.entries.first { $0.id == provider }
        return HStack(spacing: 9) {
            AgentGlyph(provider: provider, name: name, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                if let account {
                    Text(account.label)
                        .font(.system(size: 11))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .lineLimit(1).truncationMode(.middle)
                        .privacySensitive()
                    if let entry {
                        Text(UsageText.status(for: entry))
                            .font(.system(size: 11))
                            .foregroundStyle(entry.usage?.problem == nil
                                             ? Desvan.Palette.paperSecondary : Desvan.Palette.warning)
                    }
                } else {
                    Text("Connect your account")
                        .font(.system(size: 11))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                }
            }
            Spacer(minLength: 8)
            if manager.connecting == provider {
                ProgressView().controlSize(.small)
                Button("Cancel") { manager.cancel() }.controlSize(.small)
            } else {
                Button(account == nil ? String(localized: "Connect…") : String(localized: "Reconnect…")) {
                    Task { await manager.connect(provider) }
                }
                .controlSize(.small)
                .disabled(manager.connecting != nil)
                if account != nil {
                    Menu {
                        Button("Disconnect") { Task { await manager.disconnect(provider) } }
                        Link("Open usage dashboard", destination: dashboard(provider))
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel(String(localized: "Account options"))
                    .disabled(manager.connecting != nil)
                    if let store {
                        Toggle(name, isOn: Binding(
                            get: { store.settings.isUsageProviderEnabled(provider) },
                            set: { store.settings.setUsageProvider(provider, enabled: $0) }
                        ))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func dashboard(_ provider: UsageProviderID) -> URL {
        URL(string: provider == .claude ? "https://claude.ai/settings/usage" : "https://chatgpt.com/codex/settings/usage")!
    }
}
