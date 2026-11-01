import AltilloDesign
import AltilloMail
import SwiftUI

struct DesvanNativeMailView: View {
    @Bindable var controller: NativeMailController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if controller.selectedMessage != nil {
                    Button { controller.closeReader() } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Back to messages")
                }
                Text("Mail").font(Desvan.Typeface.rounded(12, weight: .semibold))
                Spacer()
                if !controller.accounts.isEmpty, controller.selectedMessage == nil {
                    Menu {
                        Picker("Mail account", selection: $controller.selectedAccountID) {
                            Text("All accounts").tag(UUID?.none)
                            ForEach(controller.accounts) { account in Text(account.address).tag(Optional(account.id)) }
                        }
                    } label: {
                        Image(systemName: controller.selectedAccountID == nil ? "tray.2" : "person.crop.circle")
                    }
                    .accessibilityLabel("Choose mail account")
                }
                if controller.isRefreshing { ProgressView().controlSize(.mini) }
                else {
                    Button { Task { await controller.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(!controller.canRefresh)
                        .accessibilityLabel("Refresh mail")
                }
                Button { SettingsWindowController.shared.show(tab: .mail) } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Mail settings")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Desvan.Palette.paperSecondary)
            if let message = controller.selectedMessage { reader(message) }
            else if controller.accounts.isEmpty {
                empty("Connect your email account", detail: "Read Google or Microsoft mail in Altillo, with your account's permission.")
            } else if controller.isPaused {
                empty("Mail is paused", detail: "Enable Mail in Settings to refresh your inbox.")
            } else {
                if controller.states.values.contains(.offline) {
                    Text("Offline. Messages already loaded in this session are still available.")
                        .font(.system(size: 11)).foregroundStyle(Desvan.Palette.paperSecondary)
                }
                if controller.states.values.contains(.reconnect) || controller.states.values.contains(.denied) {
                    Button("Reconnect your account in Settings") { SettingsWindowController.shared.show(tab: .mail) }
                        .buttonStyle(.plain).font(.system(size: 11))
                }
                if controller.visibleMessages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray").font(.system(size: 24))
                        Text(controller.isRefreshing ? String(localized: "Loading your inbox…") : String(localized: "No recent messages"))
                            .font(.system(size: 13))
                        Text("Your first sync loads recent mail quietly. Only new arrivals show a glance.")
                            .font(.system(size: 11)).foregroundStyle(Desvan.Palette.paperSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(controller.visibleMessages) { message in
                                Button { controller.read(message) } label: { row(message) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .padding(14)
        .foregroundStyle(Desvan.Palette.paper)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .desvanCard(radius: 16)
        .onAppear { controller.isInboxVisible = true }
        .onDisappear { controller.isInboxVisible = false }
    }

    private func row(_ message: NativeMailSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                if message.isUnread { Circle().fill(Desvan.Palette.bulb).frame(width: 5, height: 5) }
                Text(verbatim: message.sender).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Text(message.receivedAt, style: .time).font(.system(size: 10))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
            }
            Text(verbatim: message.subject.isEmpty ? String(localized: "(No subject)") : message.subject)
                .font(.system(size: 12, weight: message.isUnread ? .semibold : .regular)).lineLimit(2)
            if !message.preview.isEmpty {
                Text(verbatim: message.preview).font(.system(size: 11)).lineLimit(2)
                    .foregroundStyle(Desvan.Palette.paperSecondary)
            }
            if controller.accounts.count > 1 {
                Text(verbatim: controller.accountName(for: message.key.accountID))
                    .font(.system(size: 10)).lineLimit(1).foregroundStyle(Desvan.Palette.paperSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Desvan.Palette.paper.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private func reader(_ message: NativeMailSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(verbatim: message.subject.isEmpty ? String(localized: "(No subject)") : message.subject)
                .font(.system(size: 14, weight: .semibold)).lineLimit(3).textSelection(.enabled)
            Text(verbatim: message.sender).font(.system(size: 11)).textSelection(.enabled)
            Text(message.receivedAt, format: .dateTime.day().month().hour().minute())
                .font(.system(size: 10)).foregroundStyle(Desvan.Palette.paperSecondary)
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                HStack(spacing: 8) {
                    if let envelope = controller.actionEnvelope(for: message) {
                        if let code = envelope.code {
                            Button { controller.copyCode(for: message) } label: {
                                Label(code, systemImage: "doc.on.doc").monospacedDigit()
                            }
                            .accessibilityLabel("Copy sign-in code").accessibilityValue(code)
                        }
                        if let host = envelope.magicLink?.host {
                            Button { controller.openSignInLink(for: message) } label: {
                                Label(host, systemImage: "arrow.up.right").lineLimit(1)
                            }
                            .accessibilityLabel("Open sign-in link")
                        }
                    }
                    if message.webURL != nil { Button("Open original") { controller.openOriginal(message) } }
                }
                .font(.system(size: 11))
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
            }
            if controller.isReading { ProgressView().controlSize(.small) }
            if let problem = controller.readerProblem {
                Text(problem).font(.system(size: 11)).foregroundStyle(Desvan.Palette.paperSecondary)
                Button("Try again") { controller.read(message) }.buttonStyle(.plain).font(.system(size: 11))
            }
            ScrollView {
                Text(verbatim: controller.selectedContent?.text ?? message.preview)
                    .font(.system(size: 12)).lineSpacing(3).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            if controller.selectedContent?.isTruncated == true {
                Text("This message was shortened. Open the original to read all of it.")
                    .font(.system(size: 10)).foregroundStyle(Desvan.Palette.paperSecondary)
            }
            Text("Reading here leaves the message's read status unchanged.")
                .font(.system(size: 10)).foregroundStyle(Desvan.Palette.paperSecondary)
        }
    }

    private func empty(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "envelope.open").font(.system(size: 26)).foregroundStyle(Desvan.Palette.bulb)
            Text(title).font(Desvan.Typeface.rounded(14, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(Desvan.Palette.paperSecondary)
                .multilineTextAlignment(.center)
            Button("Connect an account") { SettingsWindowController.shared.show(tab: .mail) }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
