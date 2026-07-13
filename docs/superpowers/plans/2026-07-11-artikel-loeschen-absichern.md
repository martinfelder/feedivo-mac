# Artikel-Löschen absichern — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Artikel-Löschen aus dem Artikellisten-Kontextmenü bekommt eine
Bestätigung (Finding 1.1) und ein fehlgeschlagenes Löschen wird dem Nutzer
sichtbar angezeigt statt stumm verschluckt (Finding 1.2).

**Architecture:** Die DELETE-Logik wandert von der SwiftUI-View
(`SQLiteFeedArticleListView.deleteArticle(_:)`) in die bereits testbare
`@Observable`-Klasse `SQLiteFeedArticleListState`, analog zum bestehenden
`mutateStatus`-Muster (`toggleRead`/`toggleStarred`/`toggleArchived`). Die
neue Methode gibt `Bool` zurück, damit die View weiterhin
`selectedArticleID`/`SQLiteDataInvalidation.bumpStatusVersion()` nur bei
Erfolg auslöst. Vor dem eigentlichen Löschen zeigt die View einen
`.confirmationDialog` (Vorbild: `ContentView.swift`s Feed-Löschen-Dialog).

**Tech Stack:** SwiftUI, GRDB (SQLite), Swift Testing (`@testable import
Feedivo`), bestehendes L10n/`Localizable.xcstrings`-System (de/en/fr/it).

## Global Constraints

- Arbeitsweise für diese Gruppe: Commits direkt auf `main` (Nutzerentscheid
  für diese Gruppe, keine generelle Regel).
- Kommentare im Code auf Deutsch (Projektkonvention laut CLAUDE.md).
- Keine neuen Abstraktionen über das hier Nötige hinaus (SQL-Konsolidierung
  ist Finding 1.8/1.9, NICHT Teil dieser Gruppe).
- Nach jedem Task: gezielter Testlauf via
  `-only-testing:FeedivoTests/SQLiteFeedArticleListStateTests` (volle
  Testsuite hängt laut CLAUDE.md-Gotcha) + `xcodebuild build` für die
  View-Änderung (SourceKit-Diagnosen sind laut Gotcha unzuverlässig, nur ein
  echter Build zählt).
- `Localizable.xcstrings`: reale Übersetzungen für de/en/fr/it liefern (nicht
  auf den automatischen leeren Stub verlassen), siehe Finding 1.7/2.3-Kontext.

---

## Vorher/Nachher zur Einordnung

**Vorher** (`Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:781-798`):

```swift
private func deleteArticle(_ articleID: String) {
    guard let database else {
        return
    }

    do {
        try database.write { db in
            try db.execute(sql: "DELETE FROM articles WHERE id = ?", arguments: [articleID])
        }
        if selectedArticleID == articleID {
            selectedArticleID = nil
        }
        SQLiteDataInvalidation.bumpStatusVersion()
        reload()
    } catch {
        reload()
    }
}
```

Aufgerufen direkt aus dem Kontextmenü-Button
(`Feedivo/Views/ArticleList/ArticleRowView.swift:153-155`,
`role: .destructive`) ohne jede Zwischenbestätigung. Ein Fehlschlag beim
DELETE ruft nur `reload()` auf — keine sichtbare Fehlermeldung.

**Nachher:** Kontextmenü-Klick löst `.confirmationDialog` aus (analog
`ContentView.swift:199-213`); erst nach explizitem Bestätigen läuft das
DELETE über die neue, testbare
`SQLiteFeedArticleListState.deleteArticle(articleID:database:)`. Schlägt das
DELETE fehl, landet die Fehlermeldung in `state.loadState = .failed(...)` —
dieser Zustand wird bereits von `articleContent`
(`SQLiteFeedArticleListView.swift:179-184`) als sichtbarer
`ContentUnavailableView` gerendert, es ist also keine neue UI nötig, nur die
korrekte Zustandsanbindung.

---

### Task 1: `SQLiteFeedArticleListState.deleteArticle(articleID:database:)` mit Tests

**Files:**
- Modify: `Feedivo/ViewModels/SQLiteFeedArticleListState.swift`
- Test: `FeedivoTests/SQLiteFeedArticleListStateTests.swift`

**Interfaces:**
- Produces: `@discardableResult func deleteArticle(articleID: String, database: FeedivoDatabase) -> Bool`
  auf `SQLiteFeedArticleListState` — `true` bei Erfolg (Zeile wurde aus
  `rows` entfernt), `false` bei Fehler (zusätzlich `loadState = .failed(String)`
  gesetzt, `rows` bleibt unverändert).

- [ ] **Step 1: Failing Test schreiben — erfolgreiches Löschen entfernt die Row**

In `FeedivoTests/SQLiteFeedArticleListStateTests.swift`, neuen Test
direkt nach `listStateToggeltReadUndAktualisiertRows()` (nach Zeile 40)
einfügen:

```swift
@Test func listStateLoeschtArtikelUndEntferntIhnAusRows() async throws {
    let (database, firstID, secondID) = try makeDatabaseWithFeedAndArticles()
    let state = SQLiteFeedArticleListState()

    state.load(
        feedID: "feed-1",
        database: database,
        selectedArticleID: firstID
    )
    await waitForLoad(state)

    let succeeded = state.deleteArticle(articleID: firstID, database: database)

    #expect(succeeded)
    #expect(state.rows.map(\.id) == [secondID])
    #expect(state.loadState == .loaded)
}
```

- [ ] **Step 2: Zweiten Failing Test schreiben — fehlgeschlagenes Löschen setzt `.failed`**

Direkt danach einfügen:

```swift
@Test func listStateSetztFailedStateWennLoeschenFehlschlaegt() async throws {
    let (database, firstID, _) = try makeDatabaseWithFeedAndArticles()
    let state = SQLiteFeedArticleListState()

    state.load(
        feedID: "feed-1",
        database: database,
        selectedArticleID: firstID
    )
    await waitForLoad(state)
    try database.write { db in
        try db.execute(sql: "DROP TABLE articles")
    }

    let succeeded = state.deleteArticle(articleID: firstID, database: database)

    #expect(!succeeded)
    #expect(state.rows.map(\.id) == [firstID])
    guard case .failed = state.loadState else {
        Issue.record("Erwartete .failed nach fehlgeschlagenem Loeschen, war \(state.loadState)")
        return
    }
}
```

- [ ] **Step 3: Tests laufen lassen, RED verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -parallel-testing-enabled NO`
Expected: Compile-Fehler — `deleteArticle` existiert auf
`SQLiteFeedArticleListState` noch nicht. Das ist der erwartete RED-Zustand
für eine neue Methode.

- [ ] **Step 4: Minimale Implementierung**

In `Feedivo/ViewModels/SQLiteFeedArticleListState.swift`, direkt nach
`toggleArchived(articleID:database:)` (nach Zeile 296, vor
`private func mutateStatus`) einfügen:

```swift
    // Kein reload() nach einem fehlgeschlagenen Loeschen: reload() wuerde
    // ueber startLoad() den gerade gesetzten .failed-Zustand sofort wieder
    // ueberschreiben (startLoad setzt loadState = .idle, danach ggf. .loaded),
    // und die Fehlermeldung waere fuer den Nutzer nie sichtbar gewesen.
    @discardableResult
    func deleteArticle(articleID: String, database: FeedivoDatabase) -> Bool {
        do {
            try database.write { db in
                try db.execute(sql: "DELETE FROM articles WHERE id = ?", arguments: [articleID])
            }
            rows.removeAll { $0.id == articleID }
            return true
        } catch {
            loadState = .failed(error.localizedDescription)
            return false
        }
    }
```

- [ ] **Step 5: Tests laufen lassen, GREEN verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -parallel-testing-enabled NO`
Expected: Alle Tests in der Suite PASS, inklusive der 2 neuen.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/ViewModels/SQLiteFeedArticleListState.swift FeedivoTests/SQLiteFeedArticleListStateTests.swift
git commit -m "Fix: SQLiteFeedArticleListState.deleteArticle setzt sichtbaren Fehlerzustand statt stumm zu verwerfen"
```

---

### Task 2: L10n-Keys für Lösch-Bestätigung

**Files:**
- Modify: `Feedivo/Resources/L10n.swift:484` (neuer Key direkt danach)
- Modify: `Feedivo/Resources/L10n.swift:717` (neue Funktion direkt danach,
  vor `feedErrorRefreshAllPartial`)
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces: `L10n.articleDeleteConfirmationTitle: String`,
  `L10n.articleDeleteConfirmationMessage(articleTitle: String) -> String`
- Consumes (bereits vorhanden): `L10n.articleDeleteCommand: String` (wird in
  Task 3 als Text des destruktiven Bestätigungs-Buttons wiederverwendet,
  keine neue Taste dafür nötig — identischer Text wie im Kontextmenü-Eintrag).

- [ ] **Step 1: Neuen `String`-Key in `L10n.swift` ergänzen**

In `Feedivo/Resources/L10n.swift`, Zeile 484 (`static let
articleDeleteCommand = ...`), direkt danach einfügen:

```swift
    static let articleDeleteConfirmationTitle = String(localized: "article.delete.confirmation.title")
```

- [ ] **Step 2: Neue Format-Funktion in `L10n.swift` ergänzen**

In `Feedivo/Resources/L10n.swift`, nach der bestehenden Funktion
`feedDeleteConfirmationMessage(feedTitle:)` (endet bei Zeile 717, vor
`feedErrorRefreshAllPartial` in Zeile 719), einfügen:

```swift
    static func articleDeleteConfirmationMessage(articleTitle: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "article.delete.confirmation.message"),
            articleTitle
        )
    }
```

- [ ] **Step 3: Beide Keys in `Localizable.xcstrings` mit allen 4 Sprachen ergänzen**

In `Feedivo/Resources/Localizable.xcstrings`, im `"strings"`-Objekt
alphabetisch zwischen `"article.delete.command"` und
`"article.export.command"` einfügen:

```json
    "article.delete.confirmation.message" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "„%@“ wird unwiderruflich gelöscht."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "\"%@\" will be permanently deleted."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "« %@ » sera définitivement supprimé."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "\"%@\" verrà eliminato definitivamente."
          }
        }
      }
    },
    "article.delete.confirmation.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Artikel löschen?"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Delete article?"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Supprimer l'article ?"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Eliminare l'articolo?"
          }
        }
      }
    },
```

Am einfachsten mit einem kleinen Python-Snippet einfügen (JSON-Struktur ist
sonst fehleranfällig per Hand), z. B.:

```bash
python3 - <<'EOF'
import json
from collections import OrderedDict

path = "Feedivo/Resources/Localizable.xcstrings"
with open(path) as f:
    data = json.load(f, object_pairs_hook=OrderedDict)

new_entries = {
    "article.delete.confirmation.title": {
        "localizations": {
            "de": {"stringUnit": {"state": "translated", "value": "Artikel löschen?"}},
            "en": {"stringUnit": {"state": "translated", "value": "Delete article?"}},
            "fr": {"stringUnit": {"state": "translated", "value": "Supprimer l'article ?"}},
            "it": {"stringUnit": {"state": "translated", "value": "Eliminare l'articolo?"}},
        }
    },
    "article.delete.confirmation.message": {
        "localizations": {
            "de": {"stringUnit": {"state": "translated", "value": "„%@“ wird unwiderruflich gelöscht."}},
            "en": {"stringUnit": {"state": "translated", "value": "\"%@\" will be permanently deleted."}},
            "fr": {"stringUnit": {"state": "translated", "value": "« %@ » sera définitivement supprimé."}},
            "it": {"stringUnit": {"state": "translated", "value": "\"%@\" verrà eliminato definitivamente."}},
        }
    },
}

new_strings = OrderedDict()
for key, value in data["strings"].items():
    new_strings[key] = value
    if key == "article.delete.command":
        for new_key, new_value in new_entries.items():
            new_strings[new_key] = new_value

data["strings"] = new_strings

with open(path, "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=False)
    f.write("\n")
EOF
```

- [ ] **Step 4: JSON-Validität und Build prüfen**

Run: `python3 -c "import json; json.load(open('Feedivo/Resources/Localizable.xcstrings'))" && echo OK`
Expected: `OK`

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`, `git diff --stat
Feedivo/Resources/Localizable.xcstrings` zeigt nur die 2 neuen Einträge (kein
zusätzlicher Auto-Stub für andere Strings).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Doku: L10n-Keys fuer Artikel-Loesch-Bestaetigung ergaenzt (de/en/fr/it)"
```

---

### Task 3: `.confirmationDialog` in `SQLiteFeedArticleListView` verdrahten

**Files:**
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:51-63` (neue `@State`-Properties)
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:142-160` (`.confirmationDialog`-Modifier ergänzen)
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:317-319` (`onDelete`-Closure)
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:781-798` (`deleteArticle`-Funktion ersetzen)

**Interfaces:**
- Consumes: `SQLiteFeedArticleListState.deleteArticle(articleID:database:) -> Bool` (Task 1),
  `L10n.articleDeleteConfirmationTitle`, `L10n.articleDeleteConfirmationMessage(articleTitle:)`,
  `L10n.articleDeleteCommand` (Task 2), `L10n.commonCancel` (bereits vorhanden).

- [ ] **Step 1: Neue `@State`-Properties ergänzen**

In `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`, nach Zeile 54
(`@State private var ruleCreationRequest: ArticleListRuleCreationRequest?`)
einfügen:

```swift
    @State private var articlePendingDeletion: ArticleListSnapshot?
    @State private var isDeleteArticleConfirmationPresented = false
```

- [ ] **Step 2: `.confirmationDialog`-Modifier ergänzen**

In `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`, im `body`
direkt nach dem bestehenden `.sheet(item: $ruleCreationRequest) { ... }`
(endet bei Zeile 152) und vor `.toolbar { ... }` (Zeile 153) einfügen:

```swift
        .confirmationDialog(
            L10n.articleDeleteConfirmationTitle,
            isPresented: $isDeleteArticleConfirmationPresented,
            presenting: articlePendingDeletion
        ) { row in
            Button(L10n.articleDeleteCommand, role: .destructive) {
                deleteArticle(row)
            }

            Button(L10n.commonCancel, role: .cancel) {
                articlePendingDeletion = nil
            }
        } message: { row in
            Text(L10n.articleDeleteConfirmationMessage(articleTitle: row.title))
        }
```

- [ ] **Step 3: Kontextmenü-Aufruf auf Bestätigungs-Anfrage umstellen**

In `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:317-319`
ändern von:

```swift
            onDelete: {
                deleteArticle(row.id)
            },
```

zu:

```swift
            onDelete: {
                requestDeleteArticle(row)
            },
```

- [ ] **Step 4: `deleteArticle`-Funktion ersetzen**

In `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:781-798`, die
komplette bestehende Funktion ersetzen durch:

```swift
    private func requestDeleteArticle(_ row: ArticleListSnapshot) {
        articlePendingDeletion = row
        isDeleteArticleConfirmationPresented = true
    }

    private func deleteArticle(_ row: ArticleListSnapshot) {
        articlePendingDeletion = nil

        guard let database else {
            return
        }

        guard state.deleteArticle(articleID: row.id, database: database) else {
            return
        }

        if selectedArticleID == row.id {
            selectedArticleID = nil
        }
        SQLiteDataInvalidation.bumpStatusVersion()
    }
```

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`. (SourceKit-Fehleranzeigen in der IDE vor diesem
Schritt ignorieren, siehe CLAUDE.md-Gotcha.)

- [ ] **Step 6: Zielgerichteten Regressionstest laufen lassen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -parallel-testing-enabled NO`
Expected: Weiterhin alle PASS (keine Regression durch die View-Änderung, da
diese nur den bereits getesteten State-Layer aufruft).

- [ ] **Step 7: Manuelle Verifikation (Hinweis, nicht automatisierbar)**

Kein computer-use für native macOS-Apps in dieser Umgebung verfügbar (siehe
CLAUDE.md). Der Nutzer sollte nach Abschluss der Gruppe manuell prüfen:
Rechtsklick auf einen Artikel → "Artikel löschen" → Bestätigungsdialog
erscheint → "Abbrechen" lässt Artikel unverändert → erneuter Versuch mit
"Artikel löschen" (destruktiv) löscht ihn tatsächlich.

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift
git commit -m "Fix: Artikel-Loeschen im Kontextmenue erfordert Bestaetigung (Finding 1.1)"
```

---

## Abschluss dieser Gruppe

Nach Task 3: kurze Zusammenfassung für den Nutzer (Commits, Testergebnis),
dann Rückfrage, ob mit Gruppe 2 (Bulk-Aktionen-/Sidebar-Fehleranzeige: 1.3,
1.4, 1.6) fortgefahren werden soll — inklusive erneuter Nachfrage main vs.
eigener Branch für diese nächste Gruppe.
