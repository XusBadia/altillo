import AltilloCore
import Foundation
import SQLite3
import Testing
@testable import AltilloUsage

enum DevinFixtures {
    /// openusage's DevinProviderTests `makeUserStatus()`.
    static let userStatus = """
    {"userStatus":{"planStatus":{
      "planInfo":{"planName":"Max","billingStrategy":"BILLING_STRATEGY_QUOTA"},
      "dailyQuotaRemainingPercent":100,"weeklyQuotaRemainingPercent":40,
      "overageBalanceMicros":"964220000",
      "dailyQuotaResetAtUnix":"1774080000","weeklyQuotaResetAtUnix":"1774166400"}}}
    """

    static let hiddenDaily = """
    {"userStatus":{"planStatus":{"planInfo":{"planName":"Pro","hideDailyQuota":true},
      "dailyQuotaRemainingPercent":30,"weeklyQuotaRemainingPercent":75,"weeklyQuotaResetAtUnix":1774166400}}}
    """
}

struct FixedSQLite: SQLiteValueReading {
    var values: [String: String]
    func value(database: URL, sql: String) async -> String? { values[database.path] }
}

struct DevinMapperTests {
    @Test func mapsQuotasAndOverageBalance() throws {
        let mapped = try #require(DevinUsageMapper.map(Data(DevinFixtures.userStatus.utf8)))
        #expect(mapped.plan == "Max")
        #expect(mapped.windows.map(\.id) == ["weekly", "daily"])
        #expect(mapped.windows[0].kind == .weekly)
        #expect(mapped.windows[0].used == 0.6) // 40 % remaining
        #expect(mapped.windows[0].resetsAt == Date(timeIntervalSince1970: 1_774_166_400))
        #expect(mapped.windows[0].duration == TimeInterval(7 * 86400))
        #expect(mapped.windows[1].used == 0)
        #expect(mapped.windows[1].label == "Day")
        #expect(mapped.windows[1].duration == TimeInterval(86400))
        #expect(mapped.balances == [UsageBalance(id: "extra-usage", label: "Extra usage", remaining: 964.22,
                                                 used: nil, limit: nil, unit: "USD")])
    }

    @Test func hiddenDailyQuotaStaysHidden() throws {
        let mapped = try #require(DevinUsageMapper.map(Data(DevinFixtures.hiddenDaily.utf8)))
        #expect(mapped.windows.map(\.id) == ["weekly"])
        #expect(mapped.windows[0].used == 0.25)
        #expect(mapped.balances.isEmpty)

        let onlyDaily = #"{"userStatus":{"planStatus":{"planInfo":{"hideDailyQuota":true},"dailyQuotaRemainingPercent":30}}}"#
        let fallback = try #require(DevinUsageMapper.map(Data(onlyDaily.utf8)))
        #expect(fallback.windows.map(\.id) == ["daily"])
        #expect(fallback.windows[0].used == 0.7)
        #expect(fallback.plan == nil)
    }

    @Test func zeroBalanceIsARealZeroAndEmptyStatusIsNil() throws {
        let zero = #"{"userStatus":{"planStatus":{"overageBalanceMicros":"0"}}}"#
        #expect(try #require(DevinUsageMapper.map(Data(zero.utf8))).balances.first?.remaining == 0)
        #expect(DevinUsageMapper.map(Data(#"{"userStatus":{"planStatus":{}}}"#.utf8)) == nil)
        #expect(DevinUsageMapper.map(Data("{}".utf8)) == nil)
    }
}

struct DevinCredentialTests {
    @Test func readsCredentialsToml() {
        let toml = """
        # Devin CLI
        windsurf_api_key = "sk-ws-01-test"   # key
        api_server_url = 'https://eu.server.example.com/'
        """
        let credential = DevinCredential.parseCredentialsFile(toml)
        #expect(credential?.apiKey == "sk-ws-01-test")
        #expect(credential?.server.absoluteString == "https://eu.server.example.com")
        #expect(credential?.source == .cli)

        let bare = DevinCredential.parseCredentialsFile("windsurf_api_key = sk-bare # comment\napi_server_url = http://x")
        #expect(bare?.apiKey == "sk-bare")
        #expect(bare?.server == DevinCredential.defaultServer) // plain http is never used
        #expect(DevinCredential.parseCredentialsFile("other = 1") == nil)
        #expect(DevinCredential.parseCredentialsFile(#"windsurf_api_key = """#) == nil)
    }

    @Test func readsAppAuthStatus() {
        #expect(DevinCredential.parseAppAuthStatus(#"{"apiKey":"sk-app","name":"Someone"}"#)?.apiKey == "sk-app")
        #expect(DevinCredential.parseAppAuthStatus(#"{"apiKey":""}"#) == nil)
        #expect(DevinCredential.parseAppAuthStatus("null") == nil)
    }

    @Test func standardLocations() {
        let locations = DevinCredentialLocations.standard(home: URL(fileURLWithPath: "/Users/someone"))
        #expect(locations.credentialsFile.path == "/Users/someone/.local/share/devin/credentials.toml")
        #expect(locations.stateDatabases.map(\.path) == [
            "/Users/someone/Library/Application Support/Devin/User/globalStorage/state.vscdb",
            "/Users/someone/Library/Application Support/Windsurf/User/globalStorage/state.vscdb",
        ])
    }
}

struct DevinSQLiteTests {
    /// A VS Code-style `state.vscdb` in a directory with a space in its name (like "Application Support").
    private func makeDatabase(wal: Bool) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("altillo devin \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("state.vscdb")
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        var sql = "CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);"
        sql += "INSERT INTO ItemTable VALUES ('windsurfAuthStatus', '{\"apiKey\":\"sk-from-db\"}');"
        sql += "INSERT INTO ItemTable VALUES ('other', 'x');"
        if wal { sql = "PRAGMA journal_mode=WAL;" + sql }
        #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        return url
    }

    @Test func readsTheAuthRowReadOnly() async throws {
        let url = try makeDatabase(wal: false)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        let value = await SQLiteReadOnlyReader().value(database: url, sql: DevinCollector.authStatusQuery)
        #expect(DevinCredential.parseAppAuthStatus(value ?? "")?.apiKey == "sk-from-db")
        let after = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        #expect(before == after)
    }

    @Test func readsWALDatabases() async throws {
        let url = try makeDatabase(wal: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let value = await SQLiteReadOnlyReader().value(database: url, sql: DevinCollector.authStatusQuery)
        #expect(value?.contains("sk-from-db") == true)
    }

    @Test func neverCreatesMissingDatabases() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).vscdb")
        #expect(await SQLiteReadOnlyReader().value(database: url, sql: "SELECT 1") == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

struct DevinCollectorTests {
    private let locations = DevinCredentialLocations(credentialsFile: URL(fileURLWithPath: "/x/credentials.toml"),
                                                     stateDatabases: [URL(fileURLWithPath: "/x/state.vscdb")])

    private func collector(_ transport: any HTTPTransport, toml: String?, app: String? = nil) -> DevinCollector {
        DevinCollector(transport: transport, locations: locations, readFile: { _ in toml.map { Data($0.utf8) } },
                       sqlite: FixedSQLite(values: app.map { ["/x/state.vscdb": $0] } ?? [:]))
    }

    @Test func readsUsageWithTheCLIKey() async throws {
        let transport = FakeTransport([.response(status: 200, body: DevinFixtures.userStatus)])
        let usage = await collector(transport, toml: #"windsurf_api_key = "sk-cli""#).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.plan == "Max")
        #expect(usage.weekly?.used == 0.6)

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString
            == "https://server.codeium.com/exa.seat_management_pb.SeatManagementService/GetUserStatus")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
        let body = try #require(request.httpBody.flatMap(UsageParsing.object))
        let metadata = try #require(body["metadata"] as? [String: String])
        #expect(metadata["apiKey"] == "sk-cli")
        #expect(metadata["ideName"] == "devin")
    }

    @Test func fallsBackToTheAppKeyWhenTheCLIKeyIsRejected() async throws {
        let transport = FakeTransport([.response(status: 401, body: #"{"code":"unauthenticated"}"#),
                                       .response(status: 200, body: DevinFixtures.userStatus)])
        let usage = await collector(transport, toml: #"windsurf_api_key = "sk-cli""#, app: #"{"apiKey":"sk-app"}"#)
            .fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        let keys = transport.requests.compactMap { request -> String? in
            ((request.httpBody.flatMap(UsageParsing.object))?["metadata"] as? [String: String])?["apiKey"]
        }
        #expect(keys == ["sk-cli", "sk-app"])
    }

    @Test func sameKeyIsTriedOnce() async {
        let transport = FakeTransport([.response(status: 403, body: "")])
        let usage = await collector(transport, toml: #"windsurf_api_key = "sk-same""#, app: #"{"apiKey":"sk-same"}"#)
            .fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .sessionExpired)
        #expect(usage.problemDetail == "Open Devin once to renew its sign-in.")
        #expect(transport.requests.count == 1)
    }

    @Test func missingCredentialsAreNotSignedIn() async {
        let transport = FakeTransport()
        let usage = await collector(transport, toml: nil).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .notSignedIn)
        #expect(transport.requests.isEmpty)
    }

    @Test func rateLimitAndOutagesKeepLastNumbers() async {
        let good = await collector(FakeTransport([.response(status: 200, body: DevinFixtures.userStatus)]),
                                   toml: #"windsurf_api_key = "k""#).fetch(previous: nil, now: referenceNow)
        let limited = await collector(FakeTransport([.response(status: 429, body: "", headers: ["Retry-After": "30"])]),
                                      toml: #"windsurf_api_key = "k""#).fetch(previous: good, now: referenceNow)
        #expect(limited.problem == .rateLimited(retryAfter: referenceNow.addingTimeInterval(30)))
        #expect(limited.windows == good.windows)
        let down = await collector(FakeTransport([.failure(.timedOut)]), toml: #"windsurf_api_key = "k""#)
            .fetch(previous: good, now: referenceNow)
        #expect(down.problem == .unreachable("Timed out"))
        #expect(down.balances == good.balances)
    }
}
