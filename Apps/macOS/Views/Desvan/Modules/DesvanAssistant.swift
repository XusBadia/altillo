import AltilloDesign
import AppKit
import SwiftUI

/// The «Ask» tab: a question on a paper slip, the answer written under the bulb, and a prompt field at the bottom.
///
/// Answers come from Apple Intelligence on this Mac and can look at the shelf, the calendar, the music and the
/// clipboard (`AssistantTools`). Every finished answer can be copied or put up on the shelf, where it becomes a note
/// you can drag anywhere. The store only works while this view is on screen, except for an answer already on its way.
struct DesvanAssistantView: View {
    let model: NotchModel

    @FocusState private var isFieldFocused: Bool

    private var store: AssistantStore { model.assistant }
    private var isDemo: Bool { model.scenario == .openAssistant }

    /// The real conversation; the design scenario falls back to a sample so the look can be reviewed.
    private var exchanges: [AssistantStore.Exchange] {
        if store.exchanges.isEmpty && isDemo { return [.sample] }
        return store.exchanges
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                store.start()
                takeFocusRequest()
            }
            .onDisappear {
                store.stop()
                store.isFieldFocused = false
            }
            .onChange(of: store.focusRequest) { takeFocusRequest() }
            .onChange(of: isFieldFocused) { _, focused in
                store.isFieldFocused = focused
                if focused { model.actions.takeKeyboardFocus() }
            }
            .onChange(of: store.exchanges.last?.status) { _, status in
                announce(status)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch isDemo ? AssistantStore.Availability.available : store.availability {
        case .available:
            VStack(spacing: 7) {
                if exchanges.isEmpty {
                    DesvanAssistantWelcome(suggestions: store.suggestions) { suggestion in
                        store.send(suggestion.prompt)
                    }
                } else {
                    DesvanAssistantConversation(model: model, exchanges: exchanges)
                }
                promptBar
            }
        case .appleIntelligenceOff:
            DesvanModuleNotice(
                symbol: "sparkle",
                title: "Apple Intelligence is off",
                message: "Turn it on and I'll answer right here, privately, on this Mac.",
                actionTitle: "Open Settings"
            ) {
                AppleIntelligenceSettings.open()
            }
        case .modelNotReady:
            DesvanModuleNotice(
                symbol: "arrow.down.circle",
                title: "Getting ready…",
                message: "Apple Intelligence is still settling in on this Mac. I'll be here as soon as it's done."
            )
        case .deviceNotEligible:
            DesvanModuleNotice(
                symbol: "sparkle",
                title: "This Mac can't ask",
                message: "The assistant needs Apple Intelligence, which this Mac doesn't support."
            )
        case .unknown:
            Color.clear
        }
    }

    // MARK: - Prompt

    private var promptBar: some View {
        HStack(spacing: 6) {
            if !store.exchanges.isEmpty {
                Button {
                    store.newConversation()
                    isFieldFocused = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
                .help("New conversation")
                .accessibilityLabel("New conversation")
                .transition(.opacity)
            }
            DesvanPromptField(
                text: Bindable(store).draft,
                isFocused: $isFieldFocused,
                onSubmit: send,
                onClick: { model.actions.takeKeyboardFocus() }
            )
            sendButton
        }
        .frame(height: 28)
    }

    private var sendButton: some View {
        let isResponding = store.isResponding
        let isEmpty = store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            if isResponding { store.cancel() } else { send() }
        } label: {
            Image(systemName: isResponding ? "stop.fill" : "arrow.up")
                .font(.system(size: isResponding ? 10 : 12, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
                .foregroundStyle(Desvan.Palette.bulbInk)
                .background {
                    Circle()
                        .fill(Desvan.Palette.bulb.opacity(isEmpty && !isResponding ? 0.35 : 0.95))
                        .overlay { Circle().strokeBorder(Color(hex: 0xFFE2A8).opacity(0.6), lineWidth: 0.5) }
                        .shadow(color: Desvan.Palette.bulb.opacity(isEmpty && !isResponding ? 0 : 0.4), radius: 7, y: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isEmpty && !isResponding)
        .help(isResponding ? "Stop" : "Ask")
        .accessibilityLabel(isResponding ? "Stop answering" : "Ask")
    }

    private func send() {
        guard !store.isResponding else { return }
        store.send()
    }

    // MARK: - Focus and VoiceOver

    /// The shortcut summoned the assistant: straight into the field (also when the request came before the view).
    private func takeFocusRequest() {
        guard store.takeFocusRequest() else { return }
        model.actions.takeKeyboardFocus()
        // The panel has to be key before the field can take focus; give AppKit a turn.
        Task { @MainActor in
            await Task.yield()
            isFieldFocused = true
        }
    }

    private func announce(_ status: AssistantStore.Exchange.Status?) {
        guard let last = store.exchanges.last else { return }
        switch status {
        case .done:
            AccessibilityNotification.Announcement(AssistantFormat.plainText(last.answer)).post()
        case let .failed(failure):
            AccessibilityNotification.Announcement(failure.message).post()
        default:
            break
        }
    }
}

// MARK: - Welcome

/// Nothing asked yet: the bulb, one warm line, and a few questions built from what's actually up here.
private struct DesvanAssistantWelcome: View {
    let suggestions: [AssistantSuggestion]
    let ask: (AssistantSuggestion) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                DesvanBulbGlyph(size: 17, lit: 1)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("Ask the attic")
                        .font(Desvan.Typeface.display(14, weight: 600))
                        .foregroundStyle(Desvan.Palette.paper)
                    Text("Privately, on this Mac. I can look at your shelf, calendar, music and clipboard.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)

            // As many chips as fit on one row, in order of relevance.
            ViewThatFits(in: .horizontal) {
                ForEach((1...max(1, suggestions.count)).reversed(), id: \.self) { count in
                    chips(Array(suggestions.prefix(count)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chips(_ shown: [AssistantSuggestion]) -> some View {
        HStack(spacing: 6) {
            ForEach(shown) { suggestion in
                DesvanSuggestionChip(suggestion: suggestion) { ask(suggestion) }
            }
        }
        .fixedSize()
    }
}

/// A ready-made question on a small wood tile. The icon is lit by the bulb.
private struct DesvanSuggestionChip: View {
    let suggestion: AssistantSuggestion
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: suggestion.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.bulb.opacity(isHovering ? 1 : 0.8))
                Text(verbatim: suggestion.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isHovering ? Desvan.Palette.paper : Desvan.Palette.paper.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 25)
            .desvanCard(radius: 12.5, fill: isHovering ? Desvan.Palette.woodRaised : Desvan.Palette.wood, grain: 0.6)
            .offset(y: isHovering && !reduceMotion ? -1 : 0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .help(suggestion.prompt)
        .accessibilityLabel(suggestion.title)
        .accessibilityHint("Asks this question")
    }
}

// MARK: - Conversation

/// The exchanges, newest at the bottom, following the answer as it's written.
private struct DesvanAssistantConversation: View {
    let model: NotchModel
    let exchanges: [AssistantStore.Exchange]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bottom = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(exchanges) { exchange in
                        DesvanExchangeView(
                            model: model,
                            exchange: exchange,
                            activity: exchange.id == exchanges.last?.id ? model.assistant.activity : nil
                        )
                        .id(exchange.id)
                    }
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(.top, 6)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            // The top edge fades into the tabs instead of cutting a line of text in half.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 8)
                    Color.black
                }
            }
            .onAppear { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            .onChange(of: exchanges.count) {
                withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(Self.bottom, anchor: .bottom)
                }
            }
            // While words arrive, follow them without animating every token.
            .onChange(of: exchanges.last?.answer) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            .onChange(of: exchanges.last?.status) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
        }
    }
}

/// One question (a paper slip) and its answer (plain paper-white text under it), with the actions once it's done.
private struct DesvanExchangeView: View {
    let model: NotchModel
    let exchange: AssistantStore.Exchange
    /// The tool running for this exchange, if it's the live one.
    let activity: AssistantActivity?

    @State private var copied = false
    @State private var putUp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DesvanQuestionSlip(id: exchange.id, text: exchange.question)
                .frame(maxWidth: .infinity, alignment: .trailing)
            answer
            if exchange.hasAnswer {
                actions
            }
        }
    }

    @ViewBuilder
    private var answer: some View {
        if exchange.status == .thinking {
            DesvanThinkingLine(activity: activity)
        } else if !exchange.answer.isEmpty {
            Text(AssistantFormat.rendered(exchange.answer))
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(Desvan.Palette.paper)
                .tint(Desvan.Palette.bulb)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        switch exchange.status {
        case .stopped:
            Label("Stopped", systemImage: "stop.circle")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperTertiary)
        case let .failed(failure):
            Label {
                Text(verbatim: failure.message)
            } icon: {
                Image(systemName: "exclamationmark.bubble")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Desvan.Palette.warning)
            .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            Button {
                model.assistant.copy(exchange)
                model.actions.haptic(.snap)
                copied = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.6))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(Desvan.Typeface.rounded(11, weight: .semibold))
            }
            .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 20))
            .help("Copy the answer")

            Button {
                model.assistant.putUp(exchange)
                putUp = true
            } label: {
                Label(putUp ? "On the shelf" : "Put it up", systemImage: putUp ? "checkmark" : "arrow.up.to.line")
                    .font(Desvan.Typeface.rounded(11, weight: .semibold))
            }
            .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 20))
            .disabled(putUp)
            .help("Put the answer on the shelf, to drag it anywhere")

            Spacer(minLength: 6)

            // What it looked at, as quiet marks: the answer came from your things, not from thin air.
            HStack(spacing: 5) {
                ForEach(exchange.sources) { source in
                    Image(systemName: source.symbol)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                        .help(source.source)
                        .accessibilityLabel(source.source)
                }
            }
            .padding(.trailing, 4)
        }
        .padding(.leading, -8)
    }
}

/// The user's question on a slip of paper, pinned a hair off straight.
private struct DesvanQuestionSlip: View {
    let id: UUID
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Desvan.Palette.ink)
            .lineLimit(3)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
                shape.fill(Desvan.Palette.paper.opacity(0.93))
                    .grain(0.06, in: shape)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            }
            .rotationEffect(.degrees(Desvan.jitter(id) * 0.7))
            .frame(maxWidth: 360, alignment: .trailing)
            .accessibilityLabel(Text("You asked: \(text)"))
    }
}

/// "Thinking…" or what it's looking at, with the bulb gently breathing (still with Reduce Motion).
private struct DesvanThinkingLine: View {
    let activity: AssistantActivity?

    @State private var bright = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let text = activity?.progress ?? String(localized: "Thinking…")
        HStack(spacing: 7) {
            DesvanBulbGlyph(size: 11, lit: reduceMotion ? 0.8 : (bright ? 1 : 0.35))
            if let activity {
                Image(systemName: activity.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            }
            Text(verbatim: text)
                .font(.system(size: 11.5))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .contentTransition(.opacity)
        }
        .animation(Desvan.Motion.fade, value: activity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { bright = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - Prompt field

/// A single-line field set into the wood like a well, lit by the bulb while it has focus.
private struct DesvanPromptField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    /// The notch panel doesn't become key on hover; a click in the field has to ask for it.
    let onClick: () -> Void

    var body: some View {
        let focused = isFocused.wrappedValue
        HStack(spacing: 7) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(focused ? Desvan.Palette.bulb : Desvan.Palette.paperTertiary)
                .accessibilityHidden(true)
            TextField(
                "Ask",
                text: $text,
                prompt: Text("Ask about your day, your shelf, anything…").foregroundStyle(Desvan.Palette.paperTertiary)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(Desvan.Palette.paper)
            .tint(Desvan.Palette.bulb)
            .focused(isFocused)
            .onSubmit(onSubmit)
            .accessibilityLabel("Ask the assistant")
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background {
            Capsule()
                .fill(Color.black.opacity(0.4))
                .overlay {
                    // Inset: dark at the top, the wood's lip catching light at the bottom.
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [.black.opacity(0.6), Desvan.Palette.lip],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
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
        .contentShape(Capsule())
        .simultaneousGesture(TapGesture().onEnded {
            onClick()
            isFocused.wrappedValue = true
        })
    }
}
