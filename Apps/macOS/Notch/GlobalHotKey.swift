import AppKit
import Carbon.HIToolbox

/// System-wide keyboard shortcuts through Carbon's `RegisterEventHotKey`: the one API that needs no Accessibility
/// or Input Monitoring permission, and that macOS itself arbitrates (it refuses a combination another app owns).
/// One per `Slot` (Ask, the clipboard), each replaced on its own.
@MainActor
final class GlobalHotKey {
    enum Slot: UInt32, CaseIterable {
        case assistant = 1
        case clipboard = 2
    }

    /// A combination as Carbon wants it, with a name for the log.
    struct Combo: Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
        var title: String
    }

    private var hotKeyRefs: [Slot: EventHotKeyRef] = [:]
    private var registered: [Slot: Combo] = [:]
    private var actions: [Slot: () -> Void] = [:]
    private var handlerRef: EventHandlerRef?

    /// Registers the assistant's `key` (or nothing when `enabled` is false or the key is `.off`), replacing the
    /// previous one. Returns false when macOS refused the combination.
    @discardableResult
    func register(_ key: AssistantHotKey, enabled: Bool, action: @escaping () -> Void) -> Bool {
        register(.assistant, combo: enabled ? key.combo.map { Combo(keyCode: $0.keyCode, modifiers: $0.modifiers, title: key.title) } : nil,
                 action: action)
    }

    /// Registers `combo` in `slot` (nil clears it), replacing what the slot had. Returns false when macOS refused
    /// the combination (another app, or the other slot, has it).
    @discardableResult
    func register(_ slot: Slot, combo: Combo?, action: @escaping () -> Void) -> Bool {
        actions[slot] = action
        if combo == registered[slot] { return true }
        unregister(slot)
        guard let combo else { return true }
        installHandler()
        let id = EventHotKeyID(signature: Self.signature, id: slot.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            DiagnosticLog.shared.record(DiagnosticLog.Category.app, "Shortcut \(combo.title) refused by macOS (\(status))")
            return false
        }
        hotKeyRefs[slot] = ref
        registered[slot] = combo
        return true
    }

    func unregister(_ slot: Slot) {
        if let ref = hotKeyRefs[slot] { UnregisterEventHotKey(ref) }
        hotKeyRefs[slot] = nil
        registered[slot] = nil
    }

    func unregister() {
        for slot in Slot.allCases { unregister(slot) }
    }

    /// 'ALTL'
    nonisolated static let signature: OSType = 0x414C_544C

    fileprivate func pressed(_ id: UInt32) {
        guard let slot = Slot(rawValue: id) else { return }
        actions[slot]?()
    }

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
            let id = pressed.id
            // Carbon delivers hot keys on the main thread's event loop.
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().pressed(id)
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

extension ClipboardHotKey {
    /// Virtual key code and Carbon modifiers, or nil for `.off`.
    var combo: GlobalHotKey.Combo? {
        let key: (Int, Int)? = switch self {
        case .off: nil
        case .controlOptionV: (kVK_ANSI_V, controlKey | optionKey)
        case .controlOptionC: (kVK_ANSI_C, controlKey | optionKey)
        case .controlShiftV: (kVK_ANSI_V, controlKey | shiftKey)
        }
        return key.map { GlobalHotKey.Combo(keyCode: UInt32($0.0), modifiers: UInt32($0.1), title: title) }
    }
}
