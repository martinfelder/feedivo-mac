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

    func save(_ folder: FeedFolderRecord) throws {
        try database.write { db in
            var folder = folder
            try folder.save(db)
        }
    }

    func folders() throws -> [FeedFolderRecord] {
        try database.read { db in
            try FeedFolderRecord.fetchAll(db, sql: """
                SELECT *
                FROM feed_folders
                ORDER BY name COLLATE NOCASE, id COLLATE NOCASE
                """)
        }
    }

    func delete(id: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM feed_folders
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
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

            try db.execute(
                sql: """
                    UPDATE feeds
                    SET folderName = ?
                    WHERE folderName = ? COLLATE NOCASE
                    """,
                arguments: [trimmedName, oldName]
            )

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
        }
    }
}
