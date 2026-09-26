import AltilloDesign
import SwiftUI

/// "Ask about it": the third drop zone, only while the notch is on Ask. A sheet of paper under the bulb; when the
/// pointer comes over it the bulb lights and the sheet lifts, like the box's flaps.
struct DesvanAssistantDropZone: View {
    let isHovering: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .top) {
                Image(systemName: "doc.text")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(isHovering ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
                    .offset(y: isHovering && !reduceMotion ? 8 : 12)
                DesvanBulbGlyph(size: 16, lit: isHovering ? 1 : 0.35)
                    .offset(y: -8)
            }
            .frame(width: 60, height: 52)
            VStack(spacing: 2) {
                Text("Ask about it")
                    .font(Desvan.Typeface.rounded(15, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                    .lineLimit(1)
                Text("I'll read it, privately")
                    .font(.system(size: 13))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .opacity(isHovering ? 1 : 0.6)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RadialGradient(
                colors: [Desvan.Palette.bulb.opacity(isHovering ? 0.18 : 0), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 130
            )
            .blendMode(.plusLighter)
        }
        .desvanCard(glow: isHovering ? Desvan.Palette.bulb : nil)
        .animation(Desvan.Motion.pick(.spring(duration: 0.3, bounce: 0.3), reduceMotion: reduceMotion), value: isHovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ask about it")
        .accessibilityHint("Drop a file here and ask about it")
    }
}
