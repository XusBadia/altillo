import AltilloCore
import Darwin
import Foundation

/// Everything `altillo-hook <agent> <event> [--timeout seconds] [--reply-wait seconds]` does, as a testable function.
///
/// Contract (PLAN §1, §5.3): the agent must behave exactly as without Altillo whenever Altillo can't answer.
/// - Always exit 0. Never print anything except a PermissionRequest decision the user made in the notch.
/// - Altillo not running (no socket, nobody listening) → return at once, no output.
/// - Fire-and-forget for every event but PermissionRequest.
/// - PermissionRequest: wait up to the timeout for the user's decision; none/timeout → no output, so the agent
///   asks in the terminal as usual. Never approves on its own. Only for agents whose answer schema is verified
///   (Claude Code, Codex); any other agent's permission event is fire-and-forget.
/// - Stop event installed with `--reply-wait N` (opt-in, phase 14), in an interactive terminal session: wait up to
///   N s for a reply typed in the notch; none/timeout → no output, so the agent stops as usual.
public enum HookRunner {
    public struct Invocation: Sendable, Equatable {
        public var agent: String
        public var event: String
        public var timeout: Double
        /// `--reply-wait`: how long the stop hook holds the turn open for a reply. nil: it doesn't.
        public var replyWait: Double? = nil
    }

    /// Parses the command line (arguments without the executable). nil = nothing to do.
    public static func invocation(arguments: [String], environment: [String: String]) -> Invocation? {
        var positional: [String] = []
        var timeout: Double?
        var replyWait: Double?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--timeout", index + 1 < arguments.count {
                timeout = Double(arguments[index + 1])
                index += 2
                continue
            }
            if argument == "--reply-wait", index + 1 < arguments.count {
                replyWait = Double(arguments[index + 1])
                index += 2
                continue
            }
            if argument.hasPrefix("--timeout=") {
                timeout = Double(argument.dropFirst("--timeout=".count))
            } else if argument.hasPrefix("--reply-wait=") {
                replyWait = Double(argument.dropFirst("--reply-wait=".count))
            } else if !argument.hasPrefix("--") {
                positional.append(argument)
            }
            index += 1
        }
        guard positional.count >= 2, !positional[0].isEmpty, !positional[1].isEmpty else { return nil }
        let resolved = timeout ?? environment[AgentWire.timeoutEnvironment].flatMap(Double.init)
            ?? AgentWire.defaultDecisionTimeout
        return Invocation(agent: positional[0].lowercased(), event: positional[1],
                          timeout: min(max(resolved, 1), 3600),
                          replyWait: replyWait.flatMap { $0 > 0 ? min(max($0, 1), 3600) : nil })
    }

    /// Seconds to reach the app and to hand it the event.
    public static let connectTimeout: Double = 1
    public static let writeTimeout: Double = 2

    /// Agents whose PermissionRequest answer schema is verified: only their permission hooks wait for the notch.
    /// (Copilot's `permissionRequest` fires before its own rules and auto-approvals, for every tool call, so waiting
    /// there would stall the agent; Gemini's and Cursor's hooks can't answer a prompt at all.)
    public static let answerableAgents: Set<String> = ["claude", "codex"]

    public static func waitsForDecision(event: String, agent: String = "claude") -> Bool {
        answerableAgents.contains(agent) && HookPayloadParser.normalized(event) == "permissionrequest"
    }

    /// The agent that really sent the payload. Cursor's CLI also runs the hooks in Claude Code's settings.json, with
    /// its own payload (`cursor_version`, `conversation_id`); Copilot CLI reads a repository's `.claude/settings.json`
    /// (docs.github.com hooks reference), recognised by its process. Those events are observe-only.
    public static func effectiveAgent(installedFor agent: String, payload: JSONValue,
                                      chain: [ProcessTree.Entry] = []) -> String {
        if agent != "cursor", payload["cursor_version"] != nil { return "cursor" }
        if agent != "copilot", let pid = ProcessTree.agentPID(in: chain),
           let name = chain.first(where: { $0.pid == pid })?.name.lowercased(), name.hasPrefix("copilot") {
            return "copilot"
        }
        return agent
    }

    /// Cursor ignores a stop hook's follow-up once `loop_count` reaches the hook's `loop_limit` (5 unless set, per
    /// Cursor's hooks docs): don't hold the turn open for a reply that couldn't be used.
    public static let cursorLoopLimit = 5

    static func underContinuationCap(agent: String, payload: JSONValue) -> Bool {
        guard agent == "cursor", let count = payload["loop_count"]?.number else { return true }
        return Int(count) < cursorLoopLimit
    }

    /// Runs one hook call. `readStdin` is called once (always: agents may treat an unread pipe as a failed hook).
    /// Returns the bytes to print, or nil.
    public static func run(
        arguments: [String], environment: [String: String], readStdin: () -> Data,
        ancestors: () -> [ProcessTree.Entry] = { ProcessTree.ancestors() },
        agentArguments: (Int32) -> [String]? = { ProcessTree.arguments(of: $0) },
        stdinIsTerminal: (Int32) -> Bool = { ProcessTree.stdinIsTerminal($0) }
    ) -> Data? {
        let input = readStdin()
        guard let invocation = invocation(arguments: arguments, environment: environment) else { return nil }
        let socketPath = AgentWire.socketPath(environment: environment)
        // Cheapest possible check first: Altillo not running → no socket file.
        guard access(socketPath, F_OK) == 0 else { return nil }
        guard var payload = JSONValue.parse(input), payload.object != nil else { return nil }
        if input.count > 64 << 10, case .object(var object) = payload {
            // The app never needs tool output; keep the message small.
            object["tool_response"] = nil
            payload = .object(object)
        }

        let chain = ancestors()
        let agent = effectiveAgent(installedFor: invocation.agent, payload: payload, chain: chain)
        let rerouted = agent != invocation.agent
        let waitsDecision = !rerouted && waitsForDecision(event: invocation.event, agent: agent)
        let waitsReply = !rerouted && !waitsDecision && invocation.replyWait != nil
            && HookReplyOutput.isStopEvent(invocation.event, agent: AgentKind(rawValue: agent))
            && underContinuationCap(agent: agent, payload: payload)
            && ProcessTree.isInteractiveSession(agent: agent, chain: chain,
                                                agentArguments: ProcessTree.agentPID(in: chain).flatMap(agentArguments),
                                                environment: environment, stdinIsTerminal: stdinIsTerminal)
        let waits = waitsDecision || waitsReply
        let waitTimeout = waitsReply ? (invocation.replyWait ?? invocation.timeout) : invocation.timeout
        let requestID = waits ? UUID().uuidString : nil
        var env: [String: String] = [:]
        for key in HookEnvelope.forwardedEnvironment {
            if let value = environment[key], !value.isEmpty { env[key] = value }
        }
        let envelope = HookEnvelope(
            agent: agent, event: invocation.event, payload: payload, env: env,
            ppids: chain.map(\.pid), tty: ProcessTree.tty(in: chain), agentPID: ProcessTree.agentPID(in: chain),
            waitsForDecision: waitsDecision, waitsForReply: waitsReply, rerouted: rerouted, requestID: requestID,
            timeout: waits ? waitTimeout : nil)
        guard let frame = AgentWire.frame(envelope) else { return nil }

        // Every step has a deadline: a stopped or wedged app (full socket buffer, full backlog) costs the agent
        // at most connectTimeout + writeTimeout, never a hang.
        let fd: Int32
        do { fd = try UnixSocket.connect(path: socketPath, timeout: connectTimeout) } catch { return nil }
        defer { close(fd) }
        guard UnixSocket.writeAll(fd, frame, timeout: writeTimeout) else { return nil }
        // Fire-and-forget: never wait for a reply.
        guard waits, let requestID else { return nil }

        guard let line = UnixSocket.readLine(fd, timeout: waitTimeout),
              let reply = AgentWire.decodeReply(line), reply.requestID == requestID else { return nil }
        if waitsReply {
            guard reply.decision == .reply else { return nil }
            return HookReplyOutput.output(agent: AgentKind(rawValue: agent), text: reply.text)
        }
        return HookDecisionOutput.output(agent: AgentKind(rawValue: agent), decision: reply.decision,
                                         payload: payload)
    }
}
