import AltilloCore
import AltilloUsage
import AppKit
import Foundation
@preconcurrency import AppAuth
@preconcurrency import AppAuthCore

// Protocol reference: OpenUsage v0.8.0-beta.5, MIT, commit f7e38d7608da061e609e6d0c8285531e56c2f950.
// https://github.com/robinebers/openusage/blob/f7e38d7608da061e609e6d0c8285531e56c2f950/Sources/OpenUsage/Services/BrowserProviderLogins.swift
/// Compatibility with the providers' installed-app OAuth flows. These are public client identifiers, not secrets.
struct UsageAccountOAuthConfiguration: Sendable {
    let provider: UsageProviderID
    var clientID: String { provider == .claude ? "9d1c250a-e61b-44d9-88ed-5944d1962f5e" : "app_EMoamEEZ73f0CkXaXp7hrann" }
    var authorizationURL: URL { URL(string: provider == .claude ? "https://claude.ai/oauth/authorize" : "https://auth.openai.com/oauth/authorize")! }
    var tokenURL: URL { URL(string: provider == .claude ? "https://platform.claude.com/v1/oauth/token" : "https://auth.openai.com/oauth/token")! }
    var scopes: [String] { provider == .claude ? ["user:profile"] : ["openid", "profile", "email", "offline_access"] }
}

/// No credential-bearing redirect is followed, and no cookie/cache is shared with browsers or the CLI.
final class UsageAccountHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config, delegate: UsageAccountRedirectPolicy(), delegateQueue: nil)
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard data.count <= 1024 * 1024, let http = response as? HTTPURLResponse else { throw UsageAccountFailure.invalidResponse }
        return (data, http)
    }
}

private final class UsageAccountRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct UsageAccountTokenClient: Sendable {
    let transport: any HTTPTransport

    func exchange(provider: UsageProviderID, code: String, state: String, redirect: URL,
                  verifier: String, now: Date) async throws -> UsageAccountRecord {
        let config = UsageAccountOAuthConfiguration(provider: provider)
        var fields = ["grant_type": "authorization_code", "client_id": config.clientID,
                      "code": code, "redirect_uri": redirect.absoluteString, "code_verifier": verifier]
        if provider == .claude { fields["state"] = state }
        let body = try await tokenRequest(config, fields: fields)
        let tokens = try parseTokens(body, previous: nil, now: now)
        if provider == .claude {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!, timeoutInterval: 20)
            request.setValue("Bearer \(tokens.access)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Altillo", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await transport.send(request)
            guard response.statusCode == 200,
                  let profile = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = profile["account"] as? [String: Any], let uuid = text(account["uuid"]),
                  let email = text(account["email"]) ?? text(profile["email"]) else { throw UsageAccountFailure.invalidResponse }
            let org = profile["organization"] as? [String: Any]
            let record = UsageAccountRecord(provider: provider, label: email,
                                      remoteID: uuid + ":" + (text(org?["uuid"]) ?? ""),
                                      accessToken: tokens.access, refreshToken: tokens.refresh, expiresAt: tokens.expiry,
                                      subscriptionType: text(org?["organization_type"]), rateLimitTier: text(org?["rate_limit_tier"]))
            try await verifyUsage(record)
            return record
        }
        let claims = Self.jwtClaims(tokens.access)
        let auth = claims?["https://api.openai.com/auth"] as? [String: Any]
        guard let accountID = text(auth?["chatgpt_account_id"]) else { throw UsageAccountFailure.invalidResponse }
        let email = Self.jwtClaims(text(body["id_token"]) ?? "")?["email"] as? String
        let record = UsageAccountRecord(provider: provider, label: text(email) ?? "ChatGPT",
                                  remoteID: accountID, accessToken: tokens.access, refreshToken: tokens.refresh,
                                  expiresAt: tokens.expiry, accountID: accountID)
        try await verifyUsage(record)
        return record
    }

    private func verifyUsage(_ record: UsageAccountRecord) async throws {
        var request = URLRequest(url: record.provider == .claude ? ClaudeCollector.usageURL : CodexCollector.whamURL,
                                 timeoutInterval: 20)
        request.setValue("Bearer \(record.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Altillo", forHTTPHeaderField: "User-Agent")
        if record.provider == .claude { request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta") }
        if let id = record.accountID { request.setValue(id, forHTTPHeaderField: "ChatGPT-Account-Id") }
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw UsageAccountFailure.temporary(response.statusCode) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              record.provider == .claude ? (object.keys.contains("five_hour") || object.keys.contains("seven_day")) :
                (object["rate_limit"] is [String: Any] || object["additional_rate_limits"] is [Any]) else {
            throw UsageAccountFailure.invalidResponse
        }
    }

    func refresh(_ record: UsageAccountRecord, now: Date) async throws -> UsageAccountRecord {
        let config = UsageAccountOAuthConfiguration(provider: record.provider)
        var fields = ["grant_type": "refresh_token", "client_id": config.clientID, "refresh_token": record.refreshToken]
        if record.provider == .claude { fields["scope"] = "user:profile" }
        let body = try await tokenRequest(config, fields: fields)
        let tokens = try parseTokens(body, previous: record, now: now)
        var renewed = record
        renewed.accessToken = tokens.access
        renewed.refreshToken = tokens.refresh
        renewed.expiresAt = tokens.expiry
        if record.provider == .codex,
           let auth = Self.jwtClaims(tokens.access)?["https://api.openai.com/auth"] as? [String: Any],
           let account = text(auth["chatgpt_account_id"]), account != record.accountID {
            // A refresh cannot silently turn the selected provider into another account.
            throw UsageAccountFailure.sessionExpired
        }
        return renewed
    }

    private func tokenRequest(_ config: UsageAccountOAuthConfiguration, fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: config.tokenURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Altillo", forHTTPHeaderField: "User-Agent")
        if config.provider == .claude {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        } else {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.form(fields)
        }
        let (data, response) = try await transport.send(request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(response.statusCode) else {
            let terminal = Set(["invalid_grant", "refresh_token_expired", "refresh_token_reused", "refresh_token_invalidated"])
            if terminal.contains((object?["error"] as? String) ?? "") {
                throw UsageAccountFailure.sessionExpired
            }
            throw UsageAccountFailure.temporary(response.statusCode)
        }
        guard let object else { throw UsageAccountFailure.invalidResponse }
        if config.provider == .claude, let scopes = object["scope"] as? String,
           !scopes.split(separator: " ").contains("user:profile") { throw UsageAccountFailure.sessionExpired }
        return object
    }
    private func parseTokens(_ body: [String: Any], previous: UsageAccountRecord?, now: Date)
        throws -> (access: String, refresh: String, expiry: Date) {
        guard let access = text(body["access_token"]),
              let refresh = text(body["refresh_token"]) ?? previous?.refreshToken else { throw UsageAccountFailure.invalidResponse }
        let expiry: Date
        if let seconds = body["expires_in"] as? NSNumber, seconds.doubleValue > 0, seconds.doubleValue.isFinite {
            expiry = now.addingTimeInterval(seconds.doubleValue)
        } else if let exp = Self.jwtClaims(access)?["exp"] as? NSNumber, exp.doubleValue.isFinite {
            expiry = Date(timeIntervalSince1970: exp.doubleValue)
        } else { throw UsageAccountFailure.invalidResponse }
        guard expiry > now else { throw UsageAccountFailure.sessionExpired }
        return (access, refresh, expiry)
    }
    private func text(_ value: Any?) -> String? {
        guard let value = value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= 64 * 1024,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return value
    }
    static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(fields.sorted { $0.key < $1.key }.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
    /// JWT claims are identity hints from the token endpoint, never a local authorization decision.
    static func jwtClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[1].count <= 128 * 1024 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

@MainActor protocol UsageAccountAuthorizing: AnyObject {
    func authorize(_ provider: UsageProviderID) async throws -> UsageAccountRecord
    func cancel()
    func completeConnection(success: Bool)
}

extension UsageAccountAuthorizing {
    func completeConnection(success: Bool) {}
}

@MainActor final class UsageAccountOAuth: UsageAccountAuthorizing {
    private let transport: any HTTPTransport
    private var handler: OIDRedirectHTTPHandler?
    private var authorization: (any OIDExternalUserAgentSession)?
    private var cancelPending: ((UsageAccountFailure) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var returnPage: UsageAccountReturnServer?
    init(transport: any HTTPTransport = UsageAccountHTTPTransport()) { self.transport = transport }

    func authorize(_ provider: UsageProviderID) async throws -> UsageAccountRecord {
        guard [.claude, .codex].contains(provider) else { throw UsageAccountFailure.unsupported }
        guard authorization == nil else { throw UsageAccountFailure.operationInProgress }
        let config = UsageAccountOAuthConfiguration(provider: provider)
        returnPage?.stop()
        let page = UsageAccountReturnServer(provider: provider == .claude ? "Claude" : "Codex")
        let successURL = try page.start()
        returnPage = page
        let listener = OIDRedirectHTTPHandler(successURL: successURL)
        var error: NSError?
        let base = listener.startHTTPListener(&error, withPort: provider == .codex ? 1455 : 0)
        guard error == nil else { throw provider == .codex ? UsageAccountFailure.callbackPortBusy : .unavailable }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.host = "localhost"
        components.path = provider == .codex ? "/auth/callback" : "/callback"
        guard let redirect = components.url else { listener.cancelHTTPListener(); throw UsageAccountFailure.invalidResponse }
        handler = listener
        defer { timeoutTask?.cancel(); timeoutTask = nil; listener.cancelHTTPListener(); handler = nil; authorization = nil; cancelPending = nil }
        let service = OIDServiceConfiguration(authorizationEndpoint: config.authorizationURL, tokenEndpoint: config.tokenURL)
        let extras = provider == .claude ? ["code": "true"] :
            ["id_token_add_organizations": "true", "codex_cli_simplified_flow": "true", "originator": "altillo"]
        let request = OIDAuthorizationRequest(configuration: service, clientId: config.clientID, clientSecret: nil,
                                               scopes: config.scopes, redirectURL: redirect,
                                               responseType: OIDResponseTypeCode, additionalParameters: extras)
        let code: String = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let gate = UsageAccountCallbackGate(continuation)
                cancelPending = { gate.finish(.failure($0)) }
                // This HTTP callback belongs to our listener, so open a browser rather than an
                // ASWebAuthenticationSession that expects to own the callback.
                let browser = UsageAccountBrowserAgent(browser: UserDefaults.standard.string(forKey: "usageSignInBrowser") ?? "system")
                authorization = OIDAuthorizationService.present(request, externalUserAgent: browser) { response, error in
                    let payload = UsageAccountAuthorizationPayload(code: response?.authorizationCode,
                                                                    state: response?.state, error: error)
                    Task { @MainActor in
                        do { gate.finish(.success(try Self.validatedCallback(code: payload.code, state: payload.state, expectedState: request.state))) }
                        catch { gate.finish(.failure(error)) }
                    }
                }
                listener.currentAuthorizationFlow = authorization
                timeoutTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(30 * 60)) } catch { return }
                    if self?.handler === listener { self?.finish(.timedOut) }
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
        try Task.checkCancellation()
        guard let verifier = request.codeVerifier, let state = request.state else { throw UsageAccountFailure.invalidResponse }
        return try await UsageAccountTokenClient(transport: transport).exchange(provider: provider, code: code,
                                                                              state: state, redirect: redirect,
                                                                              verifier: verifier, now: .now)
    }
    static func validatedCallback(code: String?, state: String?, expectedState: String?) throws -> String {
        guard let code, !code.isEmpty, code.utf8.count <= 64 * 1024,
              let expectedState, !expectedState.isEmpty, state == expectedState else {
            throw UsageAccountFailure.cancelled
        }
        return code
    }

    func completeConnection(success: Bool) { returnPage?.complete(success: success) }

    func cancel() { finish(.cancelled) }

    private func finish(_ reason: UsageAccountFailure) {
        returnPage?.complete(success: false)
        timeoutTask?.cancel()
        timeoutTask = nil
        cancelPending?(reason)
        authorization?.cancel()
        handler?.cancelHTTPListener()
    }
}

/// SDK callback objects remain on the main actor; only immutable strings cross its callback boundary.
private struct UsageAccountAuthorizationPayload: @unchecked Sendable {
    let code: String?
    let state: String?
    let error: Error?
}
@MainActor private final class UsageAccountCallbackGate {
    private var continuation: CheckedContinuation<String, Error>?
    init(_ continuation: CheckedContinuation<String, Error>) { self.continuation = continuation }
    func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

/// Opens the selected browser without changing macOS defaults or embedding the provider's sign-in UI.
final class UsageAccountBrowserAgent: NSObject, OIDExternalUserAgent, @unchecked Sendable {
    private let browser: String
    init(browser: String) { self.browser = browser }

    static func allows(_ url: URL) -> Bool {
        url.scheme == "https" && ["claude.ai", "auth.openai.com"].contains(url.host ?? "")
            && url.path == "/oauth/authorize" && (url.port == nil || url.port == 443)
            && url.user == nil && url.password == nil
    }

    func present(_ request: any OIDExternalUserAgentRequest, session: any OIDExternalUserAgentSession) -> Bool {
        MainActor.assumeIsolated {
            guard let url = request.externalUserAgentRequestURL(), Self.allows(url) else { return false }
            guard browser == "chrome" else { return NSWorkspace.shared.open(url) }
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else { return false }
            let failure = UsageAccountBrowserFailure(session: session)
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error != nil { Task { @MainActor in failure.report() } }
            }
            return true
        }
    }

    func dismiss(animated: Bool, completion: @escaping @Sendable () -> Void) { completion() }
}

@MainActor private final class UsageAccountBrowserFailure {
    private let session: any OIDExternalUserAgentSession
    init(session: any OIDExternalUserAgentSession) { self.session = session }
    func report() { session.failExternalUserAgentFlowWithError(UsageAccountFailure.unavailable) }
}
