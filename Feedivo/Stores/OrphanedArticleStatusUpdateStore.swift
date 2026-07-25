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
}
