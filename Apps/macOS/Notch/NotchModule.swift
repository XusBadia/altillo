import Foundation

/// A section of the open notch. The shelf is always present; the rest are opt-in and reorderable (PLAN §4).
enum NotchModule: String, CaseIterable, Identifiable, Codable, Sendable {
    case shelf, assistant, usage, agents, calendar, mirror, nowPlaying

    var id: Self { self }

    /// Shown next to the icon when the module is the active one.
    var title: String {
        switch self {
        case .shelf: String(localized: "Shelf")
        case .assistant: String(localized: "Ask")
        case .usage: String(localized: "Usage")
        case .agents: String(localized: "Agents")
        case .calendar: String(localized: "Calendar")
        case .mirror: String(localized: "Mirror")
        case .nowPlaying: String(localized: "Now playing")
        }
    }

    var symbol: String {
        switch self {
        case .shelf: "house"
        case .assistant: "sparkle"
        case .usage: "gauge.with.needle"
        case .agents: "hand.raised"
        case .calendar: "calendar"
        case .mirror: "person.crop.square"
        case .nowPlaying: "music.note"
        }
    }

    /// What the user reads in Settings.
    var explanation: String {
        switch self {
        case .shelf: String(localized: "Files you leave up there for a moment.")
        case .assistant: String(localized: "Ask anything. It runs on your Mac with Apple Intelligence and can look at your shelf, calendar and music.")
        case .usage: String(localized: "How much Claude, Codex and company you have left.")
        case .agents: String(localized: "What your agents are doing, and what they're asking you for.")
        case .calendar: String(localized: "Your next event, with a button to join.")
        case .mirror: String(localized: "The Mac's camera, to check yourself before a call.")
        case .nowPlaying: String(localized: "What's playing, with its controls.")
        }
    }

    /// The shelf is the product: it can't be turned off or moved out of first place.
    var isAlwaysOn: Bool { self == .shelf }
}
