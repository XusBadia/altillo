import Foundation
import Testing
@testable import AltilloMail

struct NativeMailIMAPTests {
    @Test func inboxUsesA50MessageWindowAndUIDValidityScopedIdentifiers() async throws {
        let headers = Data("From: =?UTF-8?B?U3ludGhldGlj?= <sender@example.invalid>\r\nSubject: Fixture\r\nMessage-ID: <same@example.invalid>\r\nReply-To: reply@example.invalid\r\n".utf8)
        let fetch = "* 75 FETCH (UID 901 FLAGS () INTERNALDATE \"1-Nov-2026 12:00:00 +0000\" BODY[HEADER.FIELDS (FROM SUBJECT MESSAGE-ID REPLY-TO)] {\(headers.count)}\r\n"
        var script = imapWireStart(count: 75)
        script += [.client("A5 FETCH 26:75 (UID FLAGS INTERNALDATE BODY.PEEK[HEADER.FIELDS (FROM SUBJECT MESSAGE-ID REPLY-TO)])\r\n"),
                   .server(Data(fetch.utf8)), .server(headers.prefix(10)), .server(headers.dropFirst(10)),
                   .server(Data(")\r\nA5 OK done\r\n".utf8))]
        let socket = MailScriptedSocket(script)
        let factory = MailScriptedFactory([socket])
        let account = imapWireAccount()
        let provider = IMAPNativeMailProvider(account: account, credentials: { imapWireCredentials() }, sockets: factory.make)
        let page = try await provider.bootstrap(pageToken: nil)
        #expect(page.cursor == "imap-v1:42")
        #expect(page.isFullSnapshot)
        #expect(page.messages.count == 1)
        #expect(page.messages.first?.key == NativeMailMessageKey(accountID: account.id, remoteID: "42:901"))
        #expect(page.messages.first?.sender == "Synthetic <sender@example.invalid>")
        #expect(page.messages.first?.replyTo == "reply@example.invalid")
        #expect(page.messages.first?.isUnread == true)
        #expect(await factory.endpoints() == ["imap.example.invalid:993:tls"])
        #expect(await socket.finished())
    }

    @Test func changedUIDValidityExpiresTheCursorWithoutReturningOldIdentity() async throws {
        let socket = MailScriptedSocket(imapWireStart(count: 0, validity: 99))
        let factory = MailScriptedFactory([socket])
        let provider = IMAPNativeMailProvider(account: imapWireAccount(), credentials: { imapWireCredentials() }, sockets: factory.make)
        await #expect(throws: NativeMailFailure.cursorExpired) { try await provider.changes(cursor: "imap-v1:42", pageToken: nil) }
        #expect(await socket.finished())
    }

    @Test func bodyFetchPeeksOnlyTheSelectedPlainPartAndDecodesQuotedPrintable() async throws {
        let body = Data("Your code is =34=32=31=39.\r\n".utf8)
        let structure = "((\"TEXT\" \"HTML\" (\"CHARSET\" \"UTF-8\") NIL NIL \"7BIT\" 60 1 NIL NIL NIL NIL)(\"TEXT\" \"PLAIN\" (\"CHARSET\" \"UTF-8\") NIL NIL \"QUOTED-PRINTABLE\" \(body.count) 1 NIL NIL NIL NIL) \"ALTERNATIVE\")"
        var script = imapWireMessageStart()
        script += [.client("A6 UID FETCH 7 (UID BODYSTRUCTURE)\r\n"),
                   .server(Data("* 1 FETCH (UID 7 BODYSTRUCTURE \(structure))\r\nA6 OK done\r\n".utf8)),
                   .client("A7 UID FETCH 7 (UID BODY.PEEK[2]<0.1048576>)\r\n"),
                   .server(Data("* 1 FETCH (UID 7 BODY[2]<0> {\(body.count)}\r\n".utf8)),
                   .server(body), .server(Data(")\r\nA7 OK done\r\n".utf8))]
        let socket = MailScriptedSocket(script)
        let factory = MailScriptedFactory([socket])
        let account = imapWireAccount()
        let provider = IMAPNativeMailProvider(account: account, credentials: { imapWireCredentials() }, sockets: factory.make)
        let content = try await provider.fetchContent(for: .init(accountID: account.id, remoteID: "42:7"))
        #expect(content.text == "Your code is 4219.\r\n")
        #expect(!content.isTruncated)
        #expect(await socket.finished())
    }

    @Test func attachmentMetadataAndDownloadUseBodyStructurePartIDs() async throws {
        let structure = "((\"TEXT\" \"PLAIN\" NIL NIL NIL \"7BIT\" 4 1)(\"APPLICATION\" \"PDF\" NIL NIL NIL \"BASE64\" 8 NIL (\"ATTACHMENT\" (\"FILENAME*\" \"UTF-8''r%C3%A9sum%C3%A9.pdf\"))) \"MIXED\")"
        let partResponse = Data("* 1 FETCH (UID 7 BODYSTRUCTURE \(structure))\r\nA6 OK done\r\n".utf8)
        let listing = MailScriptedSocket(imapWireMessageStart() + [
            .client("A6 UID FETCH 7 (UID BODYSTRUCTURE)\r\n"), .server(partResponse)])
        let download = MailScriptedSocket(imapWireMessageStart() + [
            .client("A6 UID FETCH 7 (UID BODYSTRUCTURE)\r\n"), .server(partResponse),
            .client("A7 UID FETCH 7 (UID BODY.PEEK[2])\r\n"),
            .server(Data("* 1 FETCH (UID 7 BODY[2] {8}\r\nJVBERg==)\r\nA7 OK done\r\n".utf8))])
        let factory = MailScriptedFactory([listing, download])
        let account = imapWireAccount()
        let provider = IMAPNativeMailProvider(account: account, credentials: { imapWireCredentials() }, sockets: factory.make)
        let attachments = try await provider.attachments(for: .init(accountID: account.id, remoteID: "42:7"))
        #expect(attachments.first?.remoteID == "2")
        #expect(attachments.first?.filename == "résumé.pdf")
        let attachment = try #require(attachments.first)
        #expect(try await provider.download(attachment) == Data("%PDF".utf8))
        #expect(await listing.finished())
        #expect(await download.finished())
    }

    @Test func readAndMoveUseUIDCommandsWithoutGlobalExpunge() async throws {
        let mark = MailScriptedSocket(imapWireMessageStart() + [
            .client("A6 UID STORE 7 +FLAGS.SILENT (\\Seen)\r\n"), .server(Data("A6 OK done\r\n".utf8))])
        let move = MailScriptedSocket(imapWireMessageStart() + [
            .client("A6 LIST \"\" \"*\"\r\n"),
            .server(Data("* LIST (\\HasNoChildren \\Archive) \"/\" \"Archive\"\r\nA6 OK done\r\n".utf8)),
            .client("A7 UID MOVE 7 \"Archive\"\r\n"), .server(Data("A7 OK done\r\n".utf8))])
        let fallback = MailScriptedSocket(imapWireMessageStart(capabilities: "IMAP4rev1 UIDPLUS") + [
            .client("A6 LIST \"\" \"*\"\r\n"),
            .server(Data("* LIST (\\Trash) \"/\" \"Trash\"\r\nA6 OK done\r\n".utf8)),
            .client("A7 UID COPY 7 \"Trash\"\r\n"), .server(Data("A7 OK done\r\n".utf8)),
            .client("A8 UID STORE 7 +FLAGS.SILENT (\\Deleted)\r\n"), .server(Data("A8 OK done\r\n".utf8)),
            .client("A9 UID EXPUNGE 7\r\n"), .server(Data("A9 OK done\r\n".utf8))])
        let factory = MailScriptedFactory([mark, move, fallback])
        let account = imapWireAccount()
        let provider = IMAPNativeMailProvider(account: account, credentials: { imapWireCredentials() }, sockets: factory.make)
        let key = NativeMailMessageKey(accountID: account.id, remoteID: "42:7")
        try await provider.setRead(true, for: key)
        try await provider.archive(key)
        try await provider.trash(key)
        #expect(await mark.finished())
        #expect(await move.finished())
        #expect(await fallback.finished())
    }

    @Test func unsafeMoveFallbackIsRejectedBeforeAnyCopyOrDelete() async throws {
        let socket = MailScriptedSocket(imapWireMessageStart(capabilities: "IMAP4rev1") + [
            .client("A6 LIST \"\" \"*\"\r\n"),
            .server(Data("* LIST (\\Trash) \"/\" \"Trash\"\r\nA6 OK done\r\n".utf8))])
        let factory = MailScriptedFactory([socket])
        let account = imapWireAccount()
        let provider = IMAPNativeMailProvider(account: account, credentials: { imapWireCredentials() }, sockets: factory.make)
        await #expect(throws: NativeMailFailure.unsupportedOperation) {
            try await provider.trash(.init(accountID: account.id, remoteID: "42:7"))
        }
        #expect(await socket.finished())
    }

    @Test func foreignAccountAndMalformedConfigNeverOpenASocket() async throws {
        let factory = MailScriptedFactory([])
        let provider = IMAPNativeMailProvider(account: imapWireAccount(), credentials: { imapWireCredentials() }, sockets: factory.make)
        await #expect(throws: NativeMailFailure.messageMissing) {
            try await provider.setRead(true, for: .init(accountID: UUID(), remoteID: "42:7"))
        }
        var config = imapWireCredentials().configuration
        config.imapHost = "imap.example.invalid\r\nattack"
        let bad = NativeMailServerCredentials(configuration: config, password: "synthetic")
        await #expect(throws: NativeMailFailure.invalidDraft) {
            try await IMAPNativeMailProvider.validate(credentials: bad, sockets: factory.make)
        }
        #expect(await factory.endpoints().isEmpty)
    }

    @Test func parserKeepsLiteralProtocolTextOpaqueAndRejectsMalformedNesting() throws {
        let literal = Data("x)\r\n* BYE fake\r\n".utf8)
        var frame = Data("* 1 FETCH (UID 7 BODY[1] {\(literal.count)}\r\n".utf8)
        frame.append(literal); frame.append(Data(")\r\n".utf8))
        var parser = NativeMailIMAPParser(frame)
        let result = try parser.parse()
        #expect(result[3].values?.last == .bytes(literal))
        var bad = NativeMailIMAPParser(Data("* 1 FETCH (UID 7\r\n".utf8))
        #expect(throws: NativeMailFailure.invalidResponse) { try bad.parse() }
    }

    @Test func cancelledSocketReadClosesSessionAndDoesNotInventSuccess() async throws {
        let socket = MailScriptedSocket([.cancelRead])
        let factory = MailScriptedFactory([socket])
        let provider = IMAPNativeMailProvider(account: imapWireAccount(), credentials: { imapWireCredentials() }, sockets: factory.make)
        await #expect(throws: CancellationError.self) { try await provider.bootstrap(pageToken: nil) }
        #expect(await socket.finished())
    }
}

enum MailSocketScriptStep: Sendable {
    case server(Data), client(String), clientPrefix(String), tls, failRead(NativeMailFailure), cancelRead
}

actor MailScriptedSocket: NativeMailSocket {
    private var script: [MailSocketScriptStep]
    private var closed = false
    private var captured: [Data] = []
    init(_ script: [MailSocketScriptStep]) { self.script = script }

    func read(maxBytes: Int) throws -> Data {
        guard !script.isEmpty else { throw NativeMailFailure.invalidResponse }
        switch script.removeFirst() {
        case .server(let data):
            if data.count > maxBytes { script.insert(.server(Data(data.dropFirst(maxBytes))), at: 0) }
            return Data(data.prefix(maxBytes))
        case .failRead(let failure): throw failure
        case .cancelRead: throw CancellationError()
        default: throw NativeMailFailure.invalidResponse
        }
    }
    func write(_ data: Data) throws {
        guard !script.isEmpty else { throw NativeMailFailure.invalidResponse }
        captured.append(data)
        switch script.removeFirst() {
        case .client(let value): guard data == Data(value.utf8) else { throw NativeMailFailure.invalidResponse }
        case .clientPrefix(let value): guard data.starts(with: Data(value.utf8)) else { throw NativeMailFailure.invalidResponse }
        default: throw NativeMailFailure.invalidResponse
        }
    }
    func startTLS() throws {
        guard !script.isEmpty, case .tls = script.removeFirst() else { throw NativeMailFailure.invalidResponse }
    }
    func close() { closed = true }
    func finished() -> Bool { closed && script.isEmpty }
    func writes() -> [Data] { captured }
}

actor MailScriptedFactory {
    private var sockets: [MailScriptedSocket]
    private var calls: [String] = []
    init(_ sockets: [MailScriptedSocket]) { self.sockets = sockets }
    nonisolated var make: NativeMailSocketFactory { { host, port, secure in try await self.next(host, port, secure) } }
    private func next(_ host: String, _ port: Int, _ secure: Bool) throws -> any NativeMailSocket {
        guard !sockets.isEmpty else { throw NativeMailFailure.invalidResponse }
        calls.append("\(host):\(port):\(secure ? "tls" : "plain")")
        return sockets.removeFirst()
    }
    func endpoints() -> [String] { calls }
}

func imapWireAccount() -> NativeMailAccount {
    .init(service: .imap, remoteID: "fixture", address: "user@example.invalid")
}

func imapWireCredentials(security: NativeMailSMTPSecurity = .startTLS) -> NativeMailServerCredentials {
    .init(configuration: .init(address: "user@example.invalid", username: "user@example.invalid",
                              imapHost: "imap.example.invalid", smtpHost: "smtp.example.invalid",
                              smtpPort: security == .startTLS ? 587 : 465, smtpSecurity: security), password: "synthetic-password")
}

func imapWireStart(count: Int = 1, validity: UInt32 = 42,
                   capabilities: String = "IMAP4rev1 MOVE UIDPLUS") -> [MailSocketScriptStep] {
    [.server(Data("* OK synthetic\r\n".utf8)), .client("A1 CAPABILITY\r\n"),
     .server(Data("* CAPABILITY \(capabilities)\r\nA1 OK done\r\n".utf8)),
     .client("A2 LOGIN \"user@example.invalid\" \"synthetic-password\"\r\n"),
     .server(Data("A2 OK done\r\n".utf8)), .client("A3 CAPABILITY\r\n"),
     .server(Data("* CAPABILITY \(capabilities)\r\nA3 OK done\r\n".utf8)),
     .client("A4 SELECT INBOX\r\n"),
     .server(Data("* \(count) EXISTS\r\n* OK [UIDVALIDITY \(validity)] valid\r\nA4 OK selected\r\n".utf8))]
}

func imapWireMessageStart(capabilities: String = "IMAP4rev1 MOVE UIDPLUS") -> [MailSocketScriptStep] {
    imapWireStart(capabilities: capabilities) + [.client("A5 UID FETCH 7 (UID)\r\n"),
        .server(Data("* 1 FETCH (UID 7)\r\nA5 OK done\r\n".utf8))]
}
