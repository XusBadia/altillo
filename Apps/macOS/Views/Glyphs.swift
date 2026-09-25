import AltilloCore
import AltilloDesign
import SwiftUI

/// Small app-icon-like badge for an agent or an AI provider (squircle at 22 %). Claude and Codex have their own
/// marks; the other providers Altillo reads get a simple mark of its own making (an SF Symbol or a monogram on a
/// tile, never the provider's logo), and any provider it doesn't know yet gets its initial on a tile whose colour
/// comes from its id, so it's always the same colour and different providers rarely share one.
struct AgentGlyph: View {
    enum Brand: Hashable {
        case claude, codex
        /// An SF Symbol on a flat tile.
        case symbol(String, tile: UInt32, ink: UInt32)
        /// One or two letters on a flat tile.
        case monogram(String, tile: UInt32, ink: UInt32)
    }

    let brand: Brand
    let name: String
    var size: CGFloat = 18

    /// A coding agent's mark: the same as its provider's (Claude Code is Claude's, Codex is Codex's), so an agent
    /// Altillo learns later gets the tile its usage would.
    init(agent: AgentKind, size: CGFloat = 18) {
        brand = Self.brand(for: UsageProviderID(rawValue: agent.rawValue), name: agent.name)
        name = agent.name
        self.size = size
    }

    init(provider: UsageProviderID, name: String, size: CGFloat = 18) {
        brand = Self.brand(for: provider, name: name)
        self.name = name
        self.size = size
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.squircle(side: size) * 1.2, style: .continuous)
        ZStack {
            switch brand {
            case .claude:
                shape.fill(Color(hex: 0xD97757))
                ClaudeMark()
                    .fill(Color(hex: 0xFFFFFB))
                    .padding(size * 0.2)
            case .codex:
                shape.fill(Color(hex: 0xF4F1EC))
                Text(verbatim: ">_")
                    .font(.system(size: size * 0.46, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x1C1917))
                    .offset(y: -size * 0.02)
            case let .symbol(symbol, tile, ink):
                shape.fill(Color(hex: tile))
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(Color(hex: ink))
            case let .monogram(letters, tile, ink):
                shape.fill(Color(hex: tile))
                Text(verbatim: letters)
                    .font(.system(size: size * (letters.count > 1 ? 0.42 : 0.55), weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: ink))
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .accessibilityLabel(Text(name))
    }

    // MARK: Marks

    /// The mark for a provider, by its id (a few spellings each, so a collector's id can change without losing it).
    static func brand(for provider: UsageProviderID, name: String) -> Brand {
        switch provider.rawValue.lowercased() {
        case "claude": .claude
        case "codex": .codex
        case "cursor": .symbol("cursorarrow", tile: 0x1C1917, ink: 0xF6EFE3)
        case "copilot", "github-copilot", "githubcopilot": .symbol("airplane", tile: 0x24292F, ink: 0xF6EFE3)
        case "openrouter": .symbol("arrow.triangle.branch", tile: 0x5B5FD6, ink: 0xFFFFFF)
        case "zai", "z.ai", "z-ai", "zhipu", "glm": .monogram("Z", tile: 0x2B4C9B, ink: 0xFFFFFF)
        case "grok", "xai": .monogram("G", tile: 0x0B0B0C, ink: 0xF6EFE3)
        case "gemini", "antigravity", "google-antigravity": .symbol("sparkle", tile: 0x3F6FD8, ink: 0xFFFFFF)
        case "devin", "cognition": .monogram("D", tile: 0x0F766E, ink: 0xFFFFFF)
        case "opencode": .symbol("curlybraces", tile: 0x2A231C, ink: 0xF6EFE3)
        default: fallback(for: provider, name: name)
        }
    }

    /// Warm tiles that sit well on the wood, each with an ink that reads on it.
    static let fallbackTiles: [(tile: UInt32, ink: UInt32)] = [
        (0xC9A77C, 0x2B241D), // kraft
        (0x9DB88A, 0x1E2A17), // sage
        (0xE8B33A, 0x2B1A05), // mustard
        (0xD9826B, 0x2B130C), // clay
        (0x7FA7B5, 0x10232A), // slate blue
        (0xB48EAD, 0x2A1A28), // heather
        (0x8C9A6B, 0x1C2210), // olive
        (0xA3785A, 0xFFF6EA), // walnut
    ]

    /// The initial of the name (or the id) on a tile chosen by a stable hash of the id: FNV-1a, not `hashValue`,
    /// which changes on every launch.
    static func fallback(for provider: UsageProviderID, name: String) -> Brand {
        let source = name.trimmingCharacters(in: .whitespaces).isEmpty ? provider.rawValue : name
        let initial = source.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "?"
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in provider.rawValue.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let colours = fallbackTiles[Int(hash % UInt64(fallbackTiles.count))]
        return .monogram(initial, tile: colours.tile, ink: colours.ink)
    }
}

/// A radial starburst reminiscent of Claude's mark: rounded rays of alternating length.
struct ClaudeMark: Shape {
    var rays = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let thickness = radius * 0.2
        for index in 0..<rays {
            let length = radius * (index.isMultiple(of: 2) ? 1 : 0.78)
            let ray = Path(
                roundedRect: CGRect(x: -thickness / 2, y: -length, width: thickness, height: length),
                cornerRadius: thickness / 2
            )
            let angle = Double(index) / Double(rays) * 2 * .pi
            path.addPath(ray, transform: CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle))
        }
        return path
    }
}

/// AirDrop-like mark: a dot inside three concentric rings, each open at the bottom.
struct AirDropMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let line = side * 0.075
        let dot = side * 0.09
        path.addEllipse(in: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2))
        for (index, radius) in [0.2, 0.33, 0.46].enumerated() {
            // Gap centred at the bottom (90° in y-down coordinates), narrower for outer rings.
            let gap = 70.0 - Double(index) * 14
            var arc = Path()
            let steps = 48
            for step in 0...steps {
                let degrees = 90 + gap / 2 + (360 - gap) * Double(step) / Double(steps)
                let radians = degrees * .pi / 180
                let point = CGPoint(x: center.x + cos(radians) * side * radius, y: center.y + sin(radians) * side * radius)
                if step == 0 { arc.move(to: point) } else { arc.addLine(to: point) }
            }
            path.addPath(arc.strokedPath(StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)))
        }
        return path
    }
}

#Preview("Glyphs") {
    HStack(spacing: 16) {
        AgentGlyph(agent: .claude, size: 28)
        AgentGlyph(agent: .codex, size: 28)
        AgentGlyph(agent: .claude)
        ForEach(["cursor", "copilot", "openrouter", "zai", "grok", "gemini", "devin", "opencode", "mistral"],
                id: \.self) { id in
            AgentGlyph(provider: UsageProviderID(rawValue: id), name: id.capitalized, size: 28)
        }
        AirDropMark().fill(.white).frame(width: 36, height: 36)
    }
    .padding(24)
    .background(.black)
}
