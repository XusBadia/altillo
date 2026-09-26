import CoreGraphics
import Testing
@testable import Altillo

@MainActor
struct UXCoreInteractionTests {
    @Test func twelveEditableTabsKeepAUsableTargetAtNarrowWidths() {
        for width: CGFloat in [440, 560, 760] {
            let available = width - 2 * 26 - DesvanEditBody.captionWidth - 6
            let tile = DesvanEditStrip.tileWidth(count: 12, in: available)
            #expect(tile >= 42)
            #expect(tile <= DesvanEditStrip.maxTile)
        }
    }

    @Test func streamedGrowthRespectsReadingIntentAcrossExchanges() {
        var follow = AssistantScrollFollow()
        #expect(follow.shouldFollowNewContent)
        let offset: CGFloat = 400
        let viewport: CGFloat = 300
        #expect(AssistantScrollFollow.nearBottom(offset: offset, viewport: viewport, content: 700))
        // A 200 pt chunk moves the geometric bottom away without a scroll gesture.
        follow.geometryChanged(nearBottom: AssistantScrollFollow.nearBottom(
            offset: offset, viewport: viewport, content: 900
        ))
        #expect(follow.shouldFollowNewContent)
        follow.scrollPhaseChanged(userIsScrolling: true)
        #expect(!follow.shouldFollowNewContent, "a gesture takes priority even within the 40 pt bottom threshold")
        follow.geometryChanged(nearBottom: false)
        follow.scrollPhaseChanged(userIsScrolling: false)
        #expect(!follow.shouldFollowNewContent, "new streamed text must not interrupt reading above")
        follow.returnToLatest()
        #expect(follow.shouldFollowNewContent)
        follow.scrollPhaseChanged(userIsScrolling: true)
        follow.geometryChanged(nearBottom: false)
        follow.scrollPhaseChanged(userIsScrolling: false)
        follow.newExchange()
        #expect(follow.shouldFollowNewContent, "a new question starts at its answer")
    }
}
