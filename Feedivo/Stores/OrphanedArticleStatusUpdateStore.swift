import Foundation
import GRDB

struct OrphanedArticleStatusUpdateStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    /// Entfernt Einträge, die älter als `cutoffDate` sind (nie abgeholte verwaiste Status,
    /// z. B. weil der zugehörige Feed längst deabonniert wurde) — genutzt von
    /// `ArticleRetentionCleanupService.runAutomaticCleanup`.
    func deleteOlderThan(_ cutoffDate: Date) throws -> Int {
        try database.write { db in
            try db.execute(sql: "DELETE FROM orphaned_article_status_updates WHERE receivedAt < ?", arguments: [cutoffDate])
            return db.changesCount
        }
    }

    /// Leert die komplette Tabelle bedingungslos, unabhängig vom Alter — genutzt vom
    /// iCloud-Sync-Reset (`CloudSyncEngine.resetLocalState`), der alle bereits als unzustellbar
    /// erkannten Artikelstatus-Einträge verwirft, statt auf die reguläre 90-Tage-Frist
    /// (`deleteOlderThan(_:)`) zu warten.
    @discardableResult
    func deleteAll() throws -> Int {
        try database.write { db in
            try db.execute(sql: "DELETE FROM orphaned_article_status_updates")
            return db.changesCount
        }
    }
}
