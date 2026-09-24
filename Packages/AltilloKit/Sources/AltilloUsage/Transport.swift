import Foundation

// Injectable I/O so the collectors are testable without network, keychain or subprocesses.

// MARK: - HTTP

/// Sends one HTTP request. Tests inject canned responses.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession-backed transport: ephemeral (no cookies, no cache on disk), so provider tokens never leave memory.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionTransport.makeSession()) {
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

// MARK: - Commands

/// Output of a finished command.
public struct CommandResult: Sendable, Hashable {
    public var status: Int32
    public var stdout: Data
    public var stderr: Data
    public var timedOut: Bool

    public init(status: Int32, stdout: Data, stderr: Data = Data(), timedOut: Bool = false) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

/// Runs a short-lived command to completion. Returns nil when it couldn't be launched at all.
public protocol CommandRunning: Sendable {
    func run(_ executable: URL, arguments: [String], timeout: TimeInterval) async -> CommandResult?
}

/// `Process`-backed runner. Runs off the caller's thread, drains both pipes, and on timeout sends SIGTERM then
/// SIGKILL a second later, so a stuck command (e.g. a keychain dialog nobody answers) never lingers.
public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: URL, arguments: [String], timeout: TimeInterval) async -> CommandResult? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.environment = ChildEnvironment.make()
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let box = ProcessBox(process)
                let timedOut = Locked(false)
                let timer = DispatchWorkItem {
                    timedOut.withLock { $0 = true }
                    box.terminate()
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timer)

                let errorData = Locked(Data())
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    let data = stderr.fileHandleForReading.readDataToEndOfFile()
                    errorData.withLock { $0 = data }
                    group.leave()
                }
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                timer.cancel()
                continuation.resume(returning: CommandResult(
                    status: process.terminationStatus,
                    stdout: outData,
                    stderr: errorData.withLock { $0 },
                    timedOut: timedOut.withLock { $0 }
                ))
            }
        }
    }
}

// MARK: - Helpers

/// Environment for child processes: the app's own, with the usual tool directories on PATH (a GUI app inherits a
/// minimal PATH, and npm-installed CLIs are `#!/usr/bin/env node` scripts).
enum ChildEnvironment {
    static func make(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.volta/bin",
                     "\(home)/.bun/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existing = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var path = existing
        for directory in extra where !path.contains(directory) { path.append(directory) }
        environment["PATH"] = path.joined(separator: ":")
        return environment
    }
}

/// A tiny lock-protected value (NSLock-based, so it works on every deployment target this package supports).
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    @discardableResult
    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

/// Lets a `Process` cross into the timeout/cleanup closures. All access goes through `Process`'s own thread-safe
/// API (`isRunning`, `terminate`, `processIdentifier`).
final class ProcessBox: @unchecked Sendable {
    let process: Process

    init(_ process: Process) { self.process = process }

    /// SIGTERM now, SIGKILL after `grace` seconds if it's still alive. Foundation reaps the child, so no zombie.
    func terminate(grace: TimeInterval = 1) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + grace) { [self] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}
