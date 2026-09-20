import ApplicationServices
import CoreGraphics
import Foundation

struct MenuBarApplication: Sendable {
    let pid: Int32
    let bundleID: String
    let name: String
}

struct MenuBarEntry: Identifiable, Sendable {
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
    private(set) var failedApplicationPIDs: Set<Int32> = []

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

            let childrenResult: AttributeResult<[AXUIElement]> = Self.attribute(
                kAXChildrenAttribute,
                of: extrasMenuBar
            )
            guard childrenResult.error == .success, let children = childrenResult.value else {
                failures.insert(application.pid)
                continue
            }

            for (ordinal, element) in children.enumerated() {
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
        return entries
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

    // MARK: - Stable identity

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
