import AppKit
import SwiftUI

/// The search field of the utility sections (Clipboard, Shortcuts): an inset capsule like Ask's prompt, with a
/// magnifying glass that lights up while typing and a clear button once there's something to clear.
///
/// The notch panel doesn't become key on hover, so a click in the field asks for keyboard focus (`onClick`); while
/// the field is focused or holds a search, the section keeps the notch open (`NotchModel.holdsOpen`).
struct DesvanUtilitySearchField: View {
    let placeholder: LocalizedStringKey
    let accessibilityLabel: LocalizedStringKey
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}
    let onClick: () -> Void

    var body: some View {
        let focused = isFocused.wrappedValue
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(focused ? Desvan.Palette.bulb : Desvan.Palette.paperTertiary)
                .accessibilityHidden(true)
            TextField(accessibilityLabel, text: $text, prompt: Text(placeholder).foregroundStyle(Desvan.Palette.paperTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Desvan.Palette.paper)
                .tint(Desvan.Palette.bulb)
                .focused(isFocused)
                .onSubmit(onSubmit)
                .accessibilityLabel(accessibilityLabel)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                }
                .buttonStyle(.plain)
                .desvanHitTarget()
                .help("Clear the search")
                .accessibilityLabel("Clear the search")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background {
            Capsule()
                .fill(Color.black.opacity(0.4))
                .overlay {
                    // Inset: dark at the top, the wood's lip catching light at the bottom.
                    Capsule().strokeBorder(
                        LinearGradient(colors: [.black.opacity(0.6), Desvan.Palette.lip],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75
                    )
                }
                .overlay {
                    Capsule()
                        .strokeBorder(Desvan.Palette.bulb.opacity(focused ? 0.55 : 0), lineWidth: 1)
                        .shadow(color: Desvan.Palette.bulb.opacity(focused ? 0.35 : 0), radius: 6)
                }
        }
        .animation(Desvan.Motion.hover, value: focused)
        .animation(Desvan.Motion.fade, value: text.isEmpty)
        .contentShape(Capsule())
        .simultaneousGesture(TapGesture().onEnded {
            onClick()
            isFocused.wrappedValue = true
        })
    }
}

/// ↑ / ↓ / Return for a section's list while the open notch has keyboard focus. SwiftUI's `onKeyPress` doesn't
/// reliably see the arrows once a text field's editor has them, so this listens to the panel's key events directly
/// (only the notch panel's, only while the view is on screen) and swallows the ones it handles.
struct DesvanListKeys: ViewModifier {
    /// Return true when the key was used.
    let onMove: (Int) -> Bool
    let onReturn: () -> Bool

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: install)
            .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil else { return }
        let move = onMove, submit = onReturn
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window is NotchPanel else { return event }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard flags.isEmpty else { return event }
            let keyCode = event.keyCode
            let used = MainActor.assumeIsolated { () -> Bool in
                switch keyCode {
                case 126: move(-1) // ↑
                case 125: move(1) // ↓
                case 36, 76: submit() // Return, Enter
                default: false
                }
            }
            return used ? nil : event
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
