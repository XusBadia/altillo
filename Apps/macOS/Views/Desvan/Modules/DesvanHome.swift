import AltilloHome
import AppKit
import SwiftUI

/// The «Home» tab (docs/casa.md): the house's name and its rooms as chips, the scenes as big buttons, the favourite
/// tiles (eight in view, the rest scroll) and the sensors in one quiet line. Lights glow with the colour each bulb
/// is really showing; opening the section lights them up one by one.
///
/// Click a tile to toggle it (blinds open or close); drag across it to dim a light or move a blind, with a tap of the
/// trackpad at 0 and 100 %. Everything is optimistic: the tile changes at once and only goes back if Home Assistant
/// says no.
struct DesvanHomeView: View {
    let model: NotchModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The room chip picked; nil is "Favourites" (every favourite).
    @State private var area: String?
    /// How many tiles have lit up so far in the opening stagger.
    @State private var revealed = 0

    private var store: HomeStore { model.shownHome }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch store.connection {
        case .notConfigured where store.settings.homeServer == nil:
            DesvanModuleNotice(
                symbol: NotchModule.home.symbol,
                title: "Your home, up here",
                message: "Connect Home Assistant to switch lights, blinds and scenes from the notch.",
                actionTitle: "Connect Home Assistant"
            ) { model.actions.openHomeSettings() }
        case .unauthorized:
            DesvanModuleNotice(
                symbol: "key.fill",
                title: "Home Assistant didn't accept the token",
                message: "It may have been deleted or mistyped.",
                actionTitle: "Paste a New Token"
            ) { model.actions.openHomeSettings() }
        case .needsTrust:
            DesvanModuleNotice(
                symbol: "lock.shield",
                title: "A certificate to check",
                message: "Your server uses its own certificate. Check it once in Settings and Altillo remembers it.",
                actionTitle: "Check in Settings"
            ) { model.actions.openHomeSettings() }
        case .localNetworkDenied:
            DesvanModuleNotice(
                symbol: "network.slash",
                title: "Altillo can't see your local network",
                message: "Allow Altillo in Privacy & Security › Local Network to reach Home Assistant.",
                actionTitle: "Open Privacy Settings"
            ) { PrivacySettings.localNetwork.open() }
        case let .unreachable(reason):
            DesvanModuleNotice(
                symbol: "wifi.exclamationmark",
                title: "Can't reach your home right now",
                message: "\(reason) Altillo keeps trying on its own.",
                actionTitle: "Try Now"
            ) { store.reconnect() }
        case .connecting, .notConfigured:
            VStack(alignment: .leading, spacing: 10) {
                DesvanHomeHeader(name: store.homeName, areas: [], selection: $area)
                DesvanHomeSkeleton()
            }
        case .connected:
            if store.favourites.isEmpty {
                DesvanModuleNotice(
                    symbol: "star",
                    title: "Choose your favourites",
                    message: "Pick the lights, plugs, blinds and scenes you want one click away.",
                    actionTitle: "Choose Favourites"
                ) { model.actions.openHomeSettings() }
            } else {
                house
            }
        }
    }

    // MARK: - The house

    private var house: some View {
        let shown = store.favourites.filter { area == nil || $0.areaID == area }
        let actions = shown.filter(\.kind.isAction)
        let tiles = shown.filter { !$0.kind.isAction && $0.kind != .sensor && $0.kind != .binarySensor }
        let sensors = shown.filter { $0.kind == .sensor || $0.kind == .binarySensor }
        return VStack(alignment: .leading, spacing: 5) {
            DesvanHomeHeader(name: store.homeName, areas: store.favouriteAreas, selection: $area)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    // Ticks only while there's a ring to show, so the card leaves on its own two minutes later.
                    if store.ring != nil {
                        TimelineView(.periodic(from: .now, by: 15)) { context in
                            if let ring = store.ring, store.isRingFresh(at: context.date) {
                                DesvanHomeCameraCard(ring: ring, name: store.service.entities[ring.entity]?.name,
                                                     now: context.date, hasCamera: store.doorbellCamera != nil,
                                                     refresh: store.refreshSnapshot, dismiss: store.dismissRing)
                                    .transition(.opacity)
                            }
                        }
                    }
                    if !actions.isEmpty {
                        DesvanHomeScenes(entities: actions, store: store)
                    }
                    if !tiles.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, entity in
                                DesvanHomeTile(entity: entity, store: store, isRevealed: index < revealed) {
                                    model.actions.haptic($0)
                                }
                            }
                        }
                    }
                    if !sensors.isEmpty {
                        DesvanHomeSensors(entities: sensors, store: store)
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
        }
        .task(id: tiles.count) { await lightUp(count: tiles.count) }
    }

    /// The opening moment: the tiles light up one after another with their bulbs' colours. With Reduce Motion they
    /// all fade in together.
    private func lightUp(count: Int) async {
        guard revealed < count else { return }
        if reduceMotion {
            withAnimation(Desvan.Motion.fade) { revealed = count }
            return
        }
        try? await Task.sleep(for: .milliseconds(120))
        while revealed < count, !Task.isCancelled {
            withAnimation(.easeOut(duration: 0.35)) { revealed += 1 }
            try? await Task.sleep(for: .milliseconds(55))
        }
    }
}

// MARK: - Header

/// The house's name and its rooms as chips: "Favourites" first, then each room that holds a favourite.
private struct DesvanHomeHeader: View {
    let name: String
    let areas: [HomeArea]
    @Binding var selection: String?

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: name)
                .font(Desvan.Typeface.display(15, weight: 600))
                .foregroundStyle(Desvan.Palette.paper)
                .lineLimit(1)
                .fixedSize()
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    chip(String(localized: "Favourites"), id: nil)
                    ForEach(areas) { area in chip(area.name, id: area.id) }
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(height: 28)
    }

    private func chip(_ title: String, id: String?) -> some View {
        let isSelected = selection == id
        return Button {
            withAnimation(Desvan.Motion.content) { selection = id }
        } label: {
            Text(verbatim: title)
                .font(Desvan.Typeface.rounded(12, weight: .semibold))
                .foregroundStyle(isSelected ? Desvan.Palette.bulbInk : Desvan.Palette.paperSecondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background {
                    Capsule().fill(isSelected ? Desvan.Palette.bulb.opacity(0.92) : Desvan.Palette.paper.opacity(0.06))
                }
                .contentShape(Capsule())
                .desvanHitTarget()
        }
        .buttonStyle(DesvanPressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Scenes

/// Scenes and scripts as big buttons: one click and they go off, a tick when Home Assistant has run them.
private struct DesvanHomeScenes: View {
    let entities: [HomeEntity]
    let store: HomeStore

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(entities) { entity in
                    DesvanHomeSceneButton(entity: entity, store: store)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct DesvanHomeSceneButton: View {
    let entity: HomeEntity
    let store: HomeStore
    @State private var isHovering = false

    var body: some View {
        let firing = store.firing.contains(entity.id)
        let fired = store.fired.contains(entity.id)
        let problem = store.problems[entity.id]
        Button { store.activate(entity) } label: {
            HStack(spacing: 7) {
                ZStack {
                    if firing {
                        ProgressView().controlSize(.mini).tint(Desvan.Palette.bulb)
                    } else if fired {
                        Image(systemName: "checkmark").foregroundStyle(Desvan.Palette.done)
                            .transition(.scale.combined(with: .opacity))
                    } else if problem != nil {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(Desvan.Palette.critical)
                    } else {
                        Image(systemName: HomeText.symbol(for: entity, state: entity.state))
                            .foregroundStyle(Desvan.Palette.bulb)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 16)
                Text(verbatim: entity.name)
                    .font(Desvan.Typeface.rounded(13, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background {
                let shape = Capsule()
                shape.fill(Desvan.Palette.plank.opacity(isHovering ? 1 : 0.8))
                    .overlay { shape.strokeBorder(Desvan.Palette.bulb.opacity(isHovering ? 0.6 : 0.16), lineWidth: 0.75) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(DesvanPressStyle())
        .disabled(!entity.state.isAvailable)
        .opacity(entity.state.isAvailable ? 1 : 0.4)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .animation(Desvan.Motion.content, value: fired)
        .help(problem ?? String(localized: "Run “\(entity.name)”"))
        .accessibilityLabel(entity.name)
        .accessibilityHint(entity.kind == .scene ? "Activates the scene." : "Runs the script.")
    }
}

// MARK: - Sensors

/// Temperature, humidity, doors: one quiet line under the tiles.
private struct DesvanHomeSensors: View {
    let entities: [HomeEntity]
    let store: HomeStore

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(entities) { entity in
                    let state = store.state(of: entity)
                    HStack(spacing: 5) {
                        Image(systemName: HomeText.symbol(for: entity, state: state))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Desvan.Palette.paperTertiary)
                        Text(verbatim: entity.name)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Desvan.Palette.paperSecondary)
                        Text(verbatim: HomeText.stateLine(for: entity, state: state))
                            .font(Desvan.Typeface.figure(12, weight: .medium))
                            .foregroundStyle(Desvan.Palette.paper)
                    }
                    .lineLimit(1)
                    .opacity(state.isAvailable ? 1 : 0.4)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 2)
            .frame(height: 22)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Loading

/// While connecting: eight blank tiles breathing softly where the real ones will be.
private struct DesvanHomeSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Desvan.Palette.paper.opacity(dim ? 0.04 : 0.08))
                    .frame(height: DesvanHomeTile.height)
            }
        }
        .padding(.top, 42)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connecting to your home…")
    }
}
