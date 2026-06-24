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
        var didShare = false
        let actions = ArticleCommandActions(
            selectedArticle: Article(title: "Original", link: "https://example.com/article"),
            toggleRead: {},
            toggleStarred: {},
            copyLink: {
                didCopyLink = true
            },
            openOriginal: {
                didOpenOriginal = true
            },
            shareOriginal: {
                didShare = true
            }
        )

        actions.copyLink()
        actions.openOriginal()
        actions.shareOriginal()

        #expect(didCopyLink)
        #expect(didOpenOriginal)
        #expect(didShare)
    }

    @Test func archivAktionNutztPassendenTitel() {
        let archivedActions = ArticleCommandActions(
            selectedArticle: Article(title: "Archiv", isArchived: true),
            toggleRead: {},
            toggleStarred: {},
            toggleArchived: {},
            copyLink: {},
            openOriginal: {}
        )
        let unarchivedActions = ArticleCommandActions(
            selectedArticle: Article(title: "Artikel", isArchived: false),
            toggleRead: {},
            toggleStarred: {},
            toggleArchived: {},
            copyLink: {},
            openOriginal: {}
        )

        #expect(archivedActions.toggleArchivedTitle == L10n.articleUnarchiveCommand)
        #expect(unarchivedActions.toggleArchivedTitle == L10n.articleArchiveCommand)
    }
}
