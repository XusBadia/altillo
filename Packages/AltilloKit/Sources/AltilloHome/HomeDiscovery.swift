import Foundation
import Network
import Synchronization

/// A Home Assistant found on the network (Bonjour) or at homeassistant.local:8123.
public struct HomeDiscoveredServer: Hashable, Sendable, Identifiable {
    /// HA's `location_name` ("Casa"), or "Home Assistant" when it isn't known.
    public var name: String
    /// Where to connect: `internal_url`/`base_url` from the TXT record when present, else the resolved host and port.
    public var url: URL
    /// The instance's stable id (TXT `uuid`), when Bonjour told us.
    public var uuid: String?
    public var version: String?

    public init(name: String, url: URL, uuid: String? = nil, version: String? = nil) {
        self.name = name; self.url = url; self.uuid = uuid; self.version = version
    }

    public var id: String { uuid ?? HomeDiscovery.key(for: url) }
    /// "homeassistant.local:8123", for the row under the name.
    public var address: String {
        guard let host = url.host() else { return url.absoluteString }
        let shown = host.contains(":") ? "[\(host)]" : host
        return url.port.map { "\(shown):\($0)" } ?? shown
    }
}

/// What an address turned out to be, without a token (`GET /api/onboarding` and `/manifest.json`).
public enum HomeServerProbe: Hashable, Sendable {
    /// It's Home Assistant. `needsOnboarding`: its first-run setup isn't finished, so nobody can sign in yet.
    case homeAssistant(version: String?, needsOnboarding: Bool)
    /// Something answers at that address, but not Home Assistant.
    case notHomeAssistant
    case unreachable
    /// A plain http:// address outside the local network: App Transport Security refuses it.
    case insecureRemote
    /// macOS Local Network permission is off for Altillo.
    case localNetworkDenied
    /// https with a certificate the system doesn't trust (self-signed). The fingerprint is what to pin.
    case needsTrust(fingerprintSHA256: String)

    public var isHomeAssistant: Bool {
        if case .homeAssistant = self { return true }
        return false
    }

    /// What to tell the user when this isn't a Home Assistant they can sign in to; nil when it is.
    public var problem: String? {
        switch self {
        case .homeAssistant(_, let needsOnboarding): needsOnboarding ? HomeStrings.needsOnboarding : nil
        case .notHomeAssistant: HomeStrings.notHomeAssistant
        case .unreachable: HomeStrings.notFound
        case .insecureRemote: HomeStrings.insecureRemote
        case .localNetworkDenied: HomeStrings.localNetworkDenied
        case .needsTrust: HomeStrings.needsTrust
        }
    }
}

/// Finds Home Assistant on the local network and checks typed addresses. Nothing here needs a token.
///
/// `discover` browses `_home-assistant._tcp` with `NWBrowser` (this is what shows macOS's Local Network prompt the
/// first time, so call it from a user action) and, in parallel, asks http://homeassistant.local:8123 directly.
public final class HomeDiscovery: Sendable {
    public static let serviceType = "_home-assistant._tcp"
    public static let defaultLocalURL = URL(string: "http://homeassistant.local:8123")!

    private let denied = Mutex(false)

    public init() {}

    /// True when the last `discover` was refused by the Local Network permission.
    public var browsingDenied: Bool { denied.withLock { $0 } }

    /// Every Home Assistant found within `timeout`, Bonjour first, deduplicated by instance id and then by address.
    public func discover(timeout: Duration = .seconds(2)) async -> [HomeDiscoveredServer] {
        async let browsed = BonjourBrowse(type: Self.serviceType).run(timeout: timeout)
        async let probed = probeDefault(timeout: timeout)
        let (bonjour, probe) = await (browsed, probed)
        denied.withLock { $0 = bonjour.denied }
        return Self.merge(bonjour: bonjour.servers, probe: probe)
    }

    /// Checks that `url` is a Home Assistant this Mac can reach, and classifies the failure when it isn't.
    public func validate(_ url: URL, pinnedCertificateSHA256: String? = nil,
                         timeout: Duration = .seconds(4)) async -> HomeServerProbe {
        let delegate = HomeTrustDelegate(pinnedSHA256: pinnedCertificateSHA256)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = timeout.seconds
        configuration.timeoutIntervalForResource = timeout.seconds
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        async let onboarding = Self.fetch(session, url.appending(path: "api/onboarding"), timeout: timeout)
        async let manifest = Self.fetch(session, url.appending(path: "manifest.json"), timeout: timeout)
        let (first, second) = await (onboarding, manifest)
        var probe = Self.classify(onboarding: first, manifest: second, untrustedFingerprint: delegate.untrustedFingerprint)
        if case .homeAssistant(nil, let needsOnboarding) = probe,
           let version = await Self.version(at: url, delegate: delegate, timeout: min(timeout, .seconds(2))) {
            probe = .homeAssistant(version: version, needsOnboarding: needsOnboarding)
        }
        return probe
    }

    private func probeDefault(timeout: Duration) async -> HomeDiscoveredServer? {
        guard case .homeAssistant(let version, _) = await validate(Self.defaultLocalURL, timeout: timeout) else { return nil }
        return HomeDiscoveredServer(name: HomeStrings.homeAssistant, url: Self.defaultLocalURL, version: version)
    }

    // MARK: Pure pieces (tested)

    /// One HTTP answer, or the error that stopped it.
    struct Fetched: Sendable {
        var status: Int?
        var body: Data = Data()
        var error: (any Error)?
    }

    private static func fetch(_ session: URLSession, _ url: URL, timeout: Duration) async -> Fetched {
        var request = URLRequest(url: url, timeoutInterval: timeout.seconds)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            return Fetched(status: (response as? HTTPURLResponse)?.statusCode, body: data)
        } catch {
            return Fetched(error: error)
        }
    }

    /// `/api/onboarding` answers a list of `{step, done}` on every Home Assistant (no token needed); the manifest's
    /// name is the fallback. Any other HTTP answer is "not HA"; no answer at all is classified from the error.
    static func classify(onboarding: Fetched, manifest: Fetched, untrustedFingerprint: String?) -> HomeServerProbe {
        if onboarding.status == 200, let steps = (try? JSONValue.decode(String(decoding: onboarding.body, as: UTF8.self)))?.array,
           steps.allSatisfy({ $0["step"]?.string != nil }) {
            let needsOnboarding = steps.contains { $0["step"]?.string == "user" && $0["done"]?.bool == false }
            return .homeAssistant(version: nil, needsOnboarding: needsOnboarding)
        }
        if manifest.status == 200, let json = try? JSONValue.decode(String(decoding: manifest.body, as: UTF8.self)),
           [json["name"]?.string, json["short_name"]?.string].contains(where: { $0?.contains("Home Assistant") == true }) {
            return .homeAssistant(version: nil, needsOnboarding: false)
        }
        if onboarding.status != nil || manifest.status != nil { return .notHomeAssistant }
        if let untrustedFingerprint { return .needsTrust(fingerprintSHA256: untrustedFingerprint) }
        let errors = [onboarding.error, manifest.error].compactMap(\.self)
        if errors.contains(where: HAMapping.isLocalNetworkDenied) { return .localNetworkDenied }
        if errors.contains(where: HAMapping.isInsecureRemote) { return .insecureRemote }
        return .unreachable
    }

    /// A server from a Bonjour result. `internal_url`, then `base_url` (older HA), then the resolved address, then
    /// `external_url`. Nil when there's no usable address at all.
    static func server(txt: [String: String], serviceName: String, resolved: URL?) -> HomeDiscoveredServer? {
        let candidates = [txt["internal_url"], txt["base_url"]].compactMap { $0.flatMap(origin) }
            + [resolved].compactMap(\.self)
            + [txt["external_url"]].compactMap { $0.flatMap(origin) }
        guard let url = candidates.first else { return nil }
        let name = [txt["location_name"], serviceName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? HomeStrings.homeAssistant
        func nonEmpty(_ value: String?) -> String? { value.flatMap { $0.isEmpty ? nil : $0 } }
        return HomeDiscoveredServer(name: name, url: url, uuid: nonEmpty(txt["uuid"]), version: nonEmpty(txt["version"]))
    }

    /// Scheme, host and port only ("http://192.168.1.10:8123/" → "http://192.168.1.10:8123").
    static func origin(_ text: String) -> URL? {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespaces)),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.percentEncodedHost, !host.isEmpty else { return nil }
        var origin = URLComponents()
        origin.scheme = scheme
        origin.percentEncodedHost = host.lowercased()
        origin.port = components.port
        return origin.url
    }

    /// Two addresses are the same server when scheme, host and port (with http/https defaults) match.
    static func key(for url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? "http"
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(url.host()?.lowercased() ?? ""):\(port)"
    }

    /// Bonjour results first (one per uuid, then one per address); the homeassistant.local probe only fills in when
    /// Bonjour found nothing, because without a uuid it can't be matched to a server Bonjour lists by IP.
    static func merge(bonjour: [HomeDiscoveredServer], probe: HomeDiscoveredServer?) -> [HomeDiscoveredServer] {
        var result: [HomeDiscoveredServer] = []
        var uuids: Set<String> = []
        var keys: Set<String> = []
        for server in bonjour {
            if let uuid = server.uuid, !uuids.insert(uuid).inserted { continue }
            guard keys.insert(key(for: server.url)).inserted else { continue }
            result.append(server)
        }
        if result.isEmpty, let probe { result.append(probe) }
        return result
    }

    /// HA's version from the WebSocket greeting (`auth_required` carries `ha_version`; no token needed).
    private static func version(at url: URL, delegate: HomeTrustDelegate, timeout: Duration) async -> String? {
        let socket = URLSessionHomeSocket(url: HAMapping.websocketURL(for: url), delegate: delegate)
        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            await socket.close()
        }
        defer { watchdog.cancel() }
        let greeting = try? await socket.receive()
        await socket.close()
        return greeting.flatMap { try? JSONValue.decode($0) }?["ha_version"]?.string
    }
}

extension Duration {
    var seconds: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}

// MARK: - Bonjour

/// One `NWBrowser` run. Every Network callback and all state live on `queue`.
private final class BonjourBrowse: @unchecked Sendable {
    struct Outcome: Sendable {
        var servers: [HomeDiscoveredServer] = []
        var denied = false
    }

    private struct Found {
        var txt: [String: String]
        var serviceName: String
        var resolved: URL?
    }

    private let type: String
    private let queue = DispatchQueue(label: "me.badia.altillo.home.bonjour")
    private var browser: NWBrowser?
    private var found: [NWEndpoint: Found] = [:]
    private var order: [NWEndpoint] = []
    private var resolving: [NWEndpoint: NWConnection] = [:]
    private var denied = false
    private var continuation: CheckedContinuation<Outcome, Never>?

    init(type: String) { self.type = type }

    func run(timeout: Duration) async -> Outcome {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { self.start(continuation, timeout: timeout) }
            }
        } onCancel: {
            queue.async { self.finish() }
        }
    }

    private func start(_ continuation: CheckedContinuation<Outcome, Never>, timeout: Duration) {
        self.continuation = continuation
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: NWParameters())
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .waiting(let error), .failed(let error):
                if Self.isPolicyDenied(error) { self?.denied = true }
                if case .failed = state { self?.finish() }
            default: break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.update(results)
        }
        browser.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout.seconds) { [weak self] in self?.finish() }
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            var txt: [String: String] = [:]
            if case .bonjour(let record) = result.metadata { txt = record.dictionary }
            if found[result.endpoint] == nil { order.append(result.endpoint) }
            found[result.endpoint, default: Found(txt: txt, serviceName: name)].txt = txt
            let hasURL = txt["internal_url"].flatMap(HomeDiscovery.origin) != nil
                || txt["base_url"].flatMap(HomeDiscovery.origin) != nil
            if !hasURL { resolve(result.endpoint) }
        }
    }

    /// Without a URL in the TXT record, connect once to learn the service's IPv4 address and port.
    private func resolve(_ endpoint: NWEndpoint) {
        guard resolving[endpoint] == nil, found[endpoint]?.resolved == nil else { return }
        let parameters = NWParameters.tcp
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(to: endpoint, using: parameters)
        resolving[endpoint] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint {
                    let hostText: String = switch host {
                    case .ipv4(let address): "\(address)"
                    case .name(let name, _): name
                    default: ""
                    }
                    if !hostText.isEmpty, let url = URL(string: "http://\(hostText.split(separator: "%").first ?? ""):\(port.rawValue)") {
                        self.found[endpoint]?.resolved = url
                    }
                }
                connection.cancel()
            case .failed, .waiting:
                connection.cancel()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        browser?.cancel()
        browser = nil
        for connection in resolving.values { connection.cancel() }
        resolving.removeAll()
        let servers = order.compactMap { endpoint in
            found[endpoint].flatMap { HomeDiscovery.server(txt: $0.txt, serviceName: $0.serviceName, resolved: $0.resolved) }
        }
        continuation.resume(returning: Outcome(servers: servers, denied: denied))
    }

    /// kDNSServiceErr_PolicyDenied (-65570): the Local Network permission is off.
    private static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == -65570 }
        return false
    }
}

// MARK: - Strings

extension HomeStrings {
    static var homeAssistant: String { String(localized: "Home Assistant", bundle: .module) }
    static var notHomeAssistant: String {
        String(localized: "Something answers at that address, but it isn't Home Assistant.", bundle: .module)
    }
    static var needsOnboarding: String {
        String(localized: "This Home Assistant isn't set up yet. Finish its setup in the browser first.", bundle: .module)
    }
}
