import AltilloCore
import AltilloHome
import AppKit
import Observation
import SwiftUI

/// The welcome's Home step (docs/casa-v2.md §4): find Home Assistant on the network, sign in with its own page in
/// the browser (OAuth, no token to paste) and switch the Home section on. Lives on the flow so going Back and forth
/// keeps what was found.
@MainActor
@Observable
final class OnboardingHomeSetup {
    enum Phase: Equatable {
        /// Nothing asked yet: looking only starts from a click (it's what brings up macOS's Local Network prompt).
        case idle
        case searching
        /// The search is over; `servers` may be empty.
        case searched
        /// Waiting for the browser (and then the connection).
        case signingIn(URL)
        case connected(name: String)
    }

    private(set) var phase: Phase = .idle
    private(set) var servers: [HomeDiscoveredServer] = []
    private(set) var error: String?
    /// The search was refused by the Local Network permission.
    private(set) var localNetworkDenied = false
    var address = ""
    var showsAddress = false

    @ObservationIgnored private let model: NotchModel
    @ObservationIgnored private let discovery = HomeDiscovery()
    @ObservationIgnored private let auth = HomeAuthFlow()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(model: NotchModel) {
        self.model = model
        if model.home.isConnected { phase = .connected(name: model.home.homeName) }
    }

    var isBusy: Bool {
        switch phase {
        case .searching, .signingIn: true
        default: false
        }
    }

    func search() {
        guard !isBusy else { return }
        error = nil
        phase = .searching
        task = Task {
            let found = await discovery.discover()
            guard !Task.isCancelled else { return }
            servers = found
            localNetworkDenied = discovery.browsingDenied && found.isEmpty
            if found.isEmpty { showsAddress = true }
            phase = .searched
        }
    }

    func signIn(to server: HomeDiscoveredServer) {
        start(server.url, checkFirst: false)
    }

    func signInToAddress() {
        let url: URL
        do {
            url = try HomeAssistantClient.normalize(address)
        } catch {
            self.error = HomeStore.message(for: error)
            return
        }
        start(url, checkFirst: true)
    }

    /// Stops a search or a sign-in waiting for the browser.
    func cancel() {
        task?.cancel()
        task = nil
        auth.cancel()
        if phase == .searching { phase = .idle }
    }

    private func start(_ url: URL, checkFirst: Bool) {
        guard !isBusy else { return }
        error = nil
        let previous = phase
        phase = .signingIn(url)
        task = Task {
            let problem = checkFirst ? await discovery.validate(url).problem : nil
            guard !Task.isCancelled else {
                phase = previous
                return
            }
            if let problem {
                finish(failed: problem, back: previous)
                return
            }
            let token: String
            do {
                token = try await auth.signIn(to: url)
            } catch is CancellationError {
                if phase == .signingIn(url) { phase = previous }
                return
            } catch {
                finish(failed: HomeStore.message(for: error), back: previous)
                return
            }
            await connect(url, token: token, back: previous)
        }
    }

    /// Switches Home on (that's what keeps the connection alive) and connects with the new token, which the client
    /// keeps in the Keychain. If it doesn't work, Home goes back to how it was.
    private func connect(_ url: URL, token: String, back previous: Phase) async {
        let settings = model.settings
        let wasOn = settings.isEnabled(.home)
        settings.setEnabled(.home, true)
        model.home.setModuleEnabled(true)
        await model.home.connect(address: url.absoluteString, token: token)
        if let failure = model.home.connectError {
            if !wasOn {
                settings.setEnabled(.home, false)
                model.home.setModuleEnabled(false)
            }
            finish(failed: failure, back: previous)
        } else {
            phase = .connected(name: model.home.homeName)
        }
    }

    private func finish(failed message: String, back previous: Phase) {
        error = message
        phase = previous
    }
}

/// After the AI tools: "Your home in the notch?" Home Assistant is found and signed in to right here; Apple Home and
/// the rest say honestly how they work. Skippable like every page.
struct OnboardingHomePage: View {
    let flow: OnboardingFlow
    let eyebrow: String

    private var setup: OnboardingHomeSetup { flow.homeSetup }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingHeader(
                    eyebrow: eyebrow,
                    title: "Your home in the notch?",
                    subtitle: "Lights, blinds and scenes one click away. Altillo talks to your home on your own network, nothing in between. Not for you? Skip it."
                )
                homeAssistantCard
                VStack(spacing: 0) {
                    OnboardingHomeRow(
                        symbol: "homekit", title: "Apple Home", detail: "Scenes through Shortcuts",
                        note: "On the Mac, Apple only lets apps run Home through Shortcuts, so Altillo can start your scenes but can't read their state."
                    )
                    Rectangle().fill(Desvan.Palette.hairline).frame(height: 0.75).padding(.leading, 58)
                    OnboardingHomeRow(
                        symbol: "point.3.connected.trianglepath.dotted", title: "Hue, Google Home, Alexa, Matter",
                        detail: "Through Home Assistant",
                        note: "Add them to Home Assistant and they show up in Altillo with everything else."
                    )
                }
                .desvanCard(radius: 14)
            }
            .padding(.horizontal, 30)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Home Assistant

    private var homeAssistantCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "house")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.kraft)
                    .accessibilityHidden(true)
                Text("Home Assistant")
                    .font(Desvan.Typeface.display(15, weight: 650))
                    .foregroundStyle(Desvan.Palette.paper)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if case .searched = setup.phase, !setup.servers.isEmpty {
                    Button("Look Again") { setup.search() }
                        .buttonStyle(DesvanButtonStyle(kind: .quiet))
                }
            }
            haContent
            if let error = setup.error {
                Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Desvan.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .desvanCard(radius: 14)
    }

    @ViewBuilder
    private var haContent: some View {
        switch setup.phase {
        case .idle:
            Text("Altillo looks for it on this network. The first time, macOS asks to allow Local Network access.")
                .onboardingBody()
            HStack(spacing: 10) {
                Button("Find Home Assistant") { setup.search() }
                    .buttonStyle(DesvanButtonStyle(kind: .primary))
                Button("Type an Address") { setup.showsAddress = true }
                    .buttonStyle(DesvanButtonStyle(kind: .ghost))
                    .opacity(setup.showsAddress ? 0 : 1)
            }
            if setup.showsAddress { addressField }
        case .searching:
            waiting("Looking on your network…", cancellable: false)
        case .searched:
            if setup.servers.isEmpty {
                Text(setup.localNetworkDenied
                     ? "macOS isn't letting Altillo look on your network. Allow it in System Settings › Privacy & Security › Local Network, or type the address."
                     : "No Home Assistant answered on this network. Type its address, or look again.")
                    .onboardingBody()
                if setup.localNetworkDenied {
                    Button("Open Local Network Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(DesvanButtonStyle(kind: .ghost))
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(setup.servers) { server in
                        OnboardingServerRow(server: server) { setup.signIn(to: server) }
                    }
                }
            }
            if setup.showsAddress {
                addressField
            } else {
                Button("Type an Address") { setup.showsAddress = true }
                    .buttonStyle(DesvanButtonStyle(kind: .quiet))
            }
        case .signingIn:
            waiting("Sign in on the Home Assistant page that opened in your browser…", cancellable: true)
        case .connected(let name):
            OnboardingDoneLabel(text: "Connected to \(name)")
            Text("Home is on in the notch. Pick your favourites any time in Settings › Home.")
                .onboardingBody()
        }
    }

    private var addressField: some View {
        HStack(spacing: 10) {
            TextField(text: Bindable(setup).address, prompt: Text(verbatim: "homeassistant.local:8123")) {
                Text("Address")
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .autocorrectionDisabled()
            .onSubmit { setup.signInToAddress() }
            Button("Sign In…") { setup.signInToAddress() }
                .buttonStyle(DesvanButtonStyle(kind: .primary))
                .disabled(setup.address.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func waiting(_ text: LocalizedStringKey, cancellable: Bool) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).onboardingBody()
            Spacer(minLength: 8)
            if cancellable {
                Button("Cancel") { setup.cancel() }
                    .buttonStyle(DesvanButtonStyle(kind: .ghost))
            }
        }
        .frame(minHeight: 30)
    }
}

/// A Home Assistant found on the network: its name, address and version, and "Sign In…".
private struct OnboardingServerRow: View {
    let server: HomeDiscoveredServer
    let signIn: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            OnboardingSymbolTile(symbol: "house.fill", tint: Desvan.Palette.bulb, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: server.name)
                    .font(Desvan.Typeface.rounded(13, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                Text(verbatim: [server.address, server.version].compactMap(\.self).joined(separator: " · "))
                    .font(Desvan.Typeface.figure(11.5, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            }
            Spacer(minLength: 8)
            Button("Sign In…", action: signIn)
                .buttonStyle(DesvanButtonStyle(kind: .primary))
                .accessibilityLabel("Sign in to \(server.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Desvan.Palette.paper.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75)
                }
        }
        .accessibilityElement(children: .contain)
    }
}

/// An informative row: what works and how, no switch.
private struct OnboardingHomeRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let note: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            OnboardingSymbolTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Desvan.Typeface.rounded(13, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                    Text(detail)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Desvan.Palette.kraft)
                }
                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

private extension Text {
    func onboardingBody() -> some View {
        font(.system(size: 12.5))
            .foregroundStyle(Desvan.Palette.paperSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
