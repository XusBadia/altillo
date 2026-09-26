import Foundation

/// Reads what `mediaremote-adapter stream --micros` prints: one JSON object per line,
/// `{"type":"data","diff":Bool,"payload":{…}}`.
///
/// - `diff: false`: the payload *is* the state (`{}` when nothing plays).
/// - `diff: true`: only the keys that changed; `null` means the key went away.
///
/// Pure and synchronous, so the fixtures in the tests drive it exactly like the live helper does. The artwork
/// arrives as base64 (hundreds of KB) only when it changes, and is decoded once, here, off the main thread.
struct MediaRemoteAdapterStream {
    /// A payload value, free of `Any`.
    enum Value: Equatable, Sendable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case data(Data)
    }

    private(set) var state: [String: Value] = [:]

    /// Consumes one line. Returns the new snapshot (`.some(nil)`: nothing playing) when the line was a data
    /// message, `nil` when it wasn't one (a blank line, a log, garbage), which leaves the state untouched.
    mutating func consume(line: some StringProtocol) -> NowPlayingSnapshot?? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)),
              let message = object as? [String: Any],
              (message["type"] as? String) == "data"
        else { return nil }
        let payload = message["payload"] as? [String: Any] ?? [:]
        let diff = (message["diff"] as? Bool) ?? false
        if !diff { state = [:] }
        for (key, raw) in payload {
            if raw is NSNull {
                state[key] = nil
            } else if let value = Self.value(raw, key: key) {
                state[key] = value
            }
        }
        return .some(Self.snapshot(from: state))
    }

    // MARK: - Mapping

    /// The snapshot a state adds up to, or `nil` without the essentials (an app, a title, a playing flag).
    static func snapshot(from state: [String: Value]) -> NowPlayingSnapshot? {
        guard let title = text(state["title"]), let isPlaying = bool(state["playing"]) else { return nil }
        // Web audio is played by a WebKit helper; the app worth naming is its parent (Safari, a web app…).
        guard let bundleID = text(state["parentApplicationBundleIdentifier"]) ?? text(state["bundleIdentifier"])
        else { return nil }
        let duration = (number(state["durationMicros"]) ?? number(state["duration"]).map { $0 * 1_000_000 })
            .flatMap { $0 > 0 ? $0 / 1_000_000 : nil }
        let elapsed = (number(state["elapsedTimeMicros"]) ?? number(state["elapsedTime"]).map { $0 * 1_000_000 })
            .map { max(0, $0 / 1_000_000) }
        let timestamp = number(state["timestampEpochMicros"]).map { Date(timeIntervalSince1970: $0 / 1_000_000) }
        let reportedRate = number(state["playbackRate"]) ?? 0
        var artwork: Data?
        if case let .data(data)? = state["artworkData"], !data.isEmpty { artwork = data }
        return NowPlayingSnapshot(
            bundleID: bundleID,
            title: title,
            artist: text(state["artist"]) ?? "",
            album: text(state["album"]),
            duration: duration,
            elapsed: elapsed,
            timestamp: timestamp,
            // Paused players report 0; the rate only matters while playing, and "unknown" means normal speed.
            rate: reportedRate > 0 ? reportedRate : 1,
            isPlaying: isPlaying,
            artwork: artwork
        )
    }

    private static func value(_ raw: Any, key: String) -> Value? {
        if key == "artworkData" {
            guard let base64 = raw as? String else { return nil }
            return Data(base64Encoded: base64, options: .ignoreUnknownCharacters).map(Value.data)
        }
        if let string = raw as? String { return .string(string) }
        if let number = raw as? NSNumber {
            // JSONSerialization hands booleans over as NSNumber too; only CFBoolean is a real one.
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            return .number(number.doubleValue)
        }
        return nil
    }

    private static func text(_ value: Value?) -> String? {
        guard case let .string(string)? = value else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(_ value: Value?) -> Double? {
        switch value {
        case let .number(number)?: number.isFinite ? number : nil
        case let .bool(flag)?: flag ? 1 : 0
        default: nil
        }
    }

    private static func bool(_ value: Value?) -> Bool? {
        switch value {
        case let .bool(flag)?: flag
        case let .number(number)?: number != 0
        default: nil
        }
    }
}

/// Splits a byte stream into lines. Chunks from a pipe can end mid-line (and mid-UTF-8 character), so bytes are
/// kept until their newline arrives.
struct LineSplitter {
    private var pending = Data()

    mutating func append(_ chunk: Data) -> [String] {
        pending.append(chunk)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            lines.append(String(decoding: line, as: UTF8.self))
            pending.removeSubrange(pending.startIndex...newline)
        }
        return lines
    }
}
