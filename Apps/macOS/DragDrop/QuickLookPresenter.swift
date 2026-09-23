import AppKit
import Quartz

/// Shows Quick Look for shelf files. The notch panel is a non-activating panel, so instead of the responder-chain
/// handshake (`acceptsPreviewPanelControl`) the presenter feeds the shared panel directly and activates Altillo so the
/// preview panel itself can become key (arrow keys, space and Esc work there). When it closes, Altillo deactivates
/// again so the keyboard goes back to the user's app.
@MainActor
enum QuickLookPresenter {
    static func show(_ urls: [URL]) {
        let urls = existingURLs(in: urls)
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else {
            SpikeLog.shared.record(SpikeLog.Category.quickLook, "nothing to preview")
            return
        }
        source.urls = urls
        panel.dataSource = source
        panel.delegate = source
        panel.currentPreviewItemIndex = 0
        panel.reloadData()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        if closeObserver == nil {
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: panel, queue: .main
            ) { _ in
                MainActor.assumeIsolated { NSApp.deactivate() }
            }
        }
        SpikeLog.shared.record(SpikeLog.Category.quickLook,
                               "\(urls.count) file(s) · visible: \(panel.isVisible ? "yes" : "no") · key: \(panel.isKeyWindow ? "yes" : "no")")
    }

    private static let source = Source()
    private static var closeObserver: NSObjectProtocol?

    static func existingURLs(in urls: [URL]) -> [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    final class Source: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var urls: [URL] = []

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            urls.count
        }

        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
            urls.indices.contains(index) ? urls[index] as NSURL : nil
        }
    }
}
