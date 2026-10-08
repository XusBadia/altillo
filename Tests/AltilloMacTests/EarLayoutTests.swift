import AppKit
import SwiftUI
import Testing
@testable import Altillo

/// Measure the real SwiftUI content inside the production ear band. Short names previously expanded to the
/// truncation cap even though the silhouette allocated only their natural width, eating the outer margin.
@MainActor
struct EarLayoutTests {
    @MainActor private final class Bounds {
        var left: CGRect?
        var right: CGRect?
    }

    private var examples: [EarItem] {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return [
            .agentRequest(.init(agentName: "Claude", project: "altillo")),
            .usage(.init(providerName: "Claude", fraction: 0.85), isStale: false),
            .shelf(count: 6),
            .event(.init(title: "Sync", start: start, end: start + 1800, isAllDay: false), .now),
            .agentRequest(.init(agentName: "An unusually long agent name that must truncate", project: "altillo")),
            .usage(.init(providerName: "An unusually long provider name", fraction: 0.85), isStale: false),
            .event(.init(title: "An unusually long meeting name that must truncate", start: start,
                         end: start + 1800, isAllDay: false), .now)
        ]
    }

    @Test func renderedContentFitsItsSilhouetteWithEqualMarginsOnBothSides() async throws {
        let suite = "me.badia.altillo.tests.ear-layout.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = NotchModel(settings: AltilloSettings(defaults: defaults))

        for item in examples {
            let width = EarMetrics.width(for: item)
            let bounds = Bounds()
            // The 185 pt camera gap and 6 pt concave fillets are actual hardware-notch geometry.
            var chrome = NotchChrome(model: model)
            chrome.face = .ears
            chrome.size = CGSize(width: 2 * width + 185 + 12, height: 32)
            chrome.topRadius = 6
            chrome.bottomRadius = 10
            chrome.bandHeight = 32
            chrome.notchWidth = 185
            chrome.clearWidth = 185
            chrome.hasNotch = true
            chrome.showsShadow = false
            chrome.leftEarWidth = width
            chrome.rightEarWidth = width
            let band = EarBand(chrome: chrome, leadingWidth: width, trailingWidth: width) {
                DesvanEarItemView(item: item, model: model)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named("earBand"))
                    } action: { bounds.left = $0 }
            } trailing: {
                DesvanEarItemView(item: item, model: model)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named("earBand"))
                    } action: { bounds.right = $0 }
            }
            .coordinateSpace(name: "earBand")
            .fixedSize()
            let hosting = NSHostingView(rootView: band)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: chrome.size),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            hosting.frame = CGRect(origin: .zero, size: chrome.size)
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            hosting.layoutSubtreeIfNeeded()
            let left = try #require(bounds.left, "Left content geometry must render for \(item)")
            let right = try #require(bounds.right, "Right content geometry must render for \(item)")
            window.close()

            #expect(abs(left.width - EarMetrics.contentWidth(for: item)) <= 2,
                    "Rendered content and silhouette measurement disagree for \(item)")
            #expect(abs(right.width - left.width) < 0.5)
            let margins = [
                left.minX - chrome.topRadius,
                chrome.topRadius + width - left.maxX,
                right.minX - (chrome.topRadius + width + chrome.clearWidth),
                chrome.size.width - chrome.topRadius - right.maxX
            ]
            for margin in margins {
                #expect(abs(margin - 9) <= 2, "An ear loses its 9 pt margin for \(item): \(margin)")
            }
            #expect(abs(margins[0] - margins[1]) < 0.5)
            #expect(abs(margins[2] - margins[3]) < 0.5)
        }
    }
}
