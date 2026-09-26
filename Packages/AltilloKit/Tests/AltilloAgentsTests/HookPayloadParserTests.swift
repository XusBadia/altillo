import AltilloCore
import Foundation
import Testing
@testable import AltilloAgents

/// Fixtures: `Fixtures/<agent>/<Event>.json` were captured from real runs (Claude Code 2.1.281 `claude -p` and
/// Codex 0.152.0 `codex exec`, September 2026) with temporary hook settings; `*.docs.json` follow the documented
/// schema for events a headless run can't trigger. Paths are anonymized.
enum Fixtures {
    static func resource(_ folder: String, _ name: String) throws -> JSONValue {
        let url = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appendingPathComponent(folder).appendingPathComponent(name + ".json")
        return try #require(JSONValue.parse(try Data(contentsOf: url)))
    }

    static func payload(_ agent: String, _ name: String) throws -> JSONValue {
        try resource(agent, name)
    }

    static func event(_ agent: AgentKind, _ name: String) throws -> AgentEvent {
        try #require(HookPayloadParser.parse(agent: agent, eventName: nil, payload: payload(agent.rawValue, name)))
    }

    static func all(_ agent: String) throws -> [String] {
        let folder = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appendingPathComponent(agent)
        return try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }
}

@Suite("Hook payload parsing")
struct HookPayloadParserTests {
    @Test func everyFixtureParsesWithSessionAndCWD() throws {
        for agent in ["claude", "codex"] {
            for name in try Fixtures.all(agent) {
                let event = try Fixtures.event(AgentKind(rawValue: agent), name)
                #expect(!event.sessionID.isEmpty, "\(agent)/\(name)")
                #expect(event.cwd == "/Users/me/Projects/demo", "\(agent)/\(name)")
                if case .other = event.kind { Issue.record("\(agent)/\(name) parsed as .other") }
            }
        }
    }

    @Test func claudeSessionLifecycle() throws {
        let start = try Fixtures.event(.claude, "SessionStart")
        #expect(start.kind == .sessionStarted(source: "startup"))
        #expect(start.transcriptPath?.hasSuffix("\(start.sessionID).jsonl") == true)

        let prompt = try Fixtures.event(.claude, "UserPromptSubmit")
        guard case .promptSubmitted(let text) = prompt.kind else { Issue.record("not a prompt"); return }
        #expect(text?.hasPrefix("First run") == true)
        #expect(prompt.permissionMode == "default")

        #expect(try Fixtures.event(.claude, "SessionEnd").kind == .sessionEnded(reason: "other"))
    }

    @Test func claudeToolEvents() throws {
        let pre = try Fixtures.event(.claude, "PreToolUse-Bash-ls")
        guard case .toolWillRun(let call) = pre.kind else { Issue.record("not toolWillRun"); return }
        #expect(call.name == "Bash")
        #expect(call.command == "ls")
        #expect(call.id?.hasPrefix("toolu_") == true)
        #expect(pre.subagentID == nil)

        let failure = try Fixtures.event(.claude, "PostToolUseFailure")
        guard case .toolDidRun(let failed, let didFail) = failure.kind else { Issue.record("not toolDidRun"); return }
        #expect(failed.command == "false")
        #expect(didFail)

        let inSubagent = try Fixtures.event(.claude, "PreToolUse-Bash-subagent-ls")
        #expect(inSubagent.subagentID == "a63477869eba0b567")
        #expect(inSubagent.subagentType == "Explore")
    }

    @Test func claudePermissionRequestKeepsSuggestions() throws {
        let event = try Fixtures.event(.claude, "PermissionRequest")
        guard case .permissionRequested(let call, let suggestions) = event.kind else {
            Issue.record("not a permission request")
            return
        }
        #expect(call.command == "touch made-by-test.txt")
        #expect(call.id == nil) // PermissionRequest has no tool_use_id
        #expect(suggestions.map { $0["type"]?.string } == ["addDirectories", "setMode"])
    }

    @Test func claudeStopCarriesTheLastMessage() throws {
        let stop = try Fixtures.event(.claude, "Stop")
        guard case .turnFinished(let message) = stop.kind else { Issue.record("not a stop"); return }
        #expect(message?.contains("I need your approval") == true)

        let failure = try Fixtures.event(.claude, "StopFailure.docs")
        #expect(failure.kind == .turnFailed(error: "rate_limit", message: "API Error: Rate limit reached"))
    }

    @Test func claudeSubagentsAndNotifications() throws {
        #expect(try Fixtures.event(.claude, "SubagentStart").kind == .subagentStarted(type: "Explore"))
        let stop = try Fixtures.event(.claude, "SubagentStop")
        #expect(stop.kind == .subagentFinished(type: "Explore", lastMessage: "Just one file here: notes.txt"))
        #expect(stop.subagentID == nil) // the lifecycle event describes the subagent itself

        let notification = try Fixtures.event(.claude, "Notification-permission_prompt.docs")
        guard case .notification(let type, let message, let title) = notification.kind else {
            Issue.record("not a notification")
            return
        }
        #expect(type == "permission_prompt")
        #expect(message == "Claude needs your permission to use Bash")
        #expect(title == "Permission needed")
    }

    @Test func codexEvents() throws {
        let start = try Fixtures.event(.codex, "SessionStart")
        #expect(start.kind == .sessionStarted(source: "startup"))
        #expect(start.model == "gpt-5.6-sol")
        #expect(start.transcriptPath?.contains("/.codex/sessions/") == true)

        let prompt = try Fixtures.event(.codex, "UserPromptSubmit")
        guard case .promptSubmitted = prompt.kind else { Issue.record("not a prompt"); return }

        let pre = try Fixtures.event(.codex, "PreToolUse-Bash.docs")
        guard case .toolWillRun(let call) = pre.kind else { Issue.record("not toolWillRun"); return }
        #expect(call.command == "swift test --filter Parser")

        let patch = try Fixtures.event(.codex, "PermissionRequest-apply_patch.docs")
        guard case .permissionRequested(let patchCall, let suggestions) = patch.kind else {
            Issue.record("not a permission request")
            return
        }
        #expect(patchCall.filePaths == ["Sources/App/NotchModel.swift"])
        #expect(suggestions.isEmpty)

        #expect(try Fixtures.event(.codex, "Stop.docs").kind
            == .turnFinished(lastMessage: "All 12 tests pass. Want me to open a PR?"))
        #expect(try Fixtures.event(.codex, "Interrupt.docs").kind == .interrupted)
        #expect(try Fixtures.event(.codex, "SessionEnd").kind == .sessionEnded(reason: "other"))
    }

    @Test func unknownEventsAndFieldsNeverFail() {
        let payload = JSONValue.parse(#"{"session_id":"s1","hook_event_name":"TeammateIdle","new_field":{"x":[1,2]}}"#)!
        let event = HookPayloadParser.parse(agent: .claude, eventName: "TeammateIdle", payload: payload)
        #expect(event?.kind == .other(name: "TeammateIdle"))

        // The CLI's event argument stands in for a missing hook_event_name; spellings are normalized.
        let bare = JSONValue.parse(#"{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}"#)!
        guard case .toolWillRun = HookPayloadParser.parse(agent: .codex, eventName: "pre_tool_use", payload: bare)?.kind
        else { Issue.record("not toolWillRun"); return }

        // Wrong types are ignored, not fatal.
        let odd = JSONValue.parse(#"{"session_id":"s1","hook_event_name":"Stop","last_assistant_message":42,"cwd":7}"#)!
        let stop = HookPayloadParser.parse(agent: .claude, eventName: nil, payload: odd)
        #expect(stop?.kind == .turnFinished(lastMessage: nil))
        #expect(stop?.cwd == nil)

        #expect(HookPayloadParser.parse(agent: .claude, eventName: "Stop", payload: .object([:])) == nil)
        #expect(HookPayloadParser.parse(agent: .claude, eventName: "Stop", payload: .array([])) == nil)
        #expect(HookPayloadParser.parse(agent: .claude, eventName: "Stop", payload: .string("x")) == nil)
    }

    @Test func codexLegacyNotifyPayload() {
        let payload = JSONValue.parse(#"{"type":"agent-turn-complete","thread-id":"t1","turn-id":"u1","cwd":"/p","last-assistant-message":"Done."}"#)!
        let event = HookPayloadParser.parse(agent: .codex, eventName: "agent-turn-complete", payload: payload)
        #expect(event?.sessionID == "t1")
        #expect(event?.kind == .turnFinished(lastMessage: "Done."))
    }
}
