import AltilloCore
import AltilloDesign
import SwiftUI

/// Shown while a drag is near the notch: a big shelf drop zone and an AirDrop zone.
/// Both stay quiet until the pointer is over them (`model.dropZone`); only then does one light up.
/// Each zone reports its frame so the AppKit drop target knows where the pointer is.
struct DropZoneView: View {
    let model: NotchModel

    @Environment(\.altilloAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            shelfZone
                .reportingDropZoneFrame(.shelf, to: model)
            AirDropZone(isHovering: model.dropZone == .airDrop)
                .frame(width: 150)
                .reportingDropZoneFrame(.airDrop, to: model)
        }
        .animation(Tokens.Motion.snappy(reduceMotion: reduceMotion), value: model.dropZone)
    }

    private var shelfZone: some View {
        let hovering = model.isDropHovering
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(hovering ? accent.opacity(0.26) : Tokens.Palette.text.opacity(0.06))
                    .frame(width: 50, height: 50)
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(hovering ? accent : Tokens.Palette.textSecondary)
                    .symbolEffect(.bounce.down, value: hovering)
            }
            .scaleEffect(hovering && !reduceMotion ? 1.06 : 1)
            VStack(spacing: 3) {
                Text(hovering ? "Suelta para guardarlo en el altillo" : "Guardar en el altillo")
                    .font(Tokens.Typography.title)
                    .foregroundStyle(hovering ? Tokens.Palette.text : Tokens.Palette.textSecondary)
                    .contentTransition(.opacity)
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
            shape.fill(hovering ? accent.opacity(0.13) : Tokens.Palette.surface)
                .grain(0.05, in: shape)
        }
        .overlay {
            shape.strokeBorder(
                hovering ? accent.opacity(0.95) : Tokens.Palette.hairlineStrong,
                style: StrokeStyle(lineWidth: hovering ? 1.75 : 1, dash: [6, 5])
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

/// Sends whatever is dropped on it with AirDrop.
private struct AirDropZone: View {
    let isHovering: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Tokens.Palette.info.opacity(isHovering ? 0.28 : 0.10))
                    .frame(width: 50, height: 50)
                AirDropMark()
                    .fill(isHovering ? Tokens.Palette.info : Tokens.Palette.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .scaleEffect(isHovering && !reduceMotion ? 1.06 : 1)
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
            shape.fill(isHovering ? Tokens.Palette.info.opacity(0.13) : Tokens.Palette.surface)
                .grain(0.05, in: shape)
        }
        .overlay {
            shape.strokeBorder(
                isHovering ? Tokens.Palette.info.opacity(0.95) : Tokens.Palette.hairlineStrong,
                style: StrokeStyle(lineWidth: isHovering ? 1.75 : 1, dash: [6, 5])
            )
        }
        .shadow(color: Tokens.Palette.info.opacity(isHovering ? 0.35 : 0), radius: 14)
    }
}

private extension View {
    /// Publishes this zone's frame (hosting-view coordinates) so the AppKit drop target can hit-test it.
    func reportingDropZoneFrame(_ zone: DropZone, to model: NotchModel) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.dropZoneFrames[zone] = $0 }
            .onDisappear { model.dropZoneFrames[zone] = nil }
    }
}
