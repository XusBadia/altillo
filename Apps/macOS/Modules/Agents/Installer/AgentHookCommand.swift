import Foundation

/// A coding agent whose hooks Altillo can install. Raw values match `AgentKind` and the first argument of
/// `altillo-hook`.
enum AgentHookTarget: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// The file Altillo edits, inside the agent's config directory.
    var configFileName: String {
        switch self {
        case .claude: "settings.json"
        case .codex: "hooks.json"
        }
    }

    /// The environment variable that moves the agent's config directory, and the default directory in the home.
    var configDirectoryVariable: String {
        switch self {
        case .claude: "CLAUDE_CONFIG_DIR"
        case .codex: "CODEX_HOME"
        }
    }

    var defaultConfigDirectoryName: String {
        switch self {
        case .claude: ".claude"
        case .codex: ".codex"
        }
    }

    /// The events Altillo listens to, verified against Claude Code 2.1.281 and Codex 0.152.0 (September 2026):
    /// https://code.claude.com/docs/en/hooks and https://developers.openai.com/codex/hooks.
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
                .init("Stop"),
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
                .init("Stop"),
                .init("Interrupt", timeout: nil),
                .init("SubagentStart"),
                .init("SubagentStop"),
            ]
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

    init(_ name: String, timeout: Int? = AgentHookCommand.quickTimeout, waitsForDecision: Bool = false) {
        self.name = name
        self.timeout = waitsForDecision ? nil : timeout
        self.waitsForDecision = waitsForDecision
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

    /// `"<hook>" <agent> <event>`, plus `--timeout <seconds>` for PermissionRequest.
    static func command(hookPath: String, agent: AgentHookTarget, event: AgentHookEvent, wait: Int) -> String {
        var command = "\(shellQuoted(hookPath)) \(agent.rawValue) \(event.name)"
        if event.waitsForDecision { command += " --timeout \(wait)" }
        return command
    }

    /// The handler's `timeout` field for an event.
    static func timeout(for event: AgentHookEvent, wait: Int) -> Int? {
        event.waitsForDecision ? wait + permissionTimeoutMargin : event.timeout
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
