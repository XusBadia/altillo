import SwiftUI

@main
struct AltilloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            AppMenu(coordinator: appDelegate.coordinator)
        } label: {
            Image(nsImage: Self.menuBarIcon)
                .accessibilityLabel("Altillo")
        }
        Window("Spike log", id: SpikeLogView.windowID) {
            SpikeLogView(log: .shared)
        }
        .defaultSize(width: 720, height: 480)
    }

    /// Status items use an image's point size, even when its source is vector art.
    private static var menuBarIcon: NSImage {
        let image = (NSImage(named: "MenuBarIcon")?.copy() as? NSImage) ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}

/// Menu bar menu. During phase 0 it also drives the design-review scenarios.
struct AppMenu: View {
    let coordinator: NotchCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Altillo") { coordinator.model.actions.send(.click) }
            .keyboardShortcut("a", modifiers: [.command, .option])
        Button("Customize the Notch…") { coordinator.beginEditing() }
        Button("Settings…") { SettingsWindowController.shared.show() }
            .keyboardShortcut(",", modifiers: .command)
        Button("Drawer Settings…") { SettingsWindowController.shared.show(tab: .drawer) }
        Button("Check for Updates…") { Updater.shared.checkForUpdates() }
            .disabled(!Updater.shared.canCheckForUpdates)
            .help(
                Updater.shared.isConfigured
                    ? "Check for a newer version of Altillo."
                    : "This build has no update feed configured."
            )
        if coordinator.model.drawer.enabled {
            Button(coordinator.model.drawer.isHidden ? "Show menu bar icons" : "Hide menu bar icons") {
                if coordinator.model.drawer.isHidden { coordinator.model.drawer.reveal() }
                else { coordinator.model.drawer.hide() }
            }
        }
        Divider()
        Button(coordinator.model.undoShelfTitle) { coordinator.model.actions.undo() }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!coordinator.model.canUndoShelfChange)
        Button(coordinator.model.redoShelfTitle) { coordinator.model.actions.redo() }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!coordinator.model.canRedoShelfChange)
        Divider()
        Menu("Design review") {
            ForEach(DesignScenario.allCases) { scenario in
                Button(scenario.title) { coordinator.show(scenario) }
            }
            Divider()
            Button("Back to normal") { coordinator.show(nil) }
        }
        Button("Drag spike log…") {
            NSApp.activate()
            openWindow(id: SpikeLogView.windowID)
        }
        Divider()
        Button("Empty the shelf") { coordinator.model.actions.clearShelf() }
            .disabled(coordinator.model.shelf.isEmpty)
        Divider()
        Button("Quit Altillo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
