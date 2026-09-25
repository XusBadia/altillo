import AltilloCore
import AltilloDesign
import SwiftUI

/// The «Nota» section: one sheet of paper taped up in the attic. Type on it (it saves as you go), copy it, drag it
/// out anywhere by its tape, put it on the shelf, or put it away with "New note" (the last five stay in the history).
struct DesvanNoteView: View {
    let model: NotchModel

    @FocusState private var isEditorFocused: Bool
    @State private var copied = false
    @State private var putUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: NoteStore { model.note }
    private var isEmpty: Bool { store.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            sheet
            toolbar
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .desvanCard(radius: 16)
        .onAppear { store.start() }
        .onDisappear {
            store.isEditing = false
            store.stop()
        }
        .onChange(of: isEditorFocused) { _, focused in
            store.isEditing = focused
            if focused { model.actions.takeKeyboardFocus() }
        }
    }

    // MARK: - The paper

    private var sheet: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return ZStack(alignment: .topLeading) {
            TextEditor(text: Bindable(store).text)
                .font(.system(size: 13.5))
                .foregroundStyle(Desvan.Palette.ink)
                .tint(Color(hex: 0xB86A12))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused($isEditorFocused)
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 6)
                .accessibilityLabel("Note")
            if store.text.isEmpty {
                Text("Jot something down…")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Desvan.Palette.ink.opacity(0.45))
                    .padding(.horizontal, 15)
                    .padding(.top, 14)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape.fill(LinearGradient(colors: [Color(hex: 0xF7F0E2), Color(hex: 0xEFE4CF)],
                                      startPoint: .top, endPoint: .bottom))
                .grain(0.05, in: shape)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
        }
        .overlay(alignment: .top) { tape }
        .overlay(alignment: .bottom) { askUndoSlip }
        .contentShape(shape)
        .simultaneousGesture(TapGesture().onEnded {
            model.actions.takeKeyboardFocus()
            isEditorFocused = true
        })
    }

    /// Masking tape holding the sheet up. It's also the handle: drag it and the note goes out as text.
    private var tape: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color(hex: 0xE2CC98).opacity(0.92))
            .overlay {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5)
            }
            .grain(0.1, in: RoundedRectangle(cornerRadius: 1.5, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
            .frame(width: 64, height: 16)
            .rotationEffect(.degrees(-2.5))
            .offset(y: -7)
            .shelfDraggable(items: { dragItems }, onEnded: { _, _ in })
            .help("Drag the note out anywhere")
            .accessibilityHidden(true)
    }

    /// After Ask adds a line: say so on a slip at the foot of the sheet, with "Undo".
    @ViewBuilder
    private var askUndoSlip: some View {
        if let append = store.askAppend {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Desvan.Palette.bulb)
                Text("Ask added “\(append.added)”")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paper)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button("Undo") { store.undoAskAppend() }
                    .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 24))
                Button {
                    store.keepAskAppend()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 24))
                .accessibilityLabel("Keep it")
                .help("Keep it")
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .frame(height: 30)
            .background(Capsule().fill(Desvan.Palette.wood.opacity(0.94)))
            .padding(6)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var dragItems: [ShelfItem] {
        guard !isEmpty else { return [] }
        return [ShelfItem(kind: .text(store.text), displayName: Self.title(for: store.text))]
    }

    /// The note's first line, as its name on the shelf.
    static func title(for text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return String(localized: "Note") }
        return trimmed.count > 40 ? String(trimmed.prefix(39)) + "…" : trimmed
    }

    // MARK: - Toolbar

    /// Five tools down the right edge, 28 pt each: copy, shelf, drag out, new note (its menu brings back an earlier
    /// one) and clear (which turns into "Undo clear").
    private var toolbar: some View {
        VStack(spacing: 3) {
            tool(copied ? "Copied" : "Copy", symbol: copied ? "checkmark" : "doc.on.doc", disabled: isEmpty) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(store.text, forType: .string)
                flash($copied)
            }
            tool(putUp ? "On the shelf" : "Put it on the shelf", symbol: putUp ? "checkmark" : "tray.and.arrow.up",
                 disabled: isEmpty) {
                model.actions.addToShelf(dragItems)
                flash($putUp)
            }
            tool("Drag the note out", symbol: "hand.draw", disabled: isEmpty) {}
                .shelfDraggable(items: { dragItems }, onEnded: { _, _ in })
            newNote
            if store.clearedText != nil && store.text.isEmpty {
                tool("Undo clear", symbol: "arrow.uturn.backward", disabled: false) {
                    store.undoClear()
                }
            } else {
                tool("Clear", symbol: "eraser", disabled: isEmpty) {
                    store.clear()
                }
            }
        }
        .frame(width: 34)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func tool(_ title: LocalizedStringKey, symbol: String, disabled: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 16)
        }
        .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }

    /// "New note" puts this one away; its menu lists the last ones put away, to bring one back (the current note
    /// takes its place).
    private var newNote: some View {
        Menu {
            if store.history.isEmpty {
                Text("Notes you put away appear here")
            } else {
                Section("Bring back") {
                    ForEach(store.history) { note in
                        Button("\(note.title) · \(note.archivedAt.formatted(.relative(presentation: .named)))") {
                            withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) {
                                store.restore(note.id)
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12.5, weight: .semibold))
        } primaryAction: {
            guard !isEmpty else { return }
            withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) { store.newNote() }
            isEditorFocused = true
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(store.history.isEmpty ? .hidden : .visible)
        .foregroundStyle(Desvan.Palette.paperSecondary)
        .frame(width: 34, height: 28)
        .contentShape(Rectangle())
        .opacity(isEmpty && store.history.isEmpty ? 0.4 : 1)
        .help("New note (hold for earlier ones)")
        .accessibilityLabel("New note")
        .accessibilityHint("Puts this note away. Its menu brings back an earlier one.")
    }

    private func flash(_ flag: Binding<Bool>) {
        model.actions.haptic(.snap)
        withAnimation(Desvan.Motion.fade) { flag.wrappedValue = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(Desvan.Motion.fade) { flag.wrappedValue = false }
        }
    }
}
