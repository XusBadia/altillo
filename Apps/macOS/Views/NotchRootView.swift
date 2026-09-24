import SwiftUI

/// Root SwiftUI view hosted in the notch panel (a fixed transparent window, `NotchLayout.panelSize` glued to the top of the screen).
/// Altillo's look is «Desván» (PLAN.md §3): the attic at home, lit by a warm bulb.
struct NotchRootView: View {
    let model: NotchModel

    var body: some View {
        DesvanRootView(model: model)
    }
}
