import AltilloHome
import Foundation

/// What the Home section has to say beside the resting notch (docs/casa.md, "Oreja contextual"): only when there's
/// something worth a glance, never the weather in the living room.
enum HomeSignal: Equatable, Sendable {
    /// A door, window or garage door open longer than `HomeEarLogic.openThreshold`, since `since`.
    case leftOpen(name: String, deviceClass: String?, since: Date)
    /// Nobody is home (`zone.home` is "0") and these many lights are still on.
    case lightsOnWhileAway(count: Int)

    var symbol: String {
        switch self {
        case let .leftOpen(_, deviceClass, _):
            switch deviceClass {
            case "garage_door": "door.garage.open"
            case "window": "window.vertical.open"
            default: "door.left.hand.open"
            }
        case .lightsOnWhileAway: "lightbulb.fill"
        }
    }
}

// MARK: - Logic (pure, testable)

enum HomeEarLogic {
    /// A door is worth mentioning once it has been open this long.
    static let openThreshold: TimeInterval = 10 * 60
    /// Binary sensors that open and close (HA `device_class`).
    static let openingClasses: Set<String> = ["door", "window", "garage_door"]
    /// Watched without being favourites: a garage left open matters even if it isn't a tile. Doors and windows
    /// only take part when the user made them favourites (until there's a setting for it).
    static let alwaysWatchedClasses: Set<String> = ["garage_door"]

    static func isOpening(_ entity: HomeEntity) -> Bool {
        entity.kind == .binarySensor && entity.deviceClass.map(openingClasses.contains) == true
    }

    /// Garage sensors the ear keeps an eye on, favourites or not.
    static func earSensors(in entities: [HomeEntityID: HomeEntity]) -> Set<HomeEntityID> {
        Set(entities.values.filter {
            $0.kind == .binarySensor && !$0.isTechnical && $0.deviceClass.map(alwaysWatchedClasses.contains) == true
        }.map(\.id))
    }

    /// `zone.home` counts the people at home; "0" means everybody left. Unknown or unavailable never counts as away.
    static func isAway(_ entities: [HomeEntityID: HomeEntity], zone: HomeEntityID?) -> Bool {
        guard let zone, let entity = entities[zone], entity.state.isAvailable else { return false }
        return entity.state.raw.trimmingCharacters(in: .whitespaces) == "0"
    }

    /// Lights the "away" count looks at: the real ones, not helpers or diagnostics.
    static func lights(in entities: [HomeEntityID: HomeEntity]) -> Set<HomeEntityID> {
        Set(entities.values.filter { $0.kind == .light && !$0.isTechnical }.map(\.id))
    }

    /// The one thing the ear says, if any: a door left open first (it's the one to act on), then lights on while away.
    static func signal(entities: [HomeEntityID: HomeEntity], watched: Set<HomeEntityID>, zone: HomeEntityID?,
                       now: Date) -> HomeSignal? {
        let longestOpen = openSensors(entities: entities, watched: watched)
            .filter { now.timeIntervalSince($0.since) >= openThreshold }
            .min { $0.since < $1.since }
        if let longestOpen {
            return .leftOpen(name: longestOpen.entity.name, deviceClass: longestOpen.entity.deviceClass,
                             since: longestOpen.since)
        }
        if isAway(entities, zone: zone) {
            let on = entities.values.filter {
                $0.kind == .light && !$0.isTechnical && $0.state.isAvailable && $0.state.isOn == true
            }.count
            if on > 0 { return .lightsOnWhileAway(count: on) }
        }
        return nil
    }

    /// When the ear's words next change on their own (a door crossing the threshold, then each minute it stays
    /// open), or nil when only a new state from the server can change them.
    static func nextChange(entities: [HomeEntityID: HomeEntity], watched: Set<HomeEntityID>, now: Date) -> Date? {
        openSensors(entities: entities, watched: watched).map { open -> Date in
            let elapsed = now.timeIntervalSince(open.since)
            if elapsed < openThreshold { return open.since.addingTimeInterval(openThreshold) }
            return open.since.addingTimeInterval((floor(elapsed / 60) + 1) * 60)
        }.min()
    }

    /// Whole minutes a door has been open ("12 min").
    static func minutes(since: Date, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(since) / 60))
    }

    /// The whole sentence: "Front door open · 12 min", "3 lights on".
    static func sentence(_ signal: HomeSignal, now: Date) -> String {
        switch signal {
        case let .leftOpen(name, _, since):
            String(localized: "\(name) open · \(minutes(since: since, now: now)) min")
        case let .lightsOnWhileAway(count):
            lightsOnText(count)
        }
    }

    static func lightsOnText(_ count: Int) -> String {
        count == 1 ? String(localized: "1 light on") : String(localized: "\(count) lights on")
    }

    private static func openSensors(entities: [HomeEntityID: HomeEntity],
                                    watched: Set<HomeEntityID>) -> [(entity: HomeEntity, since: Date)] {
        watched.compactMap { id -> (HomeEntity, Date)? in
            guard let entity = entities[id], isOpening(entity), entity.state.isAvailable, entity.state.isOn == true,
                  let since = entity.state.lastChanged else { return nil }
            return (entity, since)
        }
    }
}
