import AltilloCore
import Foundation

// GitHub Copilot usage from GitHub's Copilot user endpoint, with a GitHub token the user's own tools already keep
// (Copilot editor plugins, the GitHub CLI). Read-only: tokens are never refreshed or rewritten.
//
// Token sources (github.com-only host scoping, go-keyring unwrap), request headers and quota mapping adapted from
// openusage (MIT), Sources/OpenUsage/Providers/Copilot/{CopilotAuthStore,CopilotUsageClient,CopilotUsageMapper}.swift
// @87c3d2db465a5eb6c6dd2c2453c55cd82141a76e.

extension UsageProviderID {
    public static let copilot = UsageProviderID(rawValue: "copilot")
}

// MARK: - Token

public struct CopilotToken: Sendable, Hashable {
    public enum Source: String, Sendable, Hashable { case editorConfig, ghConfig, ghKeychain }
    public var value: String
    public var source: Source

    public init(value: String, source: Source) {
        self.value = value
        self.source = source
    }
}

public enum CopilotTokenLookup: Sendable, Hashable {
    case found(CopilotToken)
    case notFound
    case accessDenied
}

public protocol CopilotTokenReading: Sendable {
    /// Cheap: is there an editor Copilot config or a GitHub CLI github.com sign-in (no secret read)?
    func exists() async -> Bool
    func read() async -> CopilotTokenLookup
}

/// Prompt-free files first, keychain last:
/// 1. `~/.config/github-copilot/apps.json` (older `hosts.json`), written by the Copilot editor plugins;
/// 2. `~/.config/gh/hosts.yml` `oauth_token` (GitHub CLI with file storage);
/// 3. the GitHub CLI keychain item `gh:github.com` (go-keyring, stored through `/usr/bin/security`, so no prompt).
/// Only github.com entries are used: an Enterprise host's token must never be sent to api.github.com.
public struct CopilotTokenStore: CopilotTokenReading {
    static let ghKeychainService = "gh:github.com"

    private let environment: [String: String]
    private let home: URL
    private let readFile: @Sendable (URL) -> String?
    private let keychain: any KeychainSecretReading

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                readFile: @escaping @Sendable (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) },
                keychain: any KeychainSecretReading = SecurityCLIKeychain()) {
        self.environment = environment
        self.home = home
        self.readFile = readFile
        self.keychain = keychain
    }

    var editorFiles: [URL] {
        let directory = LocalAPIKeySource.configDirectory(environment: environment, home: home)
            .appendingPathComponent("github-copilot")
        return [directory.appendingPathComponent("apps.json"), directory.appendingPathComponent("hosts.json")]
    }

    /// `$GH_CONFIG_DIR/hosts.yml`, else `${XDG_CONFIG_HOME:-~/.config}/gh/hosts.yml`.
    var ghHostsFile: URL {
        if let custom = environment["GH_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath).appendingPathComponent("hosts.yml")
        }
        return LocalAPIKeySource.configDirectory(environment: environment, home: home)
            .appendingPathComponent("gh/hosts.yml")
    }

    public func exists() async -> Bool {
        if editorFiles.contains(where: { readFile($0).flatMap(Self.editorToken) != nil }) { return true }
        guard let hosts = readFile(ghHostsFile) else { return false }
        return Self.yamlValue(hosts, key: "oauth_token") != nil || Self.yamlValue(hosts, key: "user") != nil
    }

    public func read() async -> CopilotTokenLookup {
        for file in editorFiles {
            if let token = readFile(file).flatMap(Self.editorToken) {
                return .found(CopilotToken(value: token, source: .editorConfig))
            }
        }
        let hosts = readFile(ghHostsFile)
        if let token = hosts.flatMap({ Self.yamlValue($0, key: "oauth_token") }) {
            return .found(CopilotToken(value: token, source: .ghConfig))
        }
        guard let hosts else { return .notFound }

        // gh keys its keychain item by the GitHub username; fall back to a service-only lookup.
        var accounts: [String?] = []
        if let user = Self.yamlValue(hosts, key: "user") { accounts.append(user) }
        accounts.append(nil)
        for account in accounts {
            switch await keychain.secret(service: Self.ghKeychainService, account: account) {
            case .found(let raw):
                if let token = Group1Support.unwrapGoKeyring(raw) {
                    return .found(CopilotToken(value: token, source: .ghKeychain))
                }
            case .denied:
                return .accessDenied
            case .notFound:
                continue
            }
        }
        return .notFound
    }

    /// github.com `oauth_token` from the editor config: keys `"github.com"` (hosts.json) or `"github.com:<app>"`.
    static func editorToken(_ text: String) -> String? {
        guard let object = UsageParsing.object(Data(text.utf8)) else { return nil }
        for key in object.keys.sorted() where key == "github.com" || key.hasPrefix("github.com:") {
            if let entry = object[key] as? [String: Any], let token = UsageParsing.string(entry["oauth_token"]) {
                return token
            }
        }
        return nil
    }

    /// An indented `key: value` inside the top-level `github.com:` block of gh's `hosts.yml`.
    static func yamlValue(_ text: String, key: String, host: String = "github.com") -> String? {
        let prefix = key + ":"
        var inHost = false
        for line in text.split(whereSeparator: \.isNewline) {
            if let first = line.first, !first.isWhitespace {
                inHost = line.trimmingCharacters(in: .whitespaces).hasPrefix(host + ":")
                continue
            }
            guard inHost else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix) else { continue }
            let value = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}

// MARK: - Collector

/// Reads Copilot's monthly quotas: premium requests ("Credits"), and on the free plan chat and completions.
///
/// Windows (monthly, resetting on `quota_reset_date`): `premium`, `chat`, `completions`. Balances: `extra-usage`
/// (premium requests beyond the allowance, when overage is enabled), `credits` (a business seat's own credits used,
/// when it has no per-seat allowance).
public struct CopilotCollector: UsageCollector {
    public static let usageURL = URL(string: "https://api.github.com/copilot_internal/user")!

    public let providerID: UsageProviderID = .copilot
    public let displayName = "Copilot"
    public var setupHint: String { "Sign in to GitHub Copilot in your editor, or run gh auth login" }

    static let renewDetail = "GitHub didn't accept the saved sign-in. Sign in to Copilot in your editor again, "
        + "or run `gh auth login`."

    private let tokens: any CopilotTokenReading
    private let transport: any HTTPTransport

    public init(tokens: any CopilotTokenReading = CopilotTokenStore(),
                transport: any HTTPTransport = URLSessionTransport()) {
        self.tokens = tokens
        self.transport = transport
    }

    public func isAvailable() async -> Bool { await tokens.exists() }

    public func fetch(previous: ProviderUsage?, now: Date) async -> ProviderUsage {
        if Group1Support.isBackingOff(previous, now: now) { return previous! }

        let token: CopilotToken
        switch await tokens.read() {
        case .notFound:
            return failure(.notSignedIn, detail: "No GitHub sign-in for Copilot on this Mac.", previous: previous,
                           now: now)
        case .accessDenied:
            return failure(.accessDenied, detail: "Access to the GitHub CLI's keychain item was refused.",
                           previous: previous, now: now)
        case .found(let found):
            token = found
        }

        let request = Group1Support.request(Self.usageURL, headers: [
            "Authorization": "token \(token.value)",
            "Accept": "application/json",
            "Editor-Version": "vscode/1.96.2",
            "Editor-Plugin-Version": "copilot-chat/0.26.7",
            "User-Agent": "GitHubCopilotChat/0.26.7",
            "X-Github-Api-Version": "2025-04-01",
        ])
        switch await Group1Support.send(request, transport: transport, now: now) {
        case .ok(let data):
            switch CopilotUsageMapper.map(data) {
            case .mapped(let mapped):
                return ProviderUsage(id: providerID, displayName: displayName, plan: mapped.plan,
                                     windows: mapped.windows, balances: mapped.balances, fetchedAt: now)
            case .noQuota(let plan):
                return failure(.notSignedIn, detail: "This GitHub account has no Copilot usage to show.",
                               previous: previous, plan: plan, now: now)
            case .unreadable:
                return failure(.unexpectedResponse("Copilot usage response changed shape"), detail: nil,
                               previous: previous, now: now)
            }
        case .unauthorized:
            return failure(.sessionExpired, detail: Self.renewDetail, previous: previous, now: now)
        case .rateLimited(let until):
            return failure(.rateLimited(retryAfter: until), detail: nil, previous: previous, now: now)
        case .failed(let reason):
            return failure(.unreachable(reason), detail: nil, previous: previous, now: now)
        case .status(404, _):
            return failure(.notSignedIn, detail: "This GitHub account doesn't have Copilot.", previous: previous,
                           now: now)
        case .status(let code, _):
            return failure(.unreachable("HTTP \(code)"), detail: nil, previous: previous, now: now)
        }
    }

    private func failure(_ problem: UsageProblem, detail: String?, previous: ProviderUsage?, plan: String? = nil,
                         now: Date) -> ProviderUsage {
        Group1Support.failure(problem, detail: detail, previous: previous, id: providerID, displayName: displayName,
                              plan: plan, now: now)
    }
}

/// Pure mapping of `GET /copilot_internal/user`.
enum CopilotUsageMapper {
    struct Mapped: Equatable {
        var plan: String?
        var windows: [UsageWindow]
        var balances: [UsageBalance]
    }

    enum Result: Equatable {
        case mapped(Mapped)
        /// Valid response with nothing to meter (no quota buckets and not a token-billed seat).
        case noQuota(plan: String?)
        case unreadable
    }

    static func map(_ data: Data) -> Result {
        guard let body = UsageParsing.object(data) else { return .unreadable }
        let plan = Self.plan(body)
        let resetsAt = resetDate(body["quota_reset_date_utc"]) ?? resetDate(body["quota_reset_date"])
            ?? resetDate(body["limited_user_reset_date"])
        let duration = Group1Support.monthDuration(endingAt: resetsAt)

        var windows: [UsageWindow] = []
        var balances: [UsageBalance] = []
        let snapshots = body["quota_snapshots"] as? [String: Any]
        let premium = snapshots?["premium_interactions"] as? [String: Any]

        if let used = usedFraction(premium) {
            windows.append(UsageWindow(id: "premium", kind: .monthly, label: "Credits", used: used,
                                       resetsAt: resetsAt, duration: duration))
            // Overage only means something next to an included allowance.
            if let premium, premium["overage_permitted"] as? Bool == true {
                balances.append(UsageBalance(id: "extra-usage", label: "Extra usage", remaining: nil,
                                             used: max(0, UsageParsing.number(premium["overage_count"]) ?? 0),
                                             limit: nil, unit: "credits"))
            }
        }
        for (key, label) in [("chat", "Chat"), ("completions", "Completions")] {
            if let used = usedFraction(snapshots?[key] as? [String: Any]) {
                windows.append(UsageWindow(id: key, kind: .monthly, label: label, used: used, resetsAt: resetsAt,
                                           duration: duration))
            }
        }

        // Older free-plan shape: remaining counts against monthly totals.
        if windows.isEmpty {
            let remaining = body["limited_user_quotas"] as? [String: Any]
            let totals = body["monthly_quotas"] as? [String: Any]
            for (key, label) in [("chat", "Chat"), ("completions", "Completions")] {
                guard let total = UsageParsing.number(totals?[key]), total > 0,
                      let left = UsageParsing.number(remaining?[key]) else { continue }
                windows.append(UsageWindow(id: key, kind: .monthly, label: label, used: max(0, total - left) / total,
                                           resetsAt: resetsAt, duration: duration))
            }
        }

        if windows.isEmpty {
            // Token-billed business seats have no per-seat allowance; show the seat's own credits when present.
            guard body["token_based_billing"] as? Bool == true else {
                return snapshots == nil && body["copilot_plan"] == nil ? .unreadable : .noQuota(plan: plan)
            }
            if let used = UsageParsing.number(premium?["credits_used"]), used > 0 {
                balances.append(UsageBalance(id: "credits", label: "Credits", remaining: nil, used: used, limit: nil,
                                             unit: "credits"))
            }
        }
        return .mapped(Mapped(plan: plan, windows: windows, balances: balances))
    }

    /// Copilot Free reports `copilot_plan: "individual"` with `access_type_sku: "free_limited_copilot"`: say "Free".
    static func plan(_ body: [String: Any]) -> String? {
        if UsageParsing.string(body["access_type_sku"])?.lowercased().hasPrefix("free") == true { return "Free" }
        return UsageParsing.string(body["copilot_plan"]).map(UsageParsing.titleCased)
    }

    /// Nil for a missing bucket, an unlimited one (flag or the `-1` sentinel), or a zero-entitlement placeholder.
    private static func usedFraction(_ snapshot: [String: Any]?) -> Double? {
        guard let snapshot else { return nil }
        let entitlement = UsageParsing.number(snapshot["entitlement"])
        let remaining = UsageParsing.number(snapshot["remaining"])
        if snapshot["unlimited"] as? Bool == true || entitlement == -1 || remaining == -1 { return nil }
        if entitlement == 0 { return nil }
        if let percentRemaining = UsageParsing.number(snapshot["percent_remaining"]) {
            return max(0, 100 - percentRemaining) / 100
        }
        if let entitlement, entitlement > 0, let remaining {
            return max(0, entitlement - remaining) / entitlement
        }
        return nil
    }

    /// ISO-8601 (paid) or a bare `yyyy-MM-dd` (free), UTC.
    static func resetDate(_ value: Any?) -> Date? {
        guard let text = UsageParsing.string(value) else { return nil }
        if let date = UsageParsing.isoDate(text) { return date }
        if text.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil {
            return UsageParsing.isoDate(text + "T00:00:00Z")
        }
        return nil
    }
}
