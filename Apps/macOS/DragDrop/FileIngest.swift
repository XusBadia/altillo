import AltilloCore
import Foundation

/// Decides whether a dropped file is referenced in place or copied into Altillo's inbox, and does the copy.
///
/// Policy ("referencia + mover al sacar", like Yoink): files in stable locations are referenced so dragging them
/// out again can move the original. Files in volatile locations (temporary folders, Mail attachments, browser caches,
/// the Trash, our own inbox) are cloned into `~/Library/Application Support/Altillo/Inbox/<uuid>/<name>`;
/// on APFS `FileManager.copyItem` uses `clonefile`, so the copy is instant and takes no extra space.
nonisolated struct FileIngest: Sendable {
    enum Decision: Equatable, Sendable {
        case reference
        case copy(reason: String)
    }

    enum IngestError: LocalizedError {
        case missing(URL)

        var errorDescription: String? {
            switch self {
            case let .missing(url): "No existe: \(url.path)"
            }
        }
    }

    static let standard = FileIngest(
        inboxRoot: URL.applicationSupportDirectory.appending(path: "Altillo/Inbox", directoryHint: .isDirectory)
    )

    let inboxRoot: URL
    let homeDirectory: URL
    let temporaryDirectory: URL

    init(
        inboxRoot: URL,
        homeDirectory: URL = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory),
        temporaryDirectory: URL = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
    ) {
        self.inboxRoot = inboxRoot
        self.homeDirectory = homeDirectory
        self.temporaryDirectory = temporaryDirectory
    }

    // MARK: - Classification

    /// Pure path-based decision (no disk access besides resolving symlinks such as /var → /private/var).
    func classify(_ url: URL) -> Decision {
        let path = Self.canonicalPath(url)
        let home = Self.canonicalPath(homeDirectory)

        if Self.isInside(path, Self.canonicalPath(inboxRoot)) { return .copy(reason: "inbox propio") }
        if Self.isInside(path, Self.canonicalPath(temporaryDirectory)) { return .copy(reason: "temporal") }
        for root in ["/private/var/folders", "/private/tmp", "/private/var/tmp"] where Self.isInside(path, root) {
            return .copy(reason: "temporal")
        }
        if Self.isInside(path, home + "/.Trash") || path.contains("/.Trashes/") { return .copy(reason: "papelera") }

        let library = home + "/Library"
        if Self.isInside(path, library + "/Containers/com.apple.mail")
            || Self.isInside(path, library + "/Mail")
            || Self.isInside(path, library + "/Mail Downloads") {
            return .copy(reason: "Mail")
        }
        if Self.isInside(path, library + "/Containers/com.apple.Safari")
            || Self.isInside(path, library + "/Safari") {
            return .copy(reason: "Safari")
        }
        if Self.isInside(path, library + "/Caches") { return .copy(reason: "cachés") }

        // Any sandboxed app's temporary folder: ~/Library/Containers/<bundle id>/Data/tmp/…
        let containers = library + "/Containers/"
        if path.hasPrefix(containers) {
            let parts = path.dropFirst(containers.count).split(separator: "/", omittingEmptySubsequences: true)
            if parts.count >= 3, parts[1] == "Data", parts[2] == "tmp" || parts[2] == "Library" && parts.count >= 4 && parts[3] == "Caches" {
                return .copy(reason: "temporal de \(parts[0])")
            }
        }
        return .reference
    }

    // MARK: - Ingest

    /// Turns a dropped file URL into a shelf item, copying it when `classify` says so.
    func ingest(fileAt url: URL) throws -> (item: ShelfItem, decision: Decision) {
        let url = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { throw IngestError.missing(url) }
        let decision = classify(url)
        switch decision {
        case .reference:
            return (ShelfItem(kind: .file(url, isOwnedCopy: false), displayName: Self.displayName(of: url)), decision)
        case .copy:
            let destination = try makeSlot(forName: url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: destination)
            return (ShelfItem(kind: .file(destination, isOwnedCopy: true), displayName: Self.displayName(of: destination)), decision)
        }
    }

    /// Writes raw data (an image without a file) into the inbox.
    func ingest(data: Data, suggestedName: String) throws -> ShelfItem {
        let destination = try makeSlot(forName: suggestedName)
        try data.write(to: destination, options: .atomic)
        return ShelfItem(kind: .file(destination, isOwnedCopy: true), displayName: Self.displayName(of: destination))
    }

    /// Wraps a file a promise already wrote into the inbox.
    func item(forReceivedFile url: URL) -> ShelfItem {
        ShelfItem(kind: .file(url, isOwnedCopy: true), displayName: Self.displayName(of: url))
    }

    /// A fresh `Inbox/<uuid>/` folder (file promises write into a folder and pick the file name themselves).
    func makeSlotDirectory() throws -> URL {
        let directory = inboxRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// `Inbox/<uuid>/<name>`: one folder per item keeps the original name and never collides.
    func makeSlot(forName name: String) throws -> URL {
        try makeSlotDirectory().appending(path: Self.sanitizedFileName(name), directoryHint: .notDirectory)
    }

    // MARK: - Helpers

    static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.isEmpty ? url.lastPathComponent : name
    }

    static func sanitizedFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = cleaned.hasPrefix(".") ? String(cleaned.drop(while: { $0 == "." })) : cleaned
        return trimmed.isEmpty ? "Sin título" : String(trimmed.prefix(200))
    }

    static func canonicalPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path
        // `resolvingSymlinksInPath` only resolves existing paths; normalise the well-known aliases by hand.
        for (alias, target) in [("/var/", "/private/var/"), ("/tmp/", "/private/tmp/")] where path.hasPrefix(alias) {
            path = target + path.dropFirst(alias.count)
        }
        if path == "/var" || path == "/tmp" { path = "/private" + path }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    static func isInside(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
