import AltilloCore
import Foundation
@testable import AltilloUsage

/// Canned HTTP responses; records every request so tests can assert headers or that nothing was sent.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    enum Reply {
        case response(status: Int, body: String, headers: [String: String] = [:])
        case failure(URLError.Code)
    }

    private let replies = Locked<[Reply]>([])
    private let recorded = Locked<[URLRequest]>([])

    init(_ replies: [Reply] = []) {
        self.replies.withLock { $0 = replies }
    }

    var requests: [URLRequest] { recorded.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.withLock { $0.append(request) }
        let reply = replies.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        switch reply {
        case .response(let status, let body, let headers)?:
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: headers)!
            return (Data(body.utf8), response)
        case .failure(let code)?:
            throw URLError(code)
        case nil:
            throw URLError(.cannotConnectToHost)
        }
    }
}

/// Canned command results keyed by call order; records the arguments.
final class FakeRunner: CommandRunning, @unchecked Sendable {
    private let results = Locked<[CommandResult?]>([])
    private let calls = Locked<[[String]]>([])

    init(_ results: [CommandResult?]) {
        self.results.withLock { $0 = results }
    }

    var arguments: [[String]] { calls.withLock { $0 } }

    func run(_ executable: URL, arguments: [String], timeout: TimeInterval) async -> CommandResult? {
        calls.withLock { $0.append(arguments) }
        return results.withLock { $0.isEmpty ? CommandResult(status: 44, stdout: Data()) : $0.removeFirst() }
    }
}

struct FixedCredentials: ClaudeCredentialReading {
    var lookup: ClaudeCredentialLookup
    func read(now: Date) async -> ClaudeCredentialLookup { lookup }
}

struct FakeCodexReader: CodexRateLimitReading {
    var result: Result<String, CodexAppServerError>
    func readRateLimits() async throws -> Data {
        switch result {
        case .success(let text): Data(text.utf8)
        case .failure(let error): throw error
        }
    }
}

/// 2026-09-24T10:00:00Z.
let referenceNow = Date(timeIntervalSince1970: 1_790_244_000)

func iso(_ text: String) -> Date { UsageParsing.isoDate(text)! }

func hex(_ text: String) -> String { Data(text.utf8).map { String(format: "%02x", $0) }.joined() }

enum Fixtures {
    static let claudeUsage = """
    {
      "five_hour": {"utilization": 58.0, "resets_at": "2026-09-24T15:10:00.720317+00:00"},
      "seven_day": {"utilization": 56, "resets_at": "2026-09-29T05:00:00.754Z"},
      "seven_day_sonnet": null,
      "seven_day_opus": null,
      "limits": [
        {"kind": "weekly_scoped", "percent": 10, "resets_at": "2026-09-29T04:59:59.720Z",
         "scope": {"model": {"display_name": "Fable"}}},
        {"kind": "something_else", "percent": 99, "scope": {"model": {"display_name": "Ignored"}}}
      ],
      "extra_usage": {"is_enabled": true, "used_credits": 1250, "monthly_limit": 5000}
    }
    """

    static let claudeUsageNoSession = """
    {"five_hour": null, "seven_day": {"utilization": 3.5, "resets_at": 1790650800},
     "seven_day_sonnet": {"utilization": 12, "resets_at": 1790650800000},
     "extra_usage": {"is_enabled": false, "used_credits": 0, "monthly_limit": null}}
    """

    static let claudeUsageSessionNotStarted = """
    {"five_hour": {"utilization": 0, "resets_at": null}, "seven_day": {"utilization": 20, "resets_at": null}}
    """

    static func claudeCredential(expiresAt: Date, scopes: [String] = ["user:inference", "user:profile"]) -> String {
        let scopeList = scopes.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {"claudeAiOauth":{"accessToken":"sk-ant-oat01-test","refreshToken":"sk-ant-ort01-test",
        "expiresAt":\(Int(expiresAt.timeIntervalSince1970 * 1000)),"scopes":[\(scopeList)],
        "subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}
        """
    }

    /// Shape captured from `codex app-server` 0.152 (ids/tokens trimmed).
    static let codexAppServerWeeklyOnly = """
    {"rateLimits":{"limitId":"codex","limitName":null,
      "primary":{"usedPercent":100,"windowDurationMins":10080,"resetsAt":1790414188},"secondary":null,
      "credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"prolite"},
     "rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":null,
      "primary":{"usedPercent":100,"windowDurationMins":10080,"resetsAt":1790414188},"secondary":null,
      "credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"prolite"}},
     "rateLimitResetCredits":{"availableCount":1,"credits":[]}}
    """

    static let codexAppServerFull = """
    {"rateLimits":{"limitId":"codex","primary":{"usedPercent":12.5,"windowDurationMins":300,"resetsAt":1790170000},
      "secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":1790600000},
      "credits":{"hasCredits":true,"unlimited":false,"balance":"42.75"},"planType":"pro"},
     "rateLimitsByLimitId":{
      "codex":{"limitId":"codex","primary":{"usedPercent":12.5,"windowDurationMins":300,"resetsAt":1790170000},
        "secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":1790600000},
        "credits":{"hasCredits":true,"unlimited":false,"balance":"42.75"},"planType":"pro"},
      "codex_spark":{"limitId":"codex_spark","limitName":"GPT-5.3-Codex-Spark",
        "primary":{"usedPercent":5,"windowDurationMins":300,"resetsAt":1790170000},
        "secondary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":1790600000}}}}
    """

    static let codexWham = """
    {"plan_type":"plus",
     "rate_limit":{"allowed":true,"limit_reached":false,
       "primary_window":{"used_percent":33,"limit_window_seconds":18000,"reset_at":1790170000},
       "secondary_window":{"used_percent":61,"limit_window_seconds":604800,"reset_at":1790600000}},
     "additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"codex_spark",
       "rate_limit":{"primary_window":{"used_percent":2,"limit_window_seconds":18000,"reset_at":1790170000}}},
       null],
     "credits":{"has_credits":true,"unlimited":false,"balance":"7"},
     "rate_limit_reset_credits":{"available_count":2}}
    """

    /// Shape served by the OpenUsage app's local API (captured 2026-09-24).
    static let openUsageLimits = """
    {"errors":[{"provider":"cursor","message":"Not signed in"}],"generatedAt":"2026-09-24T10:39:26.641Z",
     "providers":{
      "claude":{"displayName":"Claude","expiresAt":"2026-09-24T10:41:22.558Z","fetchedAt":"2026-09-24T10:36:22.558Z",
        "plan":"Max 5x","stale":false,"resources":{
          "fable":{"kind":"consumption","limit":100,"remaining":90,"resetsAt":"2026-09-29T04:59:59.720Z",
            "unit":"percent","used":10,"utilization":0.1,"windowSeconds":604800},
          "rateLimitResets":{"available":1,"expiresAt":["2026-10-22T16:00:00.000Z"],"kind":"balance","unit":"resets"},
          "session":{"kind":"consumption","limit":100,"remaining":58,"resetsAt":"2026-09-24T15:10:00.720Z",
            "unit":"percent","used":42,"utilization":0.42,"windowSeconds":18000},
          "weekly":{"kind":"consumption","limit":100,"remaining":45,"resetsAt":"2026-09-29T05:00:00.720Z",
            "unit":"percent","used":55,"utilization":0.55,"windowSeconds":604800}}},
      "cursor":{"displayName":"Cursor","fetchedAt":"2026-09-24T10:30:00Z","stale":true,"resources":{
          "spend":{"kind":"consumption","unit":"usd","used":12.5,"limit":20},
          "onDemand":{"kind":"consumption","unit":"usd","used":3}}},
      "grok":{"displayName":"Grok","expiresAt":"2026-09-24T10:41:22.441Z","fetchedAt":"2026-09-24T10:36:22.441Z",
        "plan":"SuperGrok","stale":false,"resources":{
          "weekly":{"kind":"consumption","limit":100,"remaining":100,"resetsAt":"2026-10-01T06:45:30.300Z",
            "unit":"percent","used":0,"utilization":0,"windowSeconds":604800}}}},
     "schema":"openusage.limits.v1"}
    """
}
