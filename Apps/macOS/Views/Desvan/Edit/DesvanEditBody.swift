import AltilloDesign
import SwiftUI

/// Edit mode's body (200 pt, PLAN §4): the tabs to arrange, the box of put-away sections, what the selected ear
/// shows, and the presets. Every change is live: the tabs above, the ears and Settings follow as you go.
///
/// Four compact rows, each with its name on the left. The ears themselves are slots in the band beside the notch
/// (`DesvanEditBand`); the chips here fill whichever one is selected, or can be dragged onto either.
struct DesvanEditBody: View {
    let model: NotchModel
    let session: NotchEditSession

    @Namespace private var namespace

    /// Wide enough for "Right ear" and its arrow at full size.
    static let captionWidth: CGFloat = 70
    static let rowSpacing: CGFloat = 12
    static let topPadding: CGFloat = 4
    /// The put-away box and the ear chips: 26–28 pt pieces (28 pt targets) with room around them.
    static let chipRowHeight: CGFloat = 32
    static let presetsHeight: CGFloat = 46

    // 200 pt budget (`NotchChrome.ExpandedContent.editing`): 4 (top) + 50 (tabs: 42 tiles + 8 for the "−" badges)
    // + 32 (put away) + 32 (ears) + 46 (presets) + 3 × 12 (spacing) = 200.

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            row { caption(Text("Tabs")).padding(.top, DesvanEditStrip.height - DesvanEditStrip.tileHeight) } content: {
                DesvanEditStrip(model: model, session: session, namespace: namespace)
            }
            .frame(height: DesvanEditStrip.height)
            .zIndex(3)

            row { caption(Text("Put away")) } content: {
                DesvanEditTray(model: model, session: session, namespace: namespace)
            }
            .frame(height: Self.chipRowHeight)
            .zIndex(2)

            row { earCaption } content: {
                DesvanEditEarsRow(model: model, session: session)
            }
            .frame(height: Self.chipRowHeight)
            .zIndex(1)

            row { caption(Text("Presets")) } content: {
                DesvanEditPresets(model: model, session: session)
            }
            .frame(height: Self.presetsHeight)
        }
        .padding(.top, Self.topPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: model.settings.modules) { _, modules in
            // A section put away (or dropped by a preset) can't stay the one the notch opens on.
            if !modules.contains(model.module) { model.jump(to: .shelf) }
        }
    }

    private func row<Caption: View, Content: View>(
        @ViewBuilder caption: () -> Caption, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            caption()
                .frame(width: Self.captionWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func caption(_ text: Text) -> some View {
        text
            .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
            .foregroundStyle(Desvan.Palette.paperTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// Names the ear the chips fill, pointing up at it.
    private var earCaption: some View {
        HStack(spacing: 2) {
            Image(systemName: session.selectedEar == .left ? "arrow.up.left" : "arrow.up.right")
                .font(.system(size: 10.5, weight: .bold))
            Text(session.selectedEar.title)
        }
        .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
        .foregroundStyle(Desvan.Palette.bulb.opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .contentTransition(.opacity)
        .accessibilityHidden(true)
    }
}

// MARK: - Tabs

/// The tab strip, editable: every section as a small plaque that jiggles (a dashed outline with Reduce Motion),
/// drags sideways to reorder, down into the box to put away, or up onto an ear. "−" puts one away. The shelf is
/// pinned first.
///
/// Keyboard: ← → walk the tabs, Space picks the focused one up, ← → then move it, Space or Return drops it.
private struct DesvanEditStrip: View {
    let model: NotchModel
    let session: NotchEditSession
    let namespace: Namespace.ID

    /// The strip takes keyboard focus as a whole (like the shelf's row); `cursor` is the tab the arrows are on.
    @FocusState private var isFocused: Bool
    @State private var cursor: NotchModule?
    /// Picked up with Space, moved with the arrows.
    @State private var picked: NotchModule?
    /// Focus rings only show once the keyboard is in use (a click shouldn't leave one behind).
    @State private var usesKeyboard = false
    /// True while a pointer drag is in flight; SwiftUI resets it even when the drag is cancelled (no `onEnded`).
    @GestureState private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 50
    static let tileHeight: CGFloat = 42
    static let spacing: CGFloat = 5
    /// Room for the longest name ("Now playing") beside its icon.
    static let maxTile: CGFloat = 108

    var body: some View {
        GeometryReader { proxy in
            let modules = model.settings.modules
            let width = Self.tileWidth(count: modules.count, in: proxy.size.width)
            let pitch = width + Self.spacing
            HStack(spacing: Self.spacing) {
                ForEach(Array(modules.enumerated()), id: \.element) { index, module in
                    tile(module, index: index, count: modules.count, width: width, pitch: pitch)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { press in
            usesKeyboard = true
            step(press.key == .leftArrow ? -1 : 1)
            return .handled
        }
        .onKeyPress(.space) {
            usesKeyboard = true
            togglePick()
            return .handled
        }
        .onKeyPress(.return) {
            guard picked != nil else { return .ignored }
            drop()
            return .handled
        }
        .onKeyPress(.escape) {
            if picked != nil { drop() } else { model.actions.send(.escape) }
            return .handled
        }
        .onChange(of: isDragging) { _, dragging in
            guard !dragging else { return }
            // A cancelled drag never reaches `onEnded`: settle the tab back and close the undo step here.
            Task { @MainActor in
                guard session.tileDrag != nil else { return }
                withAnimation(Desvan.Motion.pick(Desvan.Motion.settle, reduceMotion: reduceMotion)) {
                    session.tileDrag = nil
                }
                session.endGesture(in: model.settings)
            }
        }
        .onAppear {
            // Ready for the keyboard: the first tab that can move (the shelf can't).
            cursor = model.settings.modules.first { !$0.isAlwaysOn } ?? model.settings.modules.first
            isFocused = true
        }
        .onChange(of: model.settings.modules) { _, modules in
            // The tab under the cursor was put away: stay on a neighbour.
            if let cursor, !modules.contains(cursor) { self.cursor = modules.last }
        }
    }

    /// Equal widths (so a drag knows where each slot is), as roomy as the strip allows, never wider than a plaque.
    static func tileWidth(count: Int, in width: CGFloat) -> CGFloat {
        guard count > 0 else { return maxTile }
        return min(maxTile, floor((width - CGFloat(count - 1) * spacing) / CGFloat(count)))
    }

    private func tile(_ module: NotchModule, index: Int, count: Int, width: CGFloat, pitch: CGFloat) -> some View {
        let drag = session.tileDrag?.module == module ? session.tileDrag : nil
        let offset = drag.map { drag in
            CGSize(width: drag.translation.width - CGFloat(index - drag.startIndex) * pitch,
                   height: drag.translation.height)
        } ?? .zero
        return DesvanEditTile(
            module: module,
            width: width,
            showsTitle: width >= 74,
            isLifted: drag != nil || picked == module,
            showsFocus: usesKeyboard && isFocused && cursor == module,
            seed: index,
            namespace: namespace,
            putAway: { putAway(module) }
        )
        .offset(offset)
        .zIndex(drag != nil || picked == module ? 1 : 0)
        // The dragged tab stays under the pointer while the others make room; it only springs home when let go.
        .transaction { transaction in
            if drag != nil { transaction.animation = nil }
        }
        .gesture(dragGesture(for: module, pitch: pitch))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(module.title)
        .accessibilityValue(String(localized: "Tab \(index + 1) of \(count)"))
        .accessibilityHint(module.isAlwaysOn ? String(localized: "Always first") : String(localized: "Drag to reorder"))
        .accessibilityActions {
            if session.canMove(module, by: -1, in: model.settings) {
                Button("Move left") { move(module, by: -1) }
            }
            if session.canMove(module, by: 1, in: model.settings) {
                Button("Move right") { move(module, by: 1) }
            }
            if !module.isAlwaysOn {
                Button("Put away") { putAway(module) }
            }
        }
    }

    // MARK: Pointer

    private func dragGesture(for module: NotchModule, pitch: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(DesvanEdit.space))
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                let settings = model.settings
                if session.tileDrag?.module != module {
                    guard let index = settings.modules.firstIndex(of: module) else { return }
                    picked = nil
                    session.beginGesture(in: settings)
                    withAnimation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion)) {
                        session.tileDrag = .init(module: module, startIndex: index, translation: .zero,
                                                 location: value.location)
                    }
                }
                guard var drag = session.tileDrag else { return }
                drag.translation = value.translation
                drag.location = value.location
                session.tileDrag = drag
                // Along the strip it reorders; heading for an ear or the box, the others stay put.
                guard session.target(at: value.location) == nil, !module.isAlwaysOn else { return }
                let target = drag.startIndex + Int((value.translation.width / pitch).rounded())
                withAnimation(Desvan.Motion.pick(Desvan.Motion.section, reduceMotion: reduceMotion)) {
                    if session.move(module, to: target, in: settings) { model.actions.haptic(.snap) }
                }
            }
            .onEnded { value in
                let settings = model.settings
                withAnimation(Desvan.Motion.pick(Desvan.Motion.settle, reduceMotion: reduceMotion)) {
                    switch session.target(at: value.location) {
                    case .tray:
                        if session.putAway(module, in: settings) { model.actions.haptic(.snap) }
                    case let .ear(side):
                        if let ear = NotchEditSession.earContent(for: module), ear.isAvailable,
                           session.assign(ear, to: side, in: settings) {
                            model.actions.haptic(.snap)
                        }
                    case nil:
                        break
                    }
                    session.tileDrag = nil
                }
                session.endGesture(in: settings)
            }
    }

    // MARK: Keyboard and VoiceOver

    private func step(_ direction: Int) {
        let modules = model.settings.modules
        if let picked {
            withAnimation(Desvan.Motion.pick(Desvan.Motion.section, reduceMotion: reduceMotion)) {
                if session.move(picked, by: direction, in: model.settings) {
                    model.actions.haptic(.snap)
                } else {
                    model.bumpEdge(direction)
                }
            }
            return
        }
        guard let current = cursor, let index = modules.firstIndex(of: current) else {
            cursor = modules.first
            return
        }
        let target = index + direction
        if modules.indices.contains(target) {
            withAnimation(Desvan.Motion.hover) { cursor = modules[target] }
        } else {
            model.bumpEdge(direction)
        }
    }

    private func togglePick() {
        if picked != nil {
            drop()
            return
        }
        guard let module = cursor, !module.isAlwaysOn else { return }
        session.beginGesture(in: model.settings)
        withAnimation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion)) { picked = module }
        model.actions.haptic(.snap)
    }

    private func drop() {
        withAnimation(Desvan.Motion.pick(Desvan.Motion.settle, reduceMotion: reduceMotion)) { picked = nil }
        session.endGesture(in: model.settings)
    }

    private func move(_ module: NotchModule, by offset: Int) {
        withAnimation(Desvan.Motion.pick(Desvan.Motion.section, reduceMotion: reduceMotion)) {
            if session.move(module, by: offset, in: model.settings) { model.actions.haptic(.snap) }
        }
    }

    private func putAway(_ module: NotchModule) {
        if picked == module { drop() }
        withAnimation(Desvan.Motion.pick(Desvan.Motion.section, reduceMotion: reduceMotion)) {
            if session.putAway(module, in: model.settings) { model.actions.haptic(.snap) }
        }
    }
}

/// One section in the editable strip: a little wooden plaque with its icon (and name, when there's room).
private struct DesvanEditTile: View {
    let module: NotchModule
    let width: CGFloat
    let showsTitle: Bool
    let isLifted: Bool
    let showsFocus: Bool
    /// Its place in the strip, so neighbours never jiggle in step.
    let seed: Int
    let namespace: Namespace.ID
    let putAway: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if showsTitle {
                // The name only where it fits at full size; a plaque too narrow for it keeps just its icon.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        icon
                        Text(module.title)
                            .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    icon
                }
            } else {
                icon
            }
        }
        .foregroundStyle(Desvan.Palette.paper)
        .shadow(color: .black.opacity(0.7), radius: 0, y: -0.5)
        .padding(.horizontal, 4)
        .frame(width: width, height: DesvanEditStrip.tileHeight)
        .background {
            shape
                .fill(LinearGradient(colors: [Color(hex: 0x3B3026), Color(hex: 0x2B231B)],
                                     startPoint: .top, endPoint: .bottom))
                .desvanTexture(DesvanTexture.wood, opacity: 0.6, in: shape)
                .overlay { rim(shape) }
                .overlay { shape.inset(by: 1).strokeBorder(.black.opacity(0.4), lineWidth: 0.5) }
                .shadow(color: .black.opacity(isLifted ? 0.75 : 0.6), radius: isLifted ? 7 : 1.5, y: isLifted ? 4 : 1)
                .shadow(color: Desvan.Palette.bulb.opacity(isLifted ? 0.3 : 0), radius: 8)
        }
        // Before the badge: a content shape limits hit testing underneath it, and the "−" reaches past the corner.
        .contentShape(shape)
        .overlay(alignment: .topLeading) {
            if !module.isAlwaysOn { minusBadge.offset(x: -3, y: -3) }
        }
        .overlay(alignment: .topTrailing) {
            if module.isAlwaysOn {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Desvan.Palette.kraft)
                    .rotationEffect(.degrees(30))
                    .offset(x: -4, y: 4)
                    .help("The shelf is always first")
            }
        }
        .scaleEffect(isLifted && !reduceMotion ? 1.08 : 1)
        // Lifting only pauses the rock: swapping the view's structure mid-drag would cancel the pointer's gesture.
        .modifier(DesvanJiggle(isEnabled: !module.isAlwaysOn && !reduceMotion, isPaused: isLifted, seed: seed))
        .matchedGeometryEffect(id: module, in: namespace)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .help(module.isAlwaysOn ? String(localized: "\(module.title): always first") : module.title)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    @ViewBuilder
    private var icon: some View {
        if module.isAlwaysOn {
            DesvanHouseMark(size: 16, lit: 1)
        } else {
            Image(systemName: module.symbol)
                .font(.system(size: 15.5, weight: .medium))
                .symbolRenderingMode(.hierarchical)
        }
    }

    /// Layered rather than switched, so the tile keeps one structure (and its drag) whatever state it's in.
    private func rim(_ shape: RoundedRectangle) -> some View {
        let lit = isLifted || showsFocus
        let brass = module.isAlwaysOn && !lit
        // No jiggle with Reduce Motion: a dashed edge says "you can move this" instead.
        let dashed = reduceMotion && !module.isAlwaysOn && !lit
        let plain = !lit && !brass && !dashed
        return ZStack {
            shape.strokeBorder(Desvan.Palette.bulb.opacity(0.9), lineWidth: 1.2).opacity(lit ? 1 : 0)
            shape.strokeBorder(DesvanEditBrass.rim, lineWidth: 1).opacity(brass ? 1 : 0)
            shape.strokeBorder(Desvan.Palette.paper.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                .opacity(dashed ? 1 : 0)
            shape.strokeBorder(Desvan.Palette.paper.opacity(isHovering ? 0.28 : 0.16), lineWidth: 0.75)
                .opacity(plain ? 1 : 0)
        }
    }

    /// "−": into the box. A 16 pt badge with a 28 pt target (4 pt of it over the neighbour's rounded corner).
    private var minusBadge: some View {
        Button(action: putAway) {
            Image(systemName: "minus")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Desvan.Palette.ink)
                .frame(width: 16, height: 16)
                .background {
                    Circle()
                        .fill(Desvan.Palette.kraft)
                        .overlay { Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.5) }
                        .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
                }
                .desvanHitTarget()
        }
        .buttonStyle(DesvanEditPressStyle())
        .help("Put \(module.title) away")
        .accessibilityLabel("Put \(module.title) away")
    }
}

/// The iOS "jiggle": a slight rock (±1.4°) with a little bob, each tab on its own period so they never move in step.
/// `isPaused` (a lifted tab) holds it still without changing the view's structure.
private struct DesvanJiggle: ViewModifier {
    let isEnabled: Bool
    let isPaused: Bool
    let seed: Int

    func body(content: Content) -> some View {
        if isEnabled {
            let period = 0.26 + Double(seed % 3) * 0.025
            let sign: Double = seed.isMultiple(of: 2) ? 1 : -1
            let amount = isPaused ? 0.0 : 1.0
            content.keyframeAnimator(initialValue: Rock(), repeating: true) { content, rock in
                content
                    .rotationEffect(.degrees(rock.angle * amount))
                    .offset(y: rock.bob * amount)
            } keyframes: { _ in
                KeyframeTrack(\.angle) {
                    CubicKeyframe(1.4 * sign, duration: period * 0.25)
                    CubicKeyframe(-1.4 * sign, duration: period * 0.5)
                    CubicKeyframe(0, duration: period * 0.25)
                }
                KeyframeTrack(\.bob) {
                    CubicKeyframe(-0.3, duration: period * 0.5)
                    CubicKeyframe(0, duration: period * 0.5)
                }
            }
        } else {
            content
        }
    }

    private struct Rock {
        var angle = 0.0
        var bob: CGFloat = 0
    }
}

// MARK: - Put away

/// The cardboard box of sections that aren't in the notch. Tap one to put it back (at the end of the tabs);
/// drop a tab here to put it away.
private struct DesvanEditTray: View {
    let model: NotchModel
    let session: NotchEditSession
    let namespace: Namespace.ID

    @State private var width: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let away = NotchModule.allCases.filter { !model.settings.isEnabled($0) }
        let targeted = isTargeted
        let titles = width >= CGFloat(away.count) * 104
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 5) {
            ForEach(away) { module in
                chip(module, titles: titles)
            }
            if away.isEmpty {
                Text(targeted ? "Let go to put it away" : "Nothing put away. Tap − on a tab.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(targeted ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
                    .lineLimit(1)
                    .padding(.leading, 6)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .frame(maxHeight: .infinity)
        .background {
            // Kraft cardboard, a little open: warmer (and lit) while a tab hovers over it.
            shape
                .fill(Desvan.Palette.cardboard.opacity(targeted ? 0.22 : 0.09))
                .overlay {
                    shape.strokeBorder(
                        targeted ? Desvan.Palette.bulb.opacity(0.9) : Desvan.Palette.kraft.opacity(0.35),
                        style: StrokeStyle(lineWidth: targeted ? 1.2 : 0.9, dash: targeted ? [] : [3, 2.5])
                    )
                }
                .shadow(color: Desvan.Palette.bulb.opacity(targeted ? 0.4 : 0), radius: 6)
        }
        .animation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion), value: targeted)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(DesvanEdit.space))
        } action: { frame in
            width = frame.width
            session.targetFrames[.tray] = frame
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Put away")
    }

    private var isTargeted: Bool {
        guard let drag = session.tileDrag, !drag.module.isAlwaysOn else { return false }
        return session.target(at: drag.location) == .tray
    }

    private func chip(_ module: NotchModule, titles: Bool) -> some View {
        Button {
            withAnimation(Desvan.Motion.pick(Desvan.Motion.section, reduceMotion: reduceMotion)) {
                if session.addBack(module, in: model.settings) { model.actions.haptic(.snap) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Desvan.Palette.bulb)
                Image(systemName: module.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                if titles {
                    Text(module.title)
                        .font(Desvan.Typeface.rounded(12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Desvan.Palette.paperSecondary)
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background {
                Capsule()
                    .fill(Desvan.Palette.wood.opacity(0.9))
                    .overlay { Capsule().strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.75) }
            }
            .desvanHitTarget()
            .matchedGeometryEffect(id: module, in: namespace)
        }
        .buttonStyle(DesvanEditPressStyle())
        .transition(.scale(scale: 0.6).combined(with: .opacity))
        .help("Put \(module.title) back in the notch")
        .accessibilityLabel(module.title)
        .accessibilityHint("Adds it back to the tabs")
        .accessibilityAction(named: "Add") {
            withAnimation(Desvan.Motion.pick(Desvan.Motion.section, reduceMotion: reduceMotion)) {
                if session.addBack(module, in: model.settings) { model.actions.haptic(.snap) }
            }
        }
    }
}

// MARK: - Ears

/// What can go in an ear, as chips: tap one to put it in the selected ear, or drag it onto either. Usage and
/// agents are shown but dimmed until their modules exist. On the right, when the ears show.
private struct DesvanEditEarsRow: View {
    let model: NotchModel
    let session: NotchEditSession

    var body: some View {
        ViewThatFits(in: .horizontal) {
            layout(titles: true, visibility: .long)
            layout(titles: true, visibility: .short)
            layout(titles: false, visibility: .short)
            layout(titles: false, visibility: .tiny)
        }
    }

    private func layout(titles: Bool, visibility: DesvanEditVisibility.Length) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(EarContent.allCases) { content in
                    DesvanEarChip(content: content, titles: titles, model: model, session: session)
                }
            }
            Spacer(minLength: 0)
            DesvanEditVisibility(model: model, session: session, length: visibility)
        }
    }
}

private struct DesvanEarChip: View {
    let content: EarContent
    let titles: Bool
    let model: NotchModel
    let session: NotchEditSession

    @State private var isHovering = false
    @GestureState private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let selectedSide = session.selectedEar
        let isChosen = session.ear(selectedSide, in: model.settings) == content
        let otherSide = session.ear(selectedSide.opposite, in: model.settings) == content && content != .none
        let isDragged = session.earDrag?.content == content
        Button(action: assign) {
            DesvanEarChipLabel(content: content, titles: titles, isChosen: isChosen, isInOtherEar: otherSide,
                               isHovering: isHovering)
                .opacity(isDragged ? 0.35 : 1)
                .desvanHitTarget()
        }
        .buttonStyle(DesvanEditPressStyle())
        .disabled(!content.isAvailable)
        .simultaneousGesture(dragGesture, including: content.isAvailable ? .all : .none)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .onChange(of: isDragging) { _, dragging in
            // A cancelled drag never reaches `onEnded`: drop the ghost.
            guard !dragging else { return }
            Task { @MainActor in
                if session.earDrag?.content == content { withAnimation(Desvan.Motion.fade) { session.earDrag = nil } }
            }
        }
        .help(help)
        .accessibilityLabel(content.title)
        .accessibilityValue(accessibilityValue(isChosen: isChosen, inOther: otherSide))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityActions {
            if content.isAvailable {
                Button("Put in the left ear") { assign(to: .left) }
                Button("Put in the right ear") { assign(to: .right) }
            }
        }
    }

    private var help: String {
        content.isAvailable
            ? String(localized: "\(content.title): tap for the \(session.selectedEar == .left ? String(localized: "left") : String(localized: "right")) ear, or drag onto one")
            : String(localized: "\(content.title): coming soon")
    }

    private func accessibilityValue(isChosen: Bool, inOther: Bool) -> String {
        if !content.isAvailable { return String(localized: "Coming soon") }
        if isChosen { return String(localized: "In the \(session.selectedEar.title.lowercased())") }
        if inOther { return String(localized: "In the \(session.selectedEar.opposite.title.lowercased())") }
        return ""
    }

    private func assign() { assign(to: session.selectedEar) }

    private func assign(to side: EarSide) {
        withAnimation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion)) {
            if session.assign(content, to: side, in: model.settings) { model.actions.haptic(.snap) }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(DesvanEdit.space))
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                session.earDrag = .init(content: content, location: value.location)
            }
            .onEnded { value in
                let target = session.target(at: value.location)
                withAnimation(Desvan.Motion.pick(Desvan.Motion.settle, reduceMotion: reduceMotion)) {
                    if case let .ear(side) = target, session.assign(content, to: side, in: model.settings) {
                        model.actions.haptic(.snap)
                    }
                    session.earDrag = nil
                }
            }
    }
}

/// A chip's face, shared by the chip and the copy that follows the pointer while dragging.
struct DesvanEarChipLabel: View {
    let content: EarContent
    var titles: Bool
    var isChosen = false
    var isInOtherEar = false
    var isHovering = false

    static let height: CGFloat = 28

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: content.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                if titles {
                    Text(content.shortTitle)
                        .font(Desvan.Typeface.rounded(12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            // Not there yet: dimmed, and (with room) a little kraft tag that says so.
            .opacity(content.isAvailable ? 1 : 0.4)
            if !content.isAvailable, titles {
                Text("soon")
                    .font(Desvan.Typeface.rounded(11, weight: .bold))
                    .foregroundStyle(Desvan.Palette.ink)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Desvan.Palette.kraft.opacity(0.75)))
            }
        }
        .foregroundStyle(isChosen ? Desvan.Palette.paper : (isHovering ? Desvan.Palette.paper : Desvan.Palette.paperSecondary))
        .padding(.horizontal, titles ? 8 : 0)
        .frame(minWidth: DesvanHitTarget.minimum)
        .frame(height: Self.height)
        .background {
            if isChosen {
                shape
                    .fill(LinearGradient(colors: [Color(hex: 0x3B3026), Color(hex: 0x2B231B)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay { shape.strokeBorder(DesvanEditBrass.rim, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
            } else {
                shape
                    .fill(Desvan.Palette.paper.opacity(isHovering ? 0.09 : 0.04))
                    .overlay {
                        shape.strokeBorder(isInOtherEar ? Desvan.Palette.kraft.opacity(0.55) : Desvan.Palette.hairlineStrong,
                                           style: StrokeStyle(lineWidth: 0.75, dash: isInOtherEar ? [2.5, 2] : []))
                    }
            }
        }
        .contentShape(shape)
        .opacity(content.isAvailable ? 1 : 0.8)
    }
}

/// "Only when there's something" or "Always": a two-way switch in the band's wood.
private struct DesvanEditVisibility: View {
    enum Length { case long, short, tiny }

    let model: NotchModel
    let session: NotchEditSession
    let length: Length
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EarsVisibility.allCases) { visibility in
                segment(visibility)
            }
        }
        .padding(2)
        .background {
            Capsule()
                .fill(.black.opacity(0.35))
                .overlay { Capsule().strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.75) }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show the ears")
    }

    private func segment(_ visibility: EarsVisibility) -> some View {
        let isSelected = model.settings.earsVisibility == visibility
        return Button {
            withAnimation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion)) {
                if session.setVisibility(visibility, in: model.settings) { model.actions.haptic(.snap) }
            }
        } label: {
            Text(verbatim: title(visibility))
                .font(Desvan.Typeface.rounded(12, weight: .semibold))
                .foregroundStyle(isSelected ? Desvan.Palette.paper : Desvan.Palette.paperTertiary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: DesvanEarChipLabel.height - 4)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(LinearGradient(colors: [Color(hex: 0x3B3026), Color(hex: 0x2B231B)],
                                                 startPoint: .top, endPoint: .bottom))
                            .overlay { Capsule().strokeBorder(DesvanEditBrass.rim, lineWidth: 0.8) }
                    }
                }
                // With the switch's 2 pt rim: a 28 pt target.
                .desvanHitTarget()
        }
        .buttonStyle(DesvanEditPressStyle())
        .help(visibility.title)
        .accessibilityLabel(visibility.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func title(_ visibility: EarsVisibility) -> String {
        switch (length, visibility) {
        case (.long, _): visibility.title
        case (.short, .withActivity): String(localized: "When busy")
        case (.tiny, .withActivity): String(localized: "Auto")
        case (_, .always): String(localized: "Always")
        }
    }
}

// MARK: - Presets

/// Minimal, Developer, Everything: three small wooden cards. The one that matches what's set wears the brass rim;
/// tapping another applies it (Undo glows in the band for a few seconds, ⌘Z works too).
private struct DesvanEditPresets: View {
    let model: NotchModel
    let session: NotchEditSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let matching = model.settings.matchingPreset
        HStack(spacing: 6) {
            ForEach(NotchPreset.allCases) { preset in
                card(preset, isSelected: matching == preset)
            }
        }
    }

    private func card(_ preset: NotchPreset, isSelected: Bool) -> some View {
        Button {
            withAnimation(Desvan.Motion.pick(Desvan.Motion.section, reduceMotion: reduceMotion)) {
                if session.apply(preset, in: model.settings) { model.actions.haptic(.snap) }
            }
        } label: {
            DesvanPresetCard(preset: preset, isSelected: isSelected)
        }
        .buttonStyle(DesvanEditPressStyle())
        .help(preset.explanation)
        .accessibilityLabel(preset.title)
        .accessibilityHint(preset.explanation)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct DesvanPresetCard: View {
    let preset: NotchPreset
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(preset.title)
                    .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                    .foregroundStyle(isSelected || isHovering ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .heavy))
                        .foregroundStyle(Desvan.Palette.bulb)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            // 11 pt wherever it fits; all seven of Everything on a card at the narrowest notch need 10, then 9.
            ViewThatFits(in: .horizontal) {
                symbols(size: 11, spacing: 3.5)
                symbols(size: 10, spacing: 2.5)
                symbols(size: 9, spacing: 2)
            }
            .foregroundStyle(isSelected ? Desvan.Palette.bulb.opacity(0.8) : Desvan.Palette.paperSecondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            shape
                .fill(LinearGradient(colors: isSelected ? [Color(hex: 0x3B3026), Color(hex: 0x2B231B)]
                                                        : [Desvan.Palette.woodRaised, Desvan.Palette.wood],
                                     startPoint: .top, endPoint: .bottom))
                .desvanTexture(DesvanTexture.wood, opacity: isSelected ? 0.6 : 0.15, in: shape)
                .overlay {
                    if isSelected {
                        shape.strokeBorder(DesvanEditBrass.rim, lineWidth: 1)
                    } else {
                        shape.strokeBorder(Desvan.Palette.paper.opacity(isHovering ? 0.22 : 0.1), lineWidth: 0.75)
                    }
                }
                .shadow(color: .black.opacity(0.55), radius: 1.5, y: 1)
                .shadow(color: Desvan.Palette.bulb.opacity(isSelected ? 0.18 : 0), radius: 6)
        }
        .contentShape(shape)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
    }

    private func symbols(size: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(preset.modules) { module in
                Image(systemName: module.symbol)
                    .font(.system(size: size, weight: .semibold))
            }
        }
    }
}

// MARK: - Drag ghost

/// The ear chip following the pointer while it's dragged towards a slot.
struct DesvanEditDragGhost: View {
    let session: NotchEditSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let drag = session.earDrag {
            let targeted = session.target(at: drag.location) != nil
            DesvanEarChipLabel(content: drag.content, titles: true, isChosen: true)
                .scaleEffect(reduceMotion ? 1 : (targeted ? 0.9 : 1.08))
                .shadow(color: .black.opacity(0.7), radius: 8, y: 4)
                .shadow(color: Desvan.Palette.bulb.opacity(targeted ? 0.6 : 0.2), radius: 8)
                .position(drag.location)
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion), value: targeted)
        }
    }
}
