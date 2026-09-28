import AppKit
import SwiftUI
import XCTest
@testable import Altillo

/// Exporta para el anuncio el panel con un arrastre sobre la caja y la caja sola en varias aperturas (3×).
@MainActor
final class DropExportTests: XCTestCase {
    private func snapshot<V: View>(_ view: V, size: CGSize, to url: URL) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .top))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 3), pixelsHigh: Int(size.height * 3),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }

    func testExportDropHoverAndBox() throws {
        guard let dir = ProcessInfo.processInfo.environment["ALTILLO_EXPORT_DIR"] else { throw XCTSkip("sin ALTILLO_EXPORT_DIR") }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // Antes de que nadie lea DesvanDebug.forcedZone: el puntero está sobre la caja.
        UserDefaults.standard.set("shelf", forKey: "prototypeHoverZone")
        let model = NotchModel.preview(.dropTarget, hasNotch: true)
        try snapshot(NotchRootView(model: model), size: NotchLayout.panelSize, to: out.appendingPathComponent("dropTargetHover.png"))
        // La caja sola, de cerrada a abierta con el rebote del muelle (hasta 1,12).
        let size = DesvanCardboardBox.canvasSize
        for step in 0...28 {
            let openness = Double(step) * 0.04
            let box = DesvanCardboardBox(openness: openness, warmth: min(openness, 1), scale: 1)
            try snapshot(box, size: size, to: out.appendingPathComponent(String(format: "box-%02d.png", step)))
        }
        UserDefaults.standard.removeObject(forKey: "prototypeHoverZone")
    }
}
