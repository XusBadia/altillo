import Foundation

// The Home section's vocabulary (docs/casa.md). Every provider — Home Assistant today, Hue and Apple Home
// through Shortcuts later — speaks these types, so the notch, Settings and Ask never see what is underneath.
// This file is the contract between AltilloHome and the app: change it deliberately.

/// A stable identity that survives a URL change and tells two servers apart: `ha:<serverID>:light.salon`.
public struct HomeEntityID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let provider: String
    public let serverID: String
    public let localID: String

    public init(provider: String, serverID: String, localID: String) {
        self.provider = provider
        self.serverID = serverID
        self.localID = localID
    }

    /// `ha:<serverID>:light.salon`. The local id may itself contain colons; only the first two split.
    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
        self.init(provider: String(parts[0]), serverID: String(parts[1]), localID: String(parts[2]))
    }

    public var rawValue: String { "\(provider):\(serverID):\(localID)" }
    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let id = HomeEntityID(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad HomeEntityID \(raw)"))
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// What a tile is. H1 controls light, switch, cover, scene and script; the rest are shown read-only or used by alerts.
public enum HomeEntityKind: String, Codable, Sendable, CaseIterable {
    case light, switchable = "switch", cover, scene, script, climate, fan, lock, sensor, binarySensor, event, camera, other

    /// Kinds the user can pick as favourites in H1.
    public var isFavouritable: Bool {
        switch self {
        case .light, .switchable, .cover, .scene, .script, .sensor, .binarySensor, .fan: true
        case .climate, .lock, .event, .camera, .other: false
        }
    }

    /// Fired with one click, no on/off state of their own.
    public var isAction: Bool { self == .scene || self == .script }
}

public struct HomeRGB: Hashable, Codable, Sendable {
    public var red: Double, green: Double, blue: Double // 0…1
    public init(red: Double, green: Double, blue: Double) { self.red = red; self.green = green; self.blue = blue }
}

public struct HomeEntityState: Hashable, Sendable {
    /// The provider's own state string ("on", "off", "open", "closing", "21.5", "unavailable"…).
    public var raw: String
    public var isAvailable: Bool
    /// nil for kinds without on/off (scenes, sensors).
    public var isOn: Bool?
    /// 0…1, lights only, nil when off or not dimmable.
    public var brightness: Double?
    /// The colour the bulb is actually showing (from rgb_color, or derived from color_temp_kelvin). nil when off.
    public var color: HomeRGB?
    /// 0…1 (0 = closed), covers that report a position.
    public var position: Double?
    /// Formatted value with unit for sensors ("21,5 °C"), nil otherwise.
    public var displayValue: String?
    public var lastChanged: Date?

    public init(raw: String, isAvailable: Bool = true, isOn: Bool? = nil, brightness: Double? = nil, color: HomeRGB? = nil,
                position: Double? = nil, displayValue: String? = nil, lastChanged: Date? = nil) {
        self.raw = raw; self.isAvailable = isAvailable; self.isOn = isOn; self.brightness = brightness; self.color = color
        self.position = position; self.displayValue = displayValue; self.lastChanged = lastChanged
    }
}

public struct HomeCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let toggle = HomeCapabilities(rawValue: 1 << 0)
    public static let brightness = HomeCapabilities(rawValue: 1 << 1)
    public static let color = HomeCapabilities(rawValue: 1 << 2)
    public static let colorTemperature = HomeCapabilities(rawValue: 1 << 3)
    public static let position = HomeCapabilities(rawValue: 1 << 4)
    public static let openClose = HomeCapabilities(rawValue: 1 << 5)
    public static let activate = HomeCapabilities(rawValue: 1 << 6)
}

public struct HomeEntity: Identifiable, Hashable, Sendable {
    public let id: HomeEntityID
    public var name: String
    public var kind: HomeEntityKind
    /// HA `device_class` (garage, door, window, temperature, doorbell…), when there is one.
    public var deviceClass: String?
    public var areaID: String?
    public var capabilities: HomeCapabilities
    /// Locks, alarms, garage doors and gates: never on a single click (docs/casa.md).
    public var isDangerous: Bool
    /// Hidden, disabled, diagnostic or config entities: never suggested, still pickable from search.
    public var isTechnical: Bool
    public var state: HomeEntityState

    public init(id: HomeEntityID, name: String, kind: HomeEntityKind, deviceClass: String? = nil, areaID: String? = nil,
                capabilities: HomeCapabilities = [], isDangerous: Bool = false, isTechnical: Bool = false,
                state: HomeEntityState) {
        self.id = id; self.name = name; self.kind = kind; self.deviceClass = deviceClass; self.areaID = areaID
        self.capabilities = capabilities; self.isDangerous = isDangerous; self.isTechnical = isTechnical; self.state = state
    }
}

public struct HomeArea: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum HomeCommand: Hashable, Sendable {
    case toggle(HomeEntityID)
    case turnOn(HomeEntityID)
    case turnOff(HomeEntityID)
    /// 0…1. 0 turns the light off.
    case setBrightness(HomeEntityID, Double)
    /// 0…1, 0 = closed.
    case setPosition(HomeEntityID, Double)
    case open(HomeEntityID)
    case close(HomeEntityID)
    case stop(HomeEntityID)
    /// Scenes and scripts.
    case activate(HomeEntityID)

    public var entityID: HomeEntityID {
        switch self {
        case .toggle(let id), .turnOn(let id), .turnOff(let id), .setBrightness(let id, _), .setPosition(let id, _),
             .open(let id), .close(let id), .stop(let id), .activate(let id): id
        }
    }
}

/// A Home Assistant server the user added. The serverID is generated on this Mac when the server is added and
/// never changes, so editing the URL keeps every favourite.
public struct HomeServerConfig: Hashable, Codable, Sendable, Identifiable {
    public let serverID: String
    public var url: URL
    /// HA's `location_name`, refreshed on each connect.
    public var name: String?
    /// SHA-256 of the leaf certificate, hex, pinned the first time the user trusts a self-signed https server.
    public var pinnedCertificateSHA256: String?

    public var id: String { serverID }

    public init(serverID: String = UUID().uuidString, url: URL, name: String? = nil, pinnedCertificateSHA256: String? = nil) {
        self.serverID = serverID; self.url = url; self.name = name; self.pinnedCertificateSHA256 = pinnedCertificateSHA256
    }
}

public enum HomeConnectionState: Hashable, Sendable {
    case notConfigured
    case connecting
    case connected(serverName: String, version: String)
    /// The token was refused (deleted in HA, mistyped). The user has to paste a new one.
    case unauthorized
    /// A self-signed https server we haven't pinned yet (or whose certificate changed). The user decides.
    case needsTrust(fingerprintSHA256: String)
    /// macOS Local Network permission is off for Altillo.
    case localNetworkDenied
    /// Can't reach it right now (away from home, server down). Retries on its own with backoff.
    case unreachable(reason: String)
}

public enum HomeServiceEvent: Hashable, Sendable {
    case connectionChanged
    /// Areas or the entity list changed (an entity was added, renamed, moved).
    case catalogChanged
    /// One or more watched entities have a new state.
    case statesChanged(Set<HomeEntityID>)
    /// A watched `event.*` fired, or a watched binary sensor went from off to on. Drives the doorbell peek.
    case triggered(HomeEntityID, at: Date)
}

public struct HomeServiceError: Error, Hashable, Sendable, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// One connected home. `HomeAssistantClient` is the real one; the app's tests and previews use fakes.
@MainActor
public protocol HomeService: AnyObject {
    var connection: HomeConnectionState { get }
    var areas: [HomeArea] { get }
    /// The whole catalogue (from the registries and one `get_states` at connect). States of entities that aren't
    /// watched may be stale: only watched ones are kept live.
    var entities: [HomeEntityID: HomeEntity] { get }
    /// A fresh stream per call; every subscriber gets every event.
    func events() -> AsyncStream<HomeServiceEvent>

    /// Checks the URL and token, keeps the token in the Keychain and stays connected (reconnecting with backoff
    /// and pausing while the Mac sleeps). Throws a `HomeServiceError` with a user-facing message.
    func connect(_ config: HomeServerConfig, token: String) async throws
    /// Connects with the token already in the Keychain for this server, if any.
    func resume(_ config: HomeServerConfig)
    /// Pins the certificate shown in `.needsTrust` and connects again, saving the token once that succeeds.
    /// Returns the updated config to persist; throws a `HomeServiceError` like `connect`.
    func trustCertificate(_ fingerprintSHA256: String) async throws -> HomeServerConfig
    /// Closes the connection. With `forget`, also deletes the token from the Keychain.
    func disconnect(forget: Bool)
    /// Only these entities are subscribed to (`subscribe_entities` with `entity_ids`): favourites + alert entities.
    func watch(_ ids: Set<HomeEntityID>)
    func perform(_ command: HomeCommand) async throws
    /// JPEG/PNG bytes from `/api/camera_proxy/<entity>`.
    func snapshot(camera: HomeEntityID) async throws -> Data
}
