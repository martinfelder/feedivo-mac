# Offline-Artikel-Download-Feature entfernen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Das komplett quarantänisierte Offline-Artikel-Download-Feature (Backend, DB-Tabelle, Export-Kopplung, Tests, L10n-Keys, Dokumentation) wird vollständig aus `main` entfernt.

**Architektur:** Erst werden alle Konsumenten der Offline-Felder (`ArticleListSnapshot`, `ArticleReaderSnapshot`, `ArticleListItemSnapshot`, SQL-JOINs, Export-Bevorzugung) entkoppelt, sodass das Backend (`SQLiteOfflineStore`, `SQLiteOfflineDownloadService`, `OfflineArticleContentFetching`, `ArticleOfflineRecord`) unreferenziert daliegt. Dann wird das Backend gelöscht, danach die Datenbanktabelle per neuer Migration entfernt, zuletzt L10n/xcstrings und Dokumentation aufgeräumt.

**Tech Stack:** Swift, SwiftUI, GRDB (Migrationen), Swift Testing (`import Testing`, `@Test`, `#expect`).

## Global Constraints

- Alte Migrationen werden nie nachträglich geändert — neue Migration `v19_drop_article_offline_table` (die letzte registrierte Migration ist bereits `v18_create_cleanup_run_history`, NICHT v16 — verifiziert per `grep -n registerMigration` in `FeedivoDatabaseMigrator.swift`).
- Nicht anfassen (eigenständige, aktive Features): `networkStatusOffline`, `articleExportOfflineImagesToggle*` (Bild-Embedding beim Export), `L10n.articleExportSourceOffline`-Konstante selbst (nur ihre eine Verwendungsstelle in `ArticleExportSheet.swift` entfällt — bewusste Nutzerentscheidung aus der Design-Spec, die Konstante bleibt stehen).
- Scope beschränkt auf `main` — Worktrees/Branches `codex/sqlite-grdb-foundation` und `codex/icloud-sync-beta` bleiben unangetastet (Nutzerentscheidung).
- `docs/archive/FEATURES-legacy-2026-06-24.md` bleibt unangetastet (historisches Archiv).
- Neue Einträge/Löschungen in `Localizable.xcstrings` ausschließlich per reiner Text-Anker-Manipulation — niemals per vollem `json.load`/`json.dump`-Roundtrip (bekannter Formatierungs-Gotcha).
- Tests: Swift Testing (`import Testing`, `@testable import Feedivo`, `struct ...Tests`, `@Test func ...()`, `#expect(...)`), deutsche Testfunktionsnamen.
- Build-Verifikation nach jedem Task: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`.
- Test-Verifikation gezielt (nie die volle Suite — bekanntes Hänge-Problem): `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/<SuiteName> -parallel-testing-enabled NO`.
- `FeedivoAppSceneConfigurationTests` hat 15 bekannte, vorbestehende Testfehlschläge (unabhängig von dieser Änderung) — nach Task 4 muss die Fehlschlagszahl bei 15 bleiben, nicht höher werden.
- Kommentare im Code auf Deutsch (Projektkonvention).

---

### Task 1: Snapshots, SQL und Export-Pfad entkoppeln

**Files:**
- Modify: `Feedivo/Snapshots/ArticleListSnapshot.swift`
- Modify: `Feedivo/Snapshots/ArticleReaderSnapshot.swift`
- Modify: `Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift`
- Modify: `Feedivo/Stores/ArticleListSQL.swift`
- Modify: `Feedivo/Stores/ArticleStore.swift:103-134,254-267`
- Modify: `Feedivo/Services/ArticleExportService.swift:55-81,135-209,320-327`
- Modify: `Feedivo/Services/ArticleDocumentExportRenderers.swift:252-262,303-310`
- Modify: `Feedivo/Views/ArticleList/ArticleExportSheet.swift:108-119`
- Modify: `FeedivoTests/ArticleExportServiceTests.swift`
- Modify: `FeedivoTests/ArticleListItemSnapshotTests.swift`
- Modify: `FeedivoTests/ArticleListSQLTests.swift`

**Interfaces:**
- Consumes: nichts Neues — reine Entfernung bestehender Felder/Funktionen.
- Produces: `ArticleListSnapshot`, `ArticleReaderSnapshot`, `ArticleListItemSnapshot`, `ArticleExportSnapshot` haben danach keine `offlineState`/`offlineContent`-Felder mehr. Nach diesem Task referenziert **nichts** in `Feedivo/` oder `FeedivoTests/` außerhalb von `SQLiteOfflineStore.swift`, `OfflineArticleContentFetching.swift`, `ArticleOfflineRecord.swift`, `SQLiteOfflineDownloadServiceTests.swift` noch `ArticleOfflineState`, `offlineState`, `offlineContent` oder `offlineStateRaw` — das ist die Voraussetzung für Task 2.

- [ ] **Step 1: `ArticleListSnapshot.swift` entkoppeln**

`old_string` (komplette Datei):

```swift
import Foundation

struct ArticleListSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var feedID: String
    var feedTitle: String
    var title: String
    var summary: String?
    var link: String?
    var imageURL: String?
    var publishedAt: Date?
    var arrivedAt: Date
    var estimatedReadingMinutes: Int?
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool
    var isHidden: Bool
    var faviconURL: String?
    var offlineStateRaw: String = ArticleOfflineState.none.rawValue

    var offlineState: ArticleOfflineState {
        ArticleOfflineState(rawValue: offlineStateRaw) ?? .none
    }
}
```

`new_string`:

```swift
import Foundation

struct ArticleListSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var feedID: String
    var feedTitle: String
    var title: String
    var summary: String?
    var link: String?
    var imageURL: String?
    var publishedAt: Date?
    var arrivedAt: Date
    var estimatedReadingMinutes: Int?
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool
    var isHidden: Bool
    var faviconURL: String?
}
```

- [ ] **Step 2: `ArticleReaderSnapshot.swift` entkoppeln**

`old_string` (der `ArticleReaderSnapshot`-Struct-Block, Zeilen 15-43):

```swift
struct ArticleReaderSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var feedID: String
    var feedTitle: String
    var folderName: String?
    var title: String
    var link: String?
    var summary: String?
    var content: String?
    var imageURL: String?
    var author: String?
    var publishedAt: Date?
    var arrivedAt: Date
    var estimatedReadingMinutes: Int?
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool
    var isHidden: Bool
    var tags: [ReaderArticleTagMetadata] = []
    var offlineStateRaw: String = ArticleOfflineState.none.rawValue
    var offlineContent: String?
    var offlineRequestedAt: Date?
    var offlineSavedAt: Date?
    var offlineErrorMessage: String?

    var offlineState: ArticleOfflineState {
        ArticleOfflineState(rawValue: offlineStateRaw) ?? .none
    }
}
```

`new_string`:

```swift
struct ArticleReaderSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var feedID: String
    var feedTitle: String
    var folderName: String?
    var title: String
    var link: String?
    var summary: String?
    var content: String?
    var imageURL: String?
    var author: String?
    var publishedAt: Date?
    var arrivedAt: Date
    var estimatedReadingMinutes: Int?
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool
    var isHidden: Bool
    var tags: [ReaderArticleTagMetadata] = []
}
```

- [ ] **Step 3: `ArticleListItemSnapshot.swift` entkoppeln**

`old_string`:

```swift
    let imageURL: String?
    let offlineState: ArticleOfflineState
    let faviconURL: String?
```

`new_string`:

```swift
    let imageURL: String?
    let faviconURL: String?
```

`old_string`:

```swift
        self.faviconURL = sqliteSnapshot.faviconURL
        self.offlineState = sqliteSnapshot.offlineState
        self.hasOriginalURL = ArticleOriginalURLResolver.hasUsableWebLink(sqliteSnapshot.link)
```

`new_string`:

```swift
        self.faviconURL = sqliteSnapshot.faviconURL
        self.hasOriginalURL = ArticleOriginalURLResolver.hasUsableWebLink(sqliteSnapshot.link)
```

- [ ] **Step 4: `ArticleListSQL.swift` entkoppeln**

`old_string` (komplette Datei):

```swift
import Foundation

/// Gemeinsame SQL-Fragmente für alle Stellen, die `ArticleListSnapshot` aus
/// `articles`/`feeds`/`article_statuses`/`article_offline` laden. Vorher war dieser
/// 16-Spalten-SELECT 6-fach unabhängig kopiert — genau diese Duplikation hat bereits einen
/// `faviconURL`-Bug verursacht (siehe CLAUDE.md-Gotcha "Duplizierte SQL-SELECT-Listen").
enum ArticleListSQL {
    static let selectColumns = """
        a.id,
        a.feedID,
        f.title AS feedTitle,
        f.faviconURL AS faviconURL,
        a.title,
        a.summary,
        a.link,
        a.imageURL,
        a.publishedAt,
        a.arrivedAt,
        a.estimatedReadingMinutes,
        s.isRead,
        s.isStarred,
        s.isArchived,
        s.isHidden,
        COALESCE(o.state, 'none') AS offlineStateRaw
        """

    static let standardFromJoin = """
        FROM articles a
        JOIN feeds f ON f.id = a.feedID
        JOIN article_statuses s ON s.articleID = a.id
        LEFT JOIN article_offline o ON o.articleID = a.id
        """
}
```

`new_string`:

```swift
import Foundation

/// Gemeinsame SQL-Fragmente für alle Stellen, die `ArticleListSnapshot` aus
/// `articles`/`feeds`/`article_statuses` laden. Vorher war dieser
/// 15-Spalten-SELECT 6-fach unabhängig kopiert — genau diese Duplikation hat bereits einen
/// `faviconURL`-Bug verursacht (siehe CLAUDE.md-Gotcha "Duplizierte SQL-SELECT-Listen").
enum ArticleListSQL {
    static let selectColumns = """
        a.id,
        a.feedID,
        f.title AS feedTitle,
        f.faviconURL AS faviconURL,
        a.title,
        a.summary,
        a.link,
        a.imageURL,
        a.publishedAt,
        a.arrivedAt,
        a.estimatedReadingMinutes,
        s.isRead,
        s.isStarred,
        s.isArchived,
        s.isHidden
        """

    static let standardFromJoin = """
        FROM articles a
        JOIN feeds f ON f.id = a.feedID
        JOIN article_statuses s ON s.articleID = a.id
        """
}
```

- [ ] **Step 5: `ArticleStore.swift` — `readerArticle(id:)` entkoppeln**

`old_string`:

```swift
            var snapshot = try ArticleReaderSnapshot.fetchOne(db, sql: """
                SELECT
                    a.id,
                    a.feedID,
                    f.title AS feedTitle,
                    f.folderName AS folderName,
                    a.title,
                    a.link,
                    a.summary,
                    a.content,
                    a.imageURL,
                    a.author,
                    a.publishedAt,
                    a.arrivedAt,
                    a.estimatedReadingMinutes,
                    s.isRead,
                    s.isStarred,
                    s.isArchived,
                    s.isHidden,
                    COALESCE(o.state, 'none') AS offlineStateRaw,
                    o.content AS offlineContent,
                    o.requestedAt AS offlineRequestedAt,
                    o.savedAt AS offlineSavedAt,
                    o.errorMessage AS offlineErrorMessage
                FROM articles a
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                LEFT JOIN article_offline o ON o.articleID = a.id
                WHERE a.id = ?
                """, arguments: [id])
```

`new_string`:

```swift
            var snapshot = try ArticleReaderSnapshot.fetchOne(db, sql: """
                SELECT
                    a.id,
                    a.feedID,
                    f.title AS feedTitle,
                    f.folderName AS folderName,
                    a.title,
                    a.link,
                    a.summary,
                    a.content,
                    a.imageURL,
                    a.author,
                    a.publishedAt,
                    a.arrivedAt,
                    a.estimatedReadingMinutes,
                    s.isRead,
                    s.isStarred,
                    s.isArchived,
                    s.isHidden
                FROM articles a
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                WHERE a.id = ?
                """, arguments: [id])
```

- [ ] **Step 6: `ArticleStore.swift` — `searchArticles(matching:includeHidden:limit:)` entkoppeln**

`old_string`:

```swift
                FROM article_search search
                JOIN articles a ON a.rowid = search.rowid
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                LEFT JOIN article_offline o ON o.articleID = a.id
                WHERE article_search MATCH ?
```

`new_string`:

```swift
                FROM article_search search
                JOIN articles a ON a.rowid = search.rowid
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                WHERE article_search MATCH ?
```

- [ ] **Step 7: `ArticleExportService.swift` — `ArticleExportSnapshot` entkoppeln**

`old_string`:

```swift
struct ArticleExportSnapshot {
    let title: String
    let link: String?
    let summary: String?
    let content: String?
    let author: String?
    let publishedAt: Date?
    let feedTitle: String?
    let tagNames: [String]
    let offlineState: ArticleOfflineState
    let offlineContent: String?

    init(sqliteSnapshot: ArticleReaderSnapshot, tagNames: [String] = []) {
        self.title = sqliteSnapshot.title
        self.link = sqliteSnapshot.link
        self.summary = sqliteSnapshot.summary
        self.content = sqliteSnapshot.content
        self.author = sqliteSnapshot.author
        self.publishedAt = sqliteSnapshot.publishedAt
        self.feedTitle = sqliteSnapshot.feedTitle
        self.tagNames = tagNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        self.offlineState = sqliteSnapshot.offlineState
        self.offlineContent = sqliteSnapshot.offlineContent
    }
}
```

`new_string`:

```swift
struct ArticleExportSnapshot {
    let title: String
    let link: String?
    let summary: String?
    let content: String?
    let author: String?
    let publishedAt: Date?
    let feedTitle: String?
    let tagNames: [String]

    init(sqliteSnapshot: ArticleReaderSnapshot, tagNames: [String] = []) {
        self.title = sqliteSnapshot.title
        self.link = sqliteSnapshot.link
        self.summary = sqliteSnapshot.summary
        self.content = sqliteSnapshot.content
        self.author = sqliteSnapshot.author
        self.publishedAt = sqliteSnapshot.publishedAt
        self.feedTitle = sqliteSnapshot.feedTitle
        self.tagNames = tagNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
```

- [ ] **Step 8: `ArticleExportService.swift` — `preferredContent(for:)` entfernen, 3 Aufrufer anpassen**

`old_string` (Funktionsdefinition):

```swift
    private static func preferredContent(for snapshot: ArticleExportSnapshot) -> String? {
        if snapshot.offlineState.isAvailable,
           let offlineContent = normalizedText(snapshot.offlineContent) {
            return offlineContent
        }

        return normalizedText(snapshot.content)
    }
```

`new_string`: (Funktion komplett entfernt, keine Ersetzung — alle drei alten Aufrufer werden in den folgenden Schritten direkt auf `normalizedText(snapshot.content)` umgestellt.)

Lösche den kompletten obigen Block ersatzlos.

`old_string` (Aufrufer 1, `markdownText`):

```swift
        let bodyLines = markdownBodyLines(from: preferredContent(for: snapshot) ?? snapshot.summary)
```

`new_string`:

```swift
        let bodyLines = markdownBodyLines(from: normalizedText(snapshot.content) ?? snapshot.summary)
```

`old_string` (Aufrufer 2, `plainText`):

```swift
        lines.append(contentsOf: plainBodyLines(from: preferredContent(for: snapshot) ?? snapshot.summary))
```

`new_string`:

```swift
        lines.append(contentsOf: plainBodyLines(from: normalizedText(snapshot.content) ?? snapshot.summary))
```

`old_string` (Aufrufer 3, `htmlText`):

```swift
        if let body = normalizedText(preferredContent(for: snapshot) ?? snapshot.summary) {
```

`new_string`:

```swift
        if let body = normalizedText(normalizedText(snapshot.content) ?? snapshot.summary) {
```

- [ ] **Step 9: `ArticleDocumentExportRenderers.swift` — eigene `preferredContent(for:)`-Kopie entfernen**

`old_string` (Aufrufer, `readerMetadataText(for:)`):

```swift
                content: preferredContent(for: snapshot),
```

`new_string`:

```swift
                content: snapshot.content,
```

`old_string` (Funktionsdefinition):

```swift
    private static func preferredContent(for snapshot: ArticleExportSnapshot) -> String? {
        if snapshot.offlineState.isAvailable,
           let offlineContent = normalizedText(snapshot.offlineContent) {
            return offlineContent
        }

        return snapshot.content
    }
```

`new_string`: Lösche den kompletten obigen Block ersatzlos (keine Ersetzung).

- [ ] **Step 10: `ArticleExportSheet.swift` — Offline-Quellenanzeige entfernen**

`old_string`:

```swift
    private var contentSourceLabel: String {
        if request.snapshot.offlineState.isAvailable,
           request.snapshot.offlineContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return L10n.articleExportSourceOffline
        }

        if request.snapshot.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return L10n.articleExportSourceFeedContent
        }

        return L10n.articleExportSourceSummary
    }
```

`new_string`:

```swift
    private var contentSourceLabel: String {
        if request.snapshot.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return L10n.articleExportSourceFeedContent
        }

        return L10n.articleExportSourceSummary
    }
```

- [ ] **Step 11: `ArticleExportServiceTests.swift` — Offline-Tests entfernen, Helper entkoppeln**

`old_string` (Test 1 löschen, nutzt Ende von Test davor + Anfang von Test danach als Anker):

```swift
    }

    @Test func markdownExportBevorzugtOfflineContentVorFeedContentUndSummary() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "Offline",
                summary: "Summary",
                content: "Feed Content",
                offlineStateRaw: ArticleOfflineState.fullText.rawValue,
                offlineContent: "<p>Gespeicherter Volltext</p>"
            )
        )

        let markdown = ArticleExportService.markdown(for: snapshot)

        #expect(markdown.contains("Gespeicherter Volltext"))
        #expect(!markdown.contains("Feed Content"))
        #expect(!markdown.contains("Summary"))
    }

    @Test func markdownExportVerarbeitetUnvollstaendigesHTMLOhneAppKitHTMLImporter() {
```

`new_string`:

```swift
    }

    @Test func markdownExportVerarbeitetUnvollstaendigesHTMLOhneAppKitHTMLImporter() {
```

`old_string` (Test 2 löschen):

```swift
    }

    @Test func sqliteExportSnapshotNutztOfflineVolltextUndTags() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: ArticleReaderSnapshot(
                id: "article-1",
                feedID: "feed-1",
                feedTitle: "SQLite Feed",
                title: "SQLite Artikel",
                link: "https://example.com/article",
                summary: "Kurzfassung",
                content: "<p>Feed-Inhalt</p>",
                imageURL: nil,
                author: "Autorin",
                publishedAt: Date(timeIntervalSince1970: 1_000),
                arrivedAt: Date(timeIntervalSince1970: 1_100),
                estimatedReadingMinutes: nil,
                isRead: false,
                isStarred: false,
                isArchived: false,
                isHidden: false,
                offlineStateRaw: ArticleOfflineState.fullText.rawValue,
                offlineContent: "<article>Offline-Volltext</article>"
            ),
            tagNames: ["Swift", "RSS"]
        )

        let markdown = ArticleExportService.markdown(for: snapshot)

        #expect(markdown.contains("Offline-Volltext"))
        #expect(!markdown.contains("Feed-Inhalt"))
        #expect(markdown.contains("SQLite Feed"))
        #expect(markdown.contains("RSS, Swift"))
    }

    @Test func exportDialogBietetVorerstNurMarkdownTextUndHTMLAn() {
```

`new_string`:

```swift
    }

    @Test func exportDialogBietetVorerstNurMarkdownTextUndHTMLAn() {
```

`old_string` (Helper-Funktion entkoppeln):

```swift
private func makeReaderSnapshot(
    feedTitle: String = "",
    title: String,
    link: String? = nil,
    summary: String? = nil,
    content: String? = nil,
    imageURL: String? = nil,
    author: String? = nil,
    publishedAt: Date? = nil,
    offlineStateRaw: String = ArticleOfflineState.none.rawValue,
    offlineContent: String? = nil
) -> ArticleReaderSnapshot {
    ArticleReaderSnapshot(
        id: "article-1",
        feedID: "feed-1",
        feedTitle: feedTitle,
        title: title,
        link: link,
        summary: summary,
        content: content,
        imageURL: imageURL,
        author: author,
        publishedAt: publishedAt,
        arrivedAt: Date(timeIntervalSince1970: 0),
        estimatedReadingMinutes: nil,
        isRead: false,
        isStarred: false,
        isArchived: false,
        isHidden: false,
        offlineStateRaw: offlineStateRaw,
        offlineContent: offlineContent
    )
}
```

`new_string`:

```swift
private func makeReaderSnapshot(
    feedTitle: String = "",
    title: String,
    link: String? = nil,
    summary: String? = nil,
    content: String? = nil,
    imageURL: String? = nil,
    author: String? = nil,
    publishedAt: Date? = nil
) -> ArticleReaderSnapshot {
    ArticleReaderSnapshot(
        id: "article-1",
        feedID: "feed-1",
        feedTitle: feedTitle,
        title: title,
        link: link,
        summary: summary,
        content: content,
        imageURL: imageURL,
        author: author,
        publishedAt: publishedAt,
        arrivedAt: Date(timeIntervalSince1970: 0),
        estimatedReadingMinutes: nil,
        isRead: false,
        isStarred: false,
        isArchived: false,
        isHidden: false
    )
}
```

- [ ] **Step 12: `ArticleListItemSnapshotTests.swift` entkoppeln**

`old_string`:

```swift
        #expect(snapshot.hasOriginalURL)
        #expect(snapshot.offlineState == .none)
        #expect(snapshot.imageURL == "https://example.com/sqlite-bild.jpg")
```

`new_string`:

```swift
        #expect(snapshot.hasOriginalURL)
        #expect(snapshot.imageURL == "https://example.com/sqlite-bild.jpg")
```

- [ ] **Step 13: `ArticleListSQLTests.swift` entkoppeln**

`old_string`:

```swift
        #expect(unwrapped.isRead == false)
        #expect(unwrapped.offlineState == .none)
    }
```

`new_string`:

```swift
        #expect(unwrapped.isRead == false)
    }
```

- [ ] **Step 14: Vollständigkeit verifizieren**

Run: `grep -rln "ArticleOfflineState\|\.offlineState\b\|offlineContent\|offlineStateRaw" Feedivo/ FeedivoTests/ --include="*.swift"`
Expected: Nur noch diese 4 Dateien in der Ausgabe (die in Task 2 gelöscht werden): `Feedivo/Stores/SQLiteOfflineStore.swift`, `Feedivo/Services/OfflineArticleContentFetching.swift`, `Feedivo/Database/Records/ArticleOfflineRecord.swift`, `FeedivoTests/SQLiteOfflineDownloadServiceTests.swift`, plus `Feedivo/Database/FeedivoDatabaseMigrator.swift` (referenziert `ArticleOfflineState.none.rawValue` in der v5-Migration, bleibt dort unverändert stehen). Falls weitere Dateien auftauchen: STOPP, nicht fortfahren, sondern zusätzliche alte Referenzstelle im laufenden Task nachziehen.

- [ ] **Step 15: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 16: Betroffene Tests verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleExportServiceTests -only-testing:FeedivoTests/ArticleListItemSnapshotTests -only-testing:FeedivoTests/ArticleListSQLTests -only-testing:FeedivoTests/SQLiteArticleStoreTests -only-testing:FeedivoTests/ArticleListSnapshotFaviconTests -parallel-testing-enabled NO`
Expected: PASS (alle Tests grün)

- [ ] **Step 17: Commit**

```bash
git add Feedivo/Snapshots/ArticleListSnapshot.swift Feedivo/Snapshots/ArticleReaderSnapshot.swift Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift Feedivo/Stores/ArticleListSQL.swift Feedivo/Stores/ArticleStore.swift Feedivo/Services/ArticleExportService.swift Feedivo/Services/ArticleDocumentExportRenderers.swift Feedivo/Views/ArticleList/ArticleExportSheet.swift FeedivoTests/ArticleExportServiceTests.swift FeedivoTests/ArticleListItemSnapshotTests.swift FeedivoTests/ArticleListSQLTests.swift
git commit -m "Refactor: Offline-Felder aus Snapshots, SQL-JOINs und Export-Pfad entkoppelt (Task 1/4)"
```

---

### Task 2: Backend-Dateien löschen

**Files:**
- Delete: `Feedivo/Stores/SQLiteOfflineStore.swift`
- Delete: `Feedivo/Services/OfflineArticleContentFetching.swift`
- Delete: `Feedivo/Database/Records/ArticleOfflineRecord.swift`
- Delete: `FeedivoTests/SQLiteOfflineDownloadServiceTests.swift`

**Interfaces:**
- Consumes: Task 1 muss abgeschlossen sein — sonst brechen andere Dateien beim Löschen von `ArticleOfflineState` (definiert in `ArticleOfflineRecord.swift`).
- Produces: Keine — nach diesem Task existieren `SQLiteOfflineStore`, `SQLiteOfflineDownloadService`, `OfflineArticleContentFetching`, `ArticleOfflineState`, `ArticleOfflineRecord` nirgends mehr im Quellbaum.

- [ ] **Step 1: Vier Dateien löschen**

```bash
git rm Feedivo/Stores/SQLiteOfflineStore.swift
git rm Feedivo/Services/OfflineArticleContentFetching.swift
git rm Feedivo/Database/Records/ArticleOfflineRecord.swift
git rm FeedivoTests/SQLiteOfflineDownloadServiceTests.swift
```

- [ ] **Step 2: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git commit -m "Chore: Offline-Backend (SQLiteOfflineStore, OfflineArticleContentFetching, ArticleOfflineRecord) geloescht (Task 2/4)"
```

---

### Task 3: Datenbank-Migration v19 (Tabelle droppen)

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift:402-419`
- Modify: `FeedivoTests/SQLiteDatabaseMigrationTests.swift`

**Interfaces:**
- Consumes: Nichts aus Task 1/2.
- Produces: Neue Migration `v19_drop_article_offline_table`. Nach diesem Task existiert die Tabelle `article_offline`/der Index `idx_article_offline_state` in keiner frisch migrierten Datenbank mehr.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

Datei `FeedivoTests/SQLiteDatabaseMigrationTests.swift`, neuen Test am Ende der Datei (vor der letzten schließenden `}` der `struct SQLiteDatabaseMigrationTests`) ergänzen:

```swift
    @Test func migrationV19EntferntArticleOfflineTabelleUndIndex() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let tableNames = try database.debugTableNames()
        let indexNames = try database.debugIndexNames()

        #expect(!tableNames.contains("article_offline"))
        #expect(!indexNames.contains("idx_article_offline_state"))
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests/migrationV19EntferntArticleOfflineTabelleUndIndex -parallel-testing-enabled NO`
Expected: FAIL — `tableNames.contains("article_offline")` ist noch `true` (v19-Migration existiert noch nicht)

- [ ] **Step 3: Migration implementieren**

`old_string`:

```swift
        migrator.registerMigration("v18_create_cleanup_run_history") { database in
            try database.create(table: "cleanup_runs") { table in
                table.column("id", .text).primaryKey()
                table.column("executedAt", .datetime).notNull()
                table.column("deletedCount", .integer).notNull()
                table.column("triggerSource", .text).notNull()
                table.column("succeeded", .boolean).notNull()
                table.column("errorMessage", .text)
            }
            try database.create(
                index: "idx_cleanup_runs_executed_at",
                on: "cleanup_runs",
                columns: ["executedAt"]
            )
        }

        return migrator
    }
```

`new_string`:

```swift
        migrator.registerMigration("v18_create_cleanup_run_history") { database in
            try database.create(table: "cleanup_runs") { table in
                table.column("id", .text).primaryKey()
                table.column("executedAt", .datetime).notNull()
                table.column("deletedCount", .integer).notNull()
                table.column("triggerSource", .text).notNull()
                table.column("succeeded", .boolean).notNull()
                table.column("errorMessage", .text)
            }
            try database.create(
                index: "idx_cleanup_runs_executed_at",
                on: "cleanup_runs",
                columns: ["executedAt"]
            )
        }

        migrator.registerMigration("v19_drop_article_offline_table") { database in
            try database.drop(index: "idx_article_offline_state")
            try database.drop(table: "article_offline")
        }

        return migrator
    }
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests/migrationV19EntferntArticleOfflineTabelleUndIndex -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Bestehende, jetzt widersprüchliche Assertions korrigieren**

`old_string`:

```swift
        #expect(tableNames.contains("article_search"))
        #expect(tableNames.contains("article_offline"))
        #expect(tableNames.contains("feed_folders"))
```

`new_string`:

```swift
        #expect(tableNames.contains("article_search"))
        #expect(tableNames.contains("feed_folders"))
```

`old_string`:

```swift
        #expect(indexNames.contains("idx_feed_tags_tag_feed"))
        #expect(indexNames.contains("idx_article_offline_state"))
        #expect(indexNames.contains("idx_feed_folders_name_unique"))
```

`new_string`:

```swift
        #expect(indexNames.contains("idx_feed_tags_tag_feed"))
        #expect(indexNames.contains("idx_feed_folders_name_unique"))
```

- [ ] **Step 6: Gesamte Migrations-Testsuite verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests -parallel-testing-enabled NO`
Expected: PASS (alle Tests grün)

- [ ] **Step 7: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift FeedivoTests/SQLiteDatabaseMigrationTests.swift
git commit -m "Feature: Migration v19 entfernt article_offline-Tabelle und Index (Task 3/4)"
```

---

### Task 4: L10n, xcstrings, verbleibende Tests und Dokumentation

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: Nichts aus Task 1-3 direkt (reine Aufräumarbeit, unabhängig ausführbar nach Task 2).
- Produces: Keine neuen Symbole — letzter Task.

- [ ] **Step 1: `L10n.swift` — `readerOffline*`-Block entfernen**

`old_string`:

```swift
    static let refreshStatusNoNewArticles = String(localized: "refreshStatus.noNewArticles")
    static let readerOfflineSave = LocalizedStringKey("reader.offline.save")
    static let readerOfflineRemove = LocalizedStringKey("reader.offline.remove")
    static let readerOfflineSaving = LocalizedStringKey("reader.offline.saving")
    static let readerOfflineFullTextAvailable = LocalizedStringKey("reader.offline.fullTextAvailable")
    static let readerOfflineFeedContentAvailable = LocalizedStringKey("reader.offline.feedContentAvailable")
    static let readerOfflineFailed = LocalizedStringKey("reader.offline.failed")
    static let readerOfflineNotSaved = LocalizedStringKey("reader.offline.notSaved")
    static let readerInspectorButton = LocalizedStringKey("reader.inspector.button")
```

`new_string`:

```swift
    static let refreshStatusNoNewArticles = String(localized: "refreshStatus.noNewArticles")
    static let readerInspectorButton = LocalizedStringKey("reader.inspector.button")
```

- [ ] **Step 2: `L10n.swift` — `readerInspectorOfflineAndContentSection` entfernen**

`old_string`:

```swift
    static let readerInspectorNoTags = LocalizedStringKey("reader.inspector.noTags")
    static let readerInspectorOfflineAndContentSection = LocalizedStringKey("reader.inspector.offlineAndContentSection")
    static let readerInspectorContextSection = LocalizedStringKey("reader.inspector.contextSection")
```

`new_string`:

```swift
    static let readerInspectorNoTags = LocalizedStringKey("reader.inspector.noTags")
    static let readerInspectorContextSection = LocalizedStringKey("reader.inspector.contextSection")
```

- [ ] **Step 3: `L10n.swift` — `readerInspectorOfflineStatus`/`-OfflineDetail` entfernen**

`old_string`:

```swift
    static let readerInspectorContextSection = LocalizedStringKey("reader.inspector.contextSection")
    static let readerInspectorOfflineStatus = LocalizedStringKey("reader.inspector.offlineStatus")
    static let readerInspectorOfflineDetail = LocalizedStringKey("reader.inspector.offlineDetail")
    static let readerInspectorSourceSection = LocalizedStringKey("reader.inspector.sourceSection")
```

`new_string`:

```swift
    static let readerInspectorContextSection = LocalizedStringKey("reader.inspector.contextSection")
    static let readerInspectorSourceSection = LocalizedStringKey("reader.inspector.sourceSection")
```

- [ ] **Step 4: `L10n.swift` — `settingsOffline*`-Block entfernen**

`old_string`:

```swift
    static let settingsCacheClear = LocalizedStringKey("settings.cache.clear")
    static let settingsOfflineSection = LocalizedStringKey("settings.offline.section")
    static let settingsOfflineDescription = LocalizedStringKey("settings.offline.description")
    static let settingsOfflineManualTitle = LocalizedStringKey("settings.offline.manual.title")
    static let settingsOfflineManualDescription = LocalizedStringKey("settings.offline.manual.description")
    static let settingsOfflineFeedContentTitle = LocalizedStringKey("settings.offline.feedContent.title")
    static let settingsOfflineFeedContentDescription = LocalizedStringKey("settings.offline.feedContent.description")
    static let settingsOfflineAutomationTitle = LocalizedStringKey("settings.offline.automation.title")
    static let settingsOfflineAutomationDescription = LocalizedStringKey("settings.offline.automation.description")
    static let settingsOfflineAutoSaveStarredTitle = LocalizedStringKey("settings.offline.autoSaveStarred.title")
    static let settingsOfflineAutoSaveStarredDescription = LocalizedStringKey("settings.offline.autoSaveStarred.description")
    static let settingsNotificationsSection = LocalizedStringKey("settings.notifications.section")
```

`new_string`:

```swift
    static let settingsCacheClear = LocalizedStringKey("settings.cache.clear")
    static let settingsNotificationsSection = LocalizedStringKey("settings.notifications.section")
```

- [ ] **Step 5: `L10n.swift` — `articleRowOffline*` entfernen**

`old_string`:

```swift
    static let articleRowUnreadText = String(localized: "articleRow.unread")
    static let articleRowOfflineAvailable = String(localized: "articleRow.offline.available")
    static let articleRowOfflineFailed = String(localized: "articleRow.offline.failed")
    static let articleRowMarkRead = String(localized: "articleRow.markRead")
```

`new_string`:

```swift
    static let articleRowUnreadText = String(localized: "articleRow.unread")
    static let articleRowMarkRead = String(localized: "articleRow.markRead")
```

- [ ] **Step 6: `L10n.swift` — `offlineArchiveErrorTitle`/`-Message` entfernen**

`old_string`:

```swift
    static var feedErrorDuplicate: String {
        String(localized: "feed.error.duplicate", defaultValue: "Dieser Feed wird bereits abonniert.")
    }
    static var offlineArchiveErrorTitle: String {
        String(localized: "offline.archive.error.title", defaultValue: "Archivieren fehlgeschlagen")
    }
    static var offlineArchiveErrorMessage: String {
        String(localized: "offline.archive.error.message", defaultValue: "Die Offline-Kopie konnte nicht gespeichert werden.")
    }
    /// Titel des Alarms, wenn die SQLite-Datenbank beim Start nicht geöffnet
```

`new_string`:

```swift
    static var feedErrorDuplicate: String {
        String(localized: "feed.error.duplicate", defaultValue: "Dieser Feed wird bereits abonniert.")
    }
    /// Titel des Alarms, wenn die SQLite-Datenbank beim Start nicht geöffnet
```

- [ ] **Step 7: `Localizable.xcstrings` — 26 verwaiste Einträge per Skript entfernen**

**Nicht** `json.load`/`json.dump` auf die ganze Datei anwenden (siehe Global Constraints). Stattdessen:

```bash
python3 - <<'PYEOF'
import re

path = "Feedivo/Resources/Localizable.xcstrings"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

keys_to_remove = [
    "reader.offline.save",
    "reader.offline.remove",
    "reader.offline.saving",
    "reader.offline.fullTextAvailable",
    "reader.offline.feedContentAvailable",
    "reader.offline.failed",
    "reader.offline.notSaved",
    "reader.inspector.offlineAndContentSection",
    "reader.inspector.offlineStatus",
    "reader.inspector.offlineDetail",
    "settings.offline.section",
    "settings.offline.description",
    "settings.offline.manual.title",
    "settings.offline.manual.description",
    "settings.offline.feedContent.title",
    "settings.offline.feedContent.description",
    "settings.offline.automation.title",
    "settings.offline.automation.description",
    "settings.offline.autoSaveStarred.title",
    "settings.offline.autoSaveStarred.description",
    "articleRow.offline.available",
    "articleRow.offline.failed",
    "offline.archive.error.title",
    "offline.archive.error.message",
    "offline.error.missingOriginalURL",
    "offline.error.emptyDownloadedContent",
    "offline.error.unreachable",
]

removed = []
missing = []

for key in keys_to_remove:
    pattern = re.compile(
        r'^    "' + re.escape(key) + r'" : \{\n(?:.*\n)*?    \},?\n',
        re.MULTILINE
    )
    new_content, count = pattern.subn("", content, count=1)
    if count == 1:
        content = new_content
        removed.append(key)
    else:
        missing.append(key)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)

print(f"Entfernt: {len(removed)} von {len(keys_to_remove)}")
if missing:
    print("NICHT GEFUNDEN (manuell pruefen):", missing)
PYEOF
```

Expected Ausgabe: `Entfernt: 26 von 26` (keine "NICHT GEFUNDEN"-Zeile). Falls doch Keys fehlen: STOPP, nicht weitermachen, sondern die fehlenden Keys einzeln per `grep -n "KEY"` in der Datei lokalisieren und den Grund klären (z. B. abweichende Einrücktiefe).

- [ ] **Step 8: JSON-Validität und Diff-Sauberkeit verifizieren**

Run: `python3 -c "import json; json.load(open('Feedivo/Resources/Localizable.xcstrings'))" && echo "JSON gueltig"`
Expected: `JSON gueltig` (kein Traceback)

Run: `git diff --stat Feedivo/Resources/Localizable.xcstrings`
Expected: Nur Deletions (z. B. `1 file changed, 0 insertions(+), 728 deletions(-)`), **keine** unerwarteten Insertions — sonst wurde versehentlich reformatiert.

- [ ] **Step 9: `FeedivoAppSceneConfigurationTests.swift` — Offline-Regressionstest komplett entfernen**

`old_string`:

```swift
    }

    @Test func offlineArtikelKopienSindNichtMehrImProduktivenUIPfadVerdrahtet() throws {
        let projectRoot = projectRootURL()
        let settingsSource = try source(at: "Feedivo/Views/Settings/SettingsView.swift", projectRoot: projectRoot)
        let sqliteReaderSource = try source(at: "Feedivo/Views/Reader/SQLiteReaderView.swift", projectRoot: projectRoot)
        let rowSource = try source(at: "Feedivo/Views/ArticleList/ArticleRowView.swift", projectRoot: projectRoot)
        let listSource = try source(at: "Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift", projectRoot: projectRoot)
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let preparedSource = try source(at: "Feedivo/Views/Reader/ReaderPreparedArticle.swift", projectRoot: projectRoot)

        #expect(!settingsSource.contains("case offline"))
        #expect(!settingsSource.contains("NewOfflineSettingsView"))
        #expect(!settingsSource.contains("OfflineArticleStorageSummary"))
        #expect(!sqliteReaderSource.contains("SQLiteOfflineDownloadService"))
        #expect(!sqliteReaderSource.contains("toggleOffline"))
        #expect(!rowSource.contains("onSaveOrRemoveOffline"))
        #expect(!rowSource.contains("offlineIndicator"))
        #expect(!listSource.contains("SQLiteOfflineDownloadService"))
        #expect(!listSource.contains("saveOrRemoveOffline"))
        #expect(!contentSource.contains("automaticallySaveStarredArticles"))
        #expect(!preparedSource.contains("offlineContent"))
    }

    @Test func sqliteReaderVerdrahtetRegelErstellenMitRuleWizard() throws {
```

`new_string`:

```swift
    }

    @Test func sqliteReaderVerdrahtetRegelErstellenMitRuleWizard() throws {
```

- [ ] **Step 10: `FeedivoAppSceneConfigurationTests.swift` — veraltete Einzel-Assertion entfernen**

`old_string`:

```swift
        #expect(!contentSource.contains("@State private var articleViewModel"))
        #expect(!contentSource.contains("@State private var offlineDownloadService = OfflineDownloadService()"))
        #expect(!contentSource.contains("\n                ReaderView("))
```

`new_string`:

```swift
        #expect(!contentSource.contains("@State private var articleViewModel"))
        #expect(!contentSource.contains("\n                ReaderView("))
```

- [ ] **Step 11: Build und Test verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests -parallel-testing-enabled NO`
Expected: Bekannte 15 vorbestehende Fehlschläge (unverändert gegenüber vor diesem Task) — nicht mehr, nicht weniger. Die beiden entfernten/geänderten Tests dürfen keine neuen Fehlschläge verursachen.

- [ ] **Step 12: `CLAUDE.md` — Gotcha-Eintrag entfernen**

`old_string`:

```markdown
- **Offline-Artikel-Download-Backend ist bewusst quarantäniert, kein Versehen:**
  `SQLiteOfflineStore`, `SQLiteOfflineDownloadService`, `OfflineArticleContentFetching`-
  Protokoll, `URLSessionOfflineArticleContentFetcher` (alle in `Stores/SQLiteOfflineStore.swift`
  / `Services/OfflineArticleContentFetching.swift`) sowie ~25 zugehörige `L10n.swift`-Keys
  (`readerOffline*`, `settingsOffline*`) haben **keine aktive UI-Anbindung** mehr, sind aber
  vollständig implementiert und getestet (`SQLiteOfflineDownloadServiceTests.swift`).
  `FeedivoAppSceneConfigurationTests.swift` enthält explizite Regressionstests, die die
  **Abwesenheit** der Offline-UI prüfen (`toggleOffline`, `saveOrRemoveOffline`,
  `NewOfflineSettingsView` dürfen nicht existieren) — die UI-Schicht wurde also gezielt entfernt,
  das Backend blieb stehen. Bei künftigen Dead-Code-Scans (periphery o. ä.) **nicht löschen**,
  ohne das vorher explizit mit dem Nutzer zu klären — siehe „Offene Entscheidungen".
- **`MenuBarExtra` (SwiftUI) verursacht in `FeedivoApp.swift` einen 100%-CPU-Endlos-Spin beim
```

`new_string`:

```markdown
- **`MenuBarExtra` (SwiftUI) verursacht in `FeedivoApp.swift` einen 100%-CPU-Endlos-Spin beim
```

- [ ] **Step 13: `CLAUDE.md` — Eintrag unter „Offene Entscheidungen" entfernen**

`old_string`:

```markdown
- **App Store vs. private Verteilung:** Weiterhin offen.

- **Offline-Artikel-Download-Feature:** Backend + Settings-UI-Strings existieren vollständig
  (`SQLiteOfflineStore` u. a., siehe Gotchas oben), die UI-Anbindung wurde aber gezielt entfernt
  und ist per Regressionstest blockiert. Reaktivieren (UI wieder anbinden) oder endgültig
  entfernen (Backend + Tests + L10n-Keys)? Bisher nicht entschieden, beim Dead-Code-Cleanup
  vom 2026-07-10 bewusst unangetastet gelassen.

**Bereits gelöst (zur Referenz):**
```

`new_string`:

```markdown
- **App Store vs. private Verteilung:** Weiterhin offen.

**Bereits gelöst (zur Referenz):**
```

- [ ] **Step 14: `CLAUDE.md` — Verzeichnisbaum bereinigen (3 Stellen)**

`old_string`:

```markdown
│   │       └── ArticleOfflineRecord.swift, ArticleIdentityHistoryRecord.swift
```

`new_string`:

```markdown
│   │       └── ArticleIdentityHistoryRecord.swift
```

`old_string`:

```markdown
│   │   ├── SQLiteSmartFolderStore.swift, SQLiteOfflineStore.swift
```

`new_string`:

```markdown
│   │   ├── SQLiteSmartFolderStore.swift
```

`old_string`:

```markdown
│   │   ├── ArticleRetentionSettings.swift / ArticleRetentionCleanupService.swift  # Aufbewahrungslimits
│   │   ├── OfflineArticleContentFetching.swift  # Offline-Volltext-Speicherung
│   │   ├── BackgroundRefreshService.swift + *Settings.swift    # Hintergrund-Refresh (NSBackgroundActivityScheduler)
```

`new_string`:

```markdown
│   │   ├── ArticleRetentionSettings.swift / ArticleRetentionCleanupService.swift  # Aufbewahrungslimits
│   │   ├── BackgroundRefreshService.swift + *Settings.swift    # Hintergrund-Refresh (NSBackgroundActivityScheduler)
```

- [ ] **Step 15: `CLAUDE.md` — Migrationstabelle aktualisieren**

`old_string`:

```markdown
| v4_create_article_search_index | Volltextsuche für Artikel |
| v5_create_article_offline_table | Offline-Artikelinhalte |
| v6_create_admin_definition_tables | Regeln, Regelbedingungen, intelligente Ordner + deren Bedingungen |
```

`new_string`:

```markdown
| v4_create_article_search_index | Volltextsuche für Artikel |
| v6_create_admin_definition_tables | Regeln, Regelbedingungen, intelligente Ordner + deren Bedingungen |
```

`old_string`:

```markdown
| v16_add_tag_sort_index | `sortIndex`-Spalte auf `tags`, analog zu v15 — macht Tags in der Sidebar erstmals per Drag&Drop sortierbar |

**Achtung bei neuen Migrationen:** Vor dem Anlegen einer neuen Migration IMMER den
```

`new_string`:

```markdown
| v16_add_tag_sort_index | `sortIndex`-Spalte auf `tags`, analog zu v15 — macht Tags in der Sidebar erstmals per Drag&Drop sortierbar |
| v19_drop_article_offline_table | Entfernt `article_offline` (Feature "Offline-Artikel-Download" vollständig entfernt, 2026-07-20) — Hinweis: v17/v18 fehlen in dieser Tabelle, das ist eine vorbestehende Dokumentationslücke außerhalb des Scopes dieser Änderung |

**Achtung bei neuen Migrationen:** Vor dem Anlegen einer neuen Migration IMMER den
```

- [ ] **Step 16: `CLAUDE.md` — Eintrag unter „Letzte Änderungen" ergänzen**

`old_string`:

```markdown
## Letzte Änderungen

- 2026-07-20: CLAUDE.md-Korrektur — 9 veraltete „NICHT gepusht"-Vermerke in „Aktuell in
```

`new_string`:

```markdown
## Letzte Änderungen

- 2026-07-20: Offline-Artikel-Download-Feature vollständig entfernt (Backend, DB-Tabelle
  `article_offline` per neuer Migration `v19_drop_article_offline_table`, Kopplung an
  Artikel-Export entkoppelt, 23 unbenutzte L10n-Keys + 3 zugehörige xcstrings-Fehlermeldungs-
  Keys entfernt, Offline-spezifische Tests gelöscht/angepasst). Vier Tasks via
  Brainstorming→Spec→Plan→Subagent-Driven-Development. Entscheidung: endgültig entfernen
  statt reaktivieren (siehe ehemaliger Eintrag unter „Offene Entscheidungen").
- 2026-07-20: CLAUDE.md-Korrektur — 9 veraltete „NICHT gepusht"-Vermerke in „Aktuell in
```

- [ ] **Step 17: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings FeedivoTests/FeedivoAppSceneConfigurationTests.swift CLAUDE.md
git commit -m "Chore: L10n/xcstrings/Tests/Dokumentation fuer entferntes Offline-Feature bereinigt (Task 4/4)"
```

---

## Manuelle Live-Verifikationscheckliste (nach Task 4, vor Push)

Kein computer-use für native macOS-Apps in dieser Umgebung verfügbar — folgende Punkte sind vom Nutzer manuell zu prüfen:

1. App-Start auf einer bestehenden Datenbank mit älterem Schema — Migration `v19_drop_article_offline_table` läuft fehlerfrei durch (kein Crash, kein Datenverlust bei anderen Tabellen/Artikeln).
2. Artikel exportieren (Markdown/PDF/DOCX) — Inhalt entspricht dem Feed-Inhalt, keine Regression im Export-Dialog, keine Anzeige einer "Offline"-Quelle mehr im Export-Sheet.
3. Artikelliste/Reader laden weiterhin normal (keine SQL-Fehler durch entfernten JOIN, keine fehlenden Favicons — Regressionsrisiko aus der bereits einmal aufgetretenen `faviconURL`-Bug-Historie).
