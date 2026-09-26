import AltilloCore
import Foundation
import UniformTypeIdentifiers
import Vision

// Phase 13: drop a file (or some text, or a link) on Ask and ask about it: "What's in this PDF?", «Resume esto».
// The text is read once, when it arrives, with the same readers as the shelf tool, and kept in memory only for this
// conversation. Images can't be seen by the model, so Vision reads them on this Mac: the words in them and a few
// guesses at what they show.

/// Something dropped on Ask, read and ready to go with the next questions.
struct AssistantAttachment: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A document, a note or dropped text: `text` is its contents.
        case document
        /// An image: `text` is what Vision found in it.
        case image
        /// A web link: only its address is known.
        case link
        /// Something Ask can't read (a video, an app, an archive…): only its name goes along.
        case unreadable
    }

    let id: UUID
    /// As shown on the chip ("informe.pdf").
    var name: String
    var kind: Kind
    /// What goes to the model, already capped (`AssistantAttachments.textLimit`).
    var text: String
    /// "PDF file", "image", "text note"… for the model and the chip's tooltip.
    var description: String

    init(id: UUID = UUID(), name: String, kind: Kind, text: String, description: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.text = text
        self.description = description
    }

    var symbol: String {
        switch kind {
        case .document: "doc.text"
        case .image: "photo"
        case .link: "link"
        case .unreadable: "doc"
        }
    }
}

enum AssistantAttachments {
    /// How much of an attachment rides along with a question, in characters (≈ 550–700 tokens): the rest of the
    /// 4 096-token window is instructions, the recap, the question and the answer.
    static let textLimit = 2_200
    /// Several things dropped at once are read together, each with a share of `textLimit`.
    static let maximumItems = 3

    // MARK: - Reading what was dropped

    /// Reads dropped things into one attachment. Touches the disk and runs Vision: call it off the main actor.
    static func read(_ items: [ShelfItem], inboxRoot: URL = FileIngest.standard.inboxRoot,
                     recognizeImage: @Sendable (URL) async -> ImageReading? = { await recognize($0) })
        async -> AssistantAttachment? {
        // Beyond the first few nothing is read, but Altillo's own copies of them still go.
        for case let .file(url, true) in items.dropFirst(maximumItems).map(\.kind) {
            discardCopy(at: url, inboxRoot: inboxRoot)
        }
        let items = Array(items.prefix(maximumItems))
        guard !items.isEmpty else { return nil }
        var parts: [AssistantAttachment] = []
        let share = textLimit / items.count
        for item in items {
            parts.append(await read(item, limit: share, inboxRoot: inboxRoot, recognizeImage: recognizeImage))
        }
        guard parts.count > 1 else { return parts[0] }
        let names = parts.map(\.name)
        let text = parts.map { "\"\($0.name)\" (\($0.description)):\n\($0.text)" }.joined(separator: "\n\n")
        let kind: AssistantAttachment.Kind = parts.contains { $0.kind == .document } ? .document : parts[0].kind
        return AssistantAttachment(
            name: String(localized: "\(names[0]) and \(names.count - 1) more"),
            kind: kind,
            text: AssistantContent.truncate(text, to: textLimit),
            description: "\(parts.count) things"
        )
    }

    /// One dropped thing. Copies Altillo made while receiving it (promised files, images without a file) are
    /// removed once read: the conversation is memory only, and nothing of it stays on disk.
    static func read(_ item: ShelfItem, limit: Int = textLimit, inboxRoot: URL = FileIngest.standard.inboxRoot,
                     recognizeImage: @Sendable (URL) async -> ImageReading? = { await recognize($0) }) async
        -> AssistantAttachment {
        let description = AssistantContent.kindDescription(item)
        switch item.kind {
        case let .text(text):
            return AssistantAttachment(
                name: item.displayName, kind: .document, text: AssistantContent.truncate(text, to: limit),
                description: "text"
            )
        case let .link(url):
            return AssistantAttachment(
                name: item.displayName, kind: .link,
                text: "A web link: \(url.absoluteString). Only the address is known; the page isn't opened.",
                description: "link"
            )
        case let .file(url, isOwnedCopy):
            defer { if isOwnedCopy { discardCopy(at: url, inboxRoot: inboxRoot) } }
            if isImage(url) {
                let reading = await recognizeImage(url)
                return AssistantAttachment(
                    name: item.displayName, kind: .image, text: imageText(reading, limit: limit),
                    description: "image"
                )
            }
            let readable = AssistantContent.readable(of: url)
            let body = AssistantContent.readFile(at: url, limit: limit)
            let kind: AssistantAttachment.Kind = switch readable {
            case .plainText, .richText, .pdf, .folder: .document
            case nil: .unreadable
            }
            return AssistantAttachment(name: item.displayName, kind: kind, text: body, description: description)
        }
    }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// A copy in Altillo's inbox, made only to receive the drop: gone once read, with its slot folder if empty.
    /// Only ever inside Altillo's Inbox (like `ShelfStore.removeOwnedFiles`): anything else is left alone.
    @discardableResult
    static func discardCopy(at url: URL, inboxRoot: URL = FileIngest.standard.inboxRoot) -> Bool {
        OwnedInboxCopy.discard(at: url, inboxRoot: inboxRoot)
    }

    // MARK: - Images

    /// What Vision found in an image, on this Mac.
    struct ImageReading: Equatable, Sendable {
        /// The lines of text in it, top to bottom.
        var lines: [String]
        /// What it seems to show ("dog", "beach"), most likely first.
        var labels: [String]
    }

    /// Reads the words in an image and guesses what it shows. Both run on this Mac, with no network.
    static func recognize(_ url: URL) async -> ImageReading? {
        var text = RecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.automaticallyDetectsLanguage = true
        let lines = (try? await text.perform(on: url))?
            .compactMap { $0.topCandidates(1).first?.string } ?? []
        let labels = (try? await ClassifyImageRequest().perform(on: url))?
            .filter { $0.confidence >= 0.3 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(6)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") } ?? []
        guard !lines.isEmpty || !labels.isEmpty else { return nil }
        return ImageReading(lines: lines, labels: Array(labels))
    }

    /// What the model is told about an image it can't see.
    static func imageText(_ reading: ImageReading?, limit: Int = textLimit) -> String {
        guard let reading, !reading.lines.isEmpty || !reading.labels.isEmpty else {
            return "An image. You can't see images, and no text or recognisable subject was found in it. Tell the user you can't see images yet, only read the text in them."
        }
        var text = "An image. You can't see it; this Mac read it for you."
        if !reading.labels.isEmpty {
            text += "\nIt seems to show: \(reading.labels.joined(separator: ", "))."
        }
        if reading.lines.isEmpty {
            text += "\nThere's no text in it."
        } else {
            text += "\nThe text in it:\n" + reading.lines.joined(separator: "\n")
        }
        text += "\nOnly describe what this says; say you can't see the image itself if asked about its look."
        return AssistantContent.truncate(text, to: limit)
    }

    // MARK: - The question

    /// The question with the attachment before it, so the model answers from it.
    static func prompt(for question: String, attachment: AssistantAttachment) -> String {
        """
        The user attached "\(attachment.name)" (\(attachment.description)). Its contents:
        \"\"\"
        \(attachment.text)
        \"\"\"

        Question about it: \(AssistantInstructions.prompt(for: question))
        Answer from the attachment. If it doesn't say, say so.
        """
    }

    /// Sent when the user presses Ask with an attachment and nothing typed.
    static func defaultQuestion(for attachment: AssistantAttachment) -> String {
        switch attachment.kind {
        case .image: String(localized: "What's in this image?")
        case .link: String(localized: "What is this link?")
        case .document, .unreadable: String(localized: "Summarize “\(attachment.name)”.")
        }
    }
}
