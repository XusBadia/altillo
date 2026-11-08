import AltilloDesign
import AltilloMail
import SwiftUI

/// A short-lived inbox of new events, not a mail archive. Authentication actions are revalidated by the store.
struct DesvanMailView: View {
    let model: NotchModel
    private var store: MailStore { model.mail }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("New mail").font(Desvan.Typeface.rounded(12, weight: .semibold))
                Spacer()
                if !store.messages.isEmpty {
                    Button("Clear") { store.clear() }.buttonStyle(.plain)
                }
                Button { SettingsWindowController.shared.show(tab: .mail) } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mail settings")
            }
            .foregroundStyle(Desvan.Palette.paperSecondary)
            if let problem = store.problem {
                Text(problem).font(.system(size: 12)).foregroundStyle(Desvan.Palette.paperSecondary)
            }
            if store.messages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "envelope.open").font(.system(size: 26)).foregroundStyle(Desvan.Palette.bulb)
                    Text("Your next message will appear here").font(Desvan.Typeface.rounded(14, weight: .semibold))
                    Text("Connect Apple Mail in Settings. Messages stay only in memory for five minutes.")
                        .font(.system(size: 12)).foregroundStyle(Desvan.Palette.paperSecondary)
                        .multilineTextAlignment(.center)
                    Button("Set up Apple Mail") { SettingsWindowController.shared.show(tab: .mail) }
                        .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.messages) { message in card(message) }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .foregroundStyle(Desvan.Palette.paper)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .desvanCard(radius: 16)
    }

    private func card(_ message: MailEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(message.sender).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Button { store.dismiss(message) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .accessibilityLabel("Dismiss message")
                    .frame(width: 28, height: 28)
            }
            Text(message.subject).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                if let code = message.code {
                    Button { store.copyCode(for: message) } label: {
                        Label(code, systemImage: "doc.on.doc").monospacedDigit()
                    }
                    .help("Copy sign-in code")
                    .accessibilityLabel("Copy sign-in code")
                    .accessibilityValue(code)
                }
                if let url = message.magicLink {
                    Button { store.openLink(for: message) } label: {
                        Label(url.host ?? String(localized: "Open link"), systemImage: "arrow.up.right")
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .help("Open sign-in link in your browser")
                }
                Button("Open in Mail") { store.openMessage(for: message) }
            }
            .font(.system(size: 11.5, weight: .medium))
            .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Desvan.Palette.paper.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
}
