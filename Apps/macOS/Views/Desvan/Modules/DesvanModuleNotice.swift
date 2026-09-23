import AppKit
import SwiftUI

/// What a module says when it can't show anything: no permission yet, permission refused, no camera, nothing
/// playing, a free afternoon. One icon, one warm sentence and at most one button.
struct DesvanModuleNotice: View {
    var symbol: String
    var title: LocalizedStringKey
    var message: LocalizedStringKey?
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Desvan.Palette.paperTertiary)
            VStack(spacing: 2) {
                Text(title)
                    .font(Desvan.Typeface.display(13, weight: 600))
                    .foregroundStyle(Desvan.Palette.paper)
                if let message {
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(DesvanButtonStyle(kind: .primary, height: 24))
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Deep links into System Settings › Privacy & Security. Altillo can't grant itself anything; it can only take the
/// user to the right pane.
enum PrivacySettings {
    case calendars, camera, automation

    var url: URL? {
        let anchor = switch self {
        case .calendars: "Privacy_Calendars"
        case .camera: "Privacy_Camera"
        case .automation: "Privacy_Automation"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    func open() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
