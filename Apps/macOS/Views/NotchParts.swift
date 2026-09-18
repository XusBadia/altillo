import AltilloCore
import AltilloDesign
import SwiftUI

// Small pieces shared by the notch faces.

/// The band beside the hardware notch: a left ear, the notch body (kept clear), a right ear.
struct EarBand<Leading: View, Trailing: View>: View {
    let chrome: NotchChrome
    var earWidth: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: earWidth, alignment: .center)
                .padding(.leading, chrome.topRadius)
            Color.clear.frame(width: chrome.clearWidth)
            trailing
                .frame(width: earWidth, alignment: .center)
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
