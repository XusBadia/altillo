import AltilloCore
import SwiftUI

/// Root SwiftUI view hosted in the notch panel. STUB: replaced by the visual design work. Keep this API.
struct NotchRootView: View {
    let model: NotchModel

    var body: some View {
        VStack {
            Rectangle()
                .fill(.black)
                .frame(width: model.notchSize.width, height: model.notchSize.height)
                .onGeometryChange(for: CGSize.self, of: \.size) { model.visibleShapeSize = $0 }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
