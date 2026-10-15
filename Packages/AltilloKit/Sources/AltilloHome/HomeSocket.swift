import CryptoKit
import Foundation
import Security
import Synchronization

/// The text transport under the Home Assistant client. URLSession in the app, a scripted fake server in tests.
protocol HomeSocket: Sendable {
    func send(_ text: String) async throws
    /// The next text frame. Throws once the socket is closed or fails.
    func receive() async throws -> String
    func close() async
}

typealias HomeSocketFactory = @MainActor (URL, HomeTrustDelegate) -> any HomeSocket

/// TLS for the socket and the camera snapshot: system trust first, then the certificate the user pinned (TOFU).
/// Any other certificate is refused and its fingerprint kept so the client can offer `.needsTrust`.
final class HomeTrustDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, Sendable {
    let pinnedSHA256: String?
    private let untrusted = Mutex<String?>(nil)

    init(pinnedSHA256: String?) {
        self.pinnedSHA256 = pinnedSHA256?.lowercased()
    }

    /// The fingerprint of a certificate we refused during this connection, if any.
    var untrustedFingerprint: String? { untrusted.withLock { $0 } }
    func recordUntrusted(_ fingerprint: String) { untrusted.withLock { $0 = fingerprint } }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        evaluate(challenge)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        evaluate(challenge)
    }

    /// Never follow redirects: the snapshot request carries the token in its Authorization header.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }

    private func evaluate(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
        if SecTrustEvaluateWithError(trust, nil) { return (.useCredential, URLCredential(trust: trust)) }
        guard let fingerprint = Self.leafFingerprint(trust) else { return (.cancelAuthenticationChallenge, nil) }
        if let pinnedSHA256, pinnedSHA256 == fingerprint { return (.useCredential, URLCredential(trust: trust)) }
        recordUntrusted(fingerprint)
        return (.cancelAuthenticationChallenge, nil)
    }

    static func leafFingerprint(_ trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else { return nil }
        return sha256Hex(SecCertificateCopyData(leaf) as Data)
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// URLSessionWebSocketTask behind `HomeSocket`. One ephemeral session per connection, invalidated on close.
final class URLSessionHomeSocket: HomeSocket {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    init(url: URL, delegate: HomeTrustDelegate) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        task = session.webSocketTask(with: url)
        // get_states and the registries of a big home are several MB; the default limit is 1 MB.
        task.maximumMessageSize = 64 * 1024 * 1024
        task.resume()
    }

    @MainActor static func make(url: URL, delegate: HomeTrustDelegate) -> any HomeSocket {
        URLSessionHomeSocket(url: url, delegate: delegate)
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let text): return text
        case .data(let data): return String(decoding: data, as: UTF8.self)
        @unknown default: return ""
        }
    }

    func close() async {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}
