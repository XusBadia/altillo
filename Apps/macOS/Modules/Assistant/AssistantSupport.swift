import AltilloCore
import AppKit
import Foundation
import FoundationModels
import NaturalLanguage

// MARK: - Instructions

/// What the model is told before anything else. Short on purpose: it is paid for on every turn out of a context
/// window of about 4 096 tokens.
enum AssistantInstructions {
    /// Each route gets only the lines it needs. `.live` means web results come with the question.
    static func text(
        now: Date = .now, locale: Locale = .current, timeZone: TimeZone = .current, recap: String? = nil,
        route: AssistantRoute = .chat
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        let language = Locale.preferredLanguages.first ?? locale.identifier
        var text = """
        You are Altillo, a helpful assistant in the notch of the user's Mac, running privately on it.
        Be warm and brief: one to four short sentences, or a short list. Always reply in the language of the user's message, even when tool results are in English.
        Now: \(formatter.string(from: now)) (\(timeZone.identifier)). User's language: \(language), region: \(locale.region?.identifier ?? "unknown").
        """
        switch route {
        case .context:
            text += """

            The user is asking about their own things. Call the one tool that fits (shelf, calendar, nowPlaying, clipboard, usage or agents) and answer from its result. Never invent events, files, songs or contents. If the tool can't help, say so simply.
            """
        case .chat, .live:
            // The small model refuses too readily: it's told plainly what it's good at and to just answer.
            text += """

            Answer directly and confidently from your own knowledge: facts, explanations, writing, translation, math, ideas, advice. Don't refuse when you know.
            """
            // Without results, admitting it is what makes Altillo look it up (or offer to): see `AssistantLiveness`.
            text += route == .live
                ? "\nWhen web results come with the question, answer from them and mention the site."
                : "\nYou can't see today's news, scores, weather or prices. If asked, say you can't check live data, then give what you know."
            text += "\nIf you don't know, say so simply."
        }
        if let recap, !recap.isEmpty {
            text += "\nEarlier in this conversation:\n" + recap
        }
        return text
    }

    /// The question with web results the user allowed for it (one tap, or on its own when the model didn't search
    /// but should have): the model answers from them rather than being trusted to call the tool.
    static func prompt(for question: String, webResults: String) -> String {
        """
        Question: \(question)

        Web results, searched just now:
        \(webResults)

        Answer the question in one to three sentences from these results only, and name the site (no links). For "last" or "latest", go by the dates and pick the most recent one. If they don't say, say so.\(languageReminder(for: question).map { " " + $0 } ?? "")
        """
    }

    /// The question as sent to the model. The small model drifts into English after reading English tool results,
    /// so a question clearly written in another language carries a reminder of which one to answer in.
    static func prompt(for question: String) -> String {
        guard let reminder = languageReminder(for: question) else { return question }
        return question + "\n\n" + reminder
    }

    /// A question about something live while the web is off: without this, the small model makes up a score or a
    /// forecast with total confidence.
    static func prompt(forOfflineLive question: String) -> String {
        prompt(for: question)
            + "\n\n(You have no live data for this. Say so in one short sentence, then add only background you're sure of: no made-up results, scores, dates or numbers.)"
    }

    /// "(Reply in Spanish.)" for a question clearly in a language other than English.
    static func languageReminder(for question: String) -> String? {
        guard let language = language(of: question), language != "en",
              let name = Locale(identifier: "en_US_POSIX").localizedString(forLanguageCode: language)
        else { return nil }
        return "(Reply in \(name).)"
    }

    /// The dominant language of `text`, as a code ("es"), when the recogniser is fairly sure.
    static func language(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= 0.6
        else { return nil }
        return language.rawValue
    }

    /// The last exchanges, squeezed, to carry into a fresh session when the old one ran out of room (or was
    /// interrupted mid-answer).
    static func recap(_ exchanges: [(question: String, answer: String)]) -> String {
        exchanges.suffix(2).map { exchange in
            let question = AssistantContent.truncate(exchange.question, to: 160)
            let answer = AssistantContent.truncate(exchange.answer, to: 320)
            return "User: \(question)\nYou: \(answer)"
        }
        .joined(separator: "\n")
    }
}

// MARK: - Suggestions

/// A ready-made question on the empty state, built from what is actually there to ask about.
struct AssistantSuggestion: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case today, summarize, playing, clipboard, capabilities, reply }

    var kind: Kind
    var symbol: String
    /// On the chip (localised).
    var title: String
    /// Sent to the model (localised too: the answer comes back in the same language).
    var prompt: String

    var id: String { kind.rawValue }

    /// What the chips can be made of right now.
    struct Signals: Equatable, Sendable {
        var calendarGranted = false
        /// Name of the newest document or note on the shelf the assistant can read.
        var readableShelfItem: String?
        /// A player that is open (Music, Spotify).
        var runningPlayer: String?
        var clipboardHasText = false
    }

    static let maximum = 3

    /// Up to three chips, the contextual ones first; generic ones fill in so there are always at least two.
    static func make(_ signals: Signals) -> [AssistantSuggestion] {
        var chips: [AssistantSuggestion] = []
        if signals.calendarGranted {
            chips.append(AssistantSuggestion(
                kind: .today, symbol: "calendar",
                title: String(localized: "What do I have today?"),
                prompt: String(localized: "What do I have today?")
            ))
        }
        if let name = signals.readableShelfItem {
            let short = AssistantFormat.shortName(name)
            chips.append(AssistantSuggestion(
                kind: .summarize, symbol: "text.alignleft",
                title: String(localized: "Summarize “\(short)”"),
                prompt: String(localized: "Summarize “\(name)” from my shelf.")
            ))
        }
        if let player = signals.runningPlayer {
            chips.append(AssistantSuggestion(
                kind: .playing, symbol: "music.note",
                title: String(localized: "What's playing?"),
                prompt: String(localized: "What's playing in \(player)?")
            ))
        }
        if signals.clipboardHasText {
            chips.append(AssistantSuggestion(
                kind: .clipboard, symbol: "doc.on.clipboard",
                title: String(localized: "Explain what I copied"),
                prompt: String(localized: "Explain what I copied.")
            ))
        }
        let generic = [
            AssistantSuggestion(
                kind: .capabilities, symbol: "sparkle",
                title: String(localized: "What can you do?"),
                prompt: String(localized: "What can you help me with?")
            ),
            AssistantSuggestion(
                kind: .reply, symbol: "envelope",
                title: String(localized: "Help me say no nicely"),
                prompt: String(localized: "Help me write a short, kind message to turn down an invitation.")
            ),
        ]
        for chip in generic where chips.count < 2 {
            chips.append(chip)
        }
        return Array(chips.prefix(maximum))
    }

    /// The newest shelf item worth summarising (a document, a PDF, a note).
    static func readableItem(in items: [ShelfItem]) -> ShelfItem? {
        items.filter(AssistantContent.hasReadableText).max { $0.addedAt < $1.addedAt }
    }
}

// MARK: - Failures

/// Why an answer didn't arrive, in words the user can act on.
enum AssistantFailure: Equatable, Sendable {
    /// The conversation outgrew the model's memory (even after starting afresh with a recap).
    case contextFull
    case guardrail
    case language
    case notReady
    case busy
    case refused
    case tool(String)
    case other

    init(_ error: any Error) {
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: self = .contextFull
            case .guardrailViolation: self = .guardrail
            case .unsupportedLanguageOrLocale: self = .language
            case .assetsUnavailable: self = .notReady
            case .rateLimited, .concurrentRequests: self = .busy
            case .refusal: self = .refused
            case .unsupportedGuide, .decodingFailure: self = .other
            @unknown default: self = .other
            }
        } else if let error = error as? LanguageModelSession.ToolCallError {
            self = .tool(error.tool.name)
        } else {
            self = .other
        }
    }

    var message: String {
        switch self {
        case .contextFull:
            String(localized: "That's more than I can keep in my head at once. Start a new conversation and ask again.")
        case .guardrail:
            String(localized: "I'd rather not answer that one. Try asking it another way.")
        case .language:
            String(localized: "I can't answer in that language yet. Try asking in another one.")
        case .notReady:
            String(localized: "Apple Intelligence is still getting ready. Try again in a moment.")
        case .busy:
            String(localized: "I'm still busy with something else. Give me a moment and try again.")
        case .refused:
            String(localized: "I can't help with that one.")
        case .tool("web"):
            String(localized: "I couldn't reach the web. Try again in a moment.")
        case let .tool(name):
            String(localized: "I couldn't look at your \(AssistantFormat.toolNoun(name)). Try again in a moment.")
        case .other:
            String(localized: "Something went wrong up here. Try again.")
        }
    }
}

// MARK: - Words

enum AssistantFormat {
    /// The answer's opening words, for the peek shown when it finishes while the notch is closed.
    static func peekTitle(_ answer: String, limit: Int = 48) -> String {
        let plain = plainText(answer)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !plain.isEmpty else { return String(localized: "Your answer is ready") }
        // First sentence when it's short enough, otherwise the first words.
        if let end = plain.firstIndex(where: { ".!?".contains($0) }),
           plain.distance(from: plain.startIndex, to: end) < limit {
            return String(plain[...end])
        }
        guard plain.count > limit else { return plain }
        var head = String(plain.prefix(limit - 1))
        if let space = head.lastIndex(of: " ") { head = String(head[..<space]) }
        return head.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:—-")) + "…"
    }

    /// Markdown rendered for display. Inline only (bold, italics, code, links), keeping line breaks, so lists the
    /// model writes with "-" still read as lists.
    static func rendered(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let source = boldHeadings(markdown)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }

    /// The inline mode doesn't parse headings, and the small model likes to write them: "## Summary" becomes
    /// "**Summary**" so the answer never shows raw hashes.
    static func boldHeadings(_ markdown: String) -> String {
        markdown.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.drop { $0 == " " }
                let hashes = trimmed.prefix { $0 == "#" }
                guard (1...6).contains(hashes.count), trimmed.dropFirst(hashes.count).first == " " else {
                    return String(line)
                }
                let title = trimmed.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? "" : "**\(title)**"
            }
            .joined(separator: "\n")
    }

    /// Markdown without its marks: what gets copied, put on the shelf and read in the peek.
    static func plainText(_ markdown: String) -> String {
        let text = String(rendered(markdown).characters)
        // Headings aren't parsed by the inline mode; drop their hashes.
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let trimmed = line.drop(while: { $0 == " " })
                guard trimmed.hasPrefix("#") else { return String(line) }
                return String(trimmed.drop(while: { $0 == "#" }).drop(while: { $0 == " " }))
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Name of an answer put up on the shelf: the question it answers.
    static func shelfName(question: String) -> String {
        let line = question.split(whereSeparator: \.isNewline).first.map(String.init) ?? question
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 48 ? String(trimmed.prefix(47)) + "…" : trimmed
    }

    /// Shortened for a chip, keeping the extension visible ("A very long rep…ort.pdf").
    static func shortName(_ name: String, limit: Int = 22) -> String {
        guard name.count > limit else { return name }
        let tail = min(7, limit / 3)
        return String(name.prefix(limit - tail - 1)) + "…" + String(name.suffix(tail))
    }

    static func toolNoun(_ toolName: String) -> String {
        switch toolName {
        case "shelf": String(localized: "shelf")
        case "calendar": String(localized: "calendar")
        case "nowPlaying": String(localized: "music")
        case "clipboard": String(localized: "clipboard")
        default: String(localized: "things")
        }
    }
}

// MARK: - System Settings

/// The Apple Intelligence & Siri pane. On macOS 26 it is the `com.apple.Siri-Settings.extension` settings
/// extension (the same pane is "Siri" on Macs without Apple Intelligence).
enum AppleIntelligenceSettings {
    static let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")

    @MainActor
    static func open() {
        if let url, NSWorkspace.shared.open(url) { return }
        if let root = URL(string: "x-apple.systempreferences:") { NSWorkspace.shared.open(root) }
    }
}
