import AltilloAgents
import AltilloCore
import AppKit
import Foundation
import Observation
import os

// The demo types in DemoContent.swift still share these names until the agents UI moves to AltilloCore's model;
// qualify them here.

/// Live coding-agent sessions (PLAN §5.3, phases 4 and 14).
///
/// Three sources, merged by session id (hooks win):
/// - `altillo-hook` events over the Unix socket (`AgentSocketServer`): precise, and the only way to answer a
///   permission from the notch.
/// - Session files (`AgentSessionFileWatcher`): passive, read-only, so sessions show up before hooks are installed.
/// - OpenCode's own server (`OpenCodeMonitor`), while `opencode serve` runs: precise, and answerable.
///
/// Replies (phase 14): when a session waits for the user's next message and a reply can reach it (a stop hook
/// holding the turn open, opt-in; or OpenCode's API), `reply(_:to:)` sends what the user typed. Never on its own.
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
    /// Whether the Agents module is on. When it's off, no hook is ever held: permission and reply waits get "no
    /// decision" at once, as if no hooks were installed. Wired by the coordinator.
    @ObservationIgnored var isModuleEnabled: () -> Bool = { true }
    /// The frontmost app's bundle id and pid (injected in tests).
    @ObservationIgnored var frontmostApp: () -> (bundleID: String?, pid: pid_t?) = {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.processIdentifier)
    }

    /// Whether Altillo can tell which app hosts a session (its bundle id, or a GUI app up from the agent's process).
    /// Without it (tmux, SSH…), going to the terminal couldn't let a held hook go, so none is held. Injected in tests.
    @ObservationIgnored var identifiesHost: (AgentHost) -> Bool = {
        $0.appBundleID != nil || AgentTerminalFocus.application(for: $0) != nil
    }

    /// Replies longer than this are refused (the hook's message and the agent's prompt stay reasonable).
    static let maxReplyBytes = 16 * 1024
    /// A reply this close to the hook's deadline may land after it gave up: treated as not delivered.
    static let replyDeadlineMargin: TimeInterval = 1
    /// Replies in a row a stop hook can still use (Copilot ends the turn after 8 blocks in a row).
    static let continuationCaps: [AgentKind: Int] = [.copilot: 8]
    /// An OpenCode permission nobody answered (and no reconnection cleared) leaves the card after this long.
    static let openCodeRequestLimit: TimeInterval = 60 * 60

    enum ReplyOutcome: Equatable {
        case sent
        /// Longer than `maxReplyBytes`: nothing sent, the field keeps the text.
        case tooLong
        /// Nothing can take a reply now (the hook gave up, or it's not waiting): answer in the terminal.
        case unavailable
    }

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
    /// Stop hooks holding a turn open for a reply: request id → session id.
    @ObservationIgnored private var replyOwners: [String: String] = [:]
    /// The last tool each session was about to run (agents whose prompts are only answered in the terminal: the card
    /// shows what it asks about).
    @ObservationIgnored private var lastToolCalls: [String: AgentToolCall] = [:]
    @ObservationIgnored private var openCode: OpenCodeMonitor?
    /// OpenCode sessions (Altillo id) → the server and directory that answer for them.
    @ObservationIgnored private var openCodeLinks: [String: OpenCodeLink] = [:]
    /// OpenCode permission request id → Altillo session id.
    @ObservationIgnored private var openCodeRequests: [String: String] = [:]
    /// OpenCode message id → role, and the last assistant text per session (applied when the turn ends).
    @ObservationIgnored private var openCodeRoles: [String: String] = [:]
    @ObservationIgnored private var openCodeText: [String: String] = [:]
    @ObservationIgnored private var openCodeChildren: Set<String> = []
    /// OpenCode permission requests per session, oldest first; the first is the session's `pendingRequest`.
    @ObservationIgnored private var openCodeQueues: [String: [AgentPermissionRequest]] = [:]
    /// Replies in a row delivered through a session's stop hook (reset when the user starts a turn).
    @ObservationIgnored private var replyStreaks: [String: Int] = [:]
    /// Observes app activations while at least one stop hook is held (part C: going to the terminal lets it go).
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
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
    @ObservationIgnored private let openCodeData: URL?
    @ObservationIgnored private let now: () -> Date

    struct OpenCodeLink: Equatable {
        var server: OpenCodeMonitor.Server
        var directory: String?
    }

    /// - Parameters:
    ///   - socketPath: where `altillo-hook` connects (tests use a temporary one).
    ///   - fileRoots: the transcript folders to follow; nil turns passive detection off (tests).
    ///   - openCodeData: OpenCode's data folder, whose writes announce a running server; nil turns OpenCode off (tests).
    init(socketPath: String = AgentWire.socketPath(), fileRoots: AgentSessionFileWatcher.Roots? = .standard,
         openCodeData: URL? = OpenCodeMonitor.defaultDataDirectory, now: @escaping () -> Date = Date.init) {
        self.socketPath = socketPath
        self.fileRoots = fileRoots
        self.openCodeData = openCodeData
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

        if let openCodeData {
            let monitor = OpenCodeMonitor(dataDirectory: openCodeData)
            monitor.onEvent = { [weak self] event, directory, server in
                Task { @MainActor in self?.receive(openCode: event, directory: directory, server: server) }
            }
            monitor.onServerGone = { [weak self] server in
                Task { @MainActor in self?.openCodeServerGone(server) }
            }
            monitor.onConnected = { [weak self] server in
                Task { @MainActor in self?.reconcileOpenCode(server) }
            }
            monitor.start()
            openCode = monitor
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        server?.stop()
        server = nil
        watcher?.stop()
        watcher = nil
        openCode?.stop()
        openCode = nil
        stopObservingActivations()
        sweepTask?.cancel()
        sweepTask = nil
        sweepDeadline = nil
    }

    /// The user answered a permission request from the notch. Never called by Altillo on its own.
    func decide(_ requestID: String, _ decision: AgentDecision) {
        if let sessionID = openCodeRequests[requestID] {
            decideOpenCode(requestID, decision, sessionID: sessionID)
            return
        }
        guard let sessionID = requestOwners[requestID], let session = byID[sessionID] else { return }
        let delivered = server?.reply(requestID: requestID, decision: WireDecision(decision)) ?? false
        if delivered {
            resolve(requestID, in: session, decision: decision)
        } else {
            // The hook already gave up: the agent is asking in the terminal now.
            update(AgentStateMachine.expirePermission(requestID, in: session, at: now()))
        }
    }

    /// Sends what the user typed to a session waiting for their next message (phase 14; Ask uses it too).
    /// True when it was handed to the agent: a stop hook holding the turn open (the agent carries on with it) or
    /// OpenCode's server (a new message). False when nothing can take a reply now (no hook waiting, it gave up, the
    /// session is gone) or it's too long. Altillo never calls it on its own.
    @discardableResult
    func reply(_ text: String, to session: AgentSession) -> Bool {
        sendReply(text, to: session) == .sent
    }

    /// `reply(_:to:)` with the reason when it didn't go.
    func sendReply(_ text: String, to session: AgentSession) -> ReplyOutcome {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= Self.maxReplyBytes else { return .tooLong }
        guard !text.isEmpty, var current = byID[session.id], let channel = current.reply, !channel.isClosed else {
            return .unavailable
        }
        switch channel.kind {
        case .stopHook:
            replyOwners[channel.id] = nil
            let inTime = channel.expiresAt.map { $0.timeIntervalSince(now()) > Self.replyDeadlineMargin } ?? true
            let delivered = inTime && server?.reply(requestID: channel.id, decision: .reply, text: text) == true
            guard delivered else {
                // The hook gave up (or is about to): the agent stops and takes its next message in the terminal.
                if !inTime { server?.reply(requestID: channel.id, decision: .none) }
                current.reply?.isClosed = true
                current.reply?.expiresAt = nil
                update(current)
                return .unavailable
            }
            replyStreaks[current.id, default: 0] += 1
        case .server:
            guard let link = openCodeLinks[current.id], let openCode else { return .unavailable }
            let id = current.id
            let before = current
            openCode.prompt(server: link.server, sessionID: current.sessionID, directory: link.directory, text: text) { ok in
                guard !ok else { return }
                Task { @MainActor [weak self] in
                    // Not delivered: show it waiting again, so the user can retry or go to OpenCode.
                    guard let self, let now = self.byID[id], now.phase == .working, now.reply == nil else { return }
                    var restored = before
                    restored.lastActivity = self.now()
                    self.update(restored)
                }
            }
        }
        current.reply = nil
        current.phase = .working
        current.activity = "Thinking"
        current.lastMessage = nil
        current.pendingRequest = nil
        current.lastActivity = now()
        update(current)
        return .sent
    }

    /// "No, stop": lets a held stop hook go with no reply, so the agent stops now as it would have without Altillo.
    func letStop(_ session: AgentSession) {
        guard var current = byID[session.id], let channel = current.reply, channel.kind == .stopHook else { return }
        releaseReply(channel)
        current.reply = nil
        update(current)
    }

    /// The Agents module was switched on or off. Off: every held hook is let go at once.
    func moduleAvailabilityChanged() {
        guard !isModuleEnabled() else { return }
        for (id, session) in byID {
            var session = session
            if let channel = session.reply, channel.kind == .stopHook {
                releaseReply(channel)
                session.reply = nil
            }
            for request in queues[id] ?? [] where !request.isExpired {
                server?.reply(requestID: request.id, decision: .none)
            }
            if queues[id] != nil {
                queues[id] = queues[id]?.map { var request = $0; request.isExpired = true; return request }
                session.pendingRequest?.isExpired = true
            }
            byID[id] = session
        }
        publish()
    }

    /// Brings the session's terminal or editor forward (the right tab when the host allows it). A stop hook holding
    /// the turn open for a reply lets go first: the user is going to answer there.
    func focus(_ session: AgentSession) {
        letStop(session)
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
        if let channel = current.reply, channel.kind == .stopHook { releaseReply(channel) }
        lastToolCalls[session.id] = nil
        openCodeQueues[session.id] = nil
        replyStreaks[session.id] = nil
        dismissed[session.id] = current.lastActivity
        byID[session.id] = nil
        publish()
    }

    // MARK: - Inputs (internal for tests)

    /// One hook call.
    func receive(_ envelope: HookEnvelope) {
        var envelope = envelope
        if envelope.waits, !isModuleEnabled() {
            // Agents module off: behave as if no hooks were installed.
            if let requestID = envelope.requestID { server?.reply(requestID: requestID, decision: .none) }
            envelope.waitsForDecision = false
            envelope.waitsForReply = false
        }
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
            guard at > dismissedAt else {
                if let requestID = envelope.requestID { server?.reply(requestID: requestID, decision: .none) }
                return
            }
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
        if case .toolWillRun(let call) = event.kind, event.subagentID == nil { lastToolCalls[id] = call }
        if case .promptSubmitted = event.kind, !envelope.rerouted { replyStreaks[id] = nil }
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
        applyReplyWait(envelope, event: event, to: &session, id: id, at: at)
        showTerminalPrompt(event, agent: agent, in: &session, id: id, at: at)
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
        if let sessionID = replyOwners.removeValue(forKey: requestID) {
            // The stop hook gave up (timeout) or the agent was interrupted: it has stopped as usual.
            if var session = byID[sessionID], session.reply?.id == requestID {
                session.reply = nil
                update(session)
            }
            return
        }
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
                if let channel = session.reply, channel.kind == .stopHook { releaseReply(channel) }
                lastToolCalls[id] = nil
                openCodeLinks[id] = nil
                openCodeQueues[id] = nil
                changed = true
                continue
            }
            if let request = session.pendingRequest, openCodeRequests[request.id] != nil,
               at.timeIntervalSince(request.requestedAt) >= Self.openCodeRequestLimit {
                // A backstop: an OpenCode card nobody answered and no reconnection cleared.
                for stale in openCodeQueues[id] ?? [] { openCodeRequests[stale.id] = nil }
                openCodeQueues[id] = nil
                var cleared = session
                cleared.pendingRequest = nil
                cleared.phase = .idle
                cleared.activity = nil
                byID[id] = cleared
                changed = true
                continue
            }
            if let channel = session.reply, channel.kind == .stopHook, aged.reply == nil { releaseReply(channel) }
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

    // MARK: - Replies and terminal-only prompts

    /// A stop hook installed with `--reply-wait` holds the end of the turn open: the session can take a reply until
    /// the hook's deadline. Any later sign of a new turn lets a still-waiting hook go. Events that came through
    /// another agent's hooks (Cursor or Copilot running Claude's) never touch it, and neither does a second report
    /// of the same turn's end.
    private func applyReplyWait(_ envelope: HookEnvelope, event: AgentEvent, to session: inout AgentSession, id: String,
                                at: Date) {
        let held = session.reply
        if envelope.waitsForReply, let requestID = envelope.requestID {
            let capped = Self.continuationCaps[event.agent].map { (replyStreaks[id] ?? 0) >= $0 } ?? false
            guard case .turnFinished = event.kind, server != nil, event.subagentID == nil, !capped,
                  let host = session.host, identifiesHost(host), !hostIsFrontmost(host) else {
                // Not a turn's end, the agent's own cap is reached, the terminal app is unknown (tmux, SSH…), or the
                // user is looking at the terminal (part C): stop as usual.
                server?.reply(requestID: requestID, decision: .none)
                if let held, held.isClosed { session.reply = nil }
                return
            }
            if let held, held.kind == .stopHook, held.id != requestID { releaseReply(held) }
            session.reply = AgentReplyChannel(
                kind: .stopHook, id: requestID, openedAt: at,
                expiresAt: at.addingTimeInterval(envelope.timeout ?? AgentWire.defaultDecisionTimeout))
            replyOwners[requestID] = id
            return
        }
        guard !envelope.rerouted, let held, held.kind == .stopHook else { return }
        switch event.kind {
        case .notification, .other, .assistantMessage, .subagentFinished, .toolDidRun, .compacting, .turnFinished:
            break // background noise, or the same turn's end reported again: the turn is still over
        default:
            releaseReply(held)
            session.reply = nil
        }
    }

    // MARK: - Going to the terminal lets a held hook go (part C)

    /// Whether the session's terminal or editor is the frontmost app: the user is looking at it and will type there.
    private func hostIsFrontmost(_ host: AgentHost?) -> Bool {
        guard let host else { return false }
        let front = frontmostApp()
        return Self.host(host, is: front.bundleID, pid: front.pid)
    }

    /// Whether `host`'s app is the app with `bundleID`/`pid` (the bundle id the hook reported, else the GUI app found
    /// walking up from the agent's process).
    static func host(_ host: AgentHost, is bundleID: String?, pid: pid_t?) -> Bool {
        if let hostID = host.appBundleID, let bundleID { return hostID == bundleID }
        guard let pid, let app = AgentTerminalFocus.application(for: host) else { return false }
        return app.processIdentifier == pid
    }

    /// An app became active: every held stop hook whose session lives in it lets go.
    func applicationActivated(bundleID: String?, pid: pid_t?) {
        for (requestID, sessionID) in replyOwners {
            guard var session = byID[sessionID], let host = session.host, Self.host(host, is: bundleID, pid: pid),
                  let channel = session.reply, channel.id == requestID else { continue }
            releaseReply(channel)
            session.reply = nil
            update(session)
        }
    }

    /// Subscribed only while at least one stop hook is held.
    private func updateActivationObserver() {
        if replyOwners.isEmpty {
            stopObservingActivations()
        } else if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let (bundleID, pid) = (app?.bundleIdentifier, app?.processIdentifier)
                MainActor.assumeIsolated { self?.applicationActivated(bundleID: bundleID, pid: pid) }
            }
        }
    }

    private func stopObservingActivations() {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    /// Whether the hub is watching app activations (tests).
    var isObservingActivations: Bool { activationObserver != nil }

    /// Lets a waiting stop hook go with no reply (the agent stops as usual).
    private func releaseReply(_ channel: AgentReplyChannel) {
        guard channel.kind == .stopHook else { return }
        replyOwners[channel.id] = nil
        if !channel.isClosed { server?.reply(requestID: channel.id, decision: .none) }
        updateActivationObserver()
    }

    /// Gemini and Copilot say a permission prompt is on screen (a notification) but can't take the answer from a
    /// hook: show what it asks about from the tool they announced, answerable only in the terminal.
    private func showTerminalPrompt(_ event: AgentEvent, agent: AgentKind, in session: inout AgentSession, id: String,
                                    at: Date) {
        guard case .notification(let type, _, _) = event.kind, type == "permission_prompt",
              !HookRunner.answerableAgents.contains(agent.rawValue), session.phase == .waitingPermission,
              session.pendingRequest == nil || session.pendingRequest?.isExpired == true,
              let call = lastToolCalls[id] else { return }
        var request = ToolDescriptions.permissionRequest(
            id: UUID().uuidString, agent: agent, call: call, suggestions: [], cwd: session.cwd, requestedAt: at,
            expiresAt: at)
        request.canAllowForSession = false
        session.pendingRequest = request
        session.activity = ToolDescriptions.activity(for: call, cwd: session.cwd)
    }

    // MARK: - OpenCode

    /// One event from an OpenCode server.
    func receive(openCode event: OpenCodeEvent, directory: String?, server: OpenCodeMonitor.Server) {
        let at = now()
        func key(_ sessionID: String) -> String { "\(AgentKind.opencode.rawValue):\(sessionID)" }
        switch event {
        case .connected, .other:
            return
        case .session(let sessionID, let dir, _, let parentID, _):
            guard parentID == nil else {
                openCodeChildren.insert(sessionID)
                return
            }
            mutateOpenCode(sessionID, directory: dir ?? directory, server: server, at: at, activity: false) { _ in }
        case .deleted(let sessionID):
            let id = key(sessionID)
            openCodeLinks[id] = nil
            openCodeText[id] = nil
            if byID.removeValue(forKey: id) != nil { publish() }
        case .status(let sessionID, let status):
            guard !openCodeChildren.contains(sessionID) else { return }
            if status == "idle" {
                openCodeTurnEnded(sessionID, directory: directory, server: server, at: at)
            } else {
                mutateOpenCode(sessionID, directory: directory, server: server, at: at) { session in
                    session.reply = nil
                    guard !session.isBlockedOnPermission else { return }
                    if session.phase != .working { session.lastMessage = nil }
                    session.phase = .working
                    session.activity = status == "retry" ? "Retrying" : (session.activity ?? "Thinking")
                }
            }
        case .idle(let sessionID):
            guard !openCodeChildren.contains(sessionID) else { return }
            openCodeTurnEnded(sessionID, directory: directory, server: server, at: at)
        case .error(let sessionID, let message):
            guard let sessionID, !openCodeChildren.contains(sessionID) else { return }
            mutateOpenCode(sessionID, directory: directory, server: server, at: at) { session in
                session.reply = nil
                session.pendingRequest = nil
                session.activity = nil
                if message?.contains("Abort") == true {
                    session.phase = .idle
                } else {
                    session.phase = .failed
                    session.lastMessage = message ?? "The turn failed"
                }
            }
        case .messageRole(_, let messageID, let role):
            if openCodeRoles.count > 2048 { openCodeRoles.removeAll() }
            openCodeRoles[messageID] = role
        case .text(let sessionID, let messageID, let text):
            // Streams on every token: keep it aside and show it when the turn ends.
            if openCodeRoles[messageID] == "assistant" { openCodeText[key(sessionID)] = text }
        case .tool(let sessionID, let call, let status):
            guard !openCodeChildren.contains(sessionID), status == "running" || status == "pending" else { return }
            mutateOpenCode(sessionID, directory: directory, server: server, at: at) { session in
                guard !session.isBlockedOnPermission else { return }
                session.phase = .working
                session.reply = nil
                session.activity = ToolDescriptions.activity(for: call, cwd: session.cwd)
            }
        case .permissionAsked(let permission):
            guard !openCodeChildren.contains(permission.sessionID) else { return }
            openCodePermissionAsked(permission, directory: directory, server: server, at: at)
        case .permissionReplied(let sessionID, let requestID):
            openCodePermissionGone(requestID, sessionID: key(sessionID), at: at)
        }
    }

    /// Queues an OpenCode permission (several can wait at once in one session); the oldest is on the card.
    private func openCodePermissionAsked(_ permission: OpenCodePermission, directory: String?,
                                         server: OpenCodeMonitor.Server, at: Date) {
        let id = "\(AgentKind.opencode.rawValue):\(permission.sessionID)"
        guard openCodeRequests[permission.id] == nil else { return }
        mutateOpenCode(permission.sessionID, directory: directory, server: server, at: at) { session in
            var request = ToolDescriptions.permissionRequest(
                id: permission.id, agent: .opencode, call: permission.toolCall, suggestions: [], cwd: session.cwd,
                requestedAt: at, expiresAt: nil)
            // OpenCode's own "Always allow" (for this session's patterns), when it offers one.
            request.canAllowForSession = !permission.always.isEmpty
            var queue = self.openCodeQueues[id] ?? []
            queue.append(request)
            self.openCodeQueues[id] = queue
            session.pendingRequest = queue.first
            session.phase = .waitingPermission
            session.reply = nil
            if queue.count == 1 { session.activity = ToolDescriptions.activity(for: permission.toolCall, cwd: session.cwd) }
        }
        openCodeRequests[permission.id] = id
    }

    /// An OpenCode permission was answered (here, in OpenCode, or it's gone): show the next, or back to work.
    private func openCodePermissionGone(_ requestID: String, sessionID id: String, at: Date) {
        openCodeRequests[requestID] = nil
        openCodeQueues[id]?.removeAll { $0.id == requestID }
        if openCodeQueues[id]?.isEmpty == true { openCodeQueues[id] = nil }
        guard var session = byID[id], session.pendingRequest?.id == requestID else { return }
        if let next = openCodeQueues[id]?.first {
            session.pendingRequest = next
            session.phase = .waitingPermission
            session.lastActivity = at
            update(session)
        } else {
            update(AgentStateMachine.resolvePermission(requestID, in: session, next: nil, decision: nil, at: at))
        }
    }

    private func openCodeTurnEnded(_ sessionID: String, directory: String?, server: OpenCodeMonitor.Server, at: Date) {
        let id = "\(AgentKind.opencode.rawValue):\(sessionID)"
        guard let current = byID[id], current.phase == .working || current.phase == .waitingPermission else { return }
        mutateOpenCode(sessionID, directory: directory, server: server, at: at) { session in
            session.phase = .waitingAnswer
            session.activity = nil
            session.pendingRequest = nil
            if let text = self.openCodeText.removeValue(forKey: id) { session.lastMessage = text }
            session.reply = AgentReplyChannel(kind: .server, id: sessionID, openedAt: at)
        }
    }

    /// Creates or changes an OpenCode session. `activity: false` records the link without counting as news.
    private func mutateOpenCode(_ sessionID: String, directory: String?, server: OpenCodeMonitor.Server, at: Date,
                                activity: Bool = true, _ change: (inout AgentSession) -> Void) {
        let id = "\(AgentKind.opencode.rawValue):\(sessionID)"
        var link = openCodeLinks[id] ?? OpenCodeLink(server: server, directory: directory)
        link.server = server
        if let directory { link.directory = directory }
        openCodeLinks[id] = link
        if let dismissedAt = dismissed[id] {
            guard activity, at > dismissedAt else { return }
            dismissed[id] = nil
        }
        guard activity || byID[id] != nil else { return }
        var session = byID[id] ?? AgentSession(agent: .opencode, sessionID: sessionID, cwd: link.directory ?? "",
                                               phase: .idle, startedAt: at, lastActivity: at, source: .server)
        if session.cwd.isEmpty, let directory = link.directory {
            session.cwd = directory
            session.project = URL(fileURLWithPath: directory).lastPathComponent
        }
        session.source = .server
        change(&session)
        if activity { session.lastActivity = at }
        update(session)
    }

    /// Answers an OpenCode permission. The card moves on at once; if OpenCode doesn't take the answer, the request
    /// comes back first in line with the error on it, still answerable.
    private func decideOpenCode(_ requestID: String, _ decision: AgentDecision, sessionID: String) {
        guard let request = openCodeQueues[sessionID]?.first(where: { $0.id == requestID }) else { return }
        guard let link = openCodeLinks[sessionID], let openCode else {
            openCodeFailed(request, sessionID: sessionID)
            return
        }
        openCodePermissionGone(requestID, sessionID: sessionID, at: now())
        openCode.replyPermission(server: link.server, requestID: requestID, directory: link.directory,
                                 decision: decision) { ok in
            guard !ok else { return }
            Task { @MainActor [weak self] in self?.openCodeFailed(request, sessionID: sessionID) }
        }
    }

    private func openCodeFailed(_ request: AgentPermissionRequest, sessionID: String) {
        guard var session = byID[sessionID] else { return }
        var request = request
        request.failure = String(localized: "OpenCode didn't take the answer. Try again, or answer it in OpenCode.")
        var queue = (openCodeQueues[sessionID] ?? []).filter { $0.id != request.id }
        queue.insert(request, at: 0)
        openCodeQueues[sessionID] = queue
        openCodeRequests[request.id] = sessionID
        session.pendingRequest = request
        session.phase = .waitingPermission
        session.lastActivity = now()
        update(session)
    }

    /// On every (re)connection: what's really pending and who's really busy, so nothing the stream missed stays on
    /// screen (answered while Altillo was away, a dropped connection, a server restart).
    func reconcileOpenCode(_ server: OpenCodeMonitor.Server) {
        let directories: [String?] = [nil] + Set(openCodeLinks.values.filter { $0.server == server }
            .compactMap(\.directory)).sorted()
        openCode?.fetchState(server: server, directories: directories) { states in
            Task { @MainActor [weak self] in self?.apply(states, from: server) }
        }
    }

    /// Applies what the server says is pending (internal for tests).
    func apply(_ states: [OpenCodeMonitor.State], from server: OpenCodeMonitor.Server) {
        let at = now()
        for state in states {
            let pending = Set(state.permissions.map(\.id))
            // Answered or gone while we weren't listening. Only for sessions of the directory that was asked.
            for (id, link) in openCodeLinks where link.server == server && state.directory != nil
                && link.directory == state.directory {
                for request in openCodeQueues[id] ?? [] where !pending.contains(request.id) {
                    openCodePermissionGone(request.id, sessionID: id, at: at)
                }
                guard let session = byID[id], session.phase == .working else { continue }
                let status = state.statuses[session.sessionID] ?? "idle"
                if status == "idle" { openCodeTurnEnded(session.sessionID, directory: link.directory, server: server, at: at) }
            }
            for permission in state.permissions where !openCodeChildren.contains(permission.sessionID) {
                openCodePermissionAsked(permission, directory: state.directory, server: server, at: at)
            }
            for (sessionID, status) in state.statuses where status != "idle" && !openCodeChildren.contains(sessionID) {
                receive(openCode: .status(sessionID: sessionID, status: status), directory: state.directory, server: server)
            }
        }
    }

    private func openCodeServerGone(_ server: OpenCodeMonitor.Server) {
        var changed = false
        for (id, link) in openCodeLinks where link.server == server {
            openCodeLinks[id] = nil
            openCodeQueues[id] = nil
            guard var session = byID[id] else { continue }
            session.phase = .finished
            session.activity = nil
            session.pendingRequest = nil
            session.reply = nil
            byID[id] = session
            changed = true
        }
        openCodeRequests = openCodeRequests.filter { openCodeLinks[$0.value] != nil }
        if changed { publish() }
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
        updateActivationObserver()
    }

    /// Arms one timer for the earliest moment a session should change on its own.
    private func scheduleSweep() {
        let backstops = byID.values.compactMap { session -> Date? in
            guard let request = session.pendingRequest, openCodeRequests[request.id] != nil else { return nil }
            return request.requestedAt.addingTimeInterval(Self.openCodeRequestLimit)
        }
        let next = (byID.values.compactMap(AgentSessionAging.nextDeadline) + backstops).min()
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
