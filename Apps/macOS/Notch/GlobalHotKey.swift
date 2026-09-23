import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut through Carbon's `RegisterEventHotKey`: the one API that needs no Accessibility
/// or Input Monitoring permission, and that macOS itself arbitrates (it refuses a combination another app owns).
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var registered: AssistantHotKey = .off
    private var action: () -> Void = {}

    /// Registers `key` (or nothing when `enabled` is false or the key is `.off`), replacing the previous one.
    /// Returns false when macOS refused the combination.
    @discardableResult
    func register(_ key: AssistantHotKey, enabled: Bool, action: @escaping () -> Void) -> Bool {
        self.action = action
        let wanted: AssistantHotKey = enabled ? key : .off
        if wanted == registered { return true }
        unregister()
        guard let combo = wanted.combo else { return true }
        installHandler()
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            SpikeLog.shared.record(SpikeLog.Category.app, "Shortcut \(wanted.title) refused by macOS (\(status))")
            return false
        }
        hotKeyRef = ref
        registered = wanted
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        registered = .off
    }

    /// 'ALTL'
    nonisolated static let signature: OSType = 0x414C_544C

    private func installHandler() {
        guard handlerRef == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            // Only ours: any other hot key in the process keeps its own handler.
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard status == noErr, pressed.signature == GlobalHotKey.signature else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon delivers hot keys on the main thread's event loop.
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &type, context, &handlerRef)
    }
}

extension AssistantHotKey {
    /// Virtual key code and Carbon modifiers, or nil for `.off`.
    var combo: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .off: nil
        case .controlOptionA: (UInt32(kVK_ANSI_A), UInt32(controlKey | optionKey))
        case .optionSpace: (UInt32(kVK_Space), UInt32(optionKey))
        case .controlOptionSpace: (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        }
    }
}
