import AltilloCore
import Foundation

// Grok usage from xAI's CLI proxy, with the Grok CLI's own sign-in (read-only).
//
// Adapted from openusage (MIT), Sources/OpenUsage/Providers/Grok/{GrokUsageClient,GrokCreditsConfigDecoder,
// GrokUsageMapper,GrokAuthStore}.swift@87c3d2db465a5eb6c6dd2c2453c55cd82141a76e: the endpoints and headers, the
// credits-config shape (proto-JSON drops zero-valued fields) and the plan field. Unlike openusage, Altillo never
// refreshes the token through auth.x.ai and never rewrites `~/.grok/auth.json`: the CLI rotates its own tokens.
// See ThirdPartyNotices/README.md.

extension UsageProviderID {
    public static let grok = UsageProviderID(rawValue: "grok")
}

/// One signed-in account from the Grok CLI's `auth.json`. The refresh token is deliberately never kept.
public struct GrokCredential: Sendable, Hashable {
    public var accessToken: String
    public var expiresAt: Date?

    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    /// Expired or about to (Altillo won't refresh it, so a nearly dead token is as good as dead).
    public func isExpired(now: Date, margin: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now.addingTimeInterval(margin)
    }

    /// `{"<issuer>::<client>": {"key": "<jwt>", "expires_at": "…", …}, …}`. Entries without a key are skipped; the
    /// expiry is the JWT's `exp`, else `expires_at`/`expires`. Nil when the file isn't a JSON object.
    public static func parse(_ data: Data) -> [GrokCredential]? {
        guard let root = UsageParsing.object(data) else { return nil }
        return root.keys.sorted().compactMap { key in
            guard let entry = root[key] as? [String: Any], let token = UsageParsing.string(entry["key"]) else {
                return nil
            }
            let expiry = TokenParsing.jwtExpiry(token)
                ?? UsageParsing.date(entry["expires_at"]) ?? UsageParsing.date(entry["expires"])
            return GrokCredential(accessToken: token, expiresAt: expiry)
        }
    }

    /// The one to use: a live token (the longest-lived), else nil.
    static func usable(_ credentials: [GrokCredential], now: Date) -> GrokCredential? {
        credentials.filter { !$0.isExpired(now: now) }
            .max { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }

    /// `$GROK_HOME/auth.json`, else `~/.grok/auth.json`.
    public static func defaultFile(environment: [String: String] = ProcessInfo.processInfo.environment,
                                   home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let directory = ProviderPaths.directory("GROK_HOME", in: environment) ?? home.appendingPathComponent(".grok")
        return directory.appendingPathComponent("auth.json")
    }
}

/// Reads Grok's shared usage pool (weekly for current plans) and pay-as-you-go balance.
public struct GrokCollector: UsageCollector {
    public static let creditsURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    public static let settingsURL = URL(string: "https://cli-chat-proxy.grok.com/v1/settings")!

    public let providerID: UsageProviderID = .grok
    public let displayName = "Grok"
    public var setupHint: String { "Sign in to the Grok CLI on this Mac (run `grok login`)" }

    private let transport: any HTTPTransport
    private let authFile: URL
    private let readFile: @Sendable (URL) -> Data?

    public init(transport: any HTTPTransport = URLSessionTransport(),
                authFile: URL = GrokCredential.defaultFile(),
                readFile: @escaping @Sendable (URL) -> Data? = { try? Data(contentsOf: $0) }) {
        self.transport = transport
        self.authFile = authFile
        self.readFile = readFile
    }

    public func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: authFile.path)
    }

    public func fetch(previous: ProviderUsage?, now: Date) async -> ProviderUsage {
        if CollectorOutcome.isBackingOff(previous, now: now) { return previous! }

        guard let data = readFile(authFile) else {
            return failure(.notSignedIn, detail: "The Grok CLI isn't signed in on this Mac.", previous: previous,
                           now: now)
        }
        guard let credentials = GrokCredential.parse(data), !credentials.isEmpty else {
            return failure(.notSignedIn, detail: "The Grok CLI's sign-in couldn't be read. Run `grok login` again.",
                           previous: previous, now: now)
        }
        guard let credential = GrokCredential.usable(credentials, now: now) else {
            return failure(.sessionExpired, detail: "Open Grok once to renew its sign-in.", previous: previous,
                           now: now)
        }

        // The plan comes from a separate call; run it alongside and never let it fail the read.
        async let settings = HTTPReply.send(request(Self.settingsURL, token: credential.accessToken),
                                            with: transport, now: now)
        let billing = await HTTPReply.send(request(Self.creditsURL, token: credential.accessToken),
                                           with: transport, now: now)
        let plan: String?
        if case .success(let body) = await settings {
            plan = GrokUsageMapper.plan(body) ?? previous?.plan
        } else {
            plan = previous?.plan
        }

        switch billing {
        case .success(let body):
            guard let mapped = GrokUsageMapper.map(body) else {
                return failure(.unexpectedResponse("Grok billing response changed shape"), detail: nil,
                               previous: previous, plan: plan, now: now)
            }
            return ProviderUsage(id: providerID, displayName: displayName, plan: plan, windows: mapped.windows,
                                 balances: mapped.balances, fetchedAt: now)
        case .unauthorized:
            return failure(.sessionExpired, detail: "Open Grok once to renew its sign-in.", previous: previous,
                           plan: plan, now: now)
        case .rateLimited(let retry):
            return failure(.rateLimited(retryAfter: retry), detail: nil, previous: previous, plan: plan, now: now)
        case .failed(let reason):
            return failure(.unreachable(reason), detail: nil, previous: previous, plan: plan, now: now)
        }
    }

    private func request(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Altillo", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func failure(_ problem: UsageProblem, detail: String?, previous: ProviderUsage?, plan: String? = nil,
                         now: Date) -> ProviderUsage {
        CollectorOutcome.failure(problem, detail: detail, id: providerID, displayName: displayName,
                                 previous: previous, plan: plan, now: now)
    }
}

/// Pure mapping of `GET /v1/billing?format=credits` and `/v1/settings`.
enum GrokUsageMapper {
    struct Mapped: Equatable {
        var windows: [UsageWindow]
        var balances: [UsageBalance]
    }

    /// `{"config":{"creditUsagePercent":99,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start","end"},
    /// "onDemandCap":{"val":…},"onDemandUsed":{"val":…},"prepaidBalance":{"val":…}}}`. Proto-JSON omits zero
    /// values, so an absent percent or cap is 0; a present but non-numeric one is a shape change (nil).
    static func map(_ data: Data) -> Mapped? {
        guard let body = UsageParsing.object(data), let config = body["config"] as? [String: Any],
              let period = config["currentPeriod"] as? [String: Any],
              let type = UsageParsing.string(period["type"]),
              let start = UsageParsing.date(period["start"]), let end = UsageParsing.date(period["end"]), end > start
        else { return nil }

        let percent: Double
        if let raw = config["creditUsagePercent"] {
            guard let number = UsageParsing.number(raw) else { return nil }
            percent = number
        } else {
            percent = 0
        }

        let (id, kind, label) = periodDescription(type)
        let window = UsageWindow(id: id, kind: kind, label: label, used: max(0, percent) / 100, resetsAt: end,
                                 duration: end.timeIntervalSince(start))

        var balances: [UsageBalance] = []
        guard let cap = credits(config["onDemandCap"]), let spent = credits(config["onDemandUsed"]),
              let prepaid = credits(config["prepaidBalance"]) else { return nil }
        if cap > 0 {
            balances.append(UsageBalance(id: "pay-as-you-go", label: "Pay as you go",
                                         remaining: max(0, cap - spent), used: spent, limit: cap, unit: "credits"))
        }
        if prepaid > 0 {
            balances.append(UsageBalance(id: "prepaid", label: "Prepaid", remaining: prepaid, used: nil, limit: nil,
                                         unit: "credits"))
        }
        return Mapped(windows: [window], balances: balances)
    }

    /// `{"val": n}`, absent → 0, anything else → nil.
    private static func credits(_ value: Any?) -> Double? {
        guard let value else { return 0 }
        guard let object = value as? [String: Any] else { return nil }
        guard let raw = object["val"] else { return 0 }
        return UsageParsing.number(raw)
    }

    private static func periodDescription(_ type: String) -> (String, UsageWindow.Kind, String) {
        switch type {
        case "USAGE_PERIOD_TYPE_WEEKLY": ("weekly", .weekly, "Week")
        case "USAGE_PERIOD_TYPE_MONTHLY": ("monthly", .monthly, "Month")
        case "USAGE_PERIOD_TYPE_DAILY": ("daily", .other, "Day")
        default: ("period", .other, "Period")
        }
    }

    /// `subscription_tier_display` ("SuperGrok").
    static func plan(_ data: Data) -> String? {
        UsageParsing.object(data).flatMap { UsageParsing.string($0["subscription_tier_display"]) }
    }
}
