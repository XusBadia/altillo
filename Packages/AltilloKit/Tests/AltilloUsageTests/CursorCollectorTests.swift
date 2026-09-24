import AltilloCore
import Foundation
import SQLite3
import Testing
@testable import AltilloUsage

// MARK: - Fixtures

enum CursorFixtures {
    /// Pro plan, shape from openusage's CursorProviderTests (anonymized).
    static let proUsage = """
    {"enabled": true, "billingCycleStart": "1788220800000", "billingCycleEnd": "1790899200000",
     "planUsage": {"limit": 40000, "remaining": 32000, "totalPercentUsed": 20, "autoPercentUsed": 12.5,
                   "apiPercentUsed": 7.5},
     "spendLimitUsage": {"individualLimit": 5000, "individualRemaining": 1000}}
    """
    static let planInfo = #"{"planInfo":{"planName":"pro plan"}}"#
    static let grokBot = """
    {"usagePercent": 37.5, "currentPeriodStart": "2026-09-20T00:00:00Z",
     "nextResetTimestampUtc": "2026-09-27T00:00:00Z", "hasNonZeroIncludedLimit": true}
    """
    static let noGrants = #"{"hasCreditGrants":false}"#
    static let grants = #"{"hasCreditGrants":true,"totalCents":2000,"usedCents":500}"#
    static let stripeCredit = #"{"customerBalance":"-50000"}"#

    static let teamUsage = """
    {"enabled": true, "billingCycleEnd": 1790899200000,
     "planUsage": {"limit": 4000000, "totalSpend": 1000000},
     "spendLimitUsage": {"limitType": "team", "pooledLimit": 500000, "pooledUsed": 50000}}
    """

    /// Enterprise: no usable planUsage; the dashboard REST endpoints carry the numbers (openusage's
    /// CursorUsageSummaryTests shape).
    static let enterpriseUsage = #"{"enabled": true, "planUsage": {"autoPercentUsed": 0}}"#
    static let enterpriseSummary = """
    {"billingCycleStart": "2026-09-01T00:00:00.000Z", "billingCycleEnd": "2026-10-01T00:00:00.000Z",
     "membershipType": "enterprise", "limitType": "team",
     "individualUsage": {"plan": {"enabled": true, "limit": 0, "autoPercentUsed": 0, "apiPercentUsed": 6.25,
                                  "totalPercentUsed": 6.25},
                         "onDemand": {"enabled": true, "used": 0, "limit": 25000, "remaining": 25000}},
     "teamUsage": {"onDemand": {"enabled": true, "used": 75000, "limit": 600000, "remaining": 525000}}}
    """
    static let enterpriseRequests = """
    {"gpt-4": {"numRequests": 37, "numRequestsTotal": 37, "maxRequestUsage": 750},
     "startOfMonth": "2026-09-01T00:00:00.000Z"}
    """
}

// MARK: - Mapping

struct CursorMapperTests {
    @Test func mapsProPlanUsageAndOnDemand() throws {
        let usage = try #require(UsageParsing.object(Data(CursorFixtures.proUsage.utf8)))
        let mapped = try #require(CursorUsageMapper.mapPlanUsage(usage, planName: "pro plan"))
        #expect(mapped.windows.map(\.id) == ["total", "auto", "api"])
        #expect(mapped.windows.allSatisfy { $0.kind == .monthly })
        #expect(mapped.windows[0].label == "Month")
        #expect(mapped.windows[0].used == 0.2)
        #expect(mapped.windows[0].resetsAt == Date(timeIntervalSince1970: 1_790_899_200))
        #expect(mapped.windows[0].duration == TimeInterval(1_790_899_200 - 1_788_220_800))
        #expect(mapped.windows[1].used == 0.125)
        #expect(mapped.windows[2].used == 0.075)
        // No reported spend: inferred from limit − remaining (cents → USD).
        #expect(mapped.balances == [UsageBalance(id: "on-demand", label: "On-demand", remaining: 10, used: 40,
                                                 limit: 50, unit: "USD")])
    }

    @Test func teamPlanUsesPooledSpend() throws {
        let usage = try #require(UsageParsing.object(Data(CursorFixtures.teamUsage.utf8)))
        let mapped = try #require(CursorUsageMapper.mapPlanUsage(usage, planName: "Team"))
        #expect(mapped.windows.map(\.id) == ["total"])
        #expect(mapped.windows[0].used == 0.25)
        #expect(mapped.windows[0].duration == CursorUsageMapper.defaultCycle)
        #expect(mapped.balances.first?.used == 500)
        #expect(mapped.balances.first?.limit == 5000)
    }

    @Test func unusablePlanUsageNeedsTheDashboard() throws {
        let usage = try #require(UsageParsing.object(Data(CursorFixtures.enterpriseUsage.utf8)))
        #expect(CursorUsageMapper.mapPlanUsage(usage, planName: "Enterprise") == nil)
        #expect(CursorUsageMapper.prefersDashboardSummary(usage, planName: "Enterprise", planInfoMissing: false))
        let pro = try #require(UsageParsing.object(Data(CursorFixtures.proUsage.utf8)))
        #expect(!CursorUsageMapper.prefersDashboardSummary(pro, planName: "Pro", planInfoMissing: false))
    }

    @Test func mapsEnterpriseDashboard() throws {
        let summary = UsageParsing.object(Data(CursorFixtures.enterpriseSummary.utf8))
        let requests = UsageParsing.object(Data(CursorFixtures.enterpriseRequests.utf8))
        let mapped = try #require(CursorUsageMapper.mapDashboard(summary: summary, requests: requests))
        #expect(mapped.windows.map(\.id) == ["requests", "auto", "api"])
        #expect(abs(mapped.windows[0].used - 37.0 / 750) < 1e-9)
        #expect(mapped.windows[0].resetsAt == iso("2026-10-01T00:00:00Z"))
        #expect(mapped.windows[0].duration == TimeInterval(30 * 86400))
        #expect(mapped.windows[2].used == 0.0625)
        // The individual bucket wins over the team aggregate.
        #expect(mapped.balances == [UsageBalance(id: "on-demand", label: "On-demand", remaining: 250, used: 0,
                                                 limit: 250, unit: "USD")])
    }

    @Test func dashboardFallsBackToPooledTotal() throws {
        let summary: [String: Any] = ["limitType": "team", "teamUsage": [
            "pooled": ["enabled": true, "used": 125_000, "limit": 4_000_000],
            "onDemand": ["enabled": true, "used": 50_000, "limit": 500_000],
        ]]
        let mapped = try #require(CursorUsageMapper.mapDashboard(summary: summary, requests: nil))
        #expect(mapped.windows.map(\.id) == ["total"])
        #expect(mapped.windows[0].used == 0.03125)
        #expect(mapped.balances.first?.used == 500)
        #expect(CursorUsageMapper.mapDashboard(summary: [:], requests: nil) == nil)
    }

    @Test func grokBotAndCredits() throws {
        let grokBody = try #require(UsageParsing.object(Data(CursorFixtures.grokBot.utf8)))
        let grok = try #require(CursorUsageMapper.grokBotWindow(grokBody))
        #expect(grok.id == "grok-bot")
        #expect(grok.kind == .other)
        #expect(grok.used == 0.375)
        #expect(grok.duration == TimeInterval(7 * 86400))
        #expect(CursorUsageMapper.grokBotWindow(["usagePercent": 10, "usesPooledEnterpriseAllowance": true]) == nil)

        let stripe = UsageParsing.object(Data(CursorFixtures.stripeCredit.utf8))
        let grants = UsageParsing.object(Data(CursorFixtures.grants.utf8))
        #expect(CursorUsageMapper.credits(grants: nil, stripe: stripe)
            == UsageBalance(id: "credits", label: "Credits", remaining: 500, used: 0, limit: 500, unit: "USD"))
        #expect(CursorUsageMapper.credits(grants: grants, stripe: stripe)
            == UsageBalance(id: "credits", label: "Credits", remaining: 515, used: 5, limit: 520, unit: "USD"))
        #expect(CursorUsageMapper.credits(grants: ["hasCreditGrants": false], stripe: ["customerBalance": 100]) == nil)
    }

    @Test func formatsPlans() {
        #expect(CursorUsageMapper.plan("pro plan") == "Pro Plan")
        #expect(CursorUsageMapper.plan("free_trial") == "Free Trial")
        #expect(CursorUsageMapper.plan("  ") == nil)
    }
}

// MARK: - Collector

struct CursorCollectorTests {
    let token = cursorJWT(sub: "auth0|user_abc123", expires: referenceNow.addingTimeInterval(30 * 86400))

    func collector(_ lookup: CursorCredentialLookup, _ transport: RoutedTransport) -> CursorCollector {
        CursorCollector(credentials: FixedCursorCredentials(lookup: lookup), transport: transport)
    }

    var credential: CursorCredentials { CursorCredentials(accessToken: token, membershipType: "pro", source: .stateDatabase) }

    @Test func readsFullUsage() async throws {
        let transport = RoutedTransport([
            ("GetCurrentPeriodUsage", .response(status: 200, body: CursorFixtures.proUsage)),
            ("GetPlanInfo", .response(status: 200, body: CursorFixtures.planInfo)),
            ("GetCreditGrantsBalance", .response(status: 200, body: CursorFixtures.noGrants)),
            ("GetSandUsageStatus", .response(status: 200, body: CursorFixtures.grokBot)),
            ("/api/auth/stripe", .response(status: 200, body: CursorFixtures.stripeCredit)),
        ])
        let usage = await collector(.found(credential), transport).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.plan == "Pro Plan")
        #expect(usage.windows.map(\.id) == ["total", "auto", "api", "grok-bot"])
        #expect(usage.balances.map(\.id) == ["on-demand", "credits"])

        let rpc = try #require(transport.requests.first { $0.url?.lastPathComponent == "GetCurrentPeriodUsage" })
        #expect(rpc.httpMethod == "POST")
        #expect(rpc.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
        #expect(rpc.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
        #expect(rpc.httpBody == Data("{}".utf8))
        #expect(rpc.timeoutInterval <= 10)
        let stripe = try #require(transport.requests.first { $0.url?.path == "/api/auth/stripe" })
        #expect(stripe.value(forHTTPHeaderField: "Cookie") == "WorkosCursorSessionToken=user_abc123%3A%3A\(token)")
        // Never the token endpoint: Altillo doesn't refresh Cursor's sign-in.
        #expect(!transport.requests.contains { $0.url?.path.contains("oauth") == true })
    }

    @Test func optionalEndpointsFailingKeepTheMeters() async {
        let transport = RoutedTransport([
            ("GetCurrentPeriodUsage", .response(status: 200, body: CursorFixtures.proUsage)),
        ]) // everything else fails to connect
        let usage = await collector(.found(credential), transport).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.plan == "Pro") // from Cursor's stored membership
        #expect(usage.windows.map(\.id) == ["total", "auto", "api"])
        #expect(usage.balances.map(\.id) == ["on-demand"])
    }

    @Test func enterpriseUsesDashboardRESTEndpoints() async throws {
        let transport = RoutedTransport([
            ("GetCurrentPeriodUsage", .response(status: 200, body: CursorFixtures.enterpriseUsage)),
            ("GetPlanInfo", .response(status: 200, body: #"{"planInfo":{"planName":"Enterprise"}}"#)),
            ("usage-summary", .response(status: 200, body: CursorFixtures.enterpriseSummary)),
            ("cursor.com/api/usage", .response(status: 200, body: CursorFixtures.enterpriseRequests)),
        ])
        let usage = await collector(.found(credential), transport).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.plan == "Enterprise")
        #expect(usage.windows.first?.id == "requests")
        let rest = try #require(transport.requests.first { $0.url?.path == "/api/usage" })
        #expect(rest.url?.query == "user=user_abc123")
    }

    @Test func expiredTokenNeverTouchesTheNetwork() async {
        let expired = CursorCredentials(accessToken: cursorJWT(sub: "auth0|u", expires: referenceNow.addingTimeInterval(-60)),
                                        membershipType: "pro", source: .stateDatabase)
        let transport = RoutedTransport([])
        let usage = await collector(.found(expired), transport).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .sessionExpired)
        #expect(usage.problemDetail == "Open Cursor once to renew its sign-in.")
        #expect(usage.plan == "Pro")
        #expect(transport.requests.isEmpty)
    }

    @Test func unauthorizedKeepsPreviousWindows() async {
        let previous = ProviderUsage(id: .cursor, displayName: "Cursor", plan: "Pro", windows: [
            UsageWindow(id: "total", kind: .monthly, label: "Month", used: 0.4, resetsAt: nil, duration: nil),
        ], fetchedAt: referenceNow.addingTimeInterval(-600))
        let transport = RoutedTransport([("GetCurrentPeriodUsage", .response(status: 401, body: "{}"))])
        let usage = await collector(.found(credential), transport).fetch(previous: previous, now: referenceNow)
        #expect(usage.problem == .sessionExpired)
        #expect(usage.windows == previous.windows)
        #expect(usage.fetchedAt == previous.fetchedAt)
    }

    @Test func rateLimitHonoursRetryAfter() async {
        let transport = RoutedTransport([
            ("GetCurrentPeriodUsage", .response(status: 429, body: "", headers: ["Retry-After": "120"])),
        ])
        let first = await collector(.found(credential), transport).fetch(previous: nil, now: referenceNow)
        #expect(first.problem == .rateLimited(retryAfter: referenceNow.addingTimeInterval(120)))
        let again = await collector(.found(credential), transport).fetch(previous: first,
                                                                          now: referenceNow.addingTimeInterval(60))
        #expect(again == first)
        #expect(transport.requests.count == 1)
    }

    @Test func missingSignInAndNoPlan() async {
        let missing = await collector(.notFound, RoutedTransport([])).fetch(previous: nil, now: referenceNow)
        #expect(missing.problem == .notSignedIn)
        #expect(missing.problemDetail == "Cursor isn't signed in on this Mac.")
        let denied = await collector(.accessDenied, RoutedTransport([])).fetch(previous: nil, now: referenceNow)
        #expect(denied.problem == .accessDenied)

        let disabled = RoutedTransport([("GetCurrentPeriodUsage", .response(status: 200, body: #"{"enabled":false}"#))])
        let usage = await collector(.found(credential), disabled).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .notSignedIn)

        let garbage = RoutedTransport([("GetCurrentPeriodUsage", .response(status: 200, body: "[]"))])
        let odd = await collector(.found(credential), garbage).fetch(previous: nil, now: referenceNow)
        #expect(odd.problem == .unexpectedResponse("Cursor usage response changed shape"))

        let down = RoutedTransport([("GetCurrentPeriodUsage", .response(status: 503, body: ""))])
        #expect(await collector(.found(credential), down).fetch(previous: nil, now: referenceNow).problem
            == .unreachable("HTTP 503"))
    }
}

// MARK: - Credentials and state database

struct CursorCredentialTests {
    @Test func readsTokenFromStateDatabase() async throws {
        let token = cursorJWT(sub: "auth0|user_a", expires: referenceNow.addingTimeInterval(86400))
        let database = try TemporaryCursorDatabase(values: [CursorCredentialStore.accessTokenKey: token,
                                                            CursorCredentialStore.membershipKey: "pro",
                                                            "cursorAuth/refreshToken": "never-read"])
        let keychain = Group1Keychain([:])
        let store = CursorCredentialStore(databaseURL: database.url, keychain: keychain)
        #expect(await store.exists())
        guard case .found(let credential) = await store.read(now: referenceNow) else {
            Issue.record("expected a credential")
            return
        }
        #expect(credential.accessToken == token)
        #expect(credential.membershipType == "pro")
        #expect(credential.source == .stateDatabase)
        #expect(credential.subject == "auth0|user_a")
        #expect(keychain.readCount == 0) // a usable paid database token never touches the keychain
    }

    @Test func freeDatabaseAccountDefersToADifferentCLIAccount() async throws {
        let desktop = cursorJWT(sub: "auth0|free_user", expires: referenceNow.addingTimeInterval(86400))
        let cli = cursorJWT(sub: "auth0|paid_user", expires: referenceNow.addingTimeInterval(86400))
        let database = try TemporaryCursorDatabase(values: [CursorCredentialStore.accessTokenKey: desktop,
                                                            CursorCredentialStore.membershipKey: "free"])
        let store = CursorCredentialStore(databaseURL: database.url,
                                          keychain: Group1Keychain(["cursor-access-token": .found(cli)]))
        #expect(await store.read(now: referenceNow)
            == .found(CursorCredentials(accessToken: cli, membershipType: nil, source: .keychain)))
    }

    @Test func expiredDatabaseTokenFallsBackToKeychainThenReportsExpired() async throws {
        let old = cursorJWT(sub: "auth0|u", expires: referenceNow.addingTimeInterval(-10))
        let fresh = cursorJWT(sub: "auth0|u", expires: referenceNow.addingTimeInterval(3600))
        let database = try TemporaryCursorDatabase(values: [CursorCredentialStore.accessTokenKey: old])
        let withCLI = CursorCredentialStore(databaseURL: database.url,
                                            keychain: Group1Keychain(["cursor-access-token": .found(fresh)]))
        #expect(await withCLI.read(now: referenceNow)
            == .found(CursorCredentials(accessToken: fresh, membershipType: nil, source: .keychain)))

        let alone = CursorCredentialStore(databaseURL: database.url, keychain: Group1Keychain([:]))
        guard case .found(let expired) = await alone.read(now: referenceNow) else {
            Issue.record("expected the expired credential")
            return
        }
        #expect(expired.isExpired(now: referenceNow))
    }

    @Test func missingEverywhere() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID()).vscdb")
        let store = CursorCredentialStore(databaseURL: url, keychain: Group1Keychain([:]))
        #expect(!(await store.exists()))
        #expect(await store.read(now: referenceNow) == .notFound)
        let denied = CursorCredentialStore(databaseURL: url, keychain: Group1Keychain(["cursor-access-token": .denied]))
        #expect(await denied.read(now: referenceNow) == .accessDenied)
    }

    @Test func readsThroughAnOpenWALWithoutDisturbingIt() throws {
        let database = try TemporaryCursorDatabase(values: ["seed": "1"], wal: true)
        // Cursor keeps a connection open; its latest write is still only in the WAL.
        let writer = try database.openWriter()
        defer { sqlite3_close(writer) }
        try database.write(writer, key: CursorCredentialStore.accessTokenKey, value: "\"quoted-token\"")
        let walPath = database.url.path + "-wal"
        #expect(FileManager.default.fileExists(atPath: walPath))
        let mainBefore = try Data(contentsOf: database.url)

        let values = CursorStateDatabase(url: database.url).values(for: [CursorCredentialStore.accessTokenKey, "absent"])
        #expect(values == [CursorCredentialStore.accessTokenKey: "quoted-token"]) // JSON string literal unwrapped

        #expect(FileManager.default.fileExists(atPath: walPath)) // not checkpointed away
        #expect(try Data(contentsOf: database.url) == mainBefore)
        try database.write(writer, key: "after", value: "still writable") // Cursor keeps working
    }

    @Test func blobValuesAndMissingTable() throws {
        let database = try TemporaryCursorDatabase(values: [:])
        let writer = try database.openWriter()
        defer { sqlite3_close(writer) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(writer, "INSERT INTO ItemTable (key, value) VALUES ('k', ?1)", -1, &statement, nil)
        let bytes = Array("blob-token".utf8)
        sqlite3_bind_blob(statement, 1, bytes, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        #expect(sqlite3_step(statement) == SQLITE_DONE)
        sqlite3_finalize(statement)
        #expect(CursorStateDatabase(url: database.url).values(for: ["k"]) == ["k": "blob-token"])

        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID()).vscdb")
        FileManager.default.createFile(atPath: empty.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(CursorStateDatabase(url: empty).values(for: ["k"]).isEmpty)
    }

    @Test func sessionCookieAndExpiry() {
        let credential = CursorCredentials(accessToken: cursorJWT(sub: "github|user_42", expires: referenceNow),
                                           membershipType: nil, source: .keychain)
        #expect(credential.sessionCookie?.hasPrefix("WorkosCursorSessionToken=user_42%3A%3A") == true)
        #expect(credential.isExpired(now: referenceNow))
        let opaque = CursorCredentials(accessToken: "not-a-jwt", membershipType: nil, source: .keychain)
        #expect(!opaque.isExpired(now: referenceNow)) // unknown expiry: try it
        #expect(opaque.sessionCookie == nil)
    }
}

// MARK: - Shared helpers for the Cursor / Copilot / OpenRouter / Z.ai tests

/// Answers by URL substring (first match wins), so concurrent requests get the right reply; unmatched URLs fail to
/// connect. Records every request.
final class RoutedTransport: HTTPTransport, @unchecked Sendable {
    private let routes: [(String, FakeTransport.Reply)]
    private let recorded = Locked<[URLRequest]>([])

    init(_ routes: [(String, FakeTransport.Reply)]) { self.routes = routes }

    var requests: [URLRequest] { recorded.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.withLock { $0.append(request) }
        let url = request.url!.absoluteString
        guard let reply = routes.first(where: { url.contains($0.0) })?.1 else { throw URLError(.cannotConnectToHost) }
        switch reply {
        case .response(let status, let body, let headers):
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                                     headerFields: headers)!)
        case .failure(let code):
            throw URLError(code)
        }
    }
}

/// Keychain items by service (account ignored); counts secret reads.
final class Group1Keychain: KeychainSecretReading, @unchecked Sendable {
    private let items: [String: KeychainSecretLookup]
    private let reads = Locked<[String?]>([])

    init(_ items: [String: KeychainSecretLookup]) { self.items = items }

    var readCount: Int { reads.withLock { $0.count } }
    var accounts: [String?] { reads.withLock { $0 } }

    func secret(service: String, account: String?) async -> KeychainSecretLookup {
        reads.withLock { $0.append(account) }
        return items[service] ?? .notFound
    }

    func contains(service: String, account: String?) async -> Bool {
        if case .found = items[service] ?? .notFound { return true }
        return false
    }
}

struct FixedCursorCredentials: CursorCredentialReading {
    var lookup: CursorCredentialLookup
    func exists() async -> Bool { lookup != .notFound }
    func read(now: Date) async -> CursorCredentialLookup { lookup }
}

/// An unsigned JWT with `sub` and `exp`.
func cursorJWT(sub: String, expires: Date) -> String {
    func encode(_ json: String) -> String {
        Data(json.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    return encode(#"{"alg":"none","typ":"JWT"}"#) + "."
        + encode(#"{"sub":"\#(sub)","exp":\#(Int(expires.timeIntervalSince1970))}"#) + ".sig"
}

/// A VS Code–style state database in a temporary directory.
final class TemporaryCursorDatabase {
    let directory: URL
    let url: URL

    init(values: [String: String], wal: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-state-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("state with space.vscdb")
        let db = try openWriter()
        defer { sqlite3_close(db) }
        if wal { sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil) }
        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)",
                     nil, nil, nil)
        for (key, value) in values { try write(db, key: key, value: value) }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func openWriter() throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let db else { throw CocoaError(.fileWriteUnknown) }
        sqlite3_exec(db, "PRAGMA wal_autocheckpoint=0", nil, nil, nil)
        return db
    }

    func write(_ db: OpaquePointer, key: String, value: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO ItemTable (key, value) VALUES (?1, ?2)", -1, &statement, nil)
            == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        sqlite3_bind_text(statement, 2, value, -1, transient)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw CocoaError(.fileWriteUnknown) }
    }
}
