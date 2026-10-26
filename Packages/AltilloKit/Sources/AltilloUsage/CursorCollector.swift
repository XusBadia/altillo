import AltilloCore
import Foundation

// Cursor usage from Cursor's own dashboard API, with Cursor's own sign-in (read-only, never refreshed).
//
// Endpoints, headers, plan/team/enterprise rules and quota percentages adapted from openusage (MIT),
// Sources/OpenUsage/Providers/Cursor/{CursorUsageClient,CursorProvider,CursorUsageMapper,CursorUsageSummaryMapper}.swift
// @87c3d2db465a5eb6c6dd2c2453c55cd82141a76e.

extension UsageProviderID {
    public static let cursor = UsageProviderID(rawValue: "cursor")
}

/// Reads Cursor's reported plan-quota percentages, request allowance and Grok Bot allowance.
/// Monetary balances and spending-derived meters are deliberately excluded.
public struct CursorCollector: UsageCollector {
    static let base = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/")!
    public static let usageURL = base.appendingPathComponent("GetCurrentPeriodUsage")
    public static let planURL = base.appendingPathComponent("GetPlanInfo")
    public static let grokBotURL = base.appendingPathComponent("GetSandUsageStatus")
    public static let restUsageURL = URL(string: "https://cursor.com/api/usage")!
    public static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!

    public let providerID: UsageProviderID = .cursor
    public let displayName = "Cursor"
    public var setupHint: String { "Sign in to Cursor on this Mac" }

    static let renewDetail = "Open Cursor once to renew its sign-in."

    private let credentials: any CursorCredentialReading
    private let transport: any HTTPTransport

    public init(credentials: any CursorCredentialReading = CursorCredentialStore(),
                transport: any HTTPTransport = URLSessionTransport()) {
        self.credentials = credentials
        self.transport = transport
    }

    public func isAvailable() async -> Bool {
        await credentials.exists()
    }

    public func fetch(previous: ProviderUsage?, now: Date) async -> ProviderUsage {
        if Group1Support.isBackingOff(previous, now: now) { return previous! }

        let credential: CursorCredentials
        switch await credentials.read(now: now) {
        case .notFound:
            return failure(.notSignedIn, detail: "Cursor isn't signed in on this Mac.", previous: previous, plan: nil,
                           now: now)
        case .accessDenied:
            return failure(.accessDenied, detail: "Access to Cursor's keychain item was refused.",
                           previous: previous, plan: nil, now: now)
        case .found(let found):
            credential = found
        }

        let storedPlan = credential.membershipType.map(UsageParsing.titleCased)
        if credential.isExpired(now: now) {
            return failure(.sessionExpired, detail: Self.renewDetail, previous: previous, plan: storedPlan, now: now)
        }

        let usage: [String: Any]
        switch await Group1Support.send(connectRequest(Self.usageURL, credential), transport: transport, now: now) {
        case .ok(let data):
            guard let object = UsageParsing.object(data) else {
                return failure(.unexpectedResponse("Cursor usage response changed shape"), detail: nil,
                               previous: previous, plan: storedPlan, now: now)
            }
            usage = object
        case .unauthorized:
            return failure(.sessionExpired, detail: Self.renewDetail, previous: previous, plan: storedPlan, now: now)
        case .rateLimited(let until):
            return failure(.rateLimited(retryAfter: until), detail: nil, previous: previous, plan: storedPlan,
                           now: now)
        case .failed(let reason):
            return failure(.unreachable(reason), detail: nil, previous: previous, plan: storedPlan, now: now)
        case .status(let code, _):
            return failure(.unreachable("HTTP \(code)"), detail: nil, previous: previous, plan: storedPlan, now: now)
        }

        // Optional extras, in parallel; any of them failing just leaves its part out.
        async let planReply = optional(connectRequest(Self.planURL, credential), now: now)
        async let grokReply = optional(connectRequest(Self.grokBotURL, credential), now: now)

        let planInfo = await planReply
        let planName = (planInfo?["planInfo"] as? [String: Any]).flatMap { UsageParsing.string($0["planName"]) }
        var plan = CursorUsageMapper.plan(planName) ?? storedPlan

        if usage["enabled"] as? Bool == false {
            return failure(.notSignedIn, detail: "This Cursor account has no active plan with usage limits.",
                           previous: previous, plan: plan, now: now)
        }

        var mapped = CursorUsageMapper.mapPlanUsage(usage)
        if mapped == nil || CursorUsageMapper.prefersDashboardSummary(usage, planName: planName,
                                                                      planInfoMissing: planInfo == nil) {
            // Team/enterprise and request-based accounts: the dashboard's REST endpoints carry the real numbers.
            async let summaryReply = optional(cookieRequest(Self.usageSummaryURL, credential), now: now)
            async let requestsReply = optional(restUsageRequest(credential), now: now)
            let (summary, requests) = await (summaryReply, requestsReply)
            if let fromDashboard = CursorUsageMapper.mapDashboard(summary: summary, requests: requests) {
                mapped = fromDashboard
                if planName == nil, let membership = CursorUsageMapper.plan(summary?["membershipType"] as? String) {
                    plan = membership
                }
            }
        }
        if let grok = await grokReply, let window = CursorUsageMapper.grokBotWindow(grok) {
            if mapped == nil { mapped = CursorUsageMapper.Mapped(windows: []) }
            mapped?.windows.append(window)
        }
        guard let result = mapped else {
            return failure(.unexpectedResponse("Cursor usage response changed shape"), detail: nil,
                           previous: previous, plan: plan, now: now)
        }

        return ProviderUsage(id: providerID, displayName: displayName, plan: plan,
                             windows: result.windows.sortedForDisplay(), fetchedAt: now)
    }

    // MARK: - Requests

    private func connectRequest(_ url: URL, _ credential: CursorCredentials) -> URLRequest {
        Group1Support.request(url, method: "POST", headers: [
            "Authorization": "Bearer \(credential.accessToken)",
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
        ], body: Data("{}".utf8))
    }

    private func cookieRequest(_ url: URL, _ credential: CursorCredentials) -> URLRequest? {
        guard let cookie = credential.sessionCookie else { return nil }
        return Group1Support.request(url, headers: ["Cookie": cookie, "Accept": "application/json"])
    }

    private func restUsageRequest(_ credential: CursorCredentials) -> URLRequest? {
        guard let cookie = credential.sessionCookie, let subject = credential.subject else { return nil }
        let parts = subject.split(separator: "|", omittingEmptySubsequences: false)
        let userID = String(parts.count > 1 ? parts[1] : parts[0])
        var components = URLComponents(url: Self.restUsageURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "user", value: userID)]
        guard let url = components?.url else { return nil }
        return Group1Support.request(url, headers: ["Cookie": cookie, "Accept": "application/json"])
    }

    /// A JSON object from an optional endpoint, or nil for anything else.
    private func optional(_ request: URLRequest?, now: Date) async -> [String: Any]? {
        guard let request else { return nil }
        return await Group1Support.send(request, transport: transport, now: now).object
    }

    private func failure(_ problem: UsageProblem, detail: String?, previous: ProviderUsage?, plan: String?,
                         now: Date) -> ProviderUsage {
        Group1Support.failure(problem, detail: detail, previous: previous, id: providerID, displayName: displayName,
                              plan: plan, now: now)
    }
}

/// Pure mapping of Cursor's dashboard responses.
enum CursorUsageMapper {
    struct Mapped: Equatable {
        var windows: [UsageWindow]
    }

    static let defaultCycle: TimeInterval = 30 * 86400

    /// "pro plan" → "Pro Plan"; "free_trial" → "Free Trial".
    static func plan(_ raw: String?) -> String? {
        guard let raw = UsageParsing.string(raw) else { return nil }
        return UsageParsing.titleCased(raw)
    }

    // MARK: GetCurrentPeriodUsage

    /// Only percentages reported by the API qualify; currency limits never become quotas.
    static func mapPlanUsage(_ usage: [String: Any]) -> Mapped? {
        guard usage["enabled"] as? Bool != false, let planUsage = usage["planUsage"] as? [String: Any] else {
            return nil
        }
        let (resetsAt, duration) = cycle(start: UsageParsing.date(usage["billingCycleStart"]),
                                         end: UsageParsing.date(usage["billingCycleEnd"]))
        let windows = percentageWindows(planUsage, resetsAt: resetsAt, duration: duration)
        return windows.isEmpty ? nil : Mapped(windows: windows)
    }

    private static func percentageWindows(_ bucket: [String: Any], resetsAt: Date?, duration: TimeInterval)
        -> [UsageWindow] {
        [("totalPercentUsed", "total", "Month"), ("autoPercentUsed", "auto", "Cursor models"),
         ("apiPercentUsed", "api", "Other models")].compactMap { key, id, label in
            guard let percent = UsageParsing.number(bucket[key]), percent >= 0 else { return nil }
            return UsageWindow(id: id, kind: .monthly, label: label,
                               used: Group1Support.fraction(percent: percent), resetsAt: resetsAt, duration: duration)
        }
    }

    /// Team/enterprise accounts whose `planUsage` is missing or has no limit: prefer the dashboard's REST numbers.
    static func prefersDashboardSummary(_ usage: [String: Any], planName: String?, planInfoMissing: Bool) -> Bool {
        let planUsage = usage["planUsage"] as? [String: Any]
        let limitMissing = planUsage.map { UsageParsing.number($0["limit"]) == nil } ?? true
        let percentMissing = planUsage.map { UsageParsing.number($0["totalPercentUsed"]) == nil } ?? true
        let plan = planName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if limitMissing && (plan == "enterprise" || plan == "team") { return true }
        if limitMissing && percentMissing && plan.isEmpty && planInfoMissing { return true }
        return planUsage != nil && limitMissing && isTeamByShape(usage["spendLimitUsage"] as? [String: Any])
    }

    private static func isTeamByShape(_ spendLimit: [String: Any]?) -> Bool {
        (spendLimit?["limitType"] as? String)?.lowercased() == "team"
            || (UsageParsing.number(spendLimit?["pooledLimit"]) ?? 0) > 0
    }

    // MARK: Extras

    /// Grok Bot ("Sand") keeps its own allowance. Pooled enterprise and zero-allowance accounts have none.
    static func grokBotWindow(_ body: [String: Any]) -> UsageWindow? {
        guard body["usesPooledEnterpriseAllowance"] as? Bool != true,
              body["hasNonZeroIncludedLimit"] as? Bool != false,
              body["includedLimitZero"] as? Bool != true,
              let percent = UsageParsing.number(body["usagePercent"]), percent >= 0 else {
            return nil
        }
        let resetsAt = UsageParsing.date(body["nextResetTimestampUtc"])
        let start = UsageParsing.date(body["currentPeriodStart"])
        var duration: TimeInterval = 7 * 86400
        if let start, let resetsAt, resetsAt > start { duration = resetsAt.timeIntervalSince(start) }
        return UsageWindow(id: "grok-bot", kind: .other, label: "Grok Bot", used: percent / 100, resetsAt: resetsAt,
                           duration: duration)
    }

    // MARK: Dashboard REST (team / enterprise / request-based)

    /// `cursor.com/api/usage-summary` + `cursor.com/api/usage`. Nil when neither carries anything usable.
    static func mapDashboard(summary: [String: Any]?, requests: [String: Any]?) -> Mapped? {
        let (resetsAt, duration) = dashboardCycle(summary: summary)
        let individual = summary?["individualUsage"] as? [String: Any]
        let planBucket = individual?["plan"] as? [String: Any]
        var windows: [UsageWindow] = []

        if let gpt4 = requests?["gpt-4"] as? [String: Any],
           let limit = UsageParsing.number(gpt4["maxRequestUsage"]), limit > 0,
           let count = UsageParsing.number(gpt4["numRequests"]) ?? UsageParsing.number(gpt4["numRequestsTotal"]),
           count >= 0 {
            windows.append(UsageWindow(id: "requests", kind: .monthly, label: "Requests", used: count / limit,
                                       resetsAt: resetsAt, duration: duration))
        }
        if let planBucket {
            let percentages = percentageWindows(planBucket, resetsAt: resetsAt, duration: duration)
            let hasRequests = !windows.isEmpty
            windows += percentages.filter { !hasRequests || $0.id != "total" }
        }
        guard !windows.isEmpty else { return nil }
        return Mapped(windows: windows)
    }

    private static func dashboardCycle(summary: [String: Any]?)
        -> (resetsAt: Date?, duration: TimeInterval) {
        let start = UsageParsing.date(summary?["billingCycleStart"])
        let end = UsageParsing.date(summary?["billingCycleEnd"])
        if let start, let end, end > start { return (end, end.timeIntervalSince(start)) }
        return (end, defaultCycle)
    }

    /// Billing cycle bounds arrive as epoch milliseconds (numbers or strings).
    static func cycle(start: Date?, end: Date?) -> (resetsAt: Date?, duration: TimeInterval) {
        guard let end else { return (nil, defaultCycle) }
        if let start, end > start { return (end, end.timeIntervalSince(start)) }
        return (end, defaultCycle)
    }
}
