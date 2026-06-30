import XCTest
@testable import Feedivo

final class ReadabilityFailureNoticeTests: XCTestCase {
    func testNoticeUsesProviderRespectMessageForExtractionFailures() {
        let notice = ReadabilityFailureNotice.make(for: ReadabilityExtractionError.emptyResult)

        XCTAssertEqual(notice.titleKey, "reader.readability.failed")
        XCTAssertEqual(notice.detailKey, "reader.readability.providerBlocked.detail")
    }
}
