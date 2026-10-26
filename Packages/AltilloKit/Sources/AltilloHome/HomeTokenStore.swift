import Foundation
import Security

/// Where Home Assistant tokens live. The Keychain in the app, memory in tests. Tokens are never logged.
@MainActor
protocol HomeTokenStore: AnyObject {
    func token(for serverID: String) -> String?
    func save(_ token: String, for serverID: String) throws
    func delete(for serverID: String)
}

/// Generic passwords under service `me.badia.altillo.home`, one per server (account = serverID).
@MainActor
final class KeychainHomeTokenStore: HomeTokenStore {
    static let service = "me.badia.altillo.home"

    private func query(_ serverID: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: serverID]
    }

    func token(for serverID: String) -> String? {
        var query = query(serverID)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String, for serverID: String) throws {
        let data = Data(token.utf8)
        let update: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock]
        var status = SecItemUpdate(query(serverID) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(serverID)
            add[kSecValueData] = data
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            add[kSecAttrLabel] = "Altillo · Home Assistant"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw HomeServiceError(HomeStrings.keychain) }
    }

    func delete(for serverID: String) {
        SecItemDelete(query(serverID) as CFDictionary)
    }
}

/// Tests and previews.
@MainActor
final class InMemoryHomeTokenStore: HomeTokenStore {
    var tokens: [String: String]
    var failSaves = false
    init(_ tokens: [String: String] = [:]) { self.tokens = tokens }
    func token(for serverID: String) -> String? { tokens[serverID] }
    func save(_ token: String, for serverID: String) throws {
        if failSaves { throw HomeServiceError(HomeStrings.keychain) }
        tokens[serverID] = token
    }
    func delete(for serverID: String) { tokens[serverID] = nil }
}
