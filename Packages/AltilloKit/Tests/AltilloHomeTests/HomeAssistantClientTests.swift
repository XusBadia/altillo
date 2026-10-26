import Foundation
import Testing
@testable import AltilloHome

@MainActor
@Suite struct HomeAssistantClientTests {
    // MARK: Handshake and Keychain

    @Test func connectAuthenticatesLoadsAndSavesToken() async throws {
        let harness = Harness()
        let log = EventLog(harness.client.events())
        try await harness.connect()
        let client = harness.client!

        #expect(client.connection == .connected(serverName: "Casa Xus", version: "2026.10.1"))
        #expect(client.config?.name == "Casa Xus")
        #expect(harness.store.tokens == ["S1": "good-token"])
        #expect(harness.socket.url.absoluteString == "ws://homeassistant.local:8123/api/websocket")

        let sent = await harness.socket.sent
        #expect(sent.first == ["type": "auth", "access_token": "good-token"])
        #expect(sent.compactMap { $0["type"]?.string } == [
            "auth", "get_config", "config/area_registry/list", "config/device_registry/list", "config/entity_registry/list",
            "get_states", "subscribe_events", "subscribe_events", "subscribe_events",
        ])
        #expect(sent.dropFirst().compactMap { $0["id"]?.int } == Array(1...8))
        #expect(Set(sent.compactMap { $0["event_type"]?.string })
            == ["area_registry_updated", "entity_registry_updated", "device_registry_updated"])
        #expect(await eventually { log.events.contains(.catalogChanged) && log.events.contains(.connectionChanged) })
    }

    @Test func invalidTokenIsUnauthorizedAndNotSaved() async throws {
        let harness = Harness()
        await #expect(throws: HomeServiceError(HAFailure.unauthorized.message)) {
            try await harness.client.connect(harness.config, token: "wrong")
        }
        #expect(harness.client.connection == .unauthorized)
        #expect(harness.store.tokens.isEmpty)
        #expect(await harness.socket.sent.count == 1)
    }

    @Test func keychainFailureLeavesNothingBehind() async throws {
        let harness = Harness()
        harness.store.failSaves = true
        await #expect(throws: HomeServiceError.self) { try await harness.connect() }
        #expect(harness.client.connection == .notConfigured)
        #expect(await eventually { await harness.socket.isClosed })
    }

    @Test func resumeUsesStoredToken() async throws {
        let empty = Harness()
        empty.client.resume(empty.config)
        #expect(empty.client.connection == .unauthorized)
        #expect(empty.sockets.isEmpty)

        let harness = Harness(tokens: ["S1": "good-token"])
        harness.client.resume(harness.config)
        #expect(await eventually { harness.client.connection == .connected(serverName: "Casa Xus", version: "2026.10.1") })
        #expect(harness.client.entities.count == 15)
    }

    @Test func disconnectForgetDeletesToken() async throws {
        let harness = Harness()
        try await harness.connect()
        harness.client.disconnect(forget: false)
        #expect(harness.store.tokens["S1"] == "good-token")
        #expect(harness.client.connection == .notConfigured)
        #expect(await eventually { await harness.socket.isClosed })

        harness.client.resume(harness.config)
        #expect(await eventually { if case .connected = harness.client.connection { true } else { false } })
        harness.client.disconnect(forget: true)
        #expect(harness.store.tokens.isEmpty)
        #expect(harness.client.config == nil && harness.client.entities.isEmpty)
    }

    @Test func untrustedCertificateNeedsTrustThenPins() async throws {
        let harness = Harness()
        harness.untrustedFingerprint = "abc123"
        await #expect(throws: HomeServiceError.self) { try await harness.connect() }
        #expect(harness.client.connection == .needsTrust(fingerprintSHA256: "abc123"))
        #expect(harness.store.tokens.isEmpty)

        let updated = try await harness.client.trustCertificate("ABC123")
        #expect(updated.pinnedCertificateSHA256 == "abc123")
        #expect(updated.name == "Casa Xus")
        #expect(harness.client.connection == .connected(serverName: "Casa Xus", version: "2026.10.1"))
        #expect(harness.socket.delegate.pinnedSHA256 == "abc123")
        #expect(harness.store.tokens == ["S1": "good-token"])
        #expect(harness.client.config?.pinnedCertificateSHA256 == "abc123")
    }

    @Test func trustWithoutPendingServerThrows() async {
        let harness = Harness()
        await #expect(throws: HomeServiceError.self) { _ = try await harness.client.trustCertificate("ab") }
    }

    @Test func trustAfterResumeKeepsStoredToken() async throws {
        let harness = Harness(tokens: ["S1": "good-token"])
        harness.untrustedFingerprint = "ff00"
        harness.client.resume(harness.config)
        #expect(await eventually { harness.client.connection == .needsTrust(fingerprintSHA256: "ff00") })
        harness.store.failSaves = true   // must not try to save again
        let updated = try await harness.client.trustCertificate("ff00")
        #expect(updated.pinnedCertificateSHA256 == "ff00")
        #expect(harness.store.tokens == ["S1": "good-token"])
    }

    @Test func disconnectMidConnectClosesTheSocket() async throws {
        let harness = Harness()
        harness.server.silentOn = "get_states"
        let client = harness.client!
        let connecting = Task { try await client.connect(harness.config, token: "good-token") }
        #expect(await eventually { await harness.sockets.first?.sent(type: "get_states").count == 1 })
        client.disconnect(forget: true)
        #expect(await eventually { await harness.socket.isClosed })
        await #expect(throws: (any Error).self) { try await connecting.value }
        #expect(client.connection == .notConfigured)
        #expect(harness.store.tokens.isEmpty)
        #expect(client.entities.isEmpty)
        #expect(await harness.socket.sent(type: "subscribe_events").isEmpty)
    }

    @Test func unreachableServerThrowsFriendlyError() async throws {
        let harness = Harness()
        harness.server.locationName = "x"
        let failing = HomeAssistantClient(tokens: harness.store, socketFactory: { url, delegate in
            FakeSocket(url: url, delegate: delegate, server: nil, failure: URLError(.cannotConnectToHost))
        }, timing: .test)
        await #expect(throws: HomeServiceError(HomeStrings.notFound)) { try await failing.connect(harness.config, token: "t") }
        #expect(failing.connection == .unreachable(reason: HomeStrings.notFound))
    }

    // MARK: Catalogue

    @Test func buildsCatalogue() async throws {
        let harness = Harness()
        try await harness.connect()
        let client = harness.client!
        func entity(_ id: String) throws -> HomeEntity { try #require(client.entities[harness.id(id)]) }

        #expect(client.areas == [HomeArea(id: "salon", name: "Salón"), HomeArea(id: "despacho", name: "Despacho")])

        let salon = try entity("light.salon")
        #expect(salon.name == "Luz del salón")            // friendly_name beats original_name
        #expect(salon.areaID == "salon")                  // from its device
        #expect(salon.kind == .light)
        #expect(salon.capabilities == [.toggle, .brightness, .colorTemperature, .color])
        #expect(salon.state.isOn == true)
        #expect(abs((salon.state.brightness ?? 0) - 128.0 / 255) < 0.0001)
        #expect(salon.state.color == HomeRGB(red: 1, green: 167.0 / 255, blue: 87.0 / 255))
        #expect(salon.state.lastChanged == HAMapping.parseISODate("2026-10-15T08:00:00.000+00:00"))

        let despacho = try entity("light.despacho")
        #expect(despacho.name == "Flexo")                 // registry name wins
        #expect(despacho.areaID == "despacho")            // entity area beats device area
        #expect(despacho.capabilities == [.toggle])
        #expect(despacho.state.isOn == false && despacho.state.color == nil)
        // Registry rows whose hidden_by / disabled_by / entity_category are JSON null are ordinary entities.
        #expect(!salon.isTechnical && !despacho.isTechnical)

        let vieja = try entity("light.vieja")
        #expect(vieja.isTechnical && !vieja.state.isAvailable && vieja.name == "Vieja")

        let cafetera = try entity("switch.cafetera")
        #expect(cafetera.kind == .switchable && cafetera.areaID == nil && cafetera.capabilities == [.toggle] && !cafetera.isTechnical)

        let invitados = try entity("input_boolean.invitados")
        #expect(invitados.kind == .switchable && invitados.isTechnical && invitados.name == "Invitados")

        let temperatura = try entity("sensor.temperatura")
        #expect(temperatura.deviceClass == "temperature")
        #expect(temperatura.state.displayValue == HAMapping.displayValue("21.5", unit: "°C"))
        #expect(try entity("sensor.wifi").isTechnical)

        let garaje = try entity("cover.garaje")
        #expect(garaje.isDangerous && garaje.capabilities == [.openClose, .position] && garaje.state.position == 0)
        #expect(garaje.state.isOn == false)
        let persiana = try entity("cover.persiana")
        #expect(!persiana.isDangerous && persiana.capabilities == [.openClose] && persiana.state.isOn == true)

        #expect(try entity("scene.peli").capabilities == [.activate])
        #expect(try entity("scene.peli").state.isAvailable)
        #expect(try entity("script.buenas_noches").kind == .script)
        #expect(try entity("lock.puerta").isDangerous)
        #expect(try entity("binary_sensor.puerta").kind == .binarySensor)
        #expect(try entity("binary_sensor.puerta").state.displayValue == nil)
        #expect(try entity("event.timbre").kind == .event)

        let zone = try entity("zone.home")
        #expect(zone.kind == .other && zone.name == "Home" && zone.areaID == nil)
    }

    @Test func registryChangeRefetchesCatalogue() async throws {
        let harness = Harness()
        try await harness.connect()
        let log = EventLog(harness.client.events())
        let registryID = try #require(await harness.socket.sent(type: "subscribe_events")
            .first { $0["event_type"] == "area_registry_updated" }?["id"])
        for _ in 0..<3 { try await harness.socket.push(["id": registryID, "type": "event", "event": ["event_type": "area_registry_updated"]]) }
        #expect(await eventually { log.catalogChanges == 1 })
        #expect(await harness.socket.sent(type: "get_states").count == 2)   // debounced: one refetch for three events
        #expect(await harness.socket.sent(type: "config/area_registry/list").count == 2)
    }

    // MARK: Watching and diffs

    @Test func watchSubscribesAndResubscribes() async throws {
        let harness = Harness()
        try await harness.connect()
        let log = EventLog(harness.client.events())
        harness.client.watch([harness.id("light.salon"), harness.id("event.timbre"),
                              HomeEntityID(provider: "ha", serverID: "OTHER", localID: "light.x")])
        #expect(await eventually { await harness.socket.sent(type: "subscribe_entities").count == 1 })
        #expect(await harness.last("subscribe_entities") == ["type": "subscribe_entities", "entity_ids": ["event.timbre", "light.salon"]])
        let firstID = try #require(await harness.socket.sent(type: "subscribe_entities").first?["id"])
        #expect(await eventually { log.changedIDs == [harness.id("light.salon"), harness.id("event.timbre")] })
        #expect(log.triggered.isEmpty)

        harness.client.watch([harness.id("cover.garaje")])
        #expect(await eventually { await harness.socket.sent(type: "subscribe_entities").count == 2 })
        #expect(await harness.last("unsubscribe_events") == ["type": "unsubscribe_events", "subscription": firstID])
        #expect(await harness.last("subscribe_entities") == ["type": "subscribe_entities", "entity_ids": ["cover.garaje"]])

        harness.client.watch([])
        #expect(await eventually { await harness.socket.sent(type: "unsubscribe_events").count == 2 })
        #expect(await harness.socket.sent(type: "subscribe_entities").count == 2)
    }

    @Test func appliesDiffsAndTriggers() async throws {
        let harness = Harness()
        harness.client.now = { HAMapping.parseISODate("2026-10-15T10:00:05Z")! }
        try await harness.connect()
        let log = EventLog(harness.client.events())
        let salon = harness.id("light.salon"), timbre = harness.id("event.timbre"), puerta = harness.id("binary_sensor.puerta")
        harness.client.watch([salon, timbre, puerta])
        #expect(await eventually { log.changedIDs.count == 3 })
        let subscription = try #require(await harness.socket.sent(type: "subscribe_entities").last?["id"])

        try await harness.socket.push(["id": subscription, "type": "event", "event": [
            "c": ["light.salon": ["+": ["a": ["brightness": 255, "color_temp_kelvin": 6500], "lc": 1_760_600_000],
                                  "-": ["a": ["rgb_color"]]]],
        ]])
        #expect(await eventually { harness.client.entities[salon]?.state.brightness == 1 })
        #expect(harness.client.entities[salon]?.state.color == HAMapping.colorTemperatureRGB(kelvin: 6500))
        #expect(harness.client.entities[salon]?.state.lastChanged == Date(timeIntervalSince1970: 1_760_600_000))

        try await harness.socket.push(["id": subscription, "type": "event", "event": [
            "c": ["event.timbre": ["+": ["s": "2026-10-15T10:00:00.000+00:00", "a": ["event_type": "ring"]]],
                  "binary_sensor.puerta": ["+": ["s": "on"]]],
        ]])
        #expect(await eventually { log.triggered.count == 2 })
        let fired = Dictionary(uniqueKeysWithValues: log.triggered.map { ($0.0, $0.1) })
        #expect(fired[timbre] == HAMapping.parseISODate("2026-10-15T10:00:00Z"))
        #expect(fired[puerta] != nil)
        #expect(harness.client.entities[puerta]?.state.isOn == true)

        try await harness.socket.push(["id": subscription, "type": "event", "event": ["r": ["light.salon"]]])
        #expect(await eventually { harness.client.entities[salon]?.state.isAvailable == false })

        // Events from an old or unknown subscription are ignored.
        try await harness.socket.push(["id": 999, "type": "event", "event": ["c": ["binary_sensor.puerta": ["+": ["s": "off"]]]]])
        try await Task.sleep(for: .milliseconds(30))
        #expect(harness.client.entities[puerta]?.state.isOn == true)
    }

    // MARK: Commands

    @Test func performSendsExactServiceCalls() async throws {
        let harness = Harness()
        try await harness.connect()
        let client = harness.client!
        func expectCall(_ command: HomeCommand, _ expected: JSONValue) async throws {
            try await client.perform(command)
            #expect(await harness.last("call_service") == expected)
        }
        try await expectCall(.toggle(harness.id("light.salon")),
                             ["type": "call_service", "domain": "light", "service": "toggle", "target": ["entity_id": "light.salon"]])
        try await expectCall(.turnOn(harness.id("input_boolean.invitados")),
                             ["type": "call_service", "domain": "input_boolean", "service": "turn_on",
                              "target": ["entity_id": "input_boolean.invitados"]])
        try await expectCall(.setBrightness(harness.id("light.salon"), 0.456),
                             ["type": "call_service", "domain": "light", "service": "turn_on",
                              "service_data": ["brightness_pct": 46], "target": ["entity_id": "light.salon"]])
        try await expectCall(.setBrightness(harness.id("light.salon"), 0),
                             ["type": "call_service", "domain": "light", "service": "turn_off", "target": ["entity_id": "light.salon"]])
        try await expectCall(.setColor(harness.id("light.salon"), HomeRGB(red: 1, green: 0, blue: 0.5)),
                             ["type": "call_service", "domain": "light", "service": "turn_on",
                              "service_data": ["rgb_color": [255, 0, 128]], "target": ["entity_id": "light.salon"]])
        try await expectCall(.setColorTemperature(harness.id("light.salon"), kelvin: 4000),
                             ["type": "call_service", "domain": "light", "service": "turn_on",
                              "service_data": ["color_temp_kelvin": 4000], "target": ["entity_id": "light.salon"]])
        try await expectCall(.setPosition(harness.id("cover.garaje"), 0.5),
                             ["type": "call_service", "domain": "cover", "service": "set_cover_position",
                              "service_data": ["position": 50], "target": ["entity_id": "cover.garaje"]])
        try await expectCall(.open(harness.id("cover.persiana")),
                             ["type": "call_service", "domain": "cover", "service": "open_cover", "target": ["entity_id": "cover.persiana"]])
        try await expectCall(.activate(harness.id("script.buenas_noches")),
                             ["type": "call_service", "domain": "script", "service": "turn_on",
                              "target": ["entity_id": "script.buenas_noches"]])

        // The wire format really is integers, not 46.0.
        let text = try #require(await harness.socket.sent(type: "call_service").dropFirst(2).first).encodedString()
        #expect(text.contains(#""brightness_pct":46"#))
    }

    @Test func performErrors() async throws {
        let harness = Harness()
        harness.server.failingEntity = "cover.garaje"
        let client = harness.client!
        await #expect(throws: HomeServiceError(HAFailure.notConnected.message)) { try await client.perform(.toggle(harness.id("light.salon"))) }
        try await harness.connect()
        do {
            try await client.perform(.close(harness.id("cover.garaje")))
            Issue.record("Expected an error")
        } catch let error as HomeServiceError {
            #expect(error.message.contains("Nope, it's jammed"))
        }
        await #expect(throws: HomeServiceError(HomeStrings.unsupported)) { try await client.perform(.activate(harness.id("light.salon"))) }
        await #expect(throws: HomeServiceError(HomeStrings.otherServer)) {
            try await client.perform(.toggle(HomeEntityID(provider: "ha", serverID: "OTHER", localID: "light.salon")))
        }
    }

    // MARK: Lifecycle

    @Test func reconnectsAndResubscribesAfterDrop() async throws {
        let harness = Harness()
        try await harness.connect()
        harness.client.watch([harness.id("light.salon")])
        #expect(await eventually { await harness.socket.sent(type: "subscribe_entities").count == 1 })
        let log = EventLog(harness.client.events())

        let first = harness.socket
        await first.serverClose()
        #expect(await eventually { harness.sockets.count == 2 })
        #expect(await eventually { if case .connected = harness.client.connection { true } else { false } })
        #expect(log.events.contains(.connectionChanged))
        #expect(await eventually { await harness.socket.sent(type: "subscribe_entities").count == 1 })
        #expect(await harness.last("subscribe_entities") == ["type": "subscribe_entities", "entity_ids": ["light.salon"]])
        try await harness.client.perform(.toggle(harness.id("light.salon")))
        #expect(await first.sent(type: "call_service").isEmpty)
    }

    @Test func badTokenOnReconnectStops() async throws {
        let harness = Harness()
        try await harness.connect()
        harness.server.token = "rotated"
        await harness.socket.serverClose()
        #expect(await eventually { harness.client.connection == .unauthorized })
        try await Task.sleep(for: .milliseconds(80))
        #expect(harness.sockets.count == 2)
    }

    @Test func keepalivePingsAndDropsADeadConnection() async throws {
        var timing = HomeTiming.test
        timing.ping = .milliseconds(20)
        timing.pong = .milliseconds(30)
        let harness = Harness(timing: timing)
        try await harness.connect()
        #expect(await eventually { await harness.socket.sent(type: "ping").count >= 2 })
        #expect(harness.sockets.count == 1)
        #expect(await harness.last("ping") == ["type": "ping"])

        harness.server.answersPing = false
        await harness.socket.serverClose()   // reconnect so the new socket uses the silent server
        #expect(await eventually { harness.sockets.count == 2 })
        let silent = harness.socket
        #expect(await eventually { await silent.isClosed })   // no pong → closed → reconnect
        #expect(await eventually { harness.sockets.count == 3 })
    }

    @Test func eventsStreamsAreIndependent() async throws {
        let harness = Harness()
        let a = EventLog(harness.client.events())
        let b = EventLog(harness.client.events())
        try await harness.connect()
        #expect(await eventually { a.catalogChanges == 1 && b.catalogChanges == 1 })
    }

    @Test func sleepPausesAndWakeReconnects() async throws {
        let harness = Harness()
        try await harness.connect()
        harness.client.pause()
        #expect(await eventually { await harness.socket.isClosed })
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.sockets.count == 1)
        harness.client.wake()
        #expect(await eventually { harness.sockets.count == 2 })
        #expect(await eventually { if case .connected = harness.client.connection { true } else { false } })
    }
}
