import XCTest
@testable import Feedivo

final class ReaderDisplayModeTests: XCTestCase {
    func testDefaultModeIsNative() {
        XCTAssertEqual(ReaderDisplayMode.defaultMode, .native)
    }

    func testResolvedFallsBackToNativeForUnknownRawValue() {
        XCTAssertEqual(ReaderDisplayMode.resolved(from: "unknown"), .native)
    }

    func testResolvedReturnsWebForWebRawValue() {
        XCTAssertEqual(ReaderDisplayMode.resolved(from: ReaderDisplayMode.web.rawValue), .web)
    }

    func testAllCasesOnlyOfferFeedReaderAndOriginalWebsite() {
        XCTAssertEqual(ReaderDisplayMode.allCases, [.native, .web])
    }

    func testResolvedFallsBackToNativeForRemovedReadabilityRawValue() {
        XCTAssertEqual(ReaderDisplayMode.resolved(from: "readability"), .native)
    }
}
