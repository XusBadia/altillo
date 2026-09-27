import Foundation
import FoundationModels

// MARK: - Ask: the clipboard history

/// Ask's `clipboardHistory` tool: what the user copied before the current item, from the Clipboard section's own
/// memory. Only while that section is on (it keeps nothing otherwise); the `clipboard` tool reads the current item.
struct ClipboardHistoryTool: Tool {
    let name = "clipboardHistory"
    let description = "Texts, images and files the user copied earlier, newest first. Pass words to find one."

    @Generable
    struct Arguments {
        @Guide(description: "Words to look for. Omit for the latest copies.")
        var search: String?
    }

    var reading: @MainActor @Sendable () -> ClipboardAsk.Reading = { ClipboardAsk.liveReading() }
    let report: AssistantActivityReport

    func call(arguments: Arguments) async throws -> String {
        await report(.clipboard)
        let reading = await reading()
        let answer = ClipboardAsk.answer(reading, search: arguments.search, now: .now)
        await DiagnosticLog.shared.record(DiagnosticLog.Category.assistant, "tool clipboardHistory → \(answer.count) chars")
        return answer
    }
}

/// What the `clipboardHistory` tool says, in plain English for the model.
enum ClipboardAsk {
    struct Reading: Sendable {
        /// The Clipboard section is on (with it off there's no history at all).
        var isEnabled: Bool
        /// Pins first, then the rest, newest first.
        var items: [ClipboardItem]
    }

    /// The running app's history, as the Clipboard section has it.
    @MainActor
    static func liveReading() -> Reading {
        guard let model = AssistantAgents.live else { return Reading(isEnabled: false, items: []) }
        return Reading(isEnabled: model.settings.isEnabled(.clipboard), items: model.clipboard.history.ordered)
    }

    /// Slips listed at most, and characters quoted from each.
    static let maxListed = 8
    static let excerptLength = 260

    static func answer(_ reading: Reading, search: String?, now: Date) -> String {
        guard reading.isEnabled else {
            return "Altillo's Clipboard section is off, so it keeps no history of what the user copied. Tell the user they can turn it on in Settings › Sections (it keeps texts, images and files, never passwords)."
        }
        guard !reading.items.isEmpty else {
            return "Nothing copied since the Clipboard section was turned on (it keeps texts, images and files, never passwords)."
        }
        var items = reading.items
        let words = (search ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        if !words.isEmpty {
            items = ClipboardHistory(items: items).matching(words.joined(separator: " "))
            guard !items.isEmpty else {
                return "None of the \(reading.items.count) copies contains \"\(search ?? "")\"."
            }
        }
        // Newest first for the model, pins marked.
        items.sort { $0.copiedAt > $1.copiedAt }
        let lines = items.prefix(maxListed).map { item in
            var line = "- \(NotchFormat.ago(item.copiedAt, now: now))"
            if let app = item.sourceName { line += ", from \(app)" }
            if item.isPinned { line += " (pinned)" }
            switch item.content {
            case let .text(text):
                let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
                let excerpt = flat.count > excerptLength ? String(flat.prefix(excerptLength - 1)) + "…" : flat
                return line + ": \"\(excerpt)\""
            case let .files(files):
                let names = files.prefix(maxListed).map { "\"\($0.name)\"" }.joined(separator: ", ")
                let more = files.count > maxListed ? " and \(files.count - maxListed) more" : ""
                return line + ": " + (files.count == 1 ? "a file " : "\(files.count) files ") + names + more
            case let .image(image):
                let flat = (image.recognizedText ?? "").split(whereSeparator: \.isNewline).joined(separator: " ")
                let excerpt = flat.count > excerptLength ? String(flat.prefix(excerptLength - 1)) + "…" : flat
                return line + ": an image, \(image.width)×\(image.height) pixels"
                    + (excerpt.isEmpty ? "" : ", with the text \"\(excerpt)\"")
            }
        }
        var text = "What the user copied, newest first:\n" + lines.joined(separator: "\n")
        if items.count > maxListed { text += "\n…and \(items.count - maxListed) older ones." }
        return AssistantContent.truncate(text)
    }
}
