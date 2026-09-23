import AltilloCore
import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Everything the assistant's tools hand to the model, as short plain text.
///
/// The on-device model has a context window of about 4 096 tokens for instructions, tools, the conversation and the
/// answer together, so every tool output is capped (`toolOutputLimit`) and says so when it was cut. These strings
/// talk to the model, not to the user: they are English and never localised (the model answers in the user's
/// language anyway). Pure functions where possible so they can be tested without a model, a calendar or a player.
enum AssistantContent {
    /// Ceiling for anything a single tool returns, in characters (roughly 600–800 tokens).
    static let toolOutputLimit = 2_500
    /// Never read more than this from a plain text file: a 40 MB log would be cut to 2 500 characters anyway.
    static let readByteLimit = 64 * 1024
    /// Shelf listings stop here; the rest is summarised as a count.
    static let listingLimit = 20

    // MARK: - Truncation

    /// Cuts `text` to at most `limit` characters, preferring a word boundary, and says how much was left out so the
    /// model doesn't present a fragment as the whole thing.
    static func truncate(_ text: String, to limit: Int = toolOutputLimit) -> String {
        guard text.count > limit else { return text }
        let marker = "\n[…cut: the rest isn't shown]"
        let budget = max(0, limit - marker.count)
        var head = String(text.prefix(budget))
        // Back up to the last whitespace if it's close, so words aren't sliced in half.
        if let space = head.lastIndex(where: \.isWhitespace),
           head.distance(from: space, to: head.endIndex) < 80 {
            head = String(head[..<space])
        }
        return head.trimmingCharacters(in: .whitespacesAndNewlines) + marker
    }

    // MARK: - What a shelf item is

    /// How a file can be turned into text.
    enum Readable: Equatable, Sendable {
        /// Plain text, Markdown, source code, JSON, CSV…: read the bytes.
        case plainText
        /// RTF, RTFD, Word, OpenDocument: through `NSAttributedString`.
        case richText
        case pdf
        case folder
    }

    private static let richTextTypes: [UTType] = [
        .rtf, .rtfd, .flatRTFD,
        UTType("org.openxmlformats.wordprocessingml.document"),
        UTType("com.microsoft.word.doc"),
        UTType("org.oasis-open.opendocument.text"),
    ].compactMap(\.self)

    /// What we can read in a file of this type, or nil for images, videos, archives and other binaries.
    static func readable(_ type: UTType?) -> Readable? {
        guard let type else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if richTextTypes.contains(where: { type.conforms(to: $0) }) { return .richText }
        // HTML goes through as source: `NSAttributedString` would need WebKit on the main thread.
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) { return .plainText }
        if type.conforms(to: .directory) && !type.conforms(to: .package) { return .folder }
        return nil
    }

    /// Guessed from the extension alone: good enough for the listing and the suggestion chips, which must not
    /// touch the disk on the main actor.
    static func readable(of url: URL) -> Readable? {
        if url.hasDirectoryPath { return .folder }
        return readable(UTType(filenameExtension: url.pathExtension))
    }

    /// True when the assistant can say something about the item's contents (a document, a note), not just its name.
    static func hasReadableText(_ item: ShelfItem) -> Bool {
        switch item.kind {
        case .text: true
        case .link: false
        case let .file(url, _):
            switch readable(of: url) {
            case .plainText, .richText, .pdf: true
            case .folder, nil: false
            }
        }
    }

    /// "PDF file", "text", "link", "folder"… for the listing.
    static func kindDescription(_ item: ShelfItem) -> String {
        switch item.kind {
        case .text: return "text note"
        case .link: return "link"
        case let .file(url, _):
            if url.hasDirectoryPath { return "folder" }
            guard let type = UTType(filenameExtension: url.pathExtension) else { return "file" }
            if type.conforms(to: .pdf) { return "PDF file" }
            if type.conforms(to: .image) { return "image" }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return "video" }
            if type.conforms(to: .audio) { return "audio file" }
            if type.conforms(to: .archive) { return "archive" }
            if type.conforms(to: .application) || type.conforms(to: .applicationBundle) { return "app" }
            if type.conforms(to: .sourceCode) { return "source code file" }
            if type.conforms(to: .text) || richTextTypes.contains(where: { type.conforms(to: $0) }) {
                return "text document"
            }
            return type.localizedDescription.map { "\($0) file" } ?? "file"
        }
    }

    // MARK: - Shelf listing

    /// The whole shelf in a few lines, newest first. `size` measures files (injected so tests don't need a disk).
    static func listing(_ items: [ShelfItem], now: Date = .now, size: (URL) -> Int64?) -> String {
        guard !items.isEmpty else { return "The shelf is empty." }
        let newestFirst = items.sorted { $0.addedAt > $1.addedAt }
        let shown = newestFirst.prefix(listingLimit)
        var lines = ["\(items.count) \(items.count == 1 ? "thing" : "things") on the shelf, newest first:"]
        for item in shown {
            var parts = ["\"\(item.displayName)\"", kindDescription(item)]
            switch item.kind {
            case let .file(url, _):
                if let bytes = size(url) {
                    parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                }
            case let .text(text):
                parts.append("\(text.count) characters")
            case let .link(url):
                parts.append(url.absoluteString)
            }
            parts.append("added \(ago(item.addedAt, now: now))")
            lines.append("- " + parts.joined(separator: ", "))
        }
        if items.count > shown.count {
            lines.append("…and \(items.count - shown.count) older ones.")
        }
        return truncate(lines.joined(separator: "\n"))
    }

    /// "just now", "5 min ago", "3 h ago", "yesterday", "4 days ago". Plain English for the model.
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return "\(Int(seconds / 60)) min ago"
        case ..<86_400: return "\(Int(seconds / 3_600)) h ago"
        case ..<172_800: return "yesterday"
        default: return "\(Int(seconds / 86_400)) days ago"
        }
    }

    // MARK: - Finding an item by name

    /// The item the model means. It rarely types a name perfectly: tries the exact name, the name without its
    /// extension, then either containing the other. Ties go to the newest.
    static func find(_ query: String, in items: [ShelfItem]) -> ShelfItem? {
        let wanted = normalised(query)
        guard !wanted.isEmpty else { return nil }
        let newestFirst = items.sorted { $0.addedAt > $1.addedAt }
        let tests: [(String) -> Bool] = [
            { $0 == wanted },
            { stem($0) == stem(wanted) },
            { $0.contains(wanted) },
            { let s = stem($0); return s.count >= 3 && wanted.contains(s) },
        ]
        for test in tests {
            if let match = newestFirst.first(where: { test(normalised($0.displayName)) }) { return match }
        }
        return nil
    }

    private static func normalised(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”‘’«»")))
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func stem(_ name: String) -> String {
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, ext.count <= 5 else { return name }
        return (name as NSString).deletingPathExtension
    }

    // MARK: - Reading one item

    /// The text inside one shelf item, capped. Touches the disk: call it off the main actor.
    static func text(of item: ShelfItem) -> String {
        let header = "\"\(item.displayName)\" (\(kindDescription(item))):\n"
        switch item.kind {
        case let .text(text):
            return header + truncate(text, to: toolOutputLimit - header.count)
        case let .link(url):
            return header + "A web link: \(url.absoluteString). Only the address is known; web pages aren't opened."
        case let .file(url, _):
            return header + readFile(at: url, limit: toolOutputLimit - header.count)
        }
    }

    /// Reads a file defensively: it may have moved, be unreadable, huge, a folder or a binary.
    static func readFile(at url: URL, limit: Int = toolOutputLimit) -> String {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isReadableKey])
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return "The file isn't where it was anymore (moved or deleted)."
        }
        guard values?.isReadable != false else { return "The file can't be read (no permission)." }
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        let kind: Readable? = values?.isDirectory == true && type?.conforms(to: .package) != true
            ? .folder : readable(type)

        let body: String?
        switch kind {
        case .plainText: body = plainText(at: url)
        case .richText: body = richText(at: url)
        case .pdf: body = PDFDocument(url: url)?.string
        case .folder: body = folderListing(at: url)
        case nil:
            return "Its contents can't be read: only text, documents and PDFs can."
        }
        guard let body else { return "The file couldn't be opened." }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return kind == .pdf ? "The PDF has no text in it (probably scanned images)." : "The file is empty."
        }
        return truncate(trimmed, to: limit)
    }

    /// The first `readByteLimit` bytes as UTF-8 (lossy: a cut in the middle of a character, or a Latin-1 file,
    /// still reads).
    private static func plainText(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: readByteLimit) else { return nil }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    private static func richText(at url: URL) -> String? {
        (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
    }

    private static func folderListing(at url: URL) -> String? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))
        else { return nil }
        let visible = names.filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !visible.isEmpty else { return "An empty folder." }
        let shown = visible.prefix(30).map { "- \($0)" }.joined(separator: "\n")
        let more = visible.count > 30 ? "\n…and \(visible.count - 30) more." : ""
        return "A folder with \(visible.count) items:\n" + shown + more
    }

    /// File size in bytes, or nil for folders and missing files.
    static func fileSize(_ url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        guard values?.isDirectory != true, let size = values?.fileSize else { return nil }
        return Int64(size)
    }

    // MARK: - Shelf tool answer

    /// What the shelf tool says: the listing, or one item's text. Touches the disk: call it off the main actor.
    ///
    /// The small model rarely calls a tool twice in a row (list, then read), so a bare listing also carries the
    /// beginning of the newest readable things: "summarize the notes on my shelf" works in one call.
    static func shelfAnswer(name: String?, items: [ShelfItem], now: Date = .now) -> String {
        let query = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return truncate(listing(items, now: now, size: fileSize) + previews(of: items))
        }
        guard !items.isEmpty else { return "The shelf is empty, so there's nothing called \"\(query)\"." }
        guard let item = find(query, in: items) else {
            // Often a description in the user's words ("the meeting note"): show what there is, with its text.
            return truncate(
                "Nothing on the shelf is called \"\(query)\".\n" + listing(items, now: now, size: fileSize)
                    + previews(of: items)
            )
        }
        return text(of: item)
    }

    /// How many readable items a bare listing previews, and how much of each.
    static let previewCount = 2
    static let previewLength = 700

    /// The start of the newest documents and notes, after the listing.
    static func previews(of items: [ShelfItem]) -> String {
        let readable = items.filter(hasReadableText).sorted { $0.addedAt > $1.addedAt }.prefix(previewCount)
        guard !readable.isEmpty else { return "" }
        return readable.map { item in
            let body: String = switch item.kind {
            case let .text(text): truncate(text, to: previewLength)
            case let .file(url, _): readFile(at: url, limit: previewLength)
            case .link: ""
            }
            return "\n\nText of \"\(item.displayName)\":\n\(body)"
        }
        .joined()
    }

    // MARK: - Calendar

    /// One day's agenda. Times are 24 h and the day is spelled out in English: the model rewrites both in the
    /// user's language.
    static func agenda(
        _ events: [CalendarStore.Event], day: Date, now: Date = .now, calendar: Calendar = .current
    ) -> String {
        let dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.calendar = calendar
        dayFormat.timeZone = calendar.timeZone
        dayFormat.dateFormat = "EEEE d MMMM yyyy"
        let timeFormat = DateFormatter()
        timeFormat.locale = Locale(identifier: "en_US_POSIX")
        timeFormat.calendar = calendar
        timeFormat.timeZone = calendar.timeZone
        timeFormat.dateFormat = "HH:mm"

        let relative: String
        switch calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day {
        case 0: relative = " (today)"
        case 1: relative = " (tomorrow)"
        case -1: relative = " (yesterday)"
        default: relative = ""
        }
        let title = dayFormat.string(from: day) + relative
        guard !events.isEmpty else { return "\(title): no events." }

        var lines = ["\(title): \(events.count) \(events.count == 1 ? "event" : "events")."]
        for event in CalendarMapping.sorted(events) {
            var line = event.isAllDay
                ? "- all day: \(event.title)"
                : "- \(timeFormat.string(from: event.start))–\(timeFormat.string(from: event.end)) \(event.title)"
            if let location = event.location { line += " · at \(location)" }
            if event.conferenceURL != nil { line += " · video call" }
            if !event.isAllDay {
                if event.isRunning(at: now) { line += " (happening now)" } else if event.end <= now { line += " (over)" }
            }
            lines.append(line)
        }
        return truncate(lines.joined(separator: "\n"))
    }

    static let calendarNotGranted =
        "No calendar access. Tell the user they can allow it from the Calendar section of the notch."

    // MARK: - Now playing

    /// One sentence about a player's state.
    static func nowPlaying(_ snapshot: PlayerSnapshot, app: String) -> String {
        var sentence = "\(snapshot.isPlaying ? "Playing" : "Paused") in \(app): \"\(snapshot.title)\""
        if !snapshot.artist.isEmpty { sentence += " by \(snapshot.artist)" }
        if let album = snapshot.album { sentence += ", from the album \"\(album)\"" }
        if let duration = snapshot.duration {
            let elapsed = snapshot.elapsed.map { "\(clock($0)) of " } ?? ""
            sentence += " (\(elapsed)\(clock(duration)))"
        }
        return sentence + "."
    }

    /// "3:05", "1:02:09".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3_600, minutes = (total % 3_600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Clipboard

    /// Pasteboard types that password managers and friends set to say "don't read or keep this"
    /// (nspasteboard.org).
    static let privateClipboardTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
    ]

    /// What the clipboard tool says, from what the pasteboard exposes.
    static func clipboard(types: [String], text: String?, fileNames: [String], isDenied: Bool = false) -> String {
        if isDenied {
            return "Altillo isn't allowed to read the clipboard (System Settings › Privacy & Security › Paste from Other Apps)."
        }
        if types.contains(where: privateClipboardTypes.contains) {
            return "The clipboard holds something marked private (like a password), so it isn't read."
        }
        if !fileNames.isEmpty {
            let names = fileNames.prefix(10).map { "\"\($0)\"" }.joined(separator: ", ")
            return "The clipboard holds \(fileNames.count == 1 ? "a copied file" : "\(fileNames.count) copied files"): \(names)."
        }
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "The clipboard's text:\n" + truncate(text, to: toolOutputLimit - 24)
        }
        let imageTypes = [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue]
        if types.contains(where: imageTypes.contains) {
            return "The clipboard holds an image; its contents can't be described."
        }
        return "The clipboard is empty."
    }

    /// True when the general pasteboard has text worth explaining. Only looks at the types, never the contents,
    /// so it can't trip the pasteboard privacy alert.
    @MainActor
    static func clipboardHasText(_ pasteboard: NSPasteboard = .general) -> Bool {
        guard let types = pasteboard.types?.map(\.rawValue) else { return false }
        guard !types.contains(where: privateClipboardTypes.contains) else { return false }
        return types.contains(NSPasteboard.PasteboardType.string.rawValue)
            && !types.contains(NSPasteboard.PasteboardType.fileURL.rawValue)
    }

    /// Reads the current item of the general pasteboard. Called only when the user asked about it.
    @MainActor
    static func readClipboard(_ pasteboard: NSPasteboard = .general) -> String {
        let types = pasteboard.types?.map(\.rawValue) ?? []
        let denied = pasteboard.accessBehavior == .alwaysDeny
        guard !denied, !types.contains(where: privateClipboardTypes.contains) else {
            return clipboard(types: types, text: nil, fileNames: [], isDenied: denied)
        }
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let text = files.isEmpty ? pasteboard.string(forType: .string) : nil
        return clipboard(types: types, text: text, fileNames: files.map(\.lastPathComponent))
    }
}
