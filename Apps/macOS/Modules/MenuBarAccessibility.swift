import ApplicationServices
import CoreGraphics
import Foundation

struct MenuBarApplication: Sendable, Hashable {
    let pid: Int32
    let bundleID: String
    let name: String
}

struct MenuBarEntry: Identifiable, Sendable, Equatable {
    let id: String
    let application: MenuBarApplication
    let title: String
    let frame: CGRect
}

enum MenuBarActionResult: Sendable {
    /// Accessibility confirmed that the action completed.
    case performed
    /// The target did not answer before the timeout; modal menu tracking may still have performed the action.
    case unconfirmed
    /// The item or action is unavailable, or Accessibility rejected the request.
    case unavailable
}

extension Notification.Name {
    /// Posted on the main thread when an owner reports that one of its status items was created,
    /// destroyed, moved or resized.
    static let menuBarItemsDidChange = Notification.Name("me.badia.altillo.menuBarItemsDidChange")
}

/// Reads and activates third-party status items through macOS Accessibility.
///
/// AX objects are deliberately kept inside this actor. Calling `scan` from the UI with `await` lets the
/// synchronous Accessibility messages run on this actor instead of tying up the main actor.
actor MenuBarAccessibility {
    private struct CachedItem {
        let applicationPID: Int32
        let element: AXUIElement
        let actions: Set<String>
    }

    /// A stalled application should not hold up a complete menu-bar refresh for the system AX default timeout.
    private static let messagingTimeout: Float = 0.1

    private var itemsByID: [String: CachedItem] = [:]
    private var knownOwners: Set<String> = []
    private var menuActions: [String: AXUIElement] = [:]
    private(set) var failedApplicationPIDs: Set<Int32> = []
    /// One AX observer per status-item owner. Its callbacks only mark the catalog stale; they never scan.
    private var observers: [Int32: AXObserver] = [:]
    private var observedElements: [String: AXUIElement] = [:]

    /// Rebuilds the status-item cache. The regular application menu bar is never queried.
    func scan(applications: [MenuBarApplication]) -> [MenuBarEntry] {
        var entries: [MenuBarEntry] = []
        var refreshedItems: [String: CachedItem] = [:]
        var usedIDs: [String: Int] = [:]
        var failures: Set<Int32> = []

        applicationLoop: for application in applications {
            guard !Task.isCancelled else { break }
            let applicationElement = AXUIElementCreateApplication(pid_t(application.pid))
            Self.limitMessaging(on: applicationElement)

            let extrasResult: AttributeResult<AXUIElement> = Self.attribute(
                kAXExtrasMenuBarAttribute,
                of: applicationElement
            )
            guard extrasResult.error == .success, let extrasMenuBar = extrasResult.value else {
                if knownOwners.contains(application.bundleID),
                   extrasResult.error != .attributeUnsupported, extrasResult.error != .noValue {
                    failures.insert(application.pid)
                }
                continue
            }
            Self.limitMessaging(on: extrasMenuBar)
            knownOwners.insert(application.bundleID)
            let ownerObserver = observer(for: application.pid, extrasMenuBar: extrasMenuBar)

            let childrenResult: AttributeResult<[AXUIElement]> = Self.attribute(
                kAXChildrenAttribute,
                of: extrasMenuBar
            )
            guard childrenResult.error == .success, let children = childrenResult.value else {
                failures.insert(application.pid)
                continue
            }

            for (ordinal, element) in Self.statusItemCandidates(in: children) {
                guard !Task.isCancelled else { break applicationLoop }
                Self.limitMessaging(on: element)

                guard Self.stringAttribute(kAXRoleAttribute, of: element) == kAXMenuBarItemRole as String else {
                    continue
                }
                guard let frame = Self.frame(of: element) else {
                    failures.insert(application.pid)
                    continue
                }
                // Control Center exposes zero-width placeholders; they are not usable status items.
                guard frame.width > 0, frame.height > 0 else { continue }

                let identifier = Self.nonemptyStringAttribute(kAXIdentifierAttribute, of: element)
                let axTitle = Self.nonemptyStringAttribute(kAXTitleAttribute, of: element)
                let description = Self.nonemptyStringAttribute(kAXDescriptionAttribute, of: element)
                let title = axTitle ?? description ?? application.name
                let baseID = Self.stableID(
                    bundleID: application.bundleID,
                    identifier: identifier,
                    title: axTitle ?? description,
                    ordinal: ordinal
                )
                let duplicate = usedIDs[baseID, default: 0]
                usedIDs[baseID] = duplicate + 1
                let id = duplicate == 0 ? baseID : "\(baseID)|duplicate:\(duplicate)"
                let actionResult = Self.actions(of: element)
                // An icon without an advertised action is still visible in the catalog.
                // Activation will fail open rather than blocking the entire section.

                entries.append(MenuBarEntry(id: id, application: application, title: title, frame: frame))
                if let ownerObserver { observe(element, id: id, with: ownerObserver) }
                refreshedItems[id] = CachedItem(
                    applicationPID: application.pid,
                    element: element,
                    actions: actionResult.actions
                )
            }
        }

        // A cancelled scan is an abandoned snapshot: keep the last complete cache and failure report intact.
        guard !Task.isCancelled else { return entries }

        // The caller can keep the last entries for failed PIDs. Keep their AX references as well so those stale
        // entries remain actionable until a later successful scan replaces them.
        for (id, item) in itemsByID where failures.contains(item.applicationPID) && refreshedItems[id] == nil {
            refreshedItems[id] = item
        }
        itemsByID = refreshedItems
        failedApplicationPIDs = failures
        pruneObservers(liveIDs: Set(refreshedItems.keys), livePIDs: Set(applications.map(\.pid)))
        return entries
    }

    /// The extras menu bar's direct children, with one level of `AXGroup` unwrapped. macOS 27 hosts the
    /// system items (Wi-Fi, Focus, Control Center, Clock) in MenuBarAgent, which wraps each `AXMenuBarItem`
    /// in a group. A direct child keeps its own index as ordinal (identities are unchanged on macOS 26); a
    /// grouped item takes its group's index. Roles are checked by the caller.
    nonisolated static func statusItemCandidates<Element>(
        in children: [Element],
        role: (Element) -> String?,
        nested: (Element) -> [Element]
    ) -> [(ordinal: Int, element: Element)] {
        children.enumerated().flatMap { ordinal, element -> [(ordinal: Int, element: Element)] in
            guard role(element) == kAXGroupRole as String else { return [(ordinal, element)] }
            return nested(element).map { (ordinal, $0) }
        }
    }

    private static func statusItemCandidates(in children: [AXUIElement]) -> [(ordinal: Int, element: AXUIElement)] {
        statusItemCandidates(in: children, role: { element in
            limitMessaging(on: element)
            return stringAttribute(kAXRoleAttribute, of: element)
        }, nested: { group in
            let result: AttributeResult<[AXUIElement]> = attribute(kAXChildrenAttribute, of: group)
            return result.value ?? []
        })
    }

    // MARK: - Change notifications

    /// Registers for structural changes of one owner's status items. Registration happens only while
    /// scanning (an event-driven or user-driven moment) and only once per element.
    private func observer(for pid: Int32, extrasMenuBar: AXUIElement) -> AXObserver? {
        if let existing = observers[pid] { return existing }
        var created: AXObserver?
        guard AXObserverCreate(pid_t(pid), { _, _, _, _ in
            // Delivered on the main run loop. Coalescing and deciding whether to scan belong to the store.
            NotificationCenter.default.post(name: .menuBarItemsDidChange, object: nil)
        }, &created) == .success, let created else { return nil }
        for notification in [kAXCreatedNotification, kAXUIElementDestroyedNotification] {
            _ = AXObserverAddNotification(created, extrasMenuBar, notification as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observers[pid] = created
        return created
    }

    private func observe(_ element: AXUIElement, id: String, with observer: AXObserver) {
        if let previous = observedElements[id], CFEqual(previous, element) { return }
        for notification in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
            _ = AXObserverAddNotification(observer, element, notification as CFString, nil)
        }
        observedElements[id] = element
    }

    private func pruneObservers(liveIDs: Set<String>, livePIDs: Set<Int32>) {
        observedElements = observedElements.filter { liveIDs.contains($0.key) }
        for (pid, observer) in observers where !livePIDs.contains(pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers[pid] = nil
        }
    }

    /// Stops all change notifications, e.g. when the Drawer is turned off.
    func stopObserving() {
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
        observedElements.removeAll()
    }

    /// Performs only an action advertised by the item during the latest scan.
    func perform(id: String, showMenu: Bool) -> MenuBarActionResult {
        guard let item = itemsByID[id] else { return .unavailable }
        let action = showMenu ? kAXShowMenuAction as String : kAXPressAction as String
        guard item.actions.contains(action) else { return .unavailable }
        let currentActions = Self.actions(of: item.element)
        guard currentActions.error == .success, currentActions.actions.contains(action) else {
            return .unavailable
        }
        return switch AXUIElementPerformAction(item.element, action as CFString) {
        case .success: .performed
        case .cannotComplete: .unconfirmed
        default: .unavailable
        }
    }

    /// Standard NSMenu trees are exposed even while their status item is hidden.
    /// Keep their real AX action targets and send only immutable presentation data to AppKit.
    func menuSnapshot(id: String) -> MenuBarMenuSnapshot? {
        guard let item = itemsByID[id] else { return nil }
        menuActions.removeAll()
        let result: AttributeResult<[AXUIElement]> = Self.attribute(kAXChildrenAttribute, of: item.element)
        guard result.error == .success,
              let menu = result.value?.first(where: { Self.stringAttribute(kAXRoleAttribute, of: $0) == kAXMenuRole }) else { return nil }
        var remaining = 200
        var unsupported = false
        let nodes = snapshotChildren(of: menu, depth: 0, remaining: &remaining, unsupported: &unsupported)
        guard !nodes.isEmpty else { return nil }
        return MenuBarMenuSnapshot(nodes: nodes, hasUnsupportedContent: unsupported)
    }

    func performMenuAction(id: String) -> MenuBarActionResult {
        guard let element = menuActions[id] else { return .unavailable }
        let enabled: AttributeResult<Bool> = Self.attribute(kAXEnabledAttribute, of: element)
        guard enabled.value == true, Self.actions(of: element).actions.contains(kAXPressAction) else { return .unavailable }
        return switch AXUIElementPerformAction(element, kAXPressAction as CFString) {
        case .success: .performed
        case .cannotComplete: .unconfirmed
        default: .unavailable
        }
    }

    private func snapshotChildren(of parent: AXUIElement, depth: Int, remaining: inout Int, unsupported: inout Bool) -> [MenuBarMenuNode] {
        guard depth < 8, remaining > 0 else { unsupported = true; return [] }
        let result: AttributeResult<[AXUIElement]> = Self.attribute(kAXChildrenAttribute, of: parent)
        guard result.error == .success, let elements = result.value else { unsupported = true; return [] }
        let parentTitle = Self.stringAttribute(kAXRoleAttribute, of: parent) == kAXMenuItemRole
            ? Self.nonemptyStringAttribute(kAXTitleAttribute, of: parent) : nil
        let booleanButtons = elements.filter { element in
            guard Self.stringAttribute(kAXRoleAttribute, of: element) == kAXButtonRole,
                  Self.actions(of: element).actions.contains(kAXPressAction) else { return false }
            let value: AttributeResult<NSNumber> = Self.attribute(kAXValueAttribute, of: element)
            return value.value?.intValue == 0 || value.value?.intValue == 1
        }
        let contextualTitle = Self.anonymousToggleTitle(parentTitle: parentTitle, booleanButtonCount: booleanButtons.count)
        var nodes: [MenuBarMenuNode] = []
        for element in elements {
            guard remaining > 0 else { unsupported = true; break }
            remaining -= 1
            Self.limitMessaging(on: element)
            let role = Self.stringAttribute(kAXRoleAttribute, of: element) ?? ""
            let actions = Self.actions(of: element).actions
            // Decorative images are not missing menu commands.
            if role == kAXImageRole && actions.isEmpty { continue }
            var title = Self.menuTitle(role: role,
                title: Self.nonemptyStringAttribute(kAXTitleAttribute, of: element),
                description: Self.nonemptyStringAttribute(kAXDescriptionAttribute, of: element),
                value: Self.nonemptyStringAttribute(kAXValueAttribute, of: element))
            let inheritedToggleLabel = title.isEmpty && contextualTitle != nil
                && booleanButtons.first.map { CFEqual($0, element) } == true
            if inheritedToggleLabel { title = contextualTitle! }
            let childResult: AttributeResult<[AXUIElement]> = Self.attribute(kAXChildrenAttribute, of: element)
            let children = childResult.value ?? []
            let submenu = children.first { Self.stringAttribute(kAXRoleAttribute, of: $0) == kAXMenuRole }
            let enabled: AttributeResult<Bool> = Self.attribute(kAXEnabledAttribute, of: element)
            let controlValue: AttributeResult<NSNumber> = Self.attribute(kAXValueAttribute, of: element)
            let mark = Self.nonemptyStringAttribute(kAXMenuItemMarkCharAttribute, of: element)
                ?? Self.controlMark(role: role, value: controlValue.value?.intValue)
                ?? (inheritedToggleLabel && controlValue.value?.intValue == 1 ? "✓" : nil)
            let modifiers: AttributeResult<Int> = Self.attribute(kAXMenuItemCmdModifiersAttribute, of: element)
            let token = UUID().uuidString
            let submenuNodes = submenu.map { snapshotChildren(of: $0, depth: depth + 1, remaining: &remaining, unsupported: &unsupported) } ?? []
            let hasAction = actions.contains(kAXPressAction) && submenu == nil
            if hasAction { menuActions[token] = element }
            let isSeparator = role == kAXMenuItemRole && title.isEmpty && children.isEmpty && enabled.value != true
            if !title.isEmpty || isSeparator {
                nodes.append(MenuBarMenuNode(id: token, title: title,
                    isEnabled: enabled.value == true && (hasAction || !submenuNodes.isEmpty),
                    isChecked: mark != nil, isSeparator: isSeparator,
                    shortcut: Self.nonemptyStringAttribute(kAXMenuItemCmdCharAttribute, of: element),
                    shortcutModifiers: modifiers.value, mark: mark, children: submenuNodes))
            }
            if submenu != nil && submenuNodes.isEmpty { unsupported = true }
            // NSMenu custom views often expose useful static text and real buttons beneath
            // their menu-item wrapper. Preserve those controls as additional accessible rows.
            if submenu == nil && !children.isEmpty {
                let customNodes = snapshotChildren(of: element, depth: depth + 1, remaining: &remaining, unsupported: &unsupported)
                if !hasAction, customNodes.contains(where: { $0.title == title && menuActions[$0.id] != nil }) {
                    nodes.removeAll { $0.id == token }
                }
                nodes.append(contentsOf: customNodes)
            } else if title.isEmpty && !isSeparator {
                unsupported = true
            }
        }
        return nodes.filter { node in
            // The header's single unlabeled Boolean button now carries that exact header
            // label, so its static copy need not appear as a second row.
            !(node.title == contextualTitle && menuActions[node.id] == nil
              && nodes.contains(where: { $0.title == contextualTitle && menuActions[$0.id] != nil }))
        }.reduce(into: []) { result, node in
            // A custom view may repeat its menu wrapper's label in a static-text child.
            // Never remove actionable rows, separators, or rows with submenus.
            if let previous = result.last,
               previous.title == node.title, !node.title.isEmpty,
               !previous.isSeparator, !node.isSeparator,
               previous.children.isEmpty, node.children.isEmpty,
               menuActions[previous.id] == nil, menuActions[node.id] == nil {
                return
            }
            result.append(node)
        }
    }

    nonisolated static func anonymousToggleTitle(parentTitle: String?, booleanButtonCount: Int) -> String? {
        guard booleanButtonCount == 1, let title = normalized(parentTitle) else { return nil }
        return title
    }

    nonisolated static func menuTitle(role: String, title: String?, description: String?, value: String?) -> String {
        // AXStaticText.value contains the displayed text; its description may name a
        // different status, as in Tailscale's title label (value=Tailscale, description=Connected).
        if role == kAXStaticTextRole { return title ?? value ?? description ?? "" }
        return title ?? description ?? value ?? ""
    }

    nonisolated static func controlMark(role: String, value: Int?) -> String? {
        guard [kAXCheckBoxRole as String, kAXRadioButtonRole as String, "AXSwitch"].contains(role) else { return nil }
        return switch value {
        case 1: "✓"
        case 2: "−"
        default: nil
        }
    }

    // MARK: - Stable identity

    /// Owners of macOS's own status items. On macOS 27 MenuBarAgent hosts Wi-Fi, Focus, Control Center and
    /// the clock, and `com.apple.campo` owns Spotlight.
    nonisolated static let systemOwners: Set<String> = [
        "com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.Spotlight",
        menuBarAgentBundleID, "com.apple.campo",
    ]
    nonisolated static let menuBarAgentBundleID = "com.apple.MenuBarAgent"
    nonisolated static let controlCenterBundleID = "com.apple.controlcenter"

    /// The process whose windows present an item's panel. MenuBarAgent only hosts the system items on
    /// macOS 27; Control Center still owns their panels (verified with Wi-Fi), so placement and the
    /// open-panel session must watch Control Center.
    nonisolated static func panelOwnerBundleID(forItemOwner bundleID: String) -> String {
        bundleID == menuBarAgentBundleID ? controlCenterBundleID : bundleID
    }

    /// System controls share a single application icon. Distinguish their exposed names
    /// without capturing pixels or requiring Screen Recording access.
    nonisolated static func systemSymbol(for entry: MenuBarEntry) -> String? {
        guard systemOwners.contains(entry.application.bundleID) else { return nil }
        let name = "\(entry.id) \(entry.title)".lowercased()
        let symbols: [(keywords: [String], symbol: String)] = [
            // macOS writes "Wi‑Fi" with a non-breaking hyphen (U+2011).
            (["wifi", "wi-fi", "wi\u{2011}fi", "wi fi"], "wifi"),
            (["bluetooth"], "antenna.radiowaves.left.and.right"),
            (["battery", "batería"], "battery.100percent"),
            (["sound", "volume", "sonido", "volumen"], "speaker.wave.2.fill"),
            (["focus", "donotdisturb", "concentración"], "moon.fill"),
            (["screenmirroring", "screen mirroring", "duplicar"], "rectangle.on.rectangle"),
            (["display", "brightness", "pantalla"], "display"),
            (["clock", "date", "reloj", "fecha"], "clock"),
            (["spotlight", "search"], "magnifyingglass"),
            (["siri"], "sparkles"),
            (["camera", "cámara"], "video.fill"),
            (["screenrecording", "screen recording"], "record.circle"),
            (["nowplaying", "now playing"], "play.fill"),
            (["timemachine", "time machine"], "clock.arrow.circlepath"),
            (["input", "keyboard", "teclado"], "keyboard"),
            (["vpn"], "network.badge.shield.half.filled"),
            (["controlcenter", "control center"], "switch.2")
        ]
        return symbols.first { mapping in mapping.keywords.contains { name.contains($0) } }?.symbol ?? "switch.2"
    }

    /// Prefer the app's identifier. Titles often contain changing status (sync progress, battery level…),
    /// so the fallback is the item's position in its owner's AX children, not its screen position or title.
    nonisolated static func stableID(
        bundleID: String,
        identifier: String?,
        title: String?,
        ordinal: Int
    ) -> String {
        let app = encoded(bundleID)
        if let identifier = normalized(identifier) {
            return "\(app)|identifier:\(encoded(identifier))"
        }
        return "\(app)|ordinal:\(ordinal)"
    }

    private nonisolated static func encoded(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }

    private nonisolated static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Accessibility values

    private struct AttributeResult<Value> {
        let error: AXError
        let value: Value?
    }

    private struct ActionResult {
        let error: AXError
        let actions: Set<String>
    }

    private static func limitMessaging(on element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
    }

    private static func attribute<Value>(
        _ name: String,
        of element: AXUIElement,
        as _: Value.Type = Value.self
    ) -> AttributeResult<Value> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return AttributeResult(error: error, value: value as? Value)
    }

    private static func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        let result: AttributeResult<String> = attribute(name, of: element)
        return result.error == .success ? result.value : nil
    }

    private static func nonemptyStringAttribute(_ name: String, of element: AXUIElement) -> String? {
        normalized(stringAttribute(name, of: element))
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        let position: AttributeResult<AXValue> = attribute(kAXPositionAttribute, of: element)
        let sizeResult: AttributeResult<AXValue> = attribute(kAXSizeAttribute, of: element)
        guard position.error == .success,
              sizeResult.error == .success,
              let positionValue = position.value,
              let sizeValue = sizeResult.value,
              AXValueGetType(positionValue) == .cgPoint,
              AXValueGetType(sizeValue) == .cgSize
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue, .cgSize, &size),
              origin.x.isFinite,
              origin.y.isFinite,
              size.width.isFinite,
              size.height.isFinite
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func actions(of element: AXUIElement) -> ActionResult {
        var names: CFArray?
        let error = AXUIElementCopyActionNames(element, &names)
        guard error == .success, let names = names as? [String] else {
            return ActionResult(error: error == .success ? .failure : error, actions: [])
        }
        return ActionResult(error: .success, actions: Set(names))
    }
}
