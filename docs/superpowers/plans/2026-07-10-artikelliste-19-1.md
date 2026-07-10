# Feature 19.1 "Artikel-Liste anpassen" fertigstellen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die letzten offenen Punkte aus Feature 19.1 der Artikelliste umsetzen — Summary anzeigen/ausblenden mit Zeilen-Stepper (1–3), sowie ein app-weites Datum-Anzeigeformat (relativ/absolut).

**Architecture:** Neue Einstellungstypen in `ArticleListDisplaySettings.swift` (gleiches Muster wie `ArticleListImagePosition`/`ArticleListFeedNamePosition`: `storageKey` + `defaultXxx` + `resolved(from:)`). SwiftUI-Views (`ArticleRowView`, `SidebarView`, `ArticleMetadataInspectorView`) lesen den Datum-Modus reaktiv über `@AppStorage`. Nicht-View-Kontexte (`ReaderMetadataFormatter`, aufgerufen aus `ReaderPreparedArticle.init` — läuft laut Kommentar bewusst abseits des MainActor — und aus den Export-Renderern) lesen den Modus stattdessen direkt aus `UserDefaults.standard`, exakt nach dem Vorbild der bestehenden `appLocale`-Property in `Date+RelativeDisplay.swift`. Beide Wege münden in dieselbe neue, parametrisierte `Date.feedivoDisplay(mode:)`-Methode.

**Tech Stack:** SwiftUI, `@AppStorage`, Swift Testing (`@Test`/`#expect`, kein XCTest), `Localizable.xcstrings` (String Catalog, 4 Sprachen de/en/fr/it).

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention, siehe CLAUDE.md).
- Keine Verhaltensänderung für Bestandsnutzer ohne explizite Einstellungsänderung — alle neuen Defaults entsprechen dem heutigen (hartcodierten) Verhalten.
- Nach jedem Task: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet` muss fehlerfrei durchlaufen (SourceKit-Diagnosen in der IDE sind bekanntermaßen unzuverlässig, siehe CLAUDE.md — nur ein echter Build zählt).
- Volle Testsuite (`xcodebuild test` ohne `-only-testing`) hängt bekanntermaßen — immer gezielt mit `-only-testing:FeedivoTests/<SuiteName>` testen, mit `-parallel-testing-enabled NO`.
- Keine Uhrzeit-Komponente im absoluten Datumsformat — reines Kurzdatum, konsistent mit dem bestehenden `shortDateFormatter`.
- `Localizable.xcstrings`-Einträge müssen für alle 4 Sprachen (de/en/fr/it) mit `"state" : "translated"` befüllt werden, keine leeren Stub-Einträge stehen lassen.

---

## Task 1: Summary-Einstellungstypen + Unit-Tests

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleListDisplaySettings.swift`
- Test: `FeedivoTests/ArticleListDisplaySettingsTests.swift`

**Interfaces:**
- Produces: `ArticleListSummaryVisibilitySettings.showsSummaryKey: String`, `.defaultShowsSummary: Bool`; `ArticleListSummaryLineCount.storageKey: String`, `.defaultValue: Int`, `.allowedRange: ClosedRange<Int>`, `.resolved(from: Int) -> Int`

- [ ] **Step 1: Neue Settings-Typen in `ArticleListDisplaySettings.swift` ergänzen**

Am Ende der Datei (nach der bestehenden `ArticleListFeedNameVisibilitySettings`-Enum, vor dem letzten `}`-losen Dateiende) ergänzen:

```swift

/// Ob die Artikel-Zusammenfassung in der Artikelliste angezeigt wird (Feature 19.1).
enum ArticleListSummaryVisibilitySettings {
    static let showsSummaryKey = "articleList.showsSummary"
    static let defaultShowsSummary = true
}

/// Anzahl der Vorschautext-Zeilen der Summary in der Artikelliste (Feature 19.1).
/// Nur relevant, wenn `ArticleListSummaryVisibilitySettings.showsSummaryKey` an ist.
enum ArticleListSummaryLineCount {
    static let storageKey = "articleList.summaryLineCount"
    static let defaultValue = 2
    static let allowedRange = 1...3

    /// Fängt ungültige/veraltete gespeicherte Werte ab (z. B. durch manuelle
    /// UserDefaults-Manipulation oder künftige Range-Änderungen).
    static func resolved(from storedValue: Int) -> Int {
        allowedRange.contains(storedValue) ? storedValue : defaultValue
    }
}
```

- [ ] **Step 2: Fehlschlagende Tests schreiben**

In `FeedivoTests/ArticleListDisplaySettingsTests.swift`, nach der letzten bestehenden `@Test func`, vor der schließenden `}` der Struct ergänzen:

```swift

    @Test func summaryVisibilityDefaultIstAn() {
        #expect(ArticleListSummaryVisibilitySettings.defaultShowsSummary == true)
    }

    @Test func summaryLineCountDefaultIstZwei() {
        #expect(ArticleListSummaryLineCount.defaultValue == 2)
    }

    @Test func summaryLineCountResolvedFaengtUngueltigeWerteAb() {
        #expect(ArticleListSummaryLineCount.resolved(from: 1) == 1)
        #expect(ArticleListSummaryLineCount.resolved(from: 3) == 3)
        #expect(ArticleListSummaryLineCount.resolved(from: 0) == ArticleListSummaryLineCount.defaultValue)
        #expect(ArticleListSummaryLineCount.resolved(from: 4) == ArticleListSummaryLineCount.defaultValue)
        #expect(ArticleListSummaryLineCount.resolved(from: -1) == ArticleListSummaryLineCount.defaultValue)
    }
```

- [ ] **Step 3: Build ausführen (Tests kompilieren gegen die neuen Typen)**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen

- [ ] **Step 4: Tests ausführen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/ArticleListDisplaySettingsTests -quiet`
Expected: `** TEST SUCCEEDED **`, alle 8 Tests (5 bestehende + 3 neue) grün

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleListDisplaySettings.swift FeedivoTests/ArticleListDisplaySettingsTests.swift
git commit -m "Feature 19.1: Summary-Einstellungstypen (Sichtbarkeit + Zeilenzahl) ergänzt"
```

---

## Task 2: Summary in `ArticleRowView.swift` verdrahten

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleRowView.swift:1-64`

**Interfaces:**
- Consumes: `ArticleListSummaryVisibilitySettings.showsSummaryKey/.defaultShowsSummary`, `ArticleListSummaryLineCount.storageKey/.defaultValue/.resolved(from:)` (aus Task 1)

- [ ] **Step 1: Neue `@AppStorage`-Properties ergänzen**

In `ArticleRowView.swift`, nach der bestehenden `feedNamePositionRawValue`-Property (Zeile 12–13) ergänzen:

```swift
    @AppStorage(ArticleListSummaryVisibilitySettings.showsSummaryKey)
    private var showsSummary = ArticleListSummaryVisibilitySettings.defaultShowsSummary

    @AppStorage(ArticleListSummaryLineCount.storageKey)
    private var summaryLineCount = ArticleListSummaryLineCount.defaultValue
```

- [ ] **Step 2: Summary-Rendering anpassen**

Bestehenden Block (aktuell Zeilen 59–64):

```swift
                if let summary = snapshot.summary, !summary.isEmpty {
                    Text(summary)
                        .font(interfaceTextSize.font(size: 13))
                        .foregroundStyle(snapshot.isRead ? .tertiary : .secondary)
                        .lineLimit(2)
                }
```

ersetzen durch:

```swift
                if showsSummary, let summary = snapshot.summary, !summary.isEmpty {
                    Text(summary)
                        .font(interfaceTextSize.font(size: 13))
                        .foregroundStyle(snapshot.isRead ? .tertiary : .secondary)
                        .lineLimit(ArticleListSummaryLineCount.resolved(from: summaryLineCount))
                }
```

- [ ] **Step 3: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleRowView.swift
git commit -m "Feature 19.1: Summary-Anzeige in ArticleRowView an neue Einstellungen gekoppelt"
```

---

## Task 3: Summary-UI in `SettingsView.swift` + L10n-Keys

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift:376, 444-482`
- Modify: `Feedivo/Resources/L10n.swift:284` (Einfügung nach bestehender `settingsArticleListFeedNamePositionDescription`-Zeile)
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ArticleListSummaryVisibilitySettings`, `ArticleListSummaryLineCount` (aus Task 1)
- Produces: `L10n.settingsArticleListShowsSummaryTitle`, `L10n.settingsArticleListShowsSummaryDescription`, `L10n.settingsArticleListSummaryLineCountTitle`, `L10n.settingsArticleListSummaryLineCountDescription`

- [ ] **Step 1: L10n-Keys in `L10n.swift` ergänzen**

Nach Zeile 284 (`static let settingsArticleListFeedNamePositionDescription = LocalizedStringKey("settings.articleList.feedNamePosition.description")`) einfügen:

```swift
    static let settingsArticleListShowsSummaryTitle = LocalizedStringKey("settings.articleList.showsSummary.title")
    static let settingsArticleListShowsSummaryDescription = LocalizedStringKey("settings.articleList.showsSummary.description")
    static let settingsArticleListSummaryLineCountTitle = LocalizedStringKey("settings.articleList.summaryLineCount.title")
    static let settingsArticleListSummaryLineCountDescription = LocalizedStringKey("settings.articleList.summaryLineCount.description")
```

- [ ] **Step 2: Vier Einträge in `Localizable.xcstrings` ergänzen**

In `Feedivo/Resources/Localizable.xcstrings` ist jeder String-Key ein Top-Level-Eintrag im `"strings"`-Objekt, alphabetisch sortiert. Nach dem bestehenden Eintrag `"settings.articleList.feedNamePosition.title"` (davor liegt `.description`) die folgenden vier neuen Einträge einfügen — Einfügereihenfolge alphabetisch, exakt zwischen `"settings.articleList.feedNamePosition.title"` und dem nächsten alphabetisch folgenden bestehenden `"settings.articleList.*"`- oder `"settings.appearance*"`-Key (per Grep vor dem Einfügen die tatsächliche Nachbar-Zeile bestimmen, da die Datei sich seit Planerstellung nicht geändert haben sollte, aber Zeilennummern instabil sind — Anker ist der Key-Name, nicht die Zeilennummer):

```json
    "settings.articleList.showsSummary.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Zeigt einen kurzen Vorschautext unter dem Artikeltitel."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Shows a short preview text below the article title."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Affiche un court texte d'aperçu sous le titre de l'article."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Mostra un breve testo di anteprima sotto il titolo dell'articolo."
          }
        }
      }
    },
    "settings.articleList.showsSummary.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Zusammenfassung anzeigen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Show summary"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Afficher le résumé"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Mostra riepilogo"
          }
        }
      }
    },
    "settings.articleList.summaryLineCount.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Wie viele Zeilen der Zusammenfassung in der Artikelliste angezeigt werden."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "How many lines of the summary are shown in the article list."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nombre de lignes du résumé affichées dans la liste des articles."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Quante righe del riepilogo vengono mostrate nell'elenco articoli."
          }
        }
      }
    },
    "settings.articleList.summaryLineCount.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Zeilen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Lines"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Lignes"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Righe"
          }
        }
      }
    },
```

Nach dem Einfügen JSON-Validität prüfen:

Run: `python3 -c "import json; json.load(open('Feedivo/Resources/Localizable.xcstrings')); print('valid JSON')"`
Expected: `valid JSON`

- [ ] **Step 3: `@AppStorage`-Properties in `SettingsView.swift` ergänzen**

Nach Zeile 376 (`private var articleListFeedNamePositionRawValue = ...`) ergänzen:

```swift

    @AppStorage(ArticleListSummaryVisibilitySettings.showsSummaryKey)
    private var articleListShowsSummary = ArticleListSummaryVisibilitySettings.defaultShowsSummary

    @AppStorage(ArticleListSummaryLineCount.storageKey)
    private var articleListSummaryLineCount = ArticleListSummaryLineCount.defaultValue
```

- [ ] **Step 4: Neue Settings-Zeilen in der „Artikelliste"-Sektion ergänzen**

Innerhalb von `NewSettingsBlock(eyebrow: "Artikelliste")`, nach der bestehenden `NewSettingRow` für `settingsArticleListFeedNamePositionTitle` (unmittelbar vor der schließenden `}` dieses Blocks) ergänzen:

```swift

                NewSettingRow(
                    title: L10n.settingsArticleListShowsSummaryTitle,
                    description: L10n.settingsArticleListShowsSummaryDescription
                ) {
                    Toggle("", isOn: $articleListShowsSummary)
                        .labelsHidden()
                }

                NewSettingRow(
                    title: L10n.settingsArticleListSummaryLineCountTitle,
                    description: L10n.settingsArticleListSummaryLineCountDescription
                ) {
                    Stepper(
                        "\(articleListSummaryLineCount)",
                        value: $articleListSummaryLineCount,
                        in: ArticleListSummaryLineCount.allowedRange
                    )
                    .disabled(!articleListShowsSummary)
                    .fixedSize()
                }
```

- [ ] **Step 5: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature 19.1: Summary-Einstellungen (Toggle + Stepper) im Settings-Fenster"
```

---

## Task 4: Datum-Format-Enum + `Date`-Extension + Unit-Tests

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleListDisplaySettings.swift`
- Modify: `Feedivo/Extensions/Date+RelativeDisplay.swift`
- Modify: `Feedivo/Resources/L10n.swift:55` (Einfügung nach bestehenden `articleListFeedNamePosition*`-Keys)
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Test: `FeedivoTests/DateFeedivoDisplayTests.swift` (neu)
- Test: `FeedivoTests/ArticleListDisplaySettingsTests.swift`

**Interfaces:**
- Produces: `ArticleDateDisplayMode` (enum, cases `.relative`/`.absolute`, `.storageKey: String`, `.defaultMode: ArticleDateDisplayMode`, `.resolved(from: String) -> ArticleDateDisplayMode`, `.titleKey: LocalizedStringKey`), `Date.feedivoDisplay(mode: ArticleDateDisplayMode) -> String`

- [ ] **Step 1: L10n-Keys für die Picker-Optionen ergänzen**

In `L10n.swift`, nach Zeile 55 (`static let articleListFeedNamePositionAfterTitle = ...`) einfügen:

```swift
    static let articleDateDisplayModeRelative = LocalizedStringKey("articleDateDisplayMode.relative")
    static let articleDateDisplayModeAbsolute = LocalizedStringKey("articleDateDisplayMode.absolute")
```

- [ ] **Step 2: Zwei Einträge in `Localizable.xcstrings` ergänzen**

Analog zu Task 3 Step 2 — alphabetisch nach Key-Name einsortieren (`articleDateDisplayMode.absolute` vor `articleDateDisplayMode.relative`, in der Nähe der bestehenden `articleList.*`-Keys, da `articleD...` alphabetisch davor liegt):

```json
    "articleDateDisplayMode.absolute" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Absolut"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Absolute"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Absolue"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Assoluta"
          }
        }
      }
    },
    "articleDateDisplayMode.relative" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Relativ"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Relative"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Relative"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Relativa"
          }
        }
      }
    },
```

Run: `python3 -c "import json; json.load(open('Feedivo/Resources/Localizable.xcstrings')); print('valid JSON')"`
Expected: `valid JSON`

- [ ] **Step 3: `ArticleDateDisplayMode`-Enum in `ArticleListDisplaySettings.swift` ergänzen**

Am Dateiende ergänzen (nach den in Task 1 hinzugefügten Typen):

```swift

/// Anzeigeformat für Artikel-/Feed-Zeitstempel: relativ ("vor 2 Stunden") oder
/// absolut (kurzes Datum, z. B. "23.06.2026"). Wirkt app-weit über
/// `Date.feedivoDisplay(mode:)` (Feature 19.1).
enum ArticleDateDisplayMode: String, CaseIterable, Identifiable {
    case relative
    case absolute

    static let storageKey = "articleList.dateDisplayMode"
    static let defaultMode = ArticleDateDisplayMode.relative

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .relative:
            L10n.articleDateDisplayModeRelative
        case .absolute:
            L10n.articleDateDisplayModeAbsolute
        }
    }

    static func resolved(from rawValue: String) -> ArticleDateDisplayMode {
        ArticleDateDisplayMode(rawValue: rawValue) ?? defaultMode
    }
}
```

- [ ] **Step 4: `Date.feedivoDisplay(mode:)` in `Date+RelativeDisplay.swift` ergänzen**

Die Datei komplett wie folgt ersetzen (macht `shortDateFormatter` intern verfügbar für die neue Methode und ergänzt diese, ohne die bestehende `feedivoRelativeDisplay`-Property zu verändern):

```swift
import Foundation

extension Date {
    var feedivoRelativeDisplay: String {
        if Calendar.current.isDateInToday(self) {
            return Self.relativeFormatter.localizedString(for: self, relativeTo: .now)
        }

        return Self.shortDateFormatter.string(from: self)
    }

    /// Datumsanzeige gemäß gewähltem `ArticleDateDisplayMode` (Feature 19.1).
    /// `.relative` verhält sich identisch zu `feedivoRelativeDisplay`.
    /// `.absolute` zeigt immer das kurze Datum, auch für den heutigen Tag.
    func feedivoDisplay(mode: ArticleDateDisplayMode) -> String {
        switch mode {
        case .relative:
            feedivoRelativeDisplay
        case .absolute:
            Self.shortDateFormatter.string(from: self)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = appLocale
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.locale = appLocale
        return formatter
    }()

    /// App-Sprache aus den Einstellungen (gleicher Key wie @AppStorage in
    /// FeedivoApp). Die Formatter sind `static let` — sie werden einmal beim
    /// ersten Zugriff aufgebaut und beachten die damals gewählte Sprache.
    /// Ein Sprachwechsel greift also erst nach App-Neustart (analog zu den
    /// `String(localized:)`-Accessoren in L10n).
    private static var appLocale: Locale {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
        return AppLanguage.resolved(from: raw).locale
    }
}
```

- [ ] **Step 5: Fehlschlagende Tests schreiben**

Neue Datei `FeedivoTests/DateFeedivoDisplayTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct DateFeedivoDisplayTests {

    @Test func absoluterModusZeigtAuchHeuteDasKurzeDatum() {
        let today = Date()
        let absoluteText = today.feedivoDisplay(mode: .absolute)
        let relativeText = today.feedivoDisplay(mode: .relative)

        #expect(absoluteText == today.feedivoRelativeDisplay || relativeText != absoluteText)
        #expect(!absoluteText.isEmpty)
    }

    @Test func relativerModusEntsprichtDerBestehendenPropertyFuerVergangeneDaten() {
        let pastDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!

        #expect(pastDate.feedivoDisplay(mode: .relative) == pastDate.feedivoRelativeDisplay)
    }

    @Test func absoluterUndRelativerModusStimmenFuerVergangeneDatenUeberein() {
        // Für Tage außerhalb "heute" liefert `feedivoRelativeDisplay` bereits
        // das kurze Datum — beide Modi müssen hier identisch sein.
        let pastDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!

        #expect(pastDate.feedivoDisplay(mode: .absolute) == pastDate.feedivoDisplay(mode: .relative))
    }
}
```

- [ ] **Step 6: Tests für `ArticleDateDisplayMode.resolved(from:)` ergänzen**

In `FeedivoTests/ArticleListDisplaySettingsTests.swift`, nach den in Task 1 ergänzten Tests hinzufügen:

```swift

    @Test func dateDisplayModeResolvedFaelltBeiUnbekanntemRohwertAufDefaultZurueck() {
        #expect(ArticleDateDisplayMode.resolved(from: "relative") == .relative)
        #expect(ArticleDateDisplayMode.resolved(from: "absolute") == .absolute)
        #expect(ArticleDateDisplayMode.resolved(from: "unknown") == ArticleDateDisplayMode.defaultMode)
    }

    @Test func dateDisplayModeDefaultIstRelativ() {
        #expect(ArticleDateDisplayMode.defaultMode == .relative)
    }
```

- [ ] **Step 7: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen

- [ ] **Step 8: Tests ausführen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/DateFeedivoDisplayTests -only-testing:FeedivoTests/ArticleListDisplaySettingsTests -quiet`
Expected: `** TEST SUCCEEDED **`, alle Tests grün (3 neue in `DateFeedivoDisplayTests` + 10 in `ArticleListDisplaySettingsTests`)

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleListDisplaySettings.swift Feedivo/Extensions/Date+RelativeDisplay.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings FeedivoTests/DateFeedivoDisplayTests.swift FeedivoTests/ArticleListDisplaySettingsTests.swift
git commit -m "Feature 19.1: ArticleDateDisplayMode-Enum + Date.feedivoDisplay(mode:) ergänzt"
```

---

## Task 5: Datum-Format reaktiv in ArticleRowView, SidebarView, ArticleMetadataInspectorView verdrahten

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleRowView.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift:1063`
- Modify: `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift:399`

**Interfaces:**
- Consumes: `ArticleDateDisplayMode`, `Date.feedivoDisplay(mode:)` (aus Task 4)

- [ ] **Step 1: `ArticleRowView.swift` — Datum-Modus reaktiv lesen**

Nach den in Task 2 ergänzten `@AppStorage`-Properties ergänzen:

```swift
    @AppStorage(ArticleDateDisplayMode.storageKey)
    private var dateDisplayModeRawValue = ArticleDateDisplayMode.defaultMode.rawValue

    private var dateDisplayMode: ArticleDateDisplayMode {
        ArticleDateDisplayMode.resolved(from: dateDisplayModeRawValue)
    }
```

In `metadataText` (aktuell `snapshot.publishedAt?.feedivoRelativeDisplay`) ersetzen durch:

```swift
            snapshot.publishedAt?.feedivoDisplay(mode: dateDisplayMode)
```

- [ ] **Step 2: `SidebarView.swift` — Datum-Modus in `feedPreviewArticleRow` reaktiv lesen**

`SidebarView` ist bereits ein `struct SidebarView: View` — direkt im Struct-Body (bei den anderen `@AppStorage`-Properties, z. B. neben `showsUnreadCountInSidebar` falls dort vorhanden, sonst am Anfang des Structs) ergänzen:

```swift
    @AppStorage(ArticleDateDisplayMode.storageKey)
    private var dateDisplayModeRawValue = ArticleDateDisplayMode.defaultMode.rawValue
```

In `feedPreviewArticleRow(_:)` die Zeile

```swift
                    Text(publishedAt.feedivoRelativeDisplay)
```

ersetzen durch:

```swift
                    Text(publishedAt.feedivoDisplay(mode: ArticleDateDisplayMode.resolved(from: dateDisplayModeRawValue)))
```

- [ ] **Step 3: `ArticleMetadataInspectorView.swift` — Datum-Modus reaktiv lesen**

`ArticleMetadataInspectorView` ist `struct ArticleMetadataInspectorView: View` — im Struct-Body ergänzen:

```swift
    @AppStorage(ArticleDateDisplayMode.storageKey)
    private var dateDisplayModeRawValue = ArticleDateDisplayMode.defaultMode.rawValue
```

Die Computed Property `publishedAtText` (aktuell `currentSnapshot.publishedAt?.feedivoRelativeDisplay`) ersetzen durch:

```swift
    private var publishedAtText: String? {
        currentSnapshot.publishedAt?.feedivoDisplay(mode: ArticleDateDisplayMode.resolved(from: dateDisplayModeRawValue))
    }
```

- [ ] **Step 4: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleRowView.swift Feedivo/Views/Sidebar/SidebarView.swift Feedivo/Views/Reader/ArticleMetadataInspectorView.swift
git commit -m "Feature 19.1: Datum-Format reaktiv in Artikelliste, Sidebar-Vorschau und Reader-Inspector verdrahtet"
```

---

## Task 6: Datum-Format nicht-reaktiv in `ReaderMetadataFormatter` verdrahten (Reader-Content-Vorbereitung + Export)

**Files:**
- Modify: `Feedivo/Views/Reader/ReaderMetadataFormatter.swift`

**Interfaces:**
- Consumes: `ArticleDateDisplayMode`, `Date.feedivoDisplay(mode:)` (aus Task 4)

**Kontext:** `ReaderMetadataFormatter.metadataParts` wird sowohl aus `ReaderPreparedArticle.init(input:)` (läuft laut Code-Kommentar bewusst abseits des MainActor, `@AppStorage` ist dort nicht sicher nutzbar) als auch aus `ArticleDocumentExportRenderers.swift` (PDF/DOCX/Markdown-Export, ebenfalls kein View-Kontext) aufgerufen. Beide lesen den Modus deshalb direkt aus `UserDefaults.standard` — exakt nach dem Vorbild der bestehenden `appLocale`-Property in `Date+RelativeDisplay.swift`.

- [ ] **Step 1: `ReaderMetadataFormatter.swift` um Datum-Modus-Auflösung ergänzen**

Die Zeile

```swift
    static func metadataParts(feedName: String?, readingTime: String?, publishedAt: Date?) -> [String] {
        [
            feedName,
            readingTime,
            publishedAt?.feedivoRelativeDisplay
        ]
```

ersetzen durch:

```swift
    static func metadataParts(feedName: String?, readingTime: String?, publishedAt: Date?) -> [String] {
        [
            feedName,
            readingTime,
            publishedAt?.feedivoDisplay(mode: currentDateDisplayMode)
        ]
```

und direkt darunter, nach der bestehenden `preferredText(content:summary:)`-Hilfsfunktion, eine neue private Hilfsfunktion ergänzen:

```swift

    /// Liest den Datum-Anzeigemodus direkt aus UserDefaults statt über
    /// `@AppStorage`, da dieser Formatter auch aus `ReaderPreparedArticle.init`
    /// (bewusst abseits des MainActor) und aus den Export-Renderern
    /// (kein View-Kontext) aufgerufen wird. Analog zu `Date+RelativeDisplay`s
    /// `appLocale`-Property.
    private static var currentDateDisplayMode: ArticleDateDisplayMode {
        let raw = UserDefaults.standard.string(forKey: ArticleDateDisplayMode.storageKey)
            ?? ArticleDateDisplayMode.defaultMode.rawValue
        return ArticleDateDisplayMode.resolved(from: raw)
    }
```

- [ ] **Step 2: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen

- [ ] **Step 3: Gezielte Tests ausführen (Reader- und Export-Pfad nicht kaputt)**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/ReaderPreparedArticleTests -only-testing:FeedivoTests/ArticleExportServiceTests -quiet`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/Reader/ReaderMetadataFormatter.swift
git commit -m "Feature 19.1: Datum-Format in ReaderMetadataFormatter (Reader-Vorbereitung + Export) verdrahtet"
```

---

## Task 7: Datum-Format-Picker in `SettingsView.swift` + verbleibende L10n-Keys

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/Resources/L10n.swift:284` (nach den in Task 3 ergänzten Summary-Keys)
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ArticleDateDisplayMode` (aus Task 4)
- Produces: `L10n.settingsArticleListDateDisplayModeTitle`, `L10n.settingsArticleListDateDisplayModeDescription`

- [ ] **Step 1: L10n-Keys ergänzen**

Nach den in Task 3 ergänzten `settingsArticleListSummaryLineCountDescription`-Key einfügen:

```swift
    static let settingsArticleListDateDisplayModeTitle = LocalizedStringKey("settings.articleList.dateDisplayMode.title")
    static let settingsArticleListDateDisplayModeDescription = LocalizedStringKey("settings.articleList.dateDisplayMode.description")
```

- [ ] **Step 2: Zwei Einträge in `Localizable.xcstrings` ergänzen**

Analog zu Task 3 Step 2 / Task 4 Step 2, alphabetisch nach `settings.articleList.summaryLineCount.title` einsortieren:

```json
    "settings.articleList.dateDisplayMode.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Legt fest, ob Zeitangaben relativ (\"vor 2 Stunden\") oder als festes Datum angezeigt werden."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Controls whether timestamps are shown relatively (\"2 hours ago\") or as a fixed date."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Définit si les horodatages sont affichés de façon relative (\"il y a 2 heures\") ou avec une date fixe."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Stabilisce se gli orari vengono mostrati in modo relativo (\"2 ore fa\") o con una data fissa."
          }
        }
      }
    },
    "settings.articleList.dateDisplayMode.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Datumsformat"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Date format"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Format de date"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Formato data"
          }
        }
      }
    },
```

Run: `python3 -c "import json; json.load(open('Feedivo/Resources/Localizable.xcstrings')); print('valid JSON')"`
Expected: `valid JSON`

- [ ] **Step 3: `@AppStorage`-Property in `SettingsView.swift` ergänzen**

Nach den in Task 3 ergänzten `articleListSummaryLineCount`-Property ergänzen:

```swift

    @AppStorage(ArticleDateDisplayMode.storageKey)
    private var articleDateDisplayModeRawValue = ArticleDateDisplayMode.defaultMode.rawValue
```

- [ ] **Step 4: Neue Settings-Zeile ergänzen**

In der „Artikelliste"-Sektion, nach der in Task 3 ergänzten Zeilen-Stepper-`NewSettingRow` (vor der schließenden `}` des `NewSettingsBlock`) ergänzen:

```swift

                NewSettingRow(
                    title: L10n.settingsArticleListDateDisplayModeTitle,
                    description: L10n.settingsArticleListDateDisplayModeDescription
                ) {
                    Picker("", selection: $articleDateDisplayModeRawValue) {
                        ForEach(ArticleDateDisplayMode.allCases) { mode in
                            Text(mode.titleKey)
                                .tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                }
```

- [ ] **Step 5: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature 19.1: Datum-Format-Picker im Settings-Fenster"
```

---

## Task 8: FEATURES.md aktualisieren, finaler Build/Test-Durchlauf, Commit

**Files:**
- Modify: `FEATURES.md:806-831` (Feature 19.1) und `:1486` (Kapitelübersicht)

- [ ] **Step 1: Feature-19.1-Statuszeilen aktualisieren**

Den bestehenden Abschnitt (aktuell Zeilen 806–831):

```markdown
### 19.1 Artikel-Liste anpassen
- **Status:** 🔨 In Arbeit — teilweise umgesetzt
- **Zu implementieren (Einstellungen → Darstellung):**
  - Feeds ohne ungelesene Artikel in der Seitenleiste anzeigen / ausblenden — umgesetzt
  - Vorschautext-Zeilen: 0–3 (Stepper), Standard: 2 — 0 = nur Titel + Datum
  - Vorschaubilder in der Liste: anzeigen / ausblenden — umgesetzt 2026-07-08
  - Vorschaubild-Position: Links oder Rechts — umgesetzt 2026-07-08 (als 3-Wege-Einstellung Links/Rechts/Aus)
  - Summary anzeigen / ausblenden
- **Noch offen (nicht jetzt) — jetzt auch entschieden:**
  - Datum-Format: User wählt in Einstellungen (relativ "vor 2 Stunden" oder absolut "23.06.2026")
  - Feed-Name pro Artikel: anzeigen / ausblenden in Einstellungen (nützlich in "Alle" / Smart Filter) — umgesetzt 2026-07-08
  - Ungelesen-Markierung: fetter Text + farbiger Punkt (beides zusammen)
```

ersetzen durch:

```markdown
### 19.1 Artikel-Liste anpassen
- **Status:** ✔️ Fertig
- **Umgesetzt (Einstellungen → Darstellung):**
  - Feeds ohne ungelesene Artikel in der Seitenleiste anzeigen / ausblenden — umgesetzt
  - Vorschautext-Zeilen: 1–3 (Stepper), Standard: 2, plus eigener An/Aus-Toggle für die Summary — umgesetzt 2026-07-10
  - Vorschaubilder in der Liste: anzeigen / ausblenden — umgesetzt 2026-07-08
  - Vorschaubild-Position: Links oder Rechts — umgesetzt 2026-07-08 (als 3-Wege-Einstellung Links/Rechts/Aus)
  - Summary anzeigen / ausblenden — umgesetzt 2026-07-10 (siehe Vorschautext-Zeilen)
  - Datum-Format: relativ ("vor 2 Stunden") oder absolut ("23.06.2026") wählbar, wirkt app-weit (Artikelliste, Sidebar-Vorschau, Reader-Inspector, Reader-Metadatenzeile, Export) — umgesetzt 2026-07-10
  - Feed-Name pro Artikel: anzeigen / ausblenden in Einstellungen (nützlich in "Alle" / Smart Filter) — umgesetzt 2026-07-08
  - Ungelesen-Markierung: fetter Text + farbiger Punkt (beides zusammen) — bereits seit Einführung der Artikelliste kombiniert umgesetzt, kein separater Task nötig (bestätigt 2026-07-10)
```

- [ ] **Step 2: Kapitelübersicht-Zeile aktualisieren**

Zeile 1486 (aktuell):

```markdown
23. **Feature 19.1** — Artikel-Liste anpassen (Vorschautext-Zeilen, Bildposition, Datum-Format, Feed-Name, Ungelesen-Markierung) — Bildposition + Feed-Name (inkl. Favicon) 2026-07-08 erledigt, Rest offen
```

ersetzen durch:

```markdown
23. **Feature 19.1** — Artikel-Liste anpassen (Vorschautext-Zeilen, Bildposition, Datum-Format, Feed-Name, Ungelesen-Markierung) — vollständig umgesetzt (2026-07-08 Bildposition + Feed-Name, 2026-07-10 Summary-Steuerung + Datum-Format)
```

- [ ] **Step 3: Finaler Build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`, 0 `error:`-Zeilen

- [ ] **Step 4: Gesamte betroffene Testabdeckung final laufen lassen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/ArticleListDisplaySettingsTests -only-testing:FeedivoTests/DateFeedivoDisplayTests -only-testing:FeedivoTests/ReaderPreparedArticleTests -only-testing:FeedivoTests/ArticleExportServiceTests -only-testing:FeedivoTests/SQLiteSidebarStateTests -quiet`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add FEATURES.md
git commit -m "Feature 19.1: FEATURES.md auf vollständig umgesetzt aktualisiert"
```

- [ ] **Step 6: Manuelle Verifikation vormerken (nicht automatisierbar)**

Kein computer-use für native macOS-Apps in dieser Umgebung verfügbar (siehe CLAUDE.md). Nach Abschluss dieses Plans dem Nutzer explizit mitteilen, dass folgende Punkte manuell zu prüfen sind:
- Summary-Stepper an den Grenzen 1 und 3, plus Toggle aus (Summary verschwindet komplett)
- Datum-Format-Umschaltung sichtbar in Artikelliste, Sidebar-Feed-Vorschau und Reader-Metadaten-Inspector gleichzeitig
- Exportierter Artikel (Markdown/PDF) zeigt das aktuell gewählte Datum-Format

---

## Self-Review-Notiz (für den Plan-Autor, nicht Teil der Ausführung)

- **Spec-Abdeckung:** Alle 3 aus der Spec offenen Punkte (Summary Toggle+Stepper, Datum-Format app-weit, L10n) sind in Task 1–7 abgedeckt; Punkt 4 (Ungelesen-Markierung) ist in Task 8 als reiner Doku-Fix abgedeckt.
- **Abweichung von der Spec (dokumentiert, kein Rückfragebedarf):** Die Spec ging davon aus, dass alle 4 App-weiten Call-Sites gleich über `@AppStorage` lesen. Beim Plan-Schreiben zeigte sich, dass `ReaderMetadataFormatter` (aufgerufen aus `ReaderPreparedArticle.init`, bewusst abseits des MainActor, sowie aus den Export-Renderern) kein View-Kontext ist und `@AppStorage` dort nicht nutzbar ist. Task 6 löst das konsistent mit dem bestehenden `appLocale`-Vorbild in `Date+RelativeDisplay.swift` (direktes `UserDefaults`-Lesen). Ergebnis ist identisch zur Spec-Absicht (ein Storage-Key, eine Formatierungsmethode, app-weite Wirkung), nur der Lesezugriff unterscheidet sich technisch zwischen View- und Nicht-View-Kontexten.
- **Platzhalter-Scan:** Keine TBD/TODO-Stellen; alle Code-Blöcke sind vollständig.
- **Typkonsistenz:** `ArticleDateDisplayMode`, `ArticleListSummaryVisibilitySettings`, `ArticleListSummaryLineCount` werden in allen Tasks identisch benannt und referenziert.
