# NSEvent-Monitor-Fallback für automatischen Feed-Sprung Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ersetzt den live bestätigt wirkungslosen `.onKeyPress(.downArrow)`/`.onKeyPress(.upArrow)`-
Ansatz für den automatischen Feed-Sprung durch einen app-lokalen `NSEvent`-Tastatur-Monitor, der
Pfeiltasten-Ereignisse abfängt, bevor `List` sie am Rand der Artikelliste verschluckt.

**Architecture:** Neuer `@Observable @MainActor`-Singleton `FeedJumpKeyMonitor`
(`Feedivo/Services/FeedJumpKeyMonitor.swift`, strukturell analog zu `TextEditingFocusMonitor`)
installiert einen `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`, der bei reiner
Pfeil-Hoch/-Runter-Taste (keine Modifier) prüft: nicht im Textfeld, richtiges Fenster (neue
`ContentWindowObserver`-Bridge-View liefert die Fensterreferenz), Fokus nicht in `WKWebView`
oder `NSOutlineView` (Sidebar), und die bereits bestehende `ContentView`-Eligibility-Logik.
Trifft alles zu, wird das Ereignis konsumiert und der bereits bestehende Sprung ausgelöst;
sonst unverändert durchgereicht. Ersetzt die jetzt toten `.onKeyPress`-Blöcke vollständig.

**Tech Stack:** SwiftUI (macOS 14+), AppKit (`NSEvent`, `NSViewRepresentable`), WebKit
(`WKWebView`-Typprüfung), Swift Testing für die reine Richtungs-Klassifikation.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-17-feed-sprung-nsevent-monitor-design.md` — bei
  Widersprüchen zwischen Plan und Spec gilt die Spec. Basis-Spec (unverändert gültige
  Kernentscheidungen wie Sidebar-Reihenfolge, kein Wraparound):
  `docs/superpowers/specs/2026-07-17-naechster-feed-mit-ungelesenen-design.md`.
- Kommentare im Code auf Deutsch (Projektkonvention).
- `xcodebuild build` muss nach jedem Task grün sein: `xcodebuild build -project Feedivo.xcodeproj
  -scheme Feedivo -destination 'platform=macOS'`.
- Tests laufen gezielt: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo
  -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests
  -parallel-testing-enabled NO`.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` ist für das App-Target gesetzt (siehe CLAUDE.md-
  Gotcha) — eine reine, aus synchronem Test-Code aufrufbare Funktion auf einer `@MainActor`-
  Klasse muss explizit `nonisolated` markiert werden, sonst erbt sie die Actor-Isolation und
  ist aus einem nicht-async `@Test func` heraus nicht aufrufbar (bereits bekanntes,
  dokumentiertes Muster aus `MenubarStatusItemController`).
- Die bereits funktionierenden `.onKeyPress(.rightArrow)`/`.onKeyPress(.leftArrow)`/
  `.onKeyPress(.return)`-Handler in `ContentView.swift` bleiben unverändert — nicht Teil
  dieses Plans.
- Die bestehende `isJumpingToFeedWithUnread`-Sperre-Logik und ihre
  `.onChange(of: sqliteArticleNavigationState)`-Freigabe bleiben inhaltlich unverändert.
- Fenster-/Fokus-/`NSEvent`-Monitor-Verdrahtung ist nicht automatisiert testbar (kein
  ViewInspector, kein echter AppKit-Fensterzustand in Unit-Tests) — Verifikation über Build +
  manuelle Live-Checkliste am Ende von Task 2.

---

## Task 1: `FeedJumpKeyMonitor` mit testbarer Richtungs-Klassifikation

**Files:**
- Create: `Feedivo/Services/FeedJumpKeyMonitor.swift`
- Test: `FeedivoTests/FeedivoTests.swift` (direkt vor der schließenden `}` der
  `FeedivoTests`-Struct, Zeile 1011)

**Interfaces:**
- Produces: `final class FeedJumpKeyMonitor` mit Singleton `.shared`;
  `enum FeedJumpKeyMonitor.Direction { case next, previous }` (automatisch `Equatable`);
  `nonisolated static func direction(for specialKey: NSEvent.SpecialKey?, modifierFlagsAreEmpty: Bool) -> Direction?`;
  `var isEligible: (Direction) -> Bool` (Default: `{ _ in false }`);
  `var performJump: (Direction) -> Void` (Default: `{ _ in }`);
  `weak var contentWindow: NSWindow?`;
  `func startMonitoring()`.
- Consumes: `TextEditingFocusMonitor.shared.isEditingText`
  (`Feedivo/Services/TextEditingFocusMonitor.swift`, bereits vorhanden).

- [ ] **Step 1: Failing Tests schreiben**

In `FeedivoTests/FeedivoTests.swift`, direkt vor der schließenden `}` der `FeedivoTests`-Struct
einfügen (die Datei importiert bereits `AppKit`, `WebKit`, `Testing` — keine neuen Imports
nötig):

```swift

    @Test func feedJumpKeyMonitorDirectionErkenntAbwaertspfeilOhneModifier() {
        let direction = FeedJumpKeyMonitor.direction(for: .downArrow, modifierFlagsAreEmpty: true)
        #expect(direction == .next)
    }

    @Test func feedJumpKeyMonitorDirectionErkenntAufwaertspfeilOhneModifier() {
        let direction = FeedJumpKeyMonitor.direction(for: .upArrow, modifierFlagsAreEmpty: true)
        #expect(direction == .previous)
    }

    @Test func feedJumpKeyMonitorDirectionIgnoriertModifierKombination() {
        let direction = FeedJumpKeyMonitor.direction(for: .downArrow, modifierFlagsAreEmpty: false)
        #expect(direction == nil)
    }

    @Test func feedJumpKeyMonitorDirectionIgnoriertAndereTasten() {
        let direction = FeedJumpKeyMonitor.direction(for: .rightArrow, modifierFlagsAreEmpty: true)
        #expect(direction == nil)
    }

    @Test func feedJumpKeyMonitorDirectionIgnoriertFehlendeSpecialKey() {
        let direction = FeedJumpKeyMonitor.direction(for: nil, modifierFlagsAreEmpty: true)
        #expect(direction == nil)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/feedJumpKeyMonitorDirectionErkenntAbwaertspfeilOhneModifier -parallel-testing-enabled NO`
Expected: FAIL — Compile-Fehler, `FeedJumpKeyMonitor` existiert noch nicht.

- [ ] **Step 3: `FeedJumpKeyMonitor.swift` anlegen**

Neue Datei `Feedivo/Services/FeedJumpKeyMonitor.swift`:

```swift
import AppKit
import WebKit

/// App-lokaler Tastatur-Monitor für den automatischen Feed-Sprung (Feature:
/// Pfeil-Runter am Ende der ungelesenen Artikel eines Feeds springt zum
/// nächsten Feed mit ungelesenen Artikeln, Pfeil-Hoch symmetrisch rückwärts).
///
/// Ersetzt einen ursprünglich versuchten `.onKeyPress(.downArrow)`/
/// `.onKeyPress(.upArrow)`-Handler in `ContentView.swift`, der live bestätigt
/// wirkungslos war: macOS' native `List`-Tastatursteuerung konsumiert
/// Pfeil-Hoch/-Runter auch am Rand der Liste vollständig, bevor SwiftUIs
/// `.onKeyPress`-Mechanismus das Ereignis überhaupt sieht. Ein
/// `NSEvent.addLocalMonitorForEvents`-Monitor fängt das Ereignis dagegen ab,
/// BEVOR es an irgendeine View (auch `List`s interne `NSTableView`)
/// dispatcht wird — siehe
/// `docs/superpowers/specs/2026-07-17-feed-sprung-nsevent-monitor-design.md`.
@Observable
@MainActor
final class FeedJumpKeyMonitor {
    static let shared = FeedJumpKeyMonitor()

    enum Direction {
        case next
        case previous
    }

    /// Von `ContentView.configureFeedJumpKeyMonitor()` einmalig gesetzt.
    /// Liefert true, wenn ein Feed-Sprung in die jeweilige Richtung aktuell
    /// zulässig ist (Einzel-Feed-Auswahl, am Rand der ungelesenen Artikel,
    /// keine laufende Sprung-Sperre).
    var isEligible: (Direction) -> Bool = { _ in false }
    /// Führt den eigentlichen Sprung aus (ruft die bereits bestehenden
    /// ContentView-Methoden `selectNextFeedWithUnread()`/
    /// `selectPreviousFeedWithUnread()` auf).
    var performJump: (Direction) -> Void = { _ in }
    /// Von der neuen `ContentWindowObserver`-Bridge-View gesetzt — die
    /// `NSWindow`, die `ContentView` tatsächlich hostet. Verhindert, dass
    /// Pfeiltasten-Ereignisse in anderen Fenstern (Suche, Organizer,
    /// Einstellungen, Artikel-Popout) fälschlich einen Feed-Sprung im
    /// Hauptfenster auslösen.
    weak var contentWindow: NSWindow?

    private var monitor: Any?

    private init() {}

    func startMonitoring() {
        guard monitor == nil else { return }

        // @MainActor auf der Closure ist dieselbe von Apple empfohlene Brücke
        // wie in TextEditingFocusMonitor.startObserving() — ohne die
        // Annotation würde der Zugriff auf self.contentWindow/isEligible/
        // performJump (alles MainActor-isolierte Properties) unter
        // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor nicht kompilieren.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @MainActor [weak self] event in
            guard let self else { return event }

            let modifierFlagsAreEmpty = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .isEmpty
            guard let direction = Self.direction(
                for: event.specialKey,
                modifierFlagsAreEmpty: modifierFlagsAreEmpty
            ) else {
                return event
            }
            guard !TextEditingFocusMonitor.shared.isEditingText else { return event }
            guard let contentWindow = self.contentWindow, event.window === contentWindow else {
                return event
            }
            guard !self.firstResponderIsExcluded(in: contentWindow) else { return event }
            guard self.isEligible(direction) else { return event }

            self.performJump(direction)
            return nil
        }
    }

    /// Reine Klassifikation, unabhängig vom Fenster-/Fokus-Zustand — deshalb
    /// `nonisolated`: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` würde eine
    /// unannotierte `static func` auf dieser `@MainActor`-Klasse sonst aus
    /// synchronem Test-Code heraus unaufrufbar machen (siehe CLAUDE.md-Gotcha
    /// zu `MenubarStatusItemController`).
    nonisolated static func direction(
        for specialKey: NSEvent.SpecialKey?,
        modifierFlagsAreEmpty: Bool
    ) -> Direction? {
        guard modifierFlagsAreEmpty else { return nil }

        switch specialKey {
        case .some(.downArrow):
            return .next
        case .some(.upArrow):
            return .previous
        default:
            return nil
        }
    }

    /// Schließt zwei bekannte, eigenständig pfeiltasten-navigierbare
    /// AppKit-Bereiche im Hauptfenster aus: das eingebettete `WKWebView`
    /// (Reader-„Web-Ansicht" — dort soll Pfeil-Hoch/-Runter normal scrollen)
    /// und die Sidebar-`NSOutlineView` (dort soll Pfeil-Hoch/-Runter normal
    /// zwischen Feed-Zeilen wechseln). Aufstieg durch die `superview`-Kette
    /// ab dem First Responder — beides öffentliche AppKit-/WebKit-
    /// Basisklassen, keine fragilen privaten Klassennamen nötig.
    private func firstResponderIsExcluded(in window: NSWindow) -> Bool {
        var view = window.firstResponder as? NSView
        while let current = view {
            if current is WKWebView || current is NSOutlineView {
                return true
            }
            view = current.superview
        }
        return false
    }
}
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/feedJumpKeyMonitorDirectionErkenntAbwaertspfeilOhneModifier -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Verbleibende neue Tests + Regressionscheck**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO`
Expected: PASS (alle Tests der Datei, inkl. der 5 neuen)

- [ ] **Step 6: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/FeedJumpKeyMonitor.swift FeedivoTests/FeedivoTests.swift
git commit -m "Feature: FeedJumpKeyMonitor mit testbarer Pfeiltasten-Richtungs-Klassifikation"
```

---

## Task 2: Verdrahtung in `ContentView.swift`

**Files:**
- Modify: `Feedivo/Views/ContentView.swift`

**Interfaces:**
- Consumes: `FeedJumpKeyMonitor.shared` (`.isEligible`, `.performJump`, `.contentWindow`,
  `.startMonitoring()`) aus Task 1; bereits bestehende `selectedFeedID: String?`
  (`ContentView.swift:768`), `selectedSQLiteArticleID: String?`, `isJumpingToFeedWithUnread:
  Bool`, `sqliteArticleNavigationState: SQLiteArticleNavigationState` (`.nextArticleID`/
  `.previousArticleID: String?`), `selectNextFeedWithUnread()` (`ContentView.swift:728`),
  `selectPreviousFeedWithUnread()` (`ContentView.swift:748`).
- Produces: sichtbares Endverhalten, keine neuen öffentlichen Interfaces (letzter Task des
  Plans).

- [ ] **Step 1: `import AppKit` ergänzen**

In `Feedivo/Views/ContentView.swift`, die bestehenden Zeilen 1-3 ersetzen durch:

```swift
import AppKit
import SwiftUI
import Network
import UniformTypeIdentifiers
```

(Nötig für die neue `NSViewRepresentable`-Bridge-View in Step 5 — analog zu `SQLiteReaderView.swift`,
das `import AppKit` aus demselben Grund führt.)

- [ ] **Step 2: Tote `.onKeyPress(.downArrow)`/`.onKeyPress(.upArrow)`-Blöcke entfernen**

In `Feedivo/Views/ContentView.swift`, den folgenden Block (aktuell Zeilen 228-260 — der
`.onKeyPress(.return)`-Block direkt davor und der `.onChange(of: sqliteArticleNavigationState)`-
Block direkt danach bleiben unverändert stehen) vollständig entfernen:

```swift
        // Automatischer Feed-Sprung: Pfeil-Runter am Ende der ungelesenen
        // Artikel eines Feeds springt zum nächsten Feed mit ungelesenen
        // Artikeln (Sidebar-Reihenfolge), Pfeil-Hoch symmetrisch rückwärts.
        // Nur bei Einzel-Feed-Auswahl relevant (selectedFeedID != nil) — bei
        // Smart Foldern/Tags gibt es kein "nächster Feed"-Konzept. Zusätzliche
        // Bedingung selectedSQLiteArticleID != nil verhindert einen Sprung,
        // wenn noch gar kein Artikel ausgewählt wurde (dort ist
        // nextArticleID/previousArticleID ebenfalls nil, aber aus einem
        // anderen Grund).
        .onKeyPress(.downArrow) {
            guard selectedFeedID != nil,
                  selectedSQLiteArticleID != nil,
                  sqliteArticleNavigationState.nextArticleID == nil,
                  !isJumpingToFeedWithUnread
            else {
                return .ignored
            }

            selectNextFeedWithUnread()
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard selectedFeedID != nil,
                  selectedSQLiteArticleID != nil,
                  sqliteArticleNavigationState.previousArticleID == nil,
                  !isJumpingToFeedWithUnread
            else {
                return .ignored
            }

            selectPreviousFeedWithUnread()
            return .handled
        }
```

Direkt danach folgt weiterhin unverändert der Kommentar „Gibt die Feed-Sprung-Sperre wieder
frei…" gefolgt vom `.onChange(of: sqliteArticleNavigationState) { ... }`-Block — dieser bleibt
bestehen, NICHT löschen.

- [ ] **Step 3: `.background(ContentWindowObserver())` ergänzen**

In `Feedivo/Views/ContentView.swift`, direkt nach der bestehenden Zeile
`.onAppear(perform: handleContentAppear)` einfügen:

```swift
        .background(ContentWindowObserver())
```

- [ ] **Step 4: `configureFeedJumpKeyMonitor()` ergänzen und in `handleContentAppear()` aufrufen**

In `Feedivo/Views/ContentView.swift`, den bestehenden `handleContentAppear()`-Funktionskörper
ersetzen durch:

```swift
    private func handleContentAppear() {
        if let feedivoDatabase {
            BackgroundRefreshService.cleanupOnAppStartIfNeeded(database: feedivoDatabase)
        }
        updateFirstRunWizardPresentation()
        selectDefaultSmartFolderIfNeeded()
        updateAppIconBadge()
        restoreArticleWindowsIfNeeded()
        refreshFeedsOnLaunchIfNeeded()
        configureFeedJumpKeyMonitor()
    }
```

Direkt nach der bestehenden Funktion `selectPreviousFeedWithUnread()` (endet nach Zeile 766)
einfügen:

```swift

    /// Registriert die beiden `FeedJumpKeyMonitor`-Closures einmalig (nicht
    /// bei jedem Render) und startet den Monitor. Sicher als einmalige
    /// Registrierung, weil `@State`-Properties intern eine über Struct-
    /// Kopien hinweg geteilte Box referenzieren — ruft die Closure später
    /// `selectedFeedID` o. ä. auf, liest sie stets den aktuellen Wert, nicht
    /// den zum Registrierungszeitpunkt.
    private func configureFeedJumpKeyMonitor() {
        FeedJumpKeyMonitor.shared.isEligible = { direction in
            guard selectedFeedID != nil,
                  selectedSQLiteArticleID != nil,
                  !isJumpingToFeedWithUnread
            else {
                return false
            }

            switch direction {
            case .next:
                return sqliteArticleNavigationState.nextArticleID == nil
            case .previous:
                return sqliteArticleNavigationState.previousArticleID == nil
            }
        }

        FeedJumpKeyMonitor.shared.performJump = { direction in
            switch direction {
            case .next:
                selectNextFeedWithUnread()
            case .previous:
                selectPreviousFeedWithUnread()
            }
        }

        FeedJumpKeyMonitor.shared.startMonitoring()
    }
```

- [ ] **Step 5: `ContentWindowObserver`-Bridge-View ergänzen**

In `Feedivo/Views/ContentView.swift`, direkt nach der schließenden `}` der `ContentView`-Struct
(aktuell Zeile 972, direkt vor `private struct CleanupToast: Equatable {`) einfügen:

```swift

/// Unsichtbare Bridge-View, die ausschließlich die eigene `NSWindow`-
/// Referenz an `FeedJumpKeyMonitor.shared.contentWindow` weiterreicht —
/// analog zu `FullScreenTransitionObserver` in `SQLiteReaderView.swift`.
/// Grundlage für den Fenster-Identitäts-Check im NSEvent-Monitor-Fallback
/// des automatischen Feed-Sprungs (verhindert, dass Pfeiltasten-Ereignisse
/// in anderen Fenstern wie Suche/Organizer/Artikel-Popout fälschlich einen
/// Feed-Sprung im Hauptfenster auslösen).
private struct ContentWindowObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            FeedJumpKeyMonitor.shared.contentWindow = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        FeedJumpKeyMonitor.shared.contentWindow = nsView.window
    }
}
```

- [ ] **Step 6: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Regressionscheck der gesamten Testsuite**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO`
Expected: PASS (unverändert gegenüber Task 1, da Task 2 keine neue testbare Logik hinzufügt —
reine UI-/AppKit-Verdrahtung)

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Views/ContentView.swift
git commit -m "Fix: NSEvent-Monitor-Fallback fuer automatischen Feed-Sprung ersetzt wirkungslosen onKeyPress-Ansatz"
```

- [ ] **Step 9: Manuelle Live-Verifikationscheckliste dokumentieren (nicht automatisierbar)**

Kein computer-use-Zugriff auf native macOS-Apps in dieser Umgebung verfügbar. Folgende Punkte
bleiben für den Nutzer als manuelle Checkliste offen und sollten in `CLAUDE.md` unter
„Aktuell in Arbeit" als ausstehend vermerkt werden, sobald dieser Plan abgeschlossen ist:

1. Feed mit genau einem ungelesenen Artikel auswählen, lesen, dann nochmal Pfeil-Runter —
   springt jetzt tatsächlich zum nächsten Feed mit ungelesenen Artikeln (der entscheidende,
   beim Primäransatz fehlgeschlagene Test).
2. Symmetrisch mit Pfeil-Hoch am Anfang der Liste — springt zum vorherigen Feed mit
   ungelesenen Artikeln.
3. In der Sidebar mit Pfeiltasten durch die Feed-Liste blättern, während irgendein ANDERER
   (nicht ausgewählter) Feed zufällig „am Ende seiner ungelesenen Artikel" ist — die
   Sidebar-Navigation bleibt normal, kein ungewollter Feed-Sprung.
4. Einen Artikel in Web-Ansicht öffnen (WKWebView), in den Artikeltext klicken (WKWebView hat
   dann den Fokus), Pfeil-Runter drücken, während der aktuelle Feed am Ende seiner
   ungelesenen Artikel ist — Seite scrollt normal, kein Feed-Sprung.
5. Suchfenster oder Organizer-Fenster öffnen, dort mit Pfeiltasten navigieren, während im
   Hintergrund das Hauptfenster einen Feed am Ende seiner ungelesenen Artikel zeigt — kein
   Feed-Sprung im Hintergrundfenster.
6. Feed mit mehreren ungelesenen Artikeln: normales Durchnavigieren mit Pfeil-Runter
   innerhalb des Feeds bleibt unverändert (kein vorzeitiger Sprung).
7. Letzter Feed mit ungelesenen Artikeln in der Sidebar-Reihenfolge: Pfeil-Runter am Ende
   tut nichts (kein Wraparound).
8. Feed-Sprung funktioniert unabhängig davon, ob der Ziel-Feed einsortiert oder in einem
   Ordner liegt, und respektiert die Ordner-Reihenfolge (nicht nur alphabetisch).
9. Smart Folder/Tag-Auswahl: Pfeil-Runter am Ende bleibt unverändert wirkungslos (kein
   Feed-Sprung außerhalb von Einzel-Feed-Auswahl).
10. Rechts-/Links-Pfeil und Eingabetaste (Reader-Ansichtswechsel/Original öffnen) verhalten
    sich weiterhin exakt wie vor diesem Fix — keine Regression durch die neue globale
    `NSEvent`-Abfangung.

---

## Self-Review-Notiz für den Plan-Autor (nicht Teil der Ausführung)

- Spec-Abdeckung: Alle Punkte der Spec (`FeedJumpKeyMonitor`-Architektur, Monitor-
  Callback-Reihenfolge inkl. WKWebView-/NSOutlineView-Ausschluss, `ContentWindowObserver`,
  Entfernung der toten `.onKeyPress`-Blöcke, `nonisolated`-Testbarkeit der reinen
  Richtungs-Klassifikation) sind auf Tasks 1-2 abgebildet.
- Platzhalter-Scan: keine TBD/TODO-Stellen; jeder Code-Block ist vollständig ausgeschrieben.
- Typkonsistenz geprüft: `FeedJumpKeyMonitor.Direction` (Task 1) wird in Task 2 identisch als
  `.next`/`.previous` in den Closures verwendet; `isEligible`/`performJump`/`contentWindow`/
  `startMonitoring()` werden in Task 2 exakt mit den in Task 1 definierten Signaturen
  aufgerufen; `selectNextFeedWithUnread()`/`selectPreviousFeedWithUnread()` (bereits
  bestehend, unverändert) werden korrekt referenziert.
- Zeilennummern (Task 2) wurden am tatsächlichen Stand von `ContentView.swift` verifiziert
  (Stand: Commit `c491a63ff`) — bei Abweichung durch zwischenzeitliche Änderungen gilt der
  Textinhalt der Code-Blöcke als Quelle der Wahrheit, nicht die Zeilennummer.
