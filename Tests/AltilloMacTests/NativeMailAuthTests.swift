import AltilloMail
import Foundation
import Testing
@testable import Altillo

@MainActor struct NativeMailAuthTests {
    private let configuration = MailNativeConfiguration(info: [
        "ALTILLO_GOOGLE_MAIL_CLIENT_ID": "123456-test.apps.googleusercontent.com",
        "ALTILLO_MICROSOFT_MAIL_CLIENT_ID": "52D16CB8-E338-4311-A7EE-B791880467A9"
    ], bundleIdentifier: "me.badia.altillo.tests")

    @Test func missingUnexpandedAndMalformedRegistrationCannotOfferLogin() {
        for value in ["", "  ", "$(ALTILLO_GOOGLE_MAIL_CLIENT_ID)", "${CLIENT}", "not-a-client"] {
            let config = MailNativeConfiguration(info: ["ALTILLO_GOOGLE_MAIL_CLIENT_ID": value,
                                                        "ALTILLO_MICROSOFT_MAIL_CLIENT_ID": value])
            #expect(config.availableServices.isEmpty)
        }
        #expect(configuration.availableServices == [.google, .microsoft])
        #expect(configuration.microsoftRedirectURI == "msauth.me.badia.altillo.tests://auth")
    }

    @Test func credentialReplacementIsAtomicAndRemovalIsAccountScoped() throws {
        let backend = MemoryMailCredentialBackend()
        let vault = MailCredentialStore(backend: backend)
        let first = record("one"), second = record("two")
        try vault.save(first)
        try vault.save(second)
        backend.failWrites = true
        #expect(throws: MailAuthFailure.credentialStorage) {
            try vault.save(MailCredentialRecord(account: first.account, googleState: Data("new".utf8), microsoftAccountID: nil))
        }
        #expect(try vault.record(for: first.account.id) == first)
        backend.failWrites = false
        try vault.remove(first.account.id)
        #expect(try vault.records() == [second])
    }

    @Test func reconnectCannotReplaceAnotherIdentityAndCleansPendingCredential() async throws {
        let vault = MailCredentialStore(backend: MemoryMailCredentialBackend())
        let existing = record("original")
        try vault.save(existing)
        let driver = MockMailAuthenticationDriver()
        let coordinator = MailAuthCoordinator(vault: vault, configuration: configuration, driver: driver) { _, _ in
            NativeMailIdentity(remoteID: "different", address: "synthetic@example.invalid")
        }
        await #expect(throws: MailAuthFailure.accountMismatch) {
            try await coordinator.connect(service: .google, replacing: existing.account)
        }
        #expect(try vault.records() == [existing])
        #expect(driver.discardCount == 1)
    }

    @Test func connectingExistingIdentityKeepsItsLocalID() async throws {
        let vault = MailCredentialStore(backend: MemoryMailCredentialBackend())
        let existing = record("original")
        try vault.save(existing)
        let coordinator = MailAuthCoordinator(vault: vault, configuration: configuration,
                                               driver: MockMailAuthenticationDriver()) { _, _ in
            NativeMailIdentity(remoteID: "original", address: "synthetic@example.invalid")
        }
        let account = try await coordinator.connect(service: .google)
        #expect(account.id == existing.account.id)
        #expect(try vault.records().count == 1)
    }

    @Test func cancellationDoesNotPersistAnAuthorizedAccount() async throws {
        let vault = MailCredentialStore(backend: MemoryMailCredentialBackend())
        let driver = MockMailAuthenticationDriver()
        driver.holdAuthorization = true
        let coordinator = MailAuthCoordinator(vault: vault, configuration: configuration, driver: driver)
        let task = Task { try await coordinator.connect(service: .google) }
        while driver.authorizationContinuation == nil { await Task.yield() }
        coordinator.cancel()
        await #expect(throws: MailAuthFailure.cancelled) { try await task.value }
        #expect(try vault.records().isEmpty)
    }

    @Test func refreshIsDeduplicatedAndDisconnectPreventsLateCredentialResurrection() async throws {
        let vault = MailCredentialStore(backend: MemoryMailCredentialBackend())
        let existing = record("original")
        try vault.save(existing)
        let driver = MockMailAuthenticationDriver()
        driver.holdRefresh = true
        let coordinator = MailAuthCoordinator(vault: vault, configuration: configuration, driver: driver)
        let first = Task { try await coordinator.accessToken(for: existing.account) }
        while driver.refreshContinuation == nil { await Task.yield() }
        let second = Task { try await coordinator.accessToken(for: existing.account) }
        await Task.yield()
        #expect(driver.refreshCount == 1)
        try await coordinator.disconnect(account: existing.account)
        driver.completeRefresh()
        await #expect(throws: MailAuthFailure.cancelled) { try await first.value }
        await #expect(throws: MailAuthFailure.cancelled) { try await second.value }
        #expect(try vault.records().isEmpty)
    }

    @Test func corruptVaultDoesNotBecomeAnEmptySuccessfulRestore() {
        let backend = MemoryMailCredentialBackend()
        backend.items["corrupt"] = Data("not-json".utf8)
        let vault = MailCredentialStore(backend: backend)
        #expect(throws: MailAuthFailure.credentialStorage) { try vault.records() }
    }

    @Test func pauseCancellationDiscardsLateRefreshWithoutPersistingRotatedState() async throws {
        let vault = MailCredentialStore(backend: MemoryMailCredentialBackend())
        let original = record("original")
        try vault.save(original)
        let driver = MockMailAuthenticationDriver()
        driver.holdRefresh = true
        let coordinator = MailAuthCoordinator(vault: vault, configuration: configuration, driver: driver)
        let refresh = Task { try await coordinator.accessToken(for: original.account) }
        while driver.refreshContinuation == nil { await Task.yield() }
        coordinator.cancel()
        driver.completeRefresh()
        await #expect(throws: MailAuthFailure.cancelled) { try await refresh.value }
        #expect(try vault.record(for: original.account.id) == original)
        #expect(try coordinator.restoreAccounts() == [original.account])
        driver.holdRefresh = false
        #expect(try await coordinator.accessToken(for: original.account) == "synthetic-token")
        #expect(driver.refreshCount == 2)
    }

    private func record(_ remote: String) -> MailCredentialRecord {
        MailCredentialRecord(account: NativeMailAccount(service: .google, remoteID: remote,
                                                        address: "synthetic@example.invalid"),
                             googleState: Data("synthetic-secure-archive".utf8), microsoftAccountID: nil)
    }
}

private final class MemoryMailCredentialBackend: MailCredentialBackend, @unchecked Sendable {
    private let lock = NSLock()
    var items: [String: Data] = [:]
    var failWrites = false
    func readAll() throws -> [Data] { lock.withLock { Array(items.values) } }
    func write(_ data: Data, key: String) throws {
        try lock.withLock {
            if failWrites { throw MailAuthFailure.credentialStorage }
            items[key] = data
        }
    }
    func remove(key: String) throws { _ = lock.withLock { items.removeValue(forKey: key) } }
}

@MainActor private final class MockMailAuthenticationDriver: MailAuthenticationDriver {
    var holdAuthorization = false
    var holdRefresh = false
    var discardCount = 0
    var refreshCount = 0
    var authorizationContinuation: CheckedContinuation<MailOAuthCredential, Error>?
    var refreshContinuation: CheckedContinuation<MailOAuthCredential, Error>?
    private var credential: MailOAuthCredential {
        MailOAuthCredential(token: "synthetic-token", googleState: Data("synthetic-state".utf8), microsoftAccountID: nil)
    }
    func authorize(service: NativeMailService) async throws -> MailOAuthCredential {
        if holdAuthorization {
            return try await withCheckedThrowingContinuation { authorizationContinuation = $0 }
        }
        return credential
    }
    func refresh(record: MailCredentialRecord, force: Bool) async throws -> MailOAuthCredential {
        refreshCount += 1
        if holdRefresh { return try await withCheckedThrowingContinuation { refreshContinuation = $0 } }
        return credential
    }
    func completeRefresh() {
        refreshContinuation?.resume(returning: credential)
        refreshContinuation = nil
    }
    func remove(record: MailCredentialRecord) throws {}
    func discard(_ credential: MailOAuthCredential, preserving: [MailCredentialRecord]) throws { discardCount += 1 }
    func cancel() {
        authorizationContinuation?.resume(throwing: MailAuthFailure.cancelled)
        authorizationContinuation = nil
    }
}
