import AltilloHome
import AppKit
import Observation
import SwiftUI

// MARK: - Model

/// Settings › Home's connection flow (docs/casa-v2.md §4): find Home Assistant on the network, check typed addresses,
/// sign in with HA's own page in the browser (or paste a token), connect and save the server. The network and the
/// browser come in as closures so the tests can stand in for them.
@MainActor
@Observable
final class SettingsHomeConnectModel {
    struct Dependencies {
        var discover: @MainActor () async -> (servers: [HomeDiscoveredServer], denied: Bool)
        var validate: @MainActor (URL, String?) async -> HomeServerProbe
        var signIn: @MainActor (URL, String?) async throws -> String
        var cancelSignIn: @MainActor () -> Void
        /// Pause before checking what's being typed.
        var debounce: Duration = .milliseconds(650)

        @MainActor static func live() -> Dependencies {
            let discovery = HomeDiscovery()
            let auth = HomeAuthFlow()
            return Dependencies(
                discover: {
                    let servers = await discovery.discover()
                    return (servers, discovery.browsingDenied)
                },
                validate: { await discovery.validate($0, pinnedCertificateSHA256: $1) },
                signIn: { try await auth.signIn(to: $0, pinnedCertificateSHA256: $1) },
                cancelSignIn: { auth.cancel() }
            )
        }
    }

    enum Phase: Equatable {
        case idle
        case searching
        /// Checking the address before opening the browser.
        case checking
        /// Waiting for the browser, then connecting.
        case signingIn(URL)
    }

    private(set) var phase: Phase = .idle
    /// Found servers, deduplicated, the saved one first.
    private(set) var servers: [HomeDiscoveredServer] = []
    private(set) var hasSearched = false
    /// The search was refused by the Local Network permission and found nothing.
    private(set) var localNetworkDenied = false
    /// What the typed address turned out to be, for the address it was checked for.
    private(set) var check: (address: String, notice: HomeSettingsLogic.ProbeNotice)?
    /// The last sign-in's failure, as the user should read it.
    private(set) var error: String?
    var address = ""
    var token = ""
    var showsToken = false

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var signInTask: Task<Void, Never>?

    init(dependencies: Dependencies = .live()) {
        self.dependencies = dependencies
    }

    var isBusy: Bool { phase != .idle && phase != .searching }

    var isSigningIn: Bool {
        if case .signingIn = phase { true } else { false }
    }

    /// The typed address's check, while the field still says it.
    var currentCheck: HomeSettingsLogic.ProbeNotice? {
        guard let check, check.address == trimmedAddress, !trimmedAddress.isEmpty else { return nil }
        return check.notice
    }

    private var trimmedAddress: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Where "Sign in" goes: the typed address, or homeassistant.local:8123 when the field is empty.
    func target() throws -> URL {
        trimmedAddress.isEmpty ? HomeDiscovery.defaultLocalURL : try HomeAssistantClient.normalize(trimmedAddress)
    }

    // MARK: Appearing

    /// The section came into view: fill in the saved address and, when not connected, look for servers once.
    func appear(store: HomeStore) {
        if address.isEmpty, let url = store.settings.homeServer?.url {
            address = HomeSettingsLogic.fieldText(for: url)
        }
        guard !store.isConnected, !hasSearched, phase == .idle else { return }
        search(store: store)
    }

    func search(store: HomeStore) {
        guard phase == .idle else { return }
        phase = .searching
        let current = store.settings.homeServer?.url
        searchTask = Task {
            let found = await dependencies.discover()
            guard !Task.isCancelled else { return }
            servers = HomeSettingsLogic.rows(found.servers, current: current)
            localNetworkDenied = found.denied && servers.isEmpty
            hasSearched = true
            if phase == .searching { phase = .idle }
            if servers.count == 1, trimmedAddress.isEmpty {
                address = HomeSettingsLogic.fieldText(for: servers[0].url)
                check = (trimmedAddress, HomeSettingsLogic.notice(for: .homeAssistant(version: servers[0].version,
                                                                                   needsOnboarding: false)))
            }
        }
    }

    // MARK: Checking

    /// The field changed: check it once typing pauses.
    func addressChanged() {
        checkTask?.cancel()
        error = nil
        let typed = trimmedAddress
        guard !typed.isEmpty else { return }
        if let server = servers.first(where: { HomeSettingsLogic.fieldText(for: $0.url) == typed }) {
            check = (typed, HomeSettingsLogic.notice(for: .homeAssistant(version: server.version, needsOnboarding: false)))
            return
        }
        guard let url = try? HomeAssistantClient.normalize(typed) else { return }
        let debounce = dependencies.debounce
        checkTask = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let probe = await dependencies.validate(url, nil)
            guard !Task.isCancelled, trimmedAddress == typed else { return }
            check = (typed, HomeSettingsLogic.notice(for: probe))
        }
    }

    // MARK: Signing in

    /// A found server's row.
    func signIn(to server: HomeDiscoveredServer, store: HomeStore) {
        address = HomeSettingsLogic.fieldText(for: server.url)
        start(server.url, pinned: nil, checkFirst: false, store: store)
    }

    /// The primary button: the typed address (checked first unless it's a found server), or homeassistant.local.
    func signIn(store: HomeStore, pinning fingerprint: String? = nil) {
        let url: URL
        do {
            url = try target()
        } catch {
            self.error = HomeStore.message(for: error)
            return
        }
        let known = servers.contains { HomeSettingsLogic.sameServer($0.url, url) }
        start(url, pinned: fingerprint, checkFirst: !known && fingerprint == nil, store: store)
    }

    func cancel() {
        signInTask?.cancel()
        signInTask = nil
        dependencies.cancelSignIn()
        if phase != .idle && phase != .searching { phase = .idle }
    }

    private func start(_ url: URL, pinned: String?, checkFirst: Bool, store: HomeStore) {
        guard !isBusy, !store.isConnecting else { return }
        error = nil
        checkTask?.cancel()
        let typed = trimmedAddress
        signInTask = Task {
            if checkFirst {
                phase = .checking
                let notice = HomeSettingsLogic.notice(for: await dependencies.validate(url, nil))
                guard !Task.isCancelled else { return }
                check = (typed, notice)
                guard notice.isGood else {
                    phase = .idle
                    return
                }
            }
            phase = .signingIn(url)
            defer { if phase == .signingIn(url) { phase = .idle } }
            let token: String
            do {
                token = try await dependencies.signIn(url, pinned)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.error = HomeStore.message(for: error)
                return
            }
            guard !Task.isCancelled else { return }
            await store.connect(address: url.absoluteString, token: token)
            // The certificate was already checked and accepted on this screen: pin it without asking again.
            if let pinned, case let .needsTrust(fingerprint) = store.connection,
               fingerprint.caseInsensitiveCompare(pinned) == .orderedSame {
                await store.trustCertificate(fingerprint)
            }
            if let failure = store.connectError, !store.isConnected { self.error = failure }
        }
    }

    /// "Use a token instead".
    func connectWithToken(store: HomeStore) {
        guard !store.isConnecting else { return }
        error = nil
        let typed = trimmedAddress.isEmpty ? HomeSettingsLogic.fieldText(for: HomeDiscovery.defaultLocalURL) : trimmedAddress
        let token = self.token
        Task {
            await store.connect(address: typed, token: token)
            if store.connectError == nil { self.token = "" }
        }
    }

    /// Back to a fresh start after disconnecting.
    func reset() {
        cancel()
        token = ""
        error = nil
        hasSearched = false
    }
}

// MARK: - View

/// Home Assistant: found servers, "Sign in with Home Assistant", a token as the alternative, and the connection's
/// state once it's set up.
struct SettingsHomeConnect: View {
    private static let privacy = URL(string: "https://altillo.app/privacy/")!

    @Bindable var settings: AltilloSettings
    let store: HomeStore
    @Bindable var model: SettingsHomeConnectModel

    @State private var confirmsDisconnect = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSubheading("Home Assistant") {
                if !store.isConnected { searchControl }
            }
            if case let .connected(serverName, version) = store.connection {
                connected(serverName: serverName, version: version)
            } else {
                status
                found
                signIn
                tokenForm
            }
            Text("Altillo talks to your Home Assistant directly. The token stays in your Keychain and nothing passes through any other server.")
                .settingsHint()
            Link("See privacy details", destination: Self.privacy)
                .font(.system(size: 11.5, weight: .medium))
        }
        .onAppear { model.appear(store: store) }
        .onChange(of: model.address) { model.addressChanged() }
        .animation(SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion), value: model.phase)
        .animation(SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion), value: model.servers)
        .animation(SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion), value: model.currentCheck)
        .animation(SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion), value: model.error)
        .confirmationDialog("Disconnect from Home Assistant?", isPresented: $confirmsDisconnect) {
            Button("Disconnect", role: .destructive) {
                store.forget()
                model.reset()
            }
        } message: {
            Text("Altillo forgets the token, your favourites and the doorbell. Nothing changes in Home Assistant.")
        }
    }

    // MARK: Connected

    private func connected(serverName: String, version: String) -> some View {
        HStack(spacing: 10) {
            SettingsHomePlank(symbol: "house.fill")
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

    // MARK: Searching

    @ViewBuilder
    private var searchControl: some View {
        if model.phase == .searching {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Looking…")
                    .font(.system(size: 11))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            }
        } else {
            Button("Search Again") { model.search(store: store) }
                .controlSize(.small)
                .disabled(model.isBusy)
                .help("Looks for Home Assistant on your network again")
        }
    }

    @ViewBuilder
    private var found: some View {
        if !model.servers.isEmpty {
            SettingsWell {
                ForEach(model.servers) { server in
                    SettingsHomeServerRow(server: server, isBusy: model.isBusy || store.isConnecting) {
                        model.signIn(to: server, store: store)
                    }
                    if server.id != model.servers.last?.id { SettingsRowDivider(leading: 40) }
                }
            }
            .transition(.settingsReveal)
        } else if model.hasSearched, model.localNetworkDenied {
            SettingsNotice(
                symbol: "network.slash",
                message: "Altillo isn't allowed on your local network, so it can't look for Home Assistant.",
                tone: .warning
            ) {
                Button("Open Privacy Settings…") { PrivacySettings.localNetwork.open() }
            }
            .transition(.settingsReveal)
        } else if model.hasSearched, model.phase != .searching {
            Text("No Home Assistant answered on this network. Type its address below.")
                .settingsHint()
                .transition(.settingsReveal)
        }
    }

    // MARK: Signing in

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Address").settingsRowTitle().frame(width: 64, alignment: .leading)
                TextField(text: $model.address, prompt: Text(verbatim: "homeassistant.local:8123")) {
                    Text("Address")
                }
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .autocorrectionDisabled()
                .disabled(model.isBusy)
                .onSubmit { if !model.showsToken { model.signIn(store: store) } }
            }
            if let notice = model.currentCheck {
                checkNotice(notice)
                    .transition(.settingsReveal)
            }
            if case .signingIn = model.phase {
                SettingsNotice(symbol: "safari", message: "Waiting for you in the browser…", tone: .accent) {
                    Button("Cancel") { model.cancel() }
                }
                .transition(.settingsReveal)
            } else {
                HStack(spacing: 10) {
                    Text("Opens Home Assistant's own sign-in page. No token to copy.")
                        .settingsHint()
                    Spacer(minLength: 8)
                    if model.phase == .checking || store.isConnecting { ProgressView().controlSize(.small) }
                    Button {
                        model.signIn(store: store)
                    } label: {
                        Text("Sign in with Home Assistant")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(model.showsToken ? nil : .defaultAction)
                    .disabled(model.isBusy || store.isConnecting)
                }
            }
            if let error = model.error {
                SettingsNotice(symbol: "exclamationmark.triangle.fill", verbatim: error, tone: .warning)
                    .transition(.settingsReveal)
            }
        }
    }

    @ViewBuilder
    private func checkNotice(_ notice: HomeSettingsLogic.ProbeNotice) -> some View {
        if notice.isGood {
            Label {
                Text(verbatim: notice.message)
            } icon: {
                Image(systemName: notice.symbol).foregroundStyle(Desvan.Palette.sage)
            }
            .font(.system(size: 11))
            .foregroundStyle(Desvan.Palette.paperSecondary)
            .padding(.leading, 76)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                SettingsNotice(symbol: notice.symbol, verbatim: notice.message, tone: .warning) {
                    switch notice.action {
                    case .openLocalNetworkSettings:
                        Button("Open Privacy Settings…") { PrivacySettings.localNetwork.open() }
                    case let .trust(fingerprint):
                        Button("Trust and Sign In") { model.signIn(store: store, pinning: fingerprint) }
                            .disabled(model.isBusy)
                    case nil:
                        EmptyView()
                    }
                }
                if case let .trust(fingerprint) = notice.action {
                    fingerprintView(fingerprint)
                }
            }
        }
    }

    private func fingerprintView(_ fingerprint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SHA-256 fingerprint")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperSecondary)
            Text(verbatim: HomeText.fingerprint(fingerprint))
                .settingsCode()
        }
        .padding(.leading, 2)
    }

    // MARK: Token

    private var tokenForm: some View {
        SettingsInlineDisclosure(title: "Use a token instead", isExpanded: $model.showsToken) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("Token").settingsRowTitle().frame(width: 64, alignment: .leading)
                    SecureField(text: $model.token, prompt: Text("Long-lived access token")) {
                        Text("Token")
                    }
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .onSubmit { model.connectWithToken(store: store) }
                }
                HStack(spacing: 10) {
                    if let tokenPage {
                        Link("Create a token…", destination: tokenPage)
                            .font(.system(size: 11.5, weight: .medium))
                            .help("Opens your Home Assistant profile, where long-lived tokens are made")
                    }
                    Spacer(minLength: 8)
                    if store.isConnecting { ProgressView().controlSize(.small) }
                    Button(store.isConnecting ? "Connecting…" : "Connect") { model.connectWithToken(store: store) }
                        .controlSize(.small)
                        .keyboardShortcut(model.showsToken ? .defaultAction : nil)
                        .disabled(store.isConnecting || model.isBusy || model.token.isEmpty)
                }
                if let error = store.connectError, !model.isBusy, model.error == nil {
                    SettingsNotice(symbol: "exclamationmark.triangle.fill", verbatim: error, tone: .warning)
                        .transition(.settingsReveal)
                }
                Text("In Home Assistant, open your profile › Security › Long-lived access tokens, create one for Altillo and paste it here.")
                    .settingsHint()
            }
            .padding(.leading, 14)
        }
    }

    private var tokenPage: URL? {
        (try? model.target()).map(HomeAssistantClient.tokenPage(for:))
    }

    // MARK: Connection problems

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
                           message: "Home Assistant didn't accept the token. Sign in again, or paste a new token.",
                           tone: .warning)
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
                fingerprintView(fingerprint)
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
}

/// A found Home Assistant: "Casa · homeassistant.local:8123 · Sign In".
private struct SettingsHomeServerRow: View {
    let server: HomeDiscoveredServer
    let isBusy: Bool
    let signIn: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "house.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Desvan.Palette.bulb)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(verbatim: HomeSettingsLogic.title(of: server))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paper)
                    Text(verbatim: "·").foregroundStyle(Desvan.Palette.paperTertiary)
                    Text(verbatim: server.address)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .lineLimit(1)
                }
                if let version = server.version {
                    Text(verbatim: "Home Assistant \(version)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                }
            }
            Spacer(minLength: 8)
            Button("Sign In…", action: signIn)
                .controlSize(.small)
                .disabled(isBusy)
                .help("Opens this Home Assistant's sign-in page in your browser")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

/// The symbol on a small plank, as the Settings cards show theirs.
struct SettingsHomePlank: View {
    let symbol: String
    var tint: Color = Desvan.Palette.bulb

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background {
                let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                shape.fill(Desvan.Palette.plank.opacity(0.9))
                    .overlay { shape.strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
            }
            .accessibilityHidden(true)
    }
}
