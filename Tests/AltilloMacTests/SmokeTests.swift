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
                #expect(chrome.size.height <= NotchLayout.panelSize.height)
                #expect(chrome.size.height > chrome.contentHeight + chrome.bandHeight + NotchChrome.drawerHeight)
            }
        }
    }
}
