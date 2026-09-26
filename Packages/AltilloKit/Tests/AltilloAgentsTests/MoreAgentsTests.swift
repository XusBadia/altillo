import AltilloCore
import Darwin
import Foundation
import Testing
@testable import AltilloAgents

// Phase 14. Fixtures: `gemini/*.docs.json` follow Gemini CLI 0.61.0's bundled hooks reference, `copilot/*.docs.json`
// the docs.github.com hooks reference for Copilot CLI 1.0.88 (camelCase events; `_event` is the event the hook is
// installed for), `cursor/*.source.json` the payload builder in Cursor CLI 2026.09.23's bundled source. None of those
// CLIs is installed here, so none is a live capture. `claude/Stop-*.json` and `opencode/global-event.sse.txt` ARE
// live captures (Claude Code 2.1.281 `claude -p` with a temporary settings file; OpenCode 1.18.32 `opencode serve` in
// an isolated HOME), anonymized.

@Suite("More agents: hook payloads")
struct MoreAgentsParsingTests {
    static func event(_ agent: AgentKind, _ name: String) throws -> AgentEvent {
        let payload = try Fixtures.payload(agent.rawValue, name)
        return try #require(HookPayloadParser.parse(agent: agent, eventName: payload["_event"]?.string, payload: payload))
    }

    @Test func everyFixtureParsesWithSessionAndCWD() throws {
        for agent in ["gemini", "copilot", "cursor"] {
            for name in try Fixtures.all(agent) {
                let event = try Self.event(AgentKind(rawValue: agent), name)
                #expect(!event.sessionID.isEmpty, "\(agent)/\(name)")
                #expect(event.cwd == "/Users/me/Projects/demo", "\(agent)/\(name)")
                if case .other = event.kind { Issue.record("\(agent)/\(name) parsed as .other") }
            }
        }
    }

    @Test func gemini() throws {
        #expect(try Self.event(.gemini, "BeforeAgent.docs").kind == .promptSubmitted(prompt: "Add a --verbose flag to the CLI"))
        guard case .toolWillRun(let call) = try Self.event(.gemini, "BeforeTool-run_shell_command.docs").kind else {
            Issue.record("BeforeTool"); return
        }
        #expect(call.command == "npm test")
        #expect(ToolDescriptions.activity(for: call, cwd: nil) == "Running `npm test`")
        guard case .toolDidRun(let edit, false) = try Self.event(.gemini, "AfterTool-replace.docs").kind else {
            Issue.record("AfterTool"); return
        }
        #expect(ToolDescriptions.activity(for: edit, cwd: nil) == "Editing cli.ts")
        guard case .notification(let type, _, _) = try Self.event(.gemini, "Notification-ToolPermission.docs").kind else {
            Issue.record("Notification"); return
        }
        #expect(type == "permission_prompt")
        #expect(try Self.event(.gemini, "AfterAgent.docs").kind
            == .turnFinished(lastMessage: "Done: `--verbose` now prints each step. Want me to add a test?"))
        #expect(try Self.event(.gemini, "PreCompress.docs").kind == .compacting(done: false))
    }

    @Test func copilot() throws {
        // permissionRequest fires for every tool call before Copilot's own rules: activity, never a request.
        guard case .toolWillRun(let call) = try Self.event(.copilot, "permissionRequest-bash.docs").kind else {
            Issue.record("permissionRequest"); return
        }
        #expect(call.command == "npm test -- --runInBand")
        // `toolArgs` as a JSON string.
        guard case .toolDidRun(let edit, _) = try Self.event(.copilot, "postToolUse-edit.docs").kind else {
            Issue.record("postToolUse"); return
        }
        #expect(edit.filePaths == ["/Users/me/Projects/demo/test/app.test.ts"])
        #expect(try Self.event(.copilot, "userPromptSubmitted.docs").kind == .promptSubmitted(prompt: "Fix the flaky test"))
        #expect(try Self.event(.copilot, "agentStop.docs").kind == .turnFinished(lastMessage: nil))
        #expect(try Self.event(.copilot, "errorOccurred.docs").kind
            == .turnFailed(error: "RateLimitError", message: "Rate limit exceeded"))
        #expect(try Self.event(.copilot, "notification-agent_idle.docs").kind
            == .notification(type: "idle_prompt", message: "Copilot is waiting for your input", title: nil))
        #expect(try Self.event(.copilot, "subagentStop.docs").kind
            == .subagentFinished(type: "explore", lastMessage: "Found 3 callers"))
    }

    @Test func cursor() throws {
        guard case .toolWillRun(let call) = try Self.event(.cursor, "preToolUse-Shell.source").kind else {
            Issue.record("preToolUse"); return
        }
        #expect(call.command == "pnpm lint")
        #expect(try Self.event(.cursor, "stop-completed.source").kind == .turnFinished(lastMessage: nil))
        #expect(try Self.event(.cursor, "stop-aborted.source").kind == .interrupted)
        #expect(try Self.event(.cursor, "afterAgentResponse.source").kind
            == .assistantMessage("Renamed it to loadConfig and updated 4 imports. Should I run the tests?"))
    }

    @Test func cursorRunningClaudesHooksIsCursor() throws {
        let payload = try Fixtures.payload("cursor", "stop-completed.source")
        #expect(HookRunner.effectiveAgent(installedFor: "claude", payload: payload) == "cursor")
        #expect(HookRunner.effectiveAgent(installedFor: "claude", payload: try Fixtures.payload("claude", "Stop")) == "claude")
    }

    @Test func onlyClaudeAndCodexPermissionHooksWait() {
        #expect(HookRunner.waitsForDecision(event: "PermissionRequest", agent: "claude"))
        #expect(HookRunner.waitsForDecision(event: "PermissionRequest", agent: "codex"))
        #expect(!HookRunner.waitsForDecision(event: "permissionRequest", agent: "copilot"))
        #expect(!HookRunner.waitsForDecision(event: "Notification", agent: "gemini"))
    }

    @Test func assistantMessagesKeepThePhase() {
        let now = Date()
        var session = AgentSession(agent: .cursor, sessionID: "s", cwd: "/p", phase: .working, startedAt: now,
                                   lastActivity: now, source: .hooks)
        session = AgentStateMachine.apply(AgentEvent(agent: .cursor, sessionID: "s", kind: .assistantMessage("Hi"),
                                                     name: "afterAgentResponse"), to: session, at: now)
        #expect(session.phase == .working)
        #expect(session.lastMessage == "Hi")
    }
}

@Suite("Reply from the notch: the hook", .serialized)
struct ReplyHookTests {
    typealias FakeApp = WireProtocolTests.FakeApp

    /// A Claude TUI in a terminal: tty in the chain, and the agent's argv.
    static let terminal: [ProcessTree.Entry] = [.init(pid: 500, parent: 400, name: "claude", tty: "/dev/ttys009"),
                                                .init(pid: 400, parent: 1, name: "zsh", tty: "/dev/ttys009")]

    static func run(_ app: FakeApp, _ arguments: [String], payload: JSONValue, argv: [String] = ["claude"],
                    environment: [String: String] = [:]) -> Data? {
        HookRunner.run(arguments: arguments,
                       environment: environment.merging(["ALTILLO_AGENTS_SOCKET": app.path]) { a, _ in a },
                       readStdin: { payload.data }, ancestors: { terminal }, agentArguments: { _ in argv },
                       stdinIsTerminal: { _ in true })
    }

    @Test func claudeReplyBlocksTheStopWithTheUsersWords() throws {
        let app = try FakeApp(decision: nil, reply: "Also add a test")
        defer { app.stop() }
        let output = try #require(Self.run(app, ["claude", "Stop", "--reply-wait", "30"],
                                           payload: try Fixtures.payload("claude", "Stop-first"),
                                           environment: ["CLAUDE_CODE_ENTRYPOINT": "cli"]))
        let json = try #require(JSONValue.parse(output))
        #expect(json["decision"]?.string == "block")
        #expect(json["reason"]?.string == "The user replied from Altillo (their notch):\n\nAlso add a test")
        let envelope = try #require(app.envelopes.first)
        #expect(envelope.waitsForReply && !envelope.waitsForDecision)
        #expect(envelope.timeout == 30)
    }

    @Test func eachAgentsReplySchema() throws {
        func json(_ agent: AgentKind) throws -> JSONValue {
            let output = try #require(HookReplyOutput.output(agent: agent, text: " Yes "))
            return try #require(JSONValue.parse(output))
        }
        for agent in [AgentKind.claude, .codex, .copilot] {
            #expect(try json(agent)["decision"]?.string == "block")
            #expect(try json(agent)["reason"]?.string?.hasSuffix("\n\nYes") == true)
        }
        #expect(try json(.gemini)["decision"]?.string == "deny")
        #expect(try json(.cursor)["followup_message"]?.string?.hasSuffix("Yes") == true)
        #expect(HookReplyOutput.output(agent: .claude, text: "  ") == nil)
        #expect(HookReplyOutput.output(agent: .opencode, text: "Yes") == nil)
        #expect(HookReplyOutput.stopEvent(for: .gemini) == "AfterAgent")
        #expect(HookReplyOutput.isStopEvent("agentStop", agent: .copilot))
        #expect(HookReplyOutput.isStopEvent("stop", agent: .cursor))
        #expect(!HookReplyOutput.isStopEvent("Stop", agent: .gemini))
    }

    @Test func noReplyPrintsNothing() throws {
        let app = try FakeApp(decision: WireDecision.none)
        defer { app.stop() }
        #expect(Self.run(app, ["codex", "Stop", "--reply-wait", "30"], payload: try Fixtures.payload("codex", "Stop.docs"),
                         argv: ["codex"]) == nil)
        #expect(app.envelopes.first?.waitsForReply == true)
    }

    @Test func aPermissionAnswerNeverCountsAsAReply() throws {
        let app = try FakeApp(decision: .allow)
        defer { app.stop() }
        #expect(Self.run(app, ["claude", "Stop", "--reply-wait", "30"], payload: try Fixtures.payload("claude", "Stop")) == nil)
    }

    @Test func timeoutStopsAsUsualOnTime() throws {
        let app = try FakeApp(decision: nil) // never answers
        defer { app.stop() }
        let start = Date()
        #expect(Self.run(app, ["claude", "Stop", "--reply-wait", "1"], payload: try Fixtures.payload("claude", "Stop")) == nil)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed >= 0.9 && elapsed < 3)
    }

    @Test func withoutTheOptionTheStopNeverWaits() throws {
        let app = try FakeApp(decision: nil)
        defer { app.stop() }
        let start = Date()
        #expect(Self.run(app, ["claude", "Stop"], payload: try Fixtures.payload("claude", "Stop")) == nil)
        #expect(Date().timeIntervalSince(start) < 0.8)
        try waitUntil { !app.envelopes.isEmpty }
        #expect(app.envelopes.first?.waitsForReply == false)
    }

    @Test func headlessRunsNeverWait() throws {
        let app = try FakeApp(decision: nil)
        defer { app.stop() }
        let start = Date()
        // `claude -p`, `codex exec`, `gemini -p`, `copilot -p`, `cursor-agent --print`.
        #expect(Self.run(app, ["claude", "Stop", "--reply-wait", "5"], payload: try Fixtures.payload("claude", "Stop"),
                         environment: ["CLAUDE_CODE_ENTRYPOINT": "sdk-cli"]) == nil)
        #expect(Self.run(app, ["codex", "Stop", "--reply-wait", "5"], payload: try Fixtures.payload("codex", "Stop.docs"),
                         argv: ["codex", "exec", "fix it"]) == nil)
        #expect(Self.run(app, ["gemini", "AfterAgent", "--reply-wait", "5"],
                         payload: try Fixtures.payload("gemini", "AfterAgent.docs"),
                         argv: ["node", "/opt/homebrew/bin/gemini", "-p", "hi"]) == nil)
        #expect(Self.run(app, ["copilot", "agentStop", "--reply-wait", "5"],
                         payload: try Fixtures.payload("copilot", "agentStop.docs"), argv: ["copilot", "-p", "hi"]) == nil)
        #expect(Self.run(app, ["cursor", "stop", "--reply-wait", "5"],
                         payload: try Fixtures.payload("cursor", "stop-completed.source"),
                         argv: ["cursor-agent", "--print", "hi"]) == nil)
        #expect(Date().timeIntervalSince(start) < 2)
        try waitUntil { app.envelopes.count == 5 }
        #expect(app.envelopes.allSatisfy { !$0.waitsForReply })
    }

    @Test func cursorThroughClaudesHooksIsObserveOnly() throws {
        let app = try FakeApp(decision: .allow, reply: "hi")
        defer { app.stop() }
        #expect(Self.run(app, ["claude", "Stop", "--reply-wait", "5"],
                         payload: try Fixtures.payload("cursor", "stop-completed.source"), argv: ["cursor-agent"]) == nil)
        try waitUntil { !app.envelopes.isEmpty }
        #expect(app.envelopes.first?.agent == "cursor")
        #expect(app.envelopes.first?.waitsForReply == false)
    }

    @Test func copilotsPermissionHookNeverWaits() throws {
        let app = try FakeApp(decision: .allow)
        defer { app.stop() }
        #expect(Self.run(app, ["copilot", "permissionRequest", "--timeout", "5"],
                         payload: try Fixtures.payload("copilot", "permissionRequest-bash.docs"), argv: ["copilot"]) == nil)
        try waitUntil { !app.envelopes.isEmpty }
        #expect(app.envelopes.first?.waitsForDecision == false)
    }

    @Test func noAltilloMeansNoOutputAtOnce() throws {
        let start = Date()
        let output = HookRunner.run(arguments: ["claude", "Stop", "--reply-wait", "120"],
                                    environment: ["ALTILLO_AGENTS_SOCKET": "/tmp/altillo-none-\(UUID().uuidString).sock"],
                                    readStdin: { try! Fixtures.payload("claude", "Stop").data },
                                    ancestors: { Self.terminal }, agentArguments: { _ in ["claude"] },
                                    stdinIsTerminal: { _ in true })
        #expect(output == nil)
        #expect(Date().timeIntervalSince(start) < 0.5)
    }

    @Test func copilotRunningClaudesHooksNeverWaits() throws {
        let app = try FakeApp(decision: nil, reply: "hi")
        defer { app.stop() }
        let copilot: [ProcessTree.Entry] = [.init(pid: 700, parent: 600, name: "copilot", tty: "/dev/ttys009"),
                                            .init(pid: 600, parent: 1, name: "zsh", tty: "/dev/ttys009")]
        let start = Date()
        let output = HookRunner.run(arguments: ["claude", "Stop", "--reply-wait", "5"],
                                    environment: ["ALTILLO_AGENTS_SOCKET": app.path],
                                    readStdin: { try! Fixtures.payload("claude", "Stop").data },
                                    ancestors: { copilot }, agentArguments: { _ in ["copilot"] },
                                    stdinIsTerminal: { _ in true })
        #expect(output == nil)
        #expect(Date().timeIntervalSince(start) < 1)
        try waitUntil { !app.envelopes.isEmpty }
        let envelope = try #require(app.envelopes.first)
        #expect(envelope.agent == "copilot" && envelope.rerouted && !envelope.waitsForReply)
    }

    @Test func cursorsLoopLimitStopsTheWait() throws {
        let app = try FakeApp(decision: nil, reply: "go on")
        defer { app.stop() }
        guard case .object(var payload) = try Fixtures.payload("cursor", "stop-completed.source") else { return }
        payload["loop_count"] = .number(Double(HookRunner.cursorLoopLimit))
        #expect(Self.run(app, ["cursor", "stop", "--reply-wait", "5"], payload: .object(payload),
                         argv: ["cursor-agent"]) == nil)
        try waitUntil { !app.envelopes.isEmpty }
        #expect(app.envelopes.first?.waitsForReply == false)
        payload["loop_count"] = .number(1)
        let output = try #require(Self.run(app, ["cursor", "stop", "--reply-wait", "5"], payload: .object(payload),
                                           argv: ["cursor-agent"]))
        #expect(JSONValue.parse(output)?["followup_message"]?.string?.hasSuffix("go on") == true)
    }

    @Test func invocationReadsTheReplyWait() {
        let invocation = HookRunner.invocation(arguments: ["gemini", "AfterAgent", "--reply-wait=60"], environment: [:])
        #expect(invocation?.replyWait == 60)
        #expect(HookRunner.invocation(arguments: ["claude", "Stop"], environment: [:])?.replyWait == nil)
        #expect(HookRunner.invocation(arguments: ["claude", "Stop", "--reply-wait", "0"], environment: [:])?.replyWait == nil)
    }

    @Test func interactiveSessions() {
        let tty = Self.terminal
        let noTTY: [ProcessTree.Entry] = [.init(pid: 5, parent: 1, name: "Cursor Helper", tty: nil)]
        func interactive(_ argv: [String]?, chain: [ProcessTree.Entry] = tty, env: [String: String] = [:],
                         agent: String = "x", stdin: Bool = true) -> Bool {
            ProcessTree.isInteractiveSession(agent: agent, chain: chain, agentArguments: argv, environment: env,
                                             stdinIsTerminal: { _ in stdin })
        }
        #expect(interactive(["claude"]))
        #expect(interactive(["claude", "--resume", "abc"]))
        #expect(interactive(["node", "/opt/homebrew/bin/gemini"]))
        #expect(!interactive(["claude", "-p", "hi"]))
        #expect(!interactive(["codex", "exec", "hi"]))
        #expect(!interactive(["codex", "-m", "o3", "exec", "hi"]))
        #expect(!interactive(["copilot", "--prompt=hi"]))
        #expect(!interactive(["claude"], env: ["CLAUDE_CODE_ENTRYPOINT": "sdk-ts"]))
        #expect(!interactive(["cursor-agent"], chain: noTTY))
        #expect(!interactive(nil))
        // The agent itself needs the terminal, stdin included (piped runs and apps are out).
        #expect(!interactive(["claude"], stdin: false))
        let shellOnlyTTY: [ProcessTree.Entry] = [.init(pid: 500, parent: 400, name: "claude", tty: nil),
                                                 .init(pid: 400, parent: 1, name: "zsh", tty: "/dev/ttys009")]
        #expect(!interactive(["claude"], chain: shellOnlyTTY))
        // Gemini: a positional prompt is a one-shot run unless -i/--prompt-interactive keeps it open.
        let node = ["node", "/opt/homebrew/bin/gemini"]
        #expect(interactive(node, agent: "gemini"))
        #expect(interactive(node + ["-m", "gemini-3-pro"], agent: "gemini"))
        #expect(interactive(node + ["--resume", "latest"], agent: "gemini"))
        #expect(!interactive(node + ["fix the flaky test"], agent: "gemini"))
        #expect(!interactive(node + ["-m", "gemini-3-pro", "explain this"], agent: "gemini"))
        #expect(interactive(node + ["-i", "fix the flaky test"], agent: "gemini"))
        #expect(interactive(node + ["--prompt-interactive=fix it"], agent: "gemini"))
    }

    @Test func readsThisProcesssArguments() throws {
        let arguments = try #require(ProcessTree.arguments(of: getpid()))
        #expect(arguments == CommandLine.arguments)
        #expect(ProcessTree.arguments(of: -1) == nil)
    }

    func waitUntil(_ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            guard Date() < deadline else { Issue.record("condition not met"); return }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}

@Suite("Reply channels age")
struct ReplyAgingTests {
    @Test func aStopHooksReplyChannelClosesAtItsDeadline() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var session = AgentSession(agent: .claude, sessionID: "s", cwd: "/p", phase: .waitingAnswer, startedAt: start,
                                   lastActivity: start, source: .hooks)
        session.reply = AgentReplyChannel(kind: .stopHook, id: "r", openedAt: start, expiresAt: start.addingTimeInterval(120))
        #expect(AgentSessionAging.nextDeadline(session) == start.addingTimeInterval(120))
        #expect(AgentSessionAging.age(session, now: start.addingTimeInterval(60), processAlive: nil)?.reply != nil)
        let aged = AgentSessionAging.age(session, now: start.addingTimeInterval(121), processAlive: nil)
        #expect(aged?.reply == nil)
        #expect(aged?.phase == .waitingAnswer)
    }

    @Test func aServerChannelHasNoDeadlineButEndsWithTheSession() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var session = AgentSession(agent: .opencode, sessionID: "s", cwd: "/p", phase: .waitingAnswer, startedAt: start,
                                   lastActivity: start, source: .server)
        session.reply = AgentReplyChannel(kind: .server, id: "s", openedAt: start)
        #expect(AgentSessionAging.age(session, now: start.addingTimeInterval(60), processAlive: nil)?.reply != nil)
        session.phase = .finished
        #expect(AgentSessionAging.age(session, now: start.addingTimeInterval(60), processAlive: nil)?.reply == nil)
    }
}

@Suite("OpenCode")
struct OpenCodeTests {
    static func capture() throws -> [(event: OpenCodeEvent, directory: String?)] {
        let url = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appendingPathComponent("opencode/global-event.sse.txt")
        var parser = SSEParser()
        let data = try Data(contentsOf: url)
        // Fed in uneven chunks, as the network would.
        var events: [String] = []
        var index = 0
        while index < data.count {
            let end = min(index + 97, data.count)
            events += parser.feed(data.subdata(in: index..<end))
            index = end
        }
        return events.compactMap(OpenCodeEvent.parse)
    }

    @Test func theLiveCaptureTellsTheWholeStory() throws {
        let events = try Self.capture()
        let session = "ses_f274e86caffeGx7mnyxSXOOwyQ"
        #expect(events.first?.event == .connected)
        #expect(events.contains { $0.event == .status(sessionID: session, status: "busy") })
        let asked = events.compactMap { if case .permissionAsked(let p) = $0.event { p } else { nil } }
        let permission = try #require(asked.first)
        #expect(permission.sessionID == session)
        #expect(permission.permission == "bash")
        #expect(permission.always == ["echo *"])
        #expect(permission.toolCall.command == "echo p14-perm")
        #expect(events.contains { $0.event == .permissionReplied(sessionID: session, requestID: permission.id) })
        #expect(events.contains { $0.event == .idle(sessionID: session) })
        #expect(events.contains { if case .tool(session, let call, "running") = $0.event { call.command == "echo p14-perm" } else { false } })
        #expect(events.contains { if case .text(session, _, "BRAVO") = $0.event { true } else { false } })
        #expect(events.contains { $0.directory == "/Users/me/Projects/demo" })
        let sessions = events.compactMap { if case .session(let id, let dir, _, _, _) = $0.event { (id, dir) } else { nil } }
        #expect(sessions.contains { $0.0 == session && $0.1 == "/Users/me/Projects/demo" })
    }

    @Test func sseFraming() {
        var parser = SSEParser()
        #expect(parser.feed(Data("data: {\"a\":1}\r\n".utf8)).isEmpty)
        #expect(parser.feed(Data("\r\n: comment\n\nevent: x\ndata: one\ndata: two\n\n".utf8)) == ["{\"a\":1}", "one\ntwo"])
    }

    @Test func bareEventsAndGarbage() {
        let bare = #"{"type":"session.status","properties":{"sessionID":"s","status":{"type":"idle"}}}"#
        #expect(OpenCodeEvent.parse(bare)?.event == .status(sessionID: "s", status: "idle"))
        #expect(OpenCodeEvent.parse("not json") == nil)
        #expect(OpenCodeEvent.parse(#"{"type":"session.status","properties":{}}"#) == nil)
        #expect(OpenCodeEvent.parse(#"{"type":"future.thing","properties":{}}"#)?.event == .other("future.thing"))
    }

    @Test func serversFromTheirArguments() {
        #expect(OpenCodeAPI.serverPort(arguments: ["/x/opencode", "serve"]) == (true, nil))
        #expect(OpenCodeAPI.serverPort(arguments: ["/x/opencode", "serve", "--port", "47123"]) == (true, 47123))
        #expect(OpenCodeAPI.serverPort(arguments: ["opencode", "web", "--port=0"]) == (true, nil))
        #expect(OpenCodeAPI.serverPort(arguments: ["opencode", "--port", "5000"]) == (true, 5000))
        #expect(OpenCodeAPI.serverPort(arguments: ["opencode"]).serves == false) // the plain TUI listens on nothing
        #expect(OpenCodeAPI.serverPort(arguments: ["opencode", "run", "hi"]).serves == false)
        #expect(OpenCodeAPI.serverPort(arguments: ["node", "serve"]).serves == false)
    }

    @Test func stateReaders() {
        let permissions = OpenCodeAPI.permissions(from: Data(#"[{"id":"per_1","sessionID":"ses_1","permission":"bash","patterns":["ls"],"metadata":{"command":"ls"},"always":[]}]"#.utf8))
        #expect(permissions?.map(\.id) == ["per_1"])
        #expect(OpenCodeAPI.permissions(from: Data("[]".utf8))?.isEmpty == true)
        #expect(OpenCodeAPI.permissions(from: Data("{}".utf8)) == nil)
        #expect(OpenCodeAPI.statuses(from: Data(#"{"ses_1":{"type":"busy"},"ses_2":{"type":"retry","attempt":2}}"#.utf8))
            == ["ses_1": "busy", "ses_2": "retry"])
        #expect(OpenCodeAPI.statusPath(directory: "/p") == "/session/status?directory=/p")
        #expect(OpenCodeAPI.pendingPermissionsPath(directory: nil) == "/permission")
    }

    @Test func requestBodiesAndPaths() throws {
        #expect(String(decoding: OpenCodeAPI.permissionReplyBody(.allow), as: UTF8.self) == #"{"reply":"once"}"#)
        #expect(String(decoding: OpenCodeAPI.permissionReplyBody(.allowForSession), as: UTF8.self) == #"{"reply":"always"}"#)
        #expect(String(decoding: OpenCodeAPI.permissionReplyBody(.deny), as: UTF8.self) == #"{"reply":"reject"}"#)
        let prompt = try #require(JSONValue.parse(OpenCodeAPI.promptBody("Yes")))
        #expect(prompt.value(at: "parts")?[0]?["text"]?.string == "Yes")
        #expect(OpenCodeAPI.permissionReplyPath(requestID: "per_1", directory: "/Users/me/My Project")
            == "/permission/per_1/reply?directory=/Users/me/My%20Project")
        #expect(OpenCodeAPI.promptPath(sessionID: "ses_1", directory: nil) == "/session/ses_1/prompt_async")
    }
}

@Suite("Gemini chat files")
struct GeminiChatTests {
    static func lines(_ records: [String]) -> [Data] { records.map { Data($0.utf8) } }
    static let meta = GeminiChat.Meta(sessionID: "3f1c", startedAt: nil, isSubagent: false)

    func snapshot(_ records: [String]) -> SessionFileSnapshot? {
        GeminiChat.snapshot(tail: Self.lines(records), meta: Self.meta, cwd: "/Users/me/Projects/demo", projectID: "demo",
                            modified: Date(timeIntervalSince1970: 2_000_000_000))
    }

    @Test func phasesFromTheLastMessage() {
        let user = #"{"id":"1","timestamp":"2026-09-25T13:00:00.000Z","type":"user","content":[{"text":"Add a flag"}]}"#
        #expect(snapshot([user])?.phase == .working)
        let running = #"{"id":"2","timestamp":"2026-09-25T13:00:02.000Z","type":"gemini","content":"","toolCalls":[{"name":"run_shell_command","args":{"command":"npm test"},"status":"executing"}]}"#
        #expect(snapshot([user, running])?.activity == "Running `npm test`")
        let asking = running.replacingOccurrences(of: "executing", with: "awaiting_approval")
        #expect(snapshot([user, asking])?.phase == .waitingPermission)
        let done = #"{"id":"2","timestamp":"2026-09-25T13:00:09.000Z","type":"gemini","content":"All set. Anything else?","toolCalls":[{"name":"run_shell_command","args":{"command":"npm test"},"status":"success"}]}"#
        // The message re-appended with its final state wins over its earlier copy.
        let final = snapshot([user, running, #"{"$set":{"lastUpdated":"2026-09-25T13:00:09.000Z"}}"#, done])
        #expect(final?.phase == .waitingAnswer)
        #expect(final?.lastMessage == "All set. Anything else?")
        #expect(final?.cwd == "/Users/me/Projects/demo")
        #expect(final?.agent == .gemini)
        #expect(snapshot([#"{"id":"3","type":"error","content":"Quota exceeded"}"#])?.phase == .failed)
        #expect(snapshot([#"{"id":"4","type":"user","content":"/stats"}"#])?.phase == .idle)
    }

    @Test func metadataAndProjects() throws {
        let meta = try #require(GeminiChat.meta(firstLine: Data(#"{"sessionId":"abc","projectHash":"h","startTime":"2026-09-25T13:00:00.000Z","kind":"main"}"#.utf8)))
        #expect(meta.sessionID == "abc" && !meta.isSubagent && meta.startedAt != nil)
        #expect(GeminiChat.meta(firstLine: Data(#"{"sessionId":"x","kind":"subagent"}"#.utf8))?.isSubagent == true)
        #expect(GeminiChat.projectPaths(registry: Data(#"{"projects":{"/Users/me/Projects/demo":"demo"}}"#.utf8))
            == ["demo": "/Users/me/Projects/demo"])
        let url = URL(fileURLWithPath: "/Users/me/.gemini/tmp/demo/chats/session-2026-09-25T13-01-3f1c.jsonl")
        #expect(GeminiChat.isChatFile(url))
        #expect(GeminiChat.projectID(for: url) == "demo")
        #expect(!GeminiChat.isChatFile(URL(fileURLWithPath: "/Users/me/.gemini/tmp/demo/logs/session-x.jsonl")))
    }
}
