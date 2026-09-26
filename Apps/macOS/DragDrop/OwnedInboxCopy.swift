import AltilloCore
import Foundation

/// Deletes only disposable files that Altillo created while receiving a drop.
///
/// Keeping the containment check here gives Ask, AirDrop and future consumers one canonical deletion rule.
nonisolated enum OwnedInboxCopy {
    @discardableResult
    static func discard(at url: URL, inboxRoot: URL = FileIngest.standard.inboxRoot) -> Bool {
        let root = FileIngest.canonicalPath(inboxRoot)
        let path = FileIngest.canonicalPath(url)
        guard path != root, FileIngest.isInside(path, root) else { return false }
        let manager = FileManager.default
        try? manager.removeItem(at: url)
        let slot = url.deletingLastPathComponent()
        guard FileIngest.canonicalPath(slot) != root else { return true }
        if (try? manager.contentsOfDirectory(atPath: slot.path(percentEncoded: false)))?.isEmpty == true {
            try? manager.removeItem(at: slot)
        }
        return true
    }

    static func discard(in items: [ShelfItem], inboxRoot: URL = FileIngest.standard.inboxRoot) {
        for case let .file(url, isOwnedCopy) in items.map(\.kind) where isOwnedCopy {
            discard(at: url, inboxRoot: inboxRoot)
        }
    }
}
