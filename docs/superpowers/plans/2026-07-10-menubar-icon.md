# Feature 21.1 "Menubar-Icon" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein Menubar-Icon mit Dropdown (neueste ungelesene Artikel, Refresh, globales "Alle als gelesen markieren"), konfigurierbarer Artikelanzahl, Dock-Icon-Toggle und wählbarem Artikel-Klick-Verhalten (Feedivo-Fenster vs. Browser) hinzufügen.

**Architecture:** `MenuBarExtra(.window)` (SwiftUI, macOS 13+) als zusätzliche Scene in `FeedivoApp.swift`. Neue Settings-Typen im etablierten `storageKey`/`defaultXxx`/`resolved(from:)`-Muster. Wiederverwendung bestehender Bausteine: `ArticleDatabase.fetchUnreadArticles`, `FeedStore.feeds()`, `SQLiteUnreadCountService.rebuildAllFeedUnreadCounts()`, `SQLiteDataInvalidation.bumpStatusVersion()`, `ArticleListItemSnapshot(sqliteSnapshot:)`, `openWindow(value: ArticleWindowRequest(articleID:))`.

**Tech Stack:** SwiftUI (`MenuBarExtra`), AppKit (`NSApp.setActivationPolicy(_:)`), GRDB (raw SQL via `db.execute`), `@AppStorage`, Swift Testing.

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention, siehe CLAUDE.md).
- Alle neuen Settings-Defaults erzeugen keinen Verhaltenssprung: Menubar-Icon ist standardmäßig **aus** (`MenubarSettings.defaultIsEnabled = false`).
- Nach jedem Task: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet` muss fehlerfrei durchlaufen (SourceKit-Diagnosen in der IDE sind bekanntermaßen unzuverlässig — nur ein echter Build zählt).
- Tests immer gezielt mit `-only-testing:FeedivoTests/<SuiteName>` und `-parallel-testing-enabled NO` (volle Testsuite hängt bekanntermaßen).
- `Localizable.xcstrings`-Einträge müssen für alle 4 Sprachen (de/en/fr/it) mit `"state" : "translated"` befüllt werden.
- `ArticleWindowRequest.articleID` ist vom Typ `UUID`, während `ArticleListItemSnapshot.id`/`ArticleListSnapshot.id` vom Typ `String` sind — jede Umwandlung muss `UUID(uuidString:)` verwenden und den `nil`-Fall behandeln (Artikel-ID ist nicht immer eine valide UUID-Zeichenkette, siehe bestehendes Muster in `ContentView.swift`).

---

## Task 1: Menubar-Settings-Typen + Unit-Tests

**Files:**
- Create: `Feedivo/Views/Menubar/MenubarSettings.swift`
- Test: `FeedivoTests/MenubarSettingsTests.swift`

**Interfaces:**
- Produces: `MenubarSettings.isEnabledKey/.defaultIsEnabled`, `.articleCountKey/.defaultArticleCount/.allowedArticleCountRange`, `.hidesDockIconKey/.defaultHidesDockIcon`; `MenubarArticleClickBehavior` (enum, cases `.inFeedivo`/`.inBrowser`, `.storageKey`, `.defaultBehavior`, `.resolved(from:) -> MenubarArticleClickBehavior`, `.titleKey: LocalizedStringKey`)

- [ ] **Step 1: `MenubarSettings.swift` anlegen**

```swift
import SwiftUI

/// Ob das Menubar-Icon aktiv ist (Feature 21.1). Default aus, damit
/// Bestandsnutzer keinen Verhaltenssprung erleben.
enum MenubarSettings {
    static let isEnabledKey = "menubar.isEnabled"
    static let defaultIsEnabled = false

    static let articleCountKey = "menubar.articleCount"
    static let defaultArticleCount = 5
    static let allowedArticleCountRange = 3...10

    static let hidesDockIconKey = "menubar.hidesDockIcon"
    static let defaultHidesDockIcon = false

    /// Fängt ungültige/veraltete gespeicherte Werte ab.
    static func resolvedArticleCount(from storedValue: Int) -> Int {
        allowedArticleCountRange.contains(storedValue) ? storedValue : defaultArticleCount
    }
}

/// Verhalten beim Klick auf einen Artikel im Menubar-Dropdown (Feature 21.1).
enum MenubarArticleClickBehavior: String, CaseIterable, Identifiable {
    case inFeedivo
    case inBrowser

    static let storageKey = "menubar.articleClickBehavior"
    static let defaultBehavior = MenubarArticleClickBehavior.inFeedivo

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .inFeedivo:
            L10n.menubarArticleClickBehaviorInFeedivo
        case .inBrowser:
            L10n.menubarArticleClickBehaviorInBrowser
        }
    }

    static func resolved(from rawValue: String) -> MenubarArticleClickBehavior {
        MenubarArticleClickBehavior(rawValue: rawValue) ?? defaultBehavior
    }
}
```

- [ ] **Step 2: L10n-Keys ergänzen**

In `Feedivo/Resources/L10n.swift`, nach der letzten `articleDateDisplayMode*`-Zeile (Feature 19.1) einfügen:

```swift
    static let menubarArticleClickBehaviorInFeedivo = LocalizedStringKey("menubar.articleClickBehavior.inFeedivo")
    static let menubarArticleClickBehaviorInBrowser = LocalizedStringKey("menubar.articleClickBehavior.inBrowser")
```

- [ ] **Step 3: Zwei Einträge in `Localizable.xcstrings` ergänzen**

Alphabetisch nach Key-Name einsortieren (per `grep -n '"menubar' Feedivo/Resources/Localizable.xcstrings` den korrekten Nachbarn finden, da sich die Datei seit Planerstellung verändert haben kann — Anker ist der Key-Name, nicht eine Zeilennummer):

```json
    "menubar.articleClickBehavior.inBrowser" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Im Browser"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "In browser"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Dans le navigateur"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nel browser"
          }
        }
      }
    },
    "menubar.articleClickBehavior.inFeedivo" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "In Feedivo"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "In Feedivo"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Dans Feedivo"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "In Feedivo"
          }
        }
      }
    },
```

Run: `python3 -c "import json; json.load(open('Feedivo/Resources/Localizable.xcstrings')); print('valid JSON')"`
Expected: `valid JSON`

- [ ] **Step 4: Fehlschlagende Tests schreiben**

Neue Datei `FeedivoTests/MenubarSettingsTests.swift`:

```swift
import Testing
@testable import Feedivo

struct MenubarSettingsTests {

    @Test func isEnabledDefaultIstAus() {
        #expect(MenubarSettings.defaultIsEnabled == false)
    }

    @Test func articleCountDefaultIstFuenf() {
        #expect(MenubarSettings.defaultArticleCount == 5)
    }

    @Test func resolvedArticleCountFaengtUngueltigeWerteAb() {
        #expect(MenubarSettings.resolvedArticleCount(from: 3) == 3)
        #expect(MenubarSettings.resolvedArticleCount(from: 10) == 10)
        #expect(MenubarSettings.resolvedArticleCount(from: 2) == MenubarSettings.defaultArticleCount)
        #expect(MenubarSettings.resolvedArticleCount(from: 11) == MenubarSettings.defaultArticleCount)
    }

    @Test func hidesDockIconDefaultIstAus() {
        #expect(MenubarSettings.defaultHidesDockIcon == false)
    }

    @Test func articleClickBehaviorResolvedFaelltBeiUnbekanntemRohwertAufDefaultZurueck() {
        #expect(MenubarArticleClickBehavior.resolved(from: "inFeedivo") == .inFeedivo)
        #expect(MenubarArticleClickBehavior.resolved(from: "inBrowser") == .inBrowser)
        #expect(MenubarArticleClickBehavior.resolved(from: "unknown") == MenubarArticleClickBehavior.defaultBehavior)
    }

    @Test func articleClickBehaviorDefaultIstInFeedivo() {
        #expect(MenubarArticleClickBehavior.defaultBehavior == .inFeedivo)
    }
}
```

- [ ] **Step 5: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen

- [ ] **Step 6: Tests ausführen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MenubarSettingsTests -quiet`
Expected: `** TEST SUCCEEDED **`, alle 6 Tests grün

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Views/Menubar/MenubarSettings.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings FeedivoTests/MenubarSettingsTests.swift
git commit -m "Feature 21.1: Menubar-Settings-Typen (isEnabled, articleCount, hidesDockIcon, articleClickBehavior) ergänzt"
```

---

## Task 2: Globale "Alle als gelesen markieren"-Aktion

**Files:**
- Modify: `Feedivo/Stores/ArticleStatusStore.swift`
- Test: `FeedivoTests/ArticleStatusStoreTests.swift` (bestehende Datei — falls nicht vorhanden, neu anlegen)

**Interfaces:**
- Produces: `ArticleStatusStore.markAllUnreadAsRead() throws`

- [ ] **Step 1: Bestehende Testdatei prüfen**

Run: `ls FeedivoTests/ArticleStatusStoreTests.swift 2>/dev/null && head -5 FeedivoTests/ArticleStatusStoreTests.swift`

Falls die Datei existiert, mit dem darin verwendeten Test-Setup-Muster (z. B. In-Memory-Datenbank-Erzeugung) konsistent bleiben — die exakten Helfer aus der bestehenden Datei übernehmen, nicht neu erfinden. Falls sie nicht existiert, orientiere dich am Setup-Muster von `FeedivoTests/SQLiteSidebarStateTests.swift` (nutzt `FeedivoDatabase.inMemoryForTests()`).

- [ ] **Step 2: Neue Methode in `ArticleStatusStore.swift` ergänzen**

Nach der bestehenden `setHidden(_:articleID:at:)`-Methode, vor `private func updateBooleanStatus` einfügen:

```swift

    /// Markiert wirklich ALLE ungelesenen Artikel app-weit als gelesen —
    /// im Unterschied zu `SQLiteFeedArticleListView.markRowsRead(.allVisible)`,
    /// die nur auf die aktuell sichtbare Artikelliste wirkt. Für das
    /// Menubar-Dropdown (Feature 21.1), wo es keine "aktuelle Auswahl" gibt.
    func markAllUnreadAsRead() throws {
        let now = Date()
        var didUpdate = false

        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE article_statuses
                    SET isRead = 1, readAt = ?
                    WHERE isRead = 0
                    """,
                arguments: [now]
            )
            didUpdate = db.changesCount > 0

            if didUpdate {
                try db.execute(
                    sql: """
                        UPDATE article_identity_history
                        SET isRead = 1, readAt = ?
                        WHERE isRead = 0
                        """,
                    arguments: [now]
                )
            }
        }

        if didUpdate {
            try SQLiteUnreadCountService(database: database).rebuildAllFeedUnreadCounts()
            SQLiteDataInvalidation.bumpStatusVersion()
        }
    }
```

- [ ] **Step 3: Fehlschlagenden Test schreiben**

An `FeedivoTests/ArticleStatusStoreTests.swift` anhängen (Setup-Helfer aus der bestehenden Datei wiederverwenden — Platzhalter `<bestehendes Setup>` durch das tatsächliche Muster der Datei ersetzen, z. B. `let database = try FeedivoDatabase.inMemoryForTests()`):

```swift

    @Test func markAllUnreadAsReadSetztWirklichAlleUngelesenenArtikelAufGelesen() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let feed = FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed 1")
        try feedStore.save(feed)

        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)

        for index in 1...3 {
            let article = ArticleRecord(
                id: "article-\(index)",
                feedID: feed.id,
                title: "Artikel \(index)",
                link: nil,
                summary: nil,
                content: nil,
                publishedAt: Date(),
                arrivedAt: Date()
            )
            try articleStore.upsert(article)
            try statusStore.ensureStatus(articleID: article.id, dateArrived: Date())
        }

        try statusStore.markAllUnreadAsRead()

        for index in 1...3 {
            let status = try statusStore.status(articleID: "article-\(index)")
            #expect(status?.isRead == true)
        }
    }
```

Falls `ArticleRecord`s Initializer andere Parameter erwartet als oben angenommen: den tatsächlichen Initializer aus `Feedivo/Database/Records/ArticleRecord.swift` verwenden (per `grep -n "init(" Feedivo/Database/Records/ArticleRecord.swift` prüfen) — die Testabsicht (3 Artikel anlegen, alle auf ungelesen initialisieren, dann `markAllUnreadAsRead()` aufrufen, dann verifizieren, dass alle 3 `isRead == true` sind) bleibt in jedem Fall gleich.

- [ ] **Step 4: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen

- [ ] **Step 5: Test ausführen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/ArticleStatusStoreTests -quiet`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Stores/ArticleStatusStore.swift FeedivoTests/ArticleStatusStoreTests.swift
git commit -m "Feature 21.1: ArticleStatusStore.markAllUnreadAsRead() ergänzt"
```

---

## Task 3: Query für neueste ungelesene Artikel app-weit

**Files:**
- Modify: `Feedivo/Stores/ArticleDatabase.swift`
- Test: `FeedivoTests/ArticleDatabaseTests.swift` (bestehende Datei — Setup-Muster übernehmen)

**Interfaces:**
- Consumes: `ArticleDatabase.fetchUnreadArticles(feedIDs: Set<String>, includeHidden: Bool = false, limit: Int = 500) -> [ArticleListSnapshot]` (bereits vorhanden, sortiert `COALESCE(publishedAt, arrivedAt) DESC`), `FeedStore.feeds() throws -> [FeedRecord]` (bereits vorhanden)
- Produces: `ArticleDatabase.newestUnread(limit: Int) throws -> [ArticleListSnapshot]`

- [ ] **Step 1: Neue Methode in `ArticleDatabase.swift` ergänzen**

Nach der bestehenden `fetchUnreadArticles(feedIDs:includeHidden:limit:)`-Methode einfügen:

```swift

    /// Neueste ungelesene Artikel über ALLE Feeds hinweg, für das
    /// Menubar-Dropdown (Feature 21.1). Nutzt intern `fetchUnreadArticles`
    /// mit allen bekannten Feed-IDs statt einer Teilmenge.
    func newestUnread(limit: Int) throws -> [ArticleListSnapshot] {
        let allFeedIDs = try FeedStore(database: database).feeds().map(\.id)
        guard !allFeedIDs.isEmpty else {
            return []
        }

        return try fetchUnreadArticles(feedIDs: Set(allFeedIDs), limit: limit)
    }
```

- [ ] **Step 2: Fehlschlagenden Test schreiben**

An `FeedivoTests/ArticleDatabaseTests.swift` anhängen (Setup-Muster aus der bestehenden Datei übernehmen, insbesondere wie Feeds/Artikel dort bereits angelegt werden — `grep -n "func " FeedivoTests/ArticleDatabaseTests.swift | head -5` zur Orientierung):

```swift

    @Test func newestUnreadLiefertArtikelUeberAlleFeedsHinwegSortiertNachDatum() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let articleDatabase = ArticleDatabase(database: database)

        let feedA = FeedRecord(id: "feed-a", url: "https://a.example.com/feed", title: "Feed A")
        let feedB = FeedRecord(id: "feed-b", url: "https://b.example.com/feed", title: "Feed B")
        try feedStore.save(feedA)
        try feedStore.save(feedB)

        let older = ArticleRecord(
            id: "article-older",
            feedID: feedA.id,
            title: "Älterer Artikel",
            link: nil,
            summary: nil,
            content: nil,
            publishedAt: Date(timeIntervalSinceNow: -3600),
            arrivedAt: Date(timeIntervalSinceNow: -3600)
        )
        let newer = ArticleRecord(
            id: "article-newer",
            feedID: feedB.id,
            title: "Neuerer Artikel",
            link: nil,
            summary: nil,
            content: nil,
            publishedAt: Date(),
            arrivedAt: Date()
        )
        try articleStore.upsert(older)
        try articleStore.upsert(newer)
        try statusStore.ensureStatus(articleID: older.id, dateArrived: older.arrivedAt)
        try statusStore.ensureStatus(articleID: newer.id, dateArrived: newer.arrivedAt)

        let result = try articleDatabase.newestUnread(limit: 5)

        #expect(result.map(\.id) == ["article-newer", "article-older"])
    }

    @Test func newestUnreadRespektiertDasLimit() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let articleDatabase = ArticleDatabase(database: database)

        let feed = FeedRecord(id: "feed-a", url: "https://a.example.com/feed", title: "Feed A")
        try feedStore.save(feed)

        for index in 1...5 {
            let article = ArticleRecord(
                id: "article-\(index)",
                feedID: feed.id,
                title: "Artikel \(index)",
                link: nil,
                summary: nil,
                content: nil,
                publishedAt: Date(timeIntervalSinceNow: Double(-index)),
                arrivedAt: Date(timeIntervalSinceNow: Double(-index))
            )
            try articleStore.upsert(article)
            try statusStore.ensureStatus(articleID: article.id, dateArrived: article.arrivedAt)
        }

        let result = try articleDatabase.newestUnread(limit: 2)

        #expect(result.count == 2)
    }
```

Falls `ArticleRecord`s tatsächlicher Initializer von der obigen Annahme abweicht (siehe Hinweis in Task 2 Step 3), an den echten Initializer anpassen — die Testabsicht bleibt: zwei Feeds mit je einem Artikel unterschiedlichen Alters anlegen, prüfen dass `newestUnread` beide über Feed-Grenzen hinweg neueste-zuerst liefert, und dass `limit` die Ergebnisanzahl begrenzt.

- [ ] **Step 3: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen

- [ ] **Step 4: Tests ausführen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/ArticleDatabaseTests -quiet`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Stores/ArticleDatabase.swift FeedivoTests/ArticleDatabaseTests.swift
git commit -m "Feature 21.1: ArticleDatabase.newestUnread(limit:) für app-weite ungelesene Artikel ergänzt"
```

---

## Task 4: Menubar-Views (Icon-Label + Dropdown)

**Files:**
- Create: `Feedivo/Views/Menubar/MenubarIconLabel.swift`
- Create: `Feedivo/Views/Menubar/MenubarDropdownView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `MenubarSettings`, `MenubarArticleClickBehavior` (Task 1), `ArticleStatusStore.markAllUnreadAsRead()` (Task 2), `ArticleDatabase.newestUnread(limit:)` (Task 3), `AppIconBadgeService.unreadCount(in:)` (bestehend), `ArticleListItemSnapshot(sqliteSnapshot:)` (bestehend), `FeedViewModel.refreshAllFeeds(sqliteDatabase:)` (bestehend), `ArticleWindowRequest` (bestehend, `Feedivo/Views/Reader/ArticleWindowView.swift`)
- Produces: `MenubarIconLabel: View`, `MenubarDropdownView: View`

- [ ] **Step 1: L10n-Keys ergänzen**

In `L10n.swift`, nach den in Task 1 ergänzten `menubarArticleClickBehavior*`-Keys einfügen:

```swift
    static let menubarOpenFeedivoButton = LocalizedStringKey("menubar.openFeedivo.button")
    static let menubarRefreshButton = LocalizedStringKey("menubar.refresh.button")
    static let menubarMarkAllReadButton = LocalizedStringKey("menubar.markAllRead.button")
    static let menubarEmptyStateTitle = LocalizedStringKey("menubar.emptyState.title")
```

- [ ] **Step 2: Vier Einträge in `Localizable.xcstrings` ergänzen**

Analog zu Task 1 Step 3, alphabetisch einsortieren:

```json
    "menubar.emptyState.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Keine ungelesenen Artikel"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No unread articles"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aucun article non lu"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nessun articolo non letto"
          }
        }
      }
    },
    "menubar.markAllRead.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Alle als gelesen markieren"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Mark all as read"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Tout marquer comme lu"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Segna tutti come letti"
          }
        }
      }
    },
    "menubar.openFeedivo.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feedivo öffnen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Open Feedivo"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ouvrir Feedivo"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Apri Feedivo"
          }
        }
      }
    },
    "menubar.refresh.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aktualisieren"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Refresh"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Actualiser"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aggiorna"
          }
        }
      }
    },
```

Run: `python3 -c "import json; json.load(open('Feedivo/Resources/Localizable.xcstrings')); print('valid JSON')"`
Expected: `valid JSON`

- [ ] **Step 3: `MenubarIconLabel.swift` anlegen**

```swift
import SwiftUI

/// Icon + Badge-Text für die Menubar-Scene (Feature 21.1). Nutzt denselben
/// Unread-Count wie das Dock-Icon-Badge (`AppIconBadgeService`).
struct MenubarIconLabel: View {
    let unreadCount: Int

    var body: some View {
        Label {
            Text(unreadCount > 0 ? "\(unreadCount)" : "")
        } icon: {
            Image(systemName: unreadCount > 0 ? "tray.full" : "tray")
        }
        .labelStyle(.titleAndIcon)
    }
}
```

- [ ] **Step 4: `MenubarDropdownView.swift` anlegen**

```swift
import SwiftUI

/// Dropdown-Inhalt des Menubar-Icons (Feature 21.1): Header mit
/// Öffnen-/Refresh-Buttons, Liste der neuesten ungelesenen Artikel,
/// Footer mit globalem "Alle als gelesen markieren".
struct MenubarDropdownView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    @AppStorage(MenubarSettings.articleCountKey)
    private var articleCount = MenubarSettings.defaultArticleCount

    @AppStorage(MenubarArticleClickBehavior.storageKey)
    private var articleClickBehaviorRawValue = MenubarArticleClickBehavior.defaultBehavior.rawValue

    let feedViewModel: FeedViewModel

    @State private var articles: [ArticleListItemSnapshot] = []
    @State private var isRefreshing = false

    private var clickBehavior: MenubarArticleClickBehavior {
        MenubarArticleClickBehavior.resolved(from: articleClickBehaviorRawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(L10n.menubarOpenFeedivoButton) {
                    openMainWindow()
                }

                Spacer()

                Button {
                    Task {
                        await refresh()
                    }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
            .padding([.horizontal, .top], 12)

            Divider()

            if articles.isEmpty {
                Text(L10n.menubarEmptyStateTitle)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(articles) { article in
                    Button {
                        open(article)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(article.title)
                                .lineLimit(1)
                            if let feedTitle = article.feedTitle {
                                Text(feedTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                }

                Divider()

                Button(L10n.menubarMarkAllReadButton) {
                    markAllRead()
                }
                .padding([.horizontal, .bottom], 12)
            }
        }
        .frame(width: 320)
        .task(id: articleCount) {
            loadArticles()
        }
    }

    private func loadArticles() {
        guard let feedivoDatabase else {
            articles = []
            return
        }

        let resolvedCount = MenubarSettings.resolvedArticleCount(from: articleCount)
        let snapshots = (try? ArticleDatabase(database: feedivoDatabase).newestUnread(limit: resolvedCount)) ?? []
        articles = snapshots.map(ArticleListItemSnapshot.init(sqliteSnapshot:))
    }

    private func refresh() async {
        guard let feedivoDatabase else { return }

        isRefreshing = true
        await feedViewModel.refreshAllFeeds(sqliteDatabase: feedivoDatabase)
        loadArticles()
        isRefreshing = false
    }

    private func markAllRead() {
        guard let feedivoDatabase else { return }

        try? ArticleStatusStore(database: feedivoDatabase).markAllUnreadAsRead()
        loadArticles()
    }

    private func open(_ article: ArticleListItemSnapshot) {
        switch clickBehavior {
        case .inFeedivo:
            if let uuid = UUID(uuidString: article.id) {
                openWindow(value: ArticleWindowRequest(articleID: uuid))
            }
        case .inBrowser:
            if let link = article.hasOriginalURL ? articleOriginalURL(for: article) : nil {
                openURL(link)
            }
        }
    }

    private func articleOriginalURL(for article: ArticleListItemSnapshot) -> URL? {
        guard let feedivoDatabase else { return nil }
        guard let record = try? ArticleStore(database: feedivoDatabase).article(id: article.id) else {
            return nil
        }
        guard let link = record.link else { return nil }
        return URL(string: link)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.identifier?.rawValue.contains("main") == true {
            window.makeKeyAndOrderFront(nil)
            return
        }
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}
```

**Hinweis für die Umsetzung:** `ArticleStore.article(id:) -> ArticleRecord?` wird hier als bereits existierende Methode angenommen (Standard-Einzelabruf-Pattern, das in praktisch jedem Store dieses Projekts existiert, siehe `FeedStore.feed(id:)`). Falls die Methode unter anderem Namen existiert oder fehlt: per `grep -n "func article(id" Feedivo/Stores/ArticleStore.swift` den echten Namen ermitteln und anpassen, oder — falls sie fehlt — nach demselben Muster wie `FeedStore.feed(id:)` (GRDB `fetchOne(db, key:)`) ergänzen. `openMainWindow()` ist ein pragmatischer Fallback über den AppKit-Fenstertitel; falls das Hauptfenster in `FeedivoApp.swift` eine dedizierte `id` bekommt (siehe Task 5), diese stattdessen für einen gezielten `openWindow(id:)`-Aufruf nutzen.

- [ ] **Step 5: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen (kein Test für diesen rein UI-bezogenen Task, siehe Spec-Abschnitt "Testing")

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Menubar/MenubarIconLabel.swift Feedivo/Views/Menubar/MenubarDropdownView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature 21.1: MenubarIconLabel + MenubarDropdownView (Artikelliste, Refresh, Alle-gelesen, Klick-Verhalten)"
```

---

## Task 5: MenuBarExtra-Scene + Dock-Icon-Toggle in `FeedivoApp.swift`

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift`

**Interfaces:**
- Consumes: `MenubarSettings`, `MenubarIconLabel`, `MenubarDropdownView` (Tasks 1 + 4), `AppIconBadgeService.unreadCount(in:)` (bestehend, bereits im Dock-Badge-Pfad verwendet)

- [ ] **Step 1: Neue `@AppStorage`-Properties ergänzen**

In `FeedivoApp.swift`, nach der bestehenden `articleRetentionIncludesProtectedArticles`-Property einfügen:

```swift

    @AppStorage(MenubarSettings.isEnabledKey)
    private var menubarIsEnabled = MenubarSettings.defaultIsEnabled

    @AppStorage(MenubarSettings.hidesDockIconKey)
    private var menubarHidesDockIcon = MenubarSettings.defaultHidesDockIcon

    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0

    @State private var menubarUnreadCount = 0
```

- [ ] **Step 2: Neue Scene im `body` ergänzen**

Nach der schließenden `.windowResizability(.contentSize)`-Zeile der `Settings`-Scene (letzte Scene im `body`) einfügen:

```swift

        MenuBarExtra(isInserted: $menubarIsEnabled) {
            MenubarDropdownView(feedViewModel: feedViewModel)
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
        } label: {
            MenubarIconLabel(unreadCount: menubarUnreadCount)
        }
        .menuBarExtraStyle(.window)
```

- [ ] **Step 3: Dock-Icon-Toggle + Badge-Update verdrahten**

Im `WindowGroup`-Block (Haupt-Scene), nach dem bestehenden `.onChange(of: articleRetentionIncludesProtectedArticles)`-Block einfügen:

```swift
                .onChange(of: menubarHidesDockIcon) {
                    applyDockIconVisibility()
                }
                .task {
                    applyDockIconVisibility()
                    updateMenubarUnreadCount()
                }
                .onChange(of: sqliteStatusVersion) {
                    updateMenubarUnreadCount()
                }
```

- [ ] **Step 4: Hilfsmethoden ergänzen**

Nach der bestehenden `trimImageCacheToSelectedLimit()`-Methode einfügen:

```swift

    private func applyDockIconVisibility() {
        NSApp.setActivationPolicy(menubarHidesDockIcon ? .accessory : .regular)
    }

    @MainActor
    private func updateMenubarUnreadCount() {
        guard let sidebarFeeds = try? FeedStore(database: feedivoDatabase).sidebarFeeds() else {
            return
        }

        menubarUnreadCount = AppIconBadgeService.unreadCount(in: sidebarFeeds)
    }
```

`import AppKit` am Dateianfang ergänzen (für `NSApp`/`NSApplication.ActivationPolicy`), falls noch nicht vorhanden — `grep -n "^import" Feedivo/App/FeedivoApp.swift` prüfen.

- [ ] **Step 5: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen

- [ ] **Step 6: Commit**

```bash
git add Feedivo/App/FeedivoApp.swift
git commit -m "Feature 21.1: MenuBarExtra-Scene + Dock-Icon-Toggle (NSApp.setActivationPolicy) in FeedivoApp.swift"
```

---

## Task 6: Settings-UI-Tab "Menubar"

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `MenubarSettings`, `MenubarArticleClickBehavior` (Task 1)

- [ ] **Step 1: L10n-Keys ergänzen**

Nach den in Task 4 ergänzten `menubar*`-Keys in `L10n.swift` einfügen:

```swift
    static let settingsMenubarIsEnabledTitle = LocalizedStringKey("settings.menubar.isEnabled.title")
    static let settingsMenubarIsEnabledDescription = LocalizedStringKey("settings.menubar.isEnabled.description")
    static let settingsMenubarArticleCountTitle = LocalizedStringKey("settings.menubar.articleCount.title")
    static let settingsMenubarArticleCountDescription = LocalizedStringKey("settings.menubar.articleCount.description")
    static let settingsMenubarArticleClickBehaviorTitle = LocalizedStringKey("settings.menubar.articleClickBehavior.title")
    static let settingsMenubarArticleClickBehaviorDescription = LocalizedStringKey("settings.menubar.articleClickBehavior.description")
    static let settingsMenubarHidesDockIconTitle = LocalizedStringKey("settings.menubar.hidesDockIcon.title")
    static let settingsMenubarHidesDockIconDescription = LocalizedStringKey("settings.menubar.hidesDockIcon.description")
```

- [ ] **Step 2: Acht Einträge in `Localizable.xcstrings` ergänzen**

Alphabetisch einsortieren (per `grep -n '"settings.menubar' Feedivo/Resources/Localizable.xcstrings` den korrekten Nachbarn finden):

```json
    "settings.menubar.articleClickBehavior.description" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Legt fest, ob ein Klick auf einen Artikel im Menubar-Dropdown ihn in Feedivo oder im Standardbrowser öffnet." } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Controls whether clicking an article in the menubar dropdown opens it in Feedivo or your default browser." } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Définit si un clic sur un article dans le menu de la barre des menus l'ouvre dans Feedivo ou dans le navigateur par défaut." } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Stabilisce se un clic su un articolo nel menu della barra dei menu lo apre in Feedivo o nel browser predefinito." } }
      }
    },
    "settings.menubar.articleClickBehavior.title" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Artikel öffnen" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Open article" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Ouvrir l'article" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Apri articolo" } }
      }
    },
    "settings.menubar.articleCount.description" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Wie viele der neuesten ungelesenen Artikel im Menubar-Dropdown angezeigt werden." } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "How many of the newest unread articles are shown in the menubar dropdown." } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Nombre des articles non lus les plus récents affichés dans le menu de la barre des menus." } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Quanti dei più recenti articoli non letti vengono mostrati nel menu della barra dei menu." } }
      }
    },
    "settings.menubar.articleCount.title" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Artikelanzahl" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Article count" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Nombre d'articles" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Numero di articoli" } }
      }
    },
    "settings.menubar.hidesDockIcon.description" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Blendet das Dock-Icon aus — Feedivo ist dann nur noch über das Menubar-Icon erreichbar. Wirkt sofort, kein Neustart nötig." } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Hides the Dock icon — Feedivo is then only reachable via the menubar icon. Takes effect immediately, no restart needed." } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Masque l'icône du Dock — Feedivo n'est alors accessible que via l'icône de la barre des menus. Effet immédiat, sans redémarrage." } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Nasconde l'icona nel Dock — Feedivo sarà raggiungibile solo tramite l'icona nella barra dei menu. Ha effetto immediato, senza riavvio." } }
      }
    },
    "settings.menubar.hidesDockIcon.title" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Dock-Icon ausblenden" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Hide Dock icon" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Masquer l'icône du Dock" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Nascondi icona nel Dock" } }
      }
    },
    "settings.menubar.isEnabled.description" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Zeigt ein Feedivo-Icon in der Menüleiste mit Dropdown für die neuesten ungelesenen Artikel." } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Shows a Feedivo icon in the menu bar with a dropdown for the newest unread articles." } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Affiche une icône Feedivo dans la barre des menus avec un menu pour les articles non lus les plus récents." } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Mostra un'icona Feedivo nella barra dei menu con un menu per gli articoli non letti più recenti." } }
      }
    },
    "settings.menubar.isEnabled.title" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Menubar-Icon anzeigen" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Show menubar icon" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Afficher l'icône de la barre des menus" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Mostra icona nella barra dei menu" } }
      }
    },
```

Run: `python3 -c "import json; json.load(open('Feedivo/Resources/Localizable.xcstrings')); print('valid JSON')"`
Expected: `valid JSON`

- [ ] **Step 3: Neue Section-Case in `NewSettingsSection` ergänzen**

In `SettingsView.swift`, nach `case articleList` (Feature 19.1) einfügen:

```swift
    case menubar
```

Titel-`switch` (nach `case .articleList: "Artikelliste"`):

```swift
        case .menubar:
            "Menubar"
```

Icon-`switch` (nach `case .articleList: "list.bullet"`):

```swift
        case .menubar:
            "menubar.rectangle"
```

- [ ] **Step 4: Tab + Content-Routing ergänzen**

Im `TabView`-Body, nach `settingsTab(.articleList)`:

```swift
            settingsTab(.menubar)
```

Im `settingsContent(for:)`-Switch, nach `case .articleList: NewArticleListSettingsView()`:

```swift
        case .menubar:
            NewMenubarSettingsView()
```

- [ ] **Step 5: `NewMenubarSettingsView` anlegen**

Nach der `NewArticleListSettingsView`-Struct (Feature 19.1) einfügen:

```swift
private struct NewMenubarSettingsView: View {
    @AppStorage(MenubarSettings.isEnabledKey)
    private var menubarIsEnabled = MenubarSettings.defaultIsEnabled

    @AppStorage(MenubarSettings.articleCountKey)
    private var menubarArticleCount = MenubarSettings.defaultArticleCount

    @AppStorage(MenubarArticleClickBehavior.storageKey)
    private var menubarArticleClickBehaviorRawValue = MenubarArticleClickBehavior.defaultBehavior.rawValue

    @AppStorage(MenubarSettings.hidesDockIconKey)
    private var menubarHidesDockIcon = MenubarSettings.defaultHidesDockIcon

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewSettingsBlock(eyebrow: "Menubar") {
                NewSettingRow(
                    title: L10n.settingsMenubarIsEnabledTitle,
                    description: L10n.settingsMenubarIsEnabledDescription
                ) {
                    Toggle("", isOn: $menubarIsEnabled)
                        .labelsHidden()
                }

                NewSettingRow(
                    title: L10n.settingsMenubarArticleCountTitle,
                    description: L10n.settingsMenubarArticleCountDescription
                ) {
                    Stepper(
                        "\(menubarArticleCount)",
                        value: $menubarArticleCount,
                        in: MenubarSettings.allowedArticleCountRange
                    )
                    .disabled(!menubarIsEnabled)
                    .fixedSize()
                }

                NewSettingRow(
                    title: L10n.settingsMenubarArticleClickBehaviorTitle,
                    description: L10n.settingsMenubarArticleClickBehaviorDescription
                ) {
                    Picker("", selection: $menubarArticleClickBehaviorRawValue) {
                        ForEach(MenubarArticleClickBehavior.allCases) { behavior in
                            Text(behavior.titleKey)
                                .tag(behavior.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(!menubarIsEnabled)
                }

                NewSettingRow(
                    title: L10n.settingsMenubarHidesDockIconTitle,
                    description: L10n.settingsMenubarHidesDockIconDescription
                ) {
                    Toggle("", isOn: $menubarHidesDockIcon)
                        .labelsHidden()
                        .disabled(!menubarIsEnabled)
                }
            }
        }
    }
}
```

- [ ] **Step 6: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature 21.1: Settings-Tab 'Menubar' (Aktivieren, Artikelanzahl, Klick-Verhalten, Dock-Icon)"
```

---

## Task 7: FEATURES.md aktualisieren, finaler Build/Test-Durchlauf, Commit

**Files:**
- Modify: `FEATURES.md`

- [ ] **Step 1: Feature-21.1-Statuszeile aktualisieren**

`grep -n "### 21.1" FEATURES.md` ausführen, um die aktuelle Zeilennummer zu bestätigen. Den Abschnitt (aktuell beginnend mit `### 21.1 Menubar-Icon` gefolgt von `- **Status:** ✅ Entschieden — bereit zur Implementierung` und der `- **Zu implementieren:**`-Liste) so ersetzen, dass er auf `✔️ Fertig` steht und jeder Unterpunkt mit `— umgesetzt 2026-07-10` markiert ist, analog zum bei Feature 19.1 etablierten Muster (siehe `### 19.1` im selben Dokument als Vorbild für Formatierung).

- [ ] **Step 2: Kapitelübersicht-Zeile aktualisieren**

`grep -n "Feature 21.1" FEATURES.md` ausführen, um die entsprechende Zeile im Übersichts-Abschnitt zu finden (aktuell: `28. **Feature 21.1** — Menubar-App (Dropdown, Badge, ohne Dock, konfigurierbar)`). Den Zusatz `— vollständig umgesetzt (2026-07-10)` anhängen.

- [ ] **Step 3: Finaler Build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen

- [ ] **Step 4: Gesamte betroffene Testabdeckung final laufen lassen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MenubarSettingsTests -only-testing:FeedivoTests/ArticleStatusStoreTests -only-testing:FeedivoTests/ArticleDatabaseTests -quiet`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add FEATURES.md
git commit -m "Feature 21.1: FEATURES.md auf vollständig umgesetzt aktualisiert"
```

- [ ] **Step 6: Manuelle Verifikation vormerken (nicht automatisierbar)**

Kein computer-use für native macOS-Apps in dieser Umgebung verfügbar. Nach Abschluss dem Nutzer explizit mitteilen, dass folgende Punkte manuell zu prüfen sind:
- Menubar-Icon erscheint/verschwindet beim Toggle in den Einstellungen
- Badge-Zähler stimmt mit dem Dock-Badge überein und aktualisiert sich nach Statusänderungen
- Dropdown zeigt die eingestellte Artikelanzahl, Refresh-Spinner läuft sichtbar
- "Alle als gelesen markieren" leert das Dropdown und aktualisiert Sidebar-Badges sofort
- Dock-Icon-Toggle wirkt sofort ohne Neustart, Hauptfenster/Menüleisten-Shortcuts bleiben nutzbar
- Artikel-Klick öffnet je nach Einstellung im Feedivo-Fenster oder im Browser

---

## Self-Review-Notiz (für den Plan-Autor, nicht Teil der Ausführung)

- **Spec-Abdeckung:** Alle 6 FEATURES.md-Unterpunkte (Dropdown, konfigurierbare Anzahl, Refresh, Alle-gelesen, Badge, Dock-Icon-Einstellung, Klick-Verhalten) sind über Task 1–6 abgedeckt, Task 7 schließt Doku + finale Verifikation ab.
- **Bewusste Unschärfen (dokumentiert, kein Platzhalter):** Task 2/3/4 markieren explizit, dass der exakte `ArticleRecord`-Initializer und `ArticleStore.article(id:)` zur Implementierungszeit gegen den echten Code verifiziert werden müssen, falls er von der angenommenen Signatur abweicht — die Testabsicht bleibt in jedem Fall eindeutig spezifiziert, kein TBD. Dies ist dieselbe Art von Abweichung, die bei Feature 19.1 mehrfach auftrat (Datei-Drift zwischen Planerstellung und Ausführung) und dort jedes Mal sauber aufgelöst wurde.
- **Typkonsistenz:** `MenubarSettings`, `MenubarArticleClickBehavior` werden in allen Tasks identisch benannt und referenziert; `openMainWindow()` in Task 4 ist als pragmatischer Fallback dokumentiert.
