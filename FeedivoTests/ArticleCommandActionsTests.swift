import Testing
@testable import Feedivo

struct ArticleCommandActionsTests {

    @Test func linkAktionenSindNurMitGueltigemLinkVerfuegbar() {
        let actionsWithoutArticle = ArticleCommandActions(
            canPerformActions: false,
            canPerformLinkActions: false,
            toggleReadTitle: L10n.articleRowMarkRead,
            toggleStarredTitle: L10n.articleRowStarAdd,
            toggleArchivedTitle: L10n.articleArchiveCommand,
            toggleRead: {},
            toggleStarred: {},
            copyLink: {},
            openOriginal: {}
        )
        let actionsWithRelativeLink = ArticleCommandActions(
            canPerformActions: true,
            canPerformLinkActions: false,
            toggleReadTitle: L10n.articleRowMarkRead,
            toggleStarredTitle: L10n.articleRowStarAdd,
            toggleArchivedTitle: L10n.articleArchiveCommand,
            toggleRead: {},
            toggleStarred: {},
            copyLink: {},
            openOriginal: {}
        )
        let actionsWithLink = ArticleCommandActions(
            canPerformActions: true,
            canPerformLinkActions: true,
            toggleReadTitle: L10n.articleRowMarkRead,
            toggleStarredTitle: L10n.articleRowStarAdd,
            toggleArchivedTitle: L10n.articleArchiveCommand,
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
        var didRequestExport = false
        let actions = ArticleCommandActions(
            canPerformActions: true,
            canPerformLinkActions: true,
            toggleReadTitle: L10n.articleRowMarkRead,
            toggleStarredTitle: L10n.articleRowStarAdd,
            toggleArchivedTitle: L10n.articleArchiveCommand,
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
            },
            requestExport: {
                didRequestExport = true
            }
        )

        actions.copyLink()
        actions.openOriginal()
        actions.shareOriginal()
        actions.requestExport()

        #expect(didCopyLink)
        #expect(didOpenOriginal)
        #expect(didShare)
        #expect(didRequestExport)
    }

    @Test func archivAktionNutztPassendenTitel() {
        let archivedActions = ArticleCommandActions(
            canPerformActions: true,
            canPerformLinkActions: false,
            toggleReadTitle: L10n.articleRowMarkRead,
            toggleStarredTitle: L10n.articleRowStarAdd,
            toggleArchivedTitle: L10n.articleUnarchiveCommand,
            toggleRead: {},
            toggleStarred: {},
            toggleArchived: {},
            copyLink: {},
            openOriginal: {}
        )
        let unarchivedActions = ArticleCommandActions(
            canPerformActions: true,
            canPerformLinkActions: false,
            toggleReadTitle: L10n.articleRowMarkRead,
            toggleStarredTitle: L10n.articleRowStarAdd,
            toggleArchivedTitle: L10n.articleArchiveCommand,
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
