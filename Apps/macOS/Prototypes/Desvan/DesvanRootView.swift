import SwiftUI

/// Prototype of the "Desvan" direction (docs/design/direcciones.md). STUB: replaced by the prototype work. Keep this API.
struct DesvanRootView: View {
    let model: NotchModel

    var body: some View {
        NotchRootView(model: model, ignoresDirection: true)
    }
}
