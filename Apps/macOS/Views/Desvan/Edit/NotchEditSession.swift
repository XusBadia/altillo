import CoreGraphics
import Foundation
import Observation

extension Notification.Name {
    /// Posted by Settings › Sections' "Customize in the Notch…". `NotchCoordinator` observes it and opens the notch
    /// in edit mode (Settings can't reach the coordinator directly).
    static let altilloCustomizeNotch = Notification.Name("me.badia.altillo.customizeNotch")
}

/// One of the two ears beside the resting notch.
enum EarSide: String, CaseIterable, Identifiable, Sendable {
    case left, right

    var id: Self { self }

    var title: String {
        switch self {
        case .left: String(localized: "Left ear")
        case .right: String(localized: "Right ear")
        }
    }

    var opposite: EarSide { self == .left ? .right : .left }
}

/// Places a drag can end in while editing the notch.
enum EditDropTarget: Hashable, Sendable {
    case ear(EarSide)
    /// The "Put away" box under the tabs.
    case tray
}

/// One edit-mode visit: what the user changed (for Undo / ⌘Z), which ear the chips fill, and what is being dragged.
///
/// Every change goes straight to `AltilloSettings`, so the notch (and Settings) follow live; the session only keeps
/// the configurations it came from. A gesture (dragging a tab around) counts as one change however many times it
/// moves.
@MainActor
@Observable
final class NotchEditSession {
    /// What an edit can change: sections, their order and the ears.
    struct Snapshot: Equatable, Sendable {
        var modules: [NotchModule]
        var leftEar: EarContent
        var rightEar: EarContent
        var earsVisibility: EarsVisibility

        @MainActor
        init(_ settings: AltilloSettings) {
            modules = settings.modules
            leftEar = settings.leftEar
            rightEar = settings.rightEar
            earsVisibility = settings.earsVisibility
        }

        @MainActor
        func restore(into settings: AltilloSettings) {
            if settings.modules != modules { settings.modules = modules }
            if settings.leftEar != leftEar { settings.leftEar = leftEar }
            if settings.rightEar != rightEar { settings.rightEar = rightEar }
            if settings.earsVisibility != earsVisibility { settings.earsVisibility = earsVisibility }
        }
    }

    /// A tab being dragged by the pointer.
    struct TileDrag: Equatable {
        var module: NotchModule
        /// Where it was in the strip when the drag began, to keep it under the pointer as the others shuffle.
        var startIndex: Int
        var translation: CGSize
        /// Where the pointer is, in the edit face's coordinate space (`DesvanEdit.space`).
        var location: CGPoint
    }

    /// An ear chip being dragged towards a slot.
    struct EarDrag: Equatable {
        var content: EarContent
        var location: CGPoint
    }

    private(set) var undoStack: [Snapshot] = []
    var canUndo: Bool { !undoStack.isEmpty }
    /// The ear a tapped chip goes to. Tapping a slot picks it.
    var selectedEar: EarSide = .right
    /// The preset just applied, while its Undo is on offer (the Undo button glows for a few seconds).
    var justApplied: NotchPreset?
    var tileDrag: TileDrag?
    var earDrag: EarDrag?
    /// Frames of the drop targets in `DesvanEdit.space`, reported by the views.
    var targetFrames: [EditDropTarget: CGRect] = [:]

    /// The configuration a gesture started from; set while one is in flight so it records a single undo step.
    @ObservationIgnored private var gestureStart: Snapshot?
    static let undoLimit = 50

    /// A fresh visit: nothing to undo, and the chips fill whichever ear is empty (the right one otherwise).
    func begin(with settings: AltilloSettings) {
        undoStack.removeAll()
        justApplied = nil
        tileDrag = nil
        earDrag = nil
        gestureStart = nil
        selectedEar = settings.leftEar == .none && settings.rightEar != .none ? .left : .right
    }

    // MARK: Sections

    /// Moves a section to `index` in the tab strip. The shelf stays first: nothing moves before it, and it never
    /// moves itself. Returns whether anything changed.
    @discardableResult
    func move(_ module: NotchModule, to index: Int, in settings: AltilloSettings) -> Bool {
        guard !module.isAlwaysOn, let from = settings.modules.firstIndex(of: module) else { return false }
        let firstMovable = settings.modules.firstIndex { !$0.isAlwaysOn } ?? 0
        let target = min(max(index, firstMovable), settings.modules.count - 1)
        guard target != from else { return false }
        return change(settings) {
            settings.move(fromOffsets: IndexSet(integer: from), toOffset: target > from ? target + 1 : target)
        }
    }

    /// One step left (-1) or right (+1).
    @discardableResult
    func move(_ module: NotchModule, by offset: Int, in settings: AltilloSettings) -> Bool {
        guard let from = settings.modules.firstIndex(of: module) else { return false }
        return move(module, to: from + offset, in: settings)
    }

    /// Whether `module` can go one step that way.
    func canMove(_ module: NotchModule, by offset: Int, in settings: AltilloSettings) -> Bool {
        guard !module.isAlwaysOn, let from = settings.modules.firstIndex(of: module) else { return false }
        let target = from + offset
        return settings.modules.indices.contains(target) && !settings.modules[target].isAlwaysOn
    }

    /// Takes a section out of the notch (into the "Put away" box). The shelf can't be put away.
    @discardableResult
    func putAway(_ module: NotchModule, in settings: AltilloSettings) -> Bool {
        guard !module.isAlwaysOn, settings.isEnabled(module) else { return false }
        return change(settings) { settings.setEnabled(module, false) }
    }

    /// Brings a section back, at the end of the strip or at `index`.
    @discardableResult
    func addBack(_ module: NotchModule, at index: Int? = nil, in settings: AltilloSettings) -> Bool {
        guard !settings.isEnabled(module) else { return false }
        return change(settings) {
            settings.setEnabled(module, true)
            if let index, let from = settings.modules.firstIndex(of: module) {
                let firstMovable = settings.modules.firstIndex { !$0.isAlwaysOn } ?? 0
                let target = min(max(index, firstMovable), settings.modules.count - 1)
                if target != from {
                    settings.move(fromOffsets: IndexSet(integer: from), toOffset: target > from ? target + 1 : target)
                }
            }
        }
    }

    // MARK: Ears

    /// Puts `content` in an ear. Something already in the other ear moves rather than showing twice: the two ears
    /// swap. Usage and agents aren't available yet and are refused.
    @discardableResult
    func assign(_ content: EarContent, to side: EarSide, in settings: AltilloSettings) -> Bool {
        guard content.isAvailable else { return false }
        selectedEar = side
        let current = ear(side, in: settings)
        guard current != content else { return false }
        return change(settings) {
            if content != .none, ear(side.opposite, in: settings) == content {
                setEar(side.opposite, current, in: settings)
            }
            setEar(side, content, in: settings)
        }
    }

    @discardableResult
    func setVisibility(_ visibility: EarsVisibility, in settings: AltilloSettings) -> Bool {
        guard settings.earsVisibility != visibility else { return false }
        return change(settings) { settings.earsVisibility = visibility }
    }

    func ear(_ side: EarSide, in settings: AltilloSettings) -> EarContent {
        side == .left ? settings.leftEar : settings.rightEar
    }

    private func setEar(_ side: EarSide, _ content: EarContent, in settings: AltilloSettings) {
        switch side {
        case .left: settings.leftEar = content
        case .right: settings.rightEar = content
        }
    }

    /// What a section shows when it's dropped on an ear (PLAN §4: "arrastras módulos a las orejas"), if anything.
    static func earContent(for module: NotchModule) -> EarContent? {
        switch module {
        case .shelf: .shelf
        case .calendar: .nextEvent
        case .nowPlaying: .nowPlaying
        case .usage: .usage
        case .agents: .agents
        case .assistant, .mirror: nil
        }
    }

    // MARK: Presets

    /// Applies a preset, keeping what was there for Undo.
    @discardableResult
    func apply(_ preset: NotchPreset, in settings: AltilloSettings) -> Bool {
        let applied = change(settings) { settings.apply(preset) }
        if applied { justApplied = preset }
        return applied
    }

    // MARK: Undo

    /// Goes back one change (a preset, a move, a put-away, an ear). Returns whether there was one.
    @discardableResult
    func undo(in settings: AltilloSettings) -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        previous.restore(into: settings)
        justApplied = nil
        return true
    }

    /// A drag starts: whatever it does until `endGesture` is one undo step.
    func beginGesture(in settings: AltilloSettings) {
        gestureStart = Snapshot(settings)
    }

    func endGesture(in settings: AltilloSettings) {
        defer { gestureStart = nil }
        guard let start = gestureStart, start != Snapshot(settings) else { return }
        push(start)
    }

    /// Runs `body` and records where it came from, unless it changed nothing (or a gesture records it at its end).
    private func change(_ settings: AltilloSettings, _ body: () -> Void) -> Bool {
        let before = Snapshot(settings)
        body()
        guard Snapshot(settings) != before else { return false }
        if gestureStart == nil { push(before) }
        return true
    }

    private func push(_ snapshot: Snapshot) {
        undoStack.append(snapshot)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
    }

    // MARK: Drops

    /// The drop target under `location` (in `DesvanEdit.space`), a little forgiving around the ears: they're small.
    func target(at location: CGPoint) -> EditDropTarget? {
        for side in EarSide.allCases {
            if let frame = targetFrames[.ear(side)], frame.insetBy(dx: -8, dy: -8).contains(location) {
                return .ear(side)
            }
        }
        if let tray = targetFrames[.tray], tray.contains(location) { return .tray }
        return nil
    }
}

extension EarContent {
    /// The chip's name in edit mode: one short word.
    var shortTitle: String {
        switch self {
        case .none: String(localized: "None")
        case .shelf: String(localized: "Shelf")
        case .nextEvent: String(localized: "Event")
        case .nowPlaying: String(localized: "Music")
        case .usage: String(localized: "Usage")
        case .agents: String(localized: "Agents")
        }
    }
}
