import Foundation
import Testing
@testable import AltilloHome

@Suite struct HomeLayoutTests {
    static func id(_ local: String) -> HomeEntityID { HomeEntityID(provider: "ha", serverID: "srv", localID: local) }
    let a = id("light.a"), b = id("light.b"), c = id("light.c"), d = id("cover.d")

    // MARK: Invariants

    @Test func anEmptyLayoutHasOnlyFavourites() {
        let layout = HomeLayout()
        #expect(layout.pages.count == 1)
        #expect(layout.favourites.isFavourites)
        #expect(layout.favourites.tiles.isEmpty)
    }

    @Test func favouritesAlwaysComeFirstAndOnlyOnce() {
        let night = HomePage(kind: .custom(name: "Night"), tiles: [HomeTile(entity: a)])
        let fav1 = HomePage(kind: .favourites, tiles: [HomeTile(entity: b)])
        let fav2 = HomePage(kind: .favourites, tiles: [HomeTile(entity: c), HomeTile(entity: b)])
        let layout = HomeLayout(pages: [night, fav1, fav2])
        #expect(layout.pages.map(\.isFavourites) == [true, false])
        #expect(layout.favouriteEntities == [b, c], "merged, one tile per entity")
        #expect(layout.customPages.first?.customName == "Night")

        let none = HomeLayout(pages: [night])
        #expect(none.favourites.isFavourites)
        #expect(none.pages.count == 2)
    }

    @Test func duplicatesAndClashingIdsAreRepaired() {
        let tile = HomeTile(entity: a)
        var same = HomeTile(entity: b)
        same.id = tile.id
        let page = HomePage(kind: .custom(name: "X"), tiles: [tile, HomeTile(entity: a), same])
        let layout = HomeLayout(pages: [page, page])
        #expect(layout.pages.count == 3)
        #expect(Set(layout.pages.map(\.id)).count == 3)
        #expect(layout.pages[1].tiles.map(\.entity) == [a, b])
        #expect(Set(layout.pages[1].tiles.map(\.id)).count == 2)
    }

    // MARK: Codable

    @Test func roundTripsThroughJSON() throws {
        var layout = HomeLayout(favourites: [a, b])
        layout.update(a) { $0.name = "Lamp"; $0.symbol = "lamp.desk.fill"; $0.size = .wide; $0.isHidden = true }
        let page = layout.addPage(named: "Night")
        layout.add(c, toPage: page)
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(HomeLayout.self, from: data)
        #expect(decoded == layout)
        #expect(decoded.tile(for: a)?.name == "Lamp")
        #expect(decoded.tile(for: a)?.size == .wide)
        #expect(decoded.contains(c, onPage: page))
    }

    @Test func decodingIsTolerant() throws {
        let json = """
        {"pages":[
          {"kind":{"custom":{"name":"Office"}},"tiles":[{"entity":"ha:srv:light.c"}]},
          {"kind":{"favourites":{}},"tiles":[
            {"entity":"ha:srv:light.a","size":"huge"},
            {"entity":"not-an-id"},
            {"entity":"ha:srv:light.b","name":"Desk","isHidden":true}
          ]},
          {"kind":{"somethingNew":{}},"tiles":[]}
        ]}
        """
        let layout = try JSONDecoder().decode(HomeLayout.self, from: Data(json.utf8))
        #expect(layout.favouriteEntities == [a, b])
        #expect(layout.favourites.tiles[0].size == .small, "unknown size reads as small")
        #expect(layout.favourites.tiles[1].isHidden)
        #expect(layout.favourites.visibleTiles.map(\.entity) == [a])
        #expect(layout.customPages.map(\.customName) == ["Office"])

        let empty = try JSONDecoder().decode(HomeLayout.self, from: Data("{}".utf8))
        #expect(empty == HomeLayout(pages: empty.pages))
        #expect(empty.pages.count == 1)
    }

    // MARK: Mutations

    @Test func addRemoveAndContains() {
        var layout = HomeLayout()
        let added = layout.add(a), again = layout.add(a), front = layout.add(b, at: 0)
        #expect(added)
        #expect(!again, "once per page")
        #expect(front)
        #expect(layout.favouriteEntities == [b, a])
        #expect(layout.contains(a))
        let removed = layout.remove(a), removedAgain = layout.remove(a)
        #expect(removed)
        #expect(!removedAgain)
        #expect(!layout.contains(a))
        let nowhere = layout.add(c, toPage: UUID())
        #expect(!nowhere, "no such page")
    }

    @Test func moveOntoAndOffsets() {
        var layout = HomeLayout(favourites: [a, b, c, d])
        layout.move(d, onto: a)
        #expect(layout.favouriteEntities == [d, a, b, c])
        layout.move(d, onto: c)
        #expect(layout.favouriteEntities == [a, b, c, d], "from above lands after")
        layout.move(fromOffsets: [0], toOffset: 3)
        #expect(layout.favouriteEntities == [b, c, a, d])
        layout.move(fromOffsets: [3], toOffset: 0)
        #expect(layout.favouriteEntities == [d, b, c, a])
        layout.move(fromOffsets: [9], toOffset: 0)
        #expect(layout.favouriteEntities == [d, b, c, a], "out of range does nothing")
    }

    @Test func updateKeepsIdentityAndCleansNames() {
        var layout = HomeLayout(favourites: [a])
        let id = layout.favourites.tiles[0].id
        layout.update(a) { $0.name = "  Lamp  "; $0.id = UUID(); $0.entity = b }
        #expect(layout.favourites.tiles[0].id == id)
        #expect(layout.favourites.tiles[0].entity == a)
        #expect(layout.tile(for: a)?.name == "Lamp")
        layout.update(a) { $0.name = "   "; $0.symbol = "" }
        #expect(layout.tile(for: a)?.name == nil)
        #expect(layout.tile(for: a)?.symbol == nil)
        let missing = layout.update(c) { $0.isHidden = true }
        #expect(!missing)
    }

    @Test func setFavouritesKeepsOverrides() {
        var layout = HomeLayout(favourites: [a, b])
        layout.update(b) { $0.name = "Desk"; $0.size = .wide }
        let id = layout.tile(for: b)!.id
        layout.setFavourites([c, b, c])
        #expect(layout.favouriteEntities == [c, b])
        #expect(layout.tile(for: b)?.id == id)
        #expect(layout.tile(for: b)?.name == "Desk")
        #expect(layout.tile(for: b)?.size == .wide)
    }

    @Test func pagesBeyondFavourites() {
        var layout = HomeLayout()
        let night = layout.addPage(named: "Night")
        layout.renamePage(night, to: "Late")
        #expect(layout.page(night)?.customName == "Late")
        layout.removePage(layout.favourites.id)
        #expect(layout.pages.count == 2, "favourites can't go")
        layout.removePage(night)
        #expect(layout.pages.count == 1)
    }

    // MARK: Grid

    @Test func gridFollowsTheSpec() {
        // 7 favourites: 4 × 2 at ≈ 84 pt.
        let seven = HomeGridMetrics(count: 7, availableHeight: 168)
        #expect(seven.columns == 4)
        #expect(seven.rows == 2)
        #expect(seven.tileHeight == 84)
        #expect(!seven.scrolls)
        // 2 favourites: two columns filling the width, one row at the tallest.
        let two = HomeGridMetrics(count: 2, availableHeight: 168)
        #expect(two.columns == 2)
        #expect(two.rows == 1)
        #expect(two.tileHeight == 88)
        // 12: three rows, clamped to 64 and scrolling.
        let twelve = HomeGridMetrics(count: 12, availableHeight: 168)
        #expect(twelve.rows == 3)
        #expect(twelve.tileHeight == 64)
        #expect(twelve.scrolls)
        // Nothing.
        let none = HomeGridMetrics(count: 0, availableHeight: 168)
        #expect(none.columns == 0)
        #expect(none.rows == 0)
    }

    @Test func wideTilesTakeTwoColumnsAndWrap() {
        // n = 4 → 4 columns. small small small wide: the wide one doesn't fit after three smalls.
        let grid = HomeGridMetrics(sizes: [.small, .small, .small, .wide], availableHeight: 168, spacing: 8)
        #expect(grid.columns == 4)
        #expect(grid.rows == 2)
        #expect(grid.placements.map(\.row) == [0, 0, 0, 1])
        #expect(grid.placements[3].span == 2)
        #expect(grid.tileHeight == 80)
        // A single wide tile in a one-column grid spans one.
        let one = HomeGridMetrics(sizes: [.wide], availableHeight: 100)
        #expect(one.columns == 1)
        #expect(one.placements == [.init(row: 0, column: 0, span: 1)])
        #expect(one.tileHeight == 88)
    }
}
