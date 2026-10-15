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
