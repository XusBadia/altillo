import AltilloCore

/// Frozen states shown from the menu bar ("Revisión de diseño") to review the look of every state on the real notch.
enum DesignScenario: String, CaseIterable, Identifiable {
    case idle
    case idleWithEars
    case peekShelf
    case peekUsageAlert
    case peekAgentWaiting
    case dragArmed
    case dropTarget
    case openShelfEmpty
    case openShelf
    case openUsage
    case openAgents

    var id: Self { self }

    var title: String {
        switch self {
        case .idle: "Reposo"
        case .idleWithEars: "Reposo con orejas"
        case .peekShelf: "Peek: altillo"
        case .peekUsageAlert: "Peek: alerta de uso"
        case .peekAgentWaiting: "Peek: agente esperando"
        case .dragArmed: "Arrastre en curso"
        case .dropTarget: "Zona de soltar"
        case .openShelfEmpty: "Abierto: altillo vacío"
        case .openShelf: "Abierto: altillo con archivos"
        case .openUsage: "Abierto: uso de IA"
        case .openAgents: "Abierto: agentes"
        }
    }

    var state: NotchState {
        switch self {
        case .idle, .idleWithEars: .idle
        case .peekShelf, .peekUsageAlert, .peekAgentWaiting: .peek
        case .dragArmed: .dragArmed
        case .dropTarget: .dropTarget
        case .openShelfEmpty, .openShelf, .openUsage, .openAgents: .open
        }
    }

    /// Scenarios that show sample files in the shelf.
    var showsDemoShelf: Bool {
        switch self {
        case .idleWithEars, .peekShelf, .dropTarget, .openShelf: true
        default: false
        }
    }

    var tab: NotchTab {
        switch self {
        case .openUsage, .peekUsageAlert: .usage
        case .openAgents, .peekAgentWaiting: .agents
        default: .shelf
        }
    }
}
