import ApplicationServices
import CoreGraphics
import Foundation

/// Observes presentation rather than assuming that posting a click opened a menu.
/// AX covers NSMenu; newly visible owner windows cover custom status-item popovers.
actor MenuBarMenuSession {
    private let pid: Int32
    private let existingWindows: Set<Int>?
    private var observedWindow = false

    init(pid: Int32) {
        self.pid = pid
        self.existingWindows = Self.visibleWindows(pid: pid)
    }

    func isPresented() -> Bool? {
        guard let existingWindows, let currentWindows = Self.visibleWindows(pid: pid) else { return nil }
        if !(Self.visibleWindows(pid: pid, menusOnly: true) ?? []).isEmpty
            || !currentWindows.subtracting(existingWindows).isEmpty {
            observedWindow = true
            return true
        }
        if observedWindow { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        if let focused = Self.element(kAXFocusedUIElementAttribute, of: app), Self.isMenu(focused) { return true }
        guard let extras = Self.element(kAXExtrasMenuBarAttribute, of: app) else { return false }
        guard let items = Self.children(extras) else { return nil }
        for item in items {
            guard let children = Self.children(item) else { return nil }
            if children.contains(where: { Self.isMenu($0) }) { return true }
        }
        return false
    }

    /// Cancel only this owner's menu. A targeted Escape is the public fallback for
    /// apps whose modal menu loop cannot answer Accessibility until tracking ends.
    func dismiss() async -> Bool {
        guard isPresented() == true else { return isPresented() == false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var menus: [AXUIElement] = []
        if let focused = Self.element(kAXFocusedUIElementAttribute, of: app), Self.isMenu(focused) {
            menus.append(focused)
        }
        if let extras = Self.element(kAXExtrasMenuBarAttribute, of: app) {
            for item in Self.children(extras) ?? [] {
                menus.append(contentsOf: (Self.children(item) ?? []).filter { Self.isMenu($0) })
            }
        }
        for menu in menus { _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString) }
        try? await Task.sleep(for: .milliseconds(100))
        if isPresented() == false { return true }
        guard !Task.isCancelled, isPresented() == true,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else { return false }
        down.flags = []
        up.flags = []
        down.postToPid(pid)
        up.postToPid(pid)
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(50))
            if isPresented() == false { return true }
            guard !Task.isCancelled else { return false }
        }
        return false
    }

    private static func visibleWindows(pid: Int32, menusOnly: Bool = false) -> Set<Int>? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return nil }
        return Set(windows.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let number = window[kCGWindowNumber as String] as? NSNumber,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.height > 32 else { return nil }
            if menusOnly, (window[kCGWindowLayer as String] as? Int ?? 0) < Int(CGWindowLevelForKey(.popUpMenuWindow)) {
                return nil
            }
            return number.intValue
        })
    }

    private static func isMenu(_ element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              role as? String == kAXMenuRole as String else { return false }
        // A cached, collapsed AXMenu is not evidence that a menu is on screen.
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let size, CFGetTypeID(size) == AXValueGetTypeID() else { return false }
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions) else { return false }
        return dimensions.width > 0 && dimensions.height > 0
    }

    private static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement]? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        if result == .noValue || result == .attributeUnsupported { return [] }
        guard result == .success else { return nil }
        return value as? [AXUIElement] ?? []
    }
}
