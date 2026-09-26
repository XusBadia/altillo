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
    /// The live notch: the one that opens, peeks and takes drops. Only ever one, on the screen the user works with.
    private var window: NotchWindowController?
    /// "All of them": the notch at rest on every other screen, keyed by display.
    private var restingNotches: [CGDirectDisplayID: RestingNotchController] = [:]
    /// The connected screens, refreshed on every screen change so the pointer's hot path never asks AppKit.
    private var screens: [ScreenDescriptor] = []
    /// Displays whose current space is a full-screen app (only tracked when the setting makes the notch step aside).
    private var fullScreenDisplays: Set<CGDirectDisplayID> = []
    private var displayMode: DisplayMode = .notch
    private var appliedScreenSettings: (mode: DisplayMode, fullScreen: FullScreenBehaviour)?
    private let input = InputMonitor()
    private lazy var dragDetector = DragDetector(callbacks: .init(
        began: { [weak self] in
            // A new drag starts far away until it reports where it is (a stale value would flash the notch over a
            // full-screen app for a frame).
            self?.model.dragProximity = 0
            self?.send(.dragBegan)
        },
        moved: { [weak self] point in self?.dragMoved(to: point) },
        ended: { [weak self] in self?.dragEnded() }
    ))
    private var observers: [NSObjectProtocol] = []
    private var pendingTimers: [TimerKind: Task<Void, Never>] = [:]
    private var droppedDuringCurrentDrag = false
    /// The section the contextual ear stood for when the user reached for it (the hover's dwell or a click on it),
    /// honoured only by the open that same gesture causes. Nothing else ever switches the section on its own.
    private var indicatorTarget: NotchModule?
    private var isHovering = false
    private var isStarted = false
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var swipe = SwipeTracker()
    private let hotKey = GlobalHotKey()
    private lazy var calendarAlerts = CalendarAlertSource { [weak self] in self?.post($0) }
    private lazy var nowPlayingAlerts = NowPlayingAlertSource { [weak self] in self?.post($0) }
    /// The user's shelf, kept aside while a design scenario shows demo items.
    private var stashedShelf: (
        items: [ShelfItem], selection: Set<ShelfItem.ID>, isReceivingDrop: Bool, problem: String?
    )?

    private enum TimerKind { case hoverIntent, hoverSustained, closeGrace, alert, shelfExpiry, fullScreenSettle }

    init(shelfStore: ShelfStore = .standard) {
        self.shelfStore = shelfStore
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let restoration = shelfStore.restore(expiry: model.settings.shelfExpiry)
        model.shelf = restoration.items
        if case .recoveredFromCorruptSnapshot = restoration {
            SpikeLog.shared.record(SpikeLog.Category.shelf, "The damaged state was set aside; the shelf starts empty")
        } else if case .failed = restoration {
            model.shelfProblem = String(localized: "I couldn't restore the shelf. I've kept its data so nothing gets overwritten.")
        }
        shelfUndoManager.removeAllActions()
        updateUndoState()
        observeShelfExpiry()
        scheduleShelfExpiry()

        model.actions = NotchActions(
            send: { [weak self] event in
                guard let self else { return }
                self.send(event)
                // An explicit open (the menu's "Open Altillo", ⌘⌥A) takes keyboard focus, like a click on the notch:
                // Tab, the arrows and Esc work straight away, and VoiceOver lands inside.
                if event == .click, self.model.state == .open { self.window?.panel.makeKey() }
            },
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
            openDrawerSettings: { SettingsWindowController.shared.show(tab: .drawer) },
            addToShelf: { [weak self] items in self?.add(items) },
            takeKeyboardFocus: { [weak self] in
                guard let self, self.model.state == .open else { return }
                self.window?.panel.makeKey()
            },
            openFromIndicator: { [weak self] module in self?.openFromIndicator(module) },
            beginEditing: { [weak self] in self?.beginEditing() },
            endEditing: { [weak self] in self?.endEditing() },
            haptic: { Haptics.perform($0) }
        )
        model.assistant.context = AssistantContext(
            shelfItems: { [weak self] in self?.stashedShelf?.items ?? self?.model.shelf ?? [] },
            addToShelf: { [weak self] items in self?.add(items) },
            postAlert: { [weak self] alert in self?.post(alert) },
            isVisible: { [weak self] in self?.model.state == .open && self?.model.module == .assistant }
        )

        model.drawer.prepareForMenuBarInteraction = { [weak self] in
            guard let self else { return }
            self.cancel(.hoverIntent)
            self.cancel(.hoverSustained)
            self.isHovering = false
            self.send(.escape)
        }
        appliedScreenSettings = (model.settings.displayMode, model.settings.fullScreenBehaviour)
        arrangeScreens()
        model.drawer.start()
        input.mouseMoved = { [weak self] in self?.mouseMoved(to: $0) }
        input.mouseDown = { [weak self] point, isLocal, isRight in
            self?.mouseDown(at: point, isLocal: isLocal, isRight: isRight)
        }
        input.start()
        dragDetector.start()
        installKeyMonitor()
        installScrollMonitor()
        observeSettings()
        // AI usage: last numbers from disk at once, then its own 5-minute rhythm (paused while the Mac sleeps).
        model.usage.postAlert = { [weak self] alert in self?.post(alert) }
        model.usage.start()
        // Live agents: hook events over the socket plus the agents' own session files (phase 4).
        model.agentHub.postAlert = { [weak self] alert in self?.post(alert) }
        model.agentHub.isModuleEnabled = { [weak model] in model?.settings.isEnabled(.agents) ?? true }
        model.agentHub.start()
        // Kitchen timers (phase 12): running ones come back from disk and ring with the notch closed.
        model.timers.postAlert = { [weak self] alert in self?.post(alert) }
        model.timers.start()
        // `-openModule usage` (with `-openAltillo YES`) opens on that section: reviews of live data without a click.
        if let name = UserDefaults.standard.string(forKey: "openModule"), let module = NotchModule(rawValue: name),
           model.settings.modules.contains(module) {
            model.jump(to: module)
        }

        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        // Settings › Sections › "Customize in the Notch…".
        observers.append(center.addObserver(forName: .altilloCustomizeNotch, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginEditing() }
        })
        // Displays connected, disconnected, rearranged or resized; the lid closed with an external display.
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.arrangeScreens() } })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated {
            self?.arrangeScreens()
            self?.expireShelf()
        } })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.arrangeScreens() } })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.arrangeScreens() } })
        // Going to sleep (or to another user's session) with the notch open, peeking or armed for a drag: it comes
        // back at rest, never stuck open or stuck taking clicks.
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resetToIdle() }
            })
        }
        // A full-screen app arrives or leaves with a space change; a game or a presentation that hides the menu bar
        // on its own arrives with its app.
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fullScreenMayHaveChanged() }
            })
        }
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
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        hotKey.unregister()
        calendarAlerts.update(enabled: false)
        nowPlayingAlerts.update(enabled: false)
        model.nowPlaying.watchInBackground(false)
        model.usage.stop()
        model.agentHub.stop()
        model.timers.stop()
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
            model.jump(to: scenario.module)
            model.shelf = scenario.showsDemoShelf ? model.demo.shelfItems : []
            model.selection = []
            model.isReceivingDrop = scenario == .openShelfLoading
            model.shelfProblem = scenario == .openShelfError
                ? String(localized: "I couldn't put away what you dropped. You can try again.")
                : nil
            model.alert = scenario == .peekAlert ? .demoMeeting : nil
            machine = NotchStateMachine(state: scenario.state)
        } else {
            model.alert = nil
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

    // MARK: - Screens

    /// Puts the notch on the screens the display mode asks for. Idempotent: it runs on every screen change, wake,
    /// session switch and display-mode change, reuses the panels it has and never leaves two live notches.
    private func arrangeScreens() {
        displayMode = model.settings.displayMode
        screens = ScreenService.descriptors
        guard let plan = ScreenService.plan(
            for: displayMode, screens: screens, pointer: NSEvent.mouseLocation,
            currentLive: window?.screenID, canMove: canMoveLive
        ) else {
            // No screen at all (the lid closed without an external display): nothing to show until one is back.
            window?.setShown(false)
            restingNotches.values.forEach { $0.setShown(false) }
            return
        }
        placeLive(on: plan.live)

        // Resting notches for every screen in "All of them" (the live one's stays hidden under it).
        let restingIDs = plan.screens.count > 1 ? Set(plan.screens.map(\.id)) : []
        for (id, resting) in restingNotches where !restingIDs.contains(id) {
            resting.close()
            restingNotches[id] = nil
        }
        for screen in plan.screens where restingIDs.contains(screen.id) {
            if let resting = restingNotches[screen.id] {
                resting.update(screen: screen)
            } else {
                restingNotches[screen.id] = RestingNotchController(screen: screen)
            }
        }
        let kind = plan.live.hasNotch ? "notch" : "island"
        SpikeLog.shared.record("screens", "\(screens.count) screen(s), mode \(displayMode.rawValue), live on "
            + "\(plan.live.id) (\(kind)), \(restingNotches.count) resting")
        refreshFullScreen()
        apply()
    }

    /// The live notch may change screens only while nobody is using it: at rest, or waiting for a drag to come close.
    private var canMoveLive: Bool {
        model.scenario == nil && (machine.state == .idle || machine.state == .dragArmed)
    }

    /// Moves the live notch (creating it the first time) and gives the views that screen's notch or island.
    private func placeLive(on screen: ScreenDescriptor) {
        guard let window else {
            let controller = NotchWindowController(screen: screen, model: model)
            controller.dropTarget.zoneAt = { [weak self, weak controller] point in
                guard let self, let controller else { return nil }
                return self.dropZone(at: point, in: controller.dropTarget)
            }
            controller.dropTarget.onZoneChanged = { [weak self] zone in self?.model.dropZone = zone }
            controller.dropTarget.onAirDrop = { [weak self] items in self?.sendViaAirDrop(items) }
            controller.dropTarget.onAsk = { [weak self] items in self?.askAbout(items) }
            // Accepted before slow file promises (Photos, Mail) resolve, so the notch stays open while they arrive.
            controller.dropTarget.onDropAccepted = { [weak self] in self?.dropAccepted() }
            controller.panel.onCloseRequest = { [weak self] in self?.send(.escape) }
            controller.dropTarget.onDrop = { [weak self] items in self?.receive(items) }
            window = controller
            syncModelGeometry(with: screen)
            return
        }
        let changedScreen = window.screenID != screen.id
        guard window.update(screen: screen) else { return }
        syncModelGeometry(with: screen)
        guard changedScreen else { return }
        // The pointer is somewhere else now: hovering starts over on this screen.
        cancel(.hoverIntent)
        cancel(.hoverSustained)
        isHovering = false
        // Only a screen that went away moves a notch in use; it comes back at rest rather than open elsewhere.
        if machine.state != .idle, machine.state != .dragArmed { resetToIdle() }
        updatePanelVisibility()
    }

    /// The chrome follows the live screen's notch (or island) at once: the move is a jump, not a morph.
    private func syncModelGeometry(with screen: ScreenDescriptor) {
        let size = screen.geometry.notchRect.size
        guard model.notchSize != size || model.hasNotch != screen.hasNotch else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.hasNotch = screen.hasNotch
            model.notchSize = size
        }
    }

    /// "The one with the pointer" and "All of them": the live notch goes to the pointer's screen, only while it's at
    /// rest (or armed for a drag), so it never jumps away from under the user. Driven by the mouse events Altillo
    /// already gets; nothing polls.
    private func followPointer(to point: CGPoint) {
        guard displayMode == .cursor || displayMode == .all, let window, canMoveLive,
              !NotchGeometry.containsPointer(point, in: window.geometry.screenFrame),
              let target = ScreenService.screen(at: point, in: screens), target.id != window.screenID
        else { return }
        placeLive(on: target)
        if displayMode == .cursor { refreshFullScreen() }
        updatePanelVisibility()
    }

    /// Alerts and the Ask shortcut aren't tied to the pointer: in "All of them" they show on the home screen (the
    /// notch, else the menu bar), in "The one with the pointer" wherever the pointer is.
    private func moveLiveForAttention() {
        guard canMoveLive, machine.state == .idle,
              let target = ScreenService.attentionScreen(for: displayMode, screens: screens, pointer: NSEvent.mouseLocation),
              target.id != window?.screenID
        else { return }
        placeLive(on: target)
        updatePanelVisibility()
    }

    // MARK: - Full screen

    /// Looks again now and once the full-screen animation has settled (it takes about half a second).
    private func fullScreenMayHaveChanged() {
        guard isStarted else { return }
        refreshFullScreen()
        guard model.settings.fullScreenBehaviour.quietensOverFullScreen else { return }
        schedule(.fullScreenSettle, after: .milliseconds(700)) { [weak self] in self?.refreshFullScreen() }
    }

    private func refreshFullScreen() {
        let behaviour = model.settings.fullScreenBehaviour
        // "Stay as usual" never needs to know, so it never asks the window server.
        let displays = behaviour.quietensOverFullScreen ? FullScreenDetector.fullScreenDisplays(among: screens) : []
        if displays != fullScreenDisplays {
            fullScreenDisplays = displays
            SpikeLog.shared.record("screens", "Full-screen app on \(displays.count) display(s): \(displays.sorted())")
            // A peek (an alert, a hover hint) over a screen that just went full screen leaves with it.
            if isQuietOverFullScreen, machine.state == .peek {
                cancel(.hoverIntent)
                cancel(.hoverSustained)
                isHovering = false
                send(.escape)
            }
        }
        updatePanelVisibility()
    }

    /// The live notch is over a full-screen app and the setting asks it to keep quiet: no ears, no hover, no alerts.
    private var isQuietOverFullScreen: Bool {
        guard model.scenario == nil, let window else { return false }
        return fullScreenDisplays.contains(window.screenID) && model.settings.fullScreenBehaviour.quietensOverFullScreen
    }

    /// Orders each panel in or out for the current state. Cheap: only acts when something changes.
    private func updatePanelVisibility() {
        guard let window else { return }
        let behaviour = model.settings.fullScreenBehaviour
        let liveHidden = model.scenario == nil && fullScreenDisplays.contains(window.screenID)
            && behaviour.hidesNotch(in: machine.state, dragIsClose: model.dragProximity > 0)
        if window.isShown == liveHidden, !fullScreenDisplays.isEmpty {
            SpikeLog.shared.record("screens", "\(liveHidden ? "Out of sight" : "Back") over a full-screen app, \(machine.state)")
        }
        window.setShown(!liveHidden)
        for (id, resting) in restingNotches {
            let hidden = id == window.screenID || (fullScreenDisplays.contains(id) && behaviour.quietensOverFullScreen)
            resting.setShown(!hidden)
        }
    }

    /// Back to rest: after sleep, a session switch, or when the screen under a notch in use goes away. Never leaves
    /// the notch open, peeking or taking clicks.
    private func resetToIdle() {
        guard isStarted, model.scenario == nil else { return }
        cancel(.hoverIntent)
        cancel(.hoverSustained)
        cancel(.closeGrace)
        cancel(.alert)
        isHovering = false
        indicatorTarget = nil
        model.dragProximity = 0
        guard machine.state != .idle else { return }
        machine = NotchStateMachine(opensOnHover: model.settings.opensOnHover)
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
        let previous = model.state
        if state != previous { SpikeLog.shared.record("notch", "\(previous) → \(state)") }
        let indicator = indicatorTarget
        if state != .idle, state != .peek { indicatorTarget = nil }
        withAnimation(state == .idle ? .closeNotch : .openNotch) {
            // Reaching for an alert opens the section it's about.
            if state == .open, previous == .peek, let alert = model.alert, model.scenario == nil {
                if let module = alert.module, model.settings.modules.contains(module) { model.jump(to: module) }
                model.alert = nil
            } else if state == .open, previous == .idle || previous == .peek, let indicator, model.scenario == nil,
                      model.settings.modules.contains(indicator) {
                // Reaching for the contextual ear opens what it's about (music playing: Now playing).
                model.jump(to: indicator)
            }
            if state == .idle || state == .dragArmed || state == .dropTarget {
                model.alert = nil
                model.isEditing = false
            }
            model.state = state
        }
        if state == .idle {
            cancel(.alert)
            // Closed without the pointer leaving (Esc, the shortcut, a click outside): re-measure it against the
            // resting hover area, or a pointer that already left would never open the notch again on its way back.
            if previous != .idle, let window {
                // Only the resting area counts: the open shape it came from is already gone.
                isHovering = NotchGeometry.containsPointer(NSEvent.mouseLocation, in: window.geometry.hoverRect())
            }
        }
        if let panel = window?.panel {
            panel.ignoresMouseEvents = !state.isInteractive
            panel.allowsKey = state == .open
            if state != .open { panel.relinquishKey() }
        }
        if state == .idle || state == .open { model.dropZone = nil }
        if state != .open { cancel(.closeGrace) }
        updatePanelVisibility()
    }

    private func mouseMoved(to point: CGPoint) {
        guard !model.drawer.isPerformingMenuBarInteraction else { return }
        guard model.scenario == nil else { return }
        followPointer(to: point)
        guard let window else { return }
        let visibleArea = window.visibleShapeScreenRect
        let area = model.state == .idle ? window.geometry.hoverRect().union(visibleArea) : visibleArea
        // Over a full-screen app the resting notch doesn't open on hover (a notch the user opened still stays).
        let inside = NotchGeometry.containsPointer(point, in: area) && !(isQuietOverFullScreen && model.state == .idle)
        guard inside != isHovering else { return }
        isHovering = inside

        if inside {
            cancel(.closeGrace)
            schedule(.hoverIntent, after: NotchLayout.Timing.hoverIntent) { [weak self] in
                // Where the pointer rests once the dwell is over, not where it came in.
                self?.aimAtIndicator(NSEvent.mouseLocation)
                self?.send(.hoverIntent)
                self?.schedule(.hoverSustained, after: NotchLayout.Timing.hoverSustained) { self?.send(.hoverSustained) }
            }
        } else {
            cancel(.hoverIntent)
            cancel(.hoverSustained)
            indicatorTarget = nil
            send(.pointerLeft)
            if model.state == .open {
                schedule(.closeGrace, after: NotchLayout.Timing.closeGrace) { [weak self] in
                    // Typing, or waiting for an answer: stay until Esc or a click outside.
                    guard let self, !self.model.holdsOpen else { return }
                    self.send(.closeGraceElapsed)
                }
            }
        }
    }

    private func mouseDown(at point: CGPoint, isLocal: Bool, isRight: Bool) {
        guard !model.drawer.isPerformingMenuBarInteraction else { return }
        // Design scenarios stay frozen (e.g. while taking a ⇧⌘4 screenshot); leave them with Esc or the menu.
        guard let window, model.scenario == nil else { return }
        // A notch kept out of sight over a full-screen app has no shape to click.
        let onShape = window.isShown && NotchGeometry.containsPointer(point, in: window.visibleShapeScreenRect)
        // Right-click on the closed notch (or a peek): edit it in place. On the open notch, right-clicks belong to
        // the views (a shelf thing's menu); the open notch has its own way into edit mode.
        if isRight {
            if onShape, model.state == .idle || model.state == .peek { beginEditing() }
            else if !onShape, model.state == .open { send(.escape) }
            return
        }
        if onShape, model.state == .idle || model.state == .peek {
            aimAtIndicator(point)
            send(.click)
            // An explicit click means the user wants to interact: take keyboard focus (hover-opening never does).
            window.panel.makeKey()
        } else if !onShape, model.state != .idle, model.state != .dragArmed, model.state != .dropTarget {
            send(.escape)
        }
    }

    private func dragMoved(to point: CGPoint) {
        // A drag waiting to come close follows the pointer to its screen, so it's that screen's notch that opens.
        if model.state == .dragArmed { followPointer(to: point) }
        guard let window else { return }
        // Near the notch, or anywhere over the open notch (plus a margin): the open shelf reaches far below the
        // notch itself, so measuring only from the notch would close it under the pointer.
        let distance = window.geometry.distance(to: point)
        model.dragProximity = 1 - min(max(distance / 300, 0), 1)
        let nearNotch = distance < NotchLayout.dropActivationDistance
        let overOpenNotch = model.state == .dropTarget
            && window.visibleShapeScreenRect.insetBy(dx: -NotchLayout.dropKeepOpenMargin, dy: -NotchLayout.dropKeepOpenMargin)
                .contains(point)
        // "Hide" over a full-screen app: not even a drag brings the notch.
        let takesDrops = !isQuietOverFullScreen || model.settings.fullScreenBehaviour.takesDropsOverFullScreen
        send(.dragMoved(near: takesDrops && (nearNotch || overOpenNotch)))
        // "Only when you drag something": the notch shows up as the drag comes close.
        updatePanelVisibility()
    }

    /// Zone under a point of the drop target view. Zone frames come from SwiftUI in the hosting view's
    /// top-left coordinates; anywhere else on the open notch counts as the shelf, outside it nothing accepts.
    private func dropZone(at point: NSPoint, in view: NSView) -> DropZone? {
        guard model.state == .dropTarget else { return nil }
        let topLeft = CGPoint(x: point.x, y: view.bounds.height - point.y)
        if model.dropZoneFrames[.airDrop]?.contains(topLeft) == true { return .airDrop }
        if model.offersAskDrop, model.dropZoneFrames[.ask]?.contains(topLeft) == true { return .ask }
        if model.dropZoneFrames[.shelf]?.contains(topLeft) == true { return .shelf }
        return nil
    }

    /// Dropped on "Ask about it": Ask reads it for the next question, and the field takes the keyboard.
    private func askAbout(_ items: [ShelfItem]) {
        model.isReceivingDrop = false
        guard !items.isEmpty else { return }
        if model.module != .assistant, model.settings.modules.contains(.assistant) { model.jump(to: .assistant) }
        model.assistant.attach(items)
        model.assistant.requestFocus()
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
            SpikeLog.shared.record(SpikeLog.Category.drop, "AirDrop unavailable for \(items.count) item(s)")
            NSSound.beep()
            return
        }
        SpikeLog.shared.record(SpikeLog.Category.drop, "AirDrop: sending \(items.count) item(s)")
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
            isHovering = NotchGeometry.containsPointer(NSEvent.mouseLocation, in: window.visibleShapeScreenRect)
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
        // Edit mode handles its own keys (⌘Z undoes edits, arrows and Space move sections); Esc still closes.
        if model.isEditing { return false }
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        // ⌘1…⌘9 jump to a section, ⌃Tab / ⌃⇧Tab walk through them (like tabs everywhere else on the Mac).
        if flags == .command, let index = Self.digitKeyCodes.firstIndex(of: keyCode) {
            let modules = model.settings.modules
            guard modules.indices.contains(index) else { return true }
            selectModule(modules[index])
            return true
        }
        if keyCode == 48, flags.contains(.control) { // Tab
            stepModule(flags.contains(.shift) ? -1 : 1, wraps: true)
            return true
        }
        // A text field is editing: ⌫, ⌘Z and Esc belong to it (Esc still closes the notch).
        if window?.panel.firstResponder is NSTextView {
            if keyCode == 53 { send(.escape); return true }
            return false
        }
        guard model.module == .shelf else { return false }
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

    /// Key codes of 1…9 on the top row.
    private static let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    // MARK: - Sections

    private func selectModule(_ module: NotchModule) {
        guard module != model.module else { return }
        withAnimation(Desvan.Motion.pick(Desvan.Motion.section,
                                         reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) {
            model.select(module)
        }
    }

    /// Moves one section left or right. At either end it stays put (with a tap: there's nothing further) unless
    /// `wraps`, which the keyboard uses.
    @discardableResult
    private func stepModule(_ offset: Int, wraps: Bool = false) -> Bool {
        if let target = model.neighbour(offset) {
            selectModule(target)
            return true
        }
        guard wraps, let target = offset > 0 ? model.settings.modules.first : model.settings.modules.last else {
            return false
        }
        selectModule(target)
        return true
    }

    /// Two-finger horizontal swipes on the open notch change section, one per gesture. Vertical scrolls, and
    /// horizontal ones that start over content scrolling sideways itself (`horizontalScrollRegions`: the usage cards,
    /// the shelf's row, the drawer's icons), pass through untouched.
    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleScroll(event) ?? false }
            return handled ? nil : event
        }
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        guard let window, event.windowNumber == window.panel.windowNumber, model.state == .open,
              model.scenario == nil else { return false }
        // Only real trackpad gestures (with phases); a mouse wheel scrolls content as usual. Not while editing.
        guard event.hasPreciseScrollingDeltas, !model.isEditing else { return false }
        if event.phase == .began {
            // Over content that scrolls sideways the whole gesture belongs to it, even at its edge: it never
            // changes section. Regions are in the hosting view's top-left coordinates, like the drop zones.
            let local = window.panel.contentView?.convert(event.locationInWindow, from: nil) ?? .zero
            let topLeft = CGPoint(x: local.x, y: (window.panel.contentView?.bounds.height ?? 0) - local.y)
            swipe.begin(ignored: SwipeTracker.contentScrolls(at: topLeft, in: model.horizontalScrollRegions.values))
        }
        // With natural scrolling the delta follows the fingers; otherwise it's inverted.
        let fingersDX = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        switch swipe.track(dx: fingersDX, dy: event.scrollingDeltaY, phase: event.phase, momentum: event.momentumPhase) {
        case .pass:
            return false
        case .swallow:
            return true
        case let .step(direction):
            // Fingers moving left bring the next section in from the right, like pages.
            if stepModule(direction) {
                Haptics.perform(.snap)
            } else {
                model.bumpEdge(direction)
            }
            return true
        }
    }

    // MARK: - Contextual ear

    /// Remembers which section the contextual ear under `point` stands for, if the pointer is on it.
    private func aimAtIndicator(_ point: CGPoint) {
        indicatorTarget = indicatorModule(at: point)
    }

    /// The section behind either indicator at `point` (screen coordinates), including a fixed Calendar/Shelf/etc.
    /// indicator and the live contextual fallback.
    private func indicatorModule(at point: CGPoint) -> NotchModule? {
        guard model.scenario == nil, model.alert == nil,
              model.state == .idle || model.state == .peek,
              let window, window.isShown
        else { return nil }
        let chrome = NotchChrome(model: model)
        guard chrome.face == .ears || chrome.face == .peek(.hint) else { return nil }
        // The island's hint is one centred row; elsewhere the indicators flank the camera's clear band.
        let clearWidth = chrome.face == .ears || chrome.hasNotch ? chrome.clearWidth : 0
        let shape = window.visibleShapeScreenRect
        guard shape.contains(point) else { return nil }
        let side: EarSide
        if point.x < shape.midX - clearWidth / 2 { side = .left }
        else if point.x > shape.midX + clearWidth / 2 { side = .right }
        else { return nil }
        let fallback = model.ears.contextualFallbackSide(for: model)
        let content = side == .left ? model.settings.leftEar : model.settings.rightEar
        let module = fallback == side || content == .automatic ? model.contextualActivity.module : content.module
        guard let module, model.settings.modules.contains(module) else { return nil }
        return module
    }

    /// VoiceOver's action on the contextual ear: open straight on its section, like a click on it.
    private func openFromIndicator(_ module: NotchModule) {
        guard model.scenario == nil, model.settings.modules.contains(module),
              model.state == .idle || model.state == .peek else { return }
        indicatorTarget = module
        send(.click)
        window?.panel.makeKey()
    }

    // MARK: - Alerts

    /// Shows an alert as a peek if the notch is idle (or already showing another alert, which it replaces).
    /// Never interrupts an open notch, a drag or a frozen design scenario.
    func post(_ alert: NotchAlert) {
        guard isStarted, model.scenario == nil else { return }
        guard machine.state == .idle || (machine.state == .peek && model.alert != nil) else { return }
        moveLiveForAttention()
        // Over a full-screen app the notch keeps quiet unless the user asked for it as usual.
        guard !isQuietOverFullScreen else { return }
        withAnimation(.openNotch) { model.alert = alert }
        announce(alert)
        if machine.state == .idle { send(.alert) }
        schedule(.alert, after: alert.duration) { [weak self] in self?.expireAlert() }
    }

    /// VoiceOver users hear what the peek shows (it never takes focus).
    private func announce(_ alert: NotchAlert) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        let text = [alert.title, alert.detail, alert.trailing].compactMap { $0 }.joined(separator: ", ")
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
    }

    private func expireAlert() {
        guard model.alert != nil else { return }
        send(.alertExpired)
        // Still under the pointer: it stays until the pointer leaves (and then closes like any peek).
    }

    // MARK: - Edit mode

    /// Right-click on the notch (or the menu's "Customize the Notch…"): open it in edit mode, ready to rearrange.
    func beginEditing() {
        guard model.scenario == nil, model.state != .dragArmed, model.state != .dropTarget else { return }
        indicatorTarget = nil
        model.alert = nil
        cancel(.alert)
        cancel(.closeGrace)
        if model.state != .open {
            machine = NotchStateMachine(state: .open, opensOnHover: model.settings.opensOnHover)
        }
        withAnimation(.openNotch) { model.isEditing = true }
        apply()
        window?.panel.makeKey()
    }

    func endEditing() {
        guard model.isEditing else { return }
        withAnimation(.openNotch) { model.isEditing = false }
    }

    // MARK: - Assistant

    /// The global shortcut: opens the notch on the assistant, ready to type. Pressed again while it's showing,
    /// it closes the notch.
    func summonAssistant() {
        guard model.scenario == nil, model.settings.modules.contains(.assistant) else {
            NSSound.beep()
            return
        }
        if model.state == .open, model.module == .assistant {
            send(.escape)
            return
        }
        guard model.state == .idle || model.state == .peek || model.state == .open else { return }
        moveLiveForAttention()
        indicatorTarget = nil
        model.alert = nil
        cancel(.alert)
        model.jump(to: .assistant)
        machine = NotchStateMachine(state: .open, opensOnHover: model.settings.opensOnHover)
        apply()
        window?.panel.makeKey()
        model.assistant.requestFocus()
    }

    // MARK: - Settings

    /// Observation callbacks fire once, so re-arm after every change.
    private func observeSettings() {
        // Only these reads are tracked; applying happens outside, so whatever `applySettings` touches (the log,
        // the shortcut's problem) never becomes a dependency.
        withObservationTracking {
            let settings = model.settings
            _ = (settings.assistantHotKey, settings.modules, settings.alertsForCalendar, settings.alertsForNowPlaying)
            _ = (settings.leftEar, settings.rightEar, settings.calendarHiddenIDs)
            _ = (settings.displayMode, settings.fullScreenBehaviour)
            _ = settings.usageDisabledProviders
            _ = model.calendar.access
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.observeSettings()
            }
        }
        applySettings()
    }

    private func applySettings() {
        let settings = model.settings
        model.agentHub.moduleAvailabilityChanged()
        let accepted = hotKey.register(settings.assistantHotKey, enabled: settings.modules.contains(.assistant)) {
            [weak self] in self?.summonAssistant()
        }
        settings.assistantHotKeyProblem = accepted
            ? nil
            : String(localized: "Another app already uses this shortcut. Pick a different one.")
        calendarAlerts.update(enabled: settings.alertsForCalendar && settings.modules.contains(.calendar))
        nowPlayingAlerts.update(enabled: settings.alertsForNowPlaying && settings.modules.contains(.nowPlaying))
        calendarAlerts.accessMayHaveChanged()
        model.ears.update(left: settings.leftEar, right: settings.rightEar, modules: settings.modules)
        model.nowPlaying.watchInBackground(
            EarsLogic.watchesPlayback(left: settings.leftEar, right: settings.rightEar, modules: settings.modules)
        )
        // Usage refreshes while its section is on, or while something publishes the numbers (the iPhone).
        model.usage.setSectionEnabled(settings.modules.contains(.usage))
        model.usage.providersMayHaveChanged()
        if appliedScreenSettings?.mode != settings.displayMode
            || appliedScreenSettings?.fullScreen != settings.fullScreenBehaviour {
            appliedScreenSettings = (settings.displayMode, settings.fullScreenBehaviour)
            arrangeScreens()
        }
    }

    // MARK: - Shelf

    /// Things put on the shelf from inside Altillo: same landing as a drop, and the notch shows them.
    private func add(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        if model.scenario != nil, stashedShelf != nil {
            stashedShelf?.items.append(contentsOf: items)
            persistShelf()
            return
        }
        withAnimation(.openNotch) {
            model.shelf.append(contentsOf: items)
        }
        persistShelf()
        scheduleShelfExpiry()
        Haptics.perform(.land)
    }

    private func receive(_ items: [ShelfItem]) {
        droppedDuringCurrentDrag = true
        if model.scenario != nil, stashedShelf != nil {
            // A slow file promise can finish while a frozen design scenario is on screen. Its loading/error state
            // and result belong to the real shelf, never to the demo that temporarily occupies `model.shelf`.
            stashedShelf?.isReceivingDrop = false
            guard !items.isEmpty else {
                stashedShelf?.problem = String(localized: "I couldn't put away what you dropped. You can try again.")
                return
            }
            stashedShelf?.problem = nil
            stashedShelf?.items.append(contentsOf: items)
            persistShelf()
            return
        }
        model.isReceivingDrop = false
        guard !items.isEmpty else {
            model.shelfProblem = String(localized: "I couldn't put away what you dropped. You can try again.")
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
            shelfUndoManager.setActionName(String(localized: "Take Down"))
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
        shelfUndoManager.setActionName(String(localized: "Take Down"))
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
            model.shelfProblem = String(localized: "I couldn't save the shelf's changes. Your earlier data is still safe.")
            SpikeLog.shared.record(SpikeLog.Category.shelf, "FAILED saving the shelf: \(error.localizedDescription)")
            return false
        }
    }

    private func expireShelf() {
        guard model.scenario == nil else { return }
        let expired = shelfStore.expiredItems(in: model.shelf, expiry: model.settings.shelfExpiry)
        if !expired.isEmpty {
            SpikeLog.shared.record(SpikeLog.Category.shelf, "\(expired.count) item(s) expired")
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
