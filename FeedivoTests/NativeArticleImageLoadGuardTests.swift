import Testing
@testable import Feedivo

@Suite("NativeArticleImageLoadGuard")
struct NativeArticleImageLoadGuardTests {
    @Test func erlaubtAnwendungBeiGleichemToken() {
        #expect(NativeArticleImageLoadGuard.shouldApplyLoadedImage(requestedToken: 3, currentToken: 3))
    }

    @Test func verwirftAnwendungBeiVeraltetemToken() {
        #expect(!NativeArticleImageLoadGuard.shouldApplyLoadedImage(requestedToken: 2, currentToken: 3))
    }
}
