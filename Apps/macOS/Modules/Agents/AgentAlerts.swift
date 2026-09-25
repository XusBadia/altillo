import AltilloCore
import Foundation

/// Which peek a session's change deserves (PLAN §5.8): a permission asked ("Knock, knock"), a question, a
/// finished turn, a failure. Pure, so the hub calls it on every transition and tests pin the wording.
///
/// - A session seen for the first time only peeks if it's already waiting for the user, and only if it started
///   waiting recently (Altillo launching next to five open sessions mustn't knock five times).
/// - The same permission request never peeks twice; a new request in the same session does.
/// - Staying in a phase never peeks again (a working session's activity changing, a question's text updating).
enum AgentAlerts {
    /// A session first seen waiting only knocks if it started waiting within this long.
    static let freshness: TimeInterval = 2 * 60

    /// `previous` is nil for a session seen for the first time.
    static func alert(from previous: AgentSession?, to current: AgentSession, now: Date = .now) -> NotchAlert? {
        switch current.phase {
        case .waitingPermission:
            if let request = current.pendingRequest {
                guard previous?.pendingRequest?.id != request.id, !request.isExpired else { return nil }
                if previous == nil, now.timeIntervalSince(request.requestedAt) > freshness { return nil }
                return permission(current, request: request)
            }
            // Only the session file says it's blocked (no hook to tell what on).
            guard previous?.phase != .waitingPermission, isFresh(current, previous: previous, now: now) else { return nil }
            return permission(current, request: nil)
        case .waitingAnswer:
            guard previous?.phase != .waitingAnswer, isFresh(current, previous: previous, now: now) else { return nil }
            return AgentsLogic.isQuestion(current.lastMessage) ? question(current) : finished(current)
        case .idle:
            // A turn that ended without asking anything: done.
            guard previous?.phase == .working else { return nil }
            return finished(current)
        case .finished:
            // Only when it ends straight from working; after a question or a finished turn it has said it all.
            guard let previous, previous.phase == .working || previous.phase == .waitingPermission else { return nil }
            return finished(current)
        case .failed:
            guard previous?.phase != .failed, isFresh(current, previous: previous, now: now) else { return nil }
            return failed(current)
        case .working:
            return nil
        }
    }

    private static func isFresh(_ session: AgentSession, previous: AgentSession?, now: Date) -> Bool {
        previous != nil || now.timeIntervalSince(session.lastActivity) <= freshness
    }

    // MARK: Alerts

    static func permission(_ session: AgentSession, request: AgentPermissionRequest?) -> NotchAlert {
        let dangerous = request?.isDangerous ?? false
        let (verb, object) = request.map(phrase(for:)) ?? (nil, nil)
        let name = session.agent.name
        let project = session.project
        let action: String = switch (verb, object) {
        case let (verb?, object?): String(localized: "\(name) wants to \(verb) \(object) in \(project)")
        case let (verb?, nil): String(localized: "\(name) wants to \(verb) something in \(project)")
        default: String(localized: "\(name) wants your OK in \(project)")
        }
        let title = dangerous
            ? String(localized: "Careful: \(action)")
            : String(localized: "Knock, knock: \(action)")
        return NotchAlert(
            source: .agents,
            symbol: dangerous ? "exclamationmark.triangle.fill" : "hand.raised.fill",
            title: title,
            detail: dangerous ? String(localized: "Hold Allow to confirm") : nil,
            isUrgent: true,
            module: .agents,
            duration: .seconds(8),
            agent: AgentAlertContext(kind: .permission(dangerous: dangerous), agent: session.agent, project: project,
                                     verb: verb, object: object, excerpt: nil, sessionID: session.id,
                                     requestID: request?.id)
        )
    }

    static func question(_ session: AgentSession) -> NotchAlert {
        let excerpt = AgentsLogic.excerpt(session.lastMessage)
        return NotchAlert(
            source: .agents,
            symbol: "questionmark.bubble.fill",
            title: String(localized: "\(session.agent.name) is asking you something in \(session.project)"),
            detail: excerpt,
            isUrgent: true,
            module: .agents,
            duration: .seconds(6),
            agent: AgentAlertContext(kind: .question, agent: session.agent, project: session.project,
                                     excerpt: excerpt, sessionID: session.id)
        )
    }

    static func finished(_ session: AgentSession) -> NotchAlert {
        let excerpt = AgentsLogic.excerpt(session.lastMessage)
        return NotchAlert(
            source: .agents,
            symbol: "checkmark.seal.fill",
            title: String(localized: "\(session.agent.name) finished in \(session.project)"),
            detail: excerpt,
            module: .agents,
            duration: .seconds(5),
            agent: AgentAlertContext(kind: .finished, agent: session.agent, project: session.project,
                                     excerpt: excerpt, sessionID: session.id)
        )
    }

    static func failed(_ session: AgentSession) -> NotchAlert {
        let excerpt = AgentsLogic.excerpt(session.lastMessage)
        return NotchAlert(
            source: .agents,
            symbol: "exclamationmark.triangle.fill",
            title: String(localized: "\(session.agent.name) failed in \(session.project)"),
            detail: excerpt,
            module: .agents,
            duration: .seconds(6),
            agent: AgentAlertContext(kind: .failed, agent: session.agent, project: session.project,
                                     excerpt: excerpt, sessionID: session.id)
        )
    }

    // MARK: Wording

    /// "run" + "git push", "change" + "NotchModel.swift", "use" + "WebFetch".
    static func phrase(for request: AgentPermissionRequest) -> (verb: String, object: String?) {
        let summary = request.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        switch ToolAction(toolName: request.toolName) {
        case .run:
            return (String(localized: "run"), shortCommand(summary))
        case .edit:
            return (String(localized: "change"), shortPath(summary))
        case .read:
            return (String(localized: "read"), shortPath(summary))
        case .web:
            return (String(localized: "open"), summary.isEmpty ? nil : String(summary.prefix(32)))
        case .other:
            return (String(localized: "use"), request.toolName)
        }
    }

    /// The gist of a shell command for a one-line peek: past any `cd … &&`, the program and its subcommand
    /// ("git push", "rm -rf", "npm run"), at most 24 characters.
    static func shortCommand(_ command: String) -> String? {
        var segments = command.components(separatedBy: "&&").map { $0.trimmingCharacters(in: .whitespaces) }
        while segments.count > 1, let first = segments.first, first.hasPrefix("cd ") || first == "cd" {
            segments.removeFirst()
        }
        var words = (segments.first ?? command).split(whereSeparator: \.isWhitespace).map(String.init)
        // Environment assignments and `sudo` aren't the gist.
        while let first = words.first, first.contains("=") && !first.hasPrefix("-") || first == "sudo" {
            words.removeFirst()
        }
        guard let program = words.first else { return nil }
        var gist = (program as NSString).lastPathComponent
        if words.count > 1 {
            let next = words[1]
            if next.count <= 16, !next.contains("/"), !next.hasPrefix("\""), !next.hasPrefix("'") {
                gist += " " + next
            }
        }
        return gist.count > 24 ? String(gist.prefix(23)) + "…" : gist
    }

    /// A file's name from a path (or the summary as it is when it isn't one).
    static func shortPath(_ summary: String) -> String? {
        guard !summary.isEmpty else { return nil }
        let first = summary.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? summary
        let name = first.contains("/") ? (first as NSString).lastPathComponent : first
        return name.count > 32 ? String(name.prefix(31)) + "…" : name
    }
}
