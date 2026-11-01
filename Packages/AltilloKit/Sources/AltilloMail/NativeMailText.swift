import Foundation

/// A deliberately non-rendering HTML/MIME text reader. It has no browser, resource loader or network access.
public enum NativeMailText {
    public static let bodyByteLimit = 1_048_576

    public static func bounded(_ text: String, utf8Limit: Int) -> String {
        guard utf8Limit > 0 else { return "" }
        guard text.utf8.count > utf8Limit else { return text }
        var bytes = 0
        var output = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let count = scalar.utf8.count
            if bytes + count > utf8Limit { break }
            output.append(scalar); bytes += count
        }
        return String(output)
    }

    public static func plainText(fromHTML html: String, limit: Int = bodyByteLimit) -> String {
        // Tokenise rather than asking an HTML renderer to import the document: even malformed markup cannot
        // fetch images, styles, fonts, frames or execute code. Limit source work as well as the final text.
        let outputLimit = max(0, min(limit, bodyByteLimit))
        let source = bounded(html, utf8Limit: outputLimit * 4)
        let blocked: Set<String> = ["script", "style", "form", "iframe", "object", "template", "noscript", "svg", "math"]
        let breaks: Set<String> = ["br", "p", "div", "li", "tr", "table", "section", "article", "blockquote", "h1", "h2", "h3", "h4", "hr"]
        var output = "", hidden: [String] = []
        var index = source.startIndex
        while index < source.endIndex {
            if source[index] != "<" {
                if hidden.isEmpty { output.append(source[index]) }
                index = source.index(after: index)
                continue
            }
            if source[index...].hasPrefix("<!--") {
                if let end = source[index...].range(of: "-->") { index = end.upperBound } else { break }
                continue
            }
            // A '>' inside a quoted attribute does not close the tag.
            var end = source.index(after: index), quote: Character?
            while end < source.endIndex {
                let character = source[end]
                if let currentQuote = quote {
                    if character == currentQuote { quote = nil }
                } else if character == "\"" || character == "'" { quote = character }
                else if character == ">" { break }
                end = source.index(after: end)
            }
            guard end < source.endIndex else { break }
            var token = source[source.index(after: index)..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            let closing = token.hasPrefix("/")
            if closing { token.removeFirst(); token = token.trimmingCharacters(in: .whitespacesAndNewlines) }
            let name = String(token.prefix { $0.isASCII && ($0.isLetter || $0.isNumber) }).lowercased()
            if blocked.contains(name) {
                if closing, let matching = hidden.lastIndex(of: name) { hidden.removeSubrange(matching...) }
                else if !closing, !token.hasSuffix("/") { hidden.append(name) }
            } else if hidden.isEmpty, breaks.contains(name) { output.append("\n") }
            index = source.index(after: end)
        }
        let decoded = decodeEntities(output).replacingOccurrences(of: "\r", with: "")
        let lines = decoded.components(separatedBy: "\n").map { line in
            line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{00a0}" }).joined(separator: " ")
        }
        var compact: [String] = []
        for line in lines {
            if !line.isEmpty || compact.last?.isEmpty == false { compact.append(line) }
        }
        return bounded(compact.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), utf8Limit: outputLimit)
    }

    public static func decodeEntities(_ input: String) -> String {
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—", "hellip": "…", "copy": "©", "reg": "®", "bull": "•", "aacute": "á", "eacute": "é", "iacute": "í", "oacute": "ó", "uacute": "ú",
                     "Aacute": "Á", "Eacute": "É", "Iacute": "Í", "Oacute": "Ó", "Uacute": "Ú", "ntilde": "ñ", "Ntilde": "Ñ",
                     "agrave": "à", "egrave": "è", "igrave": "ì", "ograve": "ò", "ugrave": "ù", "ccedil": "ç", "Ccedil": "Ç",
                     "auml": "ä", "euml": "ë", "iuml": "ï", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß"]
        var result = "", index = input.startIndex
        while index < input.endIndex {
            guard input[index] == "&" else { result.append(input[index]); index = input.index(after: index); continue }
            var end = input.index(after: index), count = 0
            while end < input.endIndex, input[end] != ";", count < 14 {
                if input[end].isWhitespace || input[end] == "&" { break }
                end = input.index(after: end); count += 1
            }
            guard end < input.endIndex, input[end] == ";" else {
                result.append("&"); index = input.index(after: index); continue
            }
            let token = String(input[input.index(after: index)..<end])
            let replacement: String?
            if token.hasPrefix("#") {
                let hex = token.lowercased().hasPrefix("#x")
                let digits = String(token.dropFirst(hex ? 2 : 1))
                let validDigits = !digits.isEmpty && digits.utf8.allSatisfy { byte in
                    (48...57).contains(byte) || (hex && ((65...70).contains(byte) || (97...102).contains(byte)))
                }
                if !validDigits { replacement = nil }
                else if let number = UInt32(digits, radix: hex ? 16 : 10), let scalar = UnicodeScalar(number), number != 0,
                        !(0xD800...0xDFFF).contains(number) { replacement = String(scalar) } else { replacement = "" }
            } else { replacement = named[token] }
            if let replacement { result += replacement; index = input.index(after: end) }
            else { result.append("&"); index = input.index(after: index) }
        }
        return result
    }

    public static func decodeHeader(_ input: String) -> String {
        let joined = bounded(input, utf8Limit: 8_192).replacingOccurrences(of: #"(?<=\?=)\s+(?==\?)"#, with: "", options: .regularExpression)
        guard let regex = try? NSRegularExpression(pattern: #"=\?([^?\s]+)\?([bBqQ])\?([^?]*)\?="#) else { return bounded(input, utf8Limit: 1_024) }
        var result = joined
        for match in regex.matches(in: joined, range: NSRange(joined.startIndex..., in: joined)).reversed() {
            guard let charsetRange = Range(match.range(at: 1), in: joined), let kindRange = Range(match.range(at: 2), in: joined),
                  let valueRange = Range(match.range(at: 3), in: joined), let whole = Range(match.range, in: result) else { continue }
            let value = String(joined[valueRange]), charset = String(joined[charsetRange])
            var bytes: Data?
            if joined[kindRange].lowercased() == "b" { bytes = Data(base64Encoded: value) }
            else {
                let source = Array(value.replacingOccurrences(of: "_", with: " ").utf8)
                var data = Data(), index = 0
                while index < source.count {
                    if source[index] == 61, index + 2 < source.count,
                       let high = hex(source[index + 1]), let low = hex(source[index + 2]) {
                        data.append(high * 16 + low); index += 3
                    } else { data.append(source[index]); index += 1 }
                }
                bytes = data
            }
            if let bytes { result.replaceSubrange(whole, with: decode(bytes, charset: charset)) }
        }
        return bounded(result, utf8Limit: 1_024)
    }

    static func decode(_ data: Data, charset: String? = nil) -> String {
        let name = charset?.lowercased() ?? "utf-8"
        let encoding: String.Encoding = ["iso-8859-1", "latin1", "latin-1"].contains(name) ? .isoLatin1 :
            (["windows-1252", "cp1252"].contains(name) ? .windowsCP1252 : .utf8)
        return String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
    }

    private static func hex(_ byte: UInt8) -> UInt8? {
        switch byte { case 48...57: byte - 48; case 65...70: byte - 55; case 97...102: byte - 87; default: nil }
    }
}
