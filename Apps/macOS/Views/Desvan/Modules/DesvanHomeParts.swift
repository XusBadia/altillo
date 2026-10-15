import AltilloHome
import AppKit
import SwiftUI

// The Home section's pieces: a tile, the doorbell's camera card and the ear beside the resting notch.

extension HomeRGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

// MARK: - A tile

/// One favourite: its symbol, name and state on a wood tile. A light that's on glows with its bulb's real colour, as
/// bright as the bulb is; a plug or a fan that's on warms under the bulb. Click toggles; a sideways drag dims a light
/// or moves a blind (a tap of the trackpad at 0 and 100 %).
struct DesvanHomeTile: View {
    static let height: CGFloat = 54

    let entity: HomeEntity
    let store: HomeStore
    /// False until the opening stagger reaches this tile: its light stays off till then.
    var isRevealed: Bool
    let haptic: (Haptics.Pattern) -> Void

    @State private var isHovering = false
    @State private var dragStart: Double?
    @State private var dragValue: Double?
    @State private var width: CGFloat = 120
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: HomeEntityState { store.state(of: entity) }

    private var canDrag: Bool {
        guard state.isAvailable else { return false }
        return (entity.kind == .light && entity.capabilities.contains(.brightness))
            || (entity.kind == .cover && entity.capabilities.contains(.position))
    }

    /// 0…1: the light's brightness (0 off) or the blind's position.
    private var level: Double {
        if let dragValue { return dragValue }
        switch entity.kind {
        case .light: return state.isOn == true ? state.brightness ?? 1 : 0
        case .cover: return state.position ?? (HomeStore.coverIsOpen(state) ? 1 : 0)
        default: return state.isOn == true ? 1 : 0
        }
    }

    /// How much the tile glows: a lit bulb by its brightness, a plug or fan a little, nothing else.
    private var glow: Double {
        guard isRevealed, state.isAvailable, state.isOn == true else { return 0 }
        switch entity.kind {
        case .light: return 0.35 + 0.65 * (state.brightness ?? 1)
        case .switchable, .fan: return 0.3
        default: return 0
        }
    }

    private var tint: Color {
        entity.kind == .light ? store.glowColor(for: entity).color : Desvan.Palette.bulb
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Image(systemName: HomeText.symbol(for: entity, state: state))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(glow > 0 ? tint : Desvan.Palette.paperSecondary)
                    .shadow(color: tint.opacity(glow * 0.8), radius: 5)
                    .contentTransition(.symbolEffect(.replace))
                Spacer(minLength: 4)
                if store.isPending(entity.id) {
                    Circle()
                        .fill(Desvan.Palette.bulb.opacity(0.85))
                        .frame(width: 5, height: 5)
                        .padding(4)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: entity.name)
                .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paper)
                .lineLimit(1)
            stateLine
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(Desvan.Palette.woodRaised)
                .overlay {
                    // The bulb's light on the tile: strongest at the top left, where the symbol is.
                    shape.fill(LinearGradient(colors: [tint.opacity(0.10 + 0.42 * glow), tint.opacity(0.03 + 0.16 * glow)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                        .opacity(glow > 0 ? 1 : 0)
                }
                .overlay(alignment: .leading) {
                    // The dimmer: the tile fills from the left as far as the light is bright (or the blind open).
                    if canDrag {
                        Rectangle()
                            .fill((entity.kind == .light ? tint : Desvan.Palette.paper).opacity(dragValue != nil ? 0.16 : 0.07))
                            .frame(width: max(0, width * level))
                    }
                }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(glow > 0 ? tint.opacity(0.25 + 0.4 * glow) : Desvan.Palette.hairlineStrong,
                                       lineWidth: 0.75)
                }
                .shadow(color: tint.opacity(0.45 * glow), radius: 4 + 8 * glow)
        }
        .overlay {
            if isHovering, state.isAvailable {
                shape.strokeBorder(Desvan.Palette.paper.opacity(0.22), lineWidth: 1).allowsHitTesting(false)
            }
        }
        .opacity(state.isAvailable ? (isRevealed ? 1 : 0.55) : 0.4)
        .scaleEffect(isHovering && !reduceMotion && state.isAvailable ? 1.02 : 1)
        .contentShape(shape)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max(1, $0) }
        .onHover { hovering in
            withAnimation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion)) { isHovering = hovering }
        }
        .onTapGesture { store.activate(entity) }
        .gesture(drag, including: canDrag ? .all : .none)
        .animation(Desvan.Motion.pick(.easeOut(duration: 0.3), reduceMotion: reduceMotion), value: glow)
        .help(store.problems[entity.id] ?? entity.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entity.name)
        .accessibilityValue(HomeText.stateLine(for: entity, state: state))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.activate(entity) }
        .accessibilityAdjustableAction { direction in
            guard canDrag else { return }
            let step = direction == .increment ? 0.1 : -0.1
            store.drag(entity, to: level + step, final: true)
        }
    }

    @ViewBuilder
    private var stateLine: some View {
        if let problem = store.problems[entity.id] {
            Label(problem, systemImage: "exclamationmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(Desvan.Palette.critical)
                .lineLimit(1)
                .transition(.opacity)
        } else {
            Text(verbatim: dragValue.map { HomeText.percent($0) } ?? HomeText.stateLine(for: entity, state: state))
                .font(.system(size: 11))
                .foregroundStyle(glow > 0 ? Desvan.Palette.paper.opacity(0.8) : Desvan.Palette.paperSecondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let start = dragStart ?? level
                dragStart = start
                let next = min(max(start + value.translation.width / max(width, 1), 0), 1)
                // A tap as the drag hits either end.
                if (next == 0 || next == 1), dragValue != next { haptic(.snap) }
                dragValue = next
                store.drag(entity, to: next, final: false)
            }
            .onEnded { _ in
                if let dragValue { store.drag(entity, to: dragValue, final: true) }
                dragStart = nil
                dragValue = nil
            }
    }
}

// MARK: - Camera card

/// After a ring, for two minutes: the camera's picture, who rang and when, a refresh and a way to put it away.
struct DesvanHomeCameraCard: View {
    let ring: HomeRing
    let name: String?
    let now: Date
    let hasCamera: Bool
    let refresh: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if hasCamera {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.5))
                    if let snapshot = ring.snapshot {
                        Image(nsImage: snapshot)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    } else if ring.isLoadingSnapshot {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "video.slash").foregroundStyle(Desvan.Palette.paperTertiary)
                    }
                }
                .frame(width: 136, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.75)
                }
                .accessibilityLabel("The door camera's picture")
            }
            VStack(alignment: .leading, spacing: 3) {
                Label("Someone rang", systemImage: "bell.fill")
                    .font(Desvan.Typeface.rounded(14, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.bulb)
                Text(verbatim: [name, NotchFormat.ago(ring.at)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if hasCamera {
                        Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                            .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 26))
                    }
                    Button("Dismiss", action: dismiss)
                        .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 26))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(height: 92)
        .desvanCard(radius: 12, glow: Desvan.Palette.bulb)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Ear

/// The house in the ear: the door's symbol, how long it's been open and (in a fixed ear) its name; or a bulb and
/// how many lights were left on.
struct DesvanHomeEar: View {
    let signal: HomeSignal
    let now: Date
    var showsName: Bool

    var body: some View {
        HStack(spacing: EarMetrics.spacing) {
            Image(systemName: signal.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Desvan.Palette.bulb)
                .frame(width: EarMetrics.Glyph.home)
            switch signal {
            case let .leftOpen(name, _, since):
                Text(verbatim: EarMetrics.homeMinutesText("\(HomeEarLogic.minutes(since: since, now: now))"))
                    .font(Desvan.Typeface.figure(EarMetrics.TextSize.figure, weight: .medium))
                    .foregroundStyle(Desvan.Palette.bulb)
                    .lineLimit(1)
                    .fixedSize()
                if showsName, !name.isEmpty {
                    Text(verbatim: name)
                        .font(Desvan.Typeface.rounded(EarMetrics.TextSize.title, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: EarMetrics.measuredTitleWidth(name), alignment: .leading)
                }
            case let .lightsOnWhileAway(count):
                Text(verbatim: HomeEarLogic.lightsOnText(count))
                    .font(Desvan.Typeface.rounded(EarMetrics.TextSize.title, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paper)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .fixedSize()
    }
}

// MARK: - Previews

#Preview("Home") {
    let model = NotchModel()
    model.scenario = .openHome
    return DesvanHomeView(model: model)
        .padding(26)
        .frame(width: 560, height: 238 + 52)
        .background(Color.black)
}

#Preview("Tiles") {
    let store = HomeStore.demo()
    return HStack(spacing: 8) {
        ForEach(store.favourites.prefix(4)) { entity in
            DesvanHomeTile(entity: entity, store: store, isRevealed: true) { _ in }
        }
    }
    .padding(20)
    .frame(width: 540)
    .background(Color.black)
}
