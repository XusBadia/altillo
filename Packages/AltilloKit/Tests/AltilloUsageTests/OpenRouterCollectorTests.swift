import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

enum OpenRouterFixtures {
    static let credits = #"{"data":{"total_credits":100,"total_usage":40.25}}"#
    static let key = """
    {"data":{"label":"sk-or-v1-abc...xyz","limit":20,"limit_remaining":15,"limit_reset":"monthly","usage":5,
     "is_free_tier":false,"usage_daily":0.5,"usage_weekly":2,"usage_monthly":5}}
    """
}

struct OpenRouterMapperTests {
    @Test func mapsCreditsAndKeyLimit() throws {
        let credits = UsageParsing.object(Data(OpenRouterFixtures.credits.utf8))?["data"] as? [String: Any]
        let key = UsageParsing.object(Data(OpenRouterFixtures.key.utf8))?["data"] as? [String: Any]
        let mapped = OpenRouterUsageMapper.map(credits: credits, key: key, now: referenceNow)
        #expect(mapped.plan == "Pay as you go")
        #expect(mapped.balances.map(\.id) == ["credits", "spend-today", "spend-week", "spend-month"])
        #expect(mapped.balances[0] == UsageBalance(id: "credits", label: "Credits", remaining: 59.75, used: 40.25,
                                                   limit: 100, unit: "USD"))
        #expect(mapped.balances[3].used == 5)
        let window = try #require(mapped.windows.first)
        #expect(window.id == "key-limit")
        #expect(window.kind == .monthly)
        #expect(window.used == 0.25)
        #expect(window.resetsAt == iso("2026-10-01T00:00:00Z"))
        #expect(window.duration == TimeInterval(30 * 86400))
    }

    @Test func limitResetCadences() {
        let daily = OpenRouterUsageMapper.limitWindow("daily", now: referenceNow)
        #expect(daily.0 == .other)
        #expect(daily.1 == iso("2026-09-25T00:00:00Z"))
        let weekly = OpenRouterUsageMapper.limitWindow("weekly", now: referenceNow) // a Thursday
        #expect(weekly.0 == .weekly)
        #expect(weekly.1 == iso("2026-09-28T00:00:00Z"))
        let lifetime = OpenRouterUsageMapper.limitWindow(nil, now: referenceNow)
        #expect(lifetime.0 == .other)
        #expect(lifetime.1 == nil)
    }

    @Test func freeAccountWithoutCreditsStillShowsBalance() {
        let mapped = OpenRouterUsageMapper.map(credits: ["total_credits": 0, "total_usage": 0],
                                               key: ["is_free_tier": true, "limit": NSNull()], now: referenceNow)
        #expect(mapped.plan == "Free tier")
        #expect(mapped.windows.isEmpty)
        #expect(mapped.balances == [UsageBalance(id: "credits", label: "Credits", remaining: 0, used: 0, limit: nil,
                                                 unit: "USD")])
    }
}

struct OpenRouterCollectorTests {
    func source(_ files: [String: String] = [:], environment: [String: String] = [:]) -> LocalAPIKeySource {
        LocalAPIKeySource(files: [URL(fileURLWithPath: "/cfg/openrouter/key.json")],
                          environmentNames: ["OPENROUTER_API_KEY", "OPENROUTER_KEY"], environment: environment,
                          readFile: { files[$0.path] })
    }

    @Test func readsBothEndpoints() async throws {
        let transport = RoutedTransport([
            ("/api/v1/credits", .response(status: 200, body: OpenRouterFixtures.credits)),
            ("/api/v1/key", .response(status: 200, body: OpenRouterFixtures.key)),
        ])
        let collector = OpenRouterCollector(keySource: source(["/cfg/openrouter/key.json": #"{"apiKey":"sk-or-test"}"#]),
                                            transport: transport)
        #expect(await collector.isAvailable())
        let usage = await collector.fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.id == .openRouter)
        #expect(usage.windows.map(\.id) == ["key-limit"])
        #expect(usage.balances.first?.remaining == 59.75)
        #expect(transport.requests.count == 2)
        #expect(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-test" })
    }

    @Test func oneGatedEndpointDoesNotBlankTheOther() async {
        let transport = RoutedTransport([
            ("/api/v1/credits", .response(status: 403, body: "{}")),
            ("/api/v1/key", .response(status: 200, body: OpenRouterFixtures.key)),
        ])
        let usage = await OpenRouterCollector(keySource: source(environment: ["OPENROUTER_API_KEY": "sk-env"]),
                                              transport: transport).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.windows.count == 1)
        #expect(!usage.balances.contains { $0.id == "credits" })
    }

    @Test func failures() async {
        func run(_ credits: FakeTransport.Reply, _ key: FakeTransport.Reply) async -> ProviderUsage {
            await OpenRouterCollector(keySource: source(environment: ["OPENROUTER_KEY": "sk"]),
                                      transport: RoutedTransport([("/credits", credits), ("/key", key)]))
                .fetch(previous: nil, now: referenceNow)
        }
        let rejected = await run(.response(status: 401, body: ""), .response(status: 401, body: ""))
        #expect(rejected.problem == .sessionExpired)
        #expect(rejected.problemDetail?.contains("openrouter.ai/keys") == true)
        #expect(await run(.response(status: 429, body: "", headers: ["Retry-After": "10"]), .response(status: 403, body: ""))
            .problem == .rateLimited(retryAfter: referenceNow.addingTimeInterval(10)))
        #expect(await run(.failure(.notConnectedToInternet), .failure(.notConnectedToInternet)).problem
            == .unreachable("Offline"))
        #expect(await run(.response(status: 200, body: "{}"), .response(status: 200, body: "{}")).problem
            == .unexpectedResponse("OpenRouter response changed shape"))
    }

    @Test func missingKeyIsNotSignedIn() async {
        let collector = OpenRouterCollector(keySource: source(), transport: RoutedTransport([]))
        #expect(!(await collector.isAvailable()))
        let usage = await collector.fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .notSignedIn)
        #expect(usage.problemDetail?.contains("~/.config/openrouter/key.json") == true)
        #expect(collector.setupHint == "Add an OpenRouter API key to ~/.config/openrouter/key.json")
    }
}

struct Group1SupportTests {
    @Test func apiKeyFileFormats() {
        #expect(LocalAPIKeySource.apiKey(fromConfigText: #"{"apiKey":" sk-1 "}"#) == "sk-1")
        #expect(LocalAPIKeySource.apiKey(fromConfigText: #"{"api_key":"sk-2"}"#) == "sk-2")
        #expect(LocalAPIKeySource.apiKey(fromConfigText: #"{"key":"sk-3"}"#) == "sk-3")
        #expect(LocalAPIKeySource.apiKey(fromConfigText: "sk-plain\n") == "sk-plain")
        #expect(LocalAPIKeySource.apiKey(fromConfigText: #"{"other":"x"}"#) == nil)
        #expect(LocalAPIKeySource.apiKey(fromConfigText: "  ") == nil)
    }

    @Test func filesWinOverEnvironmentAndXDGIsHonoured() {
        let file = URL(fileURLWithPath: "/cfg/p/key.json")
        let both = LocalAPIKeySource(files: [file], environmentNames: ["A", "B"], environment: ["B": "env"],
                                     readFile: { $0 == file ? "from-file" : nil })
        #expect(both.key() == "from-file")
        let envOnly = LocalAPIKeySource(files: [file], environmentNames: ["A", "B"], environment: ["B": " env "],
                                        readFile: { _ in nil })
        #expect(envOnly.key() == "env")
        let home = URL(fileURLWithPath: "/Users/t")
        #expect(LocalAPIKeySource.configFile("zai", environment: [:], home: home).path == "/Users/t/.config/zai/key.json")
        #expect(LocalAPIKeySource.configFile("zai", environment: ["XDG_CONFIG_HOME": "/x"], home: home).path
            == "/x/zai/key.json")
    }

    @Test func securityCLIKeychainNeverAsksForMissingItems() async {
        let missing = FakeRunner([CommandResult(status: 44, stdout: Data())])
        #expect(await SecurityCLIKeychain(runner: missing).secret(service: "svc", account: nil) == .notFound)
        #expect(missing.arguments == [["find-generic-password", "-s", "svc"]]) // no -w: no prompt

        let found = FakeRunner([CommandResult(status: 0, stdout: Data()),
                                CommandResult(status: 0, stdout: Data("secret\n".utf8))])
        #expect(await SecurityCLIKeychain(runner: found).secret(service: "svc", account: "me") == .found("secret"))
        #expect(found.arguments.last == ["find-generic-password", "-s", "svc", "-a", "me", "-w"])

        let refused = FakeRunner([CommandResult(status: 0, stdout: Data()),
                                  CommandResult(status: 128, stdout: Data(), timedOut: true)])
        #expect(await SecurityCLIKeychain(runner: refused).secret(service: "svc", account: nil) == .denied)
    }

    @Test func goKeyringAndJWT() {
        #expect(Group1Support.unwrapGoKeyring("go-keyring-base64:" + Data("tok".utf8).base64EncodedString()) == "tok")
        #expect(Group1Support.unwrapGoKeyring(" plain ") == "plain")
        #expect(Group1Support.unwrapGoKeyring("go-keyring-base64:!!!") == nil)
        let jwt = cursorJWT(sub: "a|b", expires: referenceNow)
        #expect(Group1Support.jwtPayload(jwt)?["sub"] as? String == "a|b")
        #expect(Group1Support.jwtPayload("nope") == nil)
    }
}
