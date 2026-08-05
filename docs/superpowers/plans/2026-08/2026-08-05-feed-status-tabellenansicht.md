# Feed-Status-Fenster als dichte Tabelle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `FeedRefreshDiagnosticsWindowView.swift` von einer einfachen `List(.inset)` mit
versteckten Kontextmenü-Aktionen auf eine dichte Tabelle im "Konzept A"-Dialogstil
(`RuleDialogTheme`) umstellen, mit Suchfeld, fester Sortierung nach Fehlschlägen und allen
fünf bisherigen Kontextmenü-Aktionen (Aktualisieren, Eigenschaften…, Website öffnen,
XML-Adresse kopieren, Löschen) als permanent sichtbare Icon-Buttons pro Zeile.

**Architecture:** Eine neue, reine Logik-Datei (`FeedStatusTableLogic.swift`, Filter/
Sortierung/Schweregrad — TDD, isoliert testbar) plus ein vollständiger Rewrite der
bestehenden View-Datei auf die geteilten `RuleDialogTheme`-Bausteine
(`RuleDialogButton`, `RuleDialogTextField`), die im Rest der App bereits für Dialoge/die
Verwaltung etabliert sind. Gleiches Fenster, gleiche `windowID`, gleicher Menüeintrag —
keine neue Datenquelle, keine Schema-Änderung.

**Tech Stack:** SwiftUI (macOS), Swift Testing (`@Test`/`#expect`, kein XCTest), GRDB
(unverändert, keine neue DB-Abfrage), bestehendes `RuleDialogTheme`-Bausteinsystem.

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention, siehe CLAUDE.md).
- Kein neues Datenfeld auf `FeedFailureDiagnostic` — Schweregrad wird ausschließlich aus
  dem bereits vorhandenen `consecutiveFailureCount` abgeleitet.
- Die fünf Aktionen (Aktualisieren, Eigenschaften…, Website öffnen, XML-Adresse kopieren,
  Löschen) ändern sich inhaltlich nicht — nur ihre Erreichbarkeit (Icon-Button statt
  Kontextmenü).
- `Localizable.xcstrings` NIEMALS per vollem `json.load`/`json.dump`-Roundtrip anfassen —
  neue Einträge ausschließlich als reiner Text-Block an einem stabilen Anker eingefügt
  (siehe Task 2), Verifikation über `git diff --stat` (nur Insertions, keine Deletions).
- Neue `ALTER`/Migrations-Arbeit ist hier nicht nötig — reine Präsentationsschicht-Änderung
  an bereits vorhandenen Feldern.
- Sortierung/Suchfeld sind laut Nutzerentscheidung bewusst NICHT interaktiv erweiterbar
  (keine klickbare Spaltensortierung, kein Umschalten zurück zur alten Listenansicht).

---

### Task 1: Reine Logik — Filtern, Sortieren, Schweregrad

**Files:**
- Create: `Feedivo/Views/FeedDiagnostics/FeedStatusTableLogic.swift`
- Test: `FeedivoTests/Views/FeedDiagnostics/FeedStatusTableLogicTests.swift`

**Interfaces:**
- Produces (für Task 3):
  - `FeedStatusTableLogic.filtered(_ diagnostics: [FeedFailureDiagnostic], matching searchText: String) -> [FeedFailureDiagnostic]`
  - `FeedStatusTableLogic.sortedByFailureCountDescending(_ diagnostics: [FeedFailureDiagnostic]) -> [FeedFailureDiagnostic]`
  - `enum FeedFailureSeverity: Equatable { case new, warning, critical }` mit
    `FeedFailureSeverity.forConsecutiveFailureCount(_ count: Int) -> FeedFailureSeverity`
- Consumes: `FeedFailureDiagnostic` (bestehender Typ, `Feedivo/Snapshots/FeedFailureDiagnostic.swift`)
  mit Feldern `feedID: String`, `feedTitle: String`, `feedURL: String`,
  `feedWebsiteURL: String?`, `feedFaviconURL: String?`, `lastAttemptAt: Date`,
  `errorMessage: String`, `httpStatusCode: Int?`, `consecutiveFailureCount: Int`.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

Erstelle `FeedivoTests/Views/FeedDiagnostics/FeedStatusTableLogicTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct FeedStatusTableLogicTests {
    private func diagnostic(
        feedID: String = "feed-1",
        feedTitle: String,
        feedURL: String = "https://example.com/feed",
        consecutiveFailureCount: Int = 1
    ) -> FeedFailureDiagnostic {
        FeedFailureDiagnostic(
            feedID: feedID,
            feedTitle: feedTitle,
            feedURL: feedURL,
            feedWebsiteURL: nil,
            feedFaviconURL: nil,
            lastAttemptAt: Date(timeIntervalSince1970: 1_000),
            errorMessage: "Fehler",
            httpStatusCode: nil,
            consecutiveFailureCount: consecutiveFailureCount
        )
    }

    @Test func filteredLiefertAlleBeiLeeremSuchtext() {
        let diagnostics = [diagnostic(feedTitle: "GoogleWatchBlog"), diagnostic(feedTitle: "Android Police")]

        let result = FeedStatusTableLogic.filtered(diagnostics, matching: "")

        #expect(result.count == 2)
    }

    @Test func filteredFindetTitelTreffer() {
        let diagnostics = [diagnostic(feedTitle: "GoogleWatchBlog"), diagnostic(feedTitle: "Android Police")]

        let result = FeedStatusTableLogic.filtered(diagnostics, matching: "google")

        #expect(result.map(\.feedTitle) == ["GoogleWatchBlog"])
    }

    @Test func filteredFindetURLTreffer() {
        let diagnostics = [
            diagnostic(feedTitle: "GoogleWatchBlog", feedURL: "https://googlewatchblog.de/feed"),
            diagnostic(feedTitle: "Android Police", feedURL: "https://androidpolice.com/feed")
        ]

        let result = FeedStatusTableLogic.filtered(diagnostics, matching: "androidpolice")

        #expect(result.map(\.feedTitle) == ["Android Police"])
    }

    @Test func filteredIstUnabhaengigVonGrossKleinschreibung() {
        let diagnostics = [diagnostic(feedTitle: "GoogleWatchBlog")]

        let result = FeedStatusTableLogic.filtered(diagnostics, matching: "GOOGLEWATCHBLOG")

        #expect(result.count == 1)
    }

    @Test func filteredLiefertLeeresArrayOhneTreffer() {
        let diagnostics = [diagnostic(feedTitle: "GoogleWatchBlog")]

        let result = FeedStatusTableLogic.filtered(diagnostics, matching: "macrumors")

        #expect(result.isEmpty)
    }

    @Test func sortedByFailureCountDescendingSortiertAbsteigend() {
        let diagnostics = [
            diagnostic(feedID: "a", feedTitle: "A", consecutiveFailureCount: 2),
            diagnostic(feedID: "b", feedTitle: "B", consecutiveFailureCount: 9),
            diagnostic(feedID: "c", feedTitle: "C", consecutiveFailureCount: 1)
        ]

        let result = FeedStatusTableLogic.sortedByFailureCountDescending(diagnostics)

        #expect(result.map(\.feedID) == ["b", "a", "c"])
    }

    @Test func severityIstNewBeiEinemFehlschlag() {
        #expect(FeedFailureSeverity.forConsecutiveFailureCount(1) == .new)
    }

    @Test func severityIstWarningZwischenZweiUndVier() {
        #expect(FeedFailureSeverity.forConsecutiveFailureCount(2) == .warning)
        #expect(FeedFailureSeverity.forConsecutiveFailureCount(4) == .warning)
    }

    @Test func severityIstCriticalAbFuenf() {
        #expect(FeedFailureSeverity.forConsecutiveFailureCount(5) == .critical)
        #expect(FeedFailureSeverity.forConsecutiveFailureCount(9) == .critical)
    }
}
```

- [ ] **Step 2: Testlauf verifizieren, dass er fehlschlägt**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedStatusTableLogicTests -parallel-testing-enabled NO`
Expected: FAIL — `FeedStatusTableLogic`/`FeedFailureSeverity` existieren noch nicht
("Cannot find type/'FeedStatusTableLogic' in scope").

- [ ] **Step 3: Minimale Implementierung schreiben**

Erstelle `Feedivo/Views/FeedDiagnostics/FeedStatusTableLogic.swift`:

```swift
import Foundation

/// Reine, isoliert testbare Logik für die Feed-Status-Tabelle — Filterung nach
/// Suchtext, feste Sortierung nach Fehlschlägen und Schweregrad-Ableitung. Kein
/// neues Datenfeld: alles wird aus dem bereits vorhandenen `FeedFailureDiagnostic`
/// abgeleitet (analog `FeedManagementSettingsState.filteredFeeds`). Siehe
/// docs/superpowers/specs/2026-08/2026-08-05-feed-status-tabellenansicht-design.md.
enum FeedStatusTableLogic {
    static func filtered(_ diagnostics: [FeedFailureDiagnostic], matching searchText: String) -> [FeedFailureDiagnostic] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return diagnostics
        }
        return diagnostics.filter {
            $0.feedTitle.localizedCaseInsensitiveContains(trimmed)
                || $0.feedURL.localizedCaseInsensitiveContains(trimmed)
        }
    }

    static func sortedByFailureCountDescending(_ diagnostics: [FeedFailureDiagnostic]) -> [FeedFailureDiagnostic] {
        diagnostics.sorted { $0.consecutiveFailureCount > $1.consecutiveFailureCount }
    }
}

/// Rein visuelle Schweregrad-Einstufung für die Fehlschläge-Badge in der Zeile —
/// kein gespeicherter Zustand, nur eine Ableitung aus `consecutiveFailureCount`.
enum FeedFailureSeverity: Equatable {
    case new
    case warning
    case critical

    static func forConsecutiveFailureCount(_ count: Int) -> FeedFailureSeverity {
        switch count {
        case ..<2:
            .new
        case 2..<5:
            .warning
        default:
            .critical
        }
    }
}
```

- [ ] **Step 4: Testlauf verifizieren, dass er besteht**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedStatusTableLogicTests -parallel-testing-enabled NO`
Expected: PASS (9/9 Tests grün).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/FeedDiagnostics/FeedStatusTableLogic.swift FeedivoTests/Views/FeedDiagnostics/FeedStatusTableLogicTests.swift
git commit -m "feat: reine Filter-/Sortier-/Schweregrad-Logik für Feed-Status-Tabelle"
```

---

### Task 2: Neue L10n-Keys ergänzen

**Files:**
- Modify: `Feedivo/Resources/L10n.swift:675-676` (Typ-Anpassung), `:677-683` (neue Konstanten danach)
- Modify: `Feedivo/Resources/Localizable.xcstrings:3` (neue Katalogeinträge)

**Interfaces:**
- Produces (für Task 3): `L10n.feedRefreshDiagnosticsReloadListButton`/
  `feedRefreshDiagnosticsRetryAllButton` (jetzt `LocalizedStringKey`, nicht mehr `String`),
  `L10n.feedRefreshDiagnosticsSearchPlaceholder` (`LocalizedStringKey`),
  `L10n.feedRefreshDiagnosticsColumnFeed`/`ColumnError`/`ColumnLastAttempt`/
  `ColumnFailureCount`/`ColumnActions` (`String`),
  `L10n.feedRefreshDiagnosticsSeverityNew` (`String`),
  `L10n.feedRefreshDiagnosticsFooterFeedCount(_ count: Int) -> String`,
  `L10n.feedRefreshDiagnosticsFooterLastChecked(_ relative: String) -> String`,
  `L10n.feedRefreshDiagnosticsSearchNoResultsTitle` (`String`),
  `L10n.feedRefreshDiagnosticsSearchNoResultsDescription(searchText: String) -> String`.

**Hinweis:** `feedRefreshDiagnosticsReloadListButton`/`RetryAllButton` sind aktuell als
`String(localized:)` deklariert und werden nur in `FeedRefreshDiagnosticsWindowView.swift`
verwendet (per `grep` bestätigt) — sie werden hier auf `LocalizedStringKey(...)`
umgestellt, weil `RuleDialogButton.titleKey` (siehe `Feedivo/Views/Rules/RuleDialogTheme.swift:280`)
diesen Typ verlangt (exakt das bereits etablierte Muster, siehe
`L10n.settingsFeedsSelectVisible` in `L10n.swift:366`).

- [ ] **Step 1: Bestehende Button-Label-Konstanten auf `LocalizedStringKey` umstellen**

In `Feedivo/Resources/L10n.swift`, ersetze:

```swift
    static let feedRefreshDiagnosticsRetryAllButton = String(localized: "feed.refreshDiagnostics.retryAll.button")
    static let feedRefreshDiagnosticsReloadListButton = String(localized: "feed.refreshDiagnostics.reloadList.button")
```

durch:

```swift
    static let feedRefreshDiagnosticsRetryAllButton = LocalizedStringKey("feed.refreshDiagnostics.retryAll.button")
    static let feedRefreshDiagnosticsReloadListButton = LocalizedStringKey("feed.refreshDiagnostics.reloadList.button")
```

- [ ] **Step 2: Neue Konstanten ergänzen**

Im selben File, direkt nach dem Ende von `feedRefreshDiagnosticsConsecutiveFailures(_:)`
(vor `feedErrorBadgeTooltip`), ersetze:

```swift
    static func feedRefreshDiagnosticsConsecutiveFailures(_ count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "feed.refreshDiagnostics.consecutiveFailures"),
            count
        )
    }
    static let feedErrorBadgeTooltip = String(localized: "feed.error.badge.tooltip")
```

durch:

```swift
    static func feedRefreshDiagnosticsConsecutiveFailures(_ count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "feed.refreshDiagnostics.consecutiveFailures"),
            count
        )
    }
    static let feedRefreshDiagnosticsSearchPlaceholder = LocalizedStringKey("feed.refreshDiagnostics.search.placeholder")
    static let feedRefreshDiagnosticsColumnFeed = String(localized: "feed.refreshDiagnostics.column.feed")
    static let feedRefreshDiagnosticsColumnError = String(localized: "feed.refreshDiagnostics.column.error")
    static let feedRefreshDiagnosticsColumnLastAttempt = String(localized: "feed.refreshDiagnostics.column.lastAttempt")
    static let feedRefreshDiagnosticsColumnFailureCount = String(localized: "feed.refreshDiagnostics.column.failureCount")
    static let feedRefreshDiagnosticsColumnActions = String(localized: "feed.refreshDiagnostics.column.actions")
    static let feedRefreshDiagnosticsSeverityNew = String(localized: "feed.refreshDiagnostics.severity.new")
    static func feedRefreshDiagnosticsFooterFeedCount(_ count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "feed.refreshDiagnostics.footer.feedCount"),
            count
        )
    }
    static func feedRefreshDiagnosticsFooterLastChecked(_ relative: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "feed.refreshDiagnostics.footer.lastChecked"),
            relative
        )
    }
    static let feedRefreshDiagnosticsSearchNoResultsTitle = String(localized: "feed.refreshDiagnostics.search.noResults.title")
    static func feedRefreshDiagnosticsSearchNoResultsDescription(searchText: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "feed.refreshDiagnostics.search.noResults.description"),
            searchText
        )
    }
    static let feedErrorBadgeTooltip = String(localized: "feed.error.badge.tooltip")
```

- [ ] **Step 3: Katalogeinträge in `Localizable.xcstrings` ergänzen**

**Niemals die ganze Datei per `json.load`/`json.dump` roundtripen** (zerstört Xcodes
Formatierung/Sortierung, siehe CLAUDE.md-Gotcha) — stattdessen reine Text-Segment-
Einfügung direkt nach der Zeile `  "strings" : {` (Zeile 3), vor dem bestehenden ersten
Eintrag `"" : {`. In `Feedivo/Resources/Localizable.xcstrings`, ersetze:

```
  "strings" : {
    "" : {

    },
```

durch (11 neue Einträge, danach folgt unverändert der bestehende `"" : {`-Eintrag):

```
  "strings" : {
    "feed.refreshDiagnostics.search.placeholder" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feeds durchsuchen…"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Search feeds…"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Rechercher des flux…"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Cerca feed…"
          }
        }
      }
    },
    "feed.refreshDiagnostics.column.feed" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Flux"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed"
          }
        }
      }
    },
    "feed.refreshDiagnostics.column.error" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Fehler"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Error"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Erreur"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Errore"
          }
        }
      }
    },
    "feed.refreshDiagnostics.column.lastAttempt" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Zuletzt"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Last attempt"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Dernier essai"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ultimo tentativo"
          }
        }
      }
    },
    "feed.refreshDiagnostics.column.failureCount" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Fehlschläge"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Failures"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Échecs"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Errori"
          }
        }
      }
    },
    "feed.refreshDiagnostics.column.actions" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aktionen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Actions"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Actions"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Azioni"
          }
        }
      }
    },
    "feed.refreshDiagnostics.severity.new" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Erster Fehlschlag"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "First failure"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Premier échec"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Primo errore"
          }
        }
      }
    },
    "feed.refreshDiagnostics.footer.feedCount" : {
      "localizations" : {
        "de" : {
          "variations" : {
            "plural" : {
              "one" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld Feed mit Fehler"
                }
              },
              "other" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld Feeds mit Fehlern"
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
                  "value" : "%lld feed failed"
                }
              },
              "other" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld feeds failed"
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
                  "value" : "%lld flux en échec"
                }
              },
              "other" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld flux en échec"
                }
              }
            }
          }
        },
        "it" : {
          "variations" : {
            "plural" : {
              "one" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld feed non riuscito"
                }
              },
              "other" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld feed non riusciti"
                }
              }
            }
          }
        }
      }
    },
    "feed.refreshDiagnostics.footer.lastChecked" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "zuletzt geprüft %@"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "last checked %@"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "dernière vérification %@"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "ultimo controllo %@"
          }
        }
      }
    },
    "feed.refreshDiagnostics.search.noResults.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Keine Treffer"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No matches"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aucun résultat"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nessun risultato"
          }
        }
      }
    },
    "feed.refreshDiagnostics.search.noResults.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Kein Feed passt zu „%@“."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No feed matches “%@”."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aucun flux ne correspond à « %@ »."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nessun feed corrisponde a «%@»."
          }
        }
      }
    },
    "" : {

    },
```

- [ ] **Step 4: Einfügung verifizieren**

Run:
```bash
grep -c '"feed.refreshDiagnostics.search.placeholder"\|"feed.refreshDiagnostics.column.feed"\|"feed.refreshDiagnostics.column.error"\|"feed.refreshDiagnostics.column.lastAttempt"\|"feed.refreshDiagnostics.column.failureCount"\|"feed.refreshDiagnostics.column.actions"\|"feed.refreshDiagnostics.severity.new"\|"feed.refreshDiagnostics.footer.feedCount"\|"feed.refreshDiagnostics.footer.lastChecked"\|"feed.refreshDiagnostics.search.noResults.title"\|"feed.refreshDiagnostics.search.noResults.description"' Feedivo/Resources/Localizable.xcstrings
```
Expected: `11` (jeder Key genau einmal).

Run: `git diff --stat -- Feedivo/Resources/Localizable.xcstrings`
Expected: nur Insertions, keine oder kaum Deletions (reine Anker-Einfügung, kein
Roundtrip-Reformat der Gesamtdatei).

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED (die neuen `L10n`-Konstanten werden noch nirgends verwendet,
müssen aber bereits fehlerfrei kompilieren).

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat: L10n-Keys für Feed-Status-Tabelle (Spalten, Suche, Fußzeile)"
```

---

### Task 3: View auf dichte Tabelle umstellen

**Files:**
- Modify (vollständiger Rewrite): `Feedivo/Views/FeedDiagnostics/FeedRefreshDiagnosticsWindowView.swift`

**Interfaces:**
- Consumes: `FeedStatusTableLogic.filtered`/`sortedByFailureCountDescending`,
  `FeedFailureSeverity.forConsecutiveFailureCount` (Task 1); alle in Task 2 ergänzten
  `L10n`-Konstanten; `RuleDialogTheme`, `RuleDialogButton`, `RuleDialogTextField`
  (`Feedivo/Views/Rules/RuleDialogTheme.swift`); `Date.feedivoRelativeDisplay`
  (`Feedivo/Extensions/Date+RelativeDisplay.swift`); bestehend unverändert:
  `FeedViewModel`, `FeedPropertiesView`, `FeedPropertiesFormatter.linkURL`,
  `FeedLogStore.failureDiagnosticsAsync()`, `CachedRemoteImageView`.
- Produces: `FeedRefreshDiagnosticsWindowView` (öffentliche View, `windowID` unverändert
  `"feed-refresh-diagnostics-window"` — Einstiegspunkt in `FeedivoApp.swift:270`/
  `FeedCommands.swift:49` bleibt unangetastet, keine Änderung dort nötig).

**Hinweis:** Der `.contextMenu`-Modifier und die private `FeedFailureDiagnosticRow`
entfallen vollständig — per `grep` bestätigt, dass `FeedFailureDiagnosticRow` nirgends
außerhalb dieser Datei referenziert wird.

- [ ] **Step 1: Komplette Datei ersetzen**

Ersetze den gesamten Inhalt von `Feedivo/Views/FeedDiagnostics/FeedRefreshDiagnosticsWindowView.swift`
durch:

```swift
import AppKit
import SwiftUI

/// Eigenständiges Fenster: listet alle Feeds, deren letzter Aktualisierungs-
/// versuch fehlgeschlagen ist, mit echtem Fehlergrund aus `feed_logs` (statt
/// des flüchtigen `FeedViewModel.refreshItems`-Panels unten rechts in
/// `ContentView.swift`, das nur den zuletzt laufenden "Alle aktualisieren"-
/// Vorgang abdeckt). Optik/Aktionen folgen dem Konzept-A-Dialogsystem
/// (`RuleDialogTheme`) — alle fünf Aktionen, die vorher nur im Rechtsklick-
/// Kontextmenü erreichbar waren, sitzen jetzt fest sichtbar in der Zeile. Siehe
/// docs/superpowers/specs/2026-08/2026-08-05-feed-refresh-diagnose-fenster-design.md
/// und docs/superpowers/specs/2026-08/2026-08-05-feed-status-tabellenansicht-design.md.
struct FeedRefreshDiagnosticsWindowView: View {
    static let windowID = "feed-refresh-diagnostics-window"

    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.colorScheme) private var colorScheme

    @State private var diagnostics: [FeedFailureDiagnostic] = []
    @State private var feedViewModel = FeedViewModel()
    @State private var feedShowingProperties: FeedFailureDiagnostic?
    @State private var feedPendingDeletion: FeedFailureDiagnostic?
    @State private var isBusy = false
    @State private var searchText = ""
    @State private var lastReloadedAt: Date?

    private var theme: RuleDialogTheme {
        RuleDialogTheme(colorScheme: colorScheme)
    }

    private var visibleDiagnostics: [FeedFailureDiagnostic] {
        FeedStatusTableLogic.filtered(diagnostics, matching: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let errorMessage = feedViewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.destructiveText)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 8)
            }

            if diagnostics.isEmpty {
                emptyState
            } else {
                Rectangle()
                    .fill(theme.border)
                    .frame(height: 1)
                    .padding(.horizontal, 26)

                searchField

                if visibleDiagnostics.isEmpty {
                    noSearchResultsState
                } else {
                    table
                }

                footer
            }
        }
        .background(theme.bg)
        .frame(minWidth: 700, minHeight: 420)
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.feedRefreshDiagnosticsWindowTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.text)

                Text(L10n.feedRefreshDiagnosticsDescription)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.text2)
            }

            Spacer()

            RuleDialogButton(
                titleKey: L10n.feedRefreshDiagnosticsReloadListButton,
                style: .secondary,
                theme: theme,
                systemImage: "arrow.clockwise"
            ) {
                Task {
                    await reload()
                }
            }
            .disabled(isBusy)

            if !diagnostics.isEmpty {
                RuleDialogButton(
                    titleKey: L10n.feedRefreshDiagnosticsRetryAllButton,
                    style: .primary,
                    theme: theme
                ) {
                    Task {
                        await retryAll()
                    }
                }
                .disabled(isBusy)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Suche

    private var searchField: some View {
        RuleDialogTextField(
            placeholder: L10n.feedRefreshDiagnosticsSearchPlaceholder,
            text: $searchText,
            theme: theme
        )
        .frame(width: 240)
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
    }

    // MARK: - Tabelle

    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            tableHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleDiagnostics.enumerated()), id: \.element.id) { index, diagnostic in
                        FeedStatusTableRow(
                            diagnostic: diagnostic,
                            theme: theme,
                            isRetryDisabled: isBusy,
                            onRetry: {
                                Task {
                                    await retry(diagnostic)
                                }
                            },
                            onShowProperties: {
                                feedShowingProperties = diagnostic
                            },
                            onOpenWebsite: openWebsiteAction(for: diagnostic),
                            onCopyXMLAddress: {
                                copyXMLAddress(diagnostic)
                            },
                            onDelete: {
                                feedPendingDeletion = diagnostic
                            }
                        )

                        if index < visibleDiagnostics.count - 1 {
                            Rectangle()
                                .fill(theme.border)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .background(theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        .padding(.horizontal, 26)
    }

    private var tableHeader: some View {
        HStack(spacing: 14) {
            Text(L10n.feedRefreshDiagnosticsColumnFeed)
                .frame(width: 170, alignment: .leading)

            Text(L10n.feedRefreshDiagnosticsColumnError)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(L10n.feedRefreshDiagnosticsColumnLastAttempt)
                .frame(width: 90, alignment: .leading)

            HStack(spacing: 3) {
                Text(L10n.feedRefreshDiagnosticsColumnFailureCount)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(theme.accent)
            .frame(width: 118, alignment: .leading)

            Text(L10n.feedRefreshDiagnosticsColumnActions)
                .frame(width: 150, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .bold))
        .textCase(.uppercase)
        .foregroundStyle(theme.text2)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(theme.card)
    }

    // MARK: - Leerzustände

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(RuleDialogTheme.switchOn)

            Text(L10n.feedRefreshDiagnosticsEmptyTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.text)

            Text(L10n.feedRefreshDiagnosticsEmptyDescription)
                .font(.system(size: 11))
                .foregroundStyle(theme.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private var noSearchResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(theme.text2)

            Text(L10n.feedRefreshDiagnosticsSearchNoResultsTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.text)

            Text(L10n.feedRefreshDiagnosticsSearchNoResultsDescription(searchText: searchText))
                .font(.system(size: 11))
                .foregroundStyle(theme.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 26)
    }

    // MARK: - Fußzeile

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: 0xFF9F0A))
                .frame(width: 6, height: 6)

            Text(footerStatusText)

            Spacer()
        }
        .font(.system(size: 11.5))
        .foregroundStyle(theme.text2)
        .padding(.horizontal, 26)
        .padding(.vertical, 11)
    }

    private var footerStatusText: String {
        let feedCountText = L10n.feedRefreshDiagnosticsFooterFeedCount(diagnostics.count)
        guard let lastReloadedAt else {
            return feedCountText
        }
        let lastCheckedText = L10n.feedRefreshDiagnosticsFooterLastChecked(lastReloadedAt.feedivoRelativeDisplay)
        return "\(feedCountText) · \(lastCheckedText)"
    }

    // MARK: - Aktionen

    private func openWebsiteAction(for diagnostic: FeedFailureDiagnostic) -> (() -> Void)? {
        guard let url = FeedPropertiesFormatter.linkURL(diagnostic.feedWebsiteURL ?? diagnostic.feedURL) else {
            return nil
        }
        return {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyXMLAddress(_ diagnostic: FeedFailureDiagnostic) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostic.feedURL, forType: .string)
    }

    private func reload() async {
        guard let feedivoDatabase else {
            diagnostics = []
            lastReloadedAt = Date()
            return
        }
        let loaded = (try? await FeedLogStore(database: feedivoDatabase).failureDiagnosticsAsync()) ?? []
        diagnostics = FeedStatusTableLogic.sortedByFailureCountDescending(loaded)
        lastReloadedAt = Date()
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
        // Dialog-Dismiss ist unabhängig vom Ausgang — schließt nur das
        // confirmationDialog, behauptet keinen Erfolg.
        feedPendingDeletion = nil
        guard let feedivoDatabase else {
            return
        }
        feedViewModel.deleteFeed(feedID: diagnostic.feedID, sqliteDatabase: feedivoDatabase)
        // `deleteFeed` wirft nicht — ein Fehlschlag landet nur in
        // `feedViewModel.errorMessage` (siehe Fehlerbanner oben). Die Zeile darf
        // deshalb nur bei tatsächlichem Erfolg entfernt werden, sonst würde die
        // UI einen gelöschten Feed vortäuschen, der in Wahrheit noch existiert.
        if feedViewModel.errorMessage == nil {
            diagnostics.removeAll { $0.feedID == diagnostic.feedID }
        }
    }
}

// MARK: - Zeile

private struct FeedStatusTableRow: View {
    let diagnostic: FeedFailureDiagnostic
    let theme: RuleDialogTheme
    let isRetryDisabled: Bool
    let onRetry: () -> Void
    let onShowProperties: () -> Void
    let onOpenWebsite: (() -> Void)?
    let onCopyXMLAddress: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            feedColumn
            errorColumn

            Text(diagnostic.lastAttemptAt.feedivoRelativeDisplay)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.text2)
                .frame(width: 90, alignment: .leading)

            FeedFailureSeverityBadge(count: diagnostic.consecutiveFailureCount, theme: theme)
                .frame(width: 118, alignment: .leading)

            actionsColumn
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var feedColumn: some View {
        HStack(spacing: 9) {
            faviconView

            VStack(alignment: .leading, spacing: 1) {
                Text(diagnostic.feedTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Text(diagnostic.feedURL)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(width: 170, alignment: .leading)
    }

    private var errorColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let httpStatusCode = diagnostic.httpStatusCode {
                Text("HTTP \(httpStatusCode)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.text2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(theme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(theme.border, lineWidth: 1)
                    )
            }

            Text(diagnostic.errorMessage)
                .font(.system(size: 12))
                .foregroundStyle(theme.destructiveText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionsColumn: some View {
        HStack(spacing: 2) {
            FeedStatusRowActionButton(
                systemImage: "arrow.clockwise",
                accessibilityLabel: L10n.feedRefreshCommand,
                theme: theme,
                action: onRetry
            )
            .disabled(isRetryDisabled)

            FeedStatusRowActionButton(
                systemImage: "info.circle",
                accessibilityLabel: L10n.feedPropertiesCommand,
                theme: theme,
                action: onShowProperties
            )

            if let onOpenWebsite {
                FeedStatusRowActionButton(
                    systemImage: "safari",
                    accessibilityLabel: L10n.feedRefreshDiagnosticsOpenWebsiteButton,
                    theme: theme,
                    action: onOpenWebsite
                )
            }

            FeedStatusRowActionButton(
                systemImage: "doc.on.doc",
                accessibilityLabel: L10n.feedPropertiesCopyXMLAddress,
                theme: theme,
                action: onCopyXMLAddress
            )

            FeedStatusRowActionButton(
                systemImage: "trash",
                accessibilityLabel: L10n.feedDeleteCommand,
                theme: theme,
                isDestructive: true,
                action: onDelete
            )
        }
        .frame(width: 150, alignment: .trailing)
    }

    @ViewBuilder
    private var faviconView: some View {
        if let faviconURLString = diagnostic.feedFaviconURL, let url = URL(string: faviconURLString) {
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 5))
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
            .font(.system(size: 13))
            .foregroundStyle(theme.destructiveText)
            .frame(width: 20, height: 20)
    }
}

// MARK: - Schweregrad-Badge

private struct FeedFailureSeverityBadge: View {
    let count: Int
    let theme: RuleDialogTheme

    private var severity: FeedFailureSeverity {
        FeedFailureSeverity.forConsecutiveFailureCount(count)
    }

    private var label: String {
        switch severity {
        case .new:
            L10n.feedRefreshDiagnosticsSeverityNew
        case .warning, .critical:
            L10n.feedRefreshDiagnosticsConsecutiveFailures(count)
        }
    }

    private var foreground: Color {
        switch severity {
        case .new:
            theme.text2
        case .warning:
            Color(hex: 0xC76A00)
        case .critical:
            theme.destructiveText
        }
    }

    private var background: Color {
        switch severity {
        case .new:
            theme.card
        case .warning:
            Color(hex: 0xFF9F0A).opacity(0.14)
        case .critical:
            theme.destructiveTint
        }
    }

    private var border: Color {
        switch severity {
        case .new:
            theme.border
        case .warning:
            Color(hex: 0xFF9F0A).opacity(0.38)
        case .critical:
            theme.destructiveBorder
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(background)
            )
            .overlay(
                Capsule().stroke(border, lineWidth: 1)
            )
    }
}

// MARK: - Icon-Aktions-Button

private struct FeedStatusRowActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let theme: RuleDialogTheme
    var isDestructive = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(background)
                )
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var foreground: Color {
        guard isHovering else {
            return theme.text2
        }
        return isDestructive ? theme.destructiveText : theme.text
    }

    private var background: Color {
        guard isHovering else {
            return .clear
        }
        return isDestructive ? theme.destructiveTint : theme.card
    }
}
```

- [ ] **Step 2: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED. Bei Fehlern zu unbekannten Symbolen zuerst prüfen, ob Task 1
(`FeedStatusTableLogic.swift`) und Task 2 (neue `L10n`-Konstanten) tatsächlich bereits
committed/vorhanden sind.

- [ ] **Step 3: Commit**

```bash
git add Feedivo/Views/FeedDiagnostics/FeedRefreshDiagnosticsWindowView.swift
git commit -m "feat: Feed-Status-Fenster als dichte Tabelle mit sichtbaren Aktionen"
```

---

### Task 4: Regressionslauf und Release-Build

**Files:** keine Änderungen — reine Verifikation.

**Interfaces:** keine (Abschluss-Task).

- [ ] **Step 1: Gezielten Testlauf ausführen**

Run:
```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/FeedStatusTableLogicTests \
  -parallel-testing-enabled NO
```
Expected: 9/9 Tests grün.

- [ ] **Step 2: Debug-Build der gesamten App verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Release-Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Release`
Expected: BUILD SUCCEEDED (deckt u. a. auf, falls `Localizable.xcstrings` in Task 2
versehentlich fehlerhaft formatiert wurde — der String-Catalog-Compile-Schritt läuft in
beiden Konfigurationen).

- [ ] **Step 4: Manuelle Live-Verifikationscheckliste dokumentieren**

Kein computer-use für native macOS-Apps verfügbar — folgende Punkte müssen vom Nutzer
selbst geprüft werden (in `CLAUDE.md` unter „Aktuell in Arbeit" als ausstehend
vermerken, siehe Step 5):

1. Feed-Menü → „Feed-Status…" öffnet das Fenster im neuen Tabellen-Layout.
2. Ist kein Feed fehlgeschlagen: grüner Erfolgs-Leerzustand wie bisher.
3. Bei fehlgeschlagenen Feeds: Spalten Feed/Fehler/Zuletzt/Fehlschläge/Aktionen befüllt,
   Fehlschläge-Badge-Farbe passt zur jeweiligen Anzahl (1 neutral, 2–4 amber, ≥5 rot).
4. Tippen ins Suchfeld filtert sichtbar nach Titel und nach URL; bei keinem Treffer
   erscheint „Keine Treffer" statt einer leeren Fläche.
5. Alle fünf Icon-Buttons pro Zeile funktionieren identisch zum bisherigen
   Rechtsklick-Menü: Aktualisieren, Eigenschaften (öffnet Sheet), Website öffnen (nur
   sichtbar wenn URL vorhanden), XML-Adresse kopieren, Löschen (fragt nach Bestätigung).
6. Fußzeile zeigt korrekte Anzahl + „zuletzt geprüft vor …" nach „Neu laden" bzw. nach
   jeder Aktion.
7. Hell-/Dunkelmodus: Farben stimmen in beiden Darstellungen (Fenster einmal bei
   Hell- und einmal bei Dunkelmodus öffnen).

- [ ] **Step 5: CLAUDE.md aktualisieren**

Ergänze in `CLAUDE.md` unter „Aktuell in Arbeit" einen neuen Eintrag (Datum des
Ausführungstags), der zusammenfasst: Tabellen-Redesign umgesetzt (4 Tasks), automatisierte
Tests + Debug-/Release-Build grün, manuelle Live-Verifikation laut obiger Checkliste noch
ausstehend. Committe die Doku-Änderung zusammen mit einem eventuellen letzten Cleanup.

```bash
git add CLAUDE.md
git commit -m "docs: Feed-Status-Tabellen-Redesign in CLAUDE.md vermerkt"
```
