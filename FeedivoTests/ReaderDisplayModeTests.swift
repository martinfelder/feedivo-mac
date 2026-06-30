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

    func testAllCasesIncludeReadabilityModeBetweenNativeAndWeb() {
        XCTAssertEqual(ReaderDisplayMode.allCases, [.native, .readability, .web])
    }

    func testResolvedReturnsReadabilityForReadabilityRawValue() {
        XCTAssertEqual(ReaderDisplayMode.resolved(from: ReaderDisplayMode.readability.rawValue), .readability)
    }

    func testReadabilityLoadStartsWhenModeChangesToReadabilityForUnloadedURL() {
        let url = URL(string: "https://example.com/article")!

        XCTAssertTrue(ReadabilityLoadDecision.shouldStartExtraction(
            mode: .readability,
            originalURL: url,
            requestedURL: nil,
            loadedURL: nil,
            isInProgress: false
        ))
    }

    func testReadabilityLoadDoesNotStartForOtherModesOrExistingLoads() {
        let url = URL(string: "https://example.com/article")!

        XCTAssertFalse(ReadabilityLoadDecision.shouldStartExtraction(
            mode: .native,
            originalURL: url,
            requestedURL: nil,
            loadedURL: nil,
            isInProgress: false
        ))
        XCTAssertFalse(ReadabilityLoadDecision.shouldStartExtraction(
            mode: .readability,
            originalURL: url,
            requestedURL: url,
            loadedURL: nil,
            isInProgress: true
        ))
        XCTAssertFalse(ReadabilityLoadDecision.shouldStartExtraction(
            mode: .readability,
            originalURL: url,
            requestedURL: nil,
            loadedURL: url,
            isInProgress: false
        ))
    }
}
