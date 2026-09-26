import SwiftUI

/// Original connected lettering, generated from Apps/Shared/Brand/AltilloGreeting.svg.
/// The SVG is the editable geometry source; each cubic here has the same coordinates.
struct AltilloGreeting: View, Animatable {
    var progress: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        ZStack {
            AltilloGreetingStroke(index: 0, progress: progress)
                .stroke(Desvan.Palette.paper, style: StrokeStyle(lineWidth: 4.2, lineCap: .round, lineJoin: .round))
            AltilloGreetingStroke(index: 1, progress: progress)
                .stroke(Desvan.Palette.paper, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            AltilloGreetingStroke(index: 2, progress: progress)
                .stroke(Desvan.Palette.paper, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
        .shadow(color: Desvan.Palette.bulb.opacity(0.18), radius: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "altillo"))
    }
}

private struct AltilloGreetingStroke: Shape {
    let index: Int
    var progress: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch index {
        // BEGIN GENERATED SVG PATHS
        case 0:
            path.move(to: CGPoint(x: 47, y: 62))
            path.addCurve(to: CGPoint(x: 19, y: 56),
                          control1: CGPoint(x: 42, y: 49),
                          control2: CGPoint(x: 28, y: 48))
            path.addCurve(to: CGPoint(x: 29, y: 85),
                          control1: CGPoint(x: 7, y: 68),
                          control2: CGPoint(x: 15, y: 86))
            path.addCurve(to: CGPoint(x: 47, y: 62),
                          control1: CGPoint(x: 42, y: 84),
                          control2: CGPoint(x: 48, y: 72))
            path.addCurve(to: CGPoint(x: 64, y: 73),
                          control1: CGPoint(x: 47, y: 75),
                          control2: CGPoint(x: 50, y: 86))
            path.addCurve(to: CGPoint(x: 73, y: 17),
                          control1: CGPoint(x: 76, y: 55),
                          control2: CGPoint(x: 81, y: 20))
            path.addCurve(to: CGPoint(x: 66, y: 54),
                          control1: CGPoint(x: 65, y: 14),
                          control2: CGPoint(x: 65, y: 34))
            path.addCurve(to: CGPoint(x: 88, y: 71),
                          control1: CGPoint(x: 67, y: 83),
                          control2: CGPoint(x: 73, y: 88))
            path.addCurve(to: CGPoint(x: 111, y: 25),
                          control1: CGPoint(x: 100, y: 54),
                          control2: CGPoint(x: 110, y: 30))
            path.addCurve(to: CGPoint(x: 107, y: 78),
                          control1: CGPoint(x: 108, y: 44),
                          control2: CGPoint(x: 103, y: 63))
            path.addCurve(to: CGPoint(x: 130, y: 71),
                          control1: CGPoint(x: 109, y: 90),
                          control2: CGPoint(x: 123, y: 83))
            path.addCurve(to: CGPoint(x: 141, y: 57),
                          control1: CGPoint(x: 136, y: 60),
                          control2: CGPoint(x: 138, y: 55))
            path.addCurve(to: CGPoint(x: 141, y: 84),
                          control1: CGPoint(x: 144, y: 61),
                          control2: CGPoint(x: 134, y: 79))
            path.addCurve(to: CGPoint(x: 160, y: 71),
                          control1: CGPoint(x: 147, y: 88),
                          control2: CGPoint(x: 154, y: 80))
            path.addCurve(to: CGPoint(x: 172, y: 16),
                          control1: CGPoint(x: 173, y: 54),
                          control2: CGPoint(x: 180, y: 19))
            path.addCurve(to: CGPoint(x: 165, y: 61),
                          control1: CGPoint(x: 163, y: 15),
                          control2: CGPoint(x: 166, y: 43))
            path.addCurve(to: CGPoint(x: 187, y: 70),
                          control1: CGPoint(x: 166, y: 82),
                          control2: CGPoint(x: 171, y: 87))
            path.addCurve(to: CGPoint(x: 201, y: 16),
                          control1: CGPoint(x: 203, y: 50),
                          control2: CGPoint(x: 208, y: 18))
            path.addCurve(to: CGPoint(x: 193, y: 63),
                          control1: CGPoint(x: 190, y: 14),
                          control2: CGPoint(x: 191, y: 46))
            path.addCurve(to: CGPoint(x: 216, y: 70),
                          control1: CGPoint(x: 194, y: 85),
                          control2: CGPoint(x: 201, y: 87))
            path.addCurve(to: CGPoint(x: 244, y: 51),
                          control1: CGPoint(x: 223, y: 53),
                          control2: CGPoint(x: 233, y: 48))
            path.addCurve(to: CGPoint(x: 254, y: 78),
                          control1: CGPoint(x: 257, y: 54),
                          control2: CGPoint(x: 260, y: 68))
            path.addCurve(to: CGPoint(x: 226, y: 83),
                          control1: CGPoint(x: 248, y: 88),
                          control2: CGPoint(x: 235, y: 89))
            path.addCurve(to: CGPoint(x: 227, y: 57),
                          control1: CGPoint(x: 216, y: 77),
                          control2: CGPoint(x: 217, y: 65))
            path.addCurve(to: CGPoint(x: 260, y: 69),
                          control1: CGPoint(x: 238, y: 48),
                          control2: CGPoint(x: 252, y: 54))
            path.addCurve(to: CGPoint(x: 282, y: 71),
                          control1: CGPoint(x: 267, y: 79),
                          control2: CGPoint(x: 274, y: 81))
        case 1:
            path.move(to: CGPoint(x: 96, y: 44))
            path.addCurve(to: CGPoint(x: 123, y: 41),
                          control1: CGPoint(x: 104, y: 42),
                          control2: CGPoint(x: 115, y: 42))
        case 2:
            path.move(to: CGPoint(x: 142, y: 35))
            path.addCurve(to: CGPoint(x: 145, y: 34),
                          control1: CGPoint(x: 143, y: 34),
                          control2: CGPoint(x: 144, y: 34))
        // END GENERATED SVG PATHS
        default: break
        }
        let starts: [CGFloat] = [0, 0.9, 0.96]
        let durations: [CGFloat] = [0.9, 0.06, 0.04]
        let fraction = min(max((progress - starts[index]) / durations[index], 0), 1)
        return path.applying(CGAffineTransform(scaleX: rect.width / 300, y: rect.height / 110))
            .trimmedPath(from: 0, to: fraction)
    }
}

#Preview("Greeting progress") {
    VStack(spacing: 12) {
        ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { progress in
            AltilloGreeting(progress: progress)
                .frame(width: 300, height: 110)
        }
    }
    .padding(24)
    .background(Desvan.Palette.wood)
}
