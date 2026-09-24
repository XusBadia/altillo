import AltilloCore
import Foundation

// Codex usage: `codex app-server` first (the CLI's own client, which keeps its tokens fresh), then ChatGPT's
// `wham/usage` endpoint with the CLI's stored token as a read-only fallback.
//
// Window classification by duration, plan naming and the wham mapping are adapted from openusage's
// CodexUsageMapper (https://github.com/robinebers/openusage, MIT); the app-server result mapping from ai-limits'
// CodexRateLimitMapper (https://github.com/XusBadia/ai-limits, MIT). See ThirdPartyNotices/README.md.

/// The token pair `wham/usage` needs, read from Codex's `auth.json`. Never written back.
public struct CodexAuth: Sendable, Hashable {
    public var accessToken: String
    public var accountID: String?

    public init(accessToken: String, accountID: String?) {
        self.accessToken = accessToken
        self.accountID = accountID
    }

    /// `{"tokens":{"access_token","account_id",…}}`. API-key-only logins have no tokens and can't read usage.
    public static func parse(_ data: Data) -> CodexAuth? {
        guard let root = UsageParsing.object(data), let tokens = root["tokens"] as? [String: Any],
              let token = UsageParsing.string(tokens["access_token"]) else { return nil }
        return CodexAuth(accessToken: token, accountID: UsageParsing.string(tokens["account_id"]))
    }

    /// `$CODEX_HOME/auth.json`, else `~/.codex/auth.json`.
    public static func defaultFile(environment: [String: String] = ProcessInfo.processInfo.environment,
                                   home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let codexHome = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespaces), !codexHome.isEmpty {
            return URL(fileURLWithPath: (codexHome as NSString).expandingTildeInPath)
                .appendingPathComponent("auth.json")
        }
        return home.appendingPathComponent(".codex/auth.json")
    }
}

/// Reads Codex's session and weekly limits (plus per-model limits and credits).
public struct CodexCollector: UsageCollector {
    public static let whamURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    public let providerID: UsageProviderID = .codex
    public let displayName = "Codex"

    private let appServer: (any CodexRateLimitReading)?
    private let transport: any HTTPTransport
    private let readAuth: @Sendable () -> CodexAuth?
    private let authFileExists: @Sendable () -> Bool
    private let binaryExists: @Sendable () -> Bool

    /// - Parameters:
    ///   - appServer: how to talk to `codex app-server`; nil to use only the HTTP fallback.
    ///   - readAuth: reads `auth.json` for the fallback.
    public init(appServer: (any CodexRateLimitReading)? = LocatingCodexAppServer(),
                transport: any HTTPTransport = URLSessionTransport(),
                readAuth: @escaping @Sendable () -> CodexAuth? = {
                    (try? Data(contentsOf: CodexAuth.defaultFile())).flatMap(CodexAuth.parse)
                },
                authFileExists: @escaping @Sendable () -> Bool = {
                    FileManager.default.fileExists(atPath: CodexAuth.defaultFile().path)
                },
                binaryExists: @escaping @Sendable () -> Bool = { CodexAppServerClient.locate() != nil }) {
        self.appServer = appServer
        self.transport = transport
        self.readAuth = readAuth
        self.authFileExists = authFileExists
        self.binaryExists = binaryExists
    }

    public func isAvailable() async -> Bool {
        (appServer != nil && binaryExists()) || authFileExists()
    }

    public func fetch(previous: ProviderUsage?, now: Date) async -> ProviderUsage {
        if let previous, case .rateLimited(let until?) = previous.problem, now < until {
            return previous
        }

        var appServerFailure: String?
        if let appServer {
            do {
                let data = try await appServer.readRateLimits()
                if let mapped = CodexUsageMapper.mapAppServer(data) {
                    return ProviderUsage(id: providerID, displayName: displayName, plan: mapped.plan,
                                         windows: mapped.windows, balances: mapped.balances, fetchedAt: now)
                }
                appServerFailure = "codex app-server returned an unexpected result"
            } catch is CancellationError {
                return failure(.unreachable("Cancelled"), detail: nil, previous: previous, now: now)
            } catch CodexAppServerError.notInstalled {
                appServerFailure = nil
            } catch {
                appServerFailure = String(describing: error)
            }
        }

        // Fallback: the HTTP endpoint with the CLI's token (read-only; the CLI rotates it, never Altillo).
        guard let auth = readAuth() else {
            if let appServerFailure {
                return failure(.unreachable(appServerFailure), detail: nil, previous: previous, now: now)
            }
            return failure(.notSignedIn, detail: "Codex isn't signed in with ChatGPT on this Mac.",
                           previous: previous, now: now)
        }

        var request = URLRequest(url: Self.whamURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = auth.accountID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Altillo", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            return failure(.unreachable(ClaudeCollector.describe(error)), detail: nil, previous: previous, now: now)
        }
        switch response.statusCode {
        case 200..<300:
            break
        case 401, 403:
            return failure(.sessionExpired, detail: "Run `codex` once to renew its sign-in.", previous: previous,
                           now: now)
        case 429:
            let retry = UsageParsing.retryAfter(response.header("Retry-After"), now: now)
                ?? now.addingTimeInterval(5 * 60)
            return failure(.rateLimited(retryAfter: retry), detail: nil, previous: previous, now: now)
        default:
            return failure(.unreachable("HTTP \(response.statusCode)"), detail: nil, previous: previous, now: now)
        }
        guard let mapped = CodexUsageMapper.mapWham(data, now: now) else {
            return failure(.unexpectedResponse("Codex usage response changed shape"), detail: nil,
                           previous: previous, now: now)
        }
        return ProviderUsage(id: providerID, displayName: displayName, plan: mapped.plan, windows: mapped.windows,
                             balances: mapped.balances, fetchedAt: now)
    }

    private func failure(_ problem: UsageProblem, detail: String?, previous: ProviderUsage?, now: Date)
        -> ProviderUsage {
        var usage = previous ?? ProviderUsage(id: providerID, displayName: displayName, plan: nil, windows: [],
                                              fetchedAt: now)
        usage.problem = problem
        usage.problemDetail = detail
        return usage
    }
}

/// Pure mapping of the app-server result and the wham response.
enum CodexUsageMapper {
    static let sessionMaxMinutes = 360.0
    static let weeklyMinMinutes = 6.0 * 24 * 60
    static let defaultLimitID = "codex"

    struct Mapped: Equatable {
        var plan: String?
        var windows: [UsageWindow]
        var balances: [UsageBalance]
    }

    enum Slot { case primary, secondary }

    /// ≤ 6 h is the session, ≥ 6 days the week; unknown durations fall back to the slot (primary = session).
    static func classify(minutes: Double?, slot: Slot) -> UsageWindow.Kind {
        if let minutes {
            if minutes <= sessionMaxMinutes { return .session }
            if minutes >= 27 * 24 * 60 { return .monthly }
            if minutes >= weeklyMinMinutes { return .weekly }
            return .other
        }
        return slot == .primary ? .session : .weekly
    }

    // MARK: app-server

    static func mapAppServer(_ data: Data) -> Mapped? {
        guard let body = UsageParsing.object(data) else { return nil }
        var snapshots: [(String, [String: Any])] = []
        if let byID = body["rateLimitsByLimitId"] as? [String: Any], !byID.isEmpty {
            snapshots = byID.compactMap { key, value in (value as? [String: Any]).map { (key, $0) } }
        } else if let single = body["rateLimits"] as? [String: Any] {
            snapshots = [(UsageParsing.string(single["limitId"]) ?? defaultLimitID, single)]
        }
        snapshots.sort { lhs, rhs in
            if lhs.0 == defaultLimitID { return rhs.0 != defaultLimitID }
            if rhs.0 == defaultLimitID { return false }
            return lhs.0 < rhs.0
        }

        var windows: [UsageWindow] = []
        var balances: [UsageBalance] = []
        var plan = (body["rateLimits"] as? [String: Any]).flatMap { planName($0["planType"]) }
        for (limitID, snapshot) in snapshots {
            plan = plan ?? planName(snapshot["planType"])
            let name = UsageParsing.string(snapshot["limitName"]) ?? limitID
            for (key, slot) in [("primary", Slot.primary), ("secondary", Slot.secondary)] {
                guard let raw = snapshot[key] as? [String: Any],
                      let percent = UsageParsing.number(raw["usedPercent"]) else { continue }
                let minutes = UsageParsing.number(raw["windowDurationMins"])
                windows.append(window(limitID: limitID, name: name, kind: classify(minutes: minutes, slot: slot),
                                      percent: percent, resetsAt: UsageParsing.date(raw["resetsAt"]),
                                      duration: minutes.map { $0 * 60 }))
            }
            if limitID == defaultLimitID, let credits = snapshot["credits"] as? [String: Any],
               let balance = creditsBalance(balance: credits["balance"], hasCredits: credits["hasCredits"],
                                            unlimited: credits["unlimited"]) {
                balances.append(balance)
            }
        }
        if let resets = body["rateLimitResetCredits"] as? [String: Any],
           let count = UsageParsing.number(resets["availableCount"]), count > 0 {
            balances.append(resetsBalance(count))
        }
        guard !windows.isEmpty || !balances.isEmpty else { return nil }
        return Mapped(plan: plan, windows: dedupe(windows).sortedForDisplay(), balances: balances)
    }

    // MARK: wham

    static func mapWham(_ data: Data, now: Date) -> Mapped? {
        guard let body = UsageParsing.object(data) else { return nil }
        var windows = whamWindows(body["rate_limit"], limitID: defaultLimitID, name: "Codex", now: now)
        for entry in (body["additional_rate_limits"] as? [Any]) ?? [] {
            guard let object = entry as? [String: Any] else { continue }
            let name = UsageParsing.string(object["limit_name"]) ?? UsageParsing.string(object["metered_feature"])
                ?? "Model"
            let id = UsageParsing.string(object["metered_feature"]) ?? UsageParsing.slug(name)
            windows += whamWindows(object["rate_limit"], limitID: id, name: name, now: now)
        }
        var balances: [UsageBalance] = []
        if let credits = body["credits"] as? [String: Any],
           let balance = creditsBalance(balance: credits["balance"], hasCredits: credits["has_credits"],
                                        unlimited: credits["unlimited"]) {
            balances.append(balance)
        }
        if let resets = body["rate_limit_reset_credits"] as? [String: Any],
           let count = UsageParsing.number(resets["available_count"]), count > 0 {
            balances.append(resetsBalance(count))
        }
        guard !windows.isEmpty || !balances.isEmpty else { return nil }
        return Mapped(plan: planName(body["plan_type"]), windows: dedupe(windows).sortedForDisplay(),
                      balances: balances)
    }

    private static func whamWindows(_ value: Any?, limitID: String, name: String, now: Date) -> [UsageWindow] {
        guard let rateLimit = value as? [String: Any] else { return [] }
        var windows: [UsageWindow] = []
        for (key, slot) in [("primary_window", Slot.primary), ("secondary_window", Slot.secondary)] {
            guard let raw = rateLimit[key] as? [String: Any],
                  let percent = UsageParsing.number(raw["used_percent"]) else { continue }
            let seconds = UsageParsing.number(raw["limit_window_seconds"])
            var resetsAt = UsageParsing.date(raw["reset_at"])
            if resetsAt == nil, let after = UsageParsing.number(raw["reset_after_seconds"]) {
                resetsAt = now.addingTimeInterval(after)
            }
            windows.append(window(limitID: limitID, name: name, kind: classify(minutes: seconds.map { $0 / 60 },
                                                                                 slot: slot),
                                  percent: percent, resetsAt: resetsAt, duration: seconds))
        }
        return windows
    }

    // MARK: shared

    private static func window(limitID: String, name: String, kind: UsageWindow.Kind, percent: Double,
                               resetsAt: Date?, duration: TimeInterval?) -> UsageWindow {
        let used = percent / 100
        if limitID == defaultLimitID {
            switch kind {
            case .session:
                return UsageWindow(id: "session", kind: .session, label: "Session", used: used, resetsAt: resetsAt,
                                   duration: duration)
            case .weekly:
                return UsageWindow(id: "weekly", kind: .weekly, label: "Week", used: used, resetsAt: resetsAt,
                                   duration: duration)
            case .monthly:
                return UsageWindow(id: "monthly", kind: .monthly, label: "Month", used: used, resetsAt: resetsAt,
                                   duration: duration)
            case .modelWeekly, .other:
                return UsageWindow(id: "other", kind: .other, label: "Limit", used: used, resetsAt: resetsAt,
                                   duration: duration)
            }
        }
        let slug = UsageParsing.slug(limitID)
        switch kind {
        case .weekly, .modelWeekly:
            return UsageWindow(id: "weekly-\(slug)", kind: .modelWeekly, label: "\(name) week", used: used,
                               resetsAt: resetsAt, duration: duration)
        case .session:
            return UsageWindow(id: "session-\(slug)", kind: .other, label: "\(name) session", used: used,
                               resetsAt: resetsAt, duration: duration)
        case .monthly, .other:
            return UsageWindow(id: "\(slug)-limit", kind: .other, label: name, used: used, resetsAt: resetsAt,
                               duration: duration)
        }
    }

    /// Keeps the first window per id (the primary slot wins if both classify the same).
    private static func dedupe(_ windows: [UsageWindow]) -> [UsageWindow] {
        var seen = Set<String>()
        return windows.filter { seen.insert($0.id).inserted }
    }

    private static func creditsBalance(balance: Any?, hasCredits: Any?, unlimited: Any?) -> UsageBalance? {
        if unlimited as? Bool == true { return nil }
        let value = UsageParsing.number(balance) ?? 0
        guard hasCredits as? Bool == true || value > 0 else { return nil }
        return UsageBalance(id: "credits", label: "Credits", remaining: max(0, value), used: nil, limit: nil,
                            unit: "credits")
    }

    private static func resetsBalance(_ count: Double) -> UsageBalance {
        UsageBalance(id: "limit-resets", label: "Limit resets", remaining: count.rounded(.down), used: nil,
                     limit: nil, unit: "resets")
    }

    /// "prolite" → "Pro 5x", "pro" → "Pro 20x" (the multipliers ChatGPT shows, consistent with Claude's
    /// "Max 5x"/"Max 20x"), anything else title-cased ("plus" → "Plus", "team" → "Team").
    static func planName(_ value: Any?) -> String? {
        guard let raw = UsageParsing.string(value) else { return nil }
        switch raw.lowercased() {
        case "prolite": return "Pro 5x"
        case "pro": return "Pro 20x"
        default: return UsageParsing.titleCased(raw)
        }
    }
}
