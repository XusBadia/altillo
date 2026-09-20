import AltilloCore
import CoreGraphics
import Foundation
import Observation

/// Areas of the open notch that accept a drop.
enum DropZone: Hashable, Sendable {
    case shelf, airDrop
}

/// Everything the notch views render. Owned by `NotchCoordinator`, one per app (shared by every screen's panel).
@MainActor
@Observable
final class NotchModel {
    var state: NotchState = .idle
    /// Size of the hardware notch (or virtual island) on the screen being rendered, in points.
    var notchSize = CGSize(width: 185, height: 32)
    var hasNotch = true
    /// Active section of the open notch. Always one of `settings.modules`.
    var module: NotchModule = .shelf
    let settings = AltilloSettings.shared

    // Module data. Each store only works while its module is visible.
    let calendar = CalendarStore()
    let mirror = MirrorStore()
    let nowPlaying = NowPlayingStore()

    var shelf: [ShelfItem] = []
    var selection: Set<ShelfItem.ID> = []
    /// True while dropped data or file promises are still being copied into the Inbox.
    var isReceivingDrop = false
    /// Recoverable shelf problem shown in the shelf instead of existing only in the debug log.
    var shelfProblem: String?
    var canUndoShelfChange = false
    var canRedoShelfChange = false
    var undoShelfTitle = "Deshacer"
    var redoShelfTitle = "Rehacer"
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
    /// Items that physically left during drag-out are not undoable: their destination now owns the move.
    var removeDeparted: (Set<ShelfItem.ID>) -> Void = { _ in }
    var clearShelf: () -> Void = {}
    var undo: () -> Void = {}
    var redo: () -> Void = {}
    var open: (ShelfItem) -> Void = { _ in }
    var revealInFinder: ([ShelfItem]) -> Void = { _ in }
    var quickLook: ([ShelfItem]) -> Void = { _ in }
    var openSettings: () -> Void = {}
}
