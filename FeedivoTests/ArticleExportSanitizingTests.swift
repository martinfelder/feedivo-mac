import Foundation
import Testing
@testable import Feedivo

struct ArticleExportSanitizingTests {
    @Test func escapedHTMLEscaptKaufmannsUndUndSpitzklammernAberKeineAnfuehrungszeichen() {
        let result = ArticleExportSanitizing.escapedHTML(#"Swift & "RSS" <Reader>"#)

        #expect(result == #"Swift &amp; "RSS" &lt;Reader&gt;"#)
    }

    @Test func escapedHTMLAttributeEscaptZusaetzlichAnfuehrungszeichenUndApostroph() {
        let result = ArticleExportSanitizing.escapedHTMLAttribute(#""quoted" & 'single'"#)

        #expect(result == "&quot;quoted&quot; &amp; &#39;single&#39;")
    }

    @Test func isSafeLinkTargetAkzeptiertHttpHttpsUndMailtoUnabhaengigVonGrossKleinschreibung() {
        #expect(ArticleExportSanitizing.isSafeLinkTarget("https://example.com"))
        #expect(ArticleExportSanitizing.isSafeLinkTarget("HTTP://example.com"))
        #expect(ArticleExportSanitizing.isSafeLinkTarget("mailto:test@example.com"))
    }

    @Test func isSafeLinkTargetLehntGefaehrlicheSchemataUndUngueltigeEingabenAb() {
        #expect(!ArticleExportSanitizing.isSafeLinkTarget("javascript:alert(1)"))
        #expect(!ArticleExportSanitizing.isSafeLinkTarget("data:text/html,alert(1)"))
        #expect(!ArticleExportSanitizing.isSafeLinkTarget("file:///etc/passwd"))
        #expect(!ArticleExportSanitizing.isSafeLinkTarget(""))
    }

    @Test func publishedDateFormatterFormatiertAlsISO8601MitZeitzone() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let result = ArticleExportSanitizing.publishedDateFormatter.string(from: date)

        #expect(result == "2023-11-14T22:13:20Z")
    }
}
