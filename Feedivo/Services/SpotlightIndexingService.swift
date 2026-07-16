import Foundation
import GRDB
import CoreSpotlight
import UniformTypeIdentifiers
import OSLog

/// Schmale Abstraktion über `CSSearchableIndex`, damit Tests keine echten
/// Schreibzugriffe auf den System-Spotlight-Index des Entwicklerrechners
/// auslösen. `CSSearchableIndex` erfüllt diese Signaturen bereits 1:1, die
/// Konformität unten kommt ohne zusätzlichen Code aus.
protocol SpotlightIndexWriting {
    func indexSearchableItems(_ items: [CSSearchableItem], completionHandler: ((Error?) -> Void)?)
    func deleteSearchableItems(withIdentifiers identifiers: [String], completionHandler: ((Error?) -> Void)?)
    func deleteAllSearchableItems(completionHandler: ((Error?) -> Void)?)
}

extension CSSearchableIndex: SpotlightIndexWriting {}

/// Zentrale Anlaufstelle für die Spotlight-Indexierung von Artikeln
/// (Feature 9.3). Alle Methoden sind best-effort — ein Fehler aus dem
/// asynchronen `CSSearchableIndex`-Completion-Handler bricht nie einen
/// aufrufenden Feed-Refresh/Bereinigungslauf ab, sondern landet nur im
/// Systemlog (`AppLogger.dataAccess`).
enum SpotlightIndexingService {
    static let domainIdentifier = "ch.martin.Feedivo.articles"
    private static let backfillBatchSize = 500

    static func indexArticles(
        _ articles: [ArticleListSnapshot],
        userDefaults: UserDefaults = .standard,
        index: SpotlightIndexWriting = CSSearchableIndex.default()
    ) {
        guard SpotlightIndexingSettings.isEnabled(in: userDefaults), !articles.isEmpty else {
            return
        }

        let items = articles.map(searchableItem(for:))
        index.indexSearchableItems(items) { error in
            if let error {
                AppLogger.dataAccess.error("Spotlight-Indexierung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func deindexArticles(
        ids: [String],
        index: SpotlightIndexWriting = CSSearchableIndex.default()
    ) {
        guard !ids.isEmpty else {
            return
        }

        index.deleteSearchableItems(withIdentifiers: ids) { error in
            if let error {
                AppLogger.dataAccess.error("Spotlight-Deindexierung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func deindexAll(
        userDefaults: UserDefaults = .standard,
        index: SpotlightIndexWriting = CSSearchableIndex.default()
    ) {
        index.deleteAllSearchableItems { error in
            if let error {
                AppLogger.dataAccess.error("Spotlight-Komplettbereinigung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
        SpotlightIndexingSettings.setHasBackfilled(false, in: userDefaults)
    }

    /// Indexiert einmalig den kompletten Artikel-Bestand, falls der Schalter
    /// an ist und noch kein Backfill gelaufen ist (siehe
    /// `SpotlightIndexingSettings.hasBackfilledKey`). Läuft in Chunks, damit
    /// auch ein sehr großer Artikel-Bestand keine übergroße SQL-IN-Klausel
    /// erzeugt.
    ///
    /// Bewusst `async` und komplett über `FeedivoDatabase.readAsync` statt
    /// der blockierenden Sync-Variante `database.read`/`ArticleDatabase.
    /// fetchArticles` (Whole-Branch-Review-Fund, Feature 9.3): Dieses
    /// Projekt setzt `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` fürs
    /// App-Target — ein unannotierter `Task.detached`-Aufruf dieser Funktion
    /// hätte NICHT geholfen, da eine synchrone, nicht als `nonisolated`
    /// markierte Funktion in diesem Modul trotzdem implizit MainActor-
    /// isoliert bleibt und beim Awaiten wieder auf den MainActor
    /// zurückspringt. `readAsync` dagegen delegiert die eigentliche
    /// SQL-Arbeit an GRDBs eigene, echte Hintergrund-Queue (siehe
    /// `FeedivoDatabase.readAsync`-Doc-Kommentar) — das `await` gibt den
    /// aufrufenden Kontext währenddessen frei, unabhängig von dessen
    /// nomineller Actor-Isolation.
    static func ensureBackfillIfNeeded(
        database: FeedivoDatabase,
        userDefaults: UserDefaults = .standard,
        index: SpotlightIndexWriting = CSSearchableIndex.default()
    ) async throws {
        guard SpotlightIndexingSettings.isEnabled(in: userDefaults),
              !SpotlightIndexingSettings.hasBackfilled(in: userDefaults)
        else {
            return
        }

        let allArticleIDs = try await database.readAsync { db in
            try String.fetchAll(db, sql: "SELECT id FROM articles")
        }

        for chunk in allArticleIDs.chunked(into: backfillBatchSize) {
            let snapshots = try await fetchSnapshotsAsync(forArticleIDs: chunk, database: database)
            indexArticles(snapshots, userDefaults: userDefaults, index: index)
        }

        SpotlightIndexingSettings.setHasBackfilled(true, in: userDefaults)
    }

    /// Lädt `ArticleListSnapshot`s für einen Chunk von Artikel-IDs komplett
    /// auf GRDBs eigener Hintergrund-Queue (`readAsync`), statt über die
    /// blockierende Sync-Fassade `ArticleDatabase.fetchArticles(articleIDs:)`.
    /// Nutzt bewusst die gemeinsamen `ArticleListSQL`-Fragmente statt einer
    /// eigenen Spaltenliste (siehe CLAUDE.md-Gotcha zu duplizierten
    /// Artikel-SELECT-Listen). Spiegelt exakt dieselbe Filter-/Sortierlogik
    /// wie `ArticleDatabase.fetchArticles(articleIDs:includeHidden: false)`
    /// (versteckte Artikel ausgeschlossen, neueste zuerst).
    private static func fetchSnapshotsAsync(
        forArticleIDs articleIDs: [String],
        database: FeedivoDatabase
    ) async throws -> [ArticleListSnapshot] {
        guard !articleIDs.isEmpty else {
            return []
        }

        let sortedArticleIDs = Set(articleIDs).sorted()
        let placeholders = Array(repeating: "?", count: sortedArticleIDs.count).joined(separator: ", ")
        var arguments = StatementArguments(sortedArticleIDs)
        _ = arguments.append(contentsOf: [sortedArticleIDs.count])

        return try await database.readAsync { db in
            try ArticleListSnapshot.fetchAll(db, sql: """
                SELECT
                    \(ArticleListSQL.selectColumns)
                \(ArticleListSQL.standardFromJoin)
                WHERE a.id IN (\(placeholders)) AND s.isHidden = 0
                ORDER BY COALESCE(a.publishedAt, a.arrivedAt) DESC, a.arrivedAt DESC
                LIMIT ?
                """, arguments: arguments)
        }
    }

    private static func searchableItem(for article: ArticleListSnapshot) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = article.title
        attributeSet.contentDescription = article.summary.trimmedNonEmpty ?? article.title
        attributeSet.kind = article.feedTitle

        return CSSearchableItem(
            uniqueIdentifier: article.id,
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return [self]
        }

        return stride(from: 0, to: count, by: size).map { startIndex in
            Array(self[startIndex..<Swift.min(startIndex + size, count)])
        }
    }
}

private extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
