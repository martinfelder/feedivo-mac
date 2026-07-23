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

    // Root-Cause-Fund (Nutzer-Report 2026-07-23): ohne Equatable-Konformität
    // publiziert `ContentView` bei jedem body-Durchlauf einen als "geändert"
    // erkannten `articleCommandActions`-Wert über `.focusedValue(...)`, auch
    // wenn sich inhaltlich nichts geändert hat — Ursache der SwiftUI-Warnung
    // "FocusedValue update tried to update multiple times per frame".
    @Test func gleicheDatenfelderSindGleichTrotzUnterschiedlicherClosures() {
        let lhs = ArticleCommandActions(
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
        let rhs = ArticleCommandActions(
            canPerformActions: true,
            canPerformLinkActions: true,
            toggleReadTitle: L10n.articleRowMarkRead,
            toggleStarredTitle: L10n.articleRowStarAdd,
            toggleArchivedTitle: L10n.articleArchiveCommand,
            toggleRead: { print("anderer Rueckruf") },
            toggleStarred: {},
            copyLink: {},
            openOriginal: {}
        )

        #expect(lhs == rhs)
    }

    @Test func unterschiedlichesCanPerformActionsMachtWerteUngleich() {
        let lhs = ArticleCommandActions(
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
        let rhs = ArticleCommandActions(
            canPerformActions: false,
            canPerformLinkActions: true,
            toggleReadTitle: L10n.articleRowMarkRead,
            toggleStarredTitle: L10n.articleRowStarAdd,
            toggleArchivedTitle: L10n.articleArchiveCommand,
            toggleRead: {},
            toggleStarred: {},
            copyLink: {},
            openOriginal: {}
        )

        #expect(lhs != rhs)
    }
}
