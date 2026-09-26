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
    ///
    /// Phase 14 adds (field names from each CLI's docs/source; see docs/agentes-en-vivo.md):
    /// - Gemini CLI 0.61.0: snake_case like Claude; events `BeforeAgent`, `AfterAgent` (`prompt_response`),
    ///   `BeforeTool`/`AfterTool`, `Notification` (`notification_type: "ToolPermission"`, `details`), `PreCompress`.
    /// - Copilot CLI 1.0.88 (camelCase events): `sessionId`, `toolName`, `toolArgs` (object, or a JSON string),
    ///   `userPromptSubmitted`, `agentStop`, `errorOccurred` (`error.message`, `recoverable`), `notification`
    ///   (`agent_idle`, `permission_prompt`…). Its `permissionRequest` fires before Copilot's own rules for every
    ///   tool call, so it only reports activity.
    /// - Cursor 2026.09.23: `conversation_id`/`session_id`, `workspace_roots`, `beforeSubmitPrompt`, `preToolUse`,
    ///   `postToolUse(Failure)`, `stop` (`status`: completed/aborted/error), `afterAgentResponse` (`text`),
    ///   `subagentStart`/`subagentStop` (`subagent_type`, `summary`).
    public static func parse(agent: AgentKind, eventName: String?, payload: JSONValue) -> AgentEvent? {
        guard let sessionID = payload["session_id"].nonEmptyString ?? payload["sessionId"].nonEmptyString
            ?? payload["conversation_id"].nonEmptyString ?? payload["thread_id"].nonEmptyString
            ?? payload["thread-id"].nonEmptyString else { return nil }
        let name = payload["hook_event_name"].nonEmptyString ?? payload["hookEventName"].nonEmptyString
            ?? eventName ?? "Unknown"
        let tool = toolCall(payload)

        let kind: AgentEvent.Kind
        switch normalized(name) {
        case "sessionstart":
            kind = .sessionStarted(source: payload["source"].nonEmptyString)
        case "sessionend":
            kind = .sessionEnded(reason: payload["reason"].nonEmptyString)
        case "userpromptsubmit", "userpromptsubmitted", "beforeagent", "beforesubmitprompt":
            kind = .promptSubmitted(prompt: payload["prompt"]?.string)
        case "pretooluse", "beforetool":
            kind = tool.map { .toolWillRun($0) } ?? .other(name: name)
        case "posttooluse", "aftertool":
            let failed = payload["tool_response"]?["error"].nonEmptyString != nil
                || payload["toolResult"]?["resultType"]?.string == "failure"
            kind = tool.map { .toolDidRun($0, failed: failed) } ?? .other(name: name)
        case "posttoolusefailure":
            kind = tool.map { .toolDidRun($0, failed: true) } ?? .other(name: name)
        case "permissionrequest":
            if HookRunner.answerableAgents.contains(agent.rawValue) {
                kind = tool.map { .permissionRequested($0, suggestions: payload["permission_suggestions"]?.array ?? []) }
                    ?? .other(name: name)
            } else {
                // Copilot: not a prompt yet (its rules and approvals run after this hook), only what's about to run.
                kind = tool.map { .toolWillRun($0) } ?? .other(name: name)
            }
        case "notification":
            kind = .notification(type: notificationType(payload["notification_type"].nonEmptyString
                                    ?? payload["notificationType"].nonEmptyString),
                                 message: payload["message"]?.string, title: payload["title"]?.string)
        case "stop", "agentstop", "afteragent":
            switch payload["status"]?.string {
            case "aborted": kind = .interrupted
            case "error": kind = .turnFailed(error: "error", message: nil)
            default:
                kind = .turnFinished(lastMessage: payload["last_assistant_message"].nonEmptyString
                    ?? payload["prompt_response"].nonEmptyString)
            }
        case "stopfailure":
            kind = .turnFailed(error: payload["error"].nonEmptyString,
                               message: payload["last_assistant_message"].nonEmptyString
                                   ?? payload["error_details"].nonEmptyString)
        case "erroroccurred":
            if payload["recoverable"]?.bool == true {
                kind = .other(name: name)
            } else {
                kind = .turnFailed(error: payload["error"]?["name"].nonEmptyString,
                                   message: payload["error"]?["message"].nonEmptyString ?? payload["error"].nonEmptyString)
            }
        case "subagentstart":
            kind = .subagentStarted(type: subagentType(payload))
        case "subagentstop":
            kind = .subagentFinished(type: subagentType(payload),
                                     lastMessage: payload["last_assistant_message"].nonEmptyString
                                         ?? payload["response"].nonEmptyString ?? payload["summary"].nonEmptyString)
        case "afteragentresponse":
            kind = payload["text"].nonEmptyString.map { .assistantMessage($0) } ?? .other(name: name)
        case "interrupt":
            kind = .interrupted
        case "precompact", "precompress":
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
            cwd: payload["cwd"].nonEmptyString ?? payload["workspace_roots"]?[0].nonEmptyString,
            transcriptPath: payload["transcript_path"].nonEmptyString ?? payload["transcriptPath"].nonEmptyString,
            permissionMode: payload["permission_mode"].nonEmptyString,
            model: payload["model"].nonEmptyString,
            subagentID: isSubagentLifecycle ? nil : payload["agent_id"].nonEmptyString,
            subagentType: isSubagentLifecycle ? nil : payload["agent_type"].nonEmptyString)
    }

    static func toolCall(_ payload: JSONValue) -> AgentToolCall? {
        guard let name = payload["tool_name"].nonEmptyString ?? payload["toolName"].nonEmptyString else { return nil }
        var input = payload["tool_input"] ?? payload["toolArgs"] ?? payload["toolInput"] ?? .object([:])
        // Copilot may hand the arguments over as a JSON string.
        if let text = input.string, let parsed = JSONValue.parse(text), parsed.object != nil { input = parsed }
        return AgentToolCall(name: name, input: input,
                             id: payload["tool_use_id"].nonEmptyString ?? payload["tool_call_id"].nonEmptyString
                                 ?? payload["toolCallId"].nonEmptyString)
    }

    static func subagentType(_ payload: JSONValue) -> String? {
        payload["agent_type"].nonEmptyString ?? payload["subagent_type"].nonEmptyString
            ?? payload["agentType"].nonEmptyString ?? payload["agentDisplayName"].nonEmptyString
            ?? payload["agentName"].nonEmptyString
    }

    /// Other agents' notification types in Claude's words, which the state machine understands.
    static func notificationType(_ type: String?) -> String? {
        switch type {
        case "ToolPermission": "permission_prompt" // Gemini: a confirmation is on screen
        case "agent_idle": "idle_prompt" // Copilot
        default: type
        }
    }

    /// "PreToolUse", "pre_tool_use", "preToolUse" → "pretooluse" (Copilot/Gemini spell them differently).
    static func normalized(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "_", with: "")
    }
}
