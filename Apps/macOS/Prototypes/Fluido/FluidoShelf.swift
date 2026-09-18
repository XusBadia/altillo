import AltilloCore
import AltilloDesign
import AppKit
import CoreImage
import SwiftUI

/// The shelf tab: 60 pt squircle thumbnails straight on the ink, each casting a faint glow of its own colour.
/// Finder-like selection (click, ⌘, ⇧), double-click opens, context menu, drag out with `shelfDraggable`.
struct FluidoShelfView: View {
    let model: NotchModel

    @State private var anchor: ShelfItem.ID?
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.shelf.isEmpty {
                FluidoShelfEmpty()
                    .transition(.materialize(reduceMotion: reduceMotion))
            } else {
                tiles
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        // ⌫ is handled by NotchCoordinator in AppKit.
        .onKeyPress(.space) {
            let items = selectedItems
            guard !items.isEmpty else { return .ignored }
            model.actions.quickLook(items)
            return .handled
        }
        .onKeyPress(characters: ["a"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            model.selection = Set(model.shelf.map(\.id))
            return .handled
        }
        .onKeyPress(.escape) {
            model.actions.send(.escape)
            return .handled
        }
    }

    private var tiles: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(model.shelf) { item in
                        FluidoTile(
                            item: item,
                            isSelected: model.selection.contains(item.id),
                            onClick: { click(item) },
                            targets: { targets(for: item) },
                            model: model
                        )
                        // Arrivals condense out of the ink, falling from the notch.
                        .transition(ArrivalTransition(reduceMotion: reduceMotion))
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.never)
            .frame(height: 150)

            Spacer(minLength: 0)
            FluidoShelfHint(hasSelection: !model.selection.isEmpty)
        }
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.selection.removeAll() }
        }
    }

    private var selectedItems: [ShelfItem] {
        model.shelf.filter { model.selection.contains($0.id) }
    }

    private func targets(for item: ShelfItem) -> [ShelfItem] {
        model.selection.contains(item.id) ? selectedItems : [item]
    }

    /// Finder semantics: click selects, ⌘-click toggles, ⇧-click extends from the anchor, double-click opens.
    private func click(_ item: ShelfItem) {
        let flags = NSEvent.modifierFlags
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            targets(for: item).forEach(model.actions.open)
            return
        }
        withAnimation(Fluido.Motion.snappy(reduceMotion)) {
            if flags.contains(.command) {
                if model.selection.contains(item.id) { model.selection.remove(item.id) } else { model.selection.insert(item.id) }
                anchor = item.id
            } else if flags.contains(.shift), let anchor,
                      let from = model.shelf.firstIndex(where: { $0.id == anchor }),
                      let to = model.shelf.firstIndex(where: { $0.id == item.id }) {
                model.selection = Set(model.shelf[min(from, to)...max(from, to)].map(\.id))
            } else {
                model.selection = [item.id]
                anchor = item.id
            }
        }
    }
}

/// A tile arriving condenses out of the ink, falling from the notch; a tile leaving shrinks away.
private struct ArrivalTransition: Transition {
    var reduceMotion: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        if reduceMotion {
            content.opacity(phase.isIdentity ? 1 : 0)
        } else {
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .blur(radius: phase == .willAppear ? 6 : 0)
                .scaleEffect(phase.isIdentity ? 1 : (phase == .willAppear ? 0.4 : 0.8), anchor: .top)
                .offset(y: phase == .willAppear ? -30 : 0)
        }
    }
}

// MARK: - Tile

private struct FluidoTile: View {
    let item: ShelfItem
    let isSelected: Bool
    let onClick: () -> Void
    let targets: () -> [ShelfItem]
    let model: NotchModel

    @State private var isHovering = false
    @State private var glow: Color = .clear
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let side: CGFloat = 60
    static let width: CGFloat = 88

    var body: some View {
        VStack(spacing: 9) {
            FluidoThumbnail(item: item, side: Self.side, glow: $glow)
                .overlay {
                    RoundedRectangle(cornerRadius: Fluido.Radius.thumbnail + 3, style: .continuous)
                        .strokeBorder(Fluido.Light.shelf.linear(.topLeading, .bottomTrailing), lineWidth: 2)
                        .padding(-4)
                        .opacity(isSelected ? 1 : 0)
                }
                .background(alignment: .bottom) {
                    // The thumbnail's own colour, pooled on the ink below it (stronger on hover).
                    Ellipse()
                        .fill(isSelected ? Fluido.Light.shelf.mid : glow)
                        .frame(width: Self.side * 0.9, height: 16)
                        .blur(radius: isHovering ? 12 : 10)
                        .opacity(isHovering ? 0.85 : (isSelected ? 0.7 : 0.45))
                        .offset(y: isHovering ? 12 : 9)
                }
                .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
                .scaleEffect(isHovering && !reduceMotion ? 1.04 : 1)

            VStack(spacing: 2) {
                Text(item.displayName)
                    .font(Fluido.Typography.itemName)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundStyle(isSelected ? Color.black : Fluido.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background {
                        Capsule().fill(Fluido.Light.shelf.linear(.leading, .trailing)).opacity(isSelected ? 1 : 0)
                    }
                Text(NotchFormat.subtitle(for: item))
                    .font(.system(size: 10, weight: .medium).width(.condensed))
                    .foregroundStyle(Fluido.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .monospacedDigit()
            }
            .frame(width: Self.width - 4)
        }
        .frame(width: Self.width)
        .padding(.vertical, 4)
        .contentShape(RoundedRectangle(cornerRadius: Fluido.Radius.thumbnail, style: .continuous))
        .onHover { hovering in withAnimation(Fluido.Motion.hover(reduceMotion)) { isHovering = hovering } }
        .onTapGesture(perform: onClick)
        .shelfDraggable(items: targets) { _, departed in
            // Moved to a folder or dropped on the Trash → gone from here too. Copied elsewhere → it stays.
            if !departed.isEmpty { model.actions.remove(Set(departed.map(\.id))) }
        }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(NotchFormat.subtitle(for: item))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var contextMenu: some View {
        let items = targets()
        Button("Abrir") { items.forEach(model.actions.open) }
        if items.contains(where: { $0.fileURL != nil }) {
            Button("Mostrar en Finder") { model.actions.revealInFinder(items) }
            Button("Vista rápida") { model.actions.quickLook(items) }
        }
        Divider()
        Button(items.count > 1 ? "Quitar \(items.count) elementos" : "Quitar", role: .destructive) {
            model.actions.remove(Set(items.map(\.id)))
        }
    }
}

/// A 60 pt squircle (radius 14): photos fill it, documents sit inside an ink well, text is a note, links a lit tile.
private struct FluidoThumbnail: View {
    let item: ShelfItem
    let side: CGFloat
    @Binding var glow: Color

    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Fluido.Radius.thumbnail, style: .continuous)
        Group {
            switch item.kind {
            case let .file(url, _):
                file(url, shape: shape)
            case let .text(text):
                note(text, shape: shape)
            case .link:
                link(shape: shape)
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75) }
    }

    @ViewBuilder
    private func file(_ url: URL, shape: RoundedRectangle) -> some View {
        let isPhoto = ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff"].contains(url.pathExtension.lowercased())
        ZStack {
            shape.fill(Fluido.Palette.ink2)
            if let image = image ?? ThumbnailCache.shared.cached(url, side: side * 1.2, scale: displayScale) {
                if isPhoto {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .padding(7)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                }
            }
        }
        .task(id: url) {
            let loaded = await ThumbnailCache.shared.thumbnail(for: url, side: side * 1.2, scale: displayScale)
            image = loaded
            if let loaded { glow = AverageColor.of(loaded) }
        }
    }

    private func note(_ text: String, shape: RoundedRectangle) -> some View {
        ZStack(alignment: .topLeading) {
            shape.fill(Color(hex: 0xF4F4F1))
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(Fluido.Light.shelf.linear).frame(width: 16, height: 2.5)
                Text(text)
                    .font(.system(size: 6.5, weight: .medium))
                    .foregroundStyle(Color(hex: 0x2A2A2E))
                    .lineSpacing(0.5)
                    .lineLimit(5)
            }
            .padding(7)
        }
        .onAppear { glow = Color(hex: 0xFFE2B0) }
    }

    private func link(shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(LinearGradient(colors: [Color(hex: 0x1D2A4A), Color(hex: 0x0E1426)], startPoint: .top, endPoint: .bottom))
            Circle()
                .fill(Fluido.Light.airDrop.linear(.topLeading, .bottomTrailing))
                .frame(width: 30, height: 30)
                .blur(radius: 12)
                .opacity(0.7)
            Image(systemName: "link")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Fluido.Light.airDrop.linear(.top, .bottom))
        }
        .onAppear { glow = Fluido.Light.airDrop.from }
    }
}

/// Average colour of a thumbnail (`CIAreaAverage`), to tint its glow. Cached per image.
@MainActor
enum AverageColor {
    private static var cache: [ObjectIdentifier: Color] = [:]
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func of(_ image: NSImage) -> Color {
        if let cached = cache[ObjectIdentifier(image)] { return cached }
        var color = Color.white.opacity(0.4)
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let input = CIImage(cgImage: cg)
            if let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)]),
               let output = filter.outputImage {
                var pixel = [UInt8](repeating: 0, count: 4)
                context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
                // Lift it a little: it is a light, not a stain.
                let lift = { (v: UInt8) in min(1, Double(v) / 255 * 1.25 + 0.08) }
                color = Color(red: lift(pixel[0]), green: lift(pixel[1]), blue: lift(pixel[2]))
            }
        }
        cache[ObjectIdentifier(image)] = color
        return color
    }
}

/// One quiet line of help under the tiles.
private struct FluidoShelfHint: View {
    let hasSelection: Bool

    var body: some View {
        HStack(spacing: 16) {
            hint("hand.draw", "Arrastra fuera para sacarlo")
            hint("space", "Vista rápida")
            if hasSelection { hint("delete.left", "Quitar") }
        }
        .font(Fluido.Typography.caption)
        .foregroundStyle(Fluido.Palette.textTertiary)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .medium))
            Text(text)
        }
    }
}

// MARK: - Empty

/// "Nada por aquí." A dim tray with the shelf's light pooled under it.
struct FluidoShelfEmpty: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Fluido.Light.shelf.linear(.top, .bottom))
                .shadow(color: Fluido.Light.shelf.mid.opacity(0.6), radius: 14)
            VStack(spacing: 4) {
                Text("Nada por aquí.")
                    .font(Fluido.Typography.display)
                    .foregroundStyle(Fluido.Palette.text)
                Text("Suelta algo en el notch.")
                    .font(Fluido.Typography.body)
                    .foregroundStyle(Fluido.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
