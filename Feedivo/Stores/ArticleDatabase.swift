import Foundation

/// Zentrale Fassade für den produktiven SQLite-Artikelpfad.
///
/// Die spezialisierten Stores bleiben klein und testbar; UI-State und Reader
/// sprechen aber über diese Fassade mit der Artikeldatenbank, statt die
/// einzelnen Store-Typen selbst zu koordinieren.
struct ArticleDatabase {
    private let feedStore: FeedStore
    private let articleStore: ArticleStore
    private let statusStore: ArticleStatusStore
    private let timelineStore: TimelineStore

    init(database: FeedivoDatabase) {
        self.feedStore = FeedStore(database: database)
        self.articleStore = ArticleStore(database: database)
        self.statusStore = ArticleStatusStore(database: database)
        self.timelineStore = TimelineStore(database: database)
    }

    func feedExists(id: String) throws -> Bool {
        try feedStore.feed(id: id) != nil
    }

    func timelineArticles(
        scope: TimelineScope,
        searchText: String? = nil,
        includeRead: Bool = true,
        includeHidden: Bool = false,
        limit: Int = 500
    ) throws -> [ArticleListSnapshot] {
        try timelineStore.articles(
            scope: scope,
            searchText: searchText,
            includeRead: includeRead,
            includeHidden: includeHidden,
            limit: limit
        )
    }

    func readerArticle(id: String) throws -> ArticleReaderSnapshot? {
        try articleStore.readerArticle(id: id)
    }

    func setRead(_ isRead: Bool, articleID: String, at date: Date?) throws {
        try statusStore.setRead(isRead, articleID: articleID, at: date)
    }

    func setStarred(_ isStarred: Bool, articleID: String, at date: Date?) throws {
        try statusStore.setStarred(isStarred, articleID: articleID, at: date)
    }

    func setArchived(_ isArchived: Bool, articleID: String, at date: Date?) throws {
        try statusStore.setArchived(isArchived, articleID: articleID, at: date)
    }
}
