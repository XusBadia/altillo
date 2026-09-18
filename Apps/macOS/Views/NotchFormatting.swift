import AltilloCore
import Foundation
import UniformTypeIdentifiers

/// Spanish, compact formatting for the notch. Numbers are always rendered with `monospacedDigit()` by the views.
enum NotchFormat {
    /// "85 %" with a non-breaking space, as Spanish typography asks.
    static func percent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))\u{00A0}%"
    }

    /// Time until a date: "1 h 12 min", "3 d 4 h", "45 min", "menos de 1 min".
    static func countdown(to date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return hours > 0 ? "\(days) d \(hours) h" : "\(days) d" }
        if hours > 0 { return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h" }
        if minutes > 0 { return "\(minutes) min" }
        return "menos de 1 min"
    }

    /// Time since a date: "ahora", "hace 8 s", "hace 4 min", "hace 2 h", "hace 3 d".
    static func ago(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<3: return "ahora"
        case ..<60: return "hace \(seconds) s"
        case ..<3_600: return "hace \(seconds / 60) min"
        case ..<86_400: return "hace \(seconds / 3_600) h"
        default: return "hace \(seconds / 86_400) d"
        }
    }

    /// "1 cosa" / "6 cosas".
    static func things(_ count: Int) -> String {
        count == 1 ? "1 cosa" : "\(count) cosas"
    }

    /// Short description under a shelf tile: "PNG · 412 KB", "Enlace", "Texto".
    static func subtitle(for item: ShelfItem) -> String {
        switch item.kind {
        case .text: return "Texto"
        case let .link(url): return url.host(percentEncoded: false).map { "Enlace · \($0)" } ?? "Enlace"
        case let .file(url, _):
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentTypeKey])
            if values?.isDirectory == true { return "Carpeta" }
            let kind = url.pathExtension.isEmpty
                ? (values?.contentType?.localizedDescription ?? "Archivo")
                : url.pathExtension.uppercased()
            guard let size = values?.fileSize else { return kind }
            return "\(kind) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
        }
    }
}
