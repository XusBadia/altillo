import AppKit
import SwiftUI

/// Visual directions being prototyped (docs/design/direcciones.md). `-designDirection matriz|desvan|fluido`
/// renders the notch with that prototype instead of the current design; combine with `-designScenario` and
/// `-simulateNotch YES` to review each state.
enum DesignDirection: String, CaseIterable {
    case matriz, desvan, fluido

    static let current = UserDefaults.standard.string(forKey: "designDirection").flatMap(DesignDirection.init)

    var title: String {
        switch self {
        case .matriz: "A · Matriz"
        case .desvan: "B · Desván"
        case .fluido: "C · Fluido"
        }
    }

    /// Remembers the choice and relaunches Altillo with it (the direction is read once at launch).
    @MainActor
    static func switchTo(_ direction: DesignDirection?) {
        UserDefaults.standard.set(direction?.rawValue, forKey: "designDirection")
        let relaunch = Process()
        relaunch.executableURL = URL(filePath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? relaunch.run()
        NSApp.terminate(nil)
    }

    @MainActor @ViewBuilder
    func rootView(model: NotchModel) -> some View {
        switch self {
        case .matriz: MatrizRootView(model: model)
        case .desvan: DesvanRootView(model: model)
        case .fluido: FluidoRootView(model: model)
        }
    }
}
