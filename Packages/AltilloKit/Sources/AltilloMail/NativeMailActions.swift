import Foundation

public struct NativeMailOutgoingAttachment: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let filename: String
    public let mimeType: String
    public let data: Data
    public init(id: UUID = UUID(), filename: String, mimeType: String, data: Data) {
        self.id = id; self.filename = filename; self.mimeType = mimeType; self.data = data
    }
}

public struct NativeMailDraft: Equatable, Sendable {
    public var to: [String]
    public var cc: [String]
    public var bcc: [String]
    public var subject: String
    public var text: String
    public var inReplyTo: String?
    public var replyingTo: NativeMailMessageKey?
    public var attachments: [NativeMailOutgoingAttachment]
    public init(to: [String], cc: [String] = [], bcc: [String] = [], subject: String, text: String,
                inReplyTo: String? = nil, replyingTo: NativeMailMessageKey? = nil, attachments: [NativeMailOutgoingAttachment] = []) {
        self.to = to; self.cc = cc; self.bcc = bcc; self.subject = subject; self.text = text
        self.inReplyTo = inReplyTo; self.attachments = attachments
        self.replyingTo = replyingTo
    }
}

public struct NativeMailSendReceipt: Equatable, Sendable {
    public let remoteID: String?
    public let sentCopySaved: Bool?
    public init(remoteID: String? = nil, sentCopySaved: Bool? = nil) { self.remoteID = remoteID; self.sentCopySaved = sentCopySaved }
}

public struct NativeMailAttachment: Identifiable, Equatable, Sendable {
    public var id: String { remoteID }
    public let key: NativeMailMessageKey
    public let remoteID: String
    public let filename: String
    public let mimeType: String
    public let byteCount: Int
    public init(key: NativeMailMessageKey, remoteID: String, filename: String, mimeType: String, byteCount: Int) {
        self.key = key; self.remoteID = remoteID; self.filename = filename; self.mimeType = mimeType; self.byteCount = byteCount
    }
}

public enum NativeMailSMTPSecurity: String, Codable, CaseIterable, Sendable { case implicitTLS, startTLS }

public struct NativeMailServerConfiguration: Codable, Equatable, Sendable {
    public var address: String
    public var username: String
    public var displayName: String
    public var imapHost: String
    public var imapPort: Int
    public var smtpHost: String
    public var smtpPort: Int
    public var smtpSecurity: NativeMailSMTPSecurity
    public var saveSentCopy: Bool
    public init(address: String, username: String, displayName: String = "", imapHost: String, imapPort: Int = 993,
                smtpHost: String, smtpPort: Int = 587, smtpSecurity: NativeMailSMTPSecurity = .startTLS, saveSentCopy: Bool = true) {
        self.address = address; self.username = username; self.displayName = displayName
        self.imapHost = imapHost; self.imapPort = imapPort; self.smtpHost = smtpHost
        self.smtpPort = smtpPort; self.smtpSecurity = smtpSecurity
        self.saveSentCopy = saveSentCopy
    }
    public static func icloud(address: String, username: String? = nil) -> Self {
        .init(address: address, username: username ?? address, imapHost: "imap.mail.me.com", smtpHost: "smtp.mail.me.com")
    }
}

public struct NativeMailServerCredentials: Codable, Equatable, Sendable {
    public let configuration: NativeMailServerConfiguration
    public let password: String
    public init(configuration: NativeMailServerConfiguration, password: String) {
        self.configuration = configuration; self.password = password
    }
}
public typealias NativeMailServerCredentialLoader = @Sendable () async throws -> NativeMailServerCredentials
