# OPML-Import-Dialog auf "Konzept A" migrieren

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `OPMLImportReviewView.swift` visuell auf dasselbe Designsystem ("Konzept A" / `RuleDialogTheme`) heben wie `OPMLExportSheet.swift` (migriert am 2026-07-08), damit Import- und Export-Dialog nicht mehr wie zwei verschiedene Apps aussehen.

**Kontext:** Nutzer-Vergleich der beiden Dialoge ergab, dass der Export-Dialog bereits vollständig auf `RuleDialogTheme` (feste Hex-Farb-Tokens, Konzept-A-Typografie, themed Hairline-Dividers) migriert wurde, der Import-Dialog aber auf der alten, ad-hoc gestylten Optik verblieb (System-Semantikfarben + "Frosted-Glass"-`LinearGradient`s). Ein vorheriger Task hat den Import-Dialog nur soweit repariert, dass er in Dark Mode nicht mehr weiß aufblitzt (`Color.frostedCard(for:)` statt `Color.white`) — das behebt NICHT die grundsätzliche Stil-Divergenz zum Export-Dialog. Dieser Plan schließt diese Lücke.

**Architecture:** `OPMLImportReviewView` bekommt `let theme = RuleDialogTheme(colorScheme: colorScheme)` (Environment `colorScheme` existiert bereits aus dem vorherigen Dark-Mode-Fix) lokal in jeder betroffenen computed property — keine Umstellung der computed vars zu Funktionen mit `theme:`-Parameter nötig (kleinerer Diff, RuleDialogTheme-Init ist eine billige Struct-Konstruktion). `OPMLSecondaryButtonStyle`/`OPMLPrimaryButtonStyle` bekommen einen `theme: RuleDialogTheme`-Stored-Property (analog zu anderen theme-parametrisierten Bausteinen in `RuleDialogTheme.swift`) statt hartcodierter Farben. Checkbox-Toggles im Footer werden auf das etablierte `RuleDialogCheckbox`+`Text`-Wrapping-Muster umgestellt (siehe `SmartFolderEditorView.swift:136-144`, `RuleSettingsView.swift:400-406`).

**Explizit AUSSER Scope (bewusste Entscheidung, nicht vergessen):**
- `OPMLImportFeedRow.swift` — geteilt mit `FirstRunWizardView.swift` (First-Run übergibt kein `theme:`, nutzt eigenes `FirstRunTheme`). Bleibt auf neutralen Systemfarben (`.controlBackgroundColor`, `.orange`/`.green`/`.red`), funktioniert bereits in beiden Kontexten korrekt. Eine Migration hier würde First-Run's separat geshippten Dark-Mode-Fix riskieren.
- Native `Picker` (Status-Filter) und `TextField` (neuer Ordnername) bleiben native macOS-Controls — nur ihr umgebendes Chrome (Hintergrund/Rand) wird auf Theme-Tokens umgestellt, kein Nachbau als `RuleDialogSelectMenu`/`RuleDialogTextField` (die sind für andere Kontexte gebaut — feste Enum-Optionen bzw. reine Textfelder ohne Live-Filterung/Keyboard-Nav-Anforderungen).
- `resultMessage`/`errorMessage`-Banner (grün/rot) und `OPMLImportFeedRow`-Statusfarben bleiben System-Semantikfarben (Erfolg/Fehler-Bedeutung, keine Marken-/Chrome-Farbe) — nicht auf `theme.accent` o.ä. umstellen.
- `fileImporter`/`onDrop`-Mechanik unverändert (rein visuelle Migration, kein Verhalten ändert sich).

**Tech Stack:** SwiftUI, `RuleDialogTheme` (bestehend, `Feedivo/Views/Rules/RuleDialogTheme.swift`), Swift Testing.

## Global Constraints

- Kommentare im Code auf Deutsch.
- SourceKit-Diagnosen nach Edits sind oft veraltete Zustände — nur ein echter `xcodebuild build`-Lauf ist verlässlich.
- Gezielt testen: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO` (kein unscoped `xcodebuild test`, das hängt bekanntermaßen).
- Reiner visueller Refactor — kein neues Verhalten, keine neuen Tests erforderlich (analog zu Task 2 des ursprünglichen Dark-Mode-Plans). Regressionscheck via bestehender Testsuite reicht.
- Bekannte, dauerhaft vorbestehende Testfehlschläge (5 in `FeedivoAppSceneConfigurationTests.swift`, 2 in `FeedViewModelTests.swift`) nicht als neuen Bug behandeln.
- Manuelle visuelle Verifikation (Hell/Dunkel, Seite an Seite mit Export-Dialog) kann NICHT automatisiert werden (kein computer-use für native macOS-Apps verfügbar) — muss vom Nutzer nach Abschluss selbst geprüft werden.

---

### Task 1: Dialog-Rahmen, Header, Divider auf Konzept A

**Files:**
- Modify: `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift` (`body`, `header`, Divider nach Header)

**Interfaces:**
- Konsumiert: `RuleDialogTheme(colorScheme:)` (bestehend, `Feedivo/Views/Rules/RuleDialogTheme.swift`), `colorScheme`-Environment (bereits vorhanden aus vorherigem Dark-Mode-Fix).

- [ ] **Step 1: Root-Hintergrund umstellen**

In `body` (aktuell Zeilen 27-71): `LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor)], ...)` als `.background(...)`-Modifier ersetzen durch `.background(RuleDialogTheme(colorScheme: colorScheme).bg)`. `.clipShape(RoundedRectangle(cornerRadius: 12))` und `.frame(width: 1080, height: 720)` unverändert lassen (funktionale Größenvorgabe, kein Style-Aspekt).

- [ ] **Step 2: Header-Typografie und -Hintergrund auf Konzept A**

In `header` (aktuell Zeilen 73-99):
- `let theme = RuleDialogTheme(colorScheme: colorScheme)` als erste Zeile im computed var ergänzen.
- Titel: `.font(.system(size: 18, weight: .semibold))` → `.font(.system(size: 21, weight: .bold)).tracking(-0.3)`, `.foregroundStyle(theme.text)` ergänzen (Vorbild: `OPMLExportSheet.swift:99-102`).
- Beschreibung: `.font(.system(size: 13))` → `.font(.system(size: 13.5))`, `.foregroundStyle(.secondary)` → `.foregroundStyle(theme.text2)` (Vorbild: `OPMLExportSheet.swift:104-108`).
- Padding: `.padding(.horizontal, 20).padding(.vertical, 17)` → `.padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 20)` (Vorbild: `OPMLExportSheet.swift:121-123`).
- `.background(LinearGradient(colors: [Color.frostedCard(for: colorScheme).opacity(0.58), Color(nsColor: .controlBackgroundColor).opacity(0.94)], ...))` komplett entfernen — Export-Header hat KEINEN eigenen Hintergrund, sitzt flach auf `theme.bg` vom Dialog-Root.

- [ ] **Step 3: Divider nach Header themen**

Direkt nach `header` in `body` (aktuell `Divider()` nach `header`, vor `content`): ersetzen durch `Rectangle().fill(RuleDialogTheme(colorScheme: colorScheme).border).frame(height: 1)` (Vorbild: `OPMLExportSheet.swift:69-71`).

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/OPMLImport/OPMLImportReviewView.swift
git commit -m "OPML-Import Konzept A: Dialog-Rahmen, Header, Divider"
```

---

### Task 2: Datei-Auswahlzeile, Toolbar, Buttons auf Konzept A

**Files:**
- Modify: `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift` (`filePicker`, `toolbar`, `OPMLSecondaryButtonStyle`, `OPMLPrimaryButtonStyle`, alle 7 Aufrufstellen der beiden ButtonStyles)

**Interfaces:**
- `OPMLSecondaryButtonStyle` und `OPMLPrimaryButtonStyle` bekommen je einen neuen Stored-Property `let theme: RuleDialogTheme` — Breaking Change für alle Aufrufstellen, die jetzt `OPMLSecondaryButtonStyle(theme: theme)`/`OPMLPrimaryButtonStyle(theme: theme)` statt `OPMLSecondaryButtonStyle()`/`OPMLPrimaryButtonStyle()` übergeben müssen (7 Stellen: Zeilen 229, 235, 288, 294, 307 für Secondary in `filePicker`/`toolbar`, Zeile 434 Secondary + 438 Primary im `footer`, siehe Task 3).

- [ ] **Step 1: `filePicker`-Karte auf Konzept A**

In `filePicker` (aktuell Zeilen 199-253):
- `let theme = RuleDialogTheme(colorScheme: colorScheme)` als erste Zeile ergänzen.
- "OPML"-Badge: `.foregroundStyle(.blue)` → `.foregroundStyle(theme.accent)`, `.background(Color.blue.opacity(0.12), ...)` → `.background(theme.accent.opacity(0.12), ...)`, `.stroke(Color.blue.opacity(0.14))` → `.stroke(theme.accent.opacity(0.14))`.
- Card-Hintergrund: `LinearGradient(colors: [Color.frostedCard(for: colorScheme).opacity(0.74), Color(nsColor: .controlBackgroundColor).opacity(0.88)], ...)` → `theme.card` (flaches Fill, kein Verlauf, Vorbild: `OPMLExportSheet.swift:216-219`).
- Rand: `.stroke(Color.secondary.opacity(0.18))` → `.stroke(theme.border)`.
- Beide `Button(...).buttonStyle(OPMLSecondaryButtonStyle())`-Aufrufe (Zeilen 229, 235) → `.buttonStyle(OPMLSecondaryButtonStyle(theme: theme))`.

- [ ] **Step 2: `toolbar`-Suchbox auf Konzept A**

In `toolbar` (aktuell Zeilen 255-309):
- `let theme = RuleDialogTheme(colorScheme: colorScheme)` als erste Zeile ergänzen.
- Suchbox-Hintergrund: `.background(Color.frostedCard(for: colorScheme).opacity(0.82), ...)` → `.background(theme.input, ...)` (Vorbild: `OPMLExportSheet.swift:204-207`, Dateiname-Vorschau-Box).
- Rand: `.stroke(Color.secondary.opacity(0.16))` → `.stroke(theme.border)`.
- Alle vier `Button(...).buttonStyle(OPMLSecondaryButtonStyle())`-Aufrufe (selectAll, deselectAll, createFolder — Zeilen 288, 294, 307) → `.buttonStyle(OPMLSecondaryButtonStyle(theme: theme))`.

- [ ] **Step 3: `OPMLSecondaryButtonStyle` umbauen**

Aktuell (Zeilen 503-517):
```swift
private struct OPMLSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Color.frostedCard(for: colorScheme).opacity(configuration.isPressed ? 0.62 : 0.9), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.18))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
```
Neu (Vorbild: `OPMLExportSheet.swift`s Cancel-Button, Zeilen 256-275):
```swift
private struct OPMLSecondaryButtonStyle: ButtonStyle {
    let theme: RuleDialogTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(
                (configuration.isPressed ? theme.card : theme.card2),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(theme.border)
            )
            .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
```
(Entfernt das jetzt tote `@Environment(\.colorScheme) private var colorScheme` aus dieser Struct — `theme` kommt jetzt von außen rein, kein eigenes Environment-Reading mehr nötig.)

- [ ] **Step 4: `OPMLPrimaryButtonStyle` umbauen**

Aktuell (Zeilen 519-535):
```swift
private struct OPMLPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                (isEnabled ? Color.accentColor : Color.secondary.opacity(0.45))
                    .opacity(configuration.isPressed ? 0.82 : 1),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
```
Neu (Vorbild: `OPMLExportSheet.swift`s Save-Button, Zeilen 277-294):
```swift
private struct OPMLPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let theme: RuleDialogTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                (isEnabled ? theme.accent : Color.secondary.opacity(0.45))
                    .opacity(configuration.isPressed ? 0.82 : 1),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .shadow(color: theme.accent.opacity(isEnabled ? 0.45 : 0), radius: 1.5, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
```

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -30`
Expected: Fehler, da Task 3 (footer-Aufrufstellen von `OPMLSecondaryButtonStyle()`/`OPMLPrimaryButtonStyle()` ohne `theme:`) noch nicht angepasst ist — das ist erwartet, Task 3 löst das auf. Falls Task 2 und 3 in einem Rutsch umgesetzt werden (empfohlen, da sonst Zwischenstand nicht buildet), diesen Step überspringen und erst nach Task 3 Step 2 bauen.

- [ ] **Step 6: Commit**

Nur zusammen mit Task 3 committen (sonst buildet der Zwischenstand nicht, siehe Step 5) — Commit-Schritt steht in Task 3.

---

### Task 3: Footer-Toggles, Feed-Tabellen-Chrome, finale Verifikation

**Files:**
- Modify: `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift` (`footer`, `feedTable`, `tableHeader`, `dropOverlay`)
- Modify: `FEATURES.md`

**Interfaces:**
- Keine neuen Interfaces — Rest der Theme-Migration + Dokumentation.

- [ ] **Step 1: Footer-Toggles auf `RuleDialogCheckbox` umstellen**

In `footer` (aktuell Zeilen 419-442):
- `let theme = RuleDialogTheme(colorScheme: colorScheme)` als erste Zeile ergänzen.
- Alle drei `Toggle(L10n.xxx, isOn: $previewController.xxx).toggleStyle(.checkbox)` (refreshAfterImport, allowsDuplicates, allowsUnreachable) ersetzen durch das etablierte Checkbox+Label-Muster (Vorbild: `SmartFolderEditorView.swift:136-144`):
```swift
Button {
    previewController.refreshAfterImport.toggle()
} label: {
    HStack(spacing: 8) {
        RuleDialogCheckbox(isOn: previewController.refreshAfterImport, theme: theme)
        Text(L10n.opmlImportRefreshAfter)
            .font(.system(size: 13))
            .foregroundStyle(theme.text)
    }
}
.buttonStyle(.plain)
```
(analog für `allowsDuplicates`/`opmlImportAllowDuplicates` und `allowsUnreachable`/`opmlImportAllowUnreachable`).
- Cancel-Button (Zeile 434): `.buttonStyle(OPMLSecondaryButtonStyle())` → `.buttonStyle(OPMLSecondaryButtonStyle(theme: theme))`.
- Import-Button (Zeile 438): `.buttonStyle(OPMLPrimaryButtonStyle())` → `.buttonStyle(OPMLPrimaryButtonStyle(theme: theme))`.
- `.padding(18)` → `.padding(.horizontal, 26).padding(.vertical, 16)` (Konsistenz mit Header-Padding aus Task 1).
- `.background(Color(nsColor: .controlBackgroundColor).opacity(0.9))` komplett entfernen (Export-Footer hat keinen eigenen Hintergrund, sitzt flach auf `theme.bg`).
- Divider VOR footer (aktuell `Divider()` zwischen `content` und `footer` in `body`) → `Rectangle().fill(theme.border).frame(height: 1)` (wie Task 1 Step 3, gleiche Behandlung).

- [ ] **Step 2: Feed-Tabellen-Chrome auf Konzept A**

In `feedTable` (aktuell Zeilen 311-346):
- `let theme = RuleDialogTheme(colorScheme: colorScheme)` als erste Zeile ergänzen.
- `.background(Color(nsColor: .textBackgroundColor))` → `.background(theme.bg)`.
- `.stroke(Color.secondary.opacity(0.18))` → `.stroke(theme.border)`.

In `tableHeader` (aktuell Zeilen 348-367):
- `let theme = RuleDialogTheme(colorScheme: colorScheme)` als erste Zeile ergänzen.
- `.foregroundStyle(.secondary)` → `.foregroundStyle(theme.text2)`.
- `.background(Color(nsColor: .controlBackgroundColor))` → `.background(theme.card)`.

In `dropOverlay` (aktuell Zeilen 177-197): `Color.accentColor` (2 Stellen: `.stroke(...)`, `.background(...)`, `.foregroundStyle(...)`) → `RuleDialogTheme(colorScheme: colorScheme).accent`.

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **` (jetzt buildet der volle Zwischenstand inkl. Task 2).

- [ ] **Step 4: Verifizieren, dass keine hartcodierten Rest-Farben übrig sind**

Run: `grep -n "Color.white\|Color.frostedCard\|Color.blue\|Color.accentColor\|Color(nsColor: \.controlBackgroundColor)\|Color(nsColor: \.textBackgroundColor)\|Color.secondary.opacity(0\.1[68])" Feedivo/Views/OPMLImport/OPMLImportReviewView.swift`
Expected: keine Treffer mehr außer ggf. in `statusBadge`/`resultMessage`/`errorMessage`/`OPMLImportFeedRow`-Bezügen, die laut Plan bewusst System-Semantikfarben behalten (siehe "Explizit außer Scope").

- [ ] **Step 5: Gezielter Testlauf (Regressionscheck)**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, keine neuen Fehlschläge gegenüber dem bekannten Stand.

- [ ] **Step 6: Manuelle visuelle Verifikation (kann nicht automatisiert werden)**

Import-Dialog öffnen (z. B. über den Feed-Hinzufügen-Flow oder direkten Menüpunkt), Seite an Seite mit dem Export-Dialog vergleichen, in Hell UND Dunkel: Header-Typografie, Divider-Optik, Button-Stil, Checkbox-Stil sollten jetzt identisch wirken. Kein computer-use für native macOS-Apps in dieser Umgebung verfügbar — das muss der Nutzer selbst prüfen.

- [ ] **Step 7: FEATURES.md aktualisieren**

Neuen Abschnitt analog zu Feature 19.7 (Dark Mode) ergänzen: OPML-Import-Dialog auf "Konzept A" migriert, visuelle Parität mit Export-Dialog hergestellt, Datum 2026-07-09, Verweis auf diesen Plan. `OPMLImportFeedRow.swift` explizit als bewusst ausgenommen dokumentieren (geteilt mit First-Run-Assistent).

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Views/OPMLImport/OPMLImportReviewView.swift FEATURES.md
git commit -m "OPML-Import Konzept A: Footer, Feed-Tabelle, finale Angleichung an Export-Dialog"
```

---

## Self-Review (durchgeführt beim Schreiben dieses Plans)

- **Scope-Abgrenzung:** `OPMLImportFeedRow.swift` bewusst ausgenommen (geteilt mit First-Run, Risiko einer Regression im bereits geshippten First-Run-Dark-Mode-Fix) — in jedem Task explizit dokumentiert, kein stiller Ausschluss.
- **Kein Griff zu `RuleDialogButton`:** verifiziert, dass auch `OPMLExportSheet.swift` selbst keine `RuleDialogButton`-Instanzen nutzt (eigene Button-Chrome inline) — Konsistenz mit dem tatsächlichen Vorbild, nicht mit einer angenommenen "sollte doch"-Abstraktion.
- **L10n-Typkompatibilität geprüft:** sowohl `L10n.opmlImportChooseFile` als auch `L10n.opmlExportSaveButton` sind `String(localized:)`, keine `LocalizedStringKey` — keine Typkonflikte beim Umbau der Button-Styles zu erwarten.
- **Build-Reihenfolge Task 2/3:** Task 2 ändert die Signatur beider ButtonStyle-Structs, aber nicht alle 7 Aufrufstellen (die 3 im Footer liegen in Task 3) — Plan weist explizit darauf hin, dass der Zwischenstand nach Task 2 allein nicht baut, und empfiehlt gemeinsame Umsetzung.
