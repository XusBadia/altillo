import AltilloDesign
import AltilloMail
import SwiftUI

struct NativeMailComposerView: View {
    @Bindable var controller: NativeMailController
    @State private var discardConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(controller.replyingTo == nil ? String(localized: "New message") : String(localized: "Reply"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Cancel") { discardConfirmation = true }.disabled(controller.isSending)
                if controller.isSending { ProgressView().controlSize(.small) }
                else {
                    Button("Send") { Task { await controller.sendDraft() } }
                        .disabled(controller.isPaused || controller.isRefreshing || controller.composeNeedsReconnect || controller.draftTo.isEmpty && controller.draftCc.isEmpty && controller.draftBcc.isEmpty)
                }
            }
            .buttonStyle(.plain)
            Picker("From", selection: $controller.composeAccountID) {
                ForEach(controller.accounts) { account in Text(verbatim: account.address).tag(Optional(account.id)) }
            }
            .disabled(controller.isSending || controller.replyingTo != nil)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("To", text: $controller.draftTo)
                    HStack {
                        TextField("Cc", text: $controller.draftCc)
                        TextField("Bcc", text: $controller.draftBcc)
                    }
                    TextField("Subject", text: $controller.draftSubject)
                    TextEditor(text: $controller.draftText)
                        .font(.system(size: 12)).scrollContentBackground(.hidden)
                        .frame(minHeight: 130)
                        .accessibilityLabel("Message body")
                    ForEach(controller.draftAttachments) { attachment in
                        HStack(spacing: 6) {
                            Image(systemName: "paperclip")
                            Text(verbatim: attachment.filename).lineLimit(1).truncationMode(.middle)
                            Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                                .foregroundStyle(Desvan.Palette.paperSecondary)
                            Spacer(minLength: 0)
                            Button { controller.removeDraftAttachment(attachment.id) } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("Remove attachment")
                        }
                        .font(.system(size: 10)).buttonStyle(.plain)
                    }
                    Button("Attach files…") { controller.chooseAttachments() }
                        .buttonStyle(.plain).font(.system(size: 11))
                    Text("Attachments: up to 18 MB total. Drafts are cleared when Mail is paused or this Mac locks.")
                        .font(.system(size: 10)).foregroundStyle(Desvan.Palette.paperSecondary)
                }
                .disabled(controller.isSending)
                .textFieldStyle(.roundedBorder)
            }
            .scrollBounceBehavior(.basedOnSize)
            if let problem = controller.composeProblem {
                Text(problem).font(.system(size: 11)).foregroundStyle(Desvan.Palette.paperSecondary).textSelection(.enabled)
            }
            if controller.composeNeedsReconnect {
                Button("Reconnect your account in Settings") { SettingsWindowController.shared.show(tab: .mail) }
                    .buttonStyle(.plain).font(.system(size: 11))
            }
        }
        .confirmationDialog("Discard this unsent message?", isPresented: $discardConfirmation) {
            Button("Discard draft", role: .destructive) { controller.closeComposer() }
            Button("Keep editing", role: .cancel) {}
        }
    }
}
