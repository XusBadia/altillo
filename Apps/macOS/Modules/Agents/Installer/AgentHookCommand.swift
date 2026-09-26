import Foundation

/// A coding agent whose hooks Altillo can install. Raw values match `AgentKind` and the first argument of
/// `altillo-hook`. (OpenCode needs no hooks: Altillo follows its server.)
enum AgentHookTarget: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case gemini
    case copilot
    case cursor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini CLI"
        case .copilot: "Copilot CLI"
        case .cursor: "Cursor"
        }
    }

    /// The file Altillo edits, inside the agent's config directory. Copilot reads every `hooks/*.json`, so Altillo
    /// keeps its hooks in a file of its own there.
    var configFileName: String {
        switch self {
        case .claude, .gemini: "settings.json"
        case .codex, .cursor: "hooks.json"
        case .copilot: "hooks/altillo.json"
        }
    }

    /// The environment variable that moves the agent's config directory, and the default directory in the home.
    var configDirectoryVariable: String? {
        switch self {
        case .claude: "CLAUDE_CONFIG_DIR"
        case .codex: "CODEX_HOME"
        case .copilot: "COPILOT_HOME"
        case .gemini, .cursor: nil
        }
    }

    var defaultConfigDirectoryName: String {
        switch self {
        case .claude: ".claude"
        case .codex: ".codex"
        case .gemini: ".gemini"
        case .copilot: ".copilot"
        case .cursor: ".cursor"
        }
    }

    /// How the file lists handlers: Claude, Codex and Gemini wrap them in matcher groups
    /// (`hooks.<Event>: [{"hooks": [handler]}]`); Copilot and Cursor list them directly (`hooks.<event>: [handler]`)
    /// under a top-level `"version": 1`.
    enum Layout: Sendable { case grouped, flat }

    var layout: Layout {
        switch self {
        case .claude, .codex, .gemini: .grouped
        case .copilot, .cursor: .flat
        }
    }

    /// Gemini's `timeout` is in milliseconds; everyone else's in seconds.
    var timeoutScale: Int { self == .gemini ? 1000 : 1 }

    /// The event whose hook can hold the end of a turn open for a reply from the notch (all five support it).
    var replyEvent: String? { HookReplyOutputName.stopEvent(for: self) }

    /// A permission can be answered from the notch (the hook's answer schema is verified and the hook fires only
    /// when the agent would ask). Gemini's and Cursor's hooks can't answer a prompt; Copilot's fires for every tool.
    var answersPermissions: Bool { self == .claude || self == .codex }

    /// The events Altillo listens to, verified in September 2026 against Claude Code 2.1.281, Codex 0.152.0,
    /// Gemini CLI 0.61.0 (bundled docs), Copilot CLI 1.0.88 (docs.github.com) and Cursor CLI 2026.09.23 (source).
    var events: [AgentHookEvent] {
        switch self {
        case .claude:
            [
                .init("SessionStart"),
                // SessionEnd hooks share a 1.5 s budget that a longer `timeout` would raise: leave it alone.
                .init("SessionEnd", timeout: nil),
                .init("UserPromptSubmit"),
                .init("PreToolUse"),
                .init("PostToolUse"),
                .init("PermissionRequest", waitsForDecision: true),
                .init("Notification"),
                .init("Stop", repliable: true),
                .init("StopFailure"),
                .init("SubagentStart"),
                .init("SubagentStop"),
            ]
        case .codex:
            [
                .init("SessionStart"),
                // Codex caps SessionEnd and Interrupt at 1 s by default (3 s at most): leave it alone.
                .init("SessionEnd", timeout: nil),
                .init("UserPromptSubmit"),
                .init("PreToolUse"),
                .init("PostToolUse"),
                .init("PermissionRequest", waitsForDecision: true),
                .init("Stop", repliable: true),
                .init("Interrupt", timeout: nil),
                .init("SubagentStart"),
                .init("SubagentStop"),
            ]
        case .gemini:
            [
                .init("SessionStart"),
                .init("SessionEnd"),
                .init("BeforeAgent"),
                .init("BeforeTool"),
                .init("AfterTool"),
                .init("Notification"),
                .init("AfterAgent", repliable: true),
                .init("PreCompress"),
            ]
        case .copilot:
            // No preToolUse: Copilot fails it closed when the hook errors (a moved Altillo would deny every tool).
            // permissionRequest fires for every tool call before Copilot's own rules, so it only reports activity.
            [
                .init("sessionStart"),
                .init("sessionEnd"),
                .init("userPromptSubmitted"),
                .init("permissionRequest"),
                .init("postToolUse"),
                .init("postToolUseFailure"),
                .init("notification"),
                .init("agentStop", repliable: true),
                .init("subagentStart"),
                .init("subagentStop"),
                .init("errorOccurred"),
            ]
        case .cursor:
            [
                .init("sessionStart"),
                .init("sessionEnd"),
                .init("beforeSubmitPrompt"),
                .init("preToolUse"),
                .init("postToolUse"),
                .init("postToolUseFailure"),
                .init("afterAgentResponse"),
                .init("stop", repliable: true),
                .init("subagentStart"),
                .init("subagentStop"),
            ]
        }
    }
}

/// The stop event names, shared with `altillo-hook` (`HookReplyOutput.stopEvent`).
enum HookReplyOutputName {
    static func stopEvent(for target: AgentHookTarget) -> String? {
        switch target {
        case .claude, .codex: "Stop"
        case .gemini: "AfterAgent"
        case .copilot: "agentStop"
        case .cursor: "stop"
        }
    }
}

/// One hook event Altillo installs a handler for.
struct AgentHookEvent: Equatable, Sendable {
    let name: String
    /// The handler's `timeout` in seconds for events that don't wait; nil leaves the agent's default.
    let timeout: Int?
    /// PermissionRequest: the hook waits for the user's answer in the notch, up to the chosen wait.
    let waitsForDecision: Bool
    /// The agent's stop event: with "Let me reply from the notch" on, the hook holds the turn open for a reply.
    let repliable: Bool

    init(_ name: String, timeout: Int? = AgentHookCommand.quickTimeout, waitsForDecision: Bool = false,
         repliable: Bool = false) {
        self.name = name
        self.timeout = waitsForDecision ? nil : timeout
        self.waitsForDecision = waitsForDecision
        self.repliable = repliable
    }
}

/// The command line every installed hook runs, and how Altillo recognises its own hooks later. The one place to
/// change if `altillo-hook`'s arguments change.
enum AgentHookCommand {
    /// The file name of the CLI; the marker that identifies Altillo's hooks in any config file (the command's
    /// executable, whatever directory it lives in, so hooks written by older builds are found too).
    static let executableName = "altillo-hook"

    /// Events that only report something: `altillo-hook` hands the event to the socket and exits in milliseconds,
    /// so a short timeout keeps a wedged hook from ever holding the agent up.
    static let quickTimeout = 10

    /// How much longer than the user's wait the agent lets a PermissionRequest hook run, so the hook always gets
    /// to answer "no decision" itself instead of being killed.
    static let permissionTimeoutMargin = 30

    /// The wait choices offered in Settings, in seconds. 2 minutes by default (PLAN §5.3).
    static let waitChoices = [30, 60, 120, 300]
    static let defaultWait = 120

    /// `"<hook>" <agent> <event>`, plus `--timeout <seconds>` for PermissionRequest and `--reply-wait <seconds>` for
    /// the stop event when the user lets the agent wait for a reply.
    static func command(hookPath: String, agent: AgentHookTarget, event: AgentHookEvent, wait: Int,
                        reply: Bool = false) -> String {
        var command = "\(shellQuoted(hookPath)) \(agent.rawValue) \(event.name)"
        if event.waitsForDecision { command += " --timeout \(wait)" }
        if event.repliable, reply { command += " --reply-wait \(wait)" }
        return command
    }

    /// The handler's `timeout` field for an event, in seconds.
    static func timeout(for event: AgentHookEvent, wait: Int, reply: Bool = false) -> Int? {
        if event.waitsForDecision || (event.repliable && reply) { return wait + permissionTimeoutMargin }
        return event.timeout
    }

    /// Whether a hook command runs `altillo-hook` (quoted or not, from any path).
    static func isAltilloCommand(_ command: String) -> Bool {
        guard let executable = executable(of: command) else { return false }
        return (executable as NSString).lastPathComponent == executableName
    }

    /// The first word of a shell command, with quotes and backslash escapes removed.
    static func executable(of command: String) -> String? {
        var word = ""
        var quote: Character?
        var escaped = false
        var started = false
        for character in command {
            if escaped { word.append(character); escaped = false; continue }
            if let open = quote {
                if character == open {
                    quote = nil
                } else if character == "\\" && open == "\"" {
                    escaped = true
                } else {
                    word.append(character)
                }
                continue
            }
            switch character {
            case "\"", "'": quote = character; started = true
            case "\\": escaped = true; started = true
            case " ", "\t", "\n":
                if started { return word }
            default:
                word.append(character); started = true
            }
        }
        return started && !word.isEmpty ? word : nil
    }

    /// Double-quoted for `sh`/`bash`, escaping what double quotes don't protect.
    static func shellQuoted(_ text: String) -> String {
        var quoted = "\""
        for character in text {
            if "\"\\$`".contains(character) { quoted.append("\\") }
            quoted.append(character)
        }
        return quoted + "\""
    }
}
