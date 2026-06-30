import XCTest
@testable import Feedivo

final class ReadabilityScriptProviderTests: XCTestCase {
    func testExtractionScriptCombinesReadabilitySourceAndJSONResult() {
        let script = ReadabilityScriptProvider.extractionScript(readabilitySource: "function Readability() {}")

        XCTAssertTrue(script.contains("function Readability() {}"))
        XCTAssertTrue(script.contains("new Readability(document.cloneNode(true)).parse()"))
        XCTAssertTrue(script.contains("JSON.stringify(article)"))
    }
}
