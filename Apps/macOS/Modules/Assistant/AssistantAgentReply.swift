import AltilloCore
import Foundation

// Phase 13: «dile a Claude que siga con los tests», "tell Codex to run the linter". Ask hands the words to a coding
// agent that's waiting for the user's next message (`AgentHub.reply`, phase 14), and says exactly what was sent.
//
// Only an explicit request with the agent's name gets here, and the model isn't involved at all: what an agent is
// told can make it run code, so it's the user's own words, never a paraphrase by a small model.

enum AgentReplyIntent {
    struct Request: Equatable, Sendable {
        /// The agent as named ("Claude", "Codex").
        var agent: String
        /// "in altillo": which session, when more than one is waiting.
        var project: String?
        /// What to send, as typed.
        var message: String
    }

    /// The agents Altillo follows, by the names people call them.
    static let agentNames = ["claude code", "claude", "codex", "gemini", "copilot", "opencode", "open code", "cursor"]

    /// Verbs that address an agent, before its name (folded, lowercase).
    private static let leads = [
        // English
        "please tell", "tell", "ask", "reply to", "respond to", "answer", "say to", "message",
        // Spanish
        "dile a", "dile", "digale a", "digale", "pidele a", "pidele", "contesta a", "contestale a", "contestale",
        "responde a", "respondele a", "respondele", "escribele a", "escribele", "manda a", "mandale a",
        // Catalan
        "digues a", "digues-li a", "digue-li a", "demana a", "demana-li a", "respon a", "contesta-li a",
        "escriu a", "escriu-li a",
    ]

    /// Joiners between the name and the message. One is always required: "tell Claude a joke" is a request to
    /// the model, not a message for the agent.
    private static let joiners = ["that ", "to ", "que ", ": ", ":", ", "]

    /// Quotes that may wrap the whole message; one matched pair is taken off, never more.
    private static let quotePairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("«", "»"), ("'", "'")]

    /// The request, or nil when the question doesn't explicitly address an agent by name.
    static func parse(_ question: String) -> Request? {
        let original = Array(question.trimmingCharacters(in: .whitespacesAndNewlines))
        // Folding keeps the character count, so positions found in it map back to the typed text.
        let folded = Array(AssistantHTML.fold(String(original)).replacingOccurrences(of: "’", with: "'"))
        guard folded.count == original.count else { return nil }
        func has(_ text: String, at index: Int) -> Bool {
            index + text.count <= folded.count && String(folded[index..<(index + text.count)]) == text
        }
        func isJoiner(at index: Int) -> String? { joiners.first { has($0, at: index) } }

        for lead in leads.sorted(by: { $0.count > $1.count }) where has(lead + " ", at: 0) {
            var index = lead.count + 1
            guard let name = agentNames.first(where: { has($0, at: index) }) else { continue }
            let nameRange = index..<(index + name.count)
            index += name.count
            // The name must end there ("Claudette" isn't Claude, "Claude's question" isn't a message).
            if index < folded.count, folded[index].isLetter || folded[index] == "'" || original[index] == "’" {
                return nil
            }

            // "tell Claude in altillo to …": a project, only when a joiner follows its one word.
            var project: String?
            if let marker = [" in ", " en ", " a "].first(where: { has($0, at: index) }) {
                let start = index + marker.count
                var end = start
                while end < folded.count, !folded[end].isWhitespace, folded[end] != ":", folded[end] != "," { end += 1 }
                var next = end
                while next < folded.count, folded[next] == " " { next += 1 }
                if end > start, isJoiner(at: next) != nil {
                    project = String(original[start..<end])
                    index = next
                }
            }
            while index < folded.count, folded[index] == " " { index += 1 }
            // "ask Claude what it's doing", "tell Claude about Paris": no joiner, no message.
            guard let joiner = isJoiner(at: index) else { return nil }
            index += joiner.count
            let message = unwrapped(String(original[min(index, original.count)...]))
            return Request(agent: String(original[nameRange]), project: project, message: message)
        }
        return nil
    }

    /// The message exactly as typed, trimmed, without one pair of quotes around the whole of it.
    /// `commit with message "fix bug"` keeps its quotes; `"yes, go ahead"` loses them.
    static func unwrapped(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let first = trimmed.first, let last = trimmed.last,
              quotePairs.contains(where: { $0.0 == first && $0.1 == last })
        else { return trimmed }
        let inner = trimmed.dropFirst().dropLast()
        // `"a" and "b"`: the first quote closes inside, so these aren't one wrapping pair.
        if first == last, inner.contains(first) { return trimmed }
        if first != last, inner.contains(last) { return trimmed }
        return String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AssistantAgentReply {
    struct Result: Equatable, Sendable {
        /// Shown as the answer, in the user's language (no model involved).
        var answer: String
        var receipt: AssistantActionReceipt?
    }

    /// Finds the waiting session and sends the message through `send` (`AgentHub.reply`).
    @MainActor
    static func perform(_ request: AgentReplyIntent.Request, isEnabled: Bool, sessions: [AgentSession],
                        send: (String, AgentSession) -> Bool) -> Result {
        let name = request.agent
        guard isEnabled else {
            return Result(answer: String(localized: "The Agents section is off, so I can't reach \(name). You can turn it on in Settings › Sections."))
        }
        guard !request.message.isEmpty else {
            return Result(answer: String(localized: "What should I tell \(name)? Try “tell \(name) to …”."))
        }
        let wanted = AssistantHTML.fold(name)
        var candidates = sessions.filter { session in
            let agent = AssistantHTML.fold(session.agent.name)
            return agent == wanted || agent.hasPrefix(wanted) || wanted.hasPrefix(agent)
                || AssistantHTML.fold(session.agent.rawValue) == wanted.replacingOccurrences(of: " ", with: "")
        }
        if let project = request.project.map(AssistantHTML.fold) {
            // The exact project first; a prefix or part of the name only when nothing is called exactly that.
            let exact = candidates.filter { AssistantHTML.fold($0.project) == project }
            candidates = !exact.isEmpty ? exact : candidates.filter {
                let name = AssistantHTML.fold($0.project)
                return name.hasPrefix(project) || name.contains(project)
            }
        }
        guard !candidates.isEmpty else {
            return Result(answer: String(localized: "There's no \(name) session I can see right now."))
        }
        // Two sessions of the same agent and no way to tell which one was meant: nothing is sent.
        guard candidates.count == 1, let session = candidates.first else {
            let projects = candidates.map(\.project).joined(separator: ", ")
            return Result(answer: String(localized: "There's more than one \(name) session (\(projects)). Say which one: “tell \(name) in \(candidates[0].project) to …”."))
        }
        guard session.reply != nil else {
            return Result(answer: String(localized: "\(name) isn't waiting for a reply right now, so nothing was sent. You can answer it in its terminal."))
        }
        guard send(request.message, session) else {
            return Result(answer: String(localized: "\(name) in \(session.project) stopped waiting before I could send it. Answer it in its terminal."))
        }
        return Result(
            answer: String(localized: "Sent to \(session.agent.name) in \(session.project): “\(request.message)”"),
            receipt: AssistantActionReceipt(
                symbol: "paperplane",
                title: request.message,
                detail: String(localized: "Sent to \(session.agent.name) · \(session.project)"),
                isAgentReply: true
            )
        )
    }

    /// The running app's sessions and hub.
    @MainActor
    static func live(_ request: AgentReplyIntent.Request) -> Result {
        guard let model = AssistantAgents.live else {
            return Result(answer: String(localized: "I can't reach your agents right now."))
        }
        return perform(request, isEnabled: model.settings.isEnabled(.agents), sessions: model.agentHub.sessions) {
            model.agentHub.reply($0, to: $1)
        }
    }
}
