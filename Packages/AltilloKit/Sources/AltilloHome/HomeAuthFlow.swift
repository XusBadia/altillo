import CryptoKit
import Foundation
import Network
import Synchronization
#if canImport(AppKit)
import AppKit
#endif

/// "Sign in with Home Assistant" without a website of ours: OAuth authorization code + PKCE (RFC 7636) with a
/// loopback redirect (RFC 8252).
///
/// A one-shot listener on 127.0.0.1:<ephemeral port> is both the `client_id` (`http://127.0.0.1:<port>/`) and the
/// redirect (`…/callback`). Same scheme, host and port, so Home Assistant accepts the redirect without fetching
/// anything. The browser signs in on HA's own page, comes back with a code, we trade it for an access token and use
/// that once to mint a long-lived token over the WebSocket (`auth/long_lived_access_token`), which is what
/// `HomeAssistantClient.connect(_:token:)` keeps in the Keychain. The short-lived session is revoked afterwards.
/// Tokens are never logged.
@MainActor
public final class HomeAuthFlow {
    public static let timeout: Duration = .seconds(5 * 60)

    private let open: @MainActor (URL) -> Bool
    private let activate: @MainActor () -> Void
    private let httpFactory: @Sendable (String?) -> any HomeHTTP
    private let socketFactory: HomeSocketFactory
    private let clientName: String
    private let timeout: Duration
    private var attempt: HomeLoopbackServer?

    public convenience init() {
        #if canImport(AppKit)
        self.init(open: { NSWorkspace.shared.open($0) }, activate: { NSApplication.shared.activate() })
        #else
        self.init(open: { _ in false }, activate: {})
        #endif
    }

    init(open: @escaping @MainActor (URL) -> Bool, activate: @escaping @MainActor () -> Void = {},
         httpFactory: @escaping @Sendable (String?) -> any HomeHTTP = { URLSessionHomeHTTP(pinnedSHA256: $0) },
         socketFactory: @escaping HomeSocketFactory = URLSessionHomeSocket.make,
         clientName: String = HomeAuthFlow.defaultClientName, timeout: Duration = HomeAuthFlow.timeout) {
        self.open = open
        self.activate = activate
        self.httpFactory = httpFactory
        self.socketFactory = socketFactory
        self.clientName = clientName
        self.timeout = timeout
    }

    /// A sign-in is waiting for the browser.
    public var isSigningIn: Bool { attempt != nil }

    /// Opens Home Assistant's sign-in page in the browser and returns a long-lived access token once the user signs
    /// in. Throws `CancellationError` after `cancel()` (or when the calling task is cancelled), otherwise a
    /// `HomeServiceError` with a user-facing message. `url` is the server's base URL (as `HomeServerConfig.url`).
    public func signIn(to url: URL, pinnedCertificateSHA256: String? = nil) async throws -> String {
        cancel()
        let server = HomeLoopbackServer()
        attempt = server
        defer {
            server.stop()
            if attempt === server { attempt = nil }
        }
        return try await withTaskCancellationHandler {
            let port = try await server.start()
            let pkce = HomePKCE()
            let state = HomePKCE.randomURLSafe(bytes: 16)
            let request = HomeAuthRequest(server: url, port: port)
            server.expect(state: state)
            guard open(request.authorizeURL(state: state, challenge: pkce.challenge)) else {
                throw HomeServiceError(HomeStrings.browserFailed)
            }
            let timer = Task { [timeout] in
                try? await Task.sleep(for: timeout)
                if !Task.isCancelled { server.finish(.timedOut) }
            }
            defer { timer.cancel() }
            let code: String
            switch await server.outcome() {
            case .code(let value): code = value
            case .denied: throw HomeServiceError(HomeStrings.signInDenied)
            case .failed: throw HomeServiceError(HomeStrings.signInIncomplete)
            case .timedOut: throw HomeServiceError(HomeStrings.signInTimedOut)
            case .cancelled: throw CancellationError()
            }
            activate()
            let http = httpFactory(pinnedCertificateSHA256)
            let tokens = try await http.exchange(request.tokenRequest(code: code, verifier: pkce.verifier))
            try Task.checkCancellation()
            let longLived: String
            do {
                longLived = try await mintLongLivedToken(server: url, accessToken: tokens.access,
                                                         pinnedSHA256: pinnedCertificateSHA256)
            } catch {
                if let refresh = tokens.refresh { await http.revoke(request.revokeRequest(refreshToken: refresh)) }
                throw error
            }
            if let refresh = tokens.refresh { await http.revoke(request.revokeRequest(refreshToken: refresh)) }
            return longLived
        } onCancel: {
            server.finish(.cancelled)
        }
    }

    /// Stops a sign-in that's waiting for the browser; `signIn` throws `CancellationError`.
    public func cancel() {
        attempt?.finish(.cancelled)
        attempt = nil
    }

    /// "Altillo (Xus's MacBook Pro)": how the token is listed in the user's HA profile.
    public nonisolated static var defaultClientName: String {
        #if os(macOS)
        if let name = Host.current().localizedName, !name.isEmpty { return "Altillo (\(name))" }
        #endif
        return "Altillo"
    }

    private func mintLongLivedToken(server: URL, accessToken: String, pinnedSHA256: String?) async throws -> String {
        let socket = socketFactory(HAMapping.websocketURL(for: server), HomeTrustDelegate(pinnedSHA256: pinnedSHA256))
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(15))
            if !Task.isCancelled { await socket.close() }
        }
        defer {
            watchdog.cancel()
            Task { await socket.close() }
        }
        do {
            return try await HomeAuthRequest.longLivedToken(over: socket, accessToken: accessToken, clientName: clientName)
        } catch let error as HomeServiceError {
            throw error
        } catch {
            throw HomeServiceError(HomeStrings.signInIncomplete)
        }
    }
}

// MARK: - PKCE

/// RFC 7636 S256: a 43-character verifier and its SHA-256, both base64url without padding.
struct HomePKCE: Sendable {
    let verifier: String
    var challenge: String { Self.challenge(for: verifier) }

    init(verifier: String = HomePKCE.randomURLSafe(bytes: 32)) { self.verifier = verifier }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func randomURLSafe(bytes count: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Requests and answers (pure, tested)

struct HomeAuthTokens: Equatable, Sendable {
    var access: String
    var refresh: String?
}

/// What came back to the loopback callback.
enum HomeAuthCallback: Equatable, Sendable {
    case code(String)
    /// `error=access_denied`: the user said no.
    case denied
    /// Some other `error=`, or a callback without a code.
    case failed
    /// Not our `state`: a stray or forged request. Answered and ignored; the sign-in keeps waiting.
    case stateMismatch

    var isTerminal: Bool { self != .stateMismatch }
}

struct HomeAuthRequest: Sendable {
    let server: URL
    let port: UInt16

    var clientID: String { "http://127.0.0.1:\(port)/" }
    var redirectURI: String { "http://127.0.0.1:\(port)/callback" }

    func authorizeURL(state: String, challenge: String) -> URL {
        var components = URLComponents(url: server.appending(path: "auth/authorize"), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = Self.form([
            ("response_type", "code"), ("client_id", clientID), ("redirect_uri", redirectURI), ("state", state),
            ("code_challenge", challenge), ("code_challenge_method", "S256"),
        ])
        return components.url!
    }

    func tokenRequest(code: String, verifier: String) -> URLRequest {
        post("auth/token", [("grant_type", "authorization_code"), ("code", code), ("client_id", clientID),
                            ("code_verifier", verifier)])
    }

    func revokeRequest(refreshToken: String) -> URLRequest {
        post("auth/revoke", [("token", refreshToken)])
    }

    private func post(_ path: String, _ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: server.appending(path: path), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(Self.form(fields).utf8)
        return request
    }

    /// application/x-www-form-urlencoded, encoding everything but RFC 3986 unreserved characters.
    static func form(_ fields: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(.init(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
        allowed.insert(charactersIn: "-._~")
        func encode(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text }
        return fields.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
    }

    /// The request target of a GET to the loopback ("/callback?code=…&state=…"). Nil for anything that isn't the
    /// callback (the client_id page, a favicon).
    static func callback(target: String, expectedState: String) -> HomeAuthCallback? {
        guard let components = URLComponents(string: "http://127.0.0.1\(target.hasPrefix("/") ? target : "/" + target)"),
              components.path == "/callback" else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let state = value("state"), constantTimeEqual(state, expectedState) else { return .stateMismatch }
        if let error = value("error") { return error == "access_denied" ? .denied : .failed }
        guard let code = value("code"), !code.isEmpty else { return .failed }
        return .code(code)
    }

    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let left = Array(a.utf8), right = Array(b.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// The answer of `POST /auth/token`.
    static func tokens(status: Int, body: Data) throws -> HomeAuthTokens {
        let json = try? JSONValue.decode(String(decoding: body, as: UTF8.self))
        if status == 200, let access = json?["access_token"]?.string, !access.isEmpty {
            return HomeAuthTokens(access: access, refresh: json?["refresh_token"]?.string)
        }
        if let description = json?["error_description"]?.string ?? json?["error"]?.string, !description.isEmpty {
            throw HomeServiceError(HomeStrings.haSaid(description))
        }
        throw HomeServiceError(HomeStrings.signInIncomplete)
    }

    /// Authenticates the socket with the short-lived token and asks for a 10-year token named `clientName`. HA keeps
    /// one token per name, so a second sign-in from the same Mac retries once with the date added.
    static func longLivedToken(over socket: any HomeSocket, accessToken: String, clientName: String,
                               now: Date = .now) async throws -> String {
        guard try JSONValue.decode(await socket.receive())["type"]?.string == "auth_required" else {
            throw HomeServiceError(HomeStrings.unexpected)
        }
        try await socket.send(JSONValue.object(["type": "auth", "access_token": .string(accessToken)]).encodedString())
        guard try JSONValue.decode(await socket.receive())["type"]?.string == "auth_ok" else {
            throw HomeServiceError(HomeStrings.signInIncomplete)
        }
        let stamp = now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .dateSeparator(.dash).timeSeparator(.colon).dateTimeSeparator(.space))
        var lastError = HomeServiceError(HomeStrings.unexpected)
        for (index, name) in [clientName, "\(clientName) · \(stamp)"].enumerated() {
            let id = index + 1
            let message: JSONValue = ["id": .number(Double(id)), "type": "auth/long_lived_access_token",
                                      "client_name": .string(name), "lifespan": 3650]
            try await socket.send(message.encodedString())
            var reply: JSONValue
            repeat { reply = try JSONValue.decode(await socket.receive()) } while reply["id"]?.int != id
            if reply["success"]?.bool == true, let token = reply["result"]?.string, !token.isEmpty { return token }
            if let text = reply["error"]?["message"]?.string, !text.isEmpty { lastError = HomeServiceError(HomeStrings.haSaid(text)) }
        }
        throw lastError
    }

    /// The small page the browser shows after the redirect, in the user's language.
    static func page(success: Bool) -> String {
        let title = success ? HomeStrings.signInPageDone : HomeStrings.signInPageFailed
        let detail = success ? HomeStrings.signInPageClose : ""
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <title>Altillo</title><style>
        html,body{height:100%;margin:0}
        body{display:flex;align-items:center;justify-content:center;background:radial-gradient(circle at 50% 30%,#3a2c20,#1c1611 70%);
        color:#f3e7d3;font:15px -apple-system,BlinkMacSystemFont,"SF Pro Rounded",sans-serif}
        main{text-align:center;padding:40px 48px;border-radius:22px;background:rgba(255,240,220,.05);
        border:1px solid rgba(255,230,200,.14);box-shadow:0 20px 60px rgba(0,0,0,.45)}
        .bulb{width:26px;height:26px;margin:0 auto 18px;border-radius:50%;background:\(success ? "#f6c46b" : "#7a6a58");
        box-shadow:0 0 \(success ? "34px 10px rgba(246,196,107,.45)" : "0 0 transparent")}
        h1{font-size:20px;font-weight:650;margin:0 0 6px}p{margin:0;color:#c8b79e}
        </style></head><body><main><div class="bulb"></div><h1>\(escape(title))</h1><p>\(escape(detail))</p></main></body></html>
        """
    }
}

// MARK: - HTTP

/// The two HTTP calls of the sign-in. URLSession in the app, a fake in tests.
protocol HomeHTTP: Sendable {
    func send(_ request: URLRequest) async throws -> (status: Int, body: Data)
}

extension HomeHTTP {
    func exchange(_ request: URLRequest) async throws -> HomeAuthTokens {
        let answer: (status: Int, body: Data)
        do {
            answer = try await send(request)
        } catch {
            if HAMapping.isLocalNetworkDenied(error) { throw HomeServiceError(HomeStrings.localNetworkDenied) }
            if HAMapping.isInsecureRemote(error) { throw HomeServiceError(HomeStrings.insecureRemote) }
            throw HomeServiceError(HomeStrings.notFound)
        }
        return try HomeAuthRequest.tokens(status: answer.status, body: answer.body)
    }

    /// Best effort: the short-lived session isn't needed once the long-lived token exists.
    func revoke(_ request: URLRequest) async {
        _ = try? await send(request)
    }
}

/// An ephemeral session that trusts the system or the pinned certificate (same rules as the socket) and never
/// follows redirects.
final class URLSessionHomeHTTP: HomeHTTP {
    private let session: URLSession

    init(pinnedSHA256: String?) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration, delegate: HomeTrustDelegate(pinnedSHA256: pinnedSHA256),
                             delegateQueue: nil)
    }

    deinit { session.finishTasksAndInvalidate() }

    func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

// MARK: - Loopback listener

/// A tiny HTTP/1.1 server on 127.0.0.1 for one sign-in. Answers `/` (the client_id page), `/callback` (the
/// redirect) and 404 for anything else. Closed by `stop()`, which `signIn` always calls.
final class HomeLoopbackServer: Sendable {
    enum Outcome: Equatable, Sendable {
        case code(String), denied, failed, timedOut, cancelled
    }

    private struct State {
        var listener: NWListener?
        var ready: CheckedContinuation<UInt16, any Error>?
        var waiter: CheckedContinuation<Outcome, Never>?
        var outcome: Outcome?
        var expectedState: String?
        var connections: [ObjectIdentifier: NWConnection] = [:]
    }

    private let queue = DispatchQueue(label: "me.badia.altillo.home.auth")
    private let state = Mutex(State())

    /// Listens on an ephemeral loopback port and returns it.
    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.acceptLocalOnly = true
        parameters.allowLocalEndpointReuse = false
        let listener: NWListener
        do { listener = try NWListener(using: parameters) } catch { throw HomeServiceError(HomeStrings.signInStartFailed) }
        return try await withCheckedThrowingContinuation { continuation in
            let alreadyFinished = state.withLock { state -> Bool in
                if state.outcome != nil { return true }
                state.listener = listener
                state.ready = continuation
                return false
            }
            if alreadyFinished { return continuation.resume(throwing: CancellationError()) }
            listener.stateUpdateHandler = { [weak self, weak listener] newState in
                switch newState {
                case .ready:
                    self?.resumeReady(.success(listener?.port?.rawValue ?? 0))
                case .failed, .cancelled:
                    self?.resumeReady(.failure(HomeServiceError(HomeStrings.signInStartFailed)))
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
        }
    }

    func expect(state expected: String) {
        state.withLock { $0.expectedState = expected }
    }

    /// Waits for the callback, a timeout or a cancel, whichever comes first.
    func outcome() async -> Outcome {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> Outcome? in
                if let outcome = state.outcome { return outcome }
                state.waiter = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    /// Settles the outcome (first one wins).
    func finish(_ outcome: Outcome) {
        let (waiter, ready) = state.withLock { state -> (CheckedContinuation<Outcome, Never>?, CheckedContinuation<UInt16, any Error>?) in
            guard state.outcome == nil else { return (nil, nil) }
            state.outcome = outcome
            defer { state.waiter = nil; state.ready = nil }
            return (state.waiter, state.ready)
        }
        waiter?.resume(returning: outcome)
        ready?.resume(throwing: outcome == .cancelled ? CancellationError() : HomeServiceError(HomeStrings.signInStartFailed))
    }

    func stop() {
        finish(.cancelled)
        let (listener, connections) = state.withLock { state in
            defer { state.listener = nil; state.connections.removeAll() }
            return (state.listener, Array(state.connections.values))
        }
        listener?.cancel()
        // Let a page that's being sent finish; anything still open after a moment goes.
        queue.asyncAfter(deadline: .now() + 2) { connections.forEach { $0.cancel() } }
    }

    private func resumeReady(_ result: Result<UInt16, any Error>) {
        let ready = state.withLock { state in
            defer { state.ready = nil }
            return state.ready
        }
        ready?.resume(with: result)
    }

    private func accept(_ connection: NWConnection) {
        let isOpen = state.withLock { state -> Bool in
            guard state.listener != nil, state.connections.count < 16 else { return false }
            state.connections[ObjectIdentifier(connection)] = connection
            return true
        }
        guard isOpen else { return connection.cancel() }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(to: buffer[..<end.lowerBound], on: connection)
            } else if error != nil || isComplete || buffer.count > 16 * 1024 {
                self.drop(connection)
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to head: Data, on connection: NWConnection) {
        let requestLine = String(decoding: head, as: UTF8.self).split(separator: "\r\n", maxSplits: 1).first ?? ""
        let parts = requestLine.split(separator: " ")
        let target = parts.count >= 2 ? String(parts[1]) : ""
        let expected = state.withLock { $0.expectedState } ?? ""
        let status: String
        let body: String
        var settled: Outcome?
        if parts.first != "GET" {
            (status, body) = ("405 Method Not Allowed", "")
        } else if let callback = HomeAuthRequest.callback(target: target, expectedState: expected) {
            switch callback {
            case .code(let code): settled = .code(code)
            case .denied: settled = .denied
            case .failed: settled = .failed
            case .stateMismatch: break
            }
            (status, body) = ("200 OK", HomeAuthRequest.page(success: settled.map { if case .code = $0 { true } else { false } } ?? false))
        } else if target == "/" || target.hasPrefix("/?") {
            // The client_id page. HA doesn't need it (same origin), but a browser opening it sees who this is.
            (status, body) = ("200 OK", "<!doctype html><html><head><meta charset=\"utf-8\"><title>Altillo</title>"
                + "<link rel=\"redirect_uri\" href=\"/callback\"></head><body>Altillo</body></html>")
        } else {
            (status, body) = ("404 Not Found", "")
        }
        let payload = Data(body.utf8)
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(payload.count)\r\n"
            + "Cache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(headers.utf8) + payload, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.drop(connection)
        })
        if let settled { finish(settled) }
    }

    private func drop(_ connection: NWConnection) {
        connection.cancel()
        state.withLock { _ = $0.connections.removeValue(forKey: ObjectIdentifier(connection)) }
    }
}

// MARK: - Strings

extension HomeStrings {
    static var browserFailed: String { String(localized: "Couldn't open the browser to sign in.", bundle: .module) }
    static var signInStartFailed: String { String(localized: "Couldn't start the sign-in. Try again.", bundle: .module) }
    static var signInDenied: String { String(localized: "The sign-in was cancelled in Home Assistant.", bundle: .module) }
    static var signInTimedOut: String {
        String(localized: "The sign-in took too long. Try again when you're ready.", bundle: .module)
    }
    static var signInIncomplete: String {
        String(localized: "Home Assistant didn't finish the sign-in. Try again.", bundle: .module)
    }
    static var signInPageDone: String { String(localized: "Done. You can go back to Altillo.", bundle: .module) }
    static var signInPageClose: String { String(localized: "You can close this tab.", bundle: .module) }
    static var signInPageFailed: String {
        String(localized: "The sign-in didn't finish. Go back to Altillo and try again.", bundle: .module)
    }
}
