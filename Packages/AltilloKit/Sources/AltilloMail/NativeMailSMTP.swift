import Foundation

enum NativeMailSMTP {
    static func validate(credentials: NativeMailServerCredentials, sockets: NativeMailSocketFactory) async throws {
        let session = try await NativeMailSMTPSession.open(credentials, sockets: sockets)
        await session.close()
    }

    static func send(_ draft: NativeMailDraft, credentials: NativeMailServerCredentials,
                     sockets: NativeMailSocketFactory) async throws -> NativeMailSendReceipt {
        try NativeMailMIME.validateDraft(draft)
        let mime = try NativeMailMIME.encode(draft: draft, from: credentials.configuration.address, includeBcc: false)
        let recipients = Array(Set(draft.to + draft.cc + draft.bcc)).sorted()
        return try await sendPrepared(mime: mime, recipients: recipients, credentials: credentials, sockets: sockets)
    }

    /// The provider also appends these exact bytes to Sent; generating MIME a second time would change Message-ID.
    static func sendPrepared(mime: Data, recipients: [String], credentials: NativeMailServerCredentials,
                             sockets: NativeMailSocketFactory) async throws -> NativeMailSendReceipt {
        guard !recipients.isEmpty, recipients.allSatisfy(NativeMailServerValidation.address) else { throw NativeMailFailure.invalidDraft }
        guard mime.count <= NativeMailMIME.outgoingByteLimit else { throw NativeMailFailure.contentTooLarge }
        let session = try await NativeMailSMTPSession.open(credentials, sockets: sockets)
        do {
            try await session.submit(mime, from: credentials.configuration.address, recipients: recipients)
            await session.close()
            return NativeMailSendReceipt()
        } catch { await session.close(); throw error }
    }
}

actor NativeMailSMTPSession {
    private let socket: any NativeMailSocket
    private let reader: NativeMailSocketReader
    private var capabilities: [String] = []
    private var secured: Bool
    private init(socket: any NativeMailSocket, secure: Bool) {
        self.socket = socket; self.secured = secure; reader = NativeMailSocketReader(socket: socket, budget: 1 << 20)
    }

    static func open(_ credentials: NativeMailServerCredentials, sockets: NativeMailSocketFactory) async throws -> NativeMailSMTPSession {
        try NativeMailServerValidation.check(credentials)
        let config = credentials.configuration
        let implicitTLS = config.smtpSecurity == .implicitTLS
        let socket = try await sockets(config.smtpHost, config.smtpPort, implicitTLS)
        let session = NativeMailSMTPSession(socket: socket, secure: implicitTLS)
        do { try await session.login(credentials); return session }
        catch { await socket.close(); throw error }
    }

    func close() async { await socket.close() }

    private func login(_ credentials: NativeMailServerCredentials) async throws {
        try await expect(220)
        try await ehlo()
        if !secured {
            guard capabilities.contains(where: { $0 == "STARTTLS" }) else { throw NativeMailFailure.forbidden }
            try await writeLine("STARTTLS")
            try await expect(220)
            try await reader.upgradeTLS()
            secured = true
            capabilities = []
            try await ehlo()
        }
        guard secured else { throw NativeMailFailure.forbidden }
        let auth = capabilities.first(where: { $0.hasPrefix("AUTH ") || $0.hasPrefix("AUTH=") }) ?? ""
        let mechanisms = auth.replacingOccurrences(of: "AUTH=", with: "AUTH ").split(separator: " ").dropFirst()
        let config = credentials.configuration
        if mechanisms.contains("PLAIN") {
            let payload = Data(("\0" + config.username + "\0" + credentials.password).utf8).base64EncodedString()
            try await writeLine("AUTH PLAIN \(payload)")
            let response = try await reply()
            if response.code == 334 { try await writeLine(payload); try await expect(235, authenticating: true) }
            else { try Self.check(response.code, expected: 235, authenticating: true) }
        } else if mechanisms.contains("LOGIN") {
            try await writeLine("AUTH LOGIN")
            try await expect(334, authenticating: true)
            try await writeLine(Data(config.username.utf8).base64EncodedString())
            try await expect(334, authenticating: true)
            try await writeLine(Data(credentials.password.utf8).base64EncodedString())
            try await expect(235, authenticating: true)
        } else { throw NativeMailFailure.unsupportedOperation }
    }

    func submit(_ mime: Data, from: String, recipients: [String]) async throws {
        guard secured, NativeMailServerValidation.address(from), recipients.allSatisfy(NativeMailServerValidation.address),
              mime.count <= 25 << 20 else { throw NativeMailFailure.invalidDraft }
        try await writeLine("MAIL FROM:<\(from)>")
        try await expect(250)
        for recipient in recipients {
            try await writeLine("RCPT TO:<\(recipient)>")
            let response = try await reply()
            guard response.code == 250 || response.code == 251 else { try Self.check(response.code, expected: 250); continue }
        }
        try await writeLine("DATA")
        try await expect(354)
        // Once any body bytes may have left the process, connection loss (including user cancellation)
        // cannot establish whether the server committed the message. The caller must never auto-retry.
        do {
            try await socket.write(Self.dotStuff(mime))
            let response = try await reply()
            try Self.check(response.code, expected: 250)
        } catch let failure as NativeMailFailure where failure == .forbidden || failure == .rateLimited(60) {
            // An explicit negative final response establishes that this attempt was not accepted.
            throw failure
        } catch { throw NativeMailFailure.deliveryUncertain }
    }

    static func dotStuff(_ data: Data) -> Data {
        var result = Data(), atLineStart = true
        result.reserveCapacity(data.count + 8)
        for byte in data {
            if atLineStart && byte == 46 { result.append(46) }
            result.append(byte)
            atLineStart = byte == 10
        }
        if !result.suffix(2).elementsEqual([13, 10]) { result.append(contentsOf: [13, 10]) }
        result.append(contentsOf: [46, 13, 10])
        return result
    }

    private func ehlo() async throws {
        try await writeLine("EHLO altillo.local")
        let response = try await reply()
        try Self.check(response.code, expected: 250)
        capabilities = response.lines.map { $0.uppercased() }
    }

    private func writeLine(_ value: String) async throws {
        guard !value.contains("\r"), !value.contains("\n"), value.utf8.count <= 16_384 else { throw NativeMailFailure.invalidDraft }
        try Task.checkCancellation()
        try await socket.write(Data((value + "\r\n").utf8))
    }

    private func expect(_ code: Int, authenticating: Bool = false) async throws {
        let response = try await reply()
        try Self.check(response.code, expected: code, authenticating: authenticating)
    }

    private func reply() async throws -> (code: Int, lines: [String]) {
        var lines: [String] = [], expected: Int?
        for _ in 0..<100 {
            let data = try await reader.line(limit: 4_096)
            let bytes = Array(data)
            guard bytes.count >= 3, bytes.prefix(3).allSatisfy({ (48...57).contains($0) }),
                  let code = Int(String(decoding: bytes.prefix(3), as: UTF8.self)), (200...599).contains(code),
                  expected == nil || expected == code else { throw NativeMailFailure.invalidResponse }
            expected = code
            if bytes.count == 3 { return (code, lines) }
            guard bytes[3] == 32 || bytes[3] == 45 else { throw NativeMailFailure.invalidResponse }
            lines.append(String(decoding: bytes.dropFirst(4), as: UTF8.self))
            if bytes[3] == 32 { return (code, lines) }
        }
        throw NativeMailFailure.invalidResponse
    }

    private static func check(_ actual: Int, expected: Int, authenticating: Bool = false) throws {
        guard actual != expected else { return }
        if actual == 535 || actual == 534 || (authenticating && actual >= 500) { throw NativeMailFailure.unauthorized }
        if actual >= 400 && actual < 500 { throw NativeMailFailure.rateLimited(60) }
        if actual >= 500 { throw NativeMailFailure.forbidden }
        throw NativeMailFailure.invalidResponse
    }
}
