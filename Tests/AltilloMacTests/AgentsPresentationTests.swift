import AltilloCore
import Foundation
import Testing
@testable import Altillo

/// How the notch presents live agents: the list's order and its card, the header's summary, the ear, the
/// contextual ear's signal, Ask's `agents` tool and its routing, and the design scenarios' sample sessions.
@MainActor
struct AgentsPresentationTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private static func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "me.badia.altillo.tests.agents.\(name.replacingOccurrences(of: "()", with: ""))-\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    private func session(_ id: String, _ phase: AgentPhase, agent: AgentKind = .claude, project: String = "altillo",
                         ago: TimeInterval = 10, request: AgentPermissionRequest? = nil, activity: String? = nil,
                         message: String? = nil, source: AgentSession.Source = .hooks) -> AgentSession {
        AgentSession(agent: agent, sessionID: id, cwd: "/Users/me/Code/\(project)", phase: phase, activity: activity,
                     startedAt: now.addingTimeInterval(-3600), lastActivity: now.addingTimeInterval(-ago),
                     pendingRequest: request, lastMessage: message, source: source)
    }

    private func request(_ id: String, expiresIn: TimeInterval = 100, dangerous: Bool = false) -> AgentPermissionRequest {
        AgentPermissionRequest(id: id, toolName: "Bash", summary: "swift test", isDangerous: dangerous,
                               requestedAt: now.addingTimeInterval(-20), expiresAt: now.addingTimeInterval(expiresIn))
    }

    // MARK: List

    @Test func whoeverNeedsYouComesFirstThenWorkThenTheRest() {
        let sessions = [
            session("done", .finished, ago: 1),
            session("work", .working, ago: 50),
            session("question", .waitingAnswer, ago: 5),
            session("late", .waitingPermission, request: request("a", expiresIn: 90)),
            session("soon", .waitingPermission, request: request("b", expiresIn: 20)),
            session("quiet", .idle, ago: 2),
            session("broken", .failed, ago: 3),
        ]
        #expect(AgentsLogic.ordered(sessions).map(\.sessionID) == ["soon", "late", "question", "work", "quiet", "broken", "done"])
        #expect(AgentsLogic.featured(in: sessions)?.sessionID == "soon", "the one that gives up first")
        #expect(AgentsLogic.featured(in: sessions, preferring: "claude:question")?.sessionID == "question")
        #expect(AgentsLogic.featured(in: sessions, preferring: "claude:work")?.sessionID == "soon",
                "only a waiting session can be picked for the card")
        #expect(AgentsLogic.featured(in: [session("work", .working)]) == nil)
    }

    @Test func theHeaderSummary() {
        #expect(AgentsLogic.summary(.init(waiting: 1, working: 2)) == "1 knocking · 2 working")
        #expect(AgentsLogic.summary(.init(waiting: 0, working: 3)) == "3 working")
        #expect(AgentsLogic.summary(.init(waiting: 2, working: 0)) == "2 knocking")
        #expect(AgentsLogic.summary(.init(waiting: 0, working: 0)) == nil)
        let counts = AgentsLogic.counts([
            session("a", .waitingPermission), session("b", .waitingAnswer), session("c", .working),
            session("d", .idle), session("e", .finished),
        ])
        #expect(counts == .init(waiting: 2, working: 1) && counts.active == 3)
    }

    @Test func theCardsWordsAndClock() {
        #expect(AgentsLogic.ask(for: session("a", .waitingPermission, request: request("r"))) == "Claude wants to run a command")
        #expect(AgentsLogic.ask(for: session("a", .waitingAnswer, agent: .codex)) == "Codex is waiting for your answer")
        #expect(AgentsLogic.ask(for: session("a", .waitingPermission)) == "Claude wants your OK")
        let asked = request("r", expiresIn: 100)
        #expect(AgentsLogic.secondsLeft(asked, now: now) == 100)
        #expect(AgentsLogic.remainingFraction(asked, now: now) == 100.0 / 120.0)
        #expect(AgentsLogic.secondsLeft(asked, now: now.addingTimeInterval(500)) == 0)
        #expect(AgentsLogic.clock(112) == "1:52" && AgentsLogic.clock(6.2) == "0:07")
        #expect(AgentsLogic.excerpt("  one\n\n**two**  `three` ") == "one two three")
        #expect(AgentsLogic.isQuestion("Want me to push it? Let me know."))
        #expect(!AgentsLogic.isQuestion("All done."))
        #expect(AgentKind(rawValue: "gemini").name == "Gemini")
    }

    // MARK: Ears

    @Test func theEarAndTheContextualEarFollowTheHub() {
        #expect(AgentsLogic.requestSignal(in: [session("w", .working)]) == nil)
        let signal = AgentsLogic.requestSignal(in: [
            session("w", .working),
            session("q", .waitingAnswer, agent: .codex, project: "openusage", ago: 5),
            session("p", .waitingPermission, request: request("r")),
        ])
        #expect(signal == AgentRequestSignal(agentName: "Claude", project: "altillo"), "a permission before a question")
        #expect(AgentsLogic.earAccessibilityLabel(.init(waiting: 1, working: 2)) == "2 agents working, 1 waiting for you")
        #expect(AgentsLogic.earAccessibilityLabel(.init(waiting: 0, working: 0)) == "No agents working")

        // With no live session the agents ear stays quiet, and the contextual one has nothing from them.
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        settings.modules = NotchModule.allCases
        settings.leftEar = .automatic
        settings.rightEar = .agents
        let model = NotchModel(settings: settings)
        #expect(!model.ears.hasActivity(.agents, in: model))
        if case .agentRequest = model.contextualActivity { Issue.record("no agent is waiting") }
    }

    // MARK: Design scenarios

    @Test func theScenariosShowTheSampleSessionsAndTheRealPeek() throws {
        let demo = DemoContent(now: now)
        let waiting = try #require(demo.waitingAgent)
        #expect(waiting.agent == .claude && waiting.project == "altillo" && waiting.pendingRequest != nil)
        let alert = try #require(demo.agentAlert)
        #expect(alert.title == "Knock, knock: Claude wants to run git push in altillo")
        #expect(AgentsLogic.summary(AgentsLogic.counts(demo.agents)) == "1 knocking · 1 working")
        #expect(demo.agents.contains { $0.source == .sessionFile }, "the review shows the install-hooks affordance")
        #expect(DemoContent.agentsVariant(demo.agents, now: now, variant: "empty").isEmpty)
        #expect(DemoContent.agentsVariant(demo.agents, now: now, variant: "dangerous").first?.pendingRequest?.isDangerous == true)
        #expect(DemoContent.agentsVariant(demo.agents, now: now, variant: "question").first?.phase == .waitingAnswer)

        let model = NotchModel(settings: AltilloSettings(defaults: Self.makeDefaults()))
        #expect(model.agentSessions.isEmpty || model.agentSessions == model.agentHub.sessions)
        model.scenario = .openAgents
        #expect(model.agentSessions == model.demo.agents)
        #expect(model.contextualActivity == .rest, "design scenarios never reach the contextual ear")
    }

    // MARK: Ask

    @Test func askReadsTheSessionsInPlainWords() {
        let sessions = [
            session("p", .waitingPermission, request: AgentPermissionRequest(
                id: "r", toolName: "Bash", summary: "git push --force", isDangerous: true,
                requestedAt: now.addingTimeInterval(-12))),
            session("w", .working, agent: .codex, project: "openusage", activity: "Running tests · 42 of 118"),
            session("f", .finished, project: "badia.me", ago: 240, message: "The home page is live."),
            session("i", .idle, agent: .codex, project: "notes", ago: 720, source: .sessionFile),
        ]
        let reading = AssistantAgents.Reading(isEnabled: true, sessions: sessions)
        let all = AssistantAgents.answer(reading, agent: nil, now: now)
        #expect(all.contains("- Claude in altillo: waiting for permission to use Bash (git push --force), a dangerous one, asked 12 s ago."))
        #expect(all.contains("- Codex in openusage: working (Running tests · 42 of 118), started 1 h ago."))
        #expect(all.contains("- Claude in badia.me: finished 4 min ago. Its last words: \"The home page is live.\""))
        #expect(all.contains("(read from its session file, so approximate)"))
        #expect(all.contains("The user can answer from the Agents section"))

        let codex = AssistantAgents.answer(reading, agent: "codex", now: now)
        #expect(codex.contains("openusage") && codex.contains("notes") && !codex.contains("altillo"))
        #expect(AssistantAgents.answer(reading, agent: "badia.me", now: now).contains("badia.me"))
        #expect(AssistantAgents.answer(reading, agent: "Gemini", now: now).hasPrefix("No Gemini session right now"))
        #expect(AssistantAgents.answer(.init(isEnabled: true, sessions: []), agent: nil, now: now)
            .hasPrefix("No coding agent sessions right now"))
        #expect(AssistantAgents.answer(.init(isEnabled: false, sessions: sessions), agent: nil, now: now)
            .contains("turned off"))
    }

    @Test func questionsAboutAgentsGetTheLocalTools() {
        for question in [
            "¿Qué está haciendo Codex?", "What are my agents doing?", "what's Claude doing", "Is Codex done?",
            "¿Ha terminado Claude?", "Què està fent Codex?", "¿Qué hacen mis agentes?",
        ] {
            #expect(AssistantRouter.route(question, now: now) == .context, "\(question)")
        }
        #expect(AssistantRouter.route("What is an AI agent?", now: now) == .chat)
        #expect(AssistantRouter.route("¿Qué tiempo está haciendo en Madrid?", now: now) != .context)
        #expect(AssistantInstructions.text(now: now, route: .context).contains("usage or agents"))
    }
}
