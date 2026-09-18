import AltilloCore
import AltilloDesign
import SwiftUI

/// Shown while a drag is near the notch: a big shelf drop zone and an AirDrop zone (placeholder until phase 8).
/// `isDropHovering` (the pointer is over the zone itself) makes the shelf zone glow.
struct DropZoneView: View {
    let model: NotchModel

    @Environment(\.altilloAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            shelfZone
            AirDropZone()
                .frame(width: 150)
        }
        .animation(Tokens.Motion.snappy(reduceMotion: reduceMotion), value: model.isDropHovering)
    }

    private var shelfZone: some View {
        let hovering = model.isDropHovering
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(hovering ? 0.26 : 0.14))
                    .frame(width: 50, height: 50)
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(accent)
                    .symbolEffect(.bounce.down, value: hovering)
            }
            .scaleEffect(hovering && !reduceMotion ? 1.06 : 1)
            VStack(spacing: 3) {
                Text("Suelta para guardarlo en el altillo")
                    .font(Tokens.Typography.title)
                    .foregroundStyle(Tokens.Palette.text)
                Text(subtitle)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Palette.textSecondary)
            }
            if !model.shelf.isEmpty {
                ThumbnailStack(items: Array(model.shelf.suffix(4)), side: 22)
                    .opacity(0.8)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape.fill(accent.opacity(hovering ? 0.13 : 0.06))
                .grain(0.05, in: shape)
        }
        .overlay {
            shape.strokeBorder(
                accent.opacity(hovering ? 0.95 : 0.55),
                style: StrokeStyle(lineWidth: hovering ? 1.75 : 1.25, dash: [6, 5])
            )
        }
        .shadow(color: accent.opacity(hovering ? 0.35 : 0), radius: 14)
    }

    private var subtitle: String {
        model.shelf.isEmpty
            ? "Se queda aquí hasta que lo sueltes en otro sitio"
            : "Ya hay \(NotchFormat.things(model.shelf.count)) esperando"
    }
}

/// Placeholder for the AirDrop drop target (PLAN §5.6).
private struct AirDropZone: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Tokens.Palette.info.opacity(0.14))
                    .frame(width: 50, height: 50)
                AirDropMark()
                    .fill(Tokens.Palette.info)
                    .frame(width: 28, height: 28)
            }
            VStack(spacing: 3) {
                Text("AirDrop")
                    .font(Tokens.Typography.title)
                    .foregroundStyle(Tokens.Palette.text)
                Text("Enviar a un dispositivo cercano")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape.fill(Tokens.Palette.surface)
                .grain(0.05, in: shape)
        }
        .overlay {
            shape.strokeBorder(Tokens.Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
        }
    }
}
