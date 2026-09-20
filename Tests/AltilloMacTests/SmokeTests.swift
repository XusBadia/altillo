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
}
