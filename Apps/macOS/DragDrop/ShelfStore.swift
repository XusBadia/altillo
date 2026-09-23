import AltilloCore
import Foundation

/// Persists the shelf without ever taking ownership of the user's original files.
///
/// Stable files are stored as bookmarks (plus their last path as a fallback), so Finder can move or rename one
/// while Altillo is closed and the reference can still follow it. Files copied into Altillo's inbox are stored as
/// validated relative paths: those paths belong to Altillo and remain stable until the item is removed or expires.
@MainActor
final class ShelfStore {
    struct RetiredFile: Sendable {
        let itemID: ShelfItem.ID
        let originalURL: URL
        let recoveryURL: URL
    }

    enum Restoration {
        case absent
        case restored([ShelfItem])
        case recoveredFromCorruptSnapshot
        case failed

        var items: [ShelfItem] {
            if case let .restored(items) = self { items } else { [] }
        }
    }

    enum StoreError: LocalizedError {
        case writesBlocked
        case invalidOwnedLocation

        var errorDescription: String? {
            switch self {
            case .writesBlocked:
                String(localized: "Nothing is written, so a shelf state that couldn't be restored isn't overwritten.")
            case .invalidOwnedLocation:
                String(localized: "A copy marked as ours is outside Altillo's Inbox.")
            }
        }
    }

    static let standard = ShelfStore(
        snapshotURL: URL.applicationSupportDirectory.appending(path: "Altillo/shelf.json"),
        inboxRoot: FileIngest.standard.inboxRoot
    )

    private let snapshotURL: URL
    private let inboxRoot: URL
    private let recoveryRoot: URL
    private let fileManager: FileManager
    /// Last known-good bookmark per item. Needed when a reference is temporarily offline while another shelf
    /// mutation is saved: regenerating then may fail, but the bookmark that can find it again must survive.
    private var knownBookmarks: [ShelfItem.ID: Data] = [:]
    private var writesBlocked = false

    init(snapshotURL: URL, inboxRoot: URL, fileManager: FileManager = .default) {
        self.snapshotURL = snapshotURL
        self.inboxRoot = inboxRoot
        recoveryRoot = inboxRoot.deletingLastPathComponent().appending(path: "Recovery", directoryHint: .isDirectory)
        self.fileManager = fileManager
    }

    /// Restores everything still valid, quietly dropping expired entries and files that no longer exist.
    /// A corrupt snapshot is quarantined beside the original instead of being overwritten on launch.
    func restore(expiry: ShelfExpiry, now: Date = .now) -> Restoration {
        writesBlocked = false
        knownBookmarks.removeAll()
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            purgeOldRecovery(at: now)
            return .absent
        }

        let snapshot: Snapshot
        do {
            snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: snapshotURL))
        } catch {
            SpikeLog.shared.record(SpikeLog.Category.drop, "FAILED restoring the shelf: \(error.localizedDescription)")
            if quarantineCorruptSnapshot() {
                return .recoveredFromCorruptSnapshot
            }
            writesBlocked = true
            return .failed
        }

        guard snapshot.version == Snapshot.currentVersion else {
            SpikeLog.shared.record(SpikeLog.Category.drop, "Unsupported shelf format: v\(snapshot.version)")
            writesBlocked = true
            return .failed
        }

        knownBookmarks = snapshot.items.reduce(into: [:]) { result, record in
            if let bookmark = record.bookmark { result[record.id] = bookmark }
        }

        var restored: [ShelfItem] = []
        var discarded: [ShelfItem] = []
        for record in snapshot.items {
            guard let item = record.item(inboxRoot: inboxRoot) else { continue }
            if isExpired(item, expiry: expiry, now: now) || !isAvailable(item) {
                discarded.append(item)
            } else {
                restored.append(item)
            }
        }

        // Commit the new list before deleting an owned copy. If persistence fails, keeping an orphan is safer than
        // leaving the old snapshot pointing at a file we just destroyed.
        do {
            try save(restored)
            removeOwnedFiles(for: discarded, preserving: restored)
            purgeOldRecovery(at: now)
        } catch {
            SpikeLog.shared.record(SpikeLog.Category.shelf, "FAILED cleaning up the shelf: \(error.localizedDescription)")
        }
        return .restored(restored)
    }

    func save(_ items: [ShelfItem]) throws {
        guard !writesBlocked else { throw StoreError.writesBlocked }
        let directory = snapshotURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let records = items.compactMap { Record($0, inboxRoot: inboxRoot, existingBookmark: knownBookmarks[$0.id]) }
        guard records.count == items.count else { throw StoreError.invalidOwnedLocation }
        let snapshot = Snapshot(version: Snapshot.currentVersion, items: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)
        knownBookmarks = records.reduce(into: [:]) { result, record in
            if let bookmark = record.bookmark { result[record.id] = bookmark }
        }
    }

    func expiredItems(in items: [ShelfItem], expiry: ShelfExpiry, now: Date = .now) -> [ShelfItem] {
        items.filter { isExpired($0, expiry: expiry, now: now) }
    }

    /// Retires only copies underneath Altillo's own inbox. They spend seven days in Altillo's private Recovery
    /// folder before being purged, so a mistaken clear/expiry never destroys the only copy immediately. A
    /// forged/corrupt `isOwnedCopy` bit cannot touch arbitrary files because the canonical path must remain inside
    /// `inboxRoot`.
    @discardableResult
    func removeOwnedFiles(for items: [ShelfItem], preserving keptItems: [ShelfItem] = []) -> [RetiredFile] {
        let keptPaths = Set(keptItems.compactMap(\.fileURL).map { FileIngest.canonicalPath($0) })
        var retired: [RetiredFile] = []
        for item in items {
            guard case let .file(url, isOwnedCopy: true) = item.kind,
                  FileIngest.isInside(FileIngest.canonicalPath(url), FileIngest.canonicalPath(inboxRoot)),
                  !keptPaths.contains(FileIngest.canonicalPath(url))
            else { continue }

            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                let recoverySlot = recoveryRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                try fileManager.createDirectory(at: recoverySlot, withIntermediateDirectories: true)
                let recoveryURL = recoverySlot.appending(path: url.lastPathComponent)
                try fileManager.moveItem(at: url, to: recoveryURL)
                try? fileManager.setAttributes([.modificationDate: Date.now], ofItemAtPath: recoverySlot.path)
                retired.append(RetiredFile(itemID: item.id, originalURL: url, recoveryURL: recoveryURL))
            } catch {
                SpikeLog.shared.record(SpikeLog.Category.shelf, "FAILED setting aside \(url.lastPathComponent): \(error.localizedDescription)")
                continue
            }
            removeEmptySlot(containing: url)
        }
        return retired
    }

    /// Puts copies retired by an undoable removal back inside the Inbox. If their old path has since been occupied,
    /// a fresh slot is used instead of overwriting anything.
    func restoreOwnedFiles(_ retired: [RetiredFile]) -> [ShelfItem.ID: URL] {
        var restored: [ShelfItem.ID: URL] = [:]
        for file in retired {
            guard FileIngest.isInside(
                FileIngest.canonicalPath(file.originalURL),
                FileIngest.canonicalPath(inboxRoot)
            ), FileIngest.isInside(
                FileIngest.canonicalPath(file.recoveryURL),
                FileIngest.canonicalPath(recoveryRoot)
            ), fileManager.fileExists(atPath: file.recoveryURL.path)
            else { continue }

            do {
                let destination: URL
                if fileManager.fileExists(atPath: file.originalURL.path) {
                    let slot = inboxRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                    try fileManager.createDirectory(at: slot, withIntermediateDirectories: true)
                    destination = slot.appending(path: file.originalURL.lastPathComponent)
                } else {
                    try fileManager.createDirectory(
                        at: file.originalURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    destination = file.originalURL
                }
                try fileManager.moveItem(at: file.recoveryURL, to: destination)
                restored[file.itemID] = destination
                let recoverySlot = file.recoveryURL.deletingLastPathComponent()
                if (try? fileManager.contentsOfDirectory(atPath: recoverySlot.path).isEmpty) == true {
                    try? fileManager.removeItem(at: recoverySlot)
                }
            } catch {
                SpikeLog.shared.record(
                    SpikeLog.Category.shelf,
                    "FAILED restoring \(file.originalURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }
        return restored
    }

    private func purgeOldRecovery(at now: Date) {
        guard let slots = try? fileManager.contentsOfDirectory(
            at: recoveryRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        for slot in slots {
            let modified = try? slot.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified < cutoff { try? fileManager.removeItem(at: slot) }
        }
    }

    private func isExpired(_ item: ShelfItem, expiry: ShelfExpiry, now: Date) -> Bool {
        guard let duration = expiry.duration else { return false }
        return now.timeIntervalSince(item.addedAt) >= duration
    }

    private func isAvailable(_ item: ShelfItem) -> Bool {
        guard case let .file(url, isOwnedCopy) = item.kind else { return true }
        // A reference may live on an unmounted disk, in an offline cloud provider, or behind a temporarily denied
        // privacy permission. Keep it: absence at one launch is not proof that the user's original was deleted.
        guard isOwnedCopy else { return true }
        // `isOwnedCopy` from disk is untrusted. Altillo owns a file only when it is actually inside its Inbox.
        return FileIngest.isInside(FileIngest.canonicalPath(url), FileIngest.canonicalPath(inboxRoot))
            && fileManager.fileExists(atPath: url.path)
    }

    private func removeEmptySlot(containing url: URL) {
        let slot = url.deletingLastPathComponent()
        guard slot.deletingLastPathComponent().standardizedFileURL == inboxRoot.standardizedFileURL,
              (try? fileManager.contentsOfDirectory(atPath: slot.path).isEmpty) == true
        else { return }
        try? fileManager.removeItem(at: slot)
    }

    @discardableResult
    private func quarantineCorruptSnapshot() -> Bool {
        let quarantine = snapshotURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(UUID().uuidString).json")
        do {
            try fileManager.moveItem(at: snapshotURL, to: quarantine)
            return true
        } catch {
            SpikeLog.shared.record(SpikeLog.Category.shelf, "FAILED preserving the corrupt state: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - On-disk format

private extension ShelfStore {
    struct Snapshot: Codable {
        static let currentVersion = 1
        var version: Int
        var items: [Record]

        init(version: Int, items: [Record]) {
            self.version = version
            self.items = items
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            // One malformed entry must not empty the whole shelf. Each array element gets its own decoder, so a
            // failed record can be skipped while every healthy neighbour still restores.
            items = try container.decode([LossyRecord].self, forKey: .items).compactMap(\.value)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(items, forKey: .items)
        }

        private enum CodingKeys: String, CodingKey { case version, items }
    }

    struct LossyRecord: Decodable {
        let value: Record?

        init(from decoder: Decoder) throws {
            value = try? Record(from: decoder)
        }
    }

    struct Record: Codable {
        enum Kind: String, Codable { case file, text, link }

        var id: UUID
        var kind: Kind
        var displayName: String
        var addedAt: Date
        var value: String
        var isOwnedCopy: Bool?
        var bookmark: Data?
        init?(_ item: ShelfItem, inboxRoot: URL, existingBookmark: Data?) {
            id = item.id
            displayName = item.displayName
            addedAt = item.addedAt
            switch item.kind {
            case let .file(url, isOwnedCopy):
                kind = .file
                self.isOwnedCopy = isOwnedCopy
                if isOwnedCopy {
                    let path = FileIngest.canonicalPath(url)
                    let root = FileIngest.canonicalPath(inboxRoot)
                    guard FileIngest.isInside(path, root), path != root else { return nil }
                    value = String(path.dropFirst(root.count + 1))
                    bookmark = nil
                } else if FileManager.default.fileExists(atPath: url.path) {
                    value = url.path
                    bookmark = (try? url.bookmarkData()) ?? existingBookmark
                } else {
                    value = url.path
                    bookmark = existingBookmark
                }
            case let .text(text):
                kind = .text
                value = text
            case let .link(url):
                kind = .link
                value = url.absoluteString
            }
        }

        func item(inboxRoot: URL) -> ShelfItem? {
            let itemKind: ShelfItem.Kind
            switch kind {
            case .file:
                let owned = isOwnedCopy ?? false
                let url: URL
                if owned {
                    let components = value.split(separator: "/", omittingEmptySubsequences: false)
                    guard !value.hasPrefix("/"), !components.isEmpty,
                          components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
                    else { return nil }
                    let candidate = inboxRoot.appending(path: value)
                    guard FileIngest.isInside(FileIngest.canonicalPath(candidate), FileIngest.canonicalPath(inboxRoot))
                    else { return nil }
                    url = candidate
                } else if let bookmark {
                    var stale = false
                    if let resolved = try? URL(
                        resolvingBookmarkData: bookmark,
                        options: [.withoutUI],
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale
                    ) {
                        url = resolved
                    } else {
                        url = URL(filePath: value)
                    }
                } else {
                    url = URL(filePath: value)
                }
                itemKind = .file(url, isOwnedCopy: owned)
            case .text:
                itemKind = .text(value)
            case .link:
                guard let url = URL(string: value) else { return nil }
                itemKind = .link(url)
            }
            return ShelfItem(id: id, kind: itemKind, displayName: displayName, addedAt: addedAt)
        }

        enum CodingKeys: String, CodingKey {
            case id, kind, displayName, addedAt, value, isOwnedCopy, bookmark
        }
    }
}
