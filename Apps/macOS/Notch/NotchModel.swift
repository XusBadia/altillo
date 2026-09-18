import AltilloCore
import CoreGraphics
import Foundation
import Observation

/// Areas of the open notch that accept a drop.
enum DropZone: Hashable, Sendable {
    case shelf, airDrop
}

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
    /// The drop zone under the pointer during a drag, if any. Zones only light up while the pointer is over them.
    var dropZone: DropZone?
    /// Frames of the drop zones, in the hosting view's coordinates (top-left origin), reported by the views.
    var dropZoneFrames: [DropZone: CGRect] = [:]
    /// True while a drag hovers the shelf drop zone itself (not just near the notch).
    var isDropHovering: Bool { dropZone == .shelf }
    /// How close a drag is to the notch: 1 at the notch, 0 at 300 pt or more. Lights the bulb while dragArmed.
    var dragProximity: Double = 0

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
