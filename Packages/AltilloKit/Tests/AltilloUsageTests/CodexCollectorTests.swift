import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

struct CodexMapperTests {
    @Test func mapsTheLiveAppServerShape() throws {
        let mapped = try #require(CodexUsageMapper.mapAppServer(Data(Fixtures.codexAppServerWeeklyOnly.utf8)))
        #expect(mapped.plan == "Pro 5x")
        #expect(mapped.windows == [UsageWindow(id: "weekly", kind: .weekly, label: "Week", used: 1,
                                               resetsAt: Date(timeIntervalSince1970: 1_790_414_188),
                                               duration: 10080 * 60)])
        // Zero credits without hasCredits are noise; one available limit reset is shown.
        #expect(mapped.balances.map(\.id) == ["limit-resets"])
        #expect(mapped.balances[0].remaining == 1)
    }

    @Test func mapsSessionWeekModelsAndCredits() throws {
        let mapped = try #require(CodexUsageMapper.mapAppServer(Data(Fixtures.codexAppServerFull.utf8)))
        #expect(mapped.plan == "Pro 20x")
        #expect(mapped.windows.map(\.id) == ["session", "weekly", "weekly-codex-spark", "session-codex-spark"])
        #expect(mapped.windows[0].used == 0.125) // fractional percent survives (Double, not Int)
        #expect(mapped.windows[0].duration == TimeInterval(300 * 60))
        #expect(mapped.windows[2].label == "GPT-5.3-Codex-Spark week")
        #expect(mapped.windows[2].kind == .modelWeekly)
        #expect(mapped.balances == [UsageBalance(id: "credits", label: "Credits", remaining: 42.75, used: nil,
                                                 limit: nil, unit: "credits")])
    }

    @Test func mapsWham() throws {
        let mapped = try #require(CodexUsageMapper.mapWham(Data(Fixtures.codexWham.utf8), now: referenceNow))
        #expect(mapped.plan == "Plus")
        #expect(mapped.windows.map(\.id) == ["session", "weekly", "session-codex-spark"])
        #expect(mapped.windows[0].used == 0.33)
        #expect(mapped.windows[0].duration == 18000)
        #expect(mapped.windows[1].resetsAt == Date(timeIntervalSince1970: 1_790_600_000))
        #expect(mapped.balances.map(\.id) == ["credits", "limit-resets"])
        #expect(mapped.balances[1].remaining == 2)
    }

    @Test(arguments: [
        (300.0, CodexUsageMapper.Slot.primary, UsageWindow.Kind.session),
        (360, .secondary, .session),
        (10080, .primary, .weekly),
        (8640, .secondary, .weekly),
        (43200, .primary, .monthly),
        (1440, .primary, .other),
    ])
    func classifiesWindowsByDuration(minutes: Double, slot: CodexUsageMapper.Slot, kind: UsageWindow.Kind) {
        #expect(CodexUsageMapper.classify(minutes: minutes, slot: slot) == kind)
    }

    @Test func unknownDurationFallsBackToSlot() {
        #expect(CodexUsageMapper.classify(minutes: nil, slot: .primary) == .session)
        #expect(CodexUsageMapper.classify(minutes: nil, slot: .secondary) == .weekly)
    }

    @Test func planNames() {
        #expect(CodexUsageMapper.planName("prolite") == "Pro 5x")
        #expect(CodexUsageMapper.planName("pro") == "Pro 20x")
        #expect(CodexUsageMapper.planName("plus") == "Plus")
        #expect(CodexUsageMapper.planName("") == nil)
    }
}

struct CodexCollectorTests {
    let auth = CodexAuth(accessToken: "codex-token", accountID: "acct-1")

    @Test func appServerWinsAndSkipsHTTP() async {
        let transport = FakeTransport()
        let collector = CodexCollector(appServer: FakeCodexReader(result: .success(Fixtures.codexAppServerFull)),
                                       transport: transport, readAuth: { auth }, authFileExists: { true })
        let usage = await collector.fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.session?.used == 0.125)
        #expect(transport.requests.isEmpty)
    }

    @Test func fallsBackToWhamWhenAppServerFails() async throws {
        let transport = FakeTransport([.response(status: 200, body: Fixtures.codexWham)])
        let collector = CodexCollector(appServer: FakeCodexReader(result: .failure(.timedOut)),
                                       transport: transport, readAuth: { auth }, authFileExists: { true })
        let usage = await collector.fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.plan == "Plus")
        let request = try #require(transport.requests.first)
        #expect(request.url == CodexCollector.whamURL)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer codex-token")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct-1")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Altillo")
    }

    @Test func notInstalledNorSignedIn() async {
        let collector = CodexCollector(appServer: nil, transport: FakeTransport(), readAuth: { nil },
                                       authFileExists: { false })
        #expect(await !collector.isAvailable())
        let usage = await collector.fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .notSignedIn)
    }

    @Test func missingBinaryWithoutAuthIsNotSignedIn() async {
        let collector = CodexCollector(appServer: FakeCodexReader(result: .failure(.notInstalled)),
                                       transport: FakeTransport(), readAuth: { nil }, authFileExists: { false },
                                       binaryExists: { false })
        #expect(await !collector.isAvailable())
        #expect(await collector.fetch(previous: nil, now: referenceNow).problem == .notSignedIn)
    }

    @Test func appServerErrorWithoutAuthIsUnreachable() async {
        let collector = CodexCollector(appServer: FakeCodexReader(result: .failure(.rpcError("boom"))),
                                       transport: FakeTransport(), readAuth: { nil }, authFileExists: { false })
        let usage = await collector.fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .unreachable("codex app-server: boom"))
    }

    @Test func whamUnauthorizedIsExpiredAndKeepsNumbers() async {
        let previous = ProviderUsage(id: .codex, displayName: "Codex", plan: "Plus",
                                     windows: [UsageWindow(id: "weekly", kind: .weekly, label: "Week", used: 0.4,
                                                           resetsAt: nil, duration: nil)],
                                     fetchedAt: referenceNow)
        let collector = CodexCollector(appServer: nil, transport: FakeTransport([.response(status: 401, body: "")]),
                                       readAuth: { auth }, authFileExists: { true })
        let usage = await collector.fetch(previous: previous, now: referenceNow.addingTimeInterval(300))
        #expect(usage.problem == .sessionExpired)
        #expect(usage.windows == previous.windows)
    }

    @Test func whamRateLimited() async {
        let collector = CodexCollector(appServer: nil,
                                       transport: FakeTransport([.response(status: 429, body: "",
                                                                           headers: ["retry-after": "30"])]),
                                       readAuth: { auth }, authFileExists: { true })
        let usage = await collector.fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .rateLimited(retryAfter: referenceNow.addingTimeInterval(30)))
    }

    @Test func parsesAuthFile() {
        let data = Data(#"{"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":{"id_token":"i","access_token":"a","refresh_token":"r","account_id":"acct"},"last_refresh":"2026-09-20T00:00:00Z"}"#.utf8)
        #expect(CodexAuth.parse(data) == CodexAuth(accessToken: "a", accountID: "acct"))
        #expect(CodexAuth.parse(Data(#"{"OPENAI_API_KEY":"sk-x"}"#.utf8)) == nil)
        #expect(CodexAuth.defaultFile(environment: ["CODEX_HOME": "/tmp/cx"]).path == "/tmp/cx/auth.json")
    }
}

/// Drives the real `Process` plumbing with a scripted stand-in for `codex app-server`.
@Suite(.serialized)
struct CodexAppServerProcessTests {
    private func script(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-codex-\(UUID().uuidString).sh")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func isAlive(_ pidFile: URL) -> Bool {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return kill(pid, 0) == 0
    }

    @Test func speaksJSONRPCAndStopsTheServer() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("fake-codex-\(UUID()).pid")
        let fake = try script("""
        echo $$ > '\(pidFile.path)'
        read init
        echo '{"method":"remoteControl/status/changed","params":{}}'
        echo '{"id":1,"result":{"userAgent":"fake"}}'
        read initialized
        read request
        case "$request" in *account/rateLimits/read*) ;; *) exit 3 ;; esac
        echo '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":42.5,"windowDurationMins":300,"resetsAt":1790170000},"planType":"plus"}}}'
        sleep 30
        """)
        defer { try? FileManager.default.removeItem(at: fake); try? FileManager.default.removeItem(at: pidFile) }
        let data = try await CodexAppServerClient(executable: fake, timeout: 5).readRateLimits()
        let mapped = try #require(CodexUsageMapper.mapAppServer(data))
        #expect(mapped.session?.used == 0.425)
        try await Task.sleep(for: .milliseconds(1500))
        #expect(!isAlive(pidFile))
    }

    @Test func timesOutAndKillsAStubbornServer() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("fake-codex-\(UUID()).pid")
        let fake = try script("""
        trap '' TERM
        echo $$ > '\(pidFile.path)'
        while true; do sleep 1; done
        """)
        defer { try? FileManager.default.removeItem(at: fake); try? FileManager.default.removeItem(at: pidFile) }
        let started = Date()
        await #expect(throws: CodexAppServerError.timedOut) {
            try await CodexAppServerClient(executable: fake, timeout: 0.5).readRateLimits()
        }
        #expect(Date().timeIntervalSince(started) < 3)
        try await Task.sleep(for: .milliseconds(2000))
        #expect(!isAlive(pidFile))
    }

    @Test func reportsAnEarlyExit() async throws {
        let fake = try script("echo 'not logged in' >&2\nexit 2\n")
        defer { try? FileManager.default.removeItem(at: fake) }
        do {
            _ = try await CodexAppServerClient(executable: fake, timeout: 5).readRateLimits()
            Issue.record("expected failure")
        } catch let error as CodexAppServerError {
            if case .exited(let status, _) = error { #expect(status == 2) } else {
                // The write to a closed stdin can win the race; either way it fails fast.
                #expect(error == .launchFailed("stdin closed"))
            }
        }
    }
}

private extension CodexUsageMapper.Mapped {
    var session: UsageWindow? { windows.first { $0.kind == .session } }
}
