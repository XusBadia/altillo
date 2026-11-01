import Foundation

public enum NativeMailService: String, Codable, CaseIterable, Sendable {
    case google, microsoft, icloud, imap
}

/// Only account identity is persistent. Never add message content or credentials to this model.
public struct NativeMailAccount: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let service: NativeMailService
    public let remoteID: String
    public let address: String
    public let displayName: String
    public init(id: UUID = UUID(), service: NativeMailService, remoteID: String, address: String, displayName: String = "") {
        self.id = id; self.service = service; self.remoteID = remoteID; self.address = address; self.displayName = displayName
    }
}

public struct NativeMailIdentity: Equatable, Sendable {
    public let remoteID: String
    public let address: String
    public let displayName: String
    public init(remoteID: String, address: String, displayName: String = "") {
        self.remoteID = remoteID; self.address = address; self.displayName = displayName
    }
}

public struct NativeMailMessageKey: Hashable, Identifiable, Sendable {
    public let accountID: UUID
    public let remoteID: String
    public var id: Self { self }
    public init(accountID: UUID, remoteID: String) { self.accountID = accountID; self.remoteID = remoteID }
}

/// In-memory only. Provider identifiers are scoped to the local account, never globally deduplicated.
public struct NativeMailSummary: Identifiable, Equatable, Sendable {
    public var id: NativeMailMessageKey { key }
    public let key: NativeMailMessageKey
    public let sender: String
    public let subject: String
    public let preview: String
    public let receivedAt: Date
    public let isUnread: Bool
    public let webURL: URL?
    public let rfcMessageID: String?
    public let replyTo: String?
    public init(key: NativeMailMessageKey, sender: String, subject: String, preview: String = "", receivedAt: Date,
                isUnread: Bool = false, webURL: URL? = nil, rfcMessageID: String? = nil, replyTo: String? = nil) {
        self.key = key; self.sender = sender; self.subject = subject; self.preview = preview
        self.receivedAt = receivedAt; self.isUnread = isUnread; self.webURL = webURL; self.rfcMessageID = rfcMessageID
        self.replyTo = replyTo
    }
}

public struct NativeMailContent: Equatable, Sendable {
    public let key: NativeMailMessageKey
    public let text: String
    public let isTruncated: Bool
    public init(key: NativeMailMessageKey, text: String, isTruncated: Bool = false) {
        self.key = key; self.text = text; self.isTruncated = isTruncated
    }
}

public struct NativeMailPage: Sendable {
    public let messages: [NativeMailSummary]
    public let removedIDs: [String]
    public let nextPage: String?
    public let cursor: String?
    /// A complete bounded Inbox snapshot replaces the visible window without replaying old arrivals.
    public let isFullSnapshot: Bool
    /// A lost provider cursor requires a silent baseline rebuild.
    public let resetBaseline: Bool
    public init(messages: [NativeMailSummary], removedIDs: [String] = [], nextPage: String? = nil,
                cursor: String? = nil, isFullSnapshot: Bool = false, resetBaseline: Bool = false) {
        self.messages = messages; self.removedIDs = removedIDs; self.nextPage = nextPage; self.cursor = cursor
        self.isFullSnapshot = isFullSnapshot; self.resetBaseline = resetBaseline
    }
}

/// Categorical failures never carry HTTP bodies, bearer tokens, addresses or email text into UI/logs.
public enum NativeMailFailure: Error, Equatable, Sendable {
    case unauthorized, forbidden, unavailable, invalidResponse, cursorExpired, messageMissing, contentTooLarge
    case rateLimited(TimeInterval)
    case invalidDraft, unsupportedOperation, deliveryUncertain
}

public typealias NativeMailTokenLoader = @Sendable (_ forceRefresh: Bool) async throws -> String

public protocol NativeMailProvider: Sendable {
    var account: NativeMailAccount { get }
    func bootstrap(pageToken: String?) async throws -> NativeMailPage
    func changes(cursor: String, pageToken: String?) async throws -> NativeMailPage
    func fetchContent(for key: NativeMailMessageKey) async throws -> NativeMailContent
    func send(_ draft: NativeMailDraft) async throws -> NativeMailSendReceipt
    func setRead(_ isRead: Bool, for key: NativeMailMessageKey) async throws
    func archive(_ key: NativeMailMessageKey) async throws
    func trash(_ key: NativeMailMessageKey) async throws
    func attachments(for key: NativeMailMessageKey) async throws -> [NativeMailAttachment]
    func download(_ attachment: NativeMailAttachment) async throws -> Data
}

public extension NativeMailProvider {
    func send(_ draft: NativeMailDraft) async throws -> NativeMailSendReceipt { throw NativeMailFailure.unsupportedOperation }
    func setRead(_ isRead: Bool, for key: NativeMailMessageKey) async throws { throw NativeMailFailure.unsupportedOperation }
    func archive(_ key: NativeMailMessageKey) async throws { throw NativeMailFailure.unsupportedOperation }
    func trash(_ key: NativeMailMessageKey) async throws { throw NativeMailFailure.unsupportedOperation }
    func attachments(for key: NativeMailMessageKey) async throws -> [NativeMailAttachment] { [] }
    func download(_ attachment: NativeMailAttachment) async throws -> Data { throw NativeMailFailure.unsupportedOperation }
}

public struct NativeMailHTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let data: Data
    public init(status: Int, headers: [String: String] = [:], data: Data) {
        self.status = status; self.headers = headers; self.data = data
    }
}

public protocol NativeMailTransport: Sendable {
    func send(_ request: URLRequest, byteLimit: Int) async throws -> NativeMailHTTPResponse
}
