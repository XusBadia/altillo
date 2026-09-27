import AltilloCore
import AppKit
import SwiftUI

/// The «Clipboard» tab: the last texts, images and files you copied, as slips on the wood. Click one to copy it
/// again, drag it out anywhere, ⌥-click (or ×) to throw it away, pin the ones worth keeping; Space shows an image or
/// a file in Quick Look. Search at the top; ↑↓ and Return work once the field has focus.
///
/// Files are kept by reference (never their contents), and nothing marked private or copied in a password manager
/// is ever kept (`ClipboardPrivacy`). It only watches the pasteboard while the section is on (`ClipboardStore`).
struct DesvanClipboardView: View {
    let model: NotchModel

    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: ClipboardStore { model.clipboard }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onDisappear {
                store.isSearchFocused = false
                store.query = ""
                store.selection = nil
            }
            .onChange(of: isSearchFocused) { _, focused in
                store.isSearchFocused = focused
                if focused { model.actions.takeKeyboardFocus() }
            }
            .onChange(of: store.query) { store.selection = nil }
            .onChange(of: store.justCopied) { _, copied in
                guard copied != nil else { return }
                AccessibilityNotification.Announcement(String(localized: "Copied")).post()
            }
            .contextMenu { DesvanClipboardOptions(store: store) }
    }

    @ViewBuilder
    private var content: some View {
        if store.isAccessDenied {
            DesvanModuleNotice(
                symbol: "hand.raised",
                title: "Altillo can't read the clipboard",
                message: "You chose not to let it paste from other apps. Allow it in System Settings to keep a history here.",
                actionTitle: "Open Settings"
            ) {
                DesvanClipboardPrivacyPane.open()
            }
        } else if store.history.isEmpty {
            DesvanModuleNotice(
                symbol: "list.clipboard",
                title: "Nothing copied yet",
                message: "Copy some text, an image or a file and it lands here, ready to copy again. Passwords are never kept."
            )
            .overlay(alignment: .topTrailing) { undoButton.padding(2) }
        } else {
            VStack(spacing: 8) {
                header
                list
            }
            .modifier(DesvanListKeys(onMove: move, onReturn: submit))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            DesvanUtilitySearchField(
                placeholder: "Search what you copied",
                accessibilityLabel: "Search the clipboard",
                text: Bindable(store).query,
                isFocused: $isSearchFocused,
                onClick: { model.actions.takeKeyboardFocus() }
            )
            if let undoable = store.undoable {
                undoButton
                    .help(undoable.kind == .clear ? "Put the history back" : "Put the slip back")
            } else if !store.history.recent.isEmpty {
                Button("Clear") {
                    withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) { store.clear() }
                }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
                .help("Clear the history (pinned slips stay)")
                .accessibilityLabel("Clear the history")
                .accessibilityHint("Pinned slips stay.")
            }
            Menu {
                DesvanClipboardOptions(store: store)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Clipboard options")
            .accessibilityLabel("Clipboard options")
        }
        .frame(height: 30)
    }

    @ViewBuilder
    private var undoButton: some View {
        if store.undoable != nil {
            Button {
                withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) { store.undo() }
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 28))
            .transition(.opacity)
        }
    }

    // MARK: - Slips

    private var list: some View {
        let items = store.visibleItems
        return Group {
            if items.isEmpty {
                Text("No slips with “\(store.query)”.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        // Minute-level "4 min ago" without a timer while nothing changes.
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            LazyVStack(spacing: 6) {
                                ForEach(items) { item in
                                    slip(item, now: context.date)
                                        .id(item.id)
                                }
                            }
                            .padding(.top, 5)
                            .padding(.bottom, 2)
                        }
                    }
                    .scrollIndicators(.never)
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: store.selection) { _, id in
                        guard let id else { return }
                        withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) {
                            proxy.scrollTo(id, anchor: nil)
                        }
                    }
                }
            }
        }
        .animation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion), value: items.map(\.id))
    }

    private func slip(_ item: ClipboardItem, now: Date) -> some View {
        DesvanClipboardSlip(
            item: item,
            now: now,
            thumbnail: item.image.flatMap { store.images.thumbnail(for: $0) },
            isImageGone: item.image.map { !store.images.has($0) } ?? false,
            isSelected: store.selection == item.id,
            isCopied: store.justCopied == item.id,
            canPin: item.isPinned || store.history.canPinMore,
            copy: { copy(item) },
            copyPlain: item.richText == nil ? nil : { copy(item, plain: true) },
            delete: {
                withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) { store.delete(item) }
            },
            togglePin: {
                withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) {
                    _ = store.togglePin(item)
                }
            },
            putOnShelf: { putOnShelf(item) },
            dragItems: { dragItems(for: item) },
            quickLook: item.content.isPreviewable ? { quickLook(item) } : nil
        )
    }

    // MARK: - Actions

    @discardableResult
    private func copy(_ item: ClipboardItem, plain: Bool = false) -> Bool {
        let copied = withAnimation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion)) {
            store.copy(item, plain: plain)
        }
        if copied {
            model.actions.haptic(.snap)
        } else {
            AccessibilityNotification.Announcement(String(localized: "Moved or deleted")).post()
        }
        return copied
    }

    private func putOnShelf(_ item: ClipboardItem) {
        if let image = item.image {
            // The shelf gets a copy of its own, in its inbox: it outlives the slip.
            guard let png = store.images.data(for: image),
                  let shelved = try? FileIngest.standard.ingest(data: png, suggestedName: String(localized: "Image") + ".png")
            else { return }
            model.actions.addToShelf([shelved])
            return
        }
        let items = item.shelfItems
        guard !items.isEmpty else { return }
        model.actions.addToShelf(items)
    }

    /// A drag out: the text, the files, or the image as a PNG file.
    private func dragItems(for item: ClipboardItem) -> [ShelfItem] {
        guard let image = item.image else { return item.shelfItems }
        guard let url = store.images.scratchFile(for: image) else { return [] }
        return [ShelfItem(kind: .file(url, isOwnedCopy: false), displayName: item.title)]
    }

    private func quickLook(_ item: ClipboardItem) {
        let urls: [URL] = if let image = item.image {
            store.images.scratchFile(for: image).map { [$0] } ?? []
        } else {
            item.files.compactMap { $0.resolvedURL() }
        }
        QuickLookPresenter.show(urls)
    }

    private func move(_ offset: Int) -> Bool {
        guard !store.visibleItems.isEmpty else { return false }
        store.moveSelection(offset)
        return true
    }

    private func submit() -> Bool {
        guard store.selection != nil || (isSearchFocused && !store.query.isEmpty) else { return false }
        guard let item = store.visibleItems.first(where: { $0.id == store.selection }) ?? store.visibleItems.first
        else { return false }
        copy(item)
        return true
    }
}

// MARK: - A slip

/// One copy on a wood slip: the app it came from (or the file's icon), its first two lines (or the file's name and
/// folder) and when. Pinned slips are held with a strip of masking tape. Hovering shows pin, "Put on the shelf"
/// and ×. A file slip whose files are all gone stays, dimmed, until it's thrown away.
private struct DesvanClipboardSlip: View {
    let item: ClipboardItem
    let now: Date
    /// An image slip's picture (nil while it's being made).
    let thumbnail: NSImage?
    /// An image slip whose PNG is gone.
    let isImageGone: Bool
    let isSelected: Bool
    let isCopied: Bool
    let canPin: Bool
    /// False when there was nothing to copy (the files are gone).
    let copy: () -> Bool
    /// ⇧-click or ⇧Return: the text without its formatting (only for slips that have some).
    let copyPlain: (() -> Bool)?
    let delete: () -> Void
    let togglePin: () -> Void
    let putOnShelf: () -> Void
    let dragItems: () -> [ShelfItem]
    /// Space: Quick Look, for images and files.
    let quickLook: (() -> Void)?

    @State private var isHovering = false
    /// Every file the slip points to is gone (looked at when it appears).
    @State private var filesAreGone = false

    private var isMissing: Bool { filesAreGone || isImageGone }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: item.image == nil ? .top : .center, spacing: 10) {
            if item.image != nil {
                DesvanClipboardThumbnail(image: thumbnail)
                    .opacity(isMissing ? 0.45 : 1)
            } else {
                DesvanClipboardSlipIcon(item: item)
                    .padding(.top, 1)
                    .opacity(isMissing ? 0.45 : 1)
            }
            words
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .task(id: item.copiedAt) { await lookForFiles() }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(minHeight: 50)
        .desvanCard(
            radius: 9,
            fill: isHovering || isSelected ? Desvan.Palette.woodRaised : Desvan.Palette.wood,
            glow: isCopied ? Desvan.Palette.bulb : (isSelected ? Desvan.Palette.bulb.opacity(0.55) : nil)
        )
        .overlay(alignment: .topLeading) {
            if item.isPinned { tape }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            if flags.contains(.option) {
                delete()
            } else if flags.contains(.shift), let copyPlain {
                _ = copyPlain()
            } else {
                copyOrNotice()
            }
        }
        .shelfDraggable(
            items: { isMissing ? [] : dragItems() },
            onEnded: { _, _ in }
        )
        .focusable()
        .onKeyPress(keys: [.return]) { press in
            if press.modifiers.contains(.shift), let copyPlain { _ = copyPlain() } else { copyOrNotice() }
            return .handled
        }
        .onKeyPress(.space) {
            if let quickLook, !isMissing { quickLook() } else { copyOrNotice() }
            return .handled
        }
        .help(copyPlain == nil ? "Click to copy · ⌥-click to throw away · drag it out"
                               : "Click to copy with its formatting · ⇧-click for plain text · ⌥-click to throw away · drag it out")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Copies it again.")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { copyOrNotice() }
        .accessibilityActions {
            Button(item.isPinned ? "Unpin" : "Pin", action: togglePin)
            if let copyPlain { Button("Copy as Plain Text") { _ = copyPlain() } }
            Button("Put on the shelf", action: putOnShelf)
            if let quickLook, !isMissing { Button("Quick Look", action: quickLook) }
            Button("Throw away", action: delete)
        }
    }

    @ViewBuilder
    private var words: some View {
        switch item.content {
        case .text:
            Text(item.preview)
                .font(.system(size: 12.5))
                .foregroundStyle(Desvan.Palette.paper)
                .lineLimit(2)
                .lineSpacing(1.5)
                .multilineTextAlignment(.leading)
        case let .files(files):
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: files.count == 1 ? files[0].name : String(localized: "\(files.count) files"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isMissing ? Desvan.Palette.paperTertiary : Desvan.Palette.paper)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: fileDetail(files))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        case let .image(image):
            VStack(alignment: .leading, spacing: 2) {
                Text("Image")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isMissing ? Desvan.Palette.paperTertiary : Desvan.Palette.paper)
                Text(verbatim: isMissing ? String(localized: "No longer available") : imageDetail(image))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .lineLimit(1)
            }
        }
    }

    /// Under an image slip's name: its size and, when Vision read some, the first words in it.
    private func imageDetail(_ image: ClipboardImage) -> String {
        let size = "\(image.width) × \(image.height)"
        let words = (image.recognizedText ?? "").split(whereSeparator: \.isNewline).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return words.isEmpty ? size : "\(size) · \(words)"
    }

    /// Under a file slip's name: the folder it's in, the names of several, or that they're gone.
    private func fileDetail(_ files: [ClipboardFile]) -> String {
        if isMissing { return String(localized: "Moved or deleted") }
        if files.count > 1 { return files.prefix(6).map(\.name).joined(separator: ", ") }
        return String(localized: "in \(files[0].folderName)")
    }

    /// Whether any of the files is still around, looked at off the main thread (a slow volume can't stall the
    /// notch).
    private func lookForFiles() async {
        let files = item.files
        guard !files.isEmpty else { return }
        let missing = await Task.detached(priority: .utility) {
            !files.contains { $0.resolvedURL() != nil }
        }.value
        if missing != filesAreGone { filesAreGone = missing }
    }

    private func copyOrNotice() {
        if !copy() { filesAreGone = !item.files.isEmpty }
    }

    /// Time and pin at rest; the tools while hovered; "Copied" for a moment after a click.
    @ViewBuilder
    private var trailing: some View {
        ZStack(alignment: .topTrailing) {
            if isCopied {
                Label("Copied", systemImage: "checkmark")
                    .font(Desvan.Typeface.rounded(12, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.bulb)
                    .labelStyle(.titleAndIcon)
                    .fixedSize()
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
            } else if isHovering {
                HStack(spacing: 0) {
                    tool(item.isPinned ? "pin.slash" : "pin", help: item.isPinned ? "Unpin" : (canPin ? "Pin" : "Twenty pins at most"),
                         action: togglePin)
                        .disabled(!canPin)
                    tool("tray.and.arrow.up", help: "Put on the shelf", action: putOnShelf)
                        .disabled(isMissing)
                    tool("xmark", help: "Throw away (⌥-click)", action: delete)
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(NotchFormat.ago(item.copiedAt, now: now))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                    if let app = item.sourceName {
                        Text(app)
                            .font(.system(size: 11))
                            .foregroundStyle(Desvan.Palette.paperTertiary)
                            .lineLimit(1)
                    }
                }
                .fixedSize()
                .transition(.opacity)
            }
        }
        .frame(minWidth: 84, alignment: .topTrailing)
        .animation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion), value: isCopied)
        .animation(Desvan.Motion.hover, value: isHovering)
    }

    private func tool(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(DesvanClipboardToolStyle())
        .help(help)
        .accessibilityHidden(true)
    }

    /// A strip of masking tape holding the slip to the wood by its top edge: pinned.
    private var tape: some View {
        Rectangle()
            .fill(Desvan.Palette.tape.opacity(0.85))
            .grain(0.1, in: Rectangle())
            .frame(width: 30, height: 9)
            .rotationEffect(.degrees(-5))
            .offset(x: 3, y: -4)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var spoken: String {
        var parts = [item.title.isEmpty ? String(localized: "Blank text") : item.title]
        if filesAreGone { parts.append(String(localized: "moved or deleted")) }
        if isImageGone { parts.append(String(localized: "no longer available")) }
        if let app = item.sourceName { parts.append(String(localized: "from \(app)")) }
        parts.append(NotchFormat.ago(item.copiedAt, now: now))
        if item.isPinned { parts.append(String(localized: "pinned")) }
        return parts.joined(separator: ", ")
    }
}

/// Small icon buttons on a slip: quiet until hovered.
private struct DesvanClipboardToolStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DesvanClipboardToolBody(configuration: configuration)
    }
}

private struct DesvanClipboardToolBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(isHovering && isEnabled ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
            .opacity(isEnabled ? 1 : 0.4)
            .background(Circle().fill(Desvan.Palette.paper.opacity(isHovering && isEnabled ? 0.08 : 0)).padding(2))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Desvan.Motion.press, value: configuration.isPressed)
            .onHover { isHovering = $0 }
    }
}

/// The source app's icon (or, for files, the files' own icon), looked up once each; a plain text glyph when
/// it's unknown.
private struct DesvanClipboardSlipIcon: View {
    let item: ClipboardItem

    var body: some View {
        Group {
            if let icon = DesvanClipboardIcons.icon(for: item) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

@MainActor
private enum DesvanClipboardIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for item: ClipboardItem) -> NSImage? {
        switch item.content {
        case .text: appIcon(for: item.sourceBundleID)
        case let .files(files): fileIcon(for: files.prefix(3).map(\.path))
        case .image: nil
        }
    }

    private static func appIcon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }

    private static func fileIcon(for paths: [String]) -> NSImage? {
        guard !paths.isEmpty else { return nil }
        let key = "files:" + paths.joined(separator: "\n")
        if let cached = cache[key] { return cached }
        let icon = paths.count == 1 ? NSWorkspace.shared.icon(forFile: paths[0])
                                    : NSWorkspace.shared.icon(forFiles: paths) ?? NSWorkspace.shared.icon(forFile: paths[0])
        if cache.count > 200 { cache.removeAll() }
        cache[key] = icon
        return icon
    }
}

extension ClipboardItem {
    /// What the slip gives the shelf, or a drag out: the text, or the files that are still there.
    var shelfItems: [ShelfItem] {
        switch content {
        case let .text(text):
            return [ShelfItem(kind: .text(text), displayName: title)]
        case let .files(files):
            return files.compactMap { file in
                file.resolvedURL().map { ShelfItem(kind: .file($0, isOwnedCopy: false), displayName: FileIngest.displayName(of: $0)) }
            }
        case .image:
            // Needs the PNG as a file: the section makes one (`ClipboardImages.scratchFile`).
            return []
        }
    }
}

extension ClipboardContent {
    /// Images and files open in Quick Look.
    var isPreviewable: Bool {
        if case .text = self { false } else { true }
    }
}

/// An image slip's picture, small and rounded, on a dark mat while it's being made.
private struct DesvanClipboardThumbnail: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.black.opacity(0.28))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            }
        }
        .frame(width: 52, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .animation(.easeOut(duration: 0.18), value: image != nil)
        .accessibilityHidden(true)
    }
}

// MARK: - Options

/// The section's menu (… button and right-click): keep the history after quitting, clear it, and a reminder of
/// what is never kept.
private struct DesvanClipboardOptions: View {
    let store: ClipboardStore

    var body: some View {
        Toggle("Keep History After Quitting", isOn: Bindable(store).keepsHistory)
        Toggle("Keep Images", isOn: Bindable(store).keepsImages)
        Toggle("Find Text in Images", isOn: Bindable(store).readsTextInImages)
            .disabled(!store.keepsImages)
        Button("Clear History") { store.clear() }
            .disabled(store.history.recent.isEmpty)
        Divider()
        Text("Texts, images and files (files by reference). Passwords and anything marked private are never kept.")
    }
}

/// System Settings › Privacy & Security, where "Paste from Other Apps" lives.
private enum DesvanClipboardPrivacyPane {
    static func open() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard",
            "x-apple.systempreferences:com.apple.preference.security",
        ].compactMap(URL.init(string:))
        for url in urls where NSWorkspace.shared.open(url) { return }
    }
}
