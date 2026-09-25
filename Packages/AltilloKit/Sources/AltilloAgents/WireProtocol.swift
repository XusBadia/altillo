import AltilloCore
import Foundation

// The hook <-> app protocol: newline-delimited JSON over a Unix socket, one connection per hook call.
//
//   hook → app  {"v":1,"agent":"claude","event":"PreToolUse","payload":{…stdin…},"env":{…},"ppids":[…],
//                "tty":"/dev/ttys003","agentPID":123,"waitsForDecision":false,"requestID":null,"timeout":null}
//   app → hook  {"requestID":"…","decision":"allow|allowForSession|deny|none"}   (only when waitsForDecision)
//
// Versioned by `v`; both sides ignore fields they don't know, so the hook inside an older Altillo.app keeps
// working with a newer app and the other way round.

/// The user's answer as it travels back to the hook. `none` = no decision: the agent asks in the terminal.
public enum WireDecision: String, Codable, Sendable, CaseIterable {
    case allow, allowForSession, deny, none

    public init(_ decision: AgentDecision) {
        switch decision {
        case .allow: self = .allow
        case .allowForSession: self = .allowForSession
        case .deny: self = .deny
        }
    }

    /// Unknown strings from a newer app decode as `none` (never as an approval).
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireDecision(rawValue: raw) ?? .none
    }
}

/// One hook call.
public struct HookEnvelope: Codable, Sendable, Hashable {
    public static let currentVersion = 1
    /// Environment variables that identify the terminal/editor tab. Nothing else from the environment is sent.
    public static let forwardedEnvironment: [String] = [
        "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID", "ITERM_SESSION_ID", "KITTY_WINDOW_ID",
        "KITTY_PID", "WEZTERM_PANE", "WEZTERM_UNIX_SOCKET", "ALACRITTY_WINDOW_ID", "GHOSTTY_RESOURCES_DIR",
        "WARP_IS_LOCAL_SHELL_SESSION", "ZED_TERM", "TMUX", "TMUX_PANE", "STY", "VSCODE_PID", "VSCODE_INJECTION",
        "VSCODE_GIT_IPC_HANDLE", "CURSOR_TRACE_ID", "TERMINAL_EMULATOR", "__CFBundleIdentifier", "CLAUDE_PID",
        "CLAUDE_CODE_ENTRYPOINT", "CODEX_THREAD_ID",
    ]

    public var v: Int
    public var agent: String
    public var event: String
    public var payload: JSONValue
    public var env: [String: String]
    /// Parent pid chain, nearest first (the agent, its terminal shell, the terminal app…).
    public var ppids: [Int32]
    /// The controlling terminal of the nearest ancestor that has one ("/dev/ttys003"). Hooks themselves run
    /// without a controlling terminal.
    public var tty: String?
    /// The agent's own process (first non-shell ancestor).
    public var agentPID: Int32?
    public var waitsForDecision: Bool
    public var requestID: String?
    /// Seconds the hook waits for a decision.
    public var timeout: Double?

    public init(agent: String, event: String, payload: JSONValue, env: [String: String] = [:], ppids: [Int32] = [],
                tty: String? = nil, agentPID: Int32? = nil, waitsForDecision: Bool = false, requestID: String? = nil,
                timeout: Double? = nil) {
        v = Self.currentVersion
        self.agent = agent
        self.event = event
        self.payload = payload
        self.env = env
        self.ppids = ppids
        self.tty = tty
        self.agentPID = agentPID
        self.waitsForDecision = waitsForDecision
        self.requestID = requestID
        self.timeout = timeout
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = (try? c.decode(Int.self, forKey: .v)) ?? 1
        agent = try c.decode(String.self, forKey: .agent)
        event = try c.decode(String.self, forKey: .event)
        payload = (try? c.decode(JSONValue.self, forKey: .payload)) ?? .null
        env = (try? c.decode([String: String].self, forKey: .env)) ?? [:]
        ppids = (try? c.decode([Int32].self, forKey: .ppids)) ?? []
        tty = try? c.decode(String.self, forKey: .tty)
        agentPID = try? c.decode(Int32.self, forKey: .agentPID)
        waitsForDecision = (try? c.decode(Bool.self, forKey: .waitsForDecision)) ?? false
        requestID = try? c.decode(String.self, forKey: .requestID)
        timeout = try? c.decode(Double.self, forKey: .timeout)
    }
}

/// The app's answer to a waiting hook.
public struct HookReply: Codable, Sendable, Hashable {
    public var requestID: String
    public var decision: WireDecision

    public init(requestID: String, decision: WireDecision) {
        self.requestID = requestID
        self.decision = decision
    }
}

/// Where the socket lives and how messages are framed.
public enum AgentWire {
    /// Tests and side-by-side builds point both ends elsewhere with this variable.
    public static let socketPathEnvironment = "ALTILLO_AGENTS_SOCKET"
    /// Seconds a PermissionRequest hook waits for the notch (overridable per hook with `--timeout`).
    public static let timeoutEnvironment = "ALTILLO_HOOK_TIMEOUT"
    public static let defaultDecisionTimeout: Double = 120

    /// `~/Library/Application Support/Altillo`, the socket's owner-only (0700) directory.
    public static func supportDirectory(home: String = NSHomeDirectory()) -> String {
        home + "/Library/Application Support/Altillo"
    }

    /// `~/Library/Application Support/Altillo/agents.sock`, or `$ALTILLO_AGENTS_SOCKET`.
    public static func socketPath(environment: [String: String] = ProcessInfo.processInfo.environment,
                                  home: String = NSHomeDirectory()) -> String {
        if let override = environment[socketPathEnvironment], !override.isEmpty { return override }
        return supportDirectory(home: home) + "/agents.sock"
    }

    /// One JSON object per line. JSONEncoder never emits a raw newline, so the frame can't break.
    public static func frame<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard var data = try? encoder.encode(value) else { return nil }
        data.append(0x0A)
        return data
    }

    public static func decodeEnvelope(_ line: Data) -> HookEnvelope? {
        try? JSONDecoder().decode(HookEnvelope.self, from: line)
    }

    public static func decodeReply(_ line: Data) -> HookReply? {
        try? JSONDecoder().decode(HookReply.self, from: line)
    }
}

/// Splits a byte stream into lines.
public struct LineBuffer: Sendable {
    private var buffer = Data()
    /// Refuse to buffer more than this without a newline (a broken or hostile peer).
    public let limit: Int

    public init(limit: Int = 16 << 20) { self.limit = limit }

    public var isOverLimit: Bool { buffer.count > limit }

    /// Appends bytes and returns every complete line (without the newline).
    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines.map { Data($0) }
    }
}
