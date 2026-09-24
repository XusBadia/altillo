import AltilloCore
import Foundation
import SQLite3

// Devin (formerly Windsurf/Codeium) usage from Codeium's seat-management service, with the API key Devin's own CLI or
// app already stores on this Mac (read-only).
//
// Adapted from openusage (MIT), Sources/OpenUsage/Providers/Devin/{DevinAuthStore,DevinUsageClient,DevinUsageMapper,
// DevinProvider}.swift@87c3d2db465a5eb6c6dd2c2453c55cd82141a76e: the credential locations, the TOML reading, the
// `windsurfAuthStatus` row, the GetUserStatus request and the planStatus mapping. See ThirdPartyNotices/README.md.

extension UsageProviderID {
    public static let devin = UsageProviderID(rawValue: "devin")
}

/// An API key for Codeium's API server, from one of Devin's credential stores. Never written back.
public struct DevinCredential: Sendable, Hashable {
    public enum Source: String, Sendable, Hashable { case cli, app }

    public static let defaultServer = URL(string: "https://server.codeium.com")!

    public var apiKey: String
    /// `https://…` only; nil means `defaultServer`.
    public var apiServer: URL?
    public var source: Source

    public init(apiKey: String, apiServer: URL?, source: Source) {
        self.apiKey = apiKey
        self.apiServer = apiServer
        self.source = source
    }

    public var server: URL { apiServer ?? Self.defaultServer }

    /// `credentials.toml`: `windsurf_api_key = "…"`, optional `api_server_url = "https://…"`.
    public static func parseCredentialsFile(_ text: String) -> DevinCredential? {
        guard let key = tomlString(text, key: "windsurf_api_key") else { return nil }
        let server = tomlString(text, key: "api_server_url").flatMap(cleanServer)
        return DevinCredential(apiKey: key, apiServer: server, source: .cli)
    }

    /// The `windsurfAuthStatus` value in the app's `state.vscdb`: `{"apiKey": "…", …}`.
    public static func parseAppAuthStatus(_ text: String) -> DevinCredential? {
        guard let data = text.data(using: .utf8), let object = UsageParsing.object(data),
              let key = UsageParsing.string(object["apiKey"]) else { return nil }
        return DevinCredential(apiKey: key, apiServer: nil, source: .app)
    }

    static func cleanServer(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.lowercased().hasPrefix("https://") else { return nil }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host?.isEmpty == false else { return nil }
        return url
    }

    /// Minimal `key = value` reader: quoted (single or double) or bare values, `#` comments after bare values.
    static func tomlString(_ text: String, key: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'" {
                var output = ""
                var previous: Character?
                for character in value.dropFirst() {
                    if character == quote, previous != "\\" {
                        let trimmed = output.trimmingCharacters(in: .whitespaces)
                        return trimmed.isEmpty ? nil : trimmed
                    }
                    output.append(character)
                    previous = character
                }
                return nil
            }
            let bare = (value.split(separator: "#", maxSplits: 1).first.map(String.init) ?? "")
                .trimmingCharacters(in: .whitespaces)
            return bare.isEmpty ? nil : bare
        }
        return nil
    }
}

/// Where Devin keeps its sign-in on this Mac.
public struct DevinCredentialLocations: Sendable, Hashable {
    /// The CLI's `credentials.toml`.
    public var credentialsFile: URL
    /// VS Code-style state databases holding `windsurfAuthStatus`, best first.
    public var stateDatabases: [URL]

    public init(credentialsFile: URL, stateDatabases: [URL]) {
        self.credentialsFile = credentialsFile
        self.stateDatabases = stateDatabases
    }

    public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser)
        -> DevinCredentialLocations {
        let support = home.appendingPathComponent("Library/Application Support")
        return DevinCredentialLocations(
            credentialsFile: home.appendingPathComponent(".local/share/devin/credentials.toml"),
            stateDatabases: ["Devin", "Windsurf"].map {
                support.appendingPathComponent("\($0)/User/globalStorage/state.vscdb")
            })
    }
}

/// Reads one string value from a SQLite database without ever writing to it (never creates it, never takes a
/// write lock). Tests inject fixed values.
public protocol SQLiteValueReading: Sendable {
    func value(database: URL, sql: String) async -> String?
}

/// libsqlite3-backed reader. Opens `mode=ro` first (sees the WAL, so the freshest value) and falls back to
/// `immutable=1` (no locks, no -shm) when a read-only open can't attach the WAL.
public struct SQLiteReadOnlyReader: SQLiteValueReading {
    public init() {}

    public func value(database: URL, sql: String) async -> String? {
        guard FileManager.default.fileExists(atPath: database.path) else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = Self.read(database: database, sql: sql, parameters: "mode=ro")
                    ?? Self.read(database: database, sql: sql, parameters: "immutable=1")
                continuation.resume(returning: result)
            }
        }
    }

    static func read(database: URL, sql: String, parameters: String) -> String? {
        guard let path = database.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        var handle: OpaquePointer?
        defer { sqlite3_close_v2(handle) }
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2("file:\(path)?\(parameters)", &handle, flags, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(handle, 1000)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return nil }
        switch sqlite3_column_type(statement, 0) {
        case SQLITE_TEXT, SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
            let count = Int(sqlite3_column_bytes(statement, 0))
            return String(decoding: Data(bytes: bytes, count: count), as: UTF8.self)
        default:
            return nil
        }
    }
}

/// Reads Devin's daily and weekly quota and its extra-usage balance.
public struct DevinCollector: UsageCollector {
    static let service = "exa.seat_management_pb.SeatManagementService"
    static let compatibleVersion = "1.108.2"
    static let authStatusQuery = "SELECT value FROM ItemTable WHERE key = 'windsurfAuthStatus' LIMIT 1"

    public let providerID: UsageProviderID = .devin
    public let displayName = "Devin"
    public var setupHint: String { "Sign in to Devin on this Mac (run `devin auth login` or open the app)" }

    private let transport: any HTTPTransport
    private let locations: DevinCredentialLocations
    private let readFile: @Sendable (URL) -> Data?
    private let sqlite: any SQLiteValueReading

    public init(transport: any HTTPTransport = URLSessionTransport(),
                locations: DevinCredentialLocations = .standard(),
                readFile: @escaping @Sendable (URL) -> Data? = { try? Data(contentsOf: $0) },
                sqlite: any SQLiteValueReading = SQLiteReadOnlyReader()) {
        self.transport = transport
        self.locations = locations
        self.readFile = readFile
        self.sqlite = sqlite
    }

    public func isAvailable() async -> Bool {
        ([locations.credentialsFile] + locations.stateDatabases)
            .contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Every distinct credential on this Mac, CLI first.
    func credentials() async -> [DevinCredential] {
        var found: [DevinCredential] = []
        if let data = readFile(locations.credentialsFile),
           let credential = DevinCredential.parseCredentialsFile(String(decoding: data, as: UTF8.self)) {
            found.append(credential)
        }
        for database in locations.stateDatabases {
            if let value = await sqlite.value(database: database, sql: Self.authStatusQuery),
               let credential = DevinCredential.parseAppAuthStatus(value),
               !found.contains(where: { $0.apiKey == credential.apiKey && $0.server == credential.server }) {
                found.append(credential)
            }
        }
        return found
    }

    public func fetch(previous: ProviderUsage?, now: Date) async -> ProviderUsage {
        if CollectorOutcome.isBackingOff(previous, now: now) { return previous! }

        let candidates = await credentials()
        guard !candidates.isEmpty else {
            return failure(.notSignedIn, detail: "Devin isn't signed in on this Mac.", previous: previous, now: now)
        }

        var lastProblem: UsageProblem = .sessionExpired
        for credential in candidates {
            switch await HTTPReply.send(request(for: credential), with: transport, now: now) {
            case .success(let body):
                guard let mapped = DevinUsageMapper.map(body) else {
                    return failure(.unexpectedResponse("Devin usage response changed shape"), detail: nil,
                                   previous: previous, now: now)
                }
                return ProviderUsage(id: providerID, displayName: displayName, plan: mapped.plan,
                                     windows: mapped.windows, balances: mapped.balances, fetchedAt: now)
            case .unauthorized:
                continue // another stored key (the app's) may still be live
            case .rateLimited(let retry):
                return failure(.rateLimited(retryAfter: retry), detail: nil, previous: previous, now: now)
            case .failed(let reason):
                lastProblem = .unreachable(reason)
            }
        }
        if lastProblem == .sessionExpired {
            return failure(.sessionExpired, detail: "Open Devin once to renew its sign-in.", previous: previous,
                           now: now)
        }
        return failure(lastProblem, detail: nil, previous: previous, now: now)
    }

    private func request(for credential: DevinCredential) -> URLRequest {
        let url = credential.server.appendingPathComponent(Self.service).appendingPathComponent("GetUserStatus")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        let metadata: [String: String] = [
            "apiKey": credential.apiKey, "ideName": "devin", "ideVersion": Self.compatibleVersion,
            "extensionName": "devin", "extensionVersion": Self.compatibleVersion, "locale": "en",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["metadata": metadata])
        return request
    }

    private func failure(_ problem: UsageProblem, detail: String?, previous: ProviderUsage?, now: Date)
        -> ProviderUsage {
        CollectorOutcome.failure(problem, detail: detail, id: providerID, displayName: displayName,
                                 previous: previous, plan: nil, now: now)
    }
}

/// Pure mapping of `GetUserStatus`.
enum DevinUsageMapper {
    static let dayDuration: TimeInterval = 86400
    static let weekDuration: TimeInterval = 7 * 86400

    struct Mapped: Equatable {
        var plan: String?
        var windows: [UsageWindow]
        var balances: [UsageBalance]
    }

    /// `{"userStatus":{"planStatus":{"planInfo":{"planName","hideDailyQuota"},"dailyQuotaRemainingPercent",
    /// "weeklyQuotaRemainingPercent","dailyQuotaResetAtUnix","weeklyQuotaResetAtUnix","overageBalanceMicros"}}}`.
    /// Quotas arrive as percent *remaining*. Nil when there's nothing to show.
    static func map(_ data: Data) -> Mapped? {
        guard let body = UsageParsing.object(data), let status = body["userStatus"] as? [String: Any] else {
            return nil
        }
        let planStatus = status["planStatus"] as? [String: Any] ?? [:]
        let planInfo = planStatus["planInfo"] as? [String: Any] ?? [:]
        let hideDaily = planInfo["hideDailyQuota"] as? Bool == true

        var windows: [UsageWindow] = []
        let weekly = UsageParsing.number(planStatus["weeklyQuotaRemainingPercent"])
        if let weekly {
            windows.append(UsageWindow(id: "weekly", kind: .weekly, label: "Week", used: used(remaining: weekly),
                                       resetsAt: UsageParsing.date(planStatus["weeklyQuotaResetAtUnix"]),
                                       duration: weekDuration))
        }
        // A hidden daily quota is only shown when it's the only number there is.
        if let daily = UsageParsing.number(planStatus["dailyQuotaRemainingPercent"]), !hideDaily || weekly == nil {
            windows.append(UsageWindow(id: "daily", kind: .other, label: "Day", used: used(remaining: daily),
                                       resetsAt: UsageParsing.date(planStatus["dailyQuotaResetAtUnix"]),
                                       duration: dayDuration))
        }

        var balances: [UsageBalance] = []
        if let micros = UsageParsing.number(planStatus["overageBalanceMicros"]) {
            balances.append(UsageBalance(id: "extra-usage", label: "Extra usage", remaining: max(0, micros) / 1e6,
                                         used: nil, limit: nil, unit: "USD"))
        }
        guard !windows.isEmpty || !balances.isEmpty else { return nil }
        return Mapped(plan: UsageParsing.string(planInfo["planName"]), windows: windows.sortedForDisplay(),
                      balances: balances)
    }

    private static func used(remaining: Double) -> Double {
        max(0, 100 - remaining) / 100
    }
}
