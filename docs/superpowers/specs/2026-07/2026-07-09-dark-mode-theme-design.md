# Echtes Dark Mode Theme

## Ziel

Zwei Dinge zusammen:

1. Eine eigene, App-interne Darstellungs-Einstellung (System / Hell / Dunkel)
   in Feedivo, unabhängig vom macOS-Systemschalter.
2. Die Stellen im UI beheben, die heute NICHT sauber auf Dark Mode reagieren
   (hartcodierte helle Farben statt Systemsemantik), damit Dark Mode wirklich
   überall konsistent aussieht — nicht nur "zufällig meistens".

## Bestandsaufnahme (Code)

- **Der Grossteil der App** (Sidebar, Artikelliste, Reader, `SidebarStyle.swift`,
  `FeedRowView.swift` etc.) nutzt bereits System-Semantikfarben
  (`Color.primary`, `Color.secondary`, `Color(nsColor: .controlBackgroundColor)`,
  `Color(nsColor: .textBackgroundColor)`) — diese passen sich automatisch an,
  ohne eigenes Zutun. Dark Mode "funktioniert" dort schon heute.
- **Die "Verwaltung"-Dialoge** (Regeln, Smart Folders, Tags, Organizer,
  OPML-Import/-Export) haben bereits ein fertiges, eigenes Light/Dark-
  Farbsystem: `RuleDialogTheme.swift` — eine Struct mit
  `init(colorScheme: ColorScheme)`, die feste Hex-Farb-Tokens für beide
  Farbschemata liefert (`bg`, `card`, `text`, `border`, `accent`, …). Dieses
  Muster ist der Vorbild-Referenz für Punkt 2 unten.
- **Kaputt/nicht angepasst sind zwei Stellen:**
  - `Feedivo/Views/FirstRun/FirstRunWizardView.swift`: ~9 Stellen mit
    hartcodiertem `Color.white.opacity(0.62–0.72)` als Kartenfläche (Icon-
    Badge in `welcomeStep`, Auswahlkarten `FirstRunChoiceCard`, Feed-
    Eingabezeile, OPML-Tabellenzeilen, Schritt-Leisten-Zeile `FirstRunStepRow`,
    Buttons `OPMLPrimaryButtonStyle`-artige Stile). Diese Flächen bleiben in
    Dark Mode strahlend weiss — der "Frosted-Glass"-Look kippt in einen
    hellen Fremdkörper auf dunklem Grund. Zusätzlich ein hartcodierter
    Blauton `Color(red: 0.18, green: 0.44, blue: 0.78)` (aktiver Auswahl-
    Button-Rand, Zeile ~1210).
    Bereits systemadaptiv (unverändert lassen): Hintergrund-Gradient-Basis
    (`Color(nsColor: .controlBackgroundColor)`), Ränder
    (`Color.secondary.opacity(...)`), Titelleisten-/Schienen-Hintergründe.
  - `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift`: ein
    hartcodierter fast-weisser Hintergrund
    (`SQLiteArticleInspectorStyle.background = Color(red: 0.94, green: 0.95,
    blue: 0.96)`, Zeile 5), bleibt in Dark Mode ein helles Panel im sonst
    dunklen Reader-Fenster.
- Etablierte Enum-Konvention für genau diese Art App-weiter Einstellung:
  `AppLanguage.swift` (`system`/`de`/`en`/`fr`/`it`, `@AppStorage`,
  `resolved(from:)`-Fabrikmethode, `titleKey: LocalizedStringKey`). Wird 1:1
  als Vorbild für `AppAppearance` übernommen.

## Entschieden (Nutzer-Freigabe 2026-07-09)

1. **Architektur der Darstellungs-Einstellung** — ✅ freigegeben:
   - Neues `AppAppearance`-Enum (`system` / `light` / `dark`,
     `CaseIterable`, `Identifiable`), Datei
     `Feedivo/Resources/AppAppearance.swift`, exakt nach `AppLanguage.swift`-
     Vorbild (`storageKey`, `defaultMode = .system`, `resolved(from:)`,
     `titleKey`).
   - `colorScheme: ColorScheme?`-Property: `.system` → `nil`, `.light` →
     `.light`, `.dark` → `.dark`.
   - In `FeedivoApp.swift`: neues `@AppStorage(AppAppearance.storageKey)`,
     `.preferredColorScheme(appAppearance.colorScheme)` auf allen 5 Scenes
     (WindowGroup, Artikelsuchfenster, Organizer-Fenster,
     `WindowGroup(for: ArticleWindowRequest.self)`, Settings) — analog zum
     bereits bestehenden Muster für `.environment(\.locale, ...)`.
   - Neue Zeile in Einstellungen → Anzeige, **oberste Zeile** im
     "Oberfläche"-Block (vor der Oberflächenschrift-Zeile):
     `NewSettingRow` mit 3-Wege-`Picker(...).pickerStyle(.segmented)`
     (System/Hell/Dunkel), exakt im Stil der bestehenden
     Oberflächenschrift-/Vorschaubild-Position-Zeilen.
   - Neue L10n-Keys: Picker-Titel + 3 Case-Titel (System/Hell/Dunkel),
     surgical in `Localizable.xcstrings` eingefügt (nicht per
     `json.dump` — siehe CLAUDE.md-Gotcha zu diesem Thema).

2. **First-Run-Assistent: eigenes Dark-Palette** — ✅ freigegeben (nicht nur
   funktionaler Fix, sondern gestalteter Dark-Ersatz):
   - Neue Struct `FirstRunTheme`, Datei
     `Feedivo/Views/FirstRun/FirstRunTheme.swift`, `init(colorScheme:
     ColorScheme)` nach `RuleDialogTheme`-Vorbild.
   - Tokens (Arbeitsnamen, exakte Hex-Werte werden beim Umsetzen gewählt,
     siehe unten "Nicht im Detail festgelegt"):
     - `card`: ersetzt jedes `Color.white.opacity(X)` — pro Aufrufstelle
       bleibt der bisherige Opacity-Wert (0.62/0.64/0.68/0.70/0.72)
       erhalten, nur die Basisfarbe wird vom Farbschema abhängig (hell:
       weiterhin `Color.white`, dunkel: ein dezent aufgehellter dunkler Ton,
       damit die Karte weiterhin als "erhöhte Glasfläche" vom dunklen
       Hintergrund absticht).
     - `activeIndicatorBorder`: ersetzt den hartcodierten Blauton
       `Color(red: 0.18, green: 0.44, blue: 0.78)` — bekommt ein etwas
       helleres/saturierteres Dark-Pendant für ausreichenden Kontrast auf
       dunklem Grund.
   - Alles, was schon `Color.secondary`/`Color(nsColor: ...)` nutzt, bleibt
     unverändert (bereits adaptiv).
   - `FirstRunWizardView.swift` bekommt `@Environment(\.colorScheme)` und
     berechnet `FirstRunTheme(colorScheme: colorScheme)` einmal als
     computed property, genutzt an allen ~9 betroffenen Stellen.

3. **Artikel-Metadaten-Inspector** — ✅ freigegeben (einfacher Fix, kein
   eigenes Theme):
   - `SQLiteArticleInspectorStyle.background` wird von
     `Color(red: 0.94, green: 0.95, blue: 0.96)` auf eine System-
     Semantikfarbe umgestellt (`Color(nsColor: .controlBackgroundColor)`
     oder `Color(nsColor: .underPageBackgroundColor)` — endgültige Wahl beim
     Umsetzen anhand eines Seite-an-Seite-Vergleichs im Reader-Fenster, da
     der Inspector optisch leicht vom Reader-Haupthintergrund abgesetzt sein
     soll, siehe bisheriges Design-Kalkül mit dem fast-weissen Ton).

## Nicht im Detail festgelegt (bewusst offen für die Umsetzung)

- Exakte Hex-/RGB-Werte für `FirstRunTheme.card` (dunkel) und
  `activeIndicatorBorder` (dunkel) — Nutzer hat sich explizit gegen eine
  Vorab-Farbwert-Freigabe entschieden ("passt so"), Wahl erfolgt beim
  Implementieren mit anschliessender visueller Verifikation (Screenshot-
  Vergleich Hell/Dunkel/System) statt separater Abstimmungsrunde.
- Exakte Systemsemantikfarbe für den Metadaten-Inspector-Hintergrund
  (`controlBackgroundColor` vs. `underPageBackgroundColor` vs. Alternative)
  — Wahl erfolgt beim Umsetzen per visuellem Vergleich.

## Testing / Verifikation

- Bestehende Testkonvention für Settings-Enums (siehe
  `appAccentColorSettings...`-artige Tests, die im Zuge der später wieder
  zurückgesetzten Akzentfarben-Arbeit entstanden waren, jetzt aber nicht mehr
  existieren): neuer Test `appAppearanceSettingsHatDreiFaelleSystemHellDunkel()`
  o.ä. in `FeedivoTests.swift`, prüft `AppAppearance.allCases.count == 3`,
  `defaultMode == .system`, `colorScheme`-Zuordnung pro Case.
- Manuelle Verifikation via computer-use:
  - Einstellungen → Anzeige → neuen Picker zwischen System/Hell/Dunkel
    umschalten, App-weite Reaktion prüfen (Sidebar, Artikelliste, Reader,
    First-Run-Assistent, Metadaten-Inspector).
  - First-Run-Assistent gezielt erneut anzeigen lassen zum Testen (State
    liegt in `@AppStorage(FirstRunWizardState.completionStorageKey)` in
    `ContentView.swift` — für den Test einmalig auf `false` zurücksetzen,
    z. B. via `defaults write ch.martin.Feedivo hasCompletedFirstRunWizard
    -bool false` oder Äquivalent, dann App neu starten).
  - "System"-Modus zusätzlich durch Umschalten der macOS-Systemeinstellung
    verifizieren (nicht nur der In-App-Einstellung), um sicherzugehen, dass
    `nil`-`colorScheme` wirklich durchgereicht wird und nicht versehentlich
    an einer Zwischen-Environment-Ebene hängen bleibt.
- `xcodebuild build` + gezielter Testlauf
  (`-only-testing:FeedivoTests/FeedivoTests`) vor Abschluss.

## Out of Scope

- Kein komplettes Redesign der "Verwaltung"-Dialoge (haben bereits ein
  Dark-Theme).
- Kein neues Farbschema für den Kernbereich (Sidebar/Artikelliste/Reader) —
  der ist bereits systemadaptiv und wird nicht angefasst, ausser dem einen
  Inspector-Hintergrund.
- Keine Wiedereinführung der zuvor zurückgesetzten App-weiten Akzentfarbe —
  komplett getrenntes Thema, hier nicht wieder aufgegriffen.
