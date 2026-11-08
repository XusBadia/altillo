import Foundation
import CFNetwork
@preconcurrency import AppAuth

/// A separate, short-lived loopback page keeps AppAuth's tested OAuth callback unchanged.
/// No authorization code, token, account address or response body is exposed by this server.
@MainActor final class UsageAccountReturnServer: NSObject {
    private let server = HTTPServer()
    private let nonce = UUID().uuidString.lowercased()
    private let provider: String
    private var state = UsageAccountReturnPage.State.connecting
    private var expiry: Task<Void, Never>?
    private var receivedConnections = 0
    private(set) var baseURL: URL?

    init(provider: String) { self.provider = provider }

    var pagePath: String { "/complete/\(nonce)" }
    var statusPath: String { "/state/\(nonce)" }

    func start() throws -> URL {
        server.setPort(0)
        server.setDelegate(self)
        try server.start()
        let host = server.hasIPv4Socket() ? "127.0.0.1" : "[::1]"
        let base = URL(string: "http://\(host):\(server.port())")!
        baseURL = base
        return base.appending(path: pagePath)
    }

    func complete(success: Bool) {
        state = success ? .connected : .failed
        expiry?.cancel()
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(180)) } catch { return }
            self?.stop()
        }
    }

    func stop() {
        expiry?.cancel()
        expiry = nil
        server.setDelegate(nil)
        server.stop()
        baseURL = nil
    }

    @objc(HTTPServer:didMakeNewConnection:)
    private func connected(_ server: HTTPServer, connection: HTTPConnection) {
        receivedConnections += 1
        if receivedConnections > 128 { connection.invalidate() }
    }

    @objc(HTTPConnection:didReceiveRequest:)
    private func received(_ connection: HTTPConnection, request message: HTTPServerRequest) {
        let request = message.request().takeUnretainedValue()
        guard let url = CFHTTPMessageCopyRequestURL(request)?.takeRetainedValue() as URL?,
              let method = CFHTTPMessageCopyRequestMethod(request)?.takeRetainedValue() as String?,
              let baseURL,
              let host = CFHTTPMessageCopyHeaderFieldValue(request, "Host" as CFString)?.takeRetainedValue() as String?,
              host == String(baseURL.absoluteString.dropFirst("http://".count)),
              url.absoluteString.utf8.count <= 4096, method == "GET" else {
            respond(message, status: 400, type: "text/plain; charset=utf-8", body: "Invalid request")
            return
        }
        if url.path == pagePath {
            let language = CFHTTPMessageCopyHeaderFieldValue(request, "Accept-Language" as CFString)?.takeRetainedValue() as String? ?? "en"
            let html = UsageAccountReturnPage.html(providerName: provider, language: language, state: state,
                                                    statusPath: statusPath, openPath: "altillo://usage", cleanPath: pagePath)
            respond(message, status: 200, type: "text/html; charset=utf-8", body: html)
        } else if url.path == statusPath {
            respond(message, status: 200, type: "application/json", body: "{\"state\":\"\(state.rawValue)\"}")
        } else {
            respond(message, status: 404, type: "text/plain; charset=utf-8", body: "Not found")
        }
    }

    @objc(HTTPConnection:didSendResponse:)
    private func sent(_ connection: HTTPConnection, request: HTTPServerRequest) { connection.invalidate() }

    private func respond(_ message: HTTPServerRequest, status: Int, type: String, body: String) {
        let data = Data(body.utf8)
        let response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, status, nil, kCFHTTPVersion1_1).takeRetainedValue()
        let headers = [
            "Content-Type": type, "Content-Length": String(data.count), "Connection": "close",
            "Cache-Control": "no-store", "Pragma": "no-cache", "Referrer-Policy": "no-referrer",
            "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY",
            "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; img-src data:; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
        ]
        for (key, value) in headers { CFHTTPMessageSetHeaderFieldValue(response, key as CFString, value as CFString) }
        CFHTTPMessageSetBody(response, data as CFData)
        message.setResponse(response)
    }
}
