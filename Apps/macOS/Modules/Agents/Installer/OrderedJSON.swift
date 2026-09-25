import Foundation

/// A JSON value that keeps what `JSONSerialization` throws away: the order of an object's keys (and duplicate keys)
/// and the exact spelling of every number. The hook installer edits other apps' config files with it, so that a
/// file Altillo touches changes only where Altillo's entries go and a round trip of an untouched document is
/// byte-for-byte the same as `JSON.stringify(value, null, 2)` (what Claude Code and Codex write).
enum OrderedJSON: Equatable, Sendable {
    case object([Member])
    case array([OrderedJSON])
    case string(String)
    /// The number exactly as written (`1`, `1.0`, `1e3`), so re-serializing never rewrites it.
    case number(String)
    case bool(Bool)
    case null

    struct Member: Equatable, Sendable {
        var key: String
        var value: OrderedJSON
    }

    // MARK: Access

    var members: [Member]? {
        if case .object(let members) = self { members } else { nil }
    }

    var elements: [OrderedJSON]? {
        if case .array(let elements) = self { elements } else { nil }
    }

    var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    /// The value of the first member named `key` (objects only).
    subscript(key: String) -> OrderedJSON? {
        members?.first { $0.key == key }?.value
    }

    /// Replaces the first member named `key` in place, or appends it at the end. No-op on non-objects.
    mutating func set(_ key: String, _ value: OrderedJSON) {
        guard var members else { return }
        if let index = members.firstIndex(where: { $0.key == key }) {
            members[index].value = value
        } else {
            members.append(Member(key: key, value: value))
        }
        self = .object(members)
    }

    /// Removes every member named `key`. No-op on non-objects.
    mutating func remove(_ key: String) {
        guard let members else { return }
        self = .object(members.filter { $0.key != key })
    }

    // MARK: Parsing

    struct ParseError: Error, Equatable, CustomStringConvertible, Sendable {
        let line: Int
        let column: Int
        let reason: String

        var description: String { "line \(line), column \(column): \(reason)" }
    }

    /// Strict JSON (RFC 8259), with an optional UTF-8 byte-order mark. No comments, no trailing commas: the agents
    /// themselves reject those, so accepting them would only hide a broken file.
    static func parse(_ data: Data) throws(ParseError) -> OrderedJSON {
        var parser = Parser(bytes: Array(data))
        return try parser.parseDocument()
    }

    static func parse(_ text: String) throws(ParseError) -> OrderedJSON {
        try parse(Data(text.utf8))
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        init(bytes: [UInt8]) {
            // Skip a UTF-8 BOM.
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
                self.bytes = Array(bytes.dropFirst(3))
            } else {
                self.bytes = bytes
            }
        }

        mutating func parseDocument() throws(ParseError) -> OrderedJSON {
            skipWhitespace()
            guard index < bytes.count else { throw error("the file is empty") }
            let value = try parseValue(depth: 0)
            skipWhitespace()
            guard index == bytes.count else { throw error("unexpected text after the end of the document") }
            return value
        }

        private mutating func parseValue(depth: Int) throws(ParseError) -> OrderedJSON {
            guard depth < 512 else { throw error("nested too deeply") }
            skipWhitespace()
            guard index < bytes.count else { throw error("unexpected end of file") }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try parseObject(depth: depth)
            case UInt8(ascii: "["): return try parseArray(depth: depth)
            case UInt8(ascii: "\""): return .string(try parseString())
            case UInt8(ascii: "t"): try expectLiteral("true"); return .bool(true)
            case UInt8(ascii: "f"): try expectLiteral("false"); return .bool(false)
            case UInt8(ascii: "n"): try expectLiteral("null"); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try parseNumber())
            default: throw error("unexpected character '\(Character(Unicode.Scalar(bytes[index])))'")
            }
        }

        private mutating func parseObject(depth: Int) throws(ParseError) -> OrderedJSON {
            index += 1
            var members: [Member] = []
            skipWhitespace()
            if peek(UInt8(ascii: "}")) { index += 1; return .object(members) }
            while true {
                skipWhitespace()
                guard peek(UInt8(ascii: "\"")) else { throw error("expected a key in quotes") }
                let key = try parseString()
                skipWhitespace()
                guard peek(UInt8(ascii: ":")) else { throw error("expected ':' after a key") }
                index += 1
                let value = try parseValue(depth: depth + 1)
                members.append(Member(key: key, value: value))
                skipWhitespace()
                if peek(UInt8(ascii: ",")) { index += 1; continue }
                if peek(UInt8(ascii: "}")) { index += 1; return .object(members) }
                throw error("expected ',' or '}'")
            }
        }

        private mutating func parseArray(depth: Int) throws(ParseError) -> OrderedJSON {
            index += 1
            var elements: [OrderedJSON] = []
            skipWhitespace()
            if peek(UInt8(ascii: "]")) { index += 1; return .array(elements) }
            while true {
                elements.append(try parseValue(depth: depth + 1))
                skipWhitespace()
                if peek(UInt8(ascii: ",")) { index += 1; continue }
                if peek(UInt8(ascii: "]")) { index += 1; return .array(elements) }
                throw error("expected ',' or ']'")
            }
        }

        private mutating func parseString() throws(ParseError) -> String {
            index += 1 // opening quote
            var scalars = String.UnicodeScalarView()
            var chunkStart = index
            func flush(_ end: Int) throws(ParseError) {
                guard end > chunkStart else { return }
                guard let text = String(validating: bytes[chunkStart..<end], as: UTF8.self) else {
                    throw error("the file isn't valid UTF-8")
                }
                scalars.append(contentsOf: text.unicodeScalars)
            }
            while true {
                guard index < bytes.count else { throw error("a string never ends") }
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") {
                    try flush(index)
                    index += 1
                    return String(scalars)
                }
                if byte < 0x20 { throw error("a control character inside a string") }
                if byte == UInt8(ascii: "\\") {
                    try flush(index)
                    index += 1
                    guard index < bytes.count else { throw error("a string never ends") }
                    let escape = bytes[index]
                    index += 1
                    switch escape {
                    case UInt8(ascii: "\""): scalars.append("\"")
                    case UInt8(ascii: "\\"): scalars.append("\\")
                    case UInt8(ascii: "/"): scalars.append("/")
                    case UInt8(ascii: "b"): scalars.append("\u{08}")
                    case UInt8(ascii: "f"): scalars.append("\u{0C}")
                    case UInt8(ascii: "n"): scalars.append("\n")
                    case UInt8(ascii: "r"): scalars.append("\r")
                    case UInt8(ascii: "t"): scalars.append("\t")
                    case UInt8(ascii: "u"):
                        let high = try parseHex4()
                        if (0xD800...0xDBFF).contains(high) {
                            guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"),
                                  bytes[index + 1] == UInt8(ascii: "u") else {
                                throw error("a lone surrogate in a \\u escape")
                            }
                            index += 2
                            let low = try parseHex4()
                            guard (0xDC00...0xDFFF).contains(low) else { throw error("a lone surrogate in a \\u escape") }
                            let value = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
                            guard let scalar = Unicode.Scalar(value) else { throw error("an invalid \\u escape") }
                            scalars.append(scalar)
                        } else {
                            guard let scalar = Unicode.Scalar(high) else { throw error("a lone surrogate in a \\u escape") }
                            scalars.append(scalar)
                        }
                    default:
                        throw error("an invalid escape in a string")
                    }
                    chunkStart = index
                    continue
                }
                index += 1
            }
        }

        private mutating func parseHex4() throws(ParseError) -> UInt32 {
            guard index + 4 <= bytes.count else { throw error("an unfinished \\u escape") }
            var value: UInt32 = 0
            for _ in 0..<4 {
                let byte = bytes[index]
                let digit: UInt32
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
                case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a") + 10)
                case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A") + 10)
                default: throw error("an invalid \\u escape")
                }
                value = value * 16 + digit
                index += 1
            }
            return value
        }

        private mutating func parseNumber() throws(ParseError) -> String {
            let start = index
            if peek(UInt8(ascii: "-")) { index += 1 }
            guard index < bytes.count, isDigit(bytes[index]) else { throw error("an invalid number") }
            if bytes[index] == UInt8(ascii: "0") {
                index += 1
            } else {
                while index < bytes.count, isDigit(bytes[index]) { index += 1 }
            }
            if peek(UInt8(ascii: ".")) {
                index += 1
                guard index < bytes.count, isDigit(bytes[index]) else { throw error("an invalid number") }
                while index < bytes.count, isDigit(bytes[index]) { index += 1 }
            }
            if peek(UInt8(ascii: "e")) || peek(UInt8(ascii: "E")) {
                index += 1
                if peek(UInt8(ascii: "+")) || peek(UInt8(ascii: "-")) { index += 1 }
                guard index < bytes.count, isDigit(bytes[index]) else { throw error("an invalid number") }
                while index < bytes.count, isDigit(bytes[index]) { index += 1 }
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        private mutating func expectLiteral(_ literal: String) throws(ParseError) {
            let expected = Array(literal.utf8)
            guard index + expected.count <= bytes.count,
                  Array(bytes[index..<index + expected.count]) == expected else {
                throw error("unexpected text")
            }
            index += expected.count
        }

        private mutating func skipWhitespace() {
            while index < bytes.count {
                switch bytes[index] {
                case 0x20, 0x09, 0x0A, 0x0D: index += 1
                default: return
                }
            }
        }

        private func peek(_ byte: UInt8) -> Bool { index < bytes.count && bytes[index] == byte }
        private func isDigit(_ byte: UInt8) -> Bool { byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }

        private func error(_ reason: String) -> ParseError {
            var line = 1
            var column = 1
            for byte in bytes[..<min(index, bytes.count)] {
                if byte == 0x0A { line += 1; column = 1 } else if byte & 0xC0 != 0x80 { column += 1 }
            }
            return ParseError(line: line, column: column, reason: reason)
        }
    }

    // MARK: Serializing

    /// The layout of a file, so a rewrite keeps it: its indent unit and whether it ends with a newline.
    struct Style: Equatable, Sendable {
        var indent: String
        var trailingNewline: Bool

        /// Two spaces and a final newline, like Claude Code's and Codex's own files.
        static let standard = Style(indent: "  ", trailingNewline: true)

        /// Reads the indent from the first indented line and whether the text ends with a newline.
        static func detect(in text: String) -> Style {
            var indent = "  "
            for line in text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst() {
                let leading = line.prefix { $0 == " " || $0 == "\t" }
                if !leading.isEmpty {
                    indent = String(leading)
                    break
                }
            }
            return Style(indent: indent, trailingNewline: text.hasSuffix("\n"))
        }
    }

    /// Pretty-printed like `JSON.stringify(value, null, indent)`: `"key": value`, empty containers as `{}`/`[]`,
    /// only `"`, `\` and control characters escaped.
    func serialized(style: Style = .standard) -> String {
        var output = ""
        write(into: &output, level: 0, indent: style.indent)
        if style.trailingNewline { output += "\n" }
        return output
    }

    private func write(into output: inout String, level: Int, indent: String) {
        switch self {
        case .object(let members):
            guard !members.isEmpty else { output += "{}"; return }
            output += "{\n"
            for (offset, member) in members.enumerated() {
                output += String(repeating: indent, count: level + 1)
                Self.writeString(member.key, into: &output)
                output += ": "
                member.value.write(into: &output, level: level + 1, indent: indent)
                output += offset == members.count - 1 ? "\n" : ",\n"
            }
            output += String(repeating: indent, count: level) + "}"
        case .array(let elements):
            guard !elements.isEmpty else { output += "[]"; return }
            output += "[\n"
            for (offset, element) in elements.enumerated() {
                output += String(repeating: indent, count: level + 1)
                element.write(into: &output, level: level + 1, indent: indent)
                output += offset == elements.count - 1 ? "\n" : ",\n"
            }
            output += String(repeating: indent, count: level) + "]"
        case .string(let value):
            Self.writeString(value, into: &output)
        case .number(let raw):
            output += raw
        case .bool(let value):
            output += value ? "true" : "false"
        case .null:
            output += "null"
        }
    }

    private static func writeString(_ value: String, into output: inout String) {
        output += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{08}": output += "\\b"
            case "\u{0C}": output += "\\f"
            case _ where scalar.value < 0x20:
                output += "\\u" + String(format: "%04x", scalar.value)
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }
}
