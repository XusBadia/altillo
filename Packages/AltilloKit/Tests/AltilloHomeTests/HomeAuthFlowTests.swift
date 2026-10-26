import Foundation
import Testing
@testable import AltilloHome

@MainActor
struct HomeAuthFlowTests {
    // MARK: PKCE

    @Test func pkceMatchesTheRFC7636Vector() {
        // RFC 7636 appendix B.
        let pkce = HomePKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedVerifiersAreUnreservedAndLongEnough() {
        let verifier = HomePKCE().verifier
        #expect(verifier.count == 43)
        #expect(verifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) })
        #expect(HomePKCE().verifier != verifier)
        #expect(HomePKCE.challenge(for: verifier).count == 43)
    }

    // MARK: Requests

    @Test func authorizeURLCarriesEveryParameter() throws {
        let request = HomeAuthRequest(server: URL(string: "http://homeassistant.local:8123")!, port: 50123)
        let url = request.authorizeURL(state: "s-1", challenge: "c_2")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "homeassistant.local")
        #expect(components.port == 8123)
        #expect(components.path == "/auth/authorize")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items == [
            "response_type": "code", "client_id": "http://127.0.0.1:50123/",
            "redirect_uri": "http://127.0.0.1:50123/callback", "state": "s-1",
            "code_challenge": "c_2", "code_challenge_method": "S256",
        ])
        // Fully encoded, so HA's frontend reads client_id back exactly.
        #expect(url.absoluteString.contains("client_id=http%3A%2F%2F127.0.0.1%3A50123%2F"))
    }

    @Test func tokenRequestIsAFormPost() throws {
        let request = HomeAuthRequest(server: URL(string: "https://casa.example:8443")!, port: 4000)
            .tokenRequest(code: "a/b+c", verifier: "v")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://casa.example:8443/auth/token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body == "grant_type=authorization_code&code=a%2Fb%2Bc&client_id=http%3A%2F%2F127.0.0.1%3A4000%2F&code_verifier=v")
    }

    // MARK: Callback

    @Test func callbackParsing() {
        #expect(HomeAuthRequest.callback(target: "/callback?code=abc&state=xyz", expectedState: "xyz") == .code("abc"))
        #expect(HomeAuthRequest.callback(target: "/callback?state=xyz&code=a%2Fb", expectedState: "xyz") == .code("a/b"))
        #expect(HomeAuthRequest.callback(target: "/callback?code=abc&state=nope", expectedState: "xyz") == .stateMismatch)
        #expect(HomeAuthRequest.callback(target: "/callback?code=abc", expectedState: "xyz") == .stateMismatch)
        #expect(HomeAuthRequest.callback(target: "/callback?error=access_denied&state=xyz", expectedState: "xyz") == .denied)
        #expect(HomeAuthRequest.callback(target: "/callback?error=server_error&state=xyz", expectedState: "xyz") == .failed)
        #expect(HomeAuthRequest.callback(target: "/callback?state=xyz", expectedState: "xyz") == .failed)
        #expect(HomeAuthRequest.callback(target: "/", expectedState: "xyz") == nil)
        #expect(HomeAuthRequest.callback(target: "/favicon.ico", expectedState: "xyz") == nil)
        #expect(!HomeAuthCallback.stateMismatch.isTerminal)
        #expect(HomeAuthCallback.denied.isTerminal)
    }

    // MARK: Token answer

    @Test func tokenResponseParsing() throws {
        let ok = Data(#"{"access_token":"AT","token_type":"Bearer","refresh_token":"RT","expires_in":1800}"#.utf8)
        #expect(try HomeAuthRequest.tokens(status: 200, body: ok) == HomeAuthTokens(access: "AT", refresh: "RT"))
        let noRefresh = Data(#"{"access_token":"AT"}"#.utf8)
        #expect(try HomeAuthRequest.tokens(status: 200, body: noRefresh) == HomeAuthTokens(access: "AT", refresh: nil))

        let invalid = Data(#"{"error":"invalid_grant","error_description":"Invalid code verifier"}"#.utf8)
        #expect(throws: HomeServiceError(HomeStrings.haSaid("Invalid code verifier"))) {
            try HomeAuthRequest.tokens(status: 400, body: invalid)
        }
        #expect(throws: HomeServiceError(HomeStrings.signInIncomplete)) {
            try HomeAuthRequest.tokens(status: 502, body: Data("<html>".utf8))
        }
    }

    // MARK: Long-lived token over the socket

    @Test func mintsALongLivedTokenAndRetriesATakenName() async throws {
        let socket = ScriptedSocket(takenNames: ["Altillo (Mac)"])
        let token = try await HomeAuthRequest.longLivedToken(over: socket, accessToken: "AT", clientName: "Altillo (Mac)")
        #expect(token == "LLT")
        let sent = await socket.sent
        #expect(sent.first?["access_token"]?.string == "AT")
        let asks = sent.filter { $0["type"]?.string == "auth/long_lived_access_token" }
        #expect(asks.count == 2)
        #expect(asks.first?["lifespan"]?.int == 3650)
        #expect(asks.last?["client_name"]?.string?.hasPrefix("Altillo (Mac) · ") == true)
    }

    @Test func refusedShortLivedTokenFails() async {
        let socket = ScriptedSocket(acceptsAuth: false)
        await #expect(throws: HomeServiceError(HomeStrings.signInIncomplete)) {
            try await HomeAuthRequest.longLivedToken(over: socket, accessToken: "AT", clientName: "Altillo")
        }
    }

    // MARK: The whole flow with a real loopback listener

    @Test func signInEndToEnd() async throws {
        let http = FakeHTTP()
        let socket = ScriptedSocket()
        var opened: URL?
        let flow = HomeAuthFlow(open: { url in
            opened = url
            Task.detached {
                let (redirect, state) = try Self.redirect(from: url)
                // A stray request with the wrong state is answered but doesn't end the sign-in.
                _ = try? await Self.get("\(redirect)?code=forged&state=wrong")
                _ = try? await Self.get(redirect.replacingOccurrences(of: "/callback", with: "/favicon.ico"))
                let page = try await Self.get("\(redirect)?code=the-code&state=\(state)")
                await http.record(page: page)
            }
            return true
        }, httpFactory: { _ in http }, socketFactory: { _, _ in socket }, clientName: "Altillo (Test)")

        let token = try await flow.signIn(to: URL(string: "http://ha.test:8123")!)
        #expect(token == "LLT")
        #expect(!flow.isSigningIn)
        let authorize = try #require(opened)
        #expect(authorize.host == "ha.test")

        let requests = await http.requests
        let exchange = try #require(requests.first)
        #expect(exchange.url?.absoluteString == "http://ha.test:8123/auth/token")
        let body = String(decoding: exchange.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("code=the-code"))
        // The verifier sent matches the challenge in the authorize URL.
        let verifier = try #require(body.split(separator: "&").first { $0.hasPrefix("code_verifier=") }?.dropFirst(14))
        let challenge = URLComponents(url: authorize, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "code_challenge" }?.value
        #expect(HomePKCE.challenge(for: String(verifier)) == challenge)
        // The short-lived session is revoked once the long-lived token exists.
        #expect(requests.last?.url?.path() == "/auth/revoke")
        #expect(await eventually { await http.page?.contains("Altillo") == true })
    }

    @Test func deniedInTheBrowser() async throws {
        let flow = HomeAuthFlow(open: { url in
            Task.detached {
                let (redirect, state) = try Self.redirect(from: url)
                _ = try await Self.get("\(redirect)?error=access_denied&state=\(state)")
            }
            return true
        }, httpFactory: { _ in FakeHTTP() }, socketFactory: { _, _ in ScriptedSocket() })
        await #expect(throws: HomeServiceError(HomeStrings.signInDenied)) {
            try await flow.signIn(to: URL(string: "http://ha.test:8123")!)
        }
    }

    @Test func cancelStopsTheWait() async throws {
        let flow = HomeAuthFlow(open: { _ in true }, httpFactory: { _ in FakeHTTP() }, socketFactory: { _, _ in ScriptedSocket() })
        let task = Task { try await flow.signIn(to: URL(string: "http://ha.test:8123")!) }
        #expect(await eventually { flow.isSigningIn })
        flow.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func timesOut() async {
        let flow = HomeAuthFlow(open: { _ in true }, httpFactory: { _ in FakeHTTP() }, socketFactory: { _, _ in ScriptedSocket() },
                                timeout: .milliseconds(200))
        await #expect(throws: HomeServiceError(HomeStrings.signInTimedOut)) {
            try await flow.signIn(to: URL(string: "http://ha.test:8123")!)
        }
    }

    @Test func browserThatWontOpen() async {
        let flow = HomeAuthFlow(open: { _ in false }, httpFactory: { _ in FakeHTTP() }, socketFactory: { _, _ in ScriptedSocket() })
        await #expect(throws: HomeServiceError(HomeStrings.browserFailed)) {
            try await flow.signIn(to: URL(string: "http://ha.test:8123")!)
        }
    }

    // MARK: Helpers

    nonisolated static func redirect(from authorize: URL) throws -> (redirect: String, state: String) {
        let items = URLComponents(url: authorize, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let redirect = try #require(items.first { $0.name == "redirect_uri" }?.value)
        let state = try #require(items.first { $0.name == "state" }?.value)
        return (redirect, state)
    }

    nonisolated static func get(_ url: String) async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, _) = try await session.data(from: URL(string: url)!)
        return String(decoding: data, as: UTF8.self)
    }
}

/// `/auth/token` and `/auth/revoke`, scripted.
actor FakeHTTP: HomeHTTP {
    private(set) var requests: [URLRequest] = []
    private(set) var page: String?

    func record(page: String) { self.page = page }

    func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        requests.append(request)
        if request.url?.path() == "/auth/token" {
            return (200, Data(#"{"access_token":"AT","refresh_token":"RT","token_type":"Bearer","expires_in":1800}"#.utf8))
        }
        return (200, Data())
    }
}

/// Home Assistant's WebSocket for the long-lived token request.
actor ScriptedSocket: HomeSocket {
    private let acceptsAuth: Bool
    private let takenNames: Set<String>
    private(set) var sent: [JSONValue] = []
    private var inbox: [String] = [#"{"type":"auth_required","ha_version":"2026.10.1"}"#]

    init(acceptsAuth: Bool = true, takenNames: Set<String> = []) {
        self.acceptsAuth = acceptsAuth
        self.takenNames = takenNames
    }

    func send(_ text: String) async throws {
        let message = try JSONValue.decode(text)
        sent.append(message)
        let reply: JSONValue
        switch message["type"]?.string {
        case "auth":
            reply = acceptsAuth && message["access_token"]?.string == "AT"
                ? ["type": "auth_ok"] : ["type": "auth_invalid", "message": "Invalid access token or password"]
        case "auth/long_lived_access_token":
            let id = message["id"] ?? nil
            if let name = message["client_name"]?.string, takenNames.contains(name) {
                reply = ["id": id, "type": "result", "success": false, "error": ["code": "unknown_error", "message": "Unknown error"]]
            } else {
                reply = ["id": id, "type": "result", "success": true, "result": "LLT"]
            }
        default:
            return
        }
        inbox.append(try reply.encodedString())
    }

    func receive() async throws -> String {
        guard !inbox.isEmpty else { throw URLError(.networkConnectionLost) }
        return inbox.removeFirst()
    }

    func close() async {}
}

// MARK: - Lab

/// The whole sign-in against `script/home-lab.sh up`: the browser is replaced by HA's login-flow API (what HA's
/// own authorize page calls), so the code, PKCE check, token exchange and long-lived token are all real.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ALTILLO_HOME_LAB_TOKEN"] != nil))
struct HomeAuthFlowLabTests {
    nonisolated static let server = URL(string: "http://localhost:8124")!

    @Test func signsInThroughTheLoginFlowAndConnects() async throws {
        let flow = HomeAuthFlow(open: { authorize in
            Task.detached { try await Self.actLikeTheBrowser(authorize) }
            return true
        }, clientName: "Altillo (lab test)", timeout: .seconds(30))
        let token = try await flow.signIn(to: Self.server)
        #expect(!token.isEmpty)

        let client = HomeAssistantClient(tokens: InMemoryHomeTokenStore(), socketFactory: URLSessionHomeSocket.make)
        try await client.connect(HomeServerConfig(url: Self.server), token: token)
        guard case .connected = client.connection else { Issue.record("not connected: \(client.connection)"); return }
        client.disconnect(forget: true)
    }

    /// POST /auth/login_flow (with the PKCE challenge, as HA's frontend does), then the credentials step, then the
    /// redirect the frontend would perform.
    nonisolated static func actLikeTheBrowser(_ authorize: URL) async throws {
        let items = URLComponents(url: authorize, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String { items.first { $0.name == name }?.value ?? "" }
        let start: JSONValue = try await post("auth/login_flow", [
            "client_id": .string(item("client_id")), "handler": ["homeassistant", nil],
            "redirect_uri": .string(item("redirect_uri")), "code_challenge": .string(item("code_challenge")),
            "code_challenge_method": "S256",
        ])
        let flowID = try #require(start["flow_id"]?.string)
        let done = try await post("auth/login_flow/\(flowID)", [
            "client_id": .string(item("client_id")), "username": "altillo", "password": "altillo-lab-pass",
        ])
        let code = try #require(done["result"]?.string, "login flow answered \(done)")
        _ = try await HomeAuthFlowTests.get("\(item("redirect_uri"))?code=\(code)&state=\(item("state"))")
    }

    nonisolated static func post(_ path: String, _ body: JSONValue) async throws -> JSONValue {
        var request = URLRequest(url: server.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(try body.encodedString().utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONValue.decode(String(decoding: data, as: UTF8.self))
    }
}
