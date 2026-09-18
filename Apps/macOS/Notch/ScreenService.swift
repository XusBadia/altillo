import AltilloCore
import AppKit

enum ScreenService {
    static func geometry(for screen: NSScreen) -> NotchGeometry {
        NotchGeometry(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea
        )
    }

    /// Screen that hosts the notch: the one with a hardware notch, otherwise the one with the menu bar.
    /// Phase 2 adds the user's choice (notch / main / all / under the cursor).
    static var preferredScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }
}
