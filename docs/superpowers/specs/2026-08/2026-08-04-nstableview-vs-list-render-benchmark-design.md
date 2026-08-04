# Artikelliste: NSTableView-vs-List-Render-Benchmark — Design

Stand: 2026-08-04

## Kontext und Motivation

Nutzer-Eindruck: Die Darstellung/das Rendern der Artikelliste in Feedivo
wirkt gegenüber NetNewsWire viel langsamer. Der bestehende Vergleichsbericht
`docs/performance/netnewswire-feedivo-mechanik-vergleich.md` (Update
2026-07-28) benennt den größten verbleibenden Architekturunterschied: NNW
nutzt `NSTableView` (AppKit) mit echter Zellwiederverwendung und einer
einmalig berechneten, festen Zeilenhöhe; Feedivo nutzt SwiftUI `List` mit
`ArticleRowView`. Die "schnellen, hoher Impact"-Empfehlungen aus diesem
Bericht (feste Zeilenhöhe, gezieltere Invalidierung, Statement-Caching,
Content-Hash-Skip) sind bereits umgesetzt (2026-07-28). Ein direkter Wechsel
auf `NSTableView` wurde damals bewusst zurückgestellt, mit der Empfehlung,
erst zu messen. Dieser Plan setzt genau dort an.

**Zielsymptome (Nutzerentscheidung):** (1) Scroll-Ruckeln in der
Artikelliste, (2) Latenz beim Wechseln von Feed/Ordner/Smart Folder. Ein
dritter Kandidat (Reaktionszeit bei Statusänderungen wie Gelesen/Stern) ist
bewusst **nicht** Teil dieses Spikes — die dafür nötige Diff-/Teilreload-Logik
(analog NNWs `representSameArticlesInSameOrder`) wäre ein separates,
größeres Thema.

## Ziel

Ein risikoarmer, vollständig von der Produktion isolierter Vergleichs-Spike
soll beantworten: Würde ein Wechsel auf `NSTableView` mit echten,
NetNewsWire-artigen AppKit-Zellen (keine `NSHostingView`) die zwei
Zielsymptome spürbar verbessern — und lohnt sich der Aufwand einer echten
Migration? Es geht **nicht** um eine produktionsreife Implementierung,
sondern um eine fundierte Entscheidungsgrundlage.

**Bewusste Abgrenzung:** Die Datenbindung an die echte Artikelliste
(`SQLiteFeedArticleListState`, Suche, Sheets, Sticky-Rows, Kontextmenü,
Drag&Drop) ist explizit **nicht** Teil dieses Spikes — eine Anbindungs-Variante
wurde diskutiert (mehr Alltagstauglichkeit/Vergleichbarkeit), aber wegen des
deutlich höheren Aufwands und Risikos zugunsten des synthetischen Harnesses
verworfen. `SQLiteFeedArticleListView.swift` (1197 Zeilen: Toolbar, Suche,
Debounce, vier Sheets, Sticky-Row-Logik) bleibt dadurch vollständig
unangetastet.

## Lösung

### 1. Synthetisches Datenharness (kein DB-Zugriff)

Ein neuer, `#if DEBUG`-gated Fixture-Generator erzeugt direkt in Swift ein
Array von 1000 `ArticleListSnapshot`-Werten mit realistischer Streuung
(Titel-/Summary-Länge, mit/ohne Bild-URL, gestaffelte Daten, wechselnde
Feednamen/Favicons). `ArticleListSnapshot` ist laut bestehenden Tests direkt
konstruierbar (siehe z. B. `FeedivoTests/ViewModels/ArticleListQueryTests.swift`)
— kein 100k-Artikel-DB-Seed nötig. Der Generator liegt im App-Target hinter
`#if DEBUG`, damit sowohl die Debug-UI (Abschnitt 3) als auch XCTests
(`@testable import Feedivo`, Abschnitt 4) ihn nutzen können.

### 2. Baseline: unverändertes `ArticleRowView`

Ein dünner Debug-Wrapper rendert das bestehende, **unveränderte**
`ArticleRowView` in einer schlichten `List(selection:)` über das
Fixture-Array. Keine Änderung an Produktionscode — nur eine neue Debug-Datei.

### 3. Prototyp: `NSTableView` mit echten AppKit-Zellen

Neue Dateien, komplett unter `#if DEBUG`:

- `NativeArticleTableView: NSViewRepresentable` — kapselt `NSScrollView`/
  `NSTableView` + `Coordinator: NSObject, NSTableViewDataSource,
  NSTableViewDelegate`.
- `NativeArticleRowCellView: NSTableCellView` — reine AppKit-Controls, keine
  `NSHostingView`: drei `NSTextField` (Titel, Metadaten-Zeile [Feedname +
  Datum], Summary), `NSImageView` (Vorschaubild), kleines
  Favicon-`NSImageView`, ein einfacher Ungelesen-Punkt (`NSView`/`CALayer`),
  `NSButton` für den Stern.
- Feste Zeilenhöhe über `tableView.rowHeight =
  ArticleRowHeightMetrics.height(interfaceTextSize:imagePosition:summaryLineCount:)`
  — die bestehende, bereits rein einstellungsbasierte (inhaltsunabhängige)
  Funktion wird unverändert wiederverwendet, keine Duplikation.
- Bild-Laden direkt über `ImageCacheService.shared` (derselbe Cache wie
  `CachedRemoteImageView`), mit einem monoton steigenden Lade-Token pro
  Zelle: startet ein Zell-Recycling einen neuen Load, wird ein noch
  laufender alter Load anhand des Tokens verworfen, bevor er `imageView.image`
  setzen darf — Analogon zu `CachedRemoteImageView.loadImage()`s bestehendem
  Stale-URL-Guard, hier für AppKit-Zellwiederverwendung statt SwiftUI-Task-
  Cancellation.

### 4. Debug-Zugang

Eine neue `#if DEBUG`-only `Window`-Scene in `FeedivoApp.swift` (Muster wie
Suchfenster/Organizer/Statistik-Fenster) öffnet eine kleine
`ArticleListRenderBenchmarkView` mit einem Umschalter zwischen Baseline
(Abschnitt 2) und Prototyp (Abschnitt 3), damit beide Varianten live unter
Instruments angeschaut werden können, ohne die App neu zu starten. Ein
`#if DEBUG`-only Menüeintrag öffnet das Fenster. Im Release-Build existiert
weder die Scene noch der Menüeintrag.

### 5. Messmethodik

**Primäres Signal — manuell, vom Nutzer durchgeführt** (kein computer-use für
native macOS-Apps in dieser Umgebung verfügbar):

1. Debug-Build starten, Render-Benchmark-Fenster öffnen, Instruments (Time
   Profiler + Core-Animation-FPS) an den laufenden Prozess anhängen.
2. Mit der Baseline zügig und gleichmäßig durch die 1000 Zeilen scrollen
   (z. B. 10 Sekunden), Trace sichern.
3. Auf den Prototyp umschalten, identisches Scroll-Muster wiederholen, Trace
   sichern.
4. Traces vergleichen: CPU-Zeit pro Frame, sichtbare Hitches/Dropped Frames,
   und ob sich die Hypothese aus dem letzten Vergleichsgespräch bestätigt
   (dass `CachedRemoteImageView.loadImage()`s `nsImage = nil`-Reset bei jedem
   SwiftUI-Zeilen-Neuaufbau zum sichtbaren Bild-Flackern beim Scrollen
   beiträgt) — im Prototyp sollte das dank echter AppKit-Zellwiederverwendung
   nicht mehr auftreten.

**Sekundäre, automatisierte Proxy-Metrik** (bewusst nur ein grober
Anhaltspunkt, kein A/B-Beweis): Ein neuer Test
`FeedivoTests/ArticleListRenderBenchmarkTests.swift` misst die Wanduhrzeit
vom Setzen der 1000 Snapshots bis zum vollständig gelayouteten
`NSTableView` (`layoutSubtreeIfNeeded()` in einem Off-Screen-`NSWindow`).
Eine vergleichbar faire, headless Messung für die SwiftUI-Seite ist
technisch nicht zuverlässig möglich — `List` baut seinen internen
Render-Server erst mit einem echten Fenster/Compositor auf. Das wird im
Testkommentar explizit dokumentiert, damit die Zahl nicht als vollständiger
A/B-Vergleich missverstanden wird; sie dient primär als Regressions-Wächter
für den Prototyp selbst.

### 6. Entscheidungskriterium und Aufräumen

Am Ende bewertest du anhand von Instruments-Traces (Abschnitt 5), ob der
Unterschied im Alltag relevant genug wäre, um eine echte Migration der
produktiven Artikelliste zu rechtfertigen. Das Ergebnis (migrieren /
verwerfen / weitere Messung nötig) wird nach Abschluss als Nachtrag in
diesem Dokument und in `CLAUDE.md` festgehalten — nicht hier vorweggenommen.

Da der komplette Harness hinter `#if DEBUG` liegt und keine bestehende
Produktionsdatei ändert, ist er unabhängig vom Ergebnis mit einem einzigen
Löschvorgang (neue Dateien + die eine `Window`-Scene-Zeile in
`FeedivoApp.swift`) rückstandsfrei entfernbar.

## Bewusst nicht Teil dieses Spikes

- Anbindung an echte Daten/`SQLiteFeedArticleListState` (siehe Abgrenzung
  oben).
- Kontextmenü, Drag&Drop, Sticky-Rows, Tastatur-Navigation im Prototyp.
- Diff-/Teilreload-Logik für Statusänderungen (drittes, hier bewusst
  ausgeklammertes Symptom).
- Jede Aussage zur produktiven Migration selbst — dieser Plan liefert nur
  die Entscheidungsgrundlage dafür.
