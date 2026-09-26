import AppKit
import SwiftUI

/// Resolves a live SwiftUI icon's rectangle only when its menu is requested.
/// Coordinates are AppKit global screen coordinates (origin at the bottom left).
@MainActor
final class MenuBarPopupAnchor {
    fileprivate(set) weak var view: NSView?

    func screenRect() -> CGRect? {
        guard let view, let window = view.window,
              window.isVisible, !view.isHiddenOrHasHiddenAncestor,
              view.bounds.width > 0, view.bounds.height > 0
        else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

/// Wrap the complete icon cell so its click, context menu, and accessibility
/// action all capture the same stable anchor without storing layout in state.
@MainActor
struct MenuBarPopupAnchorReader<Content: View>: View {
    @State private var anchor = MenuBarPopupAnchor()
    private let content: (MenuBarPopupAnchor) -> Content
    private let toolTip: String?

    init(toolTip: String? = nil, @ViewBuilder content: @escaping (MenuBarPopupAnchor) -> Content) {
        self.toolTip = toolTip
        self.content = content
    }

    var body: some View {
        content(anchor)
            .background(MenuBarPopupAnchorProbe(anchor: anchor, toolTip: toolTip))
    }
}

@MainActor
private struct MenuBarPopupAnchorProbe: NSViewRepresentable {
    let anchor: MenuBarPopupAnchor
    let toolTip: String?

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.setAccessibilityElement(false)
        view.toolTip = toolTip
        anchor.view = view
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        anchor.view = view
        view.toolTip = toolTip
    }

    final class ProbeView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
