import AltilloCore
import Foundation

// OpenCode (phase 14): no hooks to install. While `opencode serve` (or `opencode web`, or the TUI started with
// `--port`) runs, its HTTP server streams every event over SSE and takes permission answers and new messages.
// Verified live against OpenCode 1.18.32 (September 2026, isolated HOME/XDG dirs; captures in the package tests):
//
// - `opencode serve` listens on 127.0.0.1:4096 by default (`--port 0` = "4096, else any free port"); the plain TUI
//   listens on nothing. `OPENCODE_SERVER_PASSWORD` turns on basic auth (Altillo then leaves the server alone).
// - `GET /global/event`: `data: {"directory":"/path","project":"…","payload":{"id":"evt_…","type":"…","properties":{…}}}`
//   for every project; `GET /event?directory=` is the same payload unwrapped, for one directory. A
//   `server.heartbeat` arrives every few seconds.
// - Types used: `session.created|updated|deleted` (`properties.info`: id, directory, title, parentID, time),
//   `session.status` (`status.type`: busy|idle|retry), `session.idle`, `session.error`, `message.updated`
//   (`info.role`), `message.part.updated` (`part.type == "text"`, `part.text`), `permission.asked` (`id`,
//   `sessionID`, `permission`, `patterns`, `metadata`, `always`, `tool`), `permission.replied` (`requestID`, `reply`).
// - `POST /permission/{requestID}/reply?directory=` `{"reply":"once"|"always"|"reject"}` → `true`.
// - `POST /session/{id}/prompt_async?directory=` `{"parts":[{"type":"text","text":"…"}]}` → 204, a new turn starts.

/// Splits a Server-Sent Events byte stream into the `data` of each event.
public struct SSEParser: Sendable {
    private var lines = LineBuffer(limit: 8 << 20)
    private var data: [String] = []

    public init() {}

    public var isOverLimit: Bool { lines.isOverLimit }

    /// Feeds bytes; returns the data of every event completed by them.
    public mutating func feed(_ bytes: Data) -> [String] {
        var events: [String] = []
        for raw in lines.append(bytes) {
            var line = String(decoding: raw, as: UTF8.self)
            if line.hasSuffix("\r") { line.removeLast() }
            if line.isEmpty {
                if !data.isEmpty { events.append(data.joined(separator: "\n")) }
                data.removeAll()
            } else if line.hasPrefix("data:") {
                var value = line.dropFirst(5)
                if value.first == " " { value = value.dropFirst() }
                data.append(String(value))
            }
            // `event:`, `id:`, `retry:` and comments are not used.
        }
        return events
    }
}

/// One OpenCode server event, as Altillo uses it.
public enum OpenCodeEvent: Hashable, Sendable {
    case connected
    /// Created or updated. `parentID` is set for subagent (child) sessions.
    case session(id: String, directory: String?, title: String?, parentID: String?, updatedAt: Date?)
    case deleted(sessionID: String)
    /// `busy`, `idle` or `retry`.
    case status(sessionID: String, status: String)
    case idle(sessionID: String)
    case error(sessionID: String?, message: String?)
    case messageRole(sessionID: String, messageID: String, role: String)
    case text(sessionID: String, messageID: String, text: String)
    /// A tool part (`state.status`: pending|running|completed|error), as a Claude-style call.
    case tool(sessionID: String, call: AgentToolCall, status: String)
    case permissionAsked(OpenCodePermission)
    case permissionReplied(sessionID: String, requestID: String)
    case other(String)

    /// Parses one SSE `data` (either `/global/event`'s envelope or `/event`'s bare payload). `directory` comes from
    /// the envelope when present.
    public static func parse(_ data: String) -> (event: OpenCodeEvent, directory: String?)? {
        guard let json = JSONValue.parse(data), json.object != nil else { return nil }
        let payload = json["payload"] ?? json
        let directory = json["directory"].nonEmptyString
        guard let type = payload["type"].nonEmptyString else { return nil }
        let properties = payload["properties"] ?? .object([:])
        let sessionID = properties["sessionID"].nonEmptyString

        let event: OpenCodeEvent
        switch type {
        case "server.connected":
            event = .connected
        case "session.created", "session.updated":
            guard let info = properties["info"], let id = info["id"].nonEmptyString else { return nil }
            event = .session(id: id, directory: info["directory"].nonEmptyString, title: info["title"].nonEmptyString,
                             parentID: info["parentID"].nonEmptyString,
                             updatedAt: info["time"]?["updated"]?.number.map { Date(timeIntervalSince1970: $0 / 1000) })
        case "session.deleted":
            guard let id = properties["info"]?["id"].nonEmptyString ?? sessionID else { return nil }
            event = .deleted(sessionID: id)
        case "session.status":
            guard let sessionID, let status = properties["status"]?["type"].nonEmptyString else { return nil }
            event = .status(sessionID: sessionID, status: status)
        case "session.idle":
            guard let sessionID else { return nil }
            event = .idle(sessionID: sessionID)
        case "session.error":
            let error = properties["error"]
            event = .error(sessionID: sessionID,
                           message: error?["data"]?["message"].nonEmptyString ?? error?["name"].nonEmptyString)
        case "message.updated":
            guard let info = properties["info"], let session = info["sessionID"].nonEmptyString,
                  let message = info["id"].nonEmptyString, let role = info["role"].nonEmptyString else { return nil }
            event = .messageRole(sessionID: session, messageID: message, role: role)
        case "message.part.updated" where properties["part"]?["type"]?.string == "tool":
            guard let part = properties["part"], let session = part["sessionID"].nonEmptyString,
                  let tool = part["tool"].nonEmptyString else { return nil }
            let input = part["state"]?["input"] ?? .object([:])
            let call: AgentToolCall = switch tool {
            case "bash": AgentToolCall(name: "Bash", input: input)
            case "edit": AgentToolCall(name: "Edit", input: .object(["file_path": input["filePath"] ?? .null]))
            case "write": AgentToolCall(name: "Write", input: .object(["file_path": input["filePath"] ?? .null]))
            case "read": AgentToolCall(name: "Read", input: .object(["file_path": input["filePath"] ?? .null]))
            case "webfetch": AgentToolCall(name: "WebFetch", input: input)
            default: AgentToolCall(name: tool, input: input)
            }
            event = .tool(sessionID: session, call: call, status: part["state"]?["status"]?.string ?? "running")
        case "message.part.updated":
            guard let part = properties["part"], part["type"]?.string == "text",
                  let session = part["sessionID"].nonEmptyString, let message = part["messageID"].nonEmptyString,
                  let text = part["text"].nonEmptyString else { return nil }
            event = .text(sessionID: session, messageID: message, text: text)
        case "permission.asked", "permission.updated":
            guard let permission = OpenCodePermission(properties) else { return nil }
            event = .permissionAsked(permission)
        case "permission.replied":
            guard let sessionID,
                  let request = properties["requestID"].nonEmptyString ?? properties["permissionID"].nonEmptyString
            else { return nil }
            event = .permissionReplied(sessionID: sessionID, requestID: request)
        default:
            event = .other(type)
        }
        return (event, directory)
    }
}

/// A permission OpenCode is waiting for.
public struct OpenCodePermission: Hashable, Sendable {
    public var id: String
    public var sessionID: String
    /// "bash", "edit", "webfetch", "external_directory"…
    public var permission: String
    public var patterns: [String]
    public var metadata: JSONValue
    /// Patterns "always" would allow (OpenCode offers "Always allow" when present).
    public var always: [String]

    public init?(_ properties: JSONValue) {
        guard let id = properties["id"].nonEmptyString, let session = properties["sessionID"].nonEmptyString else {
            return nil
        }
        self.id = id
        sessionID = session
        permission = properties["permission"].nonEmptyString ?? properties["type"].nonEmptyString ?? "permission"
        patterns = properties["patterns"]?.array?.compactMap(\.string)
            ?? properties["pattern"]?.string.map { [$0] } ?? []
        metadata = properties["metadata"] ?? .object([:])
        always = properties["always"]?.array?.compactMap(\.string) ?? []
    }

    /// The same request as Claude would describe it, so the notch shows it the same way.
    public var toolCall: AgentToolCall {
        switch permission {
        case "bash":
            let command = metadata["command"].nonEmptyString ?? patterns.first ?? ""
            return AgentToolCall(name: "Bash", input: .object(["command": .string(command)]))
        case "edit", "write":
            let path = metadata["filepath"].nonEmptyString ?? metadata["filePath"].nonEmptyString ?? patterns.first ?? ""
            var input: [String: JSONValue] = ["file_path": .string(path)]
            if let diff = metadata["diff"].nonEmptyString { input["patch"] = .string(diff) }
            return AgentToolCall(name: "Edit", input: .object(input))
        case "webfetch":
            return AgentToolCall(name: "WebFetch",
                                 input: .object(["url": .string(metadata["url"].nonEmptyString ?? patterns.first ?? "")]))
        default:
            return AgentToolCall(name: permission, input: metadata.object == nil ? .object([:]) : metadata)
        }
    }
}

/// Talking to an OpenCode server: where it listens, and the bodies of the two calls Altillo makes.
public enum OpenCodeAPI {
    public static let defaultPort = 4096

    /// Whether a process's argv is an OpenCode that serves HTTP (`serve`, `web`, or `--port`), and its port when the
    /// arguments say it (nil: look it up; 0 means "4096 or any free one").
    public static func serverPort(arguments: [String]) -> (serves: Bool, port: Int?) {
        guard let executable = arguments.first,
              (executable as NSString).lastPathComponent.hasPrefix("opencode") else { return (false, nil) }
        var port: Int?
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--port", index + 1 < arguments.count {
                port = Int(arguments[index + 1])
                index += 1
            } else if argument.hasPrefix("--port=") {
                port = Int(argument.dropFirst("--port=".count))
            }
            index += 1
        }
        let words = arguments.dropFirst().filter { !$0.hasPrefix("-") }
        let serves = words.first == "serve" || words.first == "web" || (port ?? 0) > 0
        return (serves, port == 0 ? nil : port)
    }

    /// `{"reply":"once"|"always"|"reject"}`.
    public static func permissionReplyBody(_ decision: AgentDecision) -> Data {
        let reply = switch decision {
        case .allow: "once"
        case .allowForSession: "always"
        case .deny: "reject"
        }
        return JSONValue.object(["reply": .string(reply)]).data
    }

    /// `{"parts":[{"type":"text","text":"…"}]}`: a new user message.
    public static func promptBody(_ text: String) -> Data {
        JSONValue.object(["parts": .array([.object(["type": .string("text"), "text": .string(text)])])]).data
    }

    /// `/permission/<id>/reply?directory=<dir>` and `/session/<id>/prompt_async?directory=<dir>`.
    public static func permissionReplyPath(requestID: String, directory: String?) -> String {
        "/permission/\(escaped(requestID))/reply" + query(directory)
    }

    public static func promptPath(sessionID: String, directory: String?) -> String {
        "/session/\(escaped(sessionID))/prompt_async" + query(directory)
    }

    /// `GET /permission?directory=`: the permissions still waiting (array of `permission.asked` properties).
    public static func pendingPermissionsPath(directory: String?) -> String { "/permission" + query(directory) }

    /// `GET /session/status?directory=`: `{"<session id>":{"type":"busy"|"idle"|"retry"}}` (verified on 1.18.32).
    public static func statusPath(directory: String?) -> String { "/session/status" + query(directory) }

    public static func permissions(from data: Data) -> [OpenCodePermission]? {
        guard let items = JSONValue.parse(data)?.array else { return nil }
        return items.compactMap(OpenCodePermission.init)
    }

    public static func statuses(from data: Data) -> [String: String]? {
        guard let object = JSONValue.parse(data)?.object else { return nil }
        return object.compactMapValues { $0["type"]?.string }
    }

    static func escaped(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/")))
            ?? component
    }

    static func query(_ directory: String?) -> String {
        guard let directory, !directory.isEmpty,
              let value = directory.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(
                  CharacterSet(charactersIn: "&=+?"))) else { return "" }
        return "?directory=" + value
    }
}
