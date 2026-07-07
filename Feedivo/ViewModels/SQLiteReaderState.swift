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
        guard force || loadedArticleID != articleID || activeLoadTask != nil else {
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
