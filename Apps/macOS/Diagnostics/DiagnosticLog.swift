import Foundation
import Observation
import os

/// Local diagnostics with a single redaction boundary before data reaches memory or Unified Logging.
///
/// Messages are deliberately operational rather than user-specific. Callers should prefer counts and outcomes;
/// `redact(_:)` is the final defence against paths, filenames, active-app names and pasteboard types accidentally
/// supplied by an error or a future call site.
@MainActor
@Observable
final class DiagnosticLog {
    static let shared = DiagnosticLog()

    enum Category {
        static let dragStart = "drag-start"
        static let dragEnd = "drag-end"
        static let drop = "drop"
        static let ingest = "ingest"
        static let promise = "promise"
        static let dragOut = "drag-out"
        static let quickLook = "quicklook"
        static let shelf = "shelf"
        static let app = "app"
        static let alerts = "alerts"
        static let assistant = "assistant"
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let category: String
        let message: String
    }

    static let capacity = 2_000

    private(set) var entries: [Entry] = []

    @ObservationIgnored private let logger = Logger(subsystem: "altillo", category: "diagnostics")

    func record(_ category: String, _ message: String) {
        let safeMessage = Self.redact(message)
        logger.log("[\(category, privacy: .public)] \(safeMessage, privacy: .public)")
        #if DEBUG
        entries.append(Entry(category: category, message: safeMessage))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
        #endif
    }

    func clear() {
        entries.removeAll()
    }

    nonisolated static func post(_ category: String, _ message: String) {
        Task { @MainActor in shared.record(category, message) }
    }

    /// A plain-text export of entries that have already crossed the redaction boundary.
    static func export(_ entries: [Entry]) -> String {
        entries.map { "\(timestamp($0.date)) [\($0.category)] \($0.message)" }.joined(separator: "\n")
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)
            .secondFraction(.fractional(3)))
    }

    nonisolated static func redact(_ message: String) -> String {
        var result = message
        let rules: [(pattern: String, replacement: String)] = [
            (#"(?i)\b(active app|app)\s*:\s*[^·\n]+"#, "$1: <redacted>"),
            (#"(?i)\btypes\s*:\s*[^·\n]+"#, "types: <redacted>"),
            (#"(?i)file://[^\s·\n]+"#, "<path>"),
            (#"(?<![\p{L}\p{N}])/(?:[^·\n]+)"#, "<path>"),
            (#"(?<![\p{L}\p{N}])~/(?:[^·\n]+)"#, "<path>"),
            (#"(?i)(?<![\p{L}\p{N}])(?:[\p{L}\p{N}_-]+[ ]){0,4}[\p{L}\p{N}_-]+\.[a-z][a-z0-9]{0,15}(?![\p{L}\p{N}])"#, "<file>"),
        ]
        for rule in rules {
            result = result.replacingOccurrences(
                of: rule.pattern,
                with: rule.replacement,
                options: .regularExpression
            )
        }
        return result
    }
}
