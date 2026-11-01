import Foundation
import Security
import AltilloMail

struct MailCredentialRecord: Codable, Equatable, Sendable {
    var version = 1
    let account: NativeMailAccount
    let googleState: Data?
    let microsoftAccountID: String?
    var serverCredentials: NativeMailServerCredentials? = nil
    var authorizationVersion: Int? = nil

    var hasCredential: Bool {
        switch account.service {
        case .google: googleState != nil
        case .microsoft: microsoftAccountID != nil
        case .icloud, .imap: serverCredentials != nil
        }
    }
}

protocol MailCredentialBackend: Sendable {
    func readAll() throws -> [Data]
    func write(_ data: Data, key: String) throws
    func remove(key: String) throws
}

/// A single Keychain item commits account identity and its credential reference together.
/// The lock also makes read/modify/write sequences safe for synchronous account restoration.
final class MailCredentialStore: @unchecked Sendable {
    private let backend: any MailCredentialBackend
    private let lock = NSLock()

    init(service: String = (Bundle.main.bundleIdentifier ?? "me.badia.altillo") + ".mail-native",
         backend: (any MailCredentialBackend)? = nil) {
        self.backend = backend ?? SecurityMailCredentialBackend(service: service)
    }

    func records() throws -> [MailCredentialRecord] {
        try lock.withLock {
            try backend.readAll().map { data in
                guard data.count <= 2 * 1_024 * 1_024,
                      let record = try? JSONDecoder().decode(MailCredentialRecord.self, from: data),
                      record.version == 1, !record.account.remoteID.isEmpty,
                      !record.account.address.isEmpty,
                      record.hasCredential
                else { throw MailAuthFailure.credentialStorage }
                return record
            }
        }
    }

    func record(for id: UUID) throws -> MailCredentialRecord? {
        try records().first { $0.account.id == id }
    }

    func save(_ record: MailCredentialRecord) throws {
        try lock.withLock {
            do { try backend.write(JSONEncoder().encode(record), key: record.account.id.uuidString) }
            catch { throw MailAuthFailure.credentialStorage }
        }
    }

    func remove(_ id: UUID) throws {
        try lock.withLock {
            do { try backend.remove(key: id.uuidString) }
            catch { throw MailAuthFailure.credentialStorage }
        }
    }
}

private struct SecurityMailCredentialBackend: MailCredentialBackend {
    let service: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }

    func readAll() throws -> [Data] {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? [Data] else {
            throw MailAuthFailure.credentialStorage
        }
        return data
    }

    func write(_ data: Data, key: String) throws {
        var query = query
        query[kSecAttrAccount as String] = key
        let attributes = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addition = query
            addition[kSecValueData as String] = data
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(addition as CFDictionary, nil)
            if status == errSecDuplicateItem { status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary) }
        }
        guard status == errSecSuccess else { throw MailAuthFailure.credentialStorage }
    }

    func remove(key: String) throws {
        var query = query
        query[kSecAttrAccount as String] = key
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw MailAuthFailure.credentialStorage }
    }
}
