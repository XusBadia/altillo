import Foundation

indirect enum NativeMailIMAPValue: Sendable, Equatable {
    case atom(String), bytes(Data), list([NativeMailIMAPValue])
    var text: String? {
        switch self { case .atom(let text): return text; case .bytes(let data): return String(decoding: data, as: UTF8.self); case .list: return nil }
    }
    var values: [Self]? { if case .list(let values) = self { return values }; return nil }
}

/// A bounded IMAP lexer: literals are byte counted, never split on their embedded CRLF or parentheses.
struct NativeMailIMAPParser {
    private let bytes: [UInt8]
    private var offset = 0
    private var tokens = 0
    init(_ data: Data) { bytes = Array(data) }

    mutating func parse() throws -> [NativeMailIMAPValue] { try sequence(depth: 0, nested: false) }

    private mutating func sequence(depth: Int, nested: Bool) throws -> [NativeMailIMAPValue] {
        guard depth <= 32 else { throw NativeMailFailure.invalidResponse }
        var result: [NativeMailIMAPValue] = []
        while offset < bytes.count {
            let byte = bytes[offset]
            if byte == 32 || byte == 13 || byte == 10 || byte == 9 { offset += 1; continue }
            if byte == 41 {
                guard nested else { throw NativeMailFailure.invalidResponse }
                offset += 1
                return result
            }
            tokens += 1
            guard tokens <= 100_000 else { throw NativeMailFailure.invalidResponse }
            if byte == 40 {
                offset += 1
                result.append(.list(try sequence(depth: depth + 1, nested: true)))
            } else if byte == 34 {
                offset += 1
                var value = Data(), closed = false
                while offset < bytes.count {
                    let next = bytes[offset]; offset += 1
                    if next == 34 { closed = true; break }
                    if next == 92 {
                        guard offset < bytes.count else { throw NativeMailFailure.invalidResponse }
                        value.append(bytes[offset]); offset += 1
                    } else { value.append(next) }
                }
                guard closed else { throw NativeMailFailure.invalidResponse }
                result.append(.bytes(value))
            } else if byte == 123 {
                offset += 1
                let start = offset
                while offset < bytes.count, (48...57).contains(bytes[offset]) { offset += 1 }
                guard start < offset, let size = Int(String(decoding: bytes[start..<offset], as: UTF8.self)),
                      offset + 2 < bytes.count, bytes[offset] == 125, bytes[offset + 1] == 13, bytes[offset + 2] == 10 else {
                    throw NativeMailFailure.invalidResponse
                }
                offset += 3
                guard size <= bytes.count - offset else { throw NativeMailFailure.invalidResponse }
                result.append(.bytes(Data(bytes[offset..<(offset + size)]))); offset += size
            } else {
                let start = offset
                var brackets = 0
                while offset < bytes.count {
                    let current = bytes[offset]
                    if current == 91 { brackets += 1 }
                    if current == 93 { brackets -= 1 }
                    if brackets == 0 && (current == 32 || current == 13 || current == 10 || current == 40 || current == 41) { break }
                    offset += 1
                }
                guard offset > start, brackets == 0 else { throw NativeMailFailure.invalidResponse }
                result.append(.atom(String(decoding: bytes[start..<offset], as: UTF8.self)))
            }
        }
        guard !nested else { throw NativeMailFailure.invalidResponse }
        return result
    }
}

struct NativeMailIMAPPart: Sendable {
    let id: String
    let mimeType: String
    let encoding: String
    let charset: String?
    let encodedBytes: Int
    let filename: String?
    let isAttachment: Bool

    static func flatten(_ value: NativeMailIMAPValue, id: String = "", depth: Int = 0) throws -> [Self] {
        guard depth <= 20, let items = value.values, !items.isEmpty else { throw NativeMailFailure.invalidResponse }
        if items[0].values != nil {
            var result: [Self] = []
            for (index, child) in items.enumerated() {
                guard child.values != nil else { break }
                let childID = id.isEmpty ? String(index + 1) : "\(id).\(index + 1)"
                result += try flatten(child, id: childID, depth: depth + 1)
                guard result.count <= 200 else { throw NativeMailFailure.invalidResponse }
            }
            return result
        }
        guard items.count >= 7, let type = items[0].text, let subtype = items[1].text,
              let encoding = items[5].text, let sizeString = items[6].text,
              let size = Int(sizeString), size >= 0 else { throw NativeMailFailure.invalidResponse }
        let mimeType = "\(type)/\(subtype)".lowercased()
        let bodyParameters = parameters(items[2])
        let dispositionIndex = type.uppercased() == "TEXT" ? 9 : (mimeType == "message/rfc822" ? 11 : 8)
        let disposition = items.indices.contains(dispositionIndex) ? items[dispositionIndex].values : nil
        let dispositionParameters = disposition.flatMap { $0.count > 1 ? parameters($0[1]) : nil } ?? [:]
        let rawName = dispositionParameters["filename*"] ?? dispositionParameters["filename"] ?? bodyParameters["name*"] ?? bodyParameters["name"]
        let filename = rawName.map { value in
            let extended = value.components(separatedBy: "''")
            let decoded = extended.count == 2 ? (extended[1].removingPercentEncoding ?? extended[1]) : NativeMailText.decodeHeader(value)
            return NativeMailText.bounded(decoded.replacingOccurrences(of: "\0", with: ""), utf8Limit: 1_024)
        }
        return [Self(id: id.isEmpty ? "1" : id, mimeType: mimeType, encoding: encoding.lowercased(),
                     charset: bodyParameters["charset"], encodedBytes: size, filename: filename,
                     isAttachment: filename != nil || disposition?.first?.text?.uppercased() == "ATTACHMENT" || !mimeType.hasPrefix("text/"))]
    }

    private static func parameters(_ value: NativeMailIMAPValue) -> [String: String] {
        guard let values = value.values else { return [:] }
        var result: [String: String] = [:]
        for index in stride(from: 0, to: values.count - 1, by: 2) {
            if let key = values[index].text, let text = values[index + 1].text { result[key.lowercased()] = text }
        }
        return result
    }
}

enum NativeMailRFC {
    static func headers(_ data: Data) -> [String: String] {
        let source = String(decoding: data.prefix(65_536), as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
        var unfolded: [String] = []
        for line in source.components(separatedBy: "\n") {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !unfolded.isEmpty {
                unfolded[unfolded.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            } else { unfolded.append(line) }
        }
        var result: [String: String] = [:]
        for line in unfolded {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased()
            if result[key] == nil { result[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces) }
        }
        return result
    }

    static func decoded(_ data: Data, encoding: String, truncated: Bool = false) throws -> Data {
        switch encoding.lowercased() {
        case "base64":
            let filtered = data.filter { byte in
                (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 43 || byte == 47 || byte == 61
            }
            let input = truncated ? Data(filtered.prefix(filtered.count / 4 * 4)) : filtered
            guard let result = Data(base64Encoded: input) else { throw NativeMailFailure.invalidResponse }
            return result
        case "quoted-printable":
            let bytes = Array(data)
            var result = Data(), index = 0
            while index < bytes.count {
                if bytes[index] == 61 {
                    if index + 2 < bytes.count, bytes[index + 1] == 13, bytes[index + 2] == 10 { index += 3; continue }
                    if index + 1 < bytes.count, bytes[index + 1] == 10 { index += 2; continue }
                    if index + 2 < bytes.count, let high = hex(bytes[index + 1]), let low = hex(bytes[index + 2]) {
                        result.append(high << 4 | low); index += 3; continue
                    }
                    if truncated && index + 2 >= bytes.count { break }
                }
                result.append(bytes[index]); index += 1
            }
            return result
        case "7bit", "8bit", "binary": return data
        default: throw NativeMailFailure.invalidResponse
        }
    }

    static func internalDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d-MMM-yyyy HH:mm:ss Z"
        formatter.isLenient = false
        return formatter.date(from: value.trimmingCharacters(in: .whitespaces))
    }

    private static func hex(_ byte: UInt8) -> UInt8? {
        switch byte { case 48...57: byte - 48; case 65...70: byte - 55; case 97...102: byte - 87; default: nil }
    }
}
