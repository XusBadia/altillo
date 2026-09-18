import AltilloCore
import AltilloDesign
import AppKit
import SwiftUI

/// Prototype of the "Matriz" direction (docs/design/direcciones.md § Dirección A).
///
/// Same contract as `NotchRootView`: a pure black silhouette drawn top-centred in the fixed 760×320 panel, morphing
/// between faces, with its drawn size reported to `model.visibleShapeSize` for hit-testing and hover.
/// Inside, the black is a switched-off LED display that Altillo lights up dot by dot.
struct MatrizRootView: View {
    let model: NotchModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: NotchModel) {
        self.model = model
        _ = Matriz.Fonts.registered
    }

    var body: some View {
        let chrome = MatrizChrome.make(for: model)
        let shape = NotchShape(topCornerRadius: chrome.topRadius, bottomCornerRadius: chrome.bottomRadius)
        let closing = chrome.face == .rest || chrome.face == .ears

        ZStack(alignment: .top) {
            shape
                .fill(Matriz.Palette.notch)
                .shadow(color: .black.opacity(chrome.showsShadow ? 0.6 : 0), radius: 16, y: 8)
                .shadow(color: .black.opacity(chrome.showsShadow ? 0.3 : 0), radius: 2, y: 1)

            ZStack(alignment: .top) {
                MatrizFace(model: model, chrome: chrome)
                    .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
                    .id(chrome.face)
                    .transition(.scanline(reduceMotion: reduceMotion))
            }
            .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(width: chrome.size.width, height: chrome.size.height)
        .contentShape(shape)
        .onGeometryChange(for: CGSize.self, of: \.size) { model.visibleShapeSize = $0 }
        // Matriz's own springs: open with a hair of overshoot, close without any. Reduce Motion: a 150 ms fade.
        .transaction(value: chrome.face) { transaction in
            guard transaction.animation != nil else { return }
            transaction.animation = closing ? Matriz.Motion.close(reduceMotion) : Matriz.Motion.open(reduceMotion)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .tint(Matriz.Palette.signal)
        .onChange(of: model.dropZone) { _, zone in
            // Trackpad haptic when a drag enters a drop field.
            if zone != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        }
        .onChange(of: model.shelf.count) { old, new in
            if new > old, model.state == .dropTarget || model.state == .open {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
        .task(id: model.scenario) { applyScenarioDemoState() }
    }

    /// A pre-selected tile so the review screenshot shows the viewfinder selection.
    private func applyScenarioDemoState() {
        guard model.scenario == .openShelf, model.selection.isEmpty, model.shelf.count > 1 else { return }
        model.selection = [model.shelf[1].id]
    }
}

/// Sizes of the silhouette: the current design's `NotchChrome`, with a wider sign for peeks (the telegraphic line
/// needs the room) and a slightly taller open notch.
enum MatrizChrome {
    static let peekWidth: CGFloat = 440

    @MainActor
    static func make(for model: NotchModel) -> NotchChrome {
        var chrome = NotchChrome(model: model)
        switch chrome.face {
        case let .peek(kind) where kind != .hint:
            chrome.size.width = max(chrome.size.width, peekWidth + 2 * chrome.topRadius)
        case .expanded:
            chrome.size.height += 6
            chrome.bottomRadius = 22
        case .dragArmed:
            if chrome.hasNotch { chrome.size.width += 24 }
        default:
            break
        }
        return chrome
    }

    /// Prototype-only launch flag: `-prototypeHoverZone shelf|airDrop` lights a drop field without a real drag, to
    /// review (and screenshot) the lit look. Only honoured while a design scenario is frozen.
    static let forcedZone: DropZone? = switch UserDefaults.standard.string(forKey: "prototypeHoverZone") {
    case "shelf": .shelf
    case "airDrop", "airdrop": .airDrop
    default: nil
    }

    @MainActor
    static func litZone(_ model: NotchModel) -> DropZone? {
        model.dropZone ?? (model.scenario != nil ? forcedZone : nil)
    }
}

/// Picks the content for a face.
private struct MatrizFace: View {
    let model: NotchModel
    let chrome: NotchChrome

    var body: some View {
        switch chrome.face {
        case .rest:
            Color.clear
        case .ears:
            MatrizEars(model: model, chrome: chrome)
        case .peek(.hint):
            MatrizHint(chrome: chrome)
        case let .peek(kind):
            MatrizPeek(model: model, chrome: chrome, kind: kind)
        case .dragArmed:
            MatrizDragArmed(chrome: chrome)
        case .expanded:
            MatrizExpanded(model: model, chrome: chrome)
        }
    }
}
