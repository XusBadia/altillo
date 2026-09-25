import AltilloCore
import Foundation

/// One tool call as the agents describe it in their hooks and session files.
public struct AgentToolCall: Hashable, Sendable {
    /// "Bash", "Edit", "apply_patch", "mcp__github__create_issue"…
    public var name: String
    /// The tool's arguments, as sent (tool-specific).
    public var input: JSONValue
    /// Claude's `tool_use_id` / Codex's call id, when given.
    public var id: String?

    public init(name: String, input: JSONValue = .object([:]), id: String? = nil) {
        self.name = name
        self.input = input
        self.id = id
    }

    /// The shell command, for shell-like tools (Claude `Bash`/`PowerShell`, Codex `Bash` — its unified exec too).
    public var command: String? {
        guard ToolNames.shell.contains(name) else { return nil }
        if let text = input["command"].nonEmptyString { return text }
        if let parts = input["command"]?.array?.compactMap(\.string), !parts.isEmpty {
            return ShellWords.commandFromArgv(parts)
        }
        return input["cmd"].nonEmptyString
    }

    /// Files the call writes or reads, absolute when the agent gave them so.
    public var filePaths: [String] {
        if name == "apply_patch" || name == "ApplyPatch" {
            return PatchText.files(in: input["command"]?.string ?? input["input"]?.string ?? input["patch"]?.string ?? "")
        }
        for key in ["file_path", "notebook_path", "path", "filePath"] {
            if let path = input[key].nonEmptyString { return [path] }
        }
        if let edits = input["edits"]?.array {
            return edits.compactMap { $0["file_path"].nonEmptyString }
        }
        return []
    }
}

/// Tool names that mean the same thing across agents.
public enum ToolNames {
    public static let shell: Set<String> = ["Bash", "PowerShell", "shell", "exec_command", "local_shell", "container.exec",
                                           "unified_exec"]
    public static let edit: Set<String> = ["Edit", "MultiEdit", "NotebookEdit", "apply_patch", "ApplyPatch", "str_replace_based_edit_tool"]
    public static let write: Set<String> = ["Write", "write_file", "create_file"]
    public static let read: Set<String> = ["Read", "read_file", "view_image"]
    public static let fileWriting: Set<String> = edit.union(write)
}

/// A hook event or session-file observation, normalized across agents. Parsers produce it; `AgentStateMachine`
/// turns it into `AgentSession` changes.
public struct AgentEvent: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// `source`: startup, resume, clear, compact, fork.
        case sessionStarted(source: String?)
        /// `reason`: clear, resume, logout, prompt_input_exit, other.
        case sessionEnded(reason: String?)
        case promptSubmitted(prompt: String?)
        case toolWillRun(AgentToolCall)
        case toolDidRun(AgentToolCall, failed: Bool)
        /// The agent is about to ask for approval. `suggestions` are Claude's `permission_suggestions` (raw).
        case permissionRequested(AgentToolCall, suggestions: [JSONValue])
        /// Claude's `Notification`: `permission_prompt`, `idle_prompt`, `agent_needs_input`, `elicitation_dialog`…
        case notification(type: String?, message: String?, title: String?)
        /// The turn ended normally (`Stop`).
        case turnFinished(lastMessage: String?)
        /// The turn ended on an API error (`StopFailure`); `error` is the machine type ("rate_limit").
        case turnFailed(error: String?, message: String?)
        case subagentStarted(type: String?)
        case subagentFinished(type: String?, lastMessage: String?)
        /// The user interrupted the turn (Codex `Interrupt`).
        case interrupted
        /// Before/after compaction.
        case compacting(done: Bool)
        /// An event this version doesn't know. Still counts as activity.
        case other(name: String)
    }

    public var agent: AgentKind
    public var sessionID: String
    public var kind: Kind
    /// The raw event name ("PreToolUse").
    public var name: String
    public var cwd: String?
    public var transcriptPath: String?
    public var permissionMode: String?
    public var model: String?
    /// Set when the event comes from a subagent of the session (Claude's `agent_id`).
    public var subagentID: String?
    public var subagentType: String?

    public init(agent: AgentKind, sessionID: String, kind: Kind, name: String, cwd: String? = nil,
                transcriptPath: String? = nil, permissionMode: String? = nil, model: String? = nil,
                subagentID: String? = nil, subagentType: String? = nil) {
        self.agent = agent
        self.sessionID = sessionID
        self.kind = kind
        self.name = name
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.permissionMode = permissionMode
        self.model = model
        self.subagentID = subagentID
        self.subagentType = subagentType
    }
}
