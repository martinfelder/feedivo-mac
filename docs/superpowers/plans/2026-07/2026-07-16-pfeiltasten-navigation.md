# Pfeiltasten-Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rechts-/Links-Pfeiltaste steuern einen festen, nicht anpassbaren Übergang
native Reader-Ansicht → eingebettete Originalansicht → externer Browser (und zurück).
Hoch/Runter für die Artikelliste sind bereits durch natives macOS-`List`-Verhalten
abgedeckt und brauchen keine Implementierung.

**Architecture:** Reine Zustandsübergangs-Logik in einer neuen, isoliert testbaren
`ReaderArrowKeyNavigation`-Datei; Verdrahtung als `.onKeyPress(.rightArrow)`/
`.onKeyPress(.leftArrow)` am Wurzel-Container von `ContentView.body`, wiederverwendet
bestehende Bausteine (`ReaderDisplayMode`, `ArticleOriginalURLResolver`,
`openSelectedSQLiteArticleOriginal()`).

**Tech Stack:** SwiftUI (macOS 14+, `.onKeyPress` API), Swift Testing für die reine
Logik, kein neuer State/keine neue Persistenz.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-16-pfeiltasten-navigation-design.md` — bei
  Widersprüchen zwischen Plan und Spec gilt die Spec.
- Kommentare im Code auf Deutsch (Projektkonvention, siehe `CLAUDE.md`).
- `xcodebuild build` muss nach jedem Task grün sein: `xcodebuild build -project Feedivo.xcodeproj
  -scheme Feedivo -destination 'platform=macOS'`.
- Tests laufen gezielt: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo
  -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests
  -parallel-testing-enabled NO`.
- KEINE Anpassbarkeit über die Shortcuts-Einstellungen (`CustomizableShortcut`) —
  dieses Feature ist bewusst fest eingebaut, nicht Teil dieses Systems.
- KEIN Wraparound-Verhalten für Hoch/Runter (unverändertes bestehendes Verhalten von
  `SQLiteArticleNavigationState`), kein Task dafür nötig.
- Hoch/Runter selbst brauchen KEINEN Implementierungs-Task — funktionieren bereits
  nativ (siehe Spec, „Rechercheergebnis"). Nur in der manuellen Checkliste verifiziert.

---

## Task 1: Reine Zustandsübergangs-Logik (`ReaderArrowKeyNavigation`)

**Files:**
- Create: `Feedivo/Views/Reader/ReaderArrowKeyNavigation.swift`
- Test: `FeedivoTests/FeedivoTests.swift` (direkt vor der schließenden `}` der
  `FeedivoTests`-Struct)

**Interfaces:**
- Produces: `enum ReaderArrowKeyNavigation` mit
  `static func rightArrowResult(currentMode: ReaderDisplayMode) -> RightArrowResult`
  (`RightArrowResult` ist ein `enum: Equatable` mit Fällen `.switchToWeb`,
  `.openInBrowser`) und `static func leftArrowShouldSwitchToNative(currentMode:
  ReaderDisplayMode) -> Bool`.
- Consumes: `ReaderDisplayMode` (bereits vorhanden, `Feedivo/Views/Reader/
  ReaderDisplayMode.swift`, Fälle `.native`/`.web`).

- [ ] **Step 1: Failing Test schreiben**

In `FeedivoTests/FeedivoTests.swift`, direkt vor der schließenden `}` der
`FeedivoTests`-Struct einfügen:

```swift

    @Test func readerArrowKeyNavigationRechtsWechseltVonNativeZuWeb() {
        #expect(ReaderArrowKeyNavigation.rightArrowResult(currentMode: .native) == .switchToWeb)
    }

    @Test func readerArrowKeyNavigationRechtsOeffnetBrowserImWebModus() {
        #expect(ReaderArrowKeyNavigation.rightArrowResult(currentMode: .web) == .openInBrowser)
    }

    @Test func readerArrowKeyNavigationLinksWechseltNurAusWebModusZurueck() {
        #expect(ReaderArrowKeyNavigation.leftArrowShouldSwitchToNative(currentMode: .web) == true)
        #expect(ReaderArrowKeyNavigation.leftArrowShouldSwitchToNative(currentMode: .native) == false)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/readerArrowKeyNavigationRechtsWechseltVonNativeZuWeb -parallel-testing-enabled NO`
Expected: FAIL — Compile-Fehler, `ReaderArrowKeyNavigation` existiert noch nicht.

- [ ] **Step 3: `ReaderArrowKeyNavigation.swift` anlegen**

Neue Datei `Feedivo/Views/Reader/ReaderArrowKeyNavigation.swift`:

```swift
import Foundation

/// Reine Übergangslogik für die feste (nicht über die Shortcuts-Einstellungen
/// anpassbare) Rechts-/Links-Pfeiltasten-Navigation im Reader: Rechts wechselt
/// von der nativen Ansicht zur eingebetteten Originalansicht, ein zweites Mal
/// Rechts öffnet den Artikel im externen Browser; Links geht von der
/// Originalansicht zurück zur nativen Ansicht. Als eigener Typ isoliert, damit
/// die Zustandsübergänge unabhängig von der `.onKeyPress`-Verdrahtung in
/// `ContentView.swift` unit-testbar sind (SwiftUI-Tastatur-Events selbst sind
/// in diesem Projekt nicht automatisiert testbar).
enum ReaderArrowKeyNavigation {
    enum RightArrowResult: Equatable {
        case switchToWeb
        case openInBrowser
    }

    static func rightArrowResult(currentMode: ReaderDisplayMode) -> RightArrowResult {
        switch currentMode {
        case .native:
            return .switchToWeb
        case .web:
            return .openInBrowser
        }
    }

    static func leftArrowShouldSwitchToNative(currentMode: ReaderDisplayMode) -> Bool {
        currentMode == .web
    }
}
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/readerArrowKeyNavigationRechtsWechseltVonNativeZuWeb -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Verbleibende neue Tests + Regressionscheck**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO`
Expected: PASS (alle Tests der Datei, inkl. der 3 neuen)

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Reader/ReaderArrowKeyNavigation.swift FeedivoTests/FeedivoTests.swift
git commit -m "Feature: Reine Zustandsuebergangs-Logik fuer Pfeiltasten-Reader-Navigation"
```

---

## Task 2: `.onKeyPress`-Verdrahtung in `ContentView.swift`

**Files:**
- Modify: `Feedivo/Views/ContentView.swift`

**Interfaces:**
- Consumes: `ReaderArrowKeyNavigation.rightArrowResult(currentMode:)` /
  `.leftArrowShouldSwitchToNative(currentMode:)` aus Task 1;
  `ReaderDisplayMode.storageKey`/`.defaultMode`/`.resolved(from:)` (bereits vorhanden);
  `ArticleOriginalURLResolver.hasUsableWebLink(_:)` (bereits vorhanden,
  `Feedivo/ViewModels/ArticleURLHelpers.swift:44`); die bestehenden `private var
  selectedSQLiteArticleID: String?`, `private var selectedSQLiteArticleSnapshot:
  ArticleReaderSnapshot?` und `private func openSelectedSQLiteArticleOriginal()`
  (`ContentView.swift:757`).
- Produces: sichtbares Endverhalten, keine neuen öffentlichen Interfaces für
  spätere Tasks (letzter Task des Plans).

**Hinweis:** Reine SwiftUI-`.onKeyPress`-Verdrahtung in einer komplexen
Multi-Spalten-View ist im Projekt nicht isoliert unit-testbar (kein ViewInspector,
wie bereits bei ähnlichen UI-Änderungen etabliert) — Verifikation über Build + die
in Step 4 dokumentierte manuelle Live-Checkliste.

- [ ] **Step 1: Neue `@AppStorage`-Property ergänzen**

In `Feedivo/Views/ContentView.swift`, direkt nach der bestehenden Zeile 41
(`@State private var sqliteArticleNavigationState = SQLiteArticleNavigationState.empty`)
einfügen:

```swift
    @AppStorage(ReaderDisplayMode.storageKey)
    private var readerDisplayModeRawValue = ReaderDisplayMode.defaultMode.rawValue
```

- [ ] **Step 2: `.onKeyPress`-Modifier ergänzen**

In `Feedivo/Views/ContentView.swift`, direkt nach der bestehenden Zeile 158
(`.onChange(of: selectedSQLiteArticleID, handleSQLiteArticleSelectionChange)`, vor
`.onAppear(perform: handleContentAppear)`) einfügen:

```swift
        // Feste, nicht über die Shortcuts-Einstellungen anpassbare Pfeiltasten-
        // Navigation: Rechts/Links steuern den Reader-Zustand (native ↔ Web-
        // Ansicht ↔ externer Browser). Am Wurzel-Container angehängt, damit
        // SwiftUIs Tastatur-Event-Bubbling die Events unabhängig davon erreicht,
        // ob die Artikelliste oder der Reader gerade den Fokus hat — beide
        // konsumieren Rechts/Links nicht selbst (im Gegensatz zu Hoch/Runter,
        // die die Artikelliste bereits nativ für die Zeilennavigation nutzt).
        // Ein fokussiertes Textfeld konsumiert Rechts/Links für die
        // Cursor-Bewegung, bevor das Event hierher blubbert — kollisionsfrei.
        .onKeyPress(.rightArrow) {
            guard selectedSQLiteArticleID != nil,
                  ArticleOriginalURLResolver.hasUsableWebLink(selectedSQLiteArticleSnapshot?.link)
            else {
                return .ignored
            }

            switch ReaderArrowKeyNavigation.rightArrowResult(
                currentMode: ReaderDisplayMode.resolved(from: readerDisplayModeRawValue)
            ) {
            case .switchToWeb:
                readerDisplayModeRawValue = ReaderDisplayMode.web.rawValue
            case .openInBrowser:
                openSelectedSQLiteArticleOriginal()
            }

            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard selectedSQLiteArticleID != nil,
                  ReaderArrowKeyNavigation.leftArrowShouldSwitchToNative(
                      currentMode: ReaderDisplayMode.resolved(from: readerDisplayModeRawValue)
                  )
            else {
                return .ignored
            }

            readerDisplayModeRawValue = ReaderDisplayMode.native.rawValue
            return .handled
        }
```

- [ ] **Step 3: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Regressionscheck der gesamten Testsuite**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO`
Expected: PASS (unverändert gegenüber Task 1, da Task 2 keine testbare Logik
hinzufügt — reine UI-Verdrahtung)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ContentView.swift
git commit -m "Feature: Rechts-/Links-Pfeiltaste steuern Reader-Ansichtswechsel (native/Web/Browser)"
```

- [ ] **Step 6: Manuelle Live-Verifikationscheckliste dokumentieren (nicht automatisierbar)**

Kein computer-use-Zugriff auf native macOS-Apps in dieser Umgebung verfügbar
(Projektkonvention, siehe `CLAUDE.md`). Folgende Punkte bleiben für den Nutzer als
manuelle Checkliste offen — sie sollten in `CLAUDE.md` unter „Aktuell in Arbeit" als
ausstehend vermerkt werden, sobald dieser Plan abgeschlossen ist:

1. Artikel in der Liste anklicken, dann Pfeil-Runter/-Hoch drücken — Artikelliste
   navigiert zum nächsten/vorherigen Artikel, Reader aktualisiert sich (sollte
   bereits ohne diese Code-Änderung funktionieren, hier nur bestätigen).
2. Bei ausgewähltem Artikel in nativer Ansicht Rechts-Pfeil drücken — wechselt zur
   eingebetteten Originalansicht (WKWebView, sichtbar am Picker in der Reader-
   Toolbar).
3. Nochmals Rechts-Pfeil im Web-Zustand — öffnet den Artikel im externen
   Standard-Browser.
4. Links-Pfeil im Web-Zustand — wechselt zurück zur nativen Ansicht.
5. **Entscheidender Fokus-Test:** Rechts-/Links-Pfeil funktioniert sowohl direkt
   nach Artikelauswahl (Artikelliste fokussiert) als auch nach Klick in den
   Reader-Bereich — SwiftUI-Fokus-Bubbling über `NavigationSplitView`-
   Spaltengrenzen hinweg ist nicht vorab garantiert.
6. Ohne ausgewählten Artikel bzw. bei einem Artikel ohne nutzbaren Link (z. B.
   reiner Text-/Podcast-Feed ohne externen Link): Rechts-/Links-Pfeil tun nichts,
   keine falsche Reaktion, kein Absturz.
7. Rechts-Pfeil bei fokussiertem Textfeld (Suche, Umbenennen, Tag-/Regel-Name)
   bewegt weiterhin nur den Text-Cursor, löst keinen Reader-Zustandswechsel aus.

---

## Self-Review-Notiz für den Plan-Autor (nicht Teil der Ausführung)

- Spec-Abdeckung: Rechercheergebnis „Hoch/Runter brauchen keinen Code" ist im
  Header und den Global Constraints festgehalten (kein eigener Task, wie in der
  Spec verlangt). Architektur-Abschnitt („Warum kein CustomizableShortcut",
  Rechts-/Links-Handler, kein neuer State) ist auf Task 1 (reine Logik) + Task 2
  (Verdrahtung) abgebildet. Testing-Abschnitt der Spec (reine Logik testbar, UI
  nicht) ist 1:1 in der Task-Aufteilung umgesetzt. Alle 7 Punkte der
  Live-Verifikationscheckliste aus der Spec sind in Task 2 Step 6 übernommen.
- Platzhalter-Scan: keine TBD/TODO-Stellen; jeder Code-Block ist vollständig
  ausgeschrieben, keine „analog zu Task N"-Verweise.
- Typkonsistenz geprüft: `ReaderArrowKeyNavigation.RightArrowResult` (Task 1) wird
  in Task 2 mit identischen Fallnamen (`.switchToWeb`/`.openInBrowser`)
  verwendet; `ReaderDisplayMode.resolved(from:)`/`.storageKey`/`.defaultMode`
  (bereits bestehend, verifiziert in `ReaderDisplayMode.swift` und dem
  identischen `@AppStorage`-Muster in `SQLiteReaderView.swift:57-58`) werden in
  Task 2 konsistent mit der bestehenden Codebasis verwendet, keine erfundenen
  Signaturen.
