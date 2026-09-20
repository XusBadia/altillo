import SwiftUI

@main
struct AltilloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Altillo", systemImage: "square.stack.3d.up") {
            AppMenu(coordinator: appDelegate.coordinator)
        }
        Window("Registro de pruebas", id: SpikeLogView.windowID) {
            SpikeLogView(log: .shared)
        }
        .defaultSize(width: 720, height: 480)
    }
}

/// Menu bar menu. During phase 0 it also drives the design-review scenarios.
struct AppMenu: View {
    let coordinator: NotchCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Abrir Altillo") { coordinator.model.actions.send(.click) }
            .keyboardShortcut("a", modifiers: [.command, .option])
        Button("Ajustes…") { SettingsWindowController.shared.show() }
            .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button(coordinator.model.undoShelfTitle) { coordinator.model.actions.undo() }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!coordinator.model.canUndoShelfChange)
        Button(coordinator.model.redoShelfTitle) { coordinator.model.actions.redo() }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!coordinator.model.canRedoShelfChange)
        Divider()
        Menu("Revisión de diseño") {
            ForEach(DesignScenario.allCases) { scenario in
                Button(scenario.title) { coordinator.show(scenario) }
            }
            Divider()
            Button("Volver al modo normal") { coordinator.show(nil) }
        }
        Button("Registro de pruebas de arrastre…") {
            NSApp.activate()
            openWindow(id: SpikeLogView.windowID)
        }
        Divider()
        Button("Vaciar el altillo") { coordinator.model.actions.clearShelf() }
            .disabled(coordinator.model.shelf.isEmpty)
        Divider()
        Button("Salir de Altillo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
