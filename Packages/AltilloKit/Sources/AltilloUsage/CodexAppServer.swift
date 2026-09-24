import Foundation

// `codex app-server --listen stdio://`: JSON-RPC 2.0 over newline-delimited JSON. The handshake and request
// sequence are adapted from ai-limits' CodexCollector (https://github.com/XusBadia/ai-limits, MIT, © 2026 Xus Badia).
// See ThirdPartyNotices/README.md.

/// Reads Codex's `account/rateLimits/read` result as raw JSON. Tests inject canned results.
public protocol CodexRateLimitReading: Sendable {
    func readRateLimits() async throws -> Data
}

public enum CodexAppServerError: Error, Sendable, Equatable, CustomStringConvertible {
    /// No `codex` binary in the usual places.
    case notInstalled
    case launchFailed(String)
    case timedOut
    case exited(Int32, String)
    case rpcError(String)

    public var description: String {
        switch self {
        case .notInstalled: "codex isn't installed"
        case .launchFailed(let reason): "Couldn't start codex app-server: \(reason)"
        case .timedOut: "codex app-server didn't answer in time"
        case .exited(let status, let stderr): "codex app-server exited (\(status))\(stderr.isEmpty ? "" : ": \(stderr)")"
        case .rpcError(let message): "codex app-server: \(message)"
        }
    }
}

/// Starts `codex app-server` for one read and always stops it again (SIGTERM, then SIGKILL after 1 s).
public struct CodexAppServerClient: CodexRateLimitReading {
    public let executable: URL
    public let timeout: TimeInterval

    public init(executable: URL, timeout: TimeInterval = 15) {
        self.executable = executable
        self.timeout = timeout
    }

    public func readRateLimits() async throws -> Data {
        let session = CodexRPCSession(executable: executable, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await session.run()
        } onCancel: {
            session.finish(.failure(CancellationError()))
        }
    }

    /// First executable `codex` in the usual install locations (standalone, Homebrew, npm/nvm/mise/volta/bun globals).
    public static func locate(fileManager: FileManager = .default,
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let home = fileManager.homeDirectoryForCurrentUser.path
        var candidates = ["\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                          "/usr/bin/codex", "\(home)/.npm-global/bin/codex", "\(home)/.volta/bin/codex",
                          "\(home)/.bun/bin/codex"]
        if let prefix = environment["NPM_CONFIG_PREFIX"] ?? environment["npm_config_prefix"] {
            candidates.append("\(prefix)/bin/codex")
        }
        for root in ["\(home)/.nvm/versions/node", "\(home)/.local/share/mise/installs/node"] {
            if let versions = try? fileManager.contentsOfDirectory(atPath: root) {
                candidates += versions.sorted().reversed().map { "\(root)/\($0)/bin/codex" }
            }
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
}

/// Finds `codex` on every read, so installing the CLI while Altillo runs just works.
public struct LocatingCodexAppServer: CodexRateLimitReading {
    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    public func readRateLimits() async throws -> Data {
        guard let executable = CodexAppServerClient.locate() else { throw CodexAppServerError.notInstalled }
        return try await CodexAppServerClient(executable: executable, timeout: timeout).readRateLimits()
    }
}

/// One app-server conversation. All mutable state is behind `state`'s lock; pipe callbacks arrive on Foundation's
/// background queues.
final class CodexRPCSession: @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<Data, any Error>?
        var result: Result<Data, any Error>?
        var buffer = Data()
        var stderr = Data()
        var sentRequest = false
        var finished = false
    }

    private let executable: URL
    private let timeout: TimeInterval
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private let state = Locked(State())

    init(executable: URL, timeout: TimeInterval) {
        self.executable = executable
        self.timeout = timeout
    }

    func run() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let early = state.withLock { state -> Result<Data, any Error>? in
                if let result = state.result { return result }
                state.continuation = continuation
                return nil
            }
            if let early {
                continuation.resume(with: early)
                return
            }
            start()
        }
    }

    private func start() {
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.environment = ChildEnvironment.make()
        process.standardInput = input
        // If the server dies early, writing to its stdin must fail with EPIPE instead of killing Altillo.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.standardOutput = output
        process.standardError = errorOutput
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.consume(data)
        }
        errorOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.state.withLock { state in
                if state.stderr.count < 8192 { state.stderr.append(data.prefix(8192 - state.stderr.count)) }
            }
        }
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            let stderr = self.state.withLock { String(decoding: $0.stderr, as: UTF8.self) }
            let summary = stderr.split(separator: "\n").last.map(String.init) ?? ""
            self.finish(.failure(CodexAppServerError.exited(process.terminationStatus, summary)))
        }

        do {
            try process.run()
        } catch {
            finish(.failure(CodexAppServerError.launchFailed(error.localizedDescription)))
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(.failure(CodexAppServerError.timedOut))
        }
        send([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "altillo", "title": "Altillo", "version": "1.0"],
                "capabilities": ["experimentalApi": true],
            ] as [String: Any],
        ])
    }

    private func consume(_ data: Data) {
        var lines: [Data] = []
        state.withLock { state in
            state.buffer.append(data)
            while let newline = state.buffer.firstIndex(of: 0x0A) {
                lines.append(Data(state.buffer[state.buffer.startIndex..<newline]))
                state.buffer.removeSubrange(state.buffer.startIndex...newline)
            }
        }
        for line in lines { handle(line) }
    }

    private func handle(_ line: Data) {
        // Only responses matter; notifications and server-initiated requests carry a "method".
        guard let message = UsageParsing.object(line), message["method"] == nil,
              let id = UsageParsing.number(message["id"]) else { return }
        if id == 1 {
            let shouldSend = state.withLock { state -> Bool in
                defer { state.sentRequest = true }
                return !state.sentRequest
            }
            guard shouldSend else { return }
            if let error = message["error"] as? [String: Any] {
                finish(.failure(CodexAppServerError.rpcError(error["message"] as? String ?? "initialize failed")))
                return
            }
            send(["jsonrpc": "2.0", "method": "initialized"])
            send(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read"])
        } else if id == 2 {
            if let error = message["error"] as? [String: Any] {
                finish(.failure(CodexAppServerError.rpcError(error["message"] as? String ?? "request failed")))
            } else if let result = message["result"],
                      let data = try? JSONSerialization.data(withJSONObject: result) {
                finish(.success(data))
            } else {
                finish(.failure(CodexAppServerError.rpcError("empty result")))
            }
        }
    }

    private func send(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        do {
            try input.fileHandleForWriting.write(contentsOf: data)
        } catch {
            finish(.failure(CodexAppServerError.launchFailed("stdin closed")))
        }
    }

    /// Resolves the read exactly once and stops the process.
    func finish(_ result: Result<Data, any Error>) {
        let continuation = state.withLock { state -> CheckedContinuation<Data, any Error>?? in
            guard !state.finished else { return .none }
            state.finished = true
            state.result = result
            defer { state.continuation = nil }
            return .some(state.continuation)
        }
        guard let continuation else { return }
        cleanup()
        continuation?.resume(with: result)
    }

    private func cleanup() {
        output.fileHandleForReading.readabilityHandler = nil
        errorOutput.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        ProcessBox(process).terminate(grace: 1)
    }
}
