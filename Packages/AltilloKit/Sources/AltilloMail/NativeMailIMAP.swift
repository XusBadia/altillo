import Foundation

/// Each operation uses a short-lived authenticated TLS session. No credentials or message bodies are retained.
public struct IMAPNativeMailProvider: NativeMailProvider {
    public let account: NativeMailAccount
    private let credentials: NativeMailServerCredentialLoader
    private let sockets: NativeMailSocketFactory

    public init(account: NativeMailAccount, credentials: @escaping NativeMailServerCredentialLoader) {
        self.init(account: account, credentials: credentials, sockets: NativeMailTLSSocket.factory)
    }

    init(account: NativeMailAccount, credentials: @escaping NativeMailServerCredentialLoader,
         sockets: @escaping NativeMailSocketFactory) {
        self.account = account; self.credentials = credentials; self.sockets = sockets
    }

    public static func validate(credentials: NativeMailServerCredentials) async throws {
        try await validate(credentials: credentials, sockets: NativeMailTLSSocket.factory)
    }

    static func validate(credentials: NativeMailServerCredentials, sockets: @escaping NativeMailSocketFactory) async throws {
        try NativeMailServerValidation.check(credentials)
        let session = try await NativeMailIMAPSession.open(credentials, sockets: sockets)
        await session.close()
        try await NativeMailSMTP.validate(credentials: credentials, sockets: sockets)
    }

    public func bootstrap(pageToken: String?) async throws -> NativeMailPage {
        guard pageToken == nil else { throw NativeMailFailure.invalidResponse }
        return try await snapshot(expectedValidity: nil)
    }

    public func changes(cursor: String, pageToken: String?) async throws -> NativeMailPage {
        guard pageToken == nil, cursor.hasPrefix("imap-v1:"), let validity = UInt32(cursor.dropFirst(8)), validity > 0 else {
            throw NativeMailFailure.cursorExpired
        }
        return try await snapshot(expectedValidity: validity)
    }

    public func fetchContent(for key: NativeMailMessageKey) async throws -> NativeMailContent {
        try await withMessage(key) { session, uid in
            let parts = try await session.parts(uid)
            let readable = parts.filter { !$0.isAttachment }
            guard let part = readable.first(where: { $0.mimeType == "text/plain" }) ?? readable.first(where: { $0.mimeType == "text/html" }) else {
                return NativeMailContent(key: key, text: "")
            }
            let limit = NativeMailText.bodyByteLimit
            let data = try await session.part(uid, id: part.id, partial: limit, byteLimit: limit)
            let truncated = part.encodedBytes > data.count
            let decoded = try NativeMailRFC.decoded(data, encoding: part.encoding, truncated: truncated)
            let text = NativeMailText.decode(decoded, charset: part.charset)
            let output = part.mimeType == "text/html" ? NativeMailText.plainText(fromHTML: text) : NativeMailText.bounded(text, utf8Limit: limit)
            return NativeMailContent(key: key, text: output, isTruncated: truncated || text.utf8.count > limit)
        }
    }

    public func setRead(_ isRead: Bool, for key: NativeMailMessageKey) async throws {
        try await withMessage(key) { session, uid in
            _ = try await session.command("UID STORE \(uid) \(isRead ? "+" : "-")FLAGS.SILENT (\\Seen)")
        }
    }

    public func archive(_ key: NativeMailMessageKey) async throws { try await move(key, flag: "\\ARCHIVE") }
    public func trash(_ key: NativeMailMessageKey) async throws { try await move(key, flag: "\\TRASH") }

    public func attachments(for key: NativeMailMessageKey) async throws -> [NativeMailAttachment] {
        try await withMessage(key) { session, uid in
            try await session.parts(uid).filter(\.isAttachment).map { part in
                NativeMailAttachment(key: key, remoteID: part.id, filename: part.filename ?? "attachment-\(part.id)",
                                     mimeType: part.mimeType, byteCount: part.encoding == "base64" ? part.encodedBytes / 4 * 3 : part.encodedBytes)
            }
        }
    }

    public func download(_ attachment: NativeMailAttachment) async throws -> Data {
        try await withMessage(attachment.key) { session, uid in
            let parts = try await session.parts(uid)
            guard let part = parts.first(where: { $0.id == attachment.remoteID && $0.isAttachment }) else {
                throw NativeMailFailure.messageMissing
            }
            let limit = 20 << 20
            guard part.encodedBytes <= 29 << 20 else { throw NativeMailFailure.contentTooLarge }
            let data = try await session.part(uid, id: part.id, byteLimit: 29 << 20)
            let decoded = try NativeMailRFC.decoded(data, encoding: part.encoding)
            guard decoded.count <= limit else { throw NativeMailFailure.contentTooLarge }
            return decoded
        }
    }

    public func send(_ draft: NativeMailDraft) async throws -> NativeMailSendReceipt {
        let credentials = try await checkedCredentials()
        try NativeMailMIME.validateDraft(draft)
        let mime = try NativeMailMIME.encode(draft: draft, from: credentials.configuration.address, includeBcc: false)
        let recipients = Array(Set(draft.to + draft.cc + draft.bcc)).sorted()
        let receipt = try await NativeMailSMTP.sendPrepared(mime: mime, recipients: recipients, credentials: credentials, sockets: sockets)
        guard credentials.configuration.saveSentCopy else { return receipt }
        // SMTP has already accepted the message. A copy failure, including cancellation, must never
        // become a send failure or cause another submission attempt.
        do {
            let session = try await NativeMailIMAPSession.open(credentials, sockets: sockets)
            do { try await session.appendSent(mime); await session.close() }
            catch { await session.close(); throw error }
            return NativeMailSendReceipt(remoteID: receipt.remoteID, sentCopySaved: true)
        } catch { return NativeMailSendReceipt(remoteID: receipt.remoteID, sentCopySaved: false) }
    }

    private func snapshot(expectedValidity: UInt32?) async throws -> NativeMailPage {
        let credentials = try await checkedCredentials()
        let session = try await NativeMailIMAPSession.open(credentials, sockets: sockets)
        do {
            let mailbox = try await session.selectInbox()
            if let expectedValidity, expectedValidity != mailbox.validity { throw NativeMailFailure.cursorExpired }
            let summaries = try await session.summaries(accountID: account.id, mailbox: mailbox)
            await session.close()
            return NativeMailPage(messages: summaries, cursor: "imap-v1:\(mailbox.validity)", isFullSnapshot: true)
        } catch { await session.close(); throw error }
    }

    private func withMessage<T: Sendable>(_ key: NativeMailMessageKey,
        operation: @Sendable (NativeMailIMAPSession, UInt32) async throws -> T) async throws -> T {
        guard key.accountID == account.id else { throw NativeMailFailure.messageMissing }
        let identifiers = key.remoteID.split(separator: ":", omittingEmptySubsequences: false)
        guard identifiers.count == 2, let validity = UInt32(identifiers[0]), validity > 0,
              let uid = UInt32(identifiers[1]), uid > 0 else { throw NativeMailFailure.messageMissing }
        let credentials = try await checkedCredentials()
        let session = try await NativeMailIMAPSession.open(credentials, sockets: sockets)
        do {
            let selected = try await session.selectInbox()
            guard selected.validity == validity else { throw NativeMailFailure.messageMissing }
            // UID STORE/MOVE can report OK for a nonexistent UID: verify its existence first.
            try await session.requireMessage(uid)
            let result = try await operation(session, uid)
            try Task.checkCancellation()
            await session.close()
            return result
        } catch { await session.close(); throw error }
    }

    private func move(_ key: NativeMailMessageKey, flag: String) async throws {
        try await withMessage(key) { session, uid in try await session.move(uid, specialUse: flag) }
    }

    private func checkedCredentials() async throws -> NativeMailServerCredentials {
        try Task.checkCancellation()
        let credentials = try await credentials()
        try Task.checkCancellation()
        try NativeMailServerValidation.check(credentials)
        guard credentials.configuration.address.caseInsensitiveCompare(account.address) == .orderedSame,
              account.service == .imap || account.service == .icloud else { throw NativeMailFailure.unauthorized }
        return credentials
    }
}

struct NativeMailIMAPMailbox: Sendable { let validity: UInt32; let count: Int }

actor NativeMailIMAPSession {
    private let socket: any NativeMailSocket
    private let reader: NativeMailSocketReader
    private var serial = 0
    private var capabilities: Set<String> = []

    private init(socket: any NativeMailSocket) { self.socket = socket; reader = NativeMailSocketReader(socket: socket) }

    static func open(_ credentials: NativeMailServerCredentials, sockets: NativeMailSocketFactory) async throws -> NativeMailIMAPSession {
        let config = credentials.configuration
        let socket = try await sockets(config.imapHost, config.imapPort, true)
        let session = NativeMailIMAPSession(socket: socket)
        do { try await session.login(credentials); return session }
        catch { await socket.close(); throw error }
    }

    func close() async { await socket.close() }

    private func login(_ credentials: NativeMailServerCredentials) async throws {
        let greeting = String(decoding: try await reader.line(), as: UTF8.self).uppercased()
        guard greeting.hasPrefix("* OK ") || greeting == "* OK" else { throw NativeMailFailure.unavailable }
        let response = try await command("CAPABILITY")
        for value in response {
            if value.count >= 2, value[1].text?.uppercased() == "CAPABILITY" {
                capabilities.formUnion(value.dropFirst(2).compactMap { $0.text?.uppercased() })
            }
        }
        guard !capabilities.contains("LOGINDISABLED") else { throw NativeMailFailure.unauthorized }
        _ = try await command("LOGIN \(Self.quoted(credentials.configuration.username)) \(Self.quoted(credentials.password))", authenticating: true)
        // Servers may advertise MOVE/SPECIAL-USE/UIDPLUS only after authentication.
        let authenticated = try await command("CAPABILITY")
        for value in authenticated where value.count >= 2 && value[1].text?.uppercased() == "CAPABILITY" {
            capabilities.formUnion(value.dropFirst(2).compactMap { $0.text?.uppercased() })
        }
    }

    func selectInbox() async throws -> NativeMailIMAPMailbox {
        let values = try await command("SELECT INBOX")
        var validity: UInt32?, count: Int?
        for response in values {
            if response.count >= 3, response[2].text?.uppercased() == "EXISTS", let text = response[1].text { count = Int(text) }
            for value in response {
                if let text = value.text, text.uppercased().hasPrefix("[UIDVALIDITY "), text.hasSuffix("]") {
                    validity = UInt32(text.dropFirst(13).dropLast())
                }
            }
        }
        guard let validity, validity > 0, let count, count >= 0 else { throw NativeMailFailure.invalidResponse }
        return NativeMailIMAPMailbox(validity: validity, count: count)
    }

    func summaries(accountID: UUID, mailbox: NativeMailIMAPMailbox) async throws -> [NativeMailSummary] {
        guard mailbox.count > 0 else { return [] }
        let first = max(1, mailbox.count - 49)
        let responses = try await command("FETCH \(first):\(mailbox.count) (UID FLAGS INTERNALDATE BODY.PEEK[HEADER.FIELDS (FROM SUBJECT MESSAGE-ID REPLY-TO)])", literalLimit: 65_536)
        var summaries: [NativeMailSummary] = []
        var seen: Set<UInt32> = []
        for response in responses {
            guard let fields = Self.fetchFields(response), let uid = Self.uid(fields), !seen.contains(uid) else { continue }
            guard summaries.count < 50 else { throw NativeMailFailure.invalidResponse }
            seen.insert(uid)
            let headerData = Self.field(fields, prefix: "BODY[HEADER.FIELDS")?.data ?? Data()
            let headers = NativeMailRFC.headers(headerData)
            let flags = Self.field(fields, name: "FLAGS")?.values?.compactMap(\.text) ?? []
            let date = Self.field(fields, name: "INTERNALDATE")?.text.flatMap(NativeMailRFC.internalDate) ?? .distantPast
            summaries.append(NativeMailSummary(key: .init(accountID: accountID, remoteID: "\(mailbox.validity):\(uid)"),
                sender: NativeMailText.bounded(NativeMailText.decodeHeader(headers["from"] ?? ""), utf8Limit: 4_096),
                subject: NativeMailText.bounded(NativeMailText.decodeHeader(headers["subject"] ?? ""), utf8Limit: 4_096),
                receivedAt: date, isUnread: !flags.contains(where: { $0.uppercased() == "\\SEEN" }),
                rfcMessageID: headers["message-id"], replyTo: headers["reply-to"].map(NativeMailText.decodeHeader)))
        }
        return summaries.sorted { $0.receivedAt > $1.receivedAt }
    }

    func requireMessage(_ uid: UInt32) async throws {
        let response = try await command("UID FETCH \(uid) (UID)")
        guard response.contains(where: { Self.fetchFields($0).flatMap(Self.uid) == uid }) else { throw NativeMailFailure.messageMissing }
    }

    func parts(_ uid: UInt32) async throws -> [NativeMailIMAPPart] {
        let response = try await command("UID FETCH \(uid) (UID BODYSTRUCTURE)")
        guard let fields = response.compactMap(Self.fetchFields).first(where: { Self.uid($0) == uid }),
              let structure = Self.field(fields, name: "BODYSTRUCTURE") else { throw NativeMailFailure.messageMissing }
        return try NativeMailIMAPPart.flatten(structure)
    }

    func part(_ uid: UInt32, id: String, partial: Int? = nil, byteLimit: Int) async throws -> Data {
        guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }) else { throw NativeMailFailure.invalidResponse }
        let suffix = partial.map { "<0.\($0)>" } ?? ""
        let response = try await command("UID FETCH \(uid) (UID BODY.PEEK[\(id)]\(suffix))", literalLimit: byteLimit)
        guard let fields = response.compactMap(Self.fetchFields).first(where: { Self.uid($0) == uid }),
              let data = Self.field(fields, prefix: "BODY[\(id)]")?.data else { throw NativeMailFailure.messageMissing }
        return data
    }

    func move(_ uid: UInt32, specialUse: String) async throws {
        let destination = try await specialUseMailbox(specialUse)
        if capabilities.contains("MOVE") {
            _ = try await command("UID MOVE \(uid) \(Self.quoted(destination))")
        } else {
            // COPY + targeted UID EXPUNGE only. Never EXPUNGE unrelated user-deleted mail.
            guard capabilities.contains("UIDPLUS") else { throw NativeMailFailure.unsupportedOperation }
            _ = try await command("UID COPY \(uid) \(Self.quoted(destination))")
            _ = try await command("UID STORE \(uid) +FLAGS.SILENT (\\Deleted)")
            _ = try await command("UID EXPUNGE \(uid)")
        }
    }

    func appendSent(_ mime: Data) async throws {
        guard !mime.isEmpty, mime.count <= NativeMailMIME.outgoingByteLimit else { throw NativeMailFailure.contentTooLarge }
        let destination = try await specialUseMailbox("\\SENT")
        _ = try await command("APPEND \(Self.quoted(destination)) (\\Seen) {\(mime.count)}", literal: mime)
    }

    private func specialUseMailbox(_ specialUse: String) async throws -> String {
        let response = try await command("LIST \"\" \"*\"")
        var destination: String?
        for row in response where row.count >= 5 && row[1].text?.uppercased() == "LIST" {
            if row[2].values?.contains(where: { $0.text?.uppercased() == specialUse }) == true { destination = row[4].text; break }
        }
        guard let destination, destination.uppercased() != "INBOX", destination.utf8.count <= 4_096 else {
            throw NativeMailFailure.unsupportedOperation
        }
        return destination
    }

    func command(_ command: String, literalLimit: Int = 65_536, authenticating: Bool = false,
                 literal: Data? = nil) async throws -> [[NativeMailIMAPValue]] {
        try Task.checkCancellation()
        guard !command.contains("\r"), !command.contains("\n"), !command.utf8.contains(0), command.utf8.count <= 16_384 else {
            throw NativeMailFailure.invalidDraft
        }
        serial += 1
        let tag = "A\(serial)"
        try await socket.write(Data("\(tag) \(command)\r\n".utf8))
        var results: [[NativeMailIMAPValue]] = []
        var literalSent = false
        for _ in 0..<1_024 {
            var frame = Data()
            for _ in 0..<201 {
                let line = try await reader.line()
                frame.append(line)
                frame.append(contentsOf: [13, 10])
                if let size = Self.literalSize(line) {
                    let data = try await reader.exact(size, limit: literalLimit)
                    guard frame.count <= (30 << 20) - data.count else { throw NativeMailFailure.contentTooLarge }
                    frame.append(data)
                } else { break }
            }
            var parser = NativeMailIMAPParser(frame)
            let values = try parser.parse()
            guard let first = values.first?.text else { throw NativeMailFailure.invalidResponse }
            if first == "+" {
                guard let literal, !literalSent else { throw NativeMailFailure.invalidResponse }
                literalSent = true
                var data = literal
                data.append(contentsOf: [13, 10])
                try await socket.write(data)
                continue
            }
            if first == tag {
                guard values.count >= 2 else { throw NativeMailFailure.invalidResponse }
                switch values[1].text?.uppercased() {
                case "OK":
                    guard literal == nil || literalSent else { throw NativeMailFailure.invalidResponse }
                    return results + [values]
                case "NO": throw authenticating ? NativeMailFailure.unauthorized : NativeMailFailure.forbidden
                case "BAD": throw NativeMailFailure.unsupportedOperation
                default: throw NativeMailFailure.invalidResponse
                }
            }
            guard first == "*", values.dropFirst().first?.text?.uppercased() != "BYE" else { throw NativeMailFailure.unavailable }
            results.append(values)
        }
        throw NativeMailFailure.invalidResponse
    }

    private static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func literalSize(_ line: Data) -> Int? {
        guard line.last == 125, let opening = line.lastIndex(of: 123) else { return nil }
        let digits = line[line.index(after: opening)..<line.index(before: line.endIndex)]
        guard !digits.isEmpty, digits.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(String(decoding: digits, as: UTF8.self))
    }

    private static func fetchFields(_ values: [NativeMailIMAPValue]) -> [NativeMailIMAPValue]? {
        guard values.count >= 4, values[0].text == "*", values[2].text?.uppercased() == "FETCH" else { return nil }
        return values[3].values
    }
    private static func uid(_ fields: [NativeMailIMAPValue]) -> UInt32? {
        field(fields, name: "UID")?.text.flatMap(UInt32.init).flatMap { $0 > 0 ? $0 : nil }
    }
    private static func field(_ fields: [NativeMailIMAPValue], name: String) -> NativeMailIMAPValue? {
        field(fields, matching: { $0.uppercased() == name })
    }
    private static func field(_ fields: [NativeMailIMAPValue], prefix: String) -> NativeMailIMAPValue? {
        field(fields, matching: { $0.uppercased().hasPrefix(prefix) })
    }
    private static func field(_ fields: [NativeMailIMAPValue], matching: (String) -> Bool) -> NativeMailIMAPValue? {
        for index in stride(from: 0, to: fields.count - 1, by: 2) {
            if let text = fields[index].text, matching(text) { return fields[index + 1] }
        }
        return nil
    }
}

private extension NativeMailIMAPValue {
    var data: Data? { if case .bytes(let data) = self { return data }; return nil }
}
