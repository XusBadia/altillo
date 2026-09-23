import AltilloCore
import Foundation

/// Frozen states shown from the menu bar ("Design review") to review the look of every state on the real notch.
enum DesignScenario: String, CaseIterable, Identifiable {
    case idle
    case idleWithEars
    case peekHint
    case peekShelf
    case peekUsageAlert
    case peekAgentWaiting
    case dragArmed
    case dropTarget
    case openShelfEmpty
    case openShelfLoading
    case openShelfError
    case openShelf
    case openAssistant
    case peekAlert
    case openUsage
    case openAgents
    case openCalendar
    case openMirror
    case openNowPlaying
    case openDrawer

    var id: Self { self }

    var title: String {
        switch self {
        case .idle: String(localized: "Idle")
        case .idleWithEars: String(localized: "Idle with ears")
        case .peekHint: String(localized: "Peek: hint (empty shelf)")
        case .peekShelf: String(localized: "Peek: shelf")
        case .peekUsageAlert: String(localized: "Peek: usage alert")
        case .peekAgentWaiting: String(localized: "Peek: agent waiting")
        case .dragArmed: String(localized: "Drag armed")
        case .dropTarget: String(localized: "Drop target")
        case .openShelfEmpty: String(localized: "Open: empty shelf")
        case .openShelfLoading: String(localized: "Open: receiving a promise")
        case .openShelfError: String(localized: "Open: save error")
        case .openShelf: String(localized: "Open: shelf with files")
        case .openAssistant: String(localized: "Open: ask")
        case .peekAlert: String(localized: "Peek: meeting about to start")
        case .openUsage: String(localized: "Open: AI usage")
        case .openAgents: String(localized: "Open: agents")
        case .openCalendar: String(localized: "Open: calendar")
        case .openMirror: String(localized: "Open: mirror")
        case .openNowPlaying: String(localized: "Open: now playing")
        case .openDrawer: String(localized: "Open: Drawer")
        }
    }

    var state: NotchState {
        switch self {
        case .idle, .idleWithEars: .idle
        case .peekHint, .peekShelf, .peekUsageAlert, .peekAgentWaiting, .peekAlert: .peek
        case .dragArmed: .dragArmed
        case .dropTarget: .dropTarget
        case .openShelfEmpty, .openShelfLoading, .openShelfError, .openShelf, .openAssistant, .openUsage, .openAgents,
             .openCalendar, .openMirror, .openNowPlaying, .openDrawer: .open
        }
    }

    /// Scenarios that show sample files in the shelf.
    var showsDemoShelf: Bool {
        switch self {
        case .idleWithEars, .peekShelf, .dropTarget, .openShelf: true
        default: false
        }
    }

    var module: NotchModule {
        switch self {
        case .openAssistant: .assistant
        case .peekAlert: .calendar
        case .openUsage, .peekUsageAlert: .usage
        case .openAgents, .peekAgentWaiting: .agents
        case .openCalendar: .calendar
        case .openMirror: .mirror
        case .openNowPlaying: .nowPlaying
        case .openDrawer: .shelf
        default: .shelf
        }
    }
}
