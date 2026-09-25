import AltilloCore
import Foundation

/// Sample content for the design-review scenarios (usage, agents, shelf). Real modules never read it: usage has
/// `UsageStore` since phase 3 and agents `AgentHub` since phase 4.
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
                agent: .claude,
                sessionID: "demo-altillo",
                cwd: "/Users/demo/Code/altillo",
                phase: .waitingPermission,
                activity: String(localized: "Wants to run a command"),
                startedAt: now.addingTimeInterval(-14 * 60),
                lastActivity: now.addingTimeInterval(-8),
                pendingRequest: AgentPermissionRequest(
                    id: "demo-request",
                    toolName: "Bash",
                    summary: "git push origin feat/notch-design",
                    detail: "git push origin feat/notch-design\n\nPush the notch design branch so the review can start.",
                    canAllowForSession: true,
                    requestedAt: now.addingTimeInterval(-8),
                    expiresAt: now.addingTimeInterval(112)
                ),
                source: .hooks
            ),
            AgentSession(
                agent: .codex,
                sessionID: "demo-openusage",
                cwd: "/Users/demo/Code/openusage",
                phase: .working,
                activity: String(localized: "Running tests · 42 of 118"),
                startedAt: now.addingTimeInterval(-6 * 60),
                lastActivity: now.addingTimeInterval(-3),
                source: .hooks
            ),
            AgentSession(
                agent: .claude,
                sessionID: "demo-badia",
                cwd: "/Users/demo/Code/badia.me",
                phase: .finished,
                activity: String(localized: "Took 6 min 12 s"),
                startedAt: now.addingTimeInterval(-10 * 60),
                lastActivity: now.addingTimeInterval(-4 * 60),
                lastMessage: String(localized: "The new home page is live and the RSS feed validates again."),
                source: .hooks
            ),
            AgentSession(
                agent: .codex,
                sessionID: "demo-notes",
                cwd: "/Users/demo/Code/notes",
                phase: .idle,
                activity: String(localized: "Waiting for your next message"),
                startedAt: now.addingTimeInterval(-50 * 60),
                lastActivity: now.addingTimeInterval(-12 * 60),
                source: .sessionFile
            ),
        ]
        agents = Self.agentsVariant(agents, now: now)
    }

    /// `-demoAgents dangerous|question|readOnly|expired|rows|empty` swaps the waiting sample for another state to review
    /// in the agents scenarios (a dangerous command, a question, a session only read from its file, a request the
    /// hook gave up on, only the rows, nobody at all).
    static func agentsVariant(_ agents: [AgentSession], now: Date,
                              variant: String? = UserDefaults.standard.string(forKey: "demoAgents")) -> [AgentSession] {
        guard let variant, var first = agents.first else { return agents }
        switch variant {
        case "empty":
            return []
        case "rows":
            return Array(agents.dropFirst())
        case "dangerous":
            first.pendingRequest = AgentPermissionRequest(
                id: "demo-dangerous", toolName: "Bash", summary: "rm -rf build/ && git push --force origin main",
                detail: "rm -rf build/ && git push --force origin main\n\nClean the build folder and overwrite main with the rebased history.",
                isDangerous: true, canAllowForSession: true, requestedAt: now.addingTimeInterval(-20),
                expiresAt: now.addingTimeInterval(100))
        case "question":
            first.phase = .waitingAnswer
            first.pendingRequest = nil
            first.lastMessage = "I've moved the settings into their own pane. Should I also migrate the old keys, or leave them for a release?"
        case "readOnly":
            first.source = .sessionFile
        case "expired":
            first.pendingRequest?.requestedAt = now.addingTimeInterval(-130)
            first.pendingRequest?.expiresAt = now.addingTimeInterval(-10)
            first.pendingRequest?.isExpired = true
        default:
            return agents
        }
        return [first] + agents.dropFirst()
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
    var waitingAgent: AgentSession? { AgentsLogic.featured(in: agents) }

    /// The peek of the "Peek: agent waiting" scenario, built exactly like a real one (`AgentAlerts`).
    var agentAlert: NotchAlert? {
        waitingAgent.flatMap { AgentAlerts.alert(from: nil, to: $0, now: $0.lastActivity) }
    }
}
