import AltilloCore
import AppKit
import Foundation
import Testing
@testable import Altillo

@MainActor
@Suite(.serialized)
struct SharingControllerTests {
    private final class FakeService: SharingServiceAdapter {
        weak var eventDelegate: (any SharingServiceAdapterDelegate)?
        var accepts = true
        var performed: [[Any]] = []

        func canPerform(with items: [Any]) -> Bool { accepts }
        func perform(with items: [Any]) { performed.append(items) }
        func succeed() { eventDelegate?.sharingServiceDidFinish() }
        func fail() { eventDelegate?.sharingServiceDidFail(TestError.failed) }
    }

    private enum TestError: Error { case failed }

    private func temporaryInbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AltilloSharingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func ownedItem(in root: URL, name: String = "image.png") throws -> ShelfItem {
        let slot = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
        let file = slot.appending(path: name)
        try Data([1, 2, 3]).write(to: file)
        return ShelfItem(kind: .file(file, isOwnedCopy: true), displayName: name)
    }

    @Test func successCleansOwnedCopyOnlyAfterCallback() throws {
        let root = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FakeService()
        let controller = SharingController(inboxRoot: root) { _ in service }
        let item = try ownedItem(in: root)
        let file = try #require(item.fileURL)

        #expect(controller.sendViaAirDrop([item], cleanupOwnedCopies: true))
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(controller.activeOperationCount == 1)

        service.succeed()

        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
        #expect(controller.activeOperationCount == 0)
    }

    @Test func failureAlsoCleansOwnedCopy() throws {
        let root = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FakeService()
        let controller = SharingController(inboxRoot: root) { _ in service }
        let item = try ownedItem(in: root)
        let file = try #require(item.fileURL)

        #expect(controller.sendViaAirDrop([item], cleanupOwnedCopies: true))
        service.fail()

        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(controller.activeOperationCount == 0)
    }

    @Test func unavailableServiceCleansAlreadyIngestedCopy() throws {
        let root = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = SharingController(inboxRoot: root) { _ in nil }
        let item = try ownedItem(in: root)
        let file = try #require(item.fileURL)

        #expect(!controller.sendViaAirDrop([item], cleanupOwnedCopies: true))
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(controller.activeOperationCount == 0)
    }

    @Test func incompatibleServiceCleansAlreadyIngestedCopy() throws {
        let root = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FakeService()
        service.accepts = false
        let controller = SharingController(inboxRoot: root) { _ in service }
        let item = try ownedItem(in: root)
        let file = try #require(item.fileURL)

        #expect(!controller.sendViaAirDrop([item], cleanupOwnedCopies: true))
        #expect(service.performed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(controller.activeOperationCount == 0)
    }

    @Test func nonOwnedAndOutsideInboxFilesAreNeverDeleted() throws {
        let root = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = FileManager.default.temporaryDirectory.appending(path: "altillo-outside-\(UUID().uuidString).txt")
        try Data("keep".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let regular = ShelfItem(kind: .file(outside, isOwnedCopy: false), displayName: "regular")
        let wronglyMarked = ShelfItem(kind: .file(outside, isOwnedCopy: true), displayName: "outside")
        let controller = SharingController(inboxRoot: root) { _ in nil }

        _ = controller.sendViaAirDrop([regular, wronglyMarked], cleanupOwnedCopies: true)

        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func shelfShareNeverDeletesItsOwnedBackingFile() throws {
        let root = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FakeService()
        let controller = SharingController(inboxRoot: root) { _ in service }
        let item = try ownedItem(in: root)
        let file = try #require(item.fileURL)

        #expect(controller.sendViaAirDrop([item], cleanupOwnedCopies: false))
        service.succeed()

        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(controller.activeOperationCount == 0)
    }

    @Test func simultaneousOperationsAreRetainedAndFinishedIndependently() throws {
        let root = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstService = FakeService()
        let secondService = FakeService()
        var services = [firstService, secondService]
        let controller = SharingController(inboxRoot: root) { _ in services.removeFirst() }
        let first = try ownedItem(in: root, name: "first.png")
        let second = try ownedItem(in: root, name: "second.png")

        #expect(controller.sendViaAirDrop([first], cleanupOwnedCopies: true))
        #expect(controller.sendViaAirDrop([second], cleanupOwnedCopies: true))
        #expect(controller.activeOperationCount == 2)

        firstService.succeed()
        #expect(controller.activeOperationCount == 1)
        #expect(!FileManager.default.fileExists(atPath: try #require(first.fileURL).path))
        #expect(FileManager.default.fileExists(atPath: try #require(second.fileURL).path))

        secondService.fail()
        #expect(controller.activeOperationCount == 0)
        #expect(!FileManager.default.fileExists(atPath: try #require(second.fileURL).path))
    }

    @Test func payloadPreservesMixedItemOrderAndTypes() throws {
        let file = URL(filePath: "/tmp/report.pdf")
        let link = try #require(URL(string: "https://example.com/a"))
        let items = [
            ShelfItem(kind: .file(file, isOwnedCopy: false), displayName: "report"),
            ShelfItem(kind: .link(link), displayName: "site"),
            ShelfItem(kind: .text("hello"), displayName: "note"),
        ]

        let payload = SharingOperation.payload(for: items)

        #expect(payload.count == 3)
        #expect(payload[0] as? URL == file)
        #expect(payload[1] as? URL == link)
        #expect(payload[2] as? String == "hello")
    }

    @Test func shelfTargetsUseTheClickedItemOrTheVisibleSelectionInShelfOrder() {
        let first = ShelfItem(kind: .text("one"), displayName: "one")
        let second = ShelfItem(kind: .text("two"), displayName: "two")
        let third = ShelfItem(kind: .text("three"), displayName: "three")
        let shelf = [first, second, third]

        #expect(ShelfSelection.targets(for: first, selection: [second.id, third.id], in: shelf) == [first])
        #expect(ShelfSelection.targets(for: third, selection: [second.id, third.id], in: shelf) == [second, third])
    }

    @Test func shelfActionsForwardAllItemsWithoutMutation() {
        let first = ShelfItem(kind: .text("one"), displayName: "one")
        let second = ShelfItem(kind: .text("two"), displayName: "two")
        let original = [first, second]
        var shared: [ShelfItem] = []
        var airDropped: [ShelfItem] = []
        let actions = NotchActions(share: { shared = $0 }, airDrop: { airDropped = $0 })

        actions.share(original)
        actions.airDrop(original)

        #expect(shared == original)
        #expect(airDropped == original)
        #expect(original == [first, second])
    }
}
