import Foundation
@testable import AltilloHome

/// A scripted Home Assistant: answers each message the client sends, like the real WebSocket API.
struct FakeHA: Sendable {
    var token = "good-token"
    var version = "2026.10.1"
    var locationName = "Casa Xus"
    var failingEntity: String?
    var answersPing = true
    /// Never answers this message type (a server that hangs mid-load).
    var silentOn: String?
    var areas: JSONValue = [
        ["area_id": "salon", "name": "Salón"],
        ["area_id": "despacho", "name": "Despacho"],
    ]
    var devices: JSONValue = [
        ["id": "dev-salon", "area_id": "salon", "name": "Hue"],
        ["id": "dev-none", "area_id": nil, "name": "Enchufe"],
    ]
    var entities: JSONValue = [
        ["entity_id": "light.salon", "device_id": "dev-salon", "area_id": nil, "name": nil, "original_name": "Lámpara",
         "hidden_by": nil, "disabled_by": nil, "entity_category": nil],
        ["entity_id": "light.despacho", "device_id": "dev-salon", "area_id": "despacho", "name": "Flexo",
         "original_name": "Bombilla", "hidden_by": nil, "disabled_by": nil, "entity_category": nil],
        ["entity_id": "light.vieja", "device_id": nil, "area_id": nil, "name": nil, "original_name": "Vieja",
         "hidden_by": nil, "disabled_by": "user", "entity_category": nil],
        ["entity_id": "switch.cafetera", "device_id": "dev-none", "area_id": nil, "name": nil, "original_name": "Cafetera"],
        ["entity_id": "input_boolean.invitados", "hidden_by": "user", "original_name": "Invitados"],
        ["entity_id": "sensor.temperatura", "device_id": "dev-salon", "original_name": "Temperatura"],
        ["entity_id": "sensor.wifi", "device_id": "dev-salon", "entity_category": "diagnostic", "original_name": "Wi-Fi"],
        ["entity_id": "cover.garaje", "area_id": nil, "original_name": "Garaje"],
        ["entity_id": "cover.persiana", "area_id": "salon", "original_name": "Persiana"],
        ["entity_id": "scene.peli", "area_id": "salon", "original_name": "Peli"],
        ["entity_id": "script.buenas_noches", "original_name": "Buenas noches"],
        ["entity_id": "lock.puerta", "original_name": "Puerta"],
        ["entity_id": "binary_sensor.puerta", "original_name": "Puerta abierta"],
        ["entity_id": "event.timbre", "original_name": "Timbre"],
    ]
    var states: JSONValue = [
        ["entity_id": "light.salon", "state": "on", "last_changed": "2026-10-15T08:00:00.000000+00:00",
         "attributes": ["friendly_name": "Luz del salón", "brightness": 128, "supported_color_modes": ["color_temp", "xy"],
                        "color_temp_kelvin": 2700, "rgb_color": [255, 167, 87]]],
        ["entity_id": "light.despacho", "state": "off", "last_changed": "2026-10-15T08:00:00+00:00",
         "attributes": ["friendly_name": "Despacho", "supported_color_modes": ["onoff"]]],
        ["entity_id": "switch.cafetera", "state": "off", "attributes": ["friendly_name": "Cafetera"]],
        ["entity_id": "input_boolean.invitados", "state": "on", "attributes": [:]],
        ["entity_id": "sensor.temperatura", "state": "21.5",
         "attributes": ["friendly_name": "Temperatura", "unit_of_measurement": "°C", "device_class": "temperature"]],
        ["entity_id": "sensor.wifi", "state": "-61", "attributes": ["unit_of_measurement": "dBm"]],
        ["entity_id": "cover.garaje", "state": "closed",
         "attributes": ["device_class": "garage", "supported_features": 15, "current_position": 0]],
        ["entity_id": "cover.persiana", "state": "open", "attributes": ["supported_features": 3]],
        ["entity_id": "scene.peli", "state": "unknown", "attributes": ["friendly_name": "Peli"]],
        ["entity_id": "script.buenas_noches", "state": "off", "attributes": [:]],
        ["entity_id": "lock.puerta", "state": "locked", "attributes": [:]],
        ["entity_id": "binary_sensor.puerta", "state": "off", "attributes": ["device_class": "door"]],
        ["entity_id": "event.timbre", "state": "unknown", "attributes": ["device_class": "doorbell"]],
        ["entity_id": "zone.home", "state": "1", "attributes": ["friendly_name": "Home"]],
    ]

    static func result(_ id: JSONValue, _ value: JSONValue = nil) -> JSONValue {
        ["id": id, "type": "result", "success": true, "result": value]
    }

    func respond(to message: JSONValue) -> [JSONValue] {
        let id = message["id"] ?? nil
        if let silentOn, message["type"]?.string == silentOn { return [] }
        switch message["type"]?.string {
        case "auth":
            if message["access_token"]?.string == token { return [["type": "auth_ok", "ha_version": .string(version)]] }
            return [["type": "auth_invalid", "message": "Invalid access token or password"]]
        case "get_config": return [Self.result(id, ["location_name": .string(locationName), "version": .string(version)])]
        case "config/area_registry/list": return [Self.result(id, areas)]
        case "config/device_registry/list": return [Self.result(id, devices)]
        case "config/entity_registry/list": return [Self.result(id, entities)]
        case "get_states": return [Self.result(id, states)]
        case "subscribe_events", "unsubscribe_events": return [Self.result(id)]
        case "subscribe_entities":
            let wanted = Set((message["entity_ids"]?.array ?? []).compactMap(\.string))
            var added: [String: JSONValue] = [:]
            for item in states.array ?? [] {
                guard let entityID = item["entity_id"]?.string, wanted.contains(entityID) else { continue }
                added[entityID] = ["s": item["state"] ?? nil, "a": item["attributes"] ?? [:], "lc": 1_760_515_200]
            }
            return [Self.result(id), ["id": id, "type": "event", "event": ["a": .object(added)]]]
        case "call_service":
            if let failingEntity, message["target"]?["entity_id"]?.string == failingEntity {
                return [["id": id, "type": "result", "success": false,
                         "error": ["code": "service_validation_error", "message": "Nope, it's jammed"]]]
            }
            return [Self.result(id, ["context": ["id": "ctx"]])]
        case "ping": return answersPing ? [["id": id, "type": "pong"]] : []
        default: return [["id": id, "type": "result", "success": false, "error": ["code": "unknown_command", "message": "Unknown"]]]
        }
    }
}

/// The client's end of a fake socket. `serverClose()` simulates the connection dropping.
actor FakeSocket: HomeSocket {
    nonisolated let url: URL
    nonisolated let delegate: HomeTrustDelegate
    private let server: FakeHA?
    private let failure: (any Error)?
    private(set) var sent: [JSONValue] = []
    private var inbox: [String] = []
    private var waiter: CheckedContinuation<String, any Error>?
    private(set) var isClosed = false

    init(url: URL, delegate: HomeTrustDelegate, server: FakeHA?, failure: (any Error)? = nil) {
        self.url = url
        self.delegate = delegate
        self.server = server
        self.failure = failure
        if server != nil, failure == nil { inbox = [#"{"type":"auth_required","ha_version":"2026.10.1"}"#] }
    }

    func send(_ text: String) async throws {
        guard !isClosed else { throw URLError(.networkConnectionLost) }
        let message = try JSONValue.decode(text)
        sent.append(message)
        for reply in server?.respond(to: message) ?? [] { deliver(try reply.encodedString()) }
    }

    func receive() async throws -> String {
        if let failure { throw failure }
        if !inbox.isEmpty { return inbox.removeFirst() }
        if isClosed { throw URLError(.networkConnectionLost) }
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }

    func close() async { serverClose() }

    func serverClose() {
        isClosed = true
        waiter?.resume(throwing: URLError(.networkConnectionLost))
        waiter = nil
    }

    func push(_ message: JSONValue) throws { deliver(try message.encodedString()) }

    func sent(type: String) -> [JSONValue] { sent.filter { $0["type"]?.string == type } }

    private func deliver(_ text: String) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: text)
        } else {
            inbox.append(text)
        }
    }
}

@MainActor
final class EventLog {
    var events: [HomeServiceEvent] = []
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<HomeServiceEvent>) {
        task = Task { [weak self] in
            for await event in stream { self?.events.append(event) }
        }
    }

    deinit { task?.cancel() }

    var triggered: [(HomeEntityID, Date)] {
        events.compactMap { if case .triggered(let id, let at) = $0 { (id, at) } else { nil } }
    }
    var changedIDs: Set<HomeEntityID> {
        events.reduce(into: []) { if case .statesChanged(let ids) = $1 { $0.formUnion(ids) } }
    }
    var catalogChanges: Int { events.filter { $0 == .catalogChanged }.count }
}

/// Polls until the condition holds (or ~2 s pass).
@MainActor
func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

extension HomeTiming {
    static let test = HomeTiming(request: .seconds(2), bulkRequest: .seconds(2), handshake: .seconds(2), ping: .seconds(3600),
                                 pong: .seconds(2), catalogDebounce: .milliseconds(40), backoffUnit: .milliseconds(10))
}

/// A client wired to fake sockets. `server` is what the next socket will talk to.
@MainActor
final class Harness {
    var server = FakeHA()
    var sockets: [FakeSocket] = []
    /// When set, the next socket fails like a refused TLS handshake with this leaf fingerprint.
    var untrustedFingerprint: String?
    let store: InMemoryHomeTokenStore
    private(set) var client: HomeAssistantClient!

    init(tokens: [String: String] = [:], timing: HomeTiming = .test) {
        store = InMemoryHomeTokenStore(tokens)
        client = HomeAssistantClient(tokens: store, socketFactory: { [unowned self] url, delegate in
            let socket: FakeSocket
            if let fingerprint = self.untrustedFingerprint, delegate.pinnedSHA256 != fingerprint {
                delegate.recordUntrusted(fingerprint)
                socket = FakeSocket(url: url, delegate: delegate, server: nil, failure: URLError(.cancelled))
            } else {
                socket = FakeSocket(url: url, delegate: delegate, server: self.server)
            }
            self.sockets.append(socket)
            return socket
        }, timing: timing)
    }

    var socket: FakeSocket { sockets.last! }
    let config = HomeServerConfig(serverID: "S1", url: URL(string: "http://homeassistant.local:8123")!)

    func id(_ localID: String) -> HomeEntityID { HomeEntityID(provider: "ha", serverID: "S1", localID: localID) }

    func connect() async throws {
        try await client.connect(config, token: server.token)
    }

    /// The last message of a type, without its id, for exact comparisons.
    func last(_ type: String) async -> JSONValue? {
        guard case .object(var object) = await socket.sent(type: type).last else { return nil }
        object["id"] = nil
        return .object(object)
    }
}
