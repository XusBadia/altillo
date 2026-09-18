import AltilloCore
import AltilloDesign
import AppKit
import SwiftUI

/// Prototype of the "Fluido" direction (docs/design/direcciones.md, direction C).
///
/// The notch is living black ink: the silhouette morphs with a heartbeat, bulges to swallow drops and leans towards
/// the pointer during a drag; the module that speaks lights the edge from inside ("la luz que se escapa del altillo").
/// The silhouette stays pure opaque black over the hardware notch; on the virtual island it becomes dark glass.
struct FluidoRootView: View {
    let model: NotchModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The pointer in window coordinates (same space as `.global`), tracked only during a drag.
    @State private var pointer: CGPoint?
    @State private var window = WindowBox()
    @State private var shapeFrame: CGRect = .zero
    /// The swallow: a belly that swells where something landed and springs back.
    @State private var swallowDepth: CGFloat = 0
    @State private var swallowX: CGFloat = 0.5
    @State private var shelfCount = 0

    var body: some View {
        let chrome = FluidoChrome(model: model)
        let magnet = magnetism(chrome)
        let depth = reduceMotion ? 0 : magnet.depth + swallowDepth
        let bulgeX = swallowDepth > 0.01 ? swallowX : magnet.x
        let shape = FluidoNotchShape(
            topRadius: chrome.topRadius,
            bottomRadius: chrome.bottomRadius,
            bulgeX: bulgeX,
            bulgeDepth: depth,
            bulgeWidth: chrome.face == .expanded ? 190 : min(chrome.size.width * 0.55, 150)
        )
        let rim = rimStyle(chrome)
        let island = !chrome.hasNotch

        ZStack(alignment: .top) {
            silhouette(shape, chrome: chrome, island: island)

            ZStack(alignment: .top) {
                FluidoFaceView(model: model, chrome: chrome, pointer: effectivePointer(chrome))
                    .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
                    .id(faceKey(chrome.face))
                    .transition(.materialize(reduceMotion: reduceMotion))
            }
            .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
        .overlay(alignment: .top) {
            if let rim { RimLight(shape: shape, size: chrome.size, style: rim) }
        }
        // Light escaping onto the desktop, under the ink.
        .background(alignment: .top) {
            if let rim { RimLight(shape: shape, size: chrome.size, style: rim, inner: false) }
        }
        // Shadow on its own layer so the clipped content can't cut it.
        .background(alignment: .top) {
            shape
                .fill(Fluido.Palette.notch.opacity(island && !reduceTransparency ? 0.35 : 1))
                .shadow(color: .black.opacity(showsShadow(chrome) ? 0.6 : 0), radius: 20, y: 10)
                .shadow(color: .black.opacity(showsShadow(chrome) ? 0.3 : 0), radius: 3, y: 1)
        }
        .frame(width: chrome.size.width, height: chrome.size.height)
        .contentShape(shape)
        .onGeometryChange(for: CGSize.self, of: \.size) { model.visibleShapeSize = $0 }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { shapeFrame = $0 }
        .transaction(value: chrome.face) { transaction in
            // Fluido's own motion: opening with NotchNook's heartbeat, closing without bounce.
            guard transaction.animation != nil else { return }
            transaction.animation = chrome.isResting ? Fluido.Motion.close(reduceMotion) : Fluido.Motion.open(reduceMotion)
        }
        .animation(Fluido.Motion.hover(reduceMotion), value: magnet)
        .animation(Fluido.Motion.snappy(reduceMotion), value: rim)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { WindowReader(box: window) }
        .environment(\.colorScheme, .dark)
        // The panel is almost never key: keep glass and controls rendering as active.
        .environment(\.controlActiveState, .key)
        .tint(Fluido.Light.shelf.from)
        .task(id: tracksPointer) { await trackPointer() }
        .task(id: model.scenario) { applyScenarioDemoState() }
        .onAppear { shelfCount = model.shelf.count }
        .onChange(of: model.shelf.count) { old, new in
            shelfCount = new
            if new > old { swallow(chrome) }
        }
    }

    // MARK: - Silhouette

    @ViewBuilder
    private func silhouette(_ shape: FluidoNotchShape, chrome: FluidoChrome, island: Bool) -> some View {
        if island && !reduceTransparency {
            // No hardware notch to blend with: the island may be dark glass.
            shape
                .fill(Color.black.opacity(chrome.face == .expanded ? 0.62 : 0.5))
                .glassEffect(Glass.regular, in: shape)
                .overlay {
                    shape.stroke(
                        LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.14)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                    .clipShape(shape)
                }
        } else {
            shape.fill(Fluido.Palette.notch)
        }
    }

    private func showsShadow(_ chrome: FluidoChrome) -> Bool {
        switch chrome.face {
        case .rest: false
        case .ears: !chrome.hasNotch
        default: true
        }
    }

    /// Faces that share the same content identity (the expanded face keeps its identity while tabs change).
    private func faceKey(_ face: NotchFace) -> String {
        switch face {
        case .rest: "rest"
        case .ears: "ears"
        case let .peek(kind): "peek-\(kind)"
        case .dragArmed: "drag"
        case .expanded: "expanded"
        }
    }

    // MARK: - Light

    /// Which module is speaking, and how.
    private func rimStyle(_ chrome: FluidoChrome) -> RimStyle? {
        let band = chrome.hasNotch ? chrome.bandHeight * 0.55 : 4
        switch chrome.face {
        case .rest:
            return nil
        case .ears:
            // An agent waiting for you: the lime rim breathes. (Demo data: only while reviewing the scenario.)
            guard model.scenario == .idleWithEars, model.demo.waitingAgent != nil else { return nil }
            return RimStyle(light: .agents, intensity: 1, breathes: true, halo: 0.55, fadeTop: chrome.hasNotch ? 12 : 2)
        case .peek(.hint):
            return RimStyle(light: .brand, intensity: 0.45, fadeTop: band)
        case .peek(.shelf):
            return RimStyle(light: .shelf, intensity: 0.75, halo: 0.25, fadeTop: band)
        case .peek(.usageAlert):
            let level = UsageLevel(fraction: model.demo.primaryUsage.session.used)
            return RimStyle(light: level == .critical ? .critical : .ai, intensity: 1, rotates: true, halo: 0.55, fadeTop: band)
        case .peek(.agentWaiting):
            return RimStyle(light: .agents, intensity: 1, rotates: true, breathes: true, halo: 0.7, fadeTop: band)
        case .dragArmed:
            let proximity = magnetism(chrome).proximity
            return RimStyle(light: .shelf, intensity: 0.55 + 0.45 * proximity, rotates: true, halo: 0.35 + 0.55 * proximity, fadeTop: band)
        case .expanded:
            if model.state == .dropTarget {
                let zone = litZone
                let light: Fluido.Light = zone == .airDrop ? .airDrop : .shelf
                return RimStyle(light: light, intensity: zone == nil ? 0.5 : 1, rotates: true, halo: zone == nil ? 0.25 : 0.6, fadeTop: chrome.bandHeight)
            }
            // Open: the active tab's light rests along the lower edge, like light under a door.
            return RimStyle(light: model.tab.fluidoLight, intensity: 0.55, halo: 0, fadeTop: chrome.bandHeight + 60)
        }
    }

    private var litZone: DropZone? { model.dropZone ?? FluidoFlags.hoverZone }

    // MARK: - Pointer & magnetism

    private struct Magnet: Equatable {
        var x: CGFloat = 0.5
        var depth: CGFloat = 0
        var proximity: Double = 0
    }

    /// During a drag the silhouette stretches up to 10 pt towards the pointer, more the closer it gets.
    private func magnetism(_ chrome: FluidoChrome) -> Magnet {
        guard let pointer = effectivePointer(chrome), shapeFrame.width > 0 else { return Magnet() }
        let x = min(max((pointer.x - shapeFrame.minX) / shapeFrame.width, 0.1), 0.9)
        switch chrome.face {
        case .dragArmed:
            let distance = max(0, pointer.y - shapeFrame.maxY) + max(0, abs(pointer.x - shapeFrame.midX) - shapeFrame.width / 2) * 0.6
            let proximity = min(max(1 - distance / 220, 0), 1)
            return Magnet(x: x, depth: 10 * proximity, proximity: proximity)
        case .expanded where model.state == .dropTarget:
            return Magnet(x: x, depth: litZone == nil ? 3 : 7, proximity: 1)
        default:
            return Magnet()
        }
    }

    private var tracksPointer: Bool {
        (model.state == .dragArmed || model.state == .dropTarget) && model.scenario == nil && !reduceMotion
    }

    /// The live pointer, or a plausible one while reviewing a frozen scenario.
    private func effectivePointer(_ chrome: FluidoChrome) -> CGPoint? {
        if let pointer, tracksPointer { return pointer }
        guard model.scenario != nil, shapeFrame.width > 0 else { return nil }
        switch model.state {
        case .dragArmed:
            return CGPoint(x: shapeFrame.midX + 38, y: shapeFrame.maxY + 62)
        case .dropTarget:
            if let zone = litZone, let frame = model.dropZoneFrames[zone] {
                return CGPoint(x: frame.minX + frame.width * 0.42, y: frame.minY + frame.height * 0.58)
            }
            return CGPoint(x: shapeFrame.midX - 60, y: shapeFrame.maxY + 40)
        default:
            return nil
        }
    }

    private func trackPointer() async {
        guard tracksPointer else {
            pointer = nil
            return
        }
        while !Task.isCancelled {
            if let frame = window.window?.frame {
                let mouse = NSEvent.mouseLocation
                pointer = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    // MARK: - The swallow

    /// Something landed: the silhouette swells 6 pt where it touched and springs back.
    private func swallow(_ chrome: FluidoChrome) {
        guard !reduceMotion else { return }
        if let pointer, shapeFrame.width > 0 {
            swallowX = min(max((pointer.x - shapeFrame.minX) / shapeFrame.width, 0.1), 0.9)
        } else {
            swallowX = 0.42
        }
        withAnimation(.easeOut(duration: 0.12)) { swallowDepth = 6 }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(Fluido.Motion.swallow) { swallowDepth = 0 }
        }
    }

    /// A pre-selected tile so the review screenshot shows the selection style.
    private func applyScenarioDemoState() {
        guard model.scenario == .openShelf, model.selection.isEmpty, model.shelf.count > 1 else { return }
        model.selection = [model.shelf[1].id]
    }
}

// MARK: - Faces

private struct FluidoFaceView: View {
    let model: NotchModel
    let chrome: FluidoChrome
    let pointer: CGPoint?

    var body: some View {
        switch chrome.face {
        case .rest:
            Color.clear
        case .ears:
            FluidoEarsFace(model: model, chrome: chrome)
        case let .peek(kind):
            FluidoPeekFace(model: model, chrome: chrome, kind: kind)
        case .dragArmed:
            FluidoDragArmedFace(chrome: chrome)
        case .expanded:
            FluidoExpandedFace(model: model, chrome: chrome, pointer: pointer)
        }
    }
}

// MARK: - Window access

/// Holds the hosting window, to convert the global pointer into view coordinates.
@MainActor
final class WindowBox {
    weak var window: NSWindow?
}

private struct WindowReader: NSViewRepresentable {
    let box: WindowBox

    func makeNSView(context: Context) -> NSView {
        let view = ReaderView()
        view.box = box
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        box.window = view.window
    }

    private final class ReaderView: NSView {
        var box: WindowBox?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            box?.window = window
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
