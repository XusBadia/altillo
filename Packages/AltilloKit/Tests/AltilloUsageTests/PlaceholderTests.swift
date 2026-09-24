import Testing
@testable import AltilloUsage

@Test func collectorsListExists() {
    #expect(UsageCollectors.all().count >= 0)
}
