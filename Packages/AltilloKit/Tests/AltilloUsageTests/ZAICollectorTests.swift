import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

enum ZAIFixtures {
    /// GLM Coding Pro, captured by openusage (ZAILiveResponseMappingTests, anonymized).
    static let proQuota = #"""
    {"code":200,"msg":"Operation successful","data":{"limits":[
      {"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":17,"nextResetTime":1782724971179},
      {"type":"TOKENS_LIMIT","unit":6,"number":1,"percentage":3,"nextResetTime":1783305486997},
      {"type":"TIME_LIMIT","unit":5,"number":1,"usage":1000,"currentValue":250,"remaining":750,"percentage":25,"nextResetTime":1785292686976,"usageDetails":[{"modelCode":"search-prime","usage":0}]}
    ],"level":"pro"},"success":true}
    """#

    /// GLM Coding Lite after the CREDIT_LIMIT rename; the idle 5-hour window has no reset time.
    static let liteCreditQuota = #"""
    {"code":200,"msg":"Operation successful","data":{"limits":[
      {"type":"CREDIT_LIMIT","unit":3,"number":5,"usage":2000,"currentValue":0,"remaining":2000,"percentage":0},
      {"type":"CREDIT_LIMIT","unit":6,"number":1,"usage":10000,"currentValue":9855,"remaining":145,"percentage":98,"nextResetTime":1786685679998}
    ],"level":"lite"},"success":true}
    """#

    static let subscription = #"""
    {"code":200,"msg":"Operation successful","data":[{"productName":"GLM Coding Pro","status":"VALID","nextRenewTime":"2026-07-29","billingCycle":"monthly","inCurrentPeriod":true}],"success":true}
    """#

    static let noCodingPlan = #"{"code":500,"msg":"No active coding plan found","success":false}"#
}

struct ZAIMapperTests {
    @Test func mapsSessionWeekAndWebSearches() throws {
        let mapped = try #require(ZAIUsageMapper.map(Data(ZAIFixtures.proQuota.utf8)))
        #expect(mapped.level == "Pro")
        #expect(mapped.windows.map(\.id) == ["session", "weekly", "web-search"])
        #expect(mapped.windows[0].kind == .session)
        #expect(mapped.windows[0].used == 0.17)
        #expect(mapped.windows[0].duration == TimeInterval(5 * 3600))
        #expect(mapped.windows[0].resetsAt == Date(timeIntervalSince1970: 1_782_724_971.179))
        #expect(mapped.windows[1].kind == .weekly)
        #expect(mapped.windows[1].label == "Week")
        #expect(mapped.windows[1].used == 0.03)
        #expect(mapped.windows[1].duration == TimeInterval(7 * 86400))
        #expect(mapped.windows[2].kind == .monthly)
        #expect(mapped.windows[2].label == "Web searches")
        #expect(mapped.windows[2].used == 0.25)
    }

    @Test func idleSessionHasNoReset() throws {
        let mapped = try #require(ZAIUsageMapper.map(Data(ZAIFixtures.liteCreditQuota.utf8)))
        #expect(mapped.windows.map(\.id) == ["session", "weekly"])
        #expect(mapped.windows[0].used == 0)
        #expect(mapped.windows[0].resetsAt == nil)
        #expect(mapped.windows[1].used == 0.98)
    }

    @Test func otherShapes() {
        #expect(ZAIUsageMapper.map(Data(#"{"data":{"limits":[]}}"#.utf8))?.windows == [])
        #expect(ZAIUsageMapper.map(Data(#"{"limits":[{"type":"TOKENS_LIMIT","unit":4,"number":30,"percentage":50}]}"#.utf8))?
            .windows.map(\.id) == ["monthly"])
        #expect(ZAIUsageMapper.map(Data(#"{"limits":[{"type":"TOKENS_LIMIT","unit":4,"number":2,"percentage":50}]}"#.utf8))?
            .windows.first?.label == "2-day")
        #expect(ZAIUsageMapper.map(Data(#"{"data":{"limits":[{"type":"TOKENS_LIMIT"}]}}"#.utf8)) == nil)
        #expect(ZAIUsageMapper.map(Data(#"{"data":"nope"}"#.utf8)) == nil)
        #expect(ZAIUsageMapper.isNoCodingPlan(Data(ZAIFixtures.noCodingPlan.utf8)))
        #expect(!ZAIUsageMapper.isNoCodingPlan(Data(ZAIFixtures.proQuota.utf8)))
        #expect(ZAIUsageMapper.planName(Data(ZAIFixtures.subscription.utf8)) == "GLM Coding Pro")
    }
}

struct ZAICollectorTests {
    func collector(_ routes: [(String, FakeTransport.Reply)], environment: [String: String] = ["ZAI_API_KEY": "zk"])
        -> (ZAICollector, RoutedTransport) {
        let transport = RoutedTransport(routes)
        let source = LocalAPIKeySource(files: [URL(fileURLWithPath: "/cfg/zai/key.json")],
                                       environmentNames: ["ZAI_API_KEY", "GLM_API_KEY"], environment: environment,
                                       readFile: { _ in nil })
        return (ZAICollector(keySource: source, transport: transport), transport)
    }

    @Test func readsQuotaAndPlan() async {
        let (zai, transport) = collector([
            ("quota/limit", .response(status: 200, body: ZAIFixtures.proQuota)),
            ("subscription/list", .response(status: 200, body: ZAIFixtures.subscription)),
        ])
        let usage = await zai.fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.id == .zai)
        #expect(usage.plan == "GLM Coding Pro")
        #expect(usage.session?.used == 0.17)
        #expect(usage.weekly?.used == 0.03)
        #expect(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer zk" })
    }

    @Test func subscriptionFailureKeepsMeters() async {
        let (zai, _) = collector([("quota/limit", .response(status: 200, body: ZAIFixtures.liteCreditQuota))],
                                 environment: ["GLM_API_KEY": "legacy"])
        let usage = await zai.fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.plan == "Lite") // from data.level
        #expect(usage.windows.count == 2)
    }

    @Test func failures() async {
        let noPlan = await collector([("quota/limit", .response(status: 200, body: ZAIFixtures.noCodingPlan))]).0
            .fetch(previous: nil, now: referenceNow)
        #expect(noPlan.problem == .notSignedIn)
        #expect(noPlan.problemDetail == "This Z.ai account has no GLM Coding Plan.")

        let previous = ProviderUsage(id: .zai, displayName: "Z.ai", plan: "GLM Coding Pro", windows: [
            UsageWindow(id: "session", kind: .session, label: "Session", used: 0.5, resetsAt: nil, duration: 18000),
        ], fetchedAt: referenceNow.addingTimeInterval(-300))
        let rejected = await collector([("quota/limit", .response(status: 401, body: ""))]).0
            .fetch(previous: previous, now: referenceNow)
        #expect(rejected.problem == .sessionExpired)
        #expect(rejected.windows == previous.windows)

        let limited = await collector([("quota/limit", .response(status: 429, body: ""))]).0
            .fetch(previous: nil, now: referenceNow)
        #expect(limited.problem == .rateLimited(retryAfter: referenceNow.addingTimeInterval(300)))

        let odd = await collector([("quota/limit", .response(status: 200, body: "{}"))]).0
            .fetch(previous: nil, now: referenceNow)
        #expect(odd.problem == .unexpectedResponse("Z.ai quota response changed shape"))

        let (missing, transport) = collector([], environment: [:])
        #expect(!(await missing.isAvailable()))
        #expect(await missing.fetch(previous: nil, now: referenceNow).problem == .notSignedIn)
        #expect(transport.requests.isEmpty)
    }
}
