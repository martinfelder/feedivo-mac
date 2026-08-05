# Feed-Status-Fenster (Ladefehler-Diagnose) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein eigenständiges Fenster ("Feed-Status"), das alle Feeds mit fehlgeschlagenem letzten Aktualisierungsversuch mit echtem Fehlergrund, HTTP-Status, Zeitpunkt und Länge der Fehlerserie auflistet, inkl. Aktionen zum erneuten Versuchen, Öffnen der Eigenschaften/Website, Kopieren der URL und Löschen.

**Architecture:** Neue GRDB-Fensterfunktions-Query in `FeedLogStore` (analog dem bestehenden `latest_feed_logs`-CTE-Muster in `FeedStore.sidebarFeeds()`) liefert pro Feed nur den aktuell fehlgeschlagenen Zustand samt Länge der Fehlerserie. Ein neues `Window`-Scene + Menüpunkt (analog Organizer/Statistik/Bereinigungsverlauf) zeigt das Ergebnis in einer `List` mit Kontextmenü-Aktionen, die auf bereits bestehende `FeedViewModel`-Methoden (`refreshFeed`, `deleteFeed`) delegieren.

**Tech Stack:** Swift, SwiftUI, GRDB, Swift Testing (`Testing`-Framework, keine XCTest).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08/2026-08-05-feed-refresh-diagnose-fenster-design.md`
- Kommentare im Code auf Deutsch (Projektkonvention, siehe `CLAUDE.md`).
- Keine neue Datenbank-Migration, keine neuen Spalten auf `feed_logs`/`feeds` — alle benötigten Daten existieren bereits.
- Kein Live-Abo eines Reaktivitäts-Signals für die Liste — neu laden nur beim Öffnen des Fensters, nach jeder im Fenster selbst ausgelösten Aktion, und über einen manuellen "Liste aktualisieren"-Button (siehe Spec, Abschnitt "Aktualisierung der Liste").
- "Alle fehlgeschlagenen erneut versuchen" läuft **sequenziell** (kein `TaskGroup`/paralleles `async let`) — `FeedViewModel.refreshFeed` guardet intern gegen Reentrancy über `isLoading`; parallele Aufrufe auf derselben `FeedViewModel`-Instanz würden alle bis auf den ersten silently no-op lassen.
- "Alle fehlgeschlagenen erneut versuchen" läuft **ohne Bestätigungsdialog** (nicht-destruktiv, Nutzerentscheidung). "Löschen" bleibt destruktiv mit Bestätigungsdialog.
- Neue `Localizable.xcstrings`-Einträge werden als reiner Text-Block direkt nach dem stabilen Anker `"strings" : {` eingefügt (NIEMALS die Datei per `json.load`/`json.dump` roundtripen — siehe CLAUDE.md-Gotcha zur Xcode-String-Catalog-Formatierung). Nach jeder xcstrings-Änderung `git diff --stat` prüfen: nur Insertions, keine/kaum Deletions.
- Jeder neue indirekte `L10n`-Key (nicht direkt als `Text("...")`-Literal verwendet) braucht einen manuellen xcstrings-Eintrag — Xcodes Auto-Stub-Mechanismus greift dafür NICHT (siehe CLAUDE.md-Gotcha). Nach dem Hinzufügen jeder Gruppe von Keys mit `grep -c "<key>" Feedivo/Resources/Localizable.xcstrings` verifizieren (muss > 0 sein).
- Test-Läufe immer gezielt mit `-only-testing:FeedivoTests/<Suite>` und `-parallel-testing-enabled NO` (volle Testsuite hängt/deadlockt, siehe CLAUDE.md-Gotcha).
- "Feed löschen" bekommt bewusst KEINEN eigenen Shortcut in `CustomizableShortcut` (destruktive Aktion, bestehende Projektkonvention) — das neue `.feedRefreshDiagnosticsOpen`-Case ist unabhängig davon und öffnet nur das Fenster.

---

## Task 1: `FeedFailureDiagnostic`-Snapshot + `FeedLogStore.failureDiagnostics()`

**Files:**
- Create: `Feedivo/Snapshots/FeedFailureDiagnostic.swift`
- Modify: `Feedivo/Stores/FeedLogStore.swift`
- Test: `FeedivoTests/Stores/SQLiteFeedLogStoreTests.swift`

**Interfaces:**
- Produces: `struct FeedFailureDiagnostic: Equatable, Identifiable, Sendable` mit den Feldern `feedID: String`, `feedTitle: String`, `feedURL: String`, `feedWebsiteURL: String?`, `feedFaviconURL: String?`, `lastAttemptAt: Date`, `errorMessage: String`, `httpStatusCode: Int?`, `consecutiveFailureCount: Int` (`id` liefert `feedID`).
- Produces: `FeedLogStore.failureDiagnostics() throws -> [FeedFailureDiagnostic]` (synchron, für Tests) und `FeedLogStore.failureDiagnosticsAsync() async throws -> [FeedFailureDiagnostic]` (für den UI-Aufruf in Task 4, nutzt `database.readAsync` statt den MainActor zu blockieren — analog `FeedStore.sidebarFeeds()`/`sidebarFeedsAsync()`).

- [ ] **Step 1: Write the failing tests**

Öffne `FeedivoTests/Stores/SQLiteFeedLogStoreTests.swift` und füge am Ende der `struct SQLiteFeedLogStoreTests { ... }` (vor der letzten schließenden Klammer der Struct) folgende Tests ein:

```swift
    @Test func failureDiagnosticsIstLeerOhneFehlgeschlageneFeeds() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "info",
            message: "Aktualisiert"
        ))

        let diagnostics = try logStore.failureDiagnostics()

        #expect(diagnostics.isEmpty)
    }

    @Test func failureDiagnosticsLiefertFeedMitEinzelnemFehlschlag() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed.xml",
            title: "Example",
            websiteURL: "https://example.com",
            faviconURL: "https://example.com/favicon.ico"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "info",
            message: "Aktualisiert"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 2_000),
            level: "error",
            message: "Zeitüberschreitung",
            httpStatusCode: nil,
            newArticleCount: 0
        ))

        let diagnostics = try logStore.failureDiagnostics()

        #expect(diagnostics.count == 1)
        let diagnostic = diagnostics[0]
        #expect(diagnostic.feedID == "feed-1")
        #expect(diagnostic.feedTitle == "Example")
        #expect(diagnostic.feedURL == "https://example.com/feed.xml")
        #expect(diagnostic.feedWebsiteURL == "https://example.com")
        #expect(diagnostic.feedFaviconURL == "https://example.com/favicon.ico")
        #expect(diagnostic.errorMessage == "Zeitüberschreitung")
        #expect(diagnostic.httpStatusCode == nil)
        #expect(diagnostic.lastAttemptAt == Date(timeIntervalSince1970: 2_000))
        #expect(diagnostic.consecutiveFailureCount == 1)
    }

    @Test func failureDiagnosticsZaehltAufeinanderfolgendeFehlschlaegeKorrekt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "info",
            message: "Aktualisiert"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 2_000),
            level: "error",
            message: "Erster Fehler",
            httpStatusCode: 500
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 3_000),
            level: "error",
            message: "Zweiter Fehler",
            httpStatusCode: 500
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 4_000),
            level: "error",
            message: "Dritter Fehler",
            httpStatusCode: 404
        ))

        let diagnostics = try logStore.failureDiagnostics()

        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].consecutiveFailureCount == 3)
        #expect(diagnostics[0].errorMessage == "Dritter Fehler")
        #expect(diagnostics[0].httpStatusCode == 404)
    }

    @Test func failureDiagnosticsIgnoriertFeedNachErneutErfolgreichemVersuch() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "error",
            message: "Alter Fehler"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 2_000),
            level: "info",
            message: "Wieder aktualisiert"
        ))

        let diagnostics = try logStore.failureDiagnostics()

        #expect(diagnostics.isEmpty)
    }

    @Test func failureDiagnosticsSortiertNachNeuestemVersuchZuerst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://one.example/feed.xml", title: "One"))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://two.example/feed.xml", title: "Two"))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "error",
            message: "Älterer Fehler"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-2",
            createdAt: Date(timeIntervalSince1970: 5_000),
            level: "error",
            message: "Neuerer Fehler"
        ))

        let diagnostics = try logStore.failureDiagnostics()

        #expect(diagnostics.map(\.feedID) == ["feed-2", "feed-1"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedLogStoreTests -parallel-testing-enabled NO`

Expected: FAIL — Compile-Fehler „value of type 'FeedLogStore' has no member 'failureDiagnostics'" (und `FeedFailureDiagnostic` existiert noch nicht).

- [ ] **Step 3: Create `FeedFailureDiagnostic`**

Erstelle `Feedivo/Snapshots/FeedFailureDiagnostic.swift`:

```swift
import Foundation

/// Ein Feed, dessen letzter Aktualisierungsversuch fehlgeschlagen ist —
/// Grundlage für das Feed-Status-Diagnose-Fenster
/// (`FeedRefreshDiagnosticsWindowView`). Wird ausschließlich über
/// `FeedLogStore.failureDiagnostics()`/`failureDiagnosticsAsync()` befüllt.
struct FeedFailureDiagnostic: Equatable, Identifiable, Sendable {
    var feedID: String
    var feedTitle: String
    var feedURL: String
    var feedWebsiteURL: String?
    var feedFaviconURL: String?
    var lastAttemptAt: Date
    var errorMessage: String
    var httpStatusCode: Int?
    var consecutiveFailureCount: Int

    var id: String { feedID }
}
```

- [ ] **Step 4: Implement `FeedLogStore.failureDiagnostics()`/`failureDiagnosticsAsync()`**

Öffne `Feedivo/Stores/FeedLogStore.swift`. Füge die neuen Methoden direkt nach der bestehenden `func latestAttemptTimes() throws -> [String: Date] { ... }` (vor `func deleteOlderThan(...)`) ein:

```swift
    /// Alle Feeds, deren letzter Aktualisierungsversuch fehlgeschlagen ist,
    /// inkl. Länge der aktuellen Fehlerserie — Grundlage für das
    /// Feed-Status-Diagnose-Fenster (`FeedRefreshDiagnosticsWindowView`).
    /// Synchrone Variante für Tests; `failureDiagnosticsAsync()` für den
    /// UI-Aufruf (analog `FeedStore.sidebarFeeds()`/`sidebarFeedsAsync()`).
    func failureDiagnostics() throws -> [FeedFailureDiagnostic] {
        try database.read { db in try Self.queryFailureDiagnostics(db) }
    }

    func failureDiagnosticsAsync() async throws -> [FeedFailureDiagnostic] {
        try await database.readAsync { db in try Self.queryFailureDiagnostics(db) }
    }

    /// Zwei CTEs: `latest` ermittelt den letzten Log-Eintrag je Feed
    /// (analog `latest_feed_logs` in `FeedStore.sidebarFeeds()`), `ordered`+
    /// `streaks` zählen die Länge der aktuellen Fehlerserie — läuft von den
    /// neuesten Einträgen je Feed rückwärts (laufende Summe der
    /// "ist kein Fehler"-Flags) und stoppt beim ersten Nicht-Fehler-Eintrag
    /// (`successBoundary = 0`). Gedeckelt durch die konfigurierbare
    /// `feed_logs`-Aufbewahrungsdauer (siehe `FeedLogRetentionSettings`) —
    /// bei einem seit über 30 Tagen kaputten Feed zählt nur die innerhalb
    /// der Aufbewahrungsfrist protokollierten Fehlschläge (bewusste,
    /// dokumentierte Einschränkung, siehe Design-Spec).
    private static func queryFailureDiagnostics(_ db: Database) throws -> [FeedFailureDiagnostic] {
        try SQLRequest<FeedFailureDiagnostic>(sql: """
            WITH ordered AS (
                SELECT
                    feedID,
                    level,
                    createdAt,
                    id,
                    SUM(CASE WHEN level != 'error' THEN 1 ELSE 0 END) OVER (
                        PARTITION BY feedID
                        ORDER BY createdAt DESC, id COLLATE NOCASE DESC
                        ROWS UNBOUNDED PRECEDING
                    ) AS successBoundary
                FROM feed_logs
            ),
            streaks AS (
                SELECT feedID, COUNT(*) AS consecutiveFailureCount
                FROM ordered
                WHERE successBoundary = 0 AND level = 'error'
                GROUP BY feedID
            ),
            latest AS (
                SELECT
                    feedID, level, message, httpStatusCode, createdAt,
                    ROW_NUMBER() OVER (
                        PARTITION BY feedID ORDER BY createdAt DESC, id COLLATE NOCASE DESC
                    ) AS rn
                FROM feed_logs
            )
            SELECT
                f.id AS feedID,
                f.title AS feedTitle,
                f.url AS feedURL,
                f.websiteURL AS feedWebsiteURL,
                f.faviconURL AS feedFaviconURL,
                l.createdAt AS lastAttemptAt,
                l.message AS errorMessage,
                l.httpStatusCode AS httpStatusCode,
                COALESCE(s.consecutiveFailureCount, 1) AS consecutiveFailureCount
            FROM feeds f
            JOIN latest l ON l.feedID = f.id AND l.rn = 1
            LEFT JOIN streaks s ON s.feedID = f.id
            WHERE l.level = 'error'
            ORDER BY l.createdAt DESC
            """, cached: true).fetchAll(db)
    }
```

Füge am Ende von `Feedivo/Stores/FeedLogStore.swift` (nach der schließenden Klammer von `struct FeedLogStore { ... }`) die `FetchableRecord`-Konformität hinzu — exakt nach dem Muster von `extension FeedSidebarSnapshot: FetchableRecord` in `Feedivo/Stores/FeedStore.swift`:

```swift

extension FeedFailureDiagnostic: FetchableRecord {
    // nonisolated noetig, da das App-Target SWIFT_DEFAULT_ACTOR_ISOLATION =
    // MainActor setzt — ohne diese Annotation waere die FetchableRecord-
    // Konformität MainActor-isoliert und SQLRequest<FeedFailureDiagnostic>s
    // generischer, Sendable-vorausgesetzter fetchAll(_:)-Pfad wuerde nicht
    // kompilieren.
    nonisolated init(row: Row) throws {
        feedID = row["feedID"]
        feedTitle = row["feedTitle"]
        feedURL = row["feedURL"]
        feedWebsiteURL = row["feedWebsiteURL"]
        feedFaviconURL = row["feedFaviconURL"]
        lastAttemptAt = row["lastAttemptAt"]
        errorMessage = row["errorMessage"]
        httpStatusCode = row["httpStatusCode"]
        consecutiveFailureCount = row["consecutiveFailureCount"]
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedLogStoreTests -parallel-testing-enabled NO`

Expected: alle Tests (bestehende + 5 neue) PASS

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Snapshots/FeedFailureDiagnostic.swift Feedivo/Stores/FeedLogStore.swift FeedivoTests/Stores/SQLiteFeedLogStoreTests.swift
git commit -m "feat: FeedLogStore.failureDiagnostics() für Feed-Status-Diagnose-Fenster"
```

---

## Task 2: L10n-Keys (Swift + Localizable.xcstrings)

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces: `L10n.feedRefreshDiagnosticsCommand`, `L10n.feedRefreshDiagnosticsWindowTitle`, `L10n.feedRefreshDiagnosticsDescription`, `L10n.feedRefreshDiagnosticsEmptyTitle`, `L10n.feedRefreshDiagnosticsEmptyDescription`, `L10n.feedRefreshDiagnosticsRetryAllButton`, `L10n.feedRefreshDiagnosticsReloadListButton`, `L10n.feedRefreshDiagnosticsOpenWebsiteButton` (alle `String`), `L10n.feedRefreshDiagnosticsConsecutiveFailures(_ count: Int) -> String`, `L10n.shortcutsLabelFeedRefreshDiagnosticsOpen` (`LocalizedStringKey`) — genutzt von Task 3 und Task 4.

- [ ] **Step 1: `L10n.swift` ergänzen**

Öffne `Feedivo/Resources/L10n.swift`. Suche die Zeile `static let feedRefreshCommand = String(localized: "feed.refresh.command")` und füge direkt danach ein:

```swift
    static let feedRefreshDiagnosticsCommand = String(localized: "feed.refreshDiagnostics.command")
    static let feedRefreshDiagnosticsWindowTitle = String(localized: "feed.refreshDiagnostics.windowTitle")
    static let feedRefreshDiagnosticsDescription = String(localized: "feed.refreshDiagnostics.description")
    static let feedRefreshDiagnosticsEmptyTitle = String(localized: "feed.refreshDiagnostics.empty.title")
    static let feedRefreshDiagnosticsEmptyDescription = String(localized: "feed.refreshDiagnostics.empty.description")
    static let feedRefreshDiagnosticsRetryAllButton = String(localized: "feed.refreshDiagnostics.retryAll.button")
    static let feedRefreshDiagnosticsReloadListButton = String(localized: "feed.refreshDiagnostics.reloadList.button")
    static let feedRefreshDiagnosticsOpenWebsiteButton = String(localized: "feed.refreshDiagnostics.openWebsite.button")
    static func feedRefreshDiagnosticsConsecutiveFailures(_ count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "feed.refreshDiagnostics.consecutiveFailures"),
            count
        )
    }
```

Suche die Zeile `static let shortcutsLabelFeedOrganizerOpen = LocalizedStringKey("shortcuts.label.feedOrganizerOpen")` und füge direkt danach ein:

```swift
    static let shortcutsLabelFeedRefreshDiagnosticsOpen = LocalizedStringKey("shortcuts.label.feedRefreshDiagnosticsOpen")
```

- [ ] **Step 2: `Localizable.xcstrings` ergänzen**

Öffne `Feedivo/Resources/Localizable.xcstrings`. Suche den Anker `"strings" : {` (Zeile 3, direkt gefolgt vom ersten bestehenden Key `"settings.articleList.usesNativeTableView.title"`). Füge **direkt danach**, vor dem ersten bestehenden Key, folgenden Text-Block ein (exakte Einrückung wie im Rest der Datei: 4/6/8/10 Leerzeichen):

```json
    "feed.refreshDiagnostics.command" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed-Status..."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed Status..."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "État des flux..."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Stato dei feed..."
          }
        }
      }
    },
    "feed.refreshDiagnostics.windowTitle" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed-Status"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed Status"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "État des flux"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Stato dei feed"
          }
        }
      }
    },
    "feed.refreshDiagnostics.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Diese Feeds konnten beim letzten Versuch nicht geladen werden."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "These feeds couldn't be loaded on their last attempt."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ces flux n'ont pas pu être chargés lors de la dernière tentative."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Questi feed non sono stati caricati nell'ultimo tentativo."
          }
        }
      }
    },
    "feed.refreshDiagnostics.empty.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Keine fehlgeschlagenen Feeds"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No failed feeds"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aucun flux en échec"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nessun feed non riuscito"
          }
        }
      }
    },
    "feed.refreshDiagnostics.empty.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Alle Feeds wurden zuletzt erfolgreich aktualisiert."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "All feeds were refreshed successfully last time."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Tous les flux ont été actualisés avec succès la dernière fois."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Tutti i feed sono stati aggiornati con successo l'ultima volta."
          }
        }
      }
    },
    "feed.refreshDiagnostics.retryAll.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Alle fehlgeschlagenen erneut versuchen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Retry all failed"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Réessayer tous les échecs"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Riprova tutti i falliti"
          }
        }
      }
    },
    "feed.refreshDiagnostics.reloadList.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Liste aktualisieren"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Refresh list"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Actualiser la liste"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aggiorna elenco"
          }
        }
      }
    },
    "feed.refreshDiagnostics.openWebsite.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Website öffnen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Open website"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ouvrir le site"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Apri sito web"
          }
        }
      }
    },
    "feed.refreshDiagnostics.consecutiveFailures" : {
      "localizations" : {
        "de" : {
          "variations" : {
            "plural" : {
              "one" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld Fehlschlag in Folge"
                }
              },
              "other" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld Fehlschläge in Folge"
                }
              }
            }
          }
        },
        "en" : {
          "variations" : {
            "plural" : {
              "one" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld failed attempt in a row"
                }
              },
              "other" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld failed attempts in a row"
                }
              }
            }
          }
        },
        "fr" : {
          "variations" : {
            "plural" : {
              "one" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld échec consécutif"
                }
              },
              "other" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld échecs consécutifs"
                }
              }
            }
          }
        },
        "it" : {
          "variations" : {
            "plural" : {
              "many" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld tentativi falliti di fila"
                }
              },
              "one" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld tentativo fallito di fila"
                }
              }
            }
          }
        }
      }
    },
    "shortcuts.label.feedRefreshDiagnosticsOpen" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed-Status öffnen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Open feed status"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ouvrir l'état des flux"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Apri stato dei feed"
          }
        }
      }
    },
```

- [ ] **Step 3: Verifizieren, dass alle 10 Keys im Katalog ankamen**

Run:
```bash
for key in \
  "feed.refreshDiagnostics.command" \
  "feed.refreshDiagnostics.windowTitle" \
  "feed.refreshDiagnostics.description" \
  "feed.refreshDiagnostics.empty.title" \
  "feed.refreshDiagnostics.empty.description" \
  "feed.refreshDiagnostics.retryAll.button" \
  "feed.refreshDiagnostics.reloadList.button" \
  "feed.refreshDiagnostics.openWebsite.button" \
  "feed.refreshDiagnostics.consecutiveFailures" \
  "shortcuts.label.feedRefreshDiagnosticsOpen"; do
  count=$(grep -c "\"$key\"" Feedivo/Resources/Localizable.xcstrings)
  echo "$key: $count"
done
```

Expected: jede Zeile zeigt `: 1` (jeder Key kommt exakt einmal vor).

- [ ] **Step 4: Diff-Stat prüfen (nur Insertions)**

Run: `git diff --stat -- Feedivo/Resources/Localizable.xcstrings`

Expected: Insertions ≈ 10 Keys × ~4 Zeilen × 4 Sprachen (grobe Größenordnung dreistellig), **0 oder nahe 0 Deletions**. Bei größeren Deletions: Änderung nicht committen, stattdessen die Datei per `git checkout -- Feedivo/Resources/Localizable.xcstrings` zurücksetzen und Step 2 erneut, diesmal ausschließlich als reine Text-Einfügung ohne die Datei anderweitig zu berühren.

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED (die neuen `L10n`-Konstanten sind noch unbenutzt, das ist an dieser Stelle kein Fehler).

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat: L10n-Keys für Feed-Status-Diagnose-Fenster"
```

---

## Task 3: `CustomizableShortcut.feedRefreshDiagnosticsOpen`

**Files:**
- Modify: `Feedivo/Models/CustomizableShortcut.swift`
- Test: `FeedivoTests/Models/CustomizableShortcutTests.swift`

**Interfaces:**
- Consumes: `L10n.shortcutsLabelFeedRefreshDiagnosticsOpen` (Task 2).
- Produces: `CustomizableShortcut.feedRefreshDiagnosticsOpen` — Kategorie `.feed`, `defaultSpec == nil` (kein vorbelegter Shortcut, analog `.feedOrganizerOpen`) — genutzt von Task 5.

- [ ] **Step 1: Write the failing test**

Öffne `FeedivoTests/Models/CustomizableShortcutTests.swift` und füge am Ende der `struct CustomizableShortcutTests { ... }` (vor der letzten schließenden Klammer) folgenden Test ein:

```swift
    @Test func feedRefreshDiagnosticsOpenGehoertZurFeedKategorieOhneDefault() {
        #expect(CustomizableShortcut.feedRefreshDiagnosticsOpen.category == .feed)
        #expect(CustomizableShortcut.feedRefreshDiagnosticsOpen.defaultSpec == nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CustomizableShortcutTests -parallel-testing-enabled NO`

Expected: FAIL — Compile-Fehler „type 'CustomizableShortcut' has no member 'feedRefreshDiagnosticsOpen'".

- [ ] **Step 3: Write minimal implementation**

Öffne `Feedivo/Models/CustomizableShortcut.swift`.

Suche die Case-Liste (`case feedOrganizerOpen`) und füge direkt danach ein:
```swift
    case feedRefreshDiagnosticsOpen
```

Suche im `category`-Switch die Zeile `case .feedAdd, .statisticsOpen, .feedRefreshAll, .feedRefresh,` / `     .feedImportOPML, .feedExportOPML, .feedOrganizerOpen:` und ändere sie zu:
```swift
        case .feedAdd, .statisticsOpen, .feedRefreshAll, .feedRefresh,
             .feedImportOPML, .feedExportOPML, .feedOrganizerOpen,
             .feedRefreshDiagnosticsOpen:
```

Suche im `titleKey`-Switch die Zeile `case .feedOrganizerOpen: L10n.shortcutsLabelFeedOrganizerOpen` und füge direkt danach ein:
```swift
        case .feedRefreshDiagnosticsOpen: L10n.shortcutsLabelFeedRefreshDiagnosticsOpen
```

Suche im `defaultSpec`-Switch die Zeile `case .feedImportOPML, .feedExportOPML, .feedOrganizerOpen:` und ändere sie zu:
```swift
        case .feedImportOPML, .feedExportOPML, .feedOrganizerOpen,
             .feedRefreshDiagnosticsOpen:
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CustomizableShortcutTests -parallel-testing-enabled NO`

Expected: PASS

- [ ] **Step 5: Run the full CustomizableShortcutTests suite to confirm no regression**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CustomizableShortcutTests -parallel-testing-enabled NO`

Expected: alle Tests PASS. (Hinweis, kein Fix-Bedarf: `FeedivoTests.swift` enthält einen vorbestehenden, bereits vor dieser Änderung falschen `#expect(CustomizableShortcut.allCases.count == 21)` — die reale Zahl war schon vorher höher. Dieser Test gehört nicht zu `CustomizableShortcutTests` und wird von dieser Suite nicht mitgeführt; nicht anfassen, außerhalb des Scopes dieses Plans.)

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Models/CustomizableShortcut.swift FeedivoTests/Models/CustomizableShortcutTests.swift
git commit -m "feat: CustomizableShortcut.feedRefreshDiagnosticsOpen für Feed-Status-Fenster"
```

---

## Task 4: `FeedRefreshDiagnosticsWindowView`

**Files:**
- Create: `Feedivo/Views/FeedDiagnostics/FeedRefreshDiagnosticsWindowView.swift`

**Interfaces:**
- Consumes: `FeedLogStore.failureDiagnosticsAsync()` (Task 1), `L10n.feedRefreshDiagnostics*` + `L10n.feedRefreshCommand`/`feedPropertiesCommand`/`feedPropertiesCopyXMLAddress`/`feedDeleteCommand`/`feedDeleteConfirmationTitle`/`feedDeleteConfirmButton`/`feedDeleteConfirmationMessage(feedTitle:)`/`commonCancel` (Task 2 + bereits bestehende Keys), `FeedViewModel.refreshFeed(feedID:sqliteDatabase:)`/`deleteFeed(feedID:sqliteDatabase:)` (bereits bestehend), `FeedPropertiesFormatter.linkURL(_:)` (bereits bestehend), `FeedPropertiesView(feedID:)` (bereits bestehend), `CachedRemoteImageView` (bereits bestehend).
- Produces: `struct FeedRefreshDiagnosticsWindowView: View` mit `static let windowID = "feed-refresh-diagnostics-window"` — genutzt von Task 5.

- [ ] **Step 1: View erstellen**

Erstelle den Ordner `Feedivo/Views/FeedDiagnostics/` (falls er nicht existiert) und darin `FeedRefreshDiagnosticsWindowView.swift`:

```swift
import AppKit
import SwiftUI

/// Eigenständiges Fenster: listet alle Feeds, deren letzter Aktualisierungs-
/// versuch fehlgeschlagen ist, mit echtem Fehlergrund aus `feed_logs` (statt
/// des flüchtigen `FeedViewModel.refreshItems`-Panels unten rechts in
/// `ContentView.swift`, das nur den zuletzt laufenden "Alle aktualisieren"-
/// Vorgang abdeckt). Siehe
/// docs/superpowers/specs/2026-08/2026-08-05-feed-refresh-diagnose-fenster-design.md.
struct FeedRefreshDiagnosticsWindowView: View {
    static let windowID = "feed-refresh-diagnostics-window"

    @Environment(\.feedivoDatabase) private var feedivoDatabase

    @State private var diagnostics: [FeedFailureDiagnostic] = []
    @State private var feedViewModel = FeedViewModel()
    @State private var feedShowingProperties: FeedFailureDiagnostic?
    @State private var feedPendingDeletion: FeedFailureDiagnostic?
    @State private var isBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if diagnostics.isEmpty {
                emptyState
            } else {
                List(diagnostics) { diagnostic in
                    FeedFailureDiagnosticRow(diagnostic: diagnostic)
                        .contextMenu {
                            rowActions(for: diagnostic)
                        }
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 360)
        .task {
            await reload()
        }
        .sheet(item: $feedShowingProperties) { diagnostic in
            FeedPropertiesView(feedID: diagnostic.feedID)
        }
        .confirmationDialog(
            L10n.feedDeleteConfirmationTitle,
            isPresented: Binding(
                get: { feedPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        feedPendingDeletion = nil
                    }
                }
            ),
            presenting: feedPendingDeletion
        ) { diagnostic in
            Button(L10n.feedDeleteConfirmButton, role: .destructive) {
                delete(diagnostic)
            }

            Button(L10n.commonCancel, role: .cancel) {
                feedPendingDeletion = nil
            }
        } message: { diagnostic in
            Text(L10n.feedDeleteConfirmationMessage(feedTitle: diagnostic.feedTitle))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.feedRefreshDiagnosticsWindowTitle)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(L10n.feedRefreshDiagnosticsDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(L10n.feedRefreshDiagnosticsReloadListButton) {
                Task {
                    await reload()
                }
            }
            .disabled(isBusy)

            if !diagnostics.isEmpty {
                Button(L10n.feedRefreshDiagnosticsRetryAllButton) {
                    Task {
                        await retryAll()
                    }
                }
                .disabled(isBusy)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.green)

            Text(L10n.feedRefreshDiagnosticsEmptyTitle)
                .font(.system(size: 13, weight: .semibold))

            Text(L10n.feedRefreshDiagnosticsEmptyDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func rowActions(for diagnostic: FeedFailureDiagnostic) -> some View {
        Button(L10n.feedRefreshCommand) {
            Task {
                await retry(diagnostic)
            }
        }
        .disabled(isBusy)

        Button(L10n.feedPropertiesCommand) {
            feedShowingProperties = diagnostic
        }

        if let url = FeedPropertiesFormatter.linkURL(diagnostic.feedWebsiteURL ?? diagnostic.feedURL) {
            Button(L10n.feedRefreshDiagnosticsOpenWebsiteButton) {
                NSWorkspace.shared.open(url)
            }
        }

        Button(L10n.feedPropertiesCopyXMLAddress) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(diagnostic.feedURL, forType: .string)
        }

        Divider()

        Button(L10n.feedDeleteCommand, role: .destructive) {
            feedPendingDeletion = diagnostic
        }
    }

    private func reload() async {
        guard let feedivoDatabase else {
            diagnostics = []
            return
        }
        diagnostics = (try? await FeedLogStore(database: feedivoDatabase).failureDiagnosticsAsync()) ?? []
    }

    private func retry(_ diagnostic: FeedFailureDiagnostic) async {
        guard let feedivoDatabase else {
            return
        }
        await feedViewModel.refreshFeed(feedID: diagnostic.feedID, sqliteDatabase: feedivoDatabase)
        await reload()
    }

    /// Läuft sequenziell (kein `TaskGroup`) — `FeedViewModel.refreshFeed`
    /// guardet intern gegen Reentrancy über `isLoading`; parallele Aufrufe
    /// auf derselben Instanz würden alle bis auf den ersten silently no-op
    /// lassen (siehe Global Constraints im Plan).
    private func retryAll() async {
        guard let feedivoDatabase else {
            return
        }
        isBusy = true
        defer {
            isBusy = false
        }
        for diagnostic in diagnostics {
            await feedViewModel.refreshFeed(feedID: diagnostic.feedID, sqliteDatabase: feedivoDatabase)
        }
        await reload()
    }

    private func delete(_ diagnostic: FeedFailureDiagnostic) {
        feedPendingDeletion = nil
        guard let feedivoDatabase else {
            return
        }
        feedViewModel.deleteFeed(feedID: diagnostic.feedID, sqliteDatabase: feedivoDatabase)
        diagnostics.removeAll { $0.feedID == diagnostic.feedID }
    }
}

private struct FeedFailureDiagnosticRow: View {
    let diagnostic: FeedFailureDiagnostic

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            faviconView

            VStack(alignment: .leading, spacing: 3) {
                Text(diagnostic.feedTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Text(diagnostic.errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(diagnostic.lastAttemptAt.formatted(date: .abbreviated, time: .shortened))

                    if let httpStatusCode = diagnostic.httpStatusCode {
                        Text("HTTP \(httpStatusCode)")
                    }

                    Text(L10n.feedRefreshDiagnosticsConsecutiveFailures(diagnostic.consecutiveFailureCount))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

                Text(diagnostic.feedURL)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var faviconView: some View {
        if let faviconURLString = diagnostic.feedFaviconURL, let url = URL(string: faviconURLString) {
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } placeholder: {
                fallbackIcon
            }
            .frame(width: 20, height: 20)
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 14))
            .foregroundStyle(.red)
            .frame(width: 20, height: 20)
    }
}
```

- [ ] **Step 2: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED. (Kein dedizierter View-Test — dieses Projekt hat kein ViewInspector, SwiftUI-Views werden ausschließlich per Build + manueller Live-Verifikation abgesichert, siehe bestehende `CleanupHistoryWindowView`/`OrganizerWindowView` als Präzedenzfall.)

- [ ] **Step 3: Commit**

```bash
git add Feedivo/Views/FeedDiagnostics/FeedRefreshDiagnosticsWindowView.swift
git commit -m "feat: FeedRefreshDiagnosticsWindowView"
```

---

## Task 5: Fenster-Scene + Menüpunkt verdrahten

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift`
- Modify: `Feedivo/App/FeedCommands.swift`

**Interfaces:**
- Consumes: `FeedRefreshDiagnosticsWindowView`/`FeedRefreshDiagnosticsWindowView.windowID` (Task 4), `CustomizableShortcut.feedRefreshDiagnosticsOpen` (Task 3), `L10n.feedRefreshDiagnosticsWindowTitle`/`feedRefreshDiagnosticsCommand` (Task 2).

- [ ] **Step 1: `Window`-Scene in `FeedivoApp.swift` ergänzen**

Öffne `Feedivo/App/FeedivoApp.swift`. Suche den Block:
```swift
        Window(L10n.cleanupHistoryTitle, id: CleanupHistoryWindowView.windowID) {
            CleanupHistoryWindowView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 420, height: 480)
```

Füge direkt danach ein:
```swift

        Window(L10n.feedRefreshDiagnosticsWindowTitle, id: FeedRefreshDiagnosticsWindowView.windowID) {
            FeedRefreshDiagnosticsWindowView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 520, height: 480)
```

- [ ] **Step 2: Menüpunkt in `FeedCommands.swift` ergänzen**

Öffne `Feedivo/App/FeedCommands.swift`. Suche den Block:
```swift
            Button(L10n.statisticsCommand) {
                openWindow(id: StatisticsWindowView.windowID)
            }
            .customizableKeyboardShortcut(.statisticsOpen, overrides: shortcutOverrides)

            Divider()
```

Füge zwischen den beiden Blöcken ein (direkt nach `.customizableKeyboardShortcut(.statisticsOpen, overrides: shortcutOverrides)`, vor `Divider()`):
```swift

            Button(L10n.feedRefreshDiagnosticsCommand) {
                openWindow(id: FeedRefreshDiagnosticsWindowView.windowID)
            }
            .customizableKeyboardShortcut(.feedRefreshDiagnosticsOpen, overrides: shortcutOverrides)
```

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Gezielter Regressionslauf**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedLogStoreTests -only-testing:FeedivoTests/CustomizableShortcutTests -parallel-testing-enabled NO`

Expected: alle Tests PASS

- [ ] **Step 5: Commit**

```bash
git add Feedivo/App/FeedivoApp.swift Feedivo/App/FeedCommands.swift
git commit -m "feat: Feed-Status-Fenster über Feed-Menü erreichbar"
```

- [ ] **Step 6: Manuelle Live-Verifikation (nicht automatisierbar)**

App starten (`xcodebuild build` + App aus DerivedData starten, oder über Xcode ⌘R) und folgende Punkte durchklicken:

1. Feed-Menü → "Feed-Status..." öffnet das neue Fenster.
2. Ohne fehlgeschlagene Feeds: leerer Zustand mit grünem Häkchen + "Keine fehlgeschlagenen Feeds" erscheint.
3. Einen Feed absichtlich kaputt machen (z. B. über Feed-Eigenschaften die URL auf eine ungültige Adresse ändern oder einen Feed mit offline stehendem Host abonnieren), "Alle aktualisieren" auslösen — der Feed erscheint im Fenster mit echtem Fehlertext (nicht nur "Fehlgeschlagen"), Zeitpunkt, ggf. HTTP-Status, Fehlerserie-Text.
4. Kontextmenü → "Aktualisieren" (Erneut versuchen) auf der Zeile — Vorgang läuft, Zeile verschwindet bei Erfolg bzw. bleibt mit aktualisiertem Fehlertext bei erneutem Fehlschlag.
5. Kontextmenü → "Eigenschaften..." öffnet den bestehenden Feed-Eigenschaften-Sheet.
6. Kontextmenü → "Website öffnen" öffnet die Feed-Website im Standardbrowser (bzw. ist ausgeblendet, falls weder `websiteURL` noch `url` eine gültige http(s)-Adresse sind).
7. Kontextmenü → "XML-Adresse kopieren" — Feed-URL landet in der Zwischenablage.
8. Kontextmenü → "Feed löschen" zeigt den bestehenden Bestätigungsdialog, nach Bestätigung verschwindet die Zeile und der Feed ist aus der Sidebar weg.
9. "Alle fehlgeschlagenen erneut versuchen" bei mehreren kaputten Feeds — läuft ohne Bestätigungsdialog, alle werden nacheinander versucht, Liste aktualisiert sich danach.
10. "Liste aktualisieren" lädt die Liste neu, ohne dass ein Refresh ausgelöst wird.
11. Einstellungen → Shortcuts: "Feed-Status öffnen" erscheint in der Kategorie "Feed" und ist frei belegbar (kein Default-Shortcut vorbelegt).

---

## Self-Review-Notiz (für die ausführende Session)

- **Spec-Abdeckung:** Datenquelle (Task 1), Fensterinhalt + Aktionen + leerer Zustand (Task 4), Aktualisierungsstrategie (Task 4, `reload()`-Aufrufe), Einstiegspunkt Menü+Shortcut (Task 3+5) — alle Spec-Abschnitte haben eine Task.
- **Bewusst nicht in eigenem Task:** Keine DB-Migration nötig (Spec "Out of Scope"), keine Änderung am bestehenden Panel unten rechts.
- **Typkonsistenz:** `FeedFailureDiagnostic` (Task 1) wird in Task 4 identisch verwendet (`feedID`, `feedTitle`, `feedURL`, `feedWebsiteURL`, `feedFaviconURL`, `lastAttemptAt`, `errorMessage`, `httpStatusCode`, `consecutiveFailureCount`) — keine Abweichung in Feldnamen zwischen den Tasks.
