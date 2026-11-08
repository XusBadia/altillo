import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

struct ClaudeMapperTests {
    @Test func mapsWindowsAndScopedLimits() throws {
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
    }

    @Test func nullSessionMeansNotStartedAndEpochResets() throws {
        let mapped = try #require(ClaudeUsageMapper.map(Data(Fixtures.claudeUsageNoSession.utf8)))
        #expect(mapped.windows.map(\.id) == ["session", "weekly", "weekly-sonnet"])
        #expect(mapped.windows[0].used == 0)
        #expect(mapped.windows[0].resetsAt == nil)
        #expect(mapped.windows[1].resetsAt == Date(timeIntervalSince1970: 1_790_650_800))
        #expect(mapped.windows[2].resetsAt == Date(timeIntervalSince1970: 1_790_650_800)) // milliseconds
    }

    @Test func missingResetMeansNotStarted() throws {
        let mapped = try #require(ClaudeUsageMapper.map(Data(Fixtures.claudeUsageSessionNotStarted.utf8)))
        #expect(mapped.windows.allSatisfy { $0.resetsAt == nil })
        #expect(mapped.windows.map(\.used) == [0, 0.2])
    }

    @Test func rejectsExtraUsageWithoutQuotas() {
        let payload = #"{"extra_usage":{"is_enabled":true,"used_credits":1250,"monthly_limit":5000}}"#
        #expect(ClaudeUsageMapper.map(Data(payload.utf8)) == nil)
    }

    @Test(arguments: ["{}", "[]", "false", "42", #""invalid""#, #"{"utilization":"invalid"}"#,
                      #"{"utilization":null}"#, #"{"utilization":true}"#])
    func malformedSessionNeverBecomesZero(_ session: String) throws {
        #expect(ClaudeUsageMapper.map(Data("{\"five_hour\":\(session)}".utf8)) == nil)
        let payload = "{\"five_hour\":\(session),\"seven_day\":{\"utilization\":20}}"
        let mapped = try #require(ClaudeUsageMapper.map(Data(payload.utf8)))
        #expect(mapped.windows.map(\.id) == ["weekly"])
        #expect(mapped.windows[0].used == 0.2)
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

    @Test func appOwnedCredentialsAreAvailableWithoutClaudeCodeAndUseOnlyInjectedToken() async throws {
        var credential = valid
        credential.accessToken = "altillo-owned-claude-token"
        let transport = FakeTransport([.response(status: 200, body: Fixtures.claudeUsage)])
        let own = ClaudeCollector(credentials: FixedCredentials(lookup: .found(credential)), transport: transport,
                                  availability: { true }, usesOwnAccount: true)
        #expect(await own.isAvailable())
        #expect(own.setupHint == "Connect your Claude account in Altillo Settings")
        #expect(await own.fetch(previous: nil, now: referenceNow).problem == nil)
        let request = try #require(transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer altillo-owned-claude-token")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Altillo")
        let disconnected = ClaudeCollector(credentials: FixedCredentials(lookup: .found(credential)),
                                           availability: { false }, usesOwnAccount: true)
        #expect(await !disconnected.isAvailable(), "own account availability overrides local CLI installation")
    }

    @Test func appOwnedCredentialFailuresPointToAltilloAndNeverTheCLI() async {
        for lookup in [ClaudeCredentialLookup.notFound, .accessDenied] {
            let own = ClaudeCollector(credentials: FixedCredentials(lookup: lookup), transport: FakeTransport(),
                                      availability: { true }, usesOwnAccount: true)
            let usage = await own.fetch(previous: nil, now: referenceNow)
            #expect(usage.problemDetail?.contains("Altillo") == true)
            #expect(usage.problemDetail?.contains("Claude Code") == false)
        }
        var expired = valid
        expired.expiresAt = referenceNow
        for transport in [FakeTransport(), FakeTransport([.response(status: 401, body: "")])] {
            let own = ClaudeCollector(credentials: FixedCredentials(lookup: .found(expired)), transport: transport,
                                      availability: { true }, usesOwnAccount: true)
            let usage = await own.fetch(previous: nil, now: referenceNow)
            #expect(usage.problem == .sessionExpired)
            #expect(usage.problemDetail == "Reconnect your Claude account in Altillo Settings.")
            #expect(transport.requests.isEmpty)
        }
        let unauthorized = ClaudeCollector(credentials: FixedCredentials(lookup: .found(valid)),
                                           transport: FakeTransport([.response(status: 401, body: "")]),
                                           userAgent: { "Altillo" }, availability: { true }, usesOwnAccount: true)
        #expect(await unauthorized.fetch(previous: nil, now: referenceNow).problemDetail
                == "Reconnect your Claude account in Altillo Settings.")
    }

    @Test func ownAccount401RefreshesOnceAndReReadsTheRotatedCredential() async throws {
        let credentials = RotatingClaudeCredentials(valid)
        let refreshes = Locked(0)
        let transport = FakeTransport([.response(status: 401, body: ""),
                                       .response(status: 200, body: Fixtures.claudeUsage)])
        let own = ClaudeCollector(credentials: credentials, transport: transport,
                                  availability: { true }, usesOwnAccount: true, refreshAfterUnauthorized: {
            refreshes.withLock { $0 += 1 }
            credentials.rotate(to: "rotated-token")
        })
        let usage = await own.fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(refreshes.withLock { $0 } == 1)
        #expect(transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }
                == ["Bearer sk-ant-oat01-test", "Bearer rotated-token"])
    }

    @Test func ownAccountDoesNotLoopOnRejectedRefreshedTokenOrRefreshForbidden() async {
        for status in [401, 403] {
            let refreshes = Locked(0)
            let transport = FakeTransport([.response(status: status, body: ""),
                                           .response(status: 401, body: "")])
            let own = ClaudeCollector(credentials: FixedCredentials(lookup: .found(valid)), transport: transport,
                                      availability: { true }, usesOwnAccount: true, refreshAfterUnauthorized: {
                refreshes.withLock { $0 += 1 }
            })
            let usage = await own.fetch(previous: nil, now: referenceNow)
            #expect(usage.problem == .sessionExpired)
            #expect(refreshes.withLock { $0 } == (status == 401 ? 1 : 0))
            #expect(transport.requests.count == (status == 401 ? 2 : 1))
        }
    }

    @Test func ownAccountRefreshNetworkFailureKeepsNumbersAndDoesNotDemandReconnect() async {
        let previous = ProviderUsage(id: .claude, displayName: "Claude", plan: "Pro",
                                     windows: [UsageWindow(id: "weekly", kind: .weekly, label: "Week", used: 0.4,
                                                           resetsAt: nil, duration: nil)], fetchedAt: referenceNow)
        let transport = FakeTransport([.response(status: 401, body: "")])
        let own = ClaudeCollector(credentials: FixedCredentials(lookup: .found(valid)), transport: transport,
                                  availability: { true }, usesOwnAccount: true, refreshAfterUnauthorized: {
            throw URLError(.notConnectedToInternet)
        })
        let usage = await own.fetch(previous: previous, now: referenceNow.addingTimeInterval(100))
        #expect(usage.problem == .unreachable("Account authorization temporarily unavailable"))
        #expect(usage.windows == previous.windows)
        #expect(usage.fetchedAt == previous.fetchedAt)
        #expect(usage.problemDetail == nil)
        #expect(transport.requests.count == 1)
    }

    @Test func ownCredentialLookupDistinguishesRevokedFromTransientRefreshFailure() async {
        let transport = FakeTransport()
        for (lookup, problem) in [(ClaudeCredentialLookup.sessionExpired, UsageProblem.sessionExpired),
                                   (.temporarilyUnavailable, .unreachable("Account authorization temporarily unavailable"))] {
            let own = ClaudeCollector(credentials: FixedCredentials(lookup: lookup), transport: transport,
                                      availability: { true }, usesOwnAccount: true)
            #expect(await own.fetch(previous: nil, now: referenceNow).problem == problem)
        }
        #expect(transport.requests.isEmpty)
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

    @Test func malformedSessionKeepsPreviousUsageAsStale() async {
        let good = await collector(.found(valid), FakeTransport([.response(status: 200, body: Fixtures.claudeUsage)]))
            .fetch(previous: nil, now: referenceNow)
        for body in [#"{"five_hour":{"utilization":"invalid"}}"#,
                     #"{"extra_usage":{"is_enabled":true,"used_credits":1250}}"#] {
            let usage = await collector(.found(valid), FakeTransport([.response(status: 200, body: body)]))
                .fetch(previous: good, now: referenceNow.addingTimeInterval(300))
            #expect(usage.problem == .unexpectedResponse("Claude usage response changed shape"))
            #expect(usage.windows == good.windows)
            #expect(usage.fetchedAt == good.fetchedAt)
        }
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

private final class RotatingClaudeCredentials: ClaudeCredentialReading, Sendable {
    private let credential: Locked<ClaudeCredentials>
    init(_ credential: ClaudeCredentials) { self.credential = Locked(credential) }
    func read(now: Date) async -> ClaudeCredentialLookup { .found(credential.withLock { $0 }) }
    func rotate(to token: String) { credential.withLock { $0.accessToken = token } }
}

struct ClaudeLivePlanTests {
    @Test func organizationProfileUsesCurrentPlanNames() {
        #expect(ClaudeUsageMapper.livePlan(subscriptionType: "claude_pro", rateLimitTier: nil) == "Pro")
        #expect(ClaudeUsageMapper.livePlan(subscriptionType: "claude_max", rateLimitTier: "default_claude_max_5x") == "Max")
        #expect(ClaudeUsageMapper.livePlan(subscriptionType: "claude_max", rateLimitTier: "default_claude_max_20x") == "Ultra")
        #expect(ClaudeUsageMapper.livePlan(subscriptionType: "claude_ultra", rateLimitTier: nil) == "Ultra")
        #expect(ClaudeUsageMapper.livePlan(subscriptionType: "claude_enterprise", rateLimitTier: nil) == "Enterprise")
        #expect(ClaudeUsageMapper.livePlan(subscriptionType: "claude_", rateLimitTier: nil) == nil)
    }
}
