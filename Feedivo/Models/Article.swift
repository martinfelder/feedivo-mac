import Foundation
import SwiftData

enum ArticleOfflineState: String, CaseIterable, Codable {
    case none
    case feedContent
    case fullText
    case failed

    var isAvailable: Bool {
        self == .feedContent || self == .fullText
    }
}

// Article repräsentiert einen einzelnen Artikel aus einem Feed
@Model
class Article {
    var id: UUID = UUID()
    var title: String = ""
    var link: String?
    var summary: String?
    var content: String?
    var author: String?
    var publishedAt: Date?
    var imageURL: String?
    var sourceID: String?
    var feedID: UUID?
    var isRead: Bool = false
    var isStarred: Bool = false
    var isArchived: Bool = false
    var isHidden: Bool = false
    var offlineStateRaw: String = ArticleOfflineState.none.rawValue
    var offlineContent: String?
    var offlineRequestedAt: Date?
    var offlineSavedAt: Date?
    var offlineErrorMessage: String?

    var offlineState: ArticleOfflineState {
        get {
            ArticleOfflineState(rawValue: offlineStateRaw) ?? .none
        }
        set {
            offlineStateRaw = newValue.rawValue
        }
    }

    @Relationship
    var feed: Feed?

    /// FetchDescriptor, das alle Skalar-Attribute lädt außer den großen Blobs
    /// `content` und `offlineContent`. Diese werden beim Regel-Matching
    /// (RuleEngine) nicht gebraucht — sie faulten nur bei tatsächlichem Zugriff.
    /// Beziehungen (feed, tags) bleiben ohnehin lazy. Spart residenten Speicher,
    /// wenn eine View viele Artikel nur zum Zählen/Hooken braucht (P1).
    static let lightPropertiesToFetch: [PartialKeyPath<Article>] = [
        \.id, \.title, \.link, \.summary, \.author, \.publishedAt,
        \.imageURL, \.sourceID, \.feedID, \.isRead, \.isStarred,
        \.isArchived, \.isHidden, \.offlineStateRaw,
        \.offlineRequestedAt, \.offlineSavedAt, \.offlineErrorMessage
    ]

    /// Leichte Felder für den Refresh-Abgleich. `content` und `offlineContent`
    /// bleiben bewusst draußen, damit ein Sammel-Refresh große Textfelder nur
    /// faultet, wenn der Feed tatsächlich neuen Volltext nachliefert.
    static let refreshLookupPropertiesToFetch: [PartialKeyPath<Article>] = [
        \.id, \.title, \.link, \.summary, \.publishedAt, \.imageURL,
        \.sourceID, \.feedID, \.isRead, \.isStarred, \.isArchived, \.isHidden
    ]

    static func lightFetchDescriptor(
        sortBy sortDescriptors: [SortDescriptor<Article>] = []
    ) -> FetchDescriptor<Article> {
        var descriptor = FetchDescriptor<Article>(sortBy: sortDescriptors)
        descriptor.propertiesToFetch = lightPropertiesToFetch
        return descriptor
    }

    @Relationship
    var tags: [Tag]? = []

    init(
        title: String,
        link: String? = nil,
        summary: String? = nil,
        content: String? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        imageURL: String? = nil,
        sourceID: String? = nil,
        isRead: Bool = false,
        isStarred: Bool = false,
        isArchived: Bool = false,
        isHidden: Bool = false,
        feed: Feed? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.link = link
        self.summary = summary
        self.content = content
        self.author = author
        self.publishedAt = publishedAt
        self.imageURL = imageURL
        self.sourceID = sourceID
        self.isRead = isRead
        self.isStarred = isStarred
        self.isArchived = isArchived
        self.isHidden = isHidden
        self.offlineStateRaw = ArticleOfflineState.none.rawValue
        self.offlineContent = nil
        self.offlineRequestedAt = nil
        self.offlineSavedAt = nil
        self.offlineErrorMessage = nil
        self.tags = []
        assign(feed: feed)
    }

    /// `feed` und `feedID` atomar setzen (M10) — hält beide Referenzen
    /// synchron. Direkte Zuweisungen an nur eine der beiden Properties sind
    /// die Ursache für Divergenz (Relationship intakt, feedID kaputt oder
    /// umgekehrt), die sonst nur per Backfill repariert wird.
    func assign(feed: Feed?) {
        self.feed = feed
        self.feedID = feed?.id
    }
}
