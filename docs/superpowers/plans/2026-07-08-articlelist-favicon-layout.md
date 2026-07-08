# Artikelliste Favicon + Bild-/Feedname-Position Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In der Artikelliste (`ArticleRowView`) drei neue Darstellungs-
Einstellungen ergänzen: Vorschaubild-Position (Links/Rechts/Aus), ein Favicon
vor dem Feedname-Text, und eine konfigurierbare Position der Feedname-Zeile
(vor oder nach dem Artikeltitel).

**Architecture:** Zwei neue reine Enums + ein Bool-Settings-Namespace in einer
neuen Datei (`ArticleListDisplaySettings.swift`, Muster wie
`ReaderDisplayMode.swift`). Favicon-URL wird von SQLite über fünf bestehende
`ArticleListSnapshot`-Query-Stellen bis zu `ArticleListItemSnapshot`
durchgereicht (Favicon-Rendering-Muster wie `FeedRowView.faviconView`).
`ArticleRowView` liest die drei neuen `@AppStorage`-Werte und ordnet
Vorschaubild/Feedname-Zeile entsprechend an.

**Tech Stack:** SwiftUI (macOS), GRDB/SQLite, Swift Testing (`@Test`/`#expect`),
`L10n.swift` + `Localizable.xcstrings` (de/en/fr/it).

## Global Constraints

- Default-Werte entsprechen exakt dem heutigen, fest verdrahteten Verhalten:
  `ArticleListImagePosition.defaultPosition = .left`,
  `ArticleListFeedNamePosition.defaultPosition = .afterTitle`,
  `ArticleListFeedNameVisibilitySettings.defaultShowsFeedName = true`. Kein
  Verhaltensbruch für Bestandsnutzer nach dem Update.
- `ArticleListSnapshot.faviconURL` MUSS einen Default-Wert `= nil` haben,
  damit die drei bestehenden Test-Dateien, die `ArticleListSnapshot(...)`
  direkt konstruieren (`ArticleListItemSnapshotTests.swift`,
  `ArticleListQueryTests.swift`, `SQLiteFeedArticleListStateTests.swift`),
  ohne Anpassung weiter kompilieren.
- Ist "Feed-Name anzeigen" ausgeschaltet (oder `feedTitle` leer/nil), bleibt
  der Zeitpunkt trotzdem sichtbar; nur Feedname und Favicon verschwinden.
- Kein Favicon rendern, wenn der Feedname nicht angezeigt wird (Favicon ist
  an die Feedname-Sichtbarkeit gekoppelt, nicht unabhängig schaltbar).
- Kommentare im Code auf Deutsch (Projekt-Konvention).
- SourceKit-Diagnosen in der IDE sind oft veraltet/falsch — verlässlich ist
  nur ein echter `xcodebuild build`-Lauf.
- Volle Testsuite (`xcodebuild test` ohne `-only-testing`) hängt bekanntermaßen
  — immer gezielt mit `-only-testing:FeedivoTests/<SuiteName>` testen.

---

### Task 1: Neue Settings-Typen + Tests

**Files:**
- Create: `Feedivo/Views/ArticleList/ArticleListDisplaySettings.swift`
- Test: `FeedivoTests/ArticleListDisplaySettingsTests.swift`

**Interfaces:**
- Produces: `ArticleListImagePosition` (enum, `.left`/`.right`/`.hidden`,
  `storageKey`, `defaultPosition`, `titleKey`, `resolved(from:)`),
  `ArticleListFeedNamePosition` (enum, `.beforeTitle`/`.afterTitle`,
  `storageKey`, `defaultPosition`, `titleKey`, `resolved(from:)`),
  `ArticleListFeedNameVisibilitySettings` (enum-Namespace,
  `showsFeedNameKey: String`, `defaultShowsFeedName: Bool`)

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Erstelle `FeedivoTests/ArticleListDisplaySettingsTests.swift`:

```swift
import Testing
@testable import Feedivo

struct ArticleListDisplaySettingsTests {

    @Test func imagePositionResolvedFaelltBeiUnbekanntemRohwertAufDefaultZurueck() {
        #expect(ArticleListImagePosition.resolved(from: "left") == .left)
        #expect(ArticleListImagePosition.resolved(from: "right") == .right)
        #expect(ArticleListImagePosition.resolved(from: "hidden") == .hidden)
        #expect(ArticleListImagePosition.resolved(from: "unknown") == ArticleListImagePosition.defaultPosition)
    }

    @Test func imagePositionDefaultIstLinks() {
        #expect(ArticleListImagePosition.defaultPosition == .left)
    }

    @Test func feedNamePositionResolvedFaelltBeiUnbekanntemRohwertAufDefaultZurueck() {
        #expect(ArticleListFeedNamePosition.resolved(from: "beforeTitle") == .beforeTitle)
        #expect(ArticleListFeedNamePosition.resolved(from: "afterTitle") == .afterTitle)
        #expect(ArticleListFeedNamePosition.resolved(from: "unknown") == ArticleListFeedNamePosition.defaultPosition)
    }

    @Test func feedNamePositionDefaultIstNachDemTitel() {
        #expect(ArticleListFeedNamePosition.defaultPosition == .afterTitle)
    }

    @Test func feedNameVisibilityDefaultIstAn() {
        #expect(ArticleListFeedNameVisibilitySettings.defaultShowsFeedName == true)
    }
}
```

- [ ] **Step 2: Test laufen lassen, um das Fehlschlagen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListDisplaySettingsTests`
Expected: FAIL — `Cannot find 'ArticleListImagePosition' in scope`

- [ ] **Step 3: Minimale Implementierung schreiben**

Erstelle `Feedivo/Views/ArticleList/ArticleListDisplaySettings.swift`:

```swift
import SwiftUI

/// Position des Vorschaubilds in der Artikelliste (Feature 19.1).
enum ArticleListImagePosition: String, CaseIterable, Identifiable {
    case left
    case right
    case hidden

    static let storageKey = "articleList.imagePosition"
    static let defaultPosition = ArticleListImagePosition.left

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .left:
            L10n.articleListImagePositionLeft
        case .right:
            L10n.articleListImagePositionRight
        case .hidden:
            L10n.articleListImagePositionHidden
        }
    }

    static func resolved(from rawValue: String) -> ArticleListImagePosition {
        ArticleListImagePosition(rawValue: rawValue) ?? defaultPosition
    }
}

/// Position der Feedname-Zeile (Favicon + Feedname + Zeitpunkt) relativ zum
/// Artikeltitel (Feature 19.1).
enum ArticleListFeedNamePosition: String, CaseIterable, Identifiable {
    case beforeTitle
    case afterTitle

    static let storageKey = "articleList.feedNamePosition"
    static let defaultPosition = ArticleListFeedNamePosition.afterTitle

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .beforeTitle:
            L10n.articleListFeedNamePositionBeforeTitle
        case .afterTitle:
            L10n.articleListFeedNamePositionAfterTitle
        }
    }

    static func resolved(from rawValue: String) -> ArticleListFeedNamePosition {
        ArticleListFeedNamePosition(rawValue: rawValue) ?? defaultPosition
    }
}

/// Ob der Feedname (und damit auch das Favicon) pro Artikel angezeigt wird.
/// Der Zeitpunkt bleibt unabhängig davon immer sichtbar (siehe `ArticleRowView`).
enum ArticleListFeedNameVisibilitySettings {
    static let showsFeedNameKey = "articleList.showsFeedName"
    static let defaultShowsFeedName = true
}
```

- [ ] **Step 4: Test laufen lassen, um das Bestehen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListDisplaySettingsTests`
Expected: PASS (alle 5 Tests grün)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleListDisplaySettings.swift FeedivoTests/ArticleListDisplaySettingsTests.swift
git commit -m "Artikelliste: Neue Settings-Typen für Bild-Position, Feedname-Position und -Sichtbarkeit"
```

---

### Task 2: Favicon-Plumbing (SQL → Snapshot → View-Snapshot)

**Files:**
- Modify: `Feedivo/Snapshots/ArticleListSnapshot.swift`
- Modify: `Feedivo/Stores/TimelineStore.swift`
- Modify: `Feedivo/Stores/ArticleStore.swift`
- Modify: `Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift`
- Test: `FeedivoTests/ArticleListSnapshotFaviconTests.swift`

**Interfaces:**
- Produces: `ArticleListSnapshot.faviconURL: String?` (Default `nil`),
  `ArticleListItemSnapshot.faviconURL: String?`

- [ ] **Step 1: Schreibe den fehlschlagenden Test**

Erstelle `FeedivoTests/ArticleListSnapshotFaviconTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct ArticleListSnapshotFaviconTests {

    @Test func timelineArticlesLiefertFaviconURLDesFeeds() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(
            FeedRecord(
                id: "feed-1",
                url: "https://example.com/feed.xml",
                title: "Example",
                faviconURL: "https://example.com/favicon.ico"
            )
        )
        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "one", title: "One")
        )

        let snapshots = try timelineStore.articles(
            scope: .feed("feed-1"),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.first?.faviconURL == "https://example.com/favicon.ico")
    }

    @Test func articleListItemSnapshotUebernimmtFaviconURLAusSqliteSnapshot() {
        let sqliteSnapshot = ArticleListSnapshot(
            id: "article-1",
            feedID: "feed-1",
            feedTitle: "Example",
            title: "Title",
            summary: nil,
            link: nil,
            imageURL: nil,
            publishedAt: nil,
            arrivedAt: Date(),
            estimatedReadingMinutes: nil,
            isRead: false,
            isStarred: false,
            isArchived: false,
            isHidden: false,
            faviconURL: "https://example.com/favicon.ico"
        )

        let itemSnapshot = ArticleListItemSnapshot(sqliteSnapshot: sqliteSnapshot)

        #expect(itemSnapshot.faviconURL == "https://example.com/favicon.ico")
    }
}
```

- [ ] **Step 2: Test laufen lassen, um das Fehlschlagen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListSnapshotFaviconTests`
Expected: FAIL — `extra argument 'faviconURL' in call` (bzw. `Value of type
'ArticleListItemSnapshot' has no member 'faviconURL'`)

- [ ] **Step 3: `ArticleListSnapshot` um `faviconURL` erweitern**

In `Feedivo/Snapshots/ArticleListSnapshot.swift` die bestehende
`var offlineStateRaw: String = ArticleOfflineState.none.rawValue`-Zeile durch
folgende zwei Zeilen ersetzen (Reihenfolge: `faviconURL` VOR
`offlineStateRaw`, damit es direkt neben den anderen Feed-/Artikel-Metadaten
steht):

```swift
    var faviconURL: String?
    var offlineStateRaw: String = ArticleOfflineState.none.rawValue
```

- [ ] **Step 4: SQL-`FetchableRecord`-Mapping erweitern**

In `Feedivo/Stores/TimelineStore.swift`, in
`extension ArticleListSnapshot: FetchableRecord { init(row: Row) throws { ... } }`,
direkt nach der Zeile `isHidden = row["isHidden"]` einfügen:

```swift
        faviconURL = row["faviconURL"]
```

- [ ] **Step 5: `f.faviconURL AS faviconURL,` in allen 5 SQL-Blöcken ergänzen**

In JEDEM der folgenden 5 SQL-`SELECT`-Blöcke direkt nach der Zeile
`f.title AS feedTitle,` eine neue Zeile `f.faviconURL AS faviconURL,`
einfügen (identische Änderung an allen 5 Stellen — alle haben bereits
`JOIN feeds f ON f.id = a.feedID`):

1. `Feedivo/Stores/TimelineStore.swift` — Funktion `articles(...)`, SQL ab
   `SELECT\n    a.id,\n    a.feedID,\n    f.title AS feedTitle,`
2. `Feedivo/Stores/ArticleStore.swift` — Funktion `latestArticleForFeed`,
   ERSTER `ArticleListSnapshot.fetchOne`-Block (mit
   `AND a.publishedAt IS NOT NULL`)
3. `Feedivo/Stores/ArticleStore.swift` — Funktion `latestArticleForFeed`,
   ZWEITER `ArticleListSnapshot.fetchOne`-Block (Fallback ohne
   `publishedAt`-Filter)
4. `Feedivo/Stores/ArticleStore.swift` — Funktion
   `searchArticles(matching:includeHidden:limit:)`
5. `Feedivo/Stores/ArticleStore.swift` — Funktion
   `searchArticles(state:includeHidden:limit:)`

Beispiel für die Änderung (gilt analog für alle 5 Stellen):

```swift
                SELECT
                    a.id,
                    a.feedID,
                    f.title AS feedTitle,
                    f.faviconURL AS faviconURL,
                    a.title,
```

- [ ] **Step 6: `ArticleListItemSnapshot` um `faviconURL` erweitern**

In `Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift` die Property
`let hasOriginalURL: Bool` NACH folgender neuer Zeile ergänzen:

```swift
    let faviconURL: String?
```

Und im `init(sqliteSnapshot:)` direkt nach
`self.imageURL = sqliteSnapshot.imageURL` einfügen:

```swift
        self.faviconURL = sqliteSnapshot.faviconURL
```

- [ ] **Step 7: Test laufen lassen, um das Bestehen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListSnapshotFaviconTests`
Expected: PASS (beide Tests grün)

- [ ] **Step 8: Bestehende Artikelisten-Tests laufen lassen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteTimelineStoreTests -only-testing:FeedivoTests/ArticleListItemSnapshotTests -only-testing:FeedivoTests/ArticleListQueryTests -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests`
Expected: PASS (alle Suiten grün — bestätigt, dass die bestehenden
Test-Konstruktionsaufrufe von `ArticleListSnapshot(...)` dank
Default-Wert `faviconURL = nil` weiterhin kompilieren und funktionieren)

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Snapshots/ArticleListSnapshot.swift Feedivo/Stores/TimelineStore.swift Feedivo/Stores/ArticleStore.swift Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift FeedivoTests/ArticleListSnapshotFaviconTests.swift
git commit -m "Artikelliste: Feed-Favicon-URL durch SQL/Snapshot-Schichten durchgereicht"
```

---

### Task 3: `ArticleRowView` — Favicon, Bild-Position, Feedname-Position

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleRowView.swift`

**Interfaces:**
- Consumes: `ArticleListImagePosition`, `ArticleListFeedNamePosition`,
  `ArticleListFeedNameVisibilitySettings` (Task 1),
  `ArticleListItemSnapshot.faviconURL` (Task 2), `CachedRemoteImageView`
  (bestehender Typ, siehe `FeedRowView.swift` für Verwendungsmuster)
- Produces: keine neuen öffentlichen Symbole — reine View-Umstrukturierung

Kein separater Unit-Test: SwiftUI-View-Layout wird wie bei Feature 1.12/3.4
manuell verifiziert (Task 4).

- [ ] **Step 1: Neue `@AppStorage`-Properties ergänzen**

In `Feedivo/Views/ArticleList/ArticleRowView.swift` direkt nach
`@Environment(\.interfaceTextSize) private var interfaceTextSize` einfügen:

```swift

    @AppStorage(ArticleListImagePosition.storageKey)
    private var imagePositionRawValue = ArticleListImagePosition.defaultPosition.rawValue

    @AppStorage(ArticleListFeedNameVisibilitySettings.showsFeedNameKey)
    private var showsFeedName = ArticleListFeedNameVisibilitySettings.defaultShowsFeedName

    @AppStorage(ArticleListFeedNamePosition.storageKey)
    private var feedNamePositionRawValue = ArticleListFeedNamePosition.defaultPosition.rawValue

    private var imagePosition: ArticleListImagePosition {
        ArticleListImagePosition.resolved(from: imagePositionRawValue)
    }

    private var feedNamePosition: ArticleListFeedNamePosition {
        ArticleListFeedNamePosition.resolved(from: feedNamePositionRawValue)
    }
```

- [ ] **Step 2: `body` umstrukturieren**

Den bestehenden `body` (aktuell Zeilen 21-64) komplett ersetzen:

```swift
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if imagePosition == .left {
                previewImage
            }

            VStack(alignment: .leading, spacing: 6) {
                if feedNamePosition == .beforeTitle {
                    metadataRow
                }

                Text(snapshot.title)
                    .font(interfaceTextSize.font(size: 14, weight: snapshot.isRead ? .regular : .semibold))
                    .fontWeight(snapshot.isRead ? .regular : .semibold)
                    .foregroundStyle(snapshot.isRead ? .secondary : .primary)
                    .lineLimit(2)

                if feedNamePosition == .afterTitle {
                    metadataRow
                }

                if let summary = snapshot.summary, !summary.isEmpty {
                    Text(summary)
                        .font(interfaceTextSize.font(size: 13))
                        .foregroundStyle(snapshot.isRead ? .tertiary : .secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if imagePosition == .right {
                previewImage
            }

            VStack {
                unreadIndicator

                Spacer(minLength: 8)

                Button(action: onToggleStarred) {
                    Image(systemName: snapshot.isStarred ? "star.fill" : "star")
                        .font(interfaceTextSize.font(size: 14, weight: .semibold))
                        .foregroundStyle(snapshot.isStarred ? .yellow : .secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(snapshot.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd)
            }
            .frame(width: 28, height: 76, alignment: .top)
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button(snapshot.isRead ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead) {
                onToggleRead()
            }

            Button(snapshot.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd) {
                onToggleStarred()
            }

            Divider()

            Button(snapshot.isArchived ? L10n.articleUnarchiveCommand : L10n.articleArchiveCommand) {
                onToggleArchived()
            }

            Button(L10n.articleAssignTagCommand) {
                onRequestAssignTag()
            }
            .disabled(!hasAvailableTags)

            Button(L10n.articleCreateRuleCommand) {
                onCreateRule()
            }

            Divider()

            Button(L10n.articleOpenInWindowCommand) {
                onOpenInWindow()
            }

            Button(L10n.articleCopyLinkCommand) {
                onCopyLink()
            }
            .disabled(!hasOriginalURL)

            Button(L10n.articleOpenOriginalCommand) {
                onOpenOriginal()
            }
            .disabled(!hasOriginalURL)

            Button(L10n.articleShareCommand) {
                onShareOriginal()
            }
            .disabled(!hasOriginalURL)

            Button(L10n.articleExportCommand) {
                onExport()
            }

            Button(L10n.articleDeleteCommand, role: .destructive) {
                onDelete()
            }

            Divider()

            Button(L10n.articleMarkAllReadCommand) {
                onMarkAllRead()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
```

(Einzige inhaltliche Änderung gegenüber dem bestehenden Code: `previewImage`
ist jetzt bedingt links/rechts platziert statt immer als erstes Element, und
der bisherige `if !metadataText.isEmpty { Text(metadataText)... }`-Block
wurde durch zwei bedingte `metadataRow`-Aufrufe vor/nach dem Titel ersetzt.)

- [ ] **Step 3: `metadataRow`, Favicon-Rendering und angepasste `metadataText`-Logik ergänzen**

Die bestehende `private var metadataText: String { ... }`-Property (aktuell
Zeilen 188-201) durch Folgendes ersetzen:

```swift
    @ViewBuilder
    private var metadataRow: some View {
        if !metadataText.isEmpty {
            HStack(spacing: 4) {
                if showsFeedNameAndFavicon {
                    metadataFavicon
                        .frame(
                            width: interfaceTextSize.scaled(11),
                            height: interfaceTextSize.scaled(11)
                        )
                }

                Text(metadataText)
                    .font(interfaceTextSize.font(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var metadataFavicon: some View {
        if let faviconURLString = snapshot.faviconURL, let url = URL(string: faviconURLString) {
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                metadataFaviconFallback
            }
        } else {
            metadataFaviconFallback
        }
    }

    private var metadataFaviconFallback: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
    }

    // Favicon nur zeigen, wenn auch tatsächlich ein Feedname angezeigt wird —
    // ist der Feedname ausgeblendet, bleibt nur der Zeitpunkt sichtbar, ohne
    // Favicon davor (siehe FEATURES.md 19.1, Entscheidung 2026-07-08).
    private var showsFeedNameAndFavicon: Bool {
        showsFeedName && snapshot.feedTitle?.isEmpty == false
    }

    private var metadataText: String {
        let feedNamePart = showsFeedNameAndFavicon ? snapshot.feedTitle : nil

        return [
            feedNamePart,
            snapshot.publishedAt?.feedivoRelativeDisplay
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else {
                return nil
            }

            return value
        }
        .joined(separator: " · ")
    }
```

- [ ] **Step 4: Build laufen lassen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo | tail -40`
Expected: `** BUILD SUCCEEDED **`. Ignoriere veraltete SourceKit-Diagnosen in
der IDE (siehe CLAUDE.md Gotchas) — nur der `xcodebuild`-Log zählt.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleRowView.swift
git commit -m "Artikelliste: Favicon vor Feedname, konfigurierbare Bild-/Feedname-Position"
```

---

### Task 4: Settings-UI + Lokalisierung

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ArticleListImagePosition`, `ArticleListFeedNamePosition`,
  `ArticleListFeedNameVisibilitySettings` (Task 1)
- Produces: keine neuen öffentlichen Symbole außerhalb dieser Dateien

- [ ] **Step 1: Neue L10n-Keys ergänzen**

In `Feedivo/Resources/L10n.swift` direkt nach Zeile 216
(`static let settingsSidebarShowsReadFeedsDescription = LocalizedStringKey("settings.sidebar.showsReadFeeds.description")`)
einfügen:

```swift
    static let articleListImagePositionLeft = LocalizedStringKey("articleList.imagePosition.left")
    static let articleListImagePositionRight = LocalizedStringKey("articleList.imagePosition.right")
    static let articleListImagePositionHidden = LocalizedStringKey("articleList.imagePosition.hidden")
    static let articleListFeedNamePositionBeforeTitle = LocalizedStringKey("articleList.feedNamePosition.beforeTitle")
    static let articleListFeedNamePositionAfterTitle = LocalizedStringKey("articleList.feedNamePosition.afterTitle")
    static let settingsArticleListImagePositionTitle = LocalizedStringKey("settings.articleList.imagePosition.title")
    static let settingsArticleListImagePositionDescription = LocalizedStringKey("settings.articleList.imagePosition.description")
    static let settingsArticleListShowsFeedNameTitle = LocalizedStringKey("settings.articleList.showsFeedName.title")
    static let settingsArticleListShowsFeedNameDescription = LocalizedStringKey("settings.articleList.showsFeedName.description")
    static let settingsArticleListFeedNamePositionTitle = LocalizedStringKey("settings.articleList.feedNamePosition.title")
    static let settingsArticleListFeedNamePositionDescription = LocalizedStringKey("settings.articleList.feedNamePosition.description")
```

- [ ] **Step 2: Neue Einträge in Localizable.xcstrings ergänzen (Block 1: `articleList.*`)**

In `Feedivo/Resources/Localizable.xcstrings` direkt vor dem Eintrag
`"articleList.loadingMore": {` (kommt alphabetisch nach `"articleList.empty.title"`)
folgende Einträge einfügen:

```json
    "articleList.feedNamePosition.afterTitle": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Nach dem Titel"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "After title"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Après le titre"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Dopo il titolo"
          }
        }
      }
    },
    "articleList.feedNamePosition.beforeTitle": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Vor dem Titel"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Before title"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Avant le titre"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Prima del titolo"
          }
        }
      }
    },
    "articleList.imagePosition.hidden": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Aus"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Off"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Désactivé"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Disattivato"
          }
        }
      }
    },
    "articleList.imagePosition.left": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Links"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Left"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Gauche"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Sinistra"
          }
        }
      }
    },
    "articleList.imagePosition.right": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Rechts"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Right"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Droite"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Destra"
          }
        }
      }
    },
```

- [ ] **Step 3: Neue Einträge in Localizable.xcstrings ergänzen (Block 2: `settings.articleList.*`)**

Direkt vor dem Eintrag `"settings.articleRetention.description": {` (kommt
alphabetisch nach `"settings.appearance.section"`) folgende Einträge
einfügen:

```json
    "settings.articleList.feedNamePosition.description": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Feedname und Zeitpunkt vor oder nach dem Artikeltitel anzeigen."
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Show feed name and date before or after the article title."
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Afficher le nom du flux et la date avant ou après le titre de l'article."
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Mostra il nome del feed e la data prima o dopo il titolo dell'articolo."
          }
        }
      }
    },
    "settings.articleList.feedNamePosition.title": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Feedname-Position"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Feed name position"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Position du nom du flux"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Posizione del nome del feed"
          }
        }
      }
    },
    "settings.articleList.imagePosition.description": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Position des Vorschaubilds in der Artikelliste."
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Position of the preview image in the article list."
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Position de l'image d'aperçu dans la liste des articles."
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Posizione dell'immagine di anteprima nell'elenco articoli."
          }
        }
      }
    },
    "settings.articleList.imagePosition.title": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Vorschaubild-Position"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Preview image position"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Position de l'image d'aperçu"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Posizione immagine di anteprima"
          }
        }
      }
    },
    "settings.articleList.showsFeedName.description": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Zeigt den Namen des Feeds pro Artikel, z. B. in \"Alle Artikel\"."
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Shows the feed name per article, e.g. in \"All Articles\"."
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Affiche le nom du flux par article, par ex. dans « Tous les articles »."
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Mostra il nome del feed per articolo, ad es. in \"Tutti gli articoli\"."
          }
        }
      }
    },
    "settings.articleList.showsFeedName.title": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Feed-Name anzeigen"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Show feed name"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Afficher le nom du flux"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Mostra nome feed"
          }
        }
      }
    },
```

- [ ] **Step 4: Neuen Settings-Block in `NewAppearanceSettingsView` ergänzen**

In `Feedivo/Views/Settings/SettingsView.swift`, in `NewAppearanceSettingsView`,
direkt nach der bestehenden `@AppStorage(ReaderTypographySettings.contentWidthKey)`-Property
(letzte `@AppStorage`-Property vor `var body`) drei neue Properties einfügen:

```swift

    @AppStorage(ArticleListImagePosition.storageKey)
    private var articleListImagePositionRawValue = ArticleListImagePosition.defaultPosition.rawValue

    @AppStorage(ArticleListFeedNameVisibilitySettings.showsFeedNameKey)
    private var articleListShowsFeedName = ArticleListFeedNameVisibilitySettings.defaultShowsFeedName

    @AppStorage(ArticleListFeedNamePosition.storageKey)
    private var articleListFeedNamePositionRawValue = ArticleListFeedNamePosition.defaultPosition.rawValue
```

Direkt NACH dem bestehenden `NewSettingsBlock(eyebrow: "Oberfläche") { ... }`-Block
(vor dem `NewSettingsBlock(eyebrow: L10n.settingsReadingSection) { ... }`-Block)
folgenden neuen Block einfügen:

```swift

            NewSettingsBlock(eyebrow: "Artikelliste") {
                NewSettingRow(
                    title: L10n.settingsArticleListImagePositionTitle,
                    description: L10n.settingsArticleListImagePositionDescription
                ) {
                    Picker("", selection: $articleListImagePositionRawValue) {
                        ForEach(ArticleListImagePosition.allCases) { position in
                            Text(position.titleKey)
                                .tag(position.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                }

                NewSettingRow(
                    title: L10n.settingsArticleListShowsFeedNameTitle,
                    description: L10n.settingsArticleListShowsFeedNameDescription
                ) {
                    Toggle("", isOn: $articleListShowsFeedName)
                        .labelsHidden()
                }

                NewSettingRow(
                    title: L10n.settingsArticleListFeedNamePositionTitle,
                    description: L10n.settingsArticleListFeedNamePositionDescription
                ) {
                    Picker("", selection: $articleListFeedNamePositionRawValue) {
                        ForEach(ArticleListFeedNamePosition.allCases) { position in
                            Text(position.titleKey)
                                .tag(position.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
```

- [ ] **Step 5: Build laufen lassen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo | tail -40`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Einstellungen: Neuer Block \"Artikelliste\" (Bild-Position, Feedname anzeigen/Position)"
```

---

### Task 5: Manuelle Verifikation in der laufenden App

**Files:** keine (nur Verifikation, keine Code-Änderung)

- [ ] **Step 1: App bauen und starten**

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build | tail -20
```
Expected: `** BUILD SUCCEEDED **`. Danach die gebaute App aus dem
DerivedData-Pfad öffnen.

- [ ] **Step 2: Standardverhalten prüfen (Default-Werte)**

- Artikelliste öffnen (z. B. "Alle Artikel").
- Vorschaubild ist wie bisher links, Feedname+Zeitpunkt-Zeile ist wie bisher
  NACH dem Titel — keine sichtbare Änderung ohne Einstellungsänderung.
- Vor dem Feedname-Text erscheint jetzt ein kleines Favicon (bzw. Platzhalter-
  Icon bei Feeds ohne Favicon), in etwa textgroß.

- [ ] **Step 3: Einstellungen → Darstellung → neuer Block "Artikelliste" prüfen**

- Vorschaubild-Position auf "Rechts" stellen → Vorschaubild in der
  Artikelliste wandert auf die rechte Seite (vor der Stern-Spalte).
- Vorschaubild-Position auf "Aus" stellen → kein Vorschaubild mehr sichtbar,
  Text nimmt die volle Breite ein.
- Zurück auf "Links" stellen.
- Feedname-Position auf "Vor dem Titel" stellen → Feedname-Zeile (mit
  Favicon) erscheint jetzt ÜBER dem Artikeltitel statt darunter.
- "Feed-Name anzeigen" ausschalten → Feedname und Favicon verschwinden, der
  Zeitpunkt ("vor X Min.") bleibt weiterhin sichtbar.
- "Feed-Name anzeigen" wieder einschalten.

- [ ] **Step 4: Abschließender Commit-Check**

```bash
git log --oneline -7
git status --short
```
Expected: Die 4 Task-Commits sichtbar, Arbeitsverzeichnis sauber (abgesehen
von nicht-projektbezogenen Altbeständen).
