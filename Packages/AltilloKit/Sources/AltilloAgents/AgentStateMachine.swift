import AltilloCore
import Foundation

/// How events move a session between phases. Pure: the hub feeds it events, session-file snapshots and the clock,
/// and posts an alert for every transition.
///
///     SessionStart ─────────────► idle
///     UserPromptSubmit / tools ──► working ("Running `swift test`", "Editing NotchModel.swift")
///     PermissionRequest ─────────► waitingPermission (+ the request card)
///     AskUserQuestion, idle/input notifications, Stop ─► waitingAnswer (+ last message)
///     StopFailure ───────────────► failed        SessionEnd ─► finished
public enum AgentStateMachine {
    /// Applies one hook event. `permission` is the card for a `.permissionRequested` event (built by the hub with
    /// the wire request id); `host` is where the hook says the agent runs.
    public static func apply(_ event: AgentEvent, to current: AgentSession?, at now: Date,
                             permission: AgentPermissionRequest? = nil, host: AgentHost? = nil) -> AgentSession {
        var session = current ?? AgentSession(
            agent: event.agent, sessionID: event.sessionID, cwd: event.cwd ?? "", phase: .idle,
            startedAt: now, lastActivity: now, source: .hooks)
        session.source = .hooks
        session.lastActivity = now
        if let cwd = event.cwd, !cwd.isEmpty, cwd != session.cwd, event.subagentID == nil {
            session.setCWD(cwd)
        }
        if let host { session.host = session.host?.merged(with: host) ?? host }

        switch event.kind {
        case .sessionStarted(let source):
            if source == "compact" {
                session.phase = .working
                session.activity = "Compacting the conversation"
            } else if current == nil || session.phase == .finished || session.phase == .failed {
                session.phase = .idle
                session.activity = nil
            }

        case .sessionEnded:
            session.phase = .finished
            session.activity = nil
            session.pendingRequest = nil

        case .promptSubmitted:
            session.phase = .working
            session.activity = "Thinking"
            session.pendingRequest = nil
            session.lastMessage = nil

        case .toolWillRun(let call):
            guard !session.isBlockedOnPermission else { break }
            if let question = ToolDescriptions.question(in: call) {
                session.phase = .waitingAnswer
                session.activity = ToolDescriptions.activity(for: call, cwd: session.cwd)
                session.lastMessage = question
            } else {
                session.phase = .working
                session.activity = ToolDescriptions.activity(for: call, cwd: session.cwd)
            }

        case .toolDidRun(let call, _):
            if let pending = session.pendingRequest, pending.matches(call, cwd: session.cwd) {
                session.pendingRequest = nil
            }
            guard !session.isBlockedOnPermission else { break }
            session.phase = .working
            // The model is thinking about the result until the next tool or the end of the turn.
            session.activity = event.subagentID == nil ? "Thinking" : session.activity

        case .permissionRequested(let call, let suggestions):
            let request = permission ?? ToolDescriptions.permissionRequest(
                id: UUID().uuidString, agent: event.agent, call: call, suggestions: suggestions, cwd: session.cwd,
                requestedAt: now, expiresAt: nil)
            session.phase = .waitingPermission
            session.pendingRequest = request
            session.activity = ToolDescriptions.activity(for: call, cwd: session.cwd)

        case .notification(let type, let message, _):
            switch type {
            case "permission_prompt":
                // Asked in the terminal (PermissionRequest hook not installed, or a sandbox network prompt).
                if session.pendingRequest == nil || session.pendingRequest?.isExpired == true {
                    session.phase = .waitingPermission
                }
            case "idle_prompt":
                if session.phase != .waitingPermission { session.phase = .waitingAnswer }
            case "agent_needs_input", "elicitation_dialog", "elicitation_url_dialog":
                if session.phase != .waitingPermission {
                    session.phase = .waitingAnswer
                    if let message, !message.isEmpty { session.lastMessage = message }
                }
            default:
                break
            }

        case .turnFinished(let lastMessage):
            session.phase = .waitingAnswer
            session.activity = nil
            session.pendingRequest = nil
            if let lastMessage { session.lastMessage = lastMessage }

        case .turnFailed(let error, let message):
            session.phase = .failed
            session.activity = nil
            session.pendingRequest = nil
            session.lastMessage = message ?? error.map(Self.describeFailure)

        case .subagentStarted(let type):
            guard !session.isBlockedOnPermission else { break }
            session.phase = .working
            session.activity = type.map { "Running the \($0) agent" } ?? "Running a subagent"

        case .subagentFinished:
            guard !session.isBlockedOnPermission else { break }
            if session.phase != .waitingAnswer { session.phase = .working }

        case .assistantMessage(let text):
            session.lastMessage = text

        case .interrupted:
            session.phase = .idle
            session.activity = nil
            session.pendingRequest = nil

        case .compacting(let done):
            guard !session.isBlockedOnPermission else { break }
            session.phase = .working
            session.activity = done ? "Thinking" : "Compacting the conversation"

        case .other:
            break
        }
        return session
    }

    /// The user answered (or the hook stopped waiting): drop `requestID`, show `next` if another is queued.
    public static func resolvePermission(_ requestID: String, in session: AgentSession, next: AgentPermissionRequest?,
                                         decision: AgentDecision?, at now: Date) -> AgentSession {
        var session = session
        guard session.pendingRequest?.id == requestID else { return session }
        session.pendingRequest = next
        session.lastActivity = now
        if next != nil {
            session.phase = .waitingPermission
        } else {
            session.phase = .working
            if decision == .deny { session.activity = "Thinking" }
        }
        return session
    }

    /// The hook gave up waiting (timeout): the agent now asks in the terminal, so the session still needs the user
    /// but the notch can't answer any more.
    public static func expirePermission(_ requestID: String, in session: AgentSession, at now: Date) -> AgentSession {
        var session = session
        guard session.pendingRequest?.id == requestID else { return session }
        session.pendingRequest?.isExpired = true
        return session
    }

    /// Merges what the session file shows. Hooks win: a hook-fed session only takes the file's view when the file
    /// is clearly ahead of the last hook event (hooks removed mid-session), and otherwise just fills blanks.
    public static func apply(_ snapshot: SessionFileSnapshot, to current: AgentSession?) -> AgentSession {
        guard var session = current else {
            var session = AgentSession(
                agent: snapshot.agent, sessionID: snapshot.sessionID, cwd: snapshot.cwd, phase: snapshot.phase,
                activity: snapshot.activity, startedAt: snapshot.startedAt ?? snapshot.lastActivity,
                lastActivity: snapshot.lastActivity, lastMessage: snapshot.lastMessage, source: .sessionFile)
            if snapshot.cwd.isEmpty { session.project = snapshot.projectHint ?? "" }
            return session
        }
        if session.cwd.isEmpty, !snapshot.cwd.isEmpty { session.setCWD(snapshot.cwd) }
        let fileIsAhead = snapshot.lastActivity.timeIntervalSince(session.lastActivity) > hookGrace
        if session.source == .hooks && !fileIsAhead {
            if session.lastMessage == nil, session.phase == .waitingAnswer || session.phase == .finished {
                session.lastMessage = snapshot.lastMessage
            }
            return session
        }
        guard snapshot.lastActivity >= session.lastActivity || session.source == .sessionFile else { return session }
        if session.isBlockedOnPermission {
            session.lastActivity = max(session.lastActivity, snapshot.lastActivity)
            return session
        }
        session.phase = snapshot.phase
        session.activity = snapshot.activity
        if snapshot.lastMessage != nil || snapshot.phase == .working { session.lastMessage = snapshot.lastMessage }
        session.lastActivity = max(session.lastActivity, snapshot.lastActivity)
        if session.phase != .waitingPermission { session.pendingRequest = nil }
        return session
    }

    /// How far a session file may run ahead of the hooks before the file's view wins.
    public static let hookGrace: TimeInterval = 90

    static func describeFailure(_ error: String) -> String {
        switch error {
        case "rate_limit": "Rate limit reached"
        case "overloaded": "The API is overloaded"
        case "authentication_failed", "oauth_org_not_allowed": "Authentication failed"
        case "billing_error", "account_on_hold": "Billing problem"
        case "max_output_tokens": "Hit the output limit"
        case "server_error": "API server error"
        default: "The turn failed"
        }
    }
}

/// When quiet sessions go idle, when finished ones leave the list.
public enum AgentSessionAging {
    /// A working or waiting session with no news for this long is shown as idle.
    public static let staleAfter: TimeInterval = 10 * 60
    /// Idle, finished and failed sessions leave the list this long after their last activity.
    public static let dropAfter: TimeInterval = 30 * 60

    /// The session as it should look at `now`, or nil to drop it. `processAlive` is nil when unknown.
    public static func age(_ session: AgentSession, now: Date, processAlive: Bool?) -> AgentSession? {
        var session = session
        let quiet = now.timeIntervalSince(session.lastActivity)
        if processAlive == false, session.phase != .finished {
            session.phase = .finished
            session.activity = nil
            session.pendingRequest = nil
        }
        if let request = session.pendingRequest, !request.isExpired, let expiry = request.expiresAt, now >= expiry {
            session.pendingRequest?.isExpired = true
        }
        if let expiry = session.reply?.expiresAt, now >= expiry {
            // The stop hook gave up: the agent stopped as usual and takes its next message in the terminal.
            session.reply = nil
        }
        if session.phase == .finished || session.phase == .failed { session.reply = nil }
        switch session.phase {
        case .working, .waitingAnswer, .waitingPermission:
            if session.isBlockedOnPermission { return session }
            if quiet >= staleAfter {
                session.phase = .idle
                session.activity = nil
                session.pendingRequest = nil
            }
        case .idle, .finished, .failed:
            break
        }
        if !session.phase.isActive, quiet >= dropAfter { return nil }
        return session
    }

    /// When `age` would next change something (nil: never on its own).
    public static func nextDeadline(_ session: AgentSession) -> Date? {
        var deadlines: [Date] = []
        if let request = session.pendingRequest, !request.isExpired, let expiry = request.expiresAt {
            deadlines.append(expiry)
        }
        if let expiry = session.reply?.expiresAt { deadlines.append(expiry) }
        switch session.phase {
        case .working, .waitingAnswer, .waitingPermission:
            if !session.isBlockedOnPermission {
                deadlines.append(session.lastActivity.addingTimeInterval(staleAfter))
            }
        case .idle, .finished, .failed:
            deadlines.append(session.lastActivity.addingTimeInterval(dropAfter))
        }
        return deadlines.min()
    }
}

/// Sort order for the notch: the ones that need you, then working, then the rest; newest first within a group.
public enum AgentSessionOrder {
    public static func rank(_ phase: AgentPhase) -> Int {
        switch phase {
        case .waitingPermission: 0
        case .waitingAnswer: 1
        case .working: 2
        case .failed: 3
        case .idle: 4
        case .finished: 5
        }
    }

    public static func sorted(_ sessions: [AgentSession]) -> [AgentSession] {
        sessions.sorted {
            let (a, b) = (rank($0.phase), rank($1.phase))
            if a != b { return a < b }
            if $0.lastActivity != $1.lastActivity { return $0.lastActivity > $1.lastActivity }
            return $0.id < $1.id
        }
    }
}

extension AgentSession {
    /// Waiting on a live permission request the notch can still answer.
    public var isBlockedOnPermission: Bool {
        phase == .waitingPermission && pendingRequest.map { !$0.isExpired } == true
    }

    mutating func setCWD(_ cwd: String) {
        self.cwd = cwd
        project = URL(fileURLWithPath: cwd).lastPathComponent
    }
}

extension AgentHost {
    /// Fills blanks in `self` from `other` (a later hook knows the same or more).
    func merged(with other: AgentHost) -> AgentHost {
        AgentHost(appBundleID: other.appBundleID ?? appBundleID, appName: other.appName ?? appName,
                  terminalProgram: other.terminalProgram ?? terminalProgram,
                  terminalSessionID: other.terminalSessionID ?? terminalSessionID, tty: other.tty ?? tty,
                  pid: other.pid ?? pid)
    }
}

extension AgentPermissionRequest {
    /// Whether a finished tool call is the one this request asked about (PermissionRequest has no tool_use_id).
    func matches(_ call: AgentToolCall, cwd: String) -> Bool {
        guard call.name == toolName else { return false }
        if let command = call.command { return command.firstLine(limit: 120) == summary }
        let files = call.filePaths.map { $0.displayPath(relativeTo: cwd) }.joined(separator: ", ")
        return files.isEmpty || files == summary
    }
}
