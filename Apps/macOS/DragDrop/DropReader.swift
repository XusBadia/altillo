import AppKit
import UniformTypeIdentifiers

/// Pasteboard types Altillo accepts, shared by the global drag detector and the drop target.
nonisolated enum DragPasteboard {
    static let promisedFileURL = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
    static let legacyFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    static let urlName = NSPasteboard.PasteboardType("public.url-name")
    static let jpeg = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
    static let heic = NSPasteboard.PasteboardType(UTType.heic.identifier)
    static let gif = NSPasteboard.PasteboardType(UTType.gif.identifier)
    static let webP = NSPasteboard.PasteboardType(UTType.webP.identifier)

    /// File promise types (new and legacy), as reported by AppKit.
    static let promiseTypes: Set<NSPasteboard.PasteboardType> =
        Set(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType(rawValue: $0) })
            .union([promisedFileURL])

    /// Raw image types, most preferred first (kept as-is when written to the inbox; TIFF is converted to PNG).
    static let imageTypes: [NSPasteboard.PasteboardType] = [.png, jpeg, heic, gif, webP, .tiff]

    static let textTypes: [NSPasteboard.PasteboardType] = [.string, .rtf, .html]

    /// Everything the drop target registers for.
    static let droppableTypes: [NSPasteboard.PasteboardType] = {
        var types: [NSPasteboard.PasteboardType] = Array(promiseTypes) + [.fileURL, legacyFilenames, .URL]
        types += imageTypes + textTypes
        var seen = Set<NSPasteboard.PasteboardType>()
        return types.filter { seen.insert($0).inserted }
    }()

    private static let droppableSet = Set(droppableTypes)

    static func isDroppable(_ types: [NSPasteboard.PasteboardType]?) -> Bool {
        types?.contains(where: droppableSet.contains) ?? false
    }
}

/// One thing read from a drop, in pasteboard order. File promises are gathered separately (see `DropPayload`).
nonisolated enum IncomingDrop: Equatable, Sendable {
    case file(URL)
    case link(URL, title: String?)
    /// Image data without a file behind it. `type` is the pasteboard type the bytes came from.
    case image(Data, type: String, suggestedName: String)
    case text(String)
}

struct DropPayload {
    /// Items that could be read synchronously, in pasteboard order.
    var items: [IncomingDrop] = []
    /// File promises (Photos, Mail, Safari, …). They must be received while the drop is being performed.
    var promises: [NSFilePromiseReceiver] = []
    /// Pasteboard items that carried a promise (for logging).
    var promiseItemCount = 0
    /// Where the promised files go among `items`, so the shelf keeps the order of the drag.
    var promiseInsertionIndex = 0

    var isEmpty: Bool { items.isEmpty && promises.isEmpty }

    /// "2 promesas, 1 archivo, 1 texto" for the log.
    var summary: String {
        var files = 0, links = 0, images = 0, texts = 0
        for item in items {
            switch item {
            case .file: files += 1
            case .link: links += 1
            case .image: images += 1
            case .text: texts += 1
            }
        }
        let parts = [(promises.count, "promesas"), (files, "archivos"), (links, "enlaces"), (images, "imágenes"), (texts, "textos")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)" }
        return parts.isEmpty ? "nada legible" : parts.joined(separator: ", ")
    }
}

/// Reads a drag pasteboard into Altillo's item kinds. Pure pasteboard access, so it can be tested with a named pasteboard.
@MainActor
enum DropReader {
    static func read(from pasteboard: NSPasteboard) -> DropPayload {
        var payload = DropPayload()
        // Items that carry a promise; `true` when the promise is the only way to get the file (no file URL too).
        var promiseItems: [Bool] = []
        for item in pasteboard.pasteboardItems ?? [] {
            let hasPromise = item.types.contains(where: DragPasteboard.promiseTypes.contains)
            let hasFile = item.types.contains(.fileURL)
            if hasPromise { promiseItems.append(!hasFile) }
            if hasPromise, !hasFile {
                if payload.promiseItemCount == 0 { payload.promiseInsertionIndex = payload.items.count }
                payload.promiseItemCount += 1
            } else if let entry = read(item) {
                payload.items.append(entry)
            }
        }
        if payload.promiseItemCount > 0 {
            // Receivers can only be created through `readObjects` (one per promise item, in order; legacy promises
            // yield a single receiver for several files). Skip the ones whose item also offered a real file URL.
            let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
            if receivers.count == promiseItems.count {
                payload.promises = zip(receivers, promiseItems).filter(\.1).map(\.0)
            } else {
                payload.promises = receivers
            }
        }
        if payload.isEmpty, let names = pasteboard.propertyList(forType: DragPasteboard.legacyFilenames) as? [String] {
            // Very old sources only write NSFilenamesPboardType on the first item.
            payload.items = names.map { .file(URL(filePath: $0)) }
        }
        return payload
    }

    /// Order of preference inside one pasteboard item: file › image data › URL › text.
    /// Image data wins over a web URL so a browser image without a promise arrives as the image, not as a link to it.
    static func read(_ item: NSPasteboardItem) -> IncomingDrop? {
        let types = item.types

        if types.contains(.fileURL), let string = item.string(forType: .fileURL), let url = fileURL(from: string) {
            return .file(url)
        }

        let webURL = item.string(forType: .URL).flatMap(URL.init(string:))
        if let type = DragPasteboard.imageTypes.first(where: types.contains), let data = item.data(forType: type) {
            return .image(data, type: type.rawValue, suggestedName: imageName(for: type, source: webURL))
        }

        if let webURL {
            if webURL.isFileURL, let url = fileURL(from: webURL.absoluteString) { return .file(url) }
            let title = item.string(forType: DragPasteboard.urlName)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .link(webURL, title: title?.isEmpty == false ? title : nil)
        }

        if let text = plainText(item) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let url = singleWebURL(trimmed) { return .link(url, title: nil) }
            return .text(text)
        }
        return nil
    }

    /// Finder writes file reference URLs (`file:///.file/id=…`); resolve them to path URLs.
    static func fileURL(from string: String) -> URL? {
        guard let url = URL(string: string), url.isFileURL else { return nil }
        return (url as NSURL).filePathURL ?? url
    }

    /// Selected text that is exactly one http(s) URL becomes a link.
    static func singleWebURL(_ text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace), let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host() != nil
        else { return nil }
        return url
    }

    private static func plainText(_ item: NSPasteboardItem) -> String? {
        if let string = item.string(forType: .string) { return string }
        if let data = item.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            return attributed.string
        }
        if let data = item.data(forType: .html),
           let attributed = NSAttributedString(html: data, documentAttributes: nil) {
            return attributed.string
        }
        return nil
    }

    private static func imageName(for type: NSPasteboard.PasteboardType, source: URL?) -> String {
        let ext = type == .tiff ? "png" : (UTType(type.rawValue)?.preferredFilenameExtension ?? "png")
        if let source, !source.lastPathComponent.isEmpty, source.lastPathComponent != "/" {
            let base = source.deletingPathExtension().lastPathComponent
            if !base.isEmpty { return "\(base).\(ext)" }
        }
        return "Imagen \(Date.now.formatted(.iso8601)).\(ext)"
    }
}
