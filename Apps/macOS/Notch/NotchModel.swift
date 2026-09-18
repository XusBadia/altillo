import AltilloCore
import CoreGraphics
import Foundation
import Observation

enum NotchTab: String, CaseIterable, Identifiable, Sendable {
    case shelf, usage, agents
    var id: Self { self }
}

/// Everything the notch views render. Owned by `NotchCoordinator`, one per app (shared by every screen's panel).
@MainActor
@Observable
final class NotchModel {
    var state: NotchState = .idle
    /// Size of the hardware notch (or virtual island) on the screen being rendered, in points.
    var notchSize = CGSize(width: 185, height: 32)
    var hasNotch = true
    var tab: NotchTab = .shelf

    var shelf: [ShelfItem] = []
    var selection: Set<ShelfItem.ID> = []
    /// True while a drag hovers the drop zone itself (not just near the notch).
    var isDropHovering = false

    /// Fake usage/agents/etc. used until the real modules exist (phase 0 design review).
    var demo: DemoContent = .sample
    /// Set while reviewing a design scenario from the menu bar; freezes the state machine.
    var scenario: DesignScenario?

    /// Size of the black notch shape currently drawn, reported by the views.
    /// The coordinator uses it for hit-testing and hover tracking.
    var visibleShapeSize: CGSize = .zero

    var actions = NotchActions()
}

/// Callbacks the views use to act. Wired by `NotchCoordinator`.
@MainActor
struct NotchActions {
    var send: (NotchEvent) -> Void = { _ in }
    var remove: (Set<ShelfItem.ID>) -> Void = { _ in }
    var clearShelf: () -> Void = {}
    var open: (ShelfItem) -> Void = { _ in }
    var revealInFinder: ([ShelfItem]) -> Void = { _ in }
    var quickLook: ([ShelfItem]) -> Void = { _ in }
}
