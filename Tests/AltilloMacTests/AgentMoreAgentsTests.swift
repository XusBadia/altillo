import AltilloAgents
import AltilloCore
import Darwin
import Foundation
import Testing
@testable import Altillo

/// Phase 14 in the app: replying from the notch through a real stop hook (the same `HookRunner` the `altillo-hook`
/// binary runs) over the hub's real socket, with its timeout and release paths; OpenCode's server events; Gemini
/// and Copilot permission prompts that only the terminal can answer; Gemini chat files.
@MainActor
@Suite(.serialized)
struct AgentRepliesHubTests {
    typealias Base = AgentHubTests

    nonisolated static let terminal: [ProcessTree.Entry] = [.init(pid: 99_990, parent: 99_991, name: "claude", tty: "/dev/ttys009"),
                                                .init(pid: 99_991, parent: 1, name: "zsh", tty: "/dev/ttys009")]

    /// A Claude TUI's Stop hook installed with `--reply-wait`, off the main actor. `terminalApp` is the terminal's
    /// bundle id as the hook reports it (`__CFBundleIdentifier`).
    nonisolated static func stopHook(_ socket: String, wait: Int, message: String = "Done. Push it?",
                                     terminalApp: String = "com.example.terminal") async -> Data? {
        let payload = Data(#"{"session_id":"fc6f9b07-c1a0-497d-96c8-94c48f710cb1","transcript_path":"/nonexistent/x.jsonl","cwd":"/Users/me/Projects/demo","permission_mode":"default","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"\#(message)"}"#.utf8)
        return await Task.detached {
            HookRunner.run(arguments: ["claude", "Stop", "--reply-wait", String(wait)],
                           environment: ["ALTILLO_AGENTS_SOCKET": socket, "CLAUDE_CODE_ENTRYPOINT": "cli",
                                         "__CFBundleIdentifier": terminalApp],
                           readStdin: { payload }, ancestors: { terminal }, agentArguments: { _ in ["claude"] },
                           stdinIsTerminal: { _ in true })
        }.value
    }

    func hub(_ path: String, frontmost: String? = "com.example.other") -> AgentHub {
        let hub = AgentHub(socketPath: path, fileRoots: nil, openCodeData: nil)
        hub.frontmostApp = { (frontmost, nil) }
        hub.start()
        return hub
    }

    /// A Cursor TUI's own `stop` hook (with `--reply-wait`), or the same turn's end through Claude's hooks.
    nonisolated static func cursorStop(_ socket: String, installedFor agent: String, wait: Int?) async -> Data? {
        let payload = Data(#"{"conversation_id":"c1","session_id":"c1","hook_event_name":"stop","status":"completed","loop_count":0,"cursor_version":"2026.09.23","workspace_roots":["/Users/me/Projects/demo"]}"#.utf8)
        var arguments = [agent, agent == "cursor" ? "stop" : "Stop"]
        if let wait { arguments += ["--reply-wait", String(wait)] }
        return await Task.detached {
            HookRunner.run(arguments: arguments,
                           environment: ["ALTILLO_AGENTS_SOCKET": socket, "__CFBundleIdentifier": "com.example.terminal"],
                           readStdin: { payload }, ancestors: { terminal }, agentArguments: { _ in ["cursor-agent"] },
                           stdinIsTerminal: { _ in true })
        }.value
    }

    @Test func cursorsSecondReportOfTheSameStopKeepsTheWait() async throws {
        // Order 1: Cursor's own stop hook waits, then the same stop arrives through Claude's hooks.
        let path = Base.socketPath()
        let hub = hub(path)
        defer { hub.stop() }
        let held = Task { await Self.cursorStop(path, installedFor: "cursor", wait: 30) }
        try await Base().waitUntil { hub.sessions.first?.reply != nil }
        #expect(await Self.cursorStop(path, installedFor: "claude", wait: 30) == nil) // rerouted: never waits
        try await Task.sleep(for: .milliseconds(200))
        let session = try #require(hub.sessions.first)
        #expect(session.id == "cursor:c1")
        #expect(session.reply?.kind == .stopHook)
        #expect(hub.reply("go on", to: session))
        let output = try #require(await held.value)
        #expect(JSONValue.parse(output)?["followup_message"]?.string?.hasSuffix("go on") == true)

        // Order 2: through Claude's hooks first, then Cursor's own.
        #expect(await Self.cursorStop(path, installedFor: "claude", wait: nil) == nil)
        let second = Task { await Self.cursorStop(path, installedFor: "cursor", wait: 30) }
        try await Base().waitUntil { hub.sessions.first?.reply != nil }
        #expect(await Self.cursorStop(path, installedFor: "claude", wait: nil) == nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(hub.sessions.first?.reply != nil)
        hub.letStop(try #require(hub.sessions.first))
        #expect(await second.value == nil)
    }

    @Test func noStopLetsTheAgentStopNow() async throws {
        let path = Base.socketPath()
        let hub = hub(path)
        defer { hub.stop() }
        let start = Date()
        let hook = Task { await Self.stopHook(path, wait: 30) }
        try await Base().waitUntil { hub.sessions.first?.reply != nil }
        hub.letStop(try #require(hub.sessions.first))
        #expect(await hook.value == nil)
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(hub.sessions.first?.phase == .waitingAnswer)
        #expect(hub.sessions.first?.reply == nil)
    }

    @Test func aReplyTooCloseToTheDeadlineFailsAndTheFieldSaysSo() async throws {
        let path = Base.socketPath()
        let hub = hub(path)
        defer { hub.stop() }
        let hook = Task { await Self.stopHook(path, wait: 1) }
        try await Base().waitUntil { hub.sessions.first?.reply != nil }
        try await Task.sleep(for: .milliseconds(200))
        let session = try #require(hub.sessions.first)
        #expect(hub.sendReply("Yes", to: session) == .unavailable)
        #expect(await hook.value == nil) // let go without the reply: the agent stops as usual
        let after = try #require(hub.sessions.first)
        #expect(after.phase == .waitingAnswer)
        #expect(after.reply?.isClosed == true) // the field stays, in its failed state
        #expect(hub.sendReply("Yes", to: after) == .unavailable)
        // Until the session moves on: a new turn clears it.
        _ = await Base.hook(path, ["claude", "UserPromptSubmit"], Base.payload("UserPromptSubmit", #","prompt":"ok""#))
        try await Base().waitUntil { hub.sessions.first?.phase == .working }
        #expect(hub.sessions.first?.reply == nil)
    }

    @Test func aTooLongReplyIsRefusedAndTheWaitGoesOn() async throws {
        let path = Base.socketPath()
        let hub = hub(path)
        defer { hub.stop() }
        let hook = Task { await Self.stopHook(path, wait: 30) }
        try await Base().waitUntil { hub.sessions.first?.reply != nil }
        let session = try #require(hub.sessions.first)
        #expect(hub.sendReply(String(repeating: "x", count: AgentHub.maxReplyBytes + 1), to: session) == .tooLong)
        #expect(hub.sessions.first?.reply?.isClosed == false)
        #expect(hub.sendReply("short", to: session) == .sent)
        #expect(await hook.value != nil)
    }

    @Test func withTheAgentsModuleOffNothingWaits() async throws {
        let path = Base.socketPath()
        let hub = hub(path)
        defer { hub.stop() }
        var enabled = false
        hub.isModuleEnabled = { enabled }
        let start = Date()
        #expect(await Self.stopHook(path, wait: 30) == nil)
        let permission = await Task.detached {
            HookRunner.run(arguments: ["claude", "PermissionRequest", "--timeout", "30"],
                           environment: ["ALTILLO_AGENTS_SOCKET": path],
                           readStdin: { Data(#"{"session_id":"p1","cwd":"/p","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}"#.utf8) })
        }.value
        #expect(permission == nil)
        #expect(Date().timeIntervalSince(start) < 5)

        // Switched off while a hook is held: it lets go at once.
        enabled = true
        let held = Task { await Self.stopHook(path, wait: 30) }
        try await Base().waitUntil { hub.sessions.contains { $0.reply != nil } }
        enabled = false
        hub.moduleAvailabilityChanged()
        #expect(await held.value == nil)
        #expect(!hub.sessions.contains { $0.reply != nil })
    }

    @Test func copilotsContinuationCapIsRespected() async throws {
        let path = Base.socketPath()
        let hub = hub(path)
        defer { hub.stop() }
        func agentStop() async -> Data? {
            let payload = Data(#"{"sessionId":"k1","timestamp":1,"cwd":"/Users/me/Projects/demo","stopReason":"end_turn","stop_hook_active":true}"#.utf8)
            return await Task.detached {
                HookRunner.run(arguments: ["copilot", "agentStop", "--reply-wait", "30"],
                               environment: ["ALTILLO_AGENTS_SOCKET": path, "__CFBundleIdentifier": "com.example.terminal"],
                               readStdin: { payload },
                               ancestors: { Self.terminal }, agentArguments: { _ in ["copilot"] },
                               stdinIsTerminal: { _ in true })
            }.value
        }
        for _ in 0..<(AgentHub.continuationCaps[.copilot] ?? 8) {
            let hook = Task { await agentStop() }
            try await Base().waitUntil { hub.sessions.first?.reply != nil }
            let waiting = try #require(hub.sessions.first)
            #expect(hub.reply("more", to: waiting))
            #expect(await hook.value != nil)
        }
        let start = Date()
        #expect(await agentStop() == nil) // Copilot would end the turn anyway: don't hold it
        #expect(Date().timeIntervalSince(start) < 2)
    }

    // MARK: Part C: going to the terminal lets the hook go

    @Test func anUnknownTerminalAppNeverHoldsTheStop() async throws {
        // tmux, SSH…: no bundle id and no GUI app up from the agent, so going back couldn't let it go.
        let path = Base.socketPath()
        let hub = hub(path)
        hub.identifiesHost = { $0.appBundleID != nil }
        defer { hub.stop() }
        let start = Date()
        #expect(await Self.stopHook(path, wait: 30, terminalApp: "") == nil)
        #expect(Date().timeIntervalSince(start) < 5)
        try await Base().waitUntil { hub.sessions.first?.phase == .waitingAnswer }
        #expect(hub.sessions.first?.reply == nil)
    }

    @Test func aStopWhileTheTerminalIsFrontmostDoesntWait() async throws {
        let path = Base.socketPath()
        let hub = hub(path, frontmost: "com.example.terminal")
        defer { hub.stop() }
        let start = Date()
        #expect(await Self.stopHook(path, wait: 30) == nil)
        #expect(Date().timeIntervalSince(start) < 5)
        try await Base().waitUntil { hub.sessions.first?.phase == .waitingAnswer }
        #expect(hub.sessions.first?.reply == nil)
        #expect(!hub.isObservingActivations)
    }

    @Test func switchingToTheTerminalLetsItGoButOtherAppsDont() async throws {
        let path = Base.socketPath()
        let hub = hub(path)
        defer { hub.stop() }
        #expect(!hub.isObservingActivations)
        let hook = Task { await Self.stopHook(path, wait: 30) }
        try await Base().waitUntil { hub.sessions.first?.reply != nil }
        #expect(hub.isObservingActivations) // only while a hook is held
        hub.applicationActivated(bundleID: "com.example.browser", pid: 123)
        #expect(hub.sessions.first?.reply != nil)
        hub.applicationActivated(bundleID: "com.example.terminal", pid: 456)
        #expect(await hook.value == nil)
        #expect(hub.sessions.first?.reply == nil)
        #expect(!hub.isObservingActivations)
    }

    @Test func aReplyReachesTheWaitingStopHookAndTheAgentCarriesOn() async throws {
        let path = Base.socketPath()
        let hub = hub(path)
        defer { hub.stop() }
        let hook = Task { await Self.stopHook(path, wait: 30) }
        try await Base().waitUntil { hub.sessions.first?.reply != nil }
        let session = try #require(hub.sessions.first)
        #expect(session.phase == .waitingAnswer)
        #expect(session.lastMessage == "Done. Push it?")
        #expect(session.reply?.kind == .stopHook)
        #expect(session.reply?.expiresAt.map { $0.timeIntervalSince(session.reply!.openedAt) } == 30)

        #expect(hub.reply("  Yes, push it  ", to: session))
        let output = try #require(await hook.value)
        let json = try #require(JSONValue.parse(output))
        #expect(json["decision"]?.string == "block")
        #expect(json["reason"]?.string == "The user replied from Altillo (their notch):\n\nYes, push it")
        let after = try #require(hub.sessions.first)
        #expect(after.phase == .working)
        #expect(after.reply == nil)
        // Nothing waits any more: a second reply has nowhere to go.
        #expect(!hub.reply("again", to: after))
    }

    @Test func whenTheHookGivesUpTheReplyFieldGoes() async throws {
        let path = Base.socketPath()
        let hub = hub(path)
        defer { hub.stop() }
        let hook = Task { await Self.stopHook(path, wait: 1) }
        try await Base().waitUntil { hub.sessions.first?.reply != nil }
        #expect(await hook.value == nil) // stopped as usual, nothing printed
        try await Base().waitUntil { hub.sessions.first?.reply == nil }
        let session = try #require(hub.sessions.first)
        #expect(session.phase == .waitingAnswer)
        #expect(!hub.reply("too late", to: session))
    }

    @Test func dismissingOrANewTurnLetsTheHookGo() async throws {
        let path = Base.socketPath()
        let hub = hub(path)
        defer { hub.stop() }
        let start = Date()
        let hook = Task { await Self.stopHook(path, wait: 30) }
        try await Base().waitUntil { hub.sessions.first?.reply != nil }
        hub.dismiss(try #require(hub.sessions.first))
        #expect(await hook.value == nil)
        #expect(Date().timeIntervalSince(start) < 5)

        let second = Task { await Self.stopHook(path, wait: 30) }
        try await Base().waitUntil { hub.sessions.first?.reply != nil }
        // The user typed in the terminal instead (the hook is killed and a prompt follows).
        _ = await Base.hook(path, ["claude", "UserPromptSubmit"], Base.payload("UserPromptSubmit", #","prompt":"no""#))
        #expect(await second.value == nil)
        try await Base().waitUntil { hub.sessions.first?.phase == .working }
        #expect(hub.sessions.first?.reply == nil)
    }

    @Test func copilotAndGeminiPromptsAreShownButAnsweredInTheTerminal() async throws {
        let path = Base.socketPath()
        let hub = hub(path)
        defer { hub.stop() }
        let session = "b7e0d3c4-2f61-4a8e-a1d9-0c5e7f3b2d48"
        let common = #""sessionId":"\#(session)","timestamp":1790341911209,"cwd":"/Users/me/Projects/demo""#
        _ = await Base.hook(path, ["copilot", "permissionRequest", "--timeout", "5"],
                            Data(#"{\#(common),"toolName":"bash","toolArgs":{"command":"npm test"}}"#.utf8))
        _ = await Base.hook(path, ["copilot", "notification"],
                            Data(#"{\#(common),"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Allow?"}"#.utf8))
        try await Base().waitUntil { hub.sessions.first?.phase == .waitingPermission }
        let waiting = try #require(hub.sessions.first)
        #expect(waiting.agent == .copilot)
        let request = try #require(waiting.pendingRequest)
        #expect(request.summary == "npm test")
        #expect(AgentsLogic.isExpired(request, now: Date())) // no buttons: the terminal answers it
        #expect(AgentAlerts.alert(from: nil, to: waiting, now: request.requestedAt) != nil)
        _ = await Base.hook(path, ["copilot", "postToolUse"],
                            Data(#"{\#(common),"toolName":"bash","toolArgs":{"command":"npm test"},"toolResult":{"resultType":"success"}}"#.utf8))
        try await Base().waitUntil { hub.sessions.first?.phase == .working }
        #expect(hub.sessions.first?.pendingRequest == nil)
    }

    @Test func openCodeSessionsFromItsServer() throws {
        let hub = AgentHub(socketPath: Base.socketPath(), fileRoots: nil, openCodeData: nil)
        let server = OpenCodeMonitor.Server(pid: 4242, port: 4096)
        let id = "ses_1"
        let dir = "/Users/me/Projects/demo"
        func send(_ event: OpenCodeEvent) { hub.receive(openCode: event, directory: dir, server: server) }

        send(.session(id: id, directory: dir, title: "t", parentID: nil, updatedAt: nil))
        #expect(hub.sessions.isEmpty) // an update alone isn't news
        send(.status(sessionID: id, status: "busy"))
        var session = try #require(hub.sessions.first)
        #expect(session.id == "opencode:ses_1")
        #expect(session.source == .server)
        #expect(session.project == "demo")
        #expect(session.phase == .working)

        send(.tool(sessionID: id, call: AgentToolCall(name: "Bash", input: .object(["command": .string("echo hi")])),
                   status: "running"))
        #expect(hub.sessions.first?.activity == "Running `echo hi`")

        let permission = try #require(OpenCodePermission(.object([
            "id": .string("per_1"), "sessionID": .string(id), "permission": .string("bash"),
            "patterns": .array([.string("echo hi")]), "metadata": .object(["command": .string("echo hi")]),
            "always": .array([.string("echo *")]),
        ])))
        send(.permissionAsked(permission))
        session = try #require(hub.sessions.first)
        #expect(session.phase == .waitingPermission)
        #expect(session.pendingRequest?.id == "per_1")
        #expect(session.pendingRequest?.canAllowForSession == true)
        #expect(session.pendingRequest?.isExpired == false) // answerable from the notch
        send(.permissionReplied(sessionID: id, requestID: "per_1"))
        #expect(hub.sessions.first?.phase == .working)

        // Subagent sessions stay out of the list.
        send(.session(id: "ses_child", directory: dir, title: nil, parentID: id, updatedAt: nil))
        send(.status(sessionID: "ses_child", status: "busy"))
        #expect(hub.sessions.count == 1)

        send(.messageRole(sessionID: id, messageID: "msg_1", role: "assistant"))
        send(.text(sessionID: id, messageID: "msg_1", text: "BRAVO"))
        send(.idle(sessionID: id))
        session = try #require(hub.sessions.first)
        #expect(session.phase == .waitingAnswer)
        #expect(session.lastMessage == "BRAVO")
        #expect(session.reply?.kind == .server)
        #expect(!hub.reply("hi", to: session)) // no monitor running in this test: nothing to send it with

        hub.receive(openCode: .error(sessionID: id, message: "MessageAbortedError"), directory: dir, server: server)
        #expect(hub.sessions.first?.phase == .idle)
    }

    static let ocServer = OpenCodeMonitor.Server(pid: 4242, port: 4096)

    static func ocPermission(_ id: String, session: String = "ses_1", command: String = "echo hi") -> OpenCodePermission {
        OpenCodePermission(.object([
            "id": .string(id), "sessionID": .string(session), "permission": .string("bash"),
            "patterns": .array([.string(command)]), "metadata": .object(["command": .string(command)]),
            "always": .array([]),
        ]))!
    }

    @Test func openCodePermissionsQueueAndFailuresComeBack() throws {
        let hub = AgentHub(socketPath: Base.socketPath(), fileRoots: nil, openCodeData: nil)
        let dir = "/Users/me/Projects/demo"
        func send(_ event: OpenCodeEvent) { hub.receive(openCode: event, directory: dir, server: Self.ocServer) }
        send(.status(sessionID: "ses_1", status: "busy"))
        send(.permissionAsked(Self.ocPermission("per_1", command: "echo one")))
        send(.permissionAsked(Self.ocPermission("per_2", command: "echo two")))
        #expect(hub.sessions.first?.pendingRequest?.id == "per_1") // the second waits its turn
        send(.permissionReplied(sessionID: "ses_1", requestID: "per_1"))
        #expect(hub.sessions.first?.pendingRequest?.id == "per_2")
        #expect(hub.sessions.first?.phase == .waitingPermission)

        // No server to take the answer (none running in this test): the request stays, saying so.
        hub.decide("per_2", .allow)
        let session = try #require(hub.sessions.first)
        #expect(session.pendingRequest?.id == "per_2")
        #expect(session.pendingRequest?.failure != nil)
        #expect(session.phase == .waitingPermission)
        send(.permissionReplied(sessionID: "ses_1", requestID: "per_2")) // answered in OpenCode after all
        #expect(hub.sessions.first?.pendingRequest == nil)
        #expect(hub.sessions.first?.phase == .working)
    }

    @Test func openCodeReconnectionReconcilesWhatThePassedStreamMissed() throws {
        let hub = AgentHub(socketPath: Base.socketPath(), fileRoots: nil, openCodeData: nil)
        let dir = "/Users/me/Projects/demo"
        func send(_ event: OpenCodeEvent) { hub.receive(openCode: event, directory: dir, server: Self.ocServer) }
        send(.status(sessionID: "ses_1", status: "busy"))
        send(.permissionAsked(Self.ocPermission("per_1")))
        send(.status(sessionID: "ses_2", status: "busy"))
        // While disconnected: per_1 was answered, ses_1 finished its turn, ses_2 still works, and a new one asks.
        hub.apply([OpenCodeMonitor.State(directory: dir, permissions: [Self.ocPermission("per_9", session: "ses_3")],
                                         statuses: ["ses_2": "busy", "ses_3": "busy"])], from: Self.ocServer)
        let byID = Dictionary(uniqueKeysWithValues: hub.sessions.map { ($0.sessionID, $0) })
        #expect(byID["ses_1"]?.pendingRequest == nil)
        #expect(byID["ses_1"]?.phase == .waitingAnswer)
        #expect(byID["ses_2"]?.phase == .working)
        #expect(byID["ses_3"]?.pendingRequest?.id == "per_9")
    }

    @Test func anUnansweredOpenCodeCardHasABackstop() throws {
        var clock = Date()
        let hub = AgentHub(socketPath: Base.socketPath(), fileRoots: nil, openCodeData: nil, now: { clock })
        hub.receive(openCode: .status(sessionID: "ses_1", status: "busy"), directory: "/p", server: Self.ocServer)
        hub.receive(openCode: .permissionAsked(Self.ocPermission("per_1")), directory: "/p", server: Self.ocServer)
        clock = clock.addingTimeInterval(AgentHub.openCodeRequestLimit - 60)
        hub.sweep()
        #expect(hub.sessions.first?.pendingRequest != nil)
        clock = clock.addingTimeInterval(120)
        hub.sweep()
        #expect(hub.sessions.first?.pendingRequest == nil)
        #expect(hub.sessions.first?.phase == .idle)
    }

    @Test func openCodeOnlyTrustsAPortItReallyListensOn() {
        #expect(OpenCodeMonitor.port(argument: 47123, listening: [47123]) == 47123)
        #expect(OpenCodeMonitor.port(argument: 47123, listening: [4096]) == nil)
        #expect(OpenCodeMonitor.port(argument: nil, listening: [4096]) == 4096)
        #expect(OpenCodeMonitor.port(argument: nil, listening: []) == nil)
    }

    @Test func withoutOpenCodeNothingIsWatchedRecursivelyAndNothingIsScanned() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "altillo-oc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let share = root.appending(path: ".local/share")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let monitor = OpenCodeMonitor(dataDirectory: share.appending(path: "opencode"))
        monitor.start()
        defer { monitor.stop() }
        func state() -> (URL?, Int) { monitor.sync { (monitor.watchedAncestor, monitor.scanCount) } }
        #expect(state().0?.standardizedFileURL.path == root.standardizedFileURL.path) // ~/.local/share missing too
        #expect(state().1 == 0)
        try FileManager.default.createDirectory(at: share, withIntermediateDirectories: true)
        try await Base().waitUntil { state().0?.standardizedFileURL.path == share.standardizedFileURL.path }
        #expect(state().1 == 0)
        try FileManager.default.createDirectory(at: share.appending(path: "opencode"), withIntermediateDirectories: true)
        try await Base().waitUntil { state().1 == 1 } // it appeared: one scan, then FSEvents on it
        #expect(state().0 == nil)
    }

    @Test func geminiChatFilesShowSessionsWithoutHooks() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "altillo-gemini-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let chats = root.appending(path: ".gemini/tmp/demo/chats")
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        try Data(#"{"projects":{"/Users/me/Projects/demo":"demo"}}"#.utf8)
            .write(to: root.appending(path: ".gemini/projects.json"))
        let now = ISO8601DateFormatter().string(from: Date())
        let lines = [
            #"{"sessionId":"3f1c2a9e","projectHash":"h","startTime":"\#(now)","lastUpdated":"\#(now)","kind":"main"}"#,
            #"{"id":"1","timestamp":"\#(now)","type":"user","content":[{"text":"Add a flag"}]}"#,
            #"{"id":"2","timestamp":"\#(now)","type":"gemini","content":"","toolCalls":[{"name":"run_shell_command","args":{"command":"npm test"},"status":"awaiting_approval"}]}"#,
        ]
        try Data((lines.joined(separator: "\n") + "\n").utf8)
            .write(to: chats.appending(path: "session-2026-09-25T13-01-3f1c2a9e.jsonl"))
        let roots = AgentSessionFileWatcher.Roots(claudeProjects: root.appending(path: "none1"),
                                                  codexSessions: root.appending(path: "none2"),
                                                  geminiTemp: root.appending(path: ".gemini/tmp"))
        let hub = AgentHub(socketPath: Base.socketPath(), fileRoots: roots, openCodeData: nil)
        hub.start()
        defer { hub.stop() }
        try await Base().waitUntil { !hub.sessions.isEmpty }
        let session = try #require(hub.sessions.first)
        #expect(session.id == "gemini:3f1c2a9e")
        #expect(session.cwd == "/Users/me/Projects/demo")
        #expect(session.phase == .waitingPermission)
        #expect(session.source == .sessionFile)
    }

    @Test func agentNames() {
        #expect([AgentKind.gemini, .copilot, .opencode, .cursor].map(\.name) == ["Gemini", "Copilot", "OpenCode", "Cursor"])
        #expect(ToolAction(toolName: "run_shell_command") == .run)
        #expect(ToolAction(toolName: "replace") == .edit)
    }
}

/// The installer for Gemini CLI, Copilot CLI and Cursor, and the reply option. Temporary homes only.
struct AgentHookInstallerMoreAgentsTests {
    typealias Sandbox = AgentHookInstallerTests.Sandbox

    static func sandbox(_ folders: [String]) throws -> Sandbox {
        let sandbox = try Sandbox()
        for folder in folders {
            try FileManager.default.createDirectory(at: sandbox.environment.home.appending(path: folder),
                                                    withIntermediateDirectories: true)
        }
        return sandbox
    }

    static func json(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    static func install(_ sandbox: Sandbox, _ target: AgentHookTarget, reply: Bool = false) throws {
        let installer = AgentHookInstaller(environment: sandbox.environment, wait: 120,
                                           replyTargets: reply ? [target] : [])
        try installer.apply(installer.planInstall(target))
        #expect(installer.status(for: target) == .installed)
    }

    static func uninstall(_ sandbox: Sandbox, _ target: AgentHookTarget) throws {
        let installer = AgentHookInstaller(environment: sandbox.environment)
        try installer.apply(installer.planUninstall(target))
        #expect(installer.status(for: target) == .notInstalled)
    }

    @Test func geminiGroupedHooksWithMillisecondTimeouts() throws {
        let sandbox = try Self.sandbox([".gemini"])
        let file = sandbox.environment.configFile(for: .gemini)
        let original = """
        {
          "hooksConfig": {
            "notifications": false
          },
          "hooks": {
            "BeforeTool": [
              {
                "matcher": "write_file",
                "hooks": [
                  {
                    "type": "command",
                    "command": "./guard.sh",
                    "timeout": 5000
                  }
                ]
              }
            ]
          }
        }

        """
        try Data(original.utf8).write(to: file)
        try Self.install(sandbox, .gemini)
        let hooks = try #require(try Self.json(file)["hooks"] as? [String: [[String: Any]]])
        #expect(Set(hooks.keys) == ["SessionStart", "SessionEnd", "BeforeAgent", "BeforeTool", "AfterTool", "Notification",
                                    "AfterAgent", "PreCompress"])
        let beforeTool = try #require(hooks["BeforeTool"])
        #expect((beforeTool[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String == "./guard.sh")
        let ours = try #require((beforeTool[1]["hooks"] as? [[String: Any]])?.first)
        #expect(ours["timeout"] as? Int == 10_000)
        #expect((ours["command"] as? String)?.hasSuffix("altillo-hook\" gemini BeforeTool") == true)
        let afterAgent = try #require((hooks["AfterAgent"]?.first?["hooks"] as? [[String: Any]])?.first)
        #expect(!(afterAgent["command"] as? String ?? "").contains("--reply-wait"))

        try Self.uninstall(sandbox, .gemini)
        #expect(try String(contentsOf: file, encoding: .utf8) == original)
    }

    @Test func geminiHooksSwitchedOffAreNoticed() throws {
        let sandbox = try Self.sandbox([".gemini"])
        try Data(#"{"hooksConfig":{"enabled":false}}"#.utf8).write(to: sandbox.environment.configFile(for: .gemini))
        #expect(!AgentHookInstaller(environment: sandbox.environment).report(for: .gemini).notes.isEmpty)
    }

    @Test func copilotGetsAFileOfItsOwnThatRemovalDeletes() throws {
        let sandbox = try Self.sandbox([".copilot"])
        let file = sandbox.environment.configFile(for: .copilot)
        #expect(file.path.hasSuffix(".copilot/hooks/altillo.json"))
        try Self.install(sandbox, .copilot, reply: true)
        let root = try Self.json(file)
        #expect(root["version"] as? Int == 1)
        let hooks = try #require(root["hooks"] as? [String: [[String: Any]]])
        #expect(hooks["preToolUse"] == nil) // fails closed on errors: never installed
        let permission = try #require(hooks["permissionRequest"]?.first)
        #expect(permission["type"] as? String == "command")
        #expect(permission["timeoutSec"] as? Int == 10)
        #expect(!(permission["bash"] as? String ?? "").contains("--timeout")) // never waits
        let stop = try #require(hooks["agentStop"]?.first)
        #expect((stop["bash"] as? String)?.hasSuffix("copilot agentStop --reply-wait 120") == true)
        #expect(stop["timeoutSec"] as? Int == 150)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        try Self.uninstall(sandbox, .copilot)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path)) // hooks/ was Altillo's
    }

    @Test func copilotsExistingHooksFolderStays() throws {
        let sandbox = try Self.sandbox([".copilot/hooks"])
        let mine = sandbox.environment.home.appending(path: ".copilot/hooks/mine.json")
        try Data(#"{"version":1,"hooks":{"sessionStart":[{"bash":"echo hi"}]}}"#.utf8).write(to: mine)
        try Self.install(sandbox, .copilot)
        try Self.uninstall(sandbox, .copilot)
        #expect(FileManager.default.fileExists(atPath: mine.path))
    }

    @Test func cursorFlatHooksLeaveTheUsersAlone() throws {
        let sandbox = try Self.sandbox([".cursor"])
        let file = sandbox.environment.configFile(for: .cursor)
        let original = """
        {
          "version": 1,
          "hooks": {
            "stop": [
              {
                "command": "./notify.sh"
              }
            ]
          }
        }

        """
        try Data(original.utf8).write(to: file)
        try Self.install(sandbox, .cursor)
        let hooks = try #require(try Self.json(file)["hooks"] as? [String: [[String: Any]]])
        let stop = try #require(hooks["stop"])
        #expect(stop.count == 2)
        #expect(stop[0]["command"] as? String == "./notify.sh")
        #expect(stop[1]["timeout"] as? Int == 10)
        #expect(Set(hooks.keys).isSuperset(of: ["sessionStart", "beforeSubmitPrompt", "preToolUse", "afterAgentResponse"]))
        // Installing again changes nothing.
        let installer = AgentHookInstaller(environment: sandbox.environment)
        #expect(try installer.planInstall(.cursor).changesNothing)
        try Self.uninstall(sandbox, .cursor)
        #expect(try String(contentsOf: file, encoding: .utf8) == original)
    }

    @Test func aFlatFileWithoutVersionComesBackByteForByte() throws {
        let sandbox = try Self.sandbox([".cursor"])
        let file = sandbox.environment.configFile(for: .cursor)
        let original = """
        {
          "hooks": {
            "stop": [
              {
                "command": "./notify.sh"
              }
            ]
          }
        }

        """
        try Data(original.utf8).write(to: file)
        try Self.install(sandbox, .cursor)
        #expect(try Self.json(file)["version"] as? Int == 1)
        try Self.uninstall(sandbox, .cursor)
        #expect(try String(contentsOf: file, encoding: .utf8) == original)
    }

    @Test func theReplyOptionOnlyTouchesTheStopHook() throws {
        let sandbox = try Self.sandbox([])
        try Self.install(sandbox, .claude)
        let withReply = AgentHookInstaller(environment: sandbox.environment, wait: 120, replyTargets: [.claude])
        #expect(withReply.status(for: .claude) == .needsRepair(.outdated))
        let plan = try withReply.planInstall(.claude)
        let removed = plan.diff.hunks.flatMap(\.lines).compactMap { if case .removed(let line) = $0 { line } else { nil } }
        let added = plan.diff.hunks.flatMap(\.lines).compactMap { if case .added(let line) = $0 { line } else { nil } }
        #expect(removed.count == 2 && added.count == 2) // the Stop command and its timeout
        #expect(added.contains { $0.contains("claude Stop --reply-wait 120") })
        #expect(added.contains { $0.contains("\"timeout\": 150") })
        try withReply.apply(plan)
        #expect(withReply.status(for: .claude) == .installed)
    }

    @MainActor
    @Test func repliesAreOnForNewClaudeAndCodexInstallsOnly() throws {
        let sandbox = try Self.sandbox([".gemini"])
        let suite = "altillo-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // An install from before this default: Claude's hooks are in, without the reply wait.
        try Self.install(sandbox, .claude)

        let model = AgentHooksModel(environment: sandbox.environment, defaults: defaults)
        model.refresh(wait: 120)
        #expect(!model.replyTargets.contains(.claude)) // left as it was, never silently upgraded
        #expect(model.reports.first { $0.target == .claude }?.status == .installed)
        #expect(defaults.object(forKey: AgentHooksModel.replyKey(.claude)) as? Bool == false)
        #expect(model.replyTargets.contains(.codex)) // a new install gets it
        #expect(!model.replyTargets.contains(.gemini))

        // The first Codex install includes the wait, and the review shows it.
        model.prepare(.install, for: .codex, wait: 120)
        let plan = try #require(model.review)
        #expect(plan.diff.text.contains("codex Stop --reply-wait 120"))
        model.confirm(plan, wait: 120)
        #expect(defaults.object(forKey: AgentHooksModel.replyKey(.codex)) as? Bool == true)
        #expect(model.reports.first { $0.target == .codex }?.status == .installed)

        // The switch still works for the older install.
        model.setReply(true, for: .claude, wait: 120)
        let upgrade = try #require(model.review)
        #expect(upgrade.diff.text.contains("claude Stop --reply-wait 120"))
        model.cancelReview(wait: 120)
        #expect(!model.replyTargets.contains(.claude))
    }

    @Test func everyTargetNamesItsStopEventLikeTheHook() {
        for target in AgentHookTarget.allCases {
            let agent = AgentKind(rawValue: target.rawValue)
            #expect(target.replyEvent == HookReplyOutput.stopEvent(for: agent), "\(target)")
            #expect(target.events.filter(\.repliable).map(\.name) == [target.replyEvent].compactMap { $0 }, "\(target)")
            #expect(target.events.contains { $0.waitsForDecision } == target.answersPermissions, "\(target)")
        }
    }
}

/// Live, opt-in (`TEST_RUNNER_ALTILLO_LIVE_OPENCODE=<data dir>` with `opencode serve` already running in an isolated
/// HOME whose config sets `"permission":{"bash":"ask"}`, and `TEST_RUNNER_ALTILLO_LIVE_OPENCODE_DIR` a project
/// folder): the real monitor finds the server by itself, follows its SSE stream, answers a permission and sends a
/// reply through its API.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["ALTILLO_LIVE_OPENCODE"] != nil))
struct OpenCodeLiveTests {
    @Test(.timeLimit(.minutes(3))) func permissionAndReplyThroughARealServer() async throws {
        let environment = ProcessInfo.processInfo.environment
        let data = URL(fileURLWithPath: try #require(environment["ALTILLO_LIVE_OPENCODE"]))
        let directory = try #require(environment["ALTILLO_LIVE_OPENCODE_DIR"])
        let hub = AgentHub(socketPath: AgentHubTests.socketPath(), fileRoots: nil, openCodeData: data)
        hub.start()
        defer { hub.stop() }
        let port = try #require(OpenCodeMonitor.servingProcesses().first?.port)
        try await Task.sleep(for: .seconds(1)) // the SSE stream connects

        // Start a turn the way any OpenCode client would.
        let base = "http://127.0.0.1:\(port)"
        let query = "?directory=" + directory.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        var create = URLRequest(url: URL(string: base + "/session" + query)!)
        create.httpMethod = "POST"
        create.setValue("application/json", forHTTPHeaderField: "Content-Type")
        create.httpBody = Data(#"{"title":"altillo live"}"#.utf8)
        let (created, _) = try await URLSession.shared.data(for: create)
        let sessionID = try #require(JSONValue.parse(created)?["id"]?.string)
        var prompt = URLRequest(url: URL(string: base + "/session/\(sessionID)/prompt_async" + query)!)
        prompt.httpMethod = "POST"
        prompt.setValue("application/json", forHTTPHeaderField: "Content-Type")
        prompt.httpBody = OpenCodeAPI.promptBody("Run the bash command `echo altillo-live` and then reply with only the word DONE.")
        _ = try await URLSession.shared.data(for: prompt)

        let id = "opencode:\(sessionID)"
        try await AgentHubTests().waitUntil(90) { hub.sessions.first { $0.id == id }?.pendingRequest != nil }
        let asking = try #require(hub.sessions.first { $0.id == id })
        #expect(asking.phase == .waitingPermission)
        #expect(asking.pendingRequest?.summary == "echo altillo-live")
        hub.decide(try #require(asking.pendingRequest?.id), .allow)
        try await AgentHubTests().waitUntil(90) { hub.sessions.first { $0.id == id }?.reply != nil }
        let done = try #require(hub.sessions.first { $0.id == id })
        #expect(done.phase == .waitingAnswer)
        print("OpenCode live: first answer:", done.lastMessage ?? "nil")

        #expect(hub.reply("Now reply with only the word BRAVO.", to: done))
        #expect(hub.sessions.first { $0.id == id }?.phase == .working)
        try await AgentHubTests().waitUntil(90) {
            let session = hub.sessions.first { $0.id == id }
            return session?.phase == .waitingAnswer && session?.lastMessage?.contains("BRAVO") == true
        }
        print("OpenCode live: reply answer:", hub.sessions.first { $0.id == id }?.lastMessage ?? "nil")
    }
}
