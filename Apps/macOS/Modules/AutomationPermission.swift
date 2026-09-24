import CoreServices
import Foundation

/// Whether Altillo may already send Apple Events to an app, asked in a way that never shows the dialog.
///
/// `osascript` runs as Altillo's child, so its Apple Events are attributed to Altillo: this answers for them too.
/// Background work (the ears) only scripts a player when this says `.granted`; the dialog is left for when the user
/// opens the Now playing section themselves.
enum AutomationPermission {
    enum Status: Sendable, Equatable {
        case granted
        /// Refused in System Settings › Privacy & Security › Automation.
        case denied
        /// Never asked: asking would show the dialog.
        case undetermined
        /// The app isn't running, or the answer couldn't be read.
        case unavailable
    }

    /// Off the main thread: the check talks to the TCC daemon.
    static func status(for bundleID: String) async -> Status {
        await Task.detached(priority: .utility) { check(bundleID) }.value
    }

    private static func check(_ bundleID: String) -> Status {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let address = target.aeDesc else { return .unavailable }
        let wildcard = AEEventClass(typeWildCard)
        let result = AEDeterminePermissionToAutomateTarget(address, wildcard, AEEventID(typeWildCard), false)
        return status(for: result)
    }

    /// Reads `AEDeterminePermissionToAutomateTarget`'s answer.
    static func status(for result: OSStatus) -> Status {
        switch result {
        case noErr: .granted
        case -1743: .denied // errAEEventNotPermitted
        case -1744: .undetermined // errAEEventWouldRequireUserConsent
        default: .unavailable // procNotFound (-600) and the rest
        }
    }
}
