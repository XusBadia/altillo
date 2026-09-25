import AltilloCore
import Foundation
import Testing
@testable import AltilloAgents

/// Session-file lines follow the shapes seen in real Claude Code 2.1.281 transcripts and Codex 0.152–0.155 rollouts
/// on the development Mac (field names only; contents are made up).
@Suite("Session files")
struct SessionFileTests {
    static let claudeID = "2b8eaec5-288a-48ab-bd15-dfce31d2329e"
    static let codexID = "01a0d551-386c-70f1-83e7-4c541bb1ad08"
    let now = Date()

    func temp(_ name: String, _ lines: [String], padding: Int = 0) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("altillo-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        var text = ""
        if padding > 0 {
            // Old history the tail must not need.
            let filler = #"{"type":"attachment","attachment":{"x":"\#(String(repeating: "a", count: 900))"}}"#
            for _ in 0..<(padding / 950) { text += filler + "\n" }
        }
        text += lines.joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func claude(_ type: String, _ message: String, extra: String = "", ts: String = "2026-09-24T21:28:20.500Z") -> String {
        #"{"type":"\#(type)","cwd":"/Users/me/Projects/demo","sessionId":"\#(claudeID)","entrypoint":"cli","isSidechain":false,"timestamp":"\#(ts)","message":\#(message)\#(extra)}"#
    }

    static let userPrompt = claude("user", #"{"role":"user","content":"Run the tests"}"#)
    static let toolUse = claude("assistant", #"{"id":"msg_1","role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"swift test"}}]}"#)
    static let toolResult = claude("user", #"{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"ok"}]}"#)
    static let thinking = claude("assistant", #"{"id":"msg_2","role":"assistant","stop_reason":"end_turn","content":[{"type":"thinking","thinking":""}]}"#)
    static let answer = claude("assistant", #"{"id":"msg_2","role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"All green. Ship it?"}]}"#)
    static let bookkeeping = [
        #"{"type":"system","subtype":"stop_hook_summary","timestamp":"2026-09-24T21:28:20.556Z","isSidechain":false}"#,
        #"{"type":"last-prompt","lastPrompt":"Run the tests","sessionId":"\#(claudeID)"}"#,
        #"{"type":"cost-state","totalCostUSD":0.01,"sessionId":"\#(claudeID)"}"#,
    ]

    func claudeSnapshot(_ lines: [String], padding: Int = 0) throws -> SessionFileSnapshot {
        let url = try temp("\(Self.claudeID).jsonl", lines, padding: padding)
        let tail = try #require(SessionFileTail.read(url))
        let sessionID = try #require(ClaudeTranscript.sessionID(for: url))
        return try #require(ClaudeTranscript.snapshot(tail: tail.lines, sessionID: sessionID, modified: tail.modified))
    }

    @Test func claudeFinishedTurnWaitsForAnswer() throws {
        let snapshot = try claudeSnapshot([Self.userPrompt, Self.toolUse, Self.toolResult, Self.thinking, Self.answer]
            + Self.bookkeeping, padding: 400_000)
        #expect(snapshot.phase == .waitingAnswer)
        #expect(snapshot.lastMessage == "All green. Ship it?")
        #expect(snapshot.cwd == "/Users/me/Projects/demo")
        #expect(snapshot.sessionID == Self.claudeID)
        #expect(snapshot.isInteractive)
    }

    @Test func claudeWorkingStates() throws {
        let running = try claudeSnapshot([Self.userPrompt, Self.toolUse])
        #expect(running.phase == .working)
        #expect(running.activity == "Running `swift test`")

        #expect(try claudeSnapshot([Self.userPrompt, Self.toolUse, Self.toolResult]).phase == .working)
        #expect(try claudeSnapshot([Self.userPrompt]).activity == "Thinking")

        let interrupted = Self.claude("user", #"{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}"#)
        #expect(try claudeSnapshot([Self.userPrompt, Self.toolUse, interrupted]).phase == .idle)
    }

    @Test func claudeHeadlessRunFinishes() throws {
        let headless = [Self.userPrompt, Self.answer].map { $0.replacingOccurrences(of: #""entrypoint":"cli""#, with: #""entrypoint":"sdk-cli""#) }
        let snapshot = try claudeSnapshot(headless)
        #expect(snapshot.phase == .finished)
        #expect(!snapshot.isInteractive)
    }

    @Test func claudeIgnoresSidechainsAndPartialLines() throws {
        let sidechain = Self.toolUse.replacingOccurrences(of: #""isSidechain":false"#, with: #""isSidechain":true"#)
        let snapshot = try claudeSnapshot([Self.userPrompt, Self.answer, sidechain, #"{"type":"assistant","message":{"#])
        #expect(snapshot.phase == .waitingAnswer)
    }

    @Test func claudeFileNamesAndLastMessage() {
        #expect(ClaudeTranscript.sessionID(for: URL(fileURLWithPath: "/x/\(Self.claudeID).jsonl")) == Self.claudeID)
        #expect(ClaudeTranscript.sessionID(for: URL(fileURLWithPath: "/x/agent-abc.jsonl")) == nil)
        let lines = [Self.userPrompt, Self.answer, Self.bookkeeping[0]].map { Data($0.utf8) }
        #expect(ClaudeTranscript.lastAssistantMessage(tail: lines) == "All green. Ship it?")
    }

    // MARK: Codex

    static let meta = #"{"timestamp":"2026-09-24T21:27:45.000Z","type":"session_meta","payload":{"id":"\#(codexID)","timestamp":"2026-09-24T21:27:45.000Z","cwd":"/Users/me/Projects/demo","originator":"codex_cli_rs","cli_version":"0.152.0","source":"cli","thread_source":"user","base_instructions":{"text":"…"}}}"#
    static func codex(_ type: String, _ payload: String) -> String {
        #"{"timestamp":"2026-09-24T21:30:00.000Z","type":"\#(type)","payload":\#(payload)}"#
    }
    static let taskStarted = codex("event_msg", #"{"type":"task_started","turn_id":"t1"}"#)
    static let turnContext = codex("turn_context", #"{"cwd":"/Users/me/Projects/demo","model":"gpt-5.6-sol"}"#)
    static let execCall = codex("response_item", #"{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"swift build\"}","call_id":"c1"}"#)
    static let patchCall = codex("response_item", #"{"type":"custom_tool_call","name":"apply_patch","input":"*** Begin Patch\n*** Update File: Sources/A.swift\n*** End Patch","call_id":"c2"}"#)
    static let callOutput = codex("response_item", #"{"type":"function_call_output","call_id":"c1","output":"ok"}"#)
    static let finalAnswer = codex("response_item", #"{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"Built fine."}]}"#)
    static let taskComplete = codex("event_msg", #"{"type":"task_complete","turn_id":"t1","last_agent_message":"Built fine."}"#)
    static let tokenCount = codex("event_msg", #"{"type":"token_count","info":null}"#)

    func codexSnapshot(_ lines: [String], meta: String = SessionFileTests.meta) throws -> SessionFileSnapshot? {
        let url = try temp("rollout-2026-09-24T23-27-45-\(Self.codexID).jsonl", [meta] + lines)
        let parsedMeta = SessionFileTail.firstLine(url).flatMap(CodexRollout.meta(firstLine:))
        let tail = try #require(SessionFileTail.read(url))
        return CodexRollout.snapshot(tail: tail.lines, meta: parsedMeta, sessionID: try #require(CodexRollout.sessionID(for: url)),
                                     modified: tail.modified)
    }

    @Test func codexPhases() throws {
        let running = try #require(try codexSnapshot([Self.taskStarted, Self.turnContext, Self.execCall]))
        #expect(running.phase == .working)
        #expect(running.activity == "Running `swift build`")
        #expect(running.sessionID == Self.codexID)
        #expect(running.startedAt != nil)

        let patching = try #require(try codexSnapshot([Self.taskStarted, Self.patchCall]))
        #expect(patching.activity == "Editing A.swift")

        #expect(try codexSnapshot([Self.taskStarted, Self.execCall, Self.callOutput])?.activity == "Thinking")

        let done = try #require(try codexSnapshot([Self.taskStarted, Self.execCall, Self.callOutput, Self.finalAnswer,
                                                   Self.taskComplete, Self.tokenCount]))
        #expect(done.phase == .waitingAnswer)
        #expect(done.lastMessage == "Built fine.")
        #expect(done.activity == nil)

        let aborted = Self.codex("event_msg", #"{"type":"turn_aborted","reason":"interrupted"}"#)
        #expect(try codexSnapshot([Self.taskStarted, Self.execCall, aborted])?.phase == .idle)
    }

    @Test func codexExecFinishesAndSubagentsAreSkipped() throws {
        let exec = Self.meta.replacingOccurrences(of: #""originator":"codex_cli_rs""#, with: #""originator":"codex_exec""#)
            .replacingOccurrences(of: #""source":"cli""#, with: #""source":"exec""#)
        #expect(try codexSnapshot([Self.taskStarted, Self.taskComplete], meta: exec)?.phase == .finished)

        let subagent = Self.meta.replacingOccurrences(of: #""source":"cli""#, with: #""source":{"subagent":{"thread_spawn":{}}}"#)
        #expect(try codexSnapshot([Self.taskStarted], meta: subagent) == nil)

        let automation = Self.meta.replacingOccurrences(of: #""thread_source":"user""#, with: #""thread_source":"automation""#)
        #expect(try codexSnapshot([Self.taskStarted], meta: automation) == nil)
    }

    @Test func codexFileNames() {
        #expect(CodexRollout.sessionID(for: URL(fileURLWithPath: "/s/rollout-2026-09-24T23-27-45-\(Self.codexID).jsonl"))
            == Self.codexID)
        #expect(CodexRollout.sessionID(for: URL(fileURLWithPath: "/s/history.jsonl")) == nil)
    }

    @Test func tailReadsOnlyTheEnd() throws {
        let url = try temp("big.jsonl", [#"{"last":true}"#], padding: 1_000_000)
        let tail = try #require(SessionFileTail.read(url, maxBytes: 4096))
        #expect(tail.size > 900_000)
        #expect(tail.lines.count < 6)
        #expect(tail.lines.allSatisfy { JSONValue.parse($0) != nil }) // the cut first line was dropped
        #expect(JSONValue.parse(tail.lines.last!)?["last"]?.bool == true)
        #expect(SessionFileTail.read(URL(fileURLWithPath: "/nonexistent/x.jsonl")) == nil)
    }
}
