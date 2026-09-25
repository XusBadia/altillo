import Foundation

/// Any JSON, decoded without a schema. Hook payloads and session files change between agent versions, so the
/// engine reads them through this tolerant view: a missing or mistyped field is `nil`, never a thrown error.
public enum JSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Parses UTF-8 JSON; nil when it isn't JSON.
    public static func parse(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func parse(_ text: String) -> JSONValue? { parse(Data(text.utf8)) }

    /// Compact UTF-8 JSON (never contains a raw newline, so it is safe to frame by lines).
    public var data: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data("null".utf8)
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        if case .array(let array) = self, array.indices.contains(index) { return array[index] }
        return nil
    }

    /// Follows a dotted path ("tool_input.command").
    public func value(at path: String) -> JSONValue? {
        var current: JSONValue? = self
        for key in path.split(separator: ".") { current = current?[String(key)] }
        return current
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// A string, or a number/bool rendered as text.
    public var text: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value ? String(Int64(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var isNull: Bool { self == .null }
}

extension Optional where Wrapped == JSONValue {
    /// `payload["x"].nonEmptyString`: the string when present and not blank.
    public var nonEmptyString: String? {
        guard let value = self?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
