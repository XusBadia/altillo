import AltilloAgents
import AltilloCore
import Darwin
import Foundation
import Testing
@testable import Altillo

/// Phase 4 engine: the hub's socket server talking to the real hook code (`HookRunner`, the same function the
/// `altillo-hook` binary runs), the permission round trip, the timeout and "answered in the terminal" paths,
/// passive session files, and the shipped binary's behaviour when Altillo isn't running.
@MainActor
@Suite(.serialized)
struct AgentHubTests {
    static func socketPath() -> String { "/tmp/altillo-hub-\(getpid())-\(UUID().uuidString.prefix(8)).sock" }

    static let claudeSession = "fc6f9b07-c1a0-497d-96c8-94c48f710cb1"

    static func payload(_ event: String, _ extra: String = "") -> Data {
        Data(#"{"session_id":"\#(claudeSession)","transcript_path":"/nonexistent/\#(claudeSession).jsonl","cwd":"/Users/me/Projects/demo","permission_mode":"default","hook_event_name":"\#(event)"\#(extra)}"#.utf8)
    }

    static let permissionExtra = #","tool_name":"Bash","tool_input":{"command":"touch made-by-test.txt","description":"Create a file"},"permission_suggestions":[{"type":"setMode","mode":"acceptEdits","destination":"session"}]"#

    /// Runs the hook code off the main actor, as the agent would (a separate process in real life).
    nonisolated static func hook(_ socket: String, _ arguments: [String], _ stdin: Data) async -> Data? {
        await Task.detached {
            HookRunner.run(arguments: arguments, environment: ["ALTILLO_AGENTS_SOCKET": socket], readStdin: { stdin })
        }.value
    }

    func waitUntil(_ timeout: Double = 3, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                Issue.record("condition not met in \(timeout) s")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func makeHub(_ path: String, roots: AgentSessionFileWatcher.Roots? = nil) -> AgentHub {
        let hub = AgentHub(socketPath: path, fileRoots: roots)
        hub.start()
        return hub
    }

    @Test func hookEventsBuildASession() async throws {
        let path = Self.socketPath()
        let hub = makeHub(path)
        defer { hub.stop() }
        #expect(await Self.hook(path, ["claude", "SessionStart"], Self.payload("SessionStart", #","source":"startup""#)) == nil)
        #expect(await Self.hook(path, ["claude", "PreToolUse"],
                                Self.payload("PreToolUse", #","tool_name":"Bash","tool_input":{"command":"swift test"}"#)) == nil)
        try await waitUntil { hub.sessions.first?.activity == "Running `swift test`" }
        let session = try #require(hub.sessions.first)
        #expect(session.id == "claude:\(Self.claudeSession)")
        #expect(session.phase == .working)
        #expect(session.project == "demo")
        #expect(session.source == .hooks)
        #expect(hub.working.count == 1)
    }

    @Test(arguments: [AgentDecision.allow, .allowForSession, .deny])
    func permissionRoundTrip(decision: AgentDecision) async throws {
        let path = Self.socketPath()
        let hub = makeHub(path)
        defer { hub.stop() }
        async let output = Self.hook(path, ["claude", "PermissionRequest", "--timeout", "10"],
                                     Self.payload("PermissionRequest", Self.permissionExtra))
        try await waitUntil { hub.waiting.first?.pendingRequest != nil }
        let request = try #require(hub.waiting.first?.pendingRequest)
        #expect(request.summary == "touch made-by-test.txt")
        #expect(request.canAllowForSession)
        #expect(!request.isExpired)
        #expect(request.expiresAt != nil)

        hub.decide(request.id, decision)
        let printed = try #require(await output)
        let json = try #require(JSONValue.parse(printed))
        #expect(json.value(at: "hookSpecificOutput.decision.behavior")?.string == (decision == .deny ? "deny" : "allow"))
        if decision == .allowForSession {
            #expect(json.value(at: "hookSpecificOutput.decision.updatedPermissions")?.array?.isEmpty == false)
        }
        #expect(hub.sessions.first?.phase == .working)
        #expect(hub.sessions.first?.pendingRequest == nil)
    }

    @Test func hookTimeoutLeavesTheRequestToTheTerminal() async throws {
        let path = Self.socketPath()
        let hub = makeHub(path)
        defer { hub.stop() }
        let started = Date()
        let output = await Self.hook(path, ["claude", "PermissionRequest", "--timeout", "1"],
                                     Self.payload("PermissionRequest", Self.permissionExtra))
        #expect(output == nil) // no decision: the agent asks in the terminal
        #expect(Date().timeIntervalSince(started) < 3)
        try await waitUntil { hub.sessions.first?.pendingRequest?.isExpired == true }
        let session = try #require(hub.sessions.first)
        #expect(session.phase == .waitingPermission) // still needs the user, in the terminal

        // Deciding afterwards can't reach the hook; the request just stays expired.
        hub.decide(try #require(session.pendingRequest?.id), .allow)
        #expect(hub.sessions.first?.pendingRequest?.isExpired == true)
    }

    @Test func answeredInTheTerminalClearsTheRequest() async throws {
        let path = Self.socketPath()
        let hub = makeHub(path)
        defer { hub.stop() }
        // A hook that waits, then is killed early (the user answered in the terminal).
        let fd = try UnixSocket.connect(path: path)
        let envelope = HookEnvelope(agent: "claude", event: "PermissionRequest",
                                    payload: try #require(JSONValue.parse(Self.payload("PermissionRequest", Self.permissionExtra))),
                                    waitsForDecision: true, requestID: "early", timeout: 120)
        UnixSocket.writeAll(fd, try #require(AgentWire.frame(envelope)))
        try await waitUntil { hub.sessions.first?.pendingRequest?.id == "early" }
        close(fd)
        try await waitUntil { hub.sessions.first?.pendingRequest == nil }
        #expect(hub.sessions.first?.phase == .working)
    }

    @Test func queuedRequestsShowOneAfterAnother() async throws {
        let path = Self.socketPath()
        let hub = makeHub(path)
        defer { hub.stop() }
        let second = Self.permissionExtra.replacingOccurrences(of: "made-by-test", with: "second")
        async let first = Self.hook(path, ["claude", "PermissionRequest"], Self.payload("PermissionRequest", Self.permissionExtra))
        try await waitUntil { hub.sessions.first?.pendingRequest != nil }
        async let other = Self.hook(path, ["claude", "PermissionRequest"], Self.payload("PermissionRequest", second))
        try await Task.sleep(for: .milliseconds(200))
        let shown = try #require(hub.sessions.first?.pendingRequest)
        #expect(shown.summary == "touch made-by-test.txt")
        hub.decide(shown.id, .deny)
        _ = await first
        try await waitUntil { hub.sessions.first?.pendingRequest?.summary == "touch second.txt" }
        hub.decide(try #require(hub.sessions.first?.pendingRequest?.id), .allow)
        #expect(await other != nil)
        #expect(hub.sessions.first?.pendingRequest == nil)
    }

    @Test func stopAndDismiss() async throws {
        let path = Self.socketPath()
        let hub = makeHub(path)
        defer { hub.stop() }
        _ = await Self.hook(path, ["claude", "Stop"], Self.payload("Stop", #","last_assistant_message":"Done. Ship it?""#))
        try await waitUntil { hub.waiting.first?.lastMessage == "Done. Ship it?" }
        #expect(hub.sessions.first?.phase == .waitingAnswer)
        hub.dismiss(try #require(hub.sessions.first))
        #expect(hub.sessions.isEmpty)
    }

    @Test func stoppingRemovesTheSocketSoHooksReturnAtOnce() async throws {
        let path = Self.socketPath()
        let hub = makeHub(path)
        #expect(FileManager.default.fileExists(atPath: path))
        var info = stat()
        #expect(stat(path, &info) == 0 && info.st_mode & 0o777 == 0o600)
        hub.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(await Self.hook(path, ["claude", "PermissionRequest"], Self.payload("PermissionRequest", Self.permissionExtra)) == nil)
    }

    @Test func aSecondInstanceStaysPassiveAndLeavesTheSocketAlone() async throws {
        let path = Self.socketPath()
        let first = makeHub(path)
        defer { first.stop() }
        let second = makeHub(path)
        #expect(first.isListening)
        #expect(!second.isListening)
        second.stop()
        #expect(FileManager.default.fileExists(atPath: path)) // the second didn't delete the first's socket

        _ = await Self.hook(path, ["claude", "SessionStart"], Self.payload("SessionStart", #","source":"startup""#))
        try await waitUntil { !first.sessions.isEmpty }
        #expect(second.sessions.isEmpty)
    }

    @Test func stopDoesNotDeleteAnotherInstancesSocket() throws {
        let path = Self.socketPath()
        let server = AgentSocketServer(path: path)
        try server.start()
        // Another instance took the path over (our file replaced by theirs).
        unlink(path)
        let other = try UnixSocket.listen(path: path)
        defer { close(other.fd); unlink(path) }
        server.stop()
        #expect(UnixSocket.inode(of: path) == other.inode)
    }

    @Test func aClearedRequestLetsItsHookGoAtOnce() async throws {
        let path = Self.socketPath()
        let hub = makeHub(path)
        defer { hub.stop() }
        let started = Date()
        async let output = Self.hook(path, ["claude", "PermissionRequest", "--timeout", "30"],
                                     Self.payload("PermissionRequest", Self.permissionExtra))
        try await waitUntil { hub.sessions.first?.pendingRequest != nil }
        // The same tool ran (answered in the terminal) while this hook is still connected.
        _ = await Self.hook(path, ["claude", "PostToolUse"], Self.payload("PostToolUse",
            #","tool_name":"Bash","tool_input":{"command":"touch made-by-test.txt"},"tool_use_id":"toolu_1","tool_response":{}"#))
        #expect(await output == nil) // "no decision", not a 30 s wait
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(hub.sessions.first?.pendingRequest == nil)
        #expect(hub.sessions.first?.phase == .working)
    }

    @Test func sessionFilesShowSessionsWithoutHooks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("altillo-hub-\(UUID().uuidString)")
        let claude = root.appendingPathComponent("claude/projects/-Users-me-Projects-demo")
        let codex = root.appendingPathComponent("codex/sessions")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transcript = claude.appendingPathComponent("\(Self.claudeSession).jsonl")
        let stamp = ISO8601DateFormatter().string(from: Date())
        func line(_ type: String, _ message: String) -> String {
            #"{"type":"\#(type)","cwd":"/Users/me/Projects/demo","entrypoint":"cli","isSidechain":false,"timestamp":"\#(stamp)","message":\#(message)}"# + "\n"
        }
        try (line("user", #"{"role":"user","content":"Build it"}"#)
            + line("assistant", #"{"id":"m1","role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use","name":"Bash","input":{"command":"swift build"}}]}"#))
            .write(to: transcript, atomically: false, encoding: .utf8)

        let hub = makeHub(Self.socketPath(), roots: .init(claudeProjects: root.appendingPathComponent("claude/projects"),
                                                          codexSessions: codex))
        defer { hub.stop() }
        try await waitUntil { hub.sessions.first?.activity == "Running `swift build`" }
        #expect(hub.sessions.first?.source == .sessionFile)
        #expect(hub.sessions.first?.phase == .working)

        // Appending the answer: FSEvents wakes the watcher, which reads only the tail.
        let handle = try FileHandle(forWritingTo: transcript)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line("assistant", #"{"id":"m2","role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"Built."}]}"#).utf8))
        try handle.close()
        try await waitUntil(5) { hub.sessions.first?.phase == .waitingAnswer }
        #expect(hub.sessions.first?.lastMessage == "Built.")
    }

    /// The shipped binary: no Altillo → exit 0, no output, fast (the agent must behave exactly as without it).
    @Test func embeddedHookExitsQuietlyWithoutAltillo() throws {
        let binary = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/altillo-hook")
        try #require(FileManager.default.isExecutableFile(atPath: binary.path))
        var timings: [Double] = []
        // The first run is a warm-up: a freshly built binary pays once for macOS's code-signature checks.
        for arguments in [["codex", "SessionStart"], ["claude", "PreToolUse"], ["claude", "PermissionRequest", "--timeout", "120"],
                          ["codex", "Stop"]] {
            let process = Process()
            process.executableURL = binary
            process.arguments = arguments
            process.environment = ["ALTILLO_AGENTS_SOCKET": Self.socketPath(), "PATH": "/usr/bin:/bin"]
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            let start = Date()
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: Self.payload("PermissionRequest", Self.permissionExtra))
            try input.fileHandleForWriting.close()
            let printed = try output.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            timings.append(Date().timeIntervalSince(start))
            #expect(process.terminationStatus == 0)
            #expect(printed.isEmpty)
        }
        // Judge the warm runs. Typically ~5 ms; the bound leaves room for a machine busy compiling in parallel, and
        // still proves the hook never waits when Altillo isn't there.
        #expect(timings.dropFirst().allSatisfy { $0 < 0.1 }, "\(timings)")
    }
}
