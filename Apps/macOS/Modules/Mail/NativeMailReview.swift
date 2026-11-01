#if DEBUG
import AltilloMail
import AppKit
import SwiftUI

/// Isolated visual QA: no real accounts, Keychain, network, hooks or other live modules.
@MainActor enum NativeMailReview {
    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "mailVisualReview") || Bundle.main.bundleIdentifier?.hasSuffix(".mail-review") == true
    }
    private static var window: NSWindow?
    static func show() {
        let account = NativeMailAccount(service: .google, remoteID: "visual-review", address: "preview@example.invalid")
        let provider = NativeMailReviewProvider(account: account)
        let controller = NativeMailController(auth: NativeMailReviewAuth(account: account), providerFactory: { _ in provider }, automaticPolling: false)
        controller.setEnabled(true)
        let store = MailStore(startsServer: false, native: controller)
        let name = "me.badia.altillo.mail-review." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let settings = AltilloSettings(defaults: defaults)
        settings.setEnabled(.mail, true)
        let root = VStack(spacing: 12) {
            Text(verbatim: "Visual review · synthetic accounts · nothing is sent")
                .font(.system(size: 11, weight: .semibold)).padding(.top, 12)
            TabView {
                DesvanNativeMailView(controller: controller)
                    .padding(12).tabItem { Text(verbatim: "Inbox") }
                ScrollView { SettingsMailGroup(settings: settings, store: store) }
                    .tabItem { Text(verbatim: "Settings") }
            }
        }
        .frame(width: 560, height: 530).preferredColorScheme(.dark)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 530),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Altillo — Mail visual review"
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { await controller.refresh() }
        // The preview retains its settings in memory only; never leave a persistent review profile.
        defaults.removePersistentDomain(forName: name)
    }
}

@MainActor private final class NativeMailReviewAuth: NativeMailAuthenticating {
    let account: NativeMailAccount
    init(account: NativeMailAccount) { self.account = account }
    var availableServices: [NativeMailService] { [.icloud, .imap] }
    func restoreAccounts() throws -> [NativeMailAccount] { [account] }
    func connect(service: NativeMailService, replacing: NativeMailAccount?) async throws -> NativeMailAccount { throw MailAuthFailure.notConfigured }
    func accessToken(for account: NativeMailAccount, forceRefresh: Bool) async throws -> String { throw MailAuthFailure.notConfigured }
    func disconnect(account: NativeMailAccount) async throws {}
    func cancel() {}
}

private actor NativeMailReviewProvider: NativeMailProvider {
    nonisolated let account: NativeMailAccount
    private var messages: [NativeMailSummary]
    init(account: NativeMailAccount) {
        self.account = account
        messages = [
            NativeMailSummary(key: .init(accountID: account.id, remoteID: "one"), sender: "Synthetic Sender <sender@example.invalid>",
                subject: "A sample message with an attachment", preview: "This is synthetic content for visual review.",
                receivedAt: .now, isUnread: true, rfcMessageID: "<preview@example.invalid>", replyTo: "reply@example.invalid"),
            NativeMailSummary(key: .init(accountID: account.id, remoteID: "two"), sender: "Synthetic Account",
                subject: "Verification code", preview: "Your verification code is 482913", receivedAt: .now.addingTimeInterval(-30))
        ]
    }
    func bootstrap(pageToken: String?) async throws -> NativeMailPage { .init(messages: messages, cursor: "preview", isFullSnapshot: true) }
    func changes(cursor: String, pageToken: String?) async throws -> NativeMailPage { try await bootstrap(pageToken: nil) }
    func fetchContent(for key: NativeMailMessageKey) async throws -> NativeMailContent {
        .init(key: key, text: "This synthetic email lets us review the real reader, reply composer and attachment controls.\n\nNo real account is connected and nothing can leave this preview.")
    }
    func attachments(for key: NativeMailMessageKey) async throws -> [NativeMailAttachment] {
        [.init(key: key, remoteID: "attachment", filename: "synthetic-notes.txt", mimeType: "text/plain", byteCount: 32)]
    }
    func send(_ draft: NativeMailDraft) async throws -> NativeMailSendReceipt {
        try NativeMailMIME.validateDraft(draft)
        return .init(remoteID: "synthetic-only")
    }
    func setRead(_ isRead: Bool, for key: NativeMailMessageKey) async throws {
        guard let index = messages.firstIndex(where: { $0.key == key }) else { return }
        let old = messages[index]
        messages[index] = .init(key: old.key, sender: old.sender, subject: old.subject, preview: old.preview,
            receivedAt: old.receivedAt, isUnread: !isRead, rfcMessageID: old.rfcMessageID, replyTo: old.replyTo)
    }
    func archive(_ key: NativeMailMessageKey) async throws { messages.removeAll { $0.key == key } }
    func trash(_ key: NativeMailMessageKey) async throws { messages.removeAll { $0.key == key } }
}
#endif
