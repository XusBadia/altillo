import AltilloCore
import Darwin
import Foundation
import Testing
@testable import AltilloAgents

@Suite("Wire protocol and the hook")
struct WireProtocolTests {
    /// A short socket path (sun_path holds 104 bytes; the test temp folder is long).
    static func socketPath() -> String {
        "/tmp/altillo-test-\(getpid())-\(UUID().uuidString.prefix(8)).sock"
    }

    @Test func envelopeRoundTripAndFraming() throws {
        let payload = try Fixtures.payload("claude", "PermissionRequest")
        let envelope = HookEnvelope(agent: "claude", event: "PermissionRequest", payload: payload,
                                    env: ["TERM_PROGRAM": "iTerm.app"], ppids: [10, 9, 1], tty: "/dev/ttys003",
                                    agentPID: 10, waitsForDecision: true, requestID: "r1", timeout: 120)
        let frame = try #require(AgentWire.frame(envelope))
        #expect(frame.last == 0x0A)
        #expect(frame.dropLast().firstIndex(of: 0x0A) == nil) // one line, whatever the payload holds
        #expect(AgentWire.decodeEnvelope(frame.dropLast()) == envelope)

        let reply = HookReply(requestID: "r1", decision: .allowForSession)
        #expect(AgentWire.decodeReply(try #require(AgentWire.frame(reply)).dropLast()) == reply)
    }

    @Test func toleratesUnknownFieldsAndDecisions() {
        let line = Data(#"{"v":2,"agent":"codex","event":"Stop","payload":{"session_id":"x"},"future":true}"#.utf8)
        let envelope = AgentWire.decodeEnvelope(line)
        #expect(envelope?.v == 2)
        #expect(envelope?.ppids == [])
        #expect(envelope?.waitsForDecision == false)

        // An answer this version doesn't know is never an approval.
        #expect(AgentWire.decodeReply(Data(#"{"requestID":"r","decision":"allowForever"}"#.utf8))?.decision == WireDecision.none)
    }

    @Test func lineBufferSplitsAcrossChunks() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("{\"a\":".utf8)).isEmpty)
        let lines = buffer.append(Data("1}\n{\"b\":2}\n{\"c\"".utf8))
        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == ["{\"a\":1}", "{\"b\":2}"])
        #expect(buffer.append(Data(":3}\n".utf8)).count == 1)
    }

    @Test func socketPathDefaultsAndOverride() {
        #expect(AgentWire.socketPath(environment: [:], home: "/Users/me")
            == "/Users/me/Library/Application Support/Altillo/agents.sock")
        #expect(AgentWire.socketPath(environment: ["ALTILLO_AGENTS_SOCKET": "/tmp/x.sock"]) == "/tmp/x.sock")
    }

    @Test func invocationParsing() {
        #expect(HookRunner.invocation(arguments: ["claude", "PermissionRequest", "--timeout", "45"], environment: [:])
            == .init(agent: "claude", event: "PermissionRequest", timeout: 45))
        #expect(HookRunner.invocation(arguments: ["codex", "Stop"], environment: ["ALTILLO_HOOK_TIMEOUT": "30"])?.timeout == 30)
        #expect(HookRunner.invocation(arguments: ["codex", "Stop", "--timeout=5"], environment: [:])?.timeout == 5)
        #expect(HookRunner.invocation(arguments: ["codex", "Stop"], environment: [:])?.timeout == 120)
        #expect(HookRunner.invocation(arguments: ["claude"], environment: [:]) == nil)
        #expect(HookRunner.invocation(arguments: [], environment: [:]) == nil)
    }

    @Test func noSocketMeansNoOutputAtOnce() throws {
        let payload = try Fixtures.payload("claude", "PermissionRequest").data
        var stdinRead = false
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let output = HookRunner.run(
                arguments: ["claude", "PermissionRequest"], environment: ["ALTILLO_AGENTS_SOCKET": Self.socketPath()],
                readStdin: { stdinRead = true; return payload })
            #expect(output == nil)
        }
        #expect(stdinRead) // always drained, so the agent never sees a broken pipe
        #expect(elapsed < .milliseconds(50))
    }

    @Test func staleSocketFileMeansNoOutputAtOnce() throws {
        // A socket file left by a crashed Altillo: nobody listens, connect is refused.
        let path = Self.socketPath()
        let listener = try UnixSocket.listen(path: path)
        close(listener.fd)
        defer { unlink(path) }
        let output = HookRunner.run(arguments: ["codex", "PermissionRequest"], environment: ["ALTILLO_AGENTS_SOCKET": path],
                                    readStdin: { Data(#"{"session_id":"s"}"#.utf8) })
        #expect(output == nil)
    }

    /// A listener that records envelopes and answers waiting ones with `decision` (or never, when nil).
    final class FakeApp: @unchecked Sendable {
        let path = WireProtocolTests.socketPath()
        let fd: Int32
        private let lock = NSLock()
        private var received: [HookEnvelope] = []
        var envelopes: [HookEnvelope] { lock.withLock { received } }

        /// `reply`: what a waiting stop hook gets (nil: held open until it gives up).
        init(decision: WireDecision?, reply: String? = nil) throws {
            fd = try UnixSocket.listen(path: path).fd
            // The fake serves one connection at a time, blocking.
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
            let (fd, path) = (fd, path)
            Thread.detachNewThread { [self] in
                while true {
                    let client = accept(fd, nil, nil)
                    if client < 0 { return }
                    guard let line = UnixSocket.readLine(client, timeout: 5),
                          let envelope = AgentWire.decodeEnvelope(line) else { close(client); continue }
                    lock.withLock { received.append(envelope) }
                    if envelope.waitsForReply, let requestID = envelope.requestID {
                        if let reply {
                            UnixSocket.writeAll(client, AgentWire.frame(HookReply(requestID: requestID, decision: .reply,
                                                                                  text: reply))!)
                        } else if let decision {
                            UnixSocket.writeAll(client, AgentWire.frame(HookReply(requestID: requestID, decision: decision))!)
                        } else {
                            _ = UnixSocket.readLine(client, timeout: 10)
                        }
                    } else if envelope.waitsForDecision, let requestID = envelope.requestID, let decision {
                        UnixSocket.writeAll(client, AgentWire.frame(HookReply(requestID: requestID, decision: decision))!)
                    } else if envelope.waitsForDecision {
                        _ = UnixSocket.readLine(client, timeout: 10) // hold it open until the hook gives up
                    }
                    close(client)
                }
            }
            _ = path
        }

        func stop() {
            shutdown(fd, SHUT_RDWR)
            close(fd)
            unlink(path)
        }
    }

    @Test func fireAndForgetEventsSendTheEnvelope() throws {
        let app = try FakeApp(decision: nil)
        defer { app.stop() }
        let payload = try Fixtures.payload("claude", "PreToolUse-Bash-ls")
        let output = HookRunner.run(
            arguments: ["claude", "PreToolUse"],
            environment: ["ALTILLO_AGENTS_SOCKET": app.path, "TERM_PROGRAM": "iTerm.app", "SECRET_TOKEN": "x"],
            readStdin: { payload.data },
            ancestors: { [.init(pid: 500, parent: 400, name: "claude", tty: "/dev/ttys009"),
                          .init(pid: 400, parent: 1, name: "zsh", tty: "/dev/ttys009")] })
        #expect(output == nil)
        try waitUntil { !app.envelopes.isEmpty }
        let envelope = try #require(app.envelopes.first)
        #expect(envelope.agent == "claude")
        #expect(envelope.event == "PreToolUse")
        #expect(envelope.payload == payload)
        #expect(envelope.env == ["TERM_PROGRAM": "iTerm.app"]) // nothing else from the environment
        #expect(envelope.ppids == [500, 400])
        #expect(envelope.agentPID == 500)
        #expect(envelope.tty == "/dev/ttys009")
        #expect(!envelope.waitsForDecision)
    }

    @Test(arguments: [WireDecision.allow, .allowForSession, .deny])
    func permissionDecisionIsPrinted(decision: WireDecision) throws {
        let app = try FakeApp(decision: decision)
        defer { app.stop() }
        let payload = try Fixtures.payload("claude", "PermissionRequest")
        let output = try #require(HookRunner.run(
            arguments: ["claude", "PermissionRequest", "--timeout", "10"],
            environment: ["ALTILLO_AGENTS_SOCKET": app.path], readStdin: { payload.data }))
        let json = try #require(JSONValue.parse(output))
        #expect(json.value(at: "hookSpecificOutput.hookEventName")?.string == "PermissionRequest")
        let behavior = json.value(at: "hookSpecificOutput.decision.behavior")?.string
        #expect(behavior == (decision == .deny ? "deny" : "allow"))
        let envelope = try #require(app.envelopes.first)
        #expect(envelope.waitsForDecision)
        #expect(envelope.timeout == 10)
    }

    @Test func noDecisionPrintsNothing() throws {
        let app = try FakeApp(decision: WireDecision.none)
        defer { app.stop() }
        let output = HookRunner.run(arguments: ["codex", "PermissionRequest"], environment: ["ALTILLO_AGENTS_SOCKET": app.path],
                                    readStdin: { try! Fixtures.payload("codex", "PermissionRequest-Bash.docs").data })
        #expect(output == nil)
    }

    @Test func timeoutPrintsNothingAndReturnsOnTime() throws {
        let app = try FakeApp(decision: nil) // never answers
        defer { app.stop() }
        let start = Date()
        let output = HookRunner.run(arguments: ["claude", "PermissionRequest", "--timeout", "1"],
                                    environment: ["ALTILLO_AGENTS_SOCKET": app.path],
                                    readStdin: { try! Fixtures.payload("claude", "PermissionRequest").data })
        #expect(output == nil)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed >= 0.9 && elapsed < 3)
    }

    // MARK: Deadlines and ownership

    /// A listener that never accepts nor reads: the app process stopped (SIGSTOP) or wedged.
    static func stalledListener() throws -> (path: String, fd: Int32) {
        let path = socketPath()
        return (path, try UnixSocket.listen(path: path, backlog: 1).fd)
    }

    @Test func writeGivesUpOnAStalledPeer() throws {
        let (path, listener) = try Self.stalledListener()
        defer { close(listener); unlink(path) }
        let fd = try UnixSocket.connect(path: path)
        defer { close(fd) }
        let start = Date()
        #expect(!UnixSocket.writeAll(fd, Data(count: 8 << 20), timeout: 0.3))
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed >= 0.25 && elapsed < 1.5)
    }

    @Test func hookNeverHangsOnAStalledApp() throws {
        let (path, listener) = try Self.stalledListener()
        defer { close(listener); unlink(path) }
        // A Write of a big file: far more than the socket buffer, and not trimmed (it's tool_input).
        let big = String(repeating: "x", count: 2 << 20)
        let payload = JSONValue.object([
            "session_id": .string("s"), "hook_event_name": .string("PreToolUse"), "tool_name": .string("Write"),
            "tool_input": .object(["file_path": .string("/p/big.txt"), "content": .string(big)]),
        ])
        let start = Date()
        let output = HookRunner.run(arguments: ["claude", "PreToolUse"], environment: ["ALTILLO_AGENTS_SOCKET": path],
                                    readStdin: { payload.data })
        #expect(output == nil)
        #expect(Date().timeIntervalSince(start) < HookRunner.connectTimeout + HookRunner.writeTimeout + 1)
    }

    @Test func aSecondListenerIsRefusedAndTheFirstKeepsItsSocket() throws {
        let path = Self.socketPath()
        let first = try UnixSocket.listen(path: path)
        defer { close(first.fd); unlink(path) }
        #expect(throws: UnixSocket.Failure.inUse) { try UnixSocket.listen(path: path) }
        #expect(UnixSocket.inode(of: path) == first.inode)
        let client = try UnixSocket.connect(path: path)
        close(client)
    }

    @Test func removeOnlyTheSocketFileWeCreated() throws {
        let path = Self.socketPath()
        let old = try UnixSocket.listen(path: path)
        close(old.fd) // it died; a new instance replaces the stale file
        let current = try UnixSocket.listen(path: path)
        defer { close(current.fd); unlink(path) }
        #expect(current.inode != old.inode)
        #expect(!UnixSocket.removeIfOwned(path: path, listener: old))
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(UnixSocket.removeIfOwned(path: path, listener: current))
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func socketsAreCloseOnExec() throws {
        let path = Self.socketPath()
        let listener = try UnixSocket.listen(path: path)
        defer { close(listener.fd); unlink(path) }
        let client = try UnixSocket.connect(path: path)
        defer { close(client) }
        #expect(fcntl(listener.fd, F_GETFD) & FD_CLOEXEC != 0)
        #expect(fcntl(client, F_GETFD) & FD_CLOEXEC != 0)
        let accepted = try #require(UnixSocket.accept(listener.fd))
        defer { close(accepted) }
        #expect(fcntl(accepted, F_GETFD) & FD_CLOEXEC != 0)
        #expect(fcntl(accepted, F_GETFL) & O_NONBLOCK != 0)
    }

    func waitUntil(_ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            if Date() > deadline { Issue.record("timed out"); return }
            usleep(5000)
        }
    }
}

@Suite("Decision output")
struct HookDecisionOutputTests {
    func decision(_ agent: AgentKind, _ wire: WireDecision, _ fixture: String) throws -> JSONValue? {
        let payload = try Fixtures.payload(agent.rawValue, fixture)
        return HookDecisionOutput.output(agent: agent, decision: wire, payload: payload).flatMap(JSONValue.parse)
    }

    @Test func claudeAllowAndDeny() throws {
        let allow = try #require(try decision(.claude, .allow, "PermissionRequest"))
        #expect(allow == JSONValue.parse(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#))
        let deny = try #require(try decision(.claude, .deny, "PermissionRequest"))
        #expect(deny.value(at: "hookSpecificOutput.decision.behavior")?.string == "deny")
        #expect(deny.value(at: "hookSpecificOutput.decision.message")?.string == HookDecisionOutput.denyMessage)
        #expect(try decision(.claude, .none, "PermissionRequest") == nil)
    }

    @Test func claudeAllowForSessionEchoesSuggestionsSessionOnly() throws {
        // Real capture: addDirectories + setMode(acceptEdits), plus the exact command as a session rule.
        let output = try #require(try decision(.claude, .allowForSession, "PermissionRequest"))
        let updates = try #require(output.value(at: "hookSpecificOutput.decision.updatedPermissions")?.array)
        #expect(updates.map { $0["type"]?.string } == ["addDirectories", "setMode", "addRules"])
        #expect(updates.allSatisfy { $0["destination"]?.string == "session" })
        #expect(updates[2].value(at: "rules")?[0]?["ruleContent"]?.string == "touch made-by-test.txt")

        // Docs example: a localSettings rule becomes session-only; a bypassPermissions mode is never echoed.
        let docs = try #require(try decision(.claude, .allowForSession, "PermissionRequest-addRules.docs"))
        let docUpdates = try #require(docs.value(at: "hookSpecificOutput.decision.updatedPermissions")?.array)
        #expect(docUpdates.count == 1)
        #expect(docUpdates[0]["type"]?.string == "addRules")
        #expect(docUpdates[0]["destination"]?.string == "session")
    }

    @Test func codexNeverGetsReservedFields() throws {
        let allow = try #require(try decision(.codex, .allowForSession, "PermissionRequest-Bash.docs"))
        #expect(allow == JSONValue.parse(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#))
        let deny = try #require(try decision(.codex, .deny, "PermissionRequest-Bash.docs"))
        #expect(deny.value(at: "hookSpecificOutput.decision")?.object?.keys.sorted() == ["behavior", "message"])
    }

    @Test func codexOutputsMatchTheInstalled0152SchemaContract() throws {
        let contract = try Fixtures.resource("contracts", "CodexPermissionRequest-0.152.0")
        #expect(contract.value(at: "provenance.version")?.string == "0.152.0")
        #expect(contract.value(at: "provenance.live_interactive_capture")?.bool == false)

        let payload = try #require(contract["input"])
        let event = try #require(HookPayloadParser.parse(agent: .codex, eventName: nil, payload: payload))
        guard case .permissionRequested(let call, let suggestions) = event.kind else {
            Issue.record("installed-schema fixture did not parse as a permission request")
            return
        }
        #expect(call.name == "Bash")
        #expect(call.command == "touch harmless-validation-file.txt")
        #expect(suggestions.isEmpty)

        let allow = try #require(HookDecisionOutput.output(agent: .codex, decision: .allow, payload: payload)
            .flatMap(JSONValue.parse))
        let deny = try #require(HookDecisionOutput.output(agent: .codex, decision: .deny, payload: payload)
            .flatMap(JSONValue.parse))
        #expect(allow == contract.value(at: "accepted_outputs.allow"))
        #expect(deny == contract.value(at: "accepted_outputs.deny"))

        let allowForSession = try #require(HookDecisionOutput.output(agent: .codex, decision: .allowForSession,
                                                                     payload: payload).flatMap(JSONValue.parse))
        #expect(allowForSession == allow)
        let decision = try #require(allowForSession.value(at: "hookSpecificOutput.decision")?.object)
        let reserved = Set(contract["reserved_decision_fields"]?.array?.compactMap(\.string) ?? [])
        #expect(reserved.isDisjoint(with: decision.keys))
        #expect(HookDecisionOutput.output(agent: .codex, decision: .none, payload: payload) == nil)
    }

    @Test func codexContractFixtureIsSanitized() throws {
        let contract = try Fixtures.resource("contracts", "CodexPermissionRequest-0.152.0")
        let text = String(decoding: contract.data, as: UTF8.self)
        #expect(!text.contains(NSHomeDirectory()))
        #expect(!text.localizedCaseInsensitiveContains("token"))
        #expect(!text.contains("@"))
    }
}
