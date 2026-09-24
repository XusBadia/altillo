import AltilloCore
import Foundation

// Small helpers shared by the Cursor, GitHub Copilot, OpenRouter and Z.ai collectors: read-only keychain access
// through `/usr/bin/security`, API keys the user already keeps in a provider's standard place, JWT payloads,
// go-keyring values, and the HTTP status → `UsageProblem` mapping every collector repeats.
//
// `apiKey(fromConfigText:)`, `jwtPayload(_:)` and `unwrapGoKeyring(_:)` are adapted from openusage (MIT),
// Sources/OpenUsage/Providers/UserAPIKeyStore.swift and Sources/OpenUsage/Support/ProviderParse.swift
// @87c3d2db465a5eb6c6dd2c2453c55cd82141a76e.

// MARK: - Keychain (read-only)

/// Result of reading another tool's keychain item.
public enum KeychainSecretLookup: Sendable, Hashable {
    case found(String)
    case notFound
    /// The keychain refused, or a prompt went unanswered.
    case denied
}

/// Reads a generic-password item another tool owns. Tests inject fixed values.
public protocol KeychainSecretReading: Sendable {
    func secret(service: String, account: String?) async -> KeychainSecretLookup
    /// Whether the item exists, without reading (or prompting for) its secret.
    func contains(service: String, account: String?) async -> Bool
}

/// Reads through `/usr/bin/security find-generic-password`. It first asks for the item's attributes only (never
/// prompts), and only asks for the secret (`-w`) when the item exists, so a Mac without the item never sees a
/// dialog. Items created by tools that store secrets through the `security` binary (gh's go-keyring, Claude Code)
/// trust it, so reading them doesn't prompt either. Nothing is ever written.
public struct SecurityCLIKeychain: KeychainSecretReading {
    static let tool = URL(fileURLWithPath: "/usr/bin/security")
    static let notFoundStatus: Int32 = 44

    private let runner: any CommandRunning
    private let timeout: TimeInterval

    public init(runner: any CommandRunning = ProcessCommandRunner(), timeout: TimeInterval = 8) {
        self.runner = runner
        self.timeout = timeout
    }

    public func contains(service: String, account: String?) async -> Bool {
        await runner.run(Self.tool, arguments: Self.arguments(service: service, account: account), timeout: 5)?
            .status == 0
    }

    static func arguments(service: String, account: String?) -> [String] {
        var arguments = ["find-generic-password", "-s", service]
        if let account, !account.isEmpty { arguments += ["-a", account] }
        return arguments
    }

    public func secret(service: String, account: String?) async -> KeychainSecretLookup {
        let arguments = Self.arguments(service: service, account: account)

        guard let probe = await runner.run(Self.tool, arguments: arguments, timeout: 5) else { return .notFound }
        if probe.status == Self.notFoundStatus { return .notFound }
        if probe.status != 0 || probe.timedOut { return .denied }

        guard let result = await runner.run(Self.tool, arguments: arguments + ["-w"], timeout: timeout) else {
            return .denied
        }
        if result.status == 0, !result.timedOut {
            let text = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? .notFound : .found(text)
        }
        return result.status == Self.notFoundStatus ? .notFound : .denied
    }
}

// MARK: - API keys the user keeps for a provider

/// An API key in a provider's standard config file (JSON `apiKey`/`api_key`/`key`, or a plain-text file holding only
/// the key) or environment variable. Files win over the environment, like openusage. Read-only.
public struct LocalAPIKeySource: Sendable {
    public var files: [URL]
    public var environmentNames: [String]
    private let environment: [String: String]
    private let readFile: @Sendable (URL) -> String?

    public init(files: [URL], environmentNames: [String],
                environment: [String: String] = ProcessInfo.processInfo.environment,
                readFile: @escaping @Sendable (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) }) {
        self.files = files
        self.environmentNames = environmentNames
        self.environment = environment
        self.readFile = readFile
    }

    /// `~/.config/<directory>/key.json`, honouring `XDG_CONFIG_HOME`.
    public static func configFile(_ directory: String, file: String = "key.json",
                                  environment: [String: String] = ProcessInfo.processInfo.environment,
                                  home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        configDirectory(environment: environment, home: home).appendingPathComponent(directory)
            .appendingPathComponent(file)
    }

    /// `$XDG_CONFIG_HOME`, or `~/.config`.
    public static func configDirectory(environment: [String: String] = ProcessInfo.processInfo.environment,
                                       home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let xdg = environment["XDG_CONFIG_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !xdg.isEmpty {
            return URL(fileURLWithPath: (xdg as NSString).expandingTildeInPath)
        }
        return home.appendingPathComponent(".config")
    }

    /// The key, or nil when none of the sources has one.
    public func key() -> String? {
        for file in files {
            if let text = readFile(file), let key = Self.apiKey(fromConfigText: text) { return key }
        }
        for name in environmentNames {
            if let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// JSON object with `apiKey` / `api_key` / `key`, or plain text holding only the key.
    static func apiKey(fromConfigText text: String) -> String? {
        if let object = UsageParsing.object(Data(text.utf8)) {
            for field in ["apiKey", "api_key", "key"] {
                if let value = UsageParsing.string(object[field]) { return value }
            }
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("{"), !trimmed.contains(where: \.isNewline) else { return nil }
        return trimmed
    }
}

// MARK: - Shared collector plumbing

enum Group1Support {
    /// Decoded payload of a JWT (no signature check: only used to read `exp`/`sub` of a token we already hold).
    static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while !payload.count.isMultiple(of: 4) { payload.append("=") }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return UsageParsing.object(data)
    }

    /// `go-keyring-base64:<base64>` (how gh stores secrets in the keychain) → the secret; other values trimmed.
    static func unwrapGoKeyring(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "go-keyring-base64:"
        if text.hasPrefix(prefix) {
            let encoded = text.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = Data(base64Encoded: encoded), let decoded = String(data: data, encoding: .utf8) else {
                return nil
            }
            text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty ? nil : text
    }

    /// The last good numbers (if any) with `problem` set, as every collector reports a failed read.
    static func failure(_ problem: UsageProblem, detail: String?, previous: ProviderUsage?, id: UsageProviderID,
                        displayName: String, plan: String?, now: Date) -> ProviderUsage {
        var usage = previous ?? ProviderUsage(id: id, displayName: displayName, plan: plan, windows: [],
                                              fetchedAt: now)
        usage.problem = problem
        usage.problemDetail = detail
        if let plan { usage.plan = plan }
        return usage
    }

    /// True while a previous 429's Retry-After hasn't passed: asking again early only extends the rate limit.
    static func isBackingOff(_ previous: ProviderUsage?, now: Date) -> Bool {
        if let previous, case .rateLimited(let until?) = previous.problem, now < until { return true }
        return false
    }

    /// Outcome of one HTTP call, classified the way every collector needs it.
    enum Reply {
        case ok(Data)
        /// 401/403.
        case unauthorized(Int)
        case rateLimited(Date)
        /// Transport error or another status; carries the `.unreachable` reason.
        case failed(String)
        /// Any other non-2xx status (e.g. 404), with the body in case it explains itself.
        case status(Int, Data)

        var data: Data? {
            if case .ok(let data) = self { return data }
            return nil
        }

        var object: [String: Any]? { data.flatMap(UsageParsing.object) }
    }

    static func send(_ request: URLRequest, transport: any HTTPTransport, now: Date,
                     defaultBackoff: TimeInterval = 5 * 60) async -> Reply {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            return .failed(ClaudeCollector.describe(error))
        }
        switch response.statusCode {
        case 200..<300:
            return .ok(data)
        case 401, 403:
            return .unauthorized(response.statusCode)
        case 429:
            return .rateLimited(UsageParsing.retryAfter(response.header("Retry-After"), now: now)
                ?? now.addingTimeInterval(defaultBackoff))
        case 500...:
            return .failed("HTTP \(response.statusCode)")
        default:
            return .status(response.statusCode, data)
        }
    }

    /// `GET`/`POST` with a ≤ 10 s timeout and no caching.
    static func request(_ url: URL, method: String = "GET", headers: [String: String], body: Data? = nil,
                        timeout: TimeInterval = 10) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: min(timeout, 10))
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = body
        return request
    }

    /// Length of the calendar month (UTC) that ends at `resetsAt`, for monthly windows without an explicit start.
    static func monthDuration(endingAt resetsAt: Date?) -> TimeInterval {
        guard let resetsAt else { return 30 * 86400 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = calendar.date(byAdding: .month, value: -1, to: resetsAt) else { return 30 * 86400 }
        return resetsAt.timeIntervalSince(start)
    }

    /// Clamps a 0…100 percentage (never negative; over 100 kept, since "over the limit" is real) into 0…n.
    static func fraction(percent: Double) -> Double { max(0, percent) / 100 }
}
