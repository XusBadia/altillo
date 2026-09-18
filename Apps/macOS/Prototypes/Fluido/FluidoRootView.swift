import SwiftUI

/// Prototype of the "Fluido" direction (docs/design/direcciones.md). STUB: replaced by the prototype work. Keep this API.
struct FluidoRootView: View {
    let model: NotchModel

    var body: some View {
        NotchRootView(model: model, ignoresDirection: true)
    }
}
