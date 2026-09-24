import Foundation
import SQLite3

// Cursor's sign-in, read-only. Altillo never refreshes or rewrites it: Cursor rotates its refresh token, and writing
// a refreshed access token back (or spending the refresh token) could sign Cursor out. The refresh token is never
// even read.
//
// Sources and source-selection rule adapted from openusage (MIT),
// Sources/OpenUsage/Providers/Cursor/CursorAuthStore.swift @87c3d2db465a5eb6c6dd2c2453c55cd82141a76e.

/// The parts of Cursor's sign-in Altillo needs.
public struct CursorCredentials: Sendable, Hashable {
    public enum Source: String, Sendable, Hashable { case stateDatabase, keychain }

    public var accessToken: String
    /// `stripeMembershipType` from Cursor's state ("pro", "free", "ultra"…), when known.
    public var membershipType: String?
    public var source: Source

    public init(accessToken: String, membershipType: String?, source: Source) {
        self.accessToken = accessToken
        self.membershipType = membershipType
        self.source = source
    }

    /// The JWT's `exp`.
    public var expiresAt: Date? {
        Group1Support.jwtPayload(accessToken).flatMap { UsageParsing.number($0["exp"]) }
            .map { Date(timeIntervalSince1970: $0) }
    }

    /// The JWT's `sub` ("auth0|user_…").
    public var subject: String? { Group1Support.jwtPayload(accessToken).flatMap { UsageParsing.string($0["sub"]) } }

    /// Expired, or expiring within `margin` (Altillo won't refresh it).
    public func isExpired(now: Date, margin: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now.addingTimeInterval(margin)
    }

    /// Cookie value cursor.com's REST endpoints accept: `<userID>%3A%3A<accessToken>`.
    public var sessionCookie: String? {
        guard let subject else { return nil }
        let parts = subject.split(separator: "|", omittingEmptySubsequences: false)
        let userID = String(parts.count > 1 ? parts[1] : parts[0])
        guard !userID.isEmpty else { return nil }
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(accessToken)"
    }
}

public enum CursorCredentialLookup: Sendable, Hashable {
    case found(CursorCredentials)
    case notFound
    case accessDenied
}

public protocol CursorCredentialReading: Sendable {
    /// Cheap: does Cursor's state database or keychain item exist (no secret read)?
    func exists() async -> Bool
    func read(now: Date) async -> CursorCredentialLookup
}

/// Reads Cursor's `state.vscdb` first (no keychain prompt possible), then the keychain items the Cursor CLI
/// (`cursor-agent`) writes. The keychain is only consulted when the database has no usable token, or when the
/// database belongs to a free account (the CLI may be signed in to a different, paid account).
public struct CursorCredentialStore: CursorCredentialReading {
    static let accessTokenKey = "cursorAuth/accessToken"
    static let membershipKey = "cursorAuth/stripeMembershipType"
    static let keychainAccessService = "cursor-access-token"

    public let databaseURL: URL
    private let database: any CursorStateReading
    private let keychain: any KeychainSecretReading

    public init(databaseURL: URL = CursorCredentialStore.defaultDatabaseURL(),
                database: (any CursorStateReading)? = nil,
                keychain: any KeychainSecretReading = SecurityCLIKeychain()) {
        self.databaseURL = databaseURL
        self.database = database ?? CursorStateDatabase(url: databaseURL)
        self.keychain = keychain
    }

    public static func defaultDatabaseURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    public func exists() async -> Bool {
        if FileManager.default.fileExists(atPath: databaseURL.path) { return true }
        return await keychain.contains(service: Self.keychainAccessService, account: nil)
    }

    public func read(now: Date) async -> CursorCredentialLookup {
        let values = database.values(for: [Self.accessTokenKey, Self.membershipKey])
        let membership = values[Self.membershipKey].map { $0.lowercased() }
        let fromDatabase = values[Self.accessTokenKey].map {
            CursorCredentials(accessToken: $0, membershipType: membership, source: .stateDatabase)
        }

        if let fromDatabase, !fromDatabase.isExpired(now: now), membership != "free" {
            return .found(fromDatabase)
        }

        var fromKeychain: CursorCredentials?
        var denied = false
        switch await keychain.secret(service: Self.keychainAccessService, account: nil) {
        case .found(let token):
            fromKeychain = CursorCredentials(accessToken: token, membershipType: nil, source: .keychain)
        case .denied:
            denied = true
        case .notFound:
            break
        }

        if let fromDatabase, !fromDatabase.isExpired(now: now) {
            // A free desktop sign-in next to a CLI sign-in for someone else: the CLI's account is the paid one.
            if let fromKeychain, !fromKeychain.isExpired(now: now), let a = fromDatabase.subject,
               let b = fromKeychain.subject, a != b {
                return .found(fromKeychain)
            }
            return .found(fromDatabase)
        }
        if let fromKeychain, !fromKeychain.isExpired(now: now) { return .found(fromKeychain) }
        if let any = fromDatabase ?? fromKeychain { return .found(any) } // expired: reported as such
        return denied ? .accessDenied : .notFound
    }
}

// MARK: - state.vscdb

/// Reads values from a VS Code–style `ItemTable`. Tests point it at a temporary database.
public protocol CursorStateReading: Sendable {
    /// The non-empty values present for `keys` (missing database or keys → absent).
    func values(for keys: [String]) -> [String: String]
}

/// Opens Cursor's `state.vscdb` strictly read-only with the SQLite C API.
///
/// First as `mode=ro` (a read-only connection sees Cursor's latest writes, including ones still in its WAL, but
/// never writes, checkpoints or deletes anything), then, if that can't open (e.g. no `-shm` file to map), as
/// `immutable=1`, which ignores the WAL and takes no locks at all. Either way Cursor's files are left untouched.
public struct CursorStateDatabase: CursorStateReading {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func values(for keys: [String]) -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let base = url.absoluteString // file:///…/Application%20Support/… (SQLite decodes %HH)
        for uri in ["\(base)?mode=ro", "\(base)?immutable=1"] {
            if let values = Self.query(uri: uri, keys: keys) { return values }
        }
        return [:]
    }

    /// Nil when the database couldn't be opened or queried with this URI.
    static func query(uri: String, keys: [String]) -> [String: String]? {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1500)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ?1 LIMIT 1", -1, &statement, nil)
            == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var values: [String: String] = [:]
        for key in keys {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, key, -1, transient)
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { continue }
            guard step == SQLITE_ROW else { return nil }
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let text = String(decoding: UnsafeRawBufferPointer(start: bytes, count: count), as: UTF8.self)
            if let value = unquoted(text) { values[key] = value }
        }
        return values
    }

    /// Trims, and unwraps a JSON string literal (some VS Code keys are stored JSON-encoded).
    static func unquoted(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\""),
           let decoded = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
           as? String {
            let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return text.isEmpty ? nil : text
    }
}
