import AltilloCore
import AppKit
import Foundation
import Testing
@testable import Altillo

/// Dragging out must never lose the user's files: only the files themselves decide what left the shelf.
@MainActor
struct DragOutSafetyTests {
    private func departed(_ items: [ShelfItem], after operation: NSDragOperation) async -> [ShelfItem] {
        await withCheckedContinuation { continuation in
            ShelfDragSourceView.resolveDeparted(items, after: operation) { _, departed in
                continuation.resume(returning: departed)
            }
        }
    }

    private func makeFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "AltilloDragOutTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "original.txt")
        try Data("hola".utf8).write(to: url)
        return url
    }

    @Test func destinationReturningEveryBitDoesNotTrashTheOriginal() async throws {
        let url = try makeFile()
        let item = ShelfItem(kind: .file(url, isOwnedCopy: false), displayName: "original.txt")
        let all: NSDragOperation = [.copy, .move, .link, .generic, .delete]

        let result = await departed([item], after: all)

        #expect(result.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func movedFileLeavesTheShelf() async throws {
        let url = try makeFile()
        let item = ShelfItem(kind: .file(url, isOwnedCopy: false), displayName: "original.txt")
        try FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appending(path: "moved.txt"))

        let result = await departed([item], after: .move)

        #expect(result.map(\.id) == [item.id])
    }

    @Test func textAndLinksNeverLeave() async {
        let items = [
            ShelfItem(kind: .text("hola"), displayName: "hola"),
            ShelfItem(kind: .link(URL(string: "https://getseam.app")!), displayName: "getseam.app"),
        ]
        #expect(await departed(items, after: .move).isEmpty)
    }

    @Test func cancelledDragKeepsEverything() async throws {
        let url = try makeFile()
        let item = ShelfItem(kind: .file(url, isOwnedCopy: false), displayName: "original.txt")
        #expect(await departed([item], after: []).isEmpty)
    }
}
