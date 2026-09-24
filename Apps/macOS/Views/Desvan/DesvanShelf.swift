import AltilloCore
import AltilloDesign
import AppKit
import SwiftUI

/// The shelf tab: things left on a plank, each standing on the board with its name written on the wall below it.
/// Finder-like selection (click, ⌘-click, ⇧-click), double-click opens, context menu, drag out with `shelfDraggable`.
struct DesvanShelfView: View {
    let model: NotchModel

    @State private var anchor: ShelfItem.ID?
    /// The moving end of a keyboard walk (⇧← / ⇧→ keep `anchor` still and move this one).
    @State private var cursor: ShelfItem.ID?
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static let rowPadding: CGFloat = 10

    /// Top of the plank (its top surface) in the card: 18 pt of air above the things, then the things themselves.
    /// The empty shelf keeps its board at the same height, so the plank doesn't jump when the first thing lands.
    static let plankY: CGFloat = 99

    /// How wide the card is, so the row can centre itself while everything fits and the fades know their size.
    @State private var cardWidth: CGFloat = 0
    /// Where the row is scrolled and how far it can go, for the edge fades and the mouse wheel.
    @State private var scrollX: CGFloat = 0
    @State private var maxScrollX: CGFloat = 0
    @State private var position = ScrollPosition(idType: ShelfItem.ID.self)

    /// Width of the fade at each end of the row when there is more shelf out of sight.
    private static let fade: CGFloat = 28

    var body: some View {
        Group {
            if model.shelf.isEmpty {
                DesvanShelfEmptyState(isReceiving: model.isReceivingDrop, problem: model.shelfProblem)
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
        // ← / → walk along the plank (⇧ extends the pick) and bring whatever they reach into view.
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { press in
            guard !model.shelf.isEmpty else { return .ignored }
            move(press.key == .leftArrow ? -1 : 1, extend: press.modifiers.contains(.shift))
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

            row
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { cardWidth = $0 }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var row: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(model.shelf) { item in
                    DesvanShelfTile(
                        item: item,
                        isSelected: model.selection.contains(item.id),
                        onClick: { click(item) },
                        menuItems: { targets(for: item) },
                        model: model
                    )
                    .id(item.id)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, Self.rowPadding)
            // While everything fits, the things sit centred on the plank instead of huddling on the left.
            .frame(minWidth: cardWidth)
        }
        .scrollIndicators(.visible, axes: .horizontal)
        .scrollClipDisabled()
        .scrollPosition($position)
        .reportsHorizontalScroll(id: "shelf.row", model: model)
        .onScrollGeometryChange(for: ShelfScroll.self) { geometry in
            ShelfScroll(
                offset: geometry.contentOffset.x,
                limit: max(0, geometry.contentSize.width - geometry.containerSize.width)
            )
        } action: { _, new in
            scrollX = new.offset
            maxScrollX = new.limit
        }
        .mask { fades }
        // A plain mouse has no horizontal wheel: turning it moves the shelf sideways.
        .overlay {
            DesvanWheelCatcher { delta in scrollBy(delta) }
                .allowsHitTesting(false)
        }
        .onChange(of: model.shelf.count) { old, new in
            // Something new landed: make room for it in view.
            guard new > old, let last = model.shelf.last?.id else { return }
            withAnimation(Desvan.Motion.pick(.spring(duration: 0.35, bounce: 0), reduceMotion: reduceMotion)) {
                position.scrollTo(id: last, anchor: .center)
            }
        }
    }

    /// Both ends fade out while there is more shelf that way, so it reads as scrollable at a glance.
    private var fades: some View {
        let width = max(cardWidth, 1)
        let stop = min(0.45, Self.fade / width)
        let leading = scrollX > 1
        let trailing = scrollX < maxScrollX - 1
        return LinearGradient(
            stops: [
                .init(color: .black.opacity(leading ? 0 : 1), location: 0),
                .init(color: .black, location: stop),
                .init(color: .black, location: 1 - stop),
                .init(color: .black.opacity(trailing ? 0 : 1), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .animation(Desvan.Motion.pick(.easeOut(duration: 0.2), reduceMotion: reduceMotion), value: leading)
        .animation(Desvan.Motion.pick(.easeOut(duration: 0.2), reduceMotion: reduceMotion), value: trailing)
    }

    /// Moves the row by `delta` points, if there is anywhere to go. Returns false so the wheel event goes on its way.
    private func scrollBy(_ delta: CGFloat) -> Bool {
        guard maxScrollX > 0.5 else { return false }
        let target = min(max(0, scrollX - delta), maxScrollX)
        guard abs(target - scrollX) > 0.01 else { return false }
        scrollX = target
        position.scrollTo(x: target)
        return true
    }

    /// Where the row sits and how far it can still go.
    private struct ShelfScroll: Equatable {
        var offset: CGFloat
        var limit: CGFloat
    }

    /// ← / →: picks the neighbour of the current pick (or the first thing), and scrolls it into view.
    private func move(_ step: Int, extend: Bool) {
        let items = model.shelf
        let current = (cursor ?? anchor).flatMap { id in items.firstIndex { $0.id == id } }
            ?? (step > 0 ? -1 : items.count)
        let next = min(max(current + step, 0), items.count - 1)
        let item = items[next]
        cursor = item.id
        if extend, let anchor, let from = items.firstIndex(where: { $0.id == anchor }) {
            model.selection = Set(items[min(from, next)...max(from, next)].map(\.id))
        } else {
            model.selection = [item.id]
            anchor = item.id
        }
        withAnimation(Desvan.Motion.pick(.spring(duration: 0.3, bounce: 0), reduceMotion: reduceMotion)) {
            position.scrollTo(id: item.id, anchor: .center)
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
            cursor = item.id
        } else if flags.contains(.shift), let anchor,
                  let from = model.shelf.firstIndex(where: { $0.id == anchor }),
                  let to = model.shelf.firstIndex(where: { $0.id == item.id }) {
            model.selection = Set(model.shelf[min(from, to)...max(from, to)].map(\.id))
            cursor = item.id
        } else {
            model.selection = [item.id]
            anchor = item.id
            cursor = item.id
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
    @State private var landing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Things keep the same comfortable width whatever the notch is set to: the row scrolls instead of stretching.
    static let width: CGFloat = 110
    static let thumbnailSide: CGFloat = 76
    /// Height of the space things stand in; their base sinks 3 pt into the plank's top surface (depth).
    static let thingHeight: CGFloat = thumbnailSide + 8
    static let sink: CGFloat = 3
    /// Wall showing between the plank's front edge and the name written under it.
    static let wallGap: CGFloat = 5

    /// The name written under the plank. Files lose their extension (the thumbnail already says what it is) and
    /// truncate in the middle so the end (dates, versions) survives; notes keep their beginning.
    private var name: String {
        switch item.kind {
        case .file:
            let stem = (item.displayName as NSString).deletingPathExtension
            return stem.isEmpty ? item.displayName : stem
        case .link, .text:
            return item.displayName.replacingOccurrences(of: "\n", with: " ")
        }
    }

    private var truncation: Text.TruncationMode {
        if case .text = item.kind { return .tail }
        return .middle
    }

    /// Things left on a shelf, not a grid: a fixed, stable tilt of ±1.5° per item.
    private var tilt: Double { Desvan.jitter(item.id) * 1.5 }
    private var lift: CGFloat { isSelected ? 2 : (isHovering ? 1 : 0) }

    var body: some View {
        VStack(spacing: 0) {
            thing
                .frame(width: Self.width, height: Self.thingHeight, alignment: .bottom)
            Color.clear.frame(height: DesvanPlank.height - Self.sink + Self.wallGap) // the plank and a little wall
            Text(name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Desvan.Palette.bulb : (isHovering ? Desvan.Palette.paper : Desvan.Palette.paperSecondary))
                .shadow(color: isSelected ? Desvan.Palette.bulb.opacity(0.45) : .clear, radius: 5)
                .lineLimit(1)
                .truncationMode(truncation)
                .padding(.horizontal, 4)
                .frame(width: Self.width)
        }
        .frame(width: Self.width)
        .padding(.top, DesvanShelfView.plankY + Self.sink - Self.thingHeight)
        .contentShape(Rectangle())
        .help(help)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .onTapGesture(perform: onClick)
        .shelfDraggable(items: menuItems) { _, departed in
            // Moved to a folder or dropped on the Trash → it's gone from here too. Copied elsewhere → it stays.
            if !departed.isEmpty { model.actions.removeDeparted(Set(departed.map(\.id))) }
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

    /// Full name and details, on hover.
    private var help: String {
        "\(item.displayName)\n\(NotchFormat.subtitle(for: item))"
    }

    /// The thumbnail resting on the plank, with its contact shadow.
    private var thing: some View {
        ZStack(alignment: .bottom) {
            contactShadow
            DesvanThumbnail(item: item, side: Self.thumbnailSide)
                .rotationEffect(.degrees(tilt), anchor: .bottom)
                .shadow(color: isSelected ? Desvan.Palette.bulb.opacity(0.4) : .clear, radius: 8, y: -1)
                .offset(y: -lift)
                .animation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion), value: lift)
                .keyframeAnimator(initialValue: LandingPose(), trigger: landing) { content, pose in
                    content
                        .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
                        .rotationEffect(.degrees(pose.rotation), anchor: .bottom)
                        .offset(y: pose.offsetY)
                } keyframes: { _ in
                    KeyframeTrack(\.offsetY) {
                        // Falls from above the card, accelerating (≈ y = t²).
                        MoveKeyframe(-104)
                        LinearKeyframe(-91, duration: 0.07)
                        LinearKeyframe(-57, duration: 0.07)
                        LinearKeyframe(0, duration: 0.07)
                    }
                    KeyframeTrack(\.rotation) {
                        MoveKeyframe(-4)
                        LinearKeyframe(-3, duration: 0.21)
                        SpringKeyframe(0, duration: 0.5, spring: .init(duration: 0.5, bounce: 0.35))
                    }
                    KeyframeTrack(\.scaleX) {
                        LinearKeyframe(1, duration: 0.21)
                        LinearKeyframe(1.05, duration: 0.06) // squash on impact
                        SpringKeyframe(1, duration: 0.5, spring: .init(duration: 0.5, bounce: 0.35))
                    }
                    KeyframeTrack(\.scaleY) {
                        LinearKeyframe(1, duration: 0.21)
                        LinearKeyframe(0.93, duration: 0.06)
                        SpringKeyframe(1, duration: 0.5, spring: .init(duration: 0.5, bounce: 0.35))
                    }
                }
        }
        .background(alignment: .bottom) {
            // Selected: the bulb's light pools on the board under it.
            Ellipse()
                .fill(RadialGradient(colors: [Desvan.Palette.bulb.opacity(isSelected ? 0.32 : 0), .clear],
                                     center: .center, startRadius: 0, endRadius: 44))
                .frame(width: 96, height: 20)
                .offset(y: 6)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }

    /// Contact shadow on the plank's top surface: a tight dark core and a wider, softer penumbra. It stays on the
    /// board: lifting (hover, selection) spreads it and makes it lighter, and it gathers as a falling thing arrives.
    private var contactShadow: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.4 - 0.06 * lift))
                .frame(width: 72 + 3 * lift, height: 8 + lift)
                .blur(radius: 2.5 + lift)
            Ellipse()
                .fill(.black.opacity(0.8 - 0.2 * lift))
                .frame(width: 56, height: 3)
                .blur(radius: 1 + 0.6 * lift)
        }
        .offset(y: 2.5)
        .animation(Desvan.Motion.pick(.spring(duration: 0.2, bounce: 0), reduceMotion: reduceMotion), value: lift)
        .keyframeAnimator(initialValue: 1.0, trigger: landing) { content, presence in
            content.opacity(presence).scaleEffect(x: 0.5 + 0.5 * presence, y: 1)
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(0.1)
                CubicKeyframe(1, duration: 0.21)
            }
        }
        .allowsHitTesting(false)
    }

    /// Falls from above, squashes on the plank and settles.
    private func land() {
        guard !reduceMotion else { return }
        landing.toggle()
    }

    @ViewBuilder
    private var contextMenu: some View {
        let items = menuItems()
        Button("Open") { items.forEach(model.actions.open) }
        if items.contains(where: { $0.fileURL != nil }) {
            Button("Show in Finder") { model.actions.revealInFinder(items) }
            Button("Quick Look") { model.actions.quickLook(items) }
        }
        Divider()
        Button(items.count > 1 ? "Take \(items.count) things down" : "Take it down", role: .destructive) {
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
                DesvanNote(text: text, scale: side / 64)
            case let .link(url):
                DesvanPostcard(host: url.host(percentEncoded: false) ?? url.absoluteString, scale: side / 64)
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

/// A paper note held with a strip of masking tape. Drawn at `scale` × its 64 pt design size.
private struct DesvanNote: View {
    let text: String
    var scale: CGFloat = 1

    var body: some View {
        let k = scale
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: 7.5 * k, weight: .medium))
                .foregroundStyle(Desvan.Palette.ink)
                .lineSpacing(1 * k)
                .lineLimit(5)
                .padding(.horizontal, 6 * k)
                .padding(.top, 9 * k)
            Spacer(minLength: 0)
        }
        .frame(width: 54 * k, height: 60 * k, alignment: .topLeading)
        .clipped()
        .background {
            Rectangle()
                .fill(Desvan.Palette.paper)
                .overlay {
                    // Faint ruled lines.
                    VStack(spacing: 9.5 * k) {
                        ForEach(0..<6, id: \.self) { _ in
                            Rectangle().fill(Desvan.Palette.sky.opacity(0.25)).frame(height: 0.5)
                        }
                    }
                    .padding(.top, 16 * k)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Desvan.Palette.tape.opacity(0.85))
                .frame(width: 26 * k, height: 8 * k)
                .rotationEffect(.degrees(-4))
                .offset(y: -4 * k)
        }
        .accessibilityHidden(true)
    }
}

/// A postcard for a link: the host written on it and a stamp in the link colour. Drawn at `scale` × 64 pt.
private struct DesvanPostcard: View {
    let host: String
    var scale: CGFloat = 1

    var body: some View {
        let k = scale
        VStack(alignment: .leading, spacing: 3 * k) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3 * k) {
                    Capsule().fill(Desvan.Palette.ink.opacity(0.25)).frame(width: 22 * k, height: 1.5)
                    Capsule().fill(Desvan.Palette.ink.opacity(0.25)).frame(width: 16 * k, height: 1.5)
                }
                .padding(.top, 3 * k)
                Spacer(minLength: 0)
                ZStack {
                    RoundedRectangle(cornerRadius: 1.5).fill(Desvan.Palette.lavender)
                    Image(systemName: "link")
                        .font(.system(size: 8 * k, weight: .bold))
                        .foregroundStyle(Desvan.Palette.ink.opacity(0.8))
                }
                .frame(width: 15 * k, height: 17 * k)
                .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [1.5, 1])))
            }
            Spacer(minLength: 0)
            Text(host)
                .font(.system(size: 8 * k, weight: .semibold))
                .foregroundStyle(Desvan.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(6 * k)
        .frame(width: 70 * k, height: 48 * k)
        .background {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(hex: 0xEFE5D2))
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Empty state

/// «The shelf is empty.» The bare plank with the house standing on it, and one warm sentence.
struct DesvanShelfEmptyState: View {
    var isReceiving = false
    var problem: String?

    var body: some View {
        ZStack(alignment: .top) {
            // The bare board, running wall to wall like the full shelf's.
            DesvanPlank()
                .padding(.top, DesvanShelfView.plankY)
            HStack(alignment: .center, spacing: 16) {
                DesvanHouseMark(size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title)
                        .font(Desvan.Typeface.display(19, weight: 600))
                        .foregroundStyle(problem == nil ? Desvan.Palette.paper : Desvan.Palette.warning)
                    Text(verbatim: detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Clear of the card's rounded edges; a narrow notch wraps the sentence instead of running into them.
            .padding(.horizontal, 20)
            .frame(height: DesvanShelfView.plankY)
            .padding(.top, 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if isReceiving { return String(localized: "Putting it up…") }
        if problem != nil { return String(localized: "Something got left half done.") }
        return String(localized: "The shelf is empty.")
    }

    private var detail: String {
        if isReceiving { return String(localized: "Some things take a moment to arrive.") }
        return problem ?? String(localized: "Put anything up here you want within reach for a while.")
    }
}

// MARK: - Mouse wheel

/// A plain mouse only has a vertical wheel, and SwiftUI's horizontal `ScrollView` ignores it. This invisible
/// AppKit view watches the scroll wheel while the pointer is over the shelf and turns a vertical turn into a
/// sideways move of the row. Trackpad gestures that are mostly horizontal are left untouched, and so is every
/// event the shelf can't use (`onWheel` returns false), which then continues on its way.
///
/// It never takes a click: `hitTest` returns nil, so selection and dragging out are unaffected.
struct DesvanWheelCatcher: NSViewRepresentable {
    /// Called with the wheel's movement in points. Returns true when the shelf used it.
    var onWheel: (CGFloat) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = WheelView()
        view.onWheel = onWheel
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WheelView)?.onWheel = onWheel
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? WheelView)?.stop()
    }

    private final class WheelView: NSView {
        var onWheel: ((CGFloat) -> Bool)?
        private var monitor: Any?

        /// Lines to points for a notched (non-precise) wheel: about one thing per notch.
        private static let lineHeight: CGFloat = 16

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stop() } else { start() }
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                // Only plain values cross into the main actor: `NSEvent` itself is not Sendable.
                let turn = Turn(
                    x: event.scrollingDeltaX,
                    y: event.scrollingDeltaY,
                    precise: event.hasPreciseScrollingDeltas,
                    location: event.locationInWindow,
                    windowNumber: event.windowNumber
                )
                let used = MainActor.assumeIsolated { self?.handle(turn) ?? false }
                return used ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ turn: Turn) -> Bool {
            guard let window, window.windowNumber == turn.windowNumber, let onWheel else { return false }
            guard turn.y != 0, abs(turn.y) > abs(turn.x) else { return false }
            guard bounds.contains(convert(turn.location, from: nil)) else { return false }
            return onWheel(turn.precise ? turn.y : turn.y * Self.lineHeight)
        }

        /// One turn of the wheel, in values that can cross actors.
        private struct Turn: Sendable {
            var x: CGFloat
            var y: CGFloat
            var precise: Bool
            var location: CGPoint
            var windowNumber: Int
        }
    }
}
