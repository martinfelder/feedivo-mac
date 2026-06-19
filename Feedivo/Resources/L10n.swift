import SwiftUI

enum L10n {
    static let contentNoFeedSelectedTitle = LocalizedStringKey("content.noFeedSelected.title")
    static let contentNoFeedSelectedDescription = LocalizedStringKey("content.noFeedSelected.description")
    static let contentNoArticleSelectedTitle = LocalizedStringKey("content.noArticleSelected.title")
    static let contentNoArticleSelectedDescription = LocalizedStringKey("content.noArticleSelected.description")
    static let sidebarEmptyTitle = LocalizedStringKey("sidebar.empty.title")
    static let sidebarAddFeedButton = LocalizedStringKey("sidebar.addFeed.button")
    static let sidebarAddFeedTitle = LocalizedStringKey("sidebar.addFeed.title")
    static let sidebarAddFeedURLPlaceholder = LocalizedStringKey("sidebar.addFeed.url.placeholder")
    static let commonCancel = LocalizedStringKey("common.cancel")
    static let commonAdd = LocalizedStringKey("common.add")
    static let articleListEmptyTitle = LocalizedStringKey("articleList.empty.title")
    static let articleListEmptyDescription = LocalizedStringKey("articleList.empty.description")
    static let articleRowUnread = LocalizedStringKey("articleRow.unread")
    static let readerOpenOriginal = LocalizedStringKey("reader.openOriginal")
    static let settingsReadingSection = LocalizedStringKey("settings.reading.section")
    static let settingsMarkReadOnOpenTitle = LocalizedStringKey("settings.markReadOnOpen.title")
    static let settingsMarkReadOnOpenDescription = LocalizedStringKey("settings.markReadOnOpen.description")

    static var articleRowStarRemove: String { String(localized: "articleRow.star.remove") }
    static var articleRowStarAdd: String { String(localized: "articleRow.star.add") }
    static var articleRowStarredText: String { String(localized: "articleRow.starred") }
    static var articleRowUnreadText: String { String(localized: "articleRow.unread") }
    static var articleRowMarkRead: String { String(localized: "articleRow.markRead") }
    static var articleRowMarkUnread: String { String(localized: "articleRow.markUnread") }
    static var feedErrorInvalidURL: String { String(localized: "feed.error.invalidURL") }
    static var feedErrorParsingFailed: String { String(localized: "feed.error.parsingFailed") }
    static var feedErrorEmptyURL: String { String(localized: "feed.error.emptyURL") }
    static var feedErrorAddFailed: String { String(localized: "feed.error.addFailed") }
}
