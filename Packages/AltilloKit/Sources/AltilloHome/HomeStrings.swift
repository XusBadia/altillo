import Foundation

/// User-facing messages (Localizable.xcstrings in this target, en source + es).
enum HomeStrings {
    static var emptyAddress: String { String(localized: "Type your Home Assistant address.", bundle: .module) }
    static var badAddress: String {
        String(localized: "That doesn't look like an address. Try something like homeassistant.local:8123.", bundle: .module)
    }
    static var badScheme: String { String(localized: "Use an address that starts with http:// or https://.", bundle: .module) }
    static var notFound: String { String(localized: "Can't find your Home Assistant at that address.", bundle: .module) }
    static var unauthorized: String {
        String(localized: "Home Assistant didn't accept that token. Create a new one and paste it again.", bundle: .module)
    }
    static var needsTrust: String {
        String(localized: "This server uses its own certificate. Check it and trust it to continue.", bundle: .module)
    }
    static var localNetworkDenied: String {
        String(localized: "Altillo needs Local Network access. Turn it on in System Settings → Privacy & Security → Local Network.",
               bundle: .module)
    }
    static var timedOut: String { String(localized: "Home Assistant is taking too long to answer.", bundle: .module) }
    static var connectionLost: String { String(localized: "Lost the connection to Home Assistant.", bundle: .module) }
    static var notConnected: String { String(localized: "Not connected to Home Assistant.", bundle: .module) }
    static var otherServer: String { String(localized: "That belongs to another Home Assistant.", bundle: .module) }
    static var unsupported: String { String(localized: "That device can't do this.", bundle: .module) }
    static var unexpected: String { String(localized: "Home Assistant answered something unexpected.", bundle: .module) }
    static var keychain: String { String(localized: "Couldn't save the token in the Keychain.", bundle: .module) }
    static var noToken: String { String(localized: "There's no token saved for this server.", bundle: .module) }
    static var camera: String { String(localized: "Couldn't get the camera image.", bundle: .module) }
    static func haSaid(_ message: String) -> String {
        String(localized: "Home Assistant says: \(message)", bundle: .module)
    }
}
