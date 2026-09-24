import SwiftUI

extension View {
    /// Tells the notch that this horizontal `ScrollView` scrolls sideways: while its content is wider than it, its
    /// frame (hosting-view coordinates, like the drop zones) is published in `NotchModel.horizontalScrollRegions`, and
    /// a two-finger swipe that starts over it scrolls it instead of changing section. Apply it to the `ScrollView`
    /// itself; `id` names it (for debugging), each instance keeps its own entry.
    func reportsHorizontalScroll(id: String, model: NotchModel) -> some View {
        modifier(HorizontalScrollReporter(id: id, model: model))
    }
}

private struct HorizontalScrollReporter: ViewModifier {
    let id: String
    let model: NotchModel

    @State private var frame: CGRect = .null
    @State private var overflows = false
    /// One entry per view instance: during a section's transition the leaving copy's `onDisappear` can land after
    /// the arriving copy has reported, and must not erase it.
    @State private var instance = UUID()
    private var key: String { "\(id).\(instance.uuidString)" }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                SwipeTracker.overflows(content: geometry.contentSize.width, viewport: geometry.containerSize.width)
            } action: { _, new in
                overflows = new
                publish()
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { new in
                frame = new
                publish()
            }
            .onAppear { publish() }
            .onDisappear { model.horizontalScrollRegions[key] = nil }
    }

    private func publish() {
        let region = overflows && !frame.isNull ? frame : nil
        guard model.horizontalScrollRegions[key] != region else { return }
        model.horizontalScrollRegions[key] = region
    }
}
