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

    public enum Source: String, Codable, Sendable {
        case hooks, sessionFile
    }

    public init(agent: AgentKind, sessionID: String, cwd: String, phase: AgentPhase, activity: String? = nil,
                startedAt: Date, lastActivity: Date, pendingRequest: AgentPermissionRequest? = nil,
                lastMessage: String? = nil, host: AgentHost? = nil, source: Source) {
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
    }
}
