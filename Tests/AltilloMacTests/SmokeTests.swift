import Testing
@testable import Altillo

@MainActor
struct SmokeTests {
    @Test func designScenariosCoverEveryState() {
        let states = Set(DesignScenario.allCases.map(\.state))
        #expect(states.count == 5)
    }
}
