import AltilloCore
import AltilloDesign
import AppKit
import SwiftUI

/// The shelf tab without cards: 56-pt thumbnails on black with a 1-px hairline, viewfinder selection and a footer of
/// shortcuts. Finder-like selection (click, ⌘, ⇧), double-click opens, context menu, drag out with AppKit.
struct MatrizShelf: View {
    let model: NotchModel

    @State private var anchor: ShelfItem.ID?
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if model.shelf.isEmpty {
                MatrizShelfEmpty()
            } else {
                tiles
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        // ⌫ is handled by NotchCoordinator in AppKit: SwiftUI never receives the Mac's backspace key here.
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
                LazyHStack(alignment: .top, spacing: 8) {
                    ForEach(model.shelf) { item in
                        MatrizTile(
                            item: item,
                            isSelected: model.selection.contains(item.id),
                            onClick: { click(item) },
                            menuItems: { targets(for: item) },
                            model: model
                        )
                        .transition(.opacity)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.never)
            .frame(height: 150)

            Spacer(minLength: 0)
            DotRule().padding(.bottom, 9)
            MatrizShelfFooter(hasSelection: !model.selection.isEmpty)
        }
        .background {
            // Clicking empty space clears the selection.
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

// MARK: - Tile

private struct MatrizTile: View {
    let item: ShelfItem
    let isSelected: Bool
    let onClick: () -> Void
    let menuItems: () -> [ShelfItem]
    let model: NotchModel

    @State private var isHovering = false
    /// Landing: the item falls 8 pt (the direction's only bounce) and its corners flash once.
    @State private var drop: CGFloat = 0
    @State private var flash: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 96
    static let socket: CGFloat = 56

    var body: some View {
        VStack(spacing: 9) {
            socket
                .offset(y: drop)
            VStack(spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Matriz.Palette.phosphor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(height: 28, alignment: .top)
                Text(Self.meta(for: item))
                    .font(Matriz.Fonts.departure())
                    .foregroundStyle(Matriz.Palette.phosphor2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: Self.width - 4)
        }
        .frame(width: Self.width)
        .padding(.top, 6)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onClick)
        .shelfDraggable(items: menuItems) { _, departed in
            // Moved to a folder or dropped on the Trash → it's gone from here too. Copied elsewhere → it stays.
            if !departed.isEmpty { model.actions.remove(Set(departed.map(\.id))) }
        }
        .contextMenu { contextMenu }
        .onAppear(perform: landIfNew)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(Self.meta(for: item))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var socket: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return ShelfThumbnail(item: item, side: Self.socket - 10)
            .frame(width: Self.socket, height: Self.socket)
            .background(shape.fill(isHovering || isSelected ? Matriz.Palette.panelRaised : Matriz.Palette.panel))
            .overlay(shape.strokeBorder(isHovering ? Matriz.Palette.phosphor3 : Matriz.Palette.hairline, lineWidth: 1))
            .overlay {
                ViewfinderCorners(arm: 7)
                    .stroke(Matriz.Palette.signal, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
                    .padding(-5)
                    .opacity(isSelected ? 1 : flash)
                    .ledGlow(2.5, opacity: 0.55, isOn: isSelected || flash > 0)
            }
    }

    private func landIfNew() {
        guard Date.now.timeIntervalSince(item.addedAt) < 1.5 else { return }
        if reduceMotion {
            flash = 0
            return
        }
        drop = -8
        withAnimation(Matriz.Motion.landing) { drop = 0 }
        withAnimation(.easeOut(duration: 0.13)) { flash = 1 }
        withAnimation(.easeIn(duration: 0.13).delay(0.13)) { flash = 0 }
    }

    /// "PDF · 13 KB", "ENLACE", "TEXTO": uppercase metadata for Departure Mono.
    static func meta(for item: ShelfItem) -> String {
        switch item.kind {
        case .text: return "TEXTO"
        case .link: return "ENLACE"
        case let .file(url, _):
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == true { return "CARPETA" }
            let kind = url.pathExtension.isEmpty ? "ARCHIVO" : url.pathExtension.uppercased()
            guard let size = values?.fileSize else { return kind }
            return "\(kind) · \(compactSize(size))"
        }
    }

    /// "305 B", "13 KB", "4,2 MB": short enough for an 11-pt Departure Mono line.
    static func compactSize(_ bytes: Int) -> String {
        if bytes < 1000 { return "\(bytes) B" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes)).uppercased()
    }

    @ViewBuilder
    private var contextMenu: some View {
        let items = menuItems()
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

/// Shortcuts in Departure Mono, phosphor3.
private struct MatrizShelfFooter: View {
    let hasSelection: Bool

    var body: some View {
        HStack(spacing: 18) {
            hint("ARRASTRA FUERA", "MOVER")
            hint("ESPACIO", "VISTA RÁPIDA")
            hint("⌘A", "TODO")
            if hasSelection { hint("⌫", "QUITAR") }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 1)
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 6) {
            Text(key).matrizLabel().foregroundStyle(Matriz.Palette.phosphor2)
            Text(action).matrizLabel().foregroundStyle(Matriz.Palette.phosphor3)
        }
    }
}

// MARK: - Empty

/// ALTILLO VACÍO: the roof lit on a dark matrix, and one quiet sentence.
struct MatrizShelfEmpty: View {
    var body: some View {
        VStack(spacing: 14) {
            DotGlyph(Glyph7.roof, pitch: 6, dot: 4, color: Matriz.Palette.phosphor)
                .ledGlow(3, opacity: 0.45)
            VStack(spacing: 6) {
                Text("ALTILLO VACÍO")
                    .matrizLabel()
                    .foregroundStyle(Matriz.Palette.phosphor)
                Text("Arrastra algo hasta aquí. Lo guardo hasta que lo bajes.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Matriz.Palette.phosphor2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            DotGrid()
                .mask(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 40, endRadius: 300))
        }
    }
}
