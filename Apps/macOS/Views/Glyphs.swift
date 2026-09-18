import AltilloDesign
import SwiftUI

/// Small app-icon-like badge for an agent / provider (squircle at 22 %).
struct AgentGlyph: View {
    let agent: AgentKind
    var size: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.squircle(side: size) * 1.2, style: .continuous)
        ZStack {
            switch agent {
            case .claude:
                shape.fill(Color(hex: 0xD97757))
                ClaudeMark()
                    .fill(Color(hex: 0xFFFFFB))
                    .padding(size * 0.2)
            case .codex:
                shape.fill(Color(hex: 0xF4F1EC))
                Text(">_")
                    .font(.system(size: size * 0.46, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x1C1917))
                    .offset(y: -size * 0.02)
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .accessibilityLabel(Text(agent.name))
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
        AirDropMark().fill(.white).frame(width: 36, height: 36)
    }
    .padding(24)
    .background(.black)
}
