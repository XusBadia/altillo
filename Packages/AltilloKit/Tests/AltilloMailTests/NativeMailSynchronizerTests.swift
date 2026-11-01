import Foundation
import Testing
@testable import AltilloMail

struct NativeMailSynchronizerTests {
    @Test func bootstrapIsSilentAndOnlyFreshUnseenChangesBecomeArrivals() async throws {
        let clock = MailSyncClock()
        let account = mailSyncAccount()
        let old = mailSyncMessage(account, "old", at: 900)
        let fresh = mailSyncMessage(account, "new", at: 1_001)
        let movedOld = mailSyncMessage(account, "moved", at: 950)
        let future = mailSyncMessage(account, "future", at: 1_100)
        let provider = MailSyncFixture(account: account, bootstrap: [.page(.init(messages: [old], cursor: "c0"))], changes: [
            .page(.init(messages: [fresh, movedOld, future], cursor: "c1")),
            .page(.init(messages: [fresh], removedIDs: ["old"], cursor: "c2")),
            .page(.init(messages: [old], cursor: "c3"))
        ])
        let sync = NativeMailSynchronizer(provider: provider, now: { clock.current() })
        #expect(try await sync.synchronize().arrivals.isEmpty)
        clock.advance(1)
        let changed = try await sync.synchronize()
        #expect(changed.arrivals.map(\.key.remoteID) == ["new"])
        let duplicate = try await sync.synchronize()
        #expect(duplicate.arrivals.isEmpty)
        #expect(!duplicate.messages.contains(where: { $0.key.remoteID == "old" }))
        #expect(try await sync.synchronize().arrivals.isEmpty)
    }

    @Test func snapshotRefreshReplacesTheWindowWithoutReplayingOldMessages() async throws {
        let clock = MailSyncClock()
        let account = mailSyncAccount()
        let old = mailSyncMessage(account, "old", at: 900)
        let changedRead = mailSyncMessage(account, "old", at: 900, unread: false)
        let fresh = mailSyncMessage(account, "fresh", at: 1_001)
        let provider = MailSyncFixture(account: account, bootstrap: [.page(.init(messages: [old], cursor: "snapshot-v1", isFullSnapshot: true))], changes: [
            .page(.init(messages: [changedRead, fresh], cursor: "snapshot-v1", isFullSnapshot: true)),
            .page(.init(messages: [fresh], cursor: "snapshot-v1", isFullSnapshot: true))
        ])
        let sync = NativeMailSynchronizer(provider: provider, now: { clock.current() })
        _ = try await sync.synchronize()
        clock.advance(1)
        let update = try await sync.synchronize()
        #expect(update.arrivals.map(\.key.remoteID) == ["fresh"])
        #expect(update.messages.first(where: { $0.key.remoteID == "old" })?.isUnread == false)
        let next = try await sync.synchronize()
        #expect(next.messages.map(\.key.remoteID) == ["fresh"])
        #expect(next.arrivals.isEmpty)
    }

    @Test func paginationIsBoundedAndCommitsTheCursorOnlyAfterItsLastPage() async throws {
        let clock = MailSyncClock()
        let account = mailSyncAccount()
        let pages: [MailSyncStep] = (0..<5).map { index -> MailSyncStep in
            let message = mailSyncMessage(account, "old-\(index)", at: Double(900 + index))
            let nextPage: String? = index < 4 ? "p\(index + 1)" : nil
            let cursor: String? = index == 4 ? "complete" : nil
            let page = NativeMailPage(messages: [message], nextPage: nextPage, cursor: cursor)
            return .page(page)
        }
        let provider = MailSyncFixture(account: account, bootstrap: pages, changes: [.page(.init(messages: [], cursor: "later"))])
        let sync = NativeMailSynchronizer(provider: provider, now: { clock.current() })
        let first = try await sync.synchronize()
        #expect(first.hasMore && first.messages.count == 4 && first.arrivals.isEmpty)
        #expect(await provider.requests().count == 4)
        let second = try await sync.synchronize()
        #expect(!second.hasMore && second.messages.count == 5 && second.arrivals.isEmpty)
        _ = try await sync.synchronize()
        #expect(await provider.requests() == ["bootstrap:-", "bootstrap:p1", "bootstrap:p2", "bootstrap:p3", "bootstrap:p4", "changes:complete:-"])
    }

    @Test func deltaPaginationKeepsTheOriginalCursorBetweenCycles() async throws {
        let account = mailSyncAccount()
        var changes: [MailSyncStep] = (0..<5).map { index -> MailSyncStep in
            let nextPage: String? = index < 4 ? "d\(index + 1)" : nil
            let cursor: String? = index == 4 ? "c1" : nil
            return .page(NativeMailPage(messages: [], nextPage: nextPage, cursor: cursor))
        }
        changes.append(.page(NativeMailPage(messages: [], cursor: "c2")))
        let provider = MailSyncFixture(account: account, bootstrap: [.page(.init(messages: [], cursor: "c0"))], changes: changes)
        let sync = NativeMailSynchronizer(provider: provider)
        _ = try await sync.synchronize()
        #expect(try await sync.synchronize().hasMore)
        let completed = try await sync.synchronize()
        #expect(!completed.hasMore)
        _ = try await sync.synchronize()
        let requests = await provider.requests()
        #expect(Array(requests.suffix(2)) == ["changes:c0:d4", "changes:c1:-"])
    }

    @Test func expiredCursorRebuildsSilentlyAndThenResumesNewArrivals() async throws {
        let clock = MailSyncClock()
        let account = mailSyncAccount()
        let provider = MailSyncFixture(account: account, bootstrap: [
            .page(.init(messages: [mailSyncMessage(account, "original", at: 900)], cursor: "c0")),
            .page(.init(messages: [mailSyncMessage(account, "during-gap", at: 1_001)], cursor: "rebuilt"))
        ], changes: [.failure(.cursorExpired), .page(.init(messages: [mailSyncMessage(account, "after-rebuild", at: 1_003)], cursor: "c2"))])
        let sync = NativeMailSynchronizer(provider: provider, now: { clock.current() })
        _ = try await sync.synchronize()
        clock.advance(2)
        let rebuilt = try await sync.synchronize()
        #expect(rebuilt.arrivals.isEmpty)
        #expect(rebuilt.messages.map(\.key.remoteID) == ["during-gap"])
        clock.advance(1)
        #expect(try await sync.synchronize().arrivals.map(\.key.remoteID) == ["after-rebuild"])
    }

    @Test func aDelayedBootstrapCannotRestoreDataAfterReset() async throws {
        let account = mailSyncAccount()
        let gate = MailSyncGate<NativeMailPage>()
        let provider = MailSyncFixture(account: account, bootstrap: [.gate(gate), .page(.init(messages: [], cursor: "new-session"))])
        let sync = NativeMailSynchronizer(provider: provider)
        let pending = Task { try await sync.synchronize() }
        await gate.waitUntilStarted()
        await sync.reset()
        await gate.release(.init(messages: [mailSyncMessage(account, "stale", at: 900)], cursor: "old-session"))
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(try await sync.synchronize().messages.isEmpty)
    }

    @Test func concurrentRefreshesCannotReturnDuplicateArrivalNotifications() async throws {
        let clock = MailSyncClock()
        let account = mailSyncAccount()
        let gate = MailSyncGate<NativeMailPage>()
        let fresh = mailSyncMessage(account, "fresh", at: 1_001)
        let provider = MailSyncFixture(account: account, bootstrap: [.page(.init(messages: [], cursor: "c0"))], changes: [
            .gate(gate), .page(.init(messages: [fresh], cursor: "c1"))
        ])
        let sync = NativeMailSynchronizer(provider: provider, now: { clock.current() })
        _ = try await sync.synchronize()
        clock.advance(1)
        let first = Task { try await sync.synchronize() }
        await gate.waitUntilStarted()
        let second = Task { try await sync.synchronize() }
        await gate.release(.init(messages: [fresh], cursor: "c1"))
        let results = try await [first.value, second.value]
        #expect(results.flatMap(\.arrivals).map(\.key.remoteID) == ["fresh"])
    }

    @Test func bodiesAreCoalescedCachedAndRejectOversizedOrForeignResults() async throws {
        let account = mailSyncAccount()
        let key = NativeMailMessageKey(accountID: account.id, remoteID: "one")
        let gate = MailSyncGate<NativeMailContent>()
        let provider = MailSyncFixture(account: account, bootstrap: [.page(.init(messages: [mailSyncMessage(account, "one", at: 900)], cursor: "c0"))])
        await provider.setBodyGate(gate, for: "one")
        let sync = NativeMailSynchronizer(provider: provider)
        _ = try await sync.synchronize()
        let first = Task { try await sync.fetchContent(for: key) }
        await gate.waitUntilStarted()
        let second = Task { try await sync.fetchContent(for: key) }
        await gate.release(.init(key: key, text: "Synthetic body"))
        #expect(try await first.value.text == "Synthetic body")
        #expect(try await second.value.text == "Synthetic body")
        #expect(try await sync.fetchContent(for: key).text == "Synthetic body")
        #expect(await provider.bodyCount("one") == 1)
        await sync.reset()
        await provider.appendBootstrap(.init(messages: [mailSyncMessage(account, "one", at: 900)], cursor: "c1"))
        _ = try await sync.synchronize()
        await provider.setBody(.init(key: key, text: String(repeating: "x", count: (1 << 20) + 1)))
        await #expect(throws: NativeMailFailure.contentTooLarge) { try await sync.fetchContent(for: key) }
        await provider.setBody(.init(key: .init(accountID: UUID(), remoteID: "one"), text: "Wrong account"), for: "one")
        await #expect(throws: NativeMailFailure.invalidResponse) { try await sync.fetchContent(for: key) }
    }

    @Test func aDelayedBodyCannotReturnAfterResetEvenWhenItsMessageReturns() async throws {
        let account = mailSyncAccount()
        let message = mailSyncMessage(account, "one", at: 900)
        let gate = MailSyncGate<NativeMailContent>()
        let provider = MailSyncFixture(account: account, bootstrap: [.page(.init(messages: [message], cursor: "c0")), .page(.init(messages: [message], cursor: "c1"))])
        await provider.setBodyGate(gate, for: "one")
        let sync = NativeMailSynchronizer(provider: provider)
        _ = try await sync.synchronize()
        let pending = Task { try await sync.fetchContent(for: message.key) }
        await gate.waitUntilStarted()
        await sync.reset()
        _ = try await sync.synchronize()
        await provider.setBody(.init(key: message.key, text: "New session"))
        await gate.release(.init(key: message.key, text: "Stale session"))
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(try await sync.fetchContent(for: message.key).text == "New session")
    }

    @Test func deletingAndReaddingAnIdentifierInvalidatesItsOldBodyFlight() async throws {
        let account = mailSyncAccount()
        let message = mailSyncMessage(account, "one", at: 900)
        let gate = MailSyncGate<NativeMailContent>()
        let provider = MailSyncFixture(account: account, bootstrap: [.page(.init(messages: [message], cursor: "c0"))], changes: [
            .page(.init(messages: [], removedIDs: ["one"], cursor: "c1")),
            .page(.init(messages: [message], cursor: "c2"))
        ])
        await provider.setBodyGate(gate, for: "one")
        let sync = NativeMailSynchronizer(provider: provider)
        _ = try await sync.synchronize()
        let pending = Task { try await sync.fetchContent(for: message.key) }
        await gate.waitUntilStarted()
        _ = try await sync.synchronize()
        _ = try await sync.synchronize()
        await provider.setBody(.init(key: message.key, text: "Replacement"))
        await gate.release(.init(key: message.key, text: "Deleted version"))
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(try await sync.fetchContent(for: message.key).text == "Replacement")
    }

    @Test func oneSharedBodyBudgetEvictsAcrossAccountsAndResetOnlyClearsItsAccount() async throws {
        let cache = NativeMailBodyCache(limit: 8)
        let firstAccount = mailSyncAccount()
        let secondAccount = mailSyncAccount()
        let firstMessage = mailSyncMessage(firstAccount, "same-id", at: 900)
        let secondMessage = mailSyncMessage(secondAccount, "same-id", at: 900)
        let firstProvider = MailSyncFixture(account: firstAccount, bootstrap: [.page(.init(messages: [firstMessage], cursor: "a")), .page(.init(messages: [firstMessage], cursor: "a2"))])
        let secondProvider = MailSyncFixture(account: secondAccount, bootstrap: [.page(.init(messages: [secondMessage], cursor: "b"))])
        await firstProvider.setBody(.init(key: firstMessage.key, text: "first1"))
        await secondProvider.setBody(.init(key: secondMessage.key, text: "second"))
        let first = NativeMailSynchronizer(provider: firstProvider, cache: cache)
        let second = NativeMailSynchronizer(provider: secondProvider, cache: cache)
        _ = try await first.synchronize()
        _ = try await second.synchronize()
        _ = try await first.fetchContent(for: firstMessage.key)
        _ = try await second.fetchContent(for: secondMessage.key)
        _ = try await first.fetchContent(for: firstMessage.key)
        #expect(await firstProvider.bodyCount("same-id") == 2)
        // Cache only the second account before resetting the first; its content must survive.
        _ = try await second.fetchContent(for: secondMessage.key)
        let count = await secondProvider.bodyCount("same-id")
        await first.reset()
        #expect(try await second.fetchContent(for: secondMessage.key).text == "second")
        #expect(await secondProvider.bodyCount("same-id") == count)
    }

    @Test func theWindowRetainsOnlyFiftyNewestMessagesAndRejectsForeignAccounts() async throws {
        let account = mailSyncAccount()
        let messages = (0..<80).map { mailSyncMessage(account, "m\($0)", at: Double($0)) }
        let foreign = mailSyncMessage(mailSyncAccount(), "foreign", at: 900)
        let provider = MailSyncFixture(account: account, bootstrap: [.page(.init(messages: messages, cursor: "c0"))], changes: [.page(.init(messages: [foreign], cursor: "c1"))])
        let sync = NativeMailSynchronizer(provider: provider)
        let first = try await sync.synchronize()
        #expect(first.messages.count == 50)
        #expect(first.messages.first?.key.remoteID == "m79")
        #expect(first.messages.last?.key.remoteID == "m30")
        await #expect(throws: NativeMailFailure.messageMissing) { try await sync.fetchContent(for: messages[0].key) }
        await #expect(throws: NativeMailFailure.invalidResponse) { try await sync.synchronize() }
    }

    @Test func pagingLoopsAndInvalidFinalCursorsFailWithoutAnInfiniteFetch() async throws {
        let account = mailSyncAccount()
        let looping = MailSyncFixture(account: account, bootstrap: [.page(.init(messages: [], nextPage: "repeat")), .page(.init(messages: [], nextPage: "repeat"))])
        let sync = NativeMailSynchronizer(provider: looping)
        await #expect(throws: NativeMailFailure.invalidResponse) { try await sync.synchronize() }
        #expect(await looping.requests().count == 2)
        let missing = NativeMailSynchronizer(provider: MailSyncFixture(account: account, bootstrap: [.page(.init(messages: []))]))
        await #expect(throws: NativeMailFailure.invalidResponse) { try await missing.synchronize() }
    }

    @Test func rateLimitsRemainCategoricalAndUnexpectedErrorsDoNotLeakDetails() async throws {
        let account = mailSyncAccount()
        let provider = MailSyncFixture(account: account, bootstrap: [.failure(.rateLimited(45)), .unexpected])
        let sync = NativeMailSynchronizer(provider: provider)
        await #expect(throws: NativeMailFailure.rateLimited(45)) { try await sync.synchronize() }
        await #expect(throws: NativeMailFailure.unavailable) { try await sync.synchronize() }
    }
}

private func mailSyncAccount() -> NativeMailAccount {
    .init(service: .google, remoteID: "synthetic", address: "test@example.invalid")
}

private func mailSyncMessage(_ account: NativeMailAccount, _ id: String, at seconds: TimeInterval, unread: Bool = true) -> NativeMailSummary {
    .init(key: .init(accountID: account.id, remoteID: id), sender: "sender@example.invalid", subject: "Synthetic", receivedAt: Date(timeIntervalSince1970: seconds), isUnread: unread)
}

private final class MailSyncClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_000)
    func current() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); date += seconds; lock.unlock() }
}

private actor MailSyncGate<Value: Sendable> {
    private var result: Value?
    private var continuations: [CheckedContinuation<Value, Never>] = []
    private var started = false
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []
    func value() async -> Value {
        started = true
        startedContinuations.forEach { $0.resume() }
        startedContinuations.removeAll()
        if let result { return result }
        return await withCheckedContinuation { continuations.append($0) }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startedContinuations.append($0) }
    }
    func release(_ value: Value) {
        result = value
        continuations.forEach { $0.resume(returning: value) }
        continuations.removeAll()
    }
}

private enum MailSyncStep: Sendable {
    case page(NativeMailPage), failure(NativeMailFailure), gate(MailSyncGate<NativeMailPage>), unexpected
}

private actor MailSyncFixture: NativeMailProvider {
    nonisolated let account: NativeMailAccount
    private var initial: [MailSyncStep]
    private var updates: [MailSyncStep]
    private var requestLog: [String] = []
    private var bodies: [String: NativeMailContent] = [:]
    private var bodyGates: [String: MailSyncGate<NativeMailContent>] = [:]
    private var bodyCounts: [String: Int] = [:]
    init(account: NativeMailAccount, bootstrap: [MailSyncStep], changes: [MailSyncStep] = []) {
        self.account = account; initial = bootstrap; updates = changes
    }
    func bootstrap(pageToken: String?) async throws -> NativeMailPage {
        requestLog.append("bootstrap:\(pageToken ?? "-")")
        guard !initial.isEmpty else { throw NativeMailFailure.invalidResponse }
        return try await resolve(initial.removeFirst())
    }
    func changes(cursor: String, pageToken: String?) async throws -> NativeMailPage {
        requestLog.append("changes:\(cursor):\(pageToken ?? "-")")
        guard !updates.isEmpty else { throw NativeMailFailure.invalidResponse }
        return try await resolve(updates.removeFirst())
    }
    func fetchContent(for key: NativeMailMessageKey) async throws -> NativeMailContent {
        bodyCounts[key.remoteID, default: 0] += 1
        if let gate = bodyGates.removeValue(forKey: key.remoteID) { return await gate.value() }
        return bodies[key.remoteID] ?? .init(key: key, text: "Synthetic body")
    }
    func requests() -> [String] { requestLog }
    func bodyCount(_ id: String) -> Int { bodyCounts[id] ?? 0 }
    func setBody(_ body: NativeMailContent, for id: String? = nil) { bodies[id ?? body.key.remoteID] = body }
    func setBodyGate(_ gate: MailSyncGate<NativeMailContent>, for id: String) { bodyGates[id] = gate }
    func appendBootstrap(_ page: NativeMailPage) { initial.append(.page(page)) }
    private func resolve(_ step: MailSyncStep) async throws -> NativeMailPage {
        switch step {
        case .page(let page): return page
        case .failure(let failure): throw failure
        case .gate(let gate): return await gate.value()
        case .unexpected: throw FixturePrivateError()
        }
    }
    private struct FixturePrivateError: Error, CustomStringConvertible {
        var description: String { "Private message text and credentials must not be exposed" }
    }
}
