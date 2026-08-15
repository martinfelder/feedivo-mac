import Foundation
import GRDB

struct TagStore {
    enum TagStoreError: Error, Equatable {
        case duplicateName
        case missingTag
    }

    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    /// Markiert `tagID` als ausstehende Sync-Änderung, falls iCloud Sync aktiv ist. Läuft
    /// bewusst INNERHALB derselben `database.write`-Transaktion wie die fachliche Mutation
    /// (atomar — kein Zwischenzustand, in dem der Tag geändert, aber nicht als sync-pending
    /// markiert ist).
    ///
    /// Liest das Aktiv-Flag ueber `db` aus `cloud_sync_settings` statt aus UserDefaults, damit
    /// auch Mutationen aus dem unsandboxed FeedivoMCPServer-Prozess korrekt greifen (siehe
    /// CloudSyncSettingsStore).
    private func enqueuePendingSync(_ db: Database, tagID: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        guard CloudSyncSettingsStore.isEnabled(in: db) else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: CloudSyncTagMapping.recordType, recordName: tagID, changeType: changeType, changedFields: changedFields)
    }

    func save(_ tag: TagRecord) throws {
        try database.write { db in
            try save(tag, in: db)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    /// Batch-Variante für Aufrufer, die bereits innerhalb einer eigenen
    /// `database.write`-Transaktion stehen (z. B. RuleEngine-Anwendung nach Feed-Refresh,
    /// siehe `SQLiteFeedRefreshService.applyRules`). GRDBs `DatabaseWriter.write` ist nicht
    /// reentrant — ein erneuter `database.write`-Aufruf von hier aus würde abstürzen. Löst
    /// bewusst NICHT `CloudSyncEngine.notifyPendingChangesAvailable` aus — das übernimmt der
    /// Batch-Aufrufer einmalig nach Abschluss der gesamten Transaktion.
    func save(_ tag: TagRecord, in db: Database) throws {
        let existingID = try String.fetchOne(db, sql: """
            SELECT id
            FROM tags
            WHERE id = ? OR name = ?
            ORDER BY CASE WHEN id = ? THEN 0 ELSE 1 END
            LIMIT 1
            """, arguments: [tag.id, tag.name, tag.id])
        let now = Date()

        if let existingID {
            try db.execute(
                sql: """
                    UPDATE tags
                    SET id = ?, name = ?, colorHex = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [tag.id, tag.name, tag.colorHex, now, existingID]
            )
        } else {
            let maxSortIndex = (try Int.fetchOne(db, sql: "SELECT MAX(sortIndex) FROM tags") ?? -1) + 1
            var tag = tag
            tag.sortIndex = maxSortIndex
            try tag.insert(db)
        }

        try enqueuePendingSync(db, tagID: tag.id, changeType: .save)
    }

    func tags() throws -> [TagRecord] {
        try database.read { db in
            try TagRecord.fetchAll(db, sql: """
                SELECT *
                FROM tags
                ORDER BY sortIndex, name COLLATE NOCASE, id COLLATE NOCASE
                """)
        }
    }

    func tags(articleID: String) throws -> [TagRecord] {
        try database.read { db in
            try TagRecord.fetchAll(db, sql: """
                SELECT t.*
                FROM tags t
                JOIN article_tags at ON at.tagID = t.id
                WHERE at.articleID = ?
                ORDER BY t.name COLLATE NOCASE, t.id COLLATE NOCASE
                """, arguments: [articleID])
        }
    }

    func tags(feedID: String) throws -> [TagRecord] {
        try database.read { db in
            try TagRecord.fetchAll(db, sql: """
                SELECT t.*
                FROM tags t
                JOIN feed_tags ft ON ft.tagID = t.id
                WHERE ft.feedID = ?
                ORDER BY t.name COLLATE NOCASE, t.id COLLATE NOCASE
                """, arguments: [feedID])
        }
    }

    // MARK: - Fehler-loggende Convenience-Varianten

    /// Wie `tags()`, aber loggt einen DB-Fehler über `logIfThrows` statt ihn
    /// als „keine Tags vorhanden" zu maskieren. Rückgabewert bei Erfolg
    /// unverändert — nur der Fehlerfall wird jetzt sichtbar statt komplett
    /// verschluckt.
    static func tagsIgnoringErrors(database: FeedivoDatabase) -> [TagRecord] {
        var tags: [TagRecord] = []
        logIfThrows(context: "Tags laden") {
            tags = try TagStore(database: database).tags()
        }
        return tags
    }

    /// Wie `tagsIgnoringErrors(database:)`, aber für die feed-gebundene
    /// Tag-Liste (`tags(feedID:)`).
    static func tagsIgnoringErrors(database: FeedivoDatabase, feedID: String) -> [TagRecord] {
        var tags: [TagRecord] = []
        logIfThrows(context: "Feed-Tags laden") {
            tags = try TagStore(database: database).tags(feedID: feedID)
        }
        return tags
    }

    func exportTagNames(articleID: String, feedID: String) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT t.name
                FROM tags t
                WHERE EXISTS (
                    SELECT 1
                    FROM article_tags at
                    WHERE at.articleID = ?
                        AND at.tagID = t.id
                )
                OR EXISTS (
                    SELECT 1
                    FROM feed_tags ft
                    WHERE ft.feedID = ?
                        AND ft.tagID = t.id
                )
                ORDER BY t.name COLLATE NOCASE
                """, arguments: [articleID, feedID])
        }
    }

    func sidebarTags() throws -> [TagSidebarSnapshot] {
        try database.read { db in
            try TagSidebarSnapshot.fetchAll(db, sql: """
                SELECT
                    t.id,
                    t.name,
                    t.colorHex,
                    (
                        SELECT COUNT(DISTINCT a.id)
                        FROM articles a
                        WHERE EXISTS (
                            SELECT 1
                            FROM article_tags at
                            WHERE at.articleID = a.id
                                AND at.tagID = t.id
                        )
                        OR EXISTS (
                            SELECT 1
                            FROM feed_tags ft
                            WHERE ft.feedID = a.feedID
                                AND ft.tagID = t.id
                        )
                    ) AS articleCount
                FROM tags t
                ORDER BY t.sortIndex, t.name COLLATE NOCASE, t.id COLLATE NOCASE
                """)
        }
    }

    func assignTag(tagID: String, toArticleID articleID: String, at assignedAt: Date) throws {
        try database.write { db in
            try assignTag(tagID: tagID, toArticleID: articleID, at: assignedAt, in: db)
        }
    }

    /// Batch-Variante für Aufrufer, die bereits innerhalb einer eigenen
    /// `database.write`-Transaktion stehen — siehe Kommentar an `save(_:in:)`.
    func assignTag(tagID: String, toArticleID articleID: String, at assignedAt: Date, in db: Database) throws {
        var assignment = ArticleTagRecord(
            articleID: articleID,
            tagID: tagID,
            assignedAt: assignedAt
        )
        try assignment.insert(db, onConflict: .ignore)
    }

    func assignTag(tagID: String, toFeedID feedID: String, at assignedAt: Date) throws {
        try database.write { db in
            var assignment = FeedTagRecord(
                feedID: feedID,
                tagID: tagID,
                assignedAt: assignedAt
            )
            try assignment.insert(db, onConflict: .ignore)
        }
    }

    func renameTag(id: String, name: String) throws {
        try database.write { db in
            let duplicateID = try String.fetchOne(db, sql: """
                SELECT id
                FROM tags
                WHERE name = ? COLLATE NOCASE
                    AND id <> ?
                LIMIT 1
                """, arguments: [name, id])

            if duplicateID != nil {
                throw TagStoreError.duplicateName
            }

            try db.execute(
                sql: """
                    UPDATE tags
                    SET name = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [name, Date(), id]
            )

            if db.changesCount == 0 {
                throw TagStoreError.missingTag
            }

            try enqueuePendingSync(db, tagID: id, changeType: .save, changedFields: ["name"])
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    /// Verschiebt den Tag mit `id` an Index `targetIndex` innerhalb der
    /// bestehenden Sortierreihenfolge (0-basiert, wird auf den gültigen
    /// Bereich geklemmt) und schreibt sortIndex für alle betroffenen Tags neu
    /// — analog zu FeedFolderStore.moveFolder.
    func move(id: String, targetIndex: Int) throws {
        try database.write { db in
            let otherIDs = try String.fetchAll(
                db,
                sql: "SELECT id FROM tags WHERE id != ? ORDER BY sortIndex",
                arguments: [id]
            )

            var orderedIDs = otherIDs
            let clampedIndex = min(max(targetIndex, 0), orderedIDs.count)
            orderedIDs.insert(id, at: clampedIndex)

            let now = Date()
            for (index, tagID) in orderedIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE tags SET sortIndex = ?, updatedAt = ? WHERE id = ?",
                    arguments: [index, now, tagID]
                )
                try enqueuePendingSync(db, tagID: tagID, changeType: .save, changedFields: ["sortIndex"])
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func updateColor(id: String, colorHex: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE tags
                    SET colorHex = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [TagViewModel.normalizedColorHex(colorHex), Date(), id]
            )

            if db.changesCount == 0 {
                throw TagStoreError.missingTag
            }

            try enqueuePendingSync(db, tagID: id, changeType: .save, changedFields: ["colorHex"])
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func removeTag(tagID: String, fromFeedID feedID: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM feed_tags
                    WHERE feedID = ? AND tagID = ?
                    """,
                arguments: [feedID, tagID]
            )
        }
    }

    func removeTag(tagID: String, fromArticleID articleID: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM article_tags
                    WHERE articleID = ? AND tagID = ?
                    """,
                arguments: [articleID, tagID]
            )
        }
    }

    func deleteTag(id: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM tags
                    WHERE id = ?
                    """,
                arguments: [id]
            )

            try enqueuePendingSync(db, tagID: id, changeType: .delete)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }
}
