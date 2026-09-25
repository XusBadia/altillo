import AltilloCore
import Foundation

// How the notch talks about live agents (PLAN §5.3): names, phases, the order of the list, the header's summary,
// the ear's figure and the contextual ear's signal. Pure, so tests pin the wording and the choices.

extension AgentKind {
    /// "Claude", "Codex"; any other agent by its id, capitalised.
    var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

extension AgentPhase {
    /// The phase chip's word.
    var title: String {
        switch self {
        case .working: String(localized: "Working")
        case .waitingPermission: String(localized: "Waiting for permission")
        case .waitingAnswer: String(localized: "Waiting for your answer")
        case .idle: String(localized: "Idle")
        case .finished: String(localized: "Done")
        case .failed: String(localized: "Error")
        }
    }
}

extension NotchModel {
    /// The sessions the agents views show: the sample ones in design scenarios, the hub's otherwise.
    var agentSessions: [AgentSession] {
        scenario != nil ? demo.agents : agentHub.sessions
    }
}

enum AgentsLogic {
    /// Waiting for the user first (a permission before a question, the one that will give up soonest first), then
    /// working, then quiet ones, then finished or failed; the most recent first within each group.
    static func ordered(_ sessions: [AgentSession]) -> [AgentSession] {
        sessions.sorted { lhs, rhs in
            let (left, right) = (rank(lhs.phase), rank(rhs.phase))
            if left != right { return left < right }
            if lhs.phase == .waitingPermission, let a = deadline(lhs), let b = deadline(rhs), a != b { return a < b }
            return lhs.lastActivity > rhs.lastActivity
        }
    }

    private static func rank(_ phase: AgentPhase) -> Int {
        switch phase {
        case .waitingPermission: 0
        case .waitingAnswer: 1
        case .working: 2
        case .idle: 3
        case .failed: 4
        case .finished: 5
        }
    }

    private static func deadline(_ session: AgentSession) -> Date? {
        session.pendingRequest?.expiresAt ?? session.pendingRequest?.requestedAt
    }

    /// The session the big card is about: the one the user picked if it still needs them, else the first waiting.
    static func featured(in sessions: [AgentSession], preferring id: AgentSession.ID? = nil) -> AgentSession? {
        let ordered = ordered(sessions)
        if let id, let picked = ordered.first(where: { $0.id == id && $0.phase.needsUser }) { return picked }
        return ordered.first { $0.phase.needsUser }
    }

    struct Counts: Equatable, Sendable {
        var waiting: Int
        var working: Int

        var active: Int { waiting + working }
    }

    static func counts(_ sessions: [AgentSession]) -> Counts {
        Counts(waiting: sessions.count { $0.phase.needsUser }, working: sessions.count { $0.phase == .working })
    }

    /// The header's summary: "1 knocking · 2 working", or nil when nobody is doing anything.
    static func summary(_ counts: Counts) -> String? {
        var parts: [String] = []
        if counts.waiting > 0 { parts.append(String(localized: "\(counts.waiting) knocking")) }
        if counts.working > 0 { parts.append(String(localized: "\(counts.working) working")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What VoiceOver reads for the agents ear.
    static func earAccessibilityLabel(_ counts: Counts) -> String {
        switch (counts.working, counts.waiting) {
        case (0, 0): String(localized: "No agents working")
        case let (working, 0): String(localized: "\(working) agents working")
        case let (0, waiting): String(localized: "\(waiting) agents waiting for you")
        case let (working, waiting): String(localized: "\(working) agents working, \(waiting) waiting for you")
        }
    }

    /// The contextual ear's agent: the first one waiting for the user.
    static func requestSignal(in sessions: [AgentSession]) -> AgentRequestSignal? {
        guard let session = featured(in: sessions) else { return nil }
        return AgentRequestSignal(agentName: session.agent.name, project: session.project.isEmpty ? nil : session.project)
    }

    /// The card's opening line: "Claude wants to run a command", "Codex is asking you something".
    static func ask(for session: AgentSession) -> String {
        guard session.phase == .waitingPermission else {
            return String(localized: "\(session.agent.name) is waiting for your answer")
        }
        guard let request = session.pendingRequest else {
            return String(localized: "\(session.agent.name) wants your OK")
        }
        switch ToolAction(toolName: request.toolName) {
        case .run: return String(localized: "\(session.agent.name) wants to run a command")
        case .edit: return String(localized: "\(session.agent.name) wants to change a file")
        case .read: return String(localized: "\(session.agent.name) wants to read a file")
        case .web: return String(localized: "\(session.agent.name) wants to go online")
        case .other: return String(localized: "\(session.agent.name) wants to use \(request.toolName)")
        }
    }

    /// Seconds left before the hook gives up (the agent then asks in the terminal), 0 once it has.
    static func secondsLeft(_ request: AgentPermissionRequest, now: Date) -> TimeInterval? {
        if request.isExpired { return 0 }
        guard let expiresAt = request.expiresAt else { return nil }
        return max(0, expiresAt.timeIntervalSince(now))
    }

    /// The notch can no longer answer it: the hook gave up and the agent asks in the terminal.
    static func isExpired(_ request: AgentPermissionRequest, now: Date) -> Bool {
        request.isExpired || (secondsLeft(request, now: now).map { $0 <= 0 } ?? false)
    }

    /// How much of the wait is left, 1 … 0, for the countdown ring.
    static func remainingFraction(_ request: AgentPermissionRequest, now: Date) -> Double? {
        guard let expiresAt = request.expiresAt else { return nil }
        let total = expiresAt.timeIntervalSince(request.requestedAt)
        guard total > 0 else { return 0 }
        return min(max(expiresAt.timeIntervalSince(now) / total, 0), 1)
    }

    /// "1:52", "0:07": the countdown's figure.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// Words from the start of a message, on one line and free of Markdown, cut at a word near `limit` with "…".
    static func excerpt(_ message: String?, limit: Int = 60) -> String? {
        guard let message else { return nil }
        let plain = message
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#>-*• ")) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !plain.isEmpty else { return nil }
        guard plain.count > limit else { return plain }
        let cut = plain.prefix(limit)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:—-")) + "…"
    }

    /// Whether the agent's last message asks the user something (rather than reporting it finished).
    static func isQuestion(_ message: String?) -> Bool {
        guard let message else { return false }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasSuffix("?") || trimmed.hasSuffix("?)") { return true }
        // A question in its last paragraph ("Should I push it? Let me know.").
        let lastParagraph = trimmed.split(whereSeparator: \.isNewline).last.map(String.init) ?? trimmed
        return lastParagraph.contains("?")
    }
}

/// What a permission's tool does, in the user's terms.
enum ToolAction: Equatable, Sendable {
    case run, edit, read, web, other

    init(toolName: String) {
        switch toolName.lowercased() {
        case "bash", "shell", "exec", "exec_command", "local_shell", "run", "terminal", "killshell", "bashoutput":
            self = .run
        case "edit", "multiedit", "write", "notebookedit", "apply_patch", "applypatch", "patch", "str_replace_editor":
            self = .edit
        case "read", "glob", "grep", "ls", "view":
            self = .read
        case "webfetch", "websearch", "fetch", "web_search", "browser":
            self = .web
        default:
            self = .other
        }
    }
}
