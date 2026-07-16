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
    static func ensureBackfillIfNeeded(
        database: FeedivoDatabase,
        userDefaults: UserDefaults = .standard,
        index: SpotlightIndexWriting = CSSearchableIndex.default()
    ) throws {
        guard SpotlightIndexingSettings.isEnabled(in: userDefaults),
              !SpotlightIndexingSettings.hasBackfilled(in: userDefaults)
        else {
            return
        }

        let allArticleIDs = try database.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM articles")
        }

        for chunk in allArticleIDs.chunked(into: backfillBatchSize) {
            let snapshots = try ArticleDatabase(database: database).fetchArticles(
                articleIDs: Set(chunk)
            )
            indexArticles(snapshots, userDefaults: userDefaults, index: index)
        }

        SpotlightIndexingSettings.setHasBackfilled(true, in: userDefaults)
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
