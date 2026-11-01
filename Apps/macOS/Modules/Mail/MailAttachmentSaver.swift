import CoreServices
import Foundation

enum MailAttachmentSaveFailure: Error { case failed }

/// Prepare a private, quarantined file before replacing the user-selected destination.
/// Failure never removes or partially overwrites an existing file.
enum MailAttachmentSaver {
    static func save(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".altillo-attachment-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            var values = URLResourceValues()
            values.quarantineProperties = [
                kLSQuarantineTypeKey as String: kLSQuarantineTypeEmailAttachment,
                kLSQuarantineAgentNameKey as String: "Altillo",
                kLSQuarantineTimeStampKey as String: Date()
            ]
            var file = temporary
            try file.setResourceValues(values)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary, options: .usingNewMetadataOnly)
            } else { try FileManager.default.moveItem(at: temporary, to: destination) }
        } catch { throw MailAttachmentSaveFailure.failed }
    }
}
