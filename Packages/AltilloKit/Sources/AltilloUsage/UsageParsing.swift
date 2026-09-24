import AltilloCore
import Foundation

/// Lenient readers for the providers' private JSON: numbers that may arrive as strings, dates as ISO-8601 (with or
/// without fractional seconds of any precision) or epoch seconds/milliseconds, hex-wrapped keychain values.
enum UsageParsing {
    /// Parses a JSON object, nil for anything else.
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// A finite number from a JSON number or numeric string (booleans are not numbers).
    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            let double = number.doubleValue
            return double.isFinite ? double : nil
        }
        if let text = value as? String, let double = Double(text.trimmingCharacters(in: .whitespaces)),
           double.isFinite {
            return double
        }
        return nil
    }

    /// Non-empty trimmed string.
    static func string(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    /// ISO-8601 text or an epoch number (seconds, or milliseconds when ≥ 1e10).
    static func date(_ value: Any?) -> Date? {
        if let text = string(value) {
            if let date = isoDate(text) { return date }
            if let number = Double(text) { return epochDate(number) }
            return nil
        }
        if let number = number(value) { return epochDate(number) }
        return nil
    }

    static func epochDate(_ number: Double) -> Date? {
        guard number.isFinite, number > 0 else { return nil }
        return Date(timeIntervalSince1970: abs(number) >= 1e10 ? number / 1000 : number)
    }

    /// `2026-09-24T15:10:00Z`, `…00.720Z`, `…00.720317+00:00`, `…00+0200`. Fractions of any length are kept.
    static func isoDate(_ text: String) -> Date? {
        let pattern = #"^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(\.\d+)?(Z|z|[+-]\d{2}(?::?\d{2})?)?$"#
        guard let match = text.wholeMatch(of: try! Regex(pattern)) else { return nil }
        guard let day = match.output[1].substring, let time = match.output[2].substring else { return nil }
        let fraction = match.output[3].substring.flatMap { Double("0" + $0) } ?? 0
        var zone = match.output[4].substring.map(String.init) ?? "Z"
        if zone == "z" { zone = "Z" }
        if zone != "Z" {
            // Normalise "+02", "+0200" and "+02:00" to "+02:00".
            let sign = zone.prefix(1)
            let digits = zone.dropFirst().filter(\.isNumber)
            let hours = digits.prefix(2)
            let minutes = digits.count >= 4 ? String(digits.suffix(2)) : "00"
            zone = "\(sign)\(hours):\(minutes)"
        }
        guard let base = try? Date("\(day)T\(time)\(zone)", strategy: .iso8601) else { return nil }
        return base.addingTimeInterval(fraction)
    }

    /// Decodes a hex string (optionally `0x`-prefixed) to UTF-8 text.
    static func hexDecodedString(_ text: String) -> String? {
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") { hex = String(hex.dropFirst(2)) }
        guard !hex.isEmpty, hex.count.isMultiple(of: 2), hex.allSatisfy(\.isHexDigit) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// JSON object from text that is either JSON or hex-encoded JSON (how some Claude Code versions store it).
    static func objectWithHexFallback(_ text: String) -> [String: Any]? {
        if let data = text.data(using: .utf8), let object = object(data) { return object }
        guard let decoded = hexDecodedString(text), let data = decoded.data(using: .utf8) else { return nil }
        return object(data)
    }

    /// `Retry-After`: delta seconds or an HTTP date. Nil when absent or unreadable.
    static func retryAfter(_ header: String?, now: Date) -> Date? {
        guard let raw = header?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let seconds = Int(raw), seconds >= 0 { return now.addingTimeInterval(TimeInterval(seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE',' dd MMM yyyy HH':'mm':'ss zzz", "EEEE',' dd'-'MMM'-'yy HH':'mm':'ss zzz",
                       "EEE MMM d HH':'mm':'ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return max(date, now) }
        }
        return nil
    }

    /// "max" → "Max", "team_plan" → "Team Plan", "rateLimitResets" → "Rate Limit Resets".
    static func titleCased(_ raw: String) -> String {
        var words: [String] = []
        var current = ""
        for character in raw {
            if character == "_" || character == "-" || character == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase, let last = current.last, last.isLowercase || last.isNumber {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }

    /// Stable id fragment: "Claude Fable 5" → "claude-fable-5".
    static func slug(_ raw: String) -> String {
        let lowered = raw.lowercased()
        var result = ""
        var lastWasDash = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash, !result.isEmpty {
                result.append("-")
                lastWasDash = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "model" : result
    }
}

extension HTTPURLResponse {
    /// Case-insensitive header lookup.
    func header(_ name: String) -> String? { value(forHTTPHeaderField: name) }
}

extension Array where Element == UsageWindow {
    /// Session first, then weekly, then per-model weeks, then the rest (the order `ProviderUsage.windows` promises).
    /// Stable within each kind.
    func sortedForDisplay() -> [UsageWindow] {
        func rank(_ kind: UsageWindow.Kind) -> Int {
            switch kind {
            case .session: 0
            case .weekly: 1
            case .modelWeekly: 2
            case .monthly: 3
            case .other: 4
            }
        }
        return enumerated().sorted { lhs, rhs in
            let (l, r) = (rank(lhs.element.kind), rank(rhs.element.kind))
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map(\.element)
    }
}
