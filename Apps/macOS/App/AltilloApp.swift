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
        Divider()
        Button("Salir de Altillo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
