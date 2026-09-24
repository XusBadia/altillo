import CoreGraphics

enum NotchLayout {
    /// Fixed size of the transparent panel. Every state must fit inside it (plus room for the shadow): the widest
    /// open notch (760) with the Drawer and the tallest section is ≈ 360 pt. Hit-testing follows the drawn shape,
    /// so the empty rest of the panel never gets in the way.
    static let panelSize = CGSize(width: 780, height: 440)
    /// A drag closer than this to the notch turns `dragArmed` into `dropTarget`.
    static let dropActivationDistance: CGFloat = 150
    /// While the notch is open as a drop target, the drag keeps it open anywhere over it plus this margin.
    static let dropKeepOpenMargin: CGFloat = 60

    enum Timing {
        static let hoverIntent: Duration = .milliseconds(80)
        static let hoverSustained: Duration = .milliseconds(300)
        static let closeGrace: Duration = .milliseconds(400)
        static let alertPeek: Duration = .seconds(3)
    }
}
