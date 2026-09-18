import SwiftUI

/// Prototype of the "Matriz" direction (docs/design/direcciones.md). STUB: replaced by the prototype work. Keep this API.
struct MatrizRootView: View {
    let model: NotchModel

    var body: some View {
        NotchRootView(model: model, ignoresDirection: true)
    }
}
