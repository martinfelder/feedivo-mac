# Artikelliste: Feed-Status-Zeile im Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Im Artikellisten-Header eine dritte Zeile ergänzen, die bei einem einzelnen
ausgewählten Feed anzeigt, wann er zuletzt erfolgreich aktualisiert wurde — oder, falls der
letzte Versuch fehlschlug, den konkreten Fehlergrund.

**Architecture:** Reine View-/State-Erweiterung von `SQLiteFeedArticleListView`. Keine neue
Migration, keine neuen Store-Methoden — nutzt ausschließlich bereits vorhandene, getestete
Primitiven (`FeedLogStore.logs(feedID:limit:)`, `FeedStore.feed(id:)`,
`Date.feedivoDisplay(mode:)`). Siehe Design-Spec:
`docs/superpowers/specs/2026-07-12-artikelliste-feed-status-zeile-design.md`.

**Tech Stack:** SwiftUI (macOS 14+), GRDB/SQLite.

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention).
- Neue `Localizable.xcstrings`-Einträge mit allen vier Sprachen (de/en/fr/it), alphabetisch
  korrekt einsortiert (Datei ist strikt alphabetisch nach Key sortiert).
- Build-Verifikation ausschließlich über `xcodebuild build`.
- Zeile nur sichtbar bei `scope == .feed` (Design-Entscheidung, siehe Spec).
- Bestehende `feedErrorBanner`-Leiste bleibt unverändert bestehen (Nutzerentscheid, siehe
  Spec) — bewusste Redundanz im Fehlerfall mit nicht-leerer Liste ist akzeptiert.
- `FeedStore.hasRecentError` selbst bleibt unangetastet (weiterhin von
  `FeedSidebarSnapshot`/`FeedRowView` genutzt, eigener Code-Pfad) — nur der eine direkte
  Aufrufer in `SQLiteFeedArticleListView.swift:507` wird ersetzt.

---

## Task 1: Feed-Status-Zeile implementieren

**Files:**
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift` (State-Property nahe
  Zeile 53, neue `@AppStorage` nahe Zeile 11, `articleListHeader` Zeilen 268-282,
  `reload()`-Fall `.feed` Zeilen 497-510, neuer privater Enum-Typ + Helper-Funktionen)
- Modify: `Feedivo/Resources/L10n.swift` (zwei neue `static func`-Accessoren)
- Modify: `Feedivo/Resources/Localizable.xcstrings` (zwei neue Keys
  `articleList.header.lastRefreshed` und `articleList.header.refreshFailed`, alphabetisch
  zwischen `articleList.feedNamePosition.beforeTitle` und `articleList.imagePosition.hidden`)

**Interfaces:**
- Konsumiert: `FeedLogStore.logs(feedID:limit:) throws -> [FeedLogRecord]` (bereits
  vorhanden, `Feedivo/Stores/FeedLogStore.swift:18-27`), `FeedLogEntryKind(rawValue:)`
  (bereits vorhanden, `Feedivo/Database/Records/FeedLogRecord.swift:6-9`, Vergleichsmuster
  bereits etabliert in `FeedPropertiesView.swift:880`), `FeedStore.feed(id:) throws ->
  FeedRecord?` (bereits vorhanden, `Feedivo/Stores/FeedStore.swift:18-24`),
  `Date.feedivoDisplay(mode: ArticleDateDisplayMode) -> String` (bereits vorhanden,
  `Feedivo/Extensions/Date+RelativeDisplay.swift:14-21`), `ArticleDateDisplayMode.storageKey`
  / `.resolved(from:)` (bereits etabliertes `@AppStorage`-Muster, siehe
  `Feedivo/Views/ArticleList/ArticleRowView.swift:18-19,30`).
- Produziert: nichts, das andere Tasks brauchen (eigenständige, abgeschlossene Änderung).

**Kontext:** `SQLiteFeedArticleListView.swift`s `reload()`-Methode (Fall `.feed`, Zeilen
497-510) ruft aktuell `FeedStore.hasRecentError(feedID:)` auf und setzt nur
`feedHasRecentError: Bool` (steuert ausschließlich die bestehende `feedErrorBanner`-Leiste,
`Zeilen 244-246`). Diese Abfrage wird durch `FeedLogStore.logs(feedID:limit:1)` ersetzt, die
sowohl `level` als auch `message` des letzten Aktualisierungsversuchs liefert — daraus lassen
sich `feedHasRecentError` (unverändertes Verhalten für die Banner-Leiste) UND der neue
Header-Zeilen-Zustand gemeinsam ableiten, ohne zwei separate Queries.

- [ ] **Step 1: Neuen Status-Enum-Typ und State-Property ergänzen**

Füge in `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift` direkt vor
`struct SQLiteFeedArticleListView: View {` ein:

```swift
/// Zustand der neuen Feed-Status-Zeile im Artikellisten-Header (nur bei `scope == .feed`).
/// `nil` bedeutet: Feed wurde noch nie aktualisiert (weder erfolgreich noch fehlgeschlagen),
/// Zeile bleibt dann ausgeblendet.
private enum FeedHeaderRefreshStatus: Equatable {
    case success(Date)
    case failure(String)
}

```

Füge direkt nach `@State private var feedHasRecentError = false` (aktuell Zeile 53) ein:

```swift
    @State private var feedHeaderRefreshStatus: FeedHeaderRefreshStatus?
```

Füge direkt nach dem bestehenden Block
`@AppStorage(SQLiteDataInvalidation.statusVersionKey) private var sqliteStatusVersion = 0`
(aktuell Zeilen 10-11) ein:

```swift
    @AppStorage(ArticleDateDisplayMode.storageKey)
    private var dateDisplayModeRawValue = ArticleDateDisplayMode.defaultMode.rawValue
```

- [ ] **Step 2: `reload()`-Fall `.feed` auf `FeedLogStore` umstellen**

Ersetze in `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift` (aktuell Zeilen
506-510):

```swift
            if let database {
                feedHasRecentError = (try? FeedStore(database: database).hasRecentError(feedID: feedID)) ?? false
            } else {
                feedHasRecentError = false
            }
```

durch:

```swift
            if let database {
                let latestLog = (try? FeedLogStore(database: database).logs(feedID: feedID, limit: 1))?.first
                let isLatestLogAnError = latestLog.map { FeedLogEntryKind(rawValue: $0.level) == .error } ?? false
                feedHasRecentError = isLatestLogAnError

                if isLatestLogAnError, let latestLog {
                    feedHeaderRefreshStatus = .failure(latestLog.message)
                } else if let lastRefreshedAt = (try? FeedStore(database: database).feed(id: feedID))?.lastRefreshedAt {
                    feedHeaderRefreshStatus = .success(lastRefreshedAt)
                } else {
                    feedHeaderRefreshStatus = nil
                }
            } else {
                feedHasRecentError = false
                feedHeaderRefreshStatus = nil
            }
```

- [ ] **Step 3: Dritte Zeile in `articleListHeader` ergänzen**

Ersetze in `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift` (aktuell Zeilen
268-282):

```swift
    private var articleListHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(navigationTitle)
                .font(interfaceTextSize.font(size: 13, weight: .medium))
                .lineLimit(1)

            Text(unreadArticleCountText)
                .font(interfaceTextSize.font(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
```

durch:

```swift
    private var articleListHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(navigationTitle)
                .font(interfaceTextSize.font(size: 13, weight: .medium))
                .lineLimit(1)

            Text(unreadArticleCountText)
                .font(interfaceTextSize.font(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if case .feed = scope, let feedHeaderRefreshStatus {
                Text(feedHeaderRefreshStatusText(feedHeaderRefreshStatus))
                    .font(interfaceTextSize.font(size: 13))
                    .foregroundStyle(feedHeaderRefreshStatusColor(feedHeaderRefreshStatus))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func feedHeaderRefreshStatusText(_ status: FeedHeaderRefreshStatus) -> String {
        switch status {
        case let .success(date):
            L10n.articleListLastRefreshed(
                date.feedivoDisplay(mode: ArticleDateDisplayMode.resolved(from: dateDisplayModeRawValue))
            )
        case let .failure(reason):
            L10n.articleListRefreshFailed(reason)
        }
    }

    private func feedHeaderRefreshStatusColor(_ status: FeedHeaderRefreshStatus) -> Color {
        switch status {
        case .success:
            .secondary
        case .failure:
            .orange
        }
    }
```

- [ ] **Step 4: L10n-Accessoren ergänzen**

Füge in `Feedivo/Resources/L10n.swift` direkt nach
`static let articleListLoadFailedTitle = String(localized: "articleList.loadFailed.title")`
(aktuell Zeile 55) ein:

```swift
    static func articleListLastRefreshed(_ date: String) -> String {
        String.localizedStringWithFormat(String(localized: "articleList.header.lastRefreshed"), date)
    }

    static func articleListRefreshFailed(_ reason: String) -> String {
        String.localizedStringWithFormat(String(localized: "articleList.header.refreshFailed"), reason)
    }
```

(Hinweis: Diese beiden sind `static func`, nicht `static let` wie die Nachbarzeilen — das ist
in `L10n.swift` bereits gängige Praxis für Format-Strings mit Platzhaltern, siehe z. B.
`ruleWizardPreviewMatchCount(count:)` weiter unten in derselben Datei.)

- [ ] **Step 5: Neue Keys in `Localizable.xcstrings` anlegen**

Füge in `Feedivo/Resources/Localizable.xcstrings` zwischen dem Ende von
`"articleList.feedNamePosition.beforeTitle"` und dem Beginn von
`"articleList.imagePosition.hidden"` folgende zwei Blöcke ein (alphabetisch: `header.last...`
vor `header.refresh...` vor `imagePosition...`):

```json
    "articleList.header.lastRefreshed" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Zuletzt aktualisiert: %@"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Last updated: %@"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Dernière mise à jour : %@"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ultimo aggiornamento: %@"
          }
        }
      }
    },
    "articleList.header.refreshFailed" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Konnte nicht aktualisiert werden: %@"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Could not be updated: %@"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Impossible de mettre à jour : %@"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Impossibile aggiornare: %@"
          }
        }
      }
    },
```

- [ ] **Step 6: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build 2>&1 | tail -30`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Bestehende, verwandte Tests gezielt laufen lassen**

Kein neuer automatisierter Test (reine View-/State-Verdrahtung, kein dedizierter
Test-Harness für `SQLiteFeedArticleListView.swift` vorhanden — konsistent mit dem
etablierten Projektmuster für reine View-Änderungen). Stattdessen sicherstellen, dass die
wiederverwendeten, bereits getesteten Bausteine nicht durch diesen Task versehentlich
verändert wurden:

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedStoreTests 2>&1 | tail -60`
Expected: alle Tests PASS, insbesondere
`hasRecentErrorLiefertStatusFuerEinzelnenFeed`/`hasRecentErrorLiefertFalseFuerUnbekannteFeedID`
(unverändert, da `FeedStore.hasRecentError` selbst nicht angefasst wird).

- [ ] **Step 8: `git status`/`git diff --stat` auf `Localizable.xcstrings` prüfen**

Sicherstellen, dass `xcodebuild build` keine zusätzlichen automatischen Stub-Einträge
hinzugefügt hat (bekannter Gotcha, siehe CLAUDE.md). Falls doch, bewusst mitcommitten.

- [ ] **Step 9: Manuelle Sichtprüfung (kein automatisierter Test möglich)**

Notiere im Abschluss, dass eine manuelle visuelle Verifikation noch aussteht (kein
computer-use für native macOS-Apps in dieser Umgebung verfügbar): einen Feed auswählen und
prüfen, dass „Zuletzt aktualisiert: …" erscheint; einen Feed-Refresh-Fehler provozieren
(z. B. Feed-URL mit ungültigem Host) und prüfen, dass stattdessen „Konnte nicht aktualisiert
werden: …" mit dem tatsächlichen Fehlertext erscheint; bei Tags/Smart Filtern/Ordnern darf
keine dritte Zeile erscheinen.

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature: Feed-Status-Zeile im Artikellisten-Header (zuletzt aktualisiert / Fehlergrund)"
```

---

## Nach Abschluss

- Whole-Branch-Review nicht zwingend nötig für einen einzelnen Task (kein Multi-Task-Plan),
  aber ein finaler Blick auf den Diff ist sinnvoll, bevor gepusht wird.
- Push nach `origin/main` nur nach expliziter Nutzerbestätigung (siehe CLAUDE.md
  „Push-Konvention").
