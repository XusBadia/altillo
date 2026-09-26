import Testing
@testable import Altillo

@MainActor
struct UXWelcomeTests {
    @Test func aiToolsRemainsCurrentUntilLeavingAfterEmptySearch() {
        let empty = OnboardingDetection(hasChecked: true, providersFound: 0, agentsFound: 0)
        let context = OnboardingContext(modules: [.shelf, .usage, .agents], detection: empty)

        let visible = OnboardingLogic.steps(for: context, keeping: .aiTools)
        #expect(visible == [.hello, .preset, .aiTools, .tricks, .done])
        #expect(OnboardingText.position(of: .aiTools, in: visible) == "Step 3 of 5")
        #expect(OnboardingLogic.step(after: .aiTools, in: visible) == .tricks)

        let afterLeaving = OnboardingLogic.steps(for: context, keeping: .tricks)
        #expect(afterLeaving == [.hello, .preset, .tricks, .done])
    }

    @Test func detectionWithResultsDoesNotDuplicateAITools() {
        let found = OnboardingDetection(hasChecked: true, providersFound: 1, agentsFound: 0)
        let context = OnboardingContext(modules: [.shelf, .usage], detection: found)
        #expect(OnboardingLogic.steps(for: context, keeping: .aiTools).filter { $0 == .aiTools }.count == 1)
    }
}
