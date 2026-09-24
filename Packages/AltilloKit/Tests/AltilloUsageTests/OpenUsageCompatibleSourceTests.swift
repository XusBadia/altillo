import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

struct OpenUsageCompatibleSourceTests {
    @Test func skipsNativeProvidersByDefault() async {
        let transport = FakeTransport([.response(status: 200, body: Fixtures.openUsageLimits)])
        let providers = await OpenUsageCompatibleSource(transport: transport).fetch(now: referenceNow)
        #expect(providers.map(\.id.rawValue) == ["cursor", "grok"])
        #expect(transport.requests.first?.timeoutInterval == 1)
        #expect(transport.requests.first?.url == OpenUsageCompatibleSource.defaultURL)
    }

    @Test func mapsResources() throws {
        let providers = try #require(OpenUsageLimitsMapper.map(Data(Fixtures.openUsageLimits.utf8), excluding: [],
                                                               now: referenceNow))
        let claude = try #require(providers.first { $0.id == .claude })
        #expect(claude.plan == "Max 5x")
        #expect(claude.fetchedAt == iso("2026-09-24T10:36:22.558Z"))
        #expect(claude.windows.map(\.id) == ["session", "weekly", "weekly-fable"])
        #expect(claude.windows.map(\.used) == [0.42, 0.55, 0.1])
        #expect(claude.windows[2].label == "Fable week")
        #expect(claude.windows[0].duration == 18000)
        #expect(claude.balances == [UsageBalance(id: "rateLimitResets", label: "Limit resets", remaining: 1, used: nil,
                                                 limit: nil, unit: "resets")])

        let cursor = try #require(providers.first { $0.id.rawValue == "cursor" })
        #expect(cursor.problem == .unreachable("Not signed in"))
        #expect(cursor.windows.map(\.used) == [0.625]) // used / limit
        #expect(cursor.windows[0].kind == .other)
        // A consumption without a limit is a spend figure, kept as a balance.
        #expect(cursor.balances == [UsageBalance(id: "onDemand", label: "On Demand", remaining: nil, used: 3,
                                                 limit: nil, unit: "USD")])
        let grok = try #require(providers.first { $0.id.rawValue == "grok" })
        #expect(grok.displayName == "Grok")
        #expect(grok.weekly?.used == 0)
    }

    @Test func rejectsOtherSchemas() {
        #expect(OpenUsageLimitsMapper.map(Data(#"{"schema":"other","providers":{}}"#.utf8), excluding: [],
                                          now: referenceNow) == nil)
    }

    @Test func unavailableWhenNothingAnswers() async {
        let source = OpenUsageCompatibleSource(transport: FakeTransport([.failure(.cannotConnectToHost)]))
        #expect(await source.fetch(now: referenceNow).isEmpty)
        let wrong = OpenUsageCompatibleSource(transport: FakeTransport([.response(status: 404, body: "")]))
        #expect(await !wrong.isAvailable())
    }

    /// Real loopback socket nobody listens on: must give up fast.
    @Test func refusedConnectionIsCheap() async {
        let source = OpenUsageCompatibleSource(url: URL(string: "http://127.0.0.1:9/v1/limits")!)
        let started = Date()
        #expect(await source.fetch().isEmpty)
        #expect(Date().timeIntervalSince(started) < 1.5)
    }
}
