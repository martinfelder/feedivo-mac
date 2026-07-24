import Foundation
import GRDB

// Fehler, die beim Umbenennen eines Ordners auftreten können. `.databaseUnavailable`
// wird nicht von dieser Store-Methode selbst geworfen (die Datenbank ist hier
// bereits injiziert), sondern ausschließlich vom UI-seitigen Aufrufer
// (`SidebarView.renameFolder`), falls die `\.feedivoDatabase`-Environment fehlt.
enum FeedFolderRenameError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case databaseUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyName: L10n.feedRenameEmptyName
        case .duplicateName: L10n.sidebarAddFolderDuplicateError
        case .databaseUnavailable: L10n.feedRenameDatabaseUnavailable
        }
    }
}

struct FeedFolderStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    /// Markiert `folderID` als ausstehende Sync-Änderung, falls iCloud Sync aktiv ist. Läuft
    /// bewusst INNERHALB derselben `database.write`-Transaktion wie die fachliche Mutation —
    /// analog zu `FeedStore.enqueuePendingSync`/`TagStore.enqueuePendingSync`.
    private func enqueuePendingSync(_ db: Database, folderID: String, changeType: CloudSyncChangeType) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: CloudSyncFeedFolderMapping.recordType, recordName: folderID, changeType: changeType)
    }

    /// Markiert einen FEED (nicht Ordner) als ausstehende Sync-Änderung — gebraucht in
    /// `renameFolder`, da `folderName` ausschließlich auf dem Feed-Record lebt (siehe
    /// `CloudSyncFeedMapping`-Dokumentation) und ein Ordner-Umbenennen deshalb auch alle
    /// betroffenen Feeds erneut synct, nicht nur den Ordner-Record selbst.
    private func enqueueFeedPendingSync(_ db: Database, feedID: String) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: CloudSyncFeedMapping.recordType, recordName: feedID, changeType: .save)
    }

    func save(_ folder: FeedFolderRecord) throws {
        try database.write { db in
            var folder = folder
            try folder.save(db)
            try enqueuePendingSync(db, folderID: folder.id, changeType: .save)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func folders() throws -> [FeedFolderRecord] {
        try database.read { db in
            try FeedFolderRecord.fetchAll(db, sql: """
                SELECT *
                FROM feed_folders
                ORDER BY sortIndex, name COLLATE NOCASE, id COLLATE NOCASE
                """)
        }
    }

    func delete(id: String) throws {
        try database.write { db in
            try enqueuePendingSync(db, folderID: id, changeType: .delete)
            try db.execute(
                sql: """
                    DELETE FROM feed_folders
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    // Ordner sind in Feedivo namensbasiert (kein FK-Konzept, das Feeds referenzieren) —
    // ein Ordner kann als expliziter feed_folders-Datensatz UND/ODER implizit nur über
    // feeds.folderName existieren. Diese Methode aktualisiert daher beide Speicherorte
    // in einer einzigen Transaktion.
    func renameFolder(from oldName: String, to newName: String) throws {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw FeedFolderRenameError.emptyName
        }

        try database.write { db in
            // Kollision case-insensitiv über beide Tabellen prüfen, den umzubenennenden
            // Ordner selbst dabei ausschließen — eine reine Großschreibungskorrektur des
            // eigenen Namens ("tech" -> "Tech") zählt nicht als Kollision.
            let collisionCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM (
                        SELECT name AS folderName FROM feed_folders
                        WHERE name = ? COLLATE NOCASE AND name != ? COLLATE NOCASE
                        UNION
                        SELECT folderName FROM feeds
                        WHERE folderName = ? COLLATE NOCASE AND folderName != ? COLLATE NOCASE
                    )
                    """,
                arguments: [trimmedName, oldName, trimmedName, oldName]
            ) ?? 0

            guard collisionCount == 0 else {
                throw FeedFolderRenameError.duplicateName
            }

            // Betroffene Feed-IDs VOR dem UPDATE ermitteln, damit sie anschließend einzeln
            // als sync-pending markiert werden können — `folderName` ist ein syncbares
            // Feed-Konfigurationsfeld (siehe `CloudSyncFeedMapping`), ein Ordner-Umbenennen
            // muss deshalb auch jeden betroffenen Feed erneut hochladen, nicht nur den
            // Ordner-Record selbst (siehe Design-Spec-Begründung).
            let affectedFeedIDs = try String.fetchAll(
                db,
                sql: "SELECT id FROM feeds WHERE folderName = ? COLLATE NOCASE",
                arguments: [oldName]
            )

            try db.execute(
                sql: """
                    UPDATE feeds
                    SET folderName = ?, configUpdatedAt = ?
                    WHERE folderName = ? COLLATE NOCASE
                    """,
                arguments: [trimmedName, Date(), oldName]
            )

            for feedID in affectedFeedIDs {
                try enqueueFeedPendingSync(db, feedID: feedID)
            }

            // Aktualisiert nur, falls ein expliziter Datensatz existiert — 0 betroffene
            // Zeilen ist hier kein Fehler und deckt rein implizite Ordner ab.
            try db.execute(
                sql: """
                    UPDATE feed_folders
                    SET name = ?, updatedAt = ?
                    WHERE name = ? COLLATE NOCASE
                    """,
                arguments: [trimmedName, Date(), oldName]
            )

            let folderID = try String.fetchOne(
                db,
                sql: "SELECT id FROM feed_folders WHERE name = ? COLLATE NOCASE",
                arguments: [trimmedName]
            )
            if let folderID {
                try enqueuePendingSync(db, folderID: folderID, changeType: .save)
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    /// Materialisiert alle Ordnernamen, die nur auf feeds.folderName existieren
    /// aber (noch) keinen feed_folders-Datensatz haben, als echte Datensätze ans
    /// Ende der aktuellen Ordner-Reihenfolge. Idempotent — bereits materialisierte
    /// Ordner werden übersprungen.
    func materializeImplicitFolders() throws {
        try database.write { db in
            try materializeImplicitFolders(db)
        }
    }

    /// Transaktionslose Variante zur Wiederverwendung innerhalb einer bereits
    /// laufenden database.write-Transaktion (siehe moveFolder unten — GRDB
    /// erlaubt keine verschachtelten Schreibtransaktionen).
    private func materializeImplicitFolders(_ db: Database) throws {
        let rawFolderNames = try String.fetchAll(
            db,
            sql: "SELECT DISTINCT folderName FROM feeds WHERE folderName IS NOT NULL"
        )
        let existingLowercasedNames = Set(
            try String.fetchAll(db, sql: "SELECT name FROM feed_folders").map { $0.lowercased() }
        )

        var canonicalNamesByLowercasedName: [String: String] = [:]
        for rawName in rawFolderNames {
            let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !existingLowercasedNames.contains(trimmed.lowercased()) else {
                continue
            }
            let key = trimmed.lowercased()
            if canonicalNamesByLowercasedName[key] == nil {
                canonicalNamesByLowercasedName[key] = trimmed
            }
        }

        let namesToMaterialize = canonicalNamesByLowercasedName.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        guard !namesToMaterialize.isEmpty else {
            return
        }

        var nextSortIndex = try Int.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(sortIndex), -1) + 1 FROM feed_folders"
        ) ?? 0

        let now = Date()
        for folderName in namesToMaterialize {
            try db.execute(
                sql: """
                    INSERT INTO feed_folders (id, name, sortIndex, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [UUID().uuidString, folderName, nextSortIndex, now, now]
            )
            nextSortIndex += 1
        }
    }

    /// Verschiebt den benannten Ordner an targetIndex innerhalb der Liste der
    /// benannten Ordner (0-basiert, wird auf 0...anzahlAndererOrdner geklemmt).
    /// Materialisiert den Ordner zuerst, falls er noch keinen Datensatz hat.
    /// Nummeriert anschließend ALLE benannten Ordner 0...n-1 neu durch.
    func moveFolder(name: String, targetIndex: Int) throws {
        try database.write { db in
            try materializeImplicitFolders(db)

            let otherFolderNames = try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM feed_folders
                    WHERE name != ? COLLATE NOCASE
                    ORDER BY sortIndex
                    """,
                arguments: [name]
            )

            var orderedNames = otherFolderNames
            let clampedIndex = min(max(targetIndex, 0), orderedNames.count)
            orderedNames.insert(name, at: clampedIndex)

            let now = Date()
            for (index, folderName) in orderedNames.enumerated() {
                try db.execute(
                    sql: "UPDATE feed_folders SET sortIndex = ?, updatedAt = ? WHERE name = ? COLLATE NOCASE",
                    arguments: [index, now, folderName]
                )
                let folderID = try String.fetchOne(
                    db,
                    sql: "SELECT id FROM feed_folders WHERE name = ? COLLATE NOCASE",
                    arguments: [folderName]
                )
                if let folderID {
                    try enqueuePendingSync(db, folderID: folderID, changeType: .save)
                }
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    /// Setzt die Ordner-Reihenfolge auf alphabetisch zurück — z. B. um eine
    /// versehentliche manuelle Umsortierung per Drag & Drop rückgängig zu
    /// machen. Betrifft nur die Ordner-Reihenfolge selbst, nicht die
    /// Feed-Reihenfolge innerhalb der Ordner. Materialisiert zuerst rein
    /// implizite Ordner, analog zu moveFolder.
    func sortAlphabetically() throws {
        try database.write { db in
            try materializeImplicitFolders(db)

            let orderedNames = try String.fetchAll(
                db,
                sql: "SELECT name FROM feed_folders ORDER BY name COLLATE NOCASE, id COLLATE NOCASE"
            )

            let now = Date()
            for (index, folderName) in orderedNames.enumerated() {
                try db.execute(
                    sql: "UPDATE feed_folders SET sortIndex = ?, updatedAt = ? WHERE name = ? COLLATE NOCASE",
                    arguments: [index, now, folderName]
                )
                let folderID = try String.fetchOne(
                    db,
                    sql: "SELECT id FROM feed_folders WHERE name = ? COLLATE NOCASE",
                    arguments: [folderName]
                )
                if let folderID {
                    try enqueuePendingSync(db, folderID: folderID, changeType: .save)
                }
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }
}
