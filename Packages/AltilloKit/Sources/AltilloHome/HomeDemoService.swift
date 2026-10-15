import Foundation
import Observation

/// A believable home that lives only in memory: the design scenarios, SwiftUI previews and the launch video use it
/// instead of a real Home Assistant. Commands change its state at once and emit the same events the real client
/// would, so the notch behaves exactly as it does with a real server (optimistic tiles, the ear, the doorbell).
@MainActor
@Observable
public final class HomeDemoService: HomeService {
    nonisolated public static let serverID = "demo"

    public private(set) var connection: HomeConnectionState
    public private(set) var areas: [HomeArea]
    public private(set) var entities: [HomeEntityID: HomeEntity]
    public private(set) var watched: Set<HomeEntityID> = []
    /// Commands received, oldest first (tests and reviews read them).
    public private(set) var performed: [HomeCommand] = []

    @ObservationIgnored private var continuations: [UUID: AsyncStream<HomeServiceEvent>.Continuation] = [:]

    public init(connected: Bool = true) {
        connection = connected ? .connected(serverName: "Casa", version: "2026.10.1") : .notConfigured
        areas = Self.demoAreas
        entities = Dictionary(uniqueKeysWithValues: Self.demoEntities().map { ($0.id, $0) })
    }

    /// `demo:<localID>`, the id of one of the demo entities.
    nonisolated public static func id(_ localID: String) -> HomeEntityID {
        HomeEntityID(provider: "ha", serverID: serverID, localID: localID)
    }

    /// Favourites that show the section at its best: the lights first, then the plug and the blind, the scenes,
    /// the script and the sensors.
    nonisolated public static let suggestedFavourites: [HomeEntityID] = [
        "light.living_room_lamp", "light.living_room_ceiling", "light.kitchen", "light.office_desk",
        "light.bedroom", "switch.coffee_machine", "cover.living_room_blind", "light.entrance",
        "scene.movie", "scene.all_off", "script.good_night",
        "sensor.living_room_temperature", "sensor.living_room_humidity", "binary_sensor.front_door",
    ].map(id)

    nonisolated public static let doorbell = id("event.front_doorbell")
    nonisolated public static let doorbellCamera = id("camera.front_door")

    // MARK: HomeService

    public func events() -> AsyncStream<HomeServiceEvent> {
        let (stream, continuation) = AsyncStream<HomeServiceEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        let key = UUID()
        continuations[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[key] = nil }
        }
        return stream
    }

    public func connect(_ config: HomeServerConfig, token: String) async throws {
        connection = .connected(serverName: "Casa", version: "2026.10.1")
        emit(.connectionChanged)
        emit(.catalogChanged)
    }

    public func resume(_ config: HomeServerConfig) {
        guard case .connected = connection else {
            connection = .connected(serverName: "Casa", version: "2026.10.1")
            emit(.connectionChanged)
            return
        }
    }

    public func trustCertificate(_ fingerprintSHA256: String) async throws -> HomeServerConfig {
        throw HomeServiceError("The demo home has no certificate to trust.")
    }

    public func disconnect(forget: Bool) {
        connection = .notConfigured
        emit(.connectionChanged)
    }

    public func watch(_ ids: Set<HomeEntityID>) { watched = ids }

    public func perform(_ command: HomeCommand) async throws {
        performed.append(command)
        let id = command.entityID
        guard var entity = entities[id] else { throw HomeServiceError("That device isn't in this home.") }
        guard entity.state.isAvailable else { throw HomeServiceError("\(entity.name) isn't available right now.") }
        var state = entity.state
        switch command {
        case .toggle:
            if entity.kind == .cover {
                let open = (state.position ?? 0) < 0.5
                state.position = open ? 1 : 0
                state.raw = open ? "open" : "closed"
            } else {
                Self.set(&state, on: !(state.isOn ?? false), kind: entity.kind, id: id)
            }
        case .turnOn: Self.set(&state, on: true, kind: entity.kind, id: id)
        case .turnOff: Self.set(&state, on: false, kind: entity.kind, id: id)
        case let .setBrightness(_, value):
            let value = min(max(value, 0), 1)
            Self.set(&state, on: value > 0, kind: entity.kind, id: id)
            state.brightness = value > 0 ? value : nil
        case let .setPosition(_, value):
            state.position = min(max(value, 0), 1)
            state.raw = state.position == 0 ? "closed" : "open"
        case .open:
            state.position = 1
            state.raw = "open"
        case .close:
            state.position = 0
            state.raw = "closed"
        case .stop:
            break
        case .activate:
            if entity.kind == .scene, id == Self.id("scene.all_off") {
                turnEverythingOff()
            } else if entity.kind == .scene, id == Self.id("scene.movie") {
                playMovie()
            }
            state.lastChanged = .now
        }
        state.lastChanged = .now
        entity.state = state
        entities[id] = entity
        emit(.statesChanged([id]))
    }

    public func snapshot(camera: HomeEntityID) async throws -> Data {
        guard entities[camera]?.kind == .camera else { throw HomeServiceError("That isn't a camera.") }
        return Self.porchSnapshot
    }

    // MARK: Demo helpers

    /// Someone at the front door: fires the doorbell's `event.*` like Home Assistant does.
    public func ringDoorbell(at date: Date = .now) {
        if var bell = entities[Self.doorbell] {
            bell.state.raw = date.ISO8601Format()
            bell.state.lastChanged = date
            entities[Self.doorbell] = bell
        }
        emit(.statesChanged([Self.doorbell]))
        emit(.triggered(Self.doorbell, at: date))
    }

    /// Changes a state from outside (a wall switch, a test): emits `statesChanged` like a real push.
    public func update(_ id: HomeEntityID, _ change: (inout HomeEntityState) -> Void) {
        guard var entity = entities[id] else { return }
        change(&entity.state)
        entities[id] = entity
        emit(.statesChanged([id]))
    }

    /// Replaces the connection state (reviews of every state of the section).
    public func setConnection(_ state: HomeConnectionState) {
        connection = state
        emit(.connectionChanged)
    }

    private func emit(_ event: HomeServiceEvent) {
        for continuation in continuations.values { continuation.yield(event) }
    }

    private func turnEverythingOff() {
        var changed: Set<HomeEntityID> = []
        for (id, var entity) in entities where entity.kind == .light || entity.kind == .switchable {
            guard entity.state.isOn == true else { continue }
            Self.set(&entity.state, on: false, kind: entity.kind, id: id)
            entities[id] = entity
            changed.insert(id)
        }
        if !changed.isEmpty { emit(.statesChanged(changed)) }
    }

    private func playMovie() {
        var changed: Set<HomeEntityID> = []
        for (id, var entity) in entities where entity.kind == .light {
            if id == Self.id("light.living_room_lamp") {
                Self.set(&entity.state, on: true, kind: .light, id: id)
                entity.state.brightness = 0.25
                entity.state.color = HomeRGB(red: 0.55, green: 0.32, blue: 0.95)
            } else if entity.state.isOn == true {
                Self.set(&entity.state, on: false, kind: .light, id: id)
            } else {
                continue
            }
            entities[id] = entity
            changed.insert(id)
        }
        if var blind = entities[Self.id("cover.living_room_blind")] {
            blind.state.position = 0
            blind.state.raw = "closed"
            entities[blind.id] = blind
            changed.insert(blind.id)
        }
        if !changed.isEmpty { emit(.statesChanged(changed)) }
    }

    /// Turns on/off keeping the colour a bulb had, the way a real bulb comes back.
    private static func set(_ state: inout HomeEntityState, on: Bool, kind: HomeEntityKind, id: HomeEntityID) {
        state.isOn = on
        state.raw = on ? "on" : "off"
        guard kind == .light else { return }
        if on {
            state.brightness = state.brightness ?? 0.8
            state.color = state.color ?? defaultColors[id.localID] ?? warmWhite
        } else {
            state.brightness = nil
            state.color = nil
        }
    }

    // MARK: The demo home

    private static let warmWhite = HomeRGB(red: 1, green: 0.78, blue: 0.5)
    private static let defaultColors: [String: HomeRGB] = [
        "light.living_room_lamp": HomeRGB(red: 1, green: 0.62, blue: 0.3),
        "light.living_room_ceiling": HomeRGB(red: 1, green: 0.86, blue: 0.66),
        "light.kitchen": HomeRGB(red: 1, green: 0.93, blue: 0.82),
        "light.office_desk": HomeRGB(red: 0.42, green: 0.62, blue: 1),
        "light.bedroom": HomeRGB(red: 1, green: 0.45, blue: 0.55),
        "light.entrance": HomeRGB(red: 1, green: 0.74, blue: 0.42),
    ]

    private static let demoAreas: [HomeArea] = [
        HomeArea(id: "living_room", name: "Living room"),
        HomeArea(id: "kitchen", name: "Kitchen"),
        HomeArea(id: "office", name: "Office"),
        HomeArea(id: "bedroom", name: "Bedroom"),
        HomeArea(id: "entrance", name: "Entrance"),
    ]

    private static func demoEntities() -> [HomeEntity] {
        let now = Date.now
        let dimmable: HomeCapabilities = [.toggle, .brightness, .colorTemperature]
        let colour: HomeCapabilities = [.toggle, .brightness, .color, .colorTemperature]
        func light(_ local: String, _ name: String, area: String, caps: HomeCapabilities, brightness: Double?,
                   color: HomeRGB? = nil) -> HomeEntity {
            let on = brightness != nil
            return HomeEntity(
                id: id(local), name: name, kind: .light, areaID: area, capabilities: caps,
                state: HomeEntityState(raw: on ? "on" : "off", isOn: on, brightness: brightness,
                                       color: on ? (color ?? defaultColors[local] ?? warmWhite) : nil,
                                       lastChanged: now.addingTimeInterval(-3_600))
            )
        }
        return [
            light("light.living_room_lamp", "Floor lamp", area: "living_room", caps: colour, brightness: 0.7),
            light("light.living_room_ceiling", "Ceiling", area: "living_room", caps: dimmable, brightness: 0.45),
            light("light.kitchen", "Kitchen", area: "kitchen", caps: dimmable, brightness: nil),
            light("light.office_desk", "Desk", area: "office", caps: colour, brightness: 0.9),
            light("light.bedroom", "Bedside", area: "bedroom", caps: colour, brightness: 0.3),
            light("light.entrance", "Hallway", area: "entrance", caps: [.toggle], brightness: nil),
            HomeEntity(id: id("switch.coffee_machine"), name: "Coffee machine", kind: .switchable, deviceClass: "outlet",
                       areaID: "kitchen", capabilities: [.toggle],
                       state: HomeEntityState(raw: "on", isOn: true, lastChanged: now.addingTimeInterval(-900))),
            HomeEntity(id: id("cover.living_room_blind"), name: "Blind", kind: .cover, deviceClass: "blind",
                       areaID: "living_room", capabilities: [.openClose, .position],
                       state: HomeEntityState(raw: "open", position: 0.6, lastChanged: now.addingTimeInterval(-7_200))),
            HomeEntity(id: id("scene.movie"), name: "Movie", kind: .scene, areaID: "living_room",
                       capabilities: [.activate], state: HomeEntityState(raw: "scening")),
            HomeEntity(id: id("scene.all_off"), name: "All off", kind: .scene, capabilities: [.activate],
                       state: HomeEntityState(raw: "scening")),
            HomeEntity(id: id("script.good_night"), name: "Good night", kind: .script, areaID: "bedroom",
                       capabilities: [.activate], state: HomeEntityState(raw: "off", isOn: false)),
            HomeEntity(id: id("sensor.living_room_temperature"), name: "Temperature", kind: .sensor,
                       deviceClass: "temperature", areaID: "living_room",
                       state: HomeEntityState(raw: "21.5", displayValue: "21.5 °C")),
            HomeEntity(id: id("sensor.living_room_humidity"), name: "Humidity", kind: .sensor, deviceClass: "humidity",
                       areaID: "living_room", state: HomeEntityState(raw: "48", displayValue: "48 %")),
            HomeEntity(id: id("binary_sensor.front_door"), name: "Front door", kind: .binarySensor, deviceClass: "door",
                       areaID: "entrance",
                       state: HomeEntityState(raw: "off", isOn: false, lastChanged: now.addingTimeInterval(-1_800))),
            HomeEntity(id: id("event.front_doorbell"), name: "Doorbell", kind: .event, deviceClass: "doorbell",
                       areaID: "entrance", state: HomeEntityState(raw: "unknown")),
            HomeEntity(id: id("camera.front_door"), name: "Front door camera", kind: .camera, areaID: "entrance",
                       state: HomeEntityState(raw: "idle")),
            HomeEntity(id: id("zone.home"), name: "Home", kind: .other, isTechnical: true,
                       state: HomeEntityState(raw: "1")),
            HomeEntity(id: id("sensor.router_uptime"), name: "Router uptime", kind: .sensor, deviceClass: "duration",
                       isTechnical: true, state: HomeEntityState(raw: "86400", displayValue: "1 d")),
            HomeEntity(id: id("lock.front_door"), name: "Front door lock", kind: .lock, areaID: "entrance",
                       isDangerous: true, state: HomeEntityState(raw: "locked")),
        ]
    }

    /// A small porch at dusk, drawn once as a PNG: what the demo camera "sees".
    private static let porchSnapshot: Data = {
        let width = 320, height = 180
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let fy = Double(y) / Double(height), fx = Double(x) / Double(width)
                // Dusk sky fading into a warm wall, a door in the middle and a lamp beside it.
                var r = 0.16 + 0.25 * fy, g = 0.14 + 0.16 * fy, b = 0.22 + 0.04 * fy
                if fx > 0.4, fx < 0.6, fy > 0.25 { r = 0.35; g = 0.22; b = 0.14 }
                let dx = fx - 0.68, dy = fy - 0.38
                let lamp = max(0, 1 - (dx * dx * 9 + dy * dy * 16) * 6)
                r += 0.9 * lamp; g += 0.65 * lamp; b += 0.3 * lamp
                if fy > 0.86 { r *= 0.6; g *= 0.6; b *= 0.6 }
                let i = (y * width + x) * 4
                pixels[i] = UInt8(min(255, r * 255)); pixels[i + 1] = UInt8(min(255, g * 255))
                pixels[i + 2] = UInt8(min(255, b * 255)); pixels[i + 3] = 255
            }
        }
        return PNG.encode(rgba: pixels, width: width, height: height)
    }()
}

/// The smallest PNG writer that works (stored deflate blocks), so the package needs neither AppKit nor ImageIO.
private enum PNG {
    static func encode(rgba: [UInt8], width: Int, height: Int) -> Data {
        var raw = Data(capacity: (width * 4 + 1) * height)
        for y in 0..<height {
            raw.append(0)
            raw.append(contentsOf: rgba[(y * width * 4)..<((y + 1) * width * 4)])
        }
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.append(be32(UInt32(width))); header.append(be32(UInt32(height)))
        header.append(contentsOf: [8, 6, 0, 0, 0])
        data.append(chunk("IHDR", header))
        data.append(chunk("IDAT", zlibStored(raw)))
        data.append(chunk("IEND", Data()))
        return data
    }

    private static func zlibStored(_ input: Data) -> Data {
        var out = Data([0x78, 0x01])
        let bytes = [UInt8](input)
        var offset = 0
        repeat {
            let count = min(65_535, bytes.count - offset)
            let last: UInt8 = offset + count >= bytes.count ? 1 : 0
            out.append(last)
            out.append(UInt8(count & 0xFF)); out.append(UInt8(count >> 8))
            out.append(UInt8(~count & 0xFF)); out.append(UInt8((~count >> 8) & 0xFF))
            out.append(contentsOf: bytes[offset..<(offset + count)])
            offset += count
        } while offset < bytes.count
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        out.append(be32(b << 16 | a))
        return out
    }

    private static func chunk(_ type: String, _ body: Data) -> Data {
        var out = be32(UInt32(body.count))
        let typed = Data(type.utf8) + body
        out.append(typed)
        out.append(be32(crc32(typed)))
        return out
    }

    private static func be32(_ value: UInt32) -> Data {
        Data([UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
