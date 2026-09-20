import AltilloCore

/// Frozen states shown from the menu bar ("Revisión de diseño") to review the look of every state on the real notch.
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
    case openUsage
    case openAgents
    case openCalendar
    case openMirror
    case openNowPlaying

    var id: Self { self }

    var title: String {
        switch self {
        case .idle: "Reposo"
        case .idleWithEars: "Reposo con orejas"
        case .peekHint: "Peek: pista (altillo vacío)"
        case .peekShelf: "Peek: altillo"
        case .peekUsageAlert: "Peek: alerta de uso"
        case .peekAgentWaiting: "Peek: agente esperando"
        case .dragArmed: "Arrastre en curso"
        case .dropTarget: "Zona de soltar"
        case .openShelfEmpty: "Abierto: altillo vacío"
        case .openShelfLoading: "Abierto: guardando una promesa"
        case .openShelfError: "Abierto: error al guardar"
        case .openShelf: "Abierto: altillo con archivos"
        case .openUsage: "Abierto: uso de IA"
        case .openAgents: "Abierto: agentes"
        case .openCalendar: "Abierto: agenda"
        case .openMirror: "Abierto: espejo"
        case .openNowPlaying: "Abierto: sonando"
        }
    }

    var state: NotchState {
        switch self {
        case .idle, .idleWithEars: .idle
        case .peekHint, .peekShelf, .peekUsageAlert, .peekAgentWaiting: .peek
        case .dragArmed: .dragArmed
        case .dropTarget: .dropTarget
        case .openShelfEmpty, .openShelfLoading, .openShelfError, .openShelf, .openUsage, .openAgents,
             .openCalendar, .openMirror, .openNowPlaying: .open
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
        case .openUsage, .peekUsageAlert: .usage
        case .openAgents, .peekAgentWaiting: .agents
        case .openCalendar: .calendar
        case .openMirror: .mirror
        case .openNowPlaying: .nowPlaying
        default: .shelf
        }
    }
}
