import Foundation
import Security

/// The protocol engine only accepts bounded reads. Fixtures implement this same byte transport.
protocol NativeMailSocket: Sendable {
    func read(maxBytes: Int) async throws -> Data
    func write(_ data: Data) async throws
    func startTLS() async throws
    func close() async
}

typealias NativeMailSocketFactory = @Sendable (String, Int, Bool) async throws -> any NativeMailSocket

/// URLSession owns the TCP socket, SNI and TLS negotiation, including an in-place SMTP STARTTLS upgrade.
/// There are no certificate exceptions; the policy below explicitly verifies the configured hostname.
final class NativeMailTLSSocket: NSObject, NativeMailSocket, URLSessionTaskDelegate, @unchecked Sendable {
    private let host: String
    private var session: URLSession!
    private var task: URLSessionStreamTask!

    init(host: String, port: Int, implicitTLS: Bool) {
        self.host = host
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        task = session.streamTask(withHostName: host, port: port)
        if implicitTLS { task.startSecureConnection() }
        task.resume()
    }

    static let factory: NativeMailSocketFactory = { host, port, secure in
        try Task.checkCancellation()
        return NativeMailTLSSocket(host: host, port: port, implicitTLS: secure)
    }

    func read(maxBytes: Int) async throws -> Data {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                task.readData(ofMinLength: 1, maxLength: min(max(maxBytes, 1), 65_536), timeout: 30) { data, _, error in
                    if let error {
                        continuation.resume(throwing: Self.failure(error))
                    } else if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: NativeMailFailure.unavailable) }
                }
            }
        } onCancel: { self.task.cancel() }
    }

    func write(_ data: Data) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                task.write(data, timeout: 30) { error in
                    if let error { continuation.resume(throwing: Self.failure(error)) }
                    else { continuation.resume() }
                }
            }
        } onCancel: { self.task.cancel() }
    }

    func startTLS() async throws {
        try Task.checkCancellation()
        // Subsequent queued I/O waits for TLS. Authentication cannot overtake this operation.
        task.startSecureConnection()
    }

    func close() async { task.cancel(); session.invalidateAndCancel() }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    private static func failure(_ error: Error) -> Error {
        if (error as? URLError)?.code == .cancelled { return CancellationError() }
        return NativeMailFailure.unavailable
    }
}

actor NativeMailSocketReader {
    let socket: any NativeMailSocket
    private var buffer = Data()
    private var receivedBytes = 0
    private let budget: Int
    private let deadline = Date.now.addingTimeInterval(120)
    init(socket: any NativeMailSocket, budget: Int = 32 << 20) { self.socket = socket; self.budget = budget }

    func line(limit: Int = 65_536) async throws -> Data {
        while true {
            if let range = buffer.range(of: Data([13, 10])) {
                guard range.lowerBound <= limit else { throw NativeMailFailure.invalidResponse }
                let line = Data(buffer[..<range.lowerBound])
                buffer.removeSubrange(..<range.upperBound)
                return line
            }
            guard buffer.count <= limit else { throw NativeMailFailure.invalidResponse }
            try await fill()
        }
    }

    func exact(_ count: Int, limit: Int) async throws -> Data {
        guard count >= 0, count <= limit else { throw NativeMailFailure.contentTooLarge }
        while buffer.count < count { try await fill() }
        let result = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        return result
    }

    func upgradeTLS() async throws {
        // Bytes after the STARTTLS success line are not accepted as authenticated TLS data.
        guard buffer.isEmpty else { throw NativeMailFailure.invalidResponse }
        try await socket.startTLS()
    }

    private func fill() async throws {
        try Task.checkCancellation()
        guard Date.now < deadline else { throw NativeMailFailure.unavailable }
        let chunk = try await socket.read(maxBytes: 65_536)
        guard !chunk.isEmpty, chunk.count <= 65_536, receivedBytes <= budget - chunk.count else {
            throw NativeMailFailure.contentTooLarge
        }
        receivedBytes += chunk.count
        buffer.append(chunk)
    }
}

enum NativeMailServerValidation {
    static func check(_ credentials: NativeMailServerCredentials) throws {
        let config = credentials.configuration
        guard address(config.address), !config.username.isEmpty, config.username.utf8.count <= 1_024,
              !config.username.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              !credentials.password.isEmpty, credentials.password.utf8.count <= 4_096,
              !credentials.password.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              host(config.imapHost), host(config.smtpHost),
              (1...65_535).contains(config.imapPort), (1...65_535).contains(config.smtpPort) else {
            throw NativeMailFailure.invalidDraft
        }
    }

    static func address(_ value: String) -> Bool {
        guard value.utf8.count <= 254, value.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 32 && $0.value < 127 }),
              !value.contains(where: { "<>(),;:\\\"[]".contains($0) }) else { return false }
        let pieces = value.split(separator: "@", omittingEmptySubsequences: false)
        return pieces.count == 2 && !pieces[0].isEmpty && pieces[0].count <= 64 && host(String(pieces[1]))
    }

    private static func host(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 253, !value.hasPrefix("."), !value.hasSuffix("."),
              value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }) else { return false }
        return value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-")
        }
    }
}
