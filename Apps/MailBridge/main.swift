import AltilloMail
import Darwin
import Foundation

// Mail starts this helper with no message fields in argv. It never prints payloads or decoding errors.
// Exit status is the sole result consumed by the rule, including when Altillo isn't listening.
let arguments = Array(CommandLine.arguments.dropFirst())
let socketPath: String
if arguments.isEmpty {
    socketPath = MailWire.defaultSocketPath
} else if arguments.count == 2, arguments[0] == "--socket", !arguments[1].isEmpty {
    socketPath = arguments[1]
} else {
    exit(1)
}

do {
    let data = try MailBridgeClient.readInput()
    _ = try MailBridgeClient.deliver(data, path: socketPath)
    exit(0)
} catch {
    exit(1)
}
