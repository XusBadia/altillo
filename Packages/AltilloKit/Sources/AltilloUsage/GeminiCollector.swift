import AltilloCore
import Foundation

// Gemini usage in Antigravity (Google's agentic IDE and its `agy` CLI): first the running language server's own
// quota RPC, then Google's Cloud Code endpoint with the sign-in Antigravity keeps in the keychain (read-only).
//
// Adapted from openusage (MIT), Sources/OpenUsage/Providers/Antigravity/{AntigravityProvider,AntigravityUsageClient,
// AntigravityUsageMapper,AntigravityAuthStore}.swift and Sources/OpenUsage/Services/LanguageServerDiscovery.swift
// @87c3d2db465a5eb6c6dd2c2453c55cd82141a76e: the process discovery (ps/lsof, CSRF flag, marker ranking), the RPC and
// Cloud Code endpoints, the quota-summary buckets, the legacy per-model pooling, plan naming and the go-keyring token
// format. Unlike openusage, Altillo never refreshes the Google token (no OAuth client secret, no token cache): an
// expired keychain token means "open Antigravity once". See ThirdPartyNotices/README.md.

extension UsageProviderID {
    public static let gemini = UsageProviderID(rawValue: "gemini")
}

// MARK: - Language server discovery

/// A running Antigravity language server (the app's `language_server`, or the `agy` CLI) Altillo can ask.
public struct GeminiLanguageServer: Sendable, Hashable {
    public var pid: Int32
    /// Sent as `x-codeium-csrf-token`; empty for servers that don't use one (`agy`).
    public var csrf: String
    /// Listening TCP ports (HTTPS with a self-signed certificate, sometimes plain HTTP).
    public var ports: [Int]
    /// `--extension_server_port`, an HTTP-only fallback.
    public var extensionPort: Int?

    public init(pid: Int32, csrf: String, ports: [Int], extensionPort: Int?) {
        self.pid = pid
        self.csrf = csrf
        self.ports = ports
        self.extensionPort = extensionPort
    }

    /// Where to call it, best first: HTTPS then HTTP on each port, then the extension port.
    var endpoints: [URL] {
        var urls = ports.flatMap { port in ["https", "http"].compactMap { URL(string: "\($0)://127.0.0.1:\(port)") } }
        if let extensionPort, let url = URL(string: "http://127.0.0.1:\(extensionPort)") { urls.append(url) }
        return urls
    }
}

/// Finds running language servers. Tests inject fixed ones.
public protocol GeminiLanguageServerLocating: Sendable {
    func locate() async -> [GeminiLanguageServer]
}

/// `ps` for the process and its flags, `lsof` for its listening ports. Two short commands, off the main thread.
public struct GeminiLanguageServerLocator: GeminiLanguageServerLocating {
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func locate() async -> [GeminiLanguageServer] {
        guard let ps = await runner.run(URL(fileURLWithPath: "/bin/ps"), arguments: ["-ax", "-o", "pid=,command="],
                                        timeout: 5), ps.status == 0 else { return [] }
        let listing = String(decoding: ps.stdout, as: UTF8.self)
        var servers: [GeminiLanguageServer] = []
        for options in GeminiDiscovery.searches {
            for candidate in GeminiDiscovery.rankedCandidates(psOutput: listing, options: options).prefix(3) {
                let csrf: String
                if let flag = options.csrfFlag {
                    guard let value = GeminiDiscovery.extractFlag(command: candidate.command, flag: flag) else {
                        continue
                    }
                    csrf = value
                } else {
                    csrf = ""
                }
                let extensionPort = options.portFlag
                    .flatMap { GeminiDiscovery.extractFlag(command: candidate.command, flag: $0) }
                    .flatMap { Int($0) }
                var ports: [Int] = []
                if let lsof = await runner.run(URL(fileURLWithPath: "/usr/sbin/lsof"),
                                               arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p",
                                                           String(candidate.pid)],
                                               timeout: 5), lsof.status == 0 {
                    ports = GeminiDiscovery.parseListeningPorts(String(decoding: lsof.stdout, as: UTF8.self))
                }
                guard !ports.isEmpty || extensionPort != nil else { continue }
                servers.append(GeminiLanguageServer(pid: candidate.pid, csrf: csrf, ports: ports,
                                                    extensionPort: extensionPort))
            }
        }
        return servers
    }
}

/// Pure parsing of `ps` and `lsof` output.
enum GeminiDiscovery {
    struct Options: Equatable {
        /// Executable name (`language_server`, `agy`).
        var processName: String
        /// Lowercased values matched against `--ide_name`/`--override_ide_name`/`--app_data_dir` (exact), else a
        /// `/marker/` path substring. Empty matches any instance.
        var markers: [String]
        var csrfFlag: String?
        var portFlag: String?
    }

    /// Antigravity's bundled language server first (richest: it knows the plan), then the `agy` CLI.
    static let searches = [
        Options(processName: "language_server", markers: ["antigravity", "antigravity-ide"],
                csrfFlag: "--csrf_token", portFlag: "--extension_server_port"),
        Options(processName: "agy", markers: [], csrfFlag: nil, portFlag: nil),
    ]

    /// `ps -ax -o pid=,command=` lines that match, exact marker flags before path matches.
    static func rankedCandidates(psOutput: String, options: Options) -> [(pid: Int32, command: String)] {
        let name = options.processName.lowercased()
        let markers = options.markers.map { $0.lowercased() }.filter { !$0.isEmpty }
        var ranked: [(rank: Int, pid: Int32, command: String)] = []
        for raw in psOutput.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(where: { $0 == " " || $0 == "\t" }),
                  let pid = Int32(line[..<space]) else { continue }
            let command = line[line.index(after: space)...].trimmingCharacters(in: .whitespaces)
            guard commandMatches(command, processName: name),
                  let rank = markerRank(command: command, markers: markers) else { continue }
            ranked.append((rank, pid, command))
        }
        return ranked.enumerated()
            .sorted { $0.element.rank != $1.element.rank ? $0.element.rank < $1.element.rank : $0.offset < $1.offset }
            .map { (pid: $0.element.pid, command: $0.element.command) }
    }

    /// `--flag value` or `--flag=value`.
    static func extractFlag(command: String, flag: String) -> String? {
        let parts = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        for (index, part) in parts.enumerated() {
            if part == flag { return index + 1 < parts.count ? parts[index + 1] : nil }
            if part.hasPrefix(flag + "=") { return String(part.dropFirst(flag.count + 1)) }
        }
        return nil
    }

    /// 0 for an exact marker flag (so "antigravity" never matches "antigravity-next"), 1 for a `/marker/` path,
    /// nil for no match. No markers: always 0.
    static func markerRank(command: String, markers: [String]) -> Int? {
        if markers.isEmpty { return 0 }
        let flags = ["--ide_name", "--override_ide_name", "--app_data_dir"]
            .compactMap { extractFlag(command: command, flag: $0)?.lowercased() }
        if !flags.isEmpty { return markers.contains { flags.contains($0) } ? 0 : nil }
        let lowered = command.lowercased()
        return markers.contains { lowered.contains("/\($0)/") } ? 1 : nil
    }

    /// The executable (first argv token, honouring a quoted path).
    static func argv0(_ command: String) -> String {
        let trimmed = command.drop { $0 == " " || $0 == "\t" }
        if let quote = trimmed.first, quote == "\"" || quote == "'" {
            let rest = trimmed.dropFirst()
            if let end = rest.firstIndex(of: quote) { return String(rest[..<end]) }
        }
        return trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
    }

    /// `language_server` also matches `language_server_macos_arm`; short names (`agy`) must be a path component.
    static func commandMatches(_ command: String, processName: String) -> Bool {
        guard !processName.isEmpty else { return false }
        let executable = (argv0(command) as NSString).lastPathComponent.lowercased()
        if executable == processName { return true }
        let lowered = command.lowercased()
        if processName.count >= 8 {
            return executable.hasPrefix(processName + "_") || lowered.contains(processName)
        }
        return lowered.hasSuffix("/\(processName)") || lowered.contains("/\(processName) ")
            || lowered.contains("/\(processName)\t")
    }

    /// Ports from `lsof -nP -iTCP -sTCP:LISTEN` (deduplicated, ascending).
    static func parseListeningPorts(_ output: String) -> [Int] {
        var ports = Set<Int>()
        for line in output.split(whereSeparator: \.isNewline) where line.contains("LISTEN") {
            for token in line.split(separator: " ").reversed() {
                if let colon = token.lastIndex(of: ":"), let port = Int(token[token.index(after: colon)...]),
                   port > 0, port < 65_536 {
                    ports.insert(port)
                    break
                }
            }
        }
        return ports.sorted()
    }
}

// MARK: - Keychain token

/// The access token Antigravity keeps in the keychain (service `gemini`, account `antigravity`, written by the
/// Antigravity app and `agy` through go-keyring). The refresh token is deliberately never kept.
public struct GeminiKeychainToken: Sendable, Hashable {
    public static let service = "gemini"
    public static let account = "antigravity"

    public var accessToken: String?
    public var expiresAt: Date?

    public init(accessToken: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    public func isExpired(now: Date, margin: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now.addingTimeInterval(margin)
    }

    /// `go-keyring-base64:` + `{"token":{"access_token","refresh_token","expiry"},…}`, or a bare JSON object, a JSON
    /// string, `Bearer …` or a raw token. Nil for anything unusable (broken JSON is never sent as a token).
    public static func parse(_ raw: String) -> GeminiKeychainToken? {
        guard let text = TokenParsing.unwrapGoKeyring(raw) else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) {
            if let object = json as? [String: Any] { return token(from: object) }
            if let string = UsageParsing.string(json) { return GeminiKeychainToken(accessToken: string, expiresAt: nil) }
            return nil
        }
        if text.hasPrefix("{") || text.hasPrefix("[") { return nil }
        if text.hasPrefix("Bearer ") {
            return UsageParsing.string(String(text.dropFirst(7))).map { GeminiKeychainToken(accessToken: $0, expiresAt: nil) }
        }
        return GeminiKeychainToken(accessToken: text, expiresAt: nil)
    }

    private static func token(from object: [String: Any]) -> GeminiKeychainToken? {
        let source = object["token"] as? [String: Any] ?? object
        let access = ["access_token", "accessToken", "token", "id_token", "idToken", "bearerToken", "auth_token",
                      "authToken"].lazy.compactMap { UsageParsing.string(source[$0]) }.first
        let hasRefresh = ["refresh_token", "refreshToken"].contains { UsageParsing.string(source[$0]) != nil }
        let expiry = ["expiry", "expires_at", "expiresAt"].lazy.compactMap { UsageParsing.date(source[$0]) }.first
        if access == nil, !hasRefresh {
            for key in ["tokens", "oauth", "oauth2", "credentials", "auth"] {
                if let nested = object[key] as? [String: Any], let found = token(from: nested) { return found }
            }
            return nil
        }
        return GeminiKeychainToken(accessToken: access, expiresAt: expiry)
    }
}

// MARK: - Collector

/// Reads Antigravity's Gemini pool and its shared non-Gemini (Claude, GPT-OSS) pool, each with a 5-hour and a weekly
/// window.
public struct GeminiCollector: UsageCollector {
    static let languageServerService = "exa.language_server_pb.LanguageServerService"
    static let cloudCodeBases = ["https://daily-cloudcode-pa.googleapis.com", "https://cloudcode-pa.googleapis.com"]
        .compactMap(URL.init(string:))
    static let languageServerMetadata = ["ideName": "antigravity", "extensionName": "antigravity",
                                         "ideVersion": "unknown", "locale": "en"]

    public let providerID: UsageProviderID = .gemini
    public let displayName = "Gemini"
    public var setupHint: String { "Open Antigravity or sign in with `agy` on this Mac" }

    private let locator: any GeminiLanguageServerLocating
    private let localTransport: any HTTPTransport
    private let transport: any HTTPTransport
    private let keychain: SecurityKeychainReader
    private let installed: @Sendable () -> Bool

    public init(locator: any GeminiLanguageServerLocating = GeminiLanguageServerLocator(),
                localTransport: any HTTPTransport = LoopbackTransport(),
                transport: any HTTPTransport = URLSessionTransport(),
                keychainRunner: any CommandRunning = ProcessCommandRunner(),
                installed: @escaping @Sendable () -> Bool = { GeminiCollector.antigravityInstalled() }) {
        self.locator = locator
        self.localTransport = localTransport
        self.transport = transport
        keychain = SecurityKeychainReader(runner: keychainRunner)
        self.installed = installed
    }

    public func isAvailable() async -> Bool { installed() }

    /// The Antigravity app, the `agy` CLI or their data directories.
    public static func antigravityInstalled(fileManager: FileManager = .default,
                                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let paths = ["/Applications/Antigravity.app", "\(home.path)/Applications/Antigravity.app",
                     "\(home.path)/.gemini/antigravity", "\(home.path)/.gemini/antigravity-cli",
                     "\(home.path)/.local/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy"]
        return paths.contains { fileManager.fileExists(atPath: $0) }
    }

    public func fetch(previous: ProviderUsage?, now: Date) async -> ProviderUsage {
        if CollectorOutcome.isBackingOff(previous, now: now) { return previous! }

        // 1. A running language server answers for itself (and knows the plan).
        let servers = await locator.locate()
        for server in servers {
            for base in server.endpoints {
                if let mapped = await readLanguageServer(base: base, csrf: server.csrf) {
                    return ProviderUsage(id: providerID, displayName: displayName, plan: mapped.plan,
                                         windows: mapped.windows, fetchedAt: now)
                }
            }
        }

        // 2. Cloud Code with the keychain sign-in, as long as it's still valid (never refreshed here).
        let token: GeminiKeychainToken
        switch await keychain.password(service: GeminiKeychainToken.service, account: GeminiKeychainToken.account) {
        case .notFound:
            if !servers.isEmpty {
                return failure(.unreachable("Antigravity's language server didn't answer"), detail: nil,
                               previous: previous, now: now)
            }
            return failure(.notSignedIn, detail: "Antigravity isn't running or signed in on this Mac.",
                           previous: previous, now: now)
        case .accessDenied:
            return failure(.accessDenied, detail: "Access to Antigravity's keychain item was refused.",
                           previous: previous, now: now)
        case .found(let raw):
            guard let parsed = GeminiKeychainToken.parse(raw) else {
                return failure(.notSignedIn, detail: "Antigravity's sign-in couldn't be read. Sign in to Antigravity again.",
                               previous: previous, now: now)
            }
            token = parsed
        }
        guard let accessToken = token.accessToken, !token.isExpired(now: now) else {
            return failure(.sessionExpired, detail: "Open Antigravity once to renew its sign-in.", previous: previous,
                           now: now)
        }
        return await readCloudCode(token: accessToken, previous: previous, now: now)
    }

    // MARK: Language server

    /// Nil when this endpoint isn't the live one or has nothing usable.
    private func readLanguageServer(base: URL, csrf: String) async -> GeminiUsageMapper.Mapped? {
        guard let summary = await callLanguageServer(base: base, csrf: csrf, method: "RetrieveUserQuotaSummary")
        else { return nil } // not listening here
        let status = await callLanguageServer(base: base, csrf: csrf, method: "GetUserStatus")
        let statusBody = status.flatMap { (200..<300).contains($0.status) ? $0.body : nil }
        let plan = statusBody.flatMap(GeminiUsageMapper.userStatusPlan)
        if (200..<300).contains(summary.status), let windows = GeminiUsageMapper.quotaSummary(summary.body) {
            return GeminiUsageMapper.Mapped(plan: plan, windows: windows)
        }
        // Builds without the summary RPC (404): the per-model quotas in GetUserStatus (5-hour pools only).
        if let statusBody, let windows = GeminiUsageMapper.userStatusWindows(statusBody), !windows.isEmpty {
            return GeminiUsageMapper.Mapped(plan: plan, windows: windows)
        }
        return nil
    }

    /// The status and body of any HTTP answer; nil when nothing answered (not the live port).
    private func callLanguageServer(base: URL, csrf: String, method: String) async -> (status: Int, body: Data)? {
        let url = base.appendingPathComponent(Self.languageServerService).appendingPathComponent(method)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(csrf, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["metadata": Self.languageServerMetadata])
        guard let (data, response) = try? await localTransport.send(request) else { return nil }
        return (response.statusCode, data)
    }

    // MARK: Cloud Code

    private func readCloudCode(token: String, previous: ProviderUsage?, now: Date) async -> ProviderUsage {
        var lastFailure = "Cloud Code didn't answer"
        // The quota summary (both pools, 5-hour and weekly), then the legacy model list (5-hour pools only).
        for (path, legacy) in [("/v1internal:retrieveUserQuotaSummary", false),
                               ("/v1internal:fetchAvailableModels", true)] {
            for base in Self.cloudCodeBases {
                switch await HTTPReply.send(cloudCodeRequest(base: base, path: path, token: token,
                                                             userAgent: "antigravity"),
                                            with: transport, now: now) {
                case .success(let body):
                    let windows = legacy ? GeminiUsageMapper.cloudCodeModelWindows(body)
                                         : GeminiUsageMapper.quotaSummary(body)
                    guard let windows, legacy ? !windows.isEmpty : true else { continue }
                    let plan = await cloudCodePlan(token: token, now: now) ?? previous?.plan
                    return ProviderUsage(id: providerID, displayName: displayName, plan: plan, windows: windows,
                                         fetchedAt: now)
                case .unauthorized:
                    return failure(.sessionExpired, detail: "Open Antigravity once to renew its sign-in.",
                                   previous: previous, now: now)
                case .rateLimited(let retry):
                    return failure(.rateLimited(retryAfter: retry), detail: nil, previous: previous, now: now)
                case .failed(let reason):
                    lastFailure = reason
                }
            }
        }
        return failure(.unreachable(lastFailure), detail: nil, previous: previous, now: now)
    }

    private func cloudCodePlan(token: String, now: Date) async -> String? {
        for base in Self.cloudCodeBases {
            if case .success(let body) = await HTTPReply.send(
                cloudCodeRequest(base: base, path: "/v1internal:loadCodeAssist", token: token, userAgent: "agy"),
                with: transport, now: now) {
                return GeminiUsageMapper.loadCodeAssistPlan(body)
            }
        }
        return nil
    }

    private func cloudCodeRequest(base: URL, path: String, token: String, userAgent: String) -> URLRequest {
        var request = URLRequest(url: URL(string: base.absoluteString + path)!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("{}".utf8)
        return request
    }

    private func failure(_ problem: UsageProblem, detail: String?, previous: ProviderUsage?, now: Date)
        -> ProviderUsage {
        CollectorOutcome.failure(problem, detail: detail, id: providerID, displayName: displayName,
                                 previous: previous, plan: nil, now: now)
    }
}

// MARK: - Mapping

/// Pure mapping of Antigravity's quota responses.
enum GeminiUsageMapper {
    static let sessionDuration: TimeInterval = 5 * 3600
    static let weekDuration: TimeInterval = 7 * 86400

    struct Mapped: Equatable {
        var plan: String?
        var windows: [UsageWindow]
    }

    /// The four pool buckets of `RetrieveUserQuotaSummary`, matched by exact `bucketId` only (a future bucket never
    /// silently joins a pool).
    static let summaryBuckets: [(bucketID: String, id: String, kind: UsageWindow.Kind, label: String,
                                 duration: TimeInterval)] = [
        ("gemini-5h", "session", .session, "Session", sessionDuration),
        ("gemini-weekly", "weekly", .weekly, "Week", weekDuration),
        ("3p-5h", "claude-session", .other, "Claude session", sessionDuration),
        ("3p-weekly", "claude-weekly", .modelWeekly, "Claude week", weekDuration),
    ]

    /// Internal or duplicate model ids that never count toward a legacy pool.
    static let modelBlacklist: Set<String> = [
        "MODEL_CHAT_20706", "MODEL_CHAT_23310", "MODEL_GOOGLE_GEMINI_2_5_FLASH",
        "MODEL_GOOGLE_GEMINI_2_5_FLASH_THINKING", "MODEL_GOOGLE_GEMINI_2_5_FLASH_LITE", "MODEL_GOOGLE_GEMINI_2_5_PRO",
        "MODEL_PLACEHOLDER_M19", "MODEL_PLACEHOLDER_M9", "MODEL_PLACEHOLDER_M12",
    ]

    /// `{"response":{"groups":[{"buckets":[{"bucketId","remainingFraction","resetTime"}]}]}}` (language server) or the
    /// same without `response` (Cloud Code). Nil when it isn't a summary at all; an empty array is an authoritative
    /// "no buckets". A bucket without a usable fraction is dropped rather than guessed.
    static func quotaSummary(_ data: Data) -> [UsageWindow]? {
        guard let body = UsageParsing.object(data) else { return nil }
        let root = body["response"] as? [String: Any] ?? body
        guard let groups = root["groups"] as? [Any] else { return nil }
        var found: [String: (remaining: Double, reset: Date?)] = [:]
        for group in groups {
            guard let buckets = (group as? [String: Any])?["buckets"] as? [Any] else { continue }
            for case let bucket as [String: Any] in buckets {
                guard let id = bucket["bucketId"] as? String, found[id] == nil,
                      summaryBuckets.contains(where: { $0.bucketID == id }),
                      let fraction = bucket["remainingFraction"] as? NSNumber,
                      CFGetTypeID(fraction) != CFBooleanGetTypeID(), fraction.doubleValue.isFinite else { continue }
                found[id] = (fraction.doubleValue, UsageParsing.date(bucket["resetTime"]))
            }
        }
        return summaryBuckets.compactMap { spec in
            found[spec.bucketID].map {
                UsageWindow(id: spec.id, kind: spec.kind, label: spec.label, used: used(remaining: $0.remaining),
                            resetsAt: $0.reset, duration: spec.duration)
            }
        }
    }

    /// Plan from `GetUserStatus`: Google's `userTier` wins over the inherited `planInfo.planName` ("Pro" for every
    /// paid tier).
    static func userStatusPlan(_ data: Data) -> String? {
        guard let status = UsageParsing.object(data)?["userStatus"] as? [String: Any] else { return nil }
        let tier = (status["userTier"] as? [String: Any]).flatMap { UsageParsing.string($0["name"]) }
        let planName = ((status["planStatus"] as? [String: Any])?["planInfo"] as? [String: Any])
            .flatMap { UsageParsing.string($0["planName"]) }
        return formatPlan(tier ?? planName)
    }

    /// Legacy per-model quotas in `GetUserStatus.cascadeModelConfigData.clientModelConfigs`, pooled.
    static func userStatusWindows(_ data: Data) -> [UsageWindow]? {
        guard let status = UsageParsing.object(data)?["userStatus"] as? [String: Any] else { return nil }
        let configs = ((status["cascadeModelConfigData"] as? [String: Any])?["clientModelConfigs"] as? [Any]) ?? []
        return pooledSessions(configs.compactMap { entry -> ModelQuota? in
            guard let object = entry as? [String: Any], let label = UsageParsing.string(object["label"]) else {
                return nil
            }
            let model = (object["modelOrAlias"] as? [String: Any]).flatMap { UsageParsing.string($0["model"]) }
            return ModelQuota(label: label, modelID: model, quota: object["quotaInfo"])
        })
    }

    /// Legacy Cloud Code `fetchAvailableModels`: `{"models":{"<key>":{"model","displayName","isInternal","quotaInfo"}}}`.
    static func cloudCodeModelWindows(_ data: Data) -> [UsageWindow]? {
        guard let models = UsageParsing.object(data)?["models"] as? [String: Any] else { return nil }
        return pooledSessions(models.keys.sorted().compactMap { key -> ModelQuota? in
            guard let model = models[key] as? [String: Any], model["isInternal"] as? Bool != true,
                  let label = UsageParsing.string(model["displayName"]) ?? UsageParsing.string(model["label"])
            else { return nil }
            return ModelQuota(label: label, modelID: UsageParsing.string(model["model"]) ?? key,
                              quota: model["quotaInfo"])
        })
    }

    /// Plan from Cloud Code `loadCodeAssist` (paid tier over current tier).
    static func loadCodeAssistPlan(_ data: Data) -> String? {
        guard let body = UsageParsing.object(data) else { return nil }
        let name = { (key: String) in (body[key] as? [String: Any]).flatMap { UsageParsing.string($0["name"]) } }
        return formatPlan(name("paidTier") ?? name("currentTier"))
    }

    /// "Google AI Pro" → "Pro"; "Gemini Code Assist in Google One AI Pro" → "Pro".
    static func formatPlan(_ raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("Google AI ") {
            return String(text.dropFirst("Google AI ".count)).split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
        for keyword in ["Ultra", "Pro", "Free"] where text.lowercased().contains(keyword.lowercased()) {
            return keyword
        }
        return text
    }

    // MARK: Legacy pooling

    struct ModelQuota {
        var label: String
        var modelID: String?
        var quota: Any?
    }

    /// Gemini models share the "Session" pool, everything else the "Claude session" pool; each keeps its worst
    /// (lowest) remaining fraction. Models without quota info are skipped rather than counted as used up.
    static func pooledSessions(_ models: [ModelQuota]) -> [UsageWindow] {
        var pools: [Bool: (remaining: Double, reset: Date?)] = [:]
        for model in models {
            if let id = model.modelID, modelBlacklist.contains(id) { continue }
            guard let quota = model.quota as? [String: Any],
                  let remaining = UsageParsing.number(quota["remainingFraction"]) else { continue }
            let isGemini = model.label.lowercased().contains("gemini")
            if let existing = pools[isGemini], existing.remaining <= remaining { continue }
            pools[isGemini] = (remaining, UsageParsing.date(quota["resetTime"]))
        }
        var windows: [UsageWindow] = []
        if let gemini = pools[true] {
            windows.append(UsageWindow(id: "session", kind: .session, label: "Session",
                                       used: used(remaining: gemini.remaining), resetsAt: gemini.reset,
                                       duration: sessionDuration))
        }
        if let other = pools[false] {
            windows.append(UsageWindow(id: "claude-session", kind: .other, label: "Claude session",
                                       used: used(remaining: other.remaining), resetsAt: other.reset,
                                       duration: sessionDuration))
        }
        return windows
    }

    private static func used(remaining: Double) -> Double {
        1 - min(max(remaining, 0), 1)
    }
}
