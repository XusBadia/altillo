import AltilloCore
import AltilloDesign
import SwiftUI

// Small pieces shared by the notch faces.

/// The band beside the hardware notch: a left ear, the notch body (kept clear), a right ear.
struct EarBand<Leading: View, Trailing: View>: View {
    let chrome: NotchChrome
    var leadingWidth: CGFloat
    var trailingWidth: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    init(chrome: NotchChrome, earWidth: CGFloat,
         @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.init(chrome: chrome, leadingWidth: earWidth, trailingWidth: earWidth, leading: leading, trailing: trailing)
    }

    /// Ears of their own widths (the resting ears fit what each one says).
    init(chrome: NotchChrome, leadingWidth: CGFloat, trailingWidth: CGFloat,
         @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.chrome = chrome
        self.leadingWidth = leadingWidth
        self.trailingWidth = trailingWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: leadingWidth, alignment: .center)
                .padding(.leading, chrome.topRadius)
            Color.clear.frame(width: chrome.clearWidth)
            trailing
                .frame(width: trailingWidth, alignment: .center)
                .padding(.trailing, chrome.topRadius)
        }
        .frame(height: chrome.bandHeight)
    }
}

/// Up to a few thumbnails overlapping like an avatar stack, newest on top, each cut out with a black ring.
struct ThumbnailStack: View {
    let items: [ShelfItem]
    var side: CGFloat = 20

    var body: some View {
        HStack(spacing: -side * 0.38) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ShelfThumbnail(item: item, side: side, compact: true)
                    .padding(1.5)
                    .background {
                        RoundedRectangle(cornerRadius: side * 0.24 + 1.5, style: .continuous).fill(.black)
                    }
                    .zIndex(Double(index))
            }
        }
        .accessibilityHidden(true)
    }
}
