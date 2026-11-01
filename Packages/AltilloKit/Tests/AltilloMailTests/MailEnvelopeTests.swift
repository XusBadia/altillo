import Foundation
import Testing
@testable import AltilloMail

@Suite("Transient Mail envelopes")
struct MailEnvelopeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(messageID: String = "fixture@example.invalid", sender: String = "Altillo <synthetic@example.invalid>",
                       subject: String = "Your sign-in", body: String = "", account: String = "Work",
                       age: Double = 0, version: Int = 1) -> MailEnvelope {
        MailEnvelope(version: version, messageID: messageID, sender: sender, subject: subject,
                     body: body, account: account, receivedAt: now.timeIntervalSince1970 - age)
    }

    @Test func unicodeAndQuotedContentRoundTripsWithoutARequiredTestPrefix() throws {
        let value = event(subject: "Acceso · 日本語", body: "Café \"quoted\"\nUna segunda línea\t🗝️")
        let data = try JSONEncoder().encode(value)
        #expect(try MailEnvelope.decode(data, now: now) == value)
        #expect(value.id == value.messageID)
    }

    @Test func olderBridgeFixturesCanOmitAccount() throws {
        var dictionary = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(event())) as? [String: Any])
        dictionary["account"] = nil
        let decoded = try MailEnvelope.decode(JSONSerialization.data(withJSONObject: dictionary), now: now)
        #expect(decoded.account.isEmpty)
    }

    @Test func malformedAndUnknownVersionErrorsDoNotContainPayload() throws {
        #expect(throws: MailEnvelope.Failure.invalidPayload) { try MailEnvelope.decode(Data("private subject".utf8), now: now) }
        #expect(throws: MailEnvelope.Failure.invalidPayload) {
            try MailEnvelope.decode(JSONEncoder().encode(event(version: 2)), now: now)
        }
    }

    @Test func freshnessHasExplicitBoundaries() throws {
        for age in [-30.0, 0, 300] {
            #expect(try MailEnvelope.decode(JSONEncoder().encode(event(age: age)), now: now).receivedAt
                == now.timeIntervalSince1970 - age)
        }
        for age in [-30.01, 300.01] {
            #expect(throws: MailEnvelope.Failure.expired) {
                try MailEnvelope.decode(JSONEncoder().encode(event(age: age)), now: now)
            }
        }
    }

    @Test func fieldsAndEncodedBytesAreBounded() throws {
        let boundary = event(sender: String(repeating: "s", count: 1_024), subject: String(repeating: "u", count: 1_024),
                             body: String(repeating: "b", count: 48_000), account: String(repeating: "a", count: 1_024))
        #expect(try MailEnvelope.decode(JSONEncoder().encode(boundary), now: now) == boundary)
        let invalid = [
            event(sender: String(repeating: "s", count: 1_025)),
            event(subject: String(repeating: "u", count: 1_025)),
            event(body: String(repeating: "b", count: 48_001)),
            event(account: String(repeating: "a", count: 1_025)),
            event(body: String(repeating: "界", count: 16_001)),
            event(sender: "private\0sender"), event(subject: "private\0subject"), event(account: "private\0account"),
        ]
        for value in invalid {
            #expect(throws: MailEnvelope.Failure.invalidPayload) {
                try MailEnvelope.decode(JSONEncoder().encode(value), now: now)
            }
        }
        // Escaping can exceed the wire limit even when the decoded body fits its own limit.
        let oversizedEncoding = try JSONEncoder().encode(event(body: String(repeating: "\"", count: 40_000)))
        #expect(oversizedEncoding.count > MailWire.byteLimit)
        #expect(throws: MailEnvelope.Failure.invalidPayload) { try MailEnvelope.decode(oversizedEncoding, now: now) }
    }

    @Test(arguments: ["", "<>", "two words@example.invalid", "id\n@example.invalid", "id\0@example.invalid", "<one>two@example.invalid", "a>id@example.invalid"])
    func invalidMessageIdentifiersDoNotBecomeURLs(_ identifier: String) throws {
        let value = event(messageID: identifier)
        #expect(value.messageURL == nil)
        #expect(throws: MailEnvelope.Failure.invalidPayload) { try MailEnvelope.decode(JSONEncoder().encode(value), now: now) }
    }

    @Test func messageURLUsesTheRFCIdentifierAndEscapesReservedCharacters() throws {
        #expect(event().messageURL?.absoluteString == "message://%3Cfixture%40example.invalid%3E")
        #expect(event(messageID: "<fixture@example.invalid>").messageURL == event().messageURL)
        #expect(event(messageID: "a?#/id@example.invalid").messageURL?.absoluteString
            == "message://%3Ca%3F%23%2Fid%40example.invalid%3E")
        let tooLong = event(messageID: String(repeating: "a", count: 513))
        #expect(tooLong.messageURL == nil)
    }

    @Test func labelledCodesAreConservativeAndDifferentCandidatesAreAmbiguous() {
        #expect(event(body: "Your verification code is 482913").code == "482913")
        #expect(event(body: "Tu código de acceso: 482913").code == "482913")
        #expect(event(subject: "Security code: 482913", body: "Security code: 482913").code == "482913")
        #expect(event(subject: "Code: 1234", body: "Code: 5678").code == nil)
        #expect(event(body: "Invoice 482913. Amount 2026.").code == nil)
        #expect(event(body: "code: 123").code == nil)
        #expect(event(body: "code: 123456789").code == nil)
        #expect(event(body: "code: 123456x").code == nil)
        #expect(event(body: "decode 123456").code == nil)
        #expect(event(body: "postcode 123456").code == nil)
    }

    @Test func recognizesOneExplicitHTTPSTokenLink() {
        let text = "Use https://example.invalid/login?token=synthetic to sign in."
        #expect(event(body: text).magicLink?.host == "example.invalid")
        #expect(event(body: "https://example.invalid/login?login_token=synthetic").magicLink != nil)
        #expect(event(body: text + "\n" + text).magicLink != nil)
        #expect(event(body: "https://example.invalid/login?token=one https://example.invalid/auth?token=two").magicLink == nil)
        #expect(event(body: "https://example.invalid/api/auth/callback?token=synthetic").magicLink != nil)
        #expect(event(body: "https://example.invalid/login.php?token=synthetic").magicLink != nil)
        #expect(event(body: "https://example.invalid/callback?magic_token=synthetic").magicLink != nil)
        #expect(event(body: "https://example.invalid/callback?verification_token=synthetic").magicLink != nil)
    }

    @Test(arguments: [
        "http://example.invalid/login?token=synthetic",
        "javascript:alert('token=synthetic')",
        "file:///tmp/login?token=synthetic",
        "https://user:password@example.invalid/login?token=synthetic",
        "https://user@example.invalid/login?token=synthetic",
        "https://example.invalid/newsletter",
        "https://example.invalid/login?token=",
        "https://example.invalid/login?token=%20",
        "https://example.invalid/unsubscribe?token=synthetic",
        "https://example.invalid/unsubscribe.html?token=synthetic",
        "https://example.invalid/auth/logout?token=synthetic",
        "https://example.invalid/logout?login_token=synthetic",
        "https://example.invalid/manage?token=synthetic",
        "https://example.invalid/newsletter?token=synthetic",
    ])
    func unsafeOrUnlabelledLinksAreNotOffered(_ text: String) {
        #expect(event(body: text).magicLink == nil)
    }
}
