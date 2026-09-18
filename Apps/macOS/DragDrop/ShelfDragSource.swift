import AltilloCore
import AppKit
import SwiftUI

extension View {
    /// Makes a shelf tile draggable out of Altillo. `items` is evaluated when the drag starts
    /// (the whole selection when the tile is selected). `onEnded` reports the operation the destination performed.
    /// STUB: implemented by the drag & drop spike. Keep this API.
    func shelfDraggable(
        items: @escaping () -> [ShelfItem],
        onEnded: @escaping (NSDragOperation, [ShelfItem]) -> Void
    ) -> some View {
        self
    }
}
