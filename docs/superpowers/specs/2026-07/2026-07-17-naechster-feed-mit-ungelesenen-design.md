# Design: Automatischer Feed-Sprung am Ende/Anfang der Artikelliste

**Datum:** 2026-07-17
**Status:** Vom Nutzer freigegeben, bereit für Implementierungsplan

## Ausgangslage

Nutzerwunsch: Wenn beim Durchnavigieren mit Pfeil-Runter der letzte ungelesene Artikel des
aktuell ausgewählten Feeds gelesen wurde und weiter Pfeil-Runter gedrückt wird, soll
automatisch zum nächsten Feed in der Sidebar-Reihenfolge gewechselt werden, der noch
ungelesene Artikel hat — dort direkt mit dem ersten ungelesenen Artikel. Ergänzt die kürzlich
gebaute Pfeiltasten-Navigation (Hoch/Runter für Artikelliste, Rechts/Links/Enter für den
Reader-Ansichtswechsel).

## Entscheidungen (mit Nutzer geklärt)

- Gilt nur bei Einzel-Feed-Auswahl in der Sidebar (`.feed(String)`) — nicht bei Smart
  Foldern, Tags oder dem Sammel-Smart-Folder „Ungelesen", wo es kein sinnvolles Konzept von
  „aktuellem Feed" zum Weiterspringen gibt.
- Beim Sprung wird automatisch der erste ungelesene Artikel des Ziel-Feeds ausgewählt (kein
  Zwischenklick nötig).
- Sidebar-Auswahl wandert sichtbar mit (`sidebarSelection` wechselt auf den neuen Feed).
- „Nächster Feed" = exakt die sichtbare Sidebar-Reihenfolge (nicht-einsortierte Feeds
  zuerst, dann Ordner der Reihe nach mit ihren Feeds), nicht eine vereinfachte alphabetische
  Sortierung.
- Pfeil-Hoch verhält sich symmetrisch: am Anfang der Liste (kein vorheriger Artikel mehr)
  springt es zum *vorherigen* Feed mit ungelesenen Artikeln und wählt dort den *letzten*
  ungelesenen Artikel (damit weiteres Pfeil-Hoch konsistent rückwärts weiterkommt).
- Kein Wraparound: gibt es keinen weiteren/vorherigen Feed mit ungelesenen Artikeln mehr,
  passiert einfach nichts.

## Bekanntes technisches Risiko

Anders als die kürzlich gebauten Rechts-/Links-/Eingabetaste-Handler (die die Artikelliste
gar nicht konsumiert) übernimmt macOS' native `List`-Tastatursteuerung Hoch/Runter *immer*
selbst — auch am Rand der Liste, wo sie ins Leere läuft (bekanntes „stumm bleiben"-Verhalten
wie in Finder/Mail-Listenansichten). Ob ein `.onKeyPress`-Handler an einer Vorfahren-View das
Ereignis am Rand der Liste überhaupt noch zu fassen bekommt (weil `List` es dort eventuell
bereits konsumiert, ohne es weiterzureichen — anders als bei Rechts/Links, das inzwischen
live bestätigt funktioniert), ist ohne Live-Test nicht sicher vorab zu klären.

**Primärer Ansatz:** genau wie bei Rechts/Links — `.onKeyPress(.downArrow)`/
`.onKeyPress(.upArrow)` am selben Wurzel-Container in `ContentView.body`, mit Guard auf
`sqliteArticleNavigationState.nextArticleID == nil` (bzw. `.previousArticleID == nil`).
Reagiert der Handler dort nicht (weil `List` das Ereignis am Rand doch komplett verschluckt),
lautet der dokumentierte Rückfallplan: ein tieferliegender, app-lokaler `NSEvent`-
Tastatur-Monitor (`NSEvent.addLocalMonitorForEvents(matching: .keyDown)`), der Ereignisse vor
der `List` abfängt, die Randbedingung prüft und bei Treffer das Ereignis selbst konsumiert —
analog zu dem bereits im Projekt dokumentierten `NSPanGestureRecognizer`-Workaround, der für
ein ähnliches AppKit/SwiftUI-Interaktionsproblem bei der Sidebar-Drag&Drop-Migration (ADR-008)
nötig war. Dieser Fallback wird nur gebaut, falls der Primäransatz im Live-Test tatsächlich
scheitert — kein Vorab-Aufwand ohne Bestätigung des Problems.

## Architektur

### Feed-Reihenfolge

Neue, isolierte reine Funktion (neue Datei unter `Feedivo/Views/Sidebar/`), die aus den
bereits bestehenden Bausteinen `FeedFolderOrganizer.feedsWithoutFolder(from:)` und
`.feedsByFolderName(in:folders:)` — denselben, die auch `SidebarOutlineNode.buildTree` für
die eigentliche Sidebar-Baumstruktur nutzt — eine flache `[FeedSidebarSnapshot]`-Liste in
exakt sichtbarer Sidebar-Reihenfolge zusammensetzt: nicht-einsortierte Feeds zuerst (sortiert
wie in der Sidebar), dann Ordner in Ordner-`sortIndex`-Reihenfolge, darin wiederum die Feeds
sortiert. Kein Zugriff auf AppKit/NSOutlineView-Code nötig — reine Wiederverwendung der
bereits Sidebar-unabhängigen `FeedFolderOrganizer`-Bausteine.

Darauf aufbauend zwei reine Nachschlage-Funktionen: „nächster Feed mit `unreadCount > 0`
nach Feed X in dieser Reihenfolge" und „vorheriger Feed mit `unreadCount > 0` vor Feed X".

### Neue Daten in `ContentView.swift`

`ContentView` lädt zusätzlich zu den bestehenden `feedSnapshots: [FeedSidebarSnapshot]` eine
`[FeedFolderRecord]`-Liste via `FeedFolderStore(database:).folders()` (derselbe
leichtgewichtige, GRDB-basierte Store-Aufruf, den auch `SQLiteSidebarState` bereits nutzt) —
im selben Reload-Zyklus wie `feedSnapshots` (`onAppear`, Status-Version-Bump).

### `.onKeyPress`-Handler

Am selben Wurzel-Container wie die bestehenden Rechts-/Links-/Eingabetaste-Handler:
- `.onKeyPress(.downArrow)`: nur relevant, wenn `sidebarSelection` aktuell ein `.feed(...)`
  ist UND `sqliteArticleNavigationState.nextArticleID == nil` (kein weiterer Artikel in der
  aktuellen Liste). Ermittelt den nächsten Feed mit ungelesenen Artikeln, setzt
  `sidebarSelection` auf diesen Feed und wählt dessen ersten ungelesenen Artikel aus. Sonst
  `.ignored` (normales `List`-Verhalten übernimmt).
- `.onKeyPress(.upArrow)`: symmetrisch mit `previousArticleID == nil`, wählt beim Zielfeed
  den letzten ungelesenen Artikel.

Kein neuer State für die Feed-Reihenfolge selbst nötig — wird bei Bedarf aus den bereits
geladenen `feedSnapshots`/Ordnerliste berechnet, kein Caching notwendig (Feed-Anzahl ist
klein).

### Auswahl des Ziel-Artikels

Für den ersten/letzten ungelesenen Artikel eines Feeds wird eine bestehende oder neu zu
ergänzende Datenbank-Abfrage genutzt (exakte Store-Methode wird beim Implementierungsplan
anhand des tatsächlichen Codes ermittelt — im Projekt existieren bereits ähnliche gezielte
Abfragen wie `newestUnread(feedID:)` für das Menubar-Dropdown-Feature, die als Vorbild
dienen).

## Testing

Die reine Feed-Reihenfolge- und Nachschlage-Logik ist isoliert unit-testbar (kein
DB-Zugriff nötig, operiert auf einfachen `[FeedSidebarSnapshot]`/`[FeedFolderRecord]`-Arrays).
Die `.onKeyPress`-Verdrahtung selbst ist wie bei den vorherigen Pfeiltasten-Features nicht
automatisiert testbar (kein ViewInspector im Projekt) — Verifikation über Build + manuelle
Live-Checkliste, mit besonderem Fokus auf das oben beschriebene technische Risiko.

**Manuelle Live-Verifikationscheckliste:**
1. Feed mit genau einem ungelesenen Artikel auswählen, diesen lesen (Pfeil-Runter oder Klick),
   dann nochmal Pfeil-Runter drücken — springt zum nächsten Feed mit ungelesenen Artikeln in
   Sidebar-Reihenfolge, Sidebar-Auswahl wechselt sichtbar, erster ungelesener Artikel dort ist
   ausgewählt.
2. Symmetrisch mit Pfeil-Hoch am Anfang der Liste — springt zum vorherigen Feed mit
   ungelesenen Artikeln, letzter ungelesener Artikel dort ausgewählt.
3. **Entscheidender Test für das technische Risiko:** falls Schritt 1/2 NICHT funktioniert
   (Pfeiltaste bleibt wirkungslos), ist das der Trigger für den dokumentierten
   `NSEvent`-Monitor-Fallback — nicht stillschweigend als „geht halt nicht" hinnehmen.
4. Feed mit mehreren ungelesenen Artikeln: normales Durchnavigieren mit Pfeil-Runter
   innerhalb des Feeds bleibt unverändert (kein vorzeitiger Sprung).
5. Letzter Feed mit ungelesenen Artikeln in der Sidebar-Reihenfolge: Pfeil-Runter am Ende
   tut nichts (kein Wraparound).
6. Feed-Sprung funktioniert unabhängig davon, ob der Ziel-Feed einsortiert oder in einem
   Ordner liegt, und respektiert die Ordner-Reihenfolge (nicht nur alphabetisch).
7. Smart Folder/Tag-Auswahl: Pfeil-Runter am Ende bleibt unverändert wirkungslos (kein
   Feed-Sprung außerhalb von Einzel-Feed-Auswahl).

## Out of Scope

- Kein Feed-Sprung bei Smart-Folder-/Tag-Auswahl.
- Kein Wraparound am Ende/Anfang aller Feeds.
- Keine Anpassbarkeit über die Shortcuts-Einstellungen (fest eingebaut, analog zur
  bestehenden Pfeiltasten-Navigation).
- Kein Verhalten in der separaten Artikel-Popout-Fenster-Szene (`ArticleWindowView`) — nur
  das Hauptfenster (`ContentView`).
