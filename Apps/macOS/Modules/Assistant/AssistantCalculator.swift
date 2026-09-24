import Foundation

/// Exact arithmetic for the assistant. The on-device model is good with words and poor with digits (it said 17 % of
/// 2 340 was 0.3978), and as a tool it called the calculator for haikus. So the question itself is read: a sum or a
/// percentage in it is worked out here and the exact result rides along with the prompt. Local and instant.
///
/// The parser is a small recursive descent: numbers, + - * / ^, a postfix %, unary minus, parentheses and
/// `sqrt(…)`. "×", "÷" and "−" are understood; so is a decimal comma when there's no dot ("2,5 * 4").
enum AssistantCalculator {
    /// "21% of 1.250 €" → "21% of 1250 = 262.5"; "(1250 + 80) / 3" → "(1250+80)/3 = 443.3333333". Nil when the
    /// question holds no arithmetic worth doing.
    static func hint(for question: String) -> String? {
        let text = normalisedNumbers(in: question)
        // "N% of M", in the languages the model is asked in most.
        let percentOf = #"(\d+(?:\.\d+)?)\s*%\s*(?:of|de|del|d'|du|des|von|di|do|da)\s+(?:the\s+|la\s+|el\s+)?(-?\d+(?:\.\d+)?)"#
        if let regex = try? Regex(percentOf), let match = text.firstMatch(of: regex),
           let percent = Double(String(match.output[1].substring ?? "")),
           let base = Double(String(match.output[2].substring ?? "")) {
            return "\(format(percent))% of \(format(base)) = \(format(percent / 100 * base))"
        }
        // The longest run of digits, operators and parentheses with at least one operator between two numbers.
        guard let arithmetic = try? Regex(#"[\d(√][\d\s.+\-*/×÷^%()√]*[\d)%]"#) else { return nil }
        let spans = text.matches(of: arithmetic)
            .map { String(text[$0.range]).trimmingCharacters(in: .whitespaces) }
            .filter(isSum)
            .sorted { $0.count > $1.count }
        for span in spans {
            let expression = span.replacingOccurrences(of: "√", with: "sqrt")
            if let value = evaluate(expression) {
                return "\(span.filter { !$0.isWhitespace }) = \(format(value))"
            }
        }
        return nil
    }

    /// At least one operator between two numbers, and not a date: "2026-09-24", "24/09/2026" and "24-09" aren't
    /// sums ("10-3" still is one).
    static func isSum(_ span: String) -> Bool {
        if span.wholeMatch(of: /\d{1,4}[-\/]\d{1,2}[-\/]\d{1,4}/) != nil { return false }
        if span.wholeMatch(of: /\d{1,2}[-\/]0\d/) != nil { return false }
        let hasOperator = span.contains { "+-*/×÷^".contains($0) }
        let numbers = span.split { !$0.isNumber && $0 != "." }
        return hasOperator && numbers.count >= 2
    }

    /// Numbers written the way people write them, as plain decimals: "1.250" and "1,250" (thousands) → "1250",
    /// "2,5" → "2.5", "1.250,75" → "1250.75". "3 x 4" becomes "3*4".
    static func normalisedNumbers(in text: String) -> String {
        var result = text
        let rules: [(String, (Substring) -> String)] = [
            (#"\d{1,3}(?:\.\d{3})+,\d+"#, { $0.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }),
            (#"\d{1,3}(?:,\d{3})+\.\d+"#, { $0.replacingOccurrences(of: ",", with: "") }),
            (#"\d{1,3}(?:\.\d{3})+(?![\d.,])"#, { $0.replacingOccurrences(of: ".", with: "") }),
            (#"\d{1,3}(?:,\d{3})+(?![\d.,])"#, { $0.replacingOccurrences(of: ",", with: "") }),
            (#"\d+,\d+"#, { $0.replacingOccurrences(of: ",", with: ".") }),
        ]
        for (pattern, rewrite) in rules {
            guard let regex = try? Regex(pattern) else { continue }
            let source = result
            result = source.replacing(regex) { rewrite(source[$0.range]) }
        }
        if let times = try? Regex(#"(\d)\s*[xX]\s*(\d)"#) {
            let source = result
            result = source.replacing(times) { match in
                let text = String(source[match.range])
                return text.replacingOccurrences(of: "x", with: "*").replacingOccurrences(of: "X", with: "*")
            }
        }
        return result
    }

    static func evaluate(_ expression: String) -> Double? {
        var text = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "**", with: "^")
        // Keep only the expression if the model sent "x = …" or a trailing "=".
        if let equals = text.lastIndex(of: "="), text[text.index(after: equals)...].trimmingCharacters(in: .whitespaces).isEmpty {
            text = String(text[..<equals])
        } else if let equals = text.firstIndex(of: "=") {
            text = String(text[text.index(after: equals)...])
        }
        // "1,250.50" → thousands; "2,5" → decimal comma.
        text = text.contains(".") ? text.replacingOccurrences(of: ",", with: "") : text.replacingOccurrences(of: ",", with: ".")
        var parser = Parser(Array(text.filter { !$0.isWhitespace }))
        guard let value = parser.expression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    /// Up to ten significant digits, no scientific notation for everyday sizes, no trailing zeros.
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = abs(value) >= 1e15 || abs(value) < 1e-6 ? .scientific : .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumSignificantDigits = 10
        formatter.usesSignificantDigits = true
        return formatter.string(from: value as NSNumber) ?? String(value)
    }

    private struct Parser {
        let characters: [Character]
        var position = 0

        init(_ characters: [Character]) { self.characters = characters }

        var isAtEnd: Bool { position == characters.count }

        private var current: Character? { position < characters.count ? characters[position] : nil }

        private mutating func take(_ character: Character) -> Bool {
            guard current == character else { return false }
            position += 1
            return true
        }

        /// sum := product (("+" | "-") product)*
        mutating func expression() -> Double? {
            guard var value = product()?.value else { return nil }
            while true {
                if take("+") {
                    guard let next = product() else { return nil }
                    // "200 + 10%" means 200 + 10 % of 200, as on a calculator.
                    value += next.isPercent ? value * next.value : next.value
                } else if take("-") {
                    guard let next = product() else { return nil }
                    value -= next.isPercent ? value * next.value : next.value
                } else {
                    return value
                }
            }
        }

        /// A product remembers whether it was a bare percentage, for "+ 10%".
        private mutating func product() -> (value: Double, isPercent: Bool)? {
            guard var term = power() else { return nil }
            var isPercent = term.isPercent
            var value = term.value
            while true {
                if take("*") {
                    guard let next = power() else { return nil }
                    value *= next.value
                    isPercent = false
                } else if take("/") {
                    guard let next = power(), next.value != 0 else { return nil }
                    value /= next.value
                    isPercent = false
                } else {
                    term = (value, isPercent)
                    return term
                }
            }
        }

        private mutating func power() -> (value: Double, isPercent: Bool)? {
            guard let base = unary() else { return nil }
            if take("^") {
                guard let exponent = power() else { return nil }
                return (pow(base.value, exponent.value), false)
            }
            return base
        }

        private mutating func unary() -> (value: Double, isPercent: Bool)? {
            if take("-") { return unary().map { (-$0.value, $0.isPercent) } }
            if take("+") { return unary() }
            return postfix()
        }

        private mutating func postfix() -> (value: Double, isPercent: Bool)? {
            guard let value = primary() else { return nil }
            if take("%") { return (value / 100, true) }
            return (value, false)
        }

        private mutating func primary() -> Double? {
            if take("(") {
                guard let value = expression(), take(")") else { return nil }
                return value
            }
            if characters[position...].starts(with: Array("sqrt")) {
                position += 4
                guard take("("), let value = expression(), take(")"), value >= 0 else { return nil }
                return value.squareRoot()
            }
            let start = position
            while let character = current, character.isNumber || character == "." {
                position += 1
            }
            guard position > start else { return nil }
            return Double(String(characters[start..<position]))
        }
    }
}
