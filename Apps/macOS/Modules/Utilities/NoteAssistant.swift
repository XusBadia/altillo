import Foundation
import FoundationModels

// Ask learns the quick note (phase 12): «apunta comprar leche», "add to my note: call Ana", "what's in my note?".
// Adding is an action: the answer says exactly what went in, and the note section offers "Undo".

struct NoteTool: Tool {
    let name = "note"
    let description = "The user's quick note in Altillo: adds a line to it or reads it."

    @Generable
    enum Action {
        case add, read
    }

    @Generable
    struct Arguments {
        @Guide(description: "add or read.")
        var action: Action
        @Guide(description: "The line to add, in the user's words, without \"note\" or \"write down\". Only to add.")
        var text: String?
    }

    let perform: @MainActor @Sendable (NoteAssistant.Request) -> String
    let report: AssistantActivityReport

    func call(arguments: Arguments) async throws -> String {
        await report(.note)
        let request: NoteAssistant.Request = switch arguments.action {
        case .add: .add(arguments.text ?? "")
        case .read: .read
        }
        let answer = await perform(request)
        await SpikeLog.shared.record(SpikeLog.Category.assistant, "tool note \(arguments.action) → \(answer.count) chars")
        return answer
    }
}

/// What Ask's `note` tool does and says, in plain English for the model.
enum NoteAssistant {
    enum Request: Equatable, Sendable {
        case add(String)
        case read
    }

    /// Acts on the running app's note (`NotchModel.note`).
    @MainActor
    static func live(_ request: Request) -> String {
        guard let model = AssistantAgents.live else { return "The note isn't available right now." }
        return perform(request, store: model.note, isEnabled: model.settings.isEnabled(.note))
    }

    @MainActor
    static func perform(_ request: Request, store: NoteStore, isEnabled: Bool) -> String {
        guard isEnabled else {
            return "The Note section is turned off in Altillo, so nothing was written down. Tell the user they can turn it on in Settings › Sections, or from the notch's Customize mode."
        }
        store.load()
        switch request {
        case let .add(line):
            let clean = cleaned(line)
            guard !clean.isEmpty else {
                return "Nothing was added: there was no text. Ask the user what to write down."
            }
            let written = store.append(clean, fromAsk: true)
            let lines = store.text.split(whereSeparator: \.isNewline).count
            return "Added to the note: \"\(written)\". The note now has \(lines) line\(lines == 1 ? "" : "s"). Tell the user exactly that; they can undo it from the Note section of the notch."
        case .read:
            let text = store.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return "The note is empty." }
            return "The note says:\n" + AssistantContent.truncate(text, to: AssistantContent.toolOutputLimit - 40)
        }
    }

    /// The line without the asking around it: «apunta: comprar leche» → "comprar leche".
    static func cleaned(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "add to my note", "add to the note", "add to note", "write down", "note down", "jot down", "note that",
            "remember that", "apunta que", "apunta", "apuntame", "apúntame", "anota que", "anota", "anótame",
            "añade a la nota", "añade a mi nota", "apunta'm", "anota'm", "afegeix a la nota",
        ]
        for prefix in prefixes where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " :,-–—\"“”«»").union(.whitespacesAndNewlines))
        return text
    }
}
