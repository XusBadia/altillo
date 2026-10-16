import Foundation
import Testing
@testable import AltilloHome

struct HomeDiscoveryTests {
    private typealias Fetched = HomeDiscovery.Fetched

    // MARK: TXT records

    @Test func prefersInternalURLAndKeepsTheInstanceIdentity() throws {
        let server = try #require(HomeDiscovery.server(
            txt: ["uuid": "abc123", "location_name": "Casa", "version": "2026.10.1",
                  "internal_url": "http://192.168.1.10:8123/", "external_url": "https://casa.ui.nabu.casa",
                  "base_url": "http://old:8123"],
            serviceName: "Casa", resolved: URL(string: "http://10.0.0.2:8123")
        ))
        #expect(server.url.absoluteString == "http://192.168.1.10:8123")
        #expect(server.name == "Casa")
        #expect(server.uuid == "abc123")
        #expect(server.version == "2026.10.1")
        #expect(server.address == "192.168.1.10:8123")
        #expect(server.id == "abc123")
    }

    @Test func fallsBackToBaseURLThenResolvedThenExternal() throws {
        let base = try #require(HomeDiscovery.server(txt: ["base_url": "http://HomeAssistant.local:8123"],
                                                     serviceName: "Home", resolved: nil))
        #expect(base.url.absoluteString == "http://homeassistant.local:8123")
        #expect(base.uuid == nil)

        let resolved = try #require(HomeDiscovery.server(txt: ["external_url": "https://x.ui.nabu.casa"], serviceName: "Home",
                                                         resolved: URL(string: "http://192.168.1.5:8123")))
        #expect(resolved.url.absoluteString == "http://192.168.1.5:8123")

        let external = try #require(HomeDiscovery.server(txt: ["external_url": "https://x.ui.nabu.casa/"], serviceName: "Home",
                                                         resolved: nil))
        #expect(external.url.absoluteString == "https://x.ui.nabu.casa")

        #expect(HomeDiscovery.server(txt: ["internal_url": "", "location_name": "Casa"], serviceName: "Casa", resolved: nil) == nil)
        #expect(HomeDiscovery.server(txt: ["internal_url": "ftp://nope"], serviceName: "Casa", resolved: nil) == nil)
    }

    @Test func nameFallsBackToTheServiceName() throws {
        let server = try #require(HomeDiscovery.server(txt: ["location_name": "  ", "uuid": ""], serviceName: "Piso",
                                                       resolved: URL(string: "http://10.0.0.3:8123")))
        #expect(server.name == "Piso")
        #expect(server.uuid == nil)
    }

    // MARK: Dedupe

    @Test func mergeDedupesByUUIDThenByAddress() {
        let url = URL(string: "http://192.168.1.10:8123")!
        let bonjour = [
            HomeDiscoveredServer(name: "Casa", url: url, uuid: "a"),
            HomeDiscoveredServer(name: "Casa (IPv6)", url: URL(string: "http://[fe80::1]:8123")!, uuid: "a"),
            HomeDiscoveredServer(name: "Same address", url: URL(string: "http://192.168.1.10:8123/")!, uuid: "b"),
            HomeDiscoveredServer(name: "Playa", url: URL(string: "http://192.168.1.20:8123")!, uuid: "c"),
        ]
        let probe = HomeDiscoveredServer(name: "Home Assistant", url: HomeDiscovery.defaultLocalURL)
        let merged = HomeDiscovery.merge(bonjour: bonjour, probe: probe)
        #expect(merged.map(\.name) == ["Casa", "Playa"])
        #expect(HomeDiscovery.merge(bonjour: [], probe: probe) == [probe])
        #expect(HomeDiscovery.merge(bonjour: [], probe: nil).isEmpty)
    }

    @Test func addressKeysUseDefaultPorts() {
        #expect(HomeDiscovery.key(for: URL(string: "https://Casa.example")!) == HomeDiscovery.key(for: URL(string: "https://casa.example:443/")!))
        #expect(HomeDiscovery.key(for: URL(string: "http://casa.local")!) != HomeDiscovery.key(for: URL(string: "http://casa.local:8123")!))
    }

    // MARK: Validate classification

    @Test func onboardingListMeansHomeAssistant() {
        let done = Fetched(status: 200, body: Data(#"[{"step":"user","done":true},{"step":"core_config","done":true}]"#.utf8))
        #expect(HomeDiscovery.classify(onboarding: done, manifest: Fetched(status: 200), untrustedFingerprint: nil)
            == .homeAssistant(version: nil, needsOnboarding: false))
        let fresh = Fetched(status: 200, body: Data(#"[{"step":"user","done":false}]"#.utf8))
        let probe = HomeDiscovery.classify(onboarding: fresh, manifest: Fetched(status: 404), untrustedFingerprint: nil)
        #expect(probe == .homeAssistant(version: nil, needsOnboarding: true))
        #expect(probe.isHomeAssistant)
        #expect(probe.problem != nil)
    }

    @Test func manifestNameIsTheFallback() {
        let manifest = Fetched(status: 200, body: Data(#"{"name":"Home Assistant","short_name":"Assistant"}"#.utf8))
        #expect(HomeDiscovery.classify(onboarding: Fetched(status: 404), manifest: manifest, untrustedFingerprint: nil)
            == .homeAssistant(version: nil, needsOnboarding: false))
    }

    @Test func otherWebServersAreNotHomeAssistant() {
        let html = Fetched(status: 200, body: Data("<html>router</html>".utf8))
        let otherManifest = Fetched(status: 200, body: Data(#"{"name":"Pi-hole"}"#.utf8))
        #expect(HomeDiscovery.classify(onboarding: html, manifest: otherManifest, untrustedFingerprint: nil) == .notHomeAssistant)
        #expect(HomeDiscovery.classify(onboarding: Fetched(status: 404), manifest: Fetched(status: 404), untrustedFingerprint: nil)
            == .notHomeAssistant)
        // A JSON list that isn't onboarding steps.
        let list = Fetched(status: 200, body: Data("[1,2]".utf8))
        #expect(HomeDiscovery.classify(onboarding: list, manifest: Fetched(status: 404), untrustedFingerprint: nil) == .notHomeAssistant)
    }

    @Test func failuresAreClassified() {
        func failed(_ error: any Error) -> Fetched { Fetched(error: error) }
        let refused = URLError(.cannotConnectToHost)
        #expect(HomeDiscovery.classify(onboarding: failed(refused), manifest: failed(refused), untrustedFingerprint: nil)
            == .unreachable)
        #expect(HomeDiscovery.classify(onboarding: failed(URLError(.serverCertificateUntrusted)),
                                       manifest: failed(URLError(.cancelled)), untrustedFingerprint: "ab12")
            == .needsTrust(fingerprintSHA256: "ab12"))
        let ats = NSError(domain: NSURLErrorDomain, code: NSURLErrorAppTransportSecurityRequiresSecureConnection)
        #expect(HomeDiscovery.classify(onboarding: failed(ats), manifest: failed(ats), untrustedFingerprint: nil) == .insecureRemote)
        let denied = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: "kNWErrorDomainPOSIX", code: 50,
                                          userInfo: [NSLocalizedDescriptionKey: "Local network prohibited"]),
        ])
        #expect(HomeDiscovery.classify(onboarding: failed(denied), manifest: failed(refused), untrustedFingerprint: nil)
            == .localNetworkDenied)
        #expect(HomeServerProbe.unreachable.problem != nil)
    }

    // MARK: Real sockets, no Home Assistant needed

    @Test func validateSaysNotHomeAssistantForAnotherWebServer() async throws {
        // The sign-in's loopback server answers 404 to both probes: a web server that isn't HA.
        let server = HomeLoopbackServer()
        let port = try await server.start()
        defer { server.stop() }
        let probe = await HomeDiscovery().validate(URL(string: "http://127.0.0.1:\(port)")!, timeout: .seconds(2))
        #expect(probe == .notHomeAssistant)
    }

    @Test func validateSaysUnreachableWhenNothingListens() async throws {
        let probe = await HomeDiscovery().validate(URL(string: "http://127.0.0.1:9")!, timeout: .seconds(2))
        #expect(probe == .unreachable)
    }
}

/// Against `script/home-lab.sh up` (http://localhost:8124). Skipped unless ALTILLO_HOME_LAB_TOKEN is set.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ALTILLO_HOME_LAB_TOKEN"] != nil))
struct HomeDiscoveryLabTests {
    @Test func validateRecognisesTheLabServer() async throws {
        let probe = await HomeDiscovery().validate(URL(string: "http://localhost:8124")!)
        guard case .homeAssistant(let version, let needsOnboarding) = probe else {
            Issue.record("not recognised: \(probe)"); return
        }
        #expect(version?.hasPrefix("20") == true)
        #expect(!needsOnboarding)
    }

    /// The lab runs in Docker, so Bonjour and homeassistant.local can't see it; this checks the browse and the probe
    /// finish on time and don't invent servers.
    @Test func discoverFinishesOnTime() async {
        let start = ContinuousClock.now
        let servers = await HomeDiscovery().discover(timeout: .seconds(2))
        #expect(ContinuousClock.now - start < .seconds(5))
        #expect(servers.allSatisfy { $0.url.scheme?.hasPrefix("http") == true })
    }
}
