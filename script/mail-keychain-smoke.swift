import Foundation
import Security

enum SmokeFailure: Error { case storage(OSStatus), protection }

func checkPrivateKeychain() throws {
    let service = "altillo.native-mail-qa." + UUID().uuidString
    let payload = Data("synthetic Keychain check".utf8)
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service, kSecAttrAccount as String: "synthetic",
        kSecUseDataProtectionKeychain as String: true, kSecAttrSynchronizable as String: false
    ]
    var item = query
    item[kSecValueData as String] = payload
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let added = SecItemAdd(item as CFDictionary, nil)
    guard added == errSecSuccess else { throw SmokeFailure.storage(added) }
    defer { SecItemDelete(query as CFDictionary) }
    var read = query
    read[kSecReturnData as String] = true
    read[kSecReturnAttributes as String] = true
    var result: CFTypeRef?
    let found = SecItemCopyMatching(read as CFDictionary, &result)
    guard found == errSecSuccess else { throw SmokeFailure.storage(found) }
    guard let attributes = result as? [String: Any], attributes[kSecValueData as String] as? Data == payload,
          attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
    else { throw SmokeFailure.protection }
    let removed = SecItemDelete(query as CFDictionary)
    guard removed == errSecSuccess, SecItemCopyMatching(read as CFDictionary, nil) == errSecItemNotFound else {
        throw SmokeFailure.storage(removed)
    }
}

do {
    try checkPrivateKeychain()
    print("PASS: private Data Protection Keychain add/read/delete; WhenUnlockedThisDeviceOnly; synthetic service only")
} catch SmokeFailure.storage(let status) {
    print("Keychain smoke failed with OSStatus \(status). No real credentials were queried.")
    exit(1)
} catch {
    print("Keychain smoke failed: incorrect protection. No real credentials were queried.")
    exit(1)
}
