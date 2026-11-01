import AltilloMail
import AppKit
import Foundation
import Observation

@MainActor
protocol NativeMailAuthenticating: AnyObject, Sendable {
    var availableServices: [NativeMailService] { get }
    func restoreAccounts() throws -> [NativeMailAccount]
    func connect(service: NativeMailService, replacing: NativeMailAccount?) async throws -> NativeMailAccount
    func accessToken(for account: NativeMailAccount, forceRefresh: Bool) async throws -> String
    func disconnect(account: NativeMailAccount) async throws
    func cancel()
}

extension MailAuthCoordinator: NativeMailAuthenticating {}

/// The direct-account inbox and reader. Email content lives only in this unlocked process session.
@MainActor
@Observable
final class NativeMailController {
    enum ConnectionState: Equatable {
        case paused, connecting, connected, refreshing, offline, reconnect, denied, throttled
    }

    private(set) var accounts: [NativeMailAccount] = []
    private(set) var messages: [NativeMailSummary] = []
    private(set) var states: [UUID: ConnectionState] = [:]
    private(set) var selectedMessage: NativeMailSummary?
    private(set) var selectedContent: NativeMailContent?
    private(set) var isReading = false
    private(set) var isConnecting = false
    private(set) var isRefreshing = false
    private(set) var problem: String?
    private(set) var readerProblem: String?
    var selectedAccountID: UUID?
    var isInboxVisible = false
    @ObservationIgnored var onArrival: (NativeMailSummary, NativeMailContent?) -> Void = { _, _ in }
    @ObservationIgnored var onContentCleared: () -> Void = {}
    @ObservationIgnored private let auth: any NativeMailAuthenticating
    @ObservationIgnored private let providerFactory: (@MainActor (NativeMailAccount) -> any NativeMailProvider)?
    @ObservationIgnored private let automaticPolling: Bool
    @ObservationIgnored private let bodyCache = NativeMailBodyCache()
    @ObservationIgnored private var hasPendingPages = false
    @ObservationIgnored private var synchronizers: [UUID: NativeMailSynchronizer] = [:]
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var generation: UInt = 0
    @ObservationIgnored private var retryAfter: [UUID: Date] = [:]
    @ObservationIgnored private var blocked: Set<UUID> = []

    init(auth: any NativeMailAuthenticating = MailAuthCoordinator(),
         providerFactory: (@MainActor (NativeMailAccount) -> any NativeMailProvider)? = nil, automaticPolling: Bool = true) {
        self.auth = auth
        self.providerFactory = providerFactory
        self.automaticPolling = automaticPolling
    }

    var availableServices: [NativeMailService] { auth.availableServices }
    var visibleMessages: [NativeMailSummary] {
        guard let selectedAccountID else { return messages }
        return messages.filter { $0.key.accountID == selectedAccountID }
    }
    var canRefresh: Bool { enabled && !suspended && !accounts.isEmpty && !isRefreshing }
    var isPaused: Bool { !enabled || suspended }

    func loadAccounts() {
        guard !loaded else { return }
        do {
            accounts = try auth.restoreAccounts()
            loaded = true
            for account in accounts { states[account.id] = .paused }
        } catch { problem = Self.explanation(error) }
    }

    @discardableResult
    func connect(_ service: NativeMailService, replacing account: NativeMailAccount? = nil) async -> Bool {
        guard !isConnecting else { return false }
        isConnecting = true
        problem = nil
        let stamp = generation
        defer { isConnecting = false }
        do {
            let connected = try await auth.connect(service: service, replacing: account)
            guard stamp == generation, !suspended, !Task.isCancelled else { return false }
            loadAccounts()
            accounts.removeAll { $0.id == connected.id }
            accounts.append(connected)
            accounts.sort { $0.address.localizedStandardCompare($1.address) == .orderedAscending }
            blocked.remove(connected.id)
            retryAfter[connected.id] = nil
            synchronizers[connected.id] = nil
            states[connected.id] = enabled && !suspended ? .connected : .paused
            if enabled && !suspended { restart() }
            return true
        } catch {
            guard stamp == generation, !suspended, !Task.isCancelled else { return false }
            if (error as? MailAuthFailure) != .cancelled { problem = Self.explanation(error) }
            return false
        }
    }

    func cancelConnection() { auth.cancel() }

    func disconnect(_ account: NativeMailAccount) async {
        // Invalidate all outstanding readers/refreshes before awaiting secure storage.
        pause()
        problem = nil
        do {
            try await auth.disconnect(account: account)
            accounts.removeAll { $0.id == account.id }
            states[account.id] = nil
            blocked.remove(account.id)
            retryAfter[account.id] = nil
            if selectedAccountID == account.id { selectedAccountID = nil }
        } catch { problem = Self.explanation(error) }
        if enabled && !suspended { restart() }
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        if enabled && !suspended {
            loadAccounts()
            restart()
        } else { pause() }
    }

    func setSuspended(_ suspended: Bool) {
        guard self.suspended != suspended else { return }
        self.suspended = suspended
        if suspended { pause() }
        else if enabled { restart() }
    }

    func refresh() async {
        guard canRefresh else { return }
        isRefreshing = true
        let stamp = generation
        hasPendingPages = false
        defer { if generation == stamp { isRefreshing = false } }
        for account in accounts {
            guard stamp == generation, enabled, !suspended, !Task.isCancelled else { return }
            guard !blocked.contains(account.id), retryAfter[account.id, default: .distantPast] <= .now else { continue }
            states[account.id] = .refreshing
            let synchronizer = synchronizer(for: account)
            do {
                let result = try await synchronizer.synchronize()
                guard stamp == generation, enabled, !suspended, !Task.isCancelled else { return }
                hasPendingPages = hasPendingPages || result.hasMore
                messages.removeAll { $0.key.accountID == account.id }
                messages.append(contentsOf: result.messages)
                messages.sort { $0.receivedAt > $1.receivedAt }
                states[account.id] = .connected
                retryAfter[account.id] = nil
                if let selected = selectedMessage, selected.key.accountID == account.id,
                   !result.messages.contains(where: { $0.key == selected.key }) { closeReader() }
                // Bound automatic body reads. Remaining arrivals still deliver their metadata immediately.
                let arrivals = Array(result.arrivals.prefix(20))
                for summary in arrivals.dropFirst(2) { onArrival(summary, nil) }
                for summary in arrivals.prefix(2) {
                    let content = try? await synchronizer.fetchContent(for: summary.key)
                    guard stamp == generation, enabled, !suspended, !Task.isCancelled else { return }
                    onArrival(summary, content)
                }
            } catch {
                guard stamp == generation, enabled, !suspended, !Task.isCancelled else { return }
                switch error {
                case NativeMailFailure.unauthorized, MailAuthFailure.reconnectRequired:
                    states[account.id] = .reconnect
                    blocked.insert(account.id)
                    await clearAccountContent(account.id, synchronizer: synchronizer)
                case NativeMailFailure.forbidden, MailAuthFailure.denied:
                    states[account.id] = .denied
                    blocked.insert(account.id)
                    await clearAccountContent(account.id, synchronizer: synchronizer)
                case NativeMailFailure.rateLimited(let delay):
                    states[account.id] = .throttled
                    retryAfter[account.id] = .now.addingTimeInterval(min(max(delay, 1), 86_400))
                default: states[account.id] = .offline
                }
            }
        }
    }

    func read(_ summary: NativeMailSummary) {
        guard enabled, !suspended, messages.contains(where: { $0.key == summary.key }),
              let account = accounts.first(where: { $0.id == summary.key.accountID }) else { return }
        readTask?.cancel()
        selectedMessage = summary
        selectedContent = nil
        readerProblem = nil
        isReading = true
        let stamp = generation
        let synchronizer = synchronizer(for: account)
        readTask = Task { [weak self] in
            do {
                let content = try await synchronizer.fetchContent(for: summary.key)
                guard let self, !Task.isCancelled, self.generation == stamp,
                      self.selectedMessage?.key == summary.key, self.enabled, !self.suspended else { return }
                self.selectedContent = content
                self.isReading = false
            } catch {
                guard let self, !Task.isCancelled, self.generation == stamp,
                      self.selectedMessage?.key == summary.key else { return }
                self.isReading = false
                self.readerProblem = Self.explanation(error)
            }
        }
    }

    private func clearAccountContent(_ id: UUID, synchronizer: NativeMailSynchronizer) async {
        messages.removeAll { $0.key.accountID == id }
        if selectedMessage?.key.accountID == id { closeReader() }
        onContentCleared()
        await synchronizer.reset()
    }

    func closeReader() {
        readTask?.cancel()
        readTask = nil
        selectedMessage = nil
        selectedContent = nil
        readerProblem = nil
        isReading = false
    }

    func accountName(for id: UUID) -> String { accounts.first { $0.id == id }?.address ?? "" }

    func openOriginal(_ summary: NativeMailSummary) {
        guard !isPaused, messages.contains(where: { $0.key == summary.key }), let url = summary.webURL,
              Self.isProviderURL(url, service: accounts.first(where: { $0.id == summary.key.accountID })?.service)
        else { return }
        NSWorkspace.shared.open(url)
    }

    func actionEnvelope(for summary: NativeMailSummary) -> MailEnvelope? {
        let age = Date.now.timeIntervalSince(summary.receivedAt)
        guard !isPaused, age >= -30, age < 300, messages.contains(where: { $0.key == summary.key }) else { return nil }
        let text = selectedMessage?.key == summary.key ? (selectedContent?.text ?? summary.preview) : summary.preview
        return MailEnvelope(messageID: "native@altillo.local", sender: summary.sender, subject: summary.subject,
                            body: text, receivedAt: summary.receivedAt.timeIntervalSince1970)
    }

    func copyCode(for summary: NativeMailSummary) {
        guard let code = actionEnvelope(for: summary)?.code else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.setString(code, forType: .string)
    }

    func openSignInLink(for summary: NativeMailSummary) {
        guard let url = actionEnvelope(for: summary)?.magicLink else { return }
        NSWorkspace.shared.open(url)
    }

    private func synchronizer(for account: NativeMailAccount) -> NativeMailSynchronizer {
        if let existing = synchronizers[account.id] { return existing }
        let token: NativeMailTokenLoader = { [auth] force in
            do { return try await auth.accessToken(for: account, forceRefresh: force) }
            catch is CancellationError { throw CancellationError() }
            catch MailAuthFailure.cancelled { throw CancellationError() }
            catch MailAuthFailure.denied { throw NativeMailFailure.forbidden }
            catch MailAuthFailure.reconnectRequired { throw NativeMailFailure.unauthorized }
            catch { throw NativeMailFailure.unavailable }
        }
        let provider: any NativeMailProvider
        if let providerFactory { provider = providerFactory(account) }
        else if account.service == .google { provider = GoogleNativeMailProvider(account: account, token: token) }
        else { provider = MicrosoftNativeMailProvider(account: account, token: token) }
        let value = NativeMailSynchronizer(provider: provider, cache: bodyCache)
        synchronizers[account.id] = value
        return value
    }

    private func restart() {
        pause()
        guard enabled, !suspended else { return }
        guard automaticPolling else { return }
        let stamp = generation
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, stamp == self.generation, self.enabled, !self.suspended else { return }
                await self.refresh()
                let delay = self.hasPendingPages ? 1 : (ProcessInfo.processInfo.isLowPowerModeEnabled ? 300 : (self.isInboxVisible ? 30 : 120))
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    private func pause() {
        generation &+= 1
        loop?.cancel()
        loop = nil
        auth.cancel()
        for synchronizer in synchronizers.values { Task { await synchronizer.reset() } }
        synchronizers.removeAll()
        messages.removeAll()
        closeReader()
        isRefreshing = false
        for account in accounts { states[account.id] = .paused }
        onContentCleared()
    }

    static func isProviderURL(_ url: URL, service: NativeMailService?) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        switch service {
        case .google: return host == "mail.google.com"
        case .microsoft: return ["outlook.office.com", "outlook.office365.com", "outlook.live.com"].contains(host)
        case nil: return false
        }
    }

    static func explanation(_ error: Error) -> String {
        switch error {
        case MailAuthFailure.notConfigured:
            String(localized: "Account connection isn't available in this build yet.")
        case MailAuthFailure.cancelled:
            String(localized: "Account connection was cancelled.")
        case MailAuthFailure.denied, NativeMailFailure.forbidden:
            String(localized: "Access was declined or blocked by your organization. Check its account permissions.")
        case MailAuthFailure.reconnectRequired, NativeMailFailure.unauthorized:
            String(localized: "Your mail session has expired. Reconnect this account.")
        case MailAuthFailure.accountMismatch:
            String(localized: "Choose the same account when reconnecting. Add a different account separately.")
        case MailAuthFailure.credentialStorage:
            String(localized: "Altillo couldn't update this account in Keychain. Please try again.")
        case NativeMailFailure.messageMissing:
            String(localized: "This message is no longer available in your inbox.")
        case NativeMailFailure.contentTooLarge:
            String(localized: "This message is too large to read here. Open the original with your provider.")
        case NativeMailFailure.rateLimited:
            String(localized: "Your mail provider asked Altillo to wait. It will retry automatically.")
        default:
            String(localized: "Mail couldn't connect. Check your internet connection and try again.")
        }
    }
}
