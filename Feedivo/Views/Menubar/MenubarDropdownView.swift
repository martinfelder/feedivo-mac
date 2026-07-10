import SwiftUI

/// Dropdown-Inhalt des Menubar-Icons (Feature 21.1): Header mit
/// Öffnen-/Refresh-Buttons, Liste der neuesten ungelesenen Artikel,
/// Footer mit globalem "Alle als gelesen markieren".
struct MenubarDropdownView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    @AppStorage(MenubarSettings.articleCountKey)
    private var articleCount = MenubarSettings.defaultArticleCount

    @AppStorage(MenubarArticleClickBehavior.storageKey)
    private var articleClickBehaviorRawValue = MenubarArticleClickBehavior.defaultBehavior.rawValue

    let feedViewModel: FeedViewModel

    @State private var articles: [ArticleListItemSnapshot] = []
    @State private var isRefreshing = false

    private var clickBehavior: MenubarArticleClickBehavior {
        MenubarArticleClickBehavior.resolved(from: articleClickBehaviorRawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(L10n.menubarOpenFeedivoButton) {
                    openMainWindow()
                }

                Spacer()

                Button {
                    Task {
                        await refresh()
                    }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
                .help(L10n.menubarRefreshButton)
            }
            .padding([.horizontal, .top], 12)

            Divider()

            if articles.isEmpty {
                Text(L10n.menubarEmptyStateTitle)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(articles) { article in
                    Button {
                        open(article)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(article.title)
                                .lineLimit(1)
                            if let feedTitle = article.feedTitle {
                                Text(feedTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                }

                Divider()

                Button(L10n.menubarMarkAllReadButton) {
                    markAllRead()
                }
                .padding([.horizontal, .bottom], 12)
            }
        }
        .frame(width: 320)
        .task(id: articleCount) {
            loadArticles()
        }
    }

    private func loadArticles() {
        guard let feedivoDatabase else {
            articles = []
            return
        }

        let resolvedCount = MenubarSettings.resolvedArticleCount(from: articleCount)
        let snapshots = (try? ArticleDatabase(database: feedivoDatabase).newestUnread(limit: resolvedCount)) ?? []
        articles = snapshots.map(ArticleListItemSnapshot.init(sqliteSnapshot:))
    }

    private func refresh() async {
        guard let feedivoDatabase else { return }

        isRefreshing = true
        await feedViewModel.refreshAllFeeds(sqliteDatabase: feedivoDatabase)
        loadArticles()
        isRefreshing = false
    }

    private func markAllRead() {
        guard let feedivoDatabase else { return }

        try? ArticleStatusStore(database: feedivoDatabase).markAllUnreadAsRead()
        loadArticles()
    }

    private func open(_ article: ArticleListItemSnapshot) {
        switch clickBehavior {
        case .inFeedivo:
            if let uuid = UUID(uuidString: article.id) {
                openWindow(value: ArticleWindowRequest(articleID: uuid))
            }
        case .inBrowser:
            if let link = article.hasOriginalURL ? articleOriginalURL(for: article) : nil {
                openURL(link)
            }
        }
    }

    private func articleOriginalURL(for article: ArticleListItemSnapshot) -> URL? {
        guard let feedivoDatabase else { return nil }
        guard let record = try? ArticleStore(database: feedivoDatabase).article(id: article.id) else {
            return nil
        }
        return ArticleOriginalURLResolver.url(for: record.link)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
