import Foundation

// Pure Home Assistant ↔ Home vocabulary mapping: registries + states → catalogue, compressed diffs, service calls,
// addresses, backoff. No I/O here, so everything is unit-tested without a socket.

/// What the entity registry (plus its device) tells us about one entity. States add the rest.
struct HAEntityMeta: Hashable, Sendable {
    var entityID: String
    var registryName: String?
    var originalName: String?
    var areaID: String?
    var isTechnical = false
}

/// One entity's last known state, as HA sends it.
struct HAState: Hashable, Sendable {
    var state: String
    var attributes: [String: JSONValue]
    var lastChanged: Date?
}

struct HACatalog: Sendable {
    var areas: [HomeArea] = []
    var metas: [String: HAEntityMeta] = [:]
    var states: [String: HAState] = [:]
}

enum HAMapping {
    // MARK: Catalogue

    static func areas(_ list: JSONValue) -> [HomeArea] {
        (list.array ?? []).compactMap { item in
            guard let id = item["area_id"]?.string else { return nil }
            return HomeArea(id: id, name: item["name"]?.string ?? id)
        }
    }

    /// device id → area id.
    static func deviceAreas(_ list: JSONValue) -> [String: String] {
        var result: [String: String] = [:]
        for item in list.array ?? [] {
            if let id = item["id"]?.string, let area = item["area_id"]?.string { result[id] = area }
        }
        return result
    }

    static func metas(_ entityRegistry: JSONValue, deviceAreas: [String: String]) -> [String: HAEntityMeta] {
        var result: [String: HAEntityMeta] = [:]
        for item in entityRegistry.array ?? [] {
            guard let entityID = item["entity_id"]?.string else { continue }
            let deviceArea = item["device_id"]?.string.flatMap { deviceAreas[$0] }
            let technical = item["hidden_by"]?.nonNull != nil || item["disabled_by"]?.nonNull != nil
                || item["entity_category"]?.nonNull != nil
            result[entityID] = HAEntityMeta(
                entityID: entityID,
                registryName: item["name"]?.string,
                originalName: item["original_name"]?.string,
                areaID: item["area_id"]?.string ?? deviceArea,
                isTechnical: technical)
        }
        return result
    }

    static func state(fromFull item: JSONValue) -> HAState? {
        guard let state = item["state"]?.string else { return nil }
        return HAState(state: state, attributes: item["attributes"]?.object ?? [:],
                       lastChanged: item["last_changed"]?.string.flatMap(parseISODate))
    }

    static func states(_ list: JSONValue) -> [String: HAState] {
        var result: [String: HAState] = [:]
        for item in list.array ?? [] {
            if let id = item["entity_id"]?.string, let state = state(fromFull: item) { result[id] = state }
        }
        return result
    }

    static func catalog(areas: JSONValue, devices: JSONValue, entities: JSONValue, states: JSONValue) -> HACatalog {
        HACatalog(areas: self.areas(areas), metas: metas(entities, deviceAreas: deviceAreas(devices)),
                  states: self.states(states))
    }

    /// Every entity in the registry or in the states (YAML entities, zone.home… have no registry entry).
    /// Registry entities without a state (disabled ones) appear as unavailable.
    static func entities(_ catalog: HACatalog, serverID: String) -> [HomeEntityID: HomeEntity] {
        var result: [HomeEntityID: HomeEntity] = [:]
        for localID in Set(catalog.metas.keys).union(catalog.states.keys) {
            let entity = entity(localID: localID, serverID: serverID, meta: catalog.metas[localID], state: catalog.states[localID])
            result[entity.id] = entity
        }
        return result
    }

    // MARK: One entity

    static func domain(_ entityID: String) -> String {
        entityID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? entityID
    }

    static func kind(domain: String) -> HomeEntityKind {
        switch domain {
        case "light": .light
        case "switch", "input_boolean": .switchable
        case "cover": .cover
        case "scene": .scene
        case "script": .script
        case "climate": .climate
        case "fan": .fan
        case "lock": .lock
        case "sensor": .sensor
        case "binary_sensor": .binarySensor
        case "event": .event
        case "camera": .camera
        default: .other
        }
    }

    static func entity(localID: String, serverID: String, meta: HAEntityMeta?, state: HAState?) -> HomeEntity {
        let domain = domain(localID)
        let kind = kind(domain: domain)
        let attributes = state?.attributes ?? [:]
        let deviceClass = attributes["device_class"]?.string
        let name = meta?.registryName ?? attributes["friendly_name"]?.string ?? meta?.originalName ?? localID
        return HomeEntity(
            id: HomeEntityID(provider: "ha", serverID: serverID, localID: localID),
            name: name, kind: kind, deviceClass: deviceClass, areaID: meta?.areaID,
            capabilities: capabilities(domain: domain, attributes: attributes),
            isDangerous: isDangerous(domain: domain, deviceClass: deviceClass),
            isTechnical: meta?.isTechnical ?? false,
            state: entityState(domain: domain, state: state))
    }

    static func capabilities(domain: String, attributes: [String: JSONValue]) -> HomeCapabilities {
        var result: HomeCapabilities = []
        switch domain {
        case "light":
            result.insert(.toggle)
            let modes = Set((attributes["supported_color_modes"]?.array ?? []).compactMap(\.string))
            if !modes.subtracting(["onoff"]).isEmpty { result.insert(.brightness) }
            if !modes.isDisjoint(with: ["hs", "rgb", "rgbw", "rgbww", "xy"]) { result.insert(.color) }
            if modes.contains("color_temp") { result.insert(.colorTemperature) }
        case "switch", "fan", "input_boolean":
            result.insert(.toggle)
        case "cover":
            let features = attributes["supported_features"]?.int ?? 0
            if features & 3 != 0 { result.insert(.openClose) }
            if features & 4 != 0 { result.insert(.position) }
        case "scene", "script":
            result.insert(.activate)
        default: break
        }
        return result
    }

    static func isDangerous(domain: String, deviceClass: String?) -> Bool {
        switch domain {
        case "lock", "alarm_control_panel": true
        case "cover": deviceClass == "garage" || deviceClass == "gate"
        default: false
        }
    }

    static func entityState(domain: String, state: HAState?) -> HomeEntityState {
        guard let state else { return HomeEntityState(raw: "unavailable", isAvailable: false) }
        let raw = state.state
        let attributes = state.attributes
        // Scenes and events keep a timestamp as their state, "unknown" until first used: still usable.
        let isAvailable = (domain == "scene" || domain == "event") ? raw != "unavailable" : !["unavailable", "unknown"].contains(raw)
        var result = HomeEntityState(raw: raw, isAvailable: isAvailable, lastChanged: state.lastChanged)
        switch domain {
        case "light":
            let on = raw == "on"
            result.isOn = on
            if on {
                result.brightness = attributes["brightness"]?.double.map { min(max($0 / 255, 0), 1) }
                result.color = lightColor(attributes)
            }
        case "switch", "fan", "input_boolean", "binary_sensor":
            result.isOn = raw == "on"
        case "cover":
            result.isOn = raw == "open" || raw == "opening"
            result.position = attributes["current_position"]?.double.map { min(max($0 / 100, 0), 1) }
        case "sensor":
            if isAvailable { result.displayValue = displayValue(raw, unit: attributes["unit_of_measurement"]?.string) }
        default: break
        }
        return result
    }

    static func lightColor(_ attributes: [String: JSONValue]) -> HomeRGB {
        if let rgb = attributes["rgb_color"]?.array?.compactMap(\.double), rgb.count == 3 {
            return HomeRGB(red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255)
        }
        if let kelvin = attributes["color_temp_kelvin"]?.double { return colorTemperatureRGB(kelvin: kelvin) }
        return colorTemperatureRGB(kelvin: 2700)
    }

    /// Tanner Helland's blackbody approximation, 1000…40000 K.
    static func colorTemperatureRGB(kelvin: Double) -> HomeRGB {
        let t = min(max(kelvin, 1000), 40000) / 100
        let red = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let green = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let blue = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        func unit(_ value: Double) -> Double { min(max(value, 0), 255) / 255 }
        return HomeRGB(red: unit(red), green: unit(green), blue: unit(blue))
    }

    /// "21.5" + "°C" → "21,5 °C" in Spanish. Non-numeric states pass through.
    static func displayValue(_ raw: String, unit: String?, locale: Locale = .current) -> String {
        var text = raw
        if let value = Double(raw), value.isFinite {
            let decimals = raw.split(separator: ".", maxSplits: 1).dropFirst().first?.count ?? 0
            text = value.formatted(.number.locale(locale).precision(.fractionLength(min(decimals, 6))))
        }
        guard let unit, !unit.isEmpty else { return text }
        return "\(text) \(unit)"
    }

    static func parseISODate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    // MARK: Compressed state diffs (subscribe_entities)

    struct DiffResult: Equatable {
        var changed: Set<String> = []
        /// Entity → when it fired (event.* new timestamp, binary_sensor off → on). Not for initial adds.
        var triggered: [String: Date] = [:]
    }

    static let eventTriggerMaxAge: TimeInterval = 30

    /// Applies one `subscribe_entities` event to `states` in place.
    static func apply(diff event: JSONValue, to states: inout [String: HAState], now: Date = .now) -> DiffResult {
        var result = DiffResult()
        for (id, compressed) in event["a"]?.object ?? [:] {
            guard let state = compressed["s"]?.string else { continue }
            states[id] = HAState(state: state, attributes: compressed["a"]?.object ?? [:],
                                 lastChanged: compressed["lc"]?.double.map(Date.init(timeIntervalSince1970:)))
            result.changed.insert(id)
        }
        for (id, change) in event["c"]?.object ?? [:] {
            guard var current = states[id] else { continue }
            let previous = current.state
            if let added = change["+"] {
                if let state = added["s"]?.string { current.state = state }
                for (key, value) in added["a"]?.object ?? [:] { current.attributes[key] = value }
                if let changed = added["lc"]?.double { current.lastChanged = Date(timeIntervalSince1970: changed) }
            }
            for key in change["-"]?["a"]?.array?.compactMap(\.string) ?? [] { current.attributes[key] = nil }
            states[id] = current
            result.changed.insert(id)
            // Coming back from "unavailable" (restart, reconnect of the integration) is not a press.
            if current.state != previous, previous != "unavailable" {
                switch domain(id) {
                case "event" where current.state != "unavailable" && current.state != "unknown":
                    // "unknown" → timestamp is a real first press; a timestamp older than 30 s is a replay.
                    let firedAt = parseISODate(current.state) ?? current.lastChanged ?? now
                    if now.timeIntervalSince(firedAt) <= eventTriggerMaxAge { result.triggered[id] = firedAt }
                case "binary_sensor" where previous == "off" && current.state == "on":
                    result.triggered[id] = current.lastChanged ?? now
                default: break
                }
            }
        }
        for id in event["r"]?.array?.compactMap(\.string) ?? [] {
            states[id] = HAState(state: "unavailable", attributes: states[id]?.attributes ?? [:], lastChanged: now)
            result.changed.insert(id)
        }
        return result
    }

    // MARK: Service calls

    struct ServiceCall: Hashable {
        var domain: String
        var service: String
        var data: [String: JSONValue] = [:]
    }

    static func serviceCall(for command: HomeCommand) -> ServiceCall? {
        let entityDomain = domain(command.entityID.localID)
        let toggles: Set<String> = ["light", "switch", "fan", "input_boolean"]
        switch command {
        case .toggle:
            if toggles.contains(entityDomain) || entityDomain == "cover" { return ServiceCall(domain: entityDomain, service: "toggle") }
            return ServiceCall(domain: "homeassistant", service: "toggle")
        case .turnOn:
            if toggles.contains(entityDomain) || entityDomain == "scene" || entityDomain == "script" {
                return ServiceCall(domain: entityDomain, service: "turn_on")
            }
            if entityDomain == "cover" { return ServiceCall(domain: "cover", service: "open_cover") }
            return ServiceCall(domain: "homeassistant", service: "turn_on")
        case .turnOff:
            if toggles.contains(entityDomain) { return ServiceCall(domain: entityDomain, service: "turn_off") }
            if entityDomain == "cover" { return ServiceCall(domain: "cover", service: "close_cover") }
            return ServiceCall(domain: "homeassistant", service: "turn_off")
        case .setBrightness(_, let value):
            guard entityDomain == "light" else { return nil }
            let percent = Int((min(max(value, 0), 1) * 100).rounded())
            if value <= 0 { return ServiceCall(domain: "light", service: "turn_off") }
            return ServiceCall(domain: "light", service: "turn_on", data: ["brightness_pct": .number(Double(max(1, percent)))])
        case .setPosition(_, let value):
            guard entityDomain == "cover" else { return nil }
            let position = Int((min(max(value, 0), 1) * 100).rounded())
            return ServiceCall(domain: "cover", service: "set_cover_position", data: ["position": .number(Double(position))])
        case .open:
            guard entityDomain == "cover" else { return nil }
            return ServiceCall(domain: "cover", service: "open_cover")
        case .close:
            guard entityDomain == "cover" else { return nil }
            return ServiceCall(domain: "cover", service: "close_cover")
        case .stop:
            guard entityDomain == "cover" else { return nil }
            return ServiceCall(domain: "cover", service: "stop_cover")
        case .activate:
            guard entityDomain == "scene" || entityDomain == "script" else { return nil }
            return ServiceCall(domain: entityDomain, service: "turn_on")
        }
    }

    // MARK: Addresses and timing

    static func websocketURL(for server: URL) -> URL {
        var components = URLComponents(url: server, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = components.scheme?.lowercased() == "https" ? "wss" : "ws"
        components.path = "/api/websocket"
        components.query = nil
        components.fragment = nil
        return components.url ?? server
    }

    static func snapshotRequest(server: URL, camera: String, token: String) -> URLRequest {
        var request = URLRequest(url: server.appending(path: "api/camera_proxy/\(camera)"), timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// 1, 2, 4, 8… seconds, capped at 60.
    static func backoffDelay(attempt: Int) -> Double {
        min(60, pow(2, Double(min(max(attempt, 0), 16))))
    }

    static func normalize(_ raw: String) throws -> URL {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw HomeServiceError(HomeStrings.emptyAddress) }
        guard !text.contains(where: \.isWhitespace) else { throw HomeServiceError(HomeStrings.badAddress) }
        if !text.contains("://") {
            // Local-looking hosts (x.local, a bare name like homeassistant or localhost, an IP) default to http;
            // anything that looks public defaults to https.
            let host = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
            text = (isLocalLooking(hostAndPort: host) ? "http://" : "https://") + text
        }
        guard let parsed = URLComponents(string: text) else { throw HomeServiceError(HomeStrings.badAddress) }
        guard let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw HomeServiceError(HomeStrings.badScheme)
        }
        guard let host = parsed.percentEncodedHost, !host.isEmpty else { throw HomeServiceError(HomeStrings.badAddress) }
        var components = URLComponents()
        components.scheme = scheme
        components.percentEncodedHost = host.lowercased()
        components.port = parsed.port
        let bare = host.lowercased()
        if parsed.port == nil, scheme == "http", bare.hasSuffix(".local") || bare == "homeassistant" || isIPv4(bare) {
            components.port = 8123
        }
        guard let url = components.url else { throw HomeServiceError(HomeStrings.badAddress) }
        return url
    }

    static func isLocalLooking(hostAndPort: String) -> Bool {
        let lowered = hostAndPort.lowercased()
        if lowered.hasPrefix("[") { return true } // IPv6 literal
        let host = lowered.split(separator: ":", maxSplits: 1).first.map(String.init) ?? lowered
        return host.hasSuffix(".local") || !host.contains(".") || isIPv4(host)
    }

    static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 3 && part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber) && (Int(part) ?? 256) <= 255
        }
    }

    /// Best effort: macOS reports a denied Local Network permission as an NWPath "Local network prohibited"
    /// or a policy denial somewhere in the error chain.
    static func isLocalNetworkDenied(_ error: any Error) -> Bool {
        var pending: [NSError] = [error as NSError]
        var seen = 0
        while let current = pending.popLast(), seen < 16 {
            seen += 1
            if let path = current.userInfo["_NSURLErrorNWPathKey"] {
                let text = String(describing: path).lowercased()
                if text.contains("local network prohibited") || text.contains("policy denied") { return true }
            }
            let text = current.localizedDescription.lowercased()
            if text.contains("local network prohibited") || text.contains("policy denied") { return true }
            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError { pending.append(underlying) }
            pending.append(contentsOf: current.underlyingErrors.map { $0 as NSError })
        }
        return false
    }

    /// App Transport Security refused a plain http:// address (only local hosts are allowed over http).
    static func isInsecureRemote(_ error: any Error) -> Bool {
        var pending: [NSError] = [error as NSError]
        var seen = 0
        while let current = pending.popLast(), seen < 16 {
            seen += 1
            if current.domain == NSURLErrorDomain, current.code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
                return true
            }
            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError { pending.append(underlying) }
        }
        return false
    }
}
