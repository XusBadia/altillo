import AltilloCore
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Real sample files for the design review, generated once in `$TMPDIR/AltilloDemo` with deterministic names and ids,
/// so Quick Look renders genuine thumbnails and drags carry real files.
enum DemoFiles {
    static let items: [ShelfItem] = make()

    static var folder: URL {
        FileManager.default.temporaryDirectory.appending(path: "AltilloDemo", directoryHint: .isDirectory)
    }

    private static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "A1711110-0000-4000-8000-%012d", n)) ?? UUID()
    }

    private static func make() -> [ShelfItem] {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date.now
        var items: [ShelfItem] = []

        // `name` is the path component on disk (stable); `displayName` is what the shelf shows.
        func file(_ n: Int, _ name: String, displayName: String, minutesAgo: Double, write: (URL) -> Void) {
            let url = folder.appending(path: name)
            if !FileManager.default.fileExists(atPath: url.path) { write(url) }
            items.append(ShelfItem(
                id: id(n),
                kind: .file(url, isOwnedCopy: false),
                displayName: displayName,
                addedAt: now.addingTimeInterval(-minutesAgo * 60)
            ))
        }

        file(
            1, "Screenshot 2026-09-18 at 10.24.12.png",
            displayName: String(localized: "Screenshot 2026-09-18 at 10.24.12.png"),
            minutesAgo: 42, write: writeScreenshotPNG
        )
        file(
            2, "Altillo proposal v2.pdf",
            displayName: String(localized: "Altillo proposal v2.pdf"),
            minutesAgo: 30, write: writeProposalPDF
        )
        file(
            3, "meeting-notes.txt",
            displayName: String(localized: "meeting-notes.txt"),
            minutesAgo: 21, write: writeNotes
        )
        file(
            4, "altillo-assets.zip",
            displayName: String(localized: "altillo-assets.zip"),
            minutesAgo: 12, write: writeZip
        )
        items.append(ShelfItem(
            id: id(5),
            kind: .link(URL(string: "https://getseam.app")!),
            displayName: "getseam.app",
            addedAt: now.addingTimeInterval(-6 * 60)
        ))
        items.append(ShelfItem(
            id: id(6),
            kind: .text(String(localized: "Go through the drag matrix before Friday: Photos, Mail and Safari.")),
            displayName: String(localized: "Go through the drag matrix"),
            addedAt: now.addingTimeInterval(-2 * 60)
        ))
        return items
    }

    // MARK: - Writers

    /// A Tahoe-ish landscape: dusk gradient, a low sun and layered hills.
    private static func writeScreenshotPNG(to url: URL) {
        let width = 1280, height = 800
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        let w = CGFloat(width), h = CGFloat(height)

        let sky = CGGradient(colorsSpace: nil, colors: [
            cg(0x2B3A67), cg(0x7A5C99), cg(0xE59A7A), cg(0xF5C98B),
        ] as CFArray, locations: [0, 0.45, 0.8, 1])!
        context.drawLinearGradient(sky, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.25), options: [.drawsAfterEndLocation])

        let sun = CGGradient(colorsSpace: nil, colors: [cg(0xFFF1C9), cg(0xFFD28A, alpha: 0)] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(sun, startCenter: CGPoint(x: w * 0.62, y: h * 0.38), startRadius: 0,
                                   endCenter: CGPoint(x: w * 0.62, y: h * 0.38), endRadius: h * 0.35, options: [])
        context.setFillColor(cg(0xFFF4D6))
        context.fillEllipse(in: CGRect(x: w * 0.62 - 46, y: h * 0.38 - 46, width: 92, height: 92))

        let hills: [(UInt32, CGFloat, CGFloat)] = [(0x5B4A7A, 0.36, 0.0), (0x3D355E, 0.26, 1.7), (0x221E3A, 0.15, 3.1)]
        for (color, base, phase) in hills {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            for x in stride(from: 0, through: w, by: 8) {
                let y = h * base + sin(x / w * .pi * 2.4 + phase) * h * 0.05 + sin(x / w * .pi * 6.3 + phase * 2) * h * 0.015
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: w, y: 0))
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(cg(color))
            context.fillPath()
        }

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    /// A one-page proposal with a title, an amber rule and paragraph blocks.
    private static func writeProposalPDF(to url: URL) {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        context.beginPDFPage(nil)
        context.setFillColor(cg(0xFFFFFB))
        context.fill(box)

        context.setFillColor(cg(0x1C1917))
        context.fill(CGRect(x: 0, y: 842 - 210, width: 595, height: 210))
        draw("Altillo", size: 54, weight: 0.4, color: cg(0xFFFFFB), at: CGPoint(x: 56, y: 842 - 120), in: context)
        draw(
            String(localized: "Design proposal · v2"),
            size: 18, weight: 0, color: cg(0xF5A524), at: CGPoint(x: 58, y: 842 - 160), in: context
        )

        draw(
            String(localized: "A place up top to leave things"),
            size: 20, weight: 0.3, color: cg(0x1C1917), at: CGPoint(x: 56, y: 842 - 270), in: context
        )
        context.setFillColor(cg(0xF5A524))
        context.fill(CGRect(x: 56, y: 842 - 292, width: 64, height: 4))

        context.setFillColor(cg(0xD6D3D1))
        var y: CGFloat = 842 - 330
        for block in 0..<4 {
            for line in 0..<5 {
                let width: CGFloat = line == 4 ? 300 : 483 - CGFloat((line * 37 + block * 13) % 60)
                context.fill(CGRect(x: 56, y: y, width: width, height: 7))
                y -= 16
            }
            y -= 22
        }
        context.endPDFPage()
        context.closePDF()
    }

    private static func writeNotes(to url: URL) {
        let text = String(localized: """
        Notes · notch review (18-09)

        - Idle has to disappear on the hardware notch.
        - Ears only if there's something to show.
        - Peek: one line, never two.
        - Drop: show where it'll land before you drop it.
        - AI usage: pace as well as the percentage.
        - Agents: Allow / Deny without going to the terminal.
        """)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// An empty but valid zip archive (end-of-central-directory record only).
    private static func writeZip(to url: URL) {
        let bytes: [UInt8] = [0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 18)
        try? Data(bytes).write(to: url)
    }

    // MARK: - Helpers

    private static func cg(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    private static func draw(_ string: String, size: CGFloat, weight: CGFloat, color: CGColor, at point: CGPoint, in context: CGContext) {
        guard let font = CTFontCreateUIFontForLanguage(weight > 0.2 ? .emphasizedSystem : .system, size, nil) else { return }
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, string as CFString, attributes) else { return }
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
