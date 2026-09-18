import AltilloCore
import AltilloDesign
import AppKit
import SwiftUI

/// The shelf tab: things left on a plank, each with a kraft luggage tag hanging below it. Finder-like selection
/// (click, ⌘-click, ⇧-click), double-click opens, context menu, drag out with `shelfDraggable`.
struct DesvanShelfView: View {
    let model: NotchModel

    @State private var anchor: ShelfItem.ID?
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Top of the plank (its top surface) in the card.
    static let plankY: CGFloat = 76

    var body: some View {
        Group {
            if model.shelf.isEmpty {
                DesvanShelfEmptyState()
                    .transition(.contentSwap(reduceMotion: reduceMotion))
            } else {
                shelf
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .desvanCard()
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

    private var shelf: some View {
        ZStack(alignment: .top) {
            // Clicking empty space clears the selection.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.selection.removeAll() }

            DesvanPlank()
                .padding(.top, Self.plankY)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 1) {
                    ForEach(model.shelf) { item in
                        DesvanShelfTile(
                            item: item,
                            isSelected: model.selection.contains(item.id),
                            onClick: { click(item) },
                            menuItems: { targets(for: item) },
                            model: model
                        )
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.never)
            .scrollClipDisabled()
            .frame(height: 170)

            DesvanShelfHint(hasSelection: !model.selection.isEmpty)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

private struct DesvanShelfTile: View {
    let item: ShelfItem
    let isSelected: Bool
    let onClick: () -> Void
    let menuItems: () -> [ShelfItem]
    let model: NotchModel

    @State private var isHovering = false
    @State private var swingAngle = 0.0
    @State private var landing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 99
    static let thumbnailSide: CGFloat = 64
    /// Height of the space things stand in; their base sinks 3 pt into the plank's top surface (depth).
    static let thingHeight: CGFloat = thumbnailSide + 8
    static let sink: CGFloat = 3
    static let tagWidth: CGFloat = width - 2

    /// The name written on the tag, fitted to its lines. The extension is already under it ("PNG · 294 KB"), so
    /// it's left off; file names keep their end (dates, versions), text keeps its beginning.
    private var tagTitle: String {
        let textWidth = Self.tagWidth - 2 * DesvanLuggageTag.horizontalPadding
        switch item.kind {
        case .file:
            let stem = (item.displayName as NSString).deletingPathExtension
            return DesvanTagText.fit(stem.isEmpty ? item.displayName : stem, width: textWidth, keepEnd: true)
        case .link:
            return DesvanTagText.fit(item.displayName, width: textWidth, keepEnd: true)
        case .text:
            return DesvanTagText.fit(item.displayName, width: textWidth, keepEnd: false)
        }
    }

    /// Things left on a shelf, not a grid: a fixed, stable tilt of ±1.5° per item.
    private var tilt: Double { Desvan.jitter(item.id) * 1.5 }
    private var lift: CGFloat { isSelected ? 2 : (isHovering ? 1 : 0) }

    var body: some View {
        VStack(spacing: 0) {
            thing
                .frame(width: Self.width, height: Self.thingHeight, alignment: .bottom)
            Color.clear.frame(height: DesvanPlank.height - Self.sink - 2.5) // the plank (the pin sits on its edge)
            DesvanLuggageTag(
                title: tagTitle,
                detail: NotchFormat.subtitle(for: item),
                edge: Desvan.labelColor(for: item),
                isSelected: isSelected,
                width: Self.tagWidth,
                cord: 6
            )
            .rotationEffect(.degrees(swingAngle), anchor: .top)
        }
        .frame(width: Self.width)
        .padding(.top, DesvanShelfView.plankY + Self.sink - Self.thingHeight)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Desvan.Motion.hover) { isHovering = hovering }
            if hovering { push(3.5) }
        }
        .onTapGesture(perform: onClick)
        .shelfDraggable(items: menuItems) { _, departed in
            // Moved to a folder or dropped on the Trash → it's gone from here too. Copied elsewhere → it stays.
            if !departed.isEmpty { model.actions.remove(Set(departed.map(\.id))) }
        }
        .contextMenu { contextMenu }
        .onAppear {
            // Just saved: it falls from the notch onto the plank.
            if Date.now.timeIntervalSince(item.addedAt) < 1.5 { land() }
        }
        .onChange(of: DesvanDebug.clock.tick) {
            // `-demoMotion landing`: the newest thing lands again and again.
            if DesvanDebug.demoMotion == .landing, model.shelf.last?.id == item.id { land() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(NotchFormat.subtitle(for: item))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// The thumbnail resting on the plank, with its contact shadow.
    private var thing: some View {
        ZStack(alignment: .bottom) {
            contactShadow
            DesvanThumbnail(item: item, side: Self.thumbnailSide)
                .rotationEffect(.degrees(tilt), anchor: .bottom)
                .shadow(color: isSelected ? Desvan.Palette.bulb.opacity(0.28) : .clear, radius: 10, y: -2)
                .offset(y: -lift)
                .animation(Desvan.Motion.pick(.spring(duration: 0.25, bounce: 0.2), reduceMotion: reduceMotion), value: lift)
                .keyframeAnimator(initialValue: LandingPose(), trigger: landing) { content, pose in
                    content
                        .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
                        .rotationEffect(.degrees(pose.rotation), anchor: .bottom)
                        .offset(y: pose.offsetY)
                } keyframes: { _ in
                    KeyframeTrack(\.offsetY) {
                        // Falls from above the card, accelerating (≈ y = t²).
                        MoveKeyframe(-90)
                        LinearKeyframe(-80, duration: 0.08)
                        LinearKeyframe(-50, duration: 0.08)
                        LinearKeyframe(0, duration: 0.08)
                    }
                    KeyframeTrack(\.rotation) {
                        MoveKeyframe(-4)
                        LinearKeyframe(-3, duration: 0.24)
                        SpringKeyframe(0, duration: 0.5, spring: .init(duration: 0.5, bounce: 0.35))
                    }
                    KeyframeTrack(\.scaleX) {
                        LinearKeyframe(1, duration: 0.24)
                        LinearKeyframe(1.04, duration: 0.06) // squash on impact
                        SpringKeyframe(1, duration: 0.5, spring: .init(duration: 0.5, bounce: 0.35))
                    }
                    KeyframeTrack(\.scaleY) {
                        LinearKeyframe(1, duration: 0.24)
                        LinearKeyframe(0.94, duration: 0.06)
                        SpringKeyframe(1, duration: 0.5, spring: .init(duration: 0.5, bounce: 0.35))
                    }
                }
        }
    }

    /// Contact shadow on the plank's top surface: a tight dark core and a wider, softer penumbra. It stays on the
    /// board: lifting (hover, selection) spreads it and makes it lighter, and it gathers as a falling thing arrives.
    private var contactShadow: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.4 - 0.06 * lift))
                .frame(width: 68 + 3 * lift, height: 7 + lift)
                .blur(radius: 3 + lift)
            Ellipse()
                .fill(.black.opacity(0.8 - 0.2 * lift))
                .frame(width: 52, height: 3)
                .blur(radius: 1 + 0.6 * lift)
        }
        .offset(y: 2.5)
        .animation(Desvan.Motion.pick(.spring(duration: 0.25, bounce: 0), reduceMotion: reduceMotion), value: lift)
        .keyframeAnimator(initialValue: 1.0, trigger: landing) { content, presence in
            content.opacity(presence).scaleEffect(x: 0.5 + 0.5 * presence, y: 1)
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(0.1)
                CubicKeyframe(1, duration: 0.24)
            }
        }
        .allowsHitTesting(false)
    }

    /// Falls from above, squashes on the plank and settles; the tag swings as the thing hits the board.
    private func land() {
        guard !reduceMotion else { return }
        landing.toggle()
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            push(8)
        }
    }

    /// A gentle push on the tag: it swings like a pendulum and comes to rest.
    private func push(_ degrees: Double) {
        guard !reduceMotion else { return }
        swingAngle = degrees * (Desvan.jitter(item.id, salt: 7) >= 0 ? 1 : -1)
        withAnimation(Desvan.Motion.pendulum) { swingAngle = 0 }
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
        Button(items.count > 1 ? "Bajar \(items.count) cosas del altillo" : "Bajar del altillo", role: .destructive) {
            model.actions.remove(Set(items.map(\.id)))
        }
    }

    private struct LandingPose {
        var offsetY = 0.0
        var rotation = 0.0
        var scaleX = 1.0
        var scaleY = 1.0
    }
}

// MARK: - Thumbnails

/// What sits on the plank: Quick Look thumbnails for files (bottom-aligned so they rest on the board),
/// a taped paper note for text and a postcard for links.
struct DesvanThumbnail: View {
    let item: ShelfItem
    let side: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?

    var body: some View {
        Group {
            switch item.kind {
            case let .file(url, _):
                file(url)
            case let .text(text):
                DesvanNote(text: text)
            case let .link(url):
                DesvanPostcard(host: url.host(percentEncoded: false) ?? url.absoluteString)
            }
        }
        .frame(width: side + 12, height: side + 8, alignment: .bottom)
    }

    @ViewBuilder
    private func file(_ url: URL) -> some View {
        Group {
            if let image = image ?? ThumbnailCache.shared.cached(url, side: side, scale: displayScale) {
                // Square images are file icons, which carry transparent padding: sit them down on the plank.
                let isIcon = abs(image.size.width / max(image.size.height, 1) - 1) < 0.02
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: side + 10, maxHeight: side)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .offset(y: isIcon ? side * 0.07 : 0)
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Desvan.Palette.woodRaised)
                    .frame(width: side * 0.72, height: side * 0.86)
            }
        }
        .task(id: url) {
            image = await ThumbnailCache.shared.thumbnail(for: url, side: side, scale: displayScale)
        }
    }
}

/// A paper note held with a strip of masking tape.
private struct DesvanNote: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: 7.5, weight: .medium))
                .foregroundStyle(Desvan.Palette.ink)
                .lineSpacing(1)
                .lineLimit(5)
                .padding(.horizontal, 6)
                .padding(.top, 9)
            Spacer(minLength: 0)
        }
        .frame(width: 54, height: 60, alignment: .topLeading)
        .background {
            Rectangle()
                .fill(Desvan.Palette.paper)
                .overlay {
                    // Faint ruled lines.
                    VStack(spacing: 9.5) {
                        ForEach(0..<6, id: \.self) { _ in
                            Rectangle().fill(Desvan.Palette.sky.opacity(0.25)).frame(height: 0.5)
                        }
                    }
                    .padding(.top, 16)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Desvan.Palette.tape.opacity(0.85))
                .frame(width: 26, height: 8)
                .rotationEffect(.degrees(-4))
                .offset(y: -4)
        }
        .accessibilityHidden(true)
    }
}

/// A postcard for a link: the host written on it and a stamp in the link colour.
private struct DesvanPostcard: View {
    let host: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(Desvan.Palette.ink.opacity(0.25)).frame(width: 22, height: 1.5)
                    Capsule().fill(Desvan.Palette.ink.opacity(0.25)).frame(width: 16, height: 1.5)
                }
                .padding(.top, 3)
                Spacer(minLength: 0)
                ZStack {
                    RoundedRectangle(cornerRadius: 1.5).fill(Desvan.Palette.lavender)
                    Image(systemName: "link")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Desvan.Palette.ink.opacity(0.8))
                }
                .frame(width: 15, height: 17)
                .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [1.5, 1])))
            }
            Spacer(minLength: 0)
            Text(host)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Desvan.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(6)
        .frame(width: 70, height: 48)
        .background {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(hex: 0xEFE5D2))
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Hint and empty state

/// One quiet line of help at the bottom of the shelf.
private struct DesvanShelfHint: View {
    let hasSelection: Bool

    var body: some View {
        HStack(spacing: 14) {
            hint("hand.draw", "Arrástralo fuera para bajarlo")
            hint("space", "Mirar")
            if hasSelection { hint("delete.left", "Quitar") }
        }
        .font(Desvan.Typeface.rounded(10.5, weight: .medium))
        .foregroundStyle(Desvan.Palette.paperTertiary)
        .frame(maxWidth: .infinity)
        .animation(Desvan.Motion.hover, value: hasSelection)
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .medium))
            Text(text)
        }
    }
}

/// «El altillo está vacío.» An empty plank, the house with its light on, and one warm sentence.
struct DesvanShelfEmptyState: View {
    var body: some View {
        ZStack(alignment: .top) {
            // The bare board, running wall to wall like the full shelf's.
            DesvanPlank()
                .padding(.top, 128)
            VStack(spacing: 6) {
                DesvanHouseMark(size: 22)
                    .padding(.bottom, 4)
                Text("El altillo está vacío.")
                    .font(Desvan.Typeface.fraunces(17, weight: 600))
                    .foregroundStyle(Desvan.Palette.paper)
                Text("Sube aquí lo que quieras tener a mano un rato.")
                    .font(.system(size: 12))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
            }
            .padding(.top, 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
