import AltilloCore
import Foundation

// OpenCode Go usage from opencode.ai, with the `opencode-go` key OpenCode keeps in its own auth.json (read-only).
//
// Adapted from openusage (MIT), Sources/OpenUsage/Providers/OpenCode/{OpenCodePaths,OpenCodeAuthStore,
// OpenCodeUsageClient,OpenCodeUsageMapper,OpenCodeProvider}.swift@87c3d2db465a5eb6c6dd2c2453c55cd82141a76e: the
// data-directory resolution, the endpoint, the rolling/weekly/monthly shape and the EntitlementError meaning.
// See ThirdPartyNotices/README.md.

extension UsageProviderID {
    public static let opencode = UsageProviderID(rawValue: "opencode")
}

/// Where OpenCode keeps its data, and the Go key inside it.
public enum OpenCodeAuth {
    /// `$OPENCODE_DATA_DIR`, else `$XDG_DATA_HOME/opencode`, else `~/.local/share/opencode` (OpenCode's own order).
    public static func dataDirectory(environment: [String: String] = ProcessInfo.processInfo.environment,
                                     home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let override = ProviderPaths.directory("OPENCODE_DATA_DIR", in: environment) { return override }
        if let xdg = ProviderPaths.directory("XDG_DATA_HOME", in: environment) {
            return xdg.appendingPathComponent("opencode", isDirectory: true)
        }
        return home.appendingPathComponent(".local/share/opencode", isDirectory: true)
    }

    public static func defaultFile(environment: [String: String] = ProcessInfo.processInfo.environment,
                                   home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        dataDirectory(environment: environment, home: home).appendingPathComponent("auth.json")
    }

    /// What `auth.json` holds for OpenCode Go.
    public enum Lookup: Sendable, Hashable {
        case key(String)
        /// Signed in to OpenCode (other providers) but not to OpenCode Go.
        case noGoKey
        /// Present but not a JSON object.
        case unreadable
    }

    /// `{"opencode-go": {"type": "api", "key": "…"}, …}`. Other entries are ignored.
    public static func parse(_ data: Data) -> Lookup {
        guard let root = UsageParsing.object(data) else { return .unreadable }
        guard let entry = root["opencode-go"] as? [String: Any], let key = UsageParsing.string(entry["key"]) else {
            return .noGoKey
        }
        return .key(key)
    }
}

/// Reads OpenCode Go's rolling (5-hour), weekly and monthly limits.
public struct OpenCodeCollector: UsageCollector {
    public static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    public let providerID: UsageProviderID = .opencode
    public let displayName = "OpenCode"
    public var setupHint: String { "Sign in to OpenCode Go in OpenCode on this Mac" }

    private let transport: any HTTPTransport
    private let authFile: URL
    private let readFile: @Sendable (URL) -> Data?

    public init(transport: any HTTPTransport = URLSessionTransport(),
                authFile: URL = OpenCodeAuth.defaultFile(),
                readFile: @escaping @Sendable (URL) -> Data? = { try? Data(contentsOf: $0) }) {
        self.transport = transport
        self.authFile = authFile
        self.readFile = readFile
    }

    /// Only an OpenCode Go key has limits to read.
    public func isAvailable() async -> Bool {
        guard let data = readFile(authFile), case .key = OpenCodeAuth.parse(data) else { return false }
        return true
    }

    public func fetch(previous: ProviderUsage?, now: Date) async -> ProviderUsage {
        if CollectorOutcome.isBackingOff(previous, now: now) { return previous! }

        guard let data = readFile(authFile) else {
            return failure(.notSignedIn, detail: "OpenCode isn't signed in on this Mac.", previous: previous,
                           now: now)
        }
        let key: String
        switch OpenCodeAuth.parse(data) {
        case .key(let found):
            key = found
        case .noGoKey:
            return failure(.notSignedIn,
                           detail: "OpenCode isn't signed in to OpenCode Go, the only OpenCode plan with usage limits.",
                           previous: previous, now: now)
        case .unreadable:
            return failure(.notSignedIn, detail: "OpenCode's auth.json couldn't be read. Sign in to OpenCode Go again.",
                           previous: previous, now: now)
        }

        var request = URLRequest(url: Self.usageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Altillo", forHTTPHeaderField: "User-Agent")

        switch await HTTPReply.send(request, with: transport, now: now) {
        case .success(let body):
            guard let windows = OpenCodeUsageMapper.map(body) else {
                return failure(.unexpectedResponse("OpenCode usage response changed shape"), detail: nil,
                               previous: previous, now: now)
            }
            return ProviderUsage(id: providerID, displayName: displayName, plan: "Go", windows: windows,
                                 fetchedAt: now)
        case .unauthorized(let status, let body):
            if status == 403, OpenCodeUsageMapper.errorType(body) == "EntitlementError" {
                // A valid key without a Go subscription: nothing to show, and last numbers no longer apply.
                return failure(.notSignedIn, detail: "This OpenCode account has no OpenCode Go subscription.",
                               previous: nil, now: now)
            }
            return failure(.notSignedIn, detail: "OpenCode rejected its Go key. Sign in to OpenCode Go again.",
                           previous: previous, now: now)
        case .rateLimited(let retry):
            return failure(.rateLimited(retryAfter: retry), detail: nil, previous: previous, now: now)
        case .failed(let reason):
            return failure(.unreachable(reason), detail: nil, previous: previous, now: now)
        }
    }

    private func failure(_ problem: UsageProblem, detail: String?, previous: ProviderUsage?, now: Date)
        -> ProviderUsage {
        CollectorOutcome.failure(problem, detail: detail, id: providerID, displayName: displayName,
                                 previous: previous, plan: nil, now: now)
    }
}

/// Pure mapping of `GET /zen/go/v1/usage`.
enum OpenCodeUsageMapper {
    static let sessionDuration: TimeInterval = 5 * 3600
    static let weekDuration: TimeInterval = 7 * 86400
    static let monthDuration: TimeInterval = 30 * 86400

    /// `{"usage":{"rolling":{"percent":12,"resetsAt":"…"},"weekly":{…},"monthly":{…}}}`. Missing windows are
    /// skipped; nil when none is readable.
    static func map(_ data: Data) -> [UsageWindow]? {
        guard let body = UsageParsing.object(data), let usage = body["usage"] as? [String: Any] else { return nil }
        let specs: [(key: String, id: String, kind: UsageWindow.Kind, label: String, duration: TimeInterval)] = [
            ("rolling", "session", .session, "Session", sessionDuration),
            ("weekly", "weekly", .weekly, "Week", weekDuration),
            ("monthly", "monthly", .monthly, "Month", monthDuration),
        ]
        let windows = specs.compactMap { spec -> UsageWindow? in
            guard let object = usage[spec.key] as? [String: Any],
                  let percent = UsageParsing.number(object["percent"]) else { return nil }
            return UsageWindow(id: spec.id, kind: spec.kind, label: spec.label, used: max(0, percent) / 100,
                               resetsAt: UsageParsing.date(object["resetsAt"]), duration: spec.duration)
        }
        return windows.isEmpty ? nil : windows
    }

    /// `{"type":"error","error":{"type":"EntitlementError","message":"…"}}` → "EntitlementError".
    static func errorType(_ data: Data) -> String? {
        guard let body = UsageParsing.object(data), let error = body["error"] as? [String: Any] else { return nil }
        return UsageParsing.string(error["type"])
    }
}
