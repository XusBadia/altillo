import AltilloCore
import Darwin
import Foundation

/// Everything `altillo-hook <agent> <event> [--timeout seconds]` does, as a testable function.
///
/// Contract (PLAN §1, §5.3): the agent must behave exactly as without Altillo whenever Altillo can't answer.
/// - Always exit 0. Never print anything except a PermissionRequest decision the user made in the notch.
/// - Altillo not running (no socket, nobody listening) → return at once, no output.
/// - Fire-and-forget for every event but PermissionRequest.
/// - PermissionRequest: wait up to the timeout for the user's decision; none/timeout → no output, so the agent
///   asks in the terminal as usual. Never approves on its own.
public enum HookRunner {
    public struct Invocation: Sendable, Equatable {
        public var agent: String
        public var event: String
        public var timeout: Double
    }

    /// Parses the command line (arguments without the executable). nil = nothing to do.
    public static func invocation(arguments: [String], environment: [String: String]) -> Invocation? {
        var positional: [String] = []
        var timeout: Double?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--timeout", index + 1 < arguments.count {
                timeout = Double(arguments[index + 1])
                index += 2
                continue
            }
            if argument.hasPrefix("--timeout=") {
                timeout = Double(argument.dropFirst("--timeout=".count))
            } else if !argument.hasPrefix("--") {
                positional.append(argument)
            }
            index += 1
        }
        guard positional.count >= 2, !positional[0].isEmpty, !positional[1].isEmpty else { return nil }
        let resolved = timeout ?? environment[AgentWire.timeoutEnvironment].flatMap(Double.init)
            ?? AgentWire.defaultDecisionTimeout
        return Invocation(agent: positional[0].lowercased(), event: positional[1],
                          timeout: min(max(resolved, 1), 3600))
    }

    /// Seconds to reach the app and to hand it the event.
    public static let connectTimeout: Double = 1
    public static let writeTimeout: Double = 2

    public static func waitsForDecision(event: String) -> Bool {
        HookPayloadParser.normalized(event) == "permissionrequest"
    }

    /// Runs one hook call. `readStdin` is called once (always: agents may treat an unread pipe as a failed hook).
    /// Returns the bytes to print, or nil.
    public static func run(
        arguments: [String], environment: [String: String], readStdin: () -> Data,
        ancestors: () -> [ProcessTree.Entry] = { ProcessTree.ancestors() }
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
        let waits = waitsForDecision(event: invocation.event)
        let requestID = waits ? UUID().uuidString : nil
        var env: [String: String] = [:]
        for key in HookEnvelope.forwardedEnvironment {
            if let value = environment[key], !value.isEmpty { env[key] = value }
        }
        let envelope = HookEnvelope(
            agent: invocation.agent, event: invocation.event, payload: payload, env: env,
            ppids: chain.map(\.pid), tty: ProcessTree.tty(in: chain), agentPID: ProcessTree.agentPID(in: chain),
            waitsForDecision: waits, requestID: requestID, timeout: waits ? invocation.timeout : nil)
        guard let frame = AgentWire.frame(envelope) else { return nil }

        // Every step has a deadline: a stopped or wedged app (full socket buffer, full backlog) costs the agent
        // at most connectTimeout + writeTimeout, never a hang.
        let fd: Int32
        do { fd = try UnixSocket.connect(path: socketPath, timeout: connectTimeout) } catch { return nil }
        defer { close(fd) }
        guard UnixSocket.writeAll(fd, frame, timeout: writeTimeout) else { return nil }
        // Fire-and-forget: never wait for a reply.
        guard waits, let requestID else { return nil }

        guard let line = UnixSocket.readLine(fd, timeout: invocation.timeout),
              let reply = AgentWire.decodeReply(line), reply.requestID == requestID else { return nil }
        return HookDecisionOutput.output(agent: AgentKind(rawValue: invocation.agent), decision: reply.decision,
                                         payload: payload)
    }
}
