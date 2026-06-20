import Testing
@testable import Feedivo

struct ArticleCommandActionsTests {

    @Test func linkAktionenSindNurMitGueltigemLinkVerfuegbar() {
        let actionsWithoutArticle = ArticleCommandActions(
            selectedArticle: nil,
            toggleRead: {},
            toggleStarred: {},
            copyLink: {},
            openOriginal: {}
        )
        let actionsWithRelativeLink = ArticleCommandActions(
            selectedArticle: Article(title: "Relativ", link: "/artikel"),
            toggleRead: {},
            toggleStarred: {},
            copyLink: {},
            openOriginal: {}
        )
        let actionsWithLink = ArticleCommandActions(
            selectedArticle: Article(title: "Original", link: "https://example.com/article"),
            toggleRead: {},
            toggleStarred: {},
            copyLink: {},
            openOriginal: {}
        )

        #expect(!actionsWithoutArticle.canPerformLinkActions)
        #expect(!actionsWithRelativeLink.canPerformLinkActions)
        #expect(actionsWithLink.canPerformLinkActions)
    }

    @Test func linkAktionenFuehrenCallbacksAus() {
        var didCopyLink = false
        var didOpenOriginal = false
        let actions = ArticleCommandActions(
            selectedArticle: Article(title: "Original", link: "https://example.com/article"),
            toggleRead: {},
            toggleStarred: {},
            copyLink: {
                didCopyLink = true
            },
            openOriginal: {
                didOpenOriginal = true
            }
        )

        actions.copyLink()
        actions.openOriginal()

        #expect(didCopyLink)
        #expect(didOpenOriginal)
    }
}
