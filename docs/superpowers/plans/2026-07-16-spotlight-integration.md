# Spotlight-Integration (Feature 9.3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Artikel als Core Spotlight Items indexieren, damit macOS Spotlight sie findet und ein Klick auf ein Resultat Feedivo direkt beim Artikel öffnet — mit einem Ein/Aus-Schalter in den Einstellungen.

**Architecture:** Ein neuer `SpotlightIndexingService` kapselt `CSSearchableIndex` hinter einem injizierbaren Protokoll (`SpotlightIndexWriting`) für Testbarkeit. Bestehende Insert-Stellen (`SQLiteFeedRefreshService`, `SQLiteFeedSubscriptionService`) und Delete-Stellen (`SQLiteFeedArticleListState`, `ArticleRetentionCleanupService`) bekommen je einen injizierbaren Closure-Hook, der im Produktivfall auf den neuen Service zeigt. Ein Spotlight-Klick liefert eine `NSUserActivity`, die `FeedivoAppDelegate` über eine neue, pur-funktionale `SpotlightContinuationParser`-Komponente in die bereits bestehende `feedivo://article`-Konsum-Pipeline (`PendingURLSchemeAction`) einspeist.

**Tech Stack:** Swift, SwiftUI, GRDB (SQLite), CoreSpotlight, Swift Testing.

## Global Constraints

- Artikel-IDs sind UUID-Strings (`ArticleRecord.id`) — identisch zu dem, was `feedivo://article?id=` erwartet und was als Spotlight-`uniqueIdentifier` dient.
- `ArticleListSnapshot` (aus `ArticleDatabase.fetchArticles(articleIDs:)`) enthält bereits `id`, `title`, `summary`, `feedTitle` — kein separater `FeedStore`-Join nötig.
- Kommentare im Code auf Deutsch (Projektkonvention).
- Neue `L10n.swift`-Keys, die nicht 1:1 einem String-Literal entsprechen, MÜSSEN manuell in `Localizable.xcstrings` ergänzt werden (Xcodes Auto-Stub greift bei indirekten Keys nicht, bekannter Gotcha).
- Bestehende Trailing-Closure-Testaufrufe von `SQLiteFeedRefreshService(...)` binden an den LETZTEN Init-Parameter (`fetcher`) — neue Parameter MÜSSEN vor `fetcher` eingefügt werden, sonst brechen 5 bestehende Tests.
- `xcodebuild build` nach jedem Task laufen lassen; `SourceKit`-Diagnosen in der IDE sind laut CLAUDE.md oft veraltete Fehlalarme — nur ein echter Build zählt.
- Tests gezielt mit `-only-testing:FeedivoTests/<SuiteName>` laufen lassen (volle Testsuite hängt bekanntlich).

---

### Task 1: SpotlightIndexingSettings

**Files:**
- Create: `Feedivo/Services/SpotlightIndexingSettings.swift`
- Test: `FeedivoTests/SpotlightIndexingSettingsTests.swift`

**Interfaces:**
- Produces: `SpotlightIndexingSettings.isEnabledKey: String`, `.defaultIsEnabled: Bool`, `.hasBackfilledKey: String`, `.defaultHasBackfilled: Bool`, `.isEnabled(in:) -> Bool`, `.hasBackfilled(in:) -> Bool`, `.setHasBackfilled(_:in:)`

- [ ] **Step 1: Write the failing tests**

Create `FeedivoTests/SpotlightIndexingSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct SpotlightIndexingSettingsTests {
    @Test func defaultsSindWieDokumentiert() {
        #expect(SpotlightIndexingSettings.isEnabledKey == "spotlight.isEnabled")
        #expect(SpotlightIndexingSettings.defaultIsEnabled == true)
        #expect(SpotlightIndexingSettings.hasBackfilledKey == "spotlight.hasBackfilled")
        #expect(SpotlightIndexingSettings.defaultHasBackfilled == false)
    }

    @Test func isEnabledLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()

        #expect(SpotlightIndexingSettings.isEnabled(in: defaults) == true)
    }

    @Test func isEnabledLiestGespeichertenWert() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(false, forKey: SpotlightIndexingSettings.isEnabledKey)

        #expect(SpotlightIndexingSettings.isEnabled(in: defaults) == false)

        defaults.set(true, forKey: SpotlightIndexingSettings.isEnabledKey)

        #expect(SpotlightIndexingSettings.isEnabled(in: defaults) == true)
    }

    @Test func hasBackfilledLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()

        #expect(SpotlightIndexingSettings.hasBackfilled(in: defaults) == false)
    }

    @Test func setHasBackfilledSchreibtUndLiestWertZurueck() throws {
        let defaults = try temporaryUserDefaults()

        SpotlightIndexingSettings.setHasBackfilled(true, in: defaults)
        #expect(SpotlightIndexingSettings.hasBackfilled(in: defaults) == true)

        SpotlightIndexingSettings.setHasBackfilled(false, in: defaults)
        #expect(SpotlightIndexingSettings.hasBackfilled(in: defaults) == false)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.SpotlightIndexingSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SpotlightIndexingSettingsTests -parallel-testing-enabled NO`
Expected: Build failure — `SpotlightIndexingSettings` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `Feedivo/Services/SpotlightIndexingSettings.swift`:

```swift
import Foundation

/// Persistente Einstellungen für die Spotlight-Indexierung (Feature 9.3).
/// Gleiches Muster wie `NotificationSettings.swift`: sicherer
/// `object(forKey:) != nil`-Guard, damit ein fehlender Key den dokumentierten
/// Default liefert statt stillschweigend `false`.
enum SpotlightIndexingSettings {
    static let isEnabledKey = "spotlight.isEnabled"
    static let defaultIsEnabled = true

    /// Hält fest, ob der aktuelle Spotlight-Index bereits den vollständigen
    /// Artikel-Bestand widerspiegelt. Wird nach einem erfolgreichen Backfill
    /// auf `true` gesetzt und beim Ausschalten des Schalters (deindexAll)
    /// wieder auf `false` zurückgesetzt, damit ein erneutes Einschalten
    /// zuverlässig einen frischen Backfill auslöst.
    static let hasBackfilledKey = "spotlight.hasBackfilled"
    static let defaultHasBackfilled = false

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isEnabledKey) != nil else {
            return defaultIsEnabled
        }
        return defaults.bool(forKey: isEnabledKey)
    }

    static func hasBackfilled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: hasBackfilledKey) != nil else {
            return defaultHasBackfilled
        }
        return defaults.bool(forKey: hasBackfilledKey)
    }

    static func setHasBackfilled(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: hasBackfilledKey)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SpotlightIndexingSettingsTests -parallel-testing-enabled NO`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/SpotlightIndexingSettings.swift FeedivoTests/SpotlightIndexingSettingsTests.swift
git commit -m "Feature: SpotlightIndexingSettings-Datenmodell (Schalter + Backfill-Flag)"
```

---

### Task 2: SpotlightIndexingService

**Files:**
- Create: `Feedivo/Services/SpotlightIndexingService.swift`
- Test: `FeedivoTests/SpotlightIndexingServiceTests.swift`

**Interfaces:**
- Consumes: `SpotlightIndexingSettings.isEnabled(in:)`, `.hasBackfilled(in:)`, `.setHasBackfilled(_:in:)` (Task 1); `ArticleListSnapshot` (`id`, `title`, `summary`, `feedTitle`, existing type); `ArticleDatabase(database:).fetchArticles(articleIDs:)` (existing); `FeedivoDatabase.read(_:)` (existing); `AppLogger.dataAccess` (existing, `Feedivo/Extensions/SilentErrorLogging.swift`)
- Produces: `SpotlightIndexWriting` protocol; `SpotlightIndexingService.domainIdentifier: String`; `.indexArticles(_:userDefaults:index:)`; `.deindexArticles(ids:index:)`; `.deindexAll(userDefaults:index:)`; `.ensureBackfillIfNeeded(database:userDefaults:index:) throws`

- [ ] **Step 1: Write the failing tests**

Create `FeedivoTests/SpotlightIndexingServiceTests.swift`:

```swift
import Foundation
import CoreSpotlight
import Testing
@testable import Feedivo

final class FakeSpotlightIndex: SpotlightIndexWriting {
    private(set) var indexedItems: [CSSearchableItem] = []
    private(set) var deletedIdentifiers: [String] = []
    private(set) var didDeleteAll = false

    func indexSearchableItems(_ items: [CSSearchableItem], completionHandler: ((Error?) -> Void)?) {
        indexedItems.append(contentsOf: items)
        completionHandler?(nil)
    }

    func deleteSearchableItems(withIdentifiers identifiers: [String], completionHandler: ((Error?) -> Void)?) {
        deletedIdentifiers.append(contentsOf: identifiers)
        completionHandler?(nil)
    }

    func deleteAllSearchableItems(completionHandler: ((Error?) -> Void)?) {
        didDeleteAll = true
        completionHandler?(nil)
    }
}

struct SpotlightIndexingServiceTests {
    @Test func indexArticlesBautCSSearchableItemsMitArtikelDaten() throws {
        let defaults = try temporaryUserDefaults()
        let index = FakeSpotlightIndex()
        let snapshot = makeSnapshot(id: "article-1", title: "Titel", summary: "Zusammenfassung", feedTitle: "Mein Feed")

        SpotlightIndexingService.indexArticles([snapshot], userDefaults: defaults, index: index)

        #expect(index.indexedItems.count == 1)
        #expect(index.indexedItems.first?.uniqueIdentifier == "article-1")
        #expect(index.indexedItems.first?.domainIdentifier == SpotlightIndexingService.domainIdentifier)
        #expect(index.indexedItems.first?.attributeSet.title == "Titel")
        #expect(index.indexedItems.first?.attributeSet.contentDescription == "Zusammenfassung")
        #expect(index.indexedItems.first?.attributeSet.kind == "Mein Feed")
    }

    @Test func indexArticlesFaelltBeiFehlenderZusammenfassungAufTitelZurueck() throws {
        let defaults = try temporaryUserDefaults()
        let index = FakeSpotlightIndex()
        let snapshot = makeSnapshot(id: "article-1", title: "Titel", summary: nil, feedTitle: "Mein Feed")

        SpotlightIndexingService.indexArticles([snapshot], userDefaults: defaults, index: index)

        #expect(index.indexedItems.first?.attributeSet.contentDescription == "Titel")
    }

    @Test func indexArticlesIstNoOpWennSchalterAusIst() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(false, forKey: SpotlightIndexingSettings.isEnabledKey)
        let index = FakeSpotlightIndex()
        let snapshot = makeSnapshot(id: "article-1", title: "Titel", summary: nil, feedTitle: "Feed")

        SpotlightIndexingService.indexArticles([snapshot], userDefaults: defaults, index: index)

        #expect(index.indexedItems.isEmpty)
    }

    @Test func deindexArticlesLeitetIdentifiersWeiter() throws {
        let index = FakeSpotlightIndex()

        SpotlightIndexingService.deindexArticles(ids: ["a", "b"], index: index)

        #expect(index.deletedIdentifiers == ["a", "b"])
    }

    @Test func deindexArticlesIstNoOpBeiLeererListe() throws {
        let index = FakeSpotlightIndex()

        SpotlightIndexingService.deindexArticles(ids: [], index: index)

        #expect(index.deletedIdentifiers.isEmpty)
    }

    @Test func deindexAllLoeschtAllesUndSetztBackfillFlagZurueck() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: SpotlightIndexingSettings.hasBackfilledKey)
        let index = FakeSpotlightIndex()

        SpotlightIndexingService.deindexAll(userDefaults: defaults, index: index)

        #expect(index.didDeleteAll == true)
        #expect(SpotlightIndexingSettings.hasBackfilled(in: defaults) == false)
    }

    @Test func ensureBackfillIfNeededIndexiertAlleBestehendenArtikel() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let index = FakeSpotlightIndex()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Feed"))
        let articleStore = ArticleStore(database: database)
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", title: "Eins"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", title: "Zwei"))

        try SpotlightIndexingService.ensureBackfillIfNeeded(database: database, userDefaults: defaults, index: index)

        #expect(index.indexedItems.count == 2)
        #expect(SpotlightIndexingSettings.hasBackfilled(in: defaults) == true)
    }

    @Test func ensureBackfillIfNeededLaeuftKeinZweitesMal() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let index = FakeSpotlightIndex()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Feed"))
        _ = try ArticleStore(database: database).upsert(ArticleUpsertInput(feedID: "feed-1", title: "Eins"))

        try SpotlightIndexingService.ensureBackfillIfNeeded(database: database, userDefaults: defaults, index: index)
        try SpotlightIndexingService.ensureBackfillIfNeeded(database: database, userDefaults: defaults, index: index)

        #expect(index.indexedItems.count == 1)
    }

    @Test func ensureBackfillIfNeededIstNoOpWennSchalterAusIst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        defaults.set(false, forKey: SpotlightIndexingSettings.isEnabledKey)
        let index = FakeSpotlightIndex()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Feed"))
        _ = try ArticleStore(database: database).upsert(ArticleUpsertInput(feedID: "feed-1", title: "Eins"))

        try SpotlightIndexingService.ensureBackfillIfNeeded(database: database, userDefaults: defaults, index: index)

        #expect(index.indexedItems.isEmpty)
        #expect(SpotlightIndexingSettings.hasBackfilled(in: defaults) == false)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.SpotlightIndexingService.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func makeSnapshot(id: String, title: String, summary: String?, feedTitle: String) -> ArticleListSnapshot {
    ArticleListSnapshot(
        id: id,
        feedID: "feed-1",
        feedTitle: feedTitle,
        title: title,
        summary: summary,
        link: nil,
        imageURL: nil,
        publishedAt: nil,
        arrivedAt: Date(timeIntervalSince1970: 0),
        estimatedReadingMinutes: nil,
        isRead: false,
        isStarred: false,
        isArchived: false,
        isHidden: false,
        faviconURL: nil
    )
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SpotlightIndexingServiceTests -parallel-testing-enabled NO`
Expected: Build failure — `SpotlightIndexingService`/`SpotlightIndexWriting` do not exist yet.

- [ ] **Step 3: Write the implementation**

Create `Feedivo/Services/SpotlightIndexingService.swift`:

```swift
import Foundation
import GRDB
import CoreSpotlight
import UniformTypeIdentifiers

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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SpotlightIndexingServiceTests -parallel-testing-enabled NO`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/SpotlightIndexingService.swift FeedivoTests/SpotlightIndexingServiceTests.swift
git commit -m "Feature: SpotlightIndexingService (CSSearchableIndex-Wrapper mit injizierbarem Protokoll)"
```

---

### Task 3: Spotlight-Klick → Deep Link (SpotlightContinuationParser + FeedivoAppDelegate)

**Files:**
- Create: `Feedivo/Services/SpotlightContinuationParser.swift`
- Modify: `Feedivo/App/FeedivoAppDelegate.swift`
- Test: `FeedivoTests/SpotlightContinuationParserTests.swift`

**Interfaces:**
- Consumes: `PendingURLSchemeAction` (existing, `Feedivo/App/PendingURLSchemeAction.swift`), `FeedivoURLSchemeAction.openArticle(articleID:)` (existing)
- Produces: `SpotlightContinuationParser.articleID(from:) -> UUID?`

- [ ] **Step 1: Write the failing tests**

Create `FeedivoTests/SpotlightContinuationParserTests.swift`:

```swift
import Foundation
import CoreSpotlight
import Testing
@testable import Feedivo

struct SpotlightContinuationParserTests {
    @Test func liestArtikelIDAusGueltigerSpotlightAktivitaet() {
        let articleID = UUID()
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: articleID.uuidString]

        #expect(SpotlightContinuationParser.articleID(from: activity) == articleID)
    }

    @Test func liefertNilBeiFalschemAktivitaetsTyp() {
        let activity = NSUserActivity(activityType: "com.example.other")
        activity.userInfo = [CSSearchableItemActivityIdentifier: UUID().uuidString]

        #expect(SpotlightContinuationParser.articleID(from: activity) == nil)
    }

    @Test func liefertNilBeiFehlenderID() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)

        #expect(SpotlightContinuationParser.articleID(from: activity) == nil)
    }

    @Test func liefertNilBeiKaputterUUID() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "not-a-uuid"]

        #expect(SpotlightContinuationParser.articleID(from: activity) == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SpotlightContinuationParserTests -parallel-testing-enabled NO`
Expected: Build failure — `SpotlightContinuationParser` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `Feedivo/Services/SpotlightContinuationParser.swift`:

```swift
import Foundation
import CoreSpotlight

/// Reine Parsing-Logik für die `NSUserActivity`, die macOS beim Klick auf ein
/// Spotlight-Suchresultat an die App liefert. Kein AppKit-/App-Bezug, dadurch
/// isoliert unit-testbar — analog zu `FeedivoURLSchemeParser`. Unbekannte
/// Aktivitätstypen oder fehlende/kaputte IDs liefern `nil` — der Aufrufer
/// ignoriert die Aktivität dann still.
enum SpotlightContinuationParser {
    static func articleID(from userActivity: NSUserActivity) -> UUID? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else {
            return nil
        }

        return UUID(uuidString: identifier)
    }
}
```

Modify `Feedivo/App/FeedivoAppDelegate.swift` — add the new method after `application(_:open:)`:

```swift
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let action = FeedivoURLSchemeParser.action(for: url) {
                pendingURLSchemeAction.action = action
            }
        }
    }

    // Feature 9.3: macOS liefert einen Klick auf ein Spotlight-Suchresultat als
    // NSUserActivity, nicht als URL — landet deshalb in einem eigenen
    // Delegate-Callback statt in application(_:open:). Nutzt denselben
    // PendingURLSchemeAction-Konsum-Pfad wie feedivo://article, damit
    // ContentView beide Auslöser identisch behandelt.
    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard let articleID = SpotlightContinuationParser.articleID(from: userActivity) else {
            return false
        }

        pendingURLSchemeAction.action = .openArticle(articleID: articleID)
        return true
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SpotlightContinuationParserTests -parallel-testing-enabled NO`
Expected: PASS (4 tests)

Also run a full build to verify `FeedivoAppDelegate.swift` compiles:
Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/SpotlightContinuationParser.swift Feedivo/App/FeedivoAppDelegate.swift FeedivoTests/SpotlightContinuationParserTests.swift
git commit -m "Feature: Spotlight-Klick oeffnet Artikel ueber bestehende Deep-Link-Pipeline"
```

---

### Task 4: Indexierungs-Hook in SQLiteFeedRefreshService

**Files:**
- Modify: `Feedivo/Services/SQLiteFeedRefreshService.swift`
- Test: `FeedivoTests/SQLiteFeedRefreshServiceTests.swift`

**Interfaces:**
- Consumes: `SpotlightIndexingService.indexArticles(_:userDefaults:index:)` (Task 2, default param usage), `ArticleDatabase(database:).fetchArticles(articleIDs:)` (existing), `logIfThrows(context:_:)` (existing, `Feedivo/Extensions/SilentErrorLogging.swift`)
- Produces: new init parameter `indexForSpotlight: @escaping SpotlightIndexer` on `SQLiteFeedRefreshService`, where `typealias SpotlightIndexer = ([ArticleListSnapshot]) -> Void`

**IMPORTANT:** `indexForSpotlight` MUST be inserted BEFORE `fetcher` in the init parameter list. Five existing tests call `SQLiteFeedRefreshService(database:, now:) { url, validators in ... }` using trailing-closure syntax that binds to whichever parameter is LAST. `fetcher` must remain last.

- [ ] **Step 1: Write the failing test**

Add to `FeedivoTests/SQLiteFeedRefreshServiceTests.swift` (inside the `SQLiteFeedRefreshServiceTests` struct, e.g. right after `refreshInsertsParsedArticlesAndUpdatesUnreadCount`):

```swift
    @Test func refreshIndexiertNeueArtikelInSpotlight() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        var indexedSnapshots: [ArticleListSnapshot] = []
        let service = SQLiteFeedRefreshService(
            database: database,
            indexForSpotlight: { indexedSnapshots.append(contentsOf: $0) }
        ) { url, _ in
            .updated(
                ParsedFeed(
                    sourceURL: url,
                    title: "Example",
                    description: nil,
                    articles: [
                        ParsedArticle(
                            title: "Neu",
                            sourceID: "one",
                            link: nil,
                            summary: "Zusammenfassung",
                            content: nil,
                            publishedAt: nil,
                            imageURL: nil
                        )
                    ]
                ),
                FeedHTTPValidators()
            )
        }

        _ = try await service.refresh(feedID: "feed-1")

        #expect(indexedSnapshots.count == 1)
        #expect(indexedSnapshots.first?.title == "Neu")
        #expect(indexedSnapshots.first?.feedTitle == "Example")
    }

    @Test func refreshRuftSpotlightIndexierungNichtBeiNotModifiedAuf() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        var indexCallCount = 0
        let service = SQLiteFeedRefreshService(
            database: database,
            indexForSpotlight: { _ in indexCallCount += 1 }
        ) { _, validators in
            .notModified(validators)
        }

        _ = try await service.refresh(feedID: "feed-1")

        #expect(indexCallCount == 0)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests -parallel-testing-enabled NO`
Expected: Build failure — `indexForSpotlight` init parameter does not exist yet.

- [ ] **Step 3: Write the implementation**

In `Feedivo/Services/SQLiteFeedRefreshService.swift`, modify the `SQLiteFeedRefreshService` struct:

Replace:
```swift
struct SQLiteFeedRefreshService {
    typealias Fetcher = (String, FeedHTTPValidators) async throws -> SQLiteFeedFetchResult
    typealias FaviconFetcher = (URL) async -> String?

    private let feedStore: FeedStore
    private let articleStore: ArticleStore
    private let statusStore: ArticleStatusStore
    private let logStore: FeedLogStore
    private let tagStore: TagStore
    private let ruleSnapshots: [RuleEngine.RuleSnapshot]
    private let now: () -> Date
    private let fetcher: Fetcher
    private let discoverFaviconURL: FaviconFetcher

    init(
        database: FeedivoDatabase,
        ruleSnapshots: [RuleEngine.RuleSnapshot] = [],
        now: @escaping () -> Date = Date.init,
        discoverFaviconURL: @escaping FaviconFetcher = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        fetcher: @escaping Fetcher = SQLiteFeedRefreshService.defaultFetcher
    ) {
        self.feedStore = FeedStore(database: database)
        self.articleStore = ArticleStore(database: database)
        self.statusStore = ArticleStatusStore(database: database)
        self.logStore = FeedLogStore(database: database)
        self.tagStore = TagStore(database: database)
        self.ruleSnapshots = ruleSnapshots
        self.now = now
        self.fetcher = fetcher
        self.discoverFaviconURL = discoverFaviconURL
    }
```

with:
```swift
struct SQLiteFeedRefreshService {
    typealias Fetcher = (String, FeedHTTPValidators) async throws -> SQLiteFeedFetchResult
    typealias FaviconFetcher = (URL) async -> String?
    typealias SpotlightIndexer = ([ArticleListSnapshot]) -> Void

    private let database: FeedivoDatabase
    private let feedStore: FeedStore
    private let articleStore: ArticleStore
    private let statusStore: ArticleStatusStore
    private let logStore: FeedLogStore
    private let tagStore: TagStore
    private let ruleSnapshots: [RuleEngine.RuleSnapshot]
    private let now: () -> Date
    private let discoverFaviconURL: FaviconFetcher
    private let indexForSpotlight: SpotlightIndexer
    private let fetcher: Fetcher

    init(
        database: FeedivoDatabase,
        ruleSnapshots: [RuleEngine.RuleSnapshot] = [],
        now: @escaping () -> Date = Date.init,
        discoverFaviconURL: @escaping FaviconFetcher = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        indexForSpotlight: @escaping SpotlightIndexer = { SpotlightIndexingService.indexArticles($0) },
        fetcher: @escaping Fetcher = SQLiteFeedRefreshService.defaultFetcher
    ) {
        self.database = database
        self.feedStore = FeedStore(database: database)
        self.articleStore = ArticleStore(database: database)
        self.statusStore = ArticleStatusStore(database: database)
        self.logStore = FeedLogStore(database: database)
        self.tagStore = TagStore(database: database)
        self.ruleSnapshots = ruleSnapshots
        self.now = now
        self.discoverFaviconURL = discoverFaviconURL
        self.indexForSpotlight = indexForSpotlight
        self.fetcher = fetcher
    }
```

Then, inside `refresh(feedID:)`, in the `.updated` case, replace:
```swift
                let upsertResult = try articleStore.upsert(inputs)
                let recentCutoff = now().addingTimeInterval(-48 * 60 * 60)
```

with:
```swift
                let upsertResult = try articleStore.upsert(inputs)
                logIfThrows(context: "Spotlight-Indexierung nach Feed-Refresh") {
                    guard !upsertResult.insertedArticleIDs.isEmpty else {
                        return
                    }
                    let snapshotsToIndex = try ArticleDatabase(database: database).fetchArticles(
                        articleIDs: Set(upsertResult.insertedArticleIDs)
                    )
                    indexForSpotlight(snapshotsToIndex)
                }
                let recentCutoff = now().addingTimeInterval(-48 * 60 * 60)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests -parallel-testing-enabled NO`
Expected: PASS (all tests in this suite, including the 2 new ones and the 5 pre-existing trailing-closure tests)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/SQLiteFeedRefreshService.swift FeedivoTests/SQLiteFeedRefreshServiceTests.swift
git commit -m "Feature: Neue Artikel aus Feed-Refresh werden in Spotlight indexiert"
```

---

### Task 5: Indexierungs-Hook in SQLiteFeedSubscriptionService

**Files:**
- Modify: `Feedivo/Services/SQLiteFeedSubscriptionService.swift`
- Test: `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift`

**Interfaces:**
- Consumes: `SpotlightIndexingService.indexArticles(_:userDefaults:index:)` (Task 2), `ArticleDatabase(database:).fetchArticles(articleIDs:)` (existing), `logIfThrows(context:_:)` (existing)
- Produces: new init parameter `indexForSpotlight: @escaping SpotlightIndexer` on `SQLiteFeedSubscriptionService`, where `typealias SpotlightIndexer = ([ArticleListSnapshot]) -> Void`

- [ ] **Step 1: Write the failing test**

Add to `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift` (inside the `SQLiteFeedSubscriptionServiceTests` struct):

```swift
    @MainActor
    @Test func addFeedIndexiertNeueArtikelInSpotlight() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        var indexedSnapshots: [ArticleListSnapshot] = []
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(
                    sourceURL: url,
                    title: "Feed",
                    description: nil,
                    articles: [
                        ParsedArticle(
                            title: "Artikel",
                            sourceID: "one",
                            link: nil,
                            summary: "Zusammenfassung",
                            content: nil,
                            publishedAt: nil,
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil },
            indexForSpotlight: { indexedSnapshots.append(contentsOf: $0) }
        )

        _ = try await service.addFeed(urlString: "https://example.com/feed.xml")

        #expect(indexedSnapshots.count == 1)
        #expect(indexedSnapshots.first?.title == "Artikel")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests -parallel-testing-enabled NO`
Expected: Build failure — `indexForSpotlight` init parameter does not exist yet.

- [ ] **Step 3: Write the implementation**

In `Feedivo/Services/SQLiteFeedSubscriptionService.swift`, modify the type declarations and init. Replace:

```swift
@MainActor
struct SQLiteFeedSubscriptionService {
    typealias FeedFetcher = (String) async throws -> ParsedFeed
    typealias FaviconFetcher = (URL) async -> String?
    typealias ArticleUpserter = ([ArticleUpsertInput]) throws -> ArticleUpsertResult
    typealias AfterArticleUpsertHook = () throws -> Void
    typealias AfterOPMLTagsSaveHook = () throws -> Void

    private let database: FeedivoDatabase
    private let fetchFeed: FeedFetcher
    private let discoverFaviconURL: FaviconFetcher
    private let articleUpsert: ArticleUpserter
    private let afterArticleUpsert: AfterArticleUpsertHook
    private let afterOPMLTagsSave: AfterOPMLTagsSaveHook
    private let userDefaults: UserDefaults

    init(
        database: FeedivoDatabase,
        fetchFeed: @escaping FeedFetcher = FeedService.fetchFeed,
        discoverFaviconURL: @escaping FaviconFetcher = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        articleUpsert: ArticleUpserter? = nil,
        afterArticleUpsert: @escaping AfterArticleUpsertHook = {},
        afterOPMLTagsSave: @escaping AfterOPMLTagsSaveHook = {},
        userDefaults: UserDefaults = .standard
    ) {
        self.database = database
        self.fetchFeed = fetchFeed
        self.discoverFaviconURL = discoverFaviconURL
        self.articleUpsert = articleUpsert ?? { inputs in
            try ArticleStore(database: database).upsert(inputs)
        }
        self.afterArticleUpsert = afterArticleUpsert
        self.afterOPMLTagsSave = afterOPMLTagsSave
        self.userDefaults = userDefaults
    }
```

with:

```swift
@MainActor
struct SQLiteFeedSubscriptionService {
    typealias FeedFetcher = (String) async throws -> ParsedFeed
    typealias FaviconFetcher = (URL) async -> String?
    typealias ArticleUpserter = ([ArticleUpsertInput]) throws -> ArticleUpsertResult
    typealias AfterArticleUpsertHook = () throws -> Void
    typealias AfterOPMLTagsSaveHook = () throws -> Void
    typealias SpotlightIndexer = ([ArticleListSnapshot]) -> Void

    private let database: FeedivoDatabase
    private let fetchFeed: FeedFetcher
    private let discoverFaviconURL: FaviconFetcher
    private let articleUpsert: ArticleUpserter
    private let afterArticleUpsert: AfterArticleUpsertHook
    private let afterOPMLTagsSave: AfterOPMLTagsSaveHook
    private let indexForSpotlight: SpotlightIndexer
    private let userDefaults: UserDefaults

    init(
        database: FeedivoDatabase,
        fetchFeed: @escaping FeedFetcher = FeedService.fetchFeed,
        discoverFaviconURL: @escaping FaviconFetcher = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        articleUpsert: ArticleUpserter? = nil,
        afterArticleUpsert: @escaping AfterArticleUpsertHook = {},
        afterOPMLTagsSave: @escaping AfterOPMLTagsSaveHook = {},
        indexForSpotlight: @escaping SpotlightIndexer = { SpotlightIndexingService.indexArticles($0) },
        userDefaults: UserDefaults = .standard
    ) {
        self.database = database
        self.fetchFeed = fetchFeed
        self.discoverFaviconURL = discoverFaviconURL
        self.articleUpsert = articleUpsert ?? { inputs in
            try ArticleStore(database: database).upsert(inputs)
        }
        self.afterArticleUpsert = afterArticleUpsert
        self.afterOPMLTagsSave = afterOPMLTagsSave
        self.indexForSpotlight = indexForSpotlight
        self.userDefaults = userDefaults
    }
```

Then, inside `addFeed(urlString:refreshIntervalMinutes:folderName:)`, replace:
```swift
            _ = try articleUpsert(articleInputs)
            try afterArticleUpsert()
            let unreadCount = try ArticleStatusStore(database: database).unreadCount(feedID: feedID)
```

with:
```swift
            let upsertResult = try articleUpsert(articleInputs)
            try afterArticleUpsert()
            logIfThrows(context: "Spotlight-Indexierung nach Feed-Abo") {
                guard !upsertResult.insertedArticleIDs.isEmpty else {
                    return
                }
                let snapshotsToIndex = try ArticleDatabase(database: database).fetchArticles(
                    articleIDs: Set(upsertResult.insertedArticleIDs)
                )
                indexForSpotlight(snapshotsToIndex)
            }
            let unreadCount = try ArticleStatusStore(database: database).unreadCount(feedID: feedID)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests -parallel-testing-enabled NO`
Expected: PASS (all tests in this suite, including the new one)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/SQLiteFeedSubscriptionService.swift FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift
git commit -m "Feature: Neue Artikel aus manuellem Feed-Abo werden in Spotlight indexiert"
```

---

### Task 6: Deindexierungs-Hooks (Einzelartikel + Bereinigung)

**Files:**
- Modify: `Feedivo/ViewModels/SQLiteFeedArticleListState.swift`
- Modify: `Feedivo/Services/ArticleRetentionCleanupService.swift`
- Test: `FeedivoTests/SQLiteFeedArticleListStateTests.swift`
- Test: `FeedivoTests/ArticleRetentionCleanupServiceTests.swift`

**Interfaces:**
- Consumes: `SpotlightIndexingService.deindexArticles(ids:index:)` (Task 2)
- Produces: new optional parameter `deindexForSpotlight: ([String]) -> Void` on `SQLiteFeedArticleListState.deleteArticle(articleID:database:)` and `ArticleRetentionCleanupService.removeExpiredSQLiteArticles(...)`

- [ ] **Step 1: Write the failing tests**

Add to `FeedivoTests/SQLiteFeedArticleListStateTests.swift` (inside the `SQLiteFeedArticleListStateTests` struct, near the existing `listStateLoeschtArtikelUndEntferntIhnAusRows`):

```swift
    @Test func listStateDeindexiertGeloeschtenArtikelAusSpotlight() async throws {
        let (database, firstID, _) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()
        var deindexedIDs: [String] = []

        state.load(feedID: "feed-1", database: database, selectedArticleID: firstID)
        await waitForLoad(state)

        let succeeded = state.deleteArticle(
            articleID: firstID,
            database: database,
            deindexForSpotlight: { deindexedIDs.append(contentsOf: $0) }
        )

        #expect(succeeded)
        #expect(deindexedIDs == [firstID])
    }
```

Add to `FeedivoTests/ArticleRetentionCleanupServiceTests.swift` (inside the test struct, near `sqliteCleanupLoeschtAlteArtikelUndKorrigiertFeedZaehler`):

```swift
    @Test func sqliteCleanupDeindexiertGeloeschteArtikelAusSpotlight() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1))
        let expiredID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Alt", publishedAt: oldDate)
        )
        var deindexedIDs: [String] = []

        _ = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            now: now,
            deindexForSpotlight: { deindexedIDs.append(contentsOf: $0) }
        )

        #expect(deindexedIDs == [expiredID])
    }

    @Test func sqliteCleanupRuftDeindexNichtAufWennNichtsGeloeschtWurde() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed"))
        _ = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Neu", publishedAt: now)
        )
        var deindexCallCount = 0

        _ = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            now: now,
            deindexForSpotlight: { _ in deindexCallCount += 1 }
        )

        #expect(deindexCallCount == 0)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -parallel-testing-enabled NO`
Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -parallel-testing-enabled NO`
Expected: Both build-fail — `deindexForSpotlight` parameters don't exist yet.

- [ ] **Step 3: Write the implementation**

In `Feedivo/ViewModels/SQLiteFeedArticleListState.swift`, replace:

```swift
    @discardableResult
    func deleteArticle(articleID: String, database: FeedivoDatabase) -> Bool {
        do {
            try database.write { db in
                try db.execute(sql: "DELETE FROM articles WHERE id = ?", arguments: [articleID])
            }
            if let deletedRow = rows.first(where: { $0.id == articleID }),
               !deletedRow.isRead,
               !deletedRow.isHidden {
                totalUnreadCount = max(0, totalUnreadCount - 1)
            }
            rows.removeAll { $0.id == articleID }
            return true
        } catch {
            loadState = .failed(error.localizedDescription)
            return false
        }
    }
```

with:

```swift
    @discardableResult
    func deleteArticle(
        articleID: String,
        database: FeedivoDatabase,
        deindexForSpotlight: ([String]) -> Void = { SpotlightIndexingService.deindexArticles(ids: $0) }
    ) -> Bool {
        do {
            try database.write { db in
                try db.execute(sql: "DELETE FROM articles WHERE id = ?", arguments: [articleID])
            }
            deindexForSpotlight([articleID])
            if let deletedRow = rows.first(where: { $0.id == articleID }),
               !deletedRow.isRead,
               !deletedRow.isHidden {
                totalUnreadCount = max(0, totalUnreadCount - 1)
            }
            rows.removeAll { $0.id == articleID }
            return true
        } catch {
            loadState = .failed(error.localizedDescription)
            return false
        }
    }
```

In `Feedivo/Services/ArticleRetentionCleanupService.swift`, replace the `removeExpiredSQLiteArticles` function:

```swift
    @MainActor
    @discardableResult
    static func removeExpiredSQLiteArticles(
        database: FeedivoDatabase,
        isEnabled: Bool,
        retentionDays: Int,
        minimumArticlesPerFeed: Int = ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
        includeProtectedArticles: Bool = false,
        now: Date = Date()
    ) throws -> Int {
        let globalConfiguration = ArticleRetentionConfiguration(
            isEnabled: isEnabled,
            retentionDays: retentionDays,
            minimumArticlesPerFeed: minimumArticlesPerFeed,
            includeProtectedArticles: includeProtectedArticles,
            now: now
        )
        let feedConfigurations = try sqliteFeedRetentionConfigurations(
            in: database,
            globalConfiguration: globalConfiguration,
            now: now
        )

        let removedCount = try database.write { db in
            let candidates = try SQLiteArticleRetentionCandidate.fetchAll(db, sql: """
                SELECT
                    a.id,
                    a.feedID,
                    a.publishedAt,
                    a.arrivedAt,
                    s.isStarred,
                    s.isArchived,
                    s.isRead,
                    s.isHidden
                FROM articles a
                JOIN article_statuses s ON s.articleID = a.id
                """)

            let protectedArticleIDs = protectedSQLiteArticleIDs(
                candidates,
                feedConfigurations: feedConfigurations,
                globalConfiguration: globalConfiguration
            )
            let expiredCandidates = candidates.filter { candidate in
                let configuration = feedConfigurations[candidate.feedID] ?? globalConfiguration
                guard !protectedArticleIDs.contains(candidate.id) else {
                    return false
                }

                return shouldRemove(
                    candidate,
                    cutoffDate: configuration.cutoffDate,
                    isEnabled: configuration.isEnabled,
                    includeProtectedArticles: configuration.includeProtectedArticles
                )
            }

            guard !expiredCandidates.isEmpty else {
                return 0
            }

            let articleIDs = expiredCandidates.map(\.id)
            let changedFeedIDs = Set(expiredCandidates.map(\.feedID))

            try saveSQLiteIdentityHistory(for: articleIDs, now: now, db: db)
            try deleteSQLiteArticles(articleIDs, db: db)
            try recalculateSQLiteUnreadCounts(for: changedFeedIDs, db: db)

            return articleIDs.count
        }

        if removedCount > 0 {
            SQLiteDataInvalidation.bumpStatusVersion()
        }

        return removedCount
    }
```

with:

```swift
    @MainActor
    @discardableResult
    static func removeExpiredSQLiteArticles(
        database: FeedivoDatabase,
        isEnabled: Bool,
        retentionDays: Int,
        minimumArticlesPerFeed: Int = ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
        includeProtectedArticles: Bool = false,
        now: Date = Date(),
        deindexForSpotlight: ([String]) -> Void = { SpotlightIndexingService.deindexArticles(ids: $0) }
    ) throws -> Int {
        let globalConfiguration = ArticleRetentionConfiguration(
            isEnabled: isEnabled,
            retentionDays: retentionDays,
            minimumArticlesPerFeed: minimumArticlesPerFeed,
            includeProtectedArticles: includeProtectedArticles,
            now: now
        )
        let feedConfigurations = try sqliteFeedRetentionConfigurations(
            in: database,
            globalConfiguration: globalConfiguration,
            now: now
        )

        var removedArticleIDs: [String] = []
        let removedCount = try database.write { db in
            let candidates = try SQLiteArticleRetentionCandidate.fetchAll(db, sql: """
                SELECT
                    a.id,
                    a.feedID,
                    a.publishedAt,
                    a.arrivedAt,
                    s.isStarred,
                    s.isArchived,
                    s.isRead,
                    s.isHidden
                FROM articles a
                JOIN article_statuses s ON s.articleID = a.id
                """)

            let protectedArticleIDs = protectedSQLiteArticleIDs(
                candidates,
                feedConfigurations: feedConfigurations,
                globalConfiguration: globalConfiguration
            )
            let expiredCandidates = candidates.filter { candidate in
                let configuration = feedConfigurations[candidate.feedID] ?? globalConfiguration
                guard !protectedArticleIDs.contains(candidate.id) else {
                    return false
                }

                return shouldRemove(
                    candidate,
                    cutoffDate: configuration.cutoffDate,
                    isEnabled: configuration.isEnabled,
                    includeProtectedArticles: configuration.includeProtectedArticles
                )
            }

            guard !expiredCandidates.isEmpty else {
                return 0
            }

            let articleIDs = expiredCandidates.map(\.id)
            let changedFeedIDs = Set(expiredCandidates.map(\.feedID))

            try saveSQLiteIdentityHistory(for: articleIDs, now: now, db: db)
            try deleteSQLiteArticles(articleIDs, db: db)
            try recalculateSQLiteUnreadCounts(for: changedFeedIDs, db: db)

            removedArticleIDs = articleIDs
            return articleIDs.count
        }

        if removedCount > 0 {
            SQLiteDataInvalidation.bumpStatusVersion()
            deindexForSpotlight(removedArticleIDs)
        }

        return removedCount
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -parallel-testing-enabled NO`
Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -parallel-testing-enabled NO`
Expected: Both PASS (all tests in both suites, including the 3 new ones)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/ViewModels/SQLiteFeedArticleListState.swift Feedivo/Services/ArticleRetentionCleanupService.swift FeedivoTests/SQLiteFeedArticleListStateTests.swift FeedivoTests/ArticleRetentionCleanupServiceTests.swift
git commit -m "Feature: Geloeschte Artikel werden aus Spotlight deindexiert (Einzelloeschen + Bereinigung)"
```

---

### Task 7: App-Level Wiring — Settings-Toggle, Backfill, L10n

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift`
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `SpotlightIndexingSettings.isEnabledKey`/`.defaultIsEnabled` (Task 1), `SpotlightIndexingService.ensureBackfillIfNeeded(database:)`/`.deindexAll()` (Task 2), `logIfThrows(context:_:)` (existing)

This task has no dedicated unit test — it wires existing, already-tested logic (Tasks 1+2) into SwiftUI `@AppStorage`/`.onChange`/`.task`, matching the established, untested convention for this kind of App-level wiring (see `articleRetentionIsEnabled` in the same file, and the documented precedent that "Master-Schalter-Gate selbst ungetestet mangels Mock-Seam" was accepted for the Notification-Settings feature). Verification is via build success + the manual live-test checklist at the end of this task.

- [ ] **Step 1: Add L10n keys**

In `Feedivo/Resources/L10n.swift`, find this line:
```swift
    static let settingsRestoreArticleWindowsDescription = LocalizedStringKey("settings.restoreArticleWindows.description")
```

Add immediately after it:
```swift
    static let settingsSpotlightSection = LocalizedStringKey("settings.spotlight.section")
    static let settingsSpotlightToggleTitle = LocalizedStringKey("settings.spotlight.toggle.title")
    static let settingsSpotlightToggleDescription = LocalizedStringKey("settings.spotlight.toggle.description")
```

- [ ] **Step 2: Add the Settings-UI toggle**

In `Feedivo/Views/Settings/SettingsView.swift`, inside `private struct GeneralSettingsView`, add a new `@AppStorage` property near the top of the struct (after the existing `@AppStorage(ArticleWindowSettings.restoreOpenArticleWindowsOnLaunchKey)` property):

```swift
    @AppStorage(ArticleWindowSettings.restoreOpenArticleWindowsOnLaunchKey)
    private var restoreOpenArticleWindowsOnLaunch = ArticleWindowSettings.defaultRestoreOpenArticleWindowsOnLaunch

    @AppStorage(SpotlightIndexingSettings.isEnabledKey)
    private var spotlightIndexingIsEnabled = SpotlightIndexingSettings.defaultIsEnabled
```

Then find the end of the "System" `SettingsBlock` (closing brace right after the `restoreOpenArticleWindowsOnLaunch` `SettingRow`):

```swift
                SettingRow(
                    title: L10n.settingsRestoreArticleWindowsTitle,
                    description: L10n.settingsRestoreArticleWindowsDescription
                ) {
                    Toggle("", isOn: $restoreOpenArticleWindowsOnLaunch)
                        .labelsHidden()
                }
            }

            CacheSettingsView()
```

Insert a new `SettingsBlock` between the closing `}` of the System block and `CacheSettingsView()`:

```swift
                SettingRow(
                    title: L10n.settingsRestoreArticleWindowsTitle,
                    description: L10n.settingsRestoreArticleWindowsDescription
                ) {
                    Toggle("", isOn: $restoreOpenArticleWindowsOnLaunch)
                        .labelsHidden()
                }
            }

            SettingsBlock(eyebrow: L10n.settingsSpotlightSection) {
                SettingRow(
                    title: L10n.settingsSpotlightToggleTitle,
                    description: L10n.settingsSpotlightToggleDescription
                ) {
                    Toggle("", isOn: $spotlightIndexingIsEnabled)
                        .labelsHidden()
                }
            }

            CacheSettingsView()
```

- [ ] **Step 3: Wire backfill + toggle side-effects in FeedivoApp.swift**

In `Feedivo/App/FeedivoApp.swift`, add a new `@AppStorage` property after `articleRetentionIncludesProtectedArticles`:

```swift
    @AppStorage(ArticleRetentionSettings.includesProtectedArticlesKey)
    private var articleRetentionIncludesProtectedArticles = ArticleRetentionSettings.defaultIncludesProtectedArticles

    @AppStorage(SpotlightIndexingSettings.isEnabledKey)
    private var spotlightIndexingIsEnabled = SpotlightIndexingSettings.defaultIsEnabled
```

In the `.task { }` block, replace:
```swift
                .task {
                    guard databaseLoadState.initializationError == nil else {
                        return
                    }
                    backfillStoredArticleMetadataIfNeeded()
                    trimImageCacheToSelectedLimit()
                    scheduleBackgroundRefresh()
                }
```

with:
```swift
                .task {
                    guard databaseLoadState.initializationError == nil else {
                        return
                    }
                    backfillStoredArticleMetadataIfNeeded()
                    trimImageCacheToSelectedLimit()
                    ensureSpotlightBackfillIfNeeded()
                    scheduleBackgroundRefresh()
                }
```

Add a new `.onChange` modifier after the existing `.onChange(of: articleRetentionIncludesProtectedArticles) { ... }` block:
```swift
                .onChange(of: articleRetentionIncludesProtectedArticles) {
                    cleanupExpiredArticlesIfNeeded()
                }
                .onChange(of: spotlightIndexingIsEnabled) {
                    handleSpotlightIndexingToggleChange()
                }
```

Add two new private methods after `cleanupExpiredArticlesIfNeeded()`:
```swift
    @MainActor
    private func cleanupExpiredArticlesIfNeeded() {
        guard databaseLoadState.initializationError == nil else {
            return
        }
        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: feedivoDatabase,
            isEnabled: articleRetentionIsEnabled,
            retentionDays: articleRetentionDays,
            minimumArticlesPerFeed: articleRetentionMinimumArticlesPerFeed,
            includeProtectedArticles: articleRetentionIncludesProtectedArticles
        )
    }

    @MainActor
    private func ensureSpotlightBackfillIfNeeded() {
        guard databaseLoadState.initializationError == nil else {
            return
        }
        logIfThrows(context: "Spotlight-Backfill") {
            try SpotlightIndexingService.ensureBackfillIfNeeded(database: feedivoDatabase)
        }
    }

    @MainActor
    private func handleSpotlightIndexingToggleChange() {
        if spotlightIndexingIsEnabled {
            ensureSpotlightBackfillIfNeeded()
        } else {
            SpotlightIndexingService.deindexAll()
        }
    }
```

- [ ] **Step 4: Add L10n catalog entries**

`xcodebuild build` alone will NOT create catalog entries for the 3 new indirect `L10n` keys (known gotcha). Add them manually with a Python script:

```bash
python3 << 'PYEOF'
path = "Feedivo/Resources/Localizable.xcstrings"
with open(path, encoding="utf-8") as f:
    content = f.read()

def block(key, de, en, fr, it):
    return (
        f'    "{key}" : {{\n'
        f'      "localizations" : {{\n'
        f'        "de" : {{\n'
        f'          "stringUnit" : {{\n'
        f'            "state" : "translated",\n'
        f'            "value" : "{de}"\n'
        f'          }}\n'
        f'        }},\n'
        f'        "en" : {{\n'
        f'          "stringUnit" : {{\n'
        f'            "state" : "translated",\n'
        f'            "value" : "{en}"\n'
        f'          }}\n'
        f'        }},\n'
        f'        "fr" : {{\n'
        f'          "stringUnit" : {{\n'
        f'            "state" : "translated",\n'
        f'            "value" : "{fr}"\n'
        f'          }}\n'
        f'        }},\n'
        f'        "it" : {{\n'
        f'          "stringUnit" : {{\n'
        f'            "state" : "translated",\n'
        f'            "value" : "{it}"\n'
        f'          }}\n'
        f'        }}\n'
        f'      }}\n'
        f'    }},\n'
    )

section = block("settings.spotlight.section", "Suche", "Search", "Recherche", "Ricerca")
toggle_title = block(
    "settings.spotlight.toggle.title",
    "Artikel in Spotlight indexieren",
    "Index Articles in Spotlight",
    "Indexer les articles dans Spotlight",
    "Indicizza articoli in Spotlight"
)
toggle_description = block(
    "settings.spotlight.toggle.description",
    "Erm\\u00f6glicht, Artikel \\u00fcber die macOS-Systemsuche zu finden. Rein lokale Indexierung, kein Cloud-Upload.",
    "Lets you find articles via macOS system search. Indexing happens entirely on-device, nothing is uploaded.",
    "Permet de retrouver les articles via la recherche syst\\u00e8me macOS. Indexation enti\\u00e8rement locale, aucun envoi dans le cloud.",
    "Consente di trovare gli articoli tramite la ricerca di sistema di macOS. Indicizzazione interamente locale, nessun caricamento nel cloud."
)

# Insert alphabetically before a neighboring, already-present key that sorts
# right after "settings.spotlight.*" (e.g. "settings.sync." or
# "settings.system", whichever exists in this catalog).
anchor = None
for candidate in ['"settings.sync.', '"settings.system']:
    if candidate in content:
        anchor = candidate
        break
assert anchor is not None, "no anchor key found — inspect Localizable.xcstrings manually"

anchor_line_start = content.index(f'    {anchor}')
content = content[:anchor_line_start] + section + toggle_title + toggle_description + content[anchor_line_start:]

with open(path, "w", encoding="utf-8") as f:
    f.write(content)

print("done")
PYEOF
```

After running, verify with:
```bash
python3 -c "
import json
with open('Feedivo/Resources/Localizable.xcstrings', encoding='utf-8') as f:
    data = json.load(f)
for k in ['settings.spotlight.section', 'settings.spotlight.toggle.title', 'settings.spotlight.toggle.description']:
    print(k, '=>', data['strings'][k]['localizations']['en']['stringUnit']['value'])
print('JSON VALID')
"
```
Expected: all 3 keys print their English value, and `JSON VALID` at the end (confirms well-formed JSON — if the anchor-based insertion produced invalid JSON, `json.load` will raise instead).

If neither anchor key exists in the file, open `Feedivo/Resources/Localizable.xcstrings`, find the alphabetically correct spot among the existing `"settings.*"` keys by hand, and insert the same three blocks there directly with a text editor, then re-run the verification script above.

- [ ] **Step 5: Build and verify**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

Run a broader scoped regression check (settings + retention + refresh + subscription + app delegate related suites all touched by this plan):
```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/SpotlightIndexingSettingsTests \
  -only-testing:FeedivoTests/SpotlightIndexingServiceTests \
  -only-testing:FeedivoTests/SpotlightContinuationParserTests \
  -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests \
  -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests \
  -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests \
  -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests \
  -parallel-testing-enabled NO
```
Expected: PASS across all suites (pre-existing, already-documented failures in OTHER suites like `FeedivoAppSceneConfigurationTests` are out of scope and unaffected by this plan).

- [ ] **Step 6: Commit**

```bash
git add Feedivo/App/FeedivoApp.swift Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature: Spotlight-Einstellungen-Schalter + Start-Backfill + An/Aus-Seiteneffekte verdrahtet"
```

- [ ] **Step 7: Manual live-verification checklist (not automatable — no computer-use for native macOS apps in this environment)**

After building and running the app locally, verify by hand:
1. Settings → Allgemein zeigt den neuen Abschnitt "Suche" mit Schalter "Artikel in Spotlight indexieren", Standard AN.
2. Nach App-Start (oder Feed-Refresh) einen bekannten Artikeltitel in macOS Spotlight (⌘+Leertaste) suchen — Feedivo-Resultat erscheint.
3. Klick auf das Spotlight-Resultat öffnet Feedivo direkt beim betreffenden Artikel.
4. Schalter ausschalten → derselbe Artikeltitel verschwindet aus Spotlight (kurze Verzögerung durch asynchrone `CSSearchableIndex`-Verarbeitung ist normal).
5. Schalter wieder einschalten → Artikel taucht nach kurzer Zeit erneut in Spotlight auf (Backfill läuft erneut).
6. Einen Artikel in der App löschen (Kontextmenü) → verschwindet aus Spotlight.
7. Sollte Core Spotlight unter App-Sandbox unerwartet einen `NSCocoaErrorDomain`/Berechtigungsfehler in der Konsole (`AppLogger`/Console.app, Kategorie "DataAccess") loggen, das genauso wie den bereits dokumentierten `UTType(exportedAs:)`-Info.plist-Gotcha behandeln: ggf. fehlt ein Info.plist-Eintrag, den Apples Dokumentation für reine In-App-Nutzung nicht immer klar verlangt — per `plutil -p` auf das gebaute App-Bundle prüfen, falls Punkt 2 nicht funktioniert.

---

## Self-Review Notes

- **Spec coverage:** Alle drei FEATURES.md-9.3-Anforderungen abgedeckt — Indexierung (Tasks 4/5/7-Backfill), Deep-Link-Rückweg (Task 3), Einstellungen-Toggle (Task 7). Zusätzlich: Deindexierung (Task 6, nicht explizit in FEATURES.md gefordert, aber notwendig, damit gelöschte Artikel nicht als tote Spotlight-Treffer liegen bleiben — im Spec bereits als Teil des Designs festgehalten).
- **Placeholder scan:** Keine TBD/TODO, jeder Schritt zeigt vollständigen Code.
- **Type consistency:** `SpotlightIndexer`-Typalias (`([ArticleListSnapshot]) -> Void`) konsistent in Task 4 und Task 5 benannt; `deindexForSpotlight: ([String]) -> Void` konsistent in Task 6 an beiden Stellen; `SpotlightIndexWriting`-Protokoll nur in Task 2 definiert und von Task 4–6 nie direkt referenziert (sie nutzen die Closure-Ebene, nicht das Protokoll) — bewusst zwei Abstraktionsebenen, siehe Architecture-Absatz oben.
