import AltilloCore
import AppKit

/// A screen as the notch sees it: who it is, where it is and where its notch (or island) goes. Pure values, so the
/// choice of screens can be tested against any arrangement without real displays.
struct ScreenDescriptor: Equatable, Identifiable, Sendable {
    /// `CGDirectDisplayID`: stable while the display stays connected, unlike an `NSScreen` instance.
    let id: CGDirectDisplayID
    let geometry: NotchGeometry
    /// The same frame in Quartz window coordinates (origin at the top-left of the menu-bar screen, y grows
    /// downwards), to compare with `CGWindowListCopyWindowInfo` bounds.
    let windowServerFrame: CGRect

    var frame: CGRect { geometry.screenFrame }
    var hasNotch: Bool { geometry.hasNotch }

    init(id: CGDirectDisplayID, geometry: NotchGeometry, primaryHeight: CGFloat) {
        self.id = id
        self.geometry = geometry
        windowServerFrame = ScreenService.windowServerFrame(for: geometry.screenFrame, primaryHeight: primaryHeight)
    }

    func contains(_ point: CGPoint) -> Bool {
        NotchGeometry.containsPointer(point, in: frame)
    }
}

/// Which screens show Altillo and which of them hosts the live notch (the one that opens, takes drops and peeks).
struct ScreenPlan: Equatable, Sendable {
    /// Every screen with a notch on it, in `NSScreen.screens` order. Only "All of them" has more than one.
    var screens: [ScreenDescriptor]
    var live: ScreenDescriptor

    /// Screens that only show the resting notch: the live notch lives on the other one.
    var resting: [ScreenDescriptor] { screens.filter { $0.id != live.id } }
}

enum ScreenService {
    @MainActor
    static func geometry(for screen: NSScreen) -> NotchGeometry {
        NotchGeometry(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea
        )
    }

    @MainActor
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// The connected screens, the one with the menu bar first (`NSScreen.screens` order).
    @MainActor
    static var descriptors: [ScreenDescriptor] {
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        return screens.compactMap { screen in
            guard let id = displayID(of: screen), !screen.frame.isEmpty else { return nil }
            return ScreenDescriptor(id: id, geometry: geometry(for: screen), primaryHeight: primaryHeight)
        }
    }

    /// AppKit screen coordinates (bottom-left origin) to Quartz window coordinates (top-left origin of the
    /// menu-bar screen).
    static func windowServerFrame(for frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    // MARK: - Choosing screens

    /// Where the notch lives when nothing else decides: the screen with a hardware notch, otherwise the one with the
    /// menu bar (`DisplayMode.notch`).
    static func home(in screens: [ScreenDescriptor]) -> ScreenDescriptor? {
        screens.first(where: \.hasNotch) ?? screens.first
    }

    static func screen(at point: CGPoint, in screens: [ScreenDescriptor]) -> ScreenDescriptor? {
        screens.first { $0.contains(point) }
    }

    /// The screens for a display mode.
    ///
    /// - Parameters:
    ///   - pointer: where the pointer is; "the one with the pointer" and "all of them" put the live notch there.
    ///   - currentLive: the screen the live notch is on now. It stays there when `canMove` is false (the notch is in
    ///     use: open, peeking or taking a drop) as long as that screen is still connected and still in the plan.
    static func plan(
        for mode: DisplayMode,
        screens: [ScreenDescriptor],
        pointer: CGPoint?,
        currentLive: CGDirectDisplayID?,
        canMove: Bool
    ) -> ScreenPlan? {
        guard let home = home(in: screens), let primary = screens.first else { return nil }
        let underPointer = pointer.flatMap { screen(at: $0, in: screens) }
        let current = currentLive.flatMap { id in screens.first { $0.id == id } }

        let shown: [ScreenDescriptor]
        var live: ScreenDescriptor
        switch mode {
        case .notch:
            shown = [home]
            live = home
        case .main:
            shown = [primary]
            live = primary
        case .cursor:
            live = underPointer ?? current ?? home
            shown = [live]
        case .all:
            shown = screens
            live = underPointer ?? current ?? home
        }
        // A notch in use never jumps away from under the user.
        if !canMove, let current, shown.contains(current) || mode == .cursor {
            live = current
        }
        return ScreenPlan(screens: mode == .cursor ? [live] : shown, live: live)
    }

    /// Where something that isn't tied to the pointer shows up (an alert, the Ask shortcut): the home screen when
    /// every screen has a notch, the pointer's screen when the notch follows it, the only screen otherwise.
    static func attentionScreen(
        for mode: DisplayMode, screens: [ScreenDescriptor], pointer: CGPoint?
    ) -> ScreenDescriptor? {
        switch mode {
        case .notch: home(in: screens)
        case .main: screens.first
        case .all: home(in: screens)
        case .cursor: pointer.flatMap { screen(at: $0, in: screens) } ?? home(in: screens)
        }
    }
}

// MARK: - Full screen

/// One on-screen window as the window server reports it (`CGWindowListCopyWindowInfo`), in Quartz coordinates.
struct WindowSnapshot: Equatable, Sendable {
    var ownerPID: pid_t
    var layer: Int
    var bounds: CGRect
    var alpha: Double
}

/// Tells whether the space showing on a screen belongs to a full-screen app, from public window-server data only.
///
/// Measured on macOS 26: in a full-screen space the menu bar window (window server, `kCGMainMenuWindowLevel`) and the
/// Dock leave the screen, and the app's window covers it at layer 0. `NSScreen.visibleFrame` does not change, so
/// it can't be used. Window bounds, layers and owners need no Screen Recording permission (only titles do).
enum FullScreenDetector {
    static let menuBarLayer = Int(CGWindowLevelForKey(.mainMenuWindow))

    static func isFullScreen(_ screen: ScreenDescriptor, windows: [WindowSnapshot], ownPID: pid_t) -> Bool {
        let frame = screen.windowServerFrame
        let tolerance: CGFloat = 1
        let menuBarShowing = windows.contains { window in
            window.layer == menuBarLayer && window.alpha > 0
                && abs(window.bounds.minY - frame.minY) <= tolerance
                && window.bounds.height < 80
                && window.bounds.intersects(frame)
        }
        guard !menuBarShowing else { return false }
        // Beside a hardware notch, full-screen apps usually start below the camera: allow the notch's height.
        let topAllowance = (screen.hasNotch ? screen.geometry.notchRect.height : 0) + tolerance
        return windows.contains { window in
            window.layer == 0 && window.alpha > 0 && window.ownerPID != ownPID
                && window.bounds.minX <= frame.minX + tolerance
                && window.bounds.maxX >= frame.maxX - tolerance
                && window.bounds.maxY >= frame.maxY - tolerance
                && window.bounds.minY <= frame.minY + topAllowance
                && window.bounds.minY >= frame.minY - tolerance
        }
    }

    /// Displays showing a full-screen app right now. A few milliseconds; only called on space, app and screen changes.
    static func fullScreenDisplays(among screens: [ScreenDescriptor]) -> Set<CGDirectDisplayID> {
        guard !screens.isEmpty else { return [] }
        let windows = onScreenWindows()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return Set(screens.filter { isFullScreen($0, windows: windows, ownPID: ownPID) }.map(\.id))
    }

    static func onScreenWindows() -> [WindowSnapshot] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0 || layer == menuBarLayer,
                  let pid = info[kCGWindowOwnerPID as String] as? Int,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo)
            else { return nil }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return WindowSnapshot(ownerPID: pid_t(pid), layer: layer, bounds: bounds, alpha: alpha)
        }
    }
}

extension FullScreenBehaviour {
    /// Over a full-screen app the notch keeps quiet: no ears, no hover, no alerts. Only "Stay as usual" doesn't.
    var quietensOverFullScreen: Bool { self != .show }

    /// Whether the notch is out of sight over a full-screen app in this state.
    ///
    /// - `dragOnly`: invisible at rest, back as soon as a drag comes close (`dragIsClose`) and while it's open.
    /// - `hide`: only an explicit open (the Ask shortcut, the menu) brings it back.
    func hidesNotch(in state: NotchState, dragIsClose: Bool) -> Bool {
        switch self {
        case .show:
            false
        case .dragOnly:
            switch state {
            case .idle, .peek: true
            case .dragArmed: !dragIsClose
            case .dropTarget, .open: false
            }
        case .hide:
            state != .open
        }
    }

    /// A drag near the notch over a full-screen app opens the drop target.
    var takesDropsOverFullScreen: Bool { self != .hide }
}
