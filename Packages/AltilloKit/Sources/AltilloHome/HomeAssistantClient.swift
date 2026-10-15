import Foundation
import Observation

/// Home Assistant over its WebSocket API (docs/casa.md). STUB: the public surface is final, the bodies are not.
@MainActor
@Observable
public final class HomeAssistantClient: HomeService {
    public private(set) var connection: HomeConnectionState = .notConfigured
    public private(set) var areas: [HomeArea] = []
    public private(set) var entities: [HomeEntityID: HomeEntity] = [:]
    public private(set) var config: HomeServerConfig?

    public init() {}

    public func events() -> AsyncStream<HomeServiceEvent> { AsyncStream { $0.finish() } }
    public func connect(_ config: HomeServerConfig, token: String) async throws { throw HomeServiceError("Not implemented") }
    public func resume(_ config: HomeServerConfig) {}
    public func trustCertificate(_ fingerprintSHA256: String) -> HomeServerConfig? { nil }
    public func disconnect(forget: Bool) {}
    public func watch(_ ids: Set<HomeEntityID>) {}
    public func perform(_ command: HomeCommand) async throws { throw HomeServiceError("Not implemented") }
    public func snapshot(camera: HomeEntityID) async throws -> Data { throw HomeServiceError("Not implemented") }

    /// "homeassistant.local:8123" → http://homeassistant.local:8123. Throws a user-facing error.
    public static func normalize(_ raw: String) throws -> URL { throw HomeServiceError("Not implemented") }
    /// `<server>/profile/security`, where the user creates a long-lived token.
    public static func tokenPage(for url: URL) -> URL { url.appending(path: "profile/security") }
}
