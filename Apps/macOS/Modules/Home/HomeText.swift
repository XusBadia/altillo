import AltilloHome
import Foundation

/// How a Home entity reads and looks, shared by the notch's tiles and Settings: its symbol and its state in a few
/// words ("On · 70 %", "Open 60 %", "21.5 °C", "Unavailable").
enum HomeText {
    static func symbol(for entity: HomeEntity, state: HomeEntityState) -> String {
        let on = state.isOn == true
        switch entity.kind {
        case .light:
            return on ? "lightbulb.fill" : "lightbulb"
        case .switchable:
            if entity.deviceClass == "outlet" { return on ? "powerplug.fill" : "powerplug" }
            return on ? "lightswitch.on" : "lightswitch.off"
        case .fan:
            return on ? "fan.fill" : "fan"
        case .cover:
            let open = HomeStore.coverIsOpen(state)
            switch entity.deviceClass {
            case "garage", "gate": return open ? "door.garage.open" : "door.garage.closed"
            case "window": return open ? "window.vertical.open" : "window.vertical.closed"
            default: return open ? "blinds.vertical.open" : "blinds.vertical.closed"
            }
        case .scene:
            return "sparkles"
        case .script:
            return "play.circle"
        case .sensor:
            switch entity.deviceClass {
            case "temperature": return "thermometer.medium"
            case "humidity", "moisture": return "humidity"
            case "power", "energy", "current", "voltage": return "bolt.fill"
            default: return "gauge.with.dots.needle.33percent"
            }
        case .binarySensor:
            switch entity.deviceClass {
            case "garage_door": return on ? "door.garage.open" : "door.garage.closed"
            case "window": return on ? "window.vertical.open" : "window.vertical.closed"
            case "door", "opening": return on ? "door.left.hand.open" : "door.left.hand.closed"
            case "motion", "occupancy", "presence": return "figure.walk"
            default: return on ? "sensor.fill" : "sensor"
            }
        case .event:
            return "bell"
        case .camera:
            return "web.camera"
        case .lock:
            return "lock.shield"
        case .climate:
            return "thermometer.medium"
        case .other:
            return "circle.dashed"
        }
    }

    /// The tile's second line.
    static func stateLine(for entity: HomeEntity, state: HomeEntityState) -> String {
        guard state.isAvailable else { return String(localized: "Unavailable") }
        switch entity.kind {
        case .light:
            guard state.isOn == true else { return String(localized: "home.state.off", defaultValue: "Off") }
            if let brightness = state.brightness { return String(localized: "home.state.onPercent", defaultValue: "On · \(percent(brightness))") }
            return String(localized: "home.state.on", defaultValue: "On")
        case .switchable, .fan:
            return state.isOn == true ? String(localized: "home.state.on", defaultValue: "On") : String(localized: "home.state.off", defaultValue: "Off")
        case .cover:
            switch state.raw {
            case "opening": return String(localized: "home.state.opening", defaultValue: "Opening…")
            case "closing": return String(localized: "home.state.closing", defaultValue: "Closing…")
            default: break
            }
            guard let position = state.position else {
                return HomeStore.coverIsOpen(state) ? String(localized: "home.state.open", defaultValue: "Open") : String(localized: "home.state.closed", defaultValue: "Closed")
            }
            if position <= 0.005 { return String(localized: "home.state.closed", defaultValue: "Closed") }
            if position >= 0.995 { return String(localized: "home.state.open", defaultValue: "Open") }
            return String(localized: "home.state.openPercent", defaultValue: "Open \(percent(position))")
        case .scene:
            return String(localized: "Scene")
        case .script:
            return state.isOn == true ? String(localized: "Running") : String(localized: "Script")
        case .sensor:
            return state.displayValue ?? state.raw
        case .binarySensor:
            let on = state.isOn == true
            switch entity.deviceClass {
            case "door", "window", "garage_door", "opening":
                return on ? String(localized: "home.state.open", defaultValue: "Open") : String(localized: "home.state.closed", defaultValue: "Closed")
            case "motion", "occupancy", "presence":
                return on ? String(localized: "Detected") : String(localized: "Clear")
            default:
                return on ? String(localized: "home.state.on", defaultValue: "On") : String(localized: "home.state.off", defaultValue: "Off")
            }
        case .event, .camera, .lock, .climate, .other:
            return state.displayValue ?? state.raw
        }
    }

    /// The notch tile's second line (docs/casa-v2.md §1): a value when there is one to say ("70 %", "Open 65 %",
    /// "Opening…", "Unavailable"), the room's name otherwise (`room`, nil when browsing that room). Never "Off": the
    /// lamp on the tile says that. VoiceOver reads the full state (`stateLine`) instead.
    static func tileLine(for entity: HomeEntity, state: HomeEntityState, room: String?) -> String? {
        guard state.isAvailable else { return String(localized: "Unavailable") }
        switch entity.kind {
        case .light:
            if state.isOn == true, let brightness = state.brightness, entity.capabilities.contains(.brightness) {
                return percent(brightness)
            }
            return room
        case .cover:
            switch state.raw {
            case "opening": return String(localized: "home.state.opening", defaultValue: "Opening…")
            case "closing": return String(localized: "home.state.closing", defaultValue: "Closing…")
            default: break
            }
            if let position = state.position, position > 0.005, position < 0.995 {
                return String(localized: "home.state.openPercent", defaultValue: "Open \(percent(position))")
            }
            return room
        case .script:
            return state.isOn == true ? String(localized: "Running") : room
        case .sensor, .binarySensor:
            return stateLine(for: entity, state: state)
        default:
            return room
        }
    }

    /// The tile's glyph when the user picked none and it isn't drawn (a light's bulb, a blind's slats): filled SF
    /// Symbols, brass when on.
    static func filledSymbol(for entity: HomeEntity, state: HomeEntityState) -> String {
        let on = state.isOn == true
        switch entity.kind {
        case .switchable:
            if entity.deviceClass == "outlet" { return "powerplug.fill" }
            return on ? "lightswitch.on.fill" : "lightswitch.off.fill"
        case .fan: return "fan.fill"
        case .scene: return "sparkles"
        case .script: return "play.fill"
        default: return symbol(for: entity, state: state)
        }
    }

    /// The icons offered in a tile's Icon menu (about sixteen per kind; filled where SF Symbols has a fill).
    static func curatedSymbols(for kind: HomeEntityKind) -> [String] {
        switch kind {
        case .light:
            ["lightbulb.fill", "lamp.floor.fill", "lamp.table.fill", "lamp.desk.fill", "lamp.ceiling.fill",
             "chandelier.fill", "light.recessed.fill", "light.panel.fill", "light.strip.2.fill", "lightbulb.led.fill",
             "light.cylindrical.ceiling.fill", "lightspectrum.horizontal", "sun.max.fill", "moon.fill", "sparkles",
             "star.fill"]
        case .cover:
            ["blinds.vertical.closed", "blinds.horizontal.closed", "roller.shade.closed", "curtains.closed",
             "window.vertical.closed", "window.horizontal.closed", "window.shade.closed", "window.awning.closed",
             "door.sliding.left.hand.closed", "sun.max.fill", "sun.haze.fill", "moon.fill", "house.fill",
             "bed.double.fill", "sofa.fill", "tree.fill"]
        case .switchable, .fan:
            ["powerplug.fill", "lightswitch.on.fill", "power", "fan.fill", "fan.ceiling.fill", "air.purifier.fill",
             "heater.vertical.fill", "cup.and.saucer.fill", "tv.fill", "hifispeaker.fill", "washer.fill",
             "dryer.fill", "dishwasher.fill", "refrigerator.fill", "spigot.fill", "bolt.fill"]
        case .scene, .script:
            ["sparkles", "play.fill", "moon.fill", "sun.max.fill", "sunrise.fill", "sunset.fill", "film.fill",
             "book.fill", "fork.knife", "bed.double.fill", "house.fill", "figure.walk", "party.popper.fill",
             "music.note", "power", "star.fill"]
        default:
            ["circle.fill", "star.fill", "house.fill", "bolt.fill", "sparkles", "sensor.fill", "thermometer.medium",
             "humidity.fill", "leaf.fill", "drop.fill", "flame.fill", "snowflake", "wind", "sun.max.fill",
             "moon.fill", "bell.fill"]
        }
    }

    /// What kind of thing it is, for Settings' list ("Light", "Plug", "Blind").
    static func kindName(_ entity: HomeEntity) -> String {
        switch entity.kind {
        case .light: String(localized: "Light")
        case .switchable: entity.deviceClass == "outlet" ? String(localized: "Plug") : String(localized: "Switch")
        case .cover: String(localized: "Blind")
        case .scene: String(localized: "Scene")
        case .script: String(localized: "Script")
        case .fan: String(localized: "Fan")
        case .sensor: String(localized: "Sensor")
        case .binarySensor: String(localized: "Sensor")
        case .event: String(localized: "Event")
        case .camera: String(localized: "Camera")
        case .climate: String(localized: "Climate")
        case .lock: String(localized: "Lock")
        case .other: String(localized: "Other")
        }
    }

    static func percent(_ fraction: Double) -> String {
        NotchFormat.percent(min(max(fraction, 0), 1))
    }

    /// The certificate's fingerprint in pairs, four groups to a line, the way people compare them.
    static func fingerprint(_ hex: String) -> String {
        let clean = hex.uppercased().filter(\.isHexDigit)
        var pairs: [String] = []
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2, limitedBy: clean.endIndex) ?? clean.endIndex
            pairs.append(String(clean[index..<next]))
            index = next
        }
        return stride(from: 0, to: pairs.count, by: 8)
            .map { pairs[$0..<min($0 + 8, pairs.count)].joined(separator: ":") }
            .joined(separator: "\n")
    }
}
