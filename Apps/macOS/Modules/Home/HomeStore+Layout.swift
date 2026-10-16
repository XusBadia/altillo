import AltilloHome
import Foundation

/// A tile ready to draw: the user's tile (overrides) and the entity it controls. Identified by the entity, which is
/// unique on a page and stable across launches.
struct HomeResolvedTile: Identifiable, Hashable {
    let tile: HomeTile
    let entity: HomeEntity

    var id: HomeEntityID { entity.id }
    /// The user's name for it, or the entity's.
    var name: String { tile.name ?? entity.name }
    /// The user's SF Symbol, nil for the kind's default glyph.
    var symbol: String? { tile.symbol }
    var size: HomeTileSize { tile.size }
}

/// The layout API the notch (Package A) and Settings (Package B) build on (docs/casa-v2.md §1–2, §5). Every
/// change is saved at once (`AltilloSettings.homeLayout`) and observable through `settings`. A `page` of nil
/// means Favourites everywhere.
extension HomeStore {
    // MARK: Reading

    /// Every page and tile, hidden ones included (observable: it reads `settings.homeLayout`).
    var layout: HomeLayout { settings.homeLayout }

    /// Favourites first, then the user's own pages.
    var pages: [HomePage] { settings.homeLayout.pages }

    /// What a page shows, in order: tiles that aren't hidden, whose entity the server knows and may be a favourite.
    func tiles(onPage page: HomePage.ID? = nil) -> [HomeResolvedTile] {
        guard let page = settings.homeLayout.page(page) else { return [] }
        let entities = service.entities
        return page.visibleTiles.compactMap { tile in
            guard let entity = entities[tile.entity], Self.canFavourite(entity) else { return nil }
            return HomeResolvedTile(tile: tile, entity: entity)
        }
    }

    /// The tile (with overrides) the entity has on a page, shown or hidden; nil when it has none.
    func tile(for id: HomeEntityID, onPage page: HomePage.ID? = nil) -> HomeTile? {
        settings.homeLayout.tile(for: id, onPage: page)
    }

    /// Everything worth a tile in an area: favourites first (in their order), then lights, blinds, switches, fans,
    /// scenes and scripts, each by name. Never technical or dangerous entities.
    func entities(inArea areaID: String) -> [HomeEntity] {
        let favourites = settings.homeLayout.favouriteEntities
        let favouriteRank = Dictionary(favourites.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let candidates = service.entities.values.filter { entity in
            entity.areaID == areaID && Self.canFavourite(entity) && !entity.isTechnical
                && (favouriteRank[entity.id] != nil || Self.areaKinds.contains(entity.kind))
        }
        return candidates.sorted { a, b in
            switch (favouriteRank[a.id], favouriteRank[b.id]) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): break
            }
            let kindA = Self.areaKindRank(a.kind), kindB = Self.areaKindRank(b.kind)
            if kindA != kindB { return kindA < kindB }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// An area's entities as tiles, carrying Favourites' overrides (name, symbol, size) where there are some.
    func tiles(inArea areaID: String) -> [HomeResolvedTile] {
        let layout = settings.homeLayout
        return entities(inArea: areaID).map { entity in
            HomeResolvedTile(tile: layout.tile(for: entity.id) ?? HomeTile(entity: entity.id), entity: entity)
        }
    }

    private static let areaKinds: [HomeEntityKind] = [.light, .cover, .switchable, .fan, .scene, .script]

    private static func areaKindRank(_ kind: HomeEntityKind) -> Int {
        switch kind {
        case .light: 0
        case .cover: 1
        case .switchable: 2
        case .fan: 3
        case .scene, .script: 4
        default: 5
        }
    }

    // MARK: Favourites

    func isFavourite(_ id: HomeEntityID) -> Bool { settings.homeLayout.contains(id) }

    /// Adds a tile for the entity at the end of Favourites (or at `index`). Ignored if it's already there.
    func addFavourite(_ id: HomeEntityID, at index: Int? = nil) {
        guard settings.homeLayout.add(id, at: index) else { return }
        autoSuggestedCount = 0
        refreshWatch()
    }

    /// Removes the entity's Favourites tile, overrides and all.
    func removeFavourite(_ id: HomeEntityID) {
        guard settings.homeLayout.remove(id) else { return }
        autoSuggestedCount = 0
        refreshWatch()
    }

    // MARK: Editing tiles

    /// The tile's own name; nil, empty or the entity's own name go back to the entity's name.
    func rename(_ id: HomeEntityID, to name: String?, onPage page: HomePage.ID? = nil) {
        let own = service.entities[id]?.name
        settings.homeLayout.update(id, onPage: page) { tile in
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            tile.name = trimmed == own ? nil : trimmed
        }
    }

    /// The tile's SF Symbol; nil for the kind's default glyph.
    func setSymbol(_ id: HomeEntityID, _ symbol: String?, onPage page: HomePage.ID? = nil) {
        settings.homeLayout.update(id, onPage: page) { $0.symbol = symbol }
    }

    /// One column or two.
    func setSize(_ id: HomeEntityID, _ size: HomeTileSize, onPage page: HomePage.ID? = nil) {
        settings.homeLayout.update(id, onPage: page) { $0.size = size }
    }

    /// Hides the tile from the notch (it keeps its place and overrides) or shows it again.
    func setHidden(_ id: HomeEntityID, _ hidden: Bool, onPage page: HomePage.ID? = nil) {
        guard settings.homeLayout.update(id, onPage: page, { $0.isHidden = hidden }) else { return }
        refreshWatch()
    }

    /// Drag-onto reordering: `source` lands just before `target` (just after it when coming from above).
    func moveTile(from source: HomeEntityID, to target: HomeEntityID, onPage page: HomePage.ID? = nil) {
        settings.homeLayout.move(source, onto: target, onPage: page)
    }

    /// `List.onMove` reordering over the page's full tile list (`layout.page(_:)?.tiles`, hidden ones included).
    func moveTiles(fromOffsets source: IndexSet, toOffset destination: Int, onPage page: HomePage.ID? = nil) {
        settings.homeLayout.move(fromOffsets: source, toOffset: destination, onPage: page)
    }

    // MARK: Exploring an area

    /// The notch's area chip: `id` selects that area and watches its entities (at most `areaWatchLimit`); nil goes
    /// back to the pages and stops watching them. Call it with nil when the section closes too. Only a changed
    /// watch set reaches the service, so switching back and forth doesn't resubscribe for nothing.
    func watchArea(_ id: String?) {
        guard id != selectedArea else { return }
        selectedArea = id
        refreshWatch()
    }

    /// The explored area's entities to keep live, capped.
    func areaWatchSet() -> Set<HomeEntityID> {
        guard let selectedArea else { return [] }
        return Set(entities(inArea: selectedArea).prefix(Self.areaWatchLimit).map(\.id))
    }

    // MARK: Suggestions

    /// A first selection, at most `suggestionLimit`: lights first, one per area in turn (so a big living room
    /// doesn't take every slot), then blinds and switches, then scenes the same way. Only entities in an area,
    /// never technical or dangerous ones, never ones already in Favourites.
    func suggestedFavourites() -> [HomeEntityID] {
        let areaOrder = Dictionary(service.areas.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let existing = Set(settings.homeLayout.favouriteEntities)
        let candidates = service.entities.values.filter { entity in
            Self.canFavourite(entity) && !entity.isTechnical && !existing.contains(entity.id)
                && entity.areaID.flatMap { areaOrder[$0] } != nil
        }
        var picked: [HomeEntityID] = []
        for kinds in [[HomeEntityKind.light], [.cover, .switchable], [.scene]] {
            guard picked.count < Self.suggestionLimit else { break }
            let sorted = candidates.filter { kinds.contains($0.kind) }.sorted { a, b in
                let areaA = areaOrder[a.areaID ?? ""] ?? .max, areaB = areaOrder[b.areaID ?? ""] ?? .max
                if areaA != areaB { return areaA < areaB }
                let kindA = kinds.firstIndex(of: a.kind) ?? 0, kindB = kinds.firstIndex(of: b.kind) ?? 0
                if kindA != kindB { return kindA < kindB }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            var byArea: [[HomeEntity]] = []
            for entity in sorted {
                if let index = byArea.firstIndex(where: { $0.first?.areaID == entity.areaID }) {
                    byArea[index].append(entity)
                } else {
                    byArea.append([entity])
                }
            }
            var round = 0
            while picked.count < Self.suggestionLimit, byArea.contains(where: { $0.count > round }) {
                for group in byArea where group.count > round && picked.count < Self.suggestionLimit {
                    picked.append(group[round].id)
                }
                round += 1
            }
        }
        return picked
    }

    /// Adds the suggestions after the favourites the user already has. Returns how many were added.
    @discardableResult
    func applySuggestions() -> Int {
        let picks = suggestedFavourites()
        guard !picks.isEmpty else { return 0 }
        var layout = settings.homeLayout
        for id in picks { layout.add(id) }
        settings.homeLayout = layout
        refreshWatch()
        return picks.count
    }

    /// Whether to show the one-time "Altillo picked N to start · Change" hint (N = `autoSuggestedCount`).
    var didAutoSuggest: Bool { autoSuggestedCount > 0 }

    /// The hint was seen or "Change" was clicked.
    func dismissAutoSuggestHint() { autoSuggestedCount = 0 }

    /// Never an empty section with a working server: the first time a connected server's catalogue is loaded and
    /// Favourites is empty, the suggestions run on their own, once ever (`homeDidAutoSuggest`).
    func autoSuggestIfNeeded() {
        guard isModuleEnabled, isConnected, !settings.homeDidAutoSuggest, !service.entities.isEmpty else { return }
        settings.homeDidAutoSuggest = true
        guard settings.homeLayout.favourites.tiles.isEmpty else { return }
        autoSuggestedCount = applySuggestions()
    }

    // MARK: Grid

    /// How `count` tiles (or these sizes) fill `availableHeight`: columns, rows, tile height, scrolling and where
    /// each tile goes (`HomeGridMetrics`, docs/casa-v2.md §1).
    nonisolated static func layoutMetrics(count: Int, availableHeight: Double, spacing: Double = 0) -> HomeGridMetrics {
        HomeGridMetrics(count: count, availableHeight: availableHeight, spacing: spacing)
    }

    nonisolated static func layoutMetrics(sizes: [HomeTileSize], availableHeight: Double,
                                          spacing: Double = 0) -> HomeGridMetrics {
        HomeGridMetrics(sizes: sizes, availableHeight: availableHeight, spacing: spacing)
    }
}
