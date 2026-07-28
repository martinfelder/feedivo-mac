# Lokalisierungslücken schließen (Findings 1.7 + 2.3 + FeedRenameView) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Alle in Findings 1.7, 2.3 und dem FeedRenameView-Punkt (Review-Abschnitt 3)
dokumentierten strukturell nie lokalisierbaren bzw. nur als leere Katalog-Stubs
existierenden deutschen Hardcode-Strings über echte `L10n`-Keys mit vollständigen
de/en/fr/it-Übersetzungen führen.

**Architecture:** Reine Lokalisierungs-Konsolidierung, keine neue Logik. Für jeden
betroffenen String: (1) `L10n.swift`-Property nach etabliertem Muster
(`static let xxxKey = String(localized: "dot.notation.key")`) ergänzen, (2) passenden
Eintrag in `Localizable.xcstrings` mit allen 4 Sprachen einfügen, (3) den/die
Aufrufstelle(n) auf die neue Property umstellen. Wo derselbe String mehrfach unabhängig
dupliziert ist (z. B. "SQLite nicht verfügbar" in 2 Dateien, "Die lokale Artikeldatenbank
konnte nicht geöffnet werden." in 3 Dateien, "SQLite-Datenbank ist nicht verfügbar." 3× in
einer Datei), wird EIN gemeinsamer Key für alle Stellen verwendet statt pro Datei ein
eigener — konsistent mit dem DRY-Prinzip der vorherigen Gruppe (SQL-/HTML-Duplikation).

**Tech Stack:** Swift, SwiftUI, `Localizable.xcstrings` (String Catalog, JSON-Format).

## Global Constraints

- **Kein granulares TDD für diese Gruppe** — bewusste Abweichung vom Muster der
  Gruppen 1-4, weil hier keine testbare Logik entsteht (reine String-Konstanten-
  Verdrahtung). Das Review-Dokument selbst empfiehlt für diesen Schritt: "eher
  mechanisch und könnte in einem Rutsch ohne granulares TDD erledigt werden, sollte
  aber am Ende gegen `Localizable.xcstrings` in allen 4 Sprachen (de/en/fr/it)
  verifiziert werden." Statt RED/GREEN-Tests gilt pro Task: `xcodebuild build`
  erfolgreich (beweist, dass alle neuen Keys kompilieren und referenziert werden
  können) + Grep-Verifikation, dass an den Zielstellen keine Hardcode-Literale mehr
  übrig sind.
- **`Localizable.xcstrings` NIEMALS per Skript/`json.dump` komplett neu schreiben** —
  bekannter Gotcha aus Gruppe „Artikel-Löschen absichern": das reformatiert die
  gesamte ~29 000-Zeilen-Datei (37 000+ geänderte Zeilen statt der paar Dutzend
  tatsächlich nötigen). Neue Einträge ausschließlich per gezieltem `Edit`-Tool-Aufruf
  einfügen, an der in der jeweiligen Task exakt angegebenen Stelle (Ankerzeile per
  `grep` vorab verifiziert).
- **L10n-Key-Namenskonvention:** `"bereich.unterbereich.name"` (Kleinbuchstaben,
  Punkt-getrennt, camelCase innerhalb eines Segments), Swift-Property-Name ist die
  camelCase-Verschmelzung ohne Punkte (`"db.unavailable.title"` →
  `L10n.dbUnavailableTitle`). Alle neuen Properties als
  `static let xxxKey = String(localized: "dot.notation.key")` (matcht die
  überwiegende Mehrheit der bestehenden `L10n.swift`-Einträge, z. B.
  `feedRenameSave`, `articleDeleteConfirmationTitle` aus Gruppe 1) — NICHT
  `LocalizedStringKey(...)`, da alle Zielstellen entweder `String`-typisierte
  Properties befüllen oder `ContentUnavailableView`s `String`-Overload nutzen
  (Präzedenzfall: `L10n.databaseInitErrorTitle`, bereits als `String` an
  `ContentUnavailableView` übergeben, siehe `ContentView.swift:226`).
- **Verwaiste Auto-Stub-Einträge bewusst NICHT löschen:** Mehrere der hier ersetzten
  Hardcode-Strings ("Artikel konnten nicht geladen werden", "Artikel nicht gefunden",
  "Feed noch nicht in SQLite", "Noch kein Artikel geladen", "SQLite nicht verfügbar",
  "Die lokale Artikeldatenbank konnte nicht geöffnet werden.", "Dieser Feed ist noch
  nicht in der lokalen Artikeldatenbank vorhanden.") haben bereits leere
  Auto-Stub-Einträge in `Localizable.xcstrings` (von früheren `xcodebuild build`-Läufen
  automatisch angelegt, siehe CLAUDE.md-Gotcha). Nach der Umstellung auf `L10n`-Keys
  werden diese Literal-Keys nicht mehr referenziert und damit zu totem Katalog-Ballast
  — laut etablierter Projekt-Praxis (Dead-Code-Cleanup 2026-07-10) harmlos, Xcode
  markiert sie beim nächsten Build automatisch als `extractionState: stale`. Nicht
  manuell aus der Datei entfernen (unnötiges Diff-Rauschen).
- **Ausstehend nach Abschluss (nicht automatisierbar in dieser Umgebung):** Manuelle
  visuelle Verifikation aller geänderten Zustände in allen 4 Sprachen (de/en/fr/it) durch
  den Nutzer — kein computer-use für native macOS-Apps verfügbar, konsistent mit dem
  bereits etablierten Muster für UI-Änderungen in diesem Projekt (siehe CLAUDE.md
  „Aktuell in Arbeit").
- Alle Commits laufen direkt auf `main` (etablierte Praxis der Gruppen 1-4 in dieser
  Session).

---

## Vorab-Verifikation (bereits erledigt, hier dokumentiert)

Gegen den aktuellen Code auf `main` (HEAD nach Gruppe 4, Commit `a6ac64c5`) verifiziert:

- **Finding 1.7:** `SQLiteFeedArticleListView.swift`s `emptyTitle`/`emptyDescription`
  (aktuell Zeilen ~435-458, im Review noch als 418-441 zitiert — Verschiebung durch
  Gruppe 1-3-Arbeit an anderer Stelle derselben Datei) bestätigt hardcodiert. **Neue
  Erkenntnis, die im Review fehlt:** `L10n.articleListEmptyTitle`/
  `L10n.articleListEmptyDescription` **existieren bereits** und werden bereits korrekt
  in dieser Datei verwendet — aber an einer ANDEREN Stelle
  (`articleListEmptyState(isSearching:)`, Zeile 343-357, für den Fall "Scope hat
  Artikel, aber Filter/Suche liefert 0 Treffer"). Der von Finding 1.7 beschriebene Fall
  (Zeile 207-214, "Scope hat GAR KEINE Artikel") ist ein separater Code-Pfad mit eigener
  hardcodierter Logik. `L10n.articleListEmptyTitle`s deutscher Text ist "Keine Artikel"
  — exakt identisch zum hardcodierten Fallback in `emptyTitle`, daher sicher
  wiederverwendbar (keine neue Übersetzungsarbeit nötig). Die 4 Scope-spezifischen
  `emptyDescription`-Texte sind jeweils eigenständig und brauchen neue Keys.
- **Finding 2.3:** Alle 5 zitierten Titel-Strings ("SQLite nicht verfügbar", "Feed noch
  nicht in SQLite", "Artikel konnten nicht geladen werden", "Noch kein Artikel geladen",
  "Artikel nicht gefunden") sowie 2 der Beschreibungs-Strings ("Die lokale
  Artikeldatenbank konnte nicht geöffnet werden.", "Dieser Feed ist noch nicht in der
  lokalen Artikeldatenbank vorhanden.") haben bereits **leere** Auto-Stub-Einträge in
  `Localizable.xcstrings` (`"key" : {}`, keine `localizations`) — exakt das im Review
  beschriebene Muster. `"Der Artikel ist nicht mehr in der lokalen Datenbank
  vorhanden."` (Fallback in einer `??`-Kette) und `"SQLite-Datenbank ist nicht
  verfügbar."` (FeedRenameView, reine `String`-Zuweisung) haben dagegen **gar keinen**
  Katalog-Eintrag — auch das deckt sich mit dem Review (Xcodes statischer Extraktor
  erkennt beide Stellen nicht, weil sie nicht direkt als Literal an einen
  `Text`/`ContentUnavailableView`-Parameter übergeben werden).
- **FeedRenameView-Punkt:** 3 identische Vorkommen von `errorMessage = "SQLite-
  Datenbank ist nicht verfügbar."` bestätigt (Zeilen 158, 174, 192 — Review zitierte
  dieselben Zeilen, keine Verschiebung).

---

### Task 1: `SQLiteFeedArticleListView.swift` — Finding 1.7 vollständig + Finding 2.3 (3 von 5 Zuständen)

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`

**Interfaces:**
- Produces: `L10n.articleListEmptyDescriptionFeed`, `L10n.articleListEmptyDescriptionTag`,
  `L10n.articleListEmptyDescriptionSmartFilter`,
  `L10n.articleListEmptyDescriptionSmartFolder`, `L10n.articleListLoadFailedTitle`,
  `L10n.dbUnavailableTitle`, `L10n.dbUnavailableDescription`,
  `L10n.feedNotInSQLiteTitle`, `L10n.feedNotInSQLiteDescription` (alle `String`) — werden
  in Task 2 wiederverwendet (`dbUnavailableTitle`/`dbUnavailableDescription`).
- Consumes: `L10n.articleListEmptyTitle` (bereits vorhanden, `Feedivo/Resources/L10n.swift:49`).

- [ ] **Step 1: 9 neue Properties in `L10n.swift` ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach Zeile 50
(`static let articleListEmptyDescription = LocalizedStringKey("articleList.empty.description")`)
einfügen:

```swift
    static let articleListEmptyDescriptionFeed = String(localized: "articleList.empty.description.feed")
    static let articleListEmptyDescriptionTag = String(localized: "articleList.empty.description.tag")
    static let articleListEmptyDescriptionSmartFilter = String(localized: "articleList.empty.description.smartFilter")
    static let articleListEmptyDescriptionSmartFolder = String(localized: "articleList.empty.description.smartFolder")
    static let articleListLoadFailedTitle = String(localized: "articleList.loadFailed.title")
    static let dbUnavailableTitle = String(localized: "db.unavailable.title")
    static let dbUnavailableDescription = String(localized: "db.unavailable.description")
    static let feedNotInSQLiteTitle = String(localized: "feed.notInSQLite.title")
    static let feedNotInSQLiteDescription = String(localized: "feed.notInSQLite.description")
```

- [ ] **Step 2: `articleList.empty.description.*` (4 Keys) in `Localizable.xcstrings` einfügen**

Verifiziere zuerst die Ankerzeile:
`grep -n '"articleList.empty.title"' Feedivo/Resources/Localizable.xcstrings`
Erwartet: Treffer bei Zeile 3222 (kann sich durch spätere Bearbeitung leicht
verschieben — die Zeile direkt VOR diesem Treffer, `    },`, ist die exakte
Einfügeposition).

Füge direkt VOR der Zeile `    "articleList.empty.title" : {` folgenden Block ein
(alphabetische Reihenfolge: feed, smartFilter, smartFolder, tag):

```json
    "articleList.empty.description.feed" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Für diesen Feed sind noch keine SQLite-Artikel gespeichert."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No SQLite articles have been saved for this feed yet."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aucun article SQLite n'a encore été enregistré pour ce flux."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Per questo feed non è ancora stato salvato alcun articolo SQLite."
          }
        }
      }
    },
    "articleList.empty.description.smartFilter" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Für diesen Filter sind noch keine SQLite-Artikel gespeichert."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No SQLite articles have been saved for this filter yet."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aucun article SQLite n'a encore été enregistré pour ce filtre."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Per questo filtro non è ancora stato salvato alcun articolo SQLite."
          }
        }
      }
    },
    "articleList.empty.description.smartFolder" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Für diesen intelligenten Ordner sind noch keine SQLite-Artikel gespeichert."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No SQLite articles have been saved for this smart folder yet."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aucun article SQLite n'a encore été enregistré pour ce dossier intelligent."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Per questa cartella intelligente non è ancora stato salvato alcun articolo SQLite."
          }
        }
      }
    },
    "articleList.empty.description.tag" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Für dieses Tag sind noch keine SQLite-Artikel gespeichert."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No SQLite articles have been saved for this tag yet."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aucun article SQLite n'a encore été enregistré pour cette étiquette."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Per questo tag non è ancora stato salvato alcun articolo SQLite."
          }
        }
      }
    },
```

- [ ] **Step 3: `articleList.loadFailed.title` in `Localizable.xcstrings` einfügen**

Verifiziere Ankerzeile: `grep -n '"articleList.loadingMore"' Feedivo/Resources/Localizable.xcstrings`
(erwartet: nach den 4 in Step 2 eingefügten Keys um 4 Blöcke = ~112 Zeilen
verschoben gegenüber der ursprünglichen Zeile 3390 — die Zeile direkt VOR diesem
Treffer ist die Einfügeposition).

Füge direkt VOR `    "articleList.loadingMore" : {` ein:

```json
    "articleList.loadFailed.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Artikel konnten nicht geladen werden"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Articles Could Not Be Loaded"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Impossible de charger les articles"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Impossibile caricare gli articoli"
          }
        }
      }
    },
```

- [ ] **Step 4: `db.unavailable.*` (2 Keys) in `Localizable.xcstrings` einfügen**

Verifiziere Ankerzeile: `grep -n '"Deutsch, Englisch, Französisch und Italienisch sind vorbereitet."' Feedivo/Resources/Localizable.xcstrings`
(ursprünglich Zeile 4566, verschiebt sich durch Steps 2-3 um ca. +150 Zeilen).

Füge direkt VOR dieser Zeile ein (alphabetisch: description vor title):

```json
    "db.unavailable.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Die lokale Artikeldatenbank konnte nicht geöffnet werden."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "The local article database could not be opened."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Impossible d'ouvrir la base de données locale des articles."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Impossibile aprire il database locale degli articoli."
          }
        }
      }
    },
    "db.unavailable.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "SQLite nicht verfügbar"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "SQLite Unavailable"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "SQLite indisponible"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "SQLite non disponibile"
          }
        }
      }
    },
```

- [ ] **Step 5: `feed.notInSQLite.*` (2 Keys) in `Localizable.xcstrings` einfügen**

Verifiziere Ankerzeile: `grep -n '"feed.progress.opmlImport.title"' Feedivo/Resources/Localizable.xcstrings`
(ursprünglich Zeile 5604, verschiebt sich durch die vorherigen Steps).

Füge direkt VOR dieser Zeile ein (alphabetisch: description vor title):

```json
    "feed.notInSQLite.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Dieser Feed ist noch nicht in der lokalen Artikeldatenbank vorhanden."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "This feed does not exist in the local article database yet."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ce flux n'existe pas encore dans la base de données locale des articles."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Questo feed non esiste ancora nel database locale degli articoli."
          }
        }
      }
    },
    "feed.notInSQLite.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed noch nicht in SQLite"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed Not Yet in SQLite"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Flux pas encore dans SQLite"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed non ancora in SQLite"
          }
        }
      }
    },
```

- [ ] **Step 6: `articleContent`-Switch in `SQLiteFeedArticleListView.swift` umstellen**

Ersetze (aktuell Zeilen ~184-201):

```swift
            case .missingSQLiteDatabase:
                ContentUnavailableView(
                    "SQLite nicht verfügbar",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Die lokale Artikeldatenbank konnte nicht geöffnet werden.")
                )
            case .missingFeed:
                ContentUnavailableView(
                    "Feed noch nicht in SQLite",
                    systemImage: "tray",
                    description: Text("Dieser Feed ist noch nicht in der lokalen Artikeldatenbank vorhanden.")
                )
            case .failed(let message):
                ContentUnavailableView(
                    "Artikel konnten nicht geladen werden",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
```

durch:

```swift
            case .missingSQLiteDatabase:
                ContentUnavailableView(
                    L10n.dbUnavailableTitle,
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(L10n.dbUnavailableDescription)
                )
            case .missingFeed:
                ContentUnavailableView(
                    L10n.feedNotInSQLiteTitle,
                    systemImage: "tray",
                    description: Text(L10n.feedNotInSQLiteDescription)
                )
            case .failed(let message):
                ContentUnavailableView(
                    L10n.articleListLoadFailedTitle,
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
```

- [ ] **Step 7: `emptyDescription`/`emptyTitle` umstellen**

Ersetze (aktuell Zeilen ~435-454):

```swift
    private var emptyDescription: String {
        if isSearching {
            return L10n.articleSearchNoResultsDescription(debouncedSearchText)
        }

        switch scope {
        case .feed:
            return "Für diesen Feed sind noch keine SQLite-Artikel gespeichert."
        case .tagID:
            return "Für dieses Tag sind noch keine SQLite-Artikel gespeichert."
        case .smartFilter:
            return "Für diesen Filter sind noch keine SQLite-Artikel gespeichert."
        case .smartFolder:
            return "Für diesen intelligenten Ordner sind noch keine SQLite-Artikel gespeichert."
        }
    }

    private var emptyTitle: String {
        isSearching ? L10n.articleSearchNoResultsTitle : "Keine Artikel"
    }
```

durch:

```swift
    private var emptyDescription: String {
        if isSearching {
            return L10n.articleSearchNoResultsDescription(debouncedSearchText)
        }

        switch scope {
        case .feed:
            return L10n.articleListEmptyDescriptionFeed
        case .tagID:
            return L10n.articleListEmptyDescriptionTag
        case .smartFilter:
            return L10n.articleListEmptyDescriptionSmartFilter
        case .smartFolder:
            return L10n.articleListEmptyDescriptionSmartFolder
        }
    }

    private var emptyTitle: String {
        isSearching ? L10n.articleSearchNoResultsTitle : L10n.articleListEmptyTitle
    }
```

- [ ] **Step 8: Build ausführen, Erfolg bestätigen**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Grep-Verifikation — keine Hardcode-Literale mehr an den Zielstellen**

Run: `grep -n '"SQLite nicht verfügbar"\|"Feed noch nicht in SQLite"\|"Artikel konnten nicht geladen werden"\|"Für diesen Feed sind noch keine SQLite-Artikel gespeichert\."\|"Für dieses Tag sind noch keine SQLite-Artikel gespeichert\."\|"Für diesen Filter sind noch keine SQLite-Artikel gespeichert\."\|"Für diesen intelligenten Ordner sind noch keine SQLite-Artikel gespeichert\."\|"Keine Artikel"' Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`
Expected: keine Treffer mehr (leere Ausgabe)

- [ ] **Step 10: Committen**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift
git commit -m "$(cat <<'EOF'
Fix: Leerer-Artikelliste- und DB-Fehlerzustands-Texte in SQLiteFeedArticleListView jetzt lokalisierbar (Finding 1.7, Teil von 2.3)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `ArticleWindowView.swift` + `SQLiteReaderView.swift` — Rest von Finding 2.3

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `Feedivo/Views/Reader/ArticleWindowView.swift`
- Modify: `Feedivo/Views/Reader/SQLiteReaderView.swift`

**Interfaces:**
- Consumes: `L10n.dbUnavailableTitle`, `L10n.dbUnavailableDescription` (Task 1)
- Produces: `L10n.readerInspectorNoArticleLoaded`, `L10n.readerArticleNotFoundTitle`,
  `L10n.readerArticleNotFoundDescription` (alle `String`) — keine weiteren Konsumenten
  in diesem Plan.

- [ ] **Step 1: 3 neue Properties in `L10n.swift` ergänzen**

Direkt nach der in Task 1 Step 1 eingefügten Zeile
`static let feedNotInSQLiteDescription = String(localized: "feed.notInSQLite.description")`
einfügen:

```swift
    static let readerInspectorNoArticleLoaded = String(localized: "reader.inspector.noArticleLoaded")
    static let readerArticleNotFoundTitle = String(localized: "reader.articleNotFound.title")
    static let readerArticleNotFoundDescription = String(localized: "reader.articleNotFound.description")
```

- [ ] **Step 2: `reader.articleNotFound.*` (2 Keys) in `Localizable.xcstrings` einfügen**

Verifiziere Ankerzeile: `grep -n '"reader.bodyFont.bold.toggle"' Feedivo/Resources/Localizable.xcstrings`

Füge direkt VOR dieser Zeile ein (alphabetisch: description vor title):

```json
    "reader.articleNotFound.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Der Artikel ist nicht mehr in der lokalen Datenbank vorhanden."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "The article no longer exists in the local database."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "L'article n'existe plus dans la base de données locale."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "L'articolo non è più presente nel database locale."
          }
        }
      }
    },
    "reader.articleNotFound.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Artikel nicht gefunden"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Article Not Found"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Article introuvable"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Articolo non trovato"
          }
        }
      }
    },
```

- [ ] **Step 3: `reader.inspector.noArticleLoaded` in `Localizable.xcstrings` einfügen**

Verifiziere Ankerzeile: `grep -n '"reader.inspector.noFolder"' Feedivo/Resources/Localizable.xcstrings`

Füge direkt VOR dieser Zeile ein:

```json
    "reader.inspector.noArticleLoaded" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Noch kein Artikel geladen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No Article Loaded Yet"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aucun article chargé pour l'instant"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nessun articolo ancora caricato"
          }
        }
      }
    },
```

- [ ] **Step 4: `ArticleWindowView.swift` umstellen**

Ersetze (aktuell Zeilen ~68-72):

```swift
                ContentUnavailableView(
                    L10n.articleWindowMissingTitle,
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Die lokale Artikeldatenbank konnte nicht geöffnet werden.")
                )
```

durch:

```swift
                ContentUnavailableView(
                    L10n.articleWindowMissingTitle,
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(L10n.dbUnavailableDescription)
                )
```

- [ ] **Step 5: `SQLiteReaderView.swift` — DB-Fehlerzustand umstellen**

Ersetze (aktuell Zeilen ~244-248):

```swift
                ContentUnavailableView(
                    "SQLite nicht verfügbar",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Die lokale Artikeldatenbank konnte nicht geöffnet werden.")
                )
```

durch:

```swift
                ContentUnavailableView(
                    L10n.dbUnavailableTitle,
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(L10n.dbUnavailableDescription)
                )
```

- [ ] **Step 6: `SQLiteReaderView.swift` — Inspector-Platzhaltertext umstellen**

Ersetze (aktuell Zeile ~265):

```swift
                Text("Noch kein Artikel geladen")
                    .padding()
```

durch:

```swift
                Text(L10n.readerInspectorNoArticleLoaded)
                    .padding()
```

- [ ] **Step 7: `SQLiteReaderView.swift` — "Artikel nicht gefunden"-Zustand umstellen**

Ersetze (aktuell Zeilen ~830-834):

```swift
                            ContentUnavailableView(
                                "Artikel nicht gefunden",
                                systemImage: "doc.text.magnifyingglass",
                                description: Text(state.errorMessage ?? "Der Artikel ist nicht mehr in der lokalen Datenbank vorhanden.")
                            )
```

durch:

```swift
                            ContentUnavailableView(
                                L10n.readerArticleNotFoundTitle,
                                systemImage: "doc.text.magnifyingglass",
                                description: Text(state.errorMessage ?? L10n.readerArticleNotFoundDescription)
                            )
```

- [ ] **Step 8: Build ausführen, Erfolg bestätigen**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Grep-Verifikation — keine Hardcode-Literale mehr an den Zielstellen**

Run: `grep -n '"SQLite nicht verfügbar"\|"Die lokale Artikeldatenbank konnte nicht geöffnet werden\."\|"Noch kein Artikel geladen"\|"Artikel nicht gefunden"\|"Der Artikel ist nicht mehr in der lokalen Datenbank vorhanden\."' Feedivo/Views/Reader/ArticleWindowView.swift Feedivo/Views/Reader/SQLiteReaderView.swift`
Expected: keine Treffer mehr (leere Ausgabe)

- [ ] **Step 10: Committen**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings Feedivo/Views/Reader/ArticleWindowView.swift Feedivo/Views/Reader/SQLiteReaderView.swift
git commit -m "$(cat <<'EOF'
Fix: DB-Fehler-, Inspector-Platzhalter- und Artikel-nicht-gefunden-Texte in ArticleWindowView/SQLiteReaderView jetzt lokalisierbar (Finding 2.3)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `FeedRenameView.swift` — dedupliziert 3× hardcodierte Fehlermeldung

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `Feedivo/Views/Sidebar/FeedRenameView.swift`

**Interfaces:**
- Produces: `L10n.feedRenameDatabaseUnavailable` (`String`) — keine weiteren Konsumenten
  in diesem Plan.

- [ ] **Step 1: Neue Property in `L10n.swift` ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach Zeile
`static let feedRenameCommand = String(localized: "feed.rename.command")` (Zeile 560)
einfügen:

```swift
    static let feedRenameDatabaseUnavailable = String(localized: "feed.rename.databaseUnavailable")
```

- [ ] **Step 2: `feed.rename.databaseUnavailable` in `Localizable.xcstrings` einfügen**

Verifiziere Ankerzeile: `grep -n '"feed.rename.description"' Feedivo/Resources/Localizable.xcstrings`

Füge direkt VOR dieser Zeile ein:

```json
    "feed.rename.databaseUnavailable" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "SQLite-Datenbank ist nicht verfügbar."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "SQLite database is unavailable."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "La base de données SQLite n'est pas disponible."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Il database SQLite non è disponibile."
          }
        }
      }
    },
```

- [ ] **Step 3: Alle 3 Vorkommen in `FeedRenameView.swift` umstellen**

Ersetze in `Feedivo/Views/Sidebar/FeedRenameView.swift` alle 3 Vorkommen (Zeilen 158,
174, 192) von:

```swift
            errorMessage = "SQLite-Datenbank ist nicht verfügbar."
```

durch:

```swift
            errorMessage = L10n.feedRenameDatabaseUnavailable
```

(Da die Zeile 3× identisch vorkommt, `replace_all` beim Edit-Aufruf verwenden.)

- [ ] **Step 4: Build ausführen, Erfolg bestätigen**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Grep-Verifikation — keine Hardcode-Literale mehr an den Zielstellen**

Run: `grep -n '"SQLite-Datenbank ist nicht verfügbar\."' Feedivo/Views/Sidebar/FeedRenameView.swift`
Expected: keine Treffer mehr (leere Ausgabe)

- [ ] **Step 6: Committen**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings Feedivo/Views/Sidebar/FeedRenameView.swift
git commit -m "$(cat <<'EOF'
Fix: FeedRenameView-Fehlermeldung 'SQLite-Datenbank ist nicht verfuegbar' dedupliziert und lokalisierbar gemacht (Review-Abschnitt 3, Niedrig-Prioritaet)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review (vom Autor dieses Plans durchgeführt)

**1. Spec-Abdeckung:**
- Finding 1.7 (`emptyTitle`/`emptyDescription`): vollständig in Task 1 (Steps 2, 7)
  abgedeckt, inklusive Wiederverwendung des bereits existierenden
  `L10n.articleListEmptyTitle` statt eines unnötigen Duplikat-Keys.
- Finding 2.3 (5 Titel + 2 zitierte Beschreibungen über 3 Dateien): alle Fundstellen
  aus dem Review abgedeckt — `SQLiteFeedArticleListView.swift` in Task 1 Step 6,
  `ArticleWindowView.swift`/`SQLiteReaderView.swift` vollständig in Task 2. Die
  Dopplung von "SQLite nicht verfügbar"/"Die lokale Artikeldatenbank konnte nicht
  geöffnet werden." über 3 Stellen wird durch EINEN gemeinsamen Key
  (`dbUnavailableTitle`/`dbUnavailableDescription`) aufgelöst statt 3 unabhängiger
  Duplikate — vermeidet die gleiche Art von Divergenzrisiko, die Finding 1.8/1.9 in
  der vorherigen Gruppe bereits für SQL/HTML behoben hat.
- FeedRenameView-Punkt (Abschnitt 3, Niedrig): vollständig in Task 3 abgedeckt, alle
  3 Vorkommen auf einen gemeinsamen Key konsolidiert (vorher 3 unabhängige
  String-Literale, potenzielles Auseinanderlaufen bei künftigen Änderungen).

**2. Placeholder-Scan:** Keine "TBD"/"implement later"-Platzhalter. Alle
Übersetzungswerte sind vollständig ausformuliert (keine leeren Stubs), da dieser Plan
selbst das Problem behebt, das leere Stubs verursacht — ein neuer leerer Stub wäre ein
Plan-Fehler. Bewusst dokumentierte Abweichung von TDD (siehe Global Constraints) ist
methodisch begründet, keine Lücke.

**3. Typ-Konsistenz:** Alle neuen `L10n`-Properties sind konsequent `String` (via
`String(localized: "key")`), passend zu den Zielstellen (`String`-typisierte
Computed Properties, `ContentUnavailableView`s `String`-Overload, `Text(String)`,
`errorMessage: String?`). Keine Vermischung mit `LocalizedStringKey` an Stellen, wo das
nicht funktionieren würde (`LocalizedStringKey` konvertiert nur aus String-*Literalen*,
nicht aus Laufzeit-`String`-Werten wie `L10n.xxx`).
