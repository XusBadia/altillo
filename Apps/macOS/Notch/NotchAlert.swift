import AltilloCore
import Foundation

/// Something worth a glance while the notch is idle: it grows into a one-line peek for a few seconds and goes back
/// to rest on its own (PLAN §5, phase 11). Hovering keeps it; clicking it (or resting on it) opens its module.
///
/// Alerts never interrupt: they are dropped while the notch is open, a drag is in progress or a design scenario is
/// frozen, and a newer alert simply replaces the one on screen.
struct NotchAlert: Identifiable, Equatable, Sendable {
    enum Source: String, Sendable {
        /// An event about to start (PLAN §5.6: "un aviso 5 min antes").
        case calendar
        /// A new song started.
        case nowPlaying
        /// An answer finished while the notch was closed.
        case assistant
        /// An AI limit running high, used up, running out early or refilled (PLAN §5.2).
        case usage
        /// A coding agent asking for permission or an answer, finishing or failing (PLAN §5.3).
        case agents
    }

    let id = UUID()
    var source: Source
    /// SF Symbol for the leading ear.
    var symbol: String
    /// The sentence, short enough for one line ("Design review").
    var title: String
    /// Secondary words after the title ("Ana, Luis"), dimmer.
    var detail: String?
    /// A figure on the trailing side ("in 5 min", "3:41").
    var trailing: String?
    /// Accent the leading symbol with the bulb (something needs you) instead of paper.
    var isUrgent = false
    /// Section the notch opens on when the user reaches for the alert.
    var module: NotchModule?
    /// How long it stays if nobody looks at it.
    var duration: Duration = .seconds(4)
    /// Set when an agent raised it: the peek knocks, shows the agent's mark and reads the command on a slip.
    var agent: AgentAlertContext?
}

/// The agent behind an alert, with the pieces of its sentence (`AgentAlerts` builds it; the peek lays it out).
struct AgentAlertContext: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// It wants permission to do something (`dangerous`: a command that needs an extra confirmation).
        case permission(dangerous: Bool)
        /// It asked the user something and waits for the answer.
        case question
        /// It finished (its turn or the session).
        case finished
        /// Its last turn failed.
        case failed
    }

    var kind: Kind
    var agent: AgentKind
    var project: String
    /// The verb for a permission ("run", "change", "read"…), nil for other kinds.
    var verb: String?
    /// What the verb acts on, short: "git push", "NotchModel.swift".
    var object: String?
    /// The first words of the agent's last message.
    var excerpt: String?
    /// `AgentSession.id`.
    var sessionID: String
    /// The permission request it's about, so the same request never peeks twice.
    var requestID: String?

    /// It knocks: the user has to do something.
    var knocks: Bool {
        switch kind {
        case .permission, .question: true
        case .finished, .failed: false
        }
    }
}
