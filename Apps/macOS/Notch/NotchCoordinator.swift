import AltilloCore
import AltilloDesign
import AppKit
import Observation
import SwiftUI

/// Wires input, drag detection and the state machine to the model and the panel.
@MainActor
final class NotchCoordinator {
    let model = NotchModel()

    private var machine = NotchStateMachine(opensOnHover: AltilloSettings.shared.opensOnHover)
    private let shelfStore: ShelfStore
    private let shelfUndoManager = UndoManager()
    private var window: NotchWindowController?
    private let input = InputMonitor()
    private lazy var dragDetector = DragDetector(callbacks: .init(
        began: { [weak self] in self?.send(.dragBegan) },
        moved: { [weak self] point in self?.dragMoved(to: point) },
        ended: { [weak self] in self?.dragEnded() }
    ))
    private var observers: [NSObjectProtocol] = []
    private var pendingTimers: [TimerKind: Task<Void, Never>] = [:]
    private var droppedDuringCurrentDrag = false
    private var isHovering = false
    private var isStarted = false
    private var keyMonitor: Any?
    /// The user's shelf, kept aside while a design scenario shows demo items.
    private var stashedShelf: (
        items: [ShelfItem], selection: Set<ShelfItem.ID>, isReceivingDrop: Bool, problem: String?
    )?

    private enum TimerKind { case hoverIntent, hoverSustained, closeGrace, alert, shelfExpiry }

    init(shelfStore: ShelfStore = .standard) {
        self.shelfStore = shelfStore
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let restoration = shelfStore.restore(expiry: model.settings.shelfExpiry)
        model.shelf = restoration.items
        if case .recoveredFromCorruptSnapshot = restoration {
            SpikeLog.shared.record(SpikeLog.Category.shelf, "El estado dañado se ha apartado; el altillo empieza vacío")
        } else if case .failed = restoration {
            model.shelfProblem = "No he podido recuperar el altillo. He conservado sus datos para no sobrescribirlos."
        }
        shelfUndoManager.removeAllActions()
        updateUndoState()
        observeShelfExpiry()
        scheduleShelfExpiry()

        model.actions = NotchActions(
            send: { [weak self] in self?.send($0) },
            remove: { [weak self] in self?.remove($0) },
            removeDeparted: { [weak self] in self?.remove($0, undoable: false) },
            clearShelf: { [weak self] in self?.remove(Set(self?.model.shelf.map(\.id) ?? [])) },
            undo: { [weak self] in self?.undoShelfChange() },
            redo: { [weak self] in self?.redoShelfChange() },
            open: { item in
                if let url = item.fileURL { NSWorkspace.shared.open(url) }
                else if case let .link(url) = item.kind { NSWorkspace.shared.open(url) }
            },
            revealInFinder: { items in NSWorkspace.shared.activateFileViewerSelecting(items.compactMap(\.fileURL)) },
            quickLook: { items in QuickLookPresenter.show(items.compactMap(\.fileURL)) },
            openSettings: { SettingsWindowController.shared.show() },
            openDrawerSettings: { SettingsWindowController.shared.show(tab: .drawer) }
        )

        rebuildWindow()
        model.drawer.start()
        input.mouseMoved = { [weak self] in self?.mouseMoved(to: $0) }
        input.mouseDown = { [weak self] point, isLocal in self?.mouseDown(at: point, isLocal: isLocal) }
        input.start()
        dragDetector.start()
        installKeyMonitor()

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.rebuildWindow() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated {
            self?.rebuildWindow()
            self?.expireShelf()
        } })
        observers.append(center.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.expireShelf() } })
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        persistShelf()
        cancelAllTimers()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        input.stop()
        dragDetector.stop()
        model.drawer.stop()
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
    }

    /// Freezes the notch in a design-review scenario (nil returns to normal behaviour).
    func show(_ scenario: DesignScenario?) {
        cancelAllTimers()
        if let scenario {
            if model.scenario == nil {
                stashedShelf = (model.shelf, model.selection, model.isReceivingDrop, model.shelfProblem)
            }
            model.module = scenario.module
            model.shelf = scenario.showsDemoShelf ? model.demo.shelfItems : []
            model.selection = []
            model.isReceivingDrop = scenario == .openShelfLoading
            model.shelfProblem = scenario == .openShelfError
                ? "No he podido guardar lo que has soltado. Puedes volver a intentarlo."
                : nil
            machine = NotchStateMachine(state: scenario.state)
        } else {
            restoreStashedShelf()
            machine = NotchStateMachine(opensOnHover: model.settings.opensOnHover)
        }
        model.scenario = scenario
        apply()
    }

    private func restoreStashedShelf() {
        guard let stashed = stashedShelf else { return }
        model.shelf = stashed.items
        model.selection = stashed.selection
        model.isReceivingDrop = stashed.isReceivingDrop
        model.shelfProblem = stashed.problem
        stashedShelf = nil
        scheduleShelfExpiry()
    }

    // MARK: - Window

    private func rebuildWindow() {
        guard let screen = ScreenService.preferredScreen else { return }
        let geometry = ScreenService.geometry(for: screen)
        model.hasNotch = geometry.hasNotch
        model.notchSize = geometry.notchRect.size
        if let window {
            window.update(geometry: geometry)
        } else {
            let controller = NotchWindowController(geometry: geometry, model: model)
            controller.dropTarget.zoneAt = { [weak self, weak controller] point in
                guard let self, let controller else { return nil }
                return self.dropZone(at: point, in: controller.dropTarget)
            }
            controller.dropTarget.onZoneChanged = { [weak self] zone in self?.model.dropZone = zone }
            controller.dropTarget.onAirDrop = { [weak self] items in self?.sendViaAirDrop(items) }
            // Accepted before slow file promises (Photos, Mail) resolve, so the notch stays open while they arrive.
            controller.dropTarget.onDropAccepted = { [weak self] in self?.dropAccepted() }
            controller.panel.onCloseRequest = { [weak self] in self?.send(.escape) }
            controller.dropTarget.onDrop = { [weak self] items in self?.receive(items) }
            window = controller
        }
        window?.show()
        apply()
    }

    // MARK: - Events

    private func send(_ event: NotchEvent) {
        guard model.scenario == nil || event == .escape else { return }
        if event == .escape, model.scenario != nil {
            show(nil)
            return
        }
        if event == .dragBegan { droppedDuringCurrentDrag = false }
        if machine.handle(event) { apply() }
    }

    private func apply() {
        machine.opensOnHover = model.settings.opensOnHover
        // A module that was turned off in Settings must not stay open.
        if !model.settings.modules.contains(model.module) { model.module = .shelf }
        let state = machine.state
        withAnimation(state == .idle ? .closeNotch : .openNotch) {
            model.state = state
        }
        if let panel = window?.panel {
            panel.ignoresMouseEvents = !state.isInteractive
            panel.allowsKey = state == .open
            if state != .open { panel.relinquishKey() }
        }
        if state == .idle || state == .open { model.dropZone = nil }
        if state != .open { cancel(.closeGrace) }
    }

    private func mouseMoved(to point: CGPoint) {
        guard let window, model.scenario == nil else { return }
        let area = model.state == .idle ? window.geometry.hoverRect() : window.visibleShapeScreenRect
        let inside = area.contains(point)
        guard inside != isHovering else { return }
        isHovering = inside

        if inside {
            cancel(.closeGrace)
            schedule(.hoverIntent, after: NotchLayout.Timing.hoverIntent) { [weak self] in
                self?.send(.hoverIntent)
                self?.schedule(.hoverSustained, after: NotchLayout.Timing.hoverSustained) { self?.send(.hoverSustained) }
            }
        } else {
            cancel(.hoverIntent)
            cancel(.hoverSustained)
            send(.pointerLeft)
            if model.state == .open {
                schedule(.closeGrace, after: NotchLayout.Timing.closeGrace) { [weak self] in self?.send(.closeGraceElapsed) }
            }
        }
    }

    private func mouseDown(at point: CGPoint, isLocal: Bool) {
        // Design scenarios stay frozen (e.g. while taking a ⇧⌘4 screenshot); leave them with Esc or the menu.
        guard let window, model.scenario == nil else { return }
        let onShape = window.visibleShapeScreenRect.contains(point)
        if onShape, model.state == .idle || model.state == .peek {
            send(.click)
            // An explicit click means the user wants to interact: take keyboard focus (hover-opening never does).
            window.panel.makeKey()
        } else if !onShape, model.state != .idle, model.state != .dragArmed, model.state != .dropTarget {
            send(.escape)
        }
    }

    private func dragMoved(to point: CGPoint) {
        guard let window else { return }
        // Near the notch, or anywhere over the open notch (plus a margin): the open shelf reaches far below the
        // notch itself, so measuring only from the notch would close it under the pointer.
        let distance = window.geometry.distance(to: point)
        model.dragProximity = 1 - min(max(distance / 300, 0), 1)
        let nearNotch = distance < NotchLayout.dropActivationDistance
        let overOpenNotch = model.state == .dropTarget
            && window.visibleShapeScreenRect.insetBy(dx: -NotchLayout.dropKeepOpenMargin, dy: -NotchLayout.dropKeepOpenMargin)
                .contains(point)
        send(.dragMoved(near: nearNotch || overOpenNotch))
    }

    /// Zone under a point of the drop target view. Zone frames come from SwiftUI in the hosting view's
    /// top-left coordinates; anywhere else on the open notch counts as the shelf, outside it nothing accepts.
    private func dropZone(at point: NSPoint, in view: NSView) -> DropZone? {
        guard model.state == .dropTarget else { return nil }
        let topLeft = CGPoint(x: point.x, y: view.bounds.height - point.y)
        if model.dropZoneFrames[.airDrop]?.contains(topLeft) == true { return .airDrop }
        if model.dropZoneFrames[.shelf]?.contains(topLeft) == true { return .shelf }
        return nil
    }

    private func sendViaAirDrop(_ items: [ShelfItem]) {
        model.isReceivingDrop = false
        let payload: [Any] = items.compactMap { item in
            switch item.kind {
            case let .file(url, _): url
            case let .link(url): url
            case let .text(text): text
            }
        }
        send(.escape)
        guard !payload.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: payload) else {
            SpikeLog.shared.record(SpikeLog.Category.drop, "AirDrop no disponible para \(items.count) ítem(s)")
            NSSound.beep()
            return
        }
        SpikeLog.shared.record(SpikeLog.Category.drop, "AirDrop: enviando \(items.count) ítem(s)")
        NSApp.activate()
        service.perform(withItems: payload)
    }

    /// Altillo accepted a drop: end the drag right away instead of waiting for a mouse-up the global monitor
    /// may never see, and track the hover so the notch closes normally once the pointer leaves.
    private func dropAccepted() {
        droppedDuringCurrentDrag = true
        model.isReceivingDrop = true
        model.shelfProblem = nil
        dragDetector.finishCurrentDrag()
        send(.dragEnded(dropped: true))
        if let window {
            isHovering = window.visibleShapeScreenRect.contains(NSEvent.mouseLocation)
        }
    }

    private func dragEnded() {
        // File promises are delivered after mouse-up; give the drop target a beat to report the drop.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self else { return }
            send(.dragEnded(dropped: droppedDuringCurrentDrag))
            droppedDuringCurrentDrag = false
        }
    }

    // MARK: - Keyboard

    /// ⌫ (and ⌘⌫, fn⌫) remove the selection. Handled in AppKit: SwiftUI's `onKeyPress` never sees the Mac's
    /// backspace key in a hosting view (it arrives as the `deleteBackward:` text command).
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let windowNumber = event.windowNumber
            let modifiers = event.modifierFlags
            let handled = MainActor.assumeIsolated {
                self?.handleKey(keyCode, modifiers: modifiers, inWindow: windowNumber) ?? false
            }
            return handled ? nil : event
        }
    }

    private func handleKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags, inWindow windowNumber: Int) -> Bool {
        guard windowNumber == window?.panel.windowNumber, model.state == .open else { return false }
        if keyCode == 6, modifiers.contains(.command) { // Z
            modifiers.contains(.shift) ? redoShelfChange() : undoShelfChange()
            return true
        }
        let deleteKeys: Set<UInt16> = [51, 117] // backspace, forward delete
        guard deleteKeys.contains(keyCode), model.module == .shelf, !model.selection.isEmpty else {
            return false
        }
        remove(model.selection)
        return true
    }

    // MARK: - Shelf

    private func receive(_ items: [ShelfItem]) {
        droppedDuringCurrentDrag = true
        if model.scenario != nil, stashedShelf != nil {
            // A slow file promise can finish while a frozen design scenario is on screen. Its loading/error state
            // and result belong to the real shelf, never to the demo that temporarily occupies `model.shelf`.
            stashedShelf?.isReceivingDrop = false
            guard !items.isEmpty else {
                stashedShelf?.problem = "No he podido guardar lo que has soltado. Puedes volver a intentarlo."
                return
            }
            stashedShelf?.problem = nil
            stashedShelf?.items.append(contentsOf: items)
            persistShelf()
            return
        }
        model.isReceivingDrop = false
        guard !items.isEmpty else {
            model.shelfProblem = "No he podido guardar lo que has soltado. Puedes volver a intentarlo."
            return
        }
        model.shelfProblem = nil
        withAnimation(.openNotch) {
            model.shelf.append(contentsOf: items)
        }
        persistShelf()
        scheduleShelfExpiry()
        if model.state != .open, model.state != .dropTarget {
            // Drops that finish after the drag ended (slow promises) still show the result.
            machine = NotchStateMachine(state: .open)
            apply()
        }
    }

    func remove(_ ids: Set<ShelfItem.ID>, undoable: Bool = true) {
        guard model.scenario == nil else { return }
        let removed = model.shelf.enumerated().compactMap { index, item in
            ids.contains(item.id) ? RemovedShelfItem(item: item, index: index) : nil
        }
        guard !removed.isEmpty else { return }
        withAnimation(.closeNotch) {
            model.shelf.removeAll { ids.contains($0.id) }
            model.selection.subtract(ids)
        }
        var retired: [ShelfStore.RetiredFile] = []
        if persistShelf() {
            retired = shelfStore.removeOwnedFiles(for: removed.map(\.item), preserving: model.shelf)
        }
        if undoable {
            shelfUndoManager.registerUndo(withTarget: self) { coordinator in
                coordinator.restoreRemoval(removed, retired: retired)
            }
            shelfUndoManager.setActionName(removed.count == 1 ? "Bajar del altillo" : "Bajar del altillo")
        }
        updateUndoState()
        scheduleShelfExpiry()
    }

    private struct RemovedShelfItem {
        var item: ShelfItem
        let index: Int
    }

    private func restoreRemoval(_ removed: [RemovedShelfItem], retired: [ShelfStore.RetiredFile]) {
        let restoredURLs = shelfStore.restoreOwnedFiles(retired)
        let retiredIDs = Set(retired.map(\.itemID))
        var restoredItems: [RemovedShelfItem] = []
        for var entry in removed {
            if retiredIDs.contains(entry.item.id) {
                guard let url = restoredURLs[entry.item.id] else { continue }
                entry.item.kind = .file(url, isOwnedCopy: true)
            }
            restoredItems.append(entry)
        }
        guard !restoredItems.isEmpty else {
            updateUndoState()
            return
        }
        for entry in restoredItems.sorted(by: { $0.index < $1.index }) {
            model.shelf.insert(entry.item, at: min(entry.index, model.shelf.count))
        }
        model.selection = Set(restoredItems.map(\.item.id))
        persistShelf()
        let ids = Set(restoredItems.map(\.item.id))
        shelfUndoManager.registerUndo(withTarget: self) { coordinator in
            coordinator.remove(ids, undoable: true)
        }
        shelfUndoManager.setActionName(restoredItems.count == 1 ? "Bajar del altillo" : "Bajar del altillo")
        updateUndoState()
        scheduleShelfExpiry()
    }

    func undoShelfChange() {
        guard shelfUndoManager.canUndo else { return }
        shelfUndoManager.undo()
        updateUndoState()
    }

    func redoShelfChange() {
        guard shelfUndoManager.canRedo else { return }
        shelfUndoManager.redo()
        updateUndoState()
    }

    private func updateUndoState() {
        model.canUndoShelfChange = shelfUndoManager.canUndo
        model.canRedoShelfChange = shelfUndoManager.canRedo
        model.undoShelfTitle = shelfUndoManager.undoMenuItemTitle
        model.redoShelfTitle = shelfUndoManager.redoMenuItemTitle
    }

    @discardableResult
    private func persistShelf() -> Bool {
        // A design scenario temporarily replaces the presentation with demo files. The stashed shelf remains the
        // source of truth, including slow file promises that finish while the scenario is visible.
        let items = stashedShelf?.items ?? model.shelf
        do {
            try shelfStore.save(items)
            model.shelfProblem = nil
            return true
        } catch {
            model.shelfProblem = "No he podido guardar los cambios del altillo. Tus datos anteriores siguen protegidos."
            SpikeLog.shared.record(SpikeLog.Category.shelf, "FALLO guardando el altillo: \(error.localizedDescription)")
            return false
        }
    }

    private func expireShelf() {
        guard model.scenario == nil else { return }
        let expired = shelfStore.expiredItems(in: model.shelf, expiry: model.settings.shelfExpiry)
        if !expired.isEmpty {
            SpikeLog.shared.record(SpikeLog.Category.shelf, "Caducaron \(expired.count) ítem(s)")
            remove(Set(expired.map(\.id)), undoable: false)
        } else {
            scheduleShelfExpiry()
        }
    }

    private func scheduleShelfExpiry() {
        cancel(.shelfExpiry)
        guard model.scenario == nil, let duration = model.settings.shelfExpiry.duration,
              let next = model.shelf.map({ $0.addedAt.addingTimeInterval(duration) }).min()
        else { return }
        let interval = next.timeIntervalSinceNow
        guard interval.isFinite else { return }
        if interval <= 0 {
            expireShelf()
            return
        }
        let milliseconds = max(1, Int64(min(interval * 1_000, Double(Int64.max))))
        schedule(.shelfExpiry, after: .milliseconds(milliseconds)) { [weak self] in self?.expireShelf() }
    }

    /// Observation callbacks fire once, so arm the next one after every settings change.
    private func observeShelfExpiry() {
        withObservationTracking {
            _ = model.settings.shelfExpiry
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.expireShelf()
                self.observeShelfExpiry()
            }
        }
    }

    // MARK: - Timers

    private func schedule(_ kind: TimerKind, after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        pendingTimers[kind]?.cancel()
        pendingTimers[kind] = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    private func cancel(_ kind: TimerKind) {
        pendingTimers.removeValue(forKey: kind)?.cancel()
    }

    private func cancelAllTimers() {
        pendingTimers.values.forEach { $0.cancel() }
        pendingTimers.removeAll()
    }
}

extension Animation {
    @MainActor static var openNotch: Animation {
        Tokens.Motion.open(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    @MainActor static var closeNotch: Animation {
        Tokens.Motion.close(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}
