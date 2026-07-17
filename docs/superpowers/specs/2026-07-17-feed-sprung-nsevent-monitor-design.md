# Design: NSEvent-Monitor-Fallback für automatischen Feed-Sprung

**Datum:** 2026-07-17
**Status:** Vom Nutzer freigegeben, bereit für Implementierungsplan

## Ausgangslage

Folge-Design zu `2026-07-17-naechster-feed-mit-ungelesenen-design.md`. Der dort als
Primäransatz beschriebene `.onKeyPress(.downArrow)`/`.onKeyPress(.upArrow)`-Handler am
Wurzel-Container von `ContentView.body` wurde live getestet und ist wirkungslos: macOS'
native `List`-Tastatursteuerung konsumiert Pfeil-Hoch/-Runter auch am Rand der Liste
vollständig, bevor der `.onKeyPress`-Handler das Ereignis überhaupt sieht. Dieses Dokument
beschreibt den in der ursprünglichen Spec bereits angekündigten Fallback: ein app-lokaler
`NSEvent`-Tastatur-Monitor, der Pfeiltasten-Ereignisse abfängt, bevor `List` sie verschluckt.

## Entscheidungen (mit Nutzer geklärt)

- **WKWebView-Fokus:** Liegt der Tastaturfokus im eingebetteten `WKWebView` (Reader-
  „Web-Ansicht", z. B. nach Klick in den Artikeltext), löst ein bloßer Pfeil-Runter/-Hoch
  dort KEINEN Feed-Sprung aus — normales Scrollen der Webseite bleibt unverändert. Grund:
  ein Nutzer, der einen langen Artikel liest und aus Gewohnheit die Pfeiltaste zum Scrollen
  drückt, soll nicht überraschend zum nächsten Feed springen.
- **Sidebar-Fokus (beim Entwerfen zusätzlich gefundenes, analoges Risiko):** Dieselbe
  Kollisionsgefahr besteht für die Sidebar (`NSOutlineView`) — wird gerade mit Pfeiltasten
  durch die Feed-Liste geblättert und ist zufällig irgendein anderer Feed „am Ende seiner
  ungelesenen Artikel", darf der Monitor NICHT die normale Sidebar-Zeilennavigation kapern.
  Gelöst mit demselben Mechanismus wie beim WKWebView (siehe Architektur unten), keine
  zusätzliche Nutzerentscheidung nötig — direkte Konsequenz derselben Grundregel: „nur wenn
  die Artikelliste selbst den Fokus hat".
- Alle übrigen Entscheidungen (nur Einzel-Feed-Auswahl, Auto-Auswahl erster/letzter
  ungelesener Artikel, sichtbare Sidebar-Reihenfolge, kein Wraparound, Pfeil-Hoch-Symmetrie)
  sind bereits in der ursprünglichen Spec getroffen und bleiben unverändert gültig — dieses
  Dokument behandelt ausschließlich den Auslösemechanismus.

## Architektur

### `FeedJumpKeyMonitor` (neue Datei `Feedivo/Services/FeedJumpKeyMonitor.swift`)

`@Observable @MainActor final class FeedJumpKeyMonitor` mit Singleton `.shared`, strukturell
analog zum bereits bestehenden, review-geprüften `TextEditingFocusMonitor`
(`Feedivo/Services/TextEditingFocusMonitor.swift`):

- `startMonitoring()` installiert einen `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`
  — idempotent (`guard monitor == nil`). Ein lokaler Event-Monitor fängt Tastendrücke ab,
  BEVOR irgendeine View (auch `List`s interne `NSTableView`) sie zu sehen bekommt — das ist
  der Grund, warum dieser Ansatz dort greift, wo `.onKeyPress` scheitert.
- Zwei von `ContentView` einmalig (nicht bei jedem Render) in `handleContentAppear()`
  gesetzte Closures:
  - `isEligible: (Direction) -> Bool`
  - `performJump: (Direction) -> Void`

  Sicher als einmalige Registrierung, weil `@State`-Properties intern eine stabile, über
  Struct-Kopien hinweg geteilte Box referenzieren — dasselbe Prinzip, das im Projekt bereits
  für normale Button-Action-Closures gilt (`self.methodenName` als Closure erfasst `self` als
  Struct-Kopie, liest aber über die geteilte `@State`-Box stets den aktuellen Wert).
- `weak var contentWindow: NSWindow?`, gesetzt von einer neuen Bridge-View (siehe unten).
- `enum Direction { case next, previous }` plus eine reine, isoliert testbare Funktion
  `static func direction(for specialKey: NSEvent.SpecialKey?, modifierFlagsAreEmpty: Bool) -> Direction?`
  (analog zum bereits im Projekt etablierten Pure-Function-Muster `ReaderArrowKeyNavigation`).

### Monitor-Callback-Reihenfolge

Der `keyDown`-Handler prüft der Reihe nach:

1. Modifier-Flags leer (nur reine Pfeiltaste, keine Cmd/Option/Shift-Kombination)
2. `Direction.direction(for: event.specialKey, modifierFlagsAreEmpty: true)` liefert
   `.next`/`.previous` (sonst Event unverändert durchreichen)
3. `!TextEditingFocusMonitor.shared.isEditingText` (bereits vorhandene Infrastruktur
   wiederverwendet, kein neuer Textfeld-Schutz-Code nötig)
4. `event.window === contentWindow` — nur das Hauptfenster. Schließt Suchfenster, Organizer,
   Einstellungen UND das Artikel-Popout-Fenster aus (deckt damit automatisch den bereits in
   der ursprünglichen Spec festgelegten Out-of-Scope-Punkt „kein Verhalten im Popout" ab,
   ohne zusätzlichen Code)
5. `firstResponder` liegt NICHT innerhalb eines `WKWebView` ODER einer `NSOutlineView` —
   Aufstieg durch die `superview`-Kette ab `window.firstResponder as? NSView`:
   ```swift
   private func firstResponderIsExcluded(in window: NSWindow) -> Bool {
       var view = window.firstResponder as? NSView
       while let current = view {
           if current is WKWebView || current is NSOutlineView { return true }
           view = current.superview
       }
       return false
   }
   ```
   Beides sind öffentliche AppKit-/WebKit-Basisklassen — keine fragilen privaten
   Klassennamen, keine Änderung an der bestehenden (laut CLAUDE.md bewusst fragilen)
   Reader-/Sidebar-Architektur nötig, kein neuer Zugriffspfad auf die dort gekapselten
   `fileprivate`/`private` WKWebView-Referenzen erforderlich.
6. `isEligible(direction)` — die bereits in `ContentView` bestehende Logik (Einzel-Feed-
   Auswahl, tatsächlich am Rand der ungelesenen Artikel, keine laufende Sprung-Sperre über
   `isJumpingToFeedWithUnread`)

Nur wenn ALLE Bedingungen zutreffen: `performJump(direction)` aufrufen, Ereignis konsumieren
(`return nil`). Sonst Original-Event unverändert zurückgeben — normales Verhalten (Sidebar-
Navigation, Web-Ansicht-Scrollen, reguläre Artikellisten-Navigation, Textfeld-Eingabe)
bleibt in jedem anderen Fall exakt wie bisher unangetastet.

### Fenster-Erkennung: `ContentWindowObserver`

Neue, unsichtbare `NSViewRepresentable`-Bridge-View, exakt nach dem bereits im Projekt
etablierten `FullScreenTransitionObserver`-Muster (`SQLiteReaderView.swift:931`) — liest
`view.window` in `makeNSView`/`updateNSView` und reicht es (bei Änderung) an
`FeedJumpKeyMonitor.shared.contentWindow` weiter. Eingehängt via
`.background(ContentWindowObserver())` in `ContentView.body`, an derselben Stelle, an der
auch die übrigen Root-Level-Modifier sitzen.

### `ContentView.swift`-Änderungen

- Die bestehenden `.onKeyPress(.downArrow)`/`.onKeyPress(.upArrow)`-Blöcke (inkl. der
  zugehörigen Kommentare) werden ENTFERNT, nicht daneben belassen — sie feuern wegen des
  neuen Monitors ohnehin nie mehr sinnvoll (der Monitor konsumiert das Ereignis bereits vor
  jeder SwiftUI-Ebene), ein totes Duplikat wäre nur Verwirrung für künftige Leser.
- Ersatz: einmalige Registrierung der beiden `FeedJumpKeyMonitor`-Closures + Aufruf von
  `FeedJumpKeyMonitor.shared.startMonitoring()` in `handleContentAppear()`.
- `isJumpingToFeedWithUnread`-Sperre + ihre bestehende
  `.onChange(of: sqliteArticleNavigationState)`-Freigabe bleiben unverändert — der Race-Fix
  aus dem vorherigen Feature ist unabhängig vom Auslösemechanismus und wird nur weiterhin
  über `isEligible` abgefragt.
- `selectNextFeedWithUnread()`/`selectPreviousFeedWithUnread()` (bestehende private
  Funktionen) bleiben inhaltlich unverändert — werden künftig aus `performJump` heraus
  aufgerufen statt aus dem entfernten `.onKeyPress`-Handler.
- `.background(ContentWindowObserver())` neu ergänzt.

## Testing

- `FeedJumpKeyMonitor.Direction.direction(for:modifierFlagsAreEmpty:)` ist eine reine
  Funktion und wird isoliert unit-getestet (Swift Testing, kein `NSEvent`/AppKit-Mock nötig).
- Fenster-Identität, Fokus-Ausschluss (`firstResponderIsExcluded`) und die
  `NSEvent.addLocalMonitorForEvents`-Verdrahtung selbst sind — wie bei den vorherigen
  Pfeiltasten-Features — nicht automatisiert testbar (kein ViewInspector, kein Zugriff auf
  echten AppKit-Fensterzustand aus Unit-Tests heraus). Verifikation über Build + eine
  erweiterte manuelle Live-Checkliste.

**Manuelle Live-Verifikationscheckliste (ergänzt die bereits bestehende Checkliste aus der
ursprünglichen Spec, ersetzt dort NICHT Punkt 1–7, sondern ergänzt):**

1. Feed mit genau einem ungelesenen Artikel auswählen, lesen, dann nochmal Pfeil-Runter —
   springt jetzt tatsächlich zum nächsten Feed mit ungelesenen Artikeln (der entscheidende,
   zuvor fehlgeschlagene Test).
2. Symmetrisch mit Pfeil-Hoch am Anfang der Liste.
3. **Neu:** In der Sidebar mit Pfeiltasten durch die Feed-Liste blättern, während irgendein
   ANDERER (nicht ausgewählter) Feed zufällig „am Ende seiner ungelesenen Artikel" ist — die
   Sidebar-Navigation bleibt normal, kein ungewollter Feed-Sprung.
4. **Neu:** Einen Artikel in Web-Ansicht öffnen (WKWebView), in den Artikeltext klicken (damit
   der WKWebView den Fokus hat), Pfeil-Runter drücken, während der aktuelle Feed am Ende
   seiner ungelesenen Artikel ist — Seite scrollt normal, kein Feed-Sprung.
5. **Neu:** Dasselbe wie 3/4, aber diesmal mit der Artikelliste selbst fokussiert (z. B. nach
   Klick auf eine Artikelzeile) — Feed-Sprung funktioniert wie in Punkt 1/2.
6. **Neu:** Suchfenster oder Organizer-Fenster öffnen, dort mit Pfeiltasten navigieren,
   während im Hintergrund das Hauptfenster einen Feed am Ende seiner ungelesenen Artikel
   zeigt — kein Feed-Sprung im Hintergrundfenster, Navigation im Vordergrundfenster bleibt
   normal.
7. Restliche Punkte 4–7 aus der ursprünglichen Spec-Checkliste (normales Durchnavigieren,
   kein Wraparound, Ordner-Reihenfolge, kein Sprung bei Smart-Folder/Tag-Auswahl) unverändert
   gültig.

## Out of Scope

- Keine Änderung an den bereits funktionierenden `.onKeyPress(.rightArrow)`/
  `.onKeyPress(.leftArrow)`/`.onKeyPress(.return)`-Handlern (Reader-Ansichtswechsel/Öffnen im
  Browser) — die sind von diesem Fix nicht betroffen und bleiben unangetastet.
- Kein genereller WKWebView- oder NSOutlineView-Fokus-Tracking-Mechanismus für andere
  Features — `firstResponderIsExcluded` ist eine lokale Prüfung innerhalb des Monitors, kein
  neuer app-weiter Observer-Typ wie `TextEditingFocusMonitor`.
- Keine Änderung an der bestehenden `isJumpingToFeedWithUnread`-Sperre-Logik selbst, nur an
  ihrem Auslösemechanismus.
