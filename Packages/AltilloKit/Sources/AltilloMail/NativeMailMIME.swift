import Foundation

/// RFC 5322/MIME writer shared by API and SMTP providers. SMTP recipients belong to the envelope.
public enum NativeMailMIME {
    public static let outgoingByteLimit = 25 * 1_048_576
    /// Per-file upper bound; the final MIME (all attachments plus body) must also fit outgoingByteLimit.
    public static func maxAttachmentBytes(for service: NativeMailService) -> Int { 18 * 1_048_576 }
    public static let attachmentDownloadByteLimit = 20 * 1_048_576

    public static func validateDraft(_ draft: NativeMailDraft) throws {
        let recipients = draft.to + draft.cc + draft.bcc
        guard !recipients.isEmpty, recipients.count <= 100, recipients.allSatisfy(validAddress),
              safeHeader(draft.subject), draft.subject.utf8.count <= 8_192,
              draft.text.utf8.count <= NativeMailText.bodyByteLimit, draft.attachments.count <= 50 else { throw NativeMailFailure.invalidDraft }
        if let reply = draft.inReplyTo {
            guard validMessageID(reply) else { throw NativeMailFailure.invalidDraft }
        }
        var total = draft.text.utf8.count
        for attachment in draft.attachments {
            guard !attachment.filename.isEmpty, attachment.filename.utf8.count <= 200,
                  safeHeader(attachment.filename), !attachment.filename.contains("/"), !attachment.filename.contains("\\"),
                  attachment.mimeType.range(of: #"^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$"#, options: .regularExpression) != nil else { throw NativeMailFailure.invalidDraft }
            guard attachment.data.count <= outgoingByteLimit - total else { throw NativeMailFailure.contentTooLarge }
            total += attachment.data.count
        }
    }

    public static func encode(draft: NativeMailDraft, from: String, includeBcc: Bool = false) throws -> Data {
        try validateDraft(draft)
        guard validAddress(from) else { throw NativeMailFailure.invalidDraft }
        var lines = ["From: \(from)", "To: \(draft.to.joined(separator: ",\r\n "))"]
        if !draft.cc.isEmpty { lines.append("Cc: " + draft.cc.joined(separator: ",\r\n ")) }
        if includeBcc, !draft.bcc.isEmpty { lines.append("Bcc: " + draft.bcc.joined(separator: ",\r\n ")) }
        lines.append("Subject: " + encodedHeader(draft.subject))
        let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.timeZone = TimeZone(secondsFromGMT: 0)
        date.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        lines.append("Date: " + date.string(from: .now))
        lines.append("Message-ID: <\(UUID().uuidString.lowercased())@\(from.split(separator: "@").last!)>")
        lines.append("MIME-Version: 1.0")
        if let reply = draft.inReplyTo { lines += ["In-Reply-To: " + reply, "References: " + reply] }
        let text = draft.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        let textPart = ["Content-Type: text/plain; charset=utf-8", "Content-Transfer-Encoding: base64", "", base64Lines(Data(text.utf8))]
        if draft.attachments.isEmpty { lines += textPart }
        else {
            let boundary = "altillo-" + UUID().uuidString.lowercased()
            lines += ["Content-Type: multipart/mixed; boundary=\"\(boundary)\"", "", "--" + boundary] + textPart
            for attachment in draft.attachments {
                let filename = attachment.filename.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))!
                lines += ["--" + boundary, "Content-Type: " + attachment.mimeType,
                          "Content-Disposition: attachment; filename*=utf-8''" + filename,
                          "Content-Transfer-Encoding: base64", "", base64Lines(attachment.data)]
            }
            lines.append("--" + boundary + "--")
        }
        let data = Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
        guard data.count <= outgoingByteLimit else { throw NativeMailFailure.contentTooLarge }
        return data
    }

    public static func validAddress(_ value: String) -> Bool {
        guard value.utf8.count <= 254, value.unicodeScalars.allSatisfy({ $0.isASCII }), safeHeader(value),
              !value.contains(where: { $0.isWhitespace }), !value.contains("..") else { return false }
        return value.range(of: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$"#, options: .regularExpression) != nil
    }

    private static func safeHeader(_ value: String) -> Bool {
        !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    private static func validMessageID(_ value: String) -> Bool {
        value.utf8.count <= 900 && safeHeader(value) && value.range(of: #"^<[^<>\s@]+@[^<>\s@]+>$"#, options: .regularExpression) != nil
    }
    private static func encodedHeader(_ value: String) -> String {
        // Small UTF-8 chunks keep every encoded word below RFC 2047's 75-character limit.
        var words: [String] = [], chunk = Data()
        for scalar in value.unicodeScalars {
            let bytes = Data(String(scalar).utf8)
            if chunk.count + bytes.count > 42 { words.append("=?UTF-8?B?" + chunk.base64EncodedString() + "?="); chunk = Data() }
            chunk.append(bytes)
        }
        if !chunk.isEmpty { words.append("=?UTF-8?B?" + chunk.base64EncodedString() + "?=") }
        return words.joined(separator: "\r\n ")
    }
    private static func base64Lines(_ data: Data) -> String {
        data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
    }
}

func nativeMailBase64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
func nativeMailAttachmentData(_ value: String) throws -> Data {
    guard value.utf8.count <= 29 * 1_048_576 else { throw NativeMailFailure.contentTooLarge }
    var encoded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
    guard let data = Data(base64Encoded: encoded), data.count <= NativeMailMIME.attachmentDownloadByteLimit else { throw NativeMailFailure.contentTooLarge }
    return data
}
