import Foundation

// How the user arranged their home (docs/casa-v2.md §2): pages of tiles, each tile pointing at one entity with the
// user's own name, symbol, size and visibility. Pure values, saved as JSON by the app. The first page is always
// Favourites; custom pages ("Night", "Office") come after it. Areas are not pages: they stay HA's own areas.

/// How much of a row a tile takes.
public enum HomeTileSize: String, Codable, Sendable, CaseIterable {
    /// One column.
    case small
    /// Two columns: a light shows its dimmer track, a blind its big glyph.
    case wide

    /// Grid columns this size takes (before clamping to the grid's width).
    public var units: Int { self == .wide ? 2 : 1 }

    /// Unknown sizes from a newer build read as `.small`.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HomeTileSize(rawValue: raw) ?? .small
    }
}

/// One entity on a page, with the user's overrides. `nil` name/symbol mean "the entity's own".
public struct HomeTile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var entity: HomeEntityID
    public var name: String?
    /// An SF Symbol name chosen by the user, nil for the kind's default glyph.
    public var symbol: String?
    public var size: HomeTileSize
    /// Hidden tiles stay in the layout (keeping their overrides) but aren't shown in the notch.
    public var isHidden: Bool

    public init(id: UUID = UUID(), entity: HomeEntityID, name: String? = nil, symbol: String? = nil,
                size: HomeTileSize = .small, isHidden: Bool = false) {
        self.id = id; self.entity = entity; self.name = name; self.symbol = symbol; self.size = size
        self.isHidden = isHidden
    }

    /// Whether the user changed anything beyond picking the entity.
    public var hasOverrides: Bool { name != nil || symbol != nil || size != .small || isHidden }

    private enum CodingKeys: String, CodingKey { case id, entity, name, symbol, size, isHidden }

    /// Tolerant: only `entity` is required, so older or newer layouts still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        entity = try c.decode(HomeEntityID.self, forKey: .entity)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        size = try c.decodeIfPresent(HomeTileSize.self, forKey: .size) ?? .small
        isHidden = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }
}

/// A page of tiles: Favourites (always first, exactly one) or one the user named.
public struct HomePage: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        case favourites
        case custom(name: String)
    }

    public var id: UUID
    public var kind: Kind
    public var tiles: [HomeTile]

    public init(id: UUID = UUID(), kind: Kind, tiles: [HomeTile] = []) {
        self.id = id; self.kind = kind; self.tiles = tiles
    }

    public var isFavourites: Bool { kind == .favourites }

    /// The custom page's name; nil for Favourites (the app localises that one).
    public var customName: String? {
        if case let .custom(name) = kind { name } else { nil }
    }

    public func contains(_ entity: HomeEntityID) -> Bool { tiles.contains { $0.entity == entity } }
    public func index(of entity: HomeEntityID) -> Int? { tiles.firstIndex { $0.entity == entity } }
    public func tile(for entity: HomeEntityID) -> HomeTile? { tiles.first { $0.entity == entity } }
    /// The tiles the notch shows, in order.
    public var visibleTiles: [HomeTile] { tiles.filter { !$0.isHidden } }

    private enum CodingKeys: String, CodingKey { case id, kind, tiles }

    /// Tiles that can't be read (a bad entity id) are dropped instead of losing the whole page.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(Kind.self, forKey: .kind)
        tiles = (try c.decodeIfPresent([Lossy<HomeTile>].self, forKey: .tiles) ?? []).compactMap(\.value)
    }

    /// One tile per entity (the first wins) and unique tile ids.
    mutating func normalise() {
        var entities = Set<HomeEntityID>(), ids = Set<UUID>()
        tiles = tiles.compactMap { tile in
            guard entities.insert(tile.entity).inserted else { return nil }
            var tile = tile
            if !ids.insert(tile.id).inserted { tile.id = UUID() }
            ids.insert(tile.id)
            return tile
        }
    }
}

/// Every page the user has. Invariants (kept by every initialiser, decoding and mutation): `pages[0]` is the one
/// Favourites page; page ids are unique; an entity appears at most once per page.
public struct HomeLayout: Codable, Hashable, Sendable {
    public private(set) var pages: [HomePage]

    /// An empty Favourites page and nothing else.
    public init() { pages = [HomePage(kind: .favourites)] }

    public init(pages: [HomePage]) {
        self.pages = pages
        normalise()
    }

    /// Favourites holding these entities in this order, no overrides (the H1 migration).
    public init(favourites: [HomeEntityID]) {
        self.init(pages: [HomePage(kind: .favourites, tiles: favourites.map { HomeTile(entity: $0) })])
    }

    private enum CodingKeys: String, CodingKey { case pages }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pages = (try c.decodeIfPresent([Lossy<HomePage>].self, forKey: .pages) ?? []).compactMap(\.value)
        normalise()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pages, forKey: .pages)
    }

    // MARK: Reading

    /// Always present.
    public var favourites: HomePage { pages[0] }
    /// The user's own pages, after Favourites.
    public var customPages: [HomePage] { Array(pages.dropFirst()) }
    /// Favourites' entities in order, hidden ones included.
    public var favouriteEntities: [HomeEntityID] { favourites.tiles.map(\.entity) }

    /// Whether the entity has a tile on that page (Favourites when `page` is nil).
    public func contains(_ entity: HomeEntityID, onPage page: HomePage.ID? = nil) -> Bool {
        self.page(page)?.contains(entity) ?? false
    }

    /// A page by id; Favourites for nil. nil when there's no such page.
    public func page(_ id: HomePage.ID?) -> HomePage? {
        guard let id else { return pages[0] }
        return pages.first { $0.id == id }
    }

    public func tile(for entity: HomeEntityID, onPage page: HomePage.ID? = nil) -> HomeTile? {
        self.page(page)?.tile(for: entity)
    }

    /// Every entity on any page, shown or hidden.
    public var allEntities: Set<HomeEntityID> { Set(pages.flatMap { $0.tiles.map(\.entity) }) }

    // MARK: Tiles

    /// Adds a tile for the entity (at the end, or at `index`). False when it was already there or the page is gone.
    @discardableResult
    public mutating func add(_ entity: HomeEntityID, toPage page: HomePage.ID? = nil, at index: Int? = nil) -> Bool {
        guard let p = pageIndex(page), !pages[p].contains(entity) else { return false }
        let tile = HomeTile(entity: entity)
        let at = min(max(index ?? pages[p].tiles.count, 0), pages[p].tiles.count)
        pages[p].tiles.insert(tile, at: at)
        return true
    }

    /// Removes the entity's tile (and its overrides). False when it wasn't there.
    @discardableResult
    public mutating func remove(_ entity: HomeEntityID, fromPage page: HomePage.ID? = nil) -> Bool {
        guard let p = pageIndex(page), let t = pages[p].index(of: entity) else { return false }
        pages[p].tiles.remove(at: t)
        return true
    }

    /// Moves `entity`'s tile to where `target` is: just before it, or just after it when coming from above
    /// (the drag-onto behaviour of a grid). False when either isn't on the page.
    @discardableResult
    public mutating func move(_ entity: HomeEntityID, onto target: HomeEntityID, onPage page: HomePage.ID? = nil) -> Bool {
        guard entity != target, let p = pageIndex(page), let source = pages[p].index(of: entity),
              let destination = pages[p].index(of: target) else { return false }
        let tile = pages[p].tiles.remove(at: source)
        pages[p].tiles.insert(tile, at: destination)
        return true
    }

    /// `List.onMove` semantics, on the page's full tile list (hidden tiles included).
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, onPage page: HomePage.ID? = nil) {
        guard let p = pageIndex(page) else { return }
        var tiles = pages[p].tiles
        let valid = IndexSet(source.filter { tiles.indices.contains($0) })
        guard !valid.isEmpty else { return }
        let moving = valid.map { tiles[$0] }
        let destination = min(max(destination, 0), tiles.count)
        let before = valid.filter { $0 < destination }.count
        for index in valid.reversed() { tiles.remove(at: index) }
        tiles.insert(contentsOf: moving, at: destination - before)
        pages[p].tiles = tiles
    }

    /// Changes the entity's tile in place (name, symbol, size, hidden). The tile keeps its id and entity.
    /// False when it isn't on the page.
    @discardableResult
    public mutating func update(_ entity: HomeEntityID, onPage page: HomePage.ID? = nil,
                                _ change: (inout HomeTile) -> Void) -> Bool {
        guard let p = pageIndex(page), let t = pages[p].index(of: entity) else { return false }
        var tile = pages[p].tiles[t]
        change(&tile)
        tile.id = pages[p].tiles[t].id
        tile.entity = entity
        if let name = tile.name?.trimmingCharacters(in: .whitespacesAndNewlines) {
            tile.name = name.isEmpty ? nil : name
        }
        if tile.symbol?.isEmpty == true { tile.symbol = nil }
        pages[p].tiles[t] = tile
        return true
    }

    /// Favourites become exactly these entities in this order; tiles already there keep their overrides and id.
    public mutating func setFavourites(_ entities: [HomeEntityID]) {
        let existing = Dictionary(pages[0].tiles.map { ($0.entity, $0) }, uniquingKeysWith: { first, _ in first })
        pages[0].tiles = entities.map { existing[$0] ?? HomeTile(entity: $0) }
        pages[0].normalise()
    }

    // MARK: Pages (P1)

    /// Adds a custom page after the others and returns its id.
    @discardableResult
    public mutating func addPage(named name: String) -> HomePage.ID {
        let page = HomePage(kind: .custom(name: name))
        pages.append(page)
        return page.id
    }

    /// Removes a custom page. Favourites can't be removed.
    public mutating func removePage(_ id: HomePage.ID) {
        guard let p = pages.firstIndex(where: { $0.id == id }), p > 0 else { return }
        pages.remove(at: p)
    }

    public mutating func renamePage(_ id: HomePage.ID, to name: String) {
        guard let p = pages.firstIndex(where: { $0.id == id }), p > 0 else { return }
        pages[p].kind = .custom(name: name)
    }

    // MARK: Invariants

    private func pageIndex(_ id: HomePage.ID?) -> Int? {
        guard let id else { return 0 }
        return pages.firstIndex { $0.id == id }
    }

    /// Favourites first and only once (several are merged into the first), unique page ids, one tile per entity.
    private mutating func normalise() {
        var favourites: HomePage?
        var custom: [HomePage] = []
        var ids = Set<UUID>()
        for var page in pages {
            if page.isFavourites {
                if favourites == nil { favourites = page } else { favourites?.tiles += page.tiles }
                continue
            }
            if !ids.insert(page.id).inserted { page.id = UUID() }
            custom.append(page)
        }
        var first = favourites ?? HomePage(kind: .favourites)
        if ids.contains(first.id) { first.id = UUID() }
        pages = [first] + custom
        for index in pages.indices { pages[index].normalise() }
    }
}

/// Decodes an element or nothing, so one bad element doesn't fail its array.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

// MARK: - Grid

/// How a page's tiles fill the open notch's fixed height (docs/casa-v2.md §1): `columns = n ≤ 3 ? n : 4`, a wide tile
/// takes two columns (one when the grid has a single column), rows are packed in order (a wide tile that doesn't fit
/// at the end of a row starts the next one), `tileHeight = clamp((height − gaps) / rows, 64, 88)`, and more than two
/// rows scroll.
public struct HomeGridMetrics: Hashable, Sendable {
    /// Where one tile goes: zero-based row and column, and how many columns it spans.
    public struct Placement: Hashable, Sendable {
        public let row: Int
        public let column: Int
        public let span: Int
    }

    public static let minTileHeight = 64.0
    public static let maxTileHeight = 88.0
    public static let maxVisibleRows = 2

    public let columns: Int
    public let rows: Int
    public let tileHeight: Double
    /// More rows than fit: the grid scrolls vertically.
    public let scrolls: Bool
    /// One per tile, in the order given.
    public let placements: [Placement]

    /// `sizes` in display order; `spacing` is the gap between rows (0 = the spec's plain formula).
    public init(sizes: [HomeTileSize], availableHeight: Double, spacing: Double = 0) {
        let count = sizes.count
        let columns = count <= 3 ? count : 4
        var placements: [Placement] = []
        var row = 0, column = 0
        for size in sizes {
            let span = min(size.units, max(columns, 1))
            if column + span > columns { row += 1; column = 0 }
            placements.append(Placement(row: row, column: column, span: span))
            column += span
        }
        let rows = count == 0 ? 0 : row + 1
        let gaps = spacing * Double(max(rows - 1, 0))
        let raw = rows == 0 ? Self.maxTileHeight : (availableHeight - gaps) / Double(rows)
        self.columns = columns
        self.rows = rows
        self.tileHeight = min(max(raw, Self.minTileHeight), Self.maxTileHeight)
        self.scrolls = rows > Self.maxVisibleRows
        self.placements = placements
    }

    /// `count` small tiles.
    public init(count: Int, availableHeight: Double, spacing: Double = 0) {
        self.init(sizes: Array(repeating: .small, count: max(count, 0)), availableHeight: availableHeight, spacing: spacing)
    }
}
