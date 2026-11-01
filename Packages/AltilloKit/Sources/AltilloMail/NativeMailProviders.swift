import Foundation

/// Gmail: an initial Inbox window followed by history changes and explicit message operations.
public struct GoogleNativeMailProvider: NativeMailProvider {
    public let account: NativeMailAccount
    let api: NativeMailAPI
    static let base = "https://gmail.googleapis.com/gmail/v1/users/me"

    public init(account: NativeMailAccount, token: @escaping NativeMailTokenLoader,
                transport: any NativeMailTransport = URLSessionNativeMailTransport()) {
        self.account = account
        api = .init(token: token, transport: transport, allowedHosts: ["gmail.googleapis.com"])
    }

    public func bootstrap(pageToken: String?) async throws -> NativeMailPage {
        guard account.service == .google, pageToken == nil else { throw NativeMailFailure.invalidResponse }
        // Capture the checkpoint BEFORE listing: arrivals during bootstrap are not lost between calls.
        let profile = try nativeMailDecode(GmailProfile.self, from: await api.get(try nativeMailURL(Self.base + "/profile")))
        guard Self.validHistoryID(profile.historyId) else { throw NativeMailFailure.invalidResponse }
        let url = try nativeMailURL(Self.base + "/messages", query: [
            .init(name: "labelIds", value: "INBOX"), .init(name: "maxResults", value: "50")
        ])
        let list = try nativeMailDecode(GmailList.self, from: await api.get(url))
        let ids = Array(Set((list.messages ?? []).prefix(50).map(\.id)))
        let messages = try await metadata(ids)
        // Only the recent window is displayed. Traversing historical list pages is deliberately unnecessary.
        return .init(messages: messages, cursor: profile.historyId, isFullSnapshot: true)
    }

    public func changes(cursor: String, pageToken: String?) async throws -> NativeMailPage {
        guard account.service == .google, Self.validHistoryID(cursor) else { throw NativeMailFailure.cursorExpired }
        var query = [URLQueryItem(name: "startHistoryId", value: cursor), .init(name: "maxResults", value: "100")]
        if let pageToken {
            guard !pageToken.isEmpty, pageToken.utf8.count <= 4_096 else { throw NativeMailFailure.invalidResponse }
            query.append(.init(name: "pageToken", value: pageToken))
        }
        let history = try nativeMailDecode(GmailHistory.self, from: await api.get(try nativeMailURL(Self.base + "/history", query: query), notFound: .cursorExpired))
        var changed = Set<String>(), removed = Set<String>(), deleted = Set<String>()
        for entry in history.history ?? [] {
            for value in entry.messages ?? [] { changed.insert(value.id) }
            for value in entry.messagesAdded ?? [] { changed.insert(value.message.id) }
            for value in entry.messagesDeleted ?? [] { removed.insert(value.message.id); deleted.insert(value.message.id) }
            for value in entry.labelsAdded ?? [] { changed.insert(value.message.id) }
            for value in entry.labelsRemoved ?? [] {
                changed.insert(value.message.id)
                if value.labelIds?.contains("INBOX") == true { removed.insert(value.message.id) }
            }
        }
        // A provider page with an unexpectedly huge batch is rebuilt silently rather than allocating history.
        guard changed.count <= 500, removed.count <= 500 else { throw NativeMailFailure.cursorExpired }
        changed.subtract(deleted)
        let resolved = try await metadataWithRemovals(Array(changed))
        removed.formUnion(resolved.removed)
        removed.subtract(resolved.messages.map { $0.key.remoteID })
        let nextPage = history.nextPageToken
        if let nextPage, nextPage.isEmpty || nextPage.utf8.count > 4_096 { throw NativeMailFailure.invalidResponse }
        let nextCursor = nextPage == nil ? history.historyId : nil
        if nextPage == nil, !Self.validHistoryID(nextCursor) { throw NativeMailFailure.invalidResponse }
        return .init(messages: resolved.messages, removedIDs: Array(removed), nextPage: nextPage, cursor: nextCursor)
    }

    public func fetchContent(for key: NativeMailMessageKey) async throws -> NativeMailContent {
        guard key.accountID == account.id, account.service == .google else { throw NativeMailFailure.invalidResponse }
        let id = try nativeMailPathComponent(key.remoteID)
        let url = try nativeMailURL(Self.base + "/messages/" + id, query: [.init(name: "format", value: "full")])
        let message = try nativeMailDecode(GmailMessage.self, from: await api.get(url, byteLimit: 4_194_304))
        guard message.id == key.remoteID else { throw NativeMailFailure.invalidResponse }
        let extracted = try Self.body(message.payload)
        return .init(key: key, text: extracted.text, isTruncated: extracted.truncated)
    }

    private func metadata(_ ids: [String]) async throws -> [NativeMailSummary] {
        try await metadataWithRemovals(ids).messages
    }

    private func metadataWithRemovals(_ ids: [String]) async throws -> (messages: [NativeMailSummary], removed: [String]) {
        try await withThrowingTaskGroup(of: (String, NativeMailSummary?).self) { group in
            var iterator = ids.makeIterator(), result: [NativeMailSummary] = [], removed: [String] = []
            for _ in 0..<min(4, ids.count) {
                if let id = iterator.next() { group.addTask { (id, try await metadata(id)) } }
            }
            while let (id, summary) = try await group.next() {
                if let summary { result.append(summary) } else { removed.append(id) }
                if let next = iterator.next() { group.addTask { (next, try await metadata(next)) } }
            }
            return (result.sorted { $0.receivedAt > $1.receivedAt }, removed)
        }
    }

    private func metadata(_ id: String) async throws -> NativeMailSummary? {
        let escaped = try nativeMailPathComponent(id)
        let url = try nativeMailURL(Self.base + "/messages/" + escaped, query: [
            .init(name: "format", value: "metadata"),
            .init(name: "metadataHeaders", value: "From"), .init(name: "metadataHeaders", value: "Subject"),
            .init(name: "metadataHeaders", value: "Message-ID"), .init(name: "metadataHeaders", value: "Reply-To")
        ])
        let data: Data
        do { data = try await api.get(url, byteLimit: 262_144) }
        catch NativeMailFailure.messageMissing { return nil }
        let message = try nativeMailDecode(GmailMessage.self, from: data)
        guard message.id == id else { throw NativeMailFailure.invalidResponse }
        guard message.labelIds?.contains("INBOX") == true else { return nil }
        guard let milliseconds = message.internalDate.flatMap(Double.init), milliseconds.isFinite, milliseconds >= 0 else { throw NativeMailFailure.invalidResponse }
        let headers = message.payload?.headers ?? []
        func header(_ name: String) -> String? { headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value }
        var components = URLComponents(string: "https://mail.google.com/mail/u/")!
        components.queryItems = [.init(name: "authuser", value: account.address)]
        components.fragment = "inbox/" + id
        return .init(key: .init(accountID: account.id, remoteID: id),
                     sender: NativeMailText.decodeHeader(header("From") ?? ""),
                     subject: NativeMailText.decodeHeader(header("Subject") ?? ""),
                     preview: NativeMailText.bounded(NativeMailText.decodeEntities(message.snippet ?? ""), utf8Limit: 2_048),
                     receivedAt: Date(timeIntervalSince1970: milliseconds / 1_000),
                     isUnread: message.labelIds?.contains("UNREAD") == true, webURL: components.url,
                     rfcMessageID: header("Message-ID").map { NativeMailText.bounded($0, utf8Limit: 1_024) },
                     replyTo: header("Reply-To").map { NativeMailText.decodeHeader($0) })
    }

    private static func validHistoryID(_ value: String?) -> Bool {
        guard let value, !value.isEmpty, value.count <= 128 else { return false }
        return value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func body(_ root: GmailPart?) throws -> (text: String, truncated: Bool) {
        guard let root else { return ("", false) }
        var stack: [(GmailPart, Int)] = [(root, 0)], plain: [GmailPart] = [], html: [GmailPart] = [], visited = 0
        while let (part, depth) = stack.popLast() {
            visited += 1
            guard visited <= 200, depth <= 20 else { throw NativeMailFailure.contentTooLarge }
            guard (part.filename ?? "").isEmpty else { continue }
            let mime = part.mimeType?.lowercased()
            if mime == "text/plain" { plain.append(part) }
            else if mime == "text/html" { html.append(part) }
            else {
                for child in (part.parts ?? []).reversed() { stack.append((child, depth + 1)) }
            }
        }
        let selected = plain.isEmpty ? html : plain
        var pieces: [String] = [], byteCount = 0, truncated = false
        for part in selected {
            guard byteCount < NativeMailText.bodyByteLimit else { truncated = true; break }
            guard let value = part.body?.data else {
                if part.body?.attachmentId != nil || (part.body?.size ?? 0) > 0 { truncated = true }
                continue
            }
            let base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            let padded = base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)
            guard let data = Data(base64Encoded: padded) else { throw NativeMailFailure.invalidResponse }
            let charset = part.headers?.first { $0.name.lowercased() == "content-type" }?.value
                .components(separatedBy: ";").dropFirst().first { $0.lowercased().contains("charset=") }?
                .components(separatedBy: "=").last?.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            let decoded = NativeMailText.decode(data, charset: charset)
            let remaining = NativeMailText.bodyByteLimit - byteCount
            let text = plain.isEmpty ? NativeMailText.plainText(fromHTML: decoded, limit: remaining) : NativeMailText.bounded(decoded, utf8Limit: remaining)
            truncated = truncated || decoded.utf8.count > remaining
            pieces.append(text); byteCount += text.utf8.count
            if pieces.count > 1 { byteCount += 1 }
        }
        let result = NativeMailText.bounded(pieces.joined(separator: "\n"), utf8Limit: NativeMailText.bodyByteLimit)
        return (result, truncated)
    }
}

/// A recent Inbox snapshot is cheaper and more private than crawling all historical Inbox messages to
/// establish Graph delta state. Repeated snapshots still track removals, read status and new arrivals.
public struct MicrosoftNativeMailProvider: NativeMailProvider {
    public let account: NativeMailAccount
    let api: NativeMailAPI
    static let base = "https://graph.microsoft.com/v1.0"
    private static let prefer = "IdType=\"ImmutableId\", outlook.body-content-type=\"text\""

    public init(account: NativeMailAccount, token: @escaping NativeMailTokenLoader,
                transport: any NativeMailTransport = URLSessionNativeMailTransport()) {
        self.account = account
        api = .init(token: token, transport: transport, allowedHosts: ["graph.microsoft.com"])
    }

    public func bootstrap(pageToken: String?) async throws -> NativeMailPage {
        guard account.service == .microsoft, pageToken == nil else { throw NativeMailFailure.invalidResponse }
        return try await snapshot()
    }

    public func changes(cursor: String, pageToken: String?) async throws -> NativeMailPage {
        guard cursor == "snapshot-v1", pageToken == nil else { throw NativeMailFailure.cursorExpired }
        return try await snapshot()
    }

    private func snapshot() async throws -> NativeMailPage {
        let initial = try nativeMailURL(Self.base + "/me/mailFolders/inbox/messages", query: [
            .init(name: "$top", value: "50"), .init(name: "$orderby", value: "receivedDateTime desc"),
            .init(name: "$select", value: "id,subject,from,sender,bodyPreview,receivedDateTime,isRead,webLink,internetMessageId,replyTo")
        ])
        var next: URL? = initial, messages: [NativeMailSummary] = [], seen = Set<String>(), pages = 0
        while let url = next, messages.count < 50 {
            pages += 1
            guard pages <= 5, validPage(url) else { throw NativeMailFailure.invalidResponse }
            let page = try nativeMailDecode(GraphPage.self, from: await api.get(url, headers: ["Prefer": Self.prefer]))
            for message in page.value {
                guard seen.insert(message.id).inserted else { continue }
                messages.append(try summary(message))
                if messages.count == 50 { break }
            }
            if let value = page.nextLink {
                guard let url = URL(string: value), validPage(url) else { throw NativeMailFailure.invalidResponse }
                next = url
            } else { next = nil }
        }
        return .init(messages: messages.sorted { $0.receivedAt > $1.receivedAt }, cursor: "snapshot-v1", isFullSnapshot: true)
    }

    public func fetchContent(for key: NativeMailMessageKey) async throws -> NativeMailContent {
        guard key.accountID == account.id, account.service == .microsoft else { throw NativeMailFailure.invalidResponse }
        let id = try nativeMailPathComponent(key.remoteID)
        let url = try nativeMailURL(Self.base + "/me/messages/" + id, query: [.init(name: "$select", value: "id,body")])
        let message = try nativeMailDecode(GraphMessage.self, from: await api.get(url, byteLimit: 4_194_304, headers: ["Prefer": Self.prefer]))
        guard message.id == key.remoteID else { throw NativeMailFailure.invalidResponse }
        let value = message.body?.content ?? ""
        let text = message.body?.contentType.lowercased() == "html" ? NativeMailText.plainText(fromHTML: value) : NativeMailText.bounded(value, utf8Limit: NativeMailText.bodyByteLimit)
        return .init(key: key, text: text, isTruncated: value.utf8.count > NativeMailText.bodyByteLimit)
    }

    private func validPage(_ url: URL) -> Bool {
        guard NativeMailAPI.isSafe(url, hosts: ["graph.microsoft.com"]) else { return false }
        // Graph may canonicalise a collection path into OData key syntax. Only this account's Inbox is allowed.
        let path = url.path.lowercased()
        let ownUser = account.remoteID.lowercased()
        return ["/v1.0/me/mailfolders/inbox/messages", "/v1.0/me/mailfolders('inbox')/messages",
                "/v1.0/users/\(ownUser)/mailfolders/inbox/messages", "/v1.0/users/\(ownUser)/mailfolders('inbox')/messages"].contains(path)
    }

    private func summary(_ message: GraphMessage) throws -> NativeMailSummary {
        guard !message.id.isEmpty, message.id.utf8.count <= 4_096,
              let rawDate = message.receivedDateTime, let receivedAt = Self.date(rawDate) else { throw NativeMailFailure.invalidResponse }
        let address = message.from?.emailAddress ?? message.sender?.emailAddress
        let sender = address?.name.flatMap { name in
            address?.address.map { name.isEmpty ? $0 : name + " <" + $0 + ">" }
        } ?? address?.address ?? ""
        let webURL = message.webLink.flatMap(URL.init(string:)).flatMap { url in
            Self.isSafeWebLink(url) ? url : nil
        }
        return .init(key: .init(accountID: account.id, remoteID: message.id),
                     sender: NativeMailText.bounded(sender, utf8Limit: 1_024),
                     subject: NativeMailText.bounded(message.subject ?? "", utf8Limit: 1_024),
                     preview: NativeMailText.bounded(message.bodyPreview ?? "", utf8Limit: 2_048),
                     receivedAt: receivedAt, isUnread: message.isRead == false, webURL: webURL,
                     rfcMessageID: message.internetMessageId.map { NativeMailText.bounded($0, utf8Limit: 1_024) },
                     replyTo: message.replyTo?.compactMap { $0.emailAddress?.address }.first.map { NativeMailText.bounded($0, utf8Limit: 1_024) })
    }

    private static func isSafeWebLink(_ url: URL) -> Bool {
        let hosts: Set<String> = ["outlook.office.com", "outlook.office365.com", "outlook.live.com", "outlook.cloud.microsoft"]
        return url.scheme == "https" && url.host.map { hosts.contains($0.lowercased()) } == true &&
            url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: value) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

public enum NativeMailIdentityResolver {
    public static func resolve(service: NativeMailService, token: String,
                               transport: any NativeMailTransport = URLSessionNativeMailTransport()) async throws -> NativeMailIdentity {
        let api = NativeMailAPI(token: { _ in token }, transport: transport,
                                allowedHosts: ["openidconnect.googleapis.com", "gmail.googleapis.com", "graph.microsoft.com"])
        switch service {
        case .google:
            let user = try nativeMailDecode(GoogleIdentity.self, from: await api.get(try nativeMailURL("https://openidconnect.googleapis.com/v1/userinfo")))
            let profile = try nativeMailDecode(GmailProfile.self, from: await api.get(try nativeMailURL("https://gmail.googleapis.com/gmail/v1/users/me/profile")))
            guard !user.sub.isEmpty, user.sub.count <= 512, let email = profile.emailAddress, validAddress(email), user.emailVerified != false else { throw NativeMailFailure.invalidResponse }
            return .init(remoteID: user.sub, address: email, displayName: NativeMailText.bounded(user.name ?? "", utf8Limit: 256))
        case .icloud, .imap: throw NativeMailFailure.unsupportedOperation
        case .microsoft:
            let url = try nativeMailURL("https://graph.microsoft.com/v1.0/me", query: [.init(name: "$select", value: "id,mail,userPrincipalName,displayName")])
            let user = try nativeMailDecode(GraphIdentity.self, from: await api.get(url))
            guard !user.id.isEmpty, user.id.count <= 512, let address = [user.mail, user.userPrincipalName].compactMap({ $0 }).first(where: validAddress) else { throw NativeMailFailure.invalidResponse }
            return .init(remoteID: user.id, address: address, displayName: NativeMailText.bounded(user.displayName ?? "", utf8Limit: 256))
        }
    }

    private static func validAddress(_ value: String) -> Bool {
        value.utf8.count <= 1_024 && value.contains("@") && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}

private struct GmailProfile: Decodable { let emailAddress: String?; let historyId: String? }
private struct GmailList: Decodable { let messages: [GmailID]?; let nextPageToken: String? }
private struct GmailID: Decodable { let id: String }
private struct GmailMessage: Decodable {
    let id: String
    let labelIds: [String]?
    let snippet: String?
    let internalDate: String?
    let payload: GmailPart?
}
private struct GmailHeader: Decodable { let name: String; let value: String }
private struct GmailBody: Decodable { let data: String?; let attachmentId: String?; let size: Int? }
private struct GmailPart: Decodable {
    let mimeType: String?; let filename: String?; let headers: [GmailHeader]?; let body: GmailBody?; let parts: [GmailPart]?
}
private struct GmailHistory: Decodable {
    let history: [Entry]?; let nextPageToken: String?; let historyId: String?
    struct Entry: Decodable {
        let messages: [GmailID]?; let messagesAdded: [Change]?; let messagesDeleted: [Change]?
        let labelsAdded: [Change]?; let labelsRemoved: [Change]?
    }
    struct Change: Decodable { let message: GmailID; let labelIds: [String]? }
}
private struct GraphPage: Decodable {
    let value: [GraphMessage]; let nextLink: String?
    private enum CodingKeys: String, CodingKey { case value; case nextLink = "@odata.nextLink" }
}
private struct GraphMessage: Decodable {
    let id: String; let subject: String?; let from: Address?; let sender: Address?; let bodyPreview: String?
    let replyTo: [Address]?
    let receivedDateTime: String?; let isRead: Bool?; let webLink: String?; let internetMessageId: String?; let body: Body?
    struct Address: Decodable { let emailAddress: Email? }
    struct Email: Decodable { let name: String?; let address: String? }
    struct Body: Decodable { let contentType: String; let content: String }
}
private struct GoogleIdentity: Decodable {
    let sub: String; let email: String?; let name: String?; let emailVerified: Bool?
    private enum CodingKeys: String, CodingKey { case sub, email, name; case emailVerified = "email_verified" }
}
private struct GraphIdentity: Decodable { let id: String; let mail: String?; let userPrincipalName: String?; let displayName: String? }
