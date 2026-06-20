import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    // columnVisibility steuert ob die Sidebar sichtbar ist.
    // .all bedeutet: alle 3 Spalten beim Start anzeigen.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // selectedFeed speichert welcher Feed gerade in der Sidebar ausgewählt ist.
    // Optional weil beim Start noch nichts ausgewählt ist.
    @State private var selectedFeed: Feed? = nil

    // selectedArticle speichert welcher Artikel gerade in der Liste ausgewählt ist.
    @State private var selectedArticle: Article? = nil

    @State private var articleViewModel = ArticleViewModel()
    @State private var feedViewModel = FeedViewModel()
    @State private var isShowingAddFeedSheet = false
    @State private var feedPendingDeletion: Feed?
    @State private var isDeleteFeedConfirmationPresented = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {

            // SPALTE 1: Sidebar — Liste aller Feeds
            SidebarView(
                selectedFeed: $selectedFeed,
                onRequestAddFeed: requestAddFeed,
                onRequestDeleteFeed: requestDeleteFeed
            )
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)

        } content: {

            // SPALTE 2: Artikel-Liste des ausgewählten Feeds
            if let feed = selectedFeed {
                ArticleListView(feed: feed, selectedArticle: $selectedArticle)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else {
                // Platzhalter wenn kein Feed ausgewählt ist
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
                ReaderView(article: article)
            } else {
                ContentUnavailableView(
                    L10n.contentNoArticleSelectedTitle,
                    systemImage: "doc.text",
                    description: Text(L10n.contentNoArticleSelectedDescription)
                )
            }

        }
        .onChange(of: selectedFeed?.persistentModelID) {
            selectedArticle = nil
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
        .focusedValue(
            \.articleCommandActions,
            ArticleCommandActions(
                selectedArticle: selectedArticle,
                toggleRead: {
                    articleViewModel.toggleRead(selectedArticle)
                },
                toggleStarred: {
                    articleViewModel.toggleStarred(selectedArticle)
                }
            )
        )
        .focusedValue(
            \.feedCommandActions,
            FeedCommandActions(
                selectedFeed: selectedFeed,
                requestAddFeed: requestAddFeed,
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
                }
            )
        )
    }

    private func requestAddFeed() {
        isShowingAddFeedSheet = true
    }

    private func requestDeleteFeed(_ feed: Feed) {
        feedPendingDeletion = feed
        isDeleteFeedConfirmationPresented = true
    }

    private func deleteFeed(_ feed: Feed) {
        let shouldClearSelection = selectedFeed?.persistentModelID == feed.persistentModelID

        feedViewModel.deleteFeed(feed, context: modelContext)

        if feedViewModel.errorMessage == nil && shouldClearSelection {
            selectedArticle = nil
            selectedFeed = nil
        }

        feedPendingDeletion = nil
    }
}
