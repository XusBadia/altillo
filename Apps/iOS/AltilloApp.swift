import AltilloDesign
import SwiftUI

@main
struct AltilloApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Placeholder until Altillo for iOS starts (phase 5).
struct ContentView: View {
    var body: some View {
        ContentUnavailableView("Altillo", systemImage: "square.stack.3d.up", description: Text("Próximamente en iPhone y iPad."))
    }
}
