import AltilloCore
import SwiftUI

/// Geometry of the Fluido silhouette per face. Starts from the current `NotchChrome` (same faces, same footprint over
/// the hardware notch, so hit-testing and the ears behave identically) and makes the shapes rounder and more liquid:
/// big concentric radii, a pill-like peek and a drop-shaped drag tab.
struct FluidoChrome: Equatable {
    var base: NotchChrome

    var face: NotchFace { base.face }
    var size: CGSize
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var bandHeight: CGFloat { base.bandHeight }
    var notchWidth: CGFloat { base.notchWidth }
    var clearWidth: CGFloat { base.clearWidth }
    var hasNotch: Bool { base.hasNotch }

    static let earWidth: CGFloat = 54
    static let peekLineHeight: CGFloat = 36
    static let expandedContentHeight: CGFloat = NotchChrome.expandedContentHeight

    var contentInset: CGFloat { topRadius + 16 }

    @MainActor
    init(model: NotchModel) {
        base = NotchChrome(model: model)
        size = base.size
        topRadius = base.topRadius
        bottomRadius = base.bottomRadius
        let notch = base.hasNotch ? CGSize(width: base.notchWidth, height: base.bandHeight) : .zero

        switch base.face {
        case .rest:
            break
        case .ears:
            if base.hasNotch {
                size = CGSize(width: base.clearWidth + 2 * Self.earWidth + 2 * topRadius, height: notch.height)
                bottomRadius = 12
            }
        case .peek(.hint):
            if base.hasNotch { bottomRadius = 14 }
        case .peek:
            topRadius = 9
            if base.hasNotch {
                size = CGSize(width: max(size.width, 384), height: notch.height + Self.peekLineHeight)
                bottomRadius = 24
            } else {
                size = CGSize(width: 392, height: 40)
                bottomRadius = 20
            }
        case .dragArmed:
            topRadius = 9
            bottomRadius = base.hasNotch ? 22 : 18
            if !base.hasNotch { size = CGSize(width: 150, height: 38) }
        case .expanded:
            topRadius = 14
            bottomRadius = Fluido.Radius.panel
        }
    }

    /// Faces where the notch is at rest (closing animations, no bounce).
    var isResting: Bool {
        switch face {
        case .rest, .ears: true
        default: false
        }
    }
}
