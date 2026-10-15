import Foundation
import Testing
@testable import AltilloHome

/// Against the real demo server from `script/home-lab.sh up`. Skipped unless ALTILLO_HOME_LAB_TOKEN is set:
/// `ALTILLO_HOME_LAB_TOKEN=$(cat ~/Library/Caches/altillo-home-lab/token) swift test --filter HomeAssistantLabTests`
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ALTILLO_HOME_LAB_TOKEN"] != nil))
struct HomeAssistantLabTests {
    @Test func connectsWatchesAndTogglesALight() async throws {
        let token = try #require(ProcessInfo.processInfo.environment["ALTILLO_HOME_LAB_TOKEN"])
        let client = HomeAssistantClient(tokens: InMemoryHomeTokenStore(), socketFactory: URLSessionHomeSocket.make)
        let config = HomeServerConfig(url: try HomeAssistantClient.normalize("localhost:8124"))
        try await client.connect(config, token: token)
        guard case .connected = client.connection else { Issue.record("not connected: \(client.connection)"); return }
        #expect(client.entities.count > 50)

        let light = try #require(client.entities.values.first { $0.kind == .light && $0.state.isAvailable })
        client.watch([light.id])
        try await Task.sleep(for: .seconds(1))
        let before = client.entities[light.id]?.state.isOn
        try await client.perform(.toggle(light.id))
        var changed = false
        for _ in 0..<50 where !changed {
            try await Task.sleep(for: .milliseconds(100))
            changed = client.entities[light.id]?.state.isOn != before
        }
        #expect(changed)
        try await client.perform(.toggle(light.id))
        client.disconnect(forget: true)
    }
}
