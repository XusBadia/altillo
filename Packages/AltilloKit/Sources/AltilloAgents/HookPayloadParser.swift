import AltilloCore
import Foundation

/// Turns a hook's stdin JSON into an `AgentEvent`. Tolerant and versioned by behaviour rather than by schema:
/// fields are read when present, unknown events become `.other`, and nothing here throws.
///
/// Verified against Claude Code 2.1.281 and Codex 0.152.0 (September 2026; fixtures in the package tests):
/// both send `session_id`, `transcript_path`, `cwd`, `hook_event_name`, plus `permission_mode` on most events;
/// tool events carry `tool_name` / `tool_input` / `tool_use_id` (PermissionRequest has no `tool_use_id`);
/// `Stop` carries `last_assistant_message`. Codex adds `turn_id` and `model`; Claude adds `prompt_id`, and
/// `agent_id` / `agent_type` when the hook fires inside a subagent.
public enum HookPayloadParser {
    /// `eventName` is the event the hook was installed for (the CLI's second argument); the payload's
    /// `hook_event_name` wins when present. Returns nil only when the payload has no session id.
    public static func parse(agent: AgentKind, eventName: String?, payload: JSONValue) -> AgentEvent? {
        guard let sessionID = payload["session_id"].nonEmptyString ?? payload["thread_id"].nonEmptyString
            ?? payload["thread-id"].nonEmptyString else { return nil }
        let name = payload["hook_event_name"].nonEmptyString ?? eventName ?? "Unknown"
        let tool = toolCall(payload)

        let kind: AgentEvent.Kind
        switch normalized(name) {
        case "sessionstart":
            kind = .sessionStarted(source: payload["source"].nonEmptyString)
        case "sessionend":
            kind = .sessionEnded(reason: payload["reason"].nonEmptyString)
        case "userpromptsubmit":
            kind = .promptSubmitted(prompt: payload["prompt"]?.string)
        case "pretooluse":
            kind = tool.map { .toolWillRun($0) } ?? .other(name: name)
        case "posttooluse":
            kind = tool.map { .toolDidRun($0, failed: false) } ?? .other(name: name)
        case "posttoolusefailure":
            kind = tool.map { .toolDidRun($0, failed: true) } ?? .other(name: name)
        case "permissionrequest":
            kind = tool.map { .permissionRequested($0, suggestions: payload["permission_suggestions"]?.array ?? []) }
                ?? .other(name: name)
        case "notification":
            kind = .notification(type: payload["notification_type"].nonEmptyString,
                                 message: payload["message"]?.string, title: payload["title"]?.string)
        case "stop":
            kind = .turnFinished(lastMessage: payload["last_assistant_message"].nonEmptyString)
        case "stopfailure":
            kind = .turnFailed(error: payload["error"].nonEmptyString,
                               message: payload["last_assistant_message"].nonEmptyString
                                   ?? payload["error_details"].nonEmptyString)
        case "subagentstart":
            kind = .subagentStarted(type: payload["agent_type"].nonEmptyString)
        case "subagentstop":
            kind = .subagentFinished(type: payload["agent_type"].nonEmptyString,
                                     lastMessage: payload["last_assistant_message"].nonEmptyString)
        case "interrupt":
            kind = .interrupted
        case "precompact":
            kind = .compacting(done: false)
        case "postcompact":
            kind = .compacting(done: true)
        case "agent-turn-complete", "agentturncomplete":
            // Codex's legacy `notify` program payload.
            kind = .turnFinished(lastMessage: payload["last-assistant-message"].nonEmptyString)
        default:
            kind = .other(name: name)
        }

        // Subagent-scoped fields: on Claude every event inside a subagent carries `agent_id`; on the subagent's
        // own Start/Stop events they describe the subagent itself, which the kind already says.
        let isSubagentLifecycle: Bool
        switch kind {
        case .subagentStarted, .subagentFinished: isSubagentLifecycle = true
        default: isSubagentLifecycle = false
        }

        return AgentEvent(
            agent: agent, sessionID: sessionID, kind: kind, name: name,
            cwd: payload["cwd"].nonEmptyString,
            transcriptPath: payload["transcript_path"].nonEmptyString,
            permissionMode: payload["permission_mode"].nonEmptyString,
            model: payload["model"].nonEmptyString,
            subagentID: isSubagentLifecycle ? nil : payload["agent_id"].nonEmptyString,
            subagentType: isSubagentLifecycle ? nil : payload["agent_type"].nonEmptyString)
    }

    static func toolCall(_ payload: JSONValue) -> AgentToolCall? {
        guard let name = payload["tool_name"].nonEmptyString else { return nil }
        return AgentToolCall(name: name, input: payload["tool_input"] ?? .object([:]),
                             id: payload["tool_use_id"].nonEmptyString)
    }

    /// "PreToolUse", "pre_tool_use", "preToolUse" → "pretooluse" (Copilot/Gemini spell them differently).
    static func normalized(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "_", with: "")
    }
}
