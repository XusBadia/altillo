import AltilloMail
import Foundation
import Testing
@testable import Altillo

@MainActor struct NativeMailControllerTests {
    @Test func stoppingWhileSuspendedDoesNotLeaveNextSessionPaused() async {
        let account = account("one")
        let message = summary(account, "message")
        let provider = ControllerMailProvider(account: account, pages: [page([message], "initial")])
        let controller = makeController([account], providers: [provider])
        let store = MailStore(startsServer: false, native: controller)
        store.selectConnectionMode(.direct)
        store.update(enabled: true)
        store.setSuspended(true)
        store.stop()
        store.update(enabled: true)
        #expect(!controller.isPaused)
        await controller.refresh()
        #expect(controller.messages == [message])
        store.stop()
    }

    @Test func baselineIsSilentAndOnlySubsequentRecentArrivalNotifies() async {
        let account = account("one")
        let old = summary(account, "baseline", date: .now.addingTimeInterval(-60))
        let provider = ControllerMailProvider(account: account, pages: [page([old], "initial")])
        let controller = makeController([account], providers: [provider])
        var arrivals: [NativeMailMessageKey] = []
        controller.onArrival = { summary, _ in arrivals.append(summary.key) }
        controller.setEnabled(true)
        await controller.refresh()
        #expect(controller.messages == [old])
        #expect(arrivals.isEmpty)
        let recent = summary(account, "arrival", date: .now)
        await provider.append(page([recent], "next"))
        await controller.refresh()
        #expect(arrivals == [recent.key])
        #expect(controller.states[account.id] == .connected)
        controller.setEnabled(false)
    }

    @Test(arguments: [false, true])
    func disableAndSuspendEraseReaderAndPreventFurtherRequests(suspend: Bool) async {
        let account = account("one")
        let message = summary(account, "message")
        let provider = ControllerMailProvider(account: account, pages: [page([message], "initial")])
        let controller = makeController([account], providers: [provider])
        controller.setEnabled(true)
        await controller.refresh()
        controller.read(message)
        await settle { controller.selectedContent != nil }
        #expect(controller.selectedContent != nil)
        var clearCount = 0
        controller.onContentCleared = { clearCount += 1 }
        if suspend { controller.setSuspended(true) } else { controller.setEnabled(false) }
        #expect(controller.messages.isEmpty)
        #expect(controller.selectedMessage == nil)
        #expect(controller.selectedContent == nil)
        #expect(controller.isPaused)
        #expect(clearCount == 1)
        let requests = await provider.requestCount
        await controller.refresh()
        controller.read(message)
        #expect(await provider.requestCount == requests)
        #expect(controller.actionEnvelope(for: message) == nil)
        controller.setEnabled(false)
    }

    @Test func lateRefreshCannotRepopulatePausedInbox() async {
        let account = account("one")
        let provider = ControllerMailProvider(account: account)
        await provider.setHoldPage(true)
        let controller = makeController([account], providers: [provider])
        controller.setEnabled(true)
        let refresh = Task { await controller.refresh() }
        await provider.waitForPageRequest()
        controller.setSuspended(true)
        await provider.completePage(page([summary(account, "late")], "cursor"))
        await refresh.value
        #expect(controller.messages.isEmpty)
        #expect(controller.states[account.id] == .paused)
        #expect(!controller.isRefreshing)
        controller.setEnabled(false)
    }

    @Test(arguments: [false, true])
    func lateConnectionDoesNotUpdateAccountsAfterPauseOrSuspend(suspend: Bool) async {
        let original = account("original"), added = account("added")
        let auth = ControllerMailAuth(accounts: [original])
        auth.holdConnection = true
        let provider = ControllerMailProvider(account: original)
        let controller = NativeMailController(auth: auth, providerFactory: { _ in provider }, automaticPolling: false)
        controller.setEnabled(true)
        let connection = Task { await controller.connect(.google) }
        await settle { auth.connectionContinuation != nil }
        if suspend { controller.setSuspended(true) } else { controller.setEnabled(false) }
        auth.completeConnection(added)
        #expect(await connection.value == false)
        #expect(controller.accounts == [original])
        #expect(controller.states[added.id] == nil)
        #expect(controller.messages.isEmpty)
        #expect(!controller.isConnecting)
        controller.setEnabled(false)
    }

    @Test func failedCredentialRemovalStillClearsContentAndRetainsRecoverableAccount() async {
        let account = account("one")
        let message = summary(account, "message")
        let auth = ControllerMailAuth(accounts: [account])
        auth.disconnectFailure = .credentialStorage
        let provider = ControllerMailProvider(account: account, pages: [page([message], "initial")])
        let controller = NativeMailController(auth: auth, providerFactory: { _ in provider }, automaticPolling: false)
        controller.setEnabled(true)
        await controller.refresh()
        controller.read(message)
        await settle { controller.selectedContent != nil }
        await controller.disconnect(account)
        #expect(controller.accounts == [account])
        #expect(controller.messages.isEmpty)
        #expect(controller.selectedContent == nil)
        #expect(controller.selectedMessage == nil)
        #expect(controller.problem == NativeMailController.explanation(MailAuthFailure.credentialStorage))
        #expect(controller.actionEnvelope(for: message) == nil)
        controller.setEnabled(false)
    }

    @Test func lateConnectionFailureCannotDisplayAnErrorInAnotherSession() async {
        let original = account("original")
        let auth = ControllerMailAuth(accounts: [original])
        auth.holdConnection = true
        let provider = ControllerMailProvider(account: original)
        let controller = NativeMailController(auth: auth, providerFactory: { _ in provider }, automaticPolling: false)
        controller.setEnabled(true)
        let connection = Task { await controller.connect(.google) }
        await settle { auth.connectionContinuation != nil }
        controller.setSuspended(true)
        auth.failConnection(.denied)
        #expect(await connection.value == false)
        #expect(controller.problem == nil)
        #expect(controller.accounts == [original])
        controller.setEnabled(false)
    }

    @Test(arguments: [false, true])
    func lateBodyCannotReopenReaderAfterPauseOrDisconnect(disconnect: Bool) async {
        let account = account("one")
        let message = summary(account, "message")
        let provider = ControllerMailProvider(account: account, pages: [page([message], "initial")])
        await provider.setHoldContent(true)
        let controller = makeController([account], providers: [provider])
        controller.setEnabled(true)
        await controller.refresh()
        controller.read(message)
        await provider.waitForContentRequest()
        if disconnect { await controller.disconnect(account) } else { controller.setSuspended(true) }
        await provider.completeContent(for: message.key)
        await settle { !controller.isReading }
        #expect(controller.selectedContent == nil)
        #expect(controller.selectedMessage == nil)
        #expect(controller.messages.isEmpty)
        if disconnect { #expect(controller.accounts.isEmpty) }
        controller.setEnabled(false)
    }

    @Test func sameRemoteMessageIDRemainsScopedToSelectedAccount() async {
        let first = account("one"), second = account("two")
        let one = summary(first, "same-provider-id"), two = summary(second, "same-provider-id")
        let providers = [ControllerMailProvider(account: first, pages: [page([one], "first")]),
                         ControllerMailProvider(account: second, pages: [page([two], "second")])]
        let controller = makeController([first, second], providers: providers)
        controller.setEnabled(true)
        await controller.refresh()
        #expect(controller.visibleMessages.count == 2)
        controller.selectedAccountID = first.id
        #expect(controller.visibleMessages == [one])
        controller.selectedAccountID = second.id
        #expect(controller.visibleMessages == [two])
        await controller.disconnect(second)
        #expect(controller.selectedAccountID == nil)
        #expect(controller.accounts == [first])
        controller.setEnabled(false)
    }

    @Test func originalMessageURLsRejectSpoofedHostsCredentialsAndUnexpectedPorts() {
        for string in ["http://mail.google.com/mail", "https://mail.google.com.evil.invalid/",
                       "https://mail.google.com@evil.invalid/", "https://user@mail.google.com/",
                       "https://mail.google.com:8443/", "file:///mail.google.com", "javascript:alert(1)"] {
            #expect(!NativeMailController.isProviderURL(URL(string: string)!, service: .google))
        }
        #expect(NativeMailController.isProviderURL(URL(string: "https://mail.google.com/mail/u/0/#inbox/123")!, service: .google))
        #expect(NativeMailController.isProviderURL(URL(string: "https://outlook.office.com/mail/inbox/id/123")!, service: .microsoft))
        #expect(!NativeMailController.isProviderURL(URL(string: "https://outlook.office.com/")!, service: .google))
        #expect(!NativeMailController.isProviderURL(URL(string: "https://mail.google.com/")!, service: nil))
    }

    @Test func codeActionsRespectFiveMinuteAgeAndInboxMembership() async {
        let account = account("one")
        let recent = summary(account, "recent", date: .now.addingTimeInterval(-30))
        let expired = summary(account, "expired", date: .now.addingTimeInterval(-301))
        let future = summary(account, "future", date: .now.addingTimeInterval(60))
        let provider = ControllerMailProvider(account: account, pages: [page([recent, expired, future], "initial")])
        let controller = makeController([account], providers: [provider])
        controller.setEnabled(true)
        await controller.refresh()
        #expect(controller.actionEnvelope(for: recent)?.code == "482913")
        #expect(controller.actionEnvelope(for: expired) == nil)
        #expect(controller.actionEnvelope(for: future) == nil)
        #expect(controller.actionEnvelope(for: summary(account, "not-loaded")) == nil)
        controller.setEnabled(false)
        #expect(controller.actionEnvelope(for: recent) == nil)
    }

    @Test(arguments: [NativeMailFailure.unauthorized, .forbidden, .unavailable])
    func providerFailuresHaveCategoricalAccountStateAndReconnectFailureKeepsAccount(failure: NativeMailFailure) async {
        let account = account("one")
        let auth = ControllerMailAuth(accounts: [account])
        let provider = ControllerMailProvider(account: account)
        await provider.setFailure(failure)
        let controller = NativeMailController(auth: auth, providerFactory: { _ in provider }, automaticPolling: false)
        controller.setEnabled(true)
        await controller.refresh()
        let expected: NativeMailController.ConnectionState = failure == .unauthorized ? .reconnect : (failure == .forbidden ? .denied : .offline)
        #expect(controller.states[account.id] == expected)
        auth.connectionFailure = .denied
        #expect(await controller.connect(.google, replacing: account) == false)
        #expect(controller.accounts == [account])
        #expect(controller.problem != nil)
        #expect(controller.states[account.id] == expected)
        controller.setEnabled(false)
    }

    private func makeController(_ accounts: [NativeMailAccount], providers: [ControllerMailProvider]) -> NativeMailController {
        let indexed = Dictionary(uniqueKeysWithValues: providers.map { ($0.account.id, $0) })
        return NativeMailController(auth: ControllerMailAuth(accounts: accounts),
                                    providerFactory: { indexed[$0.id]! }, automaticPolling: false)
    }

    private func account(_ remote: String) -> NativeMailAccount {
        NativeMailAccount(service: .google, remoteID: remote, address: "\(remote)@example.invalid")
    }

    private func summary(_ account: NativeMailAccount, _ remote: String, date: Date = .now) -> NativeMailSummary {
        NativeMailSummary(key: NativeMailMessageKey(accountID: account.id, remoteID: remote),
                          sender: "Synthetic", subject: "Verification code", preview: "Your verification code is 482913",
                          receivedAt: date)
    }

    private func page(_ messages: [NativeMailSummary], _ cursor: String) -> NativeMailPage {
        NativeMailPage(messages: messages, cursor: cursor)
    }

    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        #expect(condition(), "Asynchronous controller operation did not settle")
    }
}

@MainActor private final class ControllerMailAuth: NativeMailAuthenticating {
    let availableServices: [NativeMailService] = [.google, .microsoft]
    var accounts: [NativeMailAccount]
    var connectionFailure: MailAuthFailure?
    var disconnectFailure: MailAuthFailure?
    var holdConnection = false
    var connectionContinuation: CheckedContinuation<NativeMailAccount, Error>?
    init(accounts: [NativeMailAccount]) { self.accounts = accounts }
    func restoreAccounts() throws -> [NativeMailAccount] { accounts }
    func connect(service: NativeMailService, replacing: NativeMailAccount?) async throws -> NativeMailAccount {
        if let connectionFailure { throw connectionFailure }
        if holdConnection { return try await withCheckedThrowingContinuation { connectionContinuation = $0 } }
        return replacing ?? accounts[0]
    }
    func accessToken(for account: NativeMailAccount, forceRefresh: Bool) async throws -> String { "synthetic-token" }
    func disconnect(account: NativeMailAccount) async throws {
        if let disconnectFailure { throw disconnectFailure }
        accounts.removeAll { $0.id == account.id }
    }
    func completeConnection(_ account: NativeMailAccount) {
        connectionContinuation?.resume(returning: account)
        connectionContinuation = nil
    }
    func failConnection(_ failure: MailAuthFailure) {
        connectionContinuation?.resume(throwing: failure)
        connectionContinuation = nil
    }
    func cancel() {}
}

private actor ControllerMailProvider: NativeMailProvider {
    nonisolated let account: NativeMailAccount
    private var pages: [NativeMailPage]
    private var failure: NativeMailFailure?
    private var holdPage = false
    private var holdContent = false
    private var pageContinuation: CheckedContinuation<NativeMailPage, Error>?
    private var contentContinuation: CheckedContinuation<NativeMailContent, Error>?
    private var pageWaiter: CheckedContinuation<Void, Never>?
    private var contentWaiter: CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0

    init(account: NativeMailAccount, pages: [NativeMailPage] = []) { self.account = account; self.pages = pages }
    func append(_ page: NativeMailPage) { pages.append(page) }
    func setFailure(_ failure: NativeMailFailure) { self.failure = failure }
    func setHoldPage(_ hold: Bool) { holdPage = hold }
    func setHoldContent(_ hold: Bool) { holdContent = hold }
    func bootstrap(pageToken: String?) async throws -> NativeMailPage { try await nextPage() }
    func changes(cursor: String, pageToken: String?) async throws -> NativeMailPage { try await nextPage() }
    private func nextPage() async throws -> NativeMailPage {
        requestCount += 1
        if let failure { throw failure }
        if holdPage {
            return try await withCheckedThrowingContinuation { continuation in
                pageContinuation = continuation
                pageWaiter?.resume(); pageWaiter = nil
            }
        }
        guard !pages.isEmpty else { return NativeMailPage(messages: [], cursor: "unchanged") }
        return pages.removeFirst()
    }
    func fetchContent(for key: NativeMailMessageKey) async throws -> NativeMailContent {
        requestCount += 1
        if holdContent {
            return try await withCheckedThrowingContinuation { continuation in
                contentContinuation = continuation
                contentWaiter?.resume(); contentWaiter = nil
            }
        }
        return NativeMailContent(key: key, text: "Your verification code is 482913")
    }
    func waitForPageRequest() async {
        if pageContinuation != nil { return }
        await withCheckedContinuation { pageWaiter = $0 }
    }
    func waitForContentRequest() async {
        if contentContinuation != nil { return }
        await withCheckedContinuation { contentWaiter = $0 }
    }
    func completePage(_ page: NativeMailPage) { pageContinuation?.resume(returning: page); pageContinuation = nil }
    func completeContent(for key: NativeMailMessageKey) {
        contentContinuation?.resume(returning: NativeMailContent(key: key, text: "late synthetic body"))
        contentContinuation = nil
    }
}
