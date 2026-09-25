import AltilloAgents
import AltilloCore
import AppKit
import Foundation
import Observation
import os

// The demo types in DemoContent.swift still share these names until the agents UI moves to AltilloCore's model;
// qualify them here.

/// Live coding-agent sessions (PLAN §5.3, phase 4).
///
/// Two sources, merged by session id (hooks win):
/// - `altillo-hook` events over the Unix socket (`AgentSocketServer`): precise, and the only way to answer a
///   permission from the notch.
/// - Session files (`AgentSessionFileWatcher`): passive, read-only, so sessions show up before hooks are installed.
///
/// Event-driven end to end: the socket and FSEvents wake it, and a single timer is armed for the next moment a
/// session goes stale or should leave the list. Nothing polls. Altillo never decides on its own: a permission is
/// only answered by `decide`, and a hook that gets no answer falls back to the agent's own prompt.
@MainActor
@Observable
final class AgentHub {
    /// Every known session, most relevant first (waiting for the user, then working, then the rest).
    private(set) var sessions: [AgentSession] = []

    /// Shows a peek (a permission asked, a question, a finished turn). Wired by the coordinator.
    @ObservationIgnored var postAlert: (NotchAlert) -> Void = { _ in }

    /// Sessions waiting for the user.
    var waiting: [AgentSession] { sessions.filter { $0.phase.needsUser } }
    var working: [AgentSession] { sessions.filter { $0.phase == .working } }

    @ObservationIgnored private var byID: [String: AgentSession] = [:]
    /// Permission requests per session, oldest first; the first is the session's `pendingRequest`.
    @ObservationIgnored private var queues: [String: [AgentPermissionRequest]] = [:]
    /// Request id → session id.
    @ObservationIgnored private var requestOwners: [String: String] = [:]
    /// Dismissed sessions and the activity they had then: they come back only with newer activity.
    @ObservationIgnored private var dismissed: [String: Date] = [:]
    @ObservationIgnored private var server: AgentSocketServer?
    @ObservationIgnored private var watcher: AgentSessionFileWatcher?
    @ObservationIgnored private var sweepTask: Task<Void, Never>?
    @ObservationIgnored private var sweepDeadline: Date?
    @ObservationIgnored private(set) var isRunning = false

    private static let log = Logger(subsystem: "me.badia.altillo", category: "agents")

    /// Whether this instance owns the hook socket (false: another Altillo does, or it couldn't be created).
    var isListening: Bool { server != nil }

    @ObservationIgnored private let socketPath: String
    @ObservationIgnored private let fileRoots: AgentSessionFileWatcher.Roots?
    @ObservationIgnored private let now: () -> Date

    /// - Parameters:
    ///   - socketPath: where `altillo-hook` connects (tests use a temporary one).
    ///   - fileRoots: the transcript folders to follow; nil turns passive detection off (tests).
    init(socketPath: String = AgentWire.socketPath(), fileRoots: AgentSessionFileWatcher.Roots? = .standard,
         now: @escaping () -> Date = Date.init) {
        self.socketPath = socketPath
        self.fileRoots = fileRoots
        self.now = now
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let server = AgentSocketServer(path: socketPath)
        server.onEnvelope = { [weak self] envelope in
            Task { @MainActor in self?.receive(envelope) }
        }
        server.onRequestClosed = { [weak self] requestID in
            Task { @MainActor in self?.hookStoppedWaiting(requestID) }
        }
        do {
            try server.start()
            self.server = server
        } catch {
            // Another Altillo already answers on the socket (left alone), or the folder isn't writable: hooks go to
            // the other instance or fail open, and session files still work here.
            Self.log.error("Agents socket unavailable (\(String(describing: error), privacy: .public)); following session files only")
            self.server = nil
        }

        if let fileRoots {
            let watcher = AgentSessionFileWatcher(roots: fileRoots)
            watcher.onSnapshot = { [weak self] snapshot, initial in
                Task { @MainActor in self?.receive(snapshot, initial: initial) }
            }
            watcher.start()
            self.watcher = watcher
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        server?.stop()
        server = nil
        watcher?.stop()
        watcher = nil
        sweepTask?.cancel()
        sweepTask = nil
        sweepDeadline = nil
    }

    /// The user answered a permission request from the notch. Never called by Altillo on its own.
    func decide(_ requestID: String, _ decision: AgentDecision) {
        guard let sessionID = requestOwners[requestID], let session = byID[sessionID] else { return }
        let delivered = server?.reply(requestID: requestID, decision: WireDecision(decision)) ?? false
        if delivered {
            resolve(requestID, in: session, decision: decision)
        } else {
            // The hook already gave up: the agent is asking in the terminal now.
            update(AgentStateMachine.expirePermission(requestID, in: session, at: now()))
        }
    }

    /// Brings the session's terminal or editor forward (the right tab when the host allows it).
    func focus(_ session: AgentSession) {
        guard let host = byID[session.id]?.host ?? session.host else { return }
        AgentTerminalFocus.focus(host)
    }

    /// Forgets a finished or stale session from the list.
    func dismiss(_ session: AgentSession) {
        guard let current = byID[session.id] else { return }
        // A live permission request stays answerable in the terminal; don't leave its hook hanging on us.
        for request in queues[session.id] ?? [] {
            server?.reply(requestID: request.id, decision: .none)
            requestOwners[request.id] = nil
        }
        queues[session.id] = nil
        dismissed[session.id] = current.lastActivity
        byID[session.id] = nil
        publish()
    }

    // MARK: - Inputs (internal for tests)

    /// One hook call.
    func receive(_ envelope: HookEnvelope) {
        let agent = AgentKind(rawValue: envelope.agent)
        guard let event = HookPayloadParser.parse(agent: agent, eventName: envelope.event, payload: envelope.payload)
        else {
            // No session id: nothing to show. A waiting hook gets "no decision" at once.
            if let requestID = envelope.requestID { server?.reply(requestID: requestID, decision: .none) }
            return
        }
        let id = "\(agent.rawValue):\(event.sessionID)"
        let at = now()
        if let dismissedAt = dismissed[id] {
            // Back from a dismissal only with news.
            guard at > dismissedAt else { return }
            dismissed[id] = nil
        }
        let previous = byID[id]
        let host = previous?.host?.appBundleID == nil ? AgentTerminalFocus.host(for: envelope) : nil

        var permission: AgentPermissionRequest?
        if case .permissionRequested(let call, let suggestions) = event.kind {
            let requestID = envelope.requestID ?? UUID().uuidString
            let expiresAt = envelope.waitsForDecision ? at.addingTimeInterval(envelope.timeout ?? AgentWire.defaultDecisionTimeout) : at
            var request = ToolDescriptions.permissionRequest(
                id: requestID, agent: agent, call: call, suggestions: suggestions,
                cwd: event.cwd ?? previous?.cwd, requestedAt: at, expiresAt: expiresAt)
            // A request no hook waits on (an older hook) can only be answered in the terminal.
            request.isExpired = !envelope.waitsForDecision || server == nil
            requestOwners[requestID] = id
            let stale = (queues[id] ?? []).filter(\.isExpired)
            for expired in stale { requestOwners[expired.id] = nil }
            let queue = (queues[id] ?? []).filter { !$0.isExpired } + [request]
            queues[id] = queue
            permission = queue.first
        }

        var session = AgentStateMachine.apply(event, to: previous, at: at, permission: permission, host: host)
        switch event.kind {
        case .turnFinished, .turnFailed, .sessionEnded, .promptSubmitted, .interrupted:
            // The turn is over: nothing it asked can still be pending.
            clearQueue(id)
        default:
            if let cleared = previous?.pendingRequest, session.pendingRequest == nil {
                // That tool ran (answered in the terminal); let its hook go if it's still connected, and show the
                // next queued request, if any.
                requestOwners[cleared.id] = nil
                if !cleared.isExpired { server?.reply(requestID: cleared.id, decision: .none) }
                queues[id]?.removeAll { $0.id == cleared.id }
                if let next = queues[id]?.first {
                    session.pendingRequest = next
                    session.phase = .waitingPermission
                } else {
                    queues[id] = nil
                }
            }
        }
        update(session)

        // A Stop without the message: read it from the transcript, off the main actor.
        if case .turnFinished(nil) = event.kind, agent == .claude, let path = event.transcriptPath {
            Task.detached(priority: .utility) { [weak self] in
                guard let message = AgentSessionFileWatcher.lastClaudeMessage(transcript: URL(fileURLWithPath: path))
                else { return }
                await self?.fillLastMessage(message, sessionID: id, turnEndedAt: at)
            }
        }
    }

    /// What a session file shows.
    func receive(_ snapshot: SessionFileSnapshot, initial: Bool = false) {
        let id = "\(snapshot.agent.rawValue):\(snapshot.sessionID)"
        if let dismissedAt = dismissed[id] {
            guard snapshot.lastActivity > dismissedAt else { return }
            dismissed[id] = nil
        }
        let session = AgentStateMachine.apply(snapshot, to: byID[id])
        guard let aged = AgentSessionAging.age(session, now: now(), processAlive: nil) else { return }
        update(aged)
    }

    /// A waiting hook disconnected without our answer: it timed out, or the agent got the answer in the terminal
    /// and killed it.
    func hookStoppedWaiting(_ requestID: String) {
        guard let sessionID = requestOwners[requestID], let session = byID[sessionID] else { return }
        let request = queues[sessionID]?.first { $0.id == requestID }
        let timedOut = request?.expiresAt.map { now() >= $0.addingTimeInterval(-2) } ?? false
        if timedOut {
            // The agent asks in the terminal now: still waiting on the user, no longer answerable here.
            if var queue = queues[sessionID], let index = queue.firstIndex(where: { $0.id == requestID }) {
                queue[index].isExpired = true
                queues[sessionID] = queue
            }
            update(AgentStateMachine.expirePermission(requestID, in: session, at: now()))
        } else {
            resolve(requestID, in: session, decision: nil)
        }
    }

    /// Re-evaluates staleness now (the timer calls it; tests too).
    func sweep() {
        let at = now()
        var changed = false
        for (id, session) in byID {
            let alive = session.host?.pid.map(ProcessTree.isAlive)
            guard let aged = AgentSessionAging.age(session, now: at, processAlive: alive) else {
                byID[id] = nil
                clearQueue(id)
                changed = true
                continue
            }
            if aged != session {
                if aged.pendingRequest?.isExpired == true, let requestID = aged.pendingRequest?.id,
                   var queue = queues[id], let index = queue.firstIndex(where: { $0.id == requestID }) {
                    queue[index].isExpired = true
                    queues[id] = queue
                }
                if aged.pendingRequest == nil { clearQueue(id) }
                byID[id] = aged
                alert(from: session, to: aged)
                changed = true
            }
        }
        if changed { publish() } else { scheduleSweep() }
    }

    // MARK: - Private

    private func fillLastMessage(_ message: String, sessionID: String, turnEndedAt: Date) {
        guard var session = byID[sessionID], session.lastMessage == nil, session.phase == .waitingAnswer,
              session.lastActivity <= turnEndedAt else { return }
        session.lastMessage = message
        update(session)
    }

    private func resolve(_ requestID: String, in session: AgentSession, decision: AgentDecision?) {
        requestOwners[requestID] = nil
        var queue = queues[session.id] ?? []
        queue.removeAll { $0.id == requestID }
        queues[session.id] = queue.isEmpty ? nil : queue
        let next = queue.first
        if session.pendingRequest?.id == requestID {
            update(AgentStateMachine.resolvePermission(requestID, in: session, next: next, decision: decision,
                                                       at: now()))
        }
    }

    private func clearQueue(_ sessionID: String) {
        for request in queues[sessionID] ?? [] {
            requestOwners[request.id] = nil
            // Still waiting (e.g. the turn ended some other way): let the hook go, no decision.
            if !request.isExpired { server?.reply(requestID: request.id, decision: .none) }
        }
        queues[sessionID] = nil
    }

    private func update(_ session: AgentSession) {
        let previous = byID[session.id]
        guard previous != session else { return }
        byID[session.id] = session
        alert(from: previous, to: session)
        publish()
    }

    private func alert(from previous: AgentSession?, to current: AgentSession) {
        if let alert = AgentAlerts.alert(from: previous, to: current) { postAlert(alert) }
    }

    private func publish() {
        let sorted = AgentSessionOrder.sorted(Array(byID.values))
        if sorted != sessions { sessions = sorted }
        scheduleSweep()
    }

    /// Arms one timer for the earliest moment a session should change on its own.
    private func scheduleSweep() {
        let next = byID.values.compactMap(AgentSessionAging.nextDeadline).min()
        guard next != sweepDeadline else { return }
        sweepTask?.cancel()
        sweepDeadline = next
        guard let next else { return }
        let delay = max(next.timeIntervalSince(now()), 0) + 0.5
        sweepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.sweepDeadline = nil
            self?.sweep()
        }
    }
}
