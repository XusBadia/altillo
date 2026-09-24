import AltilloCore
import Foundation

// Small helpers shared by the Grok, Gemini, Devin and OpenCode collectors. Everything here is read-only: nothing
// writes, refreshes or deletes another tool's credentials.

// MARK: - Results

enum CollectorOutcome {
    /// Keeps the last good numbers (stale-while-revalidate) and records why this attempt failed.
    static func failure(_ problem: UsageProblem, detail: String?, id: UsageProviderID, displayName: String,
                        previous: ProviderUsage?, plan: String?, now: Date) -> ProviderUsage {
        var usage = previous ?? ProviderUsage(id: id, displayName: displayName, plan: plan, windows: [],
                                              fetchedAt: now)
        usage.problem = problem
        usage.problemDetail = detail
        if let plan { usage.plan = plan }
        return usage
    }

    /// A pending Retry-After from the last attempt: asking again early only extends the provider's rate limiting.
    static func isBackingOff(_ previous: ProviderUsage?, now: Date) -> Bool {
        guard let previous, case .rateLimited(let until?) = previous.problem else { return false }
        return now < until
    }
}

// MARK: - HTTP

/// What a provider's HTTP answer means for a collector.
enum HTTPReply: Equatable {
    case success(Data)
    /// 401/403: the credential was rejected.
    case unauthorized(status: Int, body: Data)
    case rateLimited(retryAfter: Date)
    /// Transport error or an unexpected status, already phrased for `UsageProblem.unreachable`.
    case failed(String)

    /// Sends `request` and classifies the answer. 429 without a readable Retry-After backs off five minutes.
    static func send(_ request: URLRequest, with transport: any HTTPTransport, now: Date) async -> HTTPReply {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            return .failed(ClaudeCollector.describe(error))
        }
        switch response.statusCode {
        case 200..<300:
            return .success(data)
        case 401, 403:
            return .unauthorized(status: response.statusCode, body: data)
        case 429:
            let retry = UsageParsing.retryAfter(response.header("Retry-After"), now: now)
                ?? now.addingTimeInterval(5 * 60)
            return .rateLimited(retryAfter: retry)
        default:
            return .failed("HTTP \(response.statusCode)")
        }
    }
}

/// An `HTTPTransport` for a local language server on 127.0.0.1 that serves a self-signed certificate. Server
/// trust is waived only for loopback hosts; every other host keeps the system's default validation.
public struct LoopbackTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.connectionProxyDictionary = [:] // never send loopback traffic through a proxy
        session = URLSession(configuration: configuration, delegate: LoopbackTrustDelegate(), delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let host = request.url?.host, LoopbackTrustDelegate.isLoopback(host) else {
            throw URLError(.unsupportedURL)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

final class LoopbackTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    static func isLoopback(_ host: String) -> Bool {
        ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host.lowercased())
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust, Self.isLoopback(space.host),
              let trust = space.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}

// MARK: - Keychain

/// Result of reading one generic-password item.
enum KeychainLookup: Equatable {
    case found(String)
    case notFound
    /// The keychain refused (or a prompt went unanswered).
    case accessDenied
}

/// Reads a generic password with `/usr/bin/security find-generic-password … -w`, like `ClaudeCredentialStore`:
/// items created through that binary (go-keyring, most CLIs) trust it, so no keychain prompt appears. Read-only.
struct SecurityKeychainReader {
    let runner: any CommandRunning

    func password(service: String, account: String?) async -> KeychainLookup {
        var arguments = ["find-generic-password", "-s", service]
        if let account { arguments += ["-a", account] }
        arguments.append("-w")
        guard let result = await runner.run(ClaudeCredentialStore.securityTool, arguments: arguments, timeout: 10)
        else { return .notFound }
        if result.status == 0 {
            let text = String(decoding: result.stdout, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? .notFound : .found(text)
        }
        if result.timedOut || result.status != ClaudeCredentialStore.notFoundStatus { return .accessDenied }
        return .notFound
    }
}

// MARK: - Tokens and paths

enum TokenParsing {
    /// The `exp` claim of a JWT, without verifying it (only used to skip tokens that are certainly dead).
    static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64), let payload = UsageParsing.object(data),
              let exp = UsageParsing.number(payload["exp"]) else { return nil }
        return UsageParsing.epochDate(exp)
    }

    /// `go-keyring-base64:<base64>` (how go-keyring stores values on macOS) → the decoded text; other values pass
    /// through trimmed. Nil for an empty value or undecodable base64.
    static func unwrapGoKeyring(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
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
}

enum ProviderPaths {
    /// A non-empty environment value, tilde-expanded.
    static func directory(_ name: String, in environment: [String: String]) -> URL? {
        guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
    }
}
