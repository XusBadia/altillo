import AppKit
import SwiftUI
import XCTest
@testable import Altillo

/// Exporta cada escenario de diseño a PNG a 3× para el anuncio (promo/). Solo corre con ALTILLO_EXPORT_DIR.
/// Usa un NSHostingView real en una ventana fuera de pantalla para que las vistas de AppKit también se pinten.
@MainActor
final class ScenarioExportTests: XCTestCase {
    func testExportScenarios() throws {
        guard let dir = ProcessInfo.processInfo.environment["ALTILLO_EXPORT_DIR"] else { throw XCTSkip("sin ALTILLO_EXPORT_DIR") }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let size = NotchLayout.panelSize
        for scenario in DesignScenario.allCases {
            let model = NotchModel.preview(scenario, hasNotch: true)
            if scenario == .peekAlert { model.alert = .demoMeeting }
            let host = NSHostingView(rootView: NotchRootView(model: model).frame(width: size.width, height: size.height, alignment: .top))
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
            let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try data.write(to: out.appendingPathComponent("\(scenario.rawValue).png"))
            window.orderOut(nil)
        }
    }
}
