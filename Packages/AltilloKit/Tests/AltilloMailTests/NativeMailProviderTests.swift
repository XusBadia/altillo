import Foundation
import Testing
@testable import AltilloMail

private actor NativeFixtureTransport: NativeMailTransport {
    typealias Handler = @Sendable (URLRequest, Int) throws -> NativeMailHTTPResponse
    let handler: Handler
    private var requests: [URLRequest] = []
    init(_ handler: @escaping Handler) { self.handler = handler }
    func send(_ request: URLRequest, byteLimit: Int) async throws -> NativeMailHTTPResponse {
        requests.append(request)
        return try handler(request, requests.count)
    }
    func captured() -> [URLRequest] { requests }
}

private actor NativeTokenProbe {
    private var refreshes: [Bool] = []
    func load(_ force: Bool) -> String { refreshes.append(force); return force ? "synthetic-fresh" : "synthetic-old" }
    func captured() -> [Bool] { refreshes }
}

struct NativeMailProviderTests {
    private static func json(_ value: Any, status: Int = 200, headers: [String: String] = [:]) throws -> NativeMailHTTPResponse {
        .init(status: status, headers: headers, data: try JSONSerialization.data(withJSONObject: value))
    }
    private func account(_ service: NativeMailService = .google) -> NativeMailAccount {
        .init(service: service, remoteID: "identity", address: "test@example.invalid")
    }
    private static func googleMessage(_ id: String, labels: [String] = ["INBOX", "UNREAD"]) -> [String: Any] {
        ["id": id, "labelIds": labels, "internalDate": "1793520000000", "snippet": "Your &amp; code",
         "payload": ["headers": [["name": "From", "value": "Sender <sender@example.invalid>"],
                                     ["name": "Subject", "value": "=?UTF-8?Q?Security_code=3A_482913?="],
                                     ["name": "Message-ID", "value": "<fixture@example.invalid>"]]]]
    }
    private static func graphMessage(_ id: String, webLink: String = "https://outlook.office.com/mail/inbox/id/fixture") -> [String: Any] {
        ["id": id, "subject": "Synthetic", "from": ["emailAddress": ["name": "Sender", "address": "sender@example.invalid"]],
         "bodyPreview": "Preview", "receivedDateTime": "2026-11-01T09:20:00.000Z", "isRead": false,
         "webLink": webLink, "internetMessageId": "<fixture@example.invalid>"]
    }

    @Test func googleBootstrapCapturesCheckpointThenLoadsOnlyRecentInboxMetadata() async throws {
        let transport = NativeFixtureTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/profile") { return try Self.json(["historyId": "100", "emailAddress": "test@example.invalid"]) }
            if path.hasSuffix("/messages") { return try Self.json(["messages": [["id": "a"], ["id": "a"], ["id": "b"]], "nextPageToken": "older-history"]) }
            if path.hasSuffix("/a") { return try Self.json(Self.googleMessage("a")) }
            return try Self.json(Self.googleMessage("b", labels: ["SPAM"]))
        }
        let owner = account()
        let provider = GoogleNativeMailProvider(account: owner, token: { _ in "synthetic" }, transport: transport)
        let page = try await provider.bootstrap(pageToken: nil)
        #expect(page.cursor == "100" && page.nextPage == nil && page.isFullSnapshot)
        #expect(page.messages.count == 1)
        #expect(page.messages[0].key == .init(accountID: owner.id, remoteID: "a"))
        #expect(page.messages[0].subject == "Security code: 482913")
        #expect(page.messages[0].preview == "Your & code")
        #expect(page.messages[0].isUnread)
        #expect(page.messages[0].webURL?.host == "mail.google.com")
        let requests = await transport.captured()
        #expect(requests.first?.url?.path.hasSuffix("/profile") == true)
        #expect(requests.count == 4)
        #expect(requests.filter { $0.url!.path.hasSuffix("/a") }.first?.url?.query?.contains("format=metadata") == true)
    }

    @Test func gmailHistoryPagesKeepCursorUntilCompletionAndResolveFinalInboxState() async throws {
        let transport = NativeFixtureTransport { request, _ in
            let url = request.url!
            if url.path.hasSuffix("/history") {
                if url.query?.contains("pageToken=next") == true { return try Self.json(["historyId": "120"]) }
                return try Self.json(["historyId": "120", "nextPageToken": "next", "history": [
                    ["messagesAdded": [["message": ["id": "new"]]],
                     "labelsRemoved": [["message": ["id": "moved"], "labelIds": ["INBOX"]]],
                     "labelsAdded": [["message": ["id": "moved"], "labelIds": ["INBOX"]]],
                     "messagesDeleted": [["message": ["id": "gone"]]]]
                ]])
            }
            return try Self.json(Self.googleMessage(url.lastPathComponent))
        }
        let provider = GoogleNativeMailProvider(account: account(), token: { _ in "synthetic" }, transport: transport)
        let first = try await provider.changes(cursor: "100", pageToken: nil)
        #expect(first.cursor == nil && first.nextPage == "next")
        #expect(Set(first.messages.map { $0.key.remoteID }) == ["new", "moved"])
        #expect(first.removedIDs == ["gone"])
        let last = try await provider.changes(cursor: "100", pageToken: first.nextPage)
        #expect(last.cursor == "120" && last.nextPage == nil)
    }

    @Test func aLostGoogleCursorIsCategoricalAndDoesNotLeakTheResponse() async throws {
        let transport = NativeFixtureTransport { _, _ in try Self.json(["error": "private body"], status: 404) }
        let provider = GoogleNativeMailProvider(account: account(), token: { _ in "synthetic" }, transport: transport)
        await #expect(throws: NativeMailFailure.cursorExpired) { _ = try await provider.changes(cursor: "123", pageToken: nil) }
    }

    @Test func unauthorizedRetriesExactlyOnceWithForcedTokenRenewal() async throws {
        let probe = NativeTokenProbe()
        let transport = NativeFixtureTransport { _, count in
            try Self.json(count == 1 ? ["error": "synthetic"] : ["value": []], status: count == 1 ? 401 : 200)
        }
        let provider = MicrosoftNativeMailProvider(account: account(.microsoft), token: { await probe.load($0) }, transport: transport)
        let page = try await provider.bootstrap(pageToken: nil)
        #expect(page.isFullSnapshot && page.cursor == "snapshot-v1")
        #expect(await probe.captured() == [false, true])
        let requests = await transport.captured()
        #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer synthetic-old", "Bearer synthetic-fresh"])
        let denied = NativeFixtureTransport { _, _ in try Self.json(["error": "private"], status: 401) }
        let failing = MicrosoftNativeMailProvider(account: account(.microsoft), token: { _ in "synthetic" }, transport: denied)
        await #expect(throws: NativeMailFailure.unauthorized) { _ = try await failing.bootstrap(pageToken: nil) }
        #expect(await denied.captured().count == 2)
    }

    @Test func graphSnapshotTracksReadStateAndUsesAccountScopedImmutableIDs() async throws {
        let transport = NativeFixtureTransport { _, _ in try Self.json(["value": [Self.graphMessage("same-id", webLink: "https://phishing.invalid/message")]]) }
        let firstAccount = account(.microsoft), secondAccount = account(.microsoft)
        let first = try await MicrosoftNativeMailProvider(account: firstAccount, token: { _ in "synthetic" }, transport: transport).bootstrap(pageToken: nil)
        let second = try await MicrosoftNativeMailProvider(account: secondAccount, token: { _ in "synthetic" }, transport: transport).changes(cursor: "snapshot-v1", pageToken: nil)
        #expect(first.messages[0].key != second.messages[0].key)
        #expect(first.messages[0].isUnread && first.messages[0].webURL == nil)
        let requests = await transport.captured()
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Prefer")?.contains("ImmutableId") == true })
    }

    @Test(arguments: ["https://graph.microsoft.com.evil.invalid/v1.0/me/mailFolders/inbox/messages", "http://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages", "https://graph.microsoft.com:444/v1.0/me/mailFolders/inbox/messages", "https://user@graph.microsoft.com/v1.0/me/mailFolders/inbox/messages", "https://graph.microsoft.com/v1.0/users/other/messages", "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages#leak"])
    func graphRejectsUntrustedPagingDestinationsBeforeSendingCredentials(_ next: String) async throws {
        let transport = NativeFixtureTransport { _, _ in try Self.json(["value": [], "@odata.nextLink": next]) }
        let provider = MicrosoftNativeMailProvider(account: account(.microsoft), token: { _ in "synthetic" }, transport: transport)
        await #expect(throws: NativeMailFailure.invalidResponse) { _ = try await provider.bootstrap(pageToken: nil) }
        #expect(await transport.captured().count == 1)
    }

    @Test func bodyExtractionPrefersPlainTextAndNeverDownloadsAnAttachment() async throws {
        func encoded(_ value: String) -> String { Data(value.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
        let plain = encoded("Your verification code is 482913"), html = encoded("<script>secret</script><p>Wrong code</p>"), attachment = encoded("Do not expose this attachment")
        let payload: [String: Any] = ["id": "m", "payload": ["mimeType": "multipart/mixed", "parts": [
            ["mimeType": "text/html", "body": ["data": html]], ["mimeType": "text/plain", "body": ["data": plain]],
            ["mimeType": "text/plain", "filename": "attachment.txt", "body": ["data": attachment, "attachmentId": "never-fetch"]]
        ]]]
        let data = try Self.json(payload).data
        let transport = NativeFixtureTransport { _, _ in .init(status: 200, data: data) }
        let owner = account(), key = NativeMailMessageKey(accountID: owner.id, remoteID: "m")
        let content = try await GoogleNativeMailProvider(account: owner, token: { _ in "synthetic" }, transport: transport).fetchContent(for: key)
        #expect(content.text == "Your verification code is 482913" && !content.isTruncated)
        #expect(await transport.captured().count == 1)
    }

    @Test func graphHTMLFallbackIsSanitizedAndBodiesAreBoundedWithoutBreakingUnicode() async throws {
        let owner = account(.microsoft), key = NativeMailMessageKey(accountID: owner.id, remoteID: "m")
        let htmlData = try Self.json(["id": "m", "body": ["contentType": "html", "content": "<p>Code: 482913</p><img src='https://tracker.invalid'><script>steal()</script>"]]).data
        let htmlTransport = NativeFixtureTransport { _, _ in .init(status: 200, data: htmlData) }
        let html = try await MicrosoftNativeMailProvider(account: owner, token: { _ in "synthetic" }, transport: htmlTransport).fetchContent(for: key)
        #expect(html.text == "Code: 482913")
        let body = String(repeating: "a", count: NativeMailText.bodyByteLimit - 1) + "🙂"
        let largeData = try Self.json(["id": "m", "body": ["contentType": "text", "content": body]]).data
        let largeTransport = NativeFixtureTransport { _, _ in .init(status: 200, data: largeData) }
        let large = try await MicrosoftNativeMailProvider(account: owner, token: { _ in "synthetic" }, transport: largeTransport).fetchContent(for: key)
        #expect(large.isTruncated && large.text.utf8.count <= NativeMailText.bodyByteLimit)
        #expect(!large.text.contains("�"))
    }

    @Test func wireLimitAndCrossAccountRequestsFailBeforeExposingContent() async throws {
        let transport = NativeFixtureTransport { _, _ in .init(status: 200, data: Data(repeating: 65, count: 4_194_305)) }
        let owner = account(.microsoft)
        let provider = MicrosoftNativeMailProvider(account: owner, token: { _ in "synthetic" }, transport: transport)
        await #expect(throws: NativeMailFailure.invalidResponse) {
            _ = try await provider.fetchContent(for: .init(accountID: UUID(), remoteID: "m"))
        }
        #expect(await transport.captured().isEmpty)
        await #expect(throws: NativeMailFailure.contentTooLarge) { _ = try await provider.fetchContent(for: .init(accountID: owner.id, remoteID: "m")) }
    }

    @Test func throttlingHonoursSecondsAndHTTPDatesWithoutReturningPrivateHTTPBodies() async throws {
        let transport = NativeFixtureTransport { _, _ in try Self.json(["error": "private message"], status: 429, headers: ["Retry-After": "7"]) }
        let provider = MicrosoftNativeMailProvider(account: account(.microsoft), token: { _ in "synthetic" }, transport: transport)
        await #expect(throws: NativeMailFailure.rateLimited(7)) { _ = try await provider.bootstrap(pageToken: nil) }
        let now = Date(timeIntervalSince1970: 0)
        #expect(NativeMailAPI.retryDelay("Thu, 01 Jan 1970 00:01:00 GMT", now: now) == 60)
    }

    @Test func identitiesUseStableProviderIDsAndVerifyGoogleMailboxAccess() async throws {
        let transport = NativeFixtureTransport { request, _ in
            if request.url!.host == "openidconnect.googleapis.com" { return try Self.json(["sub": "stable-google", "email": "alias@example.invalid", "email_verified": true, "name": "Fixture"]) }
            if request.url!.host == "gmail.googleapis.com" { return try Self.json(["emailAddress": "mailbox@example.invalid", "historyId": "100"]) }
            return try Self.json(["id": "stable-microsoft", "mail": "outlook@example.invalid", "displayName": "Fixture"])
        }
        let google = try await NativeMailIdentityResolver.resolve(service: .google, token: "synthetic", transport: transport)
        let microsoft = try await NativeMailIdentityResolver.resolve(service: .microsoft, token: "synthetic", transport: transport)
        #expect(google.remoteID == "stable-google" && google.address == "mailbox@example.invalid")
        #expect(microsoft.remoteID == "stable-microsoft")
    }
}
