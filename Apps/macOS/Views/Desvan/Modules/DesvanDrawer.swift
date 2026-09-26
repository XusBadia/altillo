import AppKit
import SwiftUI

/// A permanent shelf above navigation, shared by every open section.
@MainActor
struct DesvanDrawerView: View {
    let model: NotchModel
    private var store: MenuBarDrawerStore { model.drawer }
    private var isDemo: Bool { model.scenario == .openDrawer }
    private var entries: [MenuBarEntry] { isDemo ? Self.demoEntries : store.drawerEntries }

    /// Only items with something real to draw: a captured glyph, a system symbol or the owner's icon.
    private var items: [StripItem] {
        entries.compactMap { entry in icon(for: entry).map { StripItem(entry: entry, icon: $0) } }
    }

    private struct StripItem: Identifiable {
        let entry: MenuBarEntry
        let icon: NSImage
        var id: String { entry.id }
    }

    var body: some View {
        let items = items
        HStack(spacing: 8) {
            Image(systemName: "archivebox")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .accessibilityHidden(true)
            if !isDemo && !store.hasAccess {
                Button("Allow access to your menu bar icons") { store.requestAccess() }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .desvanHitTarget()
            } else if !isDemo && !store.hasIconAccess {
                Button("Allow Screen Recording to show your icons") { store.requestIconAccess() }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .desvanHitTarget()
            } else if !isDemo && items.isEmpty && (store.isLoading || (!entries.isEmpty && store.iconCapture.isCapturing)) {
                ProgressView("Finding menu bar icons…")
                    .controlSize(.small)
                    .font(.system(size: 12))
            } else if items.isEmpty {
                Button { model.actions.openDrawerSettings() } label: {
                    Label("Choose icons for Altillo", systemImage: "plus.circle")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, minHeight: DesvanHitTarget.minimum, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(items) { item in
                            let entry = item.entry
                            MenuBarPopupAnchorReader { anchor in
                                Button {
                                    guard !isDemo else { return }
                                    store.activate(entry, anchor: anchor)
                                } label: {
                                    // Template (single-colour) captures take the paper tone; colour icons stay as captured.
                                    MenuBarGlyph(image: item.icon)
                                        .foregroundStyle(Desvan.Palette.paper)
                                        .padding(.horizontal, 6)
                                        .frame(minWidth: Self.iconTarget, minHeight: Self.iconTarget)
                                        .contentShape(RoundedRectangle(cornerRadius: 7))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if !isDemo {
                                        Button("Open menu") {
                                            store.activate(entry, anchor: anchor)
                                        }
                                        Divider()
                                        Button("Move to Menu Bar") { store.move(entry, toDrawer: false) }
                                            .disabled(store.movingEntryID != nil)
                                    }
                                }
                                .help("\(entry.title) · \(entry.application.name)")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel("Open \(entry.title) from \(entry.application.name)")
                                .accessibilityAction {
                                    guard !isDemo, store.movingEntryID == nil else { return }
                                    store.activate(entry, anchor: anchor)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .reportsHorizontalScroll(id: "drawer.icons", model: model)
            }
            Spacer(minLength: 0)
            if !isDemo, let problem = store.problem {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Desvan.Palette.warning)
                    .help(problem).accessibilityLabel(problem)
            }
            Button { model.actions.openDrawerSettings() } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13.5))
                    .frame(width: Self.iconTarget, height: Self.iconTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Choose Drawer icons")
            .accessibilityLabel("Choose Drawer icons")
        }
        .foregroundStyle(Desvan.Palette.paperSecondary)
        .padding(.horizontal, 12)
        .frame(height: NotchChrome.drawerHeight)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Desvan.Palette.woodRaised.opacity(0.7))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.75)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drawer")
        // Opening the notch is the lazy refresh point; nothing refreshes while it is closed.
        .onAppear { if !isDemo { store.setVisible(true, for: .notch) } }
        .onDisappear { if !isDemo { store.setVisible(false, for: .notch) } }
    }

    /// Each icon is a 30 pt target (above the 28 pt minimum, `DesvanHitTarget`) around its glyph, shown at its native
    /// menu-bar size (up to 24 pt), like the menu bar's own spacing.
    private static let iconTarget: CGFloat = 30

    private func icon(for entry: MenuBarEntry) -> NSImage? {
        if !isDemo { return store.stripIcon(for: entry) }
        let symbol = switch entry.id {
        case "demo-cloud": "icloud"
        case "demo-vpn": "lock.shield"
        case "demo-focus": "moon"
        default: "app.dashed"
        }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
    }

    private static let demoEntries = [
        MenuBarEntry(id: "demo-cloud", application: MenuBarApplication(pid: 0, bundleID: "demo.cloud", name: "Cloud drive"), title: "Cloud drive", frame: .zero),
        MenuBarEntry(id: "demo-vpn", application: MenuBarApplication(pid: 0, bundleID: "demo.vpn", name: "VPN"), title: "VPN", frame: .zero),
        MenuBarEntry(id: "demo-focus", application: MenuBarApplication(pid: 0, bundleID: "demo.focus", name: "Focus"), title: "Focus", frame: .zero),
    ]
}
