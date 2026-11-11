import Foundation
import Testing
@testable import AltilloDesign

struct BrowserConfirmationPageTests {
    @Test func inlinesTheOfficialIconWithoutNetworkAssets() throws {
        let source = BrowserConfirmationPage.iconSource
        #expect(source.hasPrefix("data:image/png;base64,"))
        let data = try #require(Data(base64Encoded: String(source.dropFirst("data:image/png;base64,".count))))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let page = BrowserConfirmationPage.html(language: "en", state: "connected", provider: "Claude",
                                                title: "Account connected", detail: "Done", hint: "")
        #expect(page.contains(#"<img class="icon" src="data:image/png;base64,"#))
        #expect(!page.contains("http://") && !page.contains("https://"))
    }

    @Test func escapesEveryInterpolatedValue() {
        let page = BrowserConfirmationPage.html(language: "en\"", state: "failed", provider: "<b>P</b>",
                                                title: "A & B", detail: "'x'", hint: "h", action: "<go>")
        #expect(!page.contains("<b>P</b>") && !page.contains("<go>"))
        #expect(page.contains("&lt;b&gt;P&lt;/b&gt;") && page.contains("A &amp; B") && page.contains("&#39;x&#39;"))
        #expect(page.contains(#"lang="en&quot;""#))
    }
}
