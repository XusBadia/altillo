import AltilloCore
import SwiftUI

// SwiftUI Previews of edit mode (PLAN §4, "mock primero"): narrowest and widest notch, over a hardware notch and as
// the island, plus a configuration with most sections put away. Their settings live in a private suite, so nothing
// here touches the user's.

extension NotchModel {
    /// A model open in edit mode, `width` wide, with a thing on the shelf so the shelf ear has something to say.
    static func editingPreview(width: Double, hasNotch: Bool = true, preset: NotchPreset? = nil) -> NotchModel {
        let settings = AltilloSettings(defaults: UserDefaults(suiteName: "me.badia.altillo.previews.edit") ?? .standard)
        settings.openWidth = width
        if let preset { settings.apply(preset) }
        let model = NotchModel(settings: settings)
        model.hasNotch = hasNotch
        model.notchSize = hasNotch ? CGSize(width: 185, height: 32) : CGSize(width: 196, height: 24)
        model.shelf = Array(model.demo.shelfItems.prefix(2))
        model.state = .open
        model.isEditing = true
        return model
    }
}

#Preview("Edit · 440 · notch") { NotchPreviewStage(model: .editingPreview(width: 440)) }
#Preview("Edit · 760 · notch") { NotchPreviewStage(model: .editingPreview(width: 760)) }
#Preview("Edit · 440 · island") { NotchPreviewStage(model: .editingPreview(width: 440, hasNotch: false)) }
#Preview("Edit · 760 · island") { NotchPreviewStage(model: .editingPreview(width: 760, hasNotch: false)) }
#Preview("Edit · minimal") { NotchPreviewStage(model: .editingPreview(width: 560, preset: .minimal)) }

#Preview("Ears · every kind") {
    let model = NotchModel.editingPreview(width: 560)
    return HStack(spacing: 18) {
        ForEach(EarContent.allCases) { content in
            DesvanEarContent(content: content, model: model, style: .preview)
                .frame(width: NotchChrome.earWidth, height: 24)
                .background(.black)
        }
        DesvanNextEventEar(label: .countdown(minutes: 12), title: "Standup")
        DesvanNextEventEar(label: .at(.now.addingTimeInterval(7200)), title: "Review")
        DesvanEqualiser(isPlaying: true)
    }
    .padding(20)
    .background(.black)
}
