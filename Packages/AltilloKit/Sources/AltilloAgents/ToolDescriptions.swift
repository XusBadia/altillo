import AltilloCore
import Foundation

/// The few words the notch shows for a tool call ("Running `swift test`", "Editing NotchModel.swift"), and the
/// permission card built from a `PermissionRequest`. English only for now (Spanish comes with the catalog).
public enum ToolDescriptions {
    /// What the agent is doing while `call` runs.
    public static func activity(for call: AgentToolCall, cwd: String?) -> String {
        let input = call.input
        if let command = call.command {
            return "Running `\(command.firstLine(limit: 48))`"
        }
        let files = call.filePaths
        switch call.name {
        case "Edit", "MultiEdit", "NotebookEdit", "str_replace_based_edit_tool", "replace", "edit":
            return files.first.map { "Editing \($0.fileName)" } ?? "Editing a file"
        case "apply_patch", "ApplyPatch":
            if files.count == 1 { return "Editing \(files[0].fileName)" }
            return files.isEmpty ? "Editing files" : "Editing \(files.count) files"
        case "Write", "write_file", "create_file", "create":
            return files.first.map { "Writing \($0.fileName)" } ?? "Writing a file"
        case "Read", "read_file", "view", "read_many_files":
            return files.first.map { "Reading \($0.fileName)" } ?? "Reading a file"
        case "view_image":
            return "Looking at an image"
        case "Grep":
            return input["pattern"].nonEmptyString.map { "Searching for “\($0.truncated(32))”" } ?? "Searching"
        case "Glob":
            return input["pattern"].nonEmptyString.map { "Finding \($0.truncated(32))" } ?? "Finding files"
        case "LS":
            return "Listing files"
        case "WebFetch":
            if let url = input["url"].nonEmptyString, let host = URL(string: url)?.host() { return "Reading \(host)" }
            return "Reading a web page"
        case "WebSearch", "web_search":
            return input["query"].nonEmptyString.map { "Searching the web for “\($0.truncated(32))”" }
                ?? "Searching the web"
        case "Agent", "Task", "spawn_agent":
            if let type = input["subagent_type"].nonEmptyString { return "Running the \(type) agent" }
            if let description = input["description"].nonEmptyString { return description.firstLine(limit: 48) }
            return "Running a subagent"
        case "TodoWrite", "update_plan", "TaskCreate", "TaskUpdate":
            return "Updating the plan"
        case "AskUserQuestion", "request_user_input":
            return "Asking you a question"
        case "ExitPlanMode":
            return "Presenting the plan"
        case "Skill":
            return input["skill"].nonEmptyString.map { "Using the \($0) skill" } ?? "Using a skill"
        case "wait", "wait_agent":
            return "Waiting for a subagent"
        default:
            break
        }
        if call.name.hasPrefix("mcp__") {
            // mcp__server__tool; server and tool names may contain single underscores.
            let pieces = call.name.dropFirst(5).components(separatedBy: "__")
            if pieces.count >= 2 { return "Using \(pieces[0]) · \(pieces[1...].joined(separator: " "))" }
            return "Using \(pieces[0])"
        }
        return "Using \(call.name)"
    }

    /// The question an `AskUserQuestion` call asks, when it is one.
    public static func question(in call: AgentToolCall) -> String? {
        guard call.name == "AskUserQuestion" || call.name == "request_user_input" else { return nil }
        if let first = call.input["questions"]?.array?.first {
            return first["question"].nonEmptyString
        }
        return call.input["question"].nonEmptyString ?? call.input["prompt"].nonEmptyString
    }

    /// Builds the card for a permission request. `id` is the wire request id the hook waits on.
    public static func permissionRequest(
        id: String, agent: AgentKind, call: AgentToolCall, suggestions: [JSONValue], cwd: String?,
        requestedAt: Date, expiresAt: Date?
    ) -> AgentPermissionRequest {
        var summary: String
        var detail: String?
        var danger: DangerAssessment?

        if let command = call.command {
            summary = command.firstLine(limit: 120)
            let description = call.input["description"].nonEmptyString
            let fullCommand = command.count > summary.count || command.contains("\n") ? command : nil
            detail = [description, fullCommand.map { String($0.prefix(2000)) }].compactMap { $0 }.joined(separator: "\n\n")
            danger = DangerClassifier.assess(command: command, cwd: cwd)
        } else if ToolNames.fileWriting.contains(call.name) {
            let files = call.filePaths
            summary = files.isEmpty ? call.name : files.map { $0.displayPath(relativeTo: cwd) }.joined(separator: ", ")
            detail = editExcerpt(call)
            danger = files.lazy.compactMap { DangerClassifier.assessFileWrite(path: $0, cwd: cwd) }.first
        } else if call.name == "WebFetch", let url = call.input["url"].nonEmptyString {
            summary = url
            detail = call.input["prompt"].nonEmptyString
        } else {
            summary = activity(for: call, cwd: cwd)
            if case .object(let object) = call.input, !object.isEmpty {
                detail = String(decoding: call.input.data, as: UTF8.self).truncatedRaw(1500)
            }
        }
        if summary.isEmpty { summary = call.name }
        if let danger { detail = [danger.reason, detail].compactMap { $0 }.joined(separator: "\n\n") }

        return AgentPermissionRequest(
            id: id, toolName: call.name, summary: summary, detail: detail?.isEmpty == true ? nil : detail,
            isDangerous: danger != nil,
            canAllowForSession: ClaudeSessionPermissions.canAllowForSession(agent: agent, call: call,
                                                                           suggestions: suggestions),
            requestedAt: requestedAt, expiresAt: expiresAt)
    }

    /// First lines of an edit: `old → new` for Edit, the content head for Write, the patch head for apply_patch.
    static func editExcerpt(_ call: AgentToolCall) -> String? {
        let input = call.input
        if let patch = input["command"]?.string ?? input["patch"]?.string {
            return patch.split(separator: "\n", omittingEmptySubsequences: false).prefix(24).joined(separator: "\n")
        }
        if let new = input["new_string"]?.string {
            let old = input["old_string"]?.string ?? ""
            let minus = old.split(separator: "\n", omittingEmptySubsequences: false).prefix(8).map { "- " + $0 }
            let plus = new.split(separator: "\n", omittingEmptySubsequences: false).prefix(8).map { "+ " + $0 }
            return (minus + plus).joined(separator: "\n")
        }
        if let content = input["content"]?.string {
            return content.split(separator: "\n", omittingEmptySubsequences: false).prefix(12).joined(separator: "\n")
        }
        return nil
    }
}

extension String {
    func truncatedRaw(_ limit: Int) -> String {
        count > limit ? String(prefix(limit - 1)) + "…" : self
    }
}
