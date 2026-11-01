import AltilloMail
import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
protocol NativeMailAuthenticating: AnyObject, Sendable {
    var availableServices: [NativeMailService] { get }
    func restoreAccounts() throws -> [NativeMailAccount]
    func connect(service: NativeMailService, replacing: NativeMailAccount?) async throws -> NativeMailAccount
    func accessToken(for account: NativeMailAccount, forceRefresh: Bool) async throws -> String
    func disconnect(account: NativeMailAccount) async throws
    func cancel()
    func connectServer(configuration: NativeMailServerConfiguration, password: String, service: NativeMailService,
                       replacing: NativeMailAccount?) async throws -> NativeMailAccount
    func serverCredentials(for account: NativeMailAccount) async throws -> NativeMailServerCredentials
}

extension NativeMailAuthenticating {
    func connectServer(configuration: NativeMailServerConfiguration, password: String, service: NativeMailService,
                       replacing: NativeMailAccount?) async throws -> NativeMailAccount { throw MailAuthFailure.notConfigured }
    func serverCredentials(for account: NativeMailAccount) async throws -> NativeMailServerCredentials { throw MailAuthFailure.notConfigured }
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
    private(set) var selectedAttachments: [NativeMailAttachment] = []
    private(set) var isComposing = false
    private(set) var isSending = false
    private(set) var isMutating = false
    private(set) var downloadingAttachmentID: String?
    private(set) var composeProblem: String?
    private(set) var actionStatus: String?
    var composeAccountID: UUID?
    var draftTo = ""
    var draftCc = ""
    var draftBcc = ""
    var draftSubject = ""
    var draftText = ""
    private(set) var draftAttachments: [NativeMailOutgoingAttachment] = []
    private(set) var replyingTo: NativeMailMessageKey?
    @ObservationIgnored private var replyMessageID: String?
    @ObservationIgnored private var operationTask: Task<Void, Error>?
    @ObservationIgnored private var sendTask: Task<NativeMailSendReceipt, Error>?
    @ObservationIgnored private var downloadTask: Task<Data, Error>?
    @ObservationIgnored private var providers: [UUID: any NativeMailProvider] = [:]
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
    var canRefresh: Bool { enabled && !suspended && !accounts.isEmpty && !isRefreshing && !isMutating && !isSending }
    var isPaused: Bool { !enabled || suspended }
    var composeNeedsReconnect: Bool { composeAccountID.map { blocked.contains($0) } ?? false }

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
            providers[connected.id] = nil
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

    func connectServer(configuration: NativeMailServerConfiguration, password: String, service: NativeMailService,
                       replacing account: NativeMailAccount? = nil) async -> Bool {
        guard !isConnecting else { return false }
        isConnecting = true
        problem = nil
        let stamp = generation
        defer { isConnecting = false }
        do {
            let connected = try await auth.connectServer(configuration: configuration, password: password,
                                                         service: service, replacing: account)
            guard stamp == generation, !suspended, !Task.isCancelled else { return false }
            loadAccounts()
            accounts.removeAll { $0.id == connected.id }
            accounts.append(connected)
            accounts.sort { $0.address.localizedStandardCompare($1.address) == .orderedAscending }
            blocked.remove(connected.id)
            retryAfter[connected.id] = nil
            synchronizers[connected.id] = nil
            providers[connected.id] = nil
            states[connected.id] = enabled ? .connected : .paused
            if enabled { restart() }
            return true
        } catch {
            guard stamp == generation, !suspended, !Task.isCancelled else { return false }
            if (error as? MailAuthFailure) != .cancelled { problem = Self.explanation(error) }
            return false
        }
    }

    func serverConfiguration(for account: NativeMailAccount) async -> NativeMailServerConfiguration? {
        try? await auth.serverCredentials(for: account).configuration
    }

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

    func read(_ supplied: NativeMailSummary) {
        guard enabled, !suspended, let summary = messages.first(where: { $0.key == supplied.key }),
              let account = accounts.first(where: { $0.id == summary.key.accountID }) else { return }
        readTask?.cancel()
        selectedMessage = summary
        selectedContent = nil
        selectedAttachments = []
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
                let attachments = try await self.provider(for: account).attachments(for: summary.key)
                guard attachments.count <= 100, attachments.allSatisfy({ $0.key == summary.key && $0.byteCount >= 0 }),
                      Set(attachments.map(\.remoteID)).count == attachments.count else { throw NativeMailFailure.invalidResponse }
                guard !Task.isCancelled, self.generation == stamp,
                      self.selectedMessage?.key == summary.key, self.enabled, !self.suspended else { return }
                self.selectedAttachments = attachments
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
        selectedAttachments = []
        readerProblem = nil
        isReading = false
    }

    func accountName(for id: UUID) -> String { accounts.first { $0.id == id }?.address ?? "" }

    func openOriginal(_ supplied: NativeMailSummary) {
        guard !isPaused, let summary = messages.first(where: { $0.key == supplied.key }), let url = summary.webURL,
              Self.isProviderURL(url, service: accounts.first(where: { $0.id == summary.key.accountID })?.service)
        else { return }
        NSWorkspace.shared.open(url)
    }

    func actionEnvelope(for supplied: NativeMailSummary) -> MailEnvelope? {
        guard let summary = messages.first(where: { $0.key == supplied.key }) else { return nil }
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

    enum MessageAction { case read(Bool), archive, trash }

    func perform(_ action: MessageAction, on supplied: NativeMailSummary) async {
        guard !isPaused, !isMutating, !isSending, !isRefreshing,
              let summary = messages.first(where: { $0.key == supplied.key }),
              let account = accounts.first(where: { $0.id == summary.key.accountID }),
              !blocked.contains(account.id) else { return }
        let stamp = generation
        isMutating = true
        problem = nil
        let provider = provider(for: account)
        let task = Task {
            switch action {
            case .read(let value): try await provider.setRead(value, for: summary.key)
            case .archive: try await provider.archive(summary.key)
            case .trash: try await provider.trash(summary.key)
            }
        }
        operationTask = task
        defer { if generation == stamp { isMutating = false; operationTask = nil } }
        do {
            try await task.value
            guard generation == stamp, !isPaused, !Task.isCancelled else { return }
            // Rebuild this account silently so provider flags and moves are authoritative.
            if let sync = synchronizers.removeValue(forKey: account.id) { await sync.reset() }
            guard generation == stamp, !isPaused else { return }
            switch action {
            case .read(let value):
                let updated = NativeMailSummary(key: summary.key, sender: summary.sender, subject: summary.subject,
                    preview: summary.preview, receivedAt: summary.receivedAt, isUnread: !value,
                    webURL: summary.webURL, rfcMessageID: summary.rfcMessageID, replyTo: summary.replyTo)
                if let index = messages.firstIndex(where: { $0.key == summary.key }) { messages[index] = updated }
                if selectedMessage?.key == summary.key { selectedMessage = updated }
            case .archive, .trash:
                messages.removeAll { $0.key == summary.key }
                if selectedMessage?.key == summary.key { closeReader() }
            }
            onContentCleared()
            actionStatus = String(localized: "Message updated.")
        } catch {
            guard generation == stamp, !isPaused, !Task.isCancelled else { return }
            problem = Self.explanation(error)
            if error as? NativeMailFailure == .unauthorized { states[account.id] = .reconnect; blocked.insert(account.id) }
            if error as? NativeMailFailure == .forbidden { states[account.id] = .denied; blocked.insert(account.id) }
            if blocked.contains(account.id) {
                if let sync = synchronizers[account.id] { await clearAccountContent(account.id, synchronizer: sync) }
            }
        }
    }

    func startCompose(replyingTo summary: NativeMailSummary? = nil) {
        guard !isPaused, !isSending, !isMutating, !accounts.isEmpty else { return }
        closeComposer()
        actionStatus = nil
        if let supplied = summary {
            guard let summary = messages.first(where: { $0.key == supplied.key }) else { return }
            composeAccountID = summary.key.accountID
            draftTo = Self.replyAddress(summary.replyTo ?? summary.sender)
            draftSubject = summary.subject.lowercased().hasPrefix("re:") ? summary.subject : "Re: " + summary.subject
            replyMessageID = summary.rfcMessageID.flatMap { $0.hasPrefix("<") ? $0 : "<" + $0 + ">" }
            replyingTo = summary.key
        } else { composeAccountID = selectedAccountID ?? accounts.first?.id }
        isComposing = true
    }

    func closeComposer() {
        isComposing = false
        draftTo = ""; draftCc = ""; draftBcc = ""; draftSubject = ""; draftText = ""
        draftAttachments = []
        replyingTo = nil; replyMessageID = nil; composeAccountID = nil; composeProblem = nil
    }

    func sendDraft() async {
        guard !isPaused, isComposing, !isSending, !isMutating, !isRefreshing,
              let account = accounts.first(where: { $0.id == composeAccountID }), !blocked.contains(account.id),
              replyingTo == nil || replyingTo?.accountID == account.id else { return }
        let draft = NativeMailDraft(to: Self.addresses(draftTo), cc: Self.addresses(draftCc), bcc: Self.addresses(draftBcc),
            subject: draftSubject, text: draftText, inReplyTo: replyMessageID, replyingTo: replyingTo, attachments: draftAttachments)
        do { try NativeMailMIME.validateDraft(draft) }
        catch { composeProblem = Self.explanation(error); return }
        let stamp = generation
        isSending = true
        composeProblem = nil
        let provider = provider(for: account)
        let task = Task { try await provider.send(draft) }
        sendTask = task
        defer { if generation == stamp { isSending = false; sendTask = nil } }
        do {
            let receipt = try await task.value
            guard generation == stamp, !isPaused, !Task.isCancelled else { return }
            closeComposer()
            actionStatus = receipt.sentCopySaved == false
                ? String(localized: "Message sent, but a copy couldn't be saved to Sent. Don't resend it.")
                : String(localized: "Your provider accepted the message for sending.")
        } catch {
            guard generation == stamp, !isPaused, !Task.isCancelled else { return }
            composeProblem = Self.explanation(error)
            if error as? NativeMailFailure == .unauthorized { states[account.id] = .reconnect; blocked.insert(account.id) }
            if error as? NativeMailFailure == .forbidden { states[account.id] = .denied; blocked.insert(account.id) }
            if blocked.contains(account.id), let sync = synchronizers[account.id] {
                await clearAccountContent(account.id, synchronizer: sync)
            }
        }
    }

    func chooseAttachments() {
        guard isComposing, !isPaused, !isSending else { return }
        let stamp = generation
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard let self, response == .OK, self.generation == stamp, self.isComposing, !self.isPaused else { return }
            do {
                var additions: [NativeMailOutgoingAttachment] = []
                var bytes = self.draftAttachments.reduce(0) { $0 + $1.data.count }
                guard panel.urls.count + self.draftAttachments.count <= 50 else { throw NativeMailFailure.contentTooLarge }
                for url in panel.urls {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
                    guard values.isRegularFile == true, let size = values.fileSize, size >= 0,
                          size <= 18 * 1_048_576 - bytes else { throw NativeMailFailure.contentTooLarge }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 18 * 1_048_576 - bytes else { throw NativeMailFailure.contentTooLarge }
                    bytes += data.count
                    additions.append(.init(filename: url.lastPathComponent, mimeType: values.contentType?.preferredMIMEType ?? "application/octet-stream", data: data))
                }
                try self.addDraftAttachments(additions)
                self.composeProblem = nil
            } catch { self.composeProblem = Self.explanation(error) }
        }
    }

    func removeDraftAttachment(_ id: UUID) { if !isSending { draftAttachments.removeAll { $0.id == id } } }

    func addDraftAttachments(_ additions: [NativeMailOutgoingAttachment]) throws {
        guard isComposing, !isPaused, !isSending else { throw NativeMailFailure.unsupportedOperation }
        let combined = draftAttachments + additions
        let total = combined.reduce(0) { $0 + $1.data.count }
        guard total <= 18 * 1_048_576 else { throw NativeMailFailure.contentTooLarge }
        try NativeMailMIME.validateDraft(.init(to: ["synthetic@example.invalid"], subject: "", text: "", attachments: combined))
        draftAttachments = combined
    }

    func saveAttachment(_ attachment: NativeMailAttachment) {
        guard !isPaused, downloadingAttachmentID == nil, selectedAttachments.contains(attachment),
              let account = accounts.first(where: { $0.id == attachment.key.accountID }) else { return }
        let stamp = generation
        let panel = NSSavePanel()
        panel.nameFieldStringValue = URL(fileURLWithPath: attachment.filename).lastPathComponent
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url,
                  self.generation == stamp, !self.isPaused, self.selectedAttachments.contains(attachment) else { return }
            self.downloadingAttachmentID = attachment.remoteID
            let provider = self.provider(for: account)
            let task = Task { try await provider.download(attachment) }
            self.downloadTask = task
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { if self.generation == stamp { self.downloadingAttachmentID = nil; self.downloadTask = nil } }
                do {
                    let data = try await task.value
                    guard self.generation == stamp, !self.isPaused, self.selectedAttachments.contains(attachment) else { return }
                    guard data.count <= NativeMailMIME.attachmentDownloadByteLimit else { throw NativeMailFailure.contentTooLarge }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try MailAttachmentSaver.save(data, to: url)
                    self.actionStatus = String(localized: "Attachment saved.")
                } catch {
                    guard self.generation == stamp, !self.isPaused else { return }
                    self.readerProblem = Self.explanation(error)
                }
            }
        }
    }

    static func addresses(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == ";" }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func replyAddress(_ sender: String) -> String {
        if let start = sender.lastIndex(of: "<"), let end = sender.lastIndex(of: ">"), start < end {
            return String(sender[sender.index(after: start)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return sender.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func synchronizer(for account: NativeMailAccount) -> NativeMailSynchronizer {
        if let existing = synchronizers[account.id] { return existing }
        let value = NativeMailSynchronizer(provider: provider(for: account), cache: bodyCache)
        synchronizers[account.id] = value
        return value
    }

    private func provider(for account: NativeMailAccount) -> any NativeMailProvider {
        if let existing = providers[account.id] { return existing }
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
        else if account.service == .microsoft { provider = MicrosoftNativeMailProvider(account: account, token: token) }
        else {
            provider = IMAPNativeMailProvider(account: account, credentials: { [auth] in
                try await auth.serverCredentials(for: account)
            })
        }
        providers[account.id] = provider
        return provider
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
        operationTask?.cancel()
        operationTask = nil
        sendTask?.cancel()
        sendTask = nil
        downloadTask?.cancel()
        downloadTask = nil
        downloadingAttachmentID = nil
        isSending = false
        isMutating = false
        closeComposer()
        actionStatus = nil
        for synchronizer in synchronizers.values { Task { await synchronizer.reset() } }
        synchronizers.removeAll()
        providers.removeAll()
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
        case .icloud, .imap, nil: return false
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
            String(localized: "This message or attachment exceeds Altillo's size limit.")
        case NativeMailFailure.rateLimited:
            String(localized: "Your mail provider asked Altillo to wait. Try again later.")
        case NativeMailFailure.invalidDraft:
            String(localized: "Check the recipient addresses and attachment names before sending.")
        case NativeMailFailure.unsupportedOperation:
            String(localized: "This server doesn't support that action. Open your provider to finish it.")
        case NativeMailFailure.deliveryUncertain:
            String(localized: "The server may have accepted this message. Check Sent before trying again to avoid sending it twice.")
        case MailAttachmentSaveFailure.failed:
            String(localized: "The attachment couldn't be saved. Choose another location and try again.")
        default:
            String(localized: "Mail couldn't connect. Check your internet connection and try again.")
        }
    }
}
