import AltilloHome
import Foundation

/// Peeks when someone rings the doorbell chosen in Settings › Home (docs/casa.md, "Avisos"). The camera's picture
/// arrives a moment later and shows up in the peek on its own (`HomeStore.ring`); clicking it opens the Home section,
/// where the camera card waits for a couple of minutes.
///
/// Listens to the same event stream the store does, only while enabled: no timers, no polling. A ring while the
/// notch is open, a drag runs or a design scenario is frozen is dropped by `NotchCoordinator.post`, like every alert.
@MainActor
final class HomeAlertSource {
    private let post: (NotchAlert) -> Void
    private let store: HomeStore
    private var enabled = false
    private var task: Task<Void, Never>?
    /// The last ring peeked about, so a repeated push of the same event never peeks twice.
    private var lastRing: Date?

    init(store: HomeStore, post: @escaping (NotchAlert) -> Void) {
        self.store = store
        self.post = post
    }

    /// Starts or stops listening. Idempotent.
    func update(enabled: Bool) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled
        task?.cancel()
        task = nil
        guard enabled else { return }
        let stream = store.service.events()
        task = Task { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { return }
                self.handle(event)
            }
        }
    }

    /// One event from the service. Internal so tests can drive it without a stream.
    func handle(_ event: HomeServiceEvent) {
        guard enabled, case let .triggered(id, at) = event, id == store.doorbellTrigger, lastRing != at else { return }
        lastRing = at
        let name = store.service.entities[id]?.name
        post(HomeAlertBuilder.doorbell(name: name, hasCamera: store.doorbellCamera != nil))
    }
}

enum HomeAlertBuilder {
    /// "Someone's at the door", with the doorbell's name when it says more than "Doorbell".
    static func doorbell(name: String?, hasCamera: Bool) -> NotchAlert {
        NotchAlert(
            source: .home,
            symbol: "bell.fill",
            title: String(localized: "Someone's at the door"),
            detail: name.flatMap { $0.isEmpty ? nil : $0 },
            trailing: String(localized: "now"),
            isUrgent: true,
            module: .home,
            // Long enough to look at the picture.
            duration: .seconds(hasCamera ? 10 : 6)
        )
    }
}

extension NotchAlert {
    /// The peek shown by the "Peek: doorbell" design scenario.
    static let demoDoorbell = HomeAlertBuilder.doorbell(name: String(localized: "Front door"), hasCamera: true)
}
