import AltilloCore
import Foundation

// Claude usage from Anthropic's OAuth usage endpoint, with Claude Code's own credentials (read-only).
//
// Response mapping (windows, `limits[]` weekly_scoped entries, extra usage in cents, plan formatting, Retry-After)
// adapted from openusage's ClaudeUsageMapper (https://github.com/robinebers/openusage, MIT).
// See ThirdPartyNotices/README.md.

/// Reads Claude's session, weekly and per-model weekly limits.
public struct ClaudeCollector: UsageCollector {
    public static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let fallbackVersion = "2.1.280"

    public let providerID: UsageProviderID = .claude
    public let displayName = "Claude"

    private let credentials: any ClaudeCredentialReading
    private let transport: any HTTPTransport
    private let userAgent: @Sendable () async -> String

    public init(credentials: any ClaudeCredentialReading = ClaudeCredentialStore(),
                transport: any HTTPTransport = URLSessionTransport(),
                userAgent: @escaping @Sendable () async -> String = { await ClaudeCodeVersion.shared.userAgent() }) {
        self.credentials = credentials
        self.transport = transport
        self.userAgent = userAgent
    }

    public func isAvailable() async -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let store = ClaudeCredentialStore()
        return FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path)
            || FileManager.default.fileExists(atPath: store.credentialsFile.path)
    }

    public func fetch(previous: ProviderUsage?, now: Date) async -> ProviderUsage {
        // Honour a pending Retry-After: asking again early only extends Anthropic's rate limiting.
        if let previous, case .rateLimited(let until?) = previous.problem, now < until {
            return previous
        }

        let credential: ClaudeCredentials
        switch await credentials.read(now: now) {
        case .notFound:
            return failure(.notSignedIn, detail: "Claude Code isn't signed in on this Mac.", previous: previous,
                           plan: nil, now: now)
        case .accessDenied:
            return failure(.accessDenied, detail: "Access to Claude Code's keychain item was refused.",
                           previous: previous, plan: nil, now: now)
        case .found(let found):
            credential = found
        }

        let plan = ClaudeUsageMapper.plan(subscriptionType: credential.subscriptionType,
                                          rateLimitTier: credential.rateLimitTier)
        if credential.isExpired(now: now) {
            return failure(.sessionExpired, detail: "Open Claude Code once to renew its sign-in.",
                           previous: previous, plan: plan, now: now)
        }
        if !credential.canReadUsage {
            return failure(.notSignedIn,
                           detail: "This Claude Code sign-in can't read usage (no user:profile scope). "
                               + "Run `claude` and sign in again.",
                           previous: previous, plan: plan, now: now)
        }

        var request = URLRequest(url: Self.usageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(await userAgent(), forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            return failure(.unreachable(Self.describe(error)), detail: nil, previous: previous, plan: plan, now: now)
        }

        switch response.statusCode {
        case 200..<300:
            break
        case 401, 403:
            return failure(.sessionExpired, detail: "Open Claude Code once to renew its sign-in.",
                           previous: previous, plan: plan, now: now)
        case 429:
            let retry = UsageParsing.retryAfter(response.header("Retry-After"), now: now)
                ?? now.addingTimeInterval(5 * 60)
            return failure(.rateLimited(retryAfter: retry), detail: nil, previous: previous, plan: plan, now: now)
        default:
            return failure(.unreachable("HTTP \(response.statusCode)"), detail: nil, previous: previous, plan: plan,
                           now: now)
        }

        guard let mapped = ClaudeUsageMapper.map(data) else {
            return failure(.unexpectedResponse("Claude usage response changed shape"), detail: nil,
                           previous: previous, plan: plan, now: now)
        }
        return ProviderUsage(id: providerID, displayName: displayName, plan: plan, windows: mapped.windows,
                             balances: mapped.balances, fetchedAt: now)
    }

    private func failure(_ problem: UsageProblem, detail: String?, previous: ProviderUsage?, plan: String?,
                         now: Date) -> ProviderUsage {
        var usage = previous ?? ProviderUsage(id: providerID, displayName: displayName, plan: plan, windows: [],
                                              fetchedAt: now)
        usage.problem = problem
        usage.problemDetail = detail
        if let plan { usage.plan = plan }
        return usage
    }

    static func describe(_ error: any Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "Timed out"
            case .notConnectedToInternet, .networkConnectionLost: return "Offline"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "Can't reach the server"
            default: return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

/// Pure mapping of `GET /api/oauth/usage`.
enum ClaudeUsageMapper {
    static let sessionDuration: TimeInterval = 5 * 3600
    static let weekDuration: TimeInterval = 7 * 86400

    struct Mapped: Equatable {
        var windows: [UsageWindow]
        var balances: [UsageBalance]
    }

    static func map(_ data: Data) -> Mapped? {
        guard let body = UsageParsing.object(data) else { return nil }
        var windows: [UsageWindow] = []

        if let session = window(body["five_hour"], id: "session", kind: .session, label: "Session",
                                duration: sessionDuration) {
            windows.append(session)
        } else if body.keys.contains("five_hour") {
            // Null session: none started yet (no message in the last five hours).
            windows.append(UsageWindow(id: "session", kind: .session, label: "Session", used: 0, resetsAt: nil,
                                       duration: sessionDuration))
        }
        if let week = window(body["seven_day"], id: "weekly", kind: .weekly, label: "Week", duration: weekDuration) {
            windows.append(week)
        }
        // Legacy per-model keys (now usually null; the models moved into `limits`).
        for (key, name) in [("seven_day_sonnet", "Sonnet"), ("seven_day_opus", "Opus")] {
            if let model = window(body[key], id: "weekly-\(UsageParsing.slug(name))", kind: .modelWeekly,
                                  label: "\(name) week", duration: weekDuration) {
                windows.append(model)
            }
        }
        for entry in (body["limits"] as? [Any]) ?? [] {
            guard let object = entry as? [String: Any], object["kind"] as? String == "weekly_scoped",
                  let scope = object["scope"] as? [String: Any], let model = scope["model"] as? [String: Any],
                  let name = UsageParsing.string(model["display_name"]),
                  let percent = UsageParsing.number(object["percent"]) ?? UsageParsing.number(object["utilization"])
            else { continue }
            let id = "weekly-\(UsageParsing.slug(name))"
            let window = UsageWindow(id: id, kind: .modelWeekly, label: "\(name) week", used: percent / 100,
                                     resetsAt: UsageParsing.date(object["resets_at"]), duration: weekDuration)
            if let index = windows.firstIndex(where: { $0.id == id }) {
                windows[index] = window
            } else {
                windows.append(window)
            }
        }

        var balances: [UsageBalance] = []
        if let extra = body["extra_usage"] as? [String: Any], extra["is_enabled"] as? Bool == true,
           let usedCents = UsageParsing.number(extra["used_credits"]) {
            let used = usedCents / 100
            let limit = UsageParsing.number(extra["monthly_limit"]).flatMap { $0 > 0 ? $0 / 100 : nil }
            balances.append(UsageBalance(id: "extra-usage", label: "Extra usage",
                                         remaining: limit.map { max(0, $0 - used) }, used: used, limit: limit,
                                         unit: "USD"))
        }

        guard !windows.isEmpty || !balances.isEmpty else { return nil }
        return Mapped(windows: windows.sortedForDisplay(), balances: balances)
    }

    private static func window(_ value: Any?, id: String, kind: UsageWindow.Kind, label: String,
                               duration: TimeInterval) -> UsageWindow? {
        guard let object = value as? [String: Any], let utilization = UsageParsing.number(object["utilization"]) else {
            return nil
        }
        return UsageWindow(id: id, kind: kind, label: label, used: utilization / 100,
                           resetsAt: UsageParsing.date(object["resets_at"]), duration: duration)
    }

    /// "max" + "default_claude_max_20x" → "Max 20x".
    static func plan(subscriptionType: String?, rateLimitTier: String?) -> String? {
        guard let raw = subscriptionType?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let base = UsageParsing.titleCased(raw)
        guard let tier = rateLimitTier, let match = tier.range(of: #"\d+x"#, options: .regularExpression) else {
            return base
        }
        return "\(base) \(tier[match])"
    }
}

/// The installed Claude Code version, read once for the User-Agent the usage endpoint expects.
public actor ClaudeCodeVersion {
    public static let shared = ClaudeCodeVersion()

    private var cached: String?
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func userAgent() async -> String {
        "claude-code/\(await version())"
    }

    public func version() async -> String {
        if let cached { return cached }
        var found = ClaudeCollector.fallbackVersion
        if let binary = Self.locate(),
           let result = await runner.run(binary, arguments: ["--version"], timeout: 5), result.status == 0,
           let first = String(decoding: result.stdout, as: UTF8.self).split(separator: " ").first,
           first.range(of: #"^\d+\.\d+\.\d+"#, options: .regularExpression) != nil {
            found = String(first).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        cached = found
        return found
    }

    static func locate(fileManager: FileManager = .default) -> URL? {
        let home = fileManager.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude"]
            .first { fileManager.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }
}
