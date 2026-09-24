import AltilloCore
import Foundation
import Testing
@testable import Altillo

/// The legacy `openusage.mobile.v1` export for the old TestFlight iPhone app (PLAN §5.2, docs/uso-ia.md).
struct OpenUsageMobileExportTests {
    typealias Document = OpenUsageMobileDocument

    static let now = Date(timeIntervalSince1970: 1_790_246_297.75) // 2026-09-24T10:38:17.75Z (fractional on purpose)
    static let deviceID = "e69aee15-a3b9-4448-94a0-db20fe6e0e38"

    static func claude(problem: UsageProblem? = nil, fetchedAt: Date = now) -> ProviderUsage {
        ProviderUsage(
            id: .claude, displayName: "Claude", plan: "Max 5x",
            windows: [
                UsageWindow(id: "session", kind: .session, label: "Session", used: 0.42,
                            resetsAt: Date(timeIntervalSince1970: 1_790_262_600.4), duration: 5 * 3_600),
                UsageWindow(id: "weekly", kind: .weekly, label: "Week", used: 0.55,
                            resetsAt: Date(timeIntervalSince1970: 1_790_658_000), duration: 7 * 86_400),
                UsageWindow(id: "weekly-fable", kind: .modelWeekly, label: "Fable week", used: 0.10,
                            resetsAt: Date(timeIntervalSince1970: 1_790_657_999), duration: 7 * 86_400),
            ],
            balances: [UsageBalance(id: "extra-usage", label: "Extra usage", remaining: 12.5, used: 7.5, limit: 20,
                                    unit: "USD")],
            fetchedAt: fetchedAt, problem: problem)
    }

    static func codex() -> ProviderUsage {
        ProviderUsage(
            id: .codex, displayName: "Codex", plan: "Pro 5x",
            windows: [UsageWindow(id: "weekly", kind: .weekly, label: "Week", used: 1,
                                  resetsAt: Date(timeIntervalSince1970: 1_790_414_188), duration: 7 * 86_400)],
            balances: [
                UsageBalance(id: "credits", label: "Credits", remaining: 0, used: nil, limit: nil, unit: "credits"),
                UsageBalance(id: "limit-resets", label: "Limit resets", remaining: 1, used: nil, limit: nil, unit: "resets"),
            ],
            fetchedAt: now)
    }

    static func snapshot(_ providers: [ProviderUsage]) -> UsageSnapshot {
        UsageSnapshot(deviceID: "altillo-own-id", deviceName: "Copen mini", updatedAt: now, providers: providers)
    }

    // MARK: - Mapping

    @Test func windowsBecomeTheBridgesProgressMetrics() throws {
        let document = OpenUsageMobileExport.document(from: Self.snapshot([Self.claude()]), deviceID: Self.deviceID)
        let claude = try #require(document.providers["claude"])
        #expect(document.providerOrder == ["claude"])
        #expect(claude.status == .available)
        #expect(claude.plan == "Max 5x")

        let progress = claude.metrics.filter { $0.presentation == .progress }
        #expect(progress.map(\.id) == ["claude.session", "claude.weekly", "claude.fable"])
        #expect(progress.map(\.label) == ["Session", "Weekly", "Fable"])
        #expect(progress.map(\.used) == [42, 55, 10])
        #expect(progress.allSatisfy { $0.limit == 100 && $0.unit == Document.Unit(kind: .percent) && $0.values.isEmpty })
        #expect(progress.map(\.periodDurationMilliseconds) == [18_000_000, 604_800_000, 604_800_000])
        #expect(progress[0].resetsAt == Date(timeIntervalSince1970: 1_790_262_600)) // sub-seconds dropped
    }

    @Test func otherAndMonthlyWindowsKeepStableIDs() {
        let windows = [
            UsageWindow(id: "monthly", kind: .monthly, label: "Month", used: 0.2, resetsAt: nil, duration: nil),
            UsageWindow(id: "session-gpt-5", kind: .other, label: "GPT-5 session", used: 0.3, resetsAt: nil, duration: nil),
            UsageWindow(id: "weekly-sonnet", kind: .modelWeekly, label: "", used: 0.4, resetsAt: nil, duration: nil),
        ]
        let metrics = windows.map { OpenUsageMobileExport.metric(from: $0, providerID: "codex") }
        #expect(metrics.map(\.id) == ["codex.monthly", "codex.session-gpt-5", "codex.sonnet"])
        #expect(metrics.map(\.label) == ["Monthly", "GPT-5 session", "Sonnet"])
        #expect(metrics.allSatisfy { $0.resetsAt == nil && $0.periodDurationMilliseconds == nil && $0.isValid })
    }

    @Test func duplicateMetricIDsAreSuffixed() throws {
        var usage = Self.claude()
        usage.windows.append(UsageWindow(id: "weekly-fable-2", kind: .modelWeekly, label: "Fable week", used: 0.2,
                                         resetsAt: nil, duration: nil))
        let provider = try #require(OpenUsageMobileExport.provider(from: usage, now: Self.now))
        #expect(provider.metrics.map(\.id).contains("claude.fable-2"))
        #expect(Set(provider.metrics.map(\.id)).count == provider.metrics.count)
    }

    @Test func balancesBecomeValueMetrics() throws {
        let document = OpenUsageMobileExport.document(from: Self.snapshot([Self.claude(), Self.codex()]),
                                                      deviceID: Self.deviceID)
        let codex = try #require(document.providers["codex"])
        #expect(codex.metrics.map(\.id) == ["codex.weekly", "codex.credits", "codex.rate-limit-resets"])
        let credits = codex.metrics[1]
        #expect(credits.presentation == .values)
        #expect(credits.used == nil && credits.limit == nil && credits.unit == nil)
        #expect(credits.values == [Document.Value(number: 0, unit: Document.Unit(kind: .count, suffix: "credits"))])
        #expect(codex.metrics[2].label == "Rate Limit Resets")
        #expect(codex.metrics[2].values.first?.unit == Document.Unit(kind: .count, suffix: "resets"))

        let extra = try #require(document.providers["claude"]?.metrics.first { $0.id == "claude.extra-usage" })
        #expect(extra.values == [Document.Value(number: 12.5, unit: Document.Unit(kind: .dollars))])
    }

    @Test func balancesWithoutANumberAreSkipped() {
        let empty = UsageBalance(id: "credits", label: "Credits", remaining: nil, used: nil, limit: nil, unit: "credits")
        let negative = UsageBalance(id: "credits", label: "Credits", remaining: -1, used: nil, limit: nil, unit: "credits")
        #expect(OpenUsageMobileExport.metric(from: empty, providerID: "codex") == nil)
        #expect(OpenUsageMobileExport.metric(from: negative, providerID: "codex") == nil)
    }

    @Test func problemsSetTheStatus() throws {
        func status(_ problem: UsageProblem?, windows: Bool = true) -> Document.Provider.Status? {
            var usage = Self.claude(problem: problem)
            if !windows { usage.windows = []; usage.balances = [] }
            return OpenUsageMobileExport.provider(from: usage, now: Self.now)?.status
        }
        #expect(status(nil) == .available)
        #expect(status(.rateLimited(retryAfter: nil)) == .attention)
        #expect(status(.unreachable("offline")) == .attention)
        #expect(status(.unexpectedResponse("shape")) == .attention)
        #expect(status(.sessionExpired) == .unavailable)
        #expect(status(.accessDenied) == .unavailable)
        #expect(status(.unreachable("offline"), windows: false) == .unavailable)
        // Never set up: no card at all.
        #expect(status(.notSignedIn, windows: false) == nil)
        // Nothing to show and nothing wrong: no card either.
        #expect(status(nil, windows: false) == nil)

        let stale = Self.claude(fetchedAt: Self.now.addingTimeInterval(-3_600))
        #expect(OpenUsageMobileExport.provider(from: stale, now: Self.now)?.status == .attention)
    }

    @Test func providersThePhoneWouldRejectAreDropped() {
        let odd = ProviderUsage(id: UsageProviderID(rawValue: "open usage/x"), displayName: "Odd", plan: nil,
                                windows: Self.claude().windows, fetchedAt: Self.now)
        let document = OpenUsageMobileExport.document(from: Self.snapshot([odd, Self.codex()]), deviceID: Self.deviceID)
        #expect(document.providerOrder == ["codex"])
        #expect(throws: Never.self) { try document.validate() }
    }

    @Test func textIsTrimmedToThePhonesLimits() throws {
        var usage = Self.claude()
        usage.displayName = String(repeating: "C", count: 200)
        usage.plan = "  \u{7}Max\n "
        usage.windows[2].label = String(repeating: "m", count: 120) + " week"
        let snapshot = UsageSnapshot(deviceID: "x", deviceName: String(repeating: "D", count: 300), updatedAt: Self.now,
                                     providers: [usage])
        let document = OpenUsageMobileExport.document(from: snapshot, deviceID: Self.deviceID)
        let claude = try #require(document.providers["claude"])
        #expect(document.deviceName.count == Document.maxDeviceNameLength)
        #expect(claude.displayName.count == Document.maxTextLength)
        #expect(claude.plan == "Max")
        #expect(claude.metrics.allSatisfy { $0.label.count <= Document.maxTextLength })
        #expect(throws: Never.self) { try document.validate() }
    }

    // MARK: - Encoding

    @Test func encodingMatchesWhatThePhoneReads() throws {
        let document = OpenUsageMobileExport.document(from: Self.snapshot([Self.claude(), Self.codex()]),
                                                      deviceID: Self.deviceID)
        let json = try #require(String(data: try document.encoded(), encoding: .utf8))
        #expect(json.contains(#""schema" : "openusage.mobile.v1""#))
        #expect(json.contains(#""updatedAt" : "2026-09-24T10:38:17Z""#))
        // No fractional seconds anywhere: the phone's plain .iso8601 decoder rejects them.
        #expect(json.range(of: #"\d{2}:\d{2}:\d{2}\.\d+Z"#, options: .regularExpression) == nil)
        // Pretty-printed with sorted keys, like the bridge.
        #expect(json.hasPrefix("{\n  \"deviceID\""))
        let keys = ["deviceID", "deviceName", "providerOrder", "providers", "schema", "updatedAt"]
        let offsets = keys.map { json.range(of: "\n  \"\($0)\"")?.lowerBound }
        #expect(offsets.allSatisfy { $0 != nil })
        #expect(offsets.compactMap { $0 } == offsets.compactMap { $0 }.sorted())

        let decoded = try Document.decoder().decode(Document.self, from: Data(json.utf8))
        #expect(decoded == document)
    }

    @Test func invalidDocumentsAreNeverEncoded() {
        var document = OpenUsageMobileExport.document(from: Self.snapshot([Self.claude()]), deviceID: Self.deviceID)
        document.deviceID = "has space"
        #expect(throws: Document.ValidationError.invalidDevice) { try document.encoded() }

        document.deviceID = Self.deviceID
        document.providerOrder.append("ghost")
        #expect(throws: Document.ValidationError.invalidProviderOrder) { try document.encoded() }
    }

    @Test func providerIDPattern() {
        for valid in ["claude", "codex", "grok", "open-router", "cursor@0a1b2c3d"] {
            #expect(Document.isValidProviderID(valid), "\(valid)")
        }
        for invalid in ["", "Claude", "-claude", "claude_x", "cursor@XYZ", "a b"] {
            #expect(!Document.isValidProviderID(invalid), "\(invalid)")
        }
    }

    // MARK: - Round trip against the bridge's real file

    /// Trimmed copy of a file the OpenUsage Mobile Bridge wrote (iCloud~me~badia~ailimits/OpenUsage/Mobile/v1).
    static let bridgeSample = """
    {
      "deviceID" : "e69aee15-a3b9-4448-94a0-db20fe6e0e38",
      "deviceName" : "Copen mini",
      "providerOrder" : [ "claude", "codex" ],
      "providers" : {
        "claude" : {
          "displayName" : "Claude",
          "metrics" : [
            { "expiriesAt" : [ ], "id" : "claude.session", "label" : "Session", "limit" : 100,
              "periodDurationMilliseconds" : 18000000, "presentation" : "progress",
              "resetsAt" : "2026-09-24T15:10:00Z", "unit" : { "kind" : "percent" }, "used" : 42, "values" : [ ] },
            { "expiriesAt" : [ ], "id" : "claude.weekly", "label" : "Weekly", "limit" : 100,
              "periodDurationMilliseconds" : 604800000, "presentation" : "progress",
              "resetsAt" : "2026-09-29T05:00:00Z", "unit" : { "kind" : "percent" }, "used" : 55, "values" : [ ] },
            { "expiriesAt" : [ ], "id" : "claude.fable", "label" : "Fable", "limit" : 100,
              "periodDurationMilliseconds" : 604800000, "presentation" : "progress",
              "resetsAt" : "2026-09-29T04:59:59Z", "unit" : { "kind" : "percent" }, "used" : 10, "values" : [ ] }
          ],
          "plan" : "Max 5x", "providerID" : "claude", "refreshedAt" : "2026-09-24T10:38:17Z", "status" : "available"
        },
        "codex" : {
          "displayName" : "Codex",
          "metrics" : [
            { "expiriesAt" : [ ], "id" : "codex.weekly", "label" : "Weekly", "limit" : 100,
              "periodDurationMilliseconds" : 604800000, "presentation" : "progress",
              "resetsAt" : "2026-09-26T09:16:28Z", "unit" : { "kind" : "percent" }, "used" : 100, "values" : [ ] },
            { "expiriesAt" : [ ], "id" : "codex.credits", "label" : "Credits", "presentation" : "values",
              "values" : [ { "estimated" : false, "number" : 0, "unit" : { "kind" : "count", "suffix" : "credits" } } ] },
            { "expiriesAt" : [ "2026-10-22T20:50:32Z" ], "id" : "codex.rate-limit-resets", "label" : "Rate Limit Resets",
              "presentation" : "values",
              "values" : [ { "estimated" : false, "number" : 1, "unit" : { "kind" : "count", "suffix" : "resets" } } ] }
          ],
          "plan" : "Pro 5x", "providerID" : "codex", "refreshedAt" : "2026-09-24T10:38:17Z", "status" : "available"
        }
      },
      "schema" : "openusage.mobile.v1",
      "updatedAt" : "2026-09-24T10:38:17Z"
    }
    """

    @Test func bridgeFileDecodesAndValidates() throws {
        let sample = try Document.decoder().decode(Document.self, from: Data(Self.bridgeSample.utf8))
        try sample.validate()
        let reencoded = try Document.decoder().decode(Document.self, from: try sample.encoded())
        #expect(reencoded == sample)
    }

    @Test func altilloWritesTheSameCardsAsTheBridge() throws {
        let sample = try Document.decoder().decode(Document.self, from: Data(Self.bridgeSample.utf8))
        let mine = OpenUsageMobileExport.document(from: Self.snapshot([Self.claude(), Self.codex()]),
                                                  deviceID: Self.deviceID)
        #expect(mine.deviceID == sample.deviceID)
        #expect(mine.deviceName == sample.deviceName)
        #expect(mine.updatedAt == sample.updatedAt)
        #expect(mine.providerOrder == sample.providerOrder)
        for id in sample.providerOrder {
            let theirs = try #require(sample.providers[id])
            let ours = try #require(mine.providers[id])
            #expect(ours.displayName == theirs.displayName)
            #expect(ours.plan == theirs.plan)
            #expect(ours.status == theirs.status)
            #expect(ours.refreshedAt == theirs.refreshedAt)
            // Every metric the bridge wrote exists with the same id, label and presentation (Altillo may add more,
            // like Claude's extra usage). Expiry dates are the one thing Altillo's model doesn't carry.
            for metric in theirs.metrics {
                let match = try #require(ours.metrics.first { $0.id == metric.id }, "missing \(metric.id)")
                #expect(match.label == metric.label)
                #expect(match.presentation == metric.presentation)
                #expect(match.used == metric.used)
                #expect(match.limit == metric.limit)
                #expect(match.unit == metric.unit)
                #expect(match.periodDurationMilliseconds == metric.periodDurationMilliseconds)
                #expect(match.values.map(\.number) == metric.values.map(\.number))
                #expect(match.values.map(\.unit) == metric.values.map(\.unit))
            }
        }
    }

    // MARK: - Publisher

    @MainActor @Test func publisherIsInertWithoutTheEntitlement() throws {
        let suite = "OpenUsageMobileExportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let publisher = OpenUsageMobilePublisher(defaults: defaults, debounce: .milliseconds(1))
        // Test and dev builds are never signed with the iCloud entitlement.
        #expect(!OpenUsageMobilePublisher.hasContainerEntitlement)
        #expect(publisher.isSettingOn)
        #expect(!publisher.isEnabled)
        defaults.set(false, forKey: OpenUsageMobilePublisher.enabledKey)
        #expect(!publisher.isSettingOn)
        publisher.publish(Self.snapshot([Self.claude()])) // no-op, must not crash
    }

    @MainActor @Test func deviceIDIsStable() throws {
        let suite = "OpenUsageMobileExportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = OpenUsageMobilePublisher.resolveDeviceID(defaults: defaults)
        #expect(Document.isValidIdentifier(first))
        #expect(OpenUsageMobilePublisher.resolveDeviceID(defaults: defaults) == first)
        // Takes over the bridge's slot when the bridge ran on this Mac.
        if let bridge = OpenUsageMobilePublisher.bridgeDeviceID() { #expect(first == bridge) }
    }
}
