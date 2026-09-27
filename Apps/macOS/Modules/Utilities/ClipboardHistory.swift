import Foundation

// The clipboard section's plain logic, none of it touching the pasteboard: what a slip holds, what may be kept, the
// history itself (dedupe, pins, the cap) and where it's saved when the user wants it to survive a relaunch.

/// What a slip holds.
enum ClipboardContent: Hashable, Sendable {
    case text(String)
    /// Files copied in Finder (or any app that copies file references): where they are, never their contents.
    case files([ClipboardFile])
    /// A copied image; its PNG is in `ClipboardImages`.
    case image(ClipboardImage)

    /// What kind of slip it is, for the section's filter.
    enum Kind: String, CaseIterable, Sendable {
        case text, image, files
    }

    var kind: Kind {
        switch self {
        case .text: .text
        case .image: .image
        case .files: .files
        }
    }

    /// Two copies with the same key are the same slip.
    var dedupeKey: String {
        switch self {
        case let .text(text): "text:" + text
        case let .files(files): "files:" + files.map(\.path).joined(separator: "\n")
        case let .image(image): "image:" + image.hash
        }
    }
}

extension ClipboardContent: Codable {
    private enum CodingKeys: String, CodingKey { case kind, text, files, image }
    private enum StoredKind: String, Codable { case text, files, image }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(StoredKind.self, forKey: .kind) {
        case .text: self = .text(try container.decode(String.self, forKey: .text))
        case .files: self = .files(try container.decode([ClipboardFile].self, forKey: .files))
        case .image: self = .image(try container.decode(ClipboardImage.self, forKey: .image))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode(StoredKind.text, forKey: .kind)
            try container.encode(text, forKey: .text)
        case let .files(files):
            try container.encode(StoredKind.files, forKey: .kind)
            try container.encode(files, forKey: .files)
        case let .image(image):
            try container.encode(StoredKind.image, forKey: .kind)
            try container.encode(image, forKey: .image)
        }
    }
}

/// A copied file, by reference: its path and name when it was copied plus (for the first few of a copy) a small
/// bookmark, so a file Finder moves or renames afterwards is still found. Its contents are never read.
nonisolated struct ClipboardFile: Hashable, Sendable {
    var path: String
    /// Its name when copied, extension included (what search and the slip use, without touching the disk).
    var name: String
    var bookmark: Data?

    init(path: String, name: String? = nil, bookmark: Data? = nil) {
        self.path = path
        self.name = name ?? (path as NSString).lastPathComponent
        self.bookmark = bookmark
    }

    init(url: URL, bookmarked: Bool = true) {
        self.init(path: url.path, name: url.lastPathComponent,
                  bookmark: bookmarked ? try? url.bookmarkData(options: .minimalBookmark) : nil)
    }

    /// The folder it was in, by name.
    var folderName: String {
        ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
    }

    /// Where the file is now: its old path if it's still there, else wherever the bookmark finds it; nil once
    /// it's gone. Touches the disk: keep it off the main thread where a slow volume could stall it.
    func resolvedURL() -> URL? {
        if FileManager.default.fileExists(atPath: path) { return URL(filePath: path) }
        guard let bookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}

extension ClipboardFile: Codable {
    private enum CodingKeys: String, CodingKey { case path, name, bookmark }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(path: try container.decode(String.self, forKey: .path),
                  name: try container.decodeIfPresent(String.self, forKey: .name),
                  bookmark: try container.decodeIfPresent(Data.self, forKey: .bookmark))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(bookmark, forKey: .bookmark)
    }
}

/// A copied text's formatting, as the app that copied it offered it: put back beside the text when it's copied
/// again, so pasting into Pages or Mail keeps bold, links and lists.
struct ClipboardRichText: Codable, Hashable, Sendable {
    var rtf: Data?
    var html: Data?

    /// Largest formatting kept per kind: a styled page, not a copied document with pictures inside.
    static let maxBytes = 256 * 1024

    /// Only what fits; nil when nothing does.
    init?(rtf: Data?, html: Data?) {
        let rtf = rtf.flatMap { $0.isEmpty || $0.count > Self.maxBytes ? nil : $0 }
        let html = html.flatMap { $0.isEmpty || $0.count > Self.maxBytes ? nil : $0 }
        guard rtf != nil || html != nil else { return nil }
        self.rtf = rtf
        self.html = html
    }
}

/// One thing the user copied: a text (maybe with its formatting), some files or an image.
struct ClipboardItem: Identifiable, Hashable, Sendable {
    var id: UUID
    var content: ClipboardContent
    /// When it was last copied (copying the same thing again brings it back to the top).
    var copiedAt: Date
    /// The app it came from: `org.nspasteboard.source` when the app says so, else the frontmost app.
    var sourceBundleID: String?
    var sourceName: String?
    var isPinned: Bool
    /// A text slip's formatting, when it had some.
    var richText: ClipboardRichText?

    init(id: UUID = UUID(), content: ClipboardContent, copiedAt: Date = .now, sourceBundleID: String? = nil,
         sourceName: String? = nil, isPinned: Bool = false, richText: ClipboardRichText? = nil) {
        self.id = id
        self.content = content
        self.richText = richText
        self.copiedAt = copiedAt
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.isPinned = isPinned
    }

    init(id: UUID = UUID(), text: String, copiedAt: Date = .now, sourceBundleID: String? = nil,
         sourceName: String? = nil, isPinned: Bool = false) {
        self.init(id: id, content: .text(text), copiedAt: copiedAt, sourceBundleID: sourceBundleID,
                  sourceName: sourceName, isPinned: isPinned)
    }

    /// The slip's words, what search looks through: the copied text, or the files' names (one per line); none for
    /// an image.
    var text: String {
        switch content {
        case let .text(text): text
        case let .files(files): files.map(\.name).joined(separator: "\n")
        case let .image(image): image.recognizedText ?? ""
        }
    }

    var files: [ClipboardFile] {
        if case let .files(files) = content { files } else { [] }
    }

    var image: ClipboardImage? {
        if case let .image(image) = content { image } else { nil }
    }

    /// The first two non-empty lines, trimmed: what a text slip shows.
    var preview: String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.prefix(2).joined(separator: "\n")
    }

    /// A short name for the shelf and VoiceOver: the first line (or the file's name), cut at 48 characters.
    var title: String {
        switch content {
        case .text:
            let line = preview.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return line.count > 48 ? String(line.prefix(47)) + "…" : line
        case let .files(files):
            let name = files.first?.name ?? ""
            let short = name.count > 40 ? String(name.prefix(39)) + "…" : name
            return files.count > 1 ? String(localized: "\(short) and \(files.count - 1) more") : short
        case let .image(image):
            return String(localized: "Image, \(image.width) × \(image.height)")
        }
    }
}

extension ClipboardItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, content, text, copiedAt, sourceBundleID, sourceName, isPinned, richText
    }

    /// Histories saved before slips could hold files have only `text`; one saved by a newer Altillo may hold a kind
    /// this one doesn't know, which falls back to its `text` rather than losing the whole history.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        if let content = try? container.decode(ClipboardContent.self, forKey: .content) {
            self.content = content
        } else {
            content = .text(try container.decode(String.self, forKey: .text))
        }
        copiedAt = try container.decode(Date.self, forKey: .copiedAt)
        sourceBundleID = try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        richText = try? container.decodeIfPresent(ClipboardRichText.self, forKey: .richText)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        // `text` too, so an older Altillo still reads the history (a file slip becomes its names).
        try container.encode(text, forKey: .text)
        try container.encode(copiedAt, forKey: .copiedAt)
        try container.encodeIfPresent(sourceBundleID, forKey: .sourceBundleID)
        try container.encodeIfPresent(sourceName, forKey: .sourceName)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(richText, forKey: .richText)
    }
}

// MARK: - Privacy

/// What the clipboard history never keeps. Two independent signals, either one is enough:
///
/// - **Markers on the pasteboard** (nspasteboard.org and the private types password managers and text expanders
///   add): concealed (passwords), transient (restored in a moment), auto-generated (nobody pressed ⌘C).
/// - **The app it came from** is a password manager, whether it says so with `org.nspasteboard.source` or is simply
///   the frontmost app when the copy happened. Covers managers that don't mark their copies.
enum ClipboardPrivacy {
    static let concealedType = "org.nspasteboard.ConcealedType"
    static let transientType = "org.nspasteboard.TransientType"
    static let autoGeneratedType = "org.nspasteboard.AutoGeneratedType"
    /// Its value is the bundle id of the app that wrote the pasteboard.
    static let sourceType = "org.nspasteboard.source"

    /// Types that mean "don't read or keep this" (nspasteboard.org, plus the private markers Maccy and Alfred honour).
    static let privateTypes: Set<String> = [
        concealedType,
        transientType,
        autoGeneratedType,
        "com.agilebits.onepassword",
        "Pasteboard generator type",
        "de.petermaurer.TransientPasteboardType",
        "net.antelle.keeweb",
        "com.typeit4me.clipping",
    ]

    /// Password managers, by bundle id (lowercased). Exact ids first, then vendor prefixes, since vendors rename
    /// their apps between major versions (1Password 7 → 8, App Store vs direct builds).
    static let passwordManagerBundleIDs: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.passwords",
        "com.apple.passwords-app",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.agilebits.onepassword4",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.lastpass.lastpass",
        "com.lastpass.lastpassmacdesktop",
        "com.dashlane.dashlanephonefinal",
        "in.sinew.enpass-desktop",
        "com.keepersecurity.passwordmanager",
        "me.proton.pass.electron",
        "com.markmcguill.strongbox.mac",
        "com.markmcguill.strongbox",
        "com.github.mstarke.macpass",
        "com.outercorner.secrets",
        "com.nordsec.nordpass",
        "com.roboform.roboform",
    ]

    static let passwordManagerPrefixes: [String] = [
        "com.1password.", "com.agilebits.", "com.bitwarden.", "org.keepassxc.", "com.lastpass.", "com.dashlane.",
        "in.sinew.enpass", "com.keepersecurity.", "me.proton.pass", "com.markmcguill.strongbox", "com.nordsec.nordpass",
    ]

    static func isPasswordManager(_ bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased(), !id.isEmpty else { return false }
        return passwordManagerBundleIDs.contains(id) || passwordManagerPrefixes.contains { id.hasPrefix($0) }
    }

    static func isPrivate(types: [String]) -> Bool {
        types.contains(where: privateTypes.contains)
    }

    enum Decision: Equatable, Sendable {
        /// Plain text from an ordinary app: read it and keep it.
        case record
        /// File references (a Finder copy): read the URLs, never the files.
        case recordFiles
        /// An image, with no text beside it: read it and keep it as PNG.
        case recordImage
        /// Marked private, or copied in a password manager: never read.
        case skipPrivate
        /// Nothing this history keeps.
        case skipNotText
    }

    static let fileURLType = "public.file-url"

    /// Decides from the types alone (reading them never shows the pasteboard privacy alert) whether the contents
    /// may be read at all, and as what. Files win over text: Finder puts the names on the pasteboard as text too.
    /// Text wins over an image (apps put a picture of copied text or cells beside it), but a web address doesn't:
    /// "Copy Image" in a browser adds the image's URL.
    static func decide(types: [String], frontmostBundleID: String?) -> Decision {
        if isPrivate(types: types) || isPasswordManager(frontmostBundleID) { return .skipPrivate }
        if types.contains(fileURLType) { return .recordFiles }
        let plainText: Set<String> = ["public.utf8-plain-text", "NSStringPboardType"]
        let hasText = types.contains(where: plainText.contains)
        if !hasText, types.contains(where: imageTypes.contains) { return .recordImage }
        return hasText || types.contains("public.url") ? .record : .skipNotText
    }

    static let imageTypes: Set<String> = [
        "public.png", "public.tiff", "public.jpeg", "public.heic", "com.compuserve.gif", "org.webmproject.webp",
        "com.microsoft.bmp", "NeXT TIFF v4.0 pasteboard type",
    ]

    /// A single web or file address and nothing else: what a browser puts beside a copied image.
    static func isJustAnAddress(_ text: String?) -> Bool {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              !text.contains(where: \.isWhitespace), let url = URL(string: text),
              let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "file", "data", "blob"].contains(scheme)
    }

    /// Most files one slip keeps: a copy of a whole folder's contents isn't something to keep here.
    static let maxFiles = 200
    /// Files of one copy that get a bookmark (the rest are found by path only), so a big copy stays light.
    static let maxBookmarkedFiles = 20

    /// Longest text kept, in UTF-16 units (≈ 100 KB): a copied log file isn't something you paste back from here,
    /// and fifty of them would weigh on memory.
    static let maxTextLength = 100_000

    /// The text worth keeping, or nil: empty, only whitespace, or too long.
    static func keepable(_ text: String?) -> String? {
        guard let text, text.utf16.count <= maxTextLength,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

// MARK: - History

/// The slips, newest first. At most `maxItems` in all; pins (at most `maxPinned`) are never pushed out.
struct ClipboardHistory: Codable, Equatable, Sendable {
    static let maxItems = 50
    static let maxPinned = 20
    /// Image slips kept at most, and how much their PNGs may weigh together (they're in memory).
    static let maxImages = 12
    static let maxImageBytes = 64 * 1024 * 1024

    private(set) var items: [ClipboardItem] = []

    init(items: [ClipboardItem] = []) {
        self.items = items
        trim()
    }

    var pinned: [ClipboardItem] { items.filter(\.isPinned) }
    var recent: [ClipboardItem] { items.filter { !$0.isPinned } }
    /// The order the section shows: pins first, then the rest, each newest first.
    var ordered: [ClipboardItem] { pinned + recent }
    var isEmpty: Bool { items.isEmpty }
    var canPinMore: Bool { pinned.count < Self.maxPinned }
    /// The images the slips point to, by hash.
    var imageHashes: Set<String> { Set(items.compactMap(\.image?.hash)) }

    /// Keeps a copy. The same thing copied again moves to the top (keeping its pin) instead of appearing twice.
    /// A text copied again takes the formatting of this copy (or none): copying it back gives what was copied last.
    @discardableResult
    mutating func record(_ content: ClipboardContent, richText: ClipboardRichText? = nil, at date: Date = .now,
                         sourceBundleID: String? = nil, sourceName: String? = nil) -> ClipboardItem {
        var item = ClipboardItem(content: content, copiedAt: date, sourceBundleID: sourceBundleID,
                                 sourceName: sourceName, richText: richText)
        let key = content.dedupeKey
        if let index = items.firstIndex(where: { $0.content.dedupeKey == key }) {
            let existing = items.remove(at: index)
            // The same files again: keep the bookmarks already made when there are no new ones.
            if case let .files(new) = content, case let .files(old) = existing.content {
                item.content = .files(zip(new, old).map { new, old in
                    var file = new
                    if file.bookmark == nil { file.bookmark = old.bookmark }
                    return file
                })
            }
            // The same image again: what was read in it still holds.
            if case var .image(new) = content, case let .image(old) = existing.content, new.recognizedText == nil {
                new.recognizedText = old.recognizedText
                item.content = .image(new)
            }
            item.id = existing.id
            item.isPinned = existing.isPinned
            item.sourceBundleID = sourceBundleID ?? existing.sourceBundleID
            item.sourceName = sourceName ?? existing.sourceName
        }
        // Newest first: a copy that took a moment to prepare (an image) still lands by when it was copied.
        items.insert(item, at: items.firstIndex { $0.copiedAt <= date } ?? items.count)
        trim()
        return item
    }

    @discardableResult
    mutating func record(_ text: String, at date: Date = .now, sourceBundleID: String? = nil,
                         sourceName: String? = nil) -> ClipboardItem {
        record(.text(text), at: date, sourceBundleID: sourceBundleID, sourceName: sourceName)
    }

    /// The words read in an image (nil forgets them), on every slip showing it.
    mutating func setRecognizedText(_ text: String?, forImage hash: String) {
        for index in items.indices {
            guard case var .image(image) = items[index].content, image.hash == hash else { continue }
            image.recognizedText = text
            items[index].content = .image(image)
        }
    }

    /// Copied back from the section: it becomes the newest.
    mutating func touch(_ id: ClipboardItem.ID, at date: Date = .now) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.copiedAt = date
        items.insert(item, at: 0)
    }

    @discardableResult
    mutating func remove(_ id: ClipboardItem.ID) -> ClipboardItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    /// Pins or unpins. Returns false (and changes nothing) when there are already `maxPinned` pins.
    @discardableResult
    mutating func togglePin(_ id: ClipboardItem.ID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        if !items[index].isPinned && !canPinMore { return false }
        items[index].isPinned.toggle()
        trim()
        return true
    }

    /// Clears the history. Pinned slips stay: pinning is how the user says "keep this".
    mutating func clear() {
        items.removeAll { !$0.isPinned }
    }

    /// Slips whose words (`ClipboardItem.text`) contain every word of `query` (case- and accent-insensitive), in section order.
    /// Only slips of `kind`, when one is given.
    func matching(_ query: String, kind: ClipboardContent.Kind? = nil) -> [ClipboardItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let shown: [ClipboardItem] = if let kind { ordered.filter { $0.content.kind == kind } } else { ordered }
        guard !words.isEmpty else { return shown }
        return shown.filter { item in
            words.allSatisfy { item.text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// Drops the oldest unpinned slips beyond the cap, and the oldest unpinned images beyond theirs.
    private mutating func trim() {
        while items.count > Self.maxItems, let index = items.lastIndex(where: { !$0.isPinned }) {
            items.remove(at: index)
        }
        func overImages() -> Bool {
            let images = items.compactMap(\.image)
            return images.count > Self.maxImages || images.reduce(0) { $0 + $1.byteCount } > Self.maxImageBytes
        }
        while overImages(), let index = items.lastIndex(where: { !$0.isPinned && $0.image != nil }) {
            items.remove(at: index)
        }
    }
}

// MARK: - Keeping it across launches

/// The history on disk, only while the user asked for it (off by default): one JSON file in Application Support,
/// readable by the user alone (0600), with complete file protection, left out of backups. Turning the option off
/// deletes it.
struct ClipboardArchive: Sendable {
    let url: URL

    static let standard = ClipboardArchive(
        url: URL.applicationSupportDirectory.appending(path: "Altillo/Clipboard/history.json")
    )

    func load() -> ClipboardHistory? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ClipboardHistory.self, from: data)
    }

    func save(_ history: ClipboardHistory) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(history)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            // Volumes without data protection refuse the option; the permissions below still keep it private.
            try data.write(to: url, options: [.atomic])
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = url
        try? target.setResourceValues(values)
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - What a text slip is

/// A text slip that is a single web address and nothing else, split the way the slip shows it: the site, then the
/// rest. Read from the text alone; nothing is ever fetched.
struct ClipboardLink: Equatable, Sendable {
    let url: URL
    /// The site, without "www." (and with its port, when it has one): "github.com".
    let host: String
    /// Everything after the site (path, query, fragment), readable: "/xusbadia/altillo/pull/128". Empty for a bare
    /// site.
    let rest: String

    /// Longest text looked at: an address, not a pasted page.
    static let maxLength = 4_096

    /// Only http and https, with a site, and no spaces anywhere; nil for anything else.
    init?(_ text: String) {
        guard text.utf16.count <= Self.maxLength else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let rawHost = components.host, !rawHost.isEmpty,
              let url = components.url else { return nil }
        var host = rawHost.lowercased()
        if host.hasPrefix("www."), host.count > 4 { host.removeFirst(4) }
        if let port = components.port { host += ":\(port)" }
        var rest = components.percentEncodedPath.removingPercentEncoding ?? components.percentEncodedPath
        if rest == "/" { rest = "" }
        if let query = components.percentEncodedQuery { rest += "?" + (query.removingPercentEncoding ?? query) }
        if let fragment = components.percentEncodedFragment {
            rest += "#" + (fragment.removingPercentEncoding ?? fragment)
        }
        self.url = url
        self.host = host
        self.rest = rest
    }
}

/// A text slip that is only a colour code: `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, `rgb(…)` or `rgba(…)`. The
/// components are sRGB, 0 to 1.
struct ClipboardColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// nil unless the whole text (give or take surrounding spaces) is one colour code. Hex needs its "#": six bare
    /// digits are just as likely a number.
    init?(_ text: String) {
        guard text.utf16.count <= 64 else { return nil }
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let color: ClipboardColor? = if code.hasPrefix("#") {
            Self.hex(code.dropFirst())
        } else if code.hasPrefix("rgb") {
            Self.functional(code)
        } else {
            nil
        }
        guard let color else { return nil }
        self = color
    }

    /// 3, 4, 6 or 8 hex digits (the short forms doubled: "f80" is "ff8800").
    private static func hex(_ digits: Substring) -> ClipboardColor? {
        guard [3, 4, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit) else { return nil }
        let pairs: [String] = digits.count <= 4
            ? digits.map { String(repeating: $0, count: 2) }
            : stride(from: 0, to: digits.count, by: 2).map { offset in
                String(digits.dropFirst(offset).prefix(2))
            }
        let values = pairs.compactMap { UInt8($0, radix: 16) }.map { Double($0) / 255 }
        guard values.count == pairs.count else { return nil }
        return ClipboardColor(red: values[0], green: values[1], blue: values[2], alpha: values.count == 4 ? values[3] : 1)
    }

    /// `rgb(255, 136, 0)`, `rgba(255, 136, 0, 0.5)`, the space form `rgb(255 136 0 / 50%)`, and channels in percent.
    private static func functional(_ code: String) -> ClipboardColor? {
        let name = code.hasPrefix("rgba(") ? "rgba(" : "rgb("
        guard code.hasPrefix(name), code.hasSuffix(")") else { return nil }
        let inside = code.dropFirst(name.count).dropLast()
        let parts = inside.split(whereSeparator: { $0 == "," || $0 == "/" || $0.isWhitespace }).map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let channels = parts.prefix(3).compactMap { amount($0, upTo: 255) }
        guard channels.count == 3 else { return nil }
        var alpha = 1.0
        if parts.count == 4 {
            guard let value = amount(parts[3], upTo: 1) else { return nil }
            alpha = value
        }
        return ClipboardColor(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }

    /// A channel (0–255) or an opacity (0–1), or either in percent; as 0 to 1. nil when out of range.
    private static func amount(_ text: String, upTo maximum: Double) -> Double? {
        if text.hasSuffix("%") {
            guard let percent = Double(text.dropLast()), (0 ... 100).contains(percent) else { return nil }
            return percent / 100
        }
        guard let value = Double(text), (0 ... maximum).contains(value) else { return nil }
        return value / maximum
    }
}

extension ClipboardItem {
    /// The web address a text slip is, when it's only that.
    var link: ClipboardLink? {
        if case let .text(text) = content { ClipboardLink(text) } else { nil }
    }

    /// The colour a text slip is, when it's only a colour code.
    var color: ClipboardColor? {
        if case let .text(text) = content { ClipboardColor(text) } else { nil }
    }
}
