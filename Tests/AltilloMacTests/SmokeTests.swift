import Testing
@testable import Altillo

@MainActor
struct SmokeTests {
    @Test func designScenariosCoverEveryState() {
        let states = Set(DesignScenario.allCases.map(\.state))
        #expect(states.count == 5)
    }

    @Test func shelfFeedbackScenariosExposeLoadingAndError() {
        let loading = NotchModel.preview(.openShelfLoading)
        #expect(loading.isReceivingDrop)
        #expect(loading.shelfProblem == nil)

        let error = NotchModel.preview(.openShelfError)
        #expect(!error.isReceivingDrop)
        #expect(error.shelfProblem?.isEmpty == false)
    }

    @Test func drawerStaysAboveEveryModuleAndFitsThePanel() {
        let model = NotchModel.preview(.openDrawer)
        #expect(model.module == .shelf)
        for hasNotch in [true, false] {
            model.hasNotch = hasNotch
            for module in NotchModule.allCases {
                model.module = module
                let chrome = NotchChrome(model: model)
                #expect(chrome.showsDrawer)
                // Room left for the shadow under the tallest face (the Drawer plus the tallest section).
                #expect(chrome.size.height + 40 <= NotchLayout.panelSize.height)
                #expect(chrome.size.height > chrome.contentHeight + chrome.bandHeight + NotchChrome.drawerHeight)
            }
        }
    }

    /// The widest open notch fits the panel.
    @Test func widestOpenNotchFitsThePanel() {
        #expect(AltilloSettings.widthRange.upperBound <= NotchLayout.panelSize.width)
    }

    /// Pointer targets never go below 28 pt, and still fit the band beside the smallest hardware notch (32 pt) and the
    /// Drawer's navigation row.
    @Test func notchTargetsKeepTheirMinimumSize() {
        #expect(DesvanHitTarget.minimum >= 28)
        #expect(DesvanHitTarget.minimum <= 32)
        #expect(NotchChrome.drawerNavigationHeight >= DesvanHitTarget.minimum)
    }

    /// Each resting ear is as wide as what it says plus air on both sides; beside a hardware notch the shape is
    /// lopsided with the camera's band still over the notch, and the island stays centred.
    @Test func restingEarsFitWhatTheySay() {
        let model = NotchModel.preview(.idleWithEars)
        for hasNotch in [true, false] {
            model.hasNotch = hasNotch
            let chrome = NotchChrome(model: model)
            #expect(chrome.face == .ears)
            let ears = model.earsArrangement
            #expect(ears.left != nil && ears.right != nil)
            #expect(chrome.leftEarWidth >= EarMetrics.contentWidth(for: ears.left!) + 2 * EarMetrics.padding - 1)
            #expect(chrome.rightEarWidth >= EarMetrics.contentWidth(for: ears.right!) + 2 * EarMetrics.padding - 1)
            let expectedWidth = chrome.clearWidth + chrome.leftEarWidth + chrome.rightEarWidth + 2 * chrome.topRadius
            #expect(abs(chrome.size.width - expectedWidth) < 0.001)
            #expect(abs(chrome.centerOffset - (hasNotch ? (chrome.rightEarWidth - chrome.leftEarWidth) / 2 : 0)) < 0.001)
        }
    }

    /// The Settings window has to fit a 13-inch MacBook Air at its "Larger Text" resolution (≈ 630 pt below the menu
    /// bar) without clipping.
    @Test func settingsWindowFitsASmallScreen() {
        #expect(SettingsWindowController.contentSize.height <= 620)
        #expect(SettingsWindowController.contentSize.width <= 600)
    }
}
