import AltilloCore
import Foundation

/// Sample content for the design-review scenarios (usage, agents, shelf). Real modules never read it: usage has
/// `UsageStore` since phase 3; agents still show these sessions until phase 4.
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
                id: .claude,
                displayName: "Claude",
                plan: "Max 20×",
                windows: [
                    Self.session(used: 0.85, resetsIn: 72 * 60, now: now),
                    Self.week(used: 0.41, resetsIn: (3 * 24 + 4) * 3600, now: now),
                ],
                fetchedAt: usageUpdatedAt
            ),
            ProviderUsage(
                id: .codex,
                displayName: "Codex",
                plan: "Pro",
                windows: [
                    Self.session(used: 0.34, resetsIn: (3 * 60 + 5) * 60, now: now),
                    Self.week(used: 0.58, resetsIn: (1 * 24 + 9) * 3600, now: now),
                ],
                fetchedAt: usageUpdatedAt
            ),
        ]
        agents = [
            AgentSession(
                id: "claude-altillo",
                agent: .claude,
                project: "altillo",
                phase: .waitingPermission,
                activity: String(localized: "Wants to run a command"),
                lastActivity: now.addingTimeInterval(-8),
                request: PermissionRequest(tool: "Bash", command: "git push origin feat/notch-design")
            ),
            AgentSession(
                id: "codex-openusage",
                agent: .codex,
                project: "openusage",
                phase: .working,
                activity: String(localized: "Running tests · 42 of 118"),
                lastActivity: now.addingTimeInterval(-3),
                request: nil
            ),
            AgentSession(
                id: "claude-badia",
                agent: .claude,
                project: "badia.me",
                phase: .finished,
                activity: String(localized: "Took 6 min 12 s"),
                lastActivity: now.addingTimeInterval(-4 * 60),
                request: nil
            ),
        ]
    }

    /// The provider shown in the ears and in usage alerts.
    var primaryUsage: ProviderUsage { usage[0] }

    /// The peek of the "Peek: usage alert" scenario, built exactly like a real one: Claude's session crossed 80 %.
    var usageAlert: NotchAlert {
        let provider = primaryUsage
        let window = provider.session ?? provider.windows[0]
        let event = UsageAlertEvent(provider: provider.id, providerName: provider.displayName, windowID: window.id,
                                    windowLabel: window.label, kind: .threshold(80))
        return UsageAlertPresenter.alert(for: event, window: window)
    }

    private static func session(used: Double, resetsIn seconds: TimeInterval, now: Date) -> UsageWindow {
        UsageWindow(id: "session", kind: .session, label: String(localized: "Session"), used: used,
                    resetsAt: now.addingTimeInterval(seconds), duration: 5 * 3600)
    }

    private static func week(used: Double, resetsIn seconds: TimeInterval, now: Date) -> UsageWindow {
        UsageWindow(id: "weekly", kind: .weekly, label: String(localized: "Week"), used: used,
                    resetsAt: now.addingTimeInterval(seconds), duration: 7 * 24 * 3600)
    }

    /// The first agent waiting for the user, if any.
    var waitingAgent: AgentSession? { agents.first { $0.phase.needsUser } }

    var workingAgentsCount: Int { agents.count { $0.phase == .working } }
}

// MARK: - Agents (sample only until phase 4)

/// The agent behind a sample session. Usage uses `UsageProviderID` (AltilloCore) instead.
enum AgentKind: String, Sendable {
    case claude, codex

    var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

enum AgentPhase: Sendable {
    case working, waitingPermission, waitingAnswer, finished, error

    var title: String {
        switch self {
        case .working: String(localized: "Working")
        case .waitingPermission: String(localized: "Waiting for permission")
        case .waitingAnswer: String(localized: "Waiting for your answer")
        case .finished: String(localized: "Finished")
        case .error: String(localized: "Error")
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
