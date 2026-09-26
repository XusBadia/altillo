import Foundation

/// A section of the open notch. The shelf is always present; the rest are opt-in and reorderable (PLAN §4).
enum NotchModule: String, CaseIterable, Identifiable, Codable, Sendable {
    case shelf, assistant, usage, agents, calendar, mirror, nowPlaying, timer, note, clipboard, shortcuts, keepAwake

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
        case .timer: String(localized: "Timer")
        case .note: String(localized: "Note")
        case .clipboard: String(localized: "Clipboard")
        case .shortcuts: String(localized: "Shortcuts")
        case .keepAwake: String(localized: "Keep Awake")
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
        case .timer: "timer"
        case .note: "note.text"
        case .clipboard: "list.clipboard"
        case .shortcuts: "square.2.layers.3d"
        case .keepAwake: "cup.and.heat.waves"
        }
    }

    /// What the user reads in Settings.
    var explanation: String {
        switch self {
        case .shelf: String(localized: "Files you leave up there for a moment.")
        case .assistant: String(localized: "Ask anything. It runs on your Mac with Apple Intelligence and can look at your shelf, calendar and music.")
        case .usage: String(localized: "How much Claude, Codex and company you have left.")
        case .agents: String(localized: "What your agents are doing, and what they're asking you for.")
        case .calendar: String(localized: "Your day and your month, with a button to join calls.")
        case .mirror: String(localized: "The Mac's camera, to check yourself before a call.")
        case .nowPlaying: String(localized: "What's playing, with its controls.")
        case .timer: String(localized: "A kitchen timer that peeks when it rings.")
        case .note: String(localized: "A quick note you can drag out anywhere.")
        case .clipboard: String(localized: "The last things you copied, text only. Passwords are never kept.")
        case .shortcuts: String(localized: "Your favourite Shortcuts, one click away.")
        case .keepAwake: String(localized: "Keep your Mac awake for a while, only when you ask.")
        }
    }

    /// The shelf is the product: it can't be turned off or moved out of first place.
    var isAlwaysOn: Bool { self == .shelf }

    /// Utilities (phase 12) are opt-in: they never arrive switched on, neither on a fresh install nor after an
    /// update, so the tab strip stays calm. The user adds them from edit mode or Settings.
    var isOptIn: Bool {
        switch self {
        case .timer, .note, .clipboard, .shortcuts, .keepAwake: true
        default: false
        }
    }
}
