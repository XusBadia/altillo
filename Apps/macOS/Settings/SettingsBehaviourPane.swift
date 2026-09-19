import SwiftUI

/// How Altillo behaves: cómo se abre, si arranca contigo y qué hace el altillo con lo que dejas.
struct SettingsBehaviourPane: View {
    @Bindable var settings: AltilloSettings

    var body: some View {
        SettingsPane(
            title: "Comportamiento",
            subtitle: "Cómo se abre el altillo y qué hace mientras no lo miras."
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker(selection: $settings.opensOnHover) {
                                Text("Al pasar el ratón por encima").tag(true)
                                Text("Al hacer clic").tag(false)
                            } label: {
                                Text("Abrir el altillo")
                                    .font(Desvan.Typeface.rounded(13, weight: .medium))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .pickerStyle(.radioGroup)

                            Text("Con el ratón, el altillo se abre solo si te quedas un momento sobre el notch.")
                                .settingsHint()
                        }
                    }

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $settings.launchAtLogin) {
                                Text("Abrir Altillo al iniciar sesión")
                                    .font(Desvan.Typeface.rounded(13, weight: .medium))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)

                            if let problem = settings.launchAtLoginProblem {
                                Label(problem, systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Desvan.Palette.warning)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Divider().overlay(Desvan.Palette.hairline)

                            Toggle(isOn: $settings.showHintOnEmptyShelf) {
                                Text("Mostrar la pista cuando el altillo está vacío")
                                    .font(Desvan.Typeface.rounded(13, weight: .medium))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)

                            Text("Es la frase que te recuerda que puedes soltar archivos aquí arriba.")
                                .settingsHint()
                        }
                    }

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker(selection: $settings.shelfExpiry) {
                                ForEach(ShelfExpiry.allCases) { expiry in
                                    Text(expiry.title).tag(expiry)
                                }
                            } label: {
                                Text("Vaciar el altillo solo")
                                    .font(Desvan.Typeface.rounded(13, weight: .medium))
                                    .foregroundStyle(Desvan.Palette.paper)
                            }
                            .pickerStyle(.menu)
                            .fixedSize()

                            Text("Altillo quita de la balda lo que lleve ahí más tiempo del que elijas. "
                                 + "Tus archivos originales no se tocan nunca.")
                                .settingsHint()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
