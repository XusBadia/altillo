import Foundation

/// One new message received through an explicitly installed Apple Mail rule.
/// The body is transient input for access-code/link recognition, not an archive or assistant context.
public struct MailEnvelope: Codable, Sendable, Identifiable, Equatable {
    public enum Failure: Error, Equatable, Sendable {
        case invalidPayload
        case expired
    }

    public let version: Int
    public let messageID: String
    public let sender: String
    public let subject: String
    public let body: String
    public let account: String
    public let receivedAt: Double

    public var id: String { messageID }

    public init(version: Int = 1, messageID: String, sender: String, subject: String, body: String,
                account: String = "", receivedAt: Double) {
        self.version = version
        self.messageID = messageID
        self.sender = sender
        self.subject = subject
        self.body = body
        self.account = account
        self.receivedAt = receivedAt
    }

    private enum CodingKeys: String, CodingKey {
        case version, messageID, sender, subject, body, account, receivedAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        messageID = try values.decode(String.self, forKey: .messageID)
        sender = try values.decode(String.self, forKey: .sender)
        subject = try values.decode(String.self, forKey: .subject)
        body = try values.decode(String.self, forKey: .body)
        account = try values.decodeIfPresent(String.self, forKey: .account) ?? ""
        receivedAt = try values.decode(Double.self, forKey: .receivedAt)
    }

    /// Errors are categorical: decoding errors must not put sender, subject or token fragments in diagnostics.
    public static func decode(_ data: Data, now: Date = .now) throws(Failure) -> Self {
        guard data.count <= MailWire.byteLimit,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.version == 1,
              value.receivedAt.isFinite, value.validMessageID,
              value.sender.utf8.count <= 1_024, value.subject.utf8.count <= 1_024,
              value.account.utf8.count <= 1_024, value.body.utf8.count <= 48_000,
              !value.sender.contains("\0"), !value.subject.contains("\0"), !value.account.contains("\0")
        else { throw .invalidPayload }
        let age = now.timeIntervalSince1970 - value.receivedAt
        guard age >= -30, age <= MailWire.lifetime else { throw .expired }
        return value
    }

    /// The actual RFC Message-ID is needed; a numeric Mail database ID is not a message URL.
    public var messageURL: URL? {
        guard validMessageID else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let value = "<\(canonicalMessageID)>".addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "message://" + value)
    }

    private var canonicalMessageID: String {
        if messageID.hasPrefix("<"), messageID.hasSuffix(">") { return String(messageID.dropFirst().dropLast()) }
        return messageID
    }

    private var validMessageID: Bool {
        guard !messageID.isEmpty, messageID.utf8.count <= 512 else { return false }
        let value = canonicalMessageID
        return !value.isEmpty && !value.unicodeScalars.contains {
            CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
                || $0 == "<" || $0 == ">"
        }
    }

    /// Only an explicitly labelled 4–8 digit candidate is offered. Different candidates suppress the action.
    /// This is a convenience heuristic, never evidence that the message or sender is trusted.
    public var code: String? {
        let pattern = #"(?i)\b(?:verification\s+code|security\s+code|sign[ -]?in\s+code|código(?:\s+de\s+(?:acceso|verificación))?|code)\s*(?:is|es|:|=|-)?\s*\b([0-9]{4,8})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let text = subject + "\n" + body
        let values = Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        })
        return values.count == 1 ? values.first : nil
    }

    /// Restrict automatic recognition to one HTTPS token link, with no embedded credentials.
    /// The UI must still show its domain and require a click; recognition does not establish authenticity.
    public var magicLink: URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let values = Set(detector.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap { match -> URL? in
            guard let url = match.url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
                  let host = url.host, !host.isEmpty, !host.hasSuffix("."),
                  host.unicodeScalars.allSatisfy({ $0.isASCII }),
                  let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            let path = parts.path.lowercased().split(separator: "/").map {
                // Common endpoints use extensions, e.g. login.php and unsubscribe.html.
                String($0.split(separator: ".", omittingEmptySubsequences: false).first ?? "")
            }
            let nonAuthentication = Set(["unsubscribe", "logout", "log-out", "signout", "sign-out", "delete", "remove", "cancel", "unfollow"])
            guard path.allSatisfy({ !nonAuthentication.contains($0) }) else { return nil }
            let authentication = Set(["login", "signin", "sign-in", "verify", "auth", "magic", "magic-link", "magiclink"])
            let hasAuthenticationPath = path.contains { authentication.contains($0) }
            guard parts.queryItems?.contains(where: { item in
                guard !(item.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                let name = item.name.lowercased()
                if ["magic_token", "login_token", "verification_token"].contains(name) { return true }
                return name == "token" && hasAuthenticationPath
            }) == true else { return nil }
            return url
        })
        return values.count == 1 ? values.first : nil
    }
}

public enum MailWire {
    public static let byteLimit = 65_536
    public static let lifetime: Double = 300
    public static var defaultSocketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Altillo/Mail/mail.sock").path
    }
}
