import Foundation

// Shared live-agents model (PLAN §5.3, phase 4). The engine (AltilloAgents + the app's hub) produces it from hook
// events and session files, the notch and Ask read it, and later the iPhone companion gets it, so it is plain
// Codable/Sendable data with no platform code.

/// A coding agent Altillo can follow. Raw values are stable (persisted, synced, used in settings and the hook CLI).
public struct AgentKind: RawRepresentable, Hashable, Codable, Sendable, Comparable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let claude = AgentKind(rawValue: "claude")
    public static let codex = AgentKind(rawValue: "codex")
    /// Gemini CLI (hooks in `~/.gemini/settings.json`), phase 14.
    public static let gemini = AgentKind(rawValue: "gemini")
    /// GitHub Copilot CLI (hooks in `~/.copilot/hooks/*.json`), phase 14.
    public static let copilot = AgentKind(rawValue: "copilot")
    /// OpenCode, followed through the HTTP server of `opencode serve`, phase 14.
    public static let opencode = AgentKind(rawValue: "opencode")
    /// Cursor's CLI (`cursor-agent`) and editor, hooks in `~/.cursor/hooks.json`, phase 14.
    public static let cursor = AgentKind(rawValue: "cursor")

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What a session is doing, as the notch shows it.
public enum AgentPhase: String, Codable, Sendable, CaseIterable {
    /// Thinking or running tools.
    case working
    /// Blocked on a permission the user has to give (`AgentSession.pendingRequest`).
    case waitingPermission
    /// Finished its turn and is waiting for the user's next message.
    case waitingAnswer
    /// Open but quiet (no turn in progress, nothing asked).
    case idle
    /// The session ended.
    case finished
    /// The last turn failed (API error, crash).
    case failed

    /// The user has to do something.
    public var needsUser: Bool { self == .waitingPermission || self == .waitingAnswer }
    public var isActive: Bool { self == .working || needsUser }
}

/// Where the session lives, so "Go to terminal" can bring it forward.
public struct AgentHost: Hashable, Codable, Sendable {
    /// The app hosting the terminal (Terminal, iTerm2, Ghostty, VS Code, Cursor…).
    public var appBundleID: String?
    public var appName: String?
    /// `TERM_PROGRAM`, iTerm2's `ITERM_SESSION_ID`, the tty… whatever identifies the tab.
    public var terminalProgram: String?
    public var terminalSessionID: String?
    public var tty: String?
    /// The agent's own process, when known.
    public var pid: Int32?

    public init(appBundleID: String? = nil, appName: String? = nil, terminalProgram: String? = nil,
                terminalSessionID: String? = nil, tty: String? = nil, pid: Int32? = nil) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.terminalProgram = terminalProgram
        self.terminalSessionID = terminalSessionID
        self.tty = tty
        self.pid = pid
    }
}

/// A permission an agent is waiting for.
public struct AgentPermissionRequest: Identifiable, Hashable, Codable, Sendable {
    /// Unique per request (the hook waits on it).
    public var id: String
    /// "Bash", "Edit", "apply_patch"…
    public var toolName: String
    /// One line: the command, or the file being changed.
    public var summary: String
    /// More: the full command, a diff excerpt, the reason the agent gave.
    public var detail: String?
    /// Matches a dangerous pattern (`rm -rf`, `git push --force`…): the notch asks for an extra confirmation.
    public var isDangerous: Bool
    /// The agent offered "don't ask again for this session" (Claude's permission suggestions).
    public var canAllowForSession: Bool
    public var requestedAt: Date
    /// When the hook gives up and the agent falls back to asking in the terminal.
    public var expiresAt: Date?
    /// The hook stopped waiting (timed out): the agent asks in the terminal now and the notch can't answer it.
    public var isExpired: Bool
    /// The last answer from the notch didn't reach the agent (OpenCode's server refused it or is gone): shown on the
    /// card, which stays answerable.
    public var failure: String?

    public init(id: String, toolName: String, summary: String, detail: String? = nil, isDangerous: Bool = false,
                canAllowForSession: Bool = false, requestedAt: Date, expiresAt: Date? = nil, isExpired: Bool = false) {
        self.id = id
        self.toolName = toolName
        self.summary = summary
        self.detail = detail
        self.isDangerous = isDangerous
        self.canAllowForSession = canAllowForSession
        self.requestedAt = requestedAt
        self.expiresAt = expiresAt
        self.isExpired = isExpired
    }
}

/// The user's answer to a permission request. Altillo never decides on its own.
public enum AgentDecision: String, Codable, Sendable {
    case allow
    /// Allow and don't ask again for the same thing in this session (only when the agent offers it).
    case allowForSession
    case deny
}

/// How a reply typed in the notch reaches a session that is waiting for the user's next message (phase 14).
/// Altillo never writes to an agent on its own: a reply only goes out when the user sends one.
public struct AgentReplyChannel: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The agent's stop hook is holding the end of the turn open (opt-in per agent); the reply makes the agent
        /// carry on with it. Closes when the hook gives up (`expiresAt`), the user answers in the terminal, or the
        /// agent is interrupted.
        case stopHook
        /// The agent's own server takes new messages (OpenCode's `prompt_async`): no deadline.
        case server
    }

    public var kind: Kind
    /// The waiting hook's request id (`stopHook`), or the session id (`server`).
    public var id: String
    public var openedAt: Date
    /// When the hook stops waiting and the agent stops as usual. nil: no limit.
    public var expiresAt: Date?
    /// A reply didn't get through (the hook had just given up): the field stays, saying so, with the typed text,
    /// until the session changes. Nothing more can be sent through it.
    public var isClosed: Bool

    public init(kind: Kind, id: String, openedAt: Date, expiresAt: Date? = nil, isClosed: Bool = false) {
        self.kind = kind
        self.id = id
        self.openedAt = openedAt
        self.expiresAt = expiresAt
        self.isClosed = isClosed
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        id = try c.decode(String.self, forKey: .id)
        openedAt = try c.decode(Date.self, forKey: .openedAt)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        isClosed = try c.decodeIfPresent(Bool.self, forKey: .isClosed) ?? false
    }
}

/// One agent session.
public struct AgentSession: Identifiable, Hashable, Codable, Sendable {
    /// "<agent>:<session id>", stable for the session's life.
    public var id: String
    public var agent: AgentKind
    public var sessionID: String
    /// The working directory's name ("altillo").
    public var project: String
    public var cwd: String
    public var phase: AgentPhase
    /// What it's doing right now, in a few words ("Running `swift test`", "Editing NotchModel.swift").
    public var activity: String?
    public var startedAt: Date
    public var lastActivity: Date
    public var pendingRequest: AgentPermissionRequest?
    /// The start of its last message to the user (what it finished with, what it asks).
    public var lastMessage: String?
    public var host: AgentHost?
    /// Seen through hooks (precise, can approve) or only through its session file (read-only, approximate).
    public var source: Source
    /// Set while a reply typed in the notch can reach the session (phase 14).
    public var reply: AgentReplyChannel?

    public enum Source: String, Codable, Sendable {
        case hooks, sessionFile
        /// The agent's own local server (OpenCode): precise, and it can take answers.
        case server
    }

    public init(agent: AgentKind, sessionID: String, cwd: String, phase: AgentPhase, activity: String? = nil,
                startedAt: Date, lastActivity: Date, pendingRequest: AgentPermissionRequest? = nil,
                lastMessage: String? = nil, host: AgentHost? = nil, source: Source, reply: AgentReplyChannel? = nil) {
        id = "\(agent.rawValue):\(sessionID)"
        self.agent = agent
        self.sessionID = sessionID
        self.cwd = cwd
        project = URL(fileURLWithPath: cwd).lastPathComponent
        self.phase = phase
        self.activity = activity
        self.startedAt = startedAt
        self.lastActivity = lastActivity
        self.pendingRequest = pendingRequest
        self.lastMessage = lastMessage
        self.host = host
        self.source = source
        self.reply = reply
    }
}
