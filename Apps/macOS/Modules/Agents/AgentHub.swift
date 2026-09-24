import AltilloCore
import Foundation
import Observation

// The demo types in DemoContent.swift still share these names until the agents UI moves to AltilloCore's model;
// qualify them here.

/// Live coding-agent sessions (PLAN §5.3, phase 4). STUB: the engine work fills in the socket server that
/// `altillo-hook` talks to, the session-file watcher and the state machine. The API below is what the notch,
/// Settings and Ask use; keep it stable.
@MainActor
@Observable
final class AgentHub {
    /// Every known session, most relevant first (waiting for the user, then working, then the rest).
    private(set) var sessions: [AltilloCore.AgentSession] = []

    /// Shows a peek (a permission asked, a question, a finished turn). Wired by the coordinator.
    @ObservationIgnored var postAlert: (NotchAlert) -> Void = { _ in }

    /// Sessions waiting for the user.
    var waiting: [AltilloCore.AgentSession] { sessions.filter { $0.phase.needsUser } }
    var working: [AltilloCore.AgentSession] { sessions.filter { $0.phase == .working } }

    func start() {}
    func stop() {}

    /// The user answered a permission request from the notch. Never called by Altillo on its own.
    func decide(_ requestID: String, _ decision: AgentDecision) {}

    /// Brings the session's terminal or editor forward (the right tab when the host allows it).
    func focus(_ session: AltilloCore.AgentSession) {}

    /// Forgets a finished or stale session from the list.
    func dismiss(_ session: AltilloCore.AgentSession) {}
}
