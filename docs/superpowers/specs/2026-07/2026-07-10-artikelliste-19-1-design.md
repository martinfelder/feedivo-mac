# Design: Feature 19.1 „Artikel-Liste anpassen" fertigstellen

**Datum:** 2026-07-10
**Status:** Genehmigt, bereit für Implementierungsplan

## Kontext

Feature 19.1 („Artikel-Liste anpassen") ist laut `FEATURES.md` teilweise umgesetzt.
Bereits fertig (2026-07-08): Vorschaubild anzeigen/ausblenden, Vorschaubild-Position
(Links/Rechts/Aus), Feed-Name anzeigen/ausblenden, Feed-Name-Position
(vor/nach Titel, inkl. Favicon).

Noch offen laut `FEATURES.md`:
1. Vorschautext-Zeilen: 0–3 (Stepper)
2. Summary anzeigen/ausblenden
3. Datum-Format: relativ vs. absolut wählbar
4. Ungelesen-Markierung: fetter Text + farbiger Punkt (beides zusammen)

Dieses Dokument spezifiziert die Umsetzung von Punkt 1–3. Punkt 4 stellt sich beim
Code-Abgleich als bereits umgesetzt heraus (siehe „Nicht umzusetzen" unten) und wird
nur dokumentarisch nachgezogen.

## Bestehende Architektur (Vorbild)

`Feedivo/Views/ArticleList/ArticleListDisplaySettings.swift` enthält je Einstellung
einen eigenen Typ mit `storageKey`, `defaultXxx` und ggf. `resolved(from:)` für
robustes Decodieren aus `@AppStorage`. `ArticleRowView.swift` liest diese Keys per
`@AppStorage` und rendert konditional. `SettingsView.swift` bindet sie in der
`NewSettingsBlock(eyebrow: "Artikelliste")`-Sektion über `NewSettingRow` +
`Toggle`/`Picker(.segmented)` ein. Diese Arbeit folgt demselben Muster 1:1.

## 1. Summary-Anzeige (Toggle + Stepper)

**Neue Settings-Typen** in `ArticleListDisplaySettings.swift`:

```swift
/// Ob die Artikel-Zusammenfassung in der Artikelliste angezeigt wird (Feature 19.1).
enum ArticleListSummaryVisibilitySettings {
    static let showsSummaryKey = "articleList.showsSummary"
    static let defaultShowsSummary = true
}

/// Anzahl der Vorschautext-Zeilen der Summary in der Artikelliste (Feature 19.1).
enum ArticleListSummaryLineCount {
    static let storageKey = "articleList.summaryLineCount"
    static let defaultValue = 2
    static let allowedRange = 1...3

    static func resolved(from storedValue: Int) -> Int {
        allowedRange.contains(storedValue) ? storedValue : defaultValue
    }
}
```

**`ArticleRowView.swift`:** Die Summary-`Text`-View wird nur gerendert, wenn
`showsSummary == true`. `.lineLimit(2)` (hartcodiert) wird durch
`.lineLimit(ArticleListSummaryLineCount.resolved(from: summaryLineCount))` ersetzt.

**`SettingsView.swift`:** Zwei neue `NewSettingRow`s in der „Artikelliste"-Sektion,
direkt nach der Feedname-Position-Zeile:
- Toggle „Zusammenfassung anzeigen"
- Stepper „Zeilen: 1–3", `.disabled(!showsSummary)` wenn der Toggle aus ist

Default-Werte entsprechen dem heutigen (hartcodierten) Verhalten — kein Verhaltens-
sprung für Bestandsnutzer nach dem Update.

## 2. Datum-Format (relativ / absolut, app-weit)

**Neuer Enum** in `ArticleListDisplaySettings.swift` (Ursprung ist die Artikelliste,
Wirkung ist app-weit — siehe Begründung unten):

```swift
enum ArticleDateDisplayMode: String, CaseIterable, Identifiable {
    case relative
    case absolute

    static let storageKey = "articleList.dateDisplayMode"
    static let defaultMode = ArticleDateDisplayMode.relative

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .relative: L10n.articleDateDisplayModeRelative
        case .absolute: L10n.articleDateDisplayModeAbsolute
        }
    }

    static func resolved(from rawValue: String) -> ArticleDateDisplayMode {
        ArticleDateDisplayMode(rawValue: rawValue) ?? defaultMode
    }
}
```

**Verhalten:**
- `.relative` (Standard, = heutiges Verhalten unverändert): heute → relative Formulierung
  ("vor 2 Stunden"), älter → kurzes Datum ("23.06.2026")
- `.absolute`: immer kurzes Datum, auch für heutige Artikel — keine relative
  Formulierung mehr

**`Date+RelativeDisplay.swift`:** Neue Methode `feedivoDisplay(mode:)` ergänzt, die
für `.relative` die bestehende Logik wiederverwendet und für `.absolute` direkt den
(dafür intern zugänglich gemachten) `shortDateFormatter` nutzt. Die bestehende
Property `feedivoRelativeDisplay` bleibt als Alias für `.relative` erhalten, um
keine unbekannten Call-Sites zu brechen.

**App-weite Wirkung — betroffene Call-Sites:**
- `Feedivo/Views/ArticleList/ArticleRowView.swift`
- `Feedivo/Views/Reader/ReaderMetadataFormatter.swift` (Reader-Metadatenzeile)
- `Feedivo/Views/Sidebar/SidebarView.swift` (Feed-Vorschau)
- `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift`

Jede dieser Stellen liest den Modus über `@AppStorage(ArticleDateDisplayMode.storageKey)`
und ruft `feedivoDisplay(mode:)` statt der alten Property auf.

**Neue Settings-Zeile** in der „Artikelliste"-Sektion: Picker (`.segmented`, wie beim
Bildposition-Picker) mit den zwei Optionen.

## 3. L10n-Keys

Neu in `L10n.swift` + `Localizable.xcstrings` (de/en/fr/it):
- `settingsArticleListShowsSummaryTitle` / `settingsArticleListShowsSummaryDescription`
- `settingsArticleListSummaryLineCountTitle` / `settingsArticleListSummaryLineCountDescription`
- `settingsArticleListDateDisplayModeTitle` / `settingsArticleListDateDisplayModeDescription`
- `articleDateDisplayModeRelative`, `articleDateDisplayModeAbsolute`

## Nicht umzusetzen: Ungelesen-Markierung

`FEATURES.md` listet „Ungelesen-Markierung: fetter Text + farbiger Punkt (beides
zusammen)" als offenen Punkt. Der Code-Abgleich zeigt: `ArticleRowView.swift` kombi-
niert bereits heute unconditional fetten Titel (`.semibold` bei ungelesen) und
farbigen Punkt (blauer Kreis bei ungelesen) — exakt die in FEATURES.md beschriebene
Ziel-Kombination. Es gibt keine gegenläufige Alternative im Code, die entfernt werden
müsste. Kein Implementierungs-Task nötig; `FEATURES.md` wird im Rahmen dieser Arbeit
von „noch offen" auf „✔️ bereits umgesetzt" korrigiert.

## Testing

- Unit-Tests für `ArticleDateDisplayMode.resolved(from:)` (Fallback bei ungültigem
  Rohwert) und `Date.feedivoDisplay(mode:)` (beide Modi, inkl. Grenzfall „heute" vs.
  „gestern")
- Unit-Tests für `ArticleListSummaryLineCount.resolved(from:)` (Clamping außerhalb
  1...3)
- Bestehende artikellisten-nahe Test-Suiten um Fälle für Summary-Toggle/Stepper
  ergänzen
- Manuelle Verifikation (kein computer-use für native macOS-Apps in dieser Umgebung
  verfügbar): Summary-Stepper-Grenzen (1/3) visuell, Datum-Format-Umschaltung sichtbar
  in Artikelliste **und** Sidebar **und** Reader-Inspector

## Out of Scope

- Keine Änderung an bestehenden, bereits umgesetzten 19.1-Unterpunkten
  (Bildposition, Feedname-Position/-Sichtbarkeit)
- Keine Uhrzeit-Komponente im absoluten Datum-Format (bleibt reines Kurzdatum,
  konsistent mit dem bestehenden `shortDateFormatter`)
- Keine neue Wahlmöglichkeit für die Ungelesen-Markierung (siehe oben)
