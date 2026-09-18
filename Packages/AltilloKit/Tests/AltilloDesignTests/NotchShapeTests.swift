import SwiftUI
import Testing
@testable import AltilloDesign

struct NotchShapeTests {
    @Test func animatableDataRoundTrips() {
        var shape = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        shape.animatableData = AnimatablePair(19, 24)
        #expect(shape.topCornerRadius == 19)
        #expect(shape.bottomCornerRadius == 24)
    }

    @Test func pathStaysInsideItsRect() {
        let rect = CGRect(x: 0, y: 0, width: 185, height: 32)
        let bounds = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14).path(in: rect).boundingRect
        #expect(bounds.minX >= rect.minX - 0.5 && bounds.maxX <= rect.maxX + 0.5)
        #expect(bounds.minY >= rect.minY - 0.5 && bounds.maxY <= rect.maxY + 0.5)
    }

    @Test func oversizedRadiiDoNotBreakTinyRects() {
        let path = NotchShape(topCornerRadius: 40, bottomCornerRadius: 80).path(in: CGRect(x: 0, y: 0, width: 20, height: 6))
        #expect(!path.isEmpty)
    }

    @Test func emptyRectGivesEmptyPath() {
        #expect(NotchShape().path(in: .zero).isEmpty)
    }

    @Test func accentPresetsAreDistinct() {
        let ids = Tokens.AccentPreset.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
