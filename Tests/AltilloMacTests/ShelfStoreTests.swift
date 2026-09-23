import AltilloCore
import Foundation
import Testing
@testable import Altillo

@MainActor
struct ShelfStoreTests {
    @MainActor
    private struct Fixture {
        let root: URL
        let inbox: URL
        let snapshot: URL
        let store: ShelfStore

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "AltilloShelfStoreTests-\(UUID().uuidString)")
            inbox = root.appending(path: "Inbox", directoryHint: .isDirectory)
            snapshot = root.appending(path: "State/shelf.json")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            store = ShelfStore(snapshotURL: snapshot, inboxRoot: inbox)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }

        func file(_ name: String = "document.txt", under directory: URL? = nil) throws -> URL {
            let directory = directory ?? root.appending(path: "Originales", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: name)
            try Data("contenido".utf8).write(to: url)
            return url
        }

        func ownedFile(_ name: String = "copy.txt") throws -> URL {
            let slot = inbox.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            return try file(name, under: slot)
        }
    }

    @Test func roundTripPreservesEveryKindAndIdentity() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.file()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let items = [
            ShelfItem(kind: .file(original, isOwnedCopy: false), displayName: "Document", addedAt: date),
            ShelfItem(kind: .text("a note"), displayName: "a note", addedAt: date),
            ShelfItem(kind: .link(URL(string: "https://example.com/path")!), displayName: "Example", addedAt: date),
        ]

        try fixture.store.save(items)
        let restored = fixture.store.restore(expiry: .never).items

        #expect(restored.map(\.id) == items.map(\.id))
        #expect(restored.map(\.displayName) == items.map(\.displayName))
        #expect(restored.map(\.addedAt) == items.map(\.addedAt))
        #expect(restored[0].fileURL?.standardizedFileURL == original.standardizedFileURL)
        #expect(restored[1].kind == .text("a note"))
        #expect(restored[2].kind == .link(URL(string: "https://example.com/path")!))
    }

    @Test func expiryRemovesOwnedCopyOnlyAfterDroppingItsRecord() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let copy = try fixture.ownedFile()
        let old = ShelfItem(
            kind: .file(copy, isOwnedCopy: true),
            displayName: "copy.txt",
            addedAt: Date(timeIntervalSince1970: 100)
        )
        try fixture.store.save([old])

        let restored = fixture.store.restore(expiry: .day, now: Date(timeIntervalSince1970: 100 + 86_400)).items

        #expect(restored.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        let recovery = fixture.inbox.deletingLastPathComponent().appending(path: "Recovery")
        #expect((try FileManager.default.contentsOfDirectory(atPath: recovery.path)).count == 1)
        #expect(fixture.store.restore(expiry: .never).items.isEmpty, "the expired record was committed to disk")
    }

    @Test func unavailableReferenceIsKeptForExternalAndCloudVolumes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let unavailable = fixture.root.appending(path: "Volumen desmontado/documento.txt")
        let item = ShelfItem(kind: .file(unavailable, isOwnedCopy: false), displayName: "document.txt")
        try fixture.store.save([item])

        let restored = fixture.store.restore(expiry: .never).items

        #expect(restored.map(\.id) == [item.id])
        #expect(restored.first?.fileURL == unavailable)
    }

    @Test func missingOwnedCopyIsPrunedButNoUnrelatedFileIsDeleted() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let unrelated = try fixture.file("do-not-touch.txt")
        let missing = try fixture.ownedFile("gone.txt")
        let forged = try fixture.ownedFile("forged.txt")
        let items = [
            ShelfItem(kind: .file(missing, isOwnedCopy: true), displayName: "gone.txt"),
            ShelfItem(kind: .file(forged, isOwnedCopy: true), displayName: "corrupt-mark.txt"),
        ]
        try fixture.store.save(items)
        try FileManager.default.removeItem(at: missing)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.snapshot)) as? [String: Any])
        var records = try #require(json["items"] as? [[String: Any]])
        records[1]["value"] = unrelated.path // malicious absolute path with `isOwnedCopy = true`
        json["items"] = records
        try JSONSerialization.data(withJSONObject: json).write(to: fixture.snapshot, options: .atomic)

        let restored = fixture.store.restore(expiry: .never).items

        #expect(restored.isEmpty)
        #expect(FileManager.default.fileExists(atPath: unrelated.path), "owned=true outside Inbox is never authority to delete")
    }

    @Test func removingOneDuplicateDoesNotDeleteTheCopyStillOnTheShelf() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let copy = try fixture.ownedFile()
        let removed = ShelfItem(kind: .file(copy, isOwnedCopy: true), displayName: "copy.txt")
        let kept = ShelfItem(kind: .file(copy, isOwnedCopy: true), displayName: "copy.txt")

        fixture.store.removeOwnedFiles(for: [removed], preserving: [kept])

        #expect(FileManager.default.fileExists(atPath: copy.path))
    }

    @Test func undoRestoresOwnedCopyAndRedoRetiresItAgain() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let copy = try fixture.ownedFile()
        let owned = ShelfItem(kind: .file(copy, isOwnedCopy: true), displayName: "copy.txt")
        let note = ShelfItem(kind: .text("a note"), displayName: "a note")
        try fixture.store.save([owned, note])
        let coordinator = NotchCoordinator(shelfStore: fixture.store)
        coordinator.model.shelf = [owned, note]

        coordinator.remove([owned.id, note.id])

        #expect(coordinator.model.shelf.isEmpty)
        #expect(coordinator.model.canUndoShelfChange)
        #expect(!FileManager.default.fileExists(atPath: copy.path))

        coordinator.undoShelfChange()

        #expect(coordinator.model.shelf.map(\.id) == [owned.id, note.id])
        #expect(coordinator.model.shelf.first?.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        #expect(coordinator.model.selection == [owned.id, note.id])
        #expect(coordinator.model.canRedoShelfChange)

        coordinator.redoShelfChange()

        #expect(coordinator.model.shelf.isEmpty)
        #expect(coordinator.model.canUndoShelfChange)
    }

    @Test func oneMalformedRecordDoesNotEmptyItsHealthyNeighbours() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let note = ShelfItem(kind: .text("still here"), displayName: "still here")
        try fixture.store.save([note])
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.snapshot)) as? [String: Any])
        var records = try #require(json["items"] as? [[String: Any]])
        records.append(["kind": "file", "this": "is truncated"])
        json["items"] = records
        try JSONSerialization.data(withJSONObject: json).write(to: fixture.snapshot, options: .atomic)

        let restored = fixture.store.restore(expiry: .never).items

        #expect(restored.map(\.id) == [note.id])
    }

    @Test func offlineReferenceKeepsItsLastGoodBookmarkAcrossSaves() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.file()
        let reference = ShelfItem(kind: .file(original, isOwnedCopy: false), displayName: "document.txt")
        try fixture.store.save([reference])
        let initialBookmark = try bookmark(in: fixture.snapshot, itemID: reference.id)
        let bookmarkBefore = try #require(initialBookmark)
        try FileManager.default.removeItem(at: original)

        let offline = fixture.store.restore(expiry: .never).items
        try fixture.store.save(offline + [ShelfItem(kind: .text("new"), displayName: "new")])

        let bookmarkAfter = try bookmark(in: fixture.snapshot, itemID: reference.id)
        #expect(bookmarkAfter == bookmarkBefore)
    }

    @Test func futureSnapshotVersionBlocksWritesInsteadOfOverwritingIt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalData = try JSONSerialization.data(withJSONObject: ["version": 999, "items": []])
        try FileManager.default.createDirectory(at: fixture.snapshot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try originalData.write(to: fixture.snapshot)

        if case .failed = fixture.store.restore(expiry: .never) {
            // Expected: a newer app may understand it, this one must leave it intact.
        } else {
            Issue.record("expected unsupported-version failure")
        }
        #expect(throws: ShelfStore.StoreError.self) {
            try fixture.store.save([ShelfItem(kind: .text("do not overwrite"), displayName: "do not overwrite")])
        }
        #expect(try Data(contentsOf: fixture.snapshot) == originalData)
    }

    @Test func corruptSnapshotIsQuarantinedInsteadOfOverwritten() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.snapshot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("this is not JSON".utf8).write(to: fixture.snapshot)

        if case .recoveredFromCorruptSnapshot = fixture.store.restore(expiry: .never) {
            // Expected: the damaged bytes are kept under a quarantine name and normal writes can resume.
        } else {
            Issue.record("expected corrupt snapshot recovery")
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.snapshot.path))
        let quarantined = try FileManager.default.contentsOfDirectory(
            at: fixture.snapshot.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        #expect(quarantined.contains { $0.lastPathComponent.hasPrefix("shelf.corrupt-") })
    }

    private func bookmark(in snapshot: URL, itemID: UUID) throws -> String? {
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: snapshot)) as? [String: Any])
        let items = try #require(json["items"] as? [[String: Any]])
        return items.first { $0["id"] as? String == itemID.uuidString }?["bookmark"] as? String
    }
}
