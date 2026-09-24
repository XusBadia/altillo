import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

enum OpenCodeFixtures {
    /// openusage's OpenCodeUsageMapperTests sample.
    static let usage = """
    {"usage":{
      "rolling":{"status":"ok","percent":12,"resetsAt":"2026-07-12T13:30:00.662Z"},
      "weekly":{"status":"ok","percent":8,"resetsAt":"2026-07-13T00:00:00.662Z"},
      "monthly":{"status":"rate-limited","percent":100,"resetsAt":"2026-08-04T11:18:32.662Z"}}}
    """
    static let entitlementError =
        #"{"type":"error","error":{"type":"EntitlementError","message":"OpenCode Go subscription required."}}"#
    static let authError = #"{"type":"error","error":{"type":"AuthError","message":"Unauthorized"}}"#
    static let auth = #"{"anthropic":{"type":"oauth","access":"x"},"opencode-go":{"type":"api","key":"sk-go-test"}}"#
}

struct OpenCodeMapperTests {
    @Test func mapsTheThreeGoWindows() throws {
        let windows = try #require(OpenCodeUsageMapper.map(Data(OpenCodeFixtures.usage.utf8)))
        #expect(windows.map(\.id) == ["session", "weekly", "monthly"])
        #expect(windows.map(\.kind) == [.session, .weekly, .monthly])
        #expect(windows.map(\.used) == [0.12, 0.08, 1])
        #expect(windows[0].duration == TimeInterval(5 * 3600))
        #expect(windows[1].duration == TimeInterval(7 * 86400))
        let reset = try #require(windows[0].resetsAt)
        #expect(abs(reset.timeIntervalSince(iso("2026-07-12T13:30:00Z")) - 0.662) < 1e-6)
    }

    @Test func toleratesMissingWindowsButNotEmptyBodies() throws {
        let partial = try #require(OpenCodeUsageMapper.map(Data(#"{"usage":{"weekly":{"percent":"150"}}}"#.utf8)))
        #expect(partial.map(\.id) == ["weekly"])
        #expect(partial[0].used == 1.5) // over the limit stays visible
        #expect(partial[0].resetsAt == nil)
        #expect(OpenCodeUsageMapper.map(Data(#"{"usage":{}}"#.utf8)) == nil)
        #expect(OpenCodeUsageMapper.map(Data(#"{"rolling":{"percent":1}}"#.utf8)) == nil)
    }

    @Test func readsErrorTypes() {
        #expect(OpenCodeUsageMapper.errorType(Data(OpenCodeFixtures.entitlementError.utf8)) == "EntitlementError")
        #expect(OpenCodeUsageMapper.errorType(Data(OpenCodeFixtures.authError.utf8)) == "AuthError")
        #expect(OpenCodeUsageMapper.errorType(Data("<html>".utf8)) == nil)
    }
}

struct OpenCodeAuthTests {
    @Test func resolvesTheDataDirectoryLikeOpenCode() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(OpenCodeAuth.defaultFile(environment: [:], home: home).path
            == "/Users/someone/.local/share/opencode/auth.json")
        #expect(OpenCodeAuth.defaultFile(environment: ["XDG_DATA_HOME": "/xdg"], home: home).path
            == "/xdg/opencode/auth.json")
        #expect(OpenCodeAuth.defaultFile(environment: ["XDG_DATA_HOME": "/xdg", "OPENCODE_DATA_DIR": "/oc"],
                                         home: home).path == "/oc/auth.json")
        #expect(OpenCodeAuth.defaultFile(environment: ["OPENCODE_DATA_DIR": "  "], home: home).path
            == "/Users/someone/.local/share/opencode/auth.json")
    }

    @Test func readsOnlyTheGoKey() {
        #expect(OpenCodeAuth.parse(Data(OpenCodeFixtures.auth.utf8)) == .key("sk-go-test"))
        #expect(OpenCodeAuth.parse(Data(#"{"anthropic":{"type":"oauth"}}"#.utf8)) == .noGoKey)
        #expect(OpenCodeAuth.parse(Data(#"{"opencode-go":{"key":" "}}"#.utf8)) == .noGoKey)
        #expect(OpenCodeAuth.parse(Data("{broken".utf8)) == .unreadable)
    }
}

struct OpenCodeCollectorTests {
    private func collector(_ transport: any HTTPTransport, auth: String? = OpenCodeFixtures.auth) -> OpenCodeCollector {
        OpenCodeCollector(transport: transport, authFile: URL(fileURLWithPath: "/nonexistent/auth.json"),
                          readFile: { _ in auth.map { Data($0.utf8) } })
    }

    @Test func readsGoUsage() async throws {
        let transport = FakeTransport([.response(status: 200, body: OpenCodeFixtures.usage)])
        let usage = await collector(transport).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.plan == "Go")
        #expect(usage.windows.count == 3)
        let request = try #require(transport.requests.first)
        #expect(request.url == OpenCodeCollector.usageURL)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-go-test")
        #expect(request.timeoutInterval <= 10)
    }

    @Test func availabilityNeedsAGoKey() async {
        #expect(await collector(FakeTransport()).isAvailable())
        #expect(!(await collector(FakeTransport(), auth: #"{"anthropic":{}}"#).isAvailable()))
        #expect(!(await collector(FakeTransport(), auth: nil).isAvailable()))
    }

    @Test func missingSignInAndMissingGoKeyAreExplained() async {
        let transport = FakeTransport()
        let missing = await collector(transport, auth: nil).fetch(previous: nil, now: referenceNow)
        #expect(missing.problem == .notSignedIn)
        let noGo = await collector(transport, auth: #"{"anthropic":{}}"#).fetch(previous: nil, now: referenceNow)
        #expect(noGo.problem == .notSignedIn)
        #expect(noGo.problemDetail?.contains("OpenCode Go") == true)
        #expect(transport.requests.isEmpty)
    }

    @Test func entitlementErrorMeansNoGoPlan() async {
        let good = await collector(FakeTransport([.response(status: 200, body: OpenCodeFixtures.usage)]))
            .fetch(previous: nil, now: referenceNow)
        let transport = FakeTransport([.response(status: 403, body: OpenCodeFixtures.entitlementError)])
        let usage = await collector(transport).fetch(previous: good, now: referenceNow)
        #expect(usage.problem == .notSignedIn)
        #expect(usage.problemDetail == "This OpenCode account has no OpenCode Go subscription.")
        #expect(usage.windows.isEmpty) // the old plan's numbers no longer apply
    }

    @Test func rejectedKeyKeepsLastNumbers() async {
        let good = await collector(FakeTransport([.response(status: 200, body: OpenCodeFixtures.usage)]))
            .fetch(previous: nil, now: referenceNow)
        let usage = await collector(FakeTransport([.response(status: 401, body: OpenCodeFixtures.authError)]))
            .fetch(previous: good, now: referenceNow.addingTimeInterval(300))
        #expect(usage.problem == .notSignedIn)
        #expect(usage.problemDetail == "OpenCode rejected its Go key. Sign in to OpenCode Go again.")
        #expect(usage.windows == good.windows)
    }

    @Test func rateLimitAndOutagesKeepLastNumbers() async {
        let good = await collector(FakeTransport([.response(status: 200, body: OpenCodeFixtures.usage)]))
            .fetch(previous: nil, now: referenceNow)
        let limitedTransport = FakeTransport([.response(status: 429, body: "")])
        let limited = await collector(limitedTransport).fetch(previous: good, now: referenceNow)
        #expect(limited.problem == .rateLimited(retryAfter: referenceNow.addingTimeInterval(300)))
        #expect(limited.windows == good.windows)
        let skipped = await collector(limitedTransport).fetch(previous: limited, now: referenceNow.addingTimeInterval(10))
        #expect(skipped == limited)
        #expect(limitedTransport.requests.count == 1)

        let down = await collector(FakeTransport([.response(status: 502, body: "")])).fetch(previous: good, now: referenceNow)
        #expect(down.problem == .unreachable("HTTP 502"))
        #expect(down.windows == good.windows)
    }
}
