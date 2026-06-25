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

@Observable
final class ArticleViewModel {
    func toggleRead(_ article: Article) {
        let wasRead = article.isRead
        article.isRead.toggle()
        updateUnreadCount(for: article, wasRead: wasRead, isRead: article.isRead)
    }

    func toggleRead(_ article: Article?) {
        guard let article else {
            return
        }

        toggleRead(article)
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

    func markAllRead(_ articles: [Article]) {
        for article in articles where !article.isRead {
            let wasRead = article.isRead
            article.isRead = true
            updateUnreadCount(for: article, wasRead: wasRead, isRead: article.isRead)
        }
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
    func deleteArticle(_ article: Article, context: ModelContext) {
        let wasRead = article.isRead
        updateUnreadCount(for: article, wasRead: wasRead, isRead: true)
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
        guard
            let link = article?.link,
            let url = URL(string: link),
            url.scheme != nil
        else {
            return nil
        }

        return url
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
}
