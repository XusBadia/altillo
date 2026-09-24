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
    /// Active section of the open notch. Always one of `settings.modules`. Change it with `select(_:)` so the
    /// content knows which way to slide.
    var module: NotchModule = .shelf
    /// Which way the last section change went in the tab strip: +1 towards the right, -1 towards the left, 0 when
    /// it didn't come from a neighbour (the notch reopening, an alert). Content slides accordingly.
    private(set) var moduleDirection = 0
    /// Bumped when a swipe or a key tries to go past the first or last section; `edgeBumpDirection` says which
    /// end (+1 past the last, -1 past the first). The content follows the fingers a few points (away from that
    /// end) and springs back, like a rubber band.
    private(set) var edgeBump = 0
    private(set) var edgeBumpDirection = 0
    /// The notch is open in edit mode (right-click › Customize…): sections and ears are rearranged in place,
    /// like editing widgets on iOS (PLAN §4). It stays open until the user is done.
    var isEditing = false
    /// Something worth a glance, shown as a peek while the notch is otherwise idle (a meeting about to start, a
    /// new song, an answer that finished while the notch was closed).
    var alert: NotchAlert?
    let settings: AltilloSettings

    // Module data. Each store only works while its module is visible, or lightly (events, never polling) while an
    // ear needs it.
    let calendar = CalendarStore()
    let mirror = MirrorStore()
    let nowPlaying = NowPlayingStore()
    let assistant = AssistantStore()
    let ears = EarsStore()
    let drawer = MenuBarDrawerStore.shared
    /// AI usage: the numbers behind the usage section, its ear and alerts, and Ask's `usage` tool.
    let usage: UsageStore

    var shelf: [ShelfItem] = []
    var selection: Set<ShelfItem.ID> = []
    /// True while dropped data or file promises are still being copied into the Inbox.
    var isReceivingDrop = false
    /// Recoverable shelf problem shown in the shelf instead of existing only in the debug log.
    var shelfProblem: String?
    var canUndoShelfChange = false
    var canRedoShelfChange = false
    var undoShelfTitle = String(localized: "Undo")
    var redoShelfTitle = String(localized: "Redo")
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

    /// Tests pass their own settings so they never touch the user's.
    init(settings: AltilloSettings = .shared) {
        self.settings = settings
        usage = UsageStore(settings: settings)
    }

    /// While true the notch doesn't close when the pointer wanders off: the user is typing or waiting for an
    /// answer. Esc or a click outside still close it.
    var holdsOpen: Bool { state == .open && (isEditing || (module == .assistant && assistant.holdsOpen)) }

    /// Switches section, remembering the direction for the content's slide.
    func select(_ target: NotchModule) {
        guard target != module else { return }
        let modules = settings.modules
        if let from = modules.firstIndex(of: module), let to = modules.firstIndex(of: target) {
            moduleDirection = to > from ? 1 : -1
        } else {
            moduleDirection = 0
        }
        module = target
    }

    /// Switches section without a slide direction (the notch opening on it for an alert or a shortcut).
    func jump(to target: NotchModule) {
        moduleDirection = 0
        module = target
    }

    /// There's no section further that way: lean and spring back.
    func bumpEdge(_ direction: Int) {
        edgeBumpDirection = direction
        edgeBump += 1
    }

    /// What the contextual left ear is about (PLAN §4): real, enabled sources only, never a design scenario.
    /// Agents have no live source yet (phase 4), so they don't take part until they do. AI usage takes part while
    /// its main limit runs high (`UsageStore.contextualSignal`).
    var contextualActivity: NotchActivity {
        guard scenario == nil else { return .rest }
        let inputs = NotchActivityInputs(
            agentRequest: nil,
            nextEvent: ears.nextEvent,
            playback: nowPlaying.playbackSignal,
            usage: usage.contextualSignal
        )
        return NotchActivityLogic.resolve(inputs, enabled: Set(settings.modules), now: ears.clock)
    }

    /// The neighbouring section in the tab strip (`offset` +1 right, -1 left), or nil at either end.
    func neighbour(_ offset: Int) -> NotchModule? {
        let modules = settings.modules
        guard let index = modules.firstIndex(of: module) else { return nil }
        let target = index + offset
        return modules.indices.contains(target) ? modules[target] : nil
    }
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
    var openDrawerSettings: () -> Void = {}
    /// Puts things on the shelf from inside Altillo (an answer from the assistant, say), with the landing.
    var addToShelf: ([ShelfItem]) -> Void = { _ in }
    /// Gives the open notch keyboard focus (a text field was clicked or the assistant was summoned).
    var takeKeyboardFocus: () -> Void = {}
    /// Opens the notch on the section the contextual ear stands for (VoiceOver's action on it).
    var openFromIndicator: (NotchModule) -> Void = { _ in }
    /// Opens the notch in edit mode, or leaves it.
    var beginEditing: () -> Void = {}
    var endEditing: () -> Void = {}
    /// A light tap on Force Touch trackpads, if the user hasn't turned haptics off.
    var haptic: (Haptics.Pattern) -> Void = { _ in }
}
