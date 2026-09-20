import AppKit
import SwiftUI

/// Which menu bar icons live in Altillo's Drawer.
@MainActor
struct SettingsDrawerPane: View {
    @Bindable private var store = MenuBarDrawerStore.shared

    private var canArrange: Bool { store.enabled && store.hasAccess && store.isSupported && !store.isLoading }

    var body: some View {
        SettingsPane(
            title: "Drawer",
            subtitle: "Keep menu bar icons out of sight, then open them from Altillo."
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    accessCard
                    drawerCard
                    if !store.drawerEntries.isEmpty {
                        hiddenIconsCard
                    }
                    if let problem = store.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Desvan.Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { store.refresh() }
    }

    private var accessCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 9) {
                Toggle(isOn: Binding(
                    get: { store.enabled },
                    set: { value in
                        store.setEnabled(value)
                        if value { AltilloSettings.shared.setEnabled(.drawer, true) }
                    }
                )) {
                    Text("Hide menu bar icons")
                        .font(Desvan.Typeface.rounded(13, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paper)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!store.enabled && (!store.hasAccess || !store.isSupported))

                if !store.hasAccess {
                    Text("Altillo needs Accessibility access to read your menu bar icons.")
                        .settingsHint()
                    Button("Allow access") { store.requestAccess() }
                        .buttonStyle(DesvanButtonStyle(kind: .primary, height: 26))
                        .padding(.top, 1)
                } else if !store.isSupported {
                    Text("Hiding is available on macOS 26. You can still use the Drawer to reach the icons Altillo finds.")
                        .settingsHint()
                } else {
                    Text("Hidden icons stay available from the Drawer tab in the notch.")
                        .settingsHint()
                }
            }
        }
    }

    private var drawerCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("Arrange the Drawer")
                    .font(Desvan.Typeface.rounded(13, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paper)

                Text("⌘-drag icons to the left of the divider | to put them in Drawer. Icons on the right stay visible.")
                    .settingsHint()

                HStack(spacing: 8) {
                    Button(store.isHidden ? "Show icons" : "Arrange icons") { store.beginArranging() }
                        .buttonStyle(DesvanButtonStyle(kind: .primary, height: 26))
                        .disabled(!canArrange)
                        .opacity(canArrange ? 1 : 0.45)
                    Button("Hide icons") { store.hide() }
                        .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 26))
                        .disabled(!canArrange || store.isHidden)
                        .opacity(canArrange && !store.isHidden ? 1 : 0.45)
                    Button("Refresh") { store.refresh() }
                        .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 26))
                }

                if store.isLoading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Looking for menu bar icons…")
                            .settingsHint()
                    }
                }
            }
        }
    }

    private var hiddenIconsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.enabled ? "In the Drawer" : "Menu bar icons")
                    .font(Desvan.Typeface.rounded(13, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paper)

                ForEach(store.drawerEntries, id: \.id) { entry in
                    HStack(spacing: 9) {
                        Image(nsImage: icon(for: entry))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Desvan.Palette.paper)
                                .lineLimit(1)
                            Text(entry.application.name)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Desvan.Palette.paperSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func icon(for entry: MenuBarEntry) -> NSImage {
        store.appIcon(for: entry)
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage()
    }
}
