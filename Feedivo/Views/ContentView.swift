import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(sort: \Tag.name) private var tags: [Tag]

    // columnVisibility steuert ob die Sidebar sichtbar ist.
    // .all bedeutet: alle 3 Spalten beim Start anzeigen.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // sidebarSelection speichert ob ein Smart Filter oder ein Feed ausgewählt ist.
    @State private var sidebarSelection: SidebarSelection? = .smartFilter(.allArticles)

    // selectedArticle speichert welcher Artikel gerade in der Liste ausgewählt ist.
    @State private var selectedArticle: Article? = nil
    @State private var articleNavigationState = ArticleNavigationState.empty

    @State private var articleViewModel = ArticleViewModel()
    @State private var feedViewModel = FeedViewModel()
    @State private var isShowingAddFeedSheet = false
    @State private var feedPendingDeletion: Feed?
    @State private var isDeleteFeedConfirmationPresented = false
    @State private var isImportingOPML = false
    @State private var isExportingOPML = false
    @State private var opmlExportDocument = OPMLDocument()
    @State private var opmlAlert: OPMLAlert?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {

            // SPALTE 1: Sidebar — Liste aller Feeds
            SidebarView(
                selection: $sidebarSelection,
                onRequestAddFeed: requestAddFeed,
                onRequestDeleteFeed: requestDeleteFeed
            )
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)

        } content: {

            // SPALTE 2: Artikel-Liste des ausgewählten Feeds oder Smart Filters
            if let smartFilter = selectedSmartFilter {
                ArticleListView(
                    smartFilter: smartFilter,
                    selectedArticle: $selectedArticle,
                    navigationState: $articleNavigationState
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else if let feed = selectedFeed {
                ArticleListView(
                    feed: feed,
                    selectedArticle: $selectedArticle,
                    navigationState: $articleNavigationState
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else if let tag = selectedTag {
                ArticleListView(
                    tag: tag,
                    selectedArticle: $selectedArticle,
                    navigationState: $articleNavigationState
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else {
                // Platzhalter wenn kein Feed oder Smart Filter ausgewählt ist
                ContentUnavailableView(
                    L10n.contentNoFeedSelectedTitle,
                    systemImage: "newspaper",
                    description: Text(L10n.contentNoFeedSelectedDescription)
                )
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            }

        } detail: {

            // SPALTE 3: Reader — Inhalt des ausgewählten Artikels
            if let article = selectedArticle {
                ReaderView(
                    article: article,
                    canSelectPreviousArticle: articleNavigationState.previousArticle != nil,
                    canSelectNextArticle: articleNavigationState.nextArticle != nil,
                    selectPreviousArticle: selectPreviousArticle,
                    selectNextArticle: selectNextArticle
                )
            } else {
                ContentUnavailableView(
                    L10n.contentNoArticleSelectedTitle,
                    systemImage: "doc.text",
                    description: Text(L10n.contentNoArticleSelectedDescription)
                )
            }

        }
        .onChange(of: sidebarSelection) {
            selectedArticle = nil
            articleNavigationState = .empty
        }
        .sheet(isPresented: $isShowingAddFeedSheet) {
            AddFeedSheet()
        }
        .confirmationDialog(
            L10n.feedDeleteConfirmationTitle,
            isPresented: $isDeleteFeedConfirmationPresented,
            presenting: feedPendingDeletion
        ) { feed in
            Button(L10n.feedDeleteConfirmButton, role: .destructive) {
                deleteFeed(feed)
            }

            Button(L10n.commonCancel, role: .cancel) {
                feedPendingDeletion = nil
            }
        } message: { feed in
            Text(L10n.feedDeleteConfirmationMessage(feedTitle: feed.title))
        }
        .fileImporter(
            isPresented: $isImportingOPML,
            allowedContentTypes: [.opml, .xml]
        ) { result in
            importOPML(from: result)
        }
        .fileExporter(
            isPresented: $isExportingOPML,
            document: opmlExportDocument,
            contentType: .opml,
            defaultFilename: "Feedivo.opml"
        ) { _ in }
        .alert(item: $opmlAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.commonDone))
            )
        }
        .focusedValue(
            \.articleCommandActions,
            ArticleCommandActions(
                selectedArticle: selectedArticle,
                toggleRead: {
                    articleViewModel.toggleRead(selectedArticle)
                },
                toggleStarred: {
                    articleViewModel.toggleStarred(selectedArticle)
                },
                copyLink: {
                    _ = articleViewModel.copyLink(selectedArticle)
                },
                openOriginal: {
                    _ = articleViewModel.openOriginal(selectedArticle)
                },
                canSelectPreviousArticle: articleNavigationState.previousArticle != nil,
                canSelectNextArticle: articleNavigationState.nextArticle != nil,
                selectPreviousArticle: selectPreviousArticle,
                selectNextArticle: selectNextArticle
            )
        )
        .focusedValue(
            \.feedCommandActions,
            FeedCommandActions(
                selectedFeed: selectedFeed,
                requestAddFeed: requestAddFeed,
                requestImportOPML: requestImportOPML,
                requestExportOPML: requestExportOPML,
                refreshAllFeeds: {
                    Task {
                        await feedViewModel.refreshAllFeeds(feeds, context: modelContext)
                    }
                },
                refreshSelectedFeed: {
                    if let selectedFeed {
                        Task {
                            await feedViewModel.refreshFeed(selectedFeed, context: modelContext)
                        }
                    }
                },
                requestDelete: {
                    if let selectedFeed {
                        requestDeleteFeed(selectedFeed)
                    }
                },
                hasFeeds: !feeds.isEmpty
            )
        )
    }

    private func requestAddFeed() {
        isShowingAddFeedSheet = true
    }

    private func requestImportOPML() {
        isImportingOPML = true
    }

    private func requestExportOPML() {
        let opmlFeeds = feedViewModel.opmlFeedsForExport(from: feeds)
        opmlExportDocument = OPMLDocument(text: OPMLService.exportFeeds(opmlFeeds))
        isExportingOPML = true
    }

    private func requestDeleteFeed(_ feed: Feed) {
        feedPendingDeletion = feed
        isDeleteFeedConfirmationPresented = true
    }

    private func importOPML(from result: Result<URL, Error>) {
        Task {
            do {
                let url = try result.get()
                let canAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if canAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                let opmlFeeds = try OPMLService.parseFeeds(from: data)
                let importResult = try await feedViewModel.importOPMLFeeds(
                    opmlFeeds,
                    existingFeeds: feeds,
                    context: modelContext
                )
                opmlAlert = OPMLAlert(
                    title: L10n.opmlImportResultTitle,
                    message: L10n.opmlImportResultMessage(
                        imported: importResult.imported,
                        skippedDuplicates: importResult.skippedDuplicates
                    )
                )
            } catch {
                opmlAlert = OPMLAlert(
                    title: L10n.opmlImportFailedTitle,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func deleteFeed(_ feed: Feed) {
        let shouldClearSelection = selectedFeed?.persistentModelID == feed.persistentModelID

        feedViewModel.deleteFeed(feed, context: modelContext)

        if feedViewModel.errorMessage == nil && shouldClearSelection {
            selectedArticle = nil
            sidebarSelection = .smartFilter(.allArticles)
        }

        feedPendingDeletion = nil
    }

    private func selectPreviousArticle() {
        if let previousArticle = articleNavigationState.previousArticle {
            selectedArticle = previousArticle
        }
    }

    private func selectNextArticle() {
        if let nextArticle = articleNavigationState.nextArticle {
            selectedArticle = nextArticle
        }
    }

    private var selectedFeed: Feed? {
        guard case .feed(let feedID) = sidebarSelection else {
            return nil
        }

        return feeds.first { $0.persistentModelID == feedID }
    }

    private var selectedTag: Tag? {
        guard case .tag(let tagID) = sidebarSelection else {
            return nil
        }

        return tags.first { $0.persistentModelID == tagID }
    }

    private var selectedSmartFilter: SmartFilter? {
        guard case .smartFilter(let smartFilter) = sidebarSelection else {
            return nil
        }

        return smartFilter
    }

}

private struct OPMLAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
