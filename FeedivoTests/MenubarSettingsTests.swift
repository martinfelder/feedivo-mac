import Testing
@testable import Feedivo

struct MenubarSettingsTests {

    @Test func isEnabledDefaultIstAus() {
        #expect(MenubarSettings.defaultIsEnabled == false)
    }

    @Test func articleCountDefaultIstFuenf() {
        #expect(MenubarSettings.defaultArticleCount == 5)
    }

    @Test func resolvedArticleCountFaengtUngueltigeWerteAb() {
        #expect(MenubarSettings.resolvedArticleCount(from: 3) == 3)
        #expect(MenubarSettings.resolvedArticleCount(from: 10) == 10)
        #expect(MenubarSettings.resolvedArticleCount(from: 2) == MenubarSettings.defaultArticleCount)
        #expect(MenubarSettings.resolvedArticleCount(from: 11) == MenubarSettings.defaultArticleCount)
    }

    @Test func hidesDockIconDefaultIstAus() {
        #expect(MenubarSettings.defaultHidesDockIcon == false)
    }

    @Test func articleClickBehaviorResolvedFaelltBeiUnbekanntemRohwertAufDefaultZurueck() {
        #expect(MenubarArticleClickBehavior.resolved(from: "inFeedivo") == .inFeedivo)
        #expect(MenubarArticleClickBehavior.resolved(from: "inBrowser") == .inBrowser)
        #expect(MenubarArticleClickBehavior.resolved(from: "unknown") == MenubarArticleClickBehavior.defaultBehavior)
    }

    @Test func articleClickBehaviorDefaultIstInFeedivo() {
        #expect(MenubarArticleClickBehavior.defaultBehavior == .inFeedivo)
    }
}
