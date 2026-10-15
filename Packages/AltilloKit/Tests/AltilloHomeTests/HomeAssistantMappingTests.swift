import Foundation
import Testing
@testable import AltilloHome

@Suite struct HomeAssistantNormalizeTests {
    @Test func addsSchemeAndDefaultPort() throws {
        #expect(try HomeAssistantClient.normalize("homeassistant.local").absoluteString == "http://homeassistant.local:8123")
        #expect(try HomeAssistantClient.normalize("  homeassistant.local:8123/lovelace/0/ ").absoluteString
            == "http://homeassistant.local:8123")
        #expect(try HomeAssistantClient.normalize("homeassistant").absoluteString == "http://homeassistant:8123")
        #expect(try HomeAssistantClient.normalize("192.168.1.20").absoluteString == "http://192.168.1.20:8123")
        #expect(try HomeAssistantClient.normalize("192.168.1.20:80").absoluteString == "http://192.168.1.20:80")
    }

    @Test func keepsHTTPSAndPublicHostsAsTyped() throws {
        #expect(try HomeAssistantClient.normalize("https://casa.ui.nabu.casa/").absoluteString == "https://casa.ui.nabu.casa")
        #expect(try HomeAssistantClient.normalize("HTTPS://Casa.Example.com:8443///").absoluteString == "https://casa.example.com:8443")
        #expect(try HomeAssistantClient.normalize("https://homeassistant.local").absoluteString == "https://homeassistant.local")
        #expect(try HomeAssistantClient.normalize("ha.example.com").absoluteString == "https://ha.example.com")
        #expect(try HomeAssistantClient.normalize("casa.ui.nabu.casa/lovelace").absoluteString == "https://casa.ui.nabu.casa")
        #expect(try HomeAssistantClient.normalize("1.2.3.4.5").absoluteString == "https://1.2.3.4.5")
        #expect(try HomeAssistantClient.normalize("http://ha.example.com").absoluteString == "http://ha.example.com")
    }

    @Test func localLookingHostsDefaultToHTTP() throws {
        #expect(try HomeAssistantClient.normalize("localhost:8124").absoluteString == "http://localhost:8124")
        #expect(try HomeAssistantClient.normalize("localhost").absoluteString == "http://localhost")
        #expect(try HomeAssistantClient.normalize("Casa.local:8443").absoluteString == "http://casa.local:8443")
        #expect(try HomeAssistantClient.normalize("10.0.0.5/").absoluteString == "http://10.0.0.5:8123")
        #expect(try HomeAssistantClient.normalize("[fe80::1]:8123").absoluteString == "http://[fe80::1]:8123")
    }

    @Test func rejectsNonsense() {
        #expect(throws: HomeServiceError.self) { try HomeAssistantClient.normalize("   ") }
        #expect(throws: HomeServiceError.self) { try HomeAssistantClient.normalize("ftp://homeassistant.local") }
        #expect(throws: HomeServiceError.self) { try HomeAssistantClient.normalize("http://") }
        #expect(throws: HomeServiceError.self) { try HomeAssistantClient.normalize("http://my house") }
    }

    @Test func tokenPageAndWebSocketURL() throws {
        let url = try HomeAssistantClient.normalize("homeassistant.local")
        #expect(HomeAssistantClient.tokenPage(for: url).absoluteString == "http://homeassistant.local:8123/profile/security")
        #expect(HAMapping.websocketURL(for: url).absoluteString == "ws://homeassistant.local:8123/api/websocket")
        #expect(HAMapping.websocketURL(for: URL(string: "https://casa.ui.nabu.casa")!).absoluteString
            == "wss://casa.ui.nabu.casa/api/websocket")
    }

    @Test func snapshotRequestCarriesBearer() {
        let request = HAMapping.snapshotRequest(server: URL(string: "http://h.local:8123")!, camera: "camera.puerta", token: "T")
        #expect(request.url?.absoluteString == "http://h.local:8123/api/camera_proxy/camera.puerta")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer T")
        #expect(request.timeoutInterval == 10)
    }
}

@Suite struct HomeAssistantMappingTests {
    @Test func backoffDoublesUpToAMinute() {
        #expect((0...8).map { HAMapping.backoffDelay(attempt: $0) } == [1, 2, 4, 8, 16, 32, 60, 60, 60])
        #expect(HAMapping.backoffDelay(attempt: 1000) == 60)
        #expect(HAMapping.backoffDelay(attempt: -3) == 1)
    }

    @Test func colorTemperatureLooksRight() {
        let warm = HAMapping.colorTemperatureRGB(kelvin: 2700)
        #expect(warm.red == 1)
        #expect(warm.green > 0.6 && warm.green < 0.7)
        #expect(warm.blue > 0.3 && warm.blue < 0.4)
        let daylight = HAMapping.colorTemperatureRGB(kelvin: 6600)
        #expect(daylight.red > 0.95 && daylight.green > 0.95 && daylight.blue == 1)
        let cold = HAMapping.colorTemperatureRGB(kelvin: 10000)
        #expect(cold.blue == 1 && cold.red < 0.85)
        let candle = HAMapping.colorTemperatureRGB(kelvin: 1500)
        #expect(candle.blue == 0 && candle.red == 1)
        for kelvin in stride(from: 1000.0, through: 40000, by: 500) {
            let rgb = HAMapping.colorTemperatureRGB(kelvin: kelvin)
            #expect([rgb.red, rgb.green, rgb.blue].allSatisfy { $0 >= 0 && $0 <= 1 })
        }
    }

    @Test func displayValueUsesLocale() {
        #expect(HAMapping.displayValue("21.5", unit: "°C", locale: Locale(identifier: "es_ES")) == "21,5 °C")
        #expect(HAMapping.displayValue("21.5", unit: "°C", locale: Locale(identifier: "en_US")) == "21.5 °C")
        #expect(HAMapping.displayValue("40", unit: "%", locale: Locale(identifier: "en_US")) == "40 %")
        #expect(HAMapping.displayValue("sunny", unit: nil) == "sunny")
    }

    @Test func kindsCoverEveryDomain() {
        #expect(HAMapping.kind(domain: "input_boolean") == .switchable)
        #expect(HAMapping.kind(domain: "binary_sensor") == .binarySensor)
        #expect(HAMapping.kind(domain: "zone") == .other)
        #expect(HAMapping.kind(domain: "person") == .other)
        #expect(HAMapping.kind(domain: "media_player") == .other)
        #expect(HAMapping.isDangerous(domain: "alarm_control_panel", deviceClass: nil))
        #expect(HAMapping.isDangerous(domain: "cover", deviceClass: "gate"))
        #expect(!HAMapping.isDangerous(domain: "cover", deviceClass: "shutter"))
    }

    @Test func lightCapabilitiesFromColorModes() {
        func caps(_ modes: [JSONValue]) -> HomeCapabilities {
            HAMapping.capabilities(domain: "light", attributes: ["supported_color_modes": .array(modes)])
        }
        #expect(caps(["onoff"]) == [.toggle])
        #expect(caps(["brightness"]) == [.toggle, .brightness])
        #expect(caps(["color_temp"]) == [.toggle, .brightness, .colorTemperature])
        #expect(caps(["color_temp", "hs"]) == [.toggle, .brightness, .colorTemperature, .color])
        #expect(caps(["rgbww"]) == [.toggle, .brightness, .color])
    }

    @Test func lightStateColours() {
        let off = HAMapping.entityState(domain: "light", state: HAState(state: "off", attributes: ["rgb_color": [255, 0, 0]]))
        #expect(off.isOn == false && off.color == nil && off.brightness == nil)
        let kelvin = HAMapping.entityState(domain: "light", state: HAState(state: "on", attributes: ["color_temp_kelvin": 4000]))
        #expect(kelvin.color == HAMapping.colorTemperatureRGB(kelvin: 4000))
        let plain = HAMapping.entityState(domain: "light", state: HAState(state: "on", attributes: [:]))
        #expect(plain.color == HAMapping.colorTemperatureRGB(kelvin: 2700))
        let unavailable = HAMapping.entityState(domain: "switch", state: HAState(state: "unavailable", attributes: [:]))
        #expect(!unavailable.isAvailable)
        let unknownSensor = HAMapping.entityState(domain: "sensor", state: HAState(state: "unknown", attributes: ["unit_of_measurement": "W"]))
        #expect(!unknownSensor.isAvailable && unknownSensor.displayValue == nil)
        let scene = HAMapping.entityState(domain: "scene", state: HAState(state: "unknown", attributes: [:]))
        #expect(scene.isAvailable && scene.isOn == nil)
        let closing = HAMapping.entityState(domain: "cover", state: HAState(state: "opening", attributes: ["current_position": 40]))
        #expect(closing.isOn == true && closing.position == 0.4)
    }

    @Test func diffsAddChangeAndRemove() {
        var states: [String: HAState] = [:]
        let added = HAMapping.apply(diff: ["a": ["light.salon": ["s": "on", "a": ["brightness": 10, "rgb_color": [1, 2, 3]], "lc": 100]]],
                                    to: &states)
        #expect(added.changed == ["light.salon"])
        #expect(states["light.salon"]?.lastChanged == Date(timeIntervalSince1970: 100))

        let changed = HAMapping.apply(diff: ["c": ["light.salon": ["+": ["s": "off", "a": ["brightness": 0], "lc": 200],
                                                                   "-": ["a": ["rgb_color"]]]]], to: &states)
        #expect(changed.changed == ["light.salon"])
        #expect(states["light.salon"]?.state == "off")
        #expect(states["light.salon"]?.attributes["brightness"] == 0)
        #expect(states["light.salon"]?.attributes["rgb_color"] == nil)
        #expect(states["light.salon"]?.lastChanged == Date(timeIntervalSince1970: 200))

        let removed = HAMapping.apply(diff: ["r": ["light.salon"]], to: &states)
        #expect(removed.changed == ["light.salon"])
        #expect(states["light.salon"]?.state == "unavailable")
    }

    @Test func diffTriggers() {
        var states: [String: HAState] = [:]
        let initial = HAMapping.apply(diff: ["a": ["event.timbre": ["s": "2026-10-15T08:00:00.000+00:00", "a": [:], "lc": 1],
                                                   "binary_sensor.puerta": ["s": "on", "a": [:], "lc": 1]]], to: &states)
        #expect(initial.triggered.isEmpty)
        let now = HAMapping.parseISODate("2026-10-15T09:30:10Z")!
        let ring = HAMapping.apply(diff: ["c": ["event.timbre": ["+": ["s": "2026-10-15T09:30:00.250+00:00", "lc": 5]],
                                               "binary_sensor.puerta": ["+": ["s": "off", "lc": 5]]]], to: &states, now: now)
        #expect(ring.triggered == ["event.timbre": HAMapping.parseISODate("2026-10-15T09:30:00.250+00:00")!])
        let open = HAMapping.apply(diff: ["c": ["binary_sensor.puerta": ["+": ["s": "on", "lc": 9]]]], to: &states)
        #expect(open.triggered == ["binary_sensor.puerta": Date(timeIntervalSince1970: 9)])
        let attributesOnly = HAMapping.apply(diff: ["c": ["event.timbre": ["+": ["a": ["event_type": "ring"]]]]], to: &states)
        #expect(attributesOnly.triggered.isEmpty)
    }

    @Test func noPhantomDoorbell() {
        let now = HAMapping.parseISODate("2026-10-15T12:00:00Z")!
        var states: [String: HAState] = [
            "event.timbre": HAState(state: "unknown", attributes: [:]),
            "event.otro": HAState(state: "unavailable", attributes: [:]),
            "binary_sensor.puerta": HAState(state: "unavailable", attributes: [:]),
        ]
        // unavailable → timestamp / on: the integration came back, nobody pressed anything.
        let back = HAMapping.apply(diff: ["c": ["event.otro": ["+": ["s": "2026-10-15T11:59:59Z"]],
                                               "binary_sensor.puerta": ["+": ["s": "on"]]]], to: &states, now: now)
        #expect(back.triggered.isEmpty)
        // A timestamp older than 30 s is a replay.
        let stale = HAMapping.apply(diff: ["c": ["event.otro": ["+": ["s": "2026-10-15T11:59:00Z"]]]], to: &states, now: now)
        #expect(stale.triggered.isEmpty)
        // unknown → fresh timestamp is a real first press.
        let first = HAMapping.apply(diff: ["c": ["event.timbre": ["+": ["s": "2026-10-15T11:59:45Z"]]]], to: &states, now: now)
        #expect(first.triggered == ["event.timbre": HAMapping.parseISODate("2026-10-15T11:59:45Z")!])
    }

    @Test func serviceCalls() {
        let light = HomeEntityID(provider: "ha", serverID: "S", localID: "light.salon")
        let cover = HomeEntityID(provider: "ha", serverID: "S", localID: "cover.garaje")
        let scene = HomeEntityID(provider: "ha", serverID: "S", localID: "scene.peli")
        typealias Call = HAMapping.ServiceCall
        #expect(HAMapping.serviceCall(for: .toggle(light)) == Call(domain: "light", service: "toggle"))
        #expect(HAMapping.serviceCall(for: .setBrightness(light, 0.004)) == Call(domain: "light", service: "turn_on", data: ["brightness_pct": 1]))
        #expect(HAMapping.serviceCall(for: .setBrightness(light, 1.4)) == Call(domain: "light", service: "turn_on", data: ["brightness_pct": 100]))
        #expect(HAMapping.serviceCall(for: .setBrightness(light, 0)) == Call(domain: "light", service: "turn_off"))
        #expect(HAMapping.serviceCall(for: .toggle(cover)) == Call(domain: "cover", service: "toggle"))
        #expect(HAMapping.serviceCall(for: .stop(cover)) == Call(domain: "cover", service: "stop_cover"))
        #expect(HAMapping.serviceCall(for: .setPosition(cover, 0.333)) == Call(domain: "cover", service: "set_cover_position", data: ["position": 33]))
        #expect(HAMapping.serviceCall(for: .activate(scene)) == Call(domain: "scene", service: "turn_on"))
        #expect(HAMapping.serviceCall(for: .activate(light)) == nil)
        #expect(HAMapping.serviceCall(for: .setPosition(light, 1)) == nil)
    }

    @Test func detectsLocalNetworkDenial() {
        let path = NSError(domain: NSURLErrorDomain, code: -1009,
                           userInfo: ["_NSURLErrorNWPathKey": "unsatisfied (Local network prohibited), interface: en0"])
        #expect(HAMapping.isLocalNetworkDenied(path))
        let wrapped = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: [NSUnderlyingErrorKey: path])
        #expect(HAMapping.isLocalNetworkDenied(wrapped))
        #expect(!HAMapping.isLocalNetworkDenied(URLError(.cannotFindHost)))
    }

    @Test func trustDelegateRefusesRedirects() async {
        let delegate = HomeTrustDelegate(pinnedSHA256: nil)
        let url = URL(string: "http://h.local:8123/api/camera_proxy/camera.x")!
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://evil.example"])!
        let next = await delegate.urlSession(session, task: session.dataTask(with: url), willPerformHTTPRedirection: response,
                                             newRequest: URLRequest(url: URL(string: "https://evil.example")!))
        #expect(next == nil)
    }

    @Test func fingerprintIsLowercaseHex() {
        #expect(HomeTrustDelegate.sha256Hex(Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(HomeTrustDelegate(pinnedSHA256: "AB").pinnedSHA256 == "ab")
    }
}

@Suite struct HomeInsecureRemoteTests {
    @Test func atsRefusalIsRecognisedAndNotRetried() {
        let ats = NSError(domain: NSURLErrorDomain, code: NSURLErrorAppTransportSecurityRequiresSecureConnection)
        let wrapped = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: [NSUnderlyingErrorKey: ats])
        #expect(HAMapping.isInsecureRemote(ats))
        #expect(HAMapping.isInsecureRemote(wrapped))
        #expect(!HAMapping.isInsecureRemote(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)))
        #expect(!HAFailure.insecureRemote.isRetryable)
    }
}
