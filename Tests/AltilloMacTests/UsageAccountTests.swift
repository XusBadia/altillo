import AltilloCore
import AltilloUsage
import Foundation
import Testing
@testable import Altillo

struct UsageAccountTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func refreshRotatesOwnTokensAndPreservesTokenWhenOmitted() async throws {
        let vault = MemoryUsageAccountVault()
        let record = account()
        try vault.save(record)
        let transport = UsageAccountFixtureTransport(responses: [
            (200, #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#),
            (200, #"{"access_token":"next-access","expires_in":3600}"#)
        ])
        let session = UsageAccountSession(vault: vault, transport: transport)
        let credential = try await session.claudeCredentials(now: now)
        #expect(credential?.accessToken == "new-access")
        #expect(try vault.read(.claude)?.refreshToken == "new-refresh")
        _ = try await session.claudeCredentials(now: now, forceRefresh: true)
        #expect(try vault.read(.claude)?.refreshToken == "new-refresh")
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Content-Type") == "application/json" })
        let second = try #require(try JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: String])
        #expect(second["refresh_token"] == "new-refresh")
        #expect(second["scope"] == "user:profile")
    }

    @Test func rotatedTokenSurvivesFailedPersistenceWithoutReusingSpentRefresh() async throws {
        let vault = MemoryUsageAccountVault()
        try vault.save(account())
        let transport = UsageAccountFixtureTransport(responses: [
            (200, #"{"access_token":"new-access","refresh_token":"rotated","expires_in":3600}"#)
        ])
        let session = UsageAccountSession(vault: vault, transport: transport)
        vault.setFailWrites(true)
        await #expect(throws: UsageAuthorizationError.accessDenied) { try await session.claudeCredentials(now: now) }
        vault.setFailWrites(false)
        let recovered = try await session.claudeCredentials(now: now)
        #expect(recovered?.accessToken == "new-access")
        #expect(try vault.read(.claude)?.refreshToken == "rotated")
        #expect(await transport.requests.count == 1)
    }

    @Test func terminalRefreshDoesNotLoopAndDisconnectClearsOnlyOwnProvider() async throws {
        let vault = MemoryUsageAccountVault()
        try vault.save(account())
        var codex = account(); codex.provider = .codex
        try vault.save(codex)
        let transport = UsageAccountFixtureTransport(responses: [(400, #"{"error":"invalid_grant"}"#)])
        let session = UsageAccountSession(vault: vault, transport: transport)
        await #expect(throws: UsageAuthorizationError.sessionExpired) { try await session.claudeCredentials(now: now) }
        await #expect(throws: UsageAuthorizationError.sessionExpired) { try await session.claudeCredentials(now: now) }
        #expect(await transport.requests.count == 1)
        try await session.disconnect(.claude)
        #expect(await session.hasAccount(.claude) == false)
        #expect(await session.hasAccount(.codex))
    }

    @Test func unexpiredOwnAccountDoesNotUseNetwork() async throws {
        let vault = MemoryUsageAccountVault()
        var fresh = account(); fresh.expiresAt = now.addingTimeInterval(3600)
        try vault.save(fresh)
        let transport = UsageAccountFixtureTransport(responses: [])
        let session = UsageAccountSession(vault: vault, transport: transport)
        #expect(try await session.claudeCredentials(now: now)?.accessToken == "old-access")
        #expect(await transport.requests.isEmpty)
    }

    @Test func codexExchangeUsesFormPKCEAndTokenIdentity() async throws {
        let access = jwt(["exp": now.addingTimeInterval(3600).timeIntervalSince1970,
                          "https://api.openai.com/auth": ["chatgpt_account_id": "account-id"]])
        let id = jwt(["email": "synthetic@example.invalid"])
        let body = try String(data: JSONSerialization.data(withJSONObject: ["access_token": access,
                            "refresh_token": "refresh", "id_token": id]), encoding: .utf8)!
        let transport = UsageAccountFixtureTransport(responses: [(200, body), (200, #"{"rate_limit":{}}"#)])
        let record = try await UsageAccountTokenClient(transport: transport).exchange(provider: .codex,
                            code: "test+code", state: "state", redirect: URL(string: "http://localhost:1455/auth/callback")!,
                            verifier: "verifier", now: now)
        #expect(record.accountID == "account-id")
        #expect(record.label == "synthetic@example.invalid")
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(String(decoding: request.httpBody!, as: UTF8.self).contains("code=test%2Bcode"))
        #expect(String(decoding: request.httpBody!, as: UTF8.self).contains("code_verifier=verifier"))
    }

    @Test func concurrentRefreshIsSingleFlightAndDisconnectRejectsLateToken() async throws {
        let vault = MemoryUsageAccountVault()
        try vault.save(account())
        let transport = UsageAccountDelayedTransport()
        let session = UsageAccountSession(vault: vault, transport: transport)
        let first = Task { try await session.claudeCredentials(now: now) }
        await transport.waitUntilStarted()
        let second = Task { try await session.claudeCredentials(now: now) }
        // Disconnect invalidates the generation even if the server ignores task cancellation.
        try await session.disconnect(.claude)
        await transport.finish()
        for task in [first, second] {
            do { _ = try await task.value }
            catch { #expect(error is CancellationError) }
        }
        #expect(await transport.requestCount == 1)
        #expect(try vault.read(.claude) == nil)
    }

    @Test func temporaryRefreshCanRetryWithoutLosingAccount() async throws {
        let vault = MemoryUsageAccountVault()
        try vault.save(account())
        let transport = UsageAccountFixtureTransport(responses: [
            (503, #"{"error":"temporarily_unavailable"}"#),
            (200, #"{"access_token":"recovered","expires_in":3600}"#)
        ])
        let session = UsageAccountSession(vault: vault, transport: transport)
        await #expect(throws: UsageAccountFailure.temporary(503)) { try await session.claudeCredentials(now: now) }
        #expect(try await session.claudeCredentials(now: now)?.accessToken == "recovered")
        #expect(try vault.read(.claude)?.refreshToken == "old-refresh")
    }

    @MainActor @Test func callbackRequiresMatchingNonemptyStateAndCode() throws {
        #expect(try UsageAccountOAuth.validatedCallback(code: "code", state: "state", expectedState: "state") == "code")
        for state: String? in [nil, "", "different"] {
            #expect(throws: UsageAccountFailure.cancelled) {
                try UsageAccountOAuth.validatedCallback(code: "code", state: state, expectedState: "state")
            }
        }
        #expect(throws: UsageAccountFailure.cancelled) {
            try UsageAccountOAuth.validatedCallback(code: "", state: "state", expectedState: "state")
        }
    }

    @MainActor @Test func cancelledConnectionCannotReplaceStoredAccount() async throws {
        let vault = MemoryUsageAccountVault()
        let original = account()
        try vault.save(original)
        let session = UsageAccountSession(vault: vault, transport: UsageAccountFixtureTransport(responses: []))
        let driver = DelayedUsageAccountAuthorization(record: original)
        let manager = UsageAccountManager(session: session, oauth: driver)
        await manager.restore()
        let connecting = Task { await manager.connect(.claude) }
        await driver.waitUntilStarted()
        manager.cancel()
        await connecting.value
        #expect(manager.connecting == nil)
        #expect(manager.accounts[.claude]?.id == original.id)
        #expect(try vault.read(.claude) == original)
    }

    @MainActor @Test func cancelWhileInstallIsQueuedCannotWriteOrReplaceAccount() async throws {
        let vault = MemoryUsageAccountVault()
        let original = account()
        try vault.save(original)
        var replacement = original
        replacement.id = UUID()
        replacement.label = "replacement@example.invalid"
        let boundary = UsageAccountInstallBarrier()
        let session = UsageAccountSession(vault: vault, transport: UsageAccountFixtureTransport(responses: []),
                                          beforeInstall: { await boundary.hold() })
        let manager = UsageAccountManager(session: session, oauth: ImmediateUsageAccountAuthorization(record: replacement))
        await manager.restore()
        var changes = 0
        manager.onAccountChanged = { _ in changes += 1 }
        let connection = Task { await manager.connect(.claude) }
        await boundary.waitUntilReached()
        manager.cancel()
        await boundary.release()
        await connection.value
        #expect(try vault.read(.claude) == original)
        #expect(manager.accounts[.claude]?.id == original.id)
        #expect(manager.connecting == nil)
        #expect(changes == 0)
    }

    @MainActor @Test func cancelAfterCommitStillPublishesCommittedIdentityExactlyOnce() async throws {
        let vault = MemoryUsageAccountVault()
        let replacement = account()
        let boundary = UsageAccountInstallBarrier()
        let session = UsageAccountSession(vault: vault, transport: UsageAccountFixtureTransport(responses: []),
                                          afterInstall: { await boundary.hold() })
        let manager = UsageAccountManager(session: session, oauth: ImmediateUsageAccountAuthorization(record: replacement))
        var changes = 0
        manager.onAccountChanged = { _ in changes += 1 }
        let connection = Task { await manager.connect(.claude) }
        await boundary.waitUntilReached()
        #expect(try vault.read(.claude) == replacement)
        manager.cancel()
        await boundary.release()
        await connection.value
        #expect(manager.accounts[.claude]?.id == replacement.id)
        #expect(manager.connecting == nil)
        #expect(changes == 1)
    }

    @MainActor @Test func timedOutSignInShowsRecoveryAndKeepsExistingAccount() async throws {
        let vault = MemoryUsageAccountVault()
        let previous = account()
        try vault.save(previous)
        let session = UsageAccountSession(vault: vault, transport: UsageAccountFixtureTransport(responses: []))
        let manager = UsageAccountManager(session: session, oauth: TimedOutUsageAuthorization())
        await manager.restore()
        await manager.connect(.claude)
        #expect(manager.connecting == nil)
        #expect(manager.errorMessage == UsageAccountFailure.timedOut.localizedDescription)
        #expect(manager.accounts[.claude]?.id == previous.id)
        #expect(try vault.read(.claude) == previous)
    }

    @Test func browserRejectsNonProviderAndInsecureURLs() {
        for raw in ["https://claude.ai/oauth/authorize?state=synthetic", "https://auth.openai.com/oauth/authorize"] {
            #expect(UsageAccountBrowserAgent.allows(URL(string: raw)!))
        }
        for raw in ["http://claude.ai/oauth/authorize", "https://claude.ai.evil.invalid/oauth/authorize",
                    "https://claude.ai:444/oauth/authorize", "https://claude.ai/other", "https://user@claude.ai/oauth/authorize"] {
            #expect(!UsageAccountBrowserAgent.allows(URL(string: raw)!))
        }
    }

    private func account() -> UsageAccountRecord {
        .init(provider: .claude, label: "synthetic@example.invalid", remoteID: "test", accessToken: "old-access",
              refreshToken: "old-refresh", expiresAt: now.addingTimeInterval(-1))
    }
    private func jwt(_ claims: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: claims)
        let base64 = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "header.\(base64).signature"
    }
}

private final class MemoryUsageAccountVault: UsageAccountVault, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [UsageProviderID: UsageAccountRecord] = [:]
    private var failWrites = false
    func setFailWrites(_ value: Bool) { lock.withLock { failWrites = value } }
    func read(_ provider: UsageProviderID) throws -> UsageAccountRecord? { lock.withLock { records[provider] } }
    func save(_ record: UsageAccountRecord) throws {
        try lock.withLock {
            if failWrites { throw UsageAccountFailure.storage }
            records[record.provider] = record
        }
    }
    func remove(_ provider: UsageProviderID) throws { _ = lock.withLock { records.removeValue(forKey: provider) } }
}
private actor UsageAccountFixtureTransport: HTTPTransport {
    private var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []
    init(responses: [(Int, String)]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        let (status, body) = responses.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private actor UsageAccountDelayedTransport: HTTPTransport {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func finish() { responseWaiter?.resume(); responseWaiter = nil }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        started = true
        startWaiter?.resume(); startWaiter = nil
        await withCheckedContinuation { responseWaiter = $0 }
        return (Data(#"{"access_token":"late","refresh_token":"late-refresh","expires_in":3600}"#.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor private final class DelayedUsageAccountAuthorization: UsageAccountAuthorizing {
    let record: UsageAccountRecord
    private var continuation: CheckedContinuation<UsageAccountRecord, Error>?
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    init(record: UsageAccountRecord) { self.record = record }
    func authorize(_ provider: UsageProviderID) async throws -> UsageAccountRecord {
        started = true
        startWaiter?.resume(); startWaiter = nil
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func cancel() { continuation?.resume(throwing: UsageAccountFailure.cancelled); continuation = nil }
}

private actor UsageAccountInstallBarrier {
    private var reached = false
    private var observer: CheckedContinuation<Void, Never>?
    private var resume: CheckedContinuation<Void, Never>?
    func hold() async {
        reached = true
        observer?.resume(); observer = nil
        await withCheckedContinuation { resume = $0 }
    }
    func waitUntilReached() async {
        if reached { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { resume?.resume(); resume = nil }
}
@MainActor private final class ImmediateUsageAccountAuthorization: UsageAccountAuthorizing {
    let record: UsageAccountRecord
    init(record: UsageAccountRecord) { self.record = record }
    func authorize(_ provider: UsageProviderID) async throws -> UsageAccountRecord { record }
    func cancel() {}
}

@MainActor private final class TimedOutUsageAuthorization: UsageAccountAuthorizing {
    func authorize(_ provider: UsageProviderID) async throws -> UsageAccountRecord { throw UsageAccountFailure.timedOut }
    func cancel() {}
}
