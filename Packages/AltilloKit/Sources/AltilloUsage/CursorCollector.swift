import AltilloCore
import Foundation

// Cursor usage from Cursor's own dashboard API, with Cursor's own sign-in (read-only, never refreshed).
//
// Endpoints, headers, plan/team/enterprise rules, on-demand and credit maths adapted from openusage (MIT),
// Sources/OpenUsage/Providers/Cursor/{CursorUsageClient,CursorProvider,CursorUsageMapper,CursorUsageSummaryMapper}.swift
// @87c3d2db465a5eb6c6dd2c2453c55cd82141a76e.

extension UsageProviderID {
    public static let cursor = UsageProviderID(rawValue: "cursor")
}

/// Reads Cursor's monthly plan usage (total, Cursor models, other models), request allowance on request-based
/// plans, the Grok Bot allowance, on-demand spend and prepaid credits.
///
/// Windows: `total` (monthly, "Month"), `auto` ("Cursor models"), `api` ("Other models"), `requests` (monthly,
/// request-based plans), `grok-bot` (other). Balances: `on-demand` (USD spent against the on-demand limit),
/// `credits` (USD of credit grants + prepaid balance left).
public struct CursorCollector: UsageCollector {
    static let base = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/")!
    public static let usageURL = base.appendingPathComponent("GetCurrentPeriodUsage")
    public static let planURL = base.appendingPathComponent("GetPlanInfo")
    public static let creditsURL = base.appendingPathComponent("GetCreditGrantsBalance")
    public static let grokBotURL = base.appendingPathComponent("GetSandUsageStatus")
    public static let restUsageURL = URL(string: "https://cursor.com/api/usage")!
    public static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    public static let stripeURL = URL(string: "https://cursor.com/api/auth/stripe")!

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
        async let grantsReply = optional(connectRequest(Self.creditsURL, credential), now: now)
        async let grokReply = optional(connectRequest(Self.grokBotURL, credential), now: now)
        async let stripeReply = optional(cookieRequest(Self.stripeURL, credential), now: now)

        let planInfo = await planReply
        let planName = (planInfo?["planInfo"] as? [String: Any]).flatMap { UsageParsing.string($0["planName"]) }
        var plan = CursorUsageMapper.plan(planName) ?? storedPlan

        if usage["enabled"] as? Bool == false {
            return failure(.notSignedIn, detail: "This Cursor account has no active plan with usage limits.",
                           previous: previous, plan: plan, now: now)
        }

        var mapped = CursorUsageMapper.mapPlanUsage(usage, planName: planName)
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
        guard var result = mapped else {
            return failure(.unexpectedResponse("Cursor usage response changed shape"), detail: nil,
                           previous: previous, plan: plan, now: now)
        }

        if let grok = await grokReply, let window = CursorUsageMapper.grokBotWindow(grok) {
            result.windows.append(window)
        }
        if let credits = CursorUsageMapper.credits(grants: await grantsReply, stripe: await stripeReply) {
            result.balances.append(credits)
        }
        return ProviderUsage(id: providerID, displayName: displayName, plan: plan,
                             windows: result.windows.sortedForDisplay(), balances: result.balances, fetchedAt: now)
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
        var balances: [UsageBalance]
    }

    static let defaultCycle: TimeInterval = 30 * 86400

    /// "pro plan" → "Pro Plan"; "free_trial" → "Free Trial".
    static func plan(_ raw: String?) -> String? {
        guard let raw = UsageParsing.string(raw) else { return nil }
        return UsageParsing.titleCased(raw)
    }

    // MARK: GetCurrentPeriodUsage

    /// Nil when the response has no usable plan meter (no `planUsage`, or neither a limit nor a percentage).
    static func mapPlanUsage(_ usage: [String: Any], planName: String?) -> Mapped? {
        guard usage["enabled"] as? Bool != false, let planUsage = usage["planUsage"] as? [String: Any] else {
            return nil
        }
        let limit = UsageParsing.number(planUsage["limit"])
        let totalPercent = UsageParsing.number(planUsage["totalPercentUsed"])
        guard limit != nil || totalPercent != nil else { return nil }

        let (resetsAt, duration) = cycle(start: UsageParsing.date(usage["billingCycleStart"]),
                                         end: UsageParsing.date(usage["billingCycleEnd"]))
        let spendLimit = usage["spendLimitUsage"] as? [String: Any]
        let normalizedPlan = planName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let isTeam = normalizedPlan == "team" || isTeamByShape(spendLimit)

        let usedCents = UsageParsing.number(planUsage["totalSpend"])
            ?? ((limit ?? 0) - (UsageParsing.number(planUsage["remaining"]) ?? 0))
        let used: Double
        if isTeam {
            guard let limit, limit > 0 else { return nil }
            used = max(0, usedCents) / limit
        } else if let totalPercent {
            used = Group1Support.fraction(percent: totalPercent)
        } else if let limit, limit > 0 {
            used = max(0, usedCents) / limit
        } else {
            used = 0
        }

        var windows = [UsageWindow(id: "total", kind: .monthly, label: "Month", used: used, resetsAt: resetsAt,
                                   duration: duration)]
        for (key, id, label) in [("autoPercentUsed", "auto", "Cursor models"), ("apiPercentUsed", "api", "Other models")] {
            if let percent = UsageParsing.number(planUsage[key]) {
                windows.append(UsageWindow(id: id, kind: .monthly, label: label,
                                           used: Group1Support.fraction(percent: percent), resetsAt: resetsAt,
                                           duration: duration))
            }
        }

        var balances: [UsageBalance] = []
        if let spendLimit, let onDemand = onDemandBalance(spendLimit) { balances.append(onDemand) }
        return Mapped(windows: windows, balances: balances)
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

    /// On-demand spend (cents in the API) as a USD balance.
    static func onDemandBalance(_ spendLimit: [String: Any]) -> UsageBalance? {
        let limitCents = UsageParsing.number(spendLimit["individualLimit"])
            ?? UsageParsing.number(spendLimit["pooledLimit"]) ?? 0
        let remainingCents = UsageParsing.number(spendLimit["individualRemaining"])
            ?? UsageParsing.number(spendLimit["pooledRemaining"]) ?? 0
        let reported = ["individualUsed", "pooledUsed", "totalSpend"].compactMap { UsageParsing.number(spendLimit[$0]) }
        let spentCents: Double
        if let positive = reported.first(where: { $0 > 0 }) {
            spentCents = positive
        } else {
            let inferred = max(0, limitCents - remainingCents)
            spentCents = inferred > 0 ? inferred : max(0, reported.first ?? 0)
        }
        if limitCents > 0 {
            return UsageBalance(id: "on-demand", label: "On-demand", remaining: max(0, limitCents - spentCents) / 100,
                                used: spentCents / 100, limit: limitCents / 100, unit: "USD")
        }
        guard spentCents > 0 else { return nil }
        return UsageBalance(id: "on-demand", label: "On-demand", remaining: nil, used: spentCents / 100, limit: nil,
                            unit: "USD")
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

    /// Credit grants plus a prepaid Stripe balance (negative `customerBalance`), in USD left.
    static func credits(grants: [String: Any]?, stripe: [String: Any]?) -> UsageBalance? {
        var totalCents = 0.0
        var usedCents = 0.0
        if grants?["hasCreditGrants"] as? Bool == true, let total = UsageParsing.number(grants?["totalCents"]),
           total > 0 {
            totalCents += total
            usedCents += max(0, UsageParsing.number(grants?["usedCents"]) ?? 0)
        }
        if let balance = UsageParsing.number(stripe?["customerBalance"]), balance < 0 {
            totalCents += abs(balance)
        }
        guard totalCents > 0 else { return nil }
        return UsageBalance(id: "credits", label: "Credits", remaining: max(0, totalCents - usedCents) / 100,
                            used: usedCents / 100, limit: totalCents / 100, unit: "USD")
    }

    // MARK: Dashboard REST (team / enterprise / request-based)

    /// `cursor.com/api/usage-summary` + `cursor.com/api/usage`. Nil when neither carries anything usable.
    static func mapDashboard(summary: [String: Any]?, requests: [String: Any]?) -> Mapped? {
        let (resetsAt, duration) = dashboardCycle(summary: summary, requests: requests)
        let individual = summary?["individualUsage"] as? [String: Any]
        let team = summary?["teamUsage"] as? [String: Any]
        let planBucket = individual?["plan"] as? [String: Any]
        var windows: [UsageWindow] = []

        // The request allowance, when the plan has one, is the dashboard's included cap.
        if let gpt4 = requests?["gpt-4"] as? [String: Any], let max = UsageParsing.number(gpt4["maxRequestUsage"]),
           max > 0 {
            let count = UsageParsing.number(gpt4["numRequests"]) ?? UsageParsing.number(gpt4["numRequestsTotal"]) ?? 0
            windows.append(UsageWindow(id: "requests", kind: .monthly, label: "Requests", used: Swift.max(0, count) / max,
                                       resetsAt: resetsAt, duration: duration))
        } else {
            let limitType = (summary?["limitType"] as? String)?.lowercased()
            var total: Double?
            if limitType == "team", let pooled = dollarMeter(team?["pooled"]) {
                total = pooled.used / pooled.limit
            } else if let percent = UsageParsing.number(planBucket?["totalPercentUsed"]) {
                total = Group1Support.fraction(percent: percent)
            } else if let overall = dollarMeter(individual?["overall"]) {
                total = overall.used / overall.limit
            } else if let pooled = dollarMeter(team?["pooled"]) {
                total = pooled.used / pooled.limit
            }
            if let total {
                windows.append(UsageWindow(id: "total", kind: .monthly, label: "Month", used: total,
                                           resetsAt: resetsAt, duration: duration))
            }
        }
        for (key, id, label) in [("autoPercentUsed", "auto", "Cursor models"), ("apiPercentUsed", "api", "Other models")] {
            if let percent = UsageParsing.number(planBucket?[key]) {
                windows.append(UsageWindow(id: id, kind: .monthly, label: label,
                                           used: Group1Support.fraction(percent: percent), resetsAt: resetsAt,
                                           duration: duration))
            }
        }

        var balances: [UsageBalance] = []
        if let onDemand = onDemandBucket(individual?["onDemand"]) ?? onDemandBucket(team?["onDemand"]) {
            balances.append(onDemand)
        }
        guard !windows.isEmpty || !balances.isEmpty else { return nil }
        return Mapped(windows: windows, balances: balances)
    }

    private static func onDemandBucket(_ value: Any?) -> UsageBalance? {
        guard let bucket = value as? [String: Any], bucket["enabled"] as? Bool != false else { return nil }
        if let meter = dollarMeter(bucket) {
            return UsageBalance(id: "on-demand", label: "On-demand", remaining: max(0, meter.limit - meter.used) / 100,
                                used: meter.used / 100, limit: meter.limit / 100, unit: "USD")
        }
        if let used = UsageParsing.number(bucket["used"]), used > 0 {
            return UsageBalance(id: "on-demand", label: "On-demand", remaining: nil, used: used / 100, limit: nil,
                                unit: "USD")
        }
        return nil
    }

    /// Cents used/limit of an enabled bucket with a positive limit.
    private static func dollarMeter(_ value: Any?) -> (used: Double, limit: Double)? {
        guard let bucket = value as? [String: Any], bucket["enabled"] as? Bool != false,
              let limit = UsageParsing.number(bucket["limit"]), limit > 0 else { return nil }
        let reported = UsageParsing.number(bucket["used"])
        let inferred = max(0, limit - (UsageParsing.number(bucket["remaining"]) ?? limit))
        let used = reported.flatMap { $0 > 0 ? $0 : nil } ?? inferred
        return (max(0, used), limit)
    }

    private static func dashboardCycle(summary: [String: Any]?, requests: [String: Any]?)
        -> (resetsAt: Date?, duration: TimeInterval) {
        let start = UsageParsing.date(summary?["billingCycleStart"])
        let end = UsageParsing.date(summary?["billingCycleEnd"])
        if let start, let end, end > start { return (end, end.timeIntervalSince(start)) }
        let monthStart = UsageParsing.date(requests?["startOfMonth"])
        return (monthStart?.addingTimeInterval(defaultCycle), defaultCycle)
    }

    /// Billing cycle bounds arrive as epoch milliseconds (numbers or strings).
    static func cycle(start: Date?, end: Date?) -> (resetsAt: Date?, duration: TimeInterval) {
        guard let end else { return (nil, defaultCycle) }
        if let start, end > start { return (end, end.timeIntervalSince(start)) }
        return (end, defaultCycle)
    }
}
