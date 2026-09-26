import AltilloCore
import Foundation

/// What a session file says about its session: the passive source that works without hooks (read-only,
/// approximate: it can't see permission prompts and can't approve anything).
public struct SessionFileSnapshot: Hashable, Sendable {
    public var agent: AgentKind
    public var sessionID: String
    public var cwd: String
    /// A project name when the file has no cwd (from Claude's escaped folder name).
    public var projectHint: String?
    public var phase: AgentPhase
    public var activity: String?
    public var lastMessage: String?
    public var lastActivity: Date
    public var startedAt: Date?
    /// `claude -p` / `codex exec`: the session ends when its turn does.
    public var isInteractive: Bool

    public init(agent: AgentKind, sessionID: String, cwd: String, projectHint: String? = nil, phase: AgentPhase,
                activity: String? = nil, lastMessage: String? = nil, lastActivity: Date, startedAt: Date? = nil,
                isInteractive: Bool = true) {
        self.agent = agent
        self.sessionID = sessionID
        self.cwd = cwd
        self.projectHint = projectHint
        self.phase = phase
        self.activity = activity
        self.lastMessage = lastMessage
        self.lastActivity = lastActivity
        self.startedAt = startedAt
        self.isInteractive = isInteractive
    }
}

/// Reads only the end (or the first line) of append-only JSONL files; never the whole file.
public enum SessionFileTail {
    public static let defaultTailBytes = 192 << 10

    public struct Tail: Sendable {
        /// Complete lines, oldest first. A line cut by the window's start is dropped.
        public var lines: [Data]
        public var size: UInt64
        public var modified: Date
    }

    public static func read(_ url: URL, maxBytes: Int = defaultTailBytes) -> Tail? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? Date()
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else {
            return Tail(lines: [], size: size, modified: modified)
        }
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true).map { Data($0) }
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        // A last line without its newline may still be being written; JSON parsing rejects it if it's partial.
        return Tail(lines: lines, size: size, modified: modified)
    }

    /// The first line (up to `maxBytes`), e.g. Codex's `session_meta`.
    public static func firstLine(_ url: URL, maxBytes: Int = 1 << 20) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var collected = Data()
        while collected.count < maxBytes {
            guard let chunk = try? handle.read(upToCount: 64 << 10), !chunk.isEmpty else { break }
            if let newline = chunk.firstIndex(of: 0x0A) {
                collected.append(chunk[chunk.startIndex..<newline])
                return collected
            }
            collected.append(chunk)
        }
        return collected.isEmpty ? nil : collected
    }
}

enum Timestamps {
    static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(text, strategy: Date.ISO8601FormatStyle())
    }
}

// MARK: - Claude Code

/// Claude Code transcripts: `~/.claude/projects/<cwd with / and . as ->/<session id>.jsonl`, one JSON object per
/// line. Verified on 2.1.281: conversational entries have `type` `user`/`assistant`, `message` (`role`, `content`
/// string or blocks `text`/`thinking`/`tool_use`/`tool_result`, `stop_reason` `tool_use`/`end_turn`/…),
/// `cwd`, `sessionId`, `timestamp`, `isSidechain`, `entrypoint` (`cli`, `sdk-ts`, `sdk-cli` for `claude -p`).
/// Other lines (`attachment`, `system`, `last-prompt`, `ai-title`, `cost-state`, `queue-operation`, `mode`…) are
/// bookkeeping. Subagent transcripts live in `<session id>/subagents/` and are ignored.
public enum ClaudeTranscript {
    public static func sessionID(for url: URL) -> String? {
        guard url.pathExtension == "jsonl" else { return nil }
        let stem = url.deletingPathExtension().lastPathComponent
        return UUID(uuidString: stem) != nil ? stem : nil
    }

    public static func snapshot(tail: [Data], sessionID: String, modified: Date,
                                projectFolder: String? = nil) -> SessionFileSnapshot? {
        var cwd: String?
        var entrypoint: String?
        var latest: Date?
        var decided: (phase: AgentPhase, activity: String?, message: String?)?
        var pendingText: [String] = []
        var assistantMessageID: String?

        for line in tail.reversed() {
            guard let entry = JSONValue.parse(line), let type = entry["type"]?.string else { continue }
            if cwd == nil { cwd = entry["cwd"].nonEmptyString }
            if entrypoint == nil { entrypoint = entry["entrypoint"].nonEmptyString }
            if latest == nil { latest = Timestamps.parse(entry["timestamp"]?.string) }
            if decided != nil {
                if cwd != nil && entrypoint != nil && latest != nil { break }
                continue
            }
            guard type == "user" || type == "assistant", entry["isSidechain"]?.bool != true,
                  let message = entry["message"] else { continue }

            if type == "assistant" {
                let id = message["id"]?.string
                if let assistantMessageID, id != assistantMessageID {
                    // An earlier assistant message: the one after it was text-only; decide from what we gathered.
                    decided = finish(pendingText)
                    continue
                }
                assistantMessageID = id
                let blocks = message["content"]?.array ?? []
                if let toolUse = blocks.last(where: { $0["type"]?.string == "tool_use" }),
                   let name = toolUse["name"].nonEmptyString {
                    let call = AgentToolCall(name: name, input: toolUse["input"] ?? .object([:]))
                    if let question = ToolDescriptions.question(in: call) {
                        decided = (.waitingAnswer, ToolDescriptions.activity(for: call, cwd: cwd), question)
                    } else {
                        decided = (.working, ToolDescriptions.activity(for: call, cwd: cwd), nil)
                    }
                    continue
                }
                let texts = blocks.compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil }
                pendingText.insert(contentsOf: texts, at: 0)
                if let content = message["content"]?.string { pendingText.insert(content, at: 0) }
                let stop = message["stop_reason"]?.string
                if stop == nil || stop == "tool_use" {
                    // Still streaming, or its tool call isn't written yet.
                    decided = (.working, "Thinking", nil)
                }
                continue
            }

            // A user entry.
            if assistantMessageID != nil {
                decided = finish(pendingText)
                continue
            }
            if entry["isMeta"]?.bool == true { continue }
            if let text = message["content"]?.string {
                if text.hasPrefix("<local-command") || text.hasPrefix("<command-") { continue }
                if text.hasPrefix("[Request interrupted") {
                    decided = (.idle, nil, nil)
                    continue
                }
                decided = (.working, "Thinking", nil)
                continue
            }
            let blocks = message["content"]?.array ?? []
            if blocks.contains(where: { $0["type"]?.string == "text"
                && ($0["text"]?.string ?? "").hasPrefix("[Request interrupted") }) {
                decided = (.idle, nil, nil)
                continue
            }
            decided = (.working, "Thinking", nil)
        }
        if decided == nil, assistantMessageID != nil { decided = finish(pendingText) }

        let interactive = entrypoint != "sdk-cli"
        var phase = decided?.phase ?? .idle
        if !interactive, phase == .waitingAnswer { phase = .finished }
        return SessionFileSnapshot(
            agent: .claude, sessionID: sessionID, cwd: cwd ?? "", projectHint: projectFolder.map(projectName),
            phase: phase, activity: phase == .working || phase == .waitingAnswer ? decided?.activity : nil,
            lastMessage: decided?.message, lastActivity: max(latest ?? modified, modified),
            isInteractive: interactive)
    }

    private static func finish(_ texts: [String]) -> (phase: AgentPhase, activity: String?, message: String?) {
        let message = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (.waitingAnswer, nil, message.isEmpty ? nil : message)
    }

    /// `-Users-me-Documents-GitHub-altillo` → `altillo` (best effort: the escaping loses `/` vs `-`).
    static func projectName(_ folder: String) -> String {
        folder.split(separator: "-").last.map(String.init) ?? folder
    }

    /// The last assistant text in a transcript (for a `Stop` hook without `last_assistant_message`).
    public static func lastAssistantMessage(tail: [Data]) -> String? {
        for line in tail.reversed() {
            guard let entry = JSONValue.parse(line), entry["type"]?.string == "assistant",
                  entry["isSidechain"]?.bool != true else { continue }
            let texts = (entry["message"]?["content"]?.array ?? [])
                .compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil }
            let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
    }
}

// MARK: - Codex

/// Codex rollouts: `~/.codex/sessions/YYYY/MM/DD/rollout-<date>T<time>-<session id>.jsonl`. Verified on 0.152
/// (and 0.155 from other clients): line 1 is `session_meta` (`payload.id`, `cwd`, `originator` `codex_exec`/
/// `codex_cli_rs`/app names, `source` `exec`/`cli`/`vscode` or `{"subagent":…}`, `thread_source` `user`/
/// `automation`/`subagent`); then `turn_context` (`cwd`), `response_item` (`message` with `role` and `phase`
/// `commentary`/`final_answer`, `function_call` `name`+`arguments`, `custom_tool_call` `name`+`input`, their
/// `*_output`, `reasoning`) and `event_msg` (`task_started`, `task_complete` with `last_agent_message`,
/// `turn_aborted`, `item_completed`, `token_count`).
public enum CodexRollout {
    public struct Meta: Hashable, Sendable {
        public var sessionID: String?
        public var cwd: String?
        public var originator: String?
        public var startedAt: Date?
        /// A subagent thread (shown through its parent).
        public var isSubagent: Bool
        /// A scheduled automation (not something the user watches).
        public var isAutomation: Bool
        /// `codex exec`: one task, then the session ends.
        public var isExec: Bool
    }

    public static func sessionID(for url: URL) -> String? {
        guard url.pathExtension == "jsonl" else { return nil }
        let stem = url.deletingPathExtension().lastPathComponent
        guard stem.hasPrefix("rollout-"), stem.count > 36 else { return nil }
        let id = String(stem.suffix(36))
        return UUID(uuidString: id) != nil ? id : nil
    }

    public static func meta(firstLine: Data) -> Meta? {
        guard let entry = JSONValue.parse(firstLine), entry["type"]?.string == "session_meta",
              let payload = entry["payload"] else { return nil }
        let source = payload["source"]
        let threadSource = payload["thread_source"]?.string
        let isSubagent = source?["subagent"] != nil || threadSource == "subagent"
        return Meta(
            sessionID: payload["id"].nonEmptyString ?? payload["session_id"].nonEmptyString,
            cwd: payload["cwd"].nonEmptyString, originator: payload["originator"].nonEmptyString,
            startedAt: Timestamps.parse(payload["timestamp"]?.string ?? entry["timestamp"]?.string),
            isSubagent: isSubagent, isAutomation: threadSource == "automation",
            isExec: payload["originator"]?.string == "codex_exec" || source?.string == "exec")
    }

    public static func snapshot(tail: [Data], meta: Meta?, sessionID: String, modified: Date) -> SessionFileSnapshot? {
        if meta?.isSubagent == true || meta?.isAutomation == true { return nil }
        var cwd: String?
        var latest: Date?
        var phase: AgentPhase?
        var activity: String?
        var lastMessage: String?
        var finalAnswer: String?

        for line in tail.reversed() {
            guard let entry = JSONValue.parse(line) else { continue }
            if latest == nil { latest = Timestamps.parse(entry["timestamp"]?.string) }
            let payload = entry["payload"]
            let type = entry["type"]?.string
            if type == "turn_context", cwd == nil { cwd = payload?["cwd"].nonEmptyString }
            if phase != nil {
                if cwd != nil { break }
                continue
            }
            switch (type, payload?["type"]?.string) {
            case ("event_msg", "task_complete"):
                phase = .waitingAnswer
                lastMessage = payload?["last_agent_message"].nonEmptyString
            case ("event_msg", "turn_aborted"):
                phase = .idle
            case ("event_msg", "task_started"):
                phase = .working
                if activity == nil { activity = "Thinking" }
            case ("response_item", "function_call"), ("response_item", "custom_tool_call"),
                 ("response_item", "local_shell_call"):
                if activity == nil, let payload { activity = describe(call: payload) }
            case ("response_item", "function_call_output"), ("response_item", "custom_tool_call_output"),
                 ("response_item", "reasoning"):
                if activity == nil { activity = "Thinking" }
            case ("response_item", "message"):
                guard payload?["role"]?.string == "assistant" else { break }
                if finalAnswer == nil, payload?["phase"]?.string != "commentary" {
                    finalAnswer = (payload?["content"]?.array ?? [])
                        .compactMap { $0["text"]?.string }.joined(separator: "\n")
                }
                if activity == nil { activity = "Thinking" }
            default:
                break
            }
        }
        var resolved = phase ?? (activity != nil ? .working : .idle)
        if resolved == .waitingAnswer, lastMessage == nil { lastMessage = finalAnswer }
        let interactive = meta?.isExec != true
        if !interactive, resolved == .waitingAnswer { resolved = .finished }
        return SessionFileSnapshot(
            agent: .codex, sessionID: meta?.sessionID ?? sessionID, cwd: cwd ?? meta?.cwd ?? "",
            phase: resolved, activity: resolved == .working ? activity : nil,
            lastMessage: resolved == .working ? nil : lastMessage,
            lastActivity: max(latest ?? modified, modified), startedAt: meta?.startedAt,
            isInteractive: interactive)
    }

    /// A rollout tool call as an activity line.
    static func describe(call payload: JSONValue) -> String {
        let name = payload["name"]?.string ?? payload["type"]?.string ?? "tool"
        var input: JSONValue = .object([:])
        if let arguments = payload["arguments"]?.string, let parsed = JSONValue.parse(arguments) {
            input = parsed
        } else if let raw = payload["input"]?.string {
            input = .object(["command": .string(raw)])
        } else if let action = payload["action"] {
            input = action
        }
        switch name {
        case "exec_command", "shell", "local_shell_call", "container.exec", "local_shell":
            return ToolDescriptions.activity(for: AgentToolCall(name: "Bash", input: input), cwd: nil)
        case "exec", "js", "js_reset":
            return "Running code"
        default:
            return ToolDescriptions.activity(for: AgentToolCall(name: name, input: input), cwd: nil)
        }
    }
}

// MARK: - Gemini CLI

/// Gemini CLI chats (phase 14): `~/.gemini/tmp/<project id>/chats/session-<date>-<short id>.jsonl`, append-only JSONL
/// (verified in the 0.61.0 source, `chatRecordingService.ts`). The first record is the metadata (`sessionId`,
/// `projectHash`, `startTime`, `lastUpdated`, `kind`, `directories`); then messages (`id`, `timestamp`, `type`
/// `user`/`gemini`/`info`/`error`/`warning`, `content` as a string or `[{text}]`, `toolCalls` `[{name, args,
/// status}]` with status `validating|scheduled|awaiting_approval|executing|success|error|cancelled`), re-appended
/// with the same id when they change, and `{"$set":{…}}` metadata updates. `<project id>` is a slug that
/// `~/.gemini/projects.json` maps from the project's path (`{"projects":{"/path":"slug"}}`); older installs used the
/// path's SHA-256.
public enum GeminiChat {
    public struct Meta: Hashable, Sendable {
        public var sessionID: String
        public var startedAt: Date?
        public var isSubagent: Bool
    }

    public static func isChatFile(_ url: URL) -> Bool {
        url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("session-")
            && url.deletingLastPathComponent().lastPathComponent == "chats"
    }

    /// The project folder (`<project id>`) of a chat file.
    public static func projectID(for url: URL) -> String {
        url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
    }

    public static func meta(firstLine: Data) -> Meta? {
        guard let record = JSONValue.parse(firstLine), let id = record["sessionId"].nonEmptyString else { return nil }
        let kind = record["kind"]?.string?.lowercased() ?? ""
        return Meta(sessionID: id, startedAt: Timestamps.parse(record["startTime"]?.string),
                    isSubagent: kind.contains("subagent"))
    }

    /// `~/.gemini/projects.json`: project id → path.
    public static func projectPaths(registry: Data) -> [String: String] {
        guard let projects = JSONValue.parse(registry)?["projects"]?.object else { return [:] }
        var paths: [String: String] = [:]
        for (path, id) in projects { if let id = id.string { paths[id] = path } }
        return paths
    }

    public static func snapshot(tail: [Data], meta: Meta, cwd: String?, projectID: String,
                                modified: Date) -> SessionFileSnapshot? {
        var latest: Date?
        var decided: (phase: AgentPhase, activity: String?, message: String?)?
        var seen = Set<String>()
        for line in tail.reversed() {
            guard let record = JSONValue.parse(line), let type = record["type"]?.string else { continue }
            if latest == nil { latest = Timestamps.parse(record["timestamp"]?.string) }
            // A message re-appended later supersedes its earlier copies.
            if let id = record["id"]?.string, !seen.insert(id).inserted { continue }
            switch type {
            case "user":
                let text = text(of: record["content"])
                if text.hasPrefix("/") { continue } // a slash command, not a turn
                decided = (.working, "Thinking", nil)
            case "gemini":
                let calls = record["toolCalls"]?.array ?? []
                if let waiting = calls.last(where: { $0["status"]?.string == "awaiting_approval" }) {
                    let call = toolCall(waiting)
                    decided = (.waitingPermission, ToolDescriptions.activity(for: call, cwd: cwd), nil)
                } else if let running = calls.last(where: {
                    ["validating", "scheduled", "executing"].contains($0["status"]?.string ?? "")
                }) {
                    decided = (.working, ToolDescriptions.activity(for: toolCall(running), cwd: cwd), nil)
                } else {
                    let message = text(of: record["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
                    decided = message.isEmpty ? (.working, "Thinking", nil) : (.waitingAnswer, nil, message)
                }
            case "error":
                decided = (.failed, nil, text(of: record["content"]))
            default:
                continue // info, warning, metadata
            }
            break
        }
        guard let decided else {
            return SessionFileSnapshot(agent: .gemini, sessionID: meta.sessionID, cwd: cwd ?? "", projectHint: projectID,
                                       phase: .idle, lastActivity: max(latest ?? modified, modified),
                                       startedAt: meta.startedAt)
        }
        return SessionFileSnapshot(
            agent: .gemini, sessionID: meta.sessionID, cwd: cwd ?? "", projectHint: projectID, phase: decided.phase,
            activity: decided.activity, lastMessage: decided.message, lastActivity: max(latest ?? modified, modified),
            startedAt: meta.startedAt)
    }

    static func toolCall(_ call: JSONValue) -> AgentToolCall {
        AgentToolCall(name: call["name"].nonEmptyString ?? "tool", input: call["args"] ?? .object([:]))
    }

    /// `content` is a string, a part, or a list of parts (`{text}`).
    static func text(of content: JSONValue?) -> String {
        guard let content else { return "" }
        if let text = content.string { return text }
        if let parts = content.array { return parts.compactMap { $0["text"]?.string ?? $0.string }.joined(separator: "\n") }
        return content["text"]?.string ?? ""
    }
}
