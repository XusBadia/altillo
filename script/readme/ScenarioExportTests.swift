import AltilloCore
import AppKit
import SwiftUI
import XCTest
@testable import Altillo

/// Re-render current README scenarios at 2x with isolated demo settings.
/// Kept outside the normal test target; render-readme-assets.py injects it into a temporary checkout.
@MainActor
final class ScenarioExportTests: XCTestCase {
    func testExportScenarios() throws {
        let dir = "__README_EXPORT_DIRECTORY__"
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let size = NotchLayout.panelSize
        let scale: CGFloat = 2
        let renderSize = CGSize(width: size.width * scale, height: size.height * scale)
        let suite = "Altillo.ReadmeRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AltilloSettings(defaults: defaults)
        settings.openWidth = 700
        settings.modules = NotchModule.allCases
        settings.calendarStyle = .monthAndAgenda
        let scenarios: [DesignScenario] = [.openShelf, .openAssistant, .openUsage, .openAgents, .openCalendar, .openDrawer, .idleWithEars, .idleWithAgentWaiting]
        for scenario in scenarios {
            let model = NotchModel(settings: settings)
            model.hasNotch = true
            model.notchSize = CGSize(width: 185, height: 32)
            model.scenario = scenario
            model.module = scenario.module
            model.shelf = scenario.showsDemoShelf ? model.demo.shelfItems : []
            model.state = scenario.state
            let host = NSHostingView(rootView: NotchRootView(model: model).frame(width: size.width, height: size.height, alignment: .top).scaleEffect(scale, anchor: .topLeading).frame(width: renderSize.width, height: renderSize.height, alignment: .topLeading))
            host.frame = NSRect(origin: .zero, size: renderSize)
            let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: renderSize.width, height: renderSize.height),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(1.2))
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            rep.size = renderSize
            host.cacheDisplay(in: host.bounds, to: rep)
            let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try data.write(to: out.appendingPathComponent("\(scenario.rawValue).png"))
            window.orderOut(nil)
        }
    }
}
