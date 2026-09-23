import AltilloCore
import AltilloDesign
import AppKit
import SwiftUI

/// Owns the live panel: host view (hit-testing) › drop target › SwiftUI content. There is only ever one, on the
/// screen the user is working with; other screens get a `RestingNotchController`.
@MainActor
final class NotchWindowController {
    let panel: NotchPanel
    let dropTarget: DropTargetView
    private(set) var geometry: NotchGeometry
    /// The display the panel is on.
    private(set) var screenID: CGDirectDisplayID
    /// Ordered in. False while a full-screen app keeps it out of sight.
    private(set) var isShown = false

    init(screen: ScreenDescriptor, model: NotchModel) {
        geometry = screen.geometry
        screenID = screen.id
        panel = NotchPanel(frame: screen.geometry.panelFrame(size: NotchLayout.panelSize))

        let bounds = NSRect(origin: .zero, size: NotchLayout.panelSize)
        let host = NotchHostView(frame: bounds)
        host.visibleShapeSize = { [weak model] in model?.visibleShapeSize ?? .zero }

        dropTarget = DropTargetView(frame: bounds)
        dropTarget.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: NotchRootView(model: model))
        hosting.sizingOptions = []
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]

        dropTarget.addSubview(hosting)
        host.addSubview(dropTarget)
        panel.contentView = host
    }

    /// Moves the panel to a screen (or follows its new size). Returns true when anything changed.
    @discardableResult
    func update(screen: ScreenDescriptor) -> Bool {
        let frame = screen.geometry.panelFrame(size: NotchLayout.panelSize)
        guard screen.geometry != geometry || screen.id != screenID || panel.frame != frame else { return false }
        geometry = screen.geometry
        screenID = screen.id
        panel.setFrame(frame, display: isShown)
        return true
    }

    /// The visible notch shape in screen coordinates.
    var visibleShapeScreenRect: CGRect {
        guard let host = panel.contentView as? NotchHostView else { return geometry.notchRect }
        return panel.convertToScreen(host.convert(host.visibleShapeRect, to: nil))
    }

    func setShown(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        if shown { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    func close() {
        isShown = false
        panel.close()
    }
}

/// The notch at rest on a screen that isn't the live one ("All of them"): the silhouette over the hardware notch, or
/// the island's lip. Draws once, never takes events; the live notch comes over as soon as the pointer does.
@MainActor
final class RestingNotchController {
    let panel: NSPanel
    private(set) var geometry: NotchGeometry
    private(set) var isShown = false

    init(screen: ScreenDescriptor) {
        geometry = screen.geometry
        let shape = Self.shape(for: screen.geometry)
        panel = NSPanel(
            contentRect: Self.frame(for: screen.geometry, shape: shape),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        NotchPanel.configure(panel)
        panel.setAccessibilityElement(false)
        let hosting = NSHostingView(rootView: RestingNotchView(shape: shape))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func update(screen: ScreenDescriptor) {
        guard screen.geometry != geometry else { return }
        geometry = screen.geometry
        let shape = Self.shape(for: screen.geometry)
        (panel.contentView as? NSHostingView<RestingNotchView>)?.rootView = RestingNotchView(shape: shape)
        panel.setFrame(Self.frame(for: screen.geometry, shape: shape), display: isShown)
    }

    func setShown(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        if shown { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    func close() {
        isShown = false
        panel.close()
    }

    private static func shape(for geometry: NotchGeometry) -> NotchChrome.RestShape {
        NotchChrome.restShape(
            notch: NotchChrome.simulatedNotch ?? geometry.notchRect.size,
            hasNotch: geometry.hasNotch || NotchChrome.simulatedNotch != nil
        )
    }

    private static func frame(for geometry: NotchGeometry, shape: NotchChrome.RestShape) -> CGRect {
        geometry.panelFrame(size: CGSize(width: shape.size.width.rounded(.up), height: shape.size.height.rounded(.up)))
    }
}

/// The resting silhouette, the same black as the live notch.
struct RestingNotchView: View {
    let shape: NotchChrome.RestShape

    var body: some View {
        NotchShape(topCornerRadius: shape.topRadius, bottomCornerRadius: shape.bottomRadius)
            .fill(Desvan.Palette.notch)
            .frame(width: shape.size.width, height: shape.size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityHidden(true)
    }
}
