import AltilloCore
import AppKit
import SwiftUI

/// Wires input, drag detection and the state machine to the model and the panel.
@MainActor
final class NotchCoordinator {
    let model = NotchModel()

    private var machine = NotchStateMachine()
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

    private enum TimerKind { case hoverIntent, hoverSustained, closeGrace, alert }

    func start() {
        model.actions = NotchActions(
            send: { [weak self] in self?.send($0) },
            remove: { [weak self] in self?.remove($0) },
            clearShelf: { [weak self] in self?.remove(Set(self?.model.shelf.map(\.id) ?? [])) },
            open: { item in
                if let url = item.fileURL { NSWorkspace.shared.open(url) }
                else if case let .link(url) = item.kind { NSWorkspace.shared.open(url) }
            },
            revealInFinder: { items in NSWorkspace.shared.activateFileViewerSelecting(items.compactMap(\.fileURL)) },
            quickLook: { items in QuickLookPresenter.show(items.compactMap(\.fileURL)) }
        )

        rebuildWindow()
        input.mouseMoved = { [weak self] in self?.mouseMoved(to: $0) }
        input.mouseDown = { [weak self] point, isLocal in self?.mouseDown(at: point, isLocal: isLocal) }
        input.start()
        dragDetector.start()

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.rebuildWindow() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.rebuildWindow() } })
    }

    func stop() {
        input.stop()
        dragDetector.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    /// Freezes the notch in a design-review scenario (nil returns to normal behaviour).
    func show(_ scenario: DesignScenario?) {
        model.scenario = scenario
        cancelAllTimers()
        if let scenario {
            model.tab = scenario.tab
            model.shelf = scenario.showsDemoShelf ? model.demo.shelfItems : []
            machine = NotchStateMachine(state: scenario.state)
        } else {
            machine = NotchStateMachine()
        }
        apply()
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
            controller.dropTarget.onDragEntered = { [weak self] in self?.model.isDropHovering = true }
            controller.dropTarget.onDragExited = { [weak self] in self?.model.isDropHovering = false }
            controller.dropTarget.onDrop = { [weak self] items in self?.receive(items) }
            window = controller
        }
        window?.show()
        apply()
    }

    // MARK: - Events

    private func send(_ event: NotchEvent) {
        guard model.scenario == nil || event == .escape else { return }
        if event == .escape { model.scenario = nil }
        if machine.handle(event) { apply() }
    }

    private func apply() {
        let state = machine.state
        withAnimation(state == .idle ? .closeNotch : .openNotch) {
            model.state = state
        }
        window?.panel.ignoresMouseEvents = !state.isInteractive
        if state == .idle { model.isDropHovering = false }
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
        guard let window else { return }
        let onShape = window.visibleShapeScreenRect.contains(point)
        if onShape, model.state == .idle || model.state == .peek {
            send(.click)
        } else if !onShape, model.state != .idle, model.state != .dragArmed, model.state != .dropTarget {
            send(.escape)
        }
    }

    private func dragMoved(to point: CGPoint) {
        guard let window else { return }
        send(.dragMoved(near: window.geometry.distance(to: point) < NotchLayout.dropActivationDistance))
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

    // MARK: - Shelf

    private func receive(_ items: [ShelfItem]) {
        droppedDuringCurrentDrag = true
        guard !items.isEmpty else { return }
        withAnimation(.openNotch) {
            model.shelf.append(contentsOf: items)
        }
        if model.state != .open, model.state != .dropTarget {
            // Drops that finish after the drag ended (slow promises) still show the result.
            machine = NotchStateMachine(state: .open)
            apply()
        }
    }

    private func remove(_ ids: Set<ShelfItem.ID>) {
        withAnimation(.closeNotch) {
            model.shelf.removeAll { ids.contains($0.id) }
            model.selection.subtract(ids)
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
    static let openNotch = Animation.spring(response: 0.42, dampingFraction: 0.8)
    static let closeNotch = Animation.spring(response: 0.45, dampingFraction: 1.0)
}
