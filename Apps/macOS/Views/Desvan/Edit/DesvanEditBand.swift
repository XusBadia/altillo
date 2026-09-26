import AltilloDesign
import SwiftUI

/// Shared pieces of the notch's edit mode (PLAN §4: right-click › Customize…, like editing widgets on iOS).
enum DesvanEdit {
    /// Coordinate space of the open face while editing: drags and their drop targets (the ears, the box) meet here.
    static let space = "desvanEdit"
    /// `-customizeOnLaunch YES` opens the notch in edit mode right after launch (design reviews, screenshots).
    static let customizeOnLaunch = UserDefaults.standard.bool(forKey: "customizeOnLaunch")
    @MainActor static var didCustomizeOnLaunch = false
    /// How long the Undo button glows after a preset replaced the configuration.
    static let undoOffer: Duration = .seconds(6)
    /// A slot's well inside an ear (the pointer gets the whole ear).
    static let slotWidth: CGFloat = 48
    /// Height of the band's capsules (Undo, Done): they fit the island's 28 pt band with room to breathe.
    static let bandButtonHeight: CGFloat = 24
}

// MARK: - Band

/// The band beside the notch while editing: the two ears as slots, exactly where they sit on the resting notch
/// (either side of the camera, or of a small gap on the island), Undo (or the title) on the left, Done on the right.
struct DesvanEditBand: View {
    let model: NotchModel
    let chrome: NotchChrome
    let session: NotchEditSession

    /// Room kept between the silhouette's fillet and the band's content (as in the normal header).
    private static let inset: CGFloat = 6

    var body: some View {
        let ear = NotchChrome.earWidth
        let side = max(0, (chrome.size.width - 2 * (chrome.topRadius + Self.inset) - chrome.clearWidth - 2 * ear) / 2 - 3)
        HStack(spacing: 0) {
            DesvanEditLeading(model: model, session: session)
                .frame(width: side, alignment: .leading)
            Spacer(minLength: 0)
            DesvanEarSlot(side: .left, model: model, session: session, height: slotHeight)
                .frame(width: ear)
            Color.clear.frame(width: chrome.clearWidth)
            DesvanEarSlot(side: .right, model: model, session: session, height: slotHeight)
                .frame(width: ear)
            Spacer(minLength: 0)
            DesvanEditDoneButton(model: model)
                .frame(width: side, alignment: .trailing)
        }
        .frame(height: chrome.bandHeight)
        .padding(.horizontal, chrome.topRadius + Self.inset)
    }

    private var slotHeight: CGFloat { max(20, chrome.bandHeight - 8) }
}

/// The band's left end: the title while there's nothing to undo, then Undo (⌘Z). Right after a preset it glows for
/// a few seconds: the easy way back.
private struct DesvanEditLeading: View {
    let model: NotchModel
    let session: NotchEditSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            if session.canUndo {
                DesvanEditUndoButton(model: model, session: session)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            } else {
                ViewThatFits(in: .horizontal) {
                    title(Text("Customize the notch"))
                    title(Text("Customize"))
                    title(Text("Edit"))
                }
                .transition(.opacity)
            }
        }
        .animation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion), value: session.canUndo)
    }

    private func title(_ text: Text) -> some View {
        text
            .font(Desvan.Typeface.rounded(12, weight: .semibold))
            .foregroundStyle(Desvan.Palette.paperSecondary)
            .lineLimit(1)
            .fixedSize()
    }
}

private struct DesvanEditUndoButton: View {
    let model: NotchModel
    let session: NotchEditSession
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let offered = session.justApplied != nil
        Button {
            withAnimation(Desvan.Motion.pick(Desvan.Motion.section, reduceMotion: reduceMotion)) {
                if session.undo(in: model.settings) { model.actions.haptic(.snap) }
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 12, weight: .bold))
                    Text("Undo")
                }
                Image(systemName: "arrow.uturn.backward").font(.system(size: 12, weight: .bold))
            }
            .font(Desvan.Typeface.rounded(12, weight: .semibold))
            .foregroundStyle(offered ? Desvan.Palette.bulb : (isHovering ? Desvan.Palette.paper : Desvan.Palette.paperSecondary))
            .padding(.horizontal, 8)
            .frame(minWidth: DesvanHitTarget.minimum)
            .frame(height: DesvanEdit.bandButtonHeight)
            .background {
                Capsule()
                    .fill(Desvan.Palette.paper.opacity(isHovering ? 0.10 : 0.04))
                    .overlay {
                        Capsule().strokeBorder(offered ? Desvan.Palette.bulb.opacity(0.7) : Desvan.Palette.hairlineStrong,
                                               lineWidth: offered ? 1 : 0.75)
                    }
                    .shadow(color: Desvan.Palette.bulb.opacity(offered ? 0.45 : 0), radius: 6)
            }
            .desvanHitTarget()
        }
        .buttonStyle(DesvanEditPressStyle())
        .keyboardShortcut("z", modifiers: .command)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .animation(Desvan.Motion.pick(.easeInOut(duration: 0.3), reduceMotion: reduceMotion), value: offered)
        .help(undoHelp)
        .accessibilityLabel(undoHelp)
        .task(id: session.justApplied) {
            // The glow only lasts a moment; Undo itself stays for the whole visit.
            guard session.justApplied != nil else { return }
            try? await Task.sleep(for: DesvanEdit.undoOffer)
            guard !Task.isCancelled else { return }
            withAnimation(Desvan.Motion.fade) { session.justApplied = nil }
        }
    }

    private var undoHelp: String {
        if let preset = session.justApplied { return String(localized: "Undo \(preset.title) (⌘Z)") }
        return String(localized: "Undo (⌘Z)")
    }
}

/// Done: back to the normal open notch, with everything already saved. Esc closes the notch instead.
private struct DesvanEditDoneButton: View {
    let model: NotchModel

    var body: some View {
        Button { model.actions.endEditing() } label: {
            ViewThatFits(in: .horizontal) {
                Text("Done").padding(.horizontal, 11)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).padding(.horizontal, 8)
            }
        }
        .buttonStyle(DesvanEditPrimaryStyle())
        .keyboardShortcut(.return, modifiers: .command)
        .help("Done (⌘↩)")
        .accessibilityLabel("Done customizing")
    }
}

// MARK: - Ear slot

/// One ear, as a slot: what it shows right now (or a dim stand-in), in a small well. Tap it to point the chips at
/// it; drop a chip (or a tab) on it to fill it. The selected one wears the brass rim of the tab plaque.
struct DesvanEarSlot: View {
    let side: EarSide
    let model: NotchModel
    let session: NotchEditSession
    var height: CGFloat = 24

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let content = session.ear(side, in: model.settings)
        let isSelected = session.selectedEar == side
        let targeted = isTargeted
        Button {
            withAnimation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion)) {
                session.selectedEar = side
            }
        } label: {
            ZStack {
                DesvanSlotWell(isSelected: isSelected, isTargeted: targeted, isHovering: isHovering)
                Group {
                    if content == .none {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isSelected ? Desvan.Palette.bulb.opacity(0.9) : Desvan.Palette.paperTertiary)
                    } else {
                        DesvanEarContent(content: content, model: model, style: .preview)
                    }
                }
                .id(content)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            .frame(width: DesvanEdit.slotWidth, height: height)
            // The band's full height (the well is 8 pt shorter than the band): 28–38 pt, never less.
            .desvanHitTarget(max(DesvanHitTarget.minimum, height + 8))
        }
        .buttonStyle(DesvanEditPressStyle())
        .scaleEffect(targeted && !reduceMotion ? 1.1 : 1)
        .animation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion), value: targeted)
        .animation(Desvan.Motion.pick(Desvan.Motion.settle, reduceMotion: reduceMotion), value: content)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(DesvanEdit.space))
        } action: { frame in
            session.targetFrames[.ear(side)] = frame
        }
        .contextMenu {
            if content != .none {
                Button("Leave Empty") { clear() }
            }
        }
        .help(side == .left ? "Left ear: tap, then pick what it shows" : "Right ear: tap, then pick what it shows")
        .accessibilityLabel(side.title)
        .accessibilityValue(content.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Pick what it shows from the ear chips below")
        .accessibilityAction(named: "Leave empty") { clear() }
    }

    private var isTargeted: Bool {
        if let drag = session.earDrag {
            return drag.content.isAvailable && session.target(at: drag.location) == .ear(side)
        }
        if let drag = session.tileDrag, let ear = NotchEditSession.earContent(for: drag.module), ear.isAvailable {
            return session.target(at: drag.location) == .ear(side)
        }
        return false
    }

    private func clear() {
        withAnimation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion)) {
            if session.assign(.none, to: side, in: model.settings) { model.actions.haptic(.snap) }
        }
    }
}

/// The recess an ear sits in while editing: dashed while waiting, brass-rimmed when chosen, lit when a drag hovers.
private struct DesvanSlotWell: View {
    let isSelected: Bool
    let isTargeted: Bool
    let isHovering: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        shape
            .fill(Desvan.Palette.paper.opacity(isTargeted ? 0.10 : (isHovering ? 0.07 : 0.04)))
            .overlay {
                if isTargeted {
                    shape.strokeBorder(Desvan.Palette.bulb, lineWidth: 1.2)
                        .shadow(color: Desvan.Palette.bulb.opacity(0.7), radius: 6)
                } else if isSelected {
                    shape.strokeBorder(DesvanEditBrass.rim, lineWidth: 1)
                        .shadow(color: Desvan.Palette.bulb.opacity(0.25), radius: 4)
                } else {
                    shape.strokeBorder(Desvan.Palette.paper.opacity(0.22),
                                       style: StrokeStyle(lineWidth: 0.9, dash: [2.5, 2.5]))
                }
            }
    }
}

// MARK: - Shared styles

enum DesvanEditBrass {
    /// The tab plaque's brass rim: bright where it faces the bulb, dark underneath.
    static let rim = LinearGradient(
        colors: [Color(hex: 0xE8C987), Color(hex: 0xA9824A), Color(hex: 0x5E4522)],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// Small plain presses: a touch (94 %) in ≈ 100 ms, back without a wobble (like the tabs and the gear).
struct DesvanEditPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Desvan.Motion.pick(Desvan.Motion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// The bulb-filled primary capsule of `DesvanButtonStyle`, a little tighter for the band beside the notch.
struct DesvanEditPrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DesvanEditPrimaryBody(configuration: configuration)
    }
}

private struct DesvanEditPrimaryBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(Desvan.Typeface.rounded(12, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: DesvanHitTarget.minimum)
            .frame(height: DesvanEdit.bandButtonHeight)
            .foregroundStyle(Desvan.Palette.bulbInk)
            .background {
                Capsule()
                    .fill(Desvan.Palette.bulb.opacity(isHovering ? 1 : 0.94))
                    .overlay {
                        Capsule().fill(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0)],
                                                      startPoint: .top, endPoint: .center))
                    }
                    .overlay { Capsule().strokeBorder(Color(hex: 0xFFE2A8).opacity(0.6), lineWidth: 0.5) }
                    .grain(0.08, in: Capsule())
                    .shadow(color: Desvan.Palette.bulb.opacity(isHovering ? 0.55 : 0.35), radius: 8, y: 1)
            }
            .desvanHitTarget()
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(Desvan.Motion.pick(Desvan.Motion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(Desvan.Motion.hover, value: isHovering)
            .onHover { isHovering = $0 }
    }
}
