import AppKit

/// Presents the owner's accessible commands at the clicked Drawer icon. It never
/// opens, moves, or temporarily reveals the owner's status item.
@MainActor
final class MenuBarMenuPresenter: NSObject {
    enum Outcome { case selected(String), cancelled, unavailable }

    private var selectedAction: String?
    private var menu: NSMenu?

    func present(_ nodes: [MenuBarMenuNode], at anchor: CGRect,
                 hasUnsupportedContent: Bool = false) -> Outcome {
        guard !nodes.isEmpty, anchor.width > 0, anchor.height > 0,
              anchor.minX.isFinite, anchor.minY.isFinite else { return .unavailable }
        selectedAction = nil
        let menu = makeMenu(nodes)
        if hasUnsupportedContent {
            menu.addItem(.separator())
            let notice = NSMenuItem(title: String(localized: "Some controls aren't available in this menu."),
                                    action: nil, keyEquivalent: "")
            notice.isEnabled = false
            menu.addItem(notice)
        }
        self.menu = menu
        defer { self.menu = nil }
        _ = menu.popUp(positioning: nil,
                       at: NSPoint(x: anchor.minX, y: anchor.minY - 4), in: nil)
        if let selectedAction { return .selected(selectedAction) }
        // AppKit returns false for normal cancellation, not a presentation error.
        return .cancelled
    }

    func cancel() { menu?.cancelTracking() }

    func makeMenu(_ nodes: [MenuBarMenuNode]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for node in nodes {
            if node.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: node.title, action: #selector(selectCommand(_:)),
                                  keyEquivalent: node.shortcut ?? "")
            item.target = self
            item.representedObject = node.id
            item.isEnabled = node.isEnabled
            item.state = node.mark == "−" || node.mark == "-" ? .mixed : (node.isChecked ? .on : .off)
            if let modifiers = node.shortcutModifiers {
                var flags: NSEvent.ModifierFlags = []
                if modifiers & 8 == 0 { flags.insert(.command) }
                if modifiers & 1 != 0 { flags.insert(.shift) }
                if modifiers & 2 != 0 { flags.insert(.option) }
                if modifiers & 4 != 0 { flags.insert(.control) }
                item.keyEquivalentModifierMask = flags
            }
            if !node.children.isEmpty { item.submenu = makeMenu(node.children) }
            menu.addItem(item)
        }
        return menu
    }

    @objc private func selectCommand(_ sender: NSMenuItem) {
        selectedAction = sender.representedObject as? String
    }
}
