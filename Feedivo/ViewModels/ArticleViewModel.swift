import AppKit
import Foundation
import Observation
import SwiftData

protocol ArticleLinkPasteboard {
    func copy(_ string: String)
}

struct SystemArticleLinkPasteboard: ArticleLinkPasteboard {
    func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

protocol ArticleURLOpener {
    func open(_ url: URL)
}

struct SystemArticleURLOpener: ArticleURLOpener {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

protocol ArticleSharingPresenter {
    func share(_ url: URL)
}

struct SystemArticleSharingPresenter: ArticleSharingPresenter {
    func share(_ url: URL) {
        guard let contentView = NSApp.keyWindow?.contentView else {
            return
        }

        NSSharingServicePicker(items: [url]).show(
            relativeTo: contentView.bounds,
            of: contentView,
            preferredEdge: .minY
        )
    }
}

enum ArticleOriginalURLResolver {
    static func url(for article: Article?) -> URL? {
        guard
            let link = article?.link,
            let url = URL(string: link),
            url.scheme != nil
        else {
            return nil
        }

        return url
    }
}

@Observable
final class ArticleViewModel {
    func toggleRead(_ article: Article) {
        let wasRead = article.isRead
        article.isRead.toggle()
        updateUnreadCount(for: article, wasRead: wasRead, isRead: article.isRead)
    }

    @MainActor
    func toggleRead(_ article: Article, context: ModelContext) {
        let wasRead = article.isRead
        article.isRead.toggle()
        updateUnreadCount(for: article, wasRead: wasRead, isRead: article.isRead, context: context)
    }

    func toggleRead(_ article: Article?) {
        guard let article else {
            return
        }

        toggleRead(article)
    }

    @MainActor
    func toggleRead(_ article: Article?, context: ModelContext) {
        guard let article else {
            return
        }

        toggleRead(article, context: context)
    }

    func toggleStarred(_ article: Article) {
        article.isStarred.toggle()
    }

    func toggleStarred(_ article: Article?) {
        guard let article else {
            return
        }

        toggleStarred(article)
    }

    func toggleArchived(_ article: Article) {
        article.isArchived.toggle()
    }

    func toggleArchived(_ article: Article?) {
        guard let article else {
            return
        }

        toggleArchived(article)
    }

    func markReadIfNeeded(_ article: Article?, isEnabled: Bool) {
        guard isEnabled, let article, !article.isRead else {
            return
        }

        let wasRead = article.isRead
        article.isRead = true
        updateUnreadCount(for: article, wasRead: wasRead, isRead: article.isRead)
    }

    @MainActor
    func markReadIfNeeded(_ article: Article?, isEnabled: Bool, context: ModelContext) {
        guard isEnabled, let article, !article.isRead else {
            return
        }

        let wasRead = article.isRead
        article.isRead = true
        updateUnreadCount(for: article, wasRead: wasRead, isRead: article.isRead, context: context)
    }

    func markAllRead(_ articles: [Article]) {
        for article in articles where !article.isRead {
            let wasRead = article.isRead
            article.isRead = true
            updateUnreadCount(for: article, wasRead: wasRead, isRead: article.isRead)
        }
    }

    @MainActor
    func markAllRead(_ articles: [Article], context: ModelContext) {
        for article in articles where !article.isRead {
            let wasRead = article.isRead
            article.isRead = true
            updateUnreadCount(for: article, wasRead: wasRead, isRead: article.isRead, context: context)
        }

        synchronizeUnreadCounts(for: articles, context: context)
    }

    func markRead(
        _ articles: [Article],
        matching option: ArticleMarkReadOption,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        markAllRead(option.matchingArticles(in: articles, now: now, calendar: calendar))
    }

    @MainActor
    func markRead(
        _ articles: [Article],
        matching option: ArticleMarkReadOption,
        now: Date = Date(),
        calendar: Calendar = .current,
        context: ModelContext
    ) {
        let candidateArticles = articles.filter { article in
            option.includes(article, now: now, calendar: calendar)
        }

        markAllRead(
            candidateArticles,
            context: context
        )
    }

    @MainActor
    func deleteArticle(_ article: Article, context: ModelContext) {
        let wasRead = article.isRead
        updateUnreadCount(for: article, wasRead: wasRead, isRead: true, context: context)
        context.delete(article)
        try? context.save()
    }

    func sortedForList(_ articles: [Article]) -> [Article] {
        ArticleSortOption.newestFirst.sorted(articles)
    }

    func previousArticle(before article: Article?, in articles: [Article]) -> Article? {
        guard
            let article,
            let currentIndex = articles.firstIndex(where: { $0.id == article.id }),
            currentIndex > articles.startIndex
        else {
            return nil
        }

        return articles[articles.index(before: currentIndex)]
    }

    func nextArticle(after article: Article?, in articles: [Article]) -> Article? {
        guard
            let article,
            let currentIndex = articles.firstIndex(where: { $0.id == article.id })
        else {
            return nil
        }

        let nextIndex = articles.index(after: currentIndex)
        guard nextIndex < articles.endIndex else {
            return nil
        }

        return articles[nextIndex]
    }

    func originalURL(for article: Article?) -> URL? {
        ArticleOriginalURLResolver.url(for: article)
    }

    func copyLink(
        _ article: Article?,
        pasteboard: ArticleLinkPasteboard = SystemArticleLinkPasteboard()
    ) -> Bool {
        guard let url = originalURL(for: article) else {
            return false
        }

        pasteboard.copy(url.absoluteString)
        return true
    }

    func openOriginal(
        _ article: Article?,
        opener: ArticleURLOpener = SystemArticleURLOpener()
    ) -> Bool {
        guard let url = originalURL(for: article) else {
            return false
        }

        opener.open(url)
        return true
    }

    func shareOriginal(
        _ article: Article?,
        presenter: ArticleSharingPresenter = SystemArticleSharingPresenter()
    ) -> Bool {
        guard let url = originalURL(for: article) else {
            return false
        }

        presenter.share(url)
        return true
    }

    private func updateUnreadCount(for article: Article, wasRead: Bool, isRead: Bool) {
        guard wasRead != isRead, let feed = article.feed else {
            return
        }

        if isRead {
            feed.unreadCount = max(0, feed.unreadCount - 1)
        } else {
            feed.unreadCount += 1
        }
    }

    @MainActor
    private func updateUnreadCount(
        for article: Article,
        wasRead: Bool,
        isRead: Bool,
        context: ModelContext
    ) {
        guard wasRead != isRead, let feed = try? feed(for: article, context: context) else {
            return
        }

        if isRead {
            feed.unreadCount = max(0, feed.unreadCount - 1)
        } else {
            feed.unreadCount += 1
        }
    }

    @MainActor
    private func feed(for article: Article, context: ModelContext) throws -> Feed? {
        if let feed = article.feed {
            return feed
        }

        guard let feedID = article.feedID else {
            return nil
        }

        var descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate<Feed> { feed in
                feed.id == feedID
            }
        )
        descriptor.fetchLimit = 1

        return try context.fetch(descriptor).first
    }

    @MainActor
    private func synchronizeUnreadCounts(for articles: [Article], context: ModelContext) {
        let feedIDs = Set(articles.compactMap { article in
            article.feedID ?? article.feed?.id
        })

        for feedID in feedIDs {
            guard let feed = try? feed(withID: feedID, context: context) else {
                continue
            }

            feed.unreadCount = unreadArticleCount(forFeedID: feedID, context: context)
        }
    }

    @MainActor
    private func feed(withID feedID: UUID, context: ModelContext) throws -> Feed? {
        var descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate<Feed> { feed in
                feed.id == feedID
            }
        )
        descriptor.fetchLimit = 1

        return try context.fetch(descriptor).first
    }

    @MainActor
    private func unreadArticleCount(forFeedID feedID: UUID, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == feedID && !article.isRead
            }
        )

        return (try? context.fetchCount(descriptor)) ?? 0
    }
}
