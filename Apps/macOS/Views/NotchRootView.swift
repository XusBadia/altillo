import AltilloCore
import AltilloDesign
import SwiftUI

/// Root SwiftUI view hosted in the notch panel (a fixed 760×320 transparent window glued to the top of the screen).
///
/// Draws the black silhouette top-centred and morphs it between faces; every face lays out at its own final size and
/// is clipped by the shape, so content is never squeezed mid-animation. Reports the drawn size to the model, which the
/// coordinator uses for hit-testing and hover tracking.
struct NotchRootView: View {
    let model: NotchModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let chrome = NotchChrome(model: model)
        let shape = NotchShape(topCornerRadius: chrome.topRadius, bottomCornerRadius: chrome.bottomRadius)

        ZStack(alignment: .top) {
            // Shadow lives on its own layer so the clipped content can't cut it.
            shape
                .fill(Tokens.Palette.notch)
                .shadow(color: .black.opacity(chrome.showsShadow ? 0.55 : 0), radius: 18, y: 10)
                .shadow(color: .black.opacity(chrome.showsShadow ? 0.25 : 0), radius: 3, y: 1)

            // Each face keeps its own final-size frame, so an outgoing face is clipped by the morphing shape instead of
            // being re-laid out into it.
            ZStack(alignment: .top) {
                NotchFaceView(model: model, chrome: chrome)
                    .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
                    .id(chrome.face)
                    .transition(.contentSwap(shift: max(4, chrome.size.height * 0.02), reduceMotion: reduceMotion))
            }
            .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(width: chrome.size.width, height: chrome.size.height)
        .contentShape(shape)
        .onGeometryChange(for: CGSize.self, of: \.size) { model.visibleShapeSize = $0 }
        .transaction { transaction in
            // With Reduce Motion the shape still changes size, but as a quick ease instead of a spring.
            if reduceMotion, transaction.animation != nil { transaction.animation = Tokens.Motion.reducedFade }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .tint(Tokens.Palette.amber)
        .task(id: model.scenario) { applyScenarioDemoState() }
    }

    /// A pre-selected tile so the review screenshot shows the selection style.
    private func applyScenarioDemoState() {
        guard model.scenario == .openShelf, model.selection.isEmpty, model.shelf.count > 1 else { return }
        model.selection = [model.shelf[1].id]
    }
}

/// Picks the content for a face.
private struct NotchFaceView: View {
    let model: NotchModel
    let chrome: NotchChrome

    var body: some View {
        switch chrome.face {
        case .rest:
            Color.clear
        case .ears:
            EarsFace(model: model, chrome: chrome)
        case let .peek(kind):
            PeekFace(model: model, chrome: chrome, kind: kind)
        case .dragArmed:
            DragArmedFace(chrome: chrome)
        case .expanded:
            ExpandedFace(model: model, chrome: chrome)
        }
    }
}
