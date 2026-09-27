import Foundation
import Testing
@testable import Altillo

/// How a text slip is recognised as a link or a colour, from its text alone.
@MainActor
struct ClipboardSlipTests {
    // MARK: - Links

    @Test func aWebAddressSplitsIntoSiteAndRest() throws {
        let link = try #require(ClipboardLink("https://www.GitHub.com/xusbadia/altillo/pull/128?tab=files#diff"))
        #expect(link.host == "github.com")
        #expect(link.rest == "/xusbadia/altillo/pull/128?tab=files#diff")
        #expect(link.url.absoluteString == "https://www.GitHub.com/xusbadia/altillo/pull/128?tab=files#diff")
    }

    @Test func aBareSiteHasNoRest() throws {
        let link = try #require(ClipboardLink("  http://example.com/\n"))
        #expect(link.host == "example.com")
        #expect(link.rest.isEmpty)
        #expect(try #require(ClipboardLink("https://example.com")).rest.isEmpty)
    }

    @Test func aLinkKeepsItsPortAndReadsEscapes() throws {
        let link = try #require(ClipboardLink("http://localhost:8080/caf%C3%A9%20menu"))
        #expect(link.host == "localhost:8080")
        #expect(link.rest == "/café menu")
    }

    @Test func aLinkNeverShowsTheCredentialsInIt() throws {
        let link = try #require(ClipboardLink("https://user:hunter2@example.com/private"))
        #expect(link.host == "example.com")
        #expect(link.rest == "/private")
        #expect(!link.host.contains("hunter2") && !link.rest.contains("hunter2"))
    }

    // MARK: - The filter

    @Test func theFilterShowsOneKindPinsFirstAndCombinesWithSearch() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let image = ClipboardImage(hash: "ab", width: 10, height: 10, byteCount: 10)
        var history = ClipboardHistory()
        history.record("foo bar", at: now)
        history.record(.files([ClipboardFile(path: "/tmp/foo.txt")]), at: now)
        let pinned = history.record(.image(image), at: now)
        history.record("baz", at: now)
        history.record(.image(ClipboardImage(hash: "cd", width: 5, height: 5, byteCount: 5)), at: now)
        history.togglePin(pinned.id)

        let images = history.matching("", kind: .image)
        #expect(images.map(\.image?.hash) == ["ab", "cd"], "only images, the pinned one first")
        #expect(history.matching("foo", kind: .text).map(\.text) == ["foo bar"], "search and filter together")
        #expect(history.matching("foo", kind: .files).map(\.text) == ["foo.txt"])
        #expect(history.matching("foo").count == 2, "no filter: every kind")
    }

    @Test func onlyWebAddressesAreLinks() {
        #expect(ClipboardLink("file:///Users/me/notes.txt") == nil)
        #expect(ClipboardLink("mailto:me@example.com") == nil)
        #expect(ClipboardLink("example.com") == nil)
        #expect(ClipboardLink("https://") == nil)
        #expect(ClipboardLink("see https://example.com") == nil)
        #expect(ClipboardLink("https://example.com\nhttps://example.org") == nil)
        #expect(ClipboardLink("") == nil)
        #expect(ClipboardLink("https://example.com/" + String(repeating: "a", count: 5_000)) == nil)
    }

    @Test func onlyTextSlipsAreLinksOrColours() {
        let file = ClipboardItem(content: .files([ClipboardFile(path: "/tmp/https:")]))
        #expect(file.link == nil)
        #expect(file.color == nil)
        #expect(ClipboardItem(text: "https://example.com").link?.host == "example.com")
        #expect(ClipboardItem(text: "#fff").color == ClipboardColor(red: 1, green: 1, blue: 1))
    }

    // MARK: - Colours

    @Test func hexCodesInEveryLength() {
        #expect(ClipboardColor("#FF8800") == ClipboardColor(red: 1, green: 136.0 / 255, blue: 0))
        #expect(ClipboardColor("#f80") == ClipboardColor(red: 1, green: 136.0 / 255, blue: 0))
        #expect(ClipboardColor("#f808") == ClipboardColor(red: 1, green: 136.0 / 255, blue: 0, alpha: 136.0 / 255))
        #expect(ClipboardColor(" #000000FF\n") == ClipboardColor(red: 0, green: 0, blue: 0, alpha: 1))
        #expect(ClipboardColor("#1E191480") == ClipboardColor(red: 30.0 / 255, green: 25.0 / 255, blue: 20.0 / 255,
                                                              alpha: 128.0 / 255))
    }

    @Test func hexNeedsItsHashAndRightLength() {
        #expect(ClipboardColor("FF8800") == nil)
        #expect(ClipboardColor("#FF88") != nil)
        #expect(ClipboardColor("#FF880") == nil)
        #expect(ClipboardColor("#GG8800") == nil)
        #expect(ClipboardColor("#") == nil)
        #expect(ClipboardColor("#FF8800 and more") == nil)
        #expect(ClipboardColor("# FF8800") == nil)
    }

    @Test func rgbFunctions() {
        #expect(ClipboardColor("rgb(255, 136, 0)") == ClipboardColor(red: 1, green: 136.0 / 255, blue: 0))
        #expect(ClipboardColor("RGBA(0,0,0,0.5)") == ClipboardColor(red: 0, green: 0, blue: 0, alpha: 0.5))
        #expect(ClipboardColor("rgb(255 0 0 / 50%)") == ClipboardColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        #expect(ClipboardColor("rgb(100%, 50%, 0%)") == ClipboardColor(red: 1, green: 0.5, blue: 0))
    }

    @Test func rgbOutOfRangeOrMalformedIsNotAColour() {
        #expect(ClipboardColor("rgb(256, 0, 0)") == nil)
        #expect(ClipboardColor("rgb(-1, 0, 0)") == nil)
        #expect(ClipboardColor("rgba(0, 0, 0, 2)") == nil)
        #expect(ClipboardColor("rgb(0, 0)") == nil)
        #expect(ClipboardColor("rgb(0, 0, 0, 0, 0)") == nil)
        #expect(ClipboardColor("rgb(0, 0, 0") == nil)
        #expect(ClipboardColor("rgb(red, 0, 0)") == nil)
        #expect(ClipboardColor("rgb(nan, 0, 0)") == nil)
        #expect(ClipboardColor("hsl(0, 100%, 50%)") == nil)
        #expect(ClipboardColor("orange") == nil)
    }
}
