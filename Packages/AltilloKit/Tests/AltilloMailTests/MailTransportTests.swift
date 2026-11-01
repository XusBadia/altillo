#if os(macOS)
import AltilloAgents
import Darwin
import Foundation
import Testing
@testable import AltilloMail

@Suite("Mail bridge lifecycle and deadlines")
struct MailTransportTests {
    private final class Inbox: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [MailEnvelope] = []
        var events: [MailEnvelope] { lock.withLock { values } }
        func receive(_ event: MailEnvelope) { lock.withLock { values.append(event) } }
    }

    private struct Location {
        let root: String
        var socket: String { root + "/mail.sock" }
        init(create: Bool = true) throws {
            root = "/tmp/altillo-mail-\(getpid())-\(UUID().uuidString)"
            if create {
                try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: false,
                                                        attributes: [.posixPermissions: 0o700])
            }
        }
        func clean() { try? FileManager.default.removeItem(atPath: root) }
    }

    private func payload(id: String = "fixture@example.invalid") throws -> Data {
        try JSONEncoder().encode(MailEnvelope(messageID: id, sender: "Synthetic", subject: "A new message",
                                             body: "Your verification code is 482913", account: "Work",
                                             receivedAt: Date().timeIntervalSince1970))
    }

    @Test func deliveryAcknowledgesAndDeduplicatesBeforeTheClientReturns() throws {
        let location = try Location()
        defer { location.clean() }
        let inbox = Inbox()
        let server = MailEventServer(path: location.socket) { inbox.receive($0) }
        defer { server.stop() }
        try server.start()
        #expect(try MailBridgeClient.deliver(payload(), path: location.socket) == .accepted)
        #expect(try MailBridgeClient.deliver(payload(), path: location.socket) == .duplicate)
        #expect(inbox.events.count == 1)
        #expect(inbox.events.first?.code == "482913")
        #expect(try MailBridgeClient.deliver(payload(id: "another@example.invalid"), path: location.socket) == .accepted)
        #expect(inbox.events.count == 2)
        let attributes = try FileManager.default.attributesOfItem(atPath: location.socket)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func createsOnlyItsMissingPrivateDirectoryAndStopsIdempotently() throws {
        let location = try Location(create: false)
        defer { location.clean() }
        let server = MailEventServer(path: location.socket) { _ in }
        try server.start()
        try server.start()
        let attributes = try FileManager.default.attributesOfItem(atPath: location.root)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        server.stop()
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: location.socket))
        #expect(throws: MailBridgeClient.Failure.unavailable) { try MailBridgeClient.deliver(payload(), path: location.socket) }
    }

    @Test func deduplicationMetadataExpiresEvenWhenNoMoreMailArrives() async throws {
        let location = try Location()
        defer { location.clean() }
        let server = MailEventServer(path: location.socket, deduplicationLifetime: 0.05) { _ in }
        defer { server.stop() }
        try server.start()
        #expect(try MailBridgeClient.deliver(payload(), path: location.socket) == .accepted)
        #expect(server.rememberedMessageCount == 1)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while server.rememberedMessageCount != 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(server.rememberedMessageCount == 0)
        #expect(try MailBridgeClient.deliver(payload(), path: location.socket) == .accepted)
    }

    @Test func secondServerCannotReplaceTheLiveSocket() throws {
        let location = try Location()
        defer { location.clean() }
        let first = MailEventServer(path: location.socket) { _ in }
        defer { first.stop() }
        try first.start()
        let inode = UnixSocket.inode(of: location.socket)
        let second = MailEventServer(path: location.socket) { _ in }
        #expect(throws: UnixSocket.Failure.inUse) { try second.start() }
        second.stop()
        #expect(UnixSocket.inode(of: location.socket) == inode)
        #expect(try MailBridgeClient.deliver(payload(), path: location.socket) == .accepted)
    }

    @Test func refusesPublicDirectoriesSymlinksAndExistingRegularFiles() throws {
        let location = try Location()
        defer { location.clean() }
        #expect(chmod(location.root, 0o755) == 0)
        let publicDirectory = MailEventServer(path: location.socket) { _ in }
        #expect(throws: MailEventServer.Failure.unsafePath) { try publicDirectory.start() }
        var attributes = try FileManager.default.attributesOfItem(atPath: location.root)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o755)
        #expect(chmod(location.root, 0o700) == 0)
        let target = location.root + "/target"
        try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.createSymbolicLink(atPath: location.root + "/link", withDestinationPath: target)
        let symbolicDirectory = MailEventServer(path: location.root + "/link/mail.sock") { _ in }
        #expect(throws: MailEventServer.Failure.unsafePath) { try symbolicDirectory.start() }
        let sentinel = Data("do not replace".utf8)
        try sentinel.write(to: URL(fileURLWithPath: location.socket))
        let regularFile = MailEventServer(path: location.socket) { _ in }
        #expect(throws: MailEventServer.Failure.unsafePath) { try regularFile.start() }
        #expect(try Data(contentsOf: URL(fileURLWithPath: location.socket)) == sentinel)
        attributes = try FileManager.default.attributesOfItem(atPath: target)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test func rejectsMalformedAndMultipleFramesWithoutCallingTheApp() throws {
        let location = try Location()
        defer { location.clean() }
        let inbox = Inbox()
        let server = MailEventServer(path: location.socket) { inbox.receive($0) }
        defer { server.stop() }
        try server.start()
        for frame in [Data("not JSON\n".utf8), try payload() + Data([10]) + payload(id: "other@example.invalid") + Data([10])] {
            let fd = try UnixSocket.connect(path: location.socket)
            defer { close(fd) }
            #expect(UnixSocket.writeAll(fd, frame))
            #expect(UnixSocket.readLine(fd, timeout: 2) == Data("rejected".utf8))
        }
        #expect(inbox.events.isEmpty)
    }

    @Test func aSilentClientDoesNotBlockARealMessageAndIsEventuallyRejected() throws {
        let location = try Location()
        defer { location.clean() }
        let server = MailEventServer(path: location.socket) { _ in }
        defer { server.stop() }
        try server.start()
        let silent = try UnixSocket.connect(path: location.socket)
        defer { close(silent) }
        #expect(try MailBridgeClient.deliver(payload(), path: location.socket) == .accepted)
        #expect(UnixSocket.readLine(silent, timeout: 2) == Data("rejected".utf8))
    }

    @Test func clientDoesNotHangOnAReceiverThatNeverReadsOrReplies() throws {
        let location = try Location()
        defer { location.clean() }
        let listener = try UnixSocket.listen(path: location.socket)
        defer { close(listener.fd); UnixSocket.removeIfOwned(path: location.socket, listener: listener) }
        let started = Date()
        #expect(throws: MailBridgeClient.Failure.timedOut) { try MailBridgeClient.deliver(payload(), path: location.socket) }
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @Test func clientCanonicalizesPrettyPrintedJSONIntoOneWireFrame() throws {
        let location = try Location()
        defer { location.clean() }
        let server = MailEventServer(path: location.socket) { _ in }
        defer { server.stop() }
        try server.start()
        let object = try JSONSerialization.jsonObject(with: payload())
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        #expect(pretty.contains(10))
        #expect(try MailBridgeClient.deliver(pretty, path: location.socket) == .accepted)
    }

    @Test func stdinReadHasABoundWhenTheWriterNeverCloses() throws {
        var fds: [Int32] = [-1, -1]
        #expect(pipe(&fds) == 0)
        defer { close(fds[0]); close(fds[1]) }
        #expect(throws: MailBridgeClient.Failure.timedOut) { try MailBridgeClient.readInput(fd: fds[0], timeout: 0.05) }
    }

    @Test func stdinRejectsOversizeInputAndReturnsSmallInputOnEOF() throws {
        let location = try Location()
        defer { location.clean() }
        let file = location.root + "/input"
        try Data(count: MailWire.byteLimit + 1).write(to: URL(fileURLWithPath: file))
        var fd = open(file, O_RDONLY)
        #expect(fd >= 0)
        #expect(throws: MailBridgeClient.Failure.invalidInput) { try MailBridgeClient.readInput(fd: fd) }
        close(fd)
        let small = try payload()
        try small.write(to: URL(fileURLWithPath: file))
        fd = open(file, O_RDONLY)
        defer { close(fd) }
        #expect(try MailBridgeClient.readInput(fd: fd) == small)
    }
}
#endif
