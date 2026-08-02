# Artikel-Tabs im Reader-Bereich — Design Spec

**Datum:** 2026-08-02
**Status:** Zur Review

## Kontext / Problem

Artikel öffnen sich aktuell entweder direkt im Reader-Bereich des Hauptfensters
(`ContentView.swift`, 3-Spalten-`NavigationSplitView`) — strikt 1 Artikel pro
Reader-Pane, gesteuert über einen einzelnen `selectedSQLiteArticleID`-State —
oder per „In neuem Fenster öffnen" in einem eigenständigen Popout-Fenster
(`ArticleWindowView`, `WindowGroup(for: ArticleWindowRequest.self)` in
`FeedivoApp.swift`). Es gibt aktuell keine Möglichkeit, mehrere Artikel
gleichzeitig innerhalb eines Fensters offen zu halten und zwischen ihnen zu
wechseln, wie man es aus Browsern kennt.

Nutzerwunsch: Artikel sollen wie Browser-Tabs im Reader-Bereich des
Hauptfensters geöffnet werden können — mehrere gleichzeitig offene Tabs mit
unterschiedlichen Artikeln, inkl. der Möglichkeit, einen Artikel explizit in
einem neuen Tab zu öffnen (bisher war das nur als neues Fenster möglich).

## Ziel

Der Reader-Bereich des Hauptfensters bekommt eine Tab-Leiste, mit der mehrere
Artikel gleichzeitig offen gehalten und per Klick gewechselt werden können —
analog zum Tab-Verhalten in Browsern wie Safari/Chrome.

## Nicht-Ziele (bewusst außerhalb von v1)

- Tabs per Drag & Drop umsortieren
- „Zuletzt geschlossene Tabs wieder öffnen" (⌘⇧T)
- Tabs aus dem Hauptfenster in ein eigenes Fenster herausziehen (deckt das
  bestehende Popout-Feature bereits ab)
- Änderungen am bestehenden Popout-Fenster („In neuem Fenster öffnen") — bleibt
  unverändert als zusätzliche, unabhängige Option bestehen

## Architektur & Datenmodell

Neuer State `ReaderTabsState` (analog zu bestehenden State-Objekten wie
`SQLiteReaderState`), im Hauptfenster-Scope (`ContentView.swift`) gehalten:

- `tabs: [ReaderTab]` — jeder Tab hält minimal `id: UUID` + `articleID: UUID`.
  Titel, Feed-Name und Favicon werden beim Rendern aus dem ohnehin geladenen
  Artikel-Snapshot gezogen, nicht separat im Tab-Modell dupliziert.
- `activeTabID: ReaderTab.ID?`

Der Reader-Bereich (`SQLiteReaderView`) zeigt immer den Artikel des aktiven
Tabs. Das ersetzt den bisherigen `selectedSQLiteArticleID`-Mechanismus nicht
strukturell — er wird zur Quelle für den Inhalt des aktiven Tabs.

Tabs sind vollständig unabhängig von der Sidebar-/Artikellisten-Auswahl: ein
Wechsel des Feeds/Ordners in der Sidebar ändert nur, was in der Artikelliste
angezeigt wird, nie die offenen Tabs.

## Interaktionsverhalten

- **Einzelklick auf Artikel in der Liste** aktualisiert den Inhalt des
  **aktiven** Tabs (kein neuer Tab) — wie Link-Navigation im selben
  Browser-Tab.
- **Neuen Tab explizit öffnen**, über drei gleichwertige Wege:
  - Kontextmenü-Eintrag „In neuem Tab öffnen" auf einer Artikelzeile
  - ⌘-Klick auf eine Artikelzeile
  - ⌘T (dupliziert den aktuell aktiven Tab; ist kein Tab offen, aber ein
    Artikel in der Liste ausgewählt, wird dieser als erster Tab geöffnet)
- **Neue Tabs öffnen immer im Hintergrund** — der aktive Tab bleibt bestehen,
  der neue Tab wird nur der Tab-Leiste hinzugefügt, ohne den Reader-Fokus zu
  wechseln. Gilt einheitlich für alle drei Auslöser oben.
- **Pfeiltasten-Navigation** (bestehendes Feature: Hoch/Runter in der Liste)
  navigiert weiter durch die Liste und aktualisiert dabei den aktiven Tab —
  konsistent mit „Klick aktualisiert aktiven Tab".
- **⌘W** schließt den aktiven Tab. **⌘⇧]** / **⌘⇧[** wechseln zum
  nächsten/vorherigen Tab (Safari-Konvention).
- Schließt man den letzten Tab, zeigt der Reader wieder den heutigen „kein
  Artikel ausgewählt"-Leerzustand; die Tab-Leiste verschwindet, bis wieder ein
  Tab geöffnet wird.
- **Gelesen-Markierung:** Der aktive Tab markiert seinen Artikel wie bisher
  beim Anzeigen als gelesen. Im Hintergrund geöffnete Tabs markieren ihren
  Artikel **nicht** sofort als gelesen — erst wenn der Tab tatsächlich aktiv
  wird (Browser-Semantik: eine im Hintergrund geöffnete Seite gilt noch nicht
  als gelesen).

## UI-Design (Tab-Leiste)

Stil: **Chrome-Register** — Tabs sitzen direkt über dem Reader-Bereich,
aneinandergereiht; der aktive Tab hebt sich optisch als eigene Kartenfläche
nach oben ab (siehe Mockup-Auswahl während des Brainstormings).

- Jeder Tab zeigt Feed-Favicon (wiederverwendet aus der bestehenden
  Favicon-Infrastruktur, z. B. wie in Sidebar/Artikelliste) + gekürzten
  Artikeltitel.
- Schließen-Kreuz erscheint bei Hover über dem Tab.
- „+"-Button am rechten Ende der Leiste öffnet einen neuen Tab (Verhalten wie
  ⌘T: dupliziert den aktiven Tab).
- Bei vielen offenen Tabs schrumpfen alle Tabs gemeinsam auf eine
  Mindestbreite (nur noch Favicon + wenig Text) — kein horizontales Scrollen,
  keine Overflow-Menü-UI in v1.
- Die Tab-Leiste erscheint nur, sobald mindestens ein Tab offen ist; im
  heutigen „kein Artikel ausgewählt"-Zustand bleibt sie unsichtbar.

## Umgang mit gelöschten Artikeln

Wird der Artikel eines offenen Tabs zwischenzeitlich gelöscht (z. B. durch die
automatische Bereinigung), bleibt der Tab in der Leiste bestehen und zeigt
statt des Readers einen Hinweistext („Artikel nicht mehr verfügbar"). Der Tab
lässt sich normal schließen; Position und Reihenfolge der übrigen Tabs bleiben
stabil.

## Persistenz & Einstellungen

Neuer Einstellungen-Schalter „Offene Tabs beim Neustart wiederherstellen"
(Ort: vermutlich Tab „Artikelliste", analog zu bestehenden
`FeedJumpNavigationSettings`). Bei Aktivierung werden offene Tab-Artikel-IDs
inkl. des aktiven Tabs analog zu `ArticleWindowSettings.rememberOpenArticleID`
gespeichert und beim App-Start wiederhergestellt. Standardwert: AUS (Tabs sind
per Default nur für die laufende Sitzung, wie das im vorherigen Zustand der
App üblich war — kein bestehendes Verhalten wird automatisch geändert).

## Tastaturkürzel (Zusammenfassung)

| Kürzel | Aktion |
|---|---|
| ⌘T | Aktiven Tab duplizieren (neuer Hintergrund-Tab mit demselben Artikel) |
| ⌘W | Aktiven Tab schließen |
| ⌘⇧] / ⌘⇧[ | Zum nächsten/vorherigen Tab wechseln |
| ⌘-Klick auf Artikelzeile | Artikel in neuem Hintergrund-Tab öffnen |

Menübefehle werden analog zu den bestehenden Mustern in `ArticleCommands.swift`
/ `ArticleCommandActions.swift` ergänzt (z. B. „Neuer Tab", „Tab schließen").

## Beziehung zu bestehenden Features

- **Popout-Fenster** („In neuem Fenster öffnen", `ArticleWindowView`) bleibt
  unverändert als zusätzliche, unabhängige Option bestehen — Kontextmenü
  bietet künftig beide Einträge nebeneinander an: „In neuem Tab öffnen" und
  „In neuem Fenster öffnen".
- **Automatischer Feed-Sprung** (Pfeiltasten am Ende der ungelesenen Artikel
  eines Feeds) aktualisiert weiterhin den aktiven Tab, unverändert zur
  bisherigen Logik für `selectedSQLiteArticleID`.
- **Sticky-Row-Verhalten der Artikelliste** bleibt unverändert — betrifft nur
  die Listenansicht, nicht die Tab-Leiste.

## Offene technische Fragen für die Implementierungsplanung

- Exakte Platzierung des neuen Einstellungen-Schalters (welcher Tab in den
  Einstellungen).
- Ob `ReaderTabsState` als eigenständiges `@Observable`-Objekt oder als Teil
  von `ContentView`s bestehendem State eingeführt wird — folgt dem in
  `writing-plans` zu erarbeitenden Implementierungsplan, orientiert an
  bestehenden State-Objekten wie `SQLiteReaderState`/`SQLiteSidebarState`.
