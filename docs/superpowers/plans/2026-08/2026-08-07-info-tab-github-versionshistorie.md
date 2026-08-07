# Info-Tab: GitHub-Link + Versionshistorie — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Im Settings-Tab "Info" (`AboutSettingsView.swift`) einen Link zum GitHub-
Repository sowie einen Button "Versionshistorie anzeigen" ergänzen, der ein neues
Fenster mit den letzten 15 `CHANGELOG.md`-Versionseinträgen öffnet.

**Architecture:** `CHANGELOG.md` bleibt alleinige Quelle der Wahrheit am Repo-Root, wird
aber ab sofort bei jedem `scripts/bump_version.sh`-Lauf zusätzlich nach
`Feedivo/Resources/CHANGELOG.md` kopiert (file-system-synchronisierter Ordner, wird
automatisch Bundle-Resource). Ein neuer, reiner `ChangelogParser` liest die gebündelte
Datei zur Laufzeit und liefert `[ChangelogEntry]`. Ein neues `VersionHistoryWindowView`
(eigene `Window(id:)`-Scene, analog `CleanupHistoryWindowView`) zeigt die letzten 15
Einträge; `AboutSettingsView` bekommt einen `Link` zum Repo und einen Button, der dieses
Fenster öffnet.

**Tech Stack:** SwiftUI (macOS), Swift Testing (`@Test`/`#expect`, kein XCTest), reine
Foundation-String-Verarbeitung (kein GRDB, keine Datenbank nötig).

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention, siehe CLAUDE.md).
- `Localizable.xcstrings` NIEMALS per vollem `json.load`/`json.dump`-Roundtrip anfassen —
  neue Einträge ausschließlich als reiner Text-Block an einem stabilen Anker (`"strings"
  : {`) eingefügt, Verifikation über `git diff --stat` (nur Insertions, keine Deletions)
  und `grep -c`.
- `CHANGELOG.md` bleibt die alleinige, von Menschen/vom Release-Skript bearbeitete
  Quelle — `Feedivo/Resources/CHANGELOG.md` ist eine reine, automatisch synchronisierte
  Kopie, NIE von Hand bearbeiten.
- Kein neuer Datenbankzugriff (`\.feedivoDatabase`) — die Versionshistorie ist rein
  dateibasiert.
- Repository-URL ist `https://github.com/martinfelder/feedivo-mac` (privates Repo, laut
  Design-Spec bewusst so belassen — Link funktioniert nur für den eingeloggten Owner).
- Anzeige-Obergrenze: die ersten 15 geparsten Versionseinträge (Datei ist bereits
  neueste-zuerst sortiert, kein Re-Sort im Code nötig); darüber hinaus ein Link zur
  vollständigen `CHANGELOG.md` auf GitHub.
- Kein UI-Test (kein computer-use für native macOS-Apps verfügbar) — jede View-Task
  endet mit `xcodebuild build`-Verifikation, nicht mit einem automatisierten UI-Test.

---

### Task 1: `ChangelogParser` — reine Parsing-Logik

**Files:**
- Create: `Feedivo/Services/ChangelogParser.swift`
- Test: `FeedivoTests/Services/ChangelogParserTests.swift`

**Interfaces:**
- Produces (für Task 4):
  - `struct ChangelogEntry: Equatable { let version: String; let date: String; let bullets: [String] }`
  - `ChangelogParser.parse(_ markdown: String) -> [ChangelogEntry]`

- [ ] **Step 1: Fehlschlagenden Test schreiben**

Erstelle `FeedivoTests/Services/ChangelogParserTests.swift`:

```swift
import Testing
@testable import Feedivo

struct ChangelogParserTests {

    @Test func parstMehrereVersionsBloeckeMitVersionUndDatum() {
        let markdown = """
        # Changelog

        Einleitungstext, der ignoriert werden soll.

        <!-- versions -->

        ## [1.0 (28)] - 2026-08-07

        - Neu: Erster Punkt
        - Fehlerbehebung: Zweiter Punkt

        ## [1.0 (27)] - 2026-08-05

        - Verbesserung: Dritter Punkt
        """

        let entries = ChangelogParser.parse(markdown)

        #expect(entries.count == 2)
        #expect(entries[0].version == "1.0 (28)")
        #expect(entries[0].date == "2026-08-07")
        #expect(entries[0].bullets == ["Neu: Erster Punkt", "Fehlerbehebung: Zweiter Punkt"])
        #expect(entries[1].version == "1.0 (27)")
        #expect(entries[1].date == "2026-08-05")
        #expect(entries[1].bullets == ["Verbesserung: Dritter Punkt"])
    }

    @Test func fuegtMehrzeiligUmgebrocheneBulletsWiederZusammen() {
        let markdown = """
        <!-- versions -->

        ## [1.0 (1)] - 2026-01-01

        - Neu: Ein langer Satz, der über
          mehrere Zeilen
          umgebrochen wurde
        - Kurzer zweiter Punkt
        """

        let entries = ChangelogParser.parse(markdown)

        #expect(entries.count == 1)
        #expect(entries[0].bullets == [
            "Neu: Ein langer Satz, der über mehrere Zeilen umgebrochen wurde",
            "Kurzer zweiter Punkt"
        ])
    }

    @Test func ignoriertPreambelTextVorDerErstenUeberschrift() {
        let markdown = """
        # Changelog

        Alle nennenswerten Änderungen werden hier dokumentiert.
        Ein zweiter Absatz ohne Bullet-Punkte.

        <!-- versions -->

        ## [2.0] - 2026-01-01

        - Einziger Punkt
        """

        let entries = ChangelogParser.parse(markdown)

        #expect(entries.count == 1)
        #expect(entries[0].bullets == ["Einziger Punkt"])
    }

    @Test func leererTextLiefertLeeresArray() {
        #expect(ChangelogParser.parse("").isEmpty)
    }

    @Test func versionOhneBulletsLiefertLeereBulletliste() {
        let markdown = """
        <!-- versions -->

        ## [1.0] - 2026-01-01

        ## [0.9] - 2025-12-01

        - Ein Punkt
        """

        let entries = ChangelogParser.parse(markdown)

        #expect(entries.count == 2)
        #expect(entries[0].bullets.isEmpty)
        #expect(entries[1].bullets == ["Ein Punkt"])
    }

    @Test func ueberschriftOhneDatumsangabeWirdIgnoriert() {
        let markdown = """
        <!-- versions -->

        ## [Kaputte Überschrift ohne Datum]

        - Dieser Punkt gehört zu keiner erkannten Version
        """

        let entries = ChangelogParser.parse(markdown)

        #expect(entries.isEmpty)
    }

    @Test func reihenfolgeDerQuelldateiBleibtErhalten() {
        let markdown = """
        <!-- versions -->

        ## [3] - 2026-03-01

        - C

        ## [2] - 2026-02-01

        - B

        ## [1] - 2026-01-01

        - A
        """

        let entries = ChangelogParser.parse(markdown)

        #expect(entries.map(\.version) == ["3", "2", "1"])
    }
}
```

- [ ] **Step 2: Testlauf verifizieren, dass er fehlschlägt**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ChangelogParserTests -parallel-testing-enabled NO`
Expected: FAIL — `ChangelogParser`/`ChangelogEntry` existieren noch nicht ("Cannot find
type 'ChangelogParser' in scope").

- [ ] **Step 3: Minimale Implementierung schreiben**

Erstelle `Feedivo/Services/ChangelogParser.swift`:

```swift
import Foundation

/// Ein einzelner Versions-Eintrag aus CHANGELOG.md.
struct ChangelogEntry: Equatable {
    let version: String
    let date: String
    let bullets: [String]
}

/// Parst den Markdown-Text von CHANGELOG.md in strukturierte Versions-Einträge.
/// Erwartetes Format (siehe CHANGELOG.md): `## [Version] - Datum`-Überschriften,
/// gefolgt von `- `-Aufzählungspunkten, die über mehrere Zeilen umbrechen können
/// (Fortsetzungszeilen ohne "- "-Präfix werden an den letzten Punkt angehängt, da
/// CHANGELOG.md lange Sätze für die Lesbarkeit im Markdown-Quelltext umbricht).
enum ChangelogParser {
    static func parse(_ markdown: String) -> [ChangelogEntry] {
        var entries: [ChangelogEntry] = []
        var currentVersion: String?
        var currentDate: String?
        var currentBullets: [String] = []

        func flushCurrentEntry() {
            guard let version = currentVersion, let date = currentDate else { return }
            entries.append(ChangelogEntry(version: version, date: date, bullets: currentBullets))
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if rawLine.hasPrefix("## [") {
                if let heading = parseHeading(rawLine) {
                    flushCurrentEntry()
                    currentVersion = heading.version
                    currentDate = heading.date
                    currentBullets = []
                }
                // Ein nicht erkanntes Überschriftenformat wird übersprungen, darf aber
                // nicht als Fortsetzungszeile eines Bullets missverstanden werden -
                // deshalb eigener Zweig mit "continue", kein Fallthrough unten.
                continue
            }

            if trimmed.hasPrefix("- "), currentVersion != nil {
                currentBullets.append(String(trimmed.dropFirst(2)))
            } else if !trimmed.isEmpty, currentVersion != nil, !currentBullets.isEmpty {
                let lastIndex = currentBullets.count - 1
                currentBullets[lastIndex] += " " + trimmed
            }
        }
        flushCurrentEntry()

        return entries
    }

    /// Erwartet `## [Version] - Datum`, z. B. `## [1.0 (28)] - 2026-08-07`.
    private static func parseHeading(_ line: String) -> (version: String, date: String)? {
        guard let openBracket = line.firstIndex(of: "["),
              let closeBracket = line.firstIndex(of: "]"),
              openBracket < closeBracket else {
            return nil
        }
        let version = String(line[line.index(after: openBracket)..<closeBracket])

        let afterBracket = line[line.index(after: closeBracket)...]
        guard let dashRange = afterBracket.range(of: "- ") else {
            return nil
        }
        let date = afterBracket[dashRange.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !date.isEmpty else { return nil }

        return (version, date)
    }
}
```

- [ ] **Step 4: Testlauf verifizieren, dass er besteht**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ChangelogParserTests -parallel-testing-enabled NO`
Expected: PASS (7/7 Tests grün).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/ChangelogParser.swift FeedivoTests/Services/ChangelogParserTests.swift
git commit -m "feat: reinen ChangelogParser für CHANGELOG.md-Versionseinträge ergänzen"
```

---

### Task 2: `CHANGELOG.md` ins App-Bundle aufnehmen + `bump_version.sh` synchron halten

**Files:**
- Create (Kopie): `Feedivo/Resources/CHANGELOG.md`
- Modify: `scripts/bump_version.sh:35-37` (neue Pfad-Variable), `:150-154` (Sync-Kopie
  nach jedem Bump)

**Interfaces:**
- Produces (für Task 4): Bundle-Resource `CHANGELOG.md`, zur Laufzeit lesbar über
  `Bundle.main.url(forResource: "CHANGELOG", withExtension: "md")`.

- [ ] **Step 1: Initiale Kopie anlegen**

Run:
```bash
cp CHANGELOG.md Feedivo/Resources/CHANGELOG.md
diff CHANGELOG.md Feedivo/Resources/CHANGELOG.md
```
Expected: `diff` liefert keine Ausgabe (Dateien sind identisch).

- [ ] **Step 2: `bump_version.sh` um Pfad-Variable ergänzen**

In `scripts/bump_version.sh`, ersetze:

```bash
PBXPROJ="Feedivo.xcodeproj/project.pbxproj"
CHANGELOG="CHANGELOG.md"
MARKER_FILE="$(git rev-parse --git-dir)/feedivo-last-bumped-sha"
```

durch:

```bash
PBXPROJ="Feedivo.xcodeproj/project.pbxproj"
CHANGELOG="CHANGELOG.md"
BUNDLED_CHANGELOG="Feedivo/Resources/CHANGELOG.md"
MARKER_FILE="$(git rev-parse --git-dir)/feedivo-last-bumped-sha"
```

- [ ] **Step 3: Sync-Kopie nach dem CHANGELOG-Update ergänzen**

Im selben File, ersetze:

```bash
' "$CHANGELOG" > "${CHANGELOG}.tmp"
mv "${CHANGELOG}.tmp" "$CHANGELOG"
rm -f "$ENTRY_FILE"

git add "$PBXPROJ" "$CHANGELOG"
git commit -m "chore: Version ${VERSION_LABEL}" >/dev/null
```

durch:

```bash
' "$CHANGELOG" > "${CHANGELOG}.tmp"
mv "${CHANGELOG}.tmp" "$CHANGELOG"
rm -f "$ENTRY_FILE"

# Im App-Bundle gezeigte Kopie fuer das "Versionshistorie"-Fenster
# (VersionHistoryWindowView.swift) synchron halten - liegt im file-system-
# synchronisierten Resources-Ordner, wird dadurch automatisch als Bundle-Resource
# mitgebaut, ohne manuelle project.pbxproj-Aenderung.
cp "$CHANGELOG" "$BUNDLED_CHANGELOG"

git add "$PBXPROJ" "$CHANGELOG" "$BUNDLED_CHANGELOG"
git commit -m "chore: Version ${VERSION_LABEL}" >/dev/null
```

- [ ] **Step 4: Skript-Syntax verifizieren**

Run: `bash -n scripts/bump_version.sh && BUMP_VERSION_DRY_RUN=1 bash scripts/bump_version.sh`
Expected: kein Syntaxfehler; der Dry-Run bricht wie gewohnt früh ab (aktueller HEAD ist
noch nicht gepusht bzw. bereits gebumpt) und ändert keine Dateien — `git status` danach
zeigt nur die in Step 1 hinzugefügte, noch ungetrackte `Feedivo/Resources/CHANGELOG.md`
sowie die Skript-Änderung selbst.

- [ ] **Step 5: Build verifizieren und Bundle-Inhalt prüfen**

Run:
```bash
xcodebuild build -scheme Feedivo -configuration Debug
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Feedivo.app" -newer scripts/bump_version.sh 2>/dev/null | head -1)
ls "$APP_PATH/Contents/Resources/" | grep -i changelog
diff CHANGELOG.md "$APP_PATH/Contents/Resources/CHANGELOG.md"
```
Expected: `BUILD SUCCEEDED`; `ls` findet `CHANGELOG.md`; `diff` liefert keine Ausgabe
(gebündelte Kopie entspricht exakt der Root-Datei). Falls `$APP_PATH` leer ist:
`xcodebuild build -scheme Feedivo -configuration Debug -derivedDataPath build` erneut
laufen lassen und stattdessen `build/Build/Products/Debug/Feedivo.app/Contents/Resources/
CHANGELOG.md` prüfen.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Resources/CHANGELOG.md scripts/bump_version.sh
git commit -m "feat: CHANGELOG.md als Bundle-Resource aufnehmen, bump_version.sh hält sie synchron"
```

---

### Task 3: Neue L10n-Keys ergänzen

**Files:**
- Modify: `Feedivo/Resources/L10n.swift:1265` (neue Konstanten danach)
- Modify: `Feedivo/Resources/Localizable.xcstrings:3` (neue Katalogeinträge)

**Interfaces:**
- Produces (für Task 4 + Task 5):
  - `L10n.settingsAboutGitHubLink: LocalizedStringKey`
  - `L10n.settingsAboutVersionHistoryButton: LocalizedStringKey`
  - `L10n.versionHistoryWindowTitle: LocalizedStringKey`
  - `L10n.versionHistoryEmptyState: LocalizedStringKey`
  - `L10n.versionHistoryOlderVersionsLink: LocalizedStringKey`

- [ ] **Step 1: Konstanten in `L10n.swift` ergänzen**

In `Feedivo/Resources/L10n.swift`, ersetze:

```swift
    static let updateCheckHomebrewHint = LocalizedStringKey("updateCheck.homebrewHint")
    // Bewusst String (nicht LocalizedStringKey) wie updateCheckMenuItem selbst -
```

durch:

```swift
    static let updateCheckHomebrewHint = LocalizedStringKey("updateCheck.homebrewHint")
    static let settingsAboutGitHubLink = LocalizedStringKey("settings.about.githubLink")
    static let settingsAboutVersionHistoryButton = LocalizedStringKey("settings.about.versionHistoryButton")
    static let versionHistoryWindowTitle = LocalizedStringKey("versionHistory.window.title")
    static let versionHistoryEmptyState = LocalizedStringKey("versionHistory.window.empty")
    static let versionHistoryOlderVersionsLink = LocalizedStringKey("versionHistory.window.olderVersionsLink")
    // Bewusst String (nicht LocalizedStringKey) wie updateCheckMenuItem selbst -
```

- [ ] **Step 2: Katalogeinträge in `Localizable.xcstrings` ergänzen**

**Niemals die ganze Datei per `json.load`/`json.dump` roundtripen** — stattdessen reine
Text-Segment-Einfügung direkt nach der Zeile `  "strings" : {`, vor dem bestehenden
ersten Eintrag `"" : {`. In `Feedivo/Resources/Localizable.xcstrings`, ersetze:

```
  "strings" : {
    "" : {

    },
```

durch (5 neue Einträge, danach folgt unverändert der bestehende `"" : {`-Eintrag):

```
  "strings" : {
    "settings.about.githubLink" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "GitHub-Repository öffnen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Open GitHub Repository"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ouvrir le dépôt GitHub"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Apri il repository GitHub"
          }
        }
      }
    },
    "settings.about.versionHistoryButton" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Versionshistorie anzeigen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Show Version History"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Afficher l'historique des versions"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Mostra cronologia versioni"
          }
        }
      }
    },
    "versionHistory.window.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Versionshistorie"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Version History"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Historique des versions"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Cronologia versioni"
          }
        }
      }
    },
    "versionHistory.window.empty" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Keine Versionshistorie verfügbar."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No version history available."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aucun historique de version disponible."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nessuna cronologia delle versioni disponibile."
          }
        }
      }
    },
    "versionHistory.window.olderVersionsLink" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ältere Versionen auf GitHub ansehen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "View older versions on GitHub"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Voir les versions précédentes sur GitHub"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Visualizza le versioni precedenti su GitHub"
          }
        }
      }
    },
    "" : {

    },
```

- [ ] **Step 3: Einfügung verifizieren**

Run:
```bash
grep -c '"settings.about.githubLink"\|"settings.about.versionHistoryButton"\|"versionHistory.window.title"\|"versionHistory.window.empty"\|"versionHistory.window.olderVersionsLink"' Feedivo/Resources/Localizable.xcstrings
```
Expected: `5` (jeder Key genau einmal).

Run: `git diff --stat -- Feedivo/Resources/Localizable.xcstrings`
Expected: nur Insertions, keine oder kaum Deletions.

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED (die neuen `L10n`-Konstanten werden noch nirgends verwendet,
müssen aber bereits fehlerfrei kompilieren).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat: L10n-Keys für GitHub-Link und Versionshistorie ergänzen"
```

---

### Task 4: `VersionHistoryWindowView` + neue Window-Scene

**Files:**
- Create: `Feedivo/Views/Settings/VersionHistoryWindowView.swift`
- Modify: `Feedivo/App/FeedivoApp.swift` (neue `Window`-Scene nach `CleanupHistoryWindowView`)

**Interfaces:**
- Consumes: `ChangelogParser.parse(_:) -> [ChangelogEntry]` (Task 1),
  `Bundle.main.url(forResource: "CHANGELOG", withExtension: "md")` (Task 2),
  `L10n.versionHistoryWindowTitle`/`versionHistoryEmptyState`/`versionHistoryOlderVersionsLink` (Task 3).
- Produces (für Task 5): `VersionHistoryWindowView.windowID: String`.

- [ ] **Step 1: View erstellen**

Erstelle `Feedivo/Views/Settings/VersionHistoryWindowView.swift`:

```swift
import SwiftUI

/// Eigenständiges Fenster für die Versionshistorie (Info-Tab → "Versionshistorie
/// anzeigen"). Liest die im Bundle mitgelieferte Kopie von CHANGELOG.md (siehe
/// scripts/bump_version.sh, hält beide Dateien synchron) - rein dateibasiert, keine
/// Datenbankanbindung nötig, da sich der Inhalt nur mit einem neuen App-Build ändert.
struct VersionHistoryWindowView: View {
    static let windowID = "version-history-window"

    private static let maxDisplayedEntries = 15
    private static let repositoryChangelogURL = URL(string: "https://github.com/martinfelder/feedivo-mac/blob/main/CHANGELOG.md")!

    @State private var entries: [ChangelogEntry] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(displayedEntries, id: \.version) { entry in
                    versionSection(entry)
                }

                if entries.count > Self.maxDisplayedEntries {
                    Link(L10n.versionHistoryOlderVersionsLink, destination: Self.repositoryChangelogURL)
                        .font(.system(size: 11.5))
                }

                if entries.isEmpty {
                    Text(L10n.versionHistoryEmptyState)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: loadEntries)
    }

    private var displayedEntries: [ChangelogEntry] {
        Array(entries.prefix(Self.maxDisplayedEntries))
    }

    private func versionSection(_ entry: ChangelogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.version)
                    .font(.system(size: 13, weight: .semibold))
                Text(entry.date)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(entry.bullets.enumerated()), id: \.offset) { _, bullet in
                Text("•  \(bullet)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadEntries() {
        guard entries.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        entries = ChangelogParser.parse(markdown)
    }
}
```

- [ ] **Step 2: Window-Scene in `FeedivoApp.swift` registrieren**

In `Feedivo/App/FeedivoApp.swift`, ersetze:

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

        Window(L10n.feedRefreshDiagnosticsWindowTitle, id: FeedRefreshDiagnosticsWindowView.windowID) {
```

durch:

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

        Window(L10n.versionHistoryWindowTitle, id: VersionHistoryWindowView.windowID) {
            VersionHistoryWindowView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 480, height: 560)

        Window(L10n.feedRefreshDiagnosticsWindowTitle, id: FeedRefreshDiagnosticsWindowView.windowID) {
```

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Bestehende Scene-Konfigurationstests laufen lassen (Regressions-Check)**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests -parallel-testing-enabled NO`
Expected: Diese Suite hat bereits ~17-25 dokumentierte, vorbestehende Fehlschläge (siehe
CLAUDE.md-Gotcha "Bekannte, dauerhaft vorbestehende Testfehlschläge") — hier zählt nur,
dass KEINE zusätzlichen, NEUEN Fehlschläge relativ zum Stand vor diesem Task auftreten
(per `git stash`/Vergleich gegen den Commit vor Step 1 verifizieren, falls die Zahl
verdächtig erscheint).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Settings/VersionHistoryWindowView.swift Feedivo/App/FeedivoApp.swift
git commit -m "feat: Versionshistorie-Fenster (VersionHistoryWindowView) ergänzen"
```

---

### Task 5: `AboutSettingsView` — GitHub-Link + Button

**Files:**
- Modify: `Feedivo/Views/Settings/AboutSettingsView.swift`

**Interfaces:**
- Consumes: `L10n.settingsAboutGitHubLink`/`settingsAboutVersionHistoryButton` (Task 3),
  `VersionHistoryWindowView.windowID` (Task 4).

- [ ] **Step 1: `@Environment(\.openWindow)` ergänzen**

In `Feedivo/Views/Settings/AboutSettingsView.swift`, ersetze:

```swift
struct AboutSettingsView: View {
    @Environment(\.sparkleUpdateCoordinator) private var coordinator
```

durch:

```swift
struct AboutSettingsView: View {
    @Environment(\.sparkleUpdateCoordinator) private var coordinator
    @Environment(\.openWindow) private var openWindow
```

- [ ] **Step 2: GitHub-Link und Versionshistorie-Button ergänzen**

Im selben File, ersetze:

```swift
                if coordinator?.isHomebrewInstall == true {
                    // Bei Homebrew-Installationen bleibt SPUUpdater komplett inaktiv
                    // (siehe SparkleUpdateCoordinator.start()) - ein Such-Button hätte
                    // hier keine Wirkung, Updates laufen ausschließlich über
                    // `brew upgrade --cask feedivo`.
                    Text(L10n.updateCheckHomebrewHint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    Button(L10n.updateCheckMenuItem) {
                        coordinator?.checkForUpdatesManually()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
```

durch:

```swift
                if coordinator?.isHomebrewInstall == true {
                    // Bei Homebrew-Installationen bleibt SPUUpdater komplett inaktiv
                    // (siehe SparkleUpdateCoordinator.start()) - ein Such-Button hätte
                    // hier keine Wirkung, Updates laufen ausschließlich über
                    // `brew upgrade --cask feedivo`.
                    Text(L10n.updateCheckHomebrewHint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    Button(L10n.updateCheckMenuItem) {
                        coordinator?.checkForUpdatesManually()
                    }
                    .padding(.top, 4)
                }

                Link(destination: Self.repositoryURL) {
                    Text(L10n.settingsAboutGitHubLink)
                        .font(.system(size: 13))
                }
                .padding(.top, 12)

                Button(L10n.settingsAboutVersionHistoryButton) {
                    openWindow(id: VersionHistoryWindowView.windowID)
                }
                .padding(.top, 4)
            }
        }
    }

    private static let repositoryURL = URL(string: "https://github.com/martinfelder/feedivo-mac")!
}
```

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/Settings/AboutSettingsView.swift
git commit -m "feat: GitHub-Link und Versionshistorie-Button im Info-Tab ergänzen"
```

---

### Task 6: Regressionslauf und Release-Build

**Files:** Keine Änderungen — reine Verifikation.

- [ ] **Step 1: Neue und benachbarte Testsuiten gezielt laufen lassen**

Run:
```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/ChangelogParserTests \
  -parallel-testing-enabled NO
```
Expected: alle Tests grün.

- [ ] **Step 2: Vollständiger Debug-Build**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Vollständiger Release-Build**

Run: `xcodebuild build -scheme Feedivo -configuration Release`
Expected: BUILD SUCCEEDED (deckt u. a. ab, dass die in Task 3 ergänzten
`Localizable.xcstrings`-Einträge korrekt formatiert sind, da der String-Catalog-
Compile-Schritt in beiden Konfigurationen läuft).

- [ ] **Step 4: Manuelle Live-Verifikationscheckliste dokumentieren**

Kein computer-use für native macOS-Apps verfügbar — folgende Punkte bleiben für den
Nutzer als manuelle Checkliste (z. B. als Kommentar im finalen SDD-Report oder direkt an
den Nutzer kommuniziert, kein Code-Schritt):

1. Einstellungen → Info öffnen: "GitHub-Repository öffnen"-Link ist sichtbar und öffnet
   `https://github.com/martinfelder/feedivo-mac` im Standardbrowser.
2. "Versionshistorie anzeigen"-Button öffnet ein neues Fenster mit echten
   Versionseinträgen (neueste zuerst, Version + Datum + Aufzählungspunkte lesbar,
   mehrzeilig umgebrochene Sätze erscheinen als ein zusammenhängender Punkt, nicht
   abgeschnitten).
3. Ganz unten in der Liste erscheint ein Link "Ältere Versionen auf GitHub ansehen" (da
   `CHANGELOG.md` deutlich mehr als 15 Versionen enthält).
4. Fenster erneut öffnen (schließen + über den Button erneut öffnen) — keine
   Doppel-Einträge, keine Absturz/Ladeprobleme.
5. Hell-/Dunkelmodus: beide Fenster (Info-Tab, Versionshistorie) sehen in beiden
   Darstellungen stimmig aus.

- [ ] **Step 5: Finalen Stand committen (falls noch offene Änderungen vorhanden)**

Run: `git status`
Expected: bei sauberem Abschluss aller vorherigen Tasks keine offenen Änderungen mehr —
falls doch, gezielt prüfen was fehlt und in einem passenden Commit nachziehen.
