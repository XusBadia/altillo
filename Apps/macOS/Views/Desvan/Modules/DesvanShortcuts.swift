import AltilloCore
import AppKit
import SwiftUI

/// The «Shortcuts» tab: favourites as big kraft tags on the left, every other shortcut in a searchable list on the
/// right, and how the last run went underneath. One click runs a shortcut; nothing ever runs by itself.
///
/// "Run with …" (hover a tag or a row, or right-click) hands the clipboard's text or the shelf's selected item to
/// the shortcut as its input. The list comes from the `shortcuts` command, refreshed each time the tab appears.
struct DesvanShortcutsView: View {
    let model: NotchModel

    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: ShortcutsStore { model.shortcuts }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { store.start() }
            .onDisappear {
                store.stop()
                isSearchFocused = false
            }
            .onChange(of: isSearchFocused) { _, focused in
                store.isSearchFocused = focused
                if focused { model.actions.takeKeyboardFocus() }
            }
            .onChange(of: store.lastOutcome) { _, outcome in announce(outcome) }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .missing:
            DesvanModuleNotice(
                symbol: "square.2.layers.3d",
                title: "Shortcuts isn't here",
                message: "This Mac doesn't have the shortcuts command, so there's nothing to run from the notch."
            )
        case let .failed(message) where store.shortcuts.isEmpty:
            DesvanModuleNotice(
                symbol: "exclamationmark.triangle",
                title: "Couldn't list your shortcuts",
                message: LocalizedStringKey(message),
                actionTitle: "Try Again"
            ) {
                store.refresh()
            }
        case .loading where store.shortcuts.isEmpty:
            DesvanModuleNotice(symbol: "square.2.layers.3d", title: "Looking for your shortcuts…")
        default:
            if store.shortcuts.isEmpty {
                DesvanModuleNotice(
                    symbol: "square.2.layers.3d",
                    title: "No shortcuts yet",
                    message: "Make one in the Shortcuts app and it shows up here, one click away.",
                    actionTitle: "Open Shortcuts"
                ) {
                    DesvanShortcutsApp.open()
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    favourites
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    browser
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Favourites

    @ViewBuilder
    private var favourites: some View {
        let pinned = store.pinned
        if pinned.isEmpty {
            DesvanShortcutsPinHint()
        } else {
            ScrollView(.vertical) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(pinned) { shortcut in
                        DesvanShortcutsTile(
                            shortcut: shortcut,
                            state: store.runs[shortcut.id],
                            offers: offers,
                            run: { run(shortcut, with: $0) },
                            unpin: { togglePin(shortcut) }
                        )
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - The list

    private var browser: some View {
        VStack(spacing: 6) {
            DesvanUtilitySearchField(
                placeholder: "Search your shortcuts",
                accessibilityLabel: "Search your shortcuts",
                text: Bindable(store).query,
                isFocused: $isSearchFocused,
                onSubmit: runFirstMatch,
                onClick: { model.actions.takeKeyboardFocus() }
            )
            list
            DesvanShortcutsStatus(outcome: store.lastOutcome)
        }
    }

    @ViewBuilder
    private var list: some View {
        let listed = store.listed
        if listed.isEmpty {
            Text(store.query.isEmpty ? "Every shortcut is pinned." : "No shortcut called “\(store.query)”.")
                .font(.system(size: 12.5))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(listed) { shortcut in
                        DesvanShortcutsRow(
                            shortcut: shortcut,
                            state: store.runs[shortcut.id],
                            isPinned: store.isPinned(shortcut),
                            canPin: store.isPinned(shortcut) || store.canPinMore,
                            offers: offers,
                            run: { run(shortcut, with: $0) },
                            togglePin: { togglePin(shortcut) }
                        )
                    }
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    /// "Run with …" choices right now, judged from the pasteboard's types (nothing is read until one is picked).
    private func offers() -> [ShortcutsStore.InputOffer] {
        ShortcutsStore.inputOffers(shelfSelection: model.shelf.filter { model.selection.contains($0.id) })
    }

    private func run(_ shortcut: ShortcutInfo, with offer: ShortcutsStore.InputOffer?) {
        let input = offer?.resolve()
        // Asked to hand something over that's gone (or turned private) since the menu opened: never run without it.
        if offer != nil, input == nil {
            store.reportMissingInput(for: shortcut)
            return
        }
        store.trigger(shortcut, input: input)
        model.actions.haptic(.snap)
    }

    private func togglePin(_ shortcut: ShortcutInfo) {
        withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) {
            _ = store.togglePin(shortcut)
        }
    }

    /// Return in the search field: the only match, if there's exactly one.
    private func runFirstMatch() {
        let listed = store.listed
        guard !store.query.isEmpty, listed.count == 1, let shortcut = listed.first else { return }
        run(shortcut, with: nil)
    }

    private func announce(_ outcome: ShortcutsStore.Outcome?) {
        guard let outcome else { return }
        AccessibilityNotification.Announcement(DesvanShortcutsStatus.sentence(for: outcome)).post()
    }
}

// MARK: - A favourite

/// A pinned shortcut as a kraft luggage tag: its emoji (or the Shortcuts glyph), its name in ink, an eyelet in its
/// label colour. Lifts a little under the pointer; shows running, done and failed right on the tag.
private struct DesvanShortcutsTile: View {
    let shortcut: ShortcutInfo
    let state: ShortcutsStore.RunState?
    let offers: () -> [ShortcutsStore.InputOffer]
    let run: (ShortcutsStore.InputOffer?) -> Void
    let unpin: () -> Void

    @State private var isHovering = false
    @State private var hoverOffers: [ShortcutsStore.InputOffer] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let face = DesvanShortcutsFace(shortcut.name)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                DesvanShortcutsGlyph(face: face, size: 16, color: Desvan.Palette.ink)
                Spacer(minLength: 4)
                indicator
            }
            Text(face.title)
                .font(Desvan.Typeface.rounded(13, weight: .semibold))
                .foregroundStyle(Desvan.Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(height: 76)
        .background {
            shape.fill(LinearGradient(colors: [Color(hex: 0xD4B48A), Desvan.Palette.kraft],
                                      startPoint: .top, endPoint: .bottom))
                .desvanTexture(DesvanTexture.kraft, opacity: 0.28, in: shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75) }
                .shadow(color: .black.opacity(isHovering ? 0.55 : 0.4), radius: isHovering ? 6 : 2.5, y: isHovering ? 3 : 1.5)
        }
        .overlay {
            if isHovering || state == .running {
                shape.strokeBorder(Desvan.Palette.bulb.opacity(0.8), lineWidth: 1)
                    .shadow(color: Desvan.Palette.bulb.opacity(0.45), radius: 7)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isHovering, !hoverOffers.isEmpty {
                DesvanShortcutsRunWithMenu(offers: hoverOffers, tint: Desvan.Palette.ink, run: run)
                    .padding(2)
                    .transition(.opacity)
            }
        }
        .scaleEffect(isHovering && !reduceMotion ? 1.02 : 1)
        .contentShape(shape)
        .onHover { hovering in
            if hovering { hoverOffers = offers() }
            withAnimation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion)) { isHovering = hovering }
        }
        .onTapGesture { if state != .running { run(nil) } }
        .contextMenu {
            DesvanShortcutsMenuItems(shortcut: shortcut, offers: offers(), isPinned: true, canPin: true,
                                     run: run, togglePin: unpin)
        }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesvanShortcutsStatus.spoken(shortcut, state: state))
        .accessibilityHint("Runs the shortcut.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { run(nil) }
        .accessibilityActions {
            ForEach(offers()) { offer in
                Button(offer.title) { run(offer) }
            }
            Button("Unpin", action: unpin)
        }
    }

    private var help: String {
        if case let .failed(message)? = state { return message }
        return String(localized: "Run “\(shortcut.name)”")
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .running?:
            ProgressView().controlSize(.small).tint(Desvan.Palette.ink)
        case .succeeded?:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x3F6B35))
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        case .failed?:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0xA3341F))
        case nil:
            // The tag's eyelet, in the shortcut's label colour (identity only).
            Circle()
                .fill(Desvan.Palette.ink.opacity(0.85))
                .frame(width: 7, height: 7)
                .overlay { Circle().strokeBorder(DesvanShortcutsFace.labelColor(for: shortcut.id), lineWidth: 2).padding(-2.5) }
                .padding(4)
        }
    }
}

// MARK: - A row

private struct DesvanShortcutsRow: View {
    let shortcut: ShortcutInfo
    let state: ShortcutsStore.RunState?
    let isPinned: Bool
    let canPin: Bool
    let offers: () -> [ShortcutsStore.InputOffer]
    let run: (ShortcutsStore.InputOffer?) -> Void
    let togglePin: () -> Void

    @State private var isHovering = false
    @State private var hoverOffers: [ShortcutsStore.InputOffer] = []

    var body: some View {
        let face = DesvanShortcutsFace(shortcut.name)
        HStack(spacing: 8) {
            DesvanShortcutsGlyph(face: face, size: 13, color: Desvan.Palette.paperTertiary)
                .frame(width: 18)
            Text(face.title)
                .font(.system(size: 13))
                .foregroundStyle(Desvan.Palette.paper)
                .lineLimit(1)
                .truncationMode(.middle)
            if let folder = shortcut.folder {
                Text(folder)
                    .font(.system(size: 11))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Desvan.Palette.paper.opacity(isHovering ? 0.07 : 0))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            if hovering { hoverOffers = offers() }
            withAnimation(Desvan.Motion.hover) { isHovering = hovering }
        }
        .onTapGesture { if state != .running { run(nil) } }
        .contextMenu {
            DesvanShortcutsMenuItems(shortcut: shortcut, offers: offers(), isPinned: isPinned, canPin: canPin,
                                     run: run, togglePin: togglePin)
        }
        .help(state.flatMap { if case let .failed(message) = $0 { message } else { nil } }
            ?? String(localized: "Run “\(shortcut.name)”"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesvanShortcutsStatus.spoken(shortcut, state: state)
            + (shortcut.folder.map { ", " + String(localized: "in \($0)") } ?? ""))
        .accessibilityHint("Runs the shortcut.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { run(nil) }
        .accessibilityActions {
            ForEach(offers()) { offer in
                Button(offer.title) { run(offer) }
            }
            if canPin { Button(isPinned ? "Unpin" : "Pin to the Favourites", action: togglePin) }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .running?:
            DesvanWorkingDots(dot: 4).padding(.trailing, 8)
        case .succeeded?:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Desvan.Palette.done)
                .padding(.trailing, 8)
        case .failed?:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Desvan.Palette.critical)
                .padding(.trailing, 8)
        case nil:
            if isHovering {
                HStack(spacing: 0) {
                    if !hoverOffers.isEmpty {
                        DesvanShortcutsRunWithMenu(offers: hoverOffers, tint: Desvan.Palette.paperSecondary, run: run)
                    }
                    Button(action: togglePin) {
                        Image(systemName: isPinned ? "pin.slash" : "pin")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Desvan.Palette.paperSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPin)
                    .help(isPinned ? "Unpin" : (canPin ? "Pin to the favourites" : "Twelve favourites at most"))
                }
                .transition(.opacity)
            } else if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Desvan.Palette.bulb.opacity(0.8))
                    .padding(.trailing, 9)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Pieces

/// "Run with …": a small menu with the inputs on offer.
private struct DesvanShortcutsRunWithMenu: View {
    let offers: [ShortcutsStore.InputOffer]
    let tint: Color
    let run: (ShortcutsStore.InputOffer?) -> Void

    var body: some View {
        Menu {
            ForEach(offers) { offer in
                Button(offer.title) { run(offer) }
            }
        } label: {
            Image(systemName: "arrow.right.doc.on.clipboard")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Run with…")
        .accessibilityLabel("Run with…")
    }
}

/// Right-click on a tag or a row.
private struct DesvanShortcutsMenuItems: View {
    let shortcut: ShortcutInfo
    let offers: [ShortcutsStore.InputOffer]
    let isPinned: Bool
    let canPin: Bool
    let run: (ShortcutsStore.InputOffer?) -> Void
    let togglePin: () -> Void

    var body: some View {
        Button("Run") { run(nil) }
        ForEach(offers) { offer in
            Button(offer.title) { run(offer) }
        }
        Divider()
        Button(isPinned ? "Unpin" : "Pin to the Favourites", action: togglePin)
            .disabled(!canPin)
        Button("Edit in Shortcuts") { DesvanShortcutsApp.open(shortcut) }
    }
}

/// Nothing pinned yet: a dashed spot on the wood saying what goes there.
private struct DesvanShortcutsPinHint: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "pin")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperTertiary)
            Text("Your favourites")
                .font(Desvan.Typeface.display(14, weight: 600))
                .foregroundStyle(Desvan.Palette.paper)
            Text("Pin a shortcut from the list and it becomes a big tag here, one click away.")
                .font(.system(size: 12))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Desvan.Palette.paper.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .accessibilityElement(children: .combine)
    }
}

/// How the last run went, one line under the list.
private struct DesvanShortcutsStatus: View {
    let outcome: ShortcutsStore.Outcome?

    var body: some View {
        HStack(spacing: 6) {
            if let outcome {
                symbol(outcome.state)
                Text(Self.sentence(for: outcome))
                    .foregroundStyle(outcome.state.isFailure ? Desvan.Palette.critical : Desvan.Palette.paperSecondary)
            } else {
                Text("Click a shortcut to run it.")
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11.5))
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(height: 16)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func symbol(_ state: ShortcutsStore.RunState) -> some View {
        switch state {
        case .running: DesvanWorkingDots(dot: 4)
        case .succeeded: Image(systemName: "checkmark").foregroundStyle(Desvan.Palette.done)
        case .failed: Image(systemName: "exclamationmark.circle").foregroundStyle(Desvan.Palette.critical)
        }
    }

    static func sentence(for outcome: ShortcutsStore.Outcome) -> String {
        let name = outcome.shortcut.name
        switch outcome.state {
        case .running:
            return String(localized: "Running “\(name)”…")
        case let .succeeded(output):
            if let line = output?.split(whereSeparator: \.isNewline).first {
                return String(localized: "“\(name)” ran: \(String(line))")
            }
            return String(localized: "“\(name)” ran.")
        case let .failed(message):
            return String(localized: "“\(name)” didn't finish: \(message)")
        }
    }

    static func spoken(_ shortcut: ShortcutInfo, state: ShortcutsStore.RunState?) -> String {
        switch state {
        case .running?: String(localized: "\(shortcut.name), running")
        case .succeeded?: String(localized: "\(shortcut.name), done")
        case let .failed(message)?: String(localized: "\(shortcut.name), didn't finish: \(message)")
        case nil: shortcut.name
        }
    }
}

private extension ShortcutsStore.RunState {
    var isFailure: Bool {
        if case .failed = self { true } else { false }
    }
}

/// A shortcut's name split into the emoji it starts with (if any) and the words.
struct DesvanShortcutsFace {
    let emoji: String?
    let title: String

    init(_ name: String) {
        if let first = name.first, first.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation })
            || (first.unicodeScalars.count > 1 && first.unicodeScalars.first?.properties.isEmoji == true) {
            emoji = String(first)
            let rest = name.dropFirst().trimmingCharacters(in: .whitespaces)
            title = rest.isEmpty ? name : rest
        } else {
            emoji = nil
            title = name
        }
    }

    /// One of the seven label colours, stable for a shortcut (identity only, never state).
    static func labelColor(for id: String) -> Color {
        let colors = [Desvan.Palette.tomato, Desvan.Palette.mustard, Desvan.Palette.sage, Desvan.Palette.sky,
                      Desvan.Palette.lavender, Desvan.Palette.rose, Desvan.Palette.sand]
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return colors[Int(hash % UInt32(colors.count))]
    }
}

private struct DesvanShortcutsGlyph: View {
    let face: DesvanShortcutsFace
    let size: CGFloat
    let color: Color

    var body: some View {
        Group {
            if let emoji = face.emoji {
                Text(emoji).font(.system(size: size))
            } else {
                Image(systemName: "square.2.layers.3d")
                    .font(.system(size: size * 0.85, weight: .medium))
                    .foregroundStyle(color)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Opens the Shortcuts app, on one shortcut when given.
enum DesvanShortcutsApp {
    static func open(_ shortcut: ShortcutInfo? = nil) {
        if let shortcut,
           let name = shortcut.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
           let url = URL(string: "shortcuts://open-shortcut?name=\(name)"),
           NSWorkspace.shared.open(url) {
            return
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        }
    }
}
