import AltilloCore
import Foundation
import Testing
@testable import Altillo

/// Which peek each agent transition makes (PLAN §5.8): a knock for a permission, a question, a finished turn, a
/// failure; never for a session merely seen for the first time, never twice for the same request.
@MainActor
struct AgentAlertsTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func session(_ phase: AgentPhase, agent: AgentKind = .claude, project: String = "altillo",
                         request: AgentPermissionRequest? = nil, message: String? = nil,
                         lastActivity: TimeInterval = -5, source: AgentSession.Source = .hooks) -> AgentSession {
        AgentSession(agent: agent, sessionID: "s1", cwd: "/Users/me/Code/\(project)", phase: phase,
                     startedAt: now.addingTimeInterval(-600), lastActivity: now.addingTimeInterval(lastActivity),
                     pendingRequest: request, lastMessage: message, source: source)
    }

    private func request(_ id: String = "r1", tool: String = "Bash", summary: String = "git push origin main",
                         dangerous: Bool = false, askedAgo: TimeInterval = 3) -> AgentPermissionRequest {
        AgentPermissionRequest(id: id, toolName: tool, summary: summary, isDangerous: dangerous,
                               requestedAt: now.addingTimeInterval(-askedAgo), expiresAt: now.addingTimeInterval(117))
    }

    @Test func aPermissionKnocksOnceWithTheCommandsGist() throws {
        let working = session(.working)
        let waiting = session(.waitingPermission, request: request())
        let alert = try #require(AgentAlerts.alert(from: working, to: waiting, now: now))
        #expect(alert.title == "Knock, knock: Claude wants to run git push in altillo")
        #expect(alert.source == .agents && alert.module == .agents && alert.isUrgent)
        #expect(alert.agent?.kind == .permission(dangerous: false))
        #expect(alert.agent?.object == "git push" && alert.agent?.requestID == "r1")
        #expect(alert.agent?.knocks == true)

        // The same request again (its activity changed, the hub re-published it): quiet.
        var again = waiting
        again.activity = "Still waiting"
        #expect(AgentAlerts.alert(from: waiting, to: again, now: now) == nil)
        // A new request in the same session knocks again.
        let next = session(.waitingPermission, request: request("r2", tool: "Edit", summary: "/tmp/x/NotchModel.swift"))
        let edit = try #require(AgentAlerts.alert(from: waiting, to: next, now: now))
        #expect(edit.title == "Knock, knock: Claude wants to change NotchModel.swift in altillo")
    }

    @Test func aDangerousRequestSaysCarefulAndHowToConfirm() throws {
        let alert = try #require(AgentAlerts.alert(
            from: session(.working),
            to: session(.waitingPermission, request: request(summary: "rm -rf build/", dangerous: true)),
            now: now
        ))
        #expect(alert.title == "Careful: Claude wants to run rm -rf in altillo")
        #expect(alert.detail == "Hold Allow to confirm")
        #expect(alert.agent?.kind == .permission(dangerous: true))
    }

    @Test func aFirstSightingOnlyPeeksWhenItsAlreadyWaitingAndFresh() {
        #expect(AgentAlerts.alert(from: nil, to: session(.working), now: now) == nil)
        #expect(AgentAlerts.alert(from: nil, to: session(.finished, message: "Done."), now: now) == nil)
        #expect(AgentAlerts.alert(from: nil, to: session(.idle), now: now) == nil)
        #expect(AgentAlerts.alert(from: nil, to: session(.waitingPermission, request: request()), now: now) != nil)
        // Waiting for ten minutes already (Altillo just launched): no knock.
        #expect(AgentAlerts.alert(from: nil, to: session(.waitingPermission, request: request(askedAgo: 600)),
                                  now: now) == nil)
        #expect(AgentAlerts.alert(from: nil, to: session(.waitingAnswer, message: "Push it?", lastActivity: -900),
                                  now: now) == nil)
    }

    @Test func aTurnEndingIsAQuestionOrDoneDependingOnWhatItSaid() throws {
        let question = try #require(AgentAlerts.alert(
            from: session(.working, agent: .codex, project: "openusage"),
            to: session(.waitingAnswer, agent: .codex, project: "openusage",
                        message: "I updated the parser. Should I also bump the version?"),
            now: now
        ))
        #expect(question.title == "Codex is asking you something in openusage")
        #expect(question.detail == "I updated the parser. Should I also bump the version?")
        #expect(question.isUrgent && question.agent?.kind == .question)

        let done = try #require(AgentAlerts.alert(
            from: session(.working),
            to: session(.waitingAnswer, message: "## Summary\nThe **notch** now shows live agents, with tests and the peek wired up end to end."),
            now: now
        ))
        #expect(done.title == "Claude finished in altillo")
        #expect(done.detail == "Summary The notch now shows live agents, with tests and the…")
        #expect(!done.isUrgent && done.agent?.kind == .finished)

        // Staying there says nothing more.
        let waiting = session(.waitingAnswer, message: "Should I?")
        #expect(AgentAlerts.alert(from: waiting, to: waiting, now: now) == nil)
    }

    @Test func finishingAndFailing() throws {
        let ended = try #require(AgentAlerts.alert(from: session(.working), to: session(.finished), now: now))
        #expect(ended.title == "Claude finished in altillo" && ended.detail == nil)
        #expect(AgentAlerts.alert(from: session(.working), to: session(.idle), now: now)?.agent?.kind == .finished)
        // After a question or a finished turn, the session closing is no news.
        #expect(AgentAlerts.alert(from: session(.waitingAnswer), to: session(.finished), now: now) == nil)
        #expect(AgentAlerts.alert(from: session(.idle), to: session(.finished), now: now) == nil)

        let failed = try #require(AgentAlerts.alert(
            from: session(.working), to: session(.failed, message: "API Error: 529 Overloaded"), now: now))
        #expect(failed.title == "Claude failed in altillo" && failed.detail == "API Error: 529 Overloaded")
        #expect(AgentAlerts.alert(from: session(.failed), to: session(.failed), now: now) == nil)
        #expect(AgentAlerts.alert(from: session(.waitingPermission, request: request()), to: session(.working),
                                  now: now) == nil, "answered in the terminal: nothing to say")
    }

    @Test func aRequestTheHookGaveUpOnNeverKnocks() {
        var expired = request()
        expired.isExpired = true
        #expect(AgentAlerts.alert(from: session(.working), to: session(.waitingPermission, request: expired), now: now) == nil)
    }

    @Test func aSessionFileWithoutARequestStillKnocksOnce() throws {
        let blocked = session(.waitingPermission, source: .sessionFile)
        let alert = try #require(AgentAlerts.alert(from: session(.working, source: .sessionFile), to: blocked, now: now))
        #expect(alert.title == "Knock, knock: Claude wants your OK in altillo")
        #expect(AgentAlerts.alert(from: blocked, to: blocked, now: now) == nil)
    }

    @Test func theCommandsGist() {
        #expect(AgentAlerts.shortCommand("git push origin feat/notch-design") == "git push")
        #expect(AgentAlerts.shortCommand("cd /Users/me/Code/altillo && rm -rf build") == "rm -rf")
        #expect(AgentAlerts.shortCommand("FOO=1 sudo /usr/bin/make install") == "make install")
        #expect(AgentAlerts.shortCommand("ls ~/Code/some/deep/path") == "ls")
        #expect(AgentAlerts.shortCommand("   ") == nil)
        #expect(AgentAlerts.phrase(for: request(tool: "mcp__github__create_issue", summary: "x")).verb == "use")
    }
}
