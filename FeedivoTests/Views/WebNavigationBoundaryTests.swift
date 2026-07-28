import Testing
@testable import Feedivo

struct WebNavigationBoundaryTests {

    @Test func canGoBackIstFalseAnDerArtikelGrenze() {
        #expect(WebNavigationBoundary.canGoBack(webViewCanGoBack: true, isAtBoundary: true) == false)
    }

    @Test func canGoBackIstFalseOhneWebViewVerlauf() {
        #expect(WebNavigationBoundary.canGoBack(webViewCanGoBack: false, isAtBoundary: false) == false)
    }

    @Test func canGoBackIstTrueNachInPageNavigation() {
        #expect(WebNavigationBoundary.canGoBack(webViewCanGoBack: true, isAtBoundary: false) == true)
    }
}
