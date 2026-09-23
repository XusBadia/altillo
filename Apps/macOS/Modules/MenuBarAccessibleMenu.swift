import Foundation

struct MenuBarMenuSnapshot: Sendable {
    let nodes: [MenuBarMenuNode]
    /// A custom view or lazily populated submenu did not expose a complete AX representation.
    let hasUnsupportedContent: Bool
}

struct MenuBarMenuNode: Sendable, Identifiable {
    let id: String
    let title: String
    let isEnabled: Bool
    let isChecked: Bool
    let isSeparator: Bool
    let shortcut: String?
    let shortcutModifiers: Int?
    let mark: String?
    let children: [MenuBarMenuNode]
}
