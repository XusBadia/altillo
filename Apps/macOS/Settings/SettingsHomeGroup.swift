import AltilloHome
import AppKit
import SwiftUI

/// The Home section's own settings (docs/casa.md, "Configuración"): the Home Assistant server and its token, the
/// favourites the notch shows, in order, and the doorbell that peeks.
struct SettingsHomeGroup: View {
    @Bindable var settings: AltilloSettings
    let store: HomeStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHomeServer(settings: settings, store: store)
            if settings.homeServer != nil, !store.service.entities.isEmpty {
                SettingsCardDivider()
                SettingsHomeFavourites(settings: settings, store: store)
                    .transition(.settingsReveal)
                SettingsCardDivider()
                SettingsHomeDoorbell(settings: settings, store: store)
                    .transition(.settingsReveal)
            }
        }
        .padding(.vertical, 6)
        .animation(SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion), value: store.connection)
        .animation(SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion),
                   value: store.service.entities.isEmpty)
    }
}

// MARK: - Server

private struct SettingsHomeServer: View {
    private static let privacy = URL(string: "https://altillo.app/privacy/")!

    @Bindable var settings: AltilloSettings
    let store: HomeStore

    @State private var address = ""
    @State private var token = ""
    @State private var confirmsDisconnect = false

    private var tokenPage: URL? {
        (try? store.normalize(address)).map(HomeAssistantClient.tokenPage(for:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSubheading("Home Assistant")
            if case let .connected(serverName, version) = store.connection {
                connected(serverName: serverName, version: version)
            } else {
                status
                form
            }
            Text("Altillo talks to your Home Assistant directly. The token stays in your Keychain and nothing passes through any other server.")
                .settingsHint()
            Link("See privacy details", destination: Self.privacy)
                .font(.system(size: 11.5, weight: .medium))
        }
        .onAppear {
            if address.isEmpty, let url = settings.homeServer?.url { address = url.absoluteString }
        }
        .confirmationDialog("Disconnect from Home Assistant?", isPresented: $confirmsDisconnect) {
            Button("Disconnect", role: .destructive) {
                store.forget()
                token = ""
            }
        } message: {
            Text("Altillo forgets the token, your favourites and the doorbell. Nothing changes in Home Assistant.")
        }
    }

    private func connected(serverName: String, version: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "house.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Desvan.Palette.bulb)
                .frame(width: 30, height: 30)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                    shape.fill(Desvan.Palette.plank.opacity(0.9))
                        .overlay { shape.strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(verbatim: serverName.isEmpty ? store.homeName : serverName)
                        .font(Desvan.Typeface.rounded(13, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                    SettingsBadge(text: String(localized: "Connected"), symbol: "checkmark", tone: .good)
                }
                Text(verbatim: [settings.homeServer?.url.absoluteString, version.isEmpty ? nil : "Home Assistant \(version)"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .settingsCode()
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Disconnect…") { confirmsDisconnect = true }
                .controlSize(.small)
                .help("Forget this server and its token")
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var status: some View {
        switch store.connection {
        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting to your home…").settingsHint()
            }
        case .unauthorized:
            SettingsNotice(symbol: "key.fill",
                           message: "Home Assistant didn't accept the token. Paste a new one below.", tone: .warning)
        case let .needsTrust(fingerprint):
            VStack(alignment: .leading, spacing: 8) {
                SettingsNotice(
                    symbol: "lock.shield",
                    message: "This server uses its own certificate. Check that its fingerprint matches the one in Home Assistant before trusting it.",
                    tone: .warning
                ) {
                    Button("Trust This Certificate") { Task { await store.trustCertificate(fingerprint) } }
                        .disabled(store.isConnecting)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("SHA-256 fingerprint")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                    Text(verbatim: HomeText.fingerprint(fingerprint))
                        .settingsCode()
                }
                .padding(.leading, 2)
            }
        case .localNetworkDenied:
            SettingsNotice(
                symbol: "network.slash",
                message: "Altillo isn't allowed on your local network, so it can't reach Home Assistant.",
                tone: .warning
            ) {
                Button("Open Privacy Settings…") { PrivacySettings.localNetwork.open() }
            }
        case let .unreachable(reason):
            SettingsNotice(
                symbol: "wifi.exclamationmark",
                message: "Can't reach your home right now: \(reason) Altillo keeps trying on its own.",
                tone: .warning
            ) {
                Button("Try Now") { store.reconnect() }
            }
        case .notConfigured, .connected:
            EmptyView()
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Address").settingsRowTitle().frame(width: 64, alignment: .leading)
                TextField(text: $address, prompt: Text(verbatim: "homeassistant.local:8123")) {
                    Text("Address")
                }
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .autocorrectionDisabled()
                .onSubmit(connect)
            }
            HStack(spacing: 12) {
                Text("Token").settingsRowTitle().frame(width: 64, alignment: .leading)
                SecureField(text: $token, prompt: Text("Long-lived access token")) {
                    Text("Token")
                }
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .onSubmit(connect)
            }
            HStack(spacing: 10) {
                if let tokenPage {
                    Link("Create a token…", destination: tokenPage)
                        .font(.system(size: 11.5, weight: .medium))
                        .help("Opens your Home Assistant profile, where long-lived tokens are made")
                } else {
                    Text("Type your server's address to make a token there.").settingsHint()
                }
                Spacer(minLength: 8)
                if store.isConnecting { ProgressView().controlSize(.small) }
                Button(store.isConnecting ? "Connecting…" : "Connect", action: connect)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.isConnecting || address.trimmingCharacters(in: .whitespaces).isEmpty || token.isEmpty)
            }
            if let error = store.connectError {
                SettingsNotice(symbol: "exclamationmark.triangle.fill", verbatim: error, tone: .warning)
                    .transition(.settingsReveal)
            }
            Text("In Home Assistant, open your profile › Security › Long-lived access tokens, create one for Altillo and paste it here.")
                .settingsHint()
        }
    }

    private func connect() {
        guard !store.isConnecting else { return }
        Task {
            await store.connect(address: address, token: token)
            if store.connectError == nil { token = "" }
        }
    }
}

// MARK: - Favourites

private struct SettingsHomeFavourites: View {
    @Bindable var settings: AltilloSettings
    let store: HomeStore

    @State private var query = ""
    @State private var expandedAreas: Set<String> = []

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSubheading("Favourites") {
                Button("Suggest Favourites") {
                    withAnimation(SettingsMotion.reorder) { store.applySuggestions() }
                }
                .controlSize(.small)
                .help("Adds lights, plugs, blinds and scenes from your rooms, up to eight")
            }
            chosen
            search
            catalogue
            Text("Tiles show in this order in Altillo. Drag a favourite to move it. Locks, alarms and garage doors can't be favourites yet.")
                .settingsHint()
        }
    }

    @ViewBuilder
    private var chosen: some View {
        let favourites = store.favourites
        if favourites.isEmpty {
            Text("No favourites yet. Tick them below, or let Altillo suggest some.")
                .settingsHint()
        } else {
            SettingsWell {
                ForEach(favourites) { entity in
                    SettingsHomeFavouriteRow(entity: entity, area: store.area(entity.areaID)?.name) {
                        withAnimation(SettingsMotion.reorder) { store.setFavourite(entity.id, false) }
                    }
                    .draggable(entity.id.rawValue)
                    .dropDestination(for: String.self) { identifiers, _ in
                        guard let raw = identifiers.first, let dragged = HomeEntityID(rawValue: raw) else { return false }
                        withAnimation(SettingsMotion.reorder) { store.moveFavourite(dragged, onto: entity.id) }
                        return true
                    }
                    if entity.id != favourites.last?.id { SettingsRowDivider(leading: 26) }
                }
            }
        }
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .accessibilityHidden(true)
            TextField(text: $query, prompt: Text("Search lights, plugs, blinds…")) { Text("Search") }
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if searching {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Desvan.Palette.paperTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75)
                }
        }
    }

    /// Everything that can be a favourite, area by area. Technical entities (helpers, diagnostics) only show up
    /// while searching.
    @ViewBuilder
    private var catalogue: some View {
        let groups = self.groups
        if groups.isEmpty {
            Text(searching ? "Nothing called “\(query)”." : "Home Assistant hasn't shared any lights, plugs or blinds yet.")
                .settingsHint()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(groups, id: \.id) { group in
                    SettingsInlineDisclosure(title: LocalizedStringKey(group.name), count: group.entities.count,
                                             isExpanded: expanded(group.id)) {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(group.entities) { entity in
                                Toggle(isOn: favourite(entity)) {
                                    HStack(spacing: 7) {
                                        Image(systemName: HomeText.symbol(for: entity, state: entity.state))
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundStyle(Desvan.Palette.paperSecondary)
                                            .frame(width: 16)
                                            .accessibilityHidden(true)
                                        Text(verbatim: entity.name)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(Desvan.Palette.paper)
                                            .lineLimit(1)
                                        Text(verbatim: HomeText.kindName(entity))
                                            .font(.system(size: 11))
                                            .foregroundStyle(Desvan.Palette.paperTertiary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .help(entity.id.localID)
                            }
                        }
                        .padding(.leading, 14)
                    }
                }
            }
        }
    }

    private struct Group {
        let id: String
        let name: String
        let entities: [HomeEntity]
    }

    private var groups: [Group] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let candidates = store.service.entities.values.filter { entity in
            guard HomeStore.canFavourite(entity) else { return false }
            if needle.isEmpty { return !entity.isTechnical }
            return entity.name.localizedStandardContains(needle) || entity.id.localID.localizedStandardContains(needle)
        }
        let byArea = Dictionary(grouping: candidates) { $0.areaID ?? "" }
        let sort: (HomeEntity, HomeEntity) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var result = store.areas.compactMap { area -> Group? in
            guard let entities = byArea[area.id], !entities.isEmpty else { return nil }
            return Group(id: area.id, name: area.name, entities: entities.sorted(by: sort))
        }
        let known = Set(store.areas.map(\.id))
        let elsewhere = byArea.filter { !known.contains($0.key) }.flatMap(\.value)
        if !elsewhere.isEmpty {
            result.append(Group(id: "", name: String(localized: "No room"), entities: elsewhere.sorted(by: sort)))
        }
        return result
    }

    private func expanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { searching || expandedAreas.contains(id) },
            set: { open in
                if open { expandedAreas.insert(id) } else { expandedAreas.remove(id) }
            }
        )
    }

    private func favourite(_ entity: HomeEntity) -> Binding<Bool> {
        Binding(
            get: { store.isFavourite(entity.id) },
            set: { on in withAnimation(SettingsMotion.reorder) { store.setFavourite(entity.id, on) } }
        )
    }
}

/// A chosen favourite: the grip, its symbol, its name and room, and the way to take it off.
private struct SettingsHomeFavouriteRow: View {
    let entity: HomeEntity
    let area: String?
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .accessibilityHidden(true)
            Image(systemName: HomeText.symbol(for: entity, state: entity.state))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Desvan.Palette.bulb)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(verbatim: entity.name)
                .font(.system(size: 12.5))
                .foregroundStyle(Desvan.Palette.paper)
                .lineLimit(1)
            if let area {
                Text(verbatim: area)
                    .font(.system(size: 11))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Desvan.Palette.paperSecondary)
            }
            .buttonStyle(SettingsPressStyle(scale: 0.85))
            .help("Remove from the favourites")
            .accessibilityLabel(Text("Remove \(entity.name)"))
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Doorbell

private struct SettingsHomeDoorbell: View {
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
