import SwiftUI
import SwiftData

struct ContentView: View {

    // columnVisibility steuert ob die Sidebar sichtbar ist.
    // .all bedeutet: alle 3 Spalten beim Start anzeigen.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // selectedFeed speichert welcher Feed gerade in der Sidebar ausgewählt ist.
    // Optional weil beim Start noch nichts ausgewählt ist.
    @State private var selectedFeed: Feed? = nil

    // selectedArticle speichert welcher Artikel gerade in der Liste ausgewählt ist.
    @State private var selectedArticle: Article? = nil

    @State private var articleViewModel = ArticleViewModel()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {

            // SPALTE 1: Sidebar — Liste aller Feeds
            SidebarView(selectedFeed: $selectedFeed)
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
    }
}
