import AppKit
import SwiftUI

// The pieces every Settings pane is built from, so the window reads with one hierarchy:
//
//   pane title (SettingsPane)            17 rounded, the window's only big line
//   card title (SettingsGroupHeading)    13.5 rounded semibold, with its one-line detail under it
//   subheading (SettingsSubheading)      10.5 rounded caps, quiet: names a group of rows inside a card
//   row title (settingsRowTitle)         12.5 medium: the thing a control changes
//   hint (settingsHint)                  11 secondary: what it does, never shouting
//   code (settingsCode)                  10.5 mono tertiary: paths and commands
//
// Controls sit on the trailing edge of their row; lists of like things (agents, providers, apps) sit in a recessed
// well, one hairline between them. Whatever appears or disappears does it with `settingsReveal`, inside a
// `withAnimation(SettingsMotion…)`, so nothing in the window jumps.

// MARK: - Motion

enum SettingsMotion {
    /// A card or a group unfolding: the height and the content settle together, without a bounce.
    static let fold = Animation.spring(duration: 0.32, bounce: 0)
    /// A line, a warning or a button coming or going inside a card.
    static let reveal = Animation.spring(duration: 0.26, bounce: 0)
    /// A row changing place (a section switched on or off, moved).
    static let reorder = Animation.spring(duration: 0.34, bounce: 0.12)

    static func pick(_ animation: Animation, reduceMotion: Bool) -> Animation {
        Desvan.Motion.pick(animation, reduceMotion: reduceMotion)
    }
}

extension AnyTransition {
    /// Content coming into a card: it fades in as it drops the last few points into place; it leaves by fading.
    static var settingsReveal: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: -5)), removal: .opacity)
    }
}

// MARK: - Type

extension Text {
    /// Explanatory line under a control: small, paper, never shouting.
    func settingsHint() -> some View {
        self
            .font(.system(size: 11))
            .foregroundStyle(Desvan.Palette.paperSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The thing a control changes: a switch's, a picker's or a checkbox's label.
    func settingsRowTitle() -> some View {
        self
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Desvan.Palette.paper)
    }

    /// A path or a command, selectable.
    func settingsCode() -> some View {
        self
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Desvan.Palette.paperTertiary)
            .textSelection(.enabled)
    }
}

// MARK: - Headings

/// A card's title and its one-line detail.
struct SettingsGroupHeading: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?

    init(title: LocalizedStringKey, detail: LocalizedStringKey? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Desvan.Typeface.rounded(13.5, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paper)
            if let detail {
                Text(detail).settingsHint()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Names a group of rows inside a card, in quiet small caps, with room for one trailing control ("Check Again").
struct SettingsSubheading<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(Desvan.Typeface.rounded(10.5, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.leading, 2)
    }
}

extension SettingsSubheading where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.title = title
        self.trailing = EmptyView()
    }
}

// MARK: - Dividers

/// Between a card's heading and its body, or between two groups of a card.
struct SettingsCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Desvan.Palette.hairline)
            .frame(height: 0.75)
            .padding(.vertical, 10)
    }
}

/// Between two rows of a list; `leading` keeps it clear of the rows' icons.
struct SettingsRowDivider: View {
    var leading: CGFloat = 52

    var body: some View {
        Rectangle()
            .fill(Desvan.Palette.hairline)
            .frame(height: 0.75)
            .padding(.leading, leading)
    }
}

// MARK: - Rows

/// A setting with its switch on the trailing edge: the title, what it does under it.
struct SettingsToggleRow: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @Binding var isOn: Bool
    var controlSize: ControlSize = .small

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil, isOn: Binding<Bool>,
         controlSize: ControlSize = .small) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
        self.controlSize = controlSize
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).settingsRowTitle()
                if let detail {
                    Text(detail).settingsHint()
                }
            }
            Spacer(minLength: 12)
            Toggle(isOn: $isOn) { Text(title) }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(controlSize)
        }
        .contentShape(Rectangle())
    }
}

/// A recessed well on a card for a list of like things: agents, providers, calendars, apps.
struct SettingsWell<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            shape.fill(Color.black.opacity(0.18))
                .overlay { shape.strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
        }
    }
}

// MARK: - Badges and notices

enum SettingsTone {
    case neutral, good, warning, accent

    var color: Color {
        switch self {
        case .neutral: Desvan.Palette.paperSecondary
        case .good: Desvan.Palette.sage
        case .warning: Desvan.Palette.warning
        case .accent: Desvan.Palette.bulb
        }
    }
}

/// A state in a word, on a capsule of its colour ("Installed", "Needs update"). Never colour alone.
struct SettingsBadge: View {
    let text: String
    var symbol: String?
    var tone: SettingsTone = .neutral

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(verbatim: text)
                .font(Desvan.Typeface.rounded(10.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 6)
        .frame(height: 17)
        .background {
            Capsule().fill(tone == .neutral ? Desvan.Palette.paper.opacity(0.07) : tone.color.opacity(0.14))
        }
        .fixedSize()
    }
}

/// Something that needs the user before a setting can work (an access to give, a shortcut taken): its symbol, what's
/// missing and the button that fixes it, on a faint wash of its tone.
struct SettingsNotice<Actions: View>: View {
    let symbol: String
    let message: LocalizedStringKey
    var tone: SettingsTone = .accent
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            Text(message).settingsHint()
            Spacer(minLength: 8)
            actions
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            shape.fill(tone.color.opacity(0.08))
                .overlay { shape.strokeBorder(tone.color.opacity(0.22), lineWidth: 0.75) }
        }
    }
}

extension SettingsNotice where Actions == EmptyView {
    init(symbol: String, message: LocalizedStringKey, tone: SettingsTone = .accent) {
        self.symbol = symbol
        self.message = message
        self.tone = tone
        self.actions = EmptyView()
    }
}

// MARK: - Disclosure

/// A card that folds: its symbol on a plank tile, its title and detail, a chevron that turns, and the body that
/// unfolds under a hairline. The whole header is the button; it lightens under the pointer.
struct SettingsDisclosureCard<Content: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(SettingsMotion.pick(SettingsMotion.fold, reduceMotion: reduceMotion)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Desvan.Palette.bulb)
                            .frame(width: 30, height: 30)
                            .background {
                                let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                                shape.fill(Desvan.Palette.plank.opacity(isHovering || isExpanded ? 1 : 0.85))
                                    .overlay { shape.strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
                            }
                        SettingsGroupHeading(title: title, detail: detail)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isHovering ? Desvan.Palette.paper : Desvan.Palette.paperTertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Desvan.Palette.paper.opacity(isHovering ? 0.08 : 0)))
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(SettingsPressStyle())
                .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
                .help(isExpanded ? "Hide these options" : "Show these options")
                .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))

                if isExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsCardDivider()
                        content
                    }
                    .transition(.settingsReveal)
                }
            }
        }
    }
}

/// A fold inside a card ("Not set up on this Mac 7"): a turning chevron, the title and a count.
struct SettingsInlineDisclosure<Content: View>: View {
    let title: LocalizedStringKey
    var count: Int?
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(SettingsMotion.pick(SettingsMotion.fold, reduceMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                    if let count {
                        Text(verbatim: "\(count)")
                            .font(Desvan.Typeface.rounded(11, weight: .semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 5)
                            .frame(height: 15)
                            .background(Capsule().fill(Desvan.Palette.paper.opacity(0.08)))
                    }
                }
                .foregroundStyle(isHovering ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(SettingsPressStyle())
            .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
            .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))

            if isExpanded {
                content
                    .transition(.settingsReveal)
            }
        }
    }
}

// MARK: - Feedback

/// Plain buttons that give a little under the finger and come back without a wobble.
struct SettingsPressStyle: ButtonStyle {
    var scale: CGFloat = 0.985

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Desvan.Motion.press, value: configuration.isPressed)
    }
}

/// A faint lift under the pointer for rows that do something on click, drag or right-click.
struct SettingsHoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 8
    var inset: CGFloat = 6
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Desvan.Palette.paper.opacity(isHovering ? 0.045 : 0))
                    .padding(.horizontal, -inset)
            }
            .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
    }
}

extension View {
    func settingsHoverHighlight(cornerRadius: CGFloat = 8, inset: CGFloat = 6) -> some View {
        modifier(SettingsHoverHighlight(cornerRadius: cornerRadius, inset: inset))
    }
}

// MARK: - Permissions

/// Altillo's own icon, ready to be dragged into a privacy list in System Settings (Accessibility), which takes apps
/// dropped on it. It lifts a little under the pointer so it reads as something to pick up.
@MainActor
struct AppIconDragSource: View {
    var size: CGFloat = 56

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

    var body: some View {
        Image(nsImage: Self.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(isHovering ? 0.35 : 0.22), radius: isHovering ? 7 : 4, y: isHovering ? 4 : 2)
            .scaleEffect(isHovering && !reduceMotion ? 1.06 : 1)
            .animation(Desvan.Motion.hover, value: isHovering)
            .onHover { isHovering = $0 }
            .pointerStyle(.grabIdle)
            .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
            .help("Drag into the Accessibility list in System Settings")
            .accessibilityLabel("Altillo app icon")
            .accessibilityHint("Drag it into the Accessibility list in System Settings.")
    }
}
