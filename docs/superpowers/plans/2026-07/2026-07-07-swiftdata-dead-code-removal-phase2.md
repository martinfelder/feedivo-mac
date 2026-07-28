# Toten SwiftData-Code entfernen — Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die 6 Dateien aus Phase 1 bereinigen, die sowohl toten als auch aktiven Code enthalten — methodengenau statt nur typgenau, ohne die weiterhin aktiven SQLite-Pfade zu beschädigen.

**Architecture:** Jede Task betrifft genau eine Produktionsdatei (+ ihre direkten Testdateien). Es werden entweder ganze tote Top-Level-Typen gelöscht, oder einzelne tote Methoden/Overloads aus sonst aktiven Typen entfernt. Keine neuen Abstraktionen, keine Verhaltensänderung an lebendem Code.

**Tech Stack:** Swift, SwiftUI (macOS 14+), SwiftData (nur noch in den zu entfernenden Legacy-Pfaden), GRDB/SQLite (Produktivpfad), Swift Testing (`@Test`/`#expect`).

## Global Constraints

- Kein neuer Testcode nötig — reine Lösch-/Extraktions-Operation (Spec: "Kein neuer Testcode nötig").
- Erfolgskriterium: Build bleibt grün; bestehende, **gescopte** Tests bleiben grün (NICHT die volle
  ungefilterte Suite via `xcodebuild test` ohne `-only-testing:` — die hängt nachweislich, ein
  bekanntes, unabhängiges Infrastrukturproblem dieses Projekts).
- Insbesondere müssen grün bleiben: Tests für `ArticleSearchWindowView`, `ArticleStore.searchArticles`,
  `SQLiteReaderState`, `SidebarView`, `ArticleRetentionCleanupService.removeExpiredSQLiteArticles`.
- `ArticleSearchField`, `ArticleSearchDateFilter`, `ArticleSearchStatusFilter`, `ArticleSearchScope`,
  `ArticleSearchWindowState` werden NICHT gelöscht (aktiv) — nur ihre toten Methoden/Geschwistertypen.
  `ArticleSearchScope` insbesondere bleibt vollständig unverändert (Korrektur gegenüber einer ersten
  Einschätzung — siehe Task 6).
- `SidebarBadgeInvalidation` (`bumpDirectTagVersion()`/`directTagVersionKey`) bleibt vollständig
  unangetastet — stark genutzt u. a. von `RuleEngine.swift`, `TagManagerView.swift`,
  `ArticleMetadataInspectorView.swift`, `FeedPropertiesView.swift`, mehreren `@AppStorage`-Stellen.
- `SmartFolderSidebarBadgeKind` bleibt vollständig unangetastet (wurde in einer früheren Session-Arbeit
  `Equatable` + nicht-`private` gemacht, für die Sidebar-Badge-Icons — nicht Teil dieser Phase).
- Die 9 `@Model`-Klassen selbst werden in dieser Phase NICHT angetastet (spätere Phase).
- Reihenfolge der Tasks ist VERBINDLICH, nicht nur eine Empfehlung: Task 1 (SidebarUnreadCount.swift)
  MUSS vor Task 6 (ArticleListQuery.swift) abgeschlossen sein, weil `SidebarUnreadCount.swift:24`
  (in der toten `SidebarTagCount.articleCount`) die einzige verbleibende Produktiv-Referenz auf
  `LegacyArticleListQuery`/`typealias ArticleListQuery` ist. Wird Task 6 vor Task 1 ausgeführt, bricht
  der Build.
- Jeder Task-Implementierer verifiziert vor dem Löschen erneut per `grep` über `Feedivo` und
  `FeedivoTests` (nicht nur Dateiname-Treffer, echte Aufrufe), genau wie in Phase 1 etabliert — die
  Analyse unten wurde sorgfältig verifiziert, aber Phase 1 hat wiederholt gezeigt, dass eine letzte
  Prüfung unmittelbar vor dem Löschen zusätzliche versteckte Abhängigkeiten aufdecken kann.

---

## Task 1: `SidebarUnreadCount.swift` aufräumen

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarUnreadCount.swift`
- Modify: `FeedivoTests/SidebarUnreadCountTests.swift`
- Modify: `FeedivoTests/SmartFolderEngineTests.swift`

**Interfaces:**
- Produces: `SidebarUnreadCount.badgeText(for count: Int) -> String?` bleibt unverändert (aktiv
  genutzt von `SidebarView.swift`, `FeedRowView.swift`).
- Produces: `SmartFolderSidebarBadge.badgeText(for folder: SQLiteSmartFolderSnapshot, snapshot:
  SmartFolderSidebarBadgeSnapshot) -> String?` bleibt unverändert (aktiv genutzt von
  `SidebarView.swift:477`).
- Produces: `SidebarBadgeInvalidation`, `SmartFolderSidebarBadgeKind` bleiben komplett unverändert.
- Consumes: keine Abhängigkeiten von anderen Phase-2-Tasks.

- [ ] **Step 1: Verifikation vor dem Löschen**

Lauf: `grep -rn "SidebarTagCount\|SidebarBadgeCounts\|SidebarStatusBadgeSignature\|SidebarTagBadgeSignature\|SidebarBadgeSignatureBuilder" Feedivo FeedivoTests`

Erwartung: `SidebarTagCount` nur in `SidebarUnreadCount.swift` (Definition),
`FeedivoTests/SidebarUnreadCountTests.swift` (Tests) und als Negations-Check (`!...contains(...)`)
in `FeedivoTests/FeedivoAppSceneConfigurationTests.swift:927`. `SidebarBadgeCounts`,
`SidebarStatusBadgeSignature`, `SidebarTagBadgeSignature`, `SidebarBadgeSignatureBuilder` nur in
`SidebarUnreadCount.swift` (Definition) bzw. `SidebarBadgeSignatureBuilder` zusätzlich nur in
`FeedivoTests/SidebarUnreadCountTests.swift` (Tests). Falls die Treffer davon abweichen: STOPPEN,
nicht weitermachen, Befund melden (BLOCKED).

- [ ] **Step 2: Tote Methoden aus `enum SidebarUnreadCount` entfernen**

In `Feedivo/Views/Sidebar/SidebarUnreadCount.swift` das `enum SidebarUnreadCount` von:

```swift
enum SidebarUnreadCount {
    static func unreadArticleCount(for feed: Feed) -> Int {
        feed.unreadCount
    }

    static func totalUnreadArticleCount(in feeds: [Feed]) -> Int {
        feeds.reduce(0) { total, feed in
            total + feed.unreadCount
        }
    }

    static func badgeText(for count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }
}
```

zu:

```swift
enum SidebarUnreadCount {
    static func badgeText(for count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }
}
```

- [ ] **Step 3: `SidebarTagCount` (ganzer Typ) löschen**

Den kompletten Block

```swift
enum SidebarTagCount {
    @MainActor
    static func articleCount(for tag: Tag, context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Article>(
            predicate: ArticleListQuery.tagPredicate(for: tag, taggedFeeds: tag.feeds ?? [])
        )

        return try context.fetchCount(descriptor)
    }

    @MainActor
    static func badgeText(for tag: Tag, context: ModelContext) throws -> String? {
        try SidebarUnreadCount.badgeText(for: articleCount(for: tag, context: context))
    }
}
```

vollständig entfernen.

- [ ] **Step 4: 3 der 4 `SmartFolderSidebarBadge`-Overloads entfernen**

In `enum SmartFolderSidebarBadge` die drei `badgeText`-Overloads für `feeds:context:`,
`feeds:counts:` und `folder: SmartFolder, snapshot:` plus ihre jeweiligen privaten
`badgeCount`-Helfer entfernen. NUR der letzte Overload-Paar (SQLite-Snapshot-Variante) bleibt.

Von:

```swift
@MainActor
enum SmartFolderSidebarBadge {
    static func badgeText(for folder: SmartFolder, feeds: [Feed], context: ModelContext) -> String? {
        badgeCount(for: folder, feeds: feeds, context: context).flatMap(SidebarUnreadCount.badgeText)
    }

    /// In-Memory-Variante: statt N `fetchCount`-Queries pro Sidebar-Render werden
    /// die Zähler einmal zentral über alle Artikel gebündelt (Batching) und hier
    /// nur noch zugewiesen. Kein Stale-Risiko, da kein Cache.
    static func badgeText(for folder: SmartFolder, feeds: [Feed], counts: SidebarBadgeCounts) -> String? {
        badgeCount(for: folder, feeds: feeds, counts: counts).flatMap(SidebarUnreadCount.badgeText)
    }

    static func badgeText(for folder: SmartFolder, snapshot: SmartFolderSidebarBadgeSnapshot) -> String? {
        badgeCount(for: folder, snapshot: snapshot).flatMap(SidebarUnreadCount.badgeText)
    }

    static func badgeText(for folder: SQLiteSmartFolderSnapshot, snapshot: SmartFolderSidebarBadgeSnapshot) -> String? {
        badgeCount(for: folder, snapshot: snapshot).flatMap(SidebarUnreadCount.badgeText)
    }

    private static func badgeCount(for folder: SmartFolder, feeds: [Feed], context: ModelContext) -> Int? {
        guard let badgeKind = SmartFolderSidebarBadgeKind(folder: folder) else {
            return nil
        }

        switch badgeKind {
        case .unread:
            return SidebarUnreadCount.totalUnreadArticleCount(in: feeds)
        case .starred:
            return try? context.fetchCount(
                FetchDescriptor<Article>(
                    predicate: #Predicate<Article> { article in
                        article.isStarred
                    }
                )
            )
        case .hidden:
            return try? context.fetchCount(
                FetchDescriptor<Article>(
                    predicate: #Predicate<Article> { article in
                        article.isHidden
                    }
                )
            )
        case .saved:
            return try? context.fetchCount(
                FetchDescriptor<Article>(
                    predicate: #Predicate<Article> { article in
                        article.isStarred || article.isArchived
                    }
                )
            )
        }
    }

    private static func badgeCount(for folder: SmartFolder, feeds: [Feed], counts: SidebarBadgeCounts) -> Int? {
        guard let badgeKind = SmartFolderSidebarBadgeKind(folder: folder) else {
            return nil
        }

        switch badgeKind {
        case .unread:
            return SidebarUnreadCount.totalUnreadArticleCount(in: feeds)
        case .starred:
            return counts.starred
        case .hidden:
            return counts.hidden
        case .saved:
            return counts.saved
        }
    }

    private static func badgeCount(for folder: SmartFolder, snapshot: SmartFolderSidebarBadgeSnapshot) -> Int? {
        guard let badgeKind = SmartFolderSidebarBadgeKind(folder: folder) else {
            return nil
        }

        switch badgeKind {
        case .unread:
            return snapshot.unread
        case .starred:
            return snapshot.starred
        case .hidden:
            return snapshot.hidden
        case .saved:
            return snapshot.saved
        }
    }

    private static func badgeCount(for folder: SQLiteSmartFolderSnapshot, snapshot: SmartFolderSidebarBadgeSnapshot) -> Int? {
        guard let badgeKind = SmartFolderSidebarBadgeKind(folder: folder) else {
            return nil
        }

        switch badgeKind {
        case .unread:
            return snapshot.unread
        case .starred:
            return snapshot.starred
        case .hidden:
            return snapshot.hidden
        case .saved:
            return snapshot.saved
        }
    }
}
```

zu:

```swift
@MainActor
enum SmartFolderSidebarBadge {
    static func badgeText(for folder: SQLiteSmartFolderSnapshot, snapshot: SmartFolderSidebarBadgeSnapshot) -> String? {
        badgeCount(for: folder, snapshot: snapshot).flatMap(SidebarUnreadCount.badgeText)
    }

    private static func badgeCount(for folder: SQLiteSmartFolderSnapshot, snapshot: SmartFolderSidebarBadgeSnapshot) -> Int? {
        guard let badgeKind = SmartFolderSidebarBadgeKind(folder: folder) else {
            return nil
        }

        switch badgeKind {
        case .unread:
            return snapshot.unread
        case .starred:
            return snapshot.starred
        case .hidden:
            return snapshot.hidden
        case .saved:
            return snapshot.saved
        }
    }
}
```

- [ ] **Step 5: `SidebarBadgeCounts`, `SidebarStatusBadgeSignature`, `SidebarTagBadgeSignature`, `SidebarBadgeSignatureBuilder` löschen**

Diese vier Deklarationen (mit ihren Doc-Kommentaren) vollständig aus der Datei entfernen:

```swift
/// Zentral gebündelte Badge-Zähler der Sidebar. `tagCounts` liefert pro Tag die
/// Artikel-Anzahl (Tag direkt am Artikel ODER am Feed des Artikels), die
/// Status-Zähler decken die SmartFolder-Badges ab.
struct SidebarBadgeCounts: Equatable {
    let tagCounts: [PersistentIdentifier: Int]
    let starred: Int
    let hidden: Int
    let saved: Int

    static let empty = SidebarBadgeCounts(tagCounts: [:], starred: 0, hidden: 0, saved: 0)
}

/// Signatur für günstige Status-Badges. Sie nutzt nur skalare Artikelwerte und
/// kann deshalb pro Body-Auswertung laufen, ohne Relationships zu faulten.
struct SidebarStatusBadgeSignature: Equatable, Hashable {
    let starredCount: Int
    let hiddenCount: Int
    let savedCount: Int
}

/// Signatur für Tag-Badges. Nur Änderungen, die Tag-Zuordnung oder Feed-Bezug
/// betreffen, invalidieren den Relationship-heavy Tag-Cache.
struct SidebarTagBadgeSignature: Equatable, Hashable {
    let tagFeedMembershipHash: Int
    let feedRefreshHash: Int
    let tagCount: Int
    let feedCount: Int
    let directTagVersion: Int
}

enum SidebarBadgeSignatureBuilder {
    static func statusSignature(articles: [Article]) -> SidebarStatusBadgeSignature {
        var starredCount = 0
        var hiddenCount = 0
        var savedCount = 0

        for article in articles {
            if article.isStarred { starredCount += 1 }
            if article.isHidden { hiddenCount += 1 }
            if article.isStarred || article.isArchived { savedCount += 1 }
        }

        return SidebarStatusBadgeSignature(
            starredCount: starredCount,
            hiddenCount: hiddenCount,
            savedCount: savedCount
        )
    }

    static func tagSignature(
        feeds: [Feed],
        tags: [Tag],
        directTagVersion: Int
    ) -> SidebarTagBadgeSignature {
        SidebarTagBadgeSignature(
            tagFeedMembershipHash: tagFeedMembershipHash(feeds),
            feedRefreshHash: feedRefreshHash(feeds),
            tagCount: tags.count,
            feedCount: feeds.count,
            directTagVersion: directTagVersion
        )
    }

    private static func tagFeedMembershipHash(_ feeds: [Feed]) -> Int {
        var hash = feeds.count
        for feed in feeds {
            hash = hash &* 31 &+ feed.id.hashValue
            for tag in (feed.tags ?? []).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                hash = hash &* 31 &+ tag.id.hashValue
            }
        }
        return hash
    }

    private static func feedRefreshHash(_ feeds: [Feed]) -> Int {
        var hash = feeds.count
        for feed in feeds {
            hash = hash &* 31 &+ feed.id.hashValue
            hash = hash &* 31 &+ (feed.lastRefreshed?.timeIntervalSinceReferenceDate.hashValue ?? 0)
        }
        return hash
    }
}
```

Danach prüfen: wird `import SwiftData` am Dateikopf noch benötigt? Falls nicht (kein `Feed`/`Tag`/
`ModelContext`/`FetchDescriptor`/`#Predicate`/`PersistentIdentifier`-Verweis mehr in der Datei
übrig — nach diesem Schritt bleibt aber noch `SmartFolder`/`SQLiteSmartFolderSnapshot`-Bezug in
`SmartFolderSidebarBadgeKind`, `SmartFolder` ist ein `@Model`, also `import SwiftData` bleibt
nötig), dann NICHT entfernen. Nur entfernen, wenn der Compiler nach dem Build eine
"unused import"-artige Situation zeigt UND kein `@Model`-Typ mehr referenziert wird.

- [ ] **Step 6: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: Build schlägt fehl wegen fehlender Tests, die noch alte Symbole referenzieren (nächste
Schritte beheben das).

- [ ] **Step 7: Toten Test-Code in `FeedivoTests/SidebarUnreadCountTests.swift` entfernen**

Diese Datei testet ausschließlich die in Step 2-5 gelöschten Typen/Methoden
(`SidebarUnreadCount.unreadArticleCount`/`.totalUnreadArticleCount`, `SidebarTagCount`,
`SmartFolderSidebarBadge.badgeText(for:feeds:context:)`, `SidebarBadgeSignatureBuilder`). Lies die
Datei komplett, prüfe für jeden `@Test func`, ob er ausschließlich gelöschte Symbole aufruft. Falls
ja: Test-Funktion entfernen. Falls die Datei danach komplett leer ist (keine verbleibenden
`@Test func`, die nur noch `SidebarUnreadCount.badgeText(for count:)` oder
`SmartFolderSidebarBadge.badgeText(for: SQLiteSmartFolderSnapshot, ...)` testen), lösche die Datei
komplett. Falls einzelne Tests die SQLite-Snapshot-Variante oder `badgeText(for count:)` testen,
diese behalten.

- [ ] **Step 8: Versteckten Test in `FeedivoTests/SmartFolderEngineTests.swift` entfernen**

Der Test `sidebarBadgeCountNutztFeedUnreadCountFuerUngelesenOrdner` (ca. Zeile 134-168) ruft
`SmartFolderSidebarBadge.badgeText(for: unreadFolder, feeds: [firstFeed, secondFeed], context:
context)` auf — den in Step 4 gelöschten Overload. Diese `@Test func` komplett entfernen (Signatur
bis schließende `}`). Alle anderen Tests in dieser Datei bleiben unverändert (sie testen
`SmartFolder`/`RuleEngine`-Matching, nicht die gelöschten Badge-Overloads).

- [ ] **Step 9: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SmartFolderEngineTests -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests 2>&1 | tail -80`
Erwartung: alle Tests grün, außer den 5 bekannten vorbestehenden Fehlschlägen in
`FeedivoAppSceneConfigurationTests` (siehe unten), die NICHT durch diesen Task verursacht sind:
`contentViewNutztSQLiteReaderFuerSQLiteAuswahl`, `settingsFensterBleibtAufGlobalePreferencesReduziert`,
`sidebarAktionenStehenOberhalbDerIntelligentenOrdner`, `sidebarSmartFolderBadgesNutzenSQLiteSnapshots`,
`sqliteReaderBleibtOptischNahAnMainReaderToolbar`. Falls `FeedivoTests/SidebarUnreadCountTests.swift`
in Step 7 gelöscht wurde, entfällt der zugehörige `-only-testing:`-Filter dafür natürlich.

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarUnreadCount.swift FeedivoTests/SidebarUnreadCountTests.swift FeedivoTests/SmartFolderEngineTests.swift
git commit -m "Remove dead SwiftData helpers from SidebarUnreadCount.swift"
```

(Falls `SidebarUnreadCountTests.swift` gelöscht wurde, `git rm` statt `git add` entsprechend
anpassen — `git add -A` für diese drei Pfade deckt beides ab.)

---

## Task 2: `TagViewModel.swift` aufräumen

**Files:**
- Modify: `Feedivo/ViewModels/TagViewModel.swift`
- Delete: `FeedivoTests/TagViewModelTests.swift`

**Interfaces:**
- Produces: `TagViewModel.normalizedTagName(_ name: String?) -> String?` und
  `TagViewModel.normalizedColorHex(_ colorHex: String) -> String` bleiben unverändert (aktiv genutzt
  von `TagManagerView.swift`, `FeedPropertiesView.swift`, `RuleWizardView.swift`,
  `TagColorPalette.swift`).
- Consumes: keine Abhängigkeiten von anderen Phase-2-Tasks.

- [ ] **Step 1: Verifikation vor dem Löschen**

Lauf: `grep -rn "TagViewModel(" Feedivo FeedivoTests`

Erwartung: nur `FeedivoTests/TagViewModelTests.swift` instanziiert `TagViewModel()`. Kein
Produktionscode instanziiert die Klasse. Falls doch: STOPPEN, BLOCKED melden.

- [ ] **Step 2: `TagViewModel.swift` auf die zwei statischen Helfer reduzieren**

Der Typname `TagViewModel` bleibt erhalten (keine Call-Site-Änderungen nötig) — nur die
Instanzsemantik (`@Observable`/`@MainActor`/`final class`) und alle SwiftData-abhängigen
Instanzmethoden/-Helfer fallen weg, aus der Klasse wird ein reines `enum` mit den zwei
statischen Helfern. Ersetze den kompletten Inhalt von `Feedivo/ViewModels/TagViewModel.swift`:

```swift
import Foundation

/// Normalisierungshelfer für Tag-Namen und -Farben, weiterhin von den
/// SQLite-nativen Tag-Views genutzt (`TagManagerView`, `FeedPropertiesView`,
/// `RuleWizardView`, `TagColorPalette`).
enum TagViewModel {
    static func normalizedTagName(_ name: String?) -> String? {
        guard let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedName.isEmpty
        else {
            return nil
        }

        return trimmedName
    }

    static func normalizedColorHex(_ colorHex: String) -> String {
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutHash = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard withoutHash.count == 6,
              Int(withoutHash, radix: 16) != nil
        else {
            return "#888888"
        }

        return "#\(withoutHash.uppercased())"
    }
}
```

Da `TagViewModel.normalizedTagName`/`.normalizedColorHex` bereits heute als `static func`
aufgerufen werden (`TagViewModel.normalizedTagName(...)`, nicht über eine Instanz), bleiben alle 4
Call-Sites (`TagManagerView.swift`, `FeedPropertiesView.swift`, `RuleWizardView.swift`,
`TagColorPalette.swift`) unverändert kompilierbar — keine Anpassung dort nötig.

- [ ] **Step 3: Test-Datei löschen**

```bash
rm FeedivoTests/TagViewModelTests.swift
```

Diese Datei testet ausschließlich die jetzt gelöschten Instanzmethoden
(`createTag`/`renameTag`/`updateColor`/`deleteTag`).

- [ ] **Step 4: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests 2>&1 | tail -80`
Erwartung: grün außer den 5 bekannten vorbestehenden Fehlschlägen (siehe Task 1 Step 9).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/ViewModels/TagViewModel.swift FeedivoTests/TagViewModelTests.swift
git commit -m "Reduce TagViewModel to live static normalization helpers"
```

---

## Task 3: `ArticleListItemSnapshot.swift` aufräumen

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift`

**Interfaces:**
- Produces: `ArticleListItemSnapshot.init(sqliteSnapshot: ArticleListSnapshot)` bleibt unverändert
  (aktiv genutzt von `SQLiteFeedArticleListView.swift`).
- Consumes: keine Abhängigkeiten von anderen Phase-2-Tasks.

- [ ] **Step 1: Verifikation vor dem Löschen**

Lauf: `grep -rn "ArticleListItemSnapshot(article:" Feedivo FeedivoTests`

Erwartung: 0 Treffer außer der Definition selbst. Falls Treffer existieren: STOPPEN, BLOCKED melden.

- [ ] **Step 2: Toten Initializer entfernen**

Ersetze den Inhalt von `Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift`:

```swift
import Foundation

struct ArticleListItemSnapshot: Equatable, Identifiable {
    let id: String
    let title: String
    let summary: String?
    let publishedAt: Date?
    let feedID: UUID?
    let feedTitle: String?
    let isRead: Bool
    let isStarred: Bool
    let isArchived: Bool
    let isHidden: Bool
    let imageURL: String?
    let offlineState: ArticleOfflineState
    let hasOriginalURL: Bool

    init(sqliteSnapshot: ArticleListSnapshot) {
        self.id = sqliteSnapshot.id
        self.title = sqliteSnapshot.title
        self.summary = sqliteSnapshot.summary
        self.publishedAt = sqliteSnapshot.publishedAt
        self.feedID = UUID(uuidString: sqliteSnapshot.feedID)
        self.feedTitle = sqliteSnapshot.feedTitle
        self.isRead = sqliteSnapshot.isRead
        self.isStarred = sqliteSnapshot.isStarred
        self.isArchived = sqliteSnapshot.isArchived
        self.isHidden = sqliteSnapshot.isHidden
        self.imageURL = sqliteSnapshot.imageURL
        self.offlineState = sqliteSnapshot.offlineState
        self.hasOriginalURL = ArticleOriginalURLResolver.hasUsableWebLink(sqliteSnapshot.link)
    }
}
```

Beachte: `import SwiftData` entfällt (nur für den `Article`-Initializer nötig gewesen), `import
Foundation` bleibt (für `UUID`/`Date`).

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED (keine Tests referenzieren den gelöschten Initializer laut Step 1).

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift
git commit -m "Remove dead Article-based initializer from ArticleListItemSnapshot"
```

---

## Task 4: `ArticleRetentionCleanupService.swift` aufräumen

**Files:**
- Modify: `Feedivo/Services/ArticleRetentionCleanupService.swift`
- Modify: `FeedivoTests/ArticleRetentionCleanupServiceTests.swift`

**Interfaces:**
- Produces: `ArticleRetentionCleanupService.removeExpiredSQLiteArticles(...)` (beide Overloads),
  `shouldRemove(_ article: SQLiteArticleRetentionCandidate, ...)` (private, SQLite-Variante) bleiben
  unverändert (aktiv genutzt von `FeedivoApp.swift`, `FeedPropertiesView.swift`,
  `SettingsView.swift`).
- Consumes: keine Abhängigkeiten von anderen Phase-2-Tasks.

- [ ] **Step 1: Verifikation vor dem Löschen**

Lauf: `grep -rn "ArticleRetentionCleanupService\." Feedivo FeedivoTests`

Erwartung: `removeExpiredArticles(` nur in `FeedivoTests/ArticleRetentionCleanupServiceTests.swift`
(6 Aufrufe, keine Produktion). `removeExpiredSQLiteArticles(` in `FeedivoApp.swift`,
`FeedPropertiesView.swift`, `SettingsView.swift` plus mehreren Tests. Falls
`removeExpiredArticles(` irgendwo in Produktionscode auftaucht: STOPPEN, BLOCKED melden.

- [ ] **Step 2: Toten SwiftData-Pfad + seine 6 Helfer entfernen**

In `Feedivo/Services/ArticleRetentionCleanupService.swift` folgende Blöcke vollständig entfernen
(in dieser Reihenfolge, von oben nach unten in der Datei):

1. Die gesamte öffentliche Methode `removeExpiredArticles(in context: ModelContext, ...)` (der
   erste `static func` im `enum`, direkt nach der `enum ArticleRetentionCleanupService {`-Zeile, bis
   zu ihrer schließenden `}` — endet mit `return articlesToRemove.count`).

2. Die öffentliche (nicht-private) Methode `shouldRemove(_ article: Article, cutoffDate:isEnabled:
   includeProtectedArticles:)`:

```swift
    static func shouldRemove(
        _ article: Article,
        cutoffDate: Date,
        isEnabled: Bool = true,
        includeProtectedArticles: Bool = false
    ) -> Bool {
        guard isEnabled else {
            return false
        }

        guard
            let publishedAt = article.publishedAt,
            publishedAt < cutoffDate
        else {
            return false
        }

        if includeProtectedArticles {
            return true
        }

        return !article.isStarred && !article.isArchived
    }
```

   (NICHT die direkt darauf folgende `private static func shouldRemove(_ article:
   SQLiteArticleRetentionCandidate, ...)` — die bleibt unverändert.)

3. `private static func retentionConfiguration(for article: Article, ...)`.

4. `private static func protectedSwiftDataArticleIDs(...)`.

5. `private static func swiftDataRetentionSort(_ lhs: Article, _ rhs: Article) -> Bool`.

6. `@MainActor private static func feedsByID(in context: ModelContext) throws -> [UUID: Feed]`.

7. `@MainActor private static func syncUnreadCounts(for feedIDs:unreadCounts:in context:) throws`.

8. `private static func unreadCountsByFeedID(afterRemoving:from:) -> [UUID: Int]`.

Nach dem Entfernen aller 8 Blöcke bleiben in der Datei genau: `removeExpiredSQLiteArticles` (zwei
Overloads), `shouldRemove` (nur noch die SQLite-Variante, jetzt nicht mehr überladen — Name bleibt
gleich, kein Umbenennen nötig, da Overload-Mehrdeutigkeit mit dem Entfernen der `Article`-Variante
verschwindet), `retentionConfiguration` — Achtung: NICHT verwechseln, es gibt keine zweite
`retentionConfiguration`-Methode, nur die eine für `Article` die in Schritt 3 entfernt wird; die
SQLite-Seite berechnet Konfigurationen inline über `sqliteFeedRetentionConfigurations` — sowie
`protectedSQLiteArticleIDs`, `sqliteRetentionSort`, `sqliteFeedRetentionConfigurations`,
`deleteSQLiteArticles`, `saveSQLiteIdentityHistory`, `recalculateSQLiteUnreadCounts`, plus die
`private struct SQLiteArticleRetentionCandidate`, `private struct
SQLiteArticleIdentityHistoryCandidate`, `private extension Array`, `private extension
Optional<String>`, `private struct ArticleRetentionConfiguration` am Dateiende — diese bleiben alle
unverändert.

- [ ] **Step 3: `import SwiftData` prüfen**

Nach Step 2 wird `ModelContext`/`Article`/`Feed`/`FetchDescriptor` nicht mehr in dieser Datei
referenziert. Entferne `import SwiftData` vom Dateikopf, falls der Compiler das nicht ohnehin
bereits als unbenutzt markiert. `import GRDB` und `import Foundation` bleiben.

- [ ] **Step 4: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: Build schlägt fehl (Tests referenzieren noch `removeExpiredArticles`) — nächster Schritt
behebt das.

- [ ] **Step 5: 6 tote Tests aus `ArticleRetentionCleanupServiceTests.swift` entfernen**

Lies die Datei komplett. Entferne die `@Test func`-Blöcke, die `removeExpiredArticles(` (die
SwiftData-Variante) aufrufen — erwartet werden 6 Funktionen mit Namen wie
`cleanupIstStandardmaessigDeaktiviert`, `cleanupLoeschtNurAlteArtikelOhneSternOderArchiv`,
`cleanupKorrigiertFeedZaehlerNachGeloeschtenUngelesenenArtikeln`,
`cleanupKannSternUndArchivArtikelOptionalMitLoeschen`,
`cleanupBeruecksichtigtFeedEigeneAufbewahrung`,
`feedEigeneAufbewahrungKannAuchBeiGlobalAusAktivSein`. Behalte alle Tests, die
`removeExpiredSQLiteArticles(` aufrufen (Namen beginnen mit `sqliteCleanup...`), sowie
`retentionSettingsKlemmenUnbekannteWerte`/`retentionSettingsKlemmenMindestartikelProFeed` (testen
`ArticleRetentionSettings`, nicht betroffen).

- [ ] **Step 6: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests 2>&1 | tail -80`
Erwartung: alle verbleibenden Tests grün.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/ArticleRetentionCleanupService.swift FeedivoTests/ArticleRetentionCleanupServiceTests.swift
git commit -m "Remove dead SwiftData retention path from ArticleRetentionCleanupService"
```

---

## Task 5: `ReaderPreparedArticle.swift` aufräumen

**Files:**
- Modify: `Feedivo/Views/Reader/ReaderPreparedArticle.swift`
- Modify: `FeedivoTests/FeedivoTests.swift`

**Interfaces:**
- Produces: `ReaderArticleInput.make(from snapshot: ArticleReaderSnapshot)`,
  `ReaderPreparedArticle` (Struct inkl. `contentAvailability`-Feld und `ReaderContentAvailability`),
  `ReaderPreparedArticleCache`, `ReaderArticleTextFingerprint`, `ReaderArticleCacheKey` bleiben
  unverändert (aktiv genutzt von `SQLiteReaderState.swift`,
  `FeedivoTests/ReaderPreparedArticleTests.swift`, `FeedivoTests/SQLiteReaderStateTests.swift`).
- Consumes: keine Abhängigkeiten von anderen Phase-2-Tasks.
- **Korrektur gegenüber Spec:** `ReaderContentAvailability` ist NICHT tot (Feldtyp von
  `ReaderPreparedArticle.contentAvailability`, berechnet in `init(input:)`, getestet in
  `SQLiteReaderStateTests.swift`/`FeedivoTests.swift`) — bleibt unverändert.

- [ ] **Step 1: Verifikation vor dem Löschen**

Lauf: `grep -rn "ReaderArticleContentLoader\|ReaderArticleObservationSignature\|ReaderArticleInput\.make(from: article\|ReaderArticleInput\.makePreview\|ReaderPreparedArticle(article:" Feedivo FeedivoTests`

Erwartung: `ReaderArticleContentLoader` 0 Treffer außer eigener Definition.
`ReaderArticleObservationSignature` nur in eigener Definition + `FeedivoTests/FeedivoTests.swift`
(3 Aufrufe). `ReaderArticleInput.make(from: Article)`/`.makePreview(from:)`/`ReaderPreparedArticle
(article:)` nur in eigener Definition + `FeedivoTests/FeedivoTests.swift`. Falls Produktionscode
außerhalb dieser Datei diese Symbole aufruft: STOPPEN, BLOCKED melden.

- [ ] **Step 2: `ReaderArticleContentLoader` löschen**

Den kompletten Block

```swift
enum ReaderArticleContentLoader {
    static func loadInput(
        articleID: UUID,
        modelContainer: ModelContainer
    ) async -> ReaderArticleInput? {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(modelContainer)
            var descriptor = FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.id == articleID
                }
            )
            descriptor.fetchLimit = 1

            guard let article = try? context.fetch(descriptor).first else {
                return nil
            }

            let content = article.content
            return ReaderArticleInput(
                summary: article.summary,
                content: content,
                contentFingerprint: ReaderArticleTextFingerprint.make(from: content),
                imageURL: article.imageURL,
                link: article.link,
                feedTitle: article.feed?.title,
                publishedAt: article.publishedAt
            )
        }.value
    }
}
```

vollständig entfernen.

- [ ] **Step 3: `ReaderArticleObservationSignature` löschen**

Den kompletten Block

```swift
/// Leichte Signatur für Reader-Updates. Sie fasst nur Felder an, die in den
/// Listen-Fetches ohnehin geladen sind. Das große Textfeld `content` bleibt
/// bewusst draußen, damit ein Artikelwechsel nicht schon beim SwiftUI-View-
/// Aufbau schwere SwiftData-Faults auslöst.
struct ReaderArticleObservationSignature: Equatable {
    let summary: String?
    let imageURL: String?
    let offlineStateRaw: String
    let offlineRequestedAt: Date?
    let offlineSavedAt: Date?
    let offlineErrorMessage: String?

    static func make(from article: Article) -> ReaderArticleObservationSignature {
        ReaderArticleObservationSignature(
            summary: article.summary,
            imageURL: article.imageURL,
            offlineStateRaw: article.offlineStateRaw,
            offlineRequestedAt: article.offlineRequestedAt,
            offlineSavedAt: article.offlineSavedAt,
            offlineErrorMessage: article.offlineErrorMessage
        )
    }
}
```

vollständig entfernen.

- [ ] **Step 4: Zwei tote Factory-Methoden aus `ReaderArticleInput`-Extension entfernen**

Von:

```swift
extension ReaderArticleInput {
    @MainActor
    static func make(from article: Article) -> ReaderArticleInput {
        ReaderArticleInput(
            summary: article.summary,
            content: article.content,
            contentFingerprint: ReaderArticleTextFingerprint.make(from: article.content),
            imageURL: article.imageURL,
            link: article.link,
            feedTitle: article.feed?.title,
            publishedAt: article.publishedAt
        )
    }

    @MainActor
    static func makePreview(from article: Article) -> ReaderArticleInput {
        ReaderArticleInput(
            summary: article.summary,
            content: nil,
            contentFingerprint: nil,
            imageURL: article.imageURL,
            link: article.link,
            feedTitle: article.feed?.title,
            publishedAt: article.publishedAt
        )
    }

    static func make(from snapshot: ArticleReaderSnapshot) -> ReaderArticleInput {
        ReaderArticleInput(
            summary: snapshot.summary,
            content: snapshot.content,
            contentFingerprint: ReaderArticleTextFingerprint.make(from: snapshot.content),
            imageURL: snapshot.imageURL,
            link: snapshot.link,
            feedTitle: snapshot.feedTitle,
            publishedAt: snapshot.publishedAt
        )
    }
}
```

zu:

```swift
extension ReaderArticleInput {
    static func make(from snapshot: ArticleReaderSnapshot) -> ReaderArticleInput {
        ReaderArticleInput(
            summary: snapshot.summary,
            content: snapshot.content,
            contentFingerprint: ReaderArticleTextFingerprint.make(from: snapshot.content),
            imageURL: snapshot.imageURL,
            link: snapshot.link,
            feedTitle: snapshot.feedTitle,
            publishedAt: snapshot.publishedAt
        )
    }
}
```

- [ ] **Step 5: Toten `init(article: Article)`-Convenience-Initializer aus `ReaderPreparedArticle` entfernen**

Von:

```swift
    init(article: Article) {
        // Synchroner Pfad fuer Tests und Diagnose; extrahiert die Werte aus dem
        // Modell und parst danach ueber den reinen Eingabe-Initializer.
        self.init(input: ReaderArticleInput.make(from: article))
    }

    /// Reiner, thread-sicherer Build aus bereits extrahierten Eingabewerten.
```

zu:

```swift
    /// Reiner, thread-sicherer Build aus bereits extrahierten Eingabewerten.
```

(D. h. nur den `init(article:)`-Block samt seinem eigenen Kommentar entfernen, der `init(input:)`
folgende Doc-Kommentar bleibt unverändert erhalten.)

- [ ] **Step 6: `import SwiftData` prüfen**

Nach den Steps 2-5 bleibt in der Datei noch ein `Article`-Bezug? Prüfe: `grep -n "\bArticle\b"
Feedivo/Views/Reader/ReaderPreparedArticle.swift`. Falls 0 Treffer: `import SwiftData` am Dateikopf
entfernen. Falls noch Treffer vorhanden sind (z. B. übersehene Stelle): NICHT entfernen und den Fund
im Report vermerken.

- [ ] **Step 7: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: Build schlägt fehl (Tests in `FeedivoTests.swift` referenzieren noch gelöschte Symbole) —
nächster Schritt behebt das.

- [ ] **Step 8: 5 tote Tests aus `FeedivoTests/FeedivoTests.swift` entfernen**

Entferne die folgenden 5 `@Test func`-Blöcke vollständig (Namen können beim Nachschlagen leicht
abweichen, per `grep -n "@Test func reader" FeedivoTests/FeedivoTests.swift` die exakten
Fundstellen bestätigen):
- `readerPreparedArticleBerechnetTeureReaderDatenEinmalig` — nutzt `ReaderPreparedArticle(article:)`.
- `readerPreparedArticleErkenntSummaryOnlyFeedInhalt` — nutzt `ReaderPreparedArticle(article:)`.
- `readerPreparedArticleBevorzugtFeedTextVorGespeichertenOfflineAltlasten` — nutzt
  `ReaderPreparedArticle(article:)`.
- `readerObservationSignatureIgnoriertSchwereInhalte` — nutzt
  `ReaderArticleObservationSignature.make(from:)`.
- `readerPreviewInputNutztNurLeichteFelder` — nutzt `ReaderArticleInput.makePreview(from:)`.

Alle anderen Tests in der Datei (z. B. `readerTypographyBegrenztTitelZeilenabstandSeparat`,
`readerTypographyBegrenztArtikelbreite`, und alle nicht mit `reader...` beginnenden Tests)
UNVERÄNDERT lassen.

- [ ] **Step 9: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderPreparedArticleTests -only-testing:FeedivoTests/SQLiteReaderStateTests 2>&1 | tail -80`
Erwartung: alle Tests grün.

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Views/Reader/ReaderPreparedArticle.swift FeedivoTests/FeedivoTests.swift
git commit -m "Remove dead Article-based reader input paths from ReaderPreparedArticle"
```

---

## Task 6: `ArticleListQuery.swift` aufräumen (methodengenau)

**Voraussetzung:** Task 1 MUSS bereits committet sein (siehe Global Constraints — sonst bricht der
Build, weil `SidebarUnreadCount.swift`'s toter `SidebarTagCount` noch `ArticleListQuery.tagPredicate`
referenziert).

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleListQuery.swift`
- Modify: `FeedivoTests/ArticleListQueryTests.swift`

**Interfaces:**
- Produces: `ArticleSearchField`, `ArticleSearchDateFilter`, `ArticleSearchStatusFilter`,
  `ArticleSearchScope` bleiben komplett unverändert.
- Produces: `ArticleSearchFilters` behält `feedID`, `tagID`, `date`, `status`, `init`, `isActive` —
  verliert `includes(_:now:calendar:)`, `matchesFeed`, `matchesTag`, `matchesDate`, `matchesStatus`.
- Produces: `ArticleSearchQuery` behält `text`, `field`, `scope`, `filters`, `includesHeavyContent`,
  `now`, `calendar`, `init`, `normalizedText`, `isActive` — verliert `includes(_:)`, `filtered(_:)`,
  `textIncludes(_:)`, `heavyContentIncludes(_:in:)`, `contains(_:in:)`.
- Produces: `ArticleSearchWindowState` behält alles außer `filteredArticles(from:)`.
- Consumes: Task 1 muss abgeschlossen sein (siehe Voraussetzung oben).

- [ ] **Step 1: Verifikation vor dem Löschen**

Lauf: `grep -rn "\bArticleListQuery\.\|\bLegacyArticleListQuery\b" Feedivo`

Erwartung: NUR noch Treffer innerhalb von `Feedivo/Views/ArticleList/ArticleListQuery.swift` selbst
(die Definition). Falls `Feedivo/Views/Sidebar/SidebarUnreadCount.swift:24` (oder eine andere
Produktionsdatei) noch einen Treffer zeigt: STOPPEN — das bedeutet Task 1 wurde noch nicht
abgeschlossen/committet, oder es gibt eine weitere, hier nicht dokumentierte Abhängigkeit. BLOCKED
melden, nicht fortfahren.

Lauf zusätzlich: `grep -n "\.scope\b" Feedivo/Views/ArticleList/ArticleListQuery.swift
Feedivo/Views/ArticleList/ArticleSearchWindowView.swift Feedivo/Stores/ArticleStore.swift`

Erwartung: einziger Treffer ist die Feldzuweisung `self.scope = scope` im `ArticleSearchQuery.init`
— das bestätigt, dass `scope` nirgends ausgewertet wird, aber als `Equatable`-Feld einer aktiven
Struct bestehen bleibt (siehe Global Constraints).

- [ ] **Step 2: `LegacyArticleListQuery` + `typealias ArticleListQuery` löschen**

Am Dateianfang von `Feedivo/Views/ArticleList/ArticleListQuery.swift` beginnt mit
`@available(*, deprecated, ...) enum LegacyArticleListQuery { ... }` (Zeile 4-5 bis zur
schließenden `}` dieses Enums) und endet mit der separaten Zeile `typealias ArticleListQuery =
LegacyArticleListQuery`. Beide zusammen (das komplette Enum inkl. aller enthaltenen `static
let`/`static func` — Sortierung, Fetch-Descriptors für Feed/Tag/SmartFolder, Prädikate — plus die
Typealias-Zeile direkt danach) vollständig entfernen. Der Dateiinhalt beginnt danach direkt mit
`struct ArticleListDisplayState`.

- [ ] **Step 3: `ArticleListDisplayState`, `ArticleListDisplaySnapshot`, `ArticleListPaginationState`, `ArticleListFeedTitleSnapshot`, `ArticleListFeedTitleLookup` löschen**

Diese 5 aufeinanderfolgenden Deklarationen (zwischen der eben entfernten
`LegacyArticleListQuery`/Typealias-Stelle und `enum ArticleSearchField`) vollständig entfernen:
`struct ArticleListDisplayState`, `struct ArticleListDisplaySnapshot`, `struct
ArticleListPaginationState`, `struct ArticleListFeedTitleSnapshot: Equatable, Hashable`, `enum
ArticleListFeedTitleLookup`.

**Nicht verwechseln:** `SQLiteArticleListDisplayState` (definiert in
`Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`, NICHT in dieser Datei) ist ein
komplett anderer, aktiver Typ und darf nicht angetastet werden — er wird hier nicht berührt, weil er
in einer anderen Datei liegt.

- [ ] **Step 4: `ArticleSearchScope` unverändert lassen**

`enum ArticleSearchScope: String, CaseIterable, Identifiable { ... }` NICHT löschen (Korrektur
gegenüber einer ersten Einschätzung — siehe Global Constraints). Mit diesem Schritt nichts tun,
außer zu bestätigen, dass der Typ noch da ist.

- [ ] **Step 5: `ArticleSearchFilters` auf Daten + `isActive` reduzieren**

Von:

```swift
struct ArticleSearchFilters: Equatable {
    var feedID: UUID?
    var tagID: UUID?
    var date: ArticleSearchDateFilter
    var status: ArticleSearchStatusFilter

    init(
        feedID: UUID? = nil,
        tagID: UUID? = nil,
        date: ArticleSearchDateFilter = .anytime,
        status: ArticleSearchStatusFilter = .all
    ) {
        self.feedID = feedID
        self.tagID = tagID
        self.date = date
        self.status = status
    }

    var isActive: Bool {
        feedID != nil || tagID != nil || date != .anytime || status != .all
    }

    func includes(
        _ article: Article,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        matchesFeed(article)
            && matchesTag(article)
            && matchesDate(article, now: now, calendar: calendar)
            && matchesStatus(article)
    }

    private func matchesFeed(_ article: Article) -> Bool {
        guard let feedID else { return true }
        return article.feedID == feedID || article.feed?.id == feedID
    }

    private func matchesTag(_ article: Article) -> Bool {
        guard let tagID else { return true }
        if (article.tags ?? []).contains(where: { $0.id == tagID }) { return true }
        return article.feed?.tags?.contains(where: { $0.id == tagID }) ?? false
    }

    private func matchesDate(_ article: Article, now: Date, calendar: Calendar) -> Bool {
        guard date != .anytime else { return true }
        guard let publishedAt = article.publishedAt else { return false }
        switch date {
        case .anytime: return true
        case .today: return calendar.isDate(publishedAt, inSameDayAs: now)
        case .thisWeek: return calendar.isDate(publishedAt, equalTo: now, toGranularity: .weekOfYear)
        }
    }

    private func matchesStatus(_ article: Article) -> Bool {
        switch status {
        case .all: return true
        case .unread: return !article.isRead
        case .read: return article.isRead
        case .starred: return article.isStarred
        case .archived: return article.isArchived
        }
    }
}
```

zu:

```swift
struct ArticleSearchFilters: Equatable {
    var feedID: UUID?
    var tagID: UUID?
    var date: ArticleSearchDateFilter
    var status: ArticleSearchStatusFilter

    init(
        feedID: UUID? = nil,
        tagID: UUID? = nil,
        date: ArticleSearchDateFilter = .anytime,
        status: ArticleSearchStatusFilter = .all
    ) {
        self.feedID = feedID
        self.tagID = tagID
        self.date = date
        self.status = status
    }

    var isActive: Bool {
        feedID != nil || tagID != nil || date != .anytime || status != .all
    }
}
```

- [ ] **Step 6: `ArticleSearchQuery` auf Daten + `normalizedText`/`isActive` reduzieren**

Von:

```swift
struct ArticleSearchQuery: Equatable {
    var text: String
    var field: ArticleSearchField
    var scope: ArticleSearchScope
    var filters: ArticleSearchFilters
    var includesHeavyContent: Bool
    var now: Date
    var calendar: Calendar

    init(
        text: String = "",
        field: ArticleSearchField = .all,
        scope: ArticleSearchScope = .currentView,
        filters: ArticleSearchFilters = ArticleSearchFilters(),
        includesHeavyContent: Bool = true,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.text = text
        self.field = field
        self.scope = scope
        self.filters = filters
        self.includesHeavyContent = includesHeavyContent
        self.now = now
        self.calendar = calendar
    }

    var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isActive: Bool {
        !normalizedText.isEmpty || filters.isActive
    }

    func includes(_ article: Article) -> Bool {
        guard isActive else { return true }
        guard textIncludes(article) else { return false }
        return filters.includes(article, now: now, calendar: calendar)
    }

    func filtered(_ articles: [Article]) -> [Article] {
        guard isActive else { return articles }
        return articles.filter { article in includes(article) }
    }

    private func textIncludes(_ article: Article) -> Bool {
        guard !normalizedText.isEmpty else { return true }
        let needle = normalizedText
        switch field {
        case .all:
            return contains(needle, in: article.title)
                || contains(needle, in: article.summary)
                || heavyContentIncludes(needle, in: article)
        case .title: return contains(needle, in: article.title)
        case .summary: return contains(needle, in: article.summary)
        case .content: return heavyContentIncludes(needle, in: article)
        }
    }

    private func heavyContentIncludes(_ needle: String, in article: Article) -> Bool {
        guard includesHeavyContent else { return false }
        return contains(needle, in: article.content) || contains(needle, in: article.offlineContent)
    }

    private func contains(_ needle: String, in haystack: String?) -> Bool {
        guard let haystack else { return false }
        return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
```

zu:

```swift
struct ArticleSearchQuery: Equatable {
    var text: String
    var field: ArticleSearchField
    var scope: ArticleSearchScope
    var filters: ArticleSearchFilters
    var includesHeavyContent: Bool
    var now: Date
    var calendar: Calendar

    init(
        text: String = "",
        field: ArticleSearchField = .all,
        scope: ArticleSearchScope = .currentView,
        filters: ArticleSearchFilters = ArticleSearchFilters(),
        includesHeavyContent: Bool = true,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.text = text
        self.field = field
        self.scope = scope
        self.filters = filters
        self.includesHeavyContent = includesHeavyContent
        self.now = now
        self.calendar = calendar
    }

    var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isActive: Bool {
        !normalizedText.isEmpty || filters.isActive
    }
}
```

- [ ] **Step 7: `ArticleSearchWindowState.filteredArticles(from:)` entfernen**

Von:

```swift
    func filteredArticles(from articles: [Article]) -> [Article] {
        ArticleSortOption.newestFirst.sorted(query.filtered(articles))
    }
}
```

zu (die schließende Klammer des Structs direkt nach dem `query`-computed-property):

```swift
}
```

D. h. nur die Methode `filteredArticles(from:)` entfernen, `var query: ArticleSearchQuery { ... }`
und alles davor bleibt unverändert.

- [ ] **Step 8: `ArticleListPreparedArticles` löschen**

Den letzten Top-Level-Typ der Datei (`struct ArticleListPreparedArticles { ... }`, direkt nach
`ArticleSearchWindowState`) vollständig entfernen.

- [ ] **Step 9: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: Build schlägt fehl (Tests referenzieren noch gelöschte Symbole) — nächster Schritt
behebt das.

- [ ] **Step 10: Toten Test-Code aus `FeedivoTests/ArticleListQueryTests.swift` entfernen**

Lies die Datei komplett (aktuell 1084 Zeilen). Entferne jeden `@Test func`, der eines der in Steps
2-8 gelöschten Symbole aufruft oder testet:
- Alle Tests für `ArticleListDisplayState`/`ArticleListDisplaySnapshot` (Namen beginnend mit
  `displayState...`/`displaySnapshot...`).
- `feedTitleLookupWirdAusLeichtenSnapshotsGebildet` (`ArticleListFeedTitleLookup`).
- `paginationBleibtMoeglichWennArtikelNachDemLadenAusDerQueryFallen`
  (`ArticleListPaginationState`).
- `articleSearchQuerySuchtInTitelZusammenfassungUndInhalt`,
  `articleSearchQueryKannSchwereInhalteAuslassen`,
  `articleSearchQueryIgnoriertLeerzeichenUndLeereSucheFiltertNicht` (testen
  `ArticleSearchQuery.includes`/`.filtered`).
- `articleListPreparedArticlesSortiertNurEinmalVorDemFiltern`,
  `articleListPreparedArticlesKombiniertFilterSortierungUndSuche`
  (`ArticleListPreparedArticles`).
- `articleSearchFiltersFilternNachFeedUndTag`, `articleSearchFiltersFilternNachZeitraumUndStatus`,
  `articleSearchFiltersKombinierenTextFeedTagUndStatus` (testen `ArticleSearchFilters.includes`).
- `articleSearchWindowStateLiefertGlobalGefilterteUndSortierteTreffer`
  (`ArticleSearchWindowState.filteredArticles`).
- `listFetchDescriptorsLadenKeineSchwerenVolltextfelder`,
  `feedFetchDescriptorLaedtNurArtikelDesAusgewaehltenFeedsSortiert`,
  `feedFetchDescriptorBegrenztArtikelWennFetchLimitGesetztIst`,
  `feedFetchDescriptorNutztDirekteFeedIDOhneRelationshipFallback`,
  `tagFetchDescriptorLaedtNurArtikelMitAusgewaehltemTagSortiert`,
  `tagFetchDescriptorLaedtAuchArtikelAusGetaggtenFeedsOhneDuplikate`,
  `smartFolderFetchDescriptorLaedtFuerUngelesenAlleArtikelFuerFeedAehnlichesVerhalten`,
  `smartFolderFetchDescriptorLaedtGespeicherteArtikelDirektPerQuery`,
  `smartFolderFetchDescriptorFaelltFuerKomplexeTextOrdnerAufEngineZurueck` (alle nutzen
  `ArticleListQuery.feedFetchDescriptor`/`.tagFetchDescriptor`/`.smartFolderFetchDescriptor`/
  `.listPropertiesToFetch`, also `LegacyArticleListQuery` per Typealias).

**AUSDRÜCKLICH BEHALTEN** (testen aktive Typen, nicht die gelöschten):
- `sqliteDisplayStateHaeltAutomatischGeleseneArtikelSichtbar`,
  `sqliteDisplayStateHaeltAutomatischGeleseneArtikelImUngelesenFilterSichtbar`,
  `mergingStickyRowsBehaeltArtikelDerAusDerFrischenAbfrageFaellt`,
  `mergingStickyRowsBevorzugtFrischeZeileBeiDoppelterID` (testen `SQLiteArticleListDisplayState`,
  ein anderer Typ in `SQLiteFeedArticleListView.swift` — wurde in dieser Session für den
  Ungelesen-Ordner-Bugfix hinzugefügt).
- `articleSortOptionSortiertArtikelNachBenutzerauswahl`,
  `articleSortOptionFaelltBeiUngueltigemRawValueAufStandardZurueck`,
  `articleFilterOptionFiltertArtikelNachBenutzerauswahl`,
  `articleFilterOptionFaelltBeiUngueltigemRawValueAufStandardZurueck` (testen
  `ArticleSortOption`/`ArticleFilterOption`, unberührt).
- `articleInitialisiertDirekteFeedIDFuerSchnelleListenQueries` (testet nur
  `Article(title:feed:).feedID` direkt, keine Abhängigkeit von einem gelöschten Symbol).

Falls beim Durchgehen ein `@Test func` auftaucht, der hier nicht gelistet ist: per `grep` prüfen,
ob er eines der in Steps 2-8 gelöschten Symbole (`LegacyArticleListQuery`, `ArticleListQuery.`,
`ArticleListDisplayState`, `ArticleListDisplaySnapshot`, `ArticleListPaginationState`,
`ArticleListFeedTitleSnapshot`, `ArticleListFeedTitleLookup`, `ArticleListPreparedArticles`,
`.includes(`, `.filtered(`, `.filteredArticles(`) aufruft — falls ja, entfernen; falls nein,
behalten und im Report vermerken.

- [ ] **Step 11: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListQueryTests -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests 2>&1 | tail -100`
Erwartung: grün, außer den 5 bekannten vorbestehenden Fehlschlägen in
`FeedivoAppSceneConfigurationTests` (siehe Task 1 Step 9).

Zusätzlich, weil dieser Task den größten Blast-Radius hat:

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleStoreTests -only-testing:FeedivoTests/SQLiteFeedArticleListViewTests 2>&1 | tail -100`

(Falls einer dieser beiden Suite-Namen nicht existiert, per `grep -rn "@Suite\|struct.*Tests"
FeedivoTests` den tatsächlichen Namen der Test-Suite ermitteln, die `ArticleStore.searchArticles`
bzw. `ArticleSearchWindowState`/`SQLiteFeedArticleListView` abdeckt, und stattdessen diesen
Suite-Namen verwenden.)
Erwartung: alle Tests grün.

- [ ] **Step 12: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleListQuery.swift FeedivoTests/ArticleListQueryTests.swift
git commit -m "Remove dead LegacyArticleListQuery and Article-dependent search methods"
```

---

## Abschluss

Nach Task 6: finaler Whole-Branch-Review (wie in Phase 1) über den kompletten Diff-Bereich dieser
Phase (Merge-Base: der Commit, auf dem Phase 2 aufsetzt — `git merge-base main HEAD` bzw. der
Commit direkt nach `e838321ea`), dispatcht auf dem leistungsfähigsten verfügbaren Modell. Danach
Push nach `origin/main` nur nach expliziter Nutzerbestätigung (Session-Konvention).
