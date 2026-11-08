import AltilloMail
import AppKit
import Foundation
import Observation

/// A short-lived inbox, only while the user has explicitly enabled Mail. No envelope is written to disk or Ask.
@MainActor
@Observable
final class MailStore {
    private(set) var messages: [MailEnvelope] = []
    private(set) var enabled = false
    private(set) var problem: String?
    private(set) var lastReceivedAt: Date?

    @ObservationIgnored var onMessage: (MailEnvelope) -> Void = { _ in }
    /// nil revokes every copied Mail presentation; an ID revokes that message only.
    @ObservationIgnored var onRevocation: (String?) -> Void = { _ in }
    @ObservationIgnored var now: () -> Date = { .now }
    @ObservationIgnored var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    @ObservationIgnored private let socketPath: String
    @ObservationIgnored private let startsServer: Bool
    @ObservationIgnored private var server: MailEventServer?
    @ObservationIgnored private var enabledSince = Date.distantFuture
    @ObservationIgnored private var senderFilters: [String] = []
    @ObservationIgnored private var accountFilters: [String] = []
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(socketPath: String = MailRuleInstaller.defaultSocketPath, startsServer: Bool = true) {
        self.socketPath = socketPath
        self.startsServer = startsServer
    }

    func configure(senders: String, accounts: String) {
        senderFilters = MailFilters.tokens(senders)
        accountFilters = MailFilters.tokens(accounts)
        let rejected = messages.filter { !accepts($0) }.map(\.messageID)
        messages.removeAll { !accepts($0) }
        rejected.forEach { onRevocation($0) }
        expire()
    }

    func update(enabled: Bool) {
        guard self.enabled != enabled else { return }
        if !enabled { stop(); return }
        self.enabled = true
        enabledSince = now()
        problem = nil
        observe()
        guard startsServer else { return }
        do {
            try MailRuleInstaller.ensurePrivateDirectory(URL(fileURLWithPath: socketPath).deletingLastPathComponent())
            let server = MailEventServer(path: socketPath) { [weak self] envelope in
                Task { @MainActor in self?.ingest(envelope) }
            }
            try server.start()
            self.server = server
        } catch {
            // Never include an error's associated payload/path in UI or diagnostics.
            problem = String(localized: "Mail couldn't start its local connection. Try turning Mail off and on again.")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        enabled = false
        suspended = false
        enabledSince = .distantFuture
        clear()
        problem = nil
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }

    func clear() {
        expiryTask?.cancel()
        expiryTask = nil
        messages.removeAll()
        lastReceivedAt = nil
        onRevocation(nil)
        // Reapplying a rule after clearing must not resurface old mail.
        if enabled { enabledSince = now() }
    }

    func dismiss(_ envelope: MailEnvelope) {
        let existed = messages.contains { $0.messageID == envelope.messageID }
        messages.removeAll { $0.messageID == envelope.messageID }
        if existed { onRevocation(envelope.messageID) }
        expire()
    }

    /// Also used by deterministic tests; all inputs still pass the same validation as socket events.
    func ingest(_ envelope: MailEnvelope) {
        let moment = now()
        guard enabled, !suspended, envelope.receivedAt >= enabledSince.timeIntervalSince1970,
              let bytes = try? JSONEncoder().encode(envelope),
              (try? MailEnvelope.decode(bytes, now: moment)) != nil,
              accepts(envelope), !messages.contains(where: { $0.messageID == envelope.messageID }) else { return }
        messages.insert(envelope, at: 0)
        if messages.count > 20 {
            let evicted = messages.suffix(messages.count - 20).map(\.messageID)
            messages.removeLast(messages.count - 20)
            evicted.forEach { onRevocation($0) }
        }
        lastReceivedAt = moment
        expire()
        onMessage(envelope)
    }

    func expire() {
        let moment = now()
        var expired: [String] = []
        messages.removeAll {
            let age = moment.timeIntervalSince1970 - $0.receivedAt
            guard age >= 300 || age < -30 else { return false }
            expired.append($0.messageID)
            return true
        }
        expired.forEach { onRevocation($0) }
        expiryTask?.cancel()
        expiryTask = nil
        guard let next = messages.map({ $0.receivedAt + 300 }).min() else { return }
        let delay = max(0, next - moment.timeIntervalSince1970)
        expiryTask = Task { [weak self, sleep] in
            do { try await sleep(.seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.expire()
        }
    }

    @discardableResult
    func copyCode(for envelope: MailEnvelope) -> Bool {
        guard let code = current(envelope)?.code else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        return pasteboard.setString(code, forType: .string)
    }

    @discardableResult
    func openMessage(for envelope: MailEnvelope) -> Bool {
        guard let url = current(envelope)?.messageURL else { return false }
        return NSWorkspace.shared.open(url)
    }

    @discardableResult
    func openLink(for envelope: MailEnvelope) -> Bool {
        guard let url = current(envelope)?.magicLink else { return false }
        return NSWorkspace.shared.open(url)
    }

    private func current(_ supplied: MailEnvelope) -> MailEnvelope? {
        expire()
        guard enabled else { return nil }
        // Only use the stored payload, never a supplied replacement with the same identifier.
        return messages.first { $0.messageID == supplied.messageID }
    }

    private func accepts(_ envelope: MailEnvelope) -> Bool {
        MailFilters.matchesSender(envelope.sender, allowed: senderFilters)
            && (accountFilters.isEmpty || accountFilters.contains(envelope.account.lowercased()))
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let suspend: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.setSuspended(true) }
        }
        let resume: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.setSuspended(false) }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification,
                                                          object: nil, queue: .main, using: suspend)))
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main, using: resume)))
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"),
                                                              object: nil, queue: .main, using: suspend)))
        observers.append((distributed, distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"),
                                                              object: nil, queue: .main, using: resume)))
        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.expire() }
        }))
    }

    func setSuspended(_ suspended: Bool) {
        self.suspended = suspended
        clear()
    }
}

enum MailFilters {
    static func tokens(_ input: String) -> [String] {
        Array(Set(input.components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })).sorted()
    }

    static func matchesSender(_ sender: String, allowed: [String]) -> Bool {
        guard !allowed.isEmpty else { return true }
        let lowered = sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let address: String
        if let start = lowered.lastIndex(of: "<"), lowered.hasSuffix(">") {
            address = String(lowered[lowered.index(after: start)..<lowered.index(before: lowered.endIndex)])
                .trimmingCharacters(in: .whitespaces)
        } else { address = lowered }
        return allowed.contains { token in
            if token.hasPrefix("@"), let at = address.lastIndex(of: "@") {
                return String(address[at...]) == token
            }
            return token == address || token == lowered
        }
    }
}
