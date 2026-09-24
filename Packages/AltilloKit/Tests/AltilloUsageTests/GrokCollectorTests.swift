import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

/// Canned HTTP responses chosen by URL substring (for collectors that send requests concurrently). Records requests.
final class Group2RoutedTransport: HTTPTransport, @unchecked Sendable {
    private let routes: [(match: String, reply: FakeTransport.Reply)]
    private let recorded = Locked<[URLRequest]>([])

    init(_ routes: [(String, FakeTransport.Reply)]) {
        self.routes = routes.map { (match: $0.0, reply: $0.1) }
    }

    var requests: [URLRequest] { recorded.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.withLock { $0.append(request) }
        let url = request.url!.absoluteString
        guard let route = routes.first(where: { url.contains($0.match) }) else { throw URLError(.cannotConnectToHost) }
        switch route.reply {
        case .response(let status, let body, let headers):
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                                     headerFields: headers)!)
        case .failure(let code):
            throw URLError(code)
        }
    }
}

/// An unsigned JWT with the given `exp` (the collectors only read the claim, never verify it).
func group2JWT(exp: Date) -> String {
    func encode(_ json: String) -> String {
        Data(json.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    return encode(#"{"alg":"none"}"#) + "." + encode(#"{"sub":"user","exp":\#(Int(exp.timeIntervalSince1970))}"#)
        + ".sig"
}

enum GrokFixtures {
    /// Captured from cli-chat-proxy.grok.com (openusage's GrokCreditsConfigFixtures, percent edited to 99).
    static let credits = """
    {"config":{"creditUsagePercent":99.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY",\
    "start":"2026-06-30T21:36:52.140114+00:00","end":"2026-07-07T21:36:52.140114+00:00"},\
    "onDemandCap":{"val":0},"onDemandUsed":{"val":0},"isUnifiedBillingUser":true,\
    "prepaidBalance":{"val":0},"topUpMethod":"TOP_UP_METHOD_SAVED_PAYMENT_METHOD",\
    "billingPeriodStart":"2026-06-30T21:36:52.140114+00:00",\
    "billingPeriodEnd":"2026-07-07T21:36:52.140114+00:00"}}
    """

    /// Proto-JSON drops zero values: no percent at all means 0 %.
    static let creditsZero = """
    {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-09-24T06:45:30.300431+00:00",\
    "end":"2026-10-01T06:45:30.300431+00:00"},"onDemandCap":{"val":0},"onDemandUsed":{"val":0},\
    "isUnifiedBillingUser":true,"prepaidBalance":{"val":0}}}
    """

    static let settings = #"{"leader_mode":false,"subscription_tier_display":"SuperGrok","default_model":"x"}"#

    static func auth(token: String, expiresAt: String? = nil) -> String {
        let expiry = expiresAt.map { #","expires_at":"\#($0)""# } ?? ""
        return #"{"https://auth.x.ai::client-id":{"key":"\#(token)","refresh_token":"refresh"\#(expiry),"#
            + #""email":"someone@example.com"}}"#
    }
}

struct GrokMapperTests {
    @Test func mapsCapturedWeeklyPool() throws {
        let mapped = try #require(GrokUsageMapper.map(Data(GrokFixtures.credits.utf8)))
        #expect(mapped.windows.count == 1)
        let week = mapped.windows[0]
        #expect(week.id == "weekly")
        #expect(week.kind == .weekly)
        #expect(week.label == "Week")
        #expect(abs(week.used - 0.99) < 1e-9)
        let reset = try #require(week.resetsAt)
        #expect(abs(reset.timeIntervalSince(iso("2026-07-07T21:36:52Z")) - 0.140114) < 1e-5)
        #expect(abs((week.duration ?? 0) - 7 * 86400) < 1e-3)
        #expect(mapped.balances.isEmpty) // pay-as-you-go disabled, no prepaid balance
    }

    @Test func absentPercentMeansZero() throws {
        let mapped = try #require(GrokUsageMapper.map(Data(GrokFixtures.creditsZero.utf8)))
        #expect(mapped.windows.map(\.used) == [0])
    }

    @Test func mapsMonthlyPeriodsAndBalances() throws {
        let body = """
        {"config":{"creditUsagePercent":"42.5","currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY",
          "start":"2026-09-01T00:00:00Z","end":"2026-10-01T00:00:00Z"},
          "onDemandCap":{"val":2500},"onDemandUsed":{"val":300},"prepaidBalance":{"val":12}}}
        """
        let mapped = try #require(GrokUsageMapper.map(Data(body.utf8)))
        #expect(mapped.windows.map(\.id) == ["monthly"])
        #expect(mapped.windows[0].kind == .monthly)
        #expect(mapped.windows[0].used == 0.425)
        #expect(abs((mapped.windows[0].duration ?? 0) - 30 * 86400) < 1e-3)
        #expect(mapped.balances == [
            UsageBalance(id: "pay-as-you-go", label: "Pay as you go", remaining: 2200, used: 300, limit: 2500,
                         unit: "credits"),
            UsageBalance(id: "prepaid", label: "Prepaid", remaining: 12, used: nil, limit: nil, unit: "credits"),
        ])
    }

    @Test func rejectsDriftedShapes() {
        let badPercent = GrokFixtures.credits.replacingOccurrences(of: "99.0", with: "\"lots\"")
        let backwards = GrokFixtures.credits.replacingOccurrences(of: "2026-07-07T21", with: "2026-06-01T21")
        let badCap = GrokFixtures.credits.replacingOccurrences(of: #""onDemandCap":{"val":0}"#,
                                                               with: #""onDemandCap":7"#)
        for body in [badPercent, backwards, badCap, #"{"config":{}}"#, "[]", "nope"] {
            #expect(GrokUsageMapper.map(Data(body.utf8)) == nil)
        }
    }

    @Test func readsPlanFromSettings() {
        #expect(GrokUsageMapper.plan(Data(GrokFixtures.settings.utf8)) == "SuperGrok")
        #expect(GrokUsageMapper.plan(Data(#"{"subscription_tier_display":"  "}"#.utf8)) == nil)
    }
}

struct GrokCredentialTests {
    @Test func parsesEntriesWithJWTExpiry() throws {
        let token = group2JWT(exp: referenceNow.addingTimeInterval(3600))
        let credentials = try #require(GrokCredential.parse(Data(GrokFixtures.auth(token: token).utf8)))
        #expect(credentials == [GrokCredential(accessToken: token, expiresAt: referenceNow.addingTimeInterval(3600))])
    }

    @Test func fallsBackToExpiresAtAndSkipsKeylessEntries() throws {
        let json = """
        {"a::1":{"key":"opaque-token","expires_at":"2026-09-24T12:00:00.000Z"},"b::2":{"refresh_token":"r"}}
        """
        let credentials = try #require(GrokCredential.parse(Data(json.utf8)))
        #expect(credentials == [GrokCredential(accessToken: "opaque-token", expiresAt: iso("2026-09-24T12:00:00Z"))])
        #expect(GrokCredential.parse(Data("not json".utf8)) == nil)
    }

    @Test func picksTheLongestLivedLiveToken() {
        let dead = GrokCredential(accessToken: "dead", expiresAt: referenceNow.addingTimeInterval(30))
        let soon = GrokCredential(accessToken: "soon", expiresAt: referenceNow.addingTimeInterval(600))
        let later = GrokCredential(accessToken: "later", expiresAt: referenceNow.addingTimeInterval(6000))
        #expect(GrokCredential.usable([dead, soon, later], now: referenceNow)?.accessToken == "later")
        #expect(GrokCredential.usable([dead], now: referenceNow) == nil)
    }

    @Test func honoursGrokHome() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(GrokCredential.defaultFile(environment: [:], home: home).path == "/Users/someone/.grok/auth.json")
        #expect(GrokCredential.defaultFile(environment: ["GROK_HOME": "/tmp/g"], home: home).path == "/tmp/g/auth.json")
    }
}

struct GrokCollectorTests {
    private func collector(_ transport: any HTTPTransport, auth: String?) -> GrokCollector {
        GrokCollector(transport: transport, authFile: URL(fileURLWithPath: "/nonexistent/auth.json"),
                      readFile: { _ in auth.map { Data($0.utf8) } })
    }

    private var liveAuth: String { GrokFixtures.auth(token: group2JWT(exp: referenceNow.addingTimeInterval(3600))) }

    @Test func readsUsageAndPlanWithReadOnlyHeaders() async throws {
        let transport = Group2RoutedTransport([
            ("/billing", .response(status: 200, body: GrokFixtures.credits)),
            ("/settings", .response(status: 200, body: GrokFixtures.settings)),
        ])
        let usage = await collector(transport, auth: liveAuth).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.plan == "SuperGrok")
        #expect(usage.weekly?.used == 0.99)
        #expect(usage.fetchedAt == referenceNow)

        #expect(transport.requests.count == 2)
        for request in transport.requests {
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ey") == true)
            #expect(request.value(forHTTPHeaderField: "X-XAI-Token-Auth") == "xai-grok-cli")
            #expect(request.timeoutInterval <= 10)
            #expect(request.url?.host == "cli-chat-proxy.grok.com") // never auth.x.ai: no refresh
        }
    }

    @Test func planFailureDoesNotFailTheRead() async {
        let transport = Group2RoutedTransport([
            ("/billing", .response(status: 200, body: GrokFixtures.credits)),
            ("/settings", .response(status: 500, body: "")),
        ])
        let usage = await collector(transport, auth: liveAuth).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.plan == nil)
        #expect(usage.windows.count == 1)
    }

    @Test func missingOrUnreadableSignInIsNotSignedIn() async {
        let transport = FakeTransport()
        let missing = await collector(transport, auth: nil).fetch(previous: nil, now: referenceNow)
        #expect(missing.problem == .notSignedIn)
        #expect(missing.problemDetail == "The Grok CLI isn't signed in on this Mac.")
        let broken = await collector(transport, auth: "{}").fetch(previous: nil, now: referenceNow)
        #expect(broken.problem == .notSignedIn)
        #expect(transport.requests.isEmpty)
    }

    @Test func expiredTokenIsNeverRefreshed() async {
        let transport = FakeTransport()
        let auth = GrokFixtures.auth(token: group2JWT(exp: referenceNow.addingTimeInterval(-60)))
        let usage = await collector(transport, auth: auth).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .sessionExpired)
        #expect(usage.problemDetail == "Open Grok once to renew its sign-in.")
        #expect(transport.requests.isEmpty)
    }

    @Test func unauthorizedKeepsLastNumbers() async throws {
        let good = Group2RoutedTransport([
            ("/billing", .response(status: 200, body: GrokFixtures.credits)),
            ("/settings", .response(status: 200, body: GrokFixtures.settings)),
        ])
        let previous = await collector(good, auth: liveAuth).fetch(previous: nil, now: referenceNow)
        let rejected = Group2RoutedTransport([("/", .response(status: 401, body: #"{"error":"unauthorized"}"#))])
        let later = referenceNow.addingTimeInterval(300)
        let usage = await collector(rejected, auth: liveAuth).fetch(previous: previous, now: later)
        #expect(usage.problem == .sessionExpired)
        #expect(usage.windows == previous.windows)
        #expect(usage.plan == "SuperGrok")
        #expect(usage.fetchedAt == referenceNow)
    }

    @Test func rateLimitHonoursRetryAfter() async {
        let limited = Group2RoutedTransport([("/", .response(status: 429, body: "", headers: ["Retry-After": "120"]))])
        let grok = collector(limited, auth: liveAuth)
        let usage = await grok.fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .rateLimited(retryAfter: referenceNow.addingTimeInterval(120)))
        let sent = limited.requests.count

        let again = await grok.fetch(previous: usage, now: referenceNow.addingTimeInterval(60))
        #expect(again == usage)
        #expect(limited.requests.count == sent) // nothing sent while backing off
    }

    @Test func offlineAndDriftAreExplained() async {
        let offline = Group2RoutedTransport([("/", .failure(.notConnectedToInternet))])
        #expect(await collector(offline, auth: liveAuth).fetch(previous: nil, now: referenceNow).problem
            == .unreachable("Offline"))
        let drift = Group2RoutedTransport([("/", .response(status: 200, body: #"{"config":{}}"#))])
        #expect(await collector(drift, auth: liveAuth).fetch(previous: nil, now: referenceNow).problem
            == .unexpectedResponse("Grok billing response changed shape"))
    }
}
