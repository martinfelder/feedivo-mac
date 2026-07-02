import SwiftData
import SwiftUI

struct SQLiteFeedArticleListView: View {
    @Environment(\.feedivoDatabase) private var database

    let feed: Feed
    @Binding var selectedArticleID: String?
    @Binding var navigationState: SQLiteArticleNavigationState

    @State private var state = SQLiteFeedArticleListState()

    var body: some View {
        Group {
            switch state.loadState {
            case .missingSQLiteDatabase:
                ContentUnavailableView(
                    "SQLite nicht verfügbar",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Die lokale Artikeldatenbank konnte nicht geöffnet werden.")
                )
            case .missingFeed:
                ContentUnavailableView(
                    "Feed noch nicht in SQLite",
                    systemImage: "tray",
                    description: Text("Dieser Feed ist noch nicht in der lokalen Artikeldatenbank vorhanden.")
                )
            case .failed(let message):
                ContentUnavailableView(
                    "Artikel konnten nicht geladen werden",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .idle where state.rows.isEmpty:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded where state.rows.isEmpty:
                ContentUnavailableView(
                    "Keine Artikel",
                    systemImage: "doc.text",
                    description: Text("Für diesen Feed sind noch keine SQLite-Artikel gespeichert.")
                )
            case .idle, .loaded:
                articleList
            }
        }
        .task(id: loadToken) {
            reload()
        }
        .onChange(of: selectedArticleID) {
            reload()
        }
        .onChange(of: state.navigationState) {
            navigationState = state.navigationState
        }
        .navigationTitle(feed.title)
    }

    private var articleList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.rows) { row in
                        Button {
                            selectedArticleID = row.id
                        } label: {
                            ArticleRowView(
                                snapshot: ArticleListItemSnapshot(sqliteSnapshot: row),
                                hasAvailableTags: false,
                                onToggleRead: {
                                    toggleRead(row.id)
                                },
                                onToggleStarred: {
                                    toggleStarred(row.id)
                                },
                                onToggleArchived: {
                                    toggleArchived(row.id)
                                },
                                onRequestAssignTag: {},
                                onCreateRule: {},
                                onCopyLink: {},
                                onOpenOriginal: {},
                                onShareOriginal: {},
                                onOpenInWindow: {},
                                onExport: {},
                                onSaveOrRemoveOffline: {},
                                onDelete: {},
                                onMarkAllRead: {}
                            )
                            .padding(.horizontal, 12)
                            .background(rowBackground(for: row))
                        }
                        .buttonStyle(.plain)
                        .id(row.id)

                        Divider()
                    }
                }
            }
            .onChange(of: selectedArticleID) { _, newValue in
                if let newValue {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private var loadToken: String {
        "\(feed.url)#\(selectedArticleID ?? "nil")"
    }

    private func rowBackground(for row: ArticleListSnapshot) -> Color {
        row.id == selectedArticleID
            ? Color.accentColor.opacity(0.14)
            : Color.clear
    }

    private func reload() {
        state.load(
            swiftDataFeedURL: feed.url,
            database: database,
            selectedArticleID: selectedArticleID
        )
        navigationState = state.navigationState
    }

    private func toggleRead(_ articleID: String) {
        guard let database else {
            return
        }

        state.toggleRead(articleID: articleID, database: database)
        navigationState = state.navigationState
    }

    private func toggleStarred(_ articleID: String) {
        guard let database else {
            return
        }

        state.toggleStarred(articleID: articleID, database: database)
        navigationState = state.navigationState
    }

    private func toggleArchived(_ articleID: String) {
        guard let database else {
            return
        }

        state.toggleArchived(articleID: articleID, database: database)
        navigationState = state.navigationState
    }
}
