import Foundation
import AltilloMail

enum MailAuthFailure: Error, Equatable, Sendable {
    case notConfigured, cancelled, denied, unavailable, reconnectRequired, credentialStorage
    case accountMismatch, operationInProgress
}

/// Application registration belongs to the distributor, never to the person connecting a mailbox.
struct MailNativeConfiguration: Sendable {
    let googleClientID: String?
    let microsoftClientID: String?
    let bundleIdentifier: String

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:],
         bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "me.badia.altillo") {
        self.bundleIdentifier = bundleIdentifier
        let google = Self.value(info["ALTILLO_GOOGLE_MAIL_CLIENT_ID"])
        googleClientID = google.flatMap {
            $0.range(of: #"^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$"#,
                     options: .regularExpression) != nil ? $0 : nil
        }
        let microsoft = Self.value(info["ALTILLO_MICROSOFT_MAIL_CLIENT_ID"])
        microsoftClientID = microsoft.flatMap { UUID(uuidString: $0) != nil ? $0 : nil }
    }

    var availableServices: [NativeMailService] {
        NativeMailService.allCases.filter {
            switch $0 {
            case .google: googleClientID != nil
            case .microsoft: microsoftClientID != nil
            case .icloud, .imap: true
            }
        }
    }

    static let authorizationVersion = 2
    // gmail.modify also authorizes messages.send; requesting gmail.send again is redundant.
    static let googleScopes = ["openid", "email", "https://www.googleapis.com/auth/gmail.modify"]
    // MSAL itself supplies openid/profile/offline_access.
    static let microsoftScopes = ["User.Read", "Mail.ReadWrite", "Mail.Send"]

    var microsoftRedirectURI: String { "msauth.\(bundleIdentifier)://auth" }

    private static func value(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$("), !trimmed.contains("${") else { return nil }
        return trimmed
    }
}
