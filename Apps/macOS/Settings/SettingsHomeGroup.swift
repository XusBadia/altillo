import AltilloHome
import SwiftUI

/// The Home section's own settings (docs/casa-v2.md §2, §4): connecting to Home Assistant, the favourites grid
/// that mirrors the notch with "Add from a room" under it, the doorbell that peeks, and where else a home's devices
/// can come from. The pieces live in SettingsHome*.swift.
struct SettingsHomeGroup: View {
    @Bindable var settings: AltilloSettings
    let store: HomeStore

    @State private var connect = SettingsHomeConnectModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(settings: shownSettings, store: shownStore)
    }

    private func content(settings: AltilloSettings, store: HomeStore) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHomeConnect(settings: settings, store: store, model: connect)
            if settings.homeServer != nil, !store.service.entities.isEmpty {
                SettingsCardDivider()
                SettingsHomeTiles(settings: settings, store: store)
                    .transition(.settingsReveal)
                SettingsCardDivider()
                SettingsHomeDoorbell(settings: settings, store: store)
                    .transition(.settingsReveal)
            }
            SettingsCardDivider()
            SettingsHomeConnections(store: store) { connect.signIn(store: store) }
        }
        .padding(.vertical, 6)
        .animation(SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion), value: store.connection)
        .animation(SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion),
                   value: store.service.entities.isEmpty)
    }

    // Design reviews: `-homeSettingsDemo YES` shows the demo home (its own throwaway defaults) instead of the
    // user's, so screenshots of the tiles never need a real server. Debug builds only.
    #if DEBUG
    private static let demo: HomeStore? = UserDefaults.standard.bool(forKey: "homeSettingsDemo") ? HomeStore.demo() : nil
    private var shownStore: HomeStore { Self.demo ?? store }
    private var shownSettings: AltilloSettings { Self.demo?.settings ?? settings }
    #else
    private var shownStore: HomeStore { store }
    private var shownSettings: AltilloSettings { settings }
    #endif
}
