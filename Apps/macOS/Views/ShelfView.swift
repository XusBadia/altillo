import AltilloCore
import AltilloDesign
import AppKit
import SwiftUI

/// The shelf tab: a horizontal row of tiles with Finder-like selection, or an inviting empty state.
struct ShelfView: View {
    let model: NotchModel

    @State private var anchor: ShelfItem.ID?
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.shelf.isEmpty {
                ShelfEmptyState()
                    .transition(.contentSwap(reduceMotion: reduceMotion))
            } else {
                tiles
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            guard !model.selection.isEmpty else { return .ignored }
            model.actions.remove(model.selection)
            return .handled
        }
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
                LazyHStack(spacing: 4) {
                    ForEach(model.shelf) { item in
                        ShelfTile(
                            item: item,
                            isSelected: model.selection.contains(item.id),
                            onClick: { click(item) },
                            menuItems: { targets(for: item) },
                            model: model
                        )
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
            .frame(height: 162)

            Spacer(minLength: 0)
            ShelfHint(hasSelection: !model.selection.isEmpty)
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

    /// The items an action on `item` applies to: the whole selection when the item is part of it.
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

private struct ShelfTile: View {
    let item: ShelfItem
    let isSelected: Bool
    let onClick: () -> Void
    let menuItems: () -> [ShelfItem]
    let model: NotchModel

    @State private var isHovering = false
    @Environment(\.altilloAccent) private var accent

    static let width: CGFloat = 100
    static let thumbnail: CGFloat = 78

    var body: some View {
        VStack(spacing: 8) {
            ShelfThumbnail(item: item, side: Self.thumbnail)
                .frame(width: 94, height: 94)
                .background {
                    RoundedRectangle(cornerRadius: Tokens.Radius.base, style: .continuous)
                        .fill(wellFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: Tokens.Radius.base, style: .continuous)
                                .strokeBorder(isSelected ? accent.opacity(0.55) : .clear, lineWidth: 1)
                        }
                }
                .scaleEffect(isHovering && !isSelected ? 1.03 : 1)

            VStack(spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Tokens.Palette.surface : Tokens.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background {
                        Capsule().fill(isSelected ? accent : .clear)
                    }
                Text(NotchFormat.subtitle(for: item))
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .monospacedDigit()
            }
            .frame(width: Self.width - 6)
        }
        .frame(width: Self.width)
        .padding(.vertical, 6)
        .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.base, style: .continuous))
        .onHover { hovering in withAnimation(Tokens.Motion.hover) { isHovering = hovering } }
        .onTapGesture(perform: onClick)
        .shelfDraggable(items: menuItems) { _, departed in
            // Moved to a folder or dropped on the Trash → it's gone from here too. Copied elsewhere → it stays.
            if !departed.isEmpty { model.actions.remove(Set(departed.map(\.id))) }
        }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(NotchFormat.subtitle(for: item))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var wellFill: Color {
        if isSelected { return Tokens.Palette.elevated }
        return isHovering ? Tokens.Palette.text.opacity(0.06) : .clear
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

/// One quiet line of help under the tiles.
private struct ShelfHint: View {
    let hasSelection: Bool

    var body: some View {
        HStack(spacing: 14) {
            hint("hand.draw", "Arrastra fuera para mover")
            hint("space", "Vista rápida")
            if hasSelection { hint("delete.left", "Quitar") }
        }
        .font(Tokens.Typography.caption)
        .foregroundStyle(Tokens.Palette.textTertiary)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
        .animation(Tokens.Motion.hover, value: hasSelection)
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .medium))
            Text(text)
        }
    }
}

// MARK: - Empty state

struct ShelfEmptyState: View {
    @Environment(\.altilloAccent) private var accent

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(accent)
            }
            VStack(spacing: 4) {
                Text("Arrastra aquí lo que quieras guardar un momento")
                    .font(Tokens.Typography.title)
                    .foregroundStyle(Tokens.Palette.text)
                Text("Archivos, imágenes, enlaces o texto. Luego los sueltas donde quieras.")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Palette.textSecondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape.fill(Tokens.Palette.surface.opacity(0.6))
                .grain(0.05, in: shape)
        }
        .overlay {
            shape.strokeBorder(Tokens.Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }
}
