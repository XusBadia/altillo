import Foundation
import Testing
@testable import AltilloUsage

struct UsageParsingTests {
    @Test(arguments: [
        ("2026-09-24T15:10:00Z", 0.0),
        ("2026-09-24T15:10:00.720Z", 0.720),
        ("2026-09-24T15:10:00.720317+00:00", 0.720317),
        ("2026-09-24T17:10:00.5+02:00", 0.5),
        ("2026-09-24T17:10:00+0200", 0.0),
    ])
    func parsesISODatesWithAnyFraction(text: String, fraction: Double) throws {
        let base = Date(timeIntervalSince1970: 1_790_262_600) // 2026-09-24T15:10:00Z
        let date = try #require(UsageParsing.date(text))
        #expect(abs(date.timeIntervalSince(base) - fraction) < 0.000_01)
    }

    @Test func parsesEpochSecondsAndMilliseconds() {
        #expect(UsageParsing.date(1_790_262_600) == Date(timeIntervalSince1970: 1_790_262_600))
        #expect(UsageParsing.date(1_790_262_600_500.0) == Date(timeIntervalSince1970: 1_790_262_600.5))
        #expect(UsageParsing.date("1790262600") == Date(timeIntervalSince1970: 1_790_262_600))
        #expect(UsageParsing.date(nil) == nil)
        #expect(UsageParsing.date(NSNull()) == nil)
        #expect(UsageParsing.date("soon") == nil)
    }

    @Test func numbersIgnoreBooleans() {
        #expect(UsageParsing.number(NSNumber(value: true)) == nil)
        #expect(UsageParsing.number("42.75") == 42.75)
        #expect(UsageParsing.number(7) == 7)
    }

    @Test func decodesHexWrappedJSON() {
        let json = #"{"claudeAiOauth":{"accessToken":"x"}}"#
        #expect(UsageParsing.objectWithHexFallback(hex(json)) != nil)
        #expect(UsageParsing.objectWithHexFallback("0x" + hex(json)) != nil)
        #expect(UsageParsing.objectWithHexFallback("not hex") == nil)
        #expect(UsageParsing.hexDecodedString("abc") == nil)
    }

    @Test func retryAfterSecondsDatesAndGarbage() {
        #expect(UsageParsing.retryAfter("120", now: referenceNow) == referenceNow.addingTimeInterval(120))
        #expect(UsageParsing.retryAfter("Thu, 24 Sep 2026 10:10:00 GMT", now: referenceNow)
            == referenceNow.addingTimeInterval(600))
        // A date in the past means "now", never earlier.
        #expect(UsageParsing.retryAfter("Thu, 24 Sep 2026 09:00:00 GMT", now: referenceNow) == referenceNow)
        #expect(UsageParsing.retryAfter("later", now: referenceNow) == nil)
        #expect(UsageParsing.retryAfter(nil, now: referenceNow) == nil)
    }

    @Test func titleCaseAndSlug() {
        #expect(UsageParsing.titleCased("max") == "Max")
        #expect(UsageParsing.titleCased("team_plan") == "Team Plan")
        #expect(UsageParsing.titleCased("rateLimitResets") == "Rate Limit Resets")
        #expect(UsageParsing.slug("GPT-5.3-Codex-Spark") == "gpt-5-3-codex-spark")
        #expect(UsageParsing.slug("Fable") == "fable")
    }
}
