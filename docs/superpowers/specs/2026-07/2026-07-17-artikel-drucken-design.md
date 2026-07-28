# Design: Artikel drucken (Feature 25.1)

**Datum:** 2026-07-17
**Status:** Vom Nutzer freigegeben, bereit für Implementierungsplan

## Ausgangslage

FEATURES.md Feature 25.1 „Drucken" ist als „✅ Entschieden — bereit zur Implementierung"
markiert, aber noch nicht gebaut. Ursprünglicher Anstoß war Feature 18.1c (PDF-Export):
`ArticlePDFExportRenderer` (`Feedivo/Services/ArticleDocumentExportRenderers.swift`) ist
bereits vollständig implementiert (baut gestylte HTML analog zum HTML-Export, konvertiert sie
über `NSAttributedString`/`CGContext` in ein paginiertes PDF), aber nie im Export-Dialog
erreichbar (`ArticleExportFormat.dialogFormats` enthält `.pdf` nicht) und ohne jede
Testabdeckung. Grund für das Zurückstellen laut FEATURES.md (Entscheidung 2026-06-26): „PDF-
Layout... braucht einen eigenen späteren Slice mit klarerem Layout-Anspruch."

**Root-Cause-Vermutung für die Layout-Qualität:** `NSAttributedString(data:options:
documentType:.html)` ist Apples alter, stark eingeschränkter HTML-Importer, der die meisten
modernen CSS-Regeln (Custom-Fonts, `max-width` bei Bildern, Farben aus `<style>`-Blöcken)
ignoriert — die im selben Renderer sorgfältig gebaute CSS kommt im tatsächlichen PDF
vermutlich kaum an.

**Recherche-Ergebnis (NetNewsWire, per `gh api`-Code-Suche + Web-Suche):** NetNewsWire hat
keinen eigenen PDF-Export gebaut. Stattdessen wurde kürzlich normales macOS-Drucken (⌘P,
natives Druck-Panel) ergänzt — „Als PDF sichern" kommt bei jedem macOS-Druckdialog automatisch
über den PDF-Dropdown-Button dazu, ganz ohne eigenen PDF-Renderer-Code.

## Entscheidungen (mit Nutzer geklärt)

- Statt eines eigenen PDF-Renderers wird **Feature 25.1 „Drucken" (⌘P)** gebaut — nach dem
  NetNewsWire-Vorbild. „PDF exportieren" ergibt sich automatisch über den Standard-PDF-Button
  jedes macOS-Druckdialogs, ohne zusätzlichen Code.
- **Druckinhalt folgt der aktuellen Reader-Ansicht** (kein zusätzlicher Umschalter im
  Druckdialog):
  - Reader auf „Nativ" → dieselbe gestylte HTML wie beim bestehenden HTML-Export wird gedruckt.
  - Reader auf „Web-Ansicht" (Original) → die tatsächlich angezeigte `WKWebView` wird 1:1
    gedruckt (inkl. eventueller Werbung/Navigation der Originalseite, falls vorhanden).
- Aktivierungsbedingung: nur wenn ein Artikel ausgewählt ist (identisch zu Teilen/Exportieren).
  Kein Sonderfall für einen Ladefehler in der Web-Ansicht — gedruckt wird, was gerade sichtbar
  ist (auch eine Fehlerseite).
- Der alte `NSAttributedString`/`CGContext`-basierte PDF-Renderteil in
  `ArticlePDFExportRenderer` wird entfernt (wird nach dieser Umstellung unerreichbarer toter
  Code: 0% Testabdeckung, war schon vorher nie im Dialog erreichbar). Der reine
  HTML-Bauteil (`html(for:options:style:assets:)`) bleibt bestehen und wird vom neuen
  Druck-Feature mitgenutzt.
- `.pdf`-Fall in `ArticleExportFormat`/`ArticleExportService.data(for:options:)` bleibt
  bestehen (nicht Teil dieser Aufgabe) — nur der jetzt tote Rendering-Codepfad
  (`ArticlePDFExportRenderer.data(for:options:style:assets:)`, `attributedString(fromHTML:)`,
  `pdfData(from:)`) wird entfernt. DOCX (Feature 18.1c zweiter Teil) bleibt vollständig
  unangetastet.

## Architektur

### Neuer Shortcut `.articlePrint`

`Feedivo/Models/CustomizableShortcut.swift`: neuer Fall `articlePrint`, Kategorie `.article`,
Standard `KeyboardShortcutSpec(key: "p", modifiers: [.command])` (kein Konflikt gefunden — kein
bestehender Shortcut nutzt „p"), `titleKey: L10n.shortcutsLabelArticlePrint`. Neuer L10n-Key
`shortcuts.label.articlePrint` + `article.print.command` (Button-Text).

### Toolbar-Button in `SQLiteReaderView`

Neuer Druck-Button (SF Symbol `printer`) im Reader-Toolbar, direkt neben den bestehenden
Vor-/Zurück-Buttons für die Web-Ansicht — **exakt nach demselben Muster wie
`readerWebBack`/`readerWebForward`**: `.customizableKeyboardShortcut(.articlePrint,
overrides: shortcutOverrides)` sitzt direkt am Button in `SQLiteReaderView`, NICHT über das
`ArticleCommandActions`/`ContentView`-Commands-System — weil nur `SQLiteReaderView` Zugriff auf
die lebende `WebNavigationController`/`WKWebView`-Instanz hat, dieselbe Begründung wie bei den
bestehenden Web-Navigations-Buttons. Deaktiviert, wenn kein Artikel ausgewählt ist
(`selectedSQLiteArticleID == nil`, analog zu den bestehenden Toolbar-Buttons dort).

### Druck-Logik

Neue Funktion `printCurrentArticle()` in `SQLiteReaderView.swift`:

```swift
private func printCurrentArticle() {
    switch readerDisplayMode {
    case .web:
        guard let webView = webNavigationController.webView else { return }
        let printInfo = NSPrintInfo.shared
        let operation = webView.printOperation(with: printInfo)
        operation.run()
    case .native:
        guard let snapshot = state.snapshot else { return }
        let html = ArticlePDFExportRenderer.html(
            for: ArticleExportSnapshot(sqliteSnapshot: snapshot, tagNames: snapshot.tags.map(\.name)),
            options: ArticleExportOptions(format: .html, includesMetadata: true),
            style: .default,
            assets: []
        )
        let printWebView = WKWebView(frame: .zero)
        // lädt HTML, druckt nach didFinish via WKNavigationDelegate-Callback
        // (Details/genaue Delegate-Struktur im Implementierungsplan)
    }
}
```

`WebNavigationController.webView` ist aktuell `fileprivate` (siehe
`Feedivo/Views/Reader/WebContentView.swift`) — muss auf `internal` angehoben werden, damit
`SQLiteReaderView` (bereits im selben Modul, aber anderer Datei) lesend zugreifen kann. Analog
zum bereits in dieser Session gemachten Schritt bei `SidebarOutlineViewControl`.

**Offscreen-WKWebView für die native Ansicht:** Da `WKWebView.printOperation(with:)` erst nach
vollständigem Laden sinnvolle Ergebnisse liefert, muss die native-Modus-Druckfunktion auf den
`WKNavigationDelegate`-Callback `didFinish` warten, bevor `printOperation(with:)` aufgerufen
wird — die Offscreen-WebView muss dafür so lange retained werden (z. B. als
`@State`-Property in `SQLiteReaderView`), bis der Druckvorgang beendet ist. Exakte
Delegate-/State-Struktur wird im Implementierungsplan ausformuliert.

### Aufräumen in `ArticleDocumentExportRenderers.swift`

Entfernt: `data(for:options:style:assets:)` (der `.pdf`-Renderpfad, ruft aktuell `data(fromHTML:)`
auf), `data(fromHTML:)`, `attributedString(fromHTML:)`, `pdfData(from:)`. Bleibt: die
`html(for:options:style:assets:)`-Funktionsfamilie (jetzt vom Druck-Feature genutzt) sowie alle
Hilfsfunktionen, die die HTML-Generierung unterstützen (`bodyHTML`, `removingFirstH1`,
`readerHeaderHTML`, `exportMetadataHTML`, `mimeType` etc.).

`ArticleExportService.data(for:options:)`s `.pdf`-Fall muss entsprechend angepasst werden, da
`ArticlePDFExportRenderer.data(for:options:)` nicht mehr existiert — da `.pdf` weiterhin nicht
in `dialogFormats` erreichbar ist, bleibt dieser Codepfad aktuell unerreichbar; exakte
Behandlung (z. B. `fatalError`/leere `Data`/Kommentar „nicht erreichbar, siehe
dialogFormats") wird im Implementierungsplan entschieden.

## Testing

- `CustomizableShortcut`-Erweiterung (`.articlePrint`, Kategorie, `defaultSpec`) ist über
  bestehende Tests zu `CustomizableShortcut` abgesichert (analog zu bereits vorhandenen
  Fällen).
- Reine Druck-Logik (WKWebView-Aufruf, `NSPrintOperation`) ist wie bei den bestehenden
  Web-Navigations-Buttons nicht automatisiert testbar (kein ViewInspector, kein Zugriff auf
  echten Druckdialog aus Unit-Tests) — Verifikation über Build + manuelle Live-Checkliste.
- Entfernter Code (`ArticlePDFExportRenderer.data`/`attributedString(fromHTML:)`/`pdfData(from:)`)
  hatte laut CLAUDE.md-Historie ohnehin 0% Testabdeckung — keine Tests zu entfernen.

**Manuelle Live-Verifikationscheckliste:**
1. Artikel in nativer Ansicht auswählen, ⌘P drücken (oder Drucken-Button klicken) — nativer
   macOS-Druckdialog erscheint mit demselben Layout wie die HTML-Export-Vorschau.
2. Im Druckdialog unten links „PDF" → „Als PDF sichern…" — erzeugt eine lesbare PDF-Datei mit
   korrekten Fonts/Bildgrößen (im Gegensatz zum alten Renderer).
3. Artikel zur Web-Ansicht wechseln, ⌘P drücken — Druckdialog zeigt die tatsächliche
   Originalseite, nicht die Reader-Aufbereitung.
4. Kein Artikel ausgewählt: Drucken-Button/Shortcut deaktiviert.
5. Shortcut ⌘P ist über die bestehende Shortcuts-Einstellungsseite umbenennbar/deaktivierbar,
   wie alle anderen anpassbaren Shortcuts.
6. Mehrseitiger Artikel (langer Text): Druckvorschau zeigt korrekte Seitenumbrüche (natives
   WebKit-Pagination statt der alten manuellen NSLayoutManager-Paginierung).

## Out of Scope

- DOCX-Export (Feature 18.1c, zweiter Teil) — bleibt vollständig unangetastet.
- `.pdf`-Format-Option im bestehenden Export-Sheet (Kontextmenü/Toolbar-Export-Dialog) — wird
  nicht ergänzt, PDF kommt ausschließlich über den Druckdialog.
- Eigener Umschalter „Reader-Darstellung vs. Original" innerhalb des Druckdialogs — folgt
  stattdessen automatisch der aktuellen Reader-Ansicht.
- Metadaten-Toggle im Druckdialog selbst — die native Ansicht druckt immer mit Metadaten
  (`includesMetadata: true`), analog zum Standard-Verhalten des bestehenden HTML-Exports.
