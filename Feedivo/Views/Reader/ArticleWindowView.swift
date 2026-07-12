import SwiftUI

struct ArticleWindowRequest: Codable, Hashable, Identifiable {
    let articleID: UUID

    var id: UUID {
        articleID
    }
}

struct ArticleWindowView: View {
    @Environment(\.feedivoDatabase) private var database

    let request: ArticleWindowRequest

    @State private var selectedArticleID: String
    @State private var articleIDs: [String] = []
    @State private var articleSnapshot: ArticleReaderSnapshot?
    @State private var articleExportRequest: ArticleExportRequest?
    @State private var loadErrorMessage: String?

    init(request: ArticleWindowRequest) {
        self.request = request
        self._selectedArticleID = State(initialValue: request.articleID.uuidString)
    }

    private var selectedArticleIndex: Int? {
        articleIDs.firstIndex(of: selectedArticleID)
    }

    private var previousArticleID: String? {
        guard let selectedArticleIndex, selectedArticleIndex > articleIDs.startIndex else {
            return nil
        }

        return articleIDs[articleIDs.index(before: selectedArticleIndex)]
    }

    private var nextArticleID: String? {
        guard let selectedArticleIndex else {
            return nil
        }

        let nextIndex = articleIDs.index(after: selectedArticleIndex)
        guard nextIndex < articleIDs.endIndex else {
            return nil
        }

        return articleIDs[nextIndex]
    }

    var body: some View {
        Group {
            if let database {
                SQLiteReaderView(
                    articleID: selectedArticleID,
                    canSelectPreviousArticle: previousArticleID != nil,
                    canSelectNextArticle: nextArticleID != nil,
                    selectPreviousArticle: selectPreviousArticle,
                    selectNextArticle: selectNextArticle,
                    onSnapshotChange: handleSnapshotChange
                )
                .id(selectedArticleID)
                .task(id: selectedArticleID) {
                    loadNavigation(database: database)
                }
            } else {
                ContentUnavailableView(
                    L10n.articleWindowMissingTitle,
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(L10n.dbUnavailableDescription)
                )
            }
        }
        .navigationTitle(articleSnapshot?.title ?? String(localized: "article.window.missing.title"))
        .onAppear {
            rememberSelectedArticleID()
        }
        .onChange(of: selectedArticleID) { oldValue, _ in
            forgetArticleID(oldValue)
            rememberSelectedArticleID()
        }
        .onDisappear {
            forgetArticleID(selectedArticleID)
        }
        .alert(
            L10n.databaseInitErrorTitle,
            isPresented: Binding(
                get: { loadErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        loadErrorMessage = nil
                    }
                }
            )
        ) {
            Button(L10n.commonDone) {
                loadErrorMessage = nil
            }
        } message: {
            Text(loadErrorMessage ?? "")
        }
        .sheet(item: $articleExportRequest) { request in
            ArticleExportSheet(request: request) {
                articleExportRequest = nil
            }
        }
        .focusedValue(\.articleCommandActions, articleCommandActions)
    }

    private var articleCommandActions: ArticleCommandActions {
        ArticleCommandActions(
            canPerformActions: articleSnapshot != nil,
            canPerformLinkActions: ArticleOriginalURLResolver.hasUsableWebLink(articleSnapshot?.link),
            toggleReadTitle: articleSnapshot?.isRead == true ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead,
            toggleStarredTitle: articleSnapshot?.isStarred == true ? L10n.articleRowStarRemove : L10n.articleRowStarAdd,
            toggleArchivedTitle: articleSnapshot?.isArchived == true ? L10n.articleUnarchiveCommand : L10n.articleArchiveCommand,
            toggleRead: toggleRead,
            toggleStarred: toggleStarred,
            toggleArchived: toggleArchived,
            copyLink: copyLink,
            openOriginal: openOriginal,
            shareOriginal: shareOriginal,
            openInArticleWindow: {},
            requestExport: requestExportArticle,
            canSelectPreviousArticle: previousArticleID != nil,
            canSelectNextArticle: nextArticleID != nil,
            selectPreviousArticle: selectPreviousArticle,
            selectNextArticle: selectNextArticle
        )
    }

    private func handleSnapshotChange(_ snapshot: ArticleReaderSnapshot?) {
        articleSnapshot = snapshot
    }

    private func selectPreviousArticle() {
        guard let previousArticleID else {
            return
        }

        selectedArticleID = previousArticleID
    }

    private func selectNextArticle() {
        guard let nextArticleID else {
            return
        }

        selectedArticleID = nextArticleID
    }

    private func loadNavigation(database: FeedivoDatabase) {
        do {
            articleIDs = try TimelineStore(database: database).articles(
                scope: .all,
                includeRead: true,
                includeHidden: true,
                limit: ArticleFetchLimits.popoutNavigationIDs
            )
            .map(\.id)
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    private func toggleRead() {
        guard let articleSnapshot, let database else {
            return
        }

        mutateStatus(database: database) { store in
            try store.setRead(!articleSnapshot.isRead, articleID: articleSnapshot.id, at: Date())
        }
    }

    private func toggleStarred() {
        guard let articleSnapshot, let database else {
            return
        }

        mutateStatus(database: database) { store in
            try store.setStarred(!articleSnapshot.isStarred, articleID: articleSnapshot.id, at: Date())
        }
    }

    private func toggleArchived() {
        guard let articleSnapshot, let database else {
            return
        }

        mutateStatus(database: database) { store in
            try store.setArchived(!articleSnapshot.isArchived, articleID: articleSnapshot.id, at: Date())
        }
    }

    private func mutateStatus(
        database: FeedivoDatabase,
        operation: (ArticleStatusStore) throws -> Void
    ) {
        do {
            try operation(ArticleStatusStore(database: database))
            articleSnapshot = try ArticleStore(database: database).readerArticle(id: selectedArticleID)
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    private func copyLink() {
        guard let url = ArticleOriginalURLResolver.url(for: articleSnapshot?.link) else {
            return
        }

        SystemArticleLinkPasteboard().copy(url.absoluteString)
    }

    private func openOriginal() {
        guard let url = ArticleOriginalURLResolver.url(for: articleSnapshot?.link) else {
            return
        }

        ArticleOriginalBrowserLauncher.open(url)
    }

    private func shareOriginal() {
        guard let url = ArticleOriginalURLResolver.url(for: articleSnapshot?.link) else {
            return
        }

        SystemArticleSharingPresenter().share(url)
    }

    private func requestExportArticle() {
        guard let articleSnapshot, let database else {
            return
        }

        do {
            let tagNames = try TagStore(database: database).exportTagNames(
                articleID: articleSnapshot.id,
                feedID: articleSnapshot.feedID
            )
            articleExportRequest = ArticleExportRequest(
                snapshot: ArticleExportSnapshot(sqliteSnapshot: articleSnapshot, tagNames: tagNames)
            )
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    private func rememberSelectedArticleID() {
        guard let uuid = UUID(uuidString: selectedArticleID) else {
            return
        }

        ArticleWindowSettings.rememberOpenArticleID(uuid)
    }

    private func forgetArticleID(_ articleID: String) {
        guard let uuid = UUID(uuidString: articleID) else {
            return
        }

        ArticleWindowSettings.forgetOpenArticleID(uuid)
    }
}
