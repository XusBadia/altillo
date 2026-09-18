import AltilloCore
import Foundation

/// Fake content for the phase 0 design review (usage, agents, shelf). Replaced module by module by the real providers.
struct DemoContent {
    static let sample = DemoContent()

    /// Sample shelf items shown by the design scenarios that need a non-empty shelf.
    /// The files are real (generated once in a temp folder) so Quick Look thumbnails render.
    var shelfItems: [ShelfItem] { DemoFiles.items }

    var usage: [ProviderUsage]
    var agents: [AgentSession]
    /// When the usage figures were last refreshed.
    var usageUpdatedAt: Date

    init(now: Date = .now) {
        usageUpdatedAt = now.addingTimeInterval(-2 * 60)
        usage = [
            ProviderUsage(
                id: "claude",
                agent: .claude,
                plan: "Max 20×",
                session: UsageWindow(used: 0.85, resetsAt: now.addingTimeInterval(72 * 60), duration: 5 * 3600),
                weekly: UsageWindow(used: 0.41, resetsAt: now.addingTimeInterval((3 * 24 + 4) * 3600), duration: 7 * 24 * 3600)
            ),
            ProviderUsage(
                id: "codex",
                agent: .codex,
                plan: "Pro",
                session: UsageWindow(used: 0.34, resetsAt: now.addingTimeInterval((3 * 60 + 5) * 60), duration: 5 * 3600),
                weekly: UsageWindow(used: 0.58, resetsAt: now.addingTimeInterval((1 * 24 + 9) * 3600), duration: 7 * 24 * 3600)
            ),
        ]
        agents = [
            AgentSession(
                id: "claude-altillo",
                agent: .claude,
                project: "altillo",
                phase: .waitingPermission,
                activity: "Quiere ejecutar un comando",
                lastActivity: now.addingTimeInterval(-8),
                request: PermissionRequest(tool: "Bash", command: "git push origin feat/notch-design")
            ),
            AgentSession(
                id: "codex-openusage",
                agent: .codex,
                project: "openusage",
                phase: .working,
                activity: "Ejecutando tests · 42 de 118",
                lastActivity: now.addingTimeInterval(-3),
                request: nil
            ),
            AgentSession(
                id: "claude-badia",
                agent: .claude,
                project: "badia.me",
                phase: .finished,
                activity: "Terminado en 6 min 12 s",
                lastActivity: now.addingTimeInterval(-4 * 60),
                request: nil
            ),
        ]
    }

    /// The provider shown in the ears and in usage alerts.
    var primaryUsage: ProviderUsage { usage[0] }

    /// The first agent waiting for the user, if any.
    var waitingAgent: AgentSession? { agents.first { $0.phase.needsUser } }

    var workingAgentsCount: Int { agents.count { $0.phase == .working } }
}

// MARK: - Usage

enum AgentKind: String, Sendable {
    case claude, codex

    var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

struct UsageWindow: Hashable, Sendable {
    /// 0…1.
    var used: Double
    var resetsAt: Date
    var duration: TimeInterval

    /// Fraction of the window already elapsed: what you'd have used by now at an even pace.
    func expectedPace(now: Date = .now) -> Double {
        let remaining = resetsAt.timeIntervalSince(now)
        return min(max(1 - remaining / duration, 0), 1)
    }

    /// Positive when burning faster than the window allows, in fraction points.
    func paceDelta(now: Date = .now) -> Double { used - expectedPace(now: now) }
}

struct ProviderUsage: Identifiable, Sendable {
    let id: String
    var agent: AgentKind
    var plan: String
    var session: UsageWindow
    var weekly: UsageWindow
}

// MARK: - Agents

enum AgentPhase: Sendable {
    case working, waitingPermission, waitingAnswer, finished, error

    var title: String {
        switch self {
        case .working: "Trabajando"
        case .waitingPermission: "Esperando permiso"
        case .waitingAnswer: "Esperando tu respuesta"
        case .finished: "Terminado"
        case .error: "Error"
        }
    }

    var needsUser: Bool { self == .waitingPermission || self == .waitingAnswer }
}

struct PermissionRequest: Hashable, Sendable {
    var tool: String
    var command: String
}

struct AgentSession: Identifiable, Sendable {
    let id: String
    var agent: AgentKind
    var project: String
    var phase: AgentPhase
    var activity: String
    var lastActivity: Date
    var request: PermissionRequest?
}
