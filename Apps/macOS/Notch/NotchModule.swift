import Foundation

/// A section of the open notch. The shelf is always present; the rest are opt-in and reorderable (PLAN §4).
enum NotchModule: String, CaseIterable, Identifiable, Codable, Sendable {
    case shelf, usage, agents, calendar, mirror, nowPlaying

    var id: Self { self }

    /// Shown next to the icon when the module is the active one.
    var title: String {
        switch self {
        case .shelf: "Altillo"
        case .usage: "Uso"
        case .agents: "Agentes"
        case .calendar: "Agenda"
        case .mirror: "Espejo"
        case .nowPlaying: "Sonando"
        }
    }

    var symbol: String {
        switch self {
        case .shelf: "house"
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
        case .shelf: "Archivos que dejas arriba un momento."
        case .usage: "Cuánto te queda de Claude, Codex y compañía."
        case .agents: "Qué están haciendo tus agentes y qué te piden."
        case .calendar: "Tu próximo evento, con botón para unirte."
        case .mirror: "La cámara del Mac, para verte antes de una llamada."
        case .nowPlaying: "Lo que suena, con sus controles."
        }
    }

    /// The shelf is the product: it can't be turned off or moved out of first place.
    var isAlwaysOn: Bool { self == .shelf }
}
