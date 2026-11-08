import AltilloCore
import AltilloUsage
import Foundation
import Observation
import Security

struct UsageAccountSummary: Equatable, Sendable, Identifiable {
    let id: UUID
    let provider: UsageProviderID
    let label: String
}

struct UsageAccountRecord: Codable, Equatable, Sendable {
    var version = 1
    var id = UUID()
    var provider: UsageProviderID
    var label: String
    var remoteID: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var accountID: String?
    var subscriptionType: String?
    var rateLimitTier: String?

    var summary: UsageAccountSummary { .init(id: id, provider: provider, label: label) }
}

enum UsageAccountFailure: Error, Equatable, LocalizedError {
    case cancelled, unsupported, operationInProgress, storage, invalidResponse, sessionExpired, unavailable
    case callbackPortBusy
    case temporary(Int)

    var errorDescription: String? {
        switch self {
        case .cancelled: return String(localized: "Sign-in cancelled.")
        case .unsupported: return String(localized: "This provider does not support account sign-in here.")
        case .operationInProgress: return String(localized: "Another account is already connecting.")
        case .storage: return String(localized: "The account could not be saved in this Mac’s private Keychain. Try again when the Mac is unlocked.")
        case .invalidResponse: return String(localized: "The provider returned an unexpected sign-in response.")
        case .sessionExpired: return String(localized: "Reconnect this account in Altillo Settings.")
        case .unavailable: return String(localized: "The provider could not be reached. Try again later.")
        case .callbackPortBusy: return String(localized: "Port 1455 is in use. Finish the other Codex sign-in and try again.")
        case .temporary(let status): return String(localized: "The provider is temporarily unavailable (HTTP \(status)). Try again later.")
        }
    }
}

protocol UsageAccountVault: Sendable {
    func read(_ provider: UsageProviderID) throws -> UsageAccountRecord?
    func save(_ record: UsageAccountRecord) throws
    func remove(_ provider: UsageProviderID) throws
}

/// Identity and rotating credentials are one atomic, non-synchronizing private Keychain item per provider.
struct UsageAccountKeychain: UsageAccountVault {
    let service: String
    init(service: String = (Bundle.main.bundleIdentifier ?? "me.badia.altillo") + ".usage-accounts") {
        self.service = service
    }
    private func query(_ provider: UsageProviderID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue, kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }
    func read(_ provider: UsageProviderID) throws -> UsageAccountRecord? {
        var query = query(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 128 * 1024,
              let record = try? JSONDecoder().decode(UsageAccountRecord.self, from: data),
              record.version == 1, record.provider == provider, !record.accessToken.isEmpty,
              !record.refreshToken.isEmpty, !record.remoteID.isEmpty else { throw UsageAccountFailure.storage }
        return record
    }
    func save(_ record: UsageAccountRecord) throws {
        let query = query(record.provider)
        let data = try JSONEncoder().encode(record)
        let attributes = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addition = query
            addition[kSecValueData as String] = data
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(addition as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw UsageAccountFailure.storage }
    }
    func remove(_ provider: UsageProviderID) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw UsageAccountFailure.storage }
    }
}

/// Makes Cancel and the atomic Keychain commit mutually exclusive across the main actor and session actor.
/// Once committed, cancellation is too late: the manager must finish publishing the selected identity.
final class UsageAccountOperationGate: @unchecked Sendable {
    private enum State { case pending, cancelled, committed }
    private let lock = NSLock()
    private var state = State.pending

    @discardableResult func cancel() -> Bool {
        lock.withLock {
            guard state != .committed else { return false }
            state = .cancelled
            return true
        }
    }
    func commit(_ body: () throws -> Void) throws {
        try lock.withLock {
            guard state == .pending else { throw CancellationError() }
            try body()
            state = .committed
        }
    }
}

actor UsageAccountSession {
    static let shared = UsageAccountSession()
    private let vault: any UsageAccountVault
    private let transport: any HTTPTransport
    private let beforeInstall: (@Sendable () async -> Void)?
    private let afterInstall: (@Sendable () async -> Void)?
    private var generations: [UsageProviderID: UUID] = [:]
    private var flights: [UsageProviderID: (id: UUID, task: Task<UsageAccountRecord, Error>)] = [:]
    /// A refresh token may rotate before Keychain becomes writable. Keep the new pair until it can be committed.
    private var pendingPersistence: [UsageProviderID: UsageAccountRecord] = [:]
    private var terminal: Set<UsageProviderID> = []

    init(vault: any UsageAccountVault = UsageAccountKeychain(),
         transport: any HTTPTransport = UsageAccountHTTPTransport(),
         beforeInstall: (@Sendable () async -> Void)? = nil,
         afterInstall: (@Sendable () async -> Void)? = nil) {
        self.vault = vault
        self.transport = transport
        self.beforeInstall = beforeInstall
        self.afterInstall = afterInstall
    }

    func summaries() throws -> [UsageProviderID: UsageAccountSummary] {
        var result: [UsageProviderID: UsageAccountSummary] = [:]
        for provider: UsageProviderID in [.claude, .codex] {
            if let record = try pendingPersistence[provider] ?? vault.read(provider) { result[provider] = record.summary }
        }
        return result
    }
    func hasAccount(_ provider: UsageProviderID) -> Bool {
        if pendingPersistence[provider] != nil { return true }
        do { return try vault.read(provider) != nil }
        catch { return true } // Fetch exposes Keychain denial; do not disguise it as an unconfigured provider.
    }
    func install(_ record: UsageAccountRecord, operation: UsageAccountOperationGate = UsageAccountOperationGate()) async throws {
        guard [.claude, .codex].contains(record.provider) else { throw UsageAccountFailure.unsupported }
        if let beforeInstall { await beforeInstall() }
        try Task.checkCancellation()
        try operation.commit {
            try vault.save(record)
            invalidate(record.provider)
            pendingPersistence.removeValue(forKey: record.provider)
            terminal.remove(record.provider)
        }
        if let afterInstall { await afterInstall() }
    }
    func disconnect(_ provider: UsageProviderID) throws {
        // Invalidate before touching storage so an in-flight refresh cannot restore a removed account.
        invalidate(provider)
        try vault.remove(provider)
        pendingPersistence.removeValue(forKey: provider)
        terminal.remove(provider)
    }
    private func invalidate(_ provider: UsageProviderID) {
        generations[provider] = UUID()
        flights.removeValue(forKey: provider)?.task.cancel()
    }

    func claudeCredentials(now: Date, forceRefresh: Bool = false) async throws -> ClaudeCredentials? {
        guard let record = try await credential(.claude, now: now, forceRefresh: forceRefresh) else { return nil }
        return ClaudeCredentials(accessToken: record.accessToken, expiresAt: record.expiresAt,
                                 subscriptionType: record.subscriptionType, rateLimitTier: record.rateLimitTier,
                                 scopes: ["user:profile"], source: .keychain)
    }
    func codexAuth(now: Date, forceRefresh: Bool = false) async throws -> CodexAuth? {
        guard let record = try await credential(.codex, now: now, forceRefresh: forceRefresh) else { return nil }
        return CodexAuth(accessToken: record.accessToken, accountID: record.accountID)
    }

    private func credential(_ provider: UsageProviderID, now: Date, forceRefresh: Bool) async throws -> UsageAccountRecord? {
        if terminal.contains(provider) { throw UsageAuthorizationError.sessionExpired }
        if let pending = pendingPersistence[provider] {
            do { try vault.save(pending); pendingPersistence.removeValue(forKey: provider) }
            catch { throw UsageAuthorizationError.accessDenied }
        }
        if let flight = flights[provider] { return try await flight.task.value }
        let record: UsageAccountRecord
        do {
            guard let stored = try vault.read(provider) else { return nil }
            record = stored
        } catch { throw UsageAuthorizationError.accessDenied }
        if !forceRefresh, record.expiresAt > now.addingTimeInterval(5 * 60) { return record }
        let generation = generations[provider] ?? UUID()
        generations[provider] = generation
        let id = UUID()
        let task = Task { try await self.refresh(record, generation: generation, now: now) }
        flights[provider] = (id, task)
        defer { if flights[provider]?.id == id { flights.removeValue(forKey: provider) } }
        return try await task.value
    }
    private func refresh(_ record: UsageAccountRecord, generation: UUID, now: Date) async throws -> UsageAccountRecord {
        do {
            let renewed = try await UsageAccountTokenClient(transport: transport).refresh(record, now: now)
            try Task.checkCancellation()
            guard generations[record.provider] == generation else { throw CancellationError() }
            pendingPersistence[record.provider] = renewed
            do { try vault.save(renewed); pendingPersistence.removeValue(forKey: record.provider) }
            catch { throw UsageAuthorizationError.accessDenied }
            return renewed
        } catch UsageAccountFailure.sessionExpired {
            guard generations[record.provider] == generation else { throw CancellationError() }
            terminal.insert(record.provider)
            throw UsageAuthorizationError.sessionExpired
        }
    }
}

@MainActor @Observable final class UsageAccountManager {
    static let shared = UsageAccountManager()
    private(set) var accounts: [UsageProviderID: UsageAccountSummary] = [:]
    private(set) var connecting: UsageProviderID?
    private(set) var errorMessage: String?
    @ObservationIgnored var onAccountChanged: (UsageProviderID) -> Void = { _ in }
    @ObservationIgnored private let session: UsageAccountSession
    @ObservationIgnored private let oauth: any UsageAccountAuthorizing
    @ObservationIgnored private var operation: UUID?
    @ObservationIgnored private var operationGate: UsageAccountOperationGate?

    init(session: UsageAccountSession = .shared, oauth: (any UsageAccountAuthorizing)? = nil) {
        self.session = session
        self.oauth = oauth ?? UsageAccountOAuth()
    }
    func restore() async {
        do { accounts = try await session.summaries() }
        catch { errorMessage = UsageAccountFailure.storage.localizedDescription }
    }
    func connect(_ provider: UsageProviderID) async {
        guard connecting == nil else { return }
        let id = UUID()
        operation = id
        let gate = UsageAccountOperationGate()
        operationGate = gate
        connecting = provider
        errorMessage = nil
        defer { if operation == id { connecting = nil; operation = nil; operationGate = nil } }
        do {
            let record = try await oauth.authorize(provider)
            try Task.checkCancellation()
            guard operation == id else { throw CancellationError() }
            try await session.install(record, operation: gate)
            guard operation == id else { return }
            accounts[provider] = record.summary
            onAccountChanged(provider)
        } catch {
            if operation == id, !(error is CancellationError), error as? UsageAccountFailure != .cancelled {
                errorMessage = (error as? UsageAccountFailure ?? .unavailable).localizedDescription
            }
        }
    }
    func disconnect(_ provider: UsageProviderID) async {
        if connecting == provider {
            cancel()
            // Explicit Disconnect supersedes even a just-committed login whose main-actor UI has not landed.
            operation = nil
            operationGate = nil
            connecting = nil
        }
        do {
            try await session.disconnect(provider)
            accounts.removeValue(forKey: provider)
            errorMessage = nil
            onAccountChanged(provider)
        } catch {
            // A failed removal must still publish the actual committed identity instead of showing the old one.
            if let restored = try? await session.summaries() { accounts = restored }
            onAccountChanged(provider)
            errorMessage = UsageAccountFailure.storage.localizedDescription
        }
    }
    func cancel() {
        guard operationGate?.cancel() != false else { return }
        operationGate = nil
        operation = nil
        connecting = nil
        oauth.cancel()
    }
}
