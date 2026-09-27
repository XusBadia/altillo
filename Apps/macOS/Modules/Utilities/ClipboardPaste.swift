import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Pasting a picked slip into the app that was in front: one ⌘V, sent the way a keyboard would. macOS only lets an
/// app do that with Accessibility, which the user grants in System Settings (Altillo asks only from a button).
@MainActor
enum ClipboardPaste {
    /// Altillo may press keys in other apps.
    static var canPaste: Bool { AXIsProcessTrusted() }

    /// Shows macOS's own prompt, then System Settings › Accessibility if it's still not allowed.
    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard !AXIsProcessTrustedWithOptions(options),
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cgSessionEventTap)
        }
    }
}
