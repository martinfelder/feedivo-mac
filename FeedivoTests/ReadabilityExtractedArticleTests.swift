import XCTest
@testable import Feedivo

final class ReadabilityExtractedArticleTests: XCTestCase {
    func testDecodedArticleUsesContentHTMLForReaderRendering() throws {
        let json = """
        {
          "title": "Ein langer Artikel",
          "byline": "Martin",
          "dir": null,
          "content": "<article><p>Der extrahierte Volltext.</p></article>",
          "textContent": "Der extrahierte Volltext.",
          "length": 27,
          "excerpt": "Der extrahierte Volltext.",
          "siteName": "Feedivo News"
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let article = try JSONDecoder().decode(ReadabilityExtractedArticle.self, from: data)

        XCTAssertEqual(article.title, "Ein langer Artikel")
        XCTAssertEqual(article.normalizedContentHTML, "<article><p>Der extrahierte Volltext.</p></article>")
    }

    func testNormalizedContentHTMLReturnsNilForBlankContent() {
        let article = ReadabilityExtractedArticle(
            title: "Leer",
            byline: nil,
            dir: nil,
            content: "   ",
            textContent: "   ",
            length: 0,
            excerpt: nil,
            siteName: nil
        )

        XCTAssertNil(article.normalizedContentHTML)
    }
}
