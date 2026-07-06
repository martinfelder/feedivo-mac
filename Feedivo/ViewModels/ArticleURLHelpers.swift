import AppKit
import Foundation

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
        ArticleOriginalBrowserLauncher.open(url)
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
    static func hasUsableWebLink(_ link: String?) -> Bool {
        guard let link else {
            return false
        }

        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLink.isEmpty else {
            return false
        }

        let lowercasedLink = trimmedLink.lowercased()
        return lowercasedLink.hasPrefix("https://") || lowercasedLink.hasPrefix("http://")
    }

    static func url(for link: String?) -> URL? {
        guard
            let link,
            hasUsableWebLink(link),
            let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme != nil
        else {
            return nil
        }

        return url
    }

    static func url(for article: Article?) -> URL? {
        url(for: article?.link)
    }
}
