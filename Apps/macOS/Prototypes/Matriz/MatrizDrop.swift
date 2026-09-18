import AltilloCore
import AltilloDesign
import SwiftUI

/// Two grid fields while a drag is near: the shelf (≈ 75 %) and AirDrop (≈ 25 %).
/// Both stay dark until the pointer is over one of them (`model.dropZone`); only that field lights up: a flashlight on
/// the matrix around the pointer and a border of marching dots. Each field reports its frame for the AppKit drop target.
struct MatrizDropFields: View {
    let model: NotchModel

    var body: some View {
        let lit = MatrizChrome.litZone(model)
        HStack(spacing: 10) {
            DropField(zone: .shelf, isLit: lit == .shelf, tint: Matriz.Palette.signal) {
                ShelfFieldLabel(count: model.shelf.count, isLit: lit == .shelf)
            }
            .reportingMatrizZone(.shelf, to: model)

            DropField(zone: .airDrop, isLit: lit == .airDrop, tint: Matriz.Palette.airdrop) {
                AirDropFieldLabel(isLit: lit == .airDrop)
            }
            .frame(width: 164)
            .reportingMatrizZone(.airDrop, to: model)
        }
        .padding(.bottom, 2)
    }
}

private extension View {
    func reportingMatrizZone(_ zone: DropZone, to model: NotchModel) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.dropZoneFrames[zone] = $0 }
            .onDisappear { model.dropZoneFrames[zone] = nil }
    }
}

// MARK: - Field

private struct DropField<Label: View>: View {
    let zone: DropZone
    let isLit: Bool
    let tint: Color
    @ViewBuilder let label: Label

    @State private var probe = PointerProbe()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack {
            shape.fill(Matriz.Palette.panel)
            DotGrid(color: Matriz.Palette.dotOff)
            if isLit {
                flashlight
                    .transition(.opacity)
            }
            label
        }
        .clipShape(shape)
        .overlay {
            MarchingDots(color: isLit ? tint : Matriz.Palette.dotDim, cornerRadius: 8, isMarching: isLit)
                .ledGlow(2, opacity: 0.6, isOn: isLit)
        }
        .background(PointerProbeView(probe: probe))
        .animation(reduceMotion ? Matriz.Motion.reduced : .easeOut(duration: 0.12), value: isLit)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isLit ? .isSelected : [])
    }

    /// The matrix lights up in an 80-pt radius around the pointer, with a soft falloff, over a faint wash of the tint.
    private var flashlight: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !isLit || MatrizChrome.forcedZone != nil)) { _ in
                let size = proxy.size
                let fallback = CGPoint(x: size.width * (zone == .shelf ? 0.24 : 0.5), y: size.height * (zone == .shelf ? 0.62 : 0.5))
                let pointer = MatrizChrome.forcedZone != nil ? fallback : (probe.location() ?? fallback)
                let center = UnitPoint(x: pointer.x / max(size.width, 1), y: pointer.y / max(size.height, 1))
                ZStack {
                    DotGrid(color: tint.opacity(0.1))
                    DotGrid(color: tint)
                        .mask(RadialGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white.opacity(0.6), location: 0.4),
                                .init(color: .white.opacity(0), location: 1),
                            ],
                            center: center, startRadius: 0, endRadius: 90
                        ))
                        .ledGlow(2, opacity: 0.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Labels

/// GUARDAR · 6 → 7. Dim until lit; lit, the figures glow in phosphor and the verb turns signal.
private struct ShelfFieldLabel: View {
    let count: Int
    let isLit: Bool

    var body: some View {
        let figure = isLit ? Matriz.Palette.phosphor : Matriz.Palette.phosphor3
        VStack(spacing: 10) {
            Text(isLit ? "SUELTA PARA GUARDAR" : "GUARDAR EN EL ALTILLO")
                .matrizLabel()
                .foregroundStyle(isLit ? Matriz.Palette.signal : Matriz.Palette.phosphor3)
                .ledGlow(2.5, opacity: 0.6, isOn: isLit)
            HStack(spacing: 12) {
                Text("\(count)")
                    .font(Matriz.Fonts.doto(30, weight: 800))
                    .foregroundStyle(figure.opacity(isLit ? 0.55 : 1))
                DotGlyph(Glyph7.arrowRight, pitch: 3.2, dot: 2.4, color: figure)
                    .ledGlow(2, opacity: 0.5, isOn: isLit)
                Text("\(count + 1)")
                    .font(Matriz.Fonts.doto(30, weight: 800))
                    .foregroundStyle(figure)
                    .ledGlow(3, opacity: 0.6, isOn: isLit)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background {
                // A black plate so the figures read over the lit matrix.
                if isLit { Capsule().fill(Matriz.Palette.panel.opacity(0.85)).blur(radius: 8) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLit ? "Suelta para guardar en el altillo" : "Guardar en el altillo")
        .accessibilityValue("\(NotchFormat.things(count)) ahora")
    }
}

/// AIRDROP over concentric rings of dots, which expand while lit.
private struct AirDropFieldLabel: View {
    let isLit: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !isLit || reduceMotion)) { timeline in
                let phase = (isLit && !reduceMotion) ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5 : 0
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let dot: CGFloat = 2.2
                    // Centre LED.
                    let core = isLit ? Matriz.Palette.airdrop : Matriz.Palette.phosphor3
                    context.fill(Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)), with: .color(core))
                    for ring in 0..<3 {
                        let t = (Double(ring) + phase) / 3
                        let radius = 10 + t * 30
                        let fade = isLit ? (1 - t) : (0.5 - Double(ring) * 0.12)
                        let count = max(8, Int(2 * .pi * radius / 6))
                        for index in 0..<count {
                            let angle = Double(index) / Double(count) * 2 * .pi
                            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                            let rect = CGRect(x: point.x - dot / 2, y: point.y - dot / 2, width: dot, height: dot)
                            let color = isLit ? Matriz.Palette.airdrop.opacity(fade) : Matriz.Palette.phosphor.opacity(fade * 0.5)
                            context.fill(Path(ellipseIn: rect), with: .color(color))
                        }
                    }
                }
                .frame(width: 84, height: 84)
                .ledGlow(2, opacity: 0.5, isOn: isLit)
                .background {
                    // A dark disc so the rings read over the matrix.
                    Circle().fill(Matriz.Palette.panel).frame(width: 96, height: 96).blur(radius: 5)
                }
            }
            Text("AIRDROP")
                .matrizLabel()
                .foregroundStyle(isLit ? Matriz.Palette.airdrop : Matriz.Palette.phosphor3)
                .ledGlow(2.5, opacity: 0.6, isOn: isLit)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Enviar por AirDrop")
    }
}
