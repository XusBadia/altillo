import AppKit
import SwiftUI

/// The Drawer: menu bar icons that are out of sight, still one click away.
@MainActor
struct DesvanDrawerView: View {
    let model: NotchModel

    @State private var query = ""

    private var store: MenuBarDrawerStore { model.drawer }
    private var isDemo: Bool { model.scenario == .openDrawer }

    private var entries: [MenuBarEntry] {
        let source = isDemo ? Self.demoEntries : store.drawerEntries
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }
        return source.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.application.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            if isDemo {
                iconStrip(entries: entries)
            } else {
                content
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, minHeight: 144, maxHeight: 144, alignment: .top)
        .onAppear { if !isDemo { store.refresh() } }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            if isDemo || store.hasAccess { searchField }
            Spacer(minLength: 0)
            if !isDemo {
                if store.enabled && store.isSupported {
                    Button {
                        if store.isHidden { store.reveal() } else { store.hide() }
                    } label: {
                        Label(store.isHidden ? "Show icons" : "Hide icons",
                              systemImage: store.isHidden ? "eye" : "eye.slash")
                    }
                    .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 23))
                    .disabled(!store.isHidden && (!store.hasAccess || store.isLoading))
                    .help("Show or hide the icons to the left of the Drawer divider")
                } else if store.isSupported && store.hasAccess {
                    Button("Set up") { model.actions.openDrawerSettings() }
                        .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 23))
                }
                Button { store.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 23))
                .disabled(store.isLoading || !store.hasAccess)
                .help("Refresh menu bar icons")
                .accessibilityLabel("Refresh menu bar icons")
            }
            Button { model.actions.openDrawerSettings() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 23))
            .help("Drawer settings")
            .accessibilityLabel("Drawer settings")
        }
        .frame(height: 24)
    }

    @ViewBuilder
    private var content: some View {
        if !store.hasAccess {
            notice(symbol: "hand.raised", title: "Your menu bar, within reach",
                   message: "Allow Accessibility access to read and open your menu bar icons.",
                   actionTitle: "Allow access") {
                store.requestAccess()
            }
        } else if let problem = store.problem {
            notice(symbol: "exclamationmark.triangle", title: "Your icons are still available",
                   message: problem, actionTitle: "Refresh") { store.refresh() }
        } else if store.isLoading && store.entries.isEmpty {
            ProgressView("Finding menu bar icons…")
                .controlSize(.small)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("No icons match your search.")
                .font(.system(size: 11.5))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty && !store.isSupported {
            notice(symbol: "archivebox", title: "No menu bar icons found",
                   message: "Open an app with a menu bar icon, then refresh.",
                   actionTitle: "Refresh") { store.refresh() }
        } else if entries.isEmpty {
            notice(symbol: "archivebox", title: "The Drawer is empty",
                   message: store.enabled
                       ? "⌘-drag icons left of the divider, then hide them here."
                       : "Set up Drawer to choose which menu bar icons to put away.",
                   actionTitle: "Drawer settings") { model.actions.openDrawerSettings() }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                if !store.isSupported {
                    Text("Hiding is available on macOS 26. You can open icons here.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                }
                iconStrip(entries: entries)
            }
        }
    }

    private func iconStrip(entries: [MenuBarEntry]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(entries) { entry in entryButton(entry) }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var searchField: some View {
        TextField("Search icons", text: $query)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .frame(maxWidth: 170)
            .accessibilityLabel("Search Drawer icons")
    }

    private func entryButton(_ entry: MenuBarEntry) -> some View {
        Button {
            guard !isDemo else { return }
            store.activate(entry, showMenu: false) { model.actions.send(.escape) }
        } label: {
            VStack(spacing: 4) {
                Image(nsImage: icon(for: entry))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 23, height: 23)
                Text(entry.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paper)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 78)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Desvan.Palette.woodRaised)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.75)
                    }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isDemo {
                Button("Open menu") {
                    store.activate(entry, showMenu: true) { model.actions.send(.escape) }
                }
            }
        }
        .help("Open \(entry.title) from \(entry.application.name)")
        .accessibilityLabel("Open \(entry.title) from \(entry.application.name)")
    }

    @ViewBuilder
    private func notice(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(Desvan.Typeface.display(12.5, weight: 600))
                .foregroundStyle(Desvan.Palette.paper)
            Text(message)
                .font(.system(size: 10.8))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(DesvanButtonStyle(kind: .primary, height: 23))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func icon(for entry: MenuBarEntry) -> NSImage {
        if isDemo { return Self.demoIcon(for: entry) }
        return store.appIcon(for: entry)
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage()
    }

    private static let demoEntries: [MenuBarEntry] = [
        MenuBarEntry(
            id: "demo-cloud",
            application: MenuBarApplication(pid: 0, bundleID: "demo.cloud", name: "Cloud drive"),
            title: "Cloud drive",
            frame: .zero
        ),
        MenuBarEntry(
            id: "demo-vpn",
            application: MenuBarApplication(pid: 0, bundleID: "demo.vpn", name: "VPN"),
            title: "VPN",
            frame: .zero
        ),
        MenuBarEntry(
            id: "demo-focus",
            application: MenuBarApplication(pid: 0, bundleID: "demo.focus", name: "Focus"),
            title: "Focus",
            frame: .zero
        ),
    ]

    private static func demoIcon(for entry: MenuBarEntry) -> NSImage {
        let symbol = switch entry.id {
        case "demo-cloud": "icloud"
        case "demo-vpn": "lock.shield"
        default: "moon"
        }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage()
    }
}
