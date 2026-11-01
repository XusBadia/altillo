import Foundation
import Testing
@testable import AltilloMail

struct NativeMailSMTPTests {
    @Test func startTLSRequiresUpgradeAndSecondEHLOBeforeAnyCredentials() async throws {
        let socket = MailScriptedSocket(smtpWireStart())
        let factory = MailScriptedFactory([socket])
        try await NativeMailSMTP.validate(credentials: imapWireCredentials(), sockets: factory.make)
        #expect(await socket.finished())
        #expect(await factory.endpoints() == ["smtp.example.invalid:587:plain"])
    }

    @Test func missingOrRefusedSTARTTLSNeverSendsCredentials() async throws {
        let missing = MailScriptedSocket([
            .server(Data("220 synthetic\r\n".utf8)), .client("EHLO altillo.local\r\n"),
            .server(Data("250-synthetic\r\n250 AUTH PLAIN\r\n".utf8))])
        let refused = MailScriptedSocket([
            .server(Data("220 synthetic\r\n".utf8)), .client("EHLO altillo.local\r\n"),
            .server(Data("250-synthetic\r\n250 STARTTLS\r\n".utf8)),
            .client("STARTTLS\r\n"), .server(Data("454 TLS unavailable\r\n".utf8))])
        let factory = MailScriptedFactory([missing, refused])
        await #expect(throws: NativeMailFailure.forbidden) {
            try await NativeMailSMTP.validate(credentials: imapWireCredentials(), sockets: factory.make)
        }
        await #expect(throws: NativeMailFailure.rateLimited(60)) {
            try await NativeMailSMTP.validate(credentials: imapWireCredentials(), sockets: factory.make)
        }
        #expect(await missing.finished())
        #expect(await refused.finished())
    }

    @Test func implicitTLSUses465AndRejectsBadAuthentication() async throws {
        let socket = MailScriptedSocket(smtpWireStart(implicitTLS: true, authenticationReply: "535 Authentication failed"))
        let factory = MailScriptedFactory([socket])
        await #expect(throws: NativeMailFailure.unauthorized) {
            try await NativeMailSMTP.validate(credentials: imapWireCredentials(security: .implicitTLS), sockets: factory.make)
        }
        #expect(await socket.finished())
        #expect(await factory.endpoints() == ["smtp.example.invalid:465:tls"])
    }

    @Test func sendUsesAllEnvelopeRecipientsAndExcludesBccHeader() async throws {
        var script = smtpWireStart()
        script += [.client("MAIL FROM:<user@example.invalid>\r\n"), .server(Data("250 sender\r\n".utf8)),
                   .client("RCPT TO:<blind@example.invalid>\r\n"), .server(Data("250 recipient\r\n".utf8)),
                   .client("RCPT TO:<other@example.invalid>\r\n"), .server(Data("250 recipient\r\n".utf8)),
                   .client("DATA\r\n"), .server(Data("354 body\r\n".utf8)),
                   .clientPrefix("From:"), .server(Data("250 queued\r\n".utf8))]
        let socket = MailScriptedSocket(script)
        let factory = MailScriptedFactory([socket])
        let draft = NativeMailDraft(to: ["other@example.invalid"], bcc: ["blind@example.invalid"], subject: "Synthetic", text: "Fixture only")
        _ = try await NativeMailSMTP.send(draft, credentials: imapWireCredentials(), sockets: factory.make)
        let body = try #require(await socket.writes().last)
        #expect(!String(decoding: body, as: UTF8.self).contains("Bcc:"))
        #expect(body.suffix(5).elementsEqual(Data("\r\n.\r\n".utf8)))
        #expect(await socket.finished())
    }

    @Test func lostFinalAcceptanceAndCancellationAfterDATAAreUncertain() async throws {
        for ending in [MailSocketScriptStep.failRead(.unavailable), .cancelRead] {
            var script = smtpWireStart()
            script += [.client("MAIL FROM:<user@example.invalid>\r\n"), .server(Data("250 sender\r\n".utf8)),
                       .client("RCPT TO:<other@example.invalid>\r\n"), .server(Data("250 recipient\r\n".utf8)),
                       .client("DATA\r\n"), .server(Data("354 body\r\n".utf8)), .clientPrefix("From:"), ending]
            let socket = MailScriptedSocket(script)
            let factory = MailScriptedFactory([socket])
            await #expect(throws: NativeMailFailure.deliveryUncertain) {
                _ = try await NativeMailSMTP.send(.init(to: ["other@example.invalid"], subject: "Synthetic", text: "Fixture"),
                                                credentials: imapWireCredentials(), sockets: factory.make)
            }
            #expect(await socket.finished())
        }
    }

    @Test func recipientRejectionNeverSendsDATA() async throws {
        var script = smtpWireStart()
        script += [.client("MAIL FROM:<user@example.invalid>\r\n"), .server(Data("250 sender\r\n".utf8)),
                   .client("RCPT TO:<other@example.invalid>\r\n"), .server(Data("550 no recipient\r\n".utf8))]
        let socket = MailScriptedSocket(script)
        let factory = MailScriptedFactory([socket])
        await #expect(throws: NativeMailFailure.forbidden) {
            _ = try await NativeMailSMTP.send(.init(to: ["other@example.invalid"], subject: "Synthetic", text: "Fixture"),
                                            credentials: imapWireCredentials(), sockets: factory.make)
        }
        #expect(await socket.finished())
    }

    @Test func combinedValidationAuthenticatesBothServersWithoutSendingMail() async throws {
        // Validation deliberately does not SELECT or send a message.
        let imap = MailScriptedSocket(Array(imapWireStart().dropLast(2)))
        let smtp = MailScriptedSocket(smtpWireStart())
        let factory = MailScriptedFactory([imap, smtp])
        try await IMAPNativeMailProvider.validate(credentials: imapWireCredentials(), sockets: factory.make)
        #expect(await imap.finished())
        #expect(await smtp.finished())
        #expect(await factory.endpoints().count == 2)
    }

    @Test func oversizedDraftFailsBeforeOpeningTheNetworkAndDotStuffingIsByteExact() async throws {
        let factory = MailScriptedFactory([])
        let file = NativeMailOutgoingAttachment(filename: "fixture.bin", mimeType: "application/octet-stream", data: Data(repeating: 0, count: 19 << 20))
        let draft = NativeMailDraft(to: ["other@example.invalid"], subject: "Synthetic", text: "Fixture", attachments: [file])
        await #expect(throws: NativeMailFailure.contentTooLarge) {
            _ = try await NativeMailSMTP.send(draft, credentials: imapWireCredentials(), sockets: factory.make)
        }
        #expect(await factory.endpoints().isEmpty)
        let input = Data(".one\r\n..two\r\nthree".utf8)
        #expect(NativeMailSMTPSession.dotStuff(input) == Data("..one\r\n...two\r\nthree\r\n.\r\n".utf8))
    }

    @Test func acceptedMessageIsAppendedToSentWithExactlyTheSubmittedMIMEAndMessageID() async throws {
        let smtp = MailScriptedSocket(smtpWireAcceptedMessage())
        let imap = MailScriptedSocket(Array(imapWireStart().dropLast(2)) + [
            .client("A4 LIST \"\" \"*\"\r\n"),
            .server(Data("* LIST (\\Sent) \"/\" \"Sent Items\"\r\nA4 OK done\r\n".utf8)),
            .clientPrefix("A5 APPEND \"Sent Items\" (\\Seen) {"), .server(Data("+ ready for literal\r\n".utf8)),
            .clientPrefix("From:"), .server(Data("A5 OK [APPENDUID 9 101] saved\r\n".utf8))])
        let factory = MailScriptedFactory([smtp, imap])
        let provider = IMAPNativeMailProvider(account: imapWireAccount(), credentials: { imapWireCredentials() }, sockets: factory.make)
        let receipt = try await provider.send(.init(to: ["other@example.invalid"], subject: "Synthetic", text: "Fixture"))
        #expect(receipt.sentCopySaved == true)
        let submitted = try #require(await smtp.writes().last)
        let appended = try #require(await imap.writes().last)
        // SMTP adds its dot terminator; APPEND adds a command CRLF after the literal.
        #expect(Data(submitted.dropLast(3)) == Data(appended.dropLast(2)))
        let appendCommand = try #require(await imap.writes().dropLast().last)
        #expect(String(decoding: appendCommand, as: UTF8.self).hasSuffix("{\(appended.count - 2)}\r\n"))
        #expect(await smtp.finished())
        #expect(await imap.finished())
    }

    @Test func failedSentCopyStillReturnsAcceptedReceiptAndDoesNotResubmitSMTP() async throws {
        let smtp = MailScriptedSocket(smtpWireAcceptedMessage())
        let imap = MailScriptedSocket(Array(imapWireStart().dropLast(2)) + [
            .client("A4 LIST \"\" \"*\"\r\n"),
            .server(Data("* LIST (\\Sent) \"/\" \"Sent\"\r\nA4 OK done\r\n".utf8)),
            .clientPrefix("A5 APPEND \"Sent\" (\\Seen) {"), .server(Data("A5 NO [OVERQUOTA] full\r\n".utf8))])
        let factory = MailScriptedFactory([smtp, imap])
        let provider = IMAPNativeMailProvider(account: imapWireAccount(), credentials: { imapWireCredentials() }, sockets: factory.make)
        let receipt = try await provider.send(.init(to: ["other@example.invalid"], subject: "Synthetic", text: "Fixture"))
        #expect(receipt.sentCopySaved == false)
        #expect(await factory.endpoints() == ["smtp.example.invalid:587:plain", "imap.example.invalid:993:tls"])
        #expect(await smtp.writes().filter { $0 == Data("DATA\r\n".utf8) }.count == 1)
        #expect(await smtp.finished())
        #expect(await imap.finished())
    }

    @Test func automaticServerSentCopiesCanBeOptedOutWithoutOpeningIMAP() async throws {
        let smtp = MailScriptedSocket(smtpWireAcceptedMessage())
        let factory = MailScriptedFactory([smtp])
        var config = imapWireCredentials().configuration
        config.saveSentCopy = false
        let credentials = NativeMailServerCredentials(configuration: config, password: "synthetic-password")
        let provider = IMAPNativeMailProvider(account: imapWireAccount(), credentials: { credentials }, sockets: factory.make)
        let receipt = try await provider.send(.init(to: ["other@example.invalid"], subject: "Synthetic", text: "Fixture"))
        #expect(receipt.sentCopySaved == nil)
        #expect(await factory.endpoints().count == 1)
        #expect(await smtp.finished())
    }
}

func smtpWireAcceptedMessage() -> [MailSocketScriptStep] {
    smtpWireStart() + [.client("MAIL FROM:<user@example.invalid>\r\n"), .server(Data("250 sender\r\n".utf8)),
        .client("RCPT TO:<other@example.invalid>\r\n"), .server(Data("250 recipient\r\n".utf8)),
        .client("DATA\r\n"), .server(Data("354 body\r\n".utf8)), .clientPrefix("From:"), .server(Data("250 queued\r\n".utf8))]
}

func smtpWireStart(implicitTLS: Bool = false, authenticationReply: String = "235 accepted") -> [MailSocketScriptStep] {
    var result: [MailSocketScriptStep] = [.server(Data("220 synthetic\r\n".utf8)), .client("EHLO altillo.local\r\n")]
    if !implicitTLS {
        result += [.server(Data("250-synthetic\r\n250 STARTTLS\r\n".utf8)), .client("STARTTLS\r\n"),
                   .server(Data("220 ready\r\n".utf8)), .tls, .client("EHLO altillo.local\r\n")]
    }
    let payload = Data("\0user@example.invalid\0synthetic-password".utf8).base64EncodedString()
    return result + [.server(Data("250-synthetic\r\n250 AUTH PLAIN LOGIN\r\n".utf8)),
                     .client("AUTH PLAIN \(payload)\r\n"), .server(Data("\(authenticationReply)\r\n".utf8))]
}
