import AltilloHome
import Foundation

/// A Favourites tile as Settings › Home shows it: hidden tiles too (dimmed), and tiles whose entity Home Assistant no
/// longer has (so they can still be removed).
struct HomeSettingsTile: Identifiable, Hashable {
    let tile: HomeTile
    /// nil when the server doesn't know the entity (any more).
    let entity: HomeEntity?

    var id: HomeEntityID { tile.entity }
    var name: String { tile.name ?? entity?.name ?? tile.entity.localID }
    var isHidden: Bool { tile.isHidden }
    var size: HomeTileSize { tile.size }
}

/// One area of "Add from a room", or the entities outside any area ("No room", `id` empty).
struct HomeCatalogueGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let entities: [HomeEntity]
}

/// What Settings › Home needs from the store beyond the layout API (`HomeStore+Layout`).
extension HomeStore {
    /// Favourites' tiles in order, hidden ones included: the grid Settings edits.
    var settingsTiles: [HomeSettingsTile] {
        let entities = service.entities
        return settings.homeLayout.favourites.tiles.map { HomeSettingsTile(tile: $0, entity: entities[$0.entity]) }
    }

    /// Everything that can be a tile, area by area (HA's order), then "No room". Without a query, technical entities
    /// (helpers, diagnostics) stay out; a query matches the name or the entity id and includes them.
    func catalogue(matching query: String) -> [HomeCatalogueGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = service.entities.values.filter { entity in
            guard Self.canFavourite(entity) else { return false }
            if needle.isEmpty { return !entity.isTechnical }
            return entity.name.localizedStandardContains(needle) || entity.id.localID.localizedStandardContains(needle)
        }
        let byArea = Dictionary(grouping: candidates) { $0.areaID ?? "" }
        let sort: (HomeEntity, HomeEntity) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var groups = areas.compactMap { area -> HomeCatalogueGroup? in
            guard let entities = byArea[area.id], !entities.isEmpty else { return nil }
            return HomeCatalogueGroup(id: area.id, name: area.name, entities: entities.sorted(by: sort))
        }
        let known = Set(areas.map(\.id))
        let elsewhere = byArea.filter { !known.contains($0.key) }.flatMap(\.value)
        if !elsewhere.isEmpty {
            groups.append(HomeCatalogueGroup(id: "", name: String(localized: "No room"), entities: elsewhere.sorted(by: sort)))
        }
        return groups
    }

    /// Drops `dragged` where `target` is in the Settings grid (hidden tiles count: they keep their place).
    func dropTile(_ dragged: HomeEntityID, onto target: HomeEntityID) {
        guard dragged != target else { return }
        moveTile(from: dragged, to: target)
    }

    /// The icons offered for a tile, about sixteen per kind. The first is the kind's own look.
    static func curatedSymbols(for kind: HomeEntityKind) -> [String] {
        switch kind {
        case .light:
            ["lightbulb.fill", "lightbulb.led.fill", "lightbulb.2.fill", "lamp.desk.fill", "lamp.floor.fill",
             "lamp.table.fill", "lamp.ceiling.fill", "chandelier.fill", "light.recessed.fill", "light.strip.2.fill",
             "light.panel.fill", "light.cylindrical.ceiling.fill", "lightbulb.led.wide.fill", "sun.max.fill",
             "moon.fill", "star.fill"]
        case .switchable:
            ["powerplug.fill", "lightswitch.on", "poweroutlet.type.f.fill", "tv.fill", "desktopcomputer",
             "washer.fill", "dishwasher.fill", "refrigerator.fill", "oven.fill", "microwave.fill", "heater.vertical.fill",
             "air.purifier.fill", "humidifier.fill", "cup.and.saucer.fill", "speaker.wave.2.fill", "gamecontroller.fill"]
        case .cover:
            ["blinds.vertical.closed", "blinds.horizontal.closed", "roller.shade.closed", "roman.shade.closed",
             "curtains.closed", "window.shade.closed", "window.vertical.closed", "window.awning.closed",
             "window.casement.closed", "door.garage.closed", "door.sliding.left.hand.closed", "door.left.hand.closed"]
        case .fan:
            ["fan.fill", "fan.ceiling.fill", "fan.desk.fill", "fan.floor.fill", "air.conditioner.horizontal.fill",
             "air.purifier.fill", "dehumidifier.fill", "wind", "snowflake"]
        case .scene, .script:
            ["sparkles", "moon.stars.fill", "sun.horizon.fill", "sunrise.fill", "sunset.fill", "film.fill",
             "book.fill", "fork.knife", "bed.double.fill", "sofa.fill", "party.popper.fill", "music.note",
             "play.circle.fill", "house.fill", "figure.walk", "briefcase.fill"]
        case .sensor, .binarySensor:
            ["thermometer.medium", "humidity.fill", "bolt.fill", "gauge.with.dots.needle.33percent", "sensor.fill",
             "door.left.hand.closed", "window.vertical.closed", "figure.walk", "drop.fill", "leaf.fill", "aqi.medium",
             "flame.fill"]
        case .climate, .lock, .event, .camera, .other:
            ["house.fill", "star.fill", "sparkles", "bolt.fill"]
        }
    }
}

// MARK: - Connecting (Settings › Home › Home Assistant)

/// The pure pieces of the Connect section, tested in `HomeSettingsTests`.
enum HomeSettingsLogic {
    /// What a checked address turned out to be, as one inline line under the field.
    struct ProbeNotice: Equatable {
        enum Action: Equatable {
            case openLocalNetworkSettings
            /// Sign in pinning this certificate (the fingerprint is shown with the notice).
            case trust(fingerprint: String)
        }

        let symbol: String
        let message: String
        /// True when it's a Home Assistant one can sign in to.
        let isGood: Bool
        var action: Action?
    }

    static func notice(for probe: HomeServerProbe) -> ProbeNotice {
        switch probe {
        case let .homeAssistant(version, needsOnboarding):
            if needsOnboarding, let problem = probe.problem {
                return ProbeNotice(symbol: "hammer", message: problem, isGood: false)
            }
            let message = version.map { String(localized: "Home Assistant \($0) is there.") }
                ?? String(localized: "Home Assistant is there.")
            return ProbeNotice(symbol: "checkmark.circle.fill", message: message, isGood: true)
        case .notHomeAssistant:
            return ProbeNotice(symbol: "questionmark.circle", message: probe.problem ?? "", isGood: false)
        case .unreachable:
            return ProbeNotice(symbol: "wifi.exclamationmark", message: probe.problem ?? "", isGood: false)
        case .insecureRemote:
            return ProbeNotice(symbol: "lock.trianglebadge.exclamationmark", message: probe.problem ?? "", isGood: false)
        case .localNetworkDenied:
            return ProbeNotice(symbol: "network.slash", message: probe.problem ?? "", isGood: false,
                               action: .openLocalNetworkSettings)
        case let .needsTrust(fingerprint):
            return ProbeNotice(symbol: "lock.shield", message: probe.problem ?? "", isGood: false,
                               action: .trust(fingerprint: fingerprint))
        }
    }

    /// Found servers as Settings lists them: one row per instance (by its id, then by address, the first wins),
    /// the one already saved first, the rest in the order they were found.
    static func rows(_ servers: [HomeDiscoveredServer], current: URL?) -> [HomeDiscoveredServer] {
        var ids = Set<String>(), addresses = Set<String>()
        let unique = servers.filter { server in
            let address = server.address.lowercased()
            guard !ids.contains(server.id), !addresses.contains(address) else { return false }
            ids.insert(server.id)
            addresses.insert(address)
            return true
        }
        guard let current, let index = unique.firstIndex(where: { sameServer($0.url, current) }) else { return unique }
        var ordered = unique
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }

    /// The row's name: HA's `location_name`, or "Home Assistant".
    static func title(of server: HomeDiscoveredServer) -> String {
        let name = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Home Assistant" : name
    }

    /// How an address goes in the field: "homeassistant.local:8123" for plain local http, the full URL otherwise.
    static func fieldText(for url: URL) -> String {
        guard url.scheme?.lowercased() == "http", let host = url.host(), !host.isEmpty else { return url.absoluteString }
        let shown = host.contains(":") ? "[\(host)]" : host
        return url.port.map { "\(shown):\($0)" } ?? shown
    }

    /// Scheme, host and port match (paths and trailing slashes don't matter).
    static func sameServer(_ a: URL, _ b: URL) -> Bool {
        func key(_ url: URL) -> String {
            let scheme = url.scheme?.lowercased() ?? "http"
            let port = url.port ?? (scheme == "https" ? 443 : 80)
            return "\(scheme)://\(url.host()?.lowercased() ?? ""):\(port)"
        }
        return key(a) == key(b)
    }
}
