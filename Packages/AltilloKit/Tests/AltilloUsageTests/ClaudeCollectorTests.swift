import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

struct ClaudeMapperTests {
    @Test func mapsWindowsScopedLimitsAndExtraUsage() throws {
        let mapped = try #require(ClaudeUsageMapper.map(Data(Fixtures.claudeUsage.utf8)))
        #expect(mapped.windows.map(\.id) == ["session", "weekly", "weekly-fable"])

        let session = mapped.windows[0]
        #expect(session.kind == .session)
        #expect(session.used == 0.58)
        #expect(session.duration == TimeInterval(5 * 3600))
        let reset = try #require(session.resetsAt)
        #expect(abs(reset.timeIntervalSince(iso("2026-09-24T15:10:00Z")) - 0.720317) < 0.000_01)

        #expect(mapped.windows[1].used == 0.56)
        #expect(mapped.windows[1].duration == TimeInterval(7 * 86400))
        #expect(mapped.windows[2].label == "Fable week")
        #expect(mapped.windows[2].kind == .modelWeekly)
        #expect(mapped.windows[2].used == 0.1)

        #expect(mapped.balances == [UsageBalance(id: "extra-usage", label: "Extra usage", remaining: 37.5, used: 12.5,
                                                 limit: 50, unit: "USD")])
    }

    @Test func nullSessionMeansNotStartedAndEpochResets() throws {
        let mapped = try #require(ClaudeUsageMapper.map(Data(Fixtures.claudeUsageNoSession.utf8)))
        #expect(mapped.windows.map(\.id) == ["session", "weekly", "weekly-sonnet"])
        #expect(mapped.windows[0].used == 0)
        #expect(mapped.windows[0].resetsAt == nil)
        #expect(mapped.windows[1].resetsAt == Date(timeIntervalSince1970: 1_790_650_800))
        #expect(mapped.windows[2].resetsAt == Date(timeIntervalSince1970: 1_790_650_800)) // milliseconds
        #expect(mapped.balances.isEmpty) // extra usage disabled
    }

    @Test func missingResetMeansNotStarted() throws {
        let mapped = try #require(ClaudeUsageMapper.map(Data(Fixtures.claudeUsageSessionNotStarted.utf8)))
        #expect(mapped.windows.allSatisfy { $0.resetsAt == nil })
        #expect(mapped.windows.map(\.used) == [0, 0.2])
    }

    @Test func rejectsUnknownShapes() {
        #expect(ClaudeUsageMapper.map(Data("[]".utf8)) == nil)
        #expect(ClaudeUsageMapper.map(Data(#"{"error":"nope"}"#.utf8)) == nil)
    }

    @Test func formatsPlans() {
        #expect(ClaudeUsageMapper.plan(subscriptionType: "max", rateLimitTier: "default_claude_max_20x") == "Max 20x")
        #expect(ClaudeUsageMapper.plan(subscriptionType: "max", rateLimitTier: "default_claude_max_5x") == "Max 5x")
        #expect(ClaudeUsageMapper.plan(subscriptionType: "pro", rateLimitTier: "default_claude_pro") == "Pro")
        #expect(ClaudeUsageMapper.plan(subscriptionType: nil, rateLimitTier: "x") == nil)
    }
}

struct ClaudeCredentialTests {
    @Test func parsesPlainAndHexValues() throws {
        let json = Fixtures.claudeCredential(expiresAt: referenceNow.addingTimeInterval(3600))
        let plain = try #require(ClaudeCredentials.parse(json, source: .keychain))
        let wrapped = try #require(ClaudeCredentials.parse(hex(json), source: .keychain))
        #expect(plain == wrapped)
        #expect(plain.accessToken == "sk-ant-oat01-test")
        #expect(plain.expiresAt == referenceNow.addingTimeInterval(3600))
        #expect(plain.subscriptionType == "max")
        #expect(plain.canReadUsage)
    }

    @Test func expiryUsesFiveMinuteMargin() throws {
        let soon = try #require(ClaudeCredentials.parse(
            Fixtures.claudeCredential(expiresAt: referenceNow.addingTimeInterval(240)), source: .file))
        let later = try #require(ClaudeCredentials.parse(
            Fixtures.claudeCredential(expiresAt: referenceNow.addingTimeInterval(600)), source: .file))
        #expect(soon.isExpired(now: referenceNow))
        #expect(!later.isExpired(now: referenceNow))
    }

    @Test func tokensWithoutProfileScopeCantReadUsage() throws {
        let token = try #require(ClaudeCredentials.parse(
            Fixtures.claudeCredential(expiresAt: referenceNow.addingTimeInterval(3600), scopes: ["user:inference"]),
            source: .keychain))
        #expect(!token.canReadUsage)
    }

    @Test func keychainFirstRetryingWithoutAccount() async throws {
        let value = hex(Fixtures.claudeCredential(expiresAt: referenceNow.addingTimeInterval(3600)))
        let runner = FakeRunner([CommandResult(status: 44, stdout: Data()),
                                 CommandResult(status: 0, stdout: Data((value + "\n").utf8))])
        let store = ClaudeCredentialStore(runner: runner, environment: [:], homeDirectory: URL(fileURLWithPath: "/x"),
                                          userName: "me", readFile: { _ in nil })
        guard case .found(let credential) = await store.read(now: referenceNow) else {
            Issue.record("expected credentials")
            return
        }
        #expect(credential.source == .keychain)
        #expect(runner.arguments == [["find-generic-password", "-a", "me", "-s", "Claude Code-credentials", "-w"],
                                     ["find-generic-password", "-s", "Claude Code-credentials", "-w"]])
    }

    @Test func expiredKeychainFallsBackToValidFile() async {
        let expired = Fixtures.claudeCredential(expiresAt: referenceNow.addingTimeInterval(-60))
        let valid = Fixtures.claudeCredential(expiresAt: referenceNow.addingTimeInterval(3600))
        let runner = FakeRunner([CommandResult(status: 0, stdout: Data(expired.utf8))])
        let store = ClaudeCredentialStore(runner: runner, environment: [:], homeDirectory: URL(fileURLWithPath: "/h"),
                                          userName: "me", readFile: { url in
                                              url.path == "/h/.claude/.credentials.json" ? valid : nil
                                          })
        guard case .found(let credential) = await store.read(now: referenceNow) else {
            Issue.record("expected credentials")
            return
        }
        #expect(credential.source == .file)
    }

    @Test func stalePairStillReportsTheCredential() async {
        let expired = Fixtures.claudeCredential(expiresAt: referenceNow.addingTimeInterval(-60))
        let runner = FakeRunner([CommandResult(status: 0, stdout: Data(expired.utf8))])
        let store = ClaudeCredentialStore(runner: runner, environment: [:], homeDirectory: URL(fileURLWithPath: "/h"),
                                          userName: "me", readFile: { _ in expired })
        guard case .found(let credential) = await store.read(now: referenceNow) else {
            Issue.record("expected credentials")
            return
        }
        #expect(credential.source == .keychain)
        #expect(credential.isExpired(now: referenceNow))
    }

    @Test func deniedKeychainWithoutFile() async {
        let runner = FakeRunner([CommandResult(status: 51, stdout: Data())])
        let store = ClaudeCredentialStore(runner: runner, environment: [:], homeDirectory: URL(fileURLWithPath: "/h"),
                                          userName: "me", readFile: { _ in nil })
        #expect(await store.read(now: referenceNow) == .accessDenied)
    }

    @Test func nothingAnywhere() async {
        let store = ClaudeCredentialStore(runner: FakeRunner([]), environment: [:],
                                          homeDirectory: URL(fileURLWithPath: "/h"), userName: "me",
                                          readFile: { _ in nil })
        #expect(await store.read(now: referenceNow) == .notFound)
    }

    @Test func configDirectoryChangesServiceAndFile() {
        let store = ClaudeCredentialStore(runner: FakeRunner([]), environment: ["CLAUDE_CONFIG_DIR": "/tmp/claude-a"],
                                          homeDirectory: URL(fileURLWithPath: "/h"), userName: "me")
        #expect(store.credentialsFile.path == "/tmp/claude-a/.credentials.json")
        #expect(store.keychainServices.count == 2)
        #expect(store.keychainServices[0].hasPrefix("Claude Code-credentials-"))
        #expect(store.keychainServices[0].count == "Claude Code-credentials-".count + 8)
        #expect(store.keychainServices[1] == "Claude Code-credentials")
    }
}

struct ClaudeCollectorTests {
    let valid = ClaudeCredentials.parse(Fixtures.claudeCredential(expiresAt: referenceNow.addingTimeInterval(3600)),
                                        source: .keychain)!

    func collector(_ lookup: ClaudeCredentialLookup, _ transport: FakeTransport) -> ClaudeCollector {
        ClaudeCollector(credentials: FixedCredentials(lookup: lookup), transport: transport,
                        userAgent: { "claude-code/2.1.280" })
    }

    @Test func readsUsageWithTheExpectedRequest() async throws {
        let transport = FakeTransport([.response(status: 200, body: Fixtures.claudeUsage)])
        let usage = await collector(.found(valid), transport).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.plan == "Max 20x")
        #expect(usage.windows.count == 3)
        #expect(usage.fetchedAt == referenceNow)

        let request = try #require(transport.requests.first)
        #expect(request.url == ClaudeCollector.usageURL)
        #expect(request.timeoutInterval == 10)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ant-oat01-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "claude-code/2.1.280")
    }

    @Test func expiredTokenNeverHitsTheNetwork() async {
        var expired = valid
        expired.expiresAt = referenceNow.addingTimeInterval(60)
        let transport = FakeTransport()
        let usage = await collector(.found(expired), transport).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .sessionExpired)
        #expect(transport.requests.isEmpty)
    }

    @Test func unauthorizedKeepsPreviousNumbers() async throws {
        let first = FakeTransport([.response(status: 200, body: Fixtures.claudeUsage)])
        let good = await collector(.found(valid), first).fetch(previous: nil, now: referenceNow)

        let later = referenceNow.addingTimeInterval(300)
        let usage = await collector(.found(valid), FakeTransport([.response(status: 401, body: "{}")]))
            .fetch(previous: good, now: later)
        #expect(usage.problem == .sessionExpired)
        #expect(usage.windows == good.windows)
        #expect(usage.fetchedAt == referenceNow)
    }

    @Test func rateLimitHonoursRetryAfterAndSkipsEarlyRetries() async {
        let transport = FakeTransport([.response(status: 429, body: "", headers: ["Retry-After": "120"])])
        let limited = await collector(.found(valid), transport).fetch(previous: nil, now: referenceNow)
        #expect(limited.problem == .rateLimited(retryAfter: referenceNow.addingTimeInterval(120)))

        let early = FakeTransport([.response(status: 200, body: Fixtures.claudeUsage)])
        let skipped = await collector(.found(valid), early).fetch(previous: limited,
                                                                  now: referenceNow.addingTimeInterval(60))
        #expect(skipped == limited)
        #expect(early.requests.isEmpty)

        let recovered = await collector(.found(valid), early).fetch(previous: limited,
                                                                    now: referenceNow.addingTimeInterval(121))
        #expect(recovered.problem == nil)
        #expect(early.requests.count == 1)
    }

    @Test func rateLimitWithoutHeaderWaitsFiveMinutes() async {
        let transport = FakeTransport([.response(status: 429, body: "")])
        let usage = await collector(.found(valid), transport).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .rateLimited(retryAfter: referenceNow.addingTimeInterval(300)))
    }

    @Test func missingProfileScopeExplainsItself() async {
        var limited = valid
        limited.scopes = ["user:inference"]
        let transport = FakeTransport()
        let usage = await collector(.found(limited), transport).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .notSignedIn)
        #expect(usage.problemDetail?.contains("user:profile") == true)
        #expect(transport.requests.isEmpty)
    }

    @Test func noCredentialsOrDenied() async {
        let notFound = await collector(.notFound, FakeTransport()).fetch(previous: nil, now: referenceNow)
        #expect(notFound.problem == .notSignedIn)
        #expect(notFound.windows.isEmpty)
        let denied = await collector(.accessDenied, FakeTransport()).fetch(previous: nil, now: referenceNow)
        #expect(denied.problem == .accessDenied)
    }

    @Test func networkAndShapeFailures() async {
        let offline = await collector(.found(valid), FakeTransport([.failure(.notConnectedToInternet)]))
            .fetch(previous: nil, now: referenceNow)
        #expect(offline.problem == .unreachable("Offline"))
        let server = await collector(.found(valid), FakeTransport([.response(status: 503, body: "")]))
            .fetch(previous: nil, now: referenceNow)
        #expect(server.problem == .unreachable("HTTP 503"))
        let changed = await collector(.found(valid), FakeTransport([.response(status: 200, body: "{}")]))
            .fetch(previous: nil, now: referenceNow)
        if case .unexpectedResponse = changed.problem {} else { Issue.record("expected unexpectedResponse") }
    }
}
