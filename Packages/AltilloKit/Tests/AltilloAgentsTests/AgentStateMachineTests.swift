import AltilloCore
import Foundation
import Testing
@testable import AltilloAgents

@Suite("State machine")
struct AgentStateMachineTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func run(_ agent: AgentKind, _ names: [String], start: AgentSession? = nil) throws -> AgentSession? {
        var session = start
        for (index, name) in names.enumerated() {
            session = AgentStateMachine.apply(try Fixtures.event(agent, name), to: session,
                                              at: t0.addingTimeInterval(Double(index)))
        }
        return session
    }

    @Test func claudeTurnFromTheRealCapture() throws {
        let started = try #require(try run(.claude, ["SessionStart"]))
        #expect(started.phase == .idle)
        #expect(started.project == "demo")
        #expect(started.source == .hooks)
        #expect(started.id == "claude:fc6f9b07-c1a0-497d-96c8-94c48f710cb1")

        let thinking = try #require(try run(.claude, ["UserPromptSubmit"], start: started))
        #expect(thinking.phase == .working)
        #expect(thinking.activity == "Thinking")

        let running = try #require(try run(.claude, ["PreToolUse-Bash-ls"], start: thinking))
        #expect(running.phase == .working)
        #expect(running.activity == "Running `ls`")

        let asked = try #require(try run(.claude, ["PermissionRequest"], start: running))
        #expect(asked.phase == .waitingPermission)
        #expect(asked.pendingRequest?.summary == "touch made-by-test.txt")
        #expect(asked.pendingRequest?.canAllowForSession == true)

        // A parallel tool's PreToolUse doesn't hide the request.
        let still = try #require(try run(.claude, ["PreToolUse-Bash-false"], start: asked))
        #expect(still.phase == .waitingPermission)

        let stopped = try #require(try run(.claude, ["Stop"], start: still))
        #expect(stopped.phase == .waitingAnswer)
        #expect(stopped.pendingRequest == nil)
        #expect(stopped.lastMessage?.hasPrefix("I found `notes.txt`") == true)
        #expect(stopped.activity == nil)

        let ended = try #require(try run(.claude, ["SessionEnd"], start: stopped))
        #expect(ended.phase == .finished)
    }

    @Test func activityLines() {
        func activity(_ name: String, _ input: String) -> String {
            ToolDescriptions.activity(for: AgentToolCall(name: name, input: JSONValue.parse(input)!), cwd: "/p")
        }
        #expect(activity("Bash", #"{"command":"swift test"}"#) == "Running `swift test`")
        #expect(activity("Edit", #"{"file_path":"/p/Apps/NotchModel.swift"}"#) == "Editing NotchModel.swift")
        #expect(activity("Write", #"{"file_path":"/p/a.md","content":"x"}"#) == "Writing a.md")
        #expect(activity("Read", #"{"file_path":"/p/b.swift"}"#) == "Reading b.swift")
        #expect(activity("Grep", #"{"pattern":"TODO"}"#) == "Searching for “TODO”")
        #expect(activity("WebFetch", #"{"url":"https://developer.apple.com/x"}"#) == "Reading developer.apple.com")
        #expect(activity("Agent", #"{"subagent_type":"Explore","prompt":"x"}"#) == "Running the Explore agent")
        #expect(activity("apply_patch", #"{"command":"*** Update File: a/B.swift\n*** Add File: c.txt\n"}"#)
            == "Editing 2 files")
        #expect(activity("mcp__github__create_issue", "{}") == "Using github · create_issue")
        #expect(activity("SomethingNew", "{}") == "Using SomethingNew")
        #expect(activity("Bash", #"{"command":"echo one\necho two"}"#) == "Running `echo one`")
    }

    @Test func askUserQuestionWaitsForTheUser() {
        let input = JSONValue.parse(#"{"questions":[{"question":"Which framework?","header":"FW","options":[]}]}"#)!
        let event = AgentEvent(agent: .claude, sessionID: "s", kind: .toolWillRun(AgentToolCall(name: "AskUserQuestion", input: input)),
                               name: "PreToolUse", cwd: "/p")
        let session = AgentStateMachine.apply(event, to: nil, at: t0)
        #expect(session.phase == .waitingAnswer)
        #expect(session.lastMessage == "Which framework?")
    }

    @Test func failureAndInterrupt() throws {
        let failed = try #require(try run(.claude, ["UserPromptSubmit", "StopFailure.docs"]))
        #expect(failed.phase == .failed)
        #expect(failed.lastMessage == "API Error: Rate limit reached")

        let interrupted = try #require(try run(.codex, ["UserPromptSubmit", "PreToolUse-Bash.docs", "Interrupt.docs"]))
        #expect(interrupted.phase == .idle)
    }

    @Test func notificationsWithoutARequest() throws {
        let prompt = try #require(try run(.claude, ["UserPromptSubmit", "Notification-permission_prompt.docs"]))
        #expect(prompt.phase == .waitingPermission)
        #expect(prompt.pendingRequest == nil)

        let idle = try #require(try run(.claude, ["Stop", "Notification-idle_prompt.docs"]))
        #expect(idle.phase == .waitingAnswer)
    }

    @Test func toolThatRanClearsItsRequest() throws {
        let asked = try #require(try run(.claude, ["UserPromptSubmit", "PermissionRequest"]))
        let call = AgentToolCall(name: "Bash", input: JSONValue.parse(#"{"command":"touch made-by-test.txt"}"#)!)
        let ran = AgentStateMachine.apply(
            AgentEvent(agent: .claude, sessionID: asked.sessionID, kind: .toolDidRun(call, failed: false), name: "PostToolUse"),
            to: asked, at: t0.addingTimeInterval(10))
        #expect(ran.pendingRequest == nil)
        #expect(ran.phase == .working)
    }

    @Test func resolvingAndExpiring() throws {
        let asked = try #require(try run(.claude, ["PermissionRequest"]))
        let id = try #require(asked.pendingRequest?.id)

        let expired = AgentStateMachine.expirePermission(id, in: asked, at: t0)
        #expect(expired.phase == .waitingPermission)
        #expect(expired.pendingRequest?.isExpired == true)
        #expect(!expired.isBlockedOnPermission)

        let resolved = AgentStateMachine.resolvePermission(id, in: asked, next: nil, decision: .allow, at: t0)
        #expect(resolved.phase == .working)
        #expect(resolved.pendingRequest == nil)

        // Another id is ignored.
        #expect(AgentStateMachine.resolvePermission("nope", in: asked, next: nil, decision: .allow, at: t0) == asked)
    }

    @Test func codexPermissionCard() throws {
        let asked = try #require(try run(.codex, ["PermissionRequest-Bash.docs"]))
        let request = try #require(asked.pendingRequest)
        #expect(request.summary == "git push --force origin main")
        #expect(request.isDangerous)
        #expect(request.detail?.hasPrefix("Force-pushes git history") == true)
        #expect(!request.canAllowForSession) // Codex has no session-scoped approval through hooks

        let patch = try #require(try run(.codex, ["PermissionRequest-apply_patch.docs"])?.pendingRequest)
        #expect(patch.toolName == "apply_patch")
        #expect(patch.summary == "Sources/App/NotchModel.swift")
        #expect(!patch.isDangerous)
        #expect(patch.detail?.contains("+let a = 2") == true)
    }

    @Test func claudeEditCard() throws {
        let request = try #require(try run(.claude, ["PermissionRequest-Edit.docs"])?.pendingRequest)
        #expect(request.summary == "Sources/NotchModel.swift")
        #expect(request.detail == "- let a = 1\n+ let a = 2")
        #expect(request.canAllowForSession) // acceptEdits for this session is echoable
    }

    @Test func sessionFileMergeHooksWin() throws {
        let hooked = try #require(try run(.claude, ["UserPromptSubmit", "PreToolUse-Bash-ls"]))
        let snapshot = SessionFileSnapshot(agent: .claude, sessionID: hooked.sessionID, cwd: "/Users/me/Projects/demo",
                                           phase: .waitingAnswer, lastMessage: "Old", lastActivity: hooked.lastActivity)
        let merged = AgentStateMachine.apply(snapshot, to: hooked)
        #expect(merged.phase == .working)
        #expect(merged.source == .hooks)

        // The file far ahead of the hooks (hooks removed mid-session): the file's view wins.
        var later = snapshot
        later.lastActivity = hooked.lastActivity.addingTimeInterval(300)
        let taken = AgentStateMachine.apply(later, to: hooked)
        #expect(taken.phase == .waitingAnswer)
        #expect(taken.lastMessage == "Old")

        // A new session from the file alone.
        let fresh = AgentStateMachine.apply(later, to: nil)
        #expect(fresh.source == .sessionFile)
        #expect(fresh.project == "demo")
    }

    @Test func agingGoesIdleThenDrops() throws {
        let working = try #require(try run(.claude, ["UserPromptSubmit"]))
        #expect(AgentSessionAging.nextDeadline(working) == working.lastActivity.addingTimeInterval(600))
        #expect(AgentSessionAging.age(working, now: working.lastActivity.addingTimeInterval(599), processAlive: true) == working)

        let idle = try #require(AgentSessionAging.age(working, now: working.lastActivity.addingTimeInterval(600), processAlive: nil))
        #expect(idle.phase == .idle)
        #expect(AgentSessionAging.nextDeadline(idle) == working.lastActivity.addingTimeInterval(1800))
        #expect(AgentSessionAging.age(idle, now: working.lastActivity.addingTimeInterval(1800), processAlive: nil) == nil)

        let dead = try #require(AgentSessionAging.age(working, now: working.lastActivity.addingTimeInterval(5), processAlive: false))
        #expect(dead.phase == .finished)
    }

    @Test func agingLeavesALiveRequestAloneUntilItExpires() throws {
        var asked = try #require(try run(.claude, ["PermissionRequest"]))
        asked.pendingRequest?.expiresAt = asked.lastActivity.addingTimeInterval(120)
        #expect(AgentSessionAging.nextDeadline(asked) == asked.lastActivity.addingTimeInterval(120))
        let later = try #require(AgentSessionAging.age(asked, now: asked.lastActivity.addingTimeInterval(121), processAlive: nil))
        #expect(later.pendingRequest?.isExpired == true)
        #expect(later.phase == .waitingPermission)
        let stale = try #require(AgentSessionAging.age(later, now: asked.lastActivity.addingTimeInterval(601), processAlive: nil))
        #expect(stale.phase == .idle)
    }

    @Test func ordering() {
        func session(_ id: String, _ phase: AgentPhase, _ seconds: Double) -> AgentSession {
            AgentSession(agent: .claude, sessionID: id, cwd: "/p", phase: phase, startedAt: t0,
                         lastActivity: t0.addingTimeInterval(seconds), source: .hooks)
        }
        let sorted = AgentSessionOrder.sorted([
            session("a", .finished, 50), session("b", .working, 10), session("c", .waitingAnswer, 1),
            session("d", .working, 20), session("e", .waitingPermission, 0), session("f", .idle, 99),
        ])
        #expect(sorted.map(\.sessionID) == ["e", "c", "d", "b", "f", "a"])
    }
}
