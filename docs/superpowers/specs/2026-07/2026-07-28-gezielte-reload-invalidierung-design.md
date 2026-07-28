# Gezielte statt globale Reload-Invalidierung — Design

Stand: 2026-07-28

## Ausgangspunkt

Punkt 1 des NetNewsWire-Performance-Vergleichs
(`docs/performance/netnewswire-feedivo-mechanik-vergleich.md`, Update
2026-07-28). `SQLiteDataInvalidation.bumpStatusVersion()` ist ein einziger
globaler `Int`-Zähler in `UserDefaults`, ohne Scope/Payload, mit ~41
Aufrufstellen app-weit (Artikelstatus, Feed-Metadaten, Sidebar-Struktur,
Regeln, Smart Folders, Sync). Jeder Bump löst in JEDER offenen
`SQLiteFeedArticleListView` einen vollen SQL-Reload aus sowie einen vollen
Sidebar-Reload in `ContentView` — unabhängig davon, ob die Mutation den
jeweils sichtbaren Scope überhaupt betrifft. Es gibt keinen Vergleichsschritt
vor dem Reload (anders als NetNewsWires `representSameArticlesInSameOrder`).

**Ausdrücklich kein Direktvergleich mit einer Messung**: anders als bei den
bereits umgesetzten Punkten 4–6 gibt es hier keine konkrete gemessene Zahl,
die den Redundanz-Effekt beziffert — dieser Punkt ist ein architektureller
Aufräumpunkt, kein bewiesener Flaschenhals.

## Entscheidung: gezielte, risikoarme Fixes statt Großumbau

Ein vollständiger Umstieg auf ein Payload-basiertes "diese ID hat sich
geändert"-Signal würde potenziell alle ~41 Aufrufstellen berühren — zu
großes Regressions-Fenster ohne vorherige Messung des tatsächlichen Nutzens
(siehe Erfahrung mit Punkt 5: ein architektonisch "richtiger" wirkender
Umbau kollidierte dort mit einer bestehenden, bewusst gesetzten Invariante).
Stattdessen drei abgegrenzte, unabhängig überprüfbare Teile, die
ausschließlich die Konsumenten-Seite (`SQLiteFeedArticleListState`/View)
berühren — keine der 41 Bump-Aufrufstellen wird verändert.

## Teil A — Redundante Re-Renders vermeiden (Befund: bereits vorhanden)

`SQLiteFeedArticleListState.startLoad(_:)` (`SQLiteFeedArticleListState.swift:456`)
weist `self.rows` bei jedem Reload unbedingt neu zu — die ursprüngliche
Annahme war, dass das bei inhaltlich identischem SQL-Ergebnis unnötig
`@Observable`-Benachrichtigungen (und damit SwiftUI-Re-Renders) auslöst.

**Per Standalone-Kontrolltest widerlegt:** Swifts `@Observable`-Makro prüft
bei der generierten Setter-Implementierung bereits selbst auf Gleichheit,
bevor es Beobachter benachrichtigt (`withMutation`/Observation-Framework,
verifiziert mit einem isolierten `swift`-Skript: identische Array-Zuweisung
löst `onChange` NICHT aus, eine tatsächlich andere Zuweisung schon). Ein
expliziter `if result.rows != self.rows { self.rows = result.rows }`-Guard
in `startLoad(_:)` wäre damit totes Gewicht — das Framework leistet das
bereits automatisch, für `rows` ebenso wie für `navigationState`/`hasMore`/
`totalUnreadCount`/`loadState`.

**Kein Produktionscode-Fix nötig.** Der ursprünglich für RED/GREEN gedachte
Test bleibt trotzdem als Regressionsschutz bestehen — er dokumentiert eine
bisher nirgends im Projekt festgehaltene, wichtige Eigenschaft (falls
`rows` je in einen Referenztyp/anderen Speichermechanismus geändert würde,
der diese Optimierung verliert, schlägt der Test das sofort an).

## Teil B — Bump-Bursts bündeln

Neue debounced Zwischenstufe in `SQLiteFeedArticleListView`: `sqliteStatusVersion`
(roh, `@AppStorage`) → kurze Wartezeit → `debouncedStatusVersion` (`@State`),
die statt der rohen Version in `loadToken` einfließt. Mehrere Bumps
innerhalb der Wartezeit (z. B. Refresh-All über viele Feeds, mehrere
Regelanwendungen in Folge) lösen dadurch nur einen Reload aus statt N.

Technisch: `SearchDebounce.wait()` (`Feedivo/Extensions/SearchDebounce.swift`)
bekommt einen optionalen `milliseconds`-Parameter (Default = bisheriges
Verhalten `delayMilliseconds = 250`, keine Bestandsänderung für den
bestehenden Suchtext-Aufrufer) statt einer dritten, abweichenden
Debounce-Implementierung — dieselbe Lehre, die ursprünglich zur Einführung
von `SearchDebounce` als gemeinsamem Baustein führte. Neuer Aufruf mit
kürzerer, eigener Wartezeit (200ms) für die Status-Version-Debounce.
`.task(id: sqliteStatusVersion) { await updateDebouncedStatusVersion() }`
nach demselben Muster wie `updateDebouncedSearchText()`.

**Scope-Begrenzung:** Nur `SQLiteFeedArticleListView` (die primäre,
scroll-relevante Liste). Andere Konsumenten von `sqliteStatusVersion`
(Sidebar in `ContentView`, Suchfenster, Reader-Fenster, Menubar-Popover,
Sync-Tab) bleiben unangetastet — konsistent mit der gewählten
"gezielt statt Großumbau"-Linie.

## Teil C — Bugfix `stickyRowSnapshots`-Inkonsistenz

Beim Recherchieren gefunden, direkt am selben Code-Pfad: `toggleStarred`/
`toggleArchived` (`SQLiteFeedArticleListView.swift:941-957`) befüllen
`stickyRowSnapshots` NICHT, im Unterschied zu `toggleRead`
(Zeile 889-899) und `markSelectedArticleReadIfNeeded()` (Zeile 901-916).
Ein Artikel, dessen Stern/Archiv-Status in einem entsprechend gefilterten
Smart Folder (z. B. "Status ist markiert") geändert wird, verschwindet
dadurch beim nächsten Reload sofort, ohne die Karenzzeit, die
Lesen-Markieren bereits hat.

**Fix:** dieselbe `stickyRowSnapshots[articleID] = row`-Zeile (aus
`state.rows` nach der Mutation gelesen) in beide Funktionen ergänzen.

## Testing

- **Teil A:** neuer Test in `SQLiteFeedArticleListStateTests.swift` —
  zwei aufeinanderfolgende `state.load(...)`-Aufrufe mit identischem
  Scope/Inhalt; `withObservationTracking { _ = state.rows } onChange: { ... }`
  (Swift Observation Framework, bereits `import Observation` in dieser
  Datei) registriert VOR dem zweiten Load, `onChange` darf nach dem zweiten,
  inhaltlich identischen Load NICHT feuern. War entgegen der ursprünglichen
  Annahme bereits ohne Codeänderung grün (siehe Befund oben) — bleibt als
  Regressionstest für das `@Observable`-Verhalten bestehen.
- **Teil B:** reine Timing-Logik, analog zur bestehenden Such-Debounce nicht
  gesondert unit-getestet (kein bestehender Präzedenzfall für
  Timing-Tests in diesem Bereich) — Build-Verifikation, Verhalten selbst
  über den erweiterten `milliseconds`-Parameter isoliert nachvollziehbar.
- **Teil C:** `stickyRowSnapshots` ist View-lokaler `@State` in
  `SQLiteFeedArticleListView` (SwiftUI View struct) — wie der Rest der
  View-Wiring in diesem Projekt nicht automatisiert testbar (kein
  ViewInspector). Build-Verifikation plus manuelle Live-Prüfung durch den
  Nutzer (Stern/Archiv-Status in einem gefilterten Smart Folder ändern,
  Artikel bleibt bis zum Scope-Wechsel sichtbar).

## Offene Punkte / Risiken

- Kein computer-use für native macOS-Apps in dieser Umgebung — Teil B/C
  bleiben in ihrer tatsächlichen Wirkung auf die manuelle Live-Verifikation
  durch den Nutzer angewiesen.
- Teil A's Nutzen ist am größten bei eigenen Toggles in ungefiltertem Scope
  (der häufigste Fall); bei gefilterten Smart Folders bleibt der Reload
  ohnehin relevant (anderer Datensatz), Teil A greift dort nicht zusätzlich.
