# Design: Feed-Status-Fenster als dichte Tabelle mit sichtbaren Aktionen

**Datum:** 2026-08-05
**Status:** Zur Review

## Kontext

`FeedRefreshDiagnosticsWindowView.swift` (siehe
`docs/superpowers/specs/2026-08/2026-08-05-feed-refresh-diagnose-fenster-design.md`) ist
bereits umgesetzt und zeigt fehlgeschlagene Feeds als einfache `List(.inset)` mit reinem
System-Styling. Die fünf nützlichen Aktionen pro Feed — Aktualisieren, Eigenschaften
öffnen, Website öffnen, XML-Adresse kopieren, Löschen — existieren dort ausschließlich im
Rechtsklick-Kontextmenü (`rowActions(for:)`, Zeile 127–155) und sind dadurch für den
Nutzer nicht sichtbar, ohne dass er weiß, dass es sie gibt.

Im Rahmen einer Design-Review wurden drei optisch an die App angepasste Layoutvarianten
vorgeschlagen (Liste mit Aktionsleiste, Karten-Raster, dichte Tabelle). Der Nutzer hat sich
für die dichte Tabelle mit Suchfeld und sortierter Fehlschläge-Spalte entschieden.

## Ziel

Das bestehende Feed-Status-Fenster optisch auf das im Rest der App etablierte
"Konzept A"-Dialogsystem (`RuleDialogTheme.swift`) umstellen und dabei alle fünf
Kontextmenü-Aktionen direkt als sichtbare Icon-Buttons in der Zeile anbieten — ohne
Funktionsänderung an den Aktionen selbst.

## Betrachtete Ansätze

1. **Bestehende Datei komplett auf die neue Tabellenoptik umstellen (gewählt).** Gleiches
   Fenster, gleiche `windowID`, gleicher Menüeintrag. Kein Parallelbetrieb zweier
   Ansichten für dieselben Daten, kein zusätzlicher Umschalt-Zustand.
2. **Neue Ansicht zusätzlich zur bestehenden anbieten (verworfen).** Der Nutzer hat sich
   explizit gegen einen Fallback/Umschalter entschieden — die alte `List(.inset)`-Ansicht
   hat gegenüber der Tabelle keinen eigenständigen Zweck mehr, ein Parallelbetrieb wäre
   nur zusätzlicher, unbegründeter Pflegeaufwand.

## Layout

Struktur folgt dem bereits etablierten Header→Divider→Body-Muster aus
`OPMLExportSheet.swift`, Farben/Radien/Bausteine aus `RuleDialogTheme.swift`
(`RuleDialogTheme(colorScheme:)`, Akzent `#3D5FEE`):

- **Header** (unverändert an Inhalt, neu an Optik): Titel "Feed-Status" + Untertitel mit
  Feed-Anzahl, rechts zwei Buttons über `RuleDialogButton` statt Standard-`Button` —
  "Neu laden" (`.secondary`), "Alle erneut versuchen" (`.primary`, nur sichtbar wenn
  Liste nicht leer, wie bisher).
- **Suchfeld** darunter, `RuleDialogTextField` (1:1 wiederverwendet, keine Änderung an der
  geteilten Komponente).
- **Tabelle**: Kopfzeile mit Spalten Feed / Fehler / Zuletzt / Fehlschläge / Aktionen
  (Grid-Layout, keine `List`/`Table` von SwiftUI — analog zum bereits im Projekt üblichen
  Muster reiner `HStack`/Grid-Zeilen in `FeedManagementOrganizerView.swift`). Kein
  Klick-Handler auf den Spaltenköpfen.
- **Footer**: neue Statuszeile "N Feeds mit Fehlern · zuletzt geprüft `<relative Zeit>`".

Pro Zeile:

- Favicon via bestehender `CachedRemoteImageView`-Logik (unverändert aus dem aktuellen
  `FeedFailureDiagnosticRow.faviconView`, inkl. rotem Warndreieck-Fallback) — **keine**
  farbigen Monogramm-Kreise; die im Mockup gezeigten Buchstaben-Avatare waren nur ein
  Platzhalter für die Design-Review, da fehlgeschlagene Feeds typischerweise trotzdem ein
  echtes Favicon haben.
- Feed-Titel + URL (sekundär, truncated).
- Fehlertext (`diagnostic.errorMessage`, rot) + optionaler HTTP-Status-Chip.
- Zeitpunkt über `diagnostic.lastAttemptAt.feedivoRelativeDisplay` (bereits vorhandene,
  geteilte Extension aus `Date+RelativeDisplay.swift`, respektiert die App-Sprache) statt
  des bisherigen `date.formatted(date:time:)`.
- Neue **Schweregrad-Badge** (`FeedFailureSeverityBadge`, privat in dieser Datei), rein aus
  `diagnostic.consecutiveFailureCount` abgeleitet, kein neues Datenfeld:
  - `1` → neutral, "Erster Fehlschlag"
  - `2–4` → amber (System-Orange-Ton, separat vom Akzent-Blau), "N× in Folge"
  - `≥5` → rot (`theme.destructiveText`/`destructiveTint`), "N× in Folge"
- Fünf Icon-Buttons (`FeedStatusRowActionButton`, privat, 24×24, Hover-Hintergrund
  `theme.card`, Löschen zusätzlich mit `theme.destructiveTint`/`destructiveText` bei
  Hover) statt des bisherigen `.contextMenu`. Jeder Button ruft exakt denselben
  bestehenden Code auf, der heute im `rowActions(for:)`-Kontextmenü hängt — keine neue
  Retry-/Lösch-/Kopier-/Öffnen-Logik.

Der `.contextMenu`-Modifier und `rowActions(for:)` entfallen ersatzlos, da dieselben
Aktionen jetzt permanent sichtbar sind.

## Suche

`@State private var searchText = ""`. Reine, isoliert testbare Funktion filtert die bereits
geladenen `diagnostics` nach Titel- oder URL-Teilstring (case-insensitive). Kein neuer
Datenbank-Zugriff — Filterung läuft ausschließlich auf der im Speicher gehaltenen Liste.

## Sortierung

Fest, nicht interaktiv: `diagnostics` wird nach dem Laden (`reload()`) einmal nach
`consecutiveFailureCount` absteigend sortiert. Der Pfeil neben der Spaltenüberschrift
"Fehlschläge" ist rein visuell und zeigt nur, dass danach sortiert ist — kein
Klick-Handler, keine weiteren Sortierkriterien.

## Footer-Statuszeile

Neu: `@State private var lastReloadedAt: Date?`, gesetzt am Ende von `reload()`. Zeigt
Feed-Anzahl + `lastReloadedAt?.feedivoRelativeDisplay`. Rein transient (kein
`UserDefaults`/keine Persistenz) — das Fenster lädt bei jedem Öffnen ohnehin neu.

## Aktionen (unverändert)

Alle fünf Aktionen sowie "Alle erneut versuchen" bleiben inhaltlich exakt wie in
`docs/superpowers/specs/2026-08/2026-08-05-feed-refresh-diagnose-fenster-design.md`
beschrieben (`FeedViewModel.refreshFeed`/`deleteFeed`, `NSWorkspace.shared.open`,
`NSPasteboard.general`, `FeedPropertiesView`-Sheet, Bestätigungsdialog vor dem Löschen).
Diese Spec ändert nur, **wie** sie erreichbar sind, nicht **was** sie tun.

## Testing

- Neue, reine Funktionen isoliert testbar: Such-Filter (Titel-Treffer, URL-Treffer, kein
  Treffer, leerer Suchbegriff → alle), Sortierung nach `consecutiveFailureCount`
  absteigend, Schweregrad-Ableitung an den Grenzwerten 1/2/4/5.
- Aktionen selbst (Retry/Delete/Properties/Website/Copy) rufen unverändert bestehende,
  bereits getestete Pfade auf — kein neuer Test für den Effekt der Aktionen, nur dafür,
  dass die Icon-Buttons die richtige Methode mit der richtigen `diagnostic`-Instanz
  aufrufen (soweit ohne UI-Test praktikabel prüfbar, z. B. über die extrahierte
  Filter-/Sortier-Logik als Nachweis der korrekten Datenzuordnung pro Zeile).
- Manuelle Live-Verifikation (kein computer-use für native macOS-Apps verfügbar): Fenster
  öffnen, Suche filtert sichtbar, Schweregrad-Farben stimmen mit der jeweiligen
  Fehlschlag-Anzahl überein, alle fünf Icon-Buttons funktionieren identisch zum bisherigen
  Kontextmenü, Footer-Zeile zeigt korrekte Anzahl/Zeit nach "Neu laden".

## Out of Scope

- Keine klickbare/umschaltbare Spaltensortierung.
- Keine parallele alte Ansicht als Fallback — die bisherige `List(.inset)`-Optik und
  `FeedFailureDiagnosticRow` werden vollständig ersetzt, nicht daneben erhalten.
- Keine Änderung an `feed_logs`, `FeedFailureDiagnostic` oder der Datenquelle aus der
  vorherigen Spec — reine Präsentationsschicht-Änderung an bereits vorhandenen Feldern.
- Keine echten Monogramm-Avatare anstelle von Favicons.
