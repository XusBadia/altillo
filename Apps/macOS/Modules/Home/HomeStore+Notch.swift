import AltilloHome
import Foundation

/// What the notch's Home section needs beyond the layout API (docs/casa-v2.md §1, §3): the areas worth a chip, a
/// light's colour and warmth from the detail face, and the way to the entity in Home Assistant.
extension HomeStore {
    /// Areas with at least one light, blind, switch, fan, scene or script to browse, in the server's order.
    var browsableAreas: [HomeArea] {
        let used = Set(service.entities.values.compactMap { entity -> String? in
            guard Self.canFavourite(entity), !entity.isTechnical, Self.browsableKinds.contains(entity.kind) else { return nil }
            return entity.areaID
        })
        return service.areas.filter { used.contains($0.id) }
    }

    private static let browsableKinds: Set<HomeEntityKind> = [.light, .cover, .switchable, .fan, .scene, .script]

    /// Light colour from the detail face's swatches. The face shows the swatch at once; the tile follows the push.
    func setColor(_ entity: HomeEntity, _ color: HomeRGB) {
        guard entity.kind == .light, entity.capabilities.contains(.color) else { return }
        send(.setColor(entity.id, color))
    }

    /// The white's warmth, in kelvin, from the detail face's track.
    func setColorTemperature(_ entity: HomeEntity, kelvin: Double) {
        guard entity.kind == .light, entity.capabilities.contains(.colorTemperature) else { return }
        send(.setColorTemperature(entity.id, kelvin: kelvin))
    }

    /// Stops a blind where it is (the detail face's Stop).
    func stopCover(_ entity: HomeEntity) {
        guard entity.kind == .cover else { return }
        send(.stop(entity.id))
    }

    private func send(_ command: HomeCommand) {
        Task { [weak self] in
            do {
                try await self?.service.perform(command)
            } catch {
                DiagnosticLog.shared.record("home", "Command failed: \(Self.message(for: error))")
            }
        }
    }

    /// The entity on its server's own pages (Settings › Entities, searched by its id).
    func homeAssistantURL(for id: HomeEntityID) -> URL? {
        guard let server = settings.homeServer, server.serverID == id.serverID,
              var components = URLComponents(url: server.url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/config/entities"
        components.queryItems = [URLQueryItem(name: "search", value: id.localID)]
        return components.url
    }
}
