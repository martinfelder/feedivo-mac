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
                    "Kein Feed ausgewählt",
                    systemImage: "newspaper",
                    description: Text("Wähle einen Feed in der Sidebar aus.")
                )
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            }

        } detail: {

            // SPALTE 3: Reader — Inhalt des ausgewählten Artikels
            if let article = selectedArticle {
                ReaderView(article: article)
            } else {
                ContentUnavailableView(
                    "Kein Artikel ausgewählt",
                    systemImage: "doc.text",
                    description: Text("Wähle einen Artikel aus der Liste aus.")
                )
            }

        }
    }
}
