import Foundation
import Observation

@MainActor
@Observable
final class SQLiteReaderState {
    var snapshot: ArticleReaderSnapshot?
    var preparedArticle: ReaderPreparedArticle = .empty
    var errorMessage: String?
    var isLoading = false

    private var loadedArticleID: String?
    private var activeLoadToken = UUID()
    private var activeLoadTask: Task<Void, Never>?

    func load(articleID: String, database: FeedivoDatabase, force: Bool = false) {
        // Schutz gegen SwiftUI-Re-Render-Schleifen: .task(id: articleID) kann
        // erneut feuern, obwohl sich articleID nicht geaendert hat (der vorige
        // Task-Aufruf ist synchron/instant durchgelaufen und SwiftUI haelt
        // dafuer keine Task-Identitaet vor). Ohne diese Sperre setzt jeder
        // erneute Aufruf snapshot/isLoading zurueck, was einen Re-Render
        // ausloest, der .task(id:) wieder feuert — Endlosschleife.
        //
        // TEMP-DEBUG-Fund (2026-08-05, Reader-Ladeverzoegerung): ein
        // erneuter, nicht erzwungener Aufruf fuer dieselbe articleID WAEHREND
        // bereits ein Ladevorgang laeuft (activeLoadTask != nil) loeste hier
        // bisher trotzdem einen Abbruch+Neustart aus — per Live-Log
        // (log stream) verifiziert: bei praktisch jeder Artikelauswahl feuert
        // .task(id: articleID) ein zweites Mal fuer dieselbe ID, WAEHREND der
        // erste Ladevorgang noch laeuft, und startete dadurch einen kompletten
        // dritten, redundanten DB-Read+Prepare-Durchlauf. Da alle DB-Zugriffe
        // ueber eine einzige, serialisierte GRDB-DatabaseQueue laufen, hat das
        // die Reader-Ladezeit spuerbar verlaengert (~600-900ms statt einem
        // einzelnen schnellen PK-Read). `Task.detached`-Cancellation stoppt
        // die bereits gestartete synchrone SQLite-Abfrage ohnehin nicht mehr
        // — der Abbruch verhinderte also nur das Anwenden des Ergebnisses,
        // nicht die Arbeit selbst. Ein bereits laufender Ladevorgang fuer
        // dieselbe ID darf deshalb einfach zu Ende laufen, statt neu zu
        // starten; das bricht die oben beschriebene Schleifen-Absicherung
        // nicht, da ein reines No-Op (kein State-Reset) ohnehin keinen
        // erneuten Re-Render und damit kein erneutes Feuern ausloest.
        guard force || loadedArticleID != articleID else {
            return
        }

        activeLoadTask?.cancel()

        loadedArticleID = articleID
        isLoading = true
        errorMessage = nil
        // Bewusst KEIN Zuruecksetzen von snapshot/preparedArticle: der bereits
        // sichtbare Artikel bleibt stehen, bis der neue geladen ist (wie NetNewsWire
        // die WKWebView weiterzeigt). Das vermeidet den Spinner-Flash bei jedem
        // Artikelwechsel und bei force-Reloads (Stern/Gelesen). Der ProgressView
        // erscheint dadurch nur noch beim allerersten Laden (snapshot == nil).
        // Die finale Zuweisung unten ersetzt snapshot und preparedArticle gemeinsam,
        // sodass Kopf und Inhalt nie zu verschiedenen Artikeln gehoeren.

        let loadToken = UUID()
        activeLoadToken = loadToken

        activeLoadTask = Task { [database, articleID, loadToken] in
            var loadedSnapshot: ArticleReaderSnapshot?
            var preparedArticleForSnapshot = ReaderPreparedArticle.empty
            var loadError: String?

            do {
                let loadedData = try await Task.detached(priority: .userInitiated) {
                    try ArticleDatabase(database: database).readerArticle(id: articleID)
                }.value

                loadedSnapshot = loadedData

                if let snapshot = loadedSnapshot {
                    let input = ReaderArticleInput.make(from: snapshot)
                    if let cached = ReaderPreparedArticleCache.shared.prepared(for: input) {
                        preparedArticleForSnapshot = cached
                    } else {
                        preparedArticleForSnapshot = await Task.detached(priority: .userInitiated) {
                            ReaderPreparedArticle(input: input)
                        }.value
                        ReaderPreparedArticleCache.shared.store(preparedArticleForSnapshot, for: input)
                    }
                }
            } catch {
                loadError = error.localizedDescription
            }

            guard !Task.isCancelled,
                  self.loadedArticleID == articleID,
                  self.activeLoadToken == loadToken
            else {
                return
            }

            if let loadedSnapshot {
                self.snapshot = loadedSnapshot
                self.preparedArticle = preparedArticleForSnapshot
            } else {
                self.snapshot = nil
                self.preparedArticle = .empty
            }

            self.errorMessage = loadError
            self.isLoading = false
            self.activeLoadTask = nil
            self.activeLoadToken = loadToken
        }
    }

    /// Nur fuer Tests: wartet, bis der aktuell laufende Ladevorgang abgeschlossen ist.
    /// Produktionscode braucht das nicht — dort treibt SwiftUI die Aktualisierung ueber
    /// die @Observable-Bindings an. Im synchronen Testkontext gibt es keinen solchen
    /// Antrieb, deshalb muss der Task hier explizit abgewartet werden.
    func waitForActiveLoad() async {
        await activeLoadTask?.value
    }

    func toggleRead(database: FeedivoDatabase) {
        guard let snapshot else {
            return
        }

        mutateStatus(database: database) { store in
            try store.setRead(!snapshot.isRead, articleID: snapshot.id, at: Date())
        }
    }

    func toggleStarred(database: FeedivoDatabase) {
        guard let snapshot else {
            return
        }

        mutateStatus(database: database) { store in
            try store.setStarred(!snapshot.isStarred, articleID: snapshot.id, at: Date())
        }
    }

    func toggleArchived(database: FeedivoDatabase) {
        guard let snapshot else {
            return
        }

        mutateStatus(database: database) { store in
            try store.setArchived(!snapshot.isArchived, articleID: snapshot.id, at: Date())
        }
    }

    private func mutateStatus(
        database: FeedivoDatabase,
        operation: (ArticleDatabase) throws -> Void
    ) {
        guard let articleID = loadedArticleID else {
            return
        }

        do {
            try operation(ArticleDatabase(database: database))
            load(articleID: articleID, database: database, force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
