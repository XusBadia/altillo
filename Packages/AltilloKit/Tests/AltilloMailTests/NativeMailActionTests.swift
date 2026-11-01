import Foundation
import Testing
@testable import AltilloMail

private actor ActionFixtureTransport: NativeMailTransport {
    private var requests: [URLRequest] = []
    private let handler: @Sendable (URLRequest, Int) throws -> NativeMailHTTPResponse
    init(_ handler: @escaping @Sendable (URLRequest, Int) throws -> NativeMailHTTPResponse) { self.handler = handler }
    func send(_ request: URLRequest, byteLimit: Int) async throws -> NativeMailHTTPResponse {
        requests.append(request)
        return try handler(request, requests.count)
    }
    func captured() -> [URLRequest] { requests }
}

struct NativeMailActionTests {
    private let google = NativeMailAccount(service: .google, remoteID: "g", address: "sender@example.invalid")
    private let microsoft = NativeMailAccount(service: .microsoft, remoteID: "m", address: "sender@example.invalid")
    private static func json(_ object: Any, status: Int = 200) throws -> NativeMailHTTPResponse {
        .init(status: status, data: try JSONSerialization.data(withJSONObject: object))
    }
    private var draft: NativeMailDraft {
        .init(to: ["to@example.invalid"], cc: ["cc@example.invalid"], bcc: ["private@example.invalid"], subject: "Código", text: "Synthetic body", inReplyTo: "<original@example.invalid>",
              attachments: [.init(filename: "prueba-é.txt", mimeType: "text/plain", data: Data("Attachment".utf8))])
    }

    @Test func mimePreservesReplyAndAttachmentButOmitsBccForSMTP() throws {
        let encoded = try NativeMailMIME.encode(draft: draft, from: google.address)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains("In-Reply-To: <original@example.invalid>\r\nReferences:"))
        #expect(!text.contains("private@example.invalid"))
        #expect(text.contains("filename*=utf-8''prueba-%C3%A9.txt"))
        #expect(text.contains(Data("Attachment".utf8).base64EncodedString()))
        #expect(!text.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        #expect(text.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 998 })
        let api = try NativeMailMIME.encode(draft: draft, from: google.address, includeBcc: true)
        #expect(String(decoding: api, as: UTF8.self).contains("Bcc: private@example.invalid"))
    }

    @Test func mimeRejectsHeaderInjectionAndOversizedAttachmentsBeforeNetwork() throws {
        var bad = draft; bad.subject = "Subject\r\nBcc: injected@example.invalid"
        #expect(throws: NativeMailFailure.invalidDraft) { try NativeMailMIME.validateDraft(bad) }
        bad = draft; bad.to = ["name <to@example.invalid>"]
        #expect(throws: NativeMailFailure.invalidDraft) { try NativeMailMIME.validateDraft(bad) }
        bad = draft; bad.inReplyTo = "<id@example.invalid>\r\nX: injected"
        #expect(throws: NativeMailFailure.invalidDraft) { try NativeMailMIME.validateDraft(bad) }
        bad = draft; bad.attachments = [.init(filename: "huge.bin", mimeType: "application/octet-stream", data: Data(repeating: 0, count: NativeMailMIME.outgoingByteLimit + 1))]
        #expect(throws: NativeMailFailure.contentTooLarge) { try NativeMailMIME.validateDraft(bad) }
    }

    @Test func gmailReplyResolvesThreadAndRawContainsRecipientsAndReplyHeaders() async throws {
        let transport = ActionFixtureTransport { request, count in
            if count == 1 { return try Self.json(["messages": [["id": "original"]]]) }
            if count == 2 { return try Self.json(["id": "original", "threadId": "thread-1"]) }
            let object = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
            #expect(object["threadId"] == "thread-1")
            let mime = try nativeMailAttachmentData(object["raw"]!)
            #expect(String(decoding: mime, as: UTF8.self).contains("Bcc: private@example.invalid"))
            #expect(request.httpMethod == "POST")
            #expect(request.url!.path.hasSuffix("/messages/send"))
            return try Self.json(["id": "sent"])
        }
        let provider = GoogleNativeMailProvider(account: google, token: { _ in "synthetic" }, transport: transport)
        #expect(try await provider.send(draft).remoteID == "sent")
    }

    @Test(arguments: [500, 503, 408]) func sendNeverRetriesAmbiguousFailure(_ status: Int) async throws {
        let transport = ActionFixtureTransport { _, _ in .init(status: status, data: Data()) }
        let provider = MicrosoftNativeMailProvider(account: microsoft, token: { _ in "synthetic" }, transport: transport)
        await #expect(throws: NativeMailFailure.deliveryUncertain) { try await provider.send(draft) }
        #expect(await transport.captured().count == 1)
    }

    @Test func sendTimeoutIsUncertainAndDoesNotRetry() async throws {
        let transport = ActionFixtureTransport { _, _ in throw URLError(.timedOut) }
        let provider = GoogleNativeMailProvider(account: google, token: { _ in "synthetic" }, transport: transport)
        let value = NativeMailDraft(to: ["to@example.invalid"], subject: "Test", text: "Synthetic")
        await #expect(throws: NativeMailFailure.deliveryUncertain) { try await provider.send(value) }
        #expect(await transport.captured().count == 1)
    }

    @Test func googleReadArchiveAndTrashUseReversibleEndpoints() async throws {
        let transport = ActionFixtureTransport { _, _ in try Self.json(["id": "a"]) }
        let provider = GoogleNativeMailProvider(account: google, token: { _ in "synthetic" }, transport: transport)
        let key = NativeMailMessageKey(accountID: google.id, remoteID: "a")
        try await provider.setRead(false, for: key); try await provider.archive(key); try await provider.trash(key)
        let requests = await transport.captured()
        let values = try requests.prefix(2).map { try JSONSerialization.jsonObject(with: $0.httpBody!) as! [String: [String]] }
        #expect(values[0] == ["addLabelIds": ["UNREAD"]])
        #expect(values[1] == ["removeLabelIds": ["INBOX"]])
        #expect(requests.last!.url!.path.hasSuffix("/trash"))
        #expect(!requests.contains { $0.httpMethod == "DELETE" })
    }

    @Test func graphMovesToWellKnownFoldersAndRejectsForeignAccount() async throws {
        let transport = ActionFixtureTransport { _, _ in try Self.json(["id": "a"]) }
        let provider = MicrosoftNativeMailProvider(account: microsoft, token: { _ in "synthetic" }, transport: transport)
        let key = NativeMailMessageKey(accountID: microsoft.id, remoteID: "a")
        try await provider.setRead(true, for: key); try await provider.archive(key); try await provider.trash(key)
        let requests = await transport.captured()
        #expect(requests.first!.httpMethod == "PATCH")
        let destinations = try requests.dropFirst().map { try JSONSerialization.jsonObject(with: $0.httpBody!) as! [String: String] }
        #expect(destinations == [["destinationId": "archive"], ["destinationId": "deleteditems"]])
        await #expect(throws: NativeMailFailure.invalidResponse) { try await provider.trash(.init(accountID: UUID(), remoteID: "a")) }
        #expect(await transport.captured().count == 3)
    }

    @Test func googleAttachmentMetadataAndBoundedManualDownload() async throws {
        let transport = ActionFixtureTransport { request, _ in
            if request.url!.path.contains("/attachments/") { return try Self.json(["size": 3, "data": "YWJj"]) }
            return try Self.json(["id": "a", "payload": ["parts": [["partId": "1", "filename": "safe.txt", "mimeType": "text/plain", "body": ["attachmentId": "file", "size": 3]]]]])
        }
        let provider = GoogleNativeMailProvider(account: google, token: { _ in "synthetic" }, transport: transport)
        let files = try await provider.attachments(for: .init(accountID: google.id, remoteID: "a"))
        #expect(files.count == 1 && files[0].filename == "safe.txt")
        #expect(try await provider.download(files[0]) == Data("abc".utf8))
        let huge = NativeMailAttachment(key: files[0].key, remoteID: "huge", filename: "huge", mimeType: "application/octet-stream", byteCount: NativeMailMIME.attachmentDownloadByteLimit + 1)
        await #expect(throws: NativeMailFailure.contentTooLarge) { try await provider.download(huge) }
        #expect(await transport.captured().count == 2)
    }

    @Test func graphAttachmentPagingCannotExfiltrateToken() async throws {
        let transport = ActionFixtureTransport { _, _ in try Self.json(["value": [], "@odata.nextLink": "https://evil.invalid/steal"]) }
        let provider = MicrosoftNativeMailProvider(account: microsoft, token: { _ in "synthetic" }, transport: transport)
        await #expect(throws: NativeMailFailure.invalidResponse) { try await provider.attachments(for: .init(accountID: microsoft.id, remoteID: "a")) }
        #expect(await transport.captured().count == 1)
    }
    @Test(arguments: [false, true]) func graphLargeAttachmentUsesCapabilityWithoutBearerThenSendsOnlyOnce(_ openRange: Bool) async throws {
        let total = 4_200_000
        let transport = ActionFixtureTransport { request, count in
            switch count {
            case 1:
                #expect(request.url!.path.hasSuffix("/me/messages"))
                return try Self.json(["id": "draft-1"], status: 201)
            case 2:
                #expect(request.url!.path.hasSuffix("/attachments/createUploadSession"))
                return try Self.json(["uploadUrl": "https://outlook.office.com/api/v2.0/Users('synthetic')/Messages('draft-1')/AttachmentSessions('synthetic')?authtoken=synthetic", "nextExpectedRanges": [openRange ? "0-" : "0"]], status: 201)
            case 3:
                #expect(request.httpMethod == "PUT")
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.value(forHTTPHeaderField: "Content-Range") == "bytes 0-3276799/4200000")
                #expect(request.httpBody!.count == 3_276_800)
                return try Self.json(["nextExpectedRanges": [openRange ? "3276800-" : "3276800"]])
            case 4:
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.value(forHTTPHeaderField: "Content-Range") == "bytes 3276800-4199999/4200000")
                return .init(status: 201, data: Data())
            default:
                #expect(count == 5 && request.url!.path.hasSuffix("/draft-1/send"))
                return .init(status: 202, data: Data())
            }
        }
        let provider = MicrosoftNativeMailProvider(account: microsoft, token: { _ in "synthetic" }, transport: transport)
        var value = draft; value.inReplyTo = nil
        value.attachments = [.init(filename: "large.bin", mimeType: "application/octet-stream", data: Data(repeating: 5, count: total))]
        #expect(try await provider.send(value).remoteID == "draft-1")
        #expect(await transport.captured().count == 5)
    }

    @Test func graphReplyUsesAccountScopedCreateReplyBeforeSend() async throws {
        let transport = ActionFixtureTransport { request, count in
            if count == 1 {
                #expect(request.url!.path.hasSuffix("/original/createReply"))
                return try Self.json(["id": "reply-draft"], status: 201)
            }
            #expect(count == 2 && request.url!.path.hasSuffix("/reply-draft/send"))
            return .init(status: 202, data: Data())
        }
        let provider = MicrosoftNativeMailProvider(account: microsoft, token: { _ in "synthetic" }, transport: transport)
        var value = draft; value.attachments = []; value.replyingTo = .init(accountID: microsoft.id, remoteID: "original")
        #expect(try await provider.send(value).remoteID == "reply-draft")
        value.replyingTo = .init(accountID: UUID(), remoteID: "original")
        await #expect(throws: NativeMailFailure.invalidResponse) { try await provider.send(value) }
        #expect(await transport.captured().count == 2)
    }

    @Test func maliciousUploadCapabilityIsRejectedWithoutSendingFile() async throws {
        let transport = ActionFixtureTransport { _, count in
            if count == 1 { return try Self.json(["id": "draft-1"], status: 201) }
            return try Self.json(["uploadUrl": "https://evil.invalid/api/AttachmentSessions('leak')", "nextExpectedRanges": ["0"]], status: 201)
        }
        let provider = MicrosoftNativeMailProvider(account: microsoft, token: { _ in "synthetic" }, transport: transport)
        var value = draft; value.attachments = [.init(filename: "large.bin", mimeType: "application/octet-stream", data: Data(repeating: 0, count: 4_200_000))]
        await #expect(throws: NativeMailFailure.invalidResponse) { try await provider.send(value) }
        #expect(await transport.captured().count == 2)
    }

    @Test func rejectedSendRefreshesOnceWithIdenticalPayload() async throws {
        let transport = ActionFixtureTransport { request, count in
            #expect(request.value(forHTTPHeaderField: "Authorization") == (count == 1 ? "Bearer old" : "Bearer refreshed"))
            return .init(status: count == 1 ? 401 : 202, data: Data())
        }
        let provider = MicrosoftNativeMailProvider(account: microsoft, token: { $0 ? "refreshed" : "old" }, transport: transport)
        _ = try await provider.send(draft)
        let requests = await transport.captured()
        #expect(requests.count == 2)
        #expect(requests[0].httpBody == requests[1].httpBody)
    }

    @Test func graphListsOnlyFileAttachmentsAndDownloadsBytesWithoutPreview() async throws {
        let transport = ActionFixtureTransport { request, count in
            if count == 1 {
                #expect(!request.url!.query!.contains("contentBytes"))
                return try Self.json(["value": [
                    ["id": "file", "name": "synthetic.txt", "size": 3, "contentType": "text/plain", "@odata.type": "#microsoft.graph.fileAttachment"],
                    ["id": "link", "name": "cloud", "size": 0, "@odata.type": "#microsoft.graph.referenceAttachment"]
                ]])
            }
            #expect(request.url!.path.hasSuffix("/file/$value"))
            return .init(status: 200, data: Data("abc".utf8))
        }
        let provider = MicrosoftNativeMailProvider(account: microsoft, token: { _ in "synthetic" }, transport: transport)
        let files = try await provider.attachments(for: .init(accountID: microsoft.id, remoteID: "a"))
        #expect(files.count == 1 && files[0].remoteID == "file")
        #expect(try await provider.download(files[0]) == Data("abc".utf8))
    }

}
