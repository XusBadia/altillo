import SwiftUI

/// The shelf's drop zone: a cardboard box seen from slightly above. Its two top flaps are hinged on the long top
/// edges and swing open (`openness` 0 → 1) when a drag hovers it; the inside warms with the bulb's light.
///
/// Drawn in a small 3D space and projected by hand so the flaps foreshorten like real cardboard. The view is
/// `Animatable`, so the flaps follow whatever spring drives `openness`.
struct DesvanCardboardBox: View, Animatable {
    /// 0 = flaps closed and taped, 1 = flaps open.
    var openness: Double
    /// Light inside the box, 0…1.
    var warmth: Double

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(openness, warmth) }
        set {
            openness = newValue.first
            warmth = newValue.second
        }
    }

    static let canvasSize = CGSize(width: 196, height: 146)

    // Box dimensions in points (world space). x right, y up, z towards the viewer.
    private let width: Double = 108
    private let height: Double = 54
    private let depth: Double = 44
    /// Thickness of the corrugated board, as seen on its cut edges.
    private let board: Double = 2.6
    /// Camera elevation.
    private let elevation = 26.0 * .pi / 180

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .accessibilityHidden(true)
    }

    private struct P3 { var x, y, z: Double }

    private func project(_ p: P3, in size: CGSize) -> CGPoint {
        let upward = p.y * cos(elevation) - p.z * sin(elevation)
        let away = -(p.y * sin(elevation) + p.z * cos(elevation))
        let f = 1 / (1 + away * 0.0026)
        return CGPoint(x: size.width / 2 + p.x * f, y: size.height * 0.84 - upward * f)
    }

    private func polygon(_ points: [P3], in size: CGSize) -> Path {
        var path = Path()
        path.addLines(points.map { project($0, in: size) })
        path.closeSubpath()
        return path
    }

    /// Cardboard fibres and faint flutes under the liner (a cached procedural tile).
    private static var cardboardTexture: GraphicsContext.Shading {
        .tiledImage(DesvanTexture.cardboard, origin: .zero, sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: 1)
    }

    /// A cut edge of corrugated board from `a` to `b`: a pale strip `thickness` thick (towards the top of the
    /// screen, or sideways for the open flaps) with the wavy flute running between its two liners.
    private func corrugatedEdge(in context: inout GraphicsContext, from a: CGPoint, to b: CGPoint,
                                thickness: Double, outwards side: Double) {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.001)
        let dir = CGPoint(x: dx / length, y: dy / length)
        // Normal pointing up the screen (for flaps: away from the box's centre).
        var normal = CGPoint(x: dir.y, y: -dir.x)
        if normal.y > 0 { normal = CGPoint(x: -normal.x, y: -normal.y) }
        if side != 0, (normal.x > 0) != (side > 0) {
            normal = CGPoint(x: -normal.x, y: -normal.y)
        }
        let t = CGFloat(thickness)
        func at(_ s: CGFloat, _ h: CGFloat) -> CGPoint {
            CGPoint(x: a.x + dir.x * s + normal.x * h, y: a.y + dir.y * s + normal.y * h)
        }
        var strip = Path()
        strip.addLines([at(0, 0), at(length, 0), at(length, t), at(0, t)])
        strip.closeSubpath()
        context.fill(strip, with: .color(Color(hex: 0xD7B886)))
        // The flute.
        var flute = Path()
        let step: CGFloat = 0.5
        let wavelength: CGFloat = 3.2
        var s: CGFloat = 0
        flute.move(to: at(0, t / 2))
        while s <= length {
            flute.addLine(to: at(s, t / 2 + sin(2 * .pi * s / wavelength) * t * 0.36))
            s += step
        }
        context.stroke(flute, with: .color(Color(hex: 0x7A5A34).opacity(0.85)), lineWidth: 0.55)
        // Liners.
        var liners = Path()
        liners.move(to: at(0, 0)); liners.addLine(to: at(length, 0))
        liners.move(to: at(0, t)); liners.addLine(to: at(length, t))
        context.stroke(liners, with: .color(Color(hex: 0x6B4E2E).opacity(0.8)), lineWidth: 0.5)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let hw = width / 2, hd = depth / 2
        // Flap angle: closed flaps lie flat over the opening; open ones swing up and outwards (~118°).
        let angle = openness * 118 * .pi / 180
        let flapLength = hw - 0.5

        let frontFace = polygon([
            P3(x: -hw, y: 0, z: hd), P3(x: hw, y: 0, z: hd), P3(x: hw, y: height, z: hd), P3(x: -hw, y: height, z: hd),
        ], in: size)
        let opening = polygon([
            P3(x: -hw, y: height, z: hd), P3(x: hw, y: height, z: hd),
            P3(x: hw, y: height, z: -hd), P3(x: -hw, y: height, z: -hd),
        ], in: size)

        // Contact shadow on the floor.
        let floor = project(P3(x: 0, y: 0, z: hd), in: size)
        context.fill(
            Path(ellipseIn: CGRect(x: floor.x - hw - 12, y: floor.y - 6, width: width + 24, height: 12)),
            with: .color(.black.opacity(0.55))
        )

        // Inside of the box (seen through the opening): dark cardboard, warmed by the bulb.
        context.fill(opening, with: .color(Color(hex: 0x2A1E13)))
        if warmth > 0 {
            let center = project(P3(x: 0, y: height, z: -hd * 0.2), in: size)
            context.fill(opening, with: .radialGradient(
                Gradient(colors: [Desvan.Palette.bulb.opacity(0.85 * warmth), Desvan.Palette.bulb.opacity(0.15 * warmth), .clear]),
                center: center, startRadius: 0, endRadius: width * 0.55
            ))
        }
        // The back inner wall's top edge catches a little light.
        var backEdge = Path()
        backEdge.move(to: project(P3(x: -hw, y: height, z: -hd), in: size))
        backEdge.addLine(to: project(P3(x: hw, y: height, z: -hd), in: size))
        context.stroke(backEdge, with: .color(Color(hex: 0xC9A77C).opacity(0.5)), lineWidth: 1)

        // Flaps: hinged at x = ±hw along the top, swinging up and out.
        func flap(side: Double) -> (path: Path, shade: Double) {
            let dx = -side * cos(angle), dy = sin(angle)
            let hingeFront = P3(x: side * hw, y: height, z: hd)
            let hingeBack = P3(x: side * hw, y: height, z: -hd)
            let tipBack = P3(x: side * hw + dx * flapLength, y: height + dy * flapLength, z: -hd)
            let tipFront = P3(x: side * hw + dx * flapLength, y: height + dy * flapLength, z: hd)
            // Lambert-ish shade: flat flaps face the sky (bright), open ones turn to the side.
            let shade = 0.78 + 0.22 * abs(cos(angle))
            return (polygon([hingeFront, tipFront, tipBack, hingeBack], in: size), shade)
        }
        let left = flap(side: -1), right = flap(side: 1)

        // When open, the flaps sit behind the front face's top edge; draw them before the front.
        let flapFill: (Double) -> GraphicsContext.Shading = { shade in
            .linearGradient(
                Gradient(colors: [
                    Desvan.Palette.cardboard.opacity(1).mix(with: .black, by: 1 - shade),
                    Desvan.Palette.cardboardDark.mix(with: .black, by: (1 - shade) * 0.8),
                ]),
                startPoint: project(P3(x: 0, y: height + 30, z: 0), in: size),
                endPoint: project(P3(x: 0, y: height, z: hd), in: size)
            )
        }
        if openness > 0.02 {
            for flap in [left, right] {
                context.fill(flap.path, with: flapFill(flap.shade))
                context.fill(flap.path, with: Self.cardboardTexture)
                context.stroke(flap.path, with: .color(Color(hex: 0x5E4529).opacity(0.9)), lineWidth: 0.75)
            }
            // The flaps' cut edges face us: corrugated board, the wavy flute between two liners.
            for side in [-1.0, 1.0] {
                let dx = -side * cos(angle), dy = sin(angle)
                let hinge = project(P3(x: side * hw, y: height, z: hd), in: size)
                let tip = project(P3(x: side * hw + dx * flapLength, y: height + dy * flapLength, z: hd), in: size)
                corrugatedEdge(in: &context, from: hinge, to: tip, thickness: board, outwards: side)
            }
        }

        // Front face: cardboard, lit from above (the bulb), with a slightly darker, scuffed bottom.
        context.fill(frontFace, with: .linearGradient(
            Gradient(colors: [Color(hex: 0xAD8656), Color(hex: 0x98734A), Color(hex: 0x7F5F3C)]),
            startPoint: project(P3(x: 0, y: height, z: hd), in: size),
            endPoint: project(P3(x: 0, y: 0, z: hd), in: size)
        ))
        context.fill(frontFace, with: Self.cardboardTexture)
        // Corners wear first: a soft darkening towards both sides.
        context.fill(frontFace, with: .linearGradient(
            Gradient(stops: [
                .init(color: .black.opacity(0.22), location: 0),
                .init(color: .clear, location: 0.18),
                .init(color: .clear, location: 0.82),
                .init(color: .black.opacity(0.22), location: 1),
            ]),
            startPoint: project(P3(x: -hw, y: height / 2, z: hd), in: size),
            endPoint: project(P3(x: hw, y: height / 2, z: hd), in: size)
        ))
        context.stroke(frontFace, with: .color(Color(hex: 0x5E4529)), lineWidth: 0.75)
        if openness > 0.02 {
            // The front wall's cut top edge.
            let a = project(P3(x: -hw, y: height, z: hd), in: size)
            let b = project(P3(x: hw, y: height, z: hd), in: size)
            corrugatedEdge(in: &context, from: a, to: b, thickness: board, outwards: 0)
        }

        // "This side up": two small arrows printed on the front, top-right.
        let arrowsOrigin = project(P3(x: hw - 22, y: height - 11, z: hd), in: size)
        for index in 0..<2 {
            let x = arrowsOrigin.x + CGFloat(index) * 7
            var arrow = Path()
            arrow.move(to: CGPoint(x: x, y: arrowsOrigin.y + 9))
            arrow.addLine(to: CGPoint(x: x, y: arrowsOrigin.y))
            arrow.move(to: CGPoint(x: x - 2.6, y: arrowsOrigin.y + 2.8))
            arrow.addLine(to: CGPoint(x: x, y: arrowsOrigin.y))
            arrow.addLine(to: CGPoint(x: x + 2.6, y: arrowsOrigin.y + 2.8))
            context.stroke(arrow, with: .color(Color(hex: 0x4A3520).opacity(0.75)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        var underline = Path()
        underline.move(to: CGPoint(x: arrowsOrigin.x - 3, y: arrowsOrigin.y + 11.5))
        underline.addLine(to: CGPoint(x: arrowsOrigin.x + 10, y: arrowsOrigin.y + 11.5))
        context.stroke(underline, with: .color(Color(hex: 0x4A3520).opacity(0.75)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

        // A paper label on the front, left.
        let labelTopLeft = project(P3(x: -hw + 12, y: height - 13, z: hd), in: size)
        let label = Path(roundedRect: CGRect(x: labelTopLeft.x, y: labelTopLeft.y, width: 40, height: 22), cornerRadius: 1.5)
        context.fill(label, with: .color(Color(hex: 0xEFE5D2)))
        for line in 0..<3 {
            var stroke = Path()
            let y = labelTopLeft.y + 6 + CGFloat(line) * 5
            stroke.move(to: CGPoint(x: labelTopLeft.x + 5, y: y))
            stroke.addLine(to: CGPoint(x: labelTopLeft.x + (line == 2 ? 22 : 34), y: y))
            context.stroke(stroke, with: .color(Color(hex: 0x6B5A48).opacity(0.55)), lineWidth: 1)
        }

        // Closed flaps lie flat on top, taped along the seam.
        if openness <= 0.02 {
            for flap in [left, right] {
                context.fill(flap.path, with: .linearGradient(
                    Gradient(colors: [Color(hex: 0xA88255), Color(hex: 0xC29B68)]),
                    startPoint: project(P3(x: 0, y: height, z: -hd), in: size),
                    endPoint: project(P3(x: 0, y: height, z: hd), in: size)
                ))
                context.fill(flap.path, with: Self.cardboardTexture)
                context.stroke(flap.path, with: .color(Color(hex: 0x5E4529).opacity(0.9)), lineWidth: 0.75)
            }
            // The closed flaps' front cut edges sit on the front wall.
            let a = project(P3(x: -hw, y: height, z: hd), in: size)
            let b = project(P3(x: hw, y: height, z: hd), in: size)
            corrugatedEdge(in: &context, from: a, to: b, thickness: board, outwards: 0)
            let tape = polygon([
                P3(x: -7, y: height + 0.2, z: hd), P3(x: 7, y: height + 0.2, z: hd),
                P3(x: 7, y: height + 0.2, z: -hd), P3(x: -7, y: height + 0.2, z: -hd),
            ], in: size)
            context.fill(tape, with: .color(Desvan.Palette.tape.opacity(0.88)))
            // The tape wraps over the front edge a little.
            let wrap = polygon([
                P3(x: -7, y: height, z: hd + 0.2), P3(x: 7, y: height, z: hd + 0.2),
                P3(x: 7, y: height - 12, z: hd + 0.2), P3(x: -7, y: height - 12, z: hd + 0.2),
            ], in: size)
            context.fill(wrap, with: .color(Desvan.Palette.tape.opacity(0.8)))
        } else {
            // Torn tape ends stay on the flaps' tips.
            for side in [-1.0, 1.0] {
                let dx = -side * cos(angle), dy = sin(angle)
                let tip = { (z: Double) in P3(x: side * hw + dx * flapLength, y: height + dy * flapLength, z: z) }
                let inner = { (z: Double) in P3(x: side * hw + dx * (flapLength - 7), y: height + dy * (flapLength - 7), z: z) }
                let strip = polygon([inner(hd), tip(hd), tip(-hd), inner(-hd)], in: size)
                context.fill(strip, with: .color(Desvan.Palette.tape.opacity(0.8 * min(1, openness * 3))))
            }
        }

        // Light spilling out of the open box.
        if warmth > 0, openness > 0.02 {
            let mouth = project(P3(x: 0, y: height + 6, z: 0), in: size)
            context.blendMode = .plusLighter
            context.fill(
                Path(ellipseIn: CGRect(x: mouth.x - 80, y: mouth.y - 50, width: 160, height: 90)),
                with: .radialGradient(
                    Gradient(colors: [Desvan.Palette.bulb.opacity(0.22 * warmth * openness), .clear]),
                    center: mouth, startRadius: 0, endRadius: 80
                )
            )
        }
    }
}
