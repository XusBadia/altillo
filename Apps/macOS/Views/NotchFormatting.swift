import AltilloCore
import Foundation
import UniformTypeIdentifiers

/// Compact formatting for the notch. Numbers are always rendered with `monospacedDigit()` by the views.
enum NotchFormat {
    /// "85%".
    static func percent(_ fraction: Double) -> String {
        String(localized: "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%")
    }

    /// Time until a date: "1 h 12 min", "3 d 4 h", "45 min", "less than 1 min".
    static func countdown(to date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return hours > 0 ? String(localized: "\(days) d \(hours) h") : String(localized: "\(days) d")
        }
        if hours > 0 {
            return minutes > 0 ? String(localized: "\(hours) h \(minutes) min") : String(localized: "\(hours) h")
        }
        if minutes > 0 { return String(localized: "\(minutes) min") }
        return String(localized: "less than 1 min")
    }

    /// Time since a date: "just now", "8 s ago", "4 min ago", "2 h ago", "3 d ago".
    static func ago(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<3: return String(localized: "just now")
        case ..<60: return String(localized: "\(seconds) s ago")
        case ..<3_600: return String(localized: "\(seconds / 60) min ago")
        case ..<86_400: return String(localized: "\(seconds / 3_600) h ago")
        default: return String(localized: "\(seconds / 86_400) d ago")
        }
    }

    /// "1 thing" / "6 things".
    static func things(_ count: Int) -> String {
        String(localized: "\(count) things")
    }

    /// Short description under a shelf tile: "PNG · 412 KB", "Link", "Text".
    static func subtitle(for item: ShelfItem) -> String {
        switch item.kind {
        case .text: return String(localized: "Text")
        case let .link(url):
            return url.host(percentEncoded: false).map { String(localized: "Link · \($0)") }
                ?? String(localized: "Link")
        case let .file(url, _):
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentTypeKey])
            if values?.isDirectory == true { return String(localized: "Folder") }
            let kind = url.pathExtension.isEmpty
                ? (values?.contentType?.localizedDescription ?? String(localized: "File"))
                : url.pathExtension.uppercased()
            guard let size = values?.fileSize else { return kind }
            let bytes = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            return String(localized: "\(kind) · \(bytes)")
        }
    }
}
