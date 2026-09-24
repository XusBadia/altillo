import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

enum CopilotFixtures {
    /// Paid plan, shape from openusage's CopilotProviderTests (`makePaidBody`), with the unlimited completions
    /// bucket paid plans report.
    static let paid = """
    {"copilot_plan": "individual_pro", "quota_reset_date": "2026-10-01T00:00:00Z",
     "quota_snapshots": {
       "premium_interactions": {"entitlement": 300, "remaining": 123, "percent_remaining": 41, "quota_id": "premium",
                                "overage_permitted": true, "overage_count": 4},
       "chat": {"entitlement": 1000, "remaining": 950, "percent_remaining": 95, "quota_id": "chat"},
       "completions": {"entitlement": -1, "remaining": -1, "unlimited": true, "quota_id": "completions"}}}
    """

    static let freeLegacy = """
    {"copilot_plan": "free", "limited_user_reset_date": "2026-10-05",
     "limited_user_quotas": {"chat": 40, "completions": 1500},
     "monthly_quotas": {"chat": 50, "completions": 2000}}
    """

    /// Copilot Free as GitHub returned it live on 2026-09-24 (identifiers and unused fields dropped).
    static let freeLive = """
    {"copilot_plan": "individual", "access_type_sku": "free_limited_copilot", "quota_reset_date": "2026-10-01",
     "quota_reset_date_utc": "2026-10-01T00:00:00.000Z", "token_based_billing": true,
     "quota_snapshots": {
       "chat": {"overage_count": 0, "overage_permitted": false, "percent_remaining": 87.5, "quota_id": "chat",
                "unlimited": false, "has_quota": true, "credits_used": 0, "remaining": 175, "entitlement": 200},
       "completions": {"overage_count": 0, "overage_permitted": false, "percent_remaining": 100.0,
                       "quota_id": "completions", "unlimited": false, "has_quota": true, "credits_used": 0,
                       "remaining": 2000, "entitlement": 2000},
       "premium_interactions": {"overage_count": 0, "overage_permitted": false, "percent_remaining": 0.0,
                                "quota_id": "premium_interactions", "unlimited": false, "has_quota": false,
                                "credits_used": 0, "remaining": 0, "entitlement": 0}}}
    """

    /// Org-managed token-billed seat (openusage issue #1094 shape).
    static let businessSeat = """
    {"copilot_plan": "business", "token_based_billing": true,
     "quota_snapshots": {
       "chat": {"entitlement": 0, "remaining": 0, "unlimited": true},
       "premium_interactions": {"entitlement": 0, "remaining": 0, "unlimited": true, "overage_permitted": true,
                                "overage_count": 0, "credits_used": 12.5}}}
    """
}

struct CopilotMapperTests {
    @Test func mapsPaidPlan() throws {
        guard case .mapped(let mapped) = CopilotUsageMapper.map(Data(CopilotFixtures.paid.utf8)) else {
            Issue.record("expected a mapping")
            return
        }
        #expect(mapped.plan == "Individual Pro")
        #expect(mapped.windows.map(\.id) == ["premium", "chat"]) // unlimited completions hidden
        #expect(mapped.windows[0].label == "Credits")
        #expect(mapped.windows[0].used == 0.59)
        #expect(mapped.windows[0].kind == .monthly)
        #expect(mapped.windows[0].resetsAt == iso("2026-10-01T00:00:00Z"))
        #expect(mapped.windows[0].duration == TimeInterval(30 * 86400)) // September
        #expect(abs(mapped.windows[1].used - 0.05) < 1e-9)
        #expect(mapped.balances == [UsageBalance(id: "extra-usage", label: "Extra usage", remaining: nil, used: 4,
                                                 limit: nil, unit: "credits")])
    }

    @Test func mapsLegacyFreePlan() throws {
        guard case .mapped(let mapped) = CopilotUsageMapper.map(Data(CopilotFixtures.freeLegacy.utf8)) else {
            Issue.record("expected a mapping")
            return
        }
        #expect(mapped.plan == "Free")
        #expect(mapped.windows.map(\.id) == ["chat", "completions"])
        #expect(mapped.windows[0].used == 0.2)
        #expect(mapped.windows[1].used == 0.25)
        #expect(mapped.windows[0].resetsAt == iso("2026-10-05T00:00:00Z"))
    }

    @Test func mapsLiveFreePlan() throws {
        guard case .mapped(let mapped) = CopilotUsageMapper.map(Data(CopilotFixtures.freeLive.utf8)) else {
            Issue.record("expected a mapping")
            return
        }
        #expect(mapped.plan == "Free")
        #expect(mapped.windows.map(\.id) == ["chat", "completions"]) // no premium allowance on Free
        #expect(mapped.windows[0].used == 0.125)
        #expect(mapped.windows[1].used == 0)
        #expect(mapped.windows[0].resetsAt == iso("2026-10-01T00:00:00Z"))
        #expect(mapped.balances.isEmpty)
    }

    @Test func businessSeatShowsOwnCredits() throws {
        guard case .mapped(let mapped) = CopilotUsageMapper.map(Data(CopilotFixtures.businessSeat.utf8)) else {
            Issue.record("expected a mapping")
            return
        }
        #expect(mapped.plan == "Business")
        #expect(mapped.windows.isEmpty)
        #expect(mapped.balances == [UsageBalance(id: "credits", label: "Credits", remaining: nil, used: 12.5,
                                                 limit: nil, unit: "credits")])
    }

    @Test func emptyAndUnknownShapes() {
        #expect(CopilotUsageMapper.map(Data(#"{"copilot_plan":"pro","quota_snapshots":{}}"#.utf8)) == .noQuota(plan: "Pro"))
        #expect(CopilotUsageMapper.map(Data(#"{"message":"hi"}"#.utf8)) == .unreadable)
        #expect(CopilotUsageMapper.map(Data("[]".utf8)) == .unreadable)
    }
}

struct CopilotTokenStoreTests {
    let home = URL(fileURLWithPath: "/Users/tester")

    func store(_ files: [String: String], keychain: Group1Keychain = Group1Keychain([:]),
               environment: [String: String] = [:]) -> CopilotTokenStore {
        CopilotTokenStore(environment: environment, home: home, readFile: { files[$0.path] }, keychain: keychain)
    }

    @Test func editorConfigWinsAndIgnoresEnterpriseHosts() async {
        let apps = #"{"ghe.corp.example:Iv1.x":{"oauth_token":"gho_ent"},"github.com:Iv1.y":{"oauth_token":"gho_dotcom"}}"#
        let keychain = Group1Keychain(["gh:github.com": .found("gho_keychain")])
        let found = await store(["/Users/tester/.config/github-copilot/apps.json": apps], keychain: keychain).read()
        #expect(found == .found(CopilotToken(value: "gho_dotcom", source: .editorConfig)))
        #expect(keychain.readCount == 0)

        let enterpriseOnly = #"{"ghe.corp.example":{"oauth_token":"gho_ent"}}"#
        #expect(await store(["/Users/tester/.config/github-copilot/hosts.json": enterpriseOnly]).read() == .notFound)
    }

    @Test func ghHostsFileScopedToGithubDotCom() async {
        let hosts = """
        ghe.corp.example:
            oauth_token: gho_enterprise
            user: enterprise
        github.com:
            users:
                octocat:
            oauth_token: gho_dotcom
            user: octocat
        """
        let store = store(["/Users/tester/.config/gh/hosts.yml": hosts])
        #expect(await store.exists())
        #expect(await store.read() == .found(CopilotToken(value: "gho_dotcom", source: .ghConfig)))
        #expect(CopilotTokenStore.yamlValue(hosts, key: "user") == "octocat")
    }

    @Test func ghKeychainUnwrapsGoKeyringScopedToTheUser() async {
        let hosts = "github.com:\n    git_protocol: ssh\n    user: octocat\n"
        let wrapped = "go-keyring-base64:" + Data("gho_keychain".utf8).base64EncodedString()
        let keychain = Group1Keychain(["gh:github.com": .found(wrapped)])
        let found = await store(["/Users/tester/.config/gh/hosts.yml": hosts], keychain: keychain).read()
        #expect(found == .found(CopilotToken(value: "gho_keychain", source: .ghKeychain)))
        #expect(keychain.accounts == ["octocat"])

        let denied = Group1Keychain(["gh:github.com": .denied])
        #expect(await store(["/Users/tester/.config/gh/hosts.yml": hosts], keychain: denied).read() == .accessDenied)
    }

    @Test func honoursConfigDirectories() async {
        let custom = store(["/tmp/ghconf/hosts.yml": "github.com:\n    oauth_token: gho_custom\n"],
                           environment: ["GH_CONFIG_DIR": "/tmp/ghconf"])
        #expect(await custom.read() == .found(CopilotToken(value: "gho_custom", source: .ghConfig)))
        let xdg = store(["/tmp/xdg/github-copilot/apps.json": #"{"github.com":{"oauth_token":"gho_xdg"}}"#],
                        environment: ["XDG_CONFIG_HOME": "/tmp/xdg"])
        #expect(await xdg.read() == .found(CopilotToken(value: "gho_xdg", source: .editorConfig)))
    }

    @Test func nothingOnThisMac() async {
        let empty = store([:])
        #expect(!(await empty.exists()))
        #expect(await empty.read() == .notFound)
    }
}

struct CopilotCollectorTests {
    struct FixedTokens: CopilotTokenReading {
        var lookup: CopilotTokenLookup
        func exists() async -> Bool { lookup != .notFound }
        func read() async -> CopilotTokenLookup { lookup }
    }

    let token = CopilotTokenLookup.found(CopilotToken(value: "gho_test", source: .editorConfig))

    @Test func readsUsageWithCopilotHeaders() async throws {
        let transport = RoutedTransport([("copilot_internal/user", .response(status: 200, body: CopilotFixtures.paid))])
        let usage = await CopilotCollector(tokens: FixedTokens(lookup: token), transport: transport)
            .fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.id == .copilot)
        #expect(usage.plan == "Individual Pro")
        #expect(usage.windows.map(\.id) == ["premium", "chat"])
        let request = try #require(transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "token gho_test")
        #expect(request.value(forHTTPHeaderField: "Editor-Version") == "vscode/1.96.2")
        #expect(request.value(forHTTPHeaderField: "X-Github-Api-Version") == "2025-04-01")
    }

    @Test func failures() async {
        func run(_ reply: FakeTransport.Reply, lookup: CopilotTokenLookup? = nil,
                 previous: ProviderUsage? = nil) async -> ProviderUsage {
            await CopilotCollector(tokens: FixedTokens(lookup: lookup ?? token),
                                   transport: RoutedTransport([("api.github.com", reply)]))
                .fetch(previous: previous, now: referenceNow)
        }
        let previous = ProviderUsage(id: .copilot, displayName: "Copilot", plan: "Pro", windows: [
            UsageWindow(id: "premium", kind: .monthly, label: "Credits", used: 0.3, resetsAt: nil, duration: nil),
        ], fetchedAt: referenceNow.addingTimeInterval(-900))

        let expired = await run(.response(status: 401, body: "{}"), previous: previous)
        #expect(expired.problem == .sessionExpired)
        #expect(expired.windows == previous.windows)
        #expect(expired.problemDetail?.contains("gh auth login") == true)

        #expect(await run(.response(status: 429, body: "", headers: ["Retry-After": "30"])).problem
            == .rateLimited(retryAfter: referenceNow.addingTimeInterval(30)))
        #expect(await run(.response(status: 404, body: "")).problem == .notSignedIn)
        #expect(await run(.failure(.timedOut)).problem == .unreachable("Timed out"))
        #expect(await run(.response(status: 200, body: "nope")).problem
            == .unexpectedResponse("Copilot usage response changed shape"))
        #expect(await run(.response(status: 200, body: "{}"), lookup: .notFound).problem == .notSignedIn)
        #expect(await run(.response(status: 200, body: "{}"), lookup: .accessDenied).problem == .accessDenied)
    }
}
