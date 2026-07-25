import Foundation
import GRDB

/// Ein eingehender Artikelstatus (iCloud Sync Phase 2b), dessen zugehöriger Artikel lokal
/// noch nicht existiert. Wird beim Eintreffen des Artikels (`ArticleStore.upsert`) angewendet
/// und dann gelöscht — siehe `CloudSyncArticleStatusMapping.applyIncoming`.
struct OrphanedArticleStatusUpdateRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "orphaned_article_status_updates"

    var articleID: String
    var isRead: Bool
    var isStarred: Bool
    var readAt: Date?
    var starredAt: Date?
    /// Lokaler Empfangszeitpunkt (nicht der `CKRecord.modificationDate` des Absenders) —
    /// Grundlage für die spätere Bereinigung nie abgeholter Einträge, siehe
    /// `OrphanedArticleStatusUpdateStore.deleteOlderThan(_:)`.
    var receivedAt: Date
}
