import AppKit
import Foundation
import Observation

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

@Observable
final class ArticleViewModel {
    func toggleRead(_ article: Article) {
        article.isRead.toggle()
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

    func markReadIfNeeded(_ article: Article?, isEnabled: Bool) {
        guard isEnabled, let article, !article.isRead else {
            return
        }

        article.isRead = true
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
}
