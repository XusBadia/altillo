import CryptoKit
import Foundation

// Claude Code's OAuth credentials, read-only. Altillo never refreshes, rewrites or deletes them: refresh tokens
// rotate, and refreshing here would sign Claude Code out.
//
// Lookup order, keychain suffix rule and hex fallback adapted from openusage's ClaudeAuthStore
// (https://github.com/robinebers/openusage, MIT). See ThirdPartyNotices/README.md.

/// The parts of Claude Code's credential Altillo needs. The refresh token is deliberately never kept.
public struct ClaudeCredentials: Sendable, Hashable {
    public enum Source: String, Sendable, Hashable { case keychain, file }

    public var accessToken: String
    public var expiresAt: Date?
    public var subscriptionType: String?
    public var rateLimitTier: String?
    /// Nil when the credential doesn't list scopes (older versions): assume it can read usage.
    public var scopes: [String]?
    public var source: Source

    public init(accessToken: String, expiresAt: Date?, subscriptionType: String?, rateLimitTier: String?,
                scopes: [String]?, source: Source) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
        self.scopes = scopes
        self.source = source
    }

    /// Expired, or expiring within `margin` (Altillo won't refresh it, so a nearly dead token is as good as dead).
    public func isExpired(now: Date, margin: TimeInterval = 5 * 60) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now.addingTimeInterval(margin)
    }

    /// Tokens minted without `user:profile` (e.g. `claude setup-token`) can't read the usage endpoint.
    public var canReadUsage: Bool {
        guard let scopes, !scopes.isEmpty else { return true }
        return scopes.contains("user:profile")
    }

    /// Parses Claude Code's credential JSON (`{"claudeAiOauth":{…}}`), plain or hex-encoded.
    public static func parse(_ text: String, source: Source) -> ClaudeCredentials? {
        guard let root = UsageParsing.objectWithHexFallback(text),
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = UsageParsing.string(oauth["accessToken"])
        else { return nil }
        return ClaudeCredentials(
            accessToken: token,
            expiresAt: UsageParsing.date(oauth["expiresAt"]),
            subscriptionType: UsageParsing.string(oauth["subscriptionType"]),
            rateLimitTier: UsageParsing.string(oauth["rateLimitTier"]),
            scopes: (oauth["scopes"] as? [Any])?.compactMap { $0 as? String },
            source: source
        )
    }
}

/// Result of looking for Claude Code's credentials.
public enum ClaudeCredentialLookup: Sendable, Hashable {
    case found(ClaudeCredentials)
    case notFound
    /// The keychain refused (or a prompt went unanswered).
    case accessDenied
}

/// Where the Claude collector gets its credentials. Tests inject fixed values.
public protocol ClaudeCredentialReading: Sendable {
    func read(now: Date) async -> ClaudeCredentialLookup
}

/// Reads the keychain item first (Claude Code's source of truth on macOS), then the credentials file.
///
/// The keychain is read by running `/usr/bin/security find-generic-password … -w`: the item's ACL trusts that
/// binary, so no keychain prompt appears (reading it through Security.framework from Altillo would prompt).
public struct ClaudeCredentialStore: ClaudeCredentialReading {
    static let securityTool = URL(fileURLWithPath: "/usr/bin/security")
    static let serviceBase = "Claude Code-credentials"
    /// `security` exit status for "item not found".
    static let notFoundStatus: Int32 = 44

    private let runner: any CommandRunning
    private let environment: [String: String]
    private let homeDirectory: URL
    private let userName: String
    private let readFile: @Sendable (URL) -> String?

    public init(runner: any CommandRunning = ProcessCommandRunner(),
                environment: [String: String] = ProcessInfo.processInfo.environment,
                homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                userName: String = NSUserName(),
                readFile: @escaping @Sendable (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) }) {
        self.runner = runner
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.userName = userName
        self.readFile = readFile
    }

    /// `CLAUDE_CONFIG_DIR`, when set.
    var configDirectoryOverride: String? {
        guard let value = environment["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    /// `${CLAUDE_CONFIG_DIR:-~/.claude}/.credentials.json`.
    var credentialsFile: URL {
        if let override = configDirectoryOverride {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).appendingPathComponent(".credentials.json")
        }
        return homeDirectory.appendingPathComponent(".claude/.credentials.json")
    }

    /// With `CLAUDE_CONFIG_DIR` set, Claude Code suffixes the service with the first 8 hex chars of the SHA-256 of
    /// the (NFC-normalised) directory; the plain name is kept as a fallback.
    var keychainServices: [String] {
        guard let override = configDirectoryOverride else { return [Self.serviceBase] }
        let digest = SHA256.hash(data: Data(override.precomposedStringWithCanonicalMapping.utf8))
        let suffix = digest.map { String(format: "%02x", $0) }.joined().prefix(8)
        return ["\(Self.serviceBase)-\(suffix)", Self.serviceBase]
    }

    public func read(now: Date) async -> ClaudeCredentialLookup {
        var keychainDenied = false
        var keychain: ClaudeCredentials?
        search: for service in keychainServices {
            for arguments in [["find-generic-password", "-a", userName, "-s", service, "-w"],
                              ["find-generic-password", "-s", service, "-w"]] {
                guard let result = await runner.run(Self.securityTool, arguments: arguments, timeout: 10) else {
                    break search
                }
                if result.status == 0 {
                    let text = String(decoding: result.stdout, as: UTF8.self)
                    if let parsed = ClaudeCredentials.parse(text, source: .keychain) {
                        keychain = parsed
                        break search
                    }
                    continue
                }
                if result.timedOut || result.status != Self.notFoundStatus {
                    keychainDenied = true
                    break search
                }
            }
        }

        let file = readFile(credentialsFile).flatMap { ClaudeCredentials.parse($0, source: .file) }

        // A valid keychain token wins; a valid file token is next; otherwise report whichever exists (expired).
        let candidates = [keychain, file].compactMap { $0 }
        if let usable = candidates.first(where: { !$0.isExpired(now: now) }) { return .found(usable) }
        if let any = candidates.first { return .found(any) }
        return keychainDenied ? .accessDenied : .notFound
    }
}
