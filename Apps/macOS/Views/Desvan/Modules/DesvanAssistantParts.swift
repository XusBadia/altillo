import AltilloDesign
import AppKit
import SwiftUI

// Phase 13 pieces of the Ask section: the attachment chip and the mic inside the prompt field, what an action did
// under an answer, and the saved answers.

// MARK: - Attachment chip

/// What's attached, on a small paper tag at the start of the field, with a × to take it off.
struct DesvanAttachmentChip: View {
    let attachment: AssistantAttachment?
    let isReading: Bool
    let remove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            if isReading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Desvan.Palette.ink)
                    .environment(\.colorScheme, .light)
                Text("Reading…")
            } else if let attachment {
                Image(systemName: attachment.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(verbatim: AssistantFormat.shortName(attachment.name, limit: 20))
                    .lineLimit(1)
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Desvan.Palette.ink.opacity(isHovering ? 0.18 : 0.08)))
                        .desvanHitTarget(28)
                }
                .buttonStyle(.plain)
                .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
                .help("Remove the attachment")
                .accessibilityLabel(Text("Remove \(attachment.name)"))
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Desvan.Palette.ink)
        .padding(.leading, 7)
        .padding(.trailing, isReading ? 8 : 3)
        .frame(height: 22)
        .background {
            let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
            shape.fill(Desvan.Palette.paper.opacity(0.93))
                .grain(0.06, in: shape)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
        }
        .fixedSize()
        .help(attachment.map { "\($0.name) · \($0.description)" } ?? "")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(attachment.map { Text("Attached: \($0.name)") } ?? Text("Reading what you dropped"))
    }
}

// MARK: - Mic

/// The mic at the end of the field: a click starts listening, the words appear in the field as they're heard,
/// and it stops when the user goes quiet or clicks again. Its menu chooses whether the question is sent then.
struct DesvanMicButton: View {
    let dictation: AssistantDictation
    @Binding var sendsWhenDone: Bool
    /// A frozen level for the design scenario (`-demoAssistant listening`): the meter up, nothing recording.
    var demoLevel: Double?
    let toggle: () -> Void

    @State private var isHovering = false

    private var isListening: Bool {
        demoLevel != nil || dictation.state == .listening || dictation.state == .finishing
    }

    var body: some View {
        Button(action: toggle) {
            ZStack {
                if isListening {
                    DesvanLevelMeter(level: demoLevel ?? dictation.level, isFinishing: dictation.state == .finishing)
                } else {
                    Image(systemName: dictation.state == .preparing ? "mic.badge.ellipsis" : "mic")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isHovering ? Desvan.Palette.paper : Desvan.Palette.paperTertiary)
                }
            }
            .frame(width: 26, height: 26)
            .background {
                Circle().fill(isListening ? Desvan.Palette.bulb.opacity(0.22) : Color.white.opacity(isHovering ? 0.08 : 0))
            }
            .contentShape(Circle())
            .desvanHitTarget()
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .contextMenu {
            Toggle("Send when I stop talking", isOn: $sendsWhenDone)
        }
        .help(isListening ? "Stop dictating" : "Dictate, privately on this Mac")
        .accessibilityLabel(isListening ? "Stop dictating" : "Dictate")
        .accessibilityHint(isListening ? "Keeps what you said in the field" : "Listens on this Mac and writes what you say")
    }
}

/// Four bars that follow the voice. With Reduce Motion nothing grows or moves: one dot brightens with the voice.
struct DesvanLevelMeter: View {
    let level: Double
    let isFinishing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Each bar answers a little differently, so the meter reads as a voice rather than one block.
    private static let weights: [Double] = [0.55, 1, 0.8, 0.45]

    var body: some View {
        Group {
            if reduceMotion {
                Circle()
                    .fill(Desvan.Palette.bulb.opacity(isFinishing ? 0.4 : 0.45 + 0.55 * level))
                    .frame(width: 8, height: 8)
            } else {
                HStack(spacing: 2) {
                    ForEach(Self.weights.indices, id: \.self) { index in
                        Capsule()
                            .fill(Desvan.Palette.bulb)
                            .frame(width: 2.5, height: height(for: Self.weights[index]))
                    }
                }
                .animation(.easeOut(duration: 0.1), value: level)
            }
        }
        .opacity(isFinishing ? 0.5 : 1)
        .accessibilityHidden(true)
    }

    private func height(for weight: Double) -> CGFloat {
        guard !isFinishing else { return 3 }
        return 3 + CGFloat(min(1, level * weight * 1.4)) * 11
    }
}

// MARK: - What an action did

/// Under an answer that made something: what it made, whatever the model wrote, with Undo.
struct DesvanReceiptRow: View {
    let receipt: AssistantActionReceipt
    /// What VoiceOver reads for the whole card instead of its parts: the answer it stands for (an agent reply).
    var spokenAs: String?
    let undo: () -> Void
    /// The one-click follow-up ("Tomorrow at 9:00") when nothing was made.
    var accept: () -> Void = {}

    var body: some View {
        if let spokenAs {
            card
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: spokenAs))
        } else {
            card
                .accessibilityElement(children: .contain)
        }
    }

    private var card: some View {
        HStack(spacing: 7) {
            Image(systemName: receipt.isUndone ? "arrow.uturn.backward" : receipt.symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(receipt.isUndone ? Desvan.Palette.paperTertiary : (receipt.offer != nil || receipt.undoFailed ? Desvan.Palette.warning : Desvan.Palette.done))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: receipt.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(receipt.isUndone ? Desvan.Palette.paperTertiary : Desvan.Palette.paper)
                    .strikethrough(receipt.isUndone)
                    .lineLimit(1)
                Group {
                    if receipt.isUndone {
                        Text("Undone")
                    } else if receipt.undoFailed {
                        Text(receipt.offer == nil ? "Couldn't undo it. Remove it in Reminders." : "Couldn't make it. Try again.")
                    } else if let detail = receipt.detail {
                        Text(verbatim: detail)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 6)
            if case let .reminder(_, due)? = receipt.offer {
                Button(action: accept) {
                    Label {
                        Text("Tomorrow at \(AssistantReminders.userTime(due, calendar: .current))")
                    } icon: {
                        Image(systemName: "arrow.forward")
                    }
                    .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                }
                .buttonStyle(DesvanButtonStyle(kind: .primary, height: 28))
                .help("Make this reminder for tomorrow at the same time")
            } else if receipt.undo != nil && !receipt.isUndone && !receipt.undoFailed {
                Button(action: undo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                }
                .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 28))
                .help("Remove this reminder")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .desvanCard(radius: 10, fill: Desvan.Palette.wood, grain: 0.5)
    }
}

// MARK: - Saved answers

/// The answers the user kept, newest first, each with copy, put up and delete.
struct DesvanSavedAnswers: View {
    let model: NotchModel
    /// Sample answers for the design scenario (`-demoAssistant saved|savedEmpty`).
    var demoAnswers: [AssistantSavedAnswer]?

    private var store: AssistantStore { model.assistant }

    var body: some View {
        let answers = demoAnswers ?? store.saved.answers
        if answers.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "bookmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Desvan.Palette.bulb.opacity(0.8))
                Text("Nothing saved yet")
                    .font(Desvan.Typeface.display(15, weight: 600))
                    .foregroundStyle(Desvan.Palette.paper)
                Text("Save an answer to keep it here. Only what you save is kept, on this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(answers) { answer in
                        DesvanSavedRow(answer: answer, model: model)
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 16)
                    Color.black
                }
            }
        }
    }
}

private struct DesvanSavedRow: View {
    let answer: AssistantSavedAnswer
    let model: NotchModel

    @State private var isHovering = false
    @State private var copied = false
    @State private var putUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(verbatim: answer.question)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(answer.savedAt, format: .dateTime.day().month(.abbreviated))
                    .font(.system(size: 11))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            }
            Text(AssistantFormat.rendered(answer.answer))
                .font(.system(size: 12.5))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .tint(Desvan.Palette.bulb)
                .lineLimit(isHovering ? 6 : 2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 2) {
                Button {
                    model.assistant.copy(answer)
                    model.actions.haptic(.snap)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.6))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
                .help("Copy the answer")

                Button {
                    model.assistant.putUp(answer)
                    putUp = true
                } label: {
                    Label(putUp ? "On the shelf" : "Put it up", systemImage: putUp ? "checkmark" : "arrow.up.to.line")
                        .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
                .disabled(putUp)
                .help("Put the answer on the shelf, to drag it anywhere")

                Spacer(minLength: 4)

                Button(role: .destructive) {
                    withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) {
                        model.assistant.delete(answer)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
                .help("Delete this saved answer")
                .accessibilityLabel("Delete")
            }
            .padding(.leading, -10)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .desvanCard(radius: 12, fill: isHovering ? Desvan.Palette.woodRaised : Desvan.Palette.wood, grain: 0.5)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Saved: \(answer.question)"))
    }
}
