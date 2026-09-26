import AltilloCore
import Foundation

/// What `altillo-hook` prints on stdout for a `PermissionRequest` once the user decided in the notch.
///
/// Verified schemas (September 2026):
/// - Claude Code 2.1.281: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":
///   "allow"|"deny", "updatedPermissions":[…]?, "message":"…"?}}}`. "Allow for this session" echoes the
///   request's `permission_suggestions` as `updatedPermissions` with `destination` forced to `session`
///   (nothing is ever written to the user's settings files).
/// - Codex 0.152.0: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":
///   "allow"|"deny","message":"…"?}}}`. `updatedPermissions`/`updatedInput`/`interrupt` are reserved and fail
///   closed, so Codex never gets them; "allow for session" degrades to a plain allow.
/// No decision (timeout, the user ignored it, Altillo closed) → print nothing: the agent asks in the terminal.
public enum HookDecisionOutput {
    public static let denyMessage = "The user denied this from Altillo."

    /// The stdout bytes for `decision`, or nil to print nothing.
    public static func output(agent: AgentKind, decision: WireDecision, payload: JSONValue) -> Data? {
        let decisionObject: [String: JSONValue]
        switch decision {
        case .none, .reply:
            return nil
        case .deny:
            decisionObject = ["behavior": .string("deny"), "message": .string(denyMessage)]
        case .allow:
            decisionObject = ["behavior": .string("allow")]
        case .allowForSession:
            var object: [String: JSONValue] = ["behavior": .string("allow")]
            if agent == .claude {
                let updates = ClaudeSessionPermissions.updates(for: payload)
                if !updates.isEmpty { object["updatedPermissions"] = .array(updates) }
            }
            decisionObject = object
        }
        let output: JSONValue = .object([
            "hookSpecificOutput": .object([
                "hookEventName": .string("PermissionRequest"),
                "decision": .object(decisionObject),
            ]),
        ])
        return output.data
    }
}

/// What a stop hook installed with `--reply-wait` prints when the user replied from the notch: the agent's own "don't
/// stop yet, carry on with this" answer (phase 14). No reply (timeout, Altillo closed) → nothing: the agent stops.
///
/// Verified schemas (September 2026):
/// - Claude Code 2.1.281 `Stop` (live): `{"decision":"block","reason":"…"}`. Claude gets the reason as a user turn
///   ("Stop hook feedback: …") and carries on; the next `Stop` has `stop_hook_active: true`.
/// - Codex 0.152.0 `Stop` (schema + source, `codex-rs/hooks/src/events/stop.rs`): same shape; the reason becomes the
///   continuation prompt.
/// - Gemini CLI 0.61.0 `AfterAgent` (bundled docs): `{"decision":"deny","reason":"…"}`; the reason is sent to the
///   agent as a new prompt.
/// - Copilot CLI 1.0.88 `agentStop` (docs.github.com hooks reference): `{"decision":"block","reason":"…"}`; after
///   8 consecutive blocks the CLI ends the turn anyway.
/// - Cursor CLI 2026.09.23 `stop` (bundled source): `{"followup_message":"…"}`; `loop_limit` caps the follow-ups.
public enum HookReplyOutput {
    /// The agents whose stop hook can take a reply, and the event it is installed on.
    public static func stopEvent(for agent: AgentKind) -> String? {
        switch agent {
        case .claude, .codex: "Stop"
        case .gemini: "AfterAgent"
        case .copilot: "agentStop"
        case .cursor: "stop"
        default: nil
        }
    }

    /// Whether `event` is `agent`'s stop event (any spelling).
    public static func isStopEvent(_ event: String, agent: AgentKind) -> Bool {
        guard let stop = stopEvent(for: agent) else { return false }
        return HookPayloadParser.normalized(event) == HookPayloadParser.normalized(stop)
    }

    /// Frames the reply so the agent knows it comes from the user, not from a check the hook ran.
    public static func framed(_ text: String) -> String {
        "The user replied from Altillo (their notch):\n\n" + text
    }

    /// The stdout bytes for a reply, or nil to print nothing.
    public static func output(agent: AgentKind, text: String?) -> Data? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let reason = JSONValue.string(framed(text))
        let object: [String: JSONValue]
        switch agent {
        case .claude, .codex, .copilot: object = ["decision": .string("block"), "reason": reason]
        case .gemini: object = ["decision": .string("deny"), "reason": reason]
        case .cursor: object = ["followup_message": reason]
        default: return nil
        }
        return JSONValue.object(object).data
    }
}

/// Claude's "don't ask again this session", built only from what Claude itself suggested for the request.
public enum ClaudeSessionPermissions {
    /// Suggestion types Altillo may echo. `setMode` only to `acceptEdits` (what Claude's own dialog offers);
    /// never a mode that widens permissions further, and nothing that removes rules.
    static let echoableTypes: Set<String> = ["addRules", "addDirectories", "setMode"]
    static let echoableModes: Set<String> = ["acceptEdits"]

    public static func canAllowForSession(agent: AgentKind, call: AgentToolCall, suggestions: [JSONValue]) -> Bool {
        guard agent == .claude else { return false }
        if call.command != nil { return true }
        return suggestions.contains { sanitized($0) != nil }
    }

    /// The `updatedPermissions` entries for an "allow for session" answer to `payload` (a PermissionRequest).
    public static func updates(for payload: JSONValue) -> [JSONValue] {
        var updates = (payload["permission_suggestions"]?.array ?? []).compactMap(sanitized)
        let hasRule = updates.contains { $0["type"]?.string == "addRules" }
        if !hasRule, let tool = payload["tool_name"].nonEmptyString,
           let command = AgentToolCall(name: tool, input: payload["tool_input"] ?? .null).command {
            // Claude's dialog offers "don't ask again for this command"; the exact command, this session only.
            updates.append(.object([
                "type": .string("addRules"),
                "rules": .array([.object(["toolName": .string(tool), "ruleContent": .string(command)])]),
                "behavior": .string("allow"),
                "destination": .string("session"),
            ]))
        }
        return updates
    }

    static func sanitized(_ suggestion: JSONValue) -> JSONValue? {
        guard var object = suggestion.object, let type = object["type"]?.string, echoableTypes.contains(type) else {
            return nil
        }
        if type == "setMode" {
            guard let mode = object["mode"]?.string, echoableModes.contains(mode) else { return nil }
        }
        if type == "addRules", object["behavior"]?.string != "allow" { return nil }
        object["destination"] = .string("session")
        return .object(object)
    }
}
