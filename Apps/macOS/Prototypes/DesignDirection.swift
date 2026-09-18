import SwiftUI

/// Visual directions being prototyped (docs/design/direcciones.md). `-designDirection matriz|desvan|fluido`
/// renders the notch with that prototype instead of the current design; combine with `-designScenario` and
/// `-simulateNotch YES` to review each state.
enum DesignDirection: String, CaseIterable {
    case matriz, desvan, fluido

    static let current = UserDefaults.standard.string(forKey: "designDirection").flatMap(DesignDirection.init)

    @MainActor @ViewBuilder
    func rootView(model: NotchModel) -> some View {
        switch self {
        case .matriz: MatrizRootView(model: model)
        case .desvan: DesvanRootView(model: model)
        case .fluido: FluidoRootView(model: model)
        }
    }
}
