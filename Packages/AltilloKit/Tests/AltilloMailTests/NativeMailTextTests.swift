import Foundation
import Testing
@testable import AltilloMail

struct NativeMailTextTests {
    @Test func hostileHTMLIsOnlyTextAndDropsActiveAndRemoteContent() {
        let html = """
        <p>Hello &amp; welcome</p><script>fetch('https://tracker.invalid')</script>
        <style>body{background:url(https://tracker.invalid/pixel)}</style>
        <img src="https://tracker.invalid/pixel" onerror="run()"><iframe src="https://tracker.invalid">hidden</iframe>
        <form action="https://tracker.invalid">secret form</form><p>Your code: <b>482913</b></p>
        """
        let text = NativeMailText.plainText(fromHTML: html)
        // Consecutive block boundaries and stripped markup retain one paragraph separator.
        #expect(text == "Hello & welcome\n\nYour code: 482913")
        #expect(!text.contains("tracker"))
        #expect(!text.contains("secret"))
    }

    @Test func quotedTagsCommentsAndEscapedMarkupCannotBecomeExecutable() {
        #expect(NativeMailText.plainText(fromHTML: "<!-- hidden --><p title='>'>Visible</p>&lt;script&gt;literal&lt;/script&gt;") == "Visible\n<script>literal</script>")
        #expect(NativeMailText.plainText(fromHTML: "Visible<script>unterminated") == "Visible")
        #expect(NativeMailText.plainText(fromHTML: "<svg><script>secret</script>secret</svg><p>OK</p>") == "OK")
    }

    @Test func byteLimitsPreserveUnicodeScalarBoundariesAndRejectInvalidEntities() {
        #expect(NativeMailText.bounded("é🙂x", utf8Limit: 5) == "é")
        #expect(NativeMailText.plainText(fromHTML: "<p>é🙂x</p>", limit: 6) == "é🙂")
        #expect(NativeMailText.plainText(fromHTML: "test", limit: 0).isEmpty)
        #expect(NativeMailText.decodeEntities("&#x1F642; &#233; &#0; &#xD800;") == "🙂 é  ")
        #expect(NativeMailText.decodeEntities("Verificaci&oacute;n &unknown; &#oops;") == "Verificación &unknown; &#oops;")
    }

    @Test func encodedHeadersSupportUTF8AndLegacyQuotedPrintable() {
        #expect(NativeMailText.decodeHeader("=?UTF-8?B?VmVyaWZpY2FjacOzbg==?=") == "Verificación")
        #expect(NativeMailText.decodeHeader("=?ISO-8859-1?Q?C=F3digo_de_acceso?=") == "Código de acceso")
        #expect(NativeMailText.decodeHeader("=?UTF-8?Q?Hello?= \r\n =?UTF-8?Q?_world?=") == "Hello world")
    }
}
