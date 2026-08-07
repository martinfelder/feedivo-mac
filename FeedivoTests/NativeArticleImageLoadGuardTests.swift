import Testing
@testable import Feedivo

@Suite("NativeArticleListImageLoadGuard")
struct NativeArticleListImageLoadGuardTests {
    @Test func erlaubtAnwendungBeiGleichemToken() {
        #expect(NativeArticleListImageLoadGuard.shouldApplyLoadedImage(requestedToken: 3, currentToken: 3))
    }

    @Test func verwirftAnwendungBeiVeraltetemToken() {
        #expect(!NativeArticleListImageLoadGuard.shouldApplyLoadedImage(requestedToken: 2, currentToken: 3))
    }
}
