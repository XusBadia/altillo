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
}
