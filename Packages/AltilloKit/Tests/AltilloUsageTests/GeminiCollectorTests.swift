import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

enum GeminiFixtures {
    /// openusage's AntigravityQuotaSummaryTests: all four buckets, groups in scrambled order.
    static let groups = """
    "groups":[
      {"displayName":"Claude and other models","buckets":[
        {"bucketId":"3p-weekly","displayName":"Weekly","window":"weekly","remainingFraction":1,"resetTime":"2026-07-06T07:00:00Z"},
        {"bucketId":"3p-5h","displayName":"5-hour","window":"5h","remainingFraction":0.4,"resetTime":"2026-07-02T15:30:00Z"}
      ]},
      {"displayName":"Gemini models","buckets":[
        {"bucketId":"gemini-5h","displayName":"5-hour","window":"5h","remainingFraction":0.75,"resetTime":"2026-07-02T16:00:00Z"},
        {"bucketId":"gemini-weekly","displayName":"Weekly","window":"weekly","remainingFraction":0.9,"resetTime":"2026-07-06T07:00:00Z"}
      ]}
    ]
    """
    static let summaryBare = "{\(groups)}"
    static let summaryWrapped = "{\"response\":{\(groups)}}"

    static let userStatus = """
    {"userStatus":{"userTier":{"name":"Google AI Pro"},
    "planStatus":{"planInfo":{"planName":"Pro"}},
    "cascadeModelConfigData":{"clientModelConfigs":[
      {"label":"Gemini 3.1 Pro (High)","modelOrAlias":{"model":"MODEL_PLACEHOLDER_M16"},
       "quotaInfo":{"remainingFraction":0.5,"resetTime":"2026-06-26T09:37:05Z"}},
      {"label":"Claude Sonnet 4.6 (Thinking)","modelOrAlias":{"model":"MODEL_PLACEHOLDER_M35"},
       "quotaInfo":{"remainingFraction":1,"resetTime":"2026-06-26T09:47:54Z"}}
    ]}}}
    """

    /// `ps -ax -o pid=,command=` with Antigravity running (anonymized).
    static let ps = """
      4221 /Applications/Antigravity.app/Contents/MacOS/Antigravity
      4276 /Applications/Antigravity.app/Contents/Resources/bin/language_server_macos_arm --standalone --override_ide_name antigravity --csrf_token tok-123 --extension_server_port=52170 --app_data_dir antigravity
      4278 /Applications/Antigravity.app/Contents/Frameworks/Antigravity Helper (Renderer).app/Contents/MacOS/Antigravity Helper (Renderer) --type=renderer
      5000 /Applications/Windsurf.app/Contents/Resources/bin/language_server_macos_arm --csrf_token other --app_data_dir windsurf
      6100 /Users/someone/.local/bin/agy
    """

    static let lsof = """
    COMMAND    PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
    language_ 4276 someone    6u  IPv4 0xb01a07fcc634a8e1      0t0  TCP 127.0.0.1:52168 (LISTEN)
    language_ 4276 someone    7u  IPv4 0x7eb2d525b7317601      0t0  TCP 127.0.0.1:52169 (LISTEN)
    """

    static func keychain(expiry: String) -> String {
        let inner = """
        {"token":{"access_token":"ya29.test","refresh_token":"1//refresh","expiry":"\(expiry)","token_type":"Bearer"},"auth_method":"consumer"}
        """
        return "go-keyring-base64:" + Data(inner.utf8).base64EncodedString()
    }
}

struct FixedLanguageServers: GeminiLanguageServerLocating {
    var servers: [GeminiLanguageServer]
    func locate() async -> [GeminiLanguageServer] { servers }
}

struct GeminiDiscoveryTests {
    @Test func findsAntigravitysLanguageServerOnly() {
        let antigravity = GeminiDiscovery.searches[0]
        let candidates = GeminiDiscovery.rankedCandidates(psOutput: GeminiFixtures.ps, options: antigravity)
        #expect(candidates.map(\.pid) == [4276]) // not Windsurf's server, not the app or its helpers
        #expect(GeminiDiscovery.extractFlag(command: candidates[0].command, flag: "--csrf_token") == "tok-123")
        #expect(GeminiDiscovery.extractFlag(command: candidates[0].command, flag: "--extension_server_port") == "52170")

        let agy = GeminiDiscovery.rankedCandidates(psOutput: GeminiFixtures.ps, options: GeminiDiscovery.searches[1])
        #expect(agy.map(\.pid) == [6100])
    }

    @Test func ranksExactMarkersBeforePaths() {
        #expect(GeminiDiscovery.markerRank(command: "/x/language_server --app_data_dir antigravity --csrf_token z",
                                           markers: ["antigravity"]) == 0)
        #expect(GeminiDiscovery.markerRank(command: "/opt/antigravity/bin/language_server --standalone",
                                           markers: ["antigravity"]) == 1)
        #expect(GeminiDiscovery.markerRank(command: "/x/language_server --app_data_dir antigravity-next",
                                           markers: ["antigravity"]) == nil)
        #expect(GeminiDiscovery.markerRank(command: "anything", markers: []) == 0)
    }

    @Test func matchesExecutables() {
        let ls = "/Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone"
        #expect(GeminiDiscovery.commandMatches(ls, processName: "language_server"))
        #expect(!GeminiDiscovery.commandMatches(ls, processName: "agy"))
        #expect(GeminiDiscovery.commandMatches("/Users/x/.local/bin/agy", processName: "agy"))
        #expect(!GeminiDiscovery.commandMatches("/usr/bin/agyle", processName: "agy"))
        #expect(GeminiDiscovery.argv0(#""/Apps/My App/agy" --x"#) == "/Apps/My App/agy")
    }

    @Test func parsesFlagsAndPorts() {
        let command = "/bin/language_server --csrf_token ABC-123 --extension_server_port=42 --foo"
        #expect(GeminiDiscovery.extractFlag(command: command, flag: "--csrf_token") == "ABC-123")
        #expect(GeminiDiscovery.extractFlag(command: command, flag: "--extension_server_port") == "42")
        #expect(GeminiDiscovery.extractFlag(command: command, flag: "--missing") == nil)
        #expect(GeminiDiscovery.parseListeningPorts(GeminiFixtures.lsof) == [52168, 52169])
        #expect(GeminiDiscovery.parseListeningPorts("TCP *:80 (ESTABLISHED)") == [])
    }

    @Test func locatorUsesPsThenLsof() async {
        let runner = FakeRunner([CommandResult(status: 0, stdout: Data(GeminiFixtures.ps.utf8)),
                                 CommandResult(status: 0, stdout: Data(GeminiFixtures.lsof.utf8)),
                                 CommandResult(status: 1, stdout: Data())]) // agy: lsof finds nothing
        let servers = await GeminiLanguageServerLocator(runner: runner).locate()
        #expect(servers == [GeminiLanguageServer(pid: 4276, csrf: "tok-123", ports: [52168, 52169],
                                                 extensionPort: 52170)])
        #expect(runner.arguments.first == ["-ax", "-o", "pid=,command="])
        #expect(runner.arguments.dropFirst().first == ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "4276"])
        #expect(servers[0].endpoints.map(\.absoluteString) == [
            "https://127.0.0.1:52168", "http://127.0.0.1:52168", "https://127.0.0.1:52169", "http://127.0.0.1:52169",
            "http://127.0.0.1:52170",
        ])
    }

    @Test func noProcessesNoServers() async {
        #expect(await GeminiLanguageServerLocator(runner: FakeRunner([nil])).locate().isEmpty)
    }
}

struct GeminiKeychainTokenTests {
    @Test func readsGoKeyringWrappedJSON() {
        let token = GeminiKeychainToken.parse(GeminiFixtures.keychain(expiry: "2099-01-01T00:00:00Z"))
        #expect(token == GeminiKeychainToken(accessToken: "ya29.test", expiresAt: iso("2099-01-01T00:00:00Z")))
    }

    @Test func readsOtherShapes() {
        #expect(GeminiKeychainToken.parse(#"{"access_token":"abc","refresh_token":"r"}"#)?.accessToken == "abc")
        #expect(GeminiKeychainToken.parse(#"{"oauth":{"accessToken":"nested"}}"#)?.accessToken == "nested")
        #expect(GeminiKeychainToken.parse(#""quoted""#)?.accessToken == "quoted")
        #expect(GeminiKeychainToken.parse("Bearer ya29.b")?.accessToken == "ya29.b")
        #expect(GeminiKeychainToken.parse("ya29.raw\n")?.accessToken == "ya29.raw")
        #expect(GeminiKeychainToken.parse(#"{"refresh_token":"only"}"#) == GeminiKeychainToken(accessToken: nil, expiresAt: nil))
    }

    @Test func rejectsBrokenValues() {
        #expect(GeminiKeychainToken.parse("{broken") == nil)
        #expect(GeminiKeychainToken.parse("go-keyring-base64:!!!") == nil)
        #expect(GeminiKeychainToken.parse("   ") == nil)
        #expect(GeminiKeychainToken.parse(#"{"unrelated":1}"#) == nil)
    }
}

struct GeminiMapperTests {
    @Test func mapsTheFourPoolsFromEitherEnvelope() throws {
        let bare = try #require(GeminiUsageMapper.quotaSummary(Data(GeminiFixtures.summaryBare.utf8)))
        let wrapped = GeminiUsageMapper.quotaSummary(Data(GeminiFixtures.summaryWrapped.utf8))
        #expect(bare == wrapped)
        #expect(bare.map(\.id) == ["session", "weekly", "claude-session", "claude-weekly"])
        #expect(bare.map(\.kind) == [.session, .weekly, .other, .modelWeekly])
        #expect(bare.map(\.label) == ["Session", "Week", "Claude session", "Claude week"])
        let used = bare.map { ($0.used * 100).rounded() }
        #expect(used == [25, 10, 60, 0])
        #expect(bare[0].resetsAt == iso("2026-07-02T16:00:00Z"))
        let session: TimeInterval = 5 * 3600, week: TimeInterval = 7 * 86400
        #expect(bare.map(\.duration) == [session, week, session, week])
    }

    @Test func dropsUnusableAndUnknownBuckets() {
        let json = """
        {"groups":[{"buckets":[
          "junk",
          {"bucketId":"3p-5h","remainingFraction":"lots"},
          {"bucketId":"gemini-image-5h","remainingFraction":0.1},
          {"displayName":"Session","remainingFraction":0.2},
          {"bucketId":"gemini-weekly","resetTime":"2026-07-06T07:00:00Z"},
          {"bucketId":"gemini-5h","remainingFraction":0.25}
        ]}]}
        """
        let windows = GeminiUsageMapper.quotaSummary(Data(json.utf8))
        #expect(windows?.map(\.id) == ["session"])
        #expect(windows?.first?.used == 0.75)
        #expect(windows?.first?.resetsAt == nil)
    }

    @Test func emptySummaryIsAuthoritativeButNonSummaryIsNil() {
        #expect(GeminiUsageMapper.quotaSummary(Data(#"{"groups":[]}"#.utf8)) == [])
        #expect(GeminiUsageMapper.quotaSummary(Data(#"{"response":{"groups":[]}}"#.utf8)) == [])
        #expect(GeminiUsageMapper.quotaSummary(Data("{}".utf8)) == nil)
        #expect(GeminiUsageMapper.quotaSummary(Data("not json".utf8)) == nil)
    }

    @Test func legacyUserStatusPoolsModels() {
        let data = Data(GeminiFixtures.userStatus.utf8)
        #expect(GeminiUsageMapper.userStatusPlan(data) == "Pro")
        let windows = GeminiUsageMapper.userStatusWindows(data)
        #expect(windows?.map(\.id) == ["session", "claude-session"])
        #expect(windows?.map(\.used) == [0.5, 0])
        #expect(GeminiUsageMapper.userStatusWindows(Data("{}".utf8)) == nil)
    }

    @Test func legacyCloudCodeModelsSkipInternalBlacklistedAndQuotaless() {
        let json = """
        {"models":{
          "a":{"model":"MODEL_OK","displayName":"Gemini 3.1 Pro (High)","quotaInfo":{"remainingFraction":0.8}},
          "b":{"model":"MODEL_CHAT_23310","displayName":"chat","isInternal":true,"quotaInfo":{"remainingFraction":0}},
          "c":{"model":"MODEL_GOOGLE_GEMINI_2_5_PRO","displayName":"Gemini 2.5 Pro","quotaInfo":{"remainingFraction":0}},
          "d":{"model":"MODEL_X","displayName":"Gemini Flash"},
          "e":{"model":"MODEL_Y","displayName":"GPT-OSS 120B","quotaInfo":{"remainingFraction":0.3}}
        }}
        """
        let windows = GeminiUsageMapper.cloudCodeModelWindows(Data(json.utf8))
        #expect(windows?.map(\.id) == ["session", "claude-session"])
        #expect(windows.map { $0.map { ($0.used * 100).rounded() } } == [20, 70])
    }

    @Test func formatsPlans() {
        #expect(GeminiUsageMapper.formatPlan("Google AI Pro") == "Pro")
        #expect(GeminiUsageMapper.formatPlan("Google AI Ultra") == "Ultra")
        #expect(GeminiUsageMapper.formatPlan("Gemini Code Assist in Google One AI Pro") == "Pro")
        #expect(GeminiUsageMapper.formatPlan("Gemini Code Assist") == "Gemini Code Assist")
        #expect(GeminiUsageMapper.formatPlan("  ") == nil)
        #expect(GeminiUsageMapper.loadCodeAssistPlan(Data(
            #"{"currentTier":{"name":"Gemini Code Assist"},"paidTier":{"name":"Google AI Ultra"}}"#.utf8)) == "Ultra")
    }
}

struct GeminiCollectorTests {
    private let server = GeminiLanguageServer(pid: 4276, csrf: "tok-123", ports: [52168], extensionPort: 52170)

    private func collector(servers: [GeminiLanguageServer] = [], local: any HTTPTransport = FakeTransport(),
                           remote: any HTTPTransport = FakeTransport(), keychain: [CommandResult?] = [])
        -> GeminiCollector {
        GeminiCollector(locator: FixedLanguageServers(servers: servers), localTransport: local, transport: remote,
                        keychainRunner: FakeRunner(keychain), installed: { true })
    }

    private func keychainHit(expiry: String) -> CommandResult {
        CommandResult(status: 0, stdout: Data((GeminiFixtures.keychain(expiry: expiry) + "\n").utf8))
    }

    @Test func readsTheRunningLanguageServer() async throws {
        let local = Group2RoutedTransport([
            ("https://127.0.0.1:52168", .failure(.secureConnectionFailed)),
            ("RetrieveUserQuotaSummary", .response(status: 200, body: GeminiFixtures.summaryWrapped)),
            ("GetUserStatus", .response(status: 200, body: GeminiFixtures.userStatus)),
        ])
        let remote = FakeTransport()
        let usage = await collector(servers: [server], local: local, remote: remote).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.plan == "Pro")
        #expect(usage.windows.count == 4)
        #expect(usage.session?.used == 0.25)
        #expect(remote.requests.isEmpty) // no Cloud Code call, no keychain read needed

        let summary = try #require(local.requests.first { $0.url!.path.hasSuffix("RetrieveUserQuotaSummary")
            && $0.url!.scheme == "http" })
        #expect(summary.url?.absoluteString
            == "http://127.0.0.1:52168/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary")
        #expect(summary.value(forHTTPHeaderField: "x-codeium-csrf-token") == "tok-123")
        #expect(summary.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
        #expect(summary.httpMethod == "POST")
    }

    @Test func olderLanguageServersUseGetUserStatus() async {
        let local = Group2RoutedTransport([
            ("RetrieveUserQuotaSummary", .response(status: 404, body: "")),
            ("GetUserStatus", .response(status: 200, body: GeminiFixtures.userStatus)),
        ])
        let usage = await collector(servers: [server], local: local).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.plan == "Pro")
        #expect(usage.windows.map(\.id) == ["session", "claude-session"])
    }

    @Test func silentLanguageServerFallsBackToCloudCode() async {
        let local = Group2RoutedTransport([("/", .failure(.cannotConnectToHost))])
        let usage = await collector(servers: [server], local: local).fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .unreachable("Antigravity's language server didn't answer"))
        #expect(local.requests.count == server.endpoints.count) // one try per endpoint, then the keychain
    }

    @Test func notRunningAndNotSignedIn() async {
        let usage = await collector().fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .notSignedIn)
        #expect(usage.problemDetail == "Antigravity isn't running or signed in on this Mac.")
    }

    @Test func cloudCodeWithTheKeychainSignIn() async throws {
        let remote = Group2RoutedTransport([
            ("retrieveUserQuotaSummary", .response(status: 200, body: GeminiFixtures.summaryBare)),
            ("loadCodeAssist", .response(status: 200, body: #"{"paidTier":{"name":"Google AI Pro"}}"#)),
        ])
        let runner = FakeRunner([keychainHit(expiry: "2026-09-24T11:00:00Z")])
        let gemini = GeminiCollector(locator: FixedLanguageServers(servers: []), localTransport: FakeTransport(),
                                     transport: remote, keychainRunner: runner, installed: { true })
        let usage = await gemini.fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == nil)
        #expect(usage.plan == "Pro")
        #expect(abs((usage.weekly?.used ?? 0) - 0.1) < 1e-9)
        #expect(runner.arguments == [["find-generic-password", "-s", "gemini", "-a", "antigravity", "-w"]])
        let request = try #require(remote.requests.first)
        #expect(request.url?.absoluteString == "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ya29.test")
        #expect(remote.requests.allSatisfy { $0.url?.host?.hasSuffix("googleapis.com") == true
            && $0.url?.host != "oauth2.googleapis.com" }) // never a token refresh
    }

    @Test func expiredKeychainTokenIsNeverRefreshed() async {
        let remote = FakeTransport()
        let usage = await collector(remote: remote, keychain: [keychainHit(expiry: "2026-09-24T09:00:00Z")])
            .fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .sessionExpired)
        #expect(usage.problemDetail == "Open Antigravity once to renew its sign-in.")
        #expect(remote.requests.isEmpty)
    }

    @Test func rejectedTokenAndRateLimitKeepLastNumbers() async {
        let good = await collector(remote: Group2RoutedTransport([
            ("retrieveUserQuotaSummary", .response(status: 200, body: GeminiFixtures.summaryBare)),
        ]), keychain: [keychainHit(expiry: "2099-01-01T00:00:00Z")]).fetch(previous: nil, now: referenceNow)
        #expect(good.windows.count == 4)

        let rejected = await collector(remote: Group2RoutedTransport([("/", .response(status: 401, body: ""))]),
                                       keychain: [keychainHit(expiry: "2099-01-01T00:00:00Z")])
            .fetch(previous: good, now: referenceNow)
        #expect(rejected.problem == .sessionExpired)
        #expect(rejected.windows == good.windows)

        let limited = await collector(remote: Group2RoutedTransport([
            ("/", .response(status: 429, body: "", headers: ["Retry-After": "90"])),
        ]), keychain: [keychainHit(expiry: "2099-01-01T00:00:00Z")]).fetch(previous: good, now: referenceNow)
        #expect(limited.problem == .rateLimited(retryAfter: referenceNow.addingTimeInterval(90)))
        #expect(limited.windows == good.windows)
    }

    @Test func legacyCloudCodeAndOutages() async {
        let legacy = await collector(remote: Group2RoutedTransport([
            ("retrieveUserQuotaSummary", .response(status: 404, body: "")),
            ("fetchAvailableModels", .response(status: 200, body:
                #"{"models":{"a":{"displayName":"Gemini 3 Pro","quotaInfo":{"remainingFraction":0.5}}}}"#)),
        ]), keychain: [keychainHit(expiry: "2099-01-01T00:00:00Z")]).fetch(previous: nil, now: referenceNow)
        #expect(legacy.windows.map(\.id) == ["session"])
        #expect(legacy.problem == nil)

        let down = await collector(remote: Group2RoutedTransport([("/", .response(status: 503, body: ""))]),
                                   keychain: [keychainHit(expiry: "2099-01-01T00:00:00Z")])
            .fetch(previous: nil, now: referenceNow)
        #expect(down.problem == .unreachable("HTTP 503"))
    }

    @Test func refusedKeychainIsAccessDenied() async {
        let usage = await collector(keychain: [CommandResult(status: 51, stdout: Data())])
            .fetch(previous: nil, now: referenceNow)
        #expect(usage.problem == .accessDenied)
    }
}
