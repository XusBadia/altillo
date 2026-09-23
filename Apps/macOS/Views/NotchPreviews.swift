import AltilloCore
import AltilloDesign
import SwiftUI

// SwiftUI Previews for every design-review scenario, on a Tahoe-like wallpaper with a menu bar,
// both over a hardware notch (MacBook Pro 14") and as a virtual island (external display).

extension NotchModel {
    /// A model frozen in `scenario`, mirroring `NotchCoordinator.show(_:)`.
    static func preview(_ scenario: DesignScenario, hasNotch: Bool = true) -> NotchModel {
        let model = NotchModel()
        model.hasNotch = hasNotch
        model.notchSize = hasNotch ? CGSize(width: 185, height: 32) : CGSize(width: 196, height: 24)
        model.scenario = scenario
        model.module = scenario.module
        model.shelf = scenario.showsDemoShelf ? model.demo.shelfItems : []
        model.isReceivingDrop = scenario == .openShelfLoading
        model.shelfProblem = scenario == .openShelfError
            ? String(localized: "I couldn't put away what you dropped. You can try again.")
            : nil
        model.state = scenario.state
        return model
    }
}

/// 760×320 slice of the top of a screen, the size of the notch panel.
struct NotchPreviewStage: View {
    let model: NotchModel

    var body: some View {
        ZStack(alignment: .top) {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.55, 0.45], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    Color(hex: 0x6E8FC9), Color(hex: 0x9DB4E0), Color(hex: 0xE3B7A0),
                    Color(hex: 0x40609E), Color(hex: 0x7F8FC4), Color(hex: 0xD99A82),
                    Color(hex: 0x23315C), Color(hex: 0x3F4E86), Color(hex: 0x9A6A7E),
                ]
            )
            PreviewMenuBar(height: model.notchSize.height)
            NotchRootView(model: model)
        }
        .frame(width: 760, height: 320)
    }
}

private struct PreviewMenuBar: View {
    let height: CGFloat

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo")
            Text("Finder").fontWeight(.bold)
            Text("File")
            Text("Edit")
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("Fri 18 Sep 10:24")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: height)
        .background(.black.opacity(0.08))
    }
}

#Preview("Idle") { NotchPreviewStage(model: .preview(.idle)) }
#Preview("Idle · island") { NotchPreviewStage(model: .preview(.idle, hasNotch: false)) }
#Preview("Idle with ears") { NotchPreviewStage(model: .preview(.idleWithEars)) }
#Preview("Idle with ears · island") { NotchPreviewStage(model: .preview(.idleWithEars, hasNotch: false)) }
#Preview("Peek: shelf") { NotchPreviewStage(model: .preview(.peekShelf)) }
#Preview("Peek: usage alert") { NotchPreviewStage(model: .preview(.peekUsageAlert)) }
#Preview("Peek: agent waiting") { NotchPreviewStage(model: .preview(.peekAgentWaiting)) }
#Preview("Drag armed") { NotchPreviewStage(model: .preview(.dragArmed)) }
#Preview("Drop target") { NotchPreviewStage(model: .preview(.dropTarget)) }
#Preview("Drop target · hovered") {
    let model = NotchModel.preview(.dropTarget)
    model.dropZone = .shelf
    return NotchPreviewStage(model: model)
}
#Preview("Open: empty shelf") { NotchPreviewStage(model: .preview(.openShelfEmpty)) }
#Preview("Open: receiving") { NotchPreviewStage(model: .preview(.openShelfLoading)) }
#Preview("Open: error") { NotchPreviewStage(model: .preview(.openShelfError)) }
#Preview("Open: shelf with files") { NotchPreviewStage(model: .preview(.openShelf)) }
#Preview("Open: AI usage") { NotchPreviewStage(model: .preview(.openUsage)) }
#Preview("Open: agents") { NotchPreviewStage(model: .preview(.openAgents)) }
#Preview("Open: Drawer") { NotchPreviewStage(model: .preview(.openDrawer)) }
#Preview("Open: Drawer · island") { NotchPreviewStage(model: .preview(.openDrawer, hasNotch: false)) }
#Preview("Open: agents · island") { NotchPreviewStage(model: .preview(.openAgents, hasNotch: false)) }
