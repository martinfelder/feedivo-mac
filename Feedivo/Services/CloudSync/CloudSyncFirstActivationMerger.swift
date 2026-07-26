import Foundation
import CloudKit
import GRDB

/// Setzt die vom Nutzer im Erst-Aktivierungs-Dialog getroffene Entscheidung für einen erkannten
/// Namens-Duplikat um (siehe `CloudSyncFirstActivationAnalyzer`). Siehe Design-Spec Abschnitt 6.
enum CloudSyncFirstActivationMerger {
    /// „Zusammenführen": die alte lokale Zeile wird entfernt, referenzierende Fremdschlüssel
    /// werden auf die Cloud-ID umgeschrieben. Für `Tag` ist das ein echtes FK-Umschreiben
    /// (`article_tags`/`feed_tags.tagID` referenzieren über die ID, nicht über den Namen) — für
    /// `FeedFolder` genügt reines Löschen, da `feeds.folderName` ein Namens-String ist und über
    /// den identischen Namen ohnehin weiterläuft. Läuft komplett in einer einzigen Transaktion
    /// (implizit über `database.write`), damit ein Teilfehler nie FK-Referenzen hängend oder
    /// doppelt zurücklässt.
    static func merge(_ collision: CloudSyncFirstActivationAnalyzer.FirstActivationCollision, database: FeedivoDatabase) throws {
        try database.write { db in
            switch collision.recordType {
            case CloudSyncTagMapping.recordType:
                try mergeTag(db, oldTagID: collision.localID, newTagID: collision.cloudRecordID.recordName)
            case CloudSyncFeedFolderMapping.recordType:
                try db.execute(sql: "DELETE FROM feed_folders WHERE id = ?", arguments: [collision.localID])
            default:
                break
            }
        }
    }

    /// Führt den lokalen Tag `oldTagID` mit dem (bei der Erst-Aktivierung meist noch NICHT
    /// lokal vorhandenen) Cloud-Tag `newTagID` zusammen. Zwei Fälle:
    ///
    /// 1. **Ziel-Tag existiert lokal noch nicht** (Normalfall — der Cloud-Tag wurde noch nie
    ///    gepullt): die `tags`-Zeile wird direkt per `UPDATE tags SET id = ...` auf die neue
    ///    ID umgeschrieben, statt sie zu löschen und eine neue mit identischem Namen
    ///    einzufügen — Letzteres würde den UNIQUE-Index auf `tags.name`
    ///    (`idx_tags_name_unique`) verletzen, solange alte und neue Zeile gleichzeitig
    ///    existieren. Ein reines `UPDATE` der Primärschlüssel-Spalte lässt zwischenzeitlich
    ///    `article_tags`/`feed_tags`-Zeilen mit einem nicht mehr existierenden `tagID` zurück
    ///    (dangling) — SQLite würde das bei sofortiger Fremdschlüsselprüfung ablehnen, deshalb
    ///    `PRAGMA defer_foreign_keys = ON` (schiebt die Prüfung auf den COMMIT der laufenden
    ///    Transaktion auf, wird danach automatisch zurückgesetzt).
    /// 2. **Ziel-Tag existiert lokal bereits** (z. B. durch einen früheren Pull-Zyklus): die
    ///    alte Zeile bleibt vorerst stehen, wird erst nach dem FK-Umschreiben gelöscht.
    private static func mergeTag(_ db: Database, oldTagID: String, newTagID: String) throws {
        try db.execute(sql: "PRAGMA defer_foreign_keys = ON")

        let targetTagExistsLocally = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM tags WHERE id = ?)", arguments: [newTagID]) ?? false
        if !targetTagExistsLocally {
            try db.execute(sql: "UPDATE tags SET id = ? WHERE id = ?", arguments: [newTagID, oldTagID])
        }

        try remapTagReferences(db, oldTagID: oldTagID, newTagID: newTagID)

        // Kein-Op, falls die Zeile oben bereits per ID-Umschreiben "verschwunden" ist — betrifft
        // dann 0 Zeilen. Löscht im anderen Fall die jetzt referenzlose alte Zeile.
        try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [oldTagID])
    }

    /// „Beide behalten": lokale Zeile bekommt einen disambiguierenden Namenszusatz
    /// („Technik (2)"), bleibt als eigenständige Zeile bestehen und wird beim folgenden
    /// Backfill regulär als neuer Cloud-Record hochgeladen.
    static func keepBoth(_ collision: CloudSyncFirstActivationAnalyzer.FirstActivationCollision, database: FeedivoDatabase) throws {
        let newName = "\(collision.name) (2)"
        try database.write { db in
            switch collision.recordType {
            case CloudSyncTagMapping.recordType:
                try db.execute(sql: "UPDATE tags SET name = ?, updatedAt = ? WHERE id = ?", arguments: [newName, Date(), collision.localID])
            case CloudSyncFeedFolderMapping.recordType:
                try db.execute(sql: "UPDATE feed_folders SET name = ?, updatedAt = ? WHERE id = ?", arguments: [newName, Date(), collision.localID])
            default:
                break
            }
        }
    }

    /// Schreibt `article_tags`/`feed_tags`-Zeilen mit `oldTagID` auf `newTagID` um — mit
    /// Dedupe-Schutz: existiert für dieselbe `articleID`/`feedID` bereits eine Zuordnung zur
    /// `newTagID` (z. B. weil derselbe Artikel unabhängig schon einmal mit dem später
    /// gepullten Cloud-Tag verknüpft wurde), wird die alte Zeile nur gelöscht statt einen
    /// doppelten Zuordnungs-Datensatz zu erzeugen — beide Tabellen haben einen Primärschlüssel
    /// auf `(articleID, tagID)`/`(feedID, tagID)`, ein blindes UPDATE würde in diesem Fall mit
    /// einer Primärschlüsselverletzung abstürzen (siehe Design-Spec Abschnitt 6).
    private static func remapTagReferences(_ db: Database, oldTagID: String, newTagID: String) throws {
        let affectedArticleIDs = try String.fetchAll(db, sql: "SELECT articleID FROM article_tags WHERE tagID = ?", arguments: [oldTagID])
        for articleID in affectedArticleIDs {
            let alreadyHasNewTag = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM article_tags WHERE articleID = ? AND tagID = ?)", arguments: [articleID, newTagID]) ?? false
            if alreadyHasNewTag {
                try db.execute(sql: "DELETE FROM article_tags WHERE articleID = ? AND tagID = ?", arguments: [articleID, oldTagID])
            } else {
                try db.execute(sql: "UPDATE article_tags SET tagID = ? WHERE articleID = ? AND tagID = ?", arguments: [newTagID, articleID, oldTagID])
            }
        }

        let affectedFeedIDs = try String.fetchAll(db, sql: "SELECT feedID FROM feed_tags WHERE tagID = ?", arguments: [oldTagID])
        for feedID in affectedFeedIDs {
            let alreadyHasNewTag = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM feed_tags WHERE feedID = ? AND tagID = ?)", arguments: [feedID, newTagID]) ?? false
            if alreadyHasNewTag {
                try db.execute(sql: "DELETE FROM feed_tags WHERE feedID = ? AND tagID = ?", arguments: [feedID, oldTagID])
            } else {
                try db.execute(sql: "UPDATE feed_tags SET tagID = ? WHERE feedID = ? AND tagID = ?", arguments: [newTagID, feedID, oldTagID])
            }
        }
    }
}
