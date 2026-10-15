import Testing
@testable import AltilloHome

@Suite struct HomeEntityIDTests {
    @Test func roundTripsRawValue() {
        let id = HomeEntityID(provider: "ha", serverID: "A1", localID: "light.salon")
        #expect(id.rawValue == "ha:A1:light.salon")
        #expect(HomeEntityID(rawValue: id.rawValue) == id)
        #expect(HomeEntityID(rawValue: "ha:A1") == nil)
    }
}
