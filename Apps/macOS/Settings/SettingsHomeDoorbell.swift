import AltilloHome
import SwiftUI

/// The doorbell that peeks: what rings, the camera whose picture comes with it, and whether to peek.
struct SettingsHomeDoorbell: View {
    @Bindable var settings: AltilloSettings
    let store: HomeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSubheading("Doorbell")
            HStack(spacing: 12) {
                Text("Rings with").settingsRowTitle()
                Spacer(minLength: 12)
                Picker(selection: trigger) {
                    Text("None").tag(String?.none)
                    ForEach(store.doorbellCandidates) { entity in
                        Text(verbatim: entity.name).tag(String?.some(entity.id.rawValue))
                    }
                } label: {
                    Text("Rings with")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .help("The doorbell's event (or a button sensor) in Home Assistant")
            }
            HStack(spacing: 12) {
                Text("Camera").settingsRowTitle()
                Spacer(minLength: 12)
                Picker(selection: camera) {
                    Text("None").tag(String?.none)
                    ForEach(store.cameras) { entity in
                        Text(verbatim: entity.name).tag(String?.some(entity.id.rawValue))
                    }
                } label: {
                    Text("Camera")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .help("Its picture comes with the ring")
            }
            SettingsToggleRow("Peek when someone rings", isOn: $settings.alertsForHome)
                .disabled(settings.homeDoorbellTrigger == nil)
                .opacity(settings.homeDoorbellTrigger == nil ? 0.5 : 1)
            Text("Altillo peeks with the camera's picture, and the Home section shows it for two minutes. The picture is only fetched when someone rings.")
                .settingsHint()
        }
    }

    private var trigger: Binding<String?> {
        Binding(get: { settings.homeDoorbellTrigger },
                set: { store.setDoorbellTrigger($0.flatMap(HomeEntityID.init(rawValue:))) })
    }

    private var camera: Binding<String?> {
        Binding(get: { settings.homeDoorbellCamera },
                set: { store.setDoorbellCamera($0.flatMap(HomeEntityID.init(rawValue:))) })
    }
}
