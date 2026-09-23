import ApplicationServices
import CoreGraphics
import Foundation

/// Places a newly opened native status-item panel without moving or revealing its
/// status item. Ordinary NSMenu windows use the menu proxy instead: their AX
/// position setter can return success without actually moving the window.
actor MenuBarPopoverPlacement {
    private struct Window {
        let id: CGWindowID
        let frame: CGRect
    }

    private let pid: Int32
    private let originalWindowIDs: Set<CGWindowID>
    private let originalAXWindows: [AXUIElement]

    /// Construct before activating the item so an existing app document cannot be moved.
    init(pid: Int32) {
        self.pid = pid
        originalWindowIDs = Set(Self.windows(pid: pid).map(\.id))
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.1)
        originalAXWindows = Self.axWindows(application)
    }

    /// Coordinates use the Accessibility / CoreGraphics global top-left origin.
    func place(at point: CGPoint, screens: [CGRect]) async -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return false }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.1)
        for _ in 0..<10 {
            guard !Task.isCancelled else { return false }
            let candidates = Self.windows(pid: pid, includeOffscreen: true).filter { !originalWindowIDs.contains($0.id) }
            for element in Self.axWindows(application) {
                guard !originalAXWindows.contains(where: { CFEqual($0, element) }),
                      let original = Self.frame(element),
                      let candidate = candidates.first(where: { Self.matches($0.frame, original) }) else { continue }
                var settable = DarwinBoolean(false)
                guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &settable) == .success,
                      settable.boolValue else { continue }
                let content = Self.visibleContentFrame(windowFrame: original,
                                                       descendants: Self.descendantFrames(element))
                let visibleOrigin = Self.clampedOrigin(point, windowSize: content.size, screens: screens)
                var destination = CGPoint(x: visibleOrigin.x - (content.minX - original.minX),
                                          y: visibleOrigin.y - (content.minY - original.minY))
                guard let value = AXValueCreate(.cgPoint, &destination),
                      AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success else { continue }
                // AX can acknowledge the setter before WindowServer commits the move.
                // Verify compositor bounds, not just the AX value we have just assigned.
                for _ in 0..<10 {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled else { return false }
                    if let actual = Self.windows(pid: pid).first(where: { $0.id == candidate.id }),
                       abs(actual.frame.minX - destination.x) <= 2,
                       abs(actual.frame.minY - destination.y) <= 2 {
                        return true
                    }
                }
                var restore = original.origin
                if let value = AXValueCreate(.cgPoint, &restore) {
                    _ = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    nonisolated static func clampedOrigin(_ desired: CGPoint, windowSize: CGSize, screens: [CGRect]) -> CGPoint {
        guard let screen = screens.first(where: { $0.contains(desired) }) else { return desired }
        return CGPoint(x: min(max(desired.x, screen.minX), max(screen.minX, screen.maxX - windowSize.width)),
                       y: min(max(desired.y, screen.minY), max(screen.minY, screen.maxY - windowSize.height)))
    }

    /// Control Center's backing window includes hundreds of transparent points.
    /// Its scroll areas span the visible card width, while the controls leave a small
    /// vertical margin. Ordinary compact panels retain their native window bounds.
    nonisolated static func visibleContentFrame(windowFrame: CGRect, descendants: [CGRect]) -> CGRect {
        let content = descendants.filter {
            $0.width > 0 && $0.height > 0 && windowFrame.contains($0)
                && !(abs($0.width - windowFrame.width) <= 2 && abs($0.height - windowFrame.height) <= 2)
        }.reduce(CGRect.null) { $0.union($1) }
        guard !content.isNull, content.width < windowFrame.width * 0.85,
              content.height < windowFrame.height * 0.85 else { return windowFrame }
        return content.insetBy(dx: 0, dy: -8).intersection(windowFrame)
    }

    private static func descendantFrames(_ root: AXUIElement) -> [CGRect] {
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var frames: [CGRect] = []
        var visited = 0
        while let (element, depth) = pending.popLast(), visited < 80 {
            visited += 1
            AXUIElementSetMessagingTimeout(element, 0.1)
            if depth > 0, let frame = frame(element) { frames.append(frame) }
            guard depth < 3 else { continue }
            var raw: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success {
                pending.append(contentsOf: (raw as? [AXUIElement] ?? []).map { ($0, depth + 1) })
            }
        }
        return frames
    }

    private static func matches(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) <= 2 && abs(first.minY - second.minY) <= 2
            && abs(first.width - second.width) <= 2 && abs(first.height - second.height) <= 2
    }

    private static func windows(pid: Int32, includeOffscreen: Bool = false) -> [Window] {
        let options: CGWindowListOption = includeOffscreen ? [.optionAll, .excludeDesktopElements] : [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return info.compactMap { row in
            guard (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let id = row[kCGWindowNumber as String] as? NSNumber,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width > 0, frame.height > 32 else { return nil }
            return Window(id: id.uint32Value, frame: frame)
        }
    }

    private static func axWindows(_ application: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &raw) == .success else { return [] }
        return raw as? [AXUIElement] ?? []
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var originRaw: CFTypeRef?
        var sizeRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &originRaw) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRaw) == .success,
              let originRaw, let sizeRaw,
              CFGetTypeID(originRaw) == AXValueGetTypeID(), CFGetTypeID(sizeRaw) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(originRaw, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(sizeRaw, to: AXValue.self), .cgSize, &size),
              origin.x.isFinite, origin.y.isFinite, size.width.isFinite, size.height.isFinite else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
