import CoreServices
import Foundation
import Testing
@testable import Altillo

struct MailAttachmentSaverTests {
    @Test(arguments: [false, true])
    func savedAttachmentCarriesQuarantineAndReplacesOnlyAfterPreparation(replacing: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("altillo-save-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("synthetic.txt")
        if replacing { try Data("old synthetic data".utf8).write(to: destination) }
        let content = Data("synthetic attachment".utf8)
        try MailAttachmentSaver.save(content, to: destination)
        #expect(try Data(contentsOf: destination) == content)
        let metadata = try destination.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
        #expect(metadata?[kLSQuarantineAgentNameKey as String] as? String == "Altillo")
        #expect(metadata?[kLSQuarantineTypeKey as String] as? String == kLSQuarantineTypeEmailAttachment as String)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["synthetic.txt"])
    }

    @Test func failedPreparationDoesNotCreateDestination() {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("synthetic.txt")
        #expect(throws: MailAttachmentSaveFailure.self) { try MailAttachmentSaver.save(Data([1, 2]), to: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
