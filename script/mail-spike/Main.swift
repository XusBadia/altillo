// R01 experiment only. Compiled alongside AltilloAgents/UnixSocket.swift, never linked into Altillo.app.
import AppKit
import Foundation
import Darwin

// Same framing contract as AltilloAgents. Kept local so this experiment needn't build the full package.
public struct LineBuffer {
    private var buffer = Data()
    let limit: Int
    public init(limit: Int) { self.limit = limit }
    public var isOverLimit: Bool { buffer.count > limit }
    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let end = buffer.firstIndex(of: 10) {
            lines.append(Data(buffer[..<end]))
            buffer.removeSubrange(...end)
        }
        return lines
    }
}

enum ProbeError: Error { case invalid, expired, unavailable, timeout }

struct MailEvent: Codable, Sendable {
    static let prefix = "ALTILLO-MAIL-SPIKE "
    static let byteLimit = 65_536
    let version: Int
    let messageID: String
    let sender: String
    let subject: String
    let body: String
    let receivedAt: Double

    static func decode(_ data: Data, now: Date = .now) throws -> MailEvent {
        guard data.count <= byteLimit else { throw ProbeError.invalid }
        let event = try JSONDecoder().decode(Self.self, from: data)
        guard event.version == 1, event.subject.hasPrefix(prefix),
              !event.messageID.isEmpty, event.messageID.utf8.count <= 512,
              !event.messageID.contains(where: { $0.isWhitespace || $0.isNewline }),
              event.sender.utf8.count <= 1_024, event.subject.utf8.count <= 1_024,
              event.body.utf8.count <= 48_000, event.receivedAt.isFinite else { throw ProbeError.invalid }
        let age = now.timeIntervalSince1970 - event.receivedAt
        guard age >= -30, age <= 300 else { throw ProbeError.expired }
        return event
    }

    var openURL: URL? {
        let id = messageID.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let escaped = "<\(id)>".addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "message://" + escaped)
    }

    // Conservative heuristic, not a claim to understand all authentication mail. Multiple candidates => no action.
    var code: String? {
        let expression = #"(?i)(?:verification\s+code|security\s+code|sign[ -]?in\s+code|código(?:\s+de\s+(?:acceso|verificación))?|code)\s*(?:is|es|:|=|-)?\s*\b([0-9]{4,8})\b"#
        guard let regex = try? NSRegularExpression(pattern: expression) else { return nil }
        let text = subject + "\n" + body
        let values = Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        })
        return values.count == 1 ? values.first : nil
    }

    var magicLink: URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let matches = detector.matches(in: body, range: NSRange(body.startIndex..., in: body))
        let links = Set(matches.compactMap { match -> URL? in
            guard let url = match.url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
                  let host = url.host, !host.isEmpty, host.unicodeScalars.allSatisfy({ $0.isASCII }),
                  let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  parts.queryItems?.contains(where: {
                      ["token", "magic_token", "login_token", "verification_token"].contains($0.name.lowercased())
                          && !($0.value ?? "").isEmpty
                  }) == true else { return nil }
            return url
        })
        return links.count == 1 ? links.first : nil
    }
}

final class MailServer: @unchecked Sendable {
    private let path: String
    private let queue = DispatchQueue(label: "me.badia.altillo.mail-spike")
    private var source: DispatchSourceRead?
    private var bound: UnixSocket.Listener?
    private var seen: [String: Date] = [:]
    private let receive: @Sendable (MailEvent) -> Void

    init(path: String, receive: @escaping @Sendable (MailEvent) -> Void) {
        self.path = path
        self.receive = receive
    }

    func start() throws {
        // Never let UnixSocket.listen chmod an arbitrary existing directory supplied on the command line.
        let parent = (path as NSString).deletingLastPathComponent
        var info = stat()
        guard lstat(parent, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0 else { throw ProbeError.invalid }
        let listener = try UnixSocket.listen(path: path)
        bound = listener
        let source = DispatchSource.makeReadSource(fileDescriptor: listener.fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending(listener.fd) }
        source.setCancelHandler { close(listener.fd) }
        self.source = source
        source.resume()
    }

    func stop() {
        queue.sync {
            source?.cancel()
            source = nil
            if let bound { UnixSocket.removeIfOwned(path: path, listener: bound) }
            bound = nil
            seen.removeAll()
        }
    }

    private func acceptPending(_ listener: Int32) {
        // A small, bounded experiment; one stalled peer costs at most 0.5 seconds.
        for _ in 0..<8 {
            guard let fd = UnixSocket.accept(listener) else { return }
            defer { close(fd) }
            guard UnixSocket.peerIsSameUser(fd), let data = UnixSocket.readLine(fd, timeout: 0.5),
                  let event = try? MailEvent.decode(data) else {
                _ = UnixSocket.writeAll(fd, Data("rejected\n".utf8), timeout: 0.1)
                continue
            }
            let now = Date()
            seen = seen.filter { now.timeIntervalSince($0.value) < 300 }
            if seen[event.messageID] != nil {
                _ = UnixSocket.writeAll(fd, Data("duplicate\n".utf8), timeout: 0.1)
                continue
            }
            if seen.count >= 64, let oldest = seen.min(by: { $0.value < $1.value }) { seen[oldest.key] = nil }
            seen[event.messageID] = now
            receive(event)
            _ = UnixSocket.writeAll(fd, Data("accepted\n".utf8), timeout: 0.1)
        }
    }
}

@MainActor
final class MailPanel: NSObject {
    private var panel: NSPanel?
    private var event: MailEvent?
    private var expiry: Timer?

    func show(_ event: MailEvent) {
        dismiss()
        self.event = event
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 480, height: CGFloat = 212
        let frame = NSRect(x: screen.frame.midX - width / 2,
                           y: screen.visibleFrame.maxY - height - 12, width: width, height: height)
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.hasShadow = true
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 15, left: 18, bottom: 15, right: 18)
        func label(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
            let field = NSTextField(labelWithString: text.replacingOccurrences(of: "\n", with: " "))
            field.font = .systemFont(ofSize: size)
            field.textColor = color
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            return field
        }
        stack.addArrangedSubview(label("Prueba de correo · no integrada en Altillo", size: 11, color: .secondaryLabelColor))
        stack.addArrangedSubview(label(event.sender, size: 14, color: .white))
        stack.addArrangedSubview(label(event.subject, size: 13, color: .white))
        let actions = NSStackView()
        actions.spacing = 10
        func button(_ title: String, _ action: Selector) {
            actions.addArrangedSubview(NSButton(title: title, target: self, action: action))
        }
        if let code = event.code { button("Copiar \(code)", #selector(copyCode)) }
        if let link = event.magicLink { button("Abrir \(link.host ?? "enlace")", #selector(openLink)) }
        stack.addArrangedSubview(actions)
        let navigation = NSStackView()
        navigation.spacing = 10
        navigation.addArrangedSubview(NSButton(title: "Ver en Mail", target: self, action: #selector(openMessage)))
        navigation.addArrangedSubview(NSButton(title: "Cerrar", target: self, action: #selector(closePanel)))
        stack.addArrangedSubview(navigation)
        stack.addArrangedSubview(label("Solo memoria · se cierra en 30 segundos", size: 11, color: .secondaryLabelColor))
        window.contentView = stack
        self.panel = window
        window.orderFrontRegardless()
        expiry = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    func dismiss() {
        expiry?.invalidate()
        expiry = nil
        panel?.close()
        panel = nil
        event = nil
    }

    @objc private func copyCode() {
        guard let event, Date().timeIntervalSince1970 - event.receivedAt < 300, let code = event.code else { return }
        NSPasteboard.general.clearContents()
        // Altillo Clipboard and other conforming managers ignore concealed content.
        NSPasteboard.general.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        NSPasteboard.general.setString(code, forType: .string)
    }
    @objc private func openLink() {
        guard let event, Date().timeIntervalSince1970 - event.receivedAt < 300, let url = event.magicLink else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func openMessage() { if let url = event?.openURL { NSWorkspace.shared.open(url) } }
    @objc private func closePanel() { dismiss() }
}

@main
struct MailSpike {
    @MainActor static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard let mode = args.first else { throw ProbeError.invalid }
            func value(_ flag: String) -> String? {
                guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
                return args[index + 1]
            }
            if mode == "self-test" { try selfTest(); return }
            guard let path = value("--socket") else { throw ProbeError.invalid }
            if mode == "send" {
                let payload = try readInput()
                _ = try MailEvent.decode(payload)
                let fd = try UnixSocket.connect(path: path, timeout: 0.3)
                defer { close(fd) }
                guard UnixSocket.peerIsSameUser(fd),
                      UnixSocket.writeAll(fd, payload + Data([10]), timeout: 0.3),
                      let response = UnixSocket.readLine(fd, timeout: 0.8),
                      ["accepted", "duplicate"].contains(String(decoding: response, as: UTF8.self)) else { throw ProbeError.unavailable }
                print(String(decoding: response, as: UTF8.self))
            } else if mode == "listen" {
                let headless = args.contains("--headless")
                let duration = min(300, max(1, Double(value("--duration") ?? "60") ?? 60))
                let panel = headless ? nil : MailPanel()
                if !headless { NSApplication.shared.setActivationPolicy(.accessory) }
                let server = MailServer(path: path) { event in
                    // Only booleans, never sender/subject/body/ID/code/link in logs.
                    FileHandle.standardOutput.write(Data("received code=\(event.code != nil) link=\(event.magicLink != nil)\n".utf8))
                    if !headless { Task { @MainActor in panel?.show(event) } }
                }
                try server.start()
                FileHandle.standardOutput.write(Data("listening\n".utf8))
                if headless {
                    RunLoop.current.run(until: Date().addingTimeInterval(duration))
                } else {
                    let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
                        MainActor.assumeIsolated {
                            NSApp.stop(nil)
                            let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                                                         timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)
                            if let wake { NSApp.postEvent(wake, atStart: true) }
                        }
                    }
                    NSApplication.shared.run()
                    timer.invalidate()
                }
                panel?.dismiss()
                server.stop()
                print("stopped")
            } else { throw ProbeError.invalid }
        } catch {
            // Error descriptions can include decoding fragments or paths. Keep diagnostics categorical.
            FileHandle.standardError.write(Data("mail-spike failed (invalid, expired or unavailable input/bridge)\n".utf8))
            exit(1)
        }
    }

    private static func readInput() throws -> Data {
        let deadline = Date().addingTimeInterval(1)
        var data = Data(), chunk = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 100) >= 0 else { throw ProbeError.invalid }
            if descriptor.revents == 0 { continue }
            let count = Darwin.read(STDIN_FILENO, &chunk, chunk.count)
            if count == 0 { return data }
            guard count > 0 else { throw ProbeError.invalid }
            data.append(contentsOf: chunk.prefix(count))
            guard data.count <= MailEvent.byteLimit else { throw ProbeError.invalid }
        }
        throw ProbeError.timeout
    }

    private static func selfTest() throws {
        let now = Date()
        func event(_ body: String, id: String = "fixture@example.invalid", age: Double = 0) -> MailEvent {
            MailEvent(version: 1, messageID: id, sender: "Altillo prueba", subject: MailEvent.prefix + "Acceso",
                      body: body, receivedAt: now.timeIntervalSince1970 - age)
        }
        func check(_ condition: @autoclosure () -> Bool) throws { if !condition() { throw ProbeError.invalid } }
        try check(event("Your verification code is 482913").code == "482913")
        try check(event("Tu código de acceso: 482913").code == "482913")
        try check(event("Code: 1234. Code: 5678").code == nil)
        try check(event("Invoice 482913, total 2026").code == nil)
        try check(event("code: 123456789").code == nil)
        try check(event("https://example.invalid/login?token=synthetic").magicLink?.host == "example.invalid")
        try check(event("http://example.invalid/login?token=synthetic").magicLink == nil)
        try check(event("https://user:password@example.invalid/login?token=synthetic").magicLink == nil)
        try check(event("https://example.invalid/a?token=a https://example.invalid/b?token=b").magicLink == nil)
        try check(event("https://example.invalid/newsletter").magicLink == nil)
        try check(event("").openURL?.absoluteString == "message://%3Cfixture%40example.invalid%3E")
        let original = event("Unicode: café 日本語 · \"quoted\"\nsecond line")
        let decoded = try MailEvent.decode(JSONEncoder().encode(original), now: now)
        try check(decoded.body == original.body)
        for invalid in [event("", age: 301), event("", age: -31), event("", id: "bad\nid"), event(String(repeating: "a", count: 48_001))] {
            let data = try JSONEncoder().encode(invalid)
            try check((try? MailEvent.decode(data, now: now)) == nil)
        }
        print("parser self-tests passed")
    }
}
