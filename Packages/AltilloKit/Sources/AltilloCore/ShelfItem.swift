import Foundation

/// Something parked in the shelf.
public struct ShelfItem: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A file on disk. `isOwnedCopy` is true when Altillo copied it into its inbox
        /// (file promises, temporary locations, raw data); false when it references the user's original.
        case file(URL, isOwnedCopy: Bool)
        case text(String)
        case link(URL)
    }

    public let id: UUID
    public var kind: Kind
    public var displayName: String
    public var addedAt: Date

    public init(id: UUID = UUID(), kind: Kind, displayName: String, addedAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.addedAt = addedAt
    }

    public var fileURL: URL? {
        if case let .file(url, _) = kind { url } else { nil }
    }
}
