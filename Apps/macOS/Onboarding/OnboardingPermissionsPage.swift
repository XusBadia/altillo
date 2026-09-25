import AppKit
import SwiftUI

/// Page 4 (only when the chosen sections need something): each permission on its own row, why it's needed, and
/// "Allow", which brings up the real system prompt right then, or "Later". The rows follow what the system says,
/// live: back from System Settings, a row that was allowed there shows it.
struct OnboardingPermissionsPage: View {
    let flow: OnboardingFlow
    let eyebrow: String

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                OnboardingHeader(
                    eyebrow: eyebrow,
                    title: "Only what your setup needs",
                    subtitle: "macOS asks once for each. Altillo uses them only for the sections you chose, and you can change them any time in System Settings."
                )

                if flow.permissions.isEmpty {
                    Text("Nothing to allow for this setup. If you turn on a section that needs something, it asks then.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(flow.permissions.enumerated()), id: \.element) { index, permission in
                        if index > 0 {
                            Rectangle().fill(Desvan.Palette.hairline).frame(height: 0.75)
                                .padding(.leading, 60)
                        }
                        OnboardingPermissionRow(flow: flow, permission: permission)
                    }
                }
                .desvanCard(radius: 14)
                .opacity(flow.permissions.isEmpty ? 0 : 1)
            }
            .padding(.horizontal, 30)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task { await flow.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await flow.refreshPermissions() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            // Music or Spotify just opened: Now playing can be asked for now.
            Task { await flow.refreshPermissions() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            Task { await flow.refreshPermissions() }
        }
        .onChange(of: flow.model.drawer.hasAccess) { _, _ in
            Task { await flow.refreshPermissions() }
        }
    }
}

private struct OnboardingPermissionRow: View {
    let flow: OnboardingFlow
    let permission: OnboardingPermission

    private var status: OnboardingPermissionStatus { flow.status(of: permission) }
    private var isDeferred: Bool { flow.deferred.contains(permission) }
    private var wasAsked: Bool { flow.requested.contains(permission) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            OnboardingSymbolTile(symbol: symbol, tint: status == .granted ? Desvan.Palette.done : Desvan.Palette.kraft)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Desvan.Typeface.rounded(13.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                Text(why)
                    .font(.system(size: 12))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(noteColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
        .animation(Desvan.Motion.fade, value: status)
        .animation(Desvan.Motion.fade, value: isDeferred)
    }

    @ViewBuilder
    private var trailing: some View {
        switch status {
        case .granted:
            OnboardingDoneLabel(text: "Allowed")
        case .denied:
            Button("System Settings") { flow.openSystemSettings(for: permission) }
                .buttonStyle(DesvanButtonStyle(kind: .ghost))
        case .notNow:
            EmptyView()
        case .notAsked:
            if permission == .accessibility, wasAsked {
                Button("System Settings") { flow.openSystemSettings(for: permission) }
                    .buttonStyle(DesvanButtonStyle(kind: .ghost))
            } else {
                HStack(spacing: 4) {
                    if !isDeferred {
                        Button("Later") { flow.putOff(permission) }
                            .buttonStyle(DesvanButtonStyle(kind: .quiet))
                            .accessibilityLabel("Later: \(title)")
                    }
                    Button("Allow") { Task { await flow.request(permission) } }
                        .buttonStyle(DesvanButtonStyle(kind: isDeferred ? .ghost : .primary))
                        .disabled(flow.inFlight.contains(permission))
                        .accessibilityLabel("Allow \(title)")
                }
            }
        }
    }

    private var symbol: String {
        switch permission {
        case .calendar: "calendar"
        case .automation: "music.note"
        case .camera: "camera"
        case .accessibility: "accessibility"
        }
    }

    private var title: String {
        switch permission {
        case .calendar: String(localized: "Calendar")
        case .automation: String(localized: "Music and Spotify")
        case .camera: String(localized: "Camera")
        case .accessibility: String(localized: "Accessibility")
        }
    }

    private var why: String {
        switch permission {
        case .calendar:
            String(localized: "For your next event beside the notch and your day in Calendar. Events never leave your Mac.")
        case .automation:
            String(localized: "For Now playing: to show what's on and play, pause or skip from the notch.")
        case .camera:
            String(localized: "For the mirror, to check yourself before a call. The image never leaves your Mac.")
        case .accessibility:
            String(localized: "For the Drawer: to reach the menu bar icons the notch hides, and open their menus.")
        }
    }

    private var note: String? {
        switch status {
        case .granted:
            return nil
        case .denied:
            return String(localized: "Turned off in System Settings › Privacy & Security.")
        case .notNow:
            switch permission {
            case .automation:
                return String(localized: "Neither Music nor Spotify is open. Altillo asks the first time you play something with Now playing open.")
            case .camera:
                return String(localized: "No camera connected. The mirror asks when you use one.")
            case .calendar, .accessibility:
                return nil
            }
        case .notAsked:
            if permission == .accessibility, wasAsked {
                return String(localized: "Turn on Altillo in Privacy & Security › Accessibility. This page notices when you do.")
            }
            if isDeferred { return laterNote }
            return nil
        }
    }

    private var laterNote: String {
        switch permission {
        case .calendar: String(localized: "Later, then. Calendar asks the first time you open it.")
        case .automation: String(localized: "Later, then. Now playing asks the first time you open it.")
        case .camera: String(localized: "Later, then. The mirror asks the first time you open it.")
        case .accessibility: String(localized: "Later, then. The Drawer asks when you open it.")
        }
    }

    private var noteColor: Color {
        status == .denied ? Desvan.Palette.warning : Desvan.Palette.paperTertiary
    }
}
