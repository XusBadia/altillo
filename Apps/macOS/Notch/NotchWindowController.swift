import AltilloCore
import AppKit
import SwiftUI

/// Owns the panel for one screen: host view (hit-testing) › drop target › SwiftUI content.
@MainActor
final class NotchWindowController {
    let panel: NotchPanel
    let dropTarget: DropTargetView
    private(set) var geometry: NotchGeometry

    init(geometry: NotchGeometry, model: NotchModel) {
        self.geometry = geometry
        panel = NotchPanel(frame: geometry.panelFrame(size: NotchLayout.panelSize))

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

    func update(geometry: NotchGeometry) {
        self.geometry = geometry
        panel.setFrame(geometry.panelFrame(size: NotchLayout.panelSize), display: true)
    }

    /// The visible notch shape in screen coordinates.
    var visibleShapeScreenRect: CGRect {
        guard let host = panel.contentView as? NotchHostView else { return geometry.notchRect }
        return panel.convertToScreen(host.convert(host.visibleShapeRect, to: nil))
    }

    func show() { panel.orderFrontRegardless() }
    func close() { panel.close() }
}
