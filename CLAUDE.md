# CLAUDE.md — Feedivo macOS

> Diese Datei ist das Projektgedächtnis für Claude Code und Claude.ai.
> Sie wird bei jedem Gespräch automatisch geladen.
> **Immer aktuell halten wenn sich Entscheidungen ändern!**

---

## Projektübersicht

**App-Name:** Feedivo
**Root-Ordner:** FeedivoMac
**Entry Point:** Feedivo/App/FeedivoApp.swift
**Bundle ID:** ch.martin.Feedivo
**Typ:** Nativer macOS RSS Reader
**Entwickler:** Solo (Martin)
**Plattform:** macOS 14 Sonoma+
**Status:** In Development — Kernfunktionen (M1–M4) fertig und weit darüber hinaus ausgebaut
**Aktueller Fokus:** Härtung/Refactoring nach Feature-Ausbau (SwiftData vollständig entfernt,
GRDB/SQLite ist jetzt alleinige Persistenz); iCloud Sync ist als Beta-Vorbereitung sichtbar,
aber noch nicht funktional angebunden

Feedivo ist ein nativer macOS RSS Reader mit Tags, automatischen Regeln, intelligenten Ordnern,
Offline-Lesen und OPML-Import/-Export. Ziel ist eine schöne, schnelle Mac-App die sich "mac-like"
anfühlt — kein iOS-Port, keine Electron-App. Echtes AppKit-Feeling via SwiftUI für macOS.

---

## Entwickler-Kontext

- Entwickler-Hintergrund: PowerShell / IT-Administration (kein App-Entwickler)
- Swift/Xcode-Level: Anfänger — hat bereits Timivo (iOS) gebaut
- Sprache für Kommentare im Code: Deutsch
- IDE: Xcode 26
- Versionskontrolle: Git + GitHub
- Workflow: Claude Code CLI + Claude.ai (dieses File als Kontext)

> **Für Claude Code:** Erkläre Entscheidungen immer kurz. Kein "magic code" ohne Erklärung.
> Kommentare im Code auf Deutsch. Lieber ein bisschen mehr erklären als zu wenig.

---

## Technologie-Stack

| Bereich | Technologie | Version / Hinweis |
|---|---|---|
| UI Framework | SwiftUI (macOS) | Kein AppKit direkt, punktuell `NSViewRepresentable` (z. B. WKWebView) |
| Architektur | MVVM | `@Observable` Macro (kein ObservableObject) |
| Navigation | NavigationSplitView | 3-Spalten: Sidebar / Artikelliste / Reader, plus separate Fenster (Suche, Organizer, Artikel-Popout) |
| Persistenz | GRDB (SQLite) | Eigene Datenschicht in `Feedivo/Database/` + `Feedivo/Stores/`. SwiftData wurde vollständig entfernt (2026-07-07) |
| iCloud Sync | Noch nicht funktional angebunden | UI-Toggle "iCloud Sync Beta" existiert (`CloudSyncSettings`), aber ohne CloudKit-Backend auf `main`. Aktive Vorarbeit auf separatem Branch `codex/icloud-sync-beta` — basiert noch auf der alten SwiftData-Architektur und muss auf GRDB/SQLite migriert werden, bevor er mergebar ist |
| Netzwerk | URLSession + async/await | Kein Alamofire, kein Combine |
| RSS-Parsing | FeedKit | Swift Package, URL: https://github.com/nmdias/FeedKit |
| Datenbank-Package | GRDB.swift | Swift Package, URL: https://github.com/groue/GRDB.swift |
| Bilder | AsyncImage + eigener `ImageCacheService` | Built-in SwiftUI + eigenes Disk-Caching, kein Kingfisher |
| Artikel-Rendering | Nativer SwiftUI-Renderer (`ReaderContentRenderer`) **und** `WKWebView` (`WebContentView`) | Native Ansicht für den Lesefluss, WKWebView für "Originalartikel" |
| Background Refresh | `NSBackgroundActivityScheduler` (`SystemBackgroundActivityRefreshScheduler`) | Kein `BGTaskScheduler` (das ist iOS-fokussiert) |
| Mindest-macOS | macOS 14.0 Sonoma | `@Observable` Macro + moderne SwiftUI-APIs (NavigationSplitView, `.commands`, `WindowGroup(for:)`) |

---

## Projektstruktur

```
FeedivoMac/
├── Feedivo/
│   ├── App/
│   │   ├── FeedivoApp.swift            # @main Entry Point: öffnet SQLite-DB, registriert Scenes/Commands
│   │   ├── FeedCommands.swift / FeedCommandActions.swift     # Menüleiste: Feed hinzufügen/löschen/refreshen
│   │   ├── ArticleCommands.swift / ArticleCommandActions.swift  # Menüleiste: Artikel navigieren/markieren
│   │   └── ViewCommands.swift          # Menüleiste: Darstellungsoptionen
│   │
│   ├── Database/                       # GRDB/SQLite-Fundament
│   │   ├── FeedivoDatabase.swift               # DatabaseQueue-Wrapper, öffnet/erstellt die DB-Datei
│   │   ├── FeedivoDatabaseMigrator.swift       # Alle Schema-Migrationen (v1…v10, siehe unten)
│   │   ├── FeedivoDatabaseLocation.swift       # Pfad in Application Support
│   │   ├── FeedivoDatabaseEnvironment.swift    # SwiftUI-Environment-Key `\.feedivoDatabase`
│   │   ├── SQLiteDataInvalidation.swift        # AppStorage-Statusversion, triggert UI-Reloads nach Mutationen
│   │   └── Records/                    # GRDB `Codable & FetchableRecord & PersistableRecord`-Structs
│   │       ├── FeedRecord.swift, ArticleRecord.swift, ArticleStatusRecord.swift
│   │       ├── TagRecord.swift, ArticleTagRecord.swift, FeedTagRecord.swift
│   │       ├── RuleRecord.swift, RuleConditionRecord.swift
│   │       ├── SmartFolderRecord.swift, SmartFolderConditionRecord.swift
│   │       ├── FeedFolderRecord.swift, FeedLogRecord.swift
│   │       └── ArticleOfflineRecord.swift, ArticleIdentityHistoryRecord.swift
│   │
│   ├── Stores/                         # Query-/Mutation-Layer über den Records (ein Store pro Tabelle/Domäne)
│   │   ├── FeedStore.swift, ArticleStore.swift, ArticleStatusStore.swift
│   │   ├── TagStore.swift, FeedFolderStore.swift, FeedLogStore.swift
│   │   ├── SQLiteRuleStore.swift, SQLiteRuleEvaluationStore.swift
│   │   ├── SQLiteSmartFolderStore.swift, SQLiteOfflineStore.swift
│   │   └── TimelineStore.swift, ArticleDatabase.swift
│   │
│   ├── Models/                         # Reine Value-Type-Enums (KEINE SwiftData @Model mehr!)
│   │   ├── RuleAction.swift, RuleConditionField.swift, RuleConditionOperator.swift
│   │   ├── RuleMatchMode.swift, RuleNotificationPriority.swift
│   │   └── SmartFolderAppearance.swift, SmartFolderConditionField.swift,
│   │       SmartFolderConditionOperator.swift, SmartFolderDateValue.swift, SmartFolderStatusValue.swift
│   │
│   ├── Snapshots/                      # Sendable-Wertetypen, die aus SQLite-Queries befüllt werden
│   │                                    # und View/ViewModel-seitig statt Model-Objekten verwendet werden
│   │                                    # (z. B. FeedSidebarSnapshot, ArticleReaderSnapshot, ArticleListItemSnapshot)
│   │
│   ├── ViewModels/
│   │   ├── FeedViewModel.swift         # Feed hinzufügen/löschen/refreshen, OPML-Import, delegiert an SQLite-Services
│   │   ├── RuleViewModel.swift         # Regeln verwalten
│   │   ├── TagViewModel.swift          # Tag-Hilfsfunktionen (enum, kein State mehr)
│   │   ├── SQLiteFeedArticleListState.swift, SQLiteReaderState.swift, SQLiteSidebarState.swift
│   │   ├── SQLiteArticleNavigationState.swift, ArticleURLHelpers.swift, SmartFolderConditionDraft.swift
│   │
│   ├── Views/                          # ~55 Dateien, gruppiert nach Feature-Bereich
│   │   ├── ContentView.swift           # Root: NavigationSplitView (3 Spalten), verwaltet Auswahl/Alerts
│   │   ├── Sidebar/                    # Feed-/Ordner-/Tag-/SmartFolder-Liste, Feed-Eigenschaften, Umbenennen
│   │   ├── ArticleList/                # Artikelliste, Filter/Sortierung, Export-Sheet, Suchfenster
│   │   ├── Reader/                     # Lese-Ansicht: nativer Renderer + WKWebView, Typografie, Metadaten
│   │   ├── Tags/                       # Tag-Verwaltung (Farben, Umbenennen, Löschen)
│   │   ├── Rules/                      # Regel-Einstellungen + Regel-Assistent (Wizard)
│   │   ├── SmartFolders/               # Intelligente Ordner: Editor, Einstellungen, Formatierung
│   │   ├── OPMLImport/ + OPMLExport/   # OPML-Vorschau/-Review und -Export
│   │   ├── FirstRun/                   # Onboarding-Assistent beim ersten Start
│   │   ├── Organizer/                  # Separates Fenster zur Feed-/Ordner-Verwaltung
│   │   ├── Settings/                   # Einstellungen-Fenster (Refresh, Darstellung, Sync, Aufbewahrung, …)
│   │   └── Shared/                     # Wiederverwendbare Komponenten (z. B. CachedRemoteImageView)
│   │
│   ├── Services/                       # ~29 Dateien: Feed-Refresh, Regeln, OPML, Export, Caching, Icon-Badge, …
│   │   ├── FeedService.swift           # FeedKit-Wrapper: RSS/Atom/JSON Feed parsen
│   │   ├── SQLiteFeedRefreshCoordinator.swift / SQLiteFeedRefreshService.swift  # Feed-Refresh-Pipeline
│   │   ├── SQLiteFeedActionService.swift / SQLiteFeedSubscriptionService.swift  # Feed anlegen/löschen/abonnieren
│   │   ├── RuleEngine.swift            # Regeln auf neue Artikel anwenden (SQLite-Snapshots)
│   │   ├── OPMLService.swift / OPMLDocument.swift             # OPML Import/Export
│   │   ├── ArticleExportService.swift + ArticleExportPackageBuilder.swift + ArticleDocumentExportRenderers.swift
│   │   ├── ArticleRetentionSettings.swift / ArticleRetentionCleanupService.swift  # Aufbewahrungslimits
│   │   ├── OfflineArticleContentFetching.swift  # Offline-Volltext-Speicherung
│   │   ├── BackgroundRefreshService.swift + *Settings.swift    # Hintergrund-Refresh (NSBackgroundActivityScheduler)
│   │   ├── FaviconService.swift, ImageCacheService.swift, AppIconBadgeService.swift
│   │   └── FeedDiscoveryService.swift, FeedNotificationService.swift, CloudSyncSettings.swift, …
│   │
│   ├── Extensions/                     # Kleine Swift-Erweiterungen
│   │
│   └── Resources/
│       ├── Assets.xcassets             # inkl. befülltem AppIcon.appiconset
│       ├── L10n.swift + Localizable.xcstrings   # Vollständig lokalisierte Strings (Deutsch/Englisch)
│       └── Fonts/                      # Gebündelte Reader-Schriften
│
├── FeedivoTests/                       # Swift-Testing-Suiten (kein XCTest), ~64 Testdateien
├── Feedivo.xcodeproj
└── CLAUDE.md                           # Diese Datei
```

---

## Kernarchitektur

### Datenfluss
Views halten keine SwiftData-`@Model`-Objekte mehr, sondern laden **Snapshots** (reine,
`Sendable`-fähige Structs aus `Feedivo/Snapshots/`) direkt aus den `Stores/` über die
SwiftUI-Environment `\.feedivoDatabase`. Mutationen laufen über die `SQLite*Service`-Klassen
in `Services/`, die anschließend `SQLiteDataInvalidation.bumpStatusVersion()` aufrufen — das
ist ein `@AppStorage`-Zähler, dessen Änderung betroffene Views zum Neu-Laden ihrer Snapshots
anstößt (kein `@Query`/Observation-Mechanismus wie bei SwiftData, weil GRDB das nicht bietet).

### FeedivoApp.swift
Öffnet beim Start die SQLite-Datenbank (`FeedivoDatabaseLocation.databaseURL()`), fällt bei
Öffnungsfehlern auf eine In-Memory-Datenbank zurück und zeigt dem Nutzer dafür einmalig einen
Alert (`DatabaseLoadState`). Registriert Hintergrund-Refresh, räumt abgelaufene Artikel auf
und begrenzt den Bildcache beim Start. Definiert vier Scenes: Haupt-`WindowGroup`,
Artikelsuchfenster, Organizer-Fenster, `WindowGroup(for: ArticleWindowRequest.self)` für
Artikel-Popouts, plus das Settings-Fenster.

### ContentView.swift
`NavigationSplitView` mit 3 Spalten (Sidebar / Artikelliste / Reader). Feed-Auswahl läuft
komplett über String-IDs (`FeedRecord.id`, ein UUID-String) statt über Objektidentität.

### Datenbank-Schema (GRDB-Migrationen, Stand: v10)
| Migration | Inhalt |
|---|---|
| v1_create_core_tables | `feeds`, `articles`, `article_status`, `feed_logs` |
| v2_create_tag_tables | `tags`, `article_tags` |
| v3_create_feed_tag_table | `feed_tags` |
| v4_create_article_search_index | Volltextsuche für Artikel |
| v5_create_article_offline_table | Offline-Artikelinhalte |
| v6_create_admin_definition_tables | Regeln, Regelbedingungen, intelligente Ordner + deren Bedingungen |
| v7_add_feed_admin_fields | Zusätzliche Feed-Verwaltungsfelder |
| v8_drop_unique_feed_url_index | Lockert Eindeutigkeits-Constraint auf Feed-URLs |
| v9_create_article_identity_history | Historie für Artikel-Identitätswechsel (z. B. bei URL-Änderungen) |
| v10_add_feed_retention_minimum_articles | Mindestanzahl Artikel pro Feed bei Aufbewahrungs-Cleanup |

Volle Details je Tabelle: `Feedivo/Database/FeedivoDatabaseMigrator.swift`. Die passenden
Record-Structs liegen 1:1 in `Feedivo/Database/Records/`.

---

## Architektur-Entscheidungen (ADR)

### ADR-001 (ÜBERHOLT durch ADR-007): SwiftData statt Core Data
- **Ursprüngliche Entscheidung (2026-06-19):** SwiftData
- **Grund damals:** Moderner, weniger Boilerplate, native CloudKit-Integration via `isCloudKitEnabled`
- **Status:** Am 2026-07-07 vollständig rückgängig gemacht — siehe ADR-007

### ADR-002: FeedKit für RSS-Parsing
- **Entscheidung:** FeedKit Swift Package
- **Grund:** Unterstützt RSS 1.0/2.0, Atom, JSON Feed — kein eigenes XML-Parsing nötig
- **Paket-URL:** https://github.com/nmdias/FeedKit
- **Datum:** 2026-06-19

### ADR-003: async/await statt Combine
- **Entscheidung:** async/await überall
- **Grund:** Einfacher zu lesen, Swift-Standard, kein Combine-Lernaufwand
- **Datum:** 2026-06-19

### ADR-004: NavigationSplitView für 3-Spalten-Layout
- **Entscheidung:** NavigationSplitView (nicht NavigationStack)
- **Grund:** macOS-Standard für Sidebar/Liste/Detail — fühlt sich nativ an
- **Hinweis:** NavigationView ist deprecated, nie verwenden
- **Datum:** 2026-06-19

### ADR-005: @Observable statt ObservableObject
- **Entscheidung:** @Observable Macro (Swift 5.9+)
- **Grund:** Moderner, weniger Boilerplate als `@Published` + `ObservableObject`
- **Datum:** 2026-06-19

### ADR-006: URLs als String speichern
- **Entscheidung:** URLs als `String` speichern, bei Verwendung mit `URL(string:)` konvertieren
- **Grund ursprünglich:** CloudKit unterstützt keinen nativen URL-Typ (SwiftData-Ära)
- **Grund heute:** Gilt unverändert weiter — auch GRDB/SQLite hat keinen nativen URL-Spaltentyp
- **Datum:** 2026-06-19 (Begründung am 2026-07-07 aktualisiert)

### ADR-007: SwiftData vollständig durch GRDB/SQLite ersetzt
- **Entscheidung:** SwiftData komplett entfernt (alle 9 `@Model`-Klassen gelöscht), GRDB/SQLite
  ist die alleinige Persistenzschicht
- **Grund:** Der produktive Datenpfad war schon vor dieser Aufräumaktion vollständig auf eine
  eigene SQLite-Schicht umgestellt (Snapshot-Pattern, siehe „Kernarchitektur" oben) — SwiftData
  war nur noch technische Altlast ohne aktiven Nutzen (kein `ModelContainer` wurde mehr
  instanziiert). Motivation für die vollständige Entfernung: toten Code eliminieren, die
  Snapshot/Store-Architektur als einzige Quelle der Wahrheit etablieren, keine zwei parallelen
  Datenmodelle mehr pflegen müssen.
- **Ausführung:** Dreiphasiger Plan (Dead-Code-Erkennung, methodengenaue Bereinigung gemischter
  Dateien, finale Löschung der 9 Model-Dateien), umgesetzt über Subagent-Driven-Development mit
  Task- und finalem Whole-Branch-Review.
- **Konsequenz für iCloud Sync:** Die CloudKit-Anbindung, die ursprünglich über
  `isCloudKitEnabled` an SwiftData hing, existiert dadurch aktuell nicht mehr. Ein neuer,
  GRDB-kompatibler Sync-Mechanismus ist Ziel des (aktuell pausierten) Branches
  `codex/icloud-sync-beta`.
- **Datum:** 2026-07-07

---

## Bekannte Gotchas & Fallstricke

> Diese Liste wächst während der Entwicklung. Immer ergänzen!

- **SourceKit-Diagnosen sind oft falsch:** Nach praktisch jedem Edit zeigt die IDE/das
  Diagnose-System teils dutzende Fehler wie "Cannot find type X in scope" oder "No such module
  'GRDB'/'Testing'". Das sind in aller Regel veraltete/gecachte SourceKit-Zustände, KEINE echten
  Fehler. Verlässlich ist ausschließlich ein echter `xcodebuild build`-Lauf.
- **Volle Testsuite hängt:** Ein unscoped `xcodebuild test` über alle Testdateien hängt/deadlockt
  reproduzierbar (bekanntes, ungelöstes Infrastrukturproblem). Immer gezielt mit
  `-only-testing:FeedivoTests/<SuiteName>` testen.
- **Bekannte, dauerhaft vorbestehende Testfehlschläge** (nicht neu einführen, aber auch nicht
  grundlos als eigenen Bug behandeln): 9 Tests in `FeedivoAppSceneConfigurationTests.swift`
  (Zahl am 2026-07-11 per Git-Stash-Vergleich korrigiert — vorher hier fälschlich „5"
  dokumentiert, tatsächlich bereits vor dem `WindowGroup`→`Window`-Fix desselben Tages
  9 Fehlschläge), 2 flaky-unter-Last Tests in `FeedViewModelTests.swift`
  (`refreshAllFeedsMitSQLiteDatabaseNutztSQLiteFirstOhneDoppeltenAbruf`,
  `refreshAllFeedsMitSQLiteDatabaseMeldetFeedBenachrichtigungen`).
- **Hauptfenster-Szene muss `Window`, nicht `WindowGroup` sein:** `WindowGroup(id:)` ist laut
  SwiftUI-Design für mehrere gleichzeitige Fenster-Instanzen gedacht — `openWindow(id:)`
  gegen eine `WindowGroup` erzeugt bei jedem Aufruf eine NEUE Instanz, statt eine bestehende
  zu fokussieren. Betraf `FeedivoApp.swift`s Hauptfenster (Klick auf „Feedivo öffnen" im
  Menubar-Popover öffnete immer ein zusätzliches Fenster statt das bestehende zu zeigen,
  gefunden 2026-07-11). Fix: `Window("Feedivo", id: "main")` statt `WindowGroup(id: "main")`
  — echter Singleton-Szenentyp, den die anderen Einzelfenster der App (Suche, Organizer,
  Statistik) bereits korrekt nutzten. Nur `WindowGroup(for: ArticleWindowRequest.self)`
  (Artikel-Popout, bewusst mehrfach instanziierbar) bleibt zu Recht eine `WindowGroup`.
- **Reader-Toolbar-Icon-Overlap nach Fenster-verkleinern → App-Neustart → Vollbild
  (Nutzer-Report 2026-07-11) — ÜBERHOLTER Fix-Versuch dokumentiert als Warnung:**
  Erster Versuch (Commit `29e0110`, per Code-Analyse ohne Live-Verifikation): die eine
  grosse `ToolbarItemGroup` mit ~15 Controls in mehrere unabhängige
  `ToolbarItem`/`ToolbarItemGroup`-Geschwister aufsplitten, in der Annahme, `NSToolbar`
  behandle eine `ToolbarItemGroup` als unteilbares Element und könne bei Platzmangel
  nicht sauber kollabieren. **Per direktem `NSToolbar`-Item-Frame-Logging widerlegt:**
  Dieser Fix hat das Overlap NICHT behoben, sondern selbst eines verursacht — zwei der
  neu entstandenen Toolbar-Items renderten seither in JEDEM Log-Eintrag (App-Start bis
  letztes Resize) mit exakt identischem Frame übereinander. `NSToolbar` kann offenbar
  mehrere unabhängige, unbenannte `ToolbarItemGroup`-Geschwister in derselben Platzierung
  nicht zuverlässig nebeneinander anordnen. **Tatsächlicher Fix (Commit `a4e81cd`):**
  zurück zur einzelnen `ToolbarItemGroup`; stattdessen neue `FullScreenTransitionObserver`
  (`NSViewRepresentable` in `SQLiteReaderView.swift`), die Vollbild-Ein-/Austritt des
  umschliessenden `NSWindow` beobachtet und einen Zähler erhöht — die Toolbar-
  Inhaltsgruppe trägt `.id(diesesZählers)` und wird dadurch bei jedem Vollbild-Wechsel
  komplett neu aufgebaut, was eine frische `NSToolbarItem`-Messung erzwingt. **Lehre:**
  Bei AppKit/`NSToolbar`-Layout-Bugs reicht Code-Analyse allein nicht — vor einem
  strukturellen Fix per direktem `NSToolbar.items`/`.view?.frame`-Logging verifizieren
  (Notification-Observer auf `didEnterFullScreenNotification` etc. in
  `FeedivoAppDelegate.applicationDidFinishLaunching`, TEMP-DEBUG-Pattern), nicht nur auf
  Apple-Dokumentations-Vermutung vertrauen. **Zweite Überraschung:** Der Vollbild-
  Rebuild-Trigger selbst feuerte anfangs nie — "Vollbild" per grünem Fenster-Knopf-Klick
  löst auf diesem System KEINEN echten macOS-Fullscreen-Space-Wechsel aus
  (`didEnterFullScreenNotification` kam nie an), sondern nur ein normales
  Zoomen/Maximieren (`didResizeNotification`). `FullScreenTransitionObserver`
  (`SQLiteReaderView.swift`) beobachtet seit Commit `bb44536` zusätzlich
  `didResizeNotification` als Rebuild-Trigger. **Vom Nutzer bestätigt behoben.**
- **GRDB statt SwiftData:** Keine `@Query`/Observation-Automatik — UI-Updates nach Mutationen
  laufen explizit über `SQLiteDataInvalidation.bumpStatusVersion()` + `.onChange(...)` in den
  Views. Wer eine Mutation schreibt und vergisst, den Statuszähler zu bumpen, bekommt eine
  UI, die nicht aktualisiert.
- **Optionale Relationship-/Datumsvergleiche in älteren Notizen beziehen sich auf SwiftData
  `#Predicate`** — nicht mehr relevant, da kein SwiftData-Code mehr existiert.
- **FeedKit ist nicht async:** `parseAsync` muss mit `withCheckedThrowingContinuation`
  gewrappt werden.
- **NavigationView ist deprecated:** Immer `NavigationSplitView` oder `NavigationStack`.
- **WKWebView in SwiftUI:** Braucht einen `NSViewRepresentable`-Wrapper für macOS (siehe
  `WebContentView.swift`).
- **`WebContentView` behält ihre WKWebView bewusst über Artikelwechsel hinweg bei** (kein
  `.id(articleID)`, Commit `eca556f93` — Fix für den Reader-Spinner-Flash): Ein Artikelwechsel
  ruft nur `webView.load()` auf einer bestehenden Instanz auf, statt die WKWebView neu zu
  erzeugen. Das ist inzwischen auch die Grundlage für die Vor-/Zurück-Navigation in der
  Original-Ansicht (Feature 1.12, `WebNavigationBoundary`/`articleLoadBoundaryItem` in
  `WebContentView.swift`), die genau deshalb eine Artikelgrenzen-Klemmung braucht — WKWebViews
  `backForwardList` enthält sonst auch Einträge aus vorherigen Artikeln. Vor einem `.id()` auf
  `WebContentView` (z. B. um ein anderes Problem zu "fixen") immer beide Abhängigkeiten prüfen.
- **Background Refresh macOS:** Läuft über `NSBackgroundActivityScheduler`, NICHT über das
  iOS-fokussierte `BGTaskScheduler`/`BGTaskSchedulerPermittedIdentifiers`.
- **macOS Menüleiste:** Commands werden mit `.commands { }` an die `WindowGroup` gehängt,
  nicht an eine View.
- **OPML-Format:** XML-basiert, eigenes Parsing in `OPMLService.swift`/`OPMLDocument.swift`.
- **Datenbank-Migrationen:** Neue Migrationen immer als neuer `migrator.registerMigration("vN_…")`
  -Block anhängen, nie bestehende Migrationen nachträglich ändern (sonst bricht die Migration
  bei Bestandsnutzern).
- **Swift Trailing Closures bei optionalem Closure-Parameter vor einem Pflicht-Closure:**
  Hat eine Funktion/ein Initializer zwei Closure-Parameter in der Reihenfolge
  `action: (() -> Void)? = nil` gefolgt von `@ViewBuilder content: Content` (kein Default,
  z. B. `CollapsibleSidebarSection` in `SidebarView.swift`), dann bindet ein einzelner,
  **unlabeled** Trailing-Closure korrekt an `content` (Swift überspringt den defaulteten
  `action`-Parameter automatisch). Ein einzelner **labeled** Trailing-Closure
  (`) content: { … }` OHNE vorausgehenden unlabeled Closure) ist dagegen **kein gültiges
  Swift** — der Parser interpretiert `content:` als Label eines `do`/Loop-Blocks und meldet
  „labeled block needs 'do'". Für den Zwei-Closure-Fall (`action` UND `content` beide gesetzt)
  bleibt die bekannte Doppel-Trailing-Closure-Syntax `{ action } content: { … }` weiterhin
  richtig. Bei Unsicherheit mit `swiftc -typecheck` gegen eine minimale Repro-Struct prüfen,
  nicht raten.
- **`.sheet(isPresented:)` mit zwei getrennten `@State`-Properties (Bool + zusätzlicher
  Wert) racet:** Werden Präsentations-Flag und abhängiger Wert (z. B. eine vorauszufüllende
  URL) in zwei getrennten `@State`-Properties der Elternview gehalten und im selben
  Run-Loop-Turn gesetzt, kann SwiftUI die gesheetete View **zweimal** konstruieren — einmal
  mit dem alten/leeren Wert, bevor der zweite State committed. Da `@State` in der Kind-View
  nur beim ersten Bau aus `init()` geseedet wird, gewinnt der leere erste Aufruf (gefunden
  und gefixt bei Feature 23.2, `AddFeedSheet`/`ContentView.swift`, Commit `d906b41eb`).
  Fix: **immer** `.sheet(item:)` mit einem einzelnen `Identifiable`-Payload verwenden, sobald
  die gesheetete View mit assoziierten Daten vorbefüllt werden soll — Präsentation und Daten
  müssen atomar in einem Wert stecken. Bestehendes Beispiel dieses Musters im Projekt:
  `RuleCreationRequest` in `ContentView.swift`.
- **`.onOpenURL` verpasst das Launch-Apple-Event beim Kaltstart:** SwiftUIs `.onOpenURL`
  funktioniert zuverlässig, solange die App bereits läuft, kann aber die URL verlieren, mit
  der die App gerade frisch gestartet wurde — das Apple Event kommt an, bevor die
  `WindowGroup`-View-Hierarchie (und damit der `.onOpenURL`-Modifier) existiert, und es gibt
  kein automatisches Replay (gefunden bei Feature 23.2s `feedivo://`-URL-Schema, Commit
  `75a19143a`). Fix: `NSApplicationDelegateAdaptor` + `NSApplicationDelegate.application(_:open:)`
  verwenden (feuert zuverlässig bei Kaltstart UND laufender App), die geparste Aktion in einem
  gemeinsamen `@Observable`-Objekt ablegen und von der View sowohl per `.task` (deckt
  Kaltstart ab, falls die Aktion schon wartet) als auch per `.onChange` (laufende App) mit
  derselben guard-then-clear-Funktion konsumieren, damit dieselbe Aktion nicht doppelt
  verarbeitet wird. Siehe `FeedivoAppDelegate.swift`/`PendingURLSchemeAction.swift`.
- **`INFOPLIST_KEY_CFBundleURLTypes` als reines Build-Setting wird von Xcode stillschweigend
  verworfen:** Bei `GENERATE_INFOPLIST_FILE = YES` unterstützt die `INFOPLIST_KEY_*`-Synthese
  nachweislich nur Skalar-Werte — ein Array-of-Dictionary-Schlüssel wie `CFBundleURLTypes`
  (z. B. für ein eigenes URL-Schema) wird beim Build nicht gemeldet, taucht aber im
  tatsächlich generierten `Info.plist` der gebauten App nie auf (`xcodebuild build` meldet
  trotzdem `BUILD SUCCEEDED` — nur `plutil -p` auf das generierte `Contents/Info.plist`
  deckt das auf). Fix: physische `Info.plist`-Datei anlegen, `GENERATE_INFOPLIST_FILE = NO`
  + `INFOPLIST_FILE = Pfad/Info.plist` setzen, und **da die Datei sonst zusätzlich als
  gewöhnliche Resource kopiert wird**, wenn sie innerhalb eines file-system-synchronisierten
  Ordners liegt, eine `PBXFileSystemSynchronizedBuildFileExceptionSet` ergänzen, die sie
  von der Resources-Build-Phase ausschließt. Siehe `Feedivo/Info.plist` + `project.pbxproj`
  (Feature 23.2, Commit `d71f74d8b`).
- **`xcodebuild build` fügt automatisch leere Stub-Einträge in `Localizable.xcstrings` ein:**
  Trifft der Build auf ein noch nicht katalogisiertes String-Literal in einer `Text(...)`-
  artigen Stelle (z. B. ein hartcodierter deutscher `description`-String in einer neuen
  Settings-Zeile), legt Xcodes String-Catalog-Kompilierung dafür selbständig einen neuen,
  leeren Eintrag in `Localizable.xcstrings` an — ganz ohne eigenes Zutun, einfach durch einen
  normalen `xcodebuild build`-Lauf (gefunden bei den Dark-Mode-Nachbesserungen, 2026-07-09).
  Das ist kein Fehler und keine versehentliche Reformatierung (der Diff bleibt klein, nur der
  neue Stub-Block kommt hinzu) — einfach nach jedem Build kurz `git status`/`git diff --stat`
  auf `Localizable.xcstrings` prüfen und den Stub bewusst mitcommitten oder (falls der
  String besser doch als `L10n`-Key lokalisiert werden sollte) gezielt nachpflegen.
- **`periphery` (Dead-Code-Scanner) hat in diesem Projekt eine hohe Fehlalarmquote bei
  GRDB-Record-Typen:** Wird ein Typ ausschließlich über generische, aus Protokoll-Extensions
  geerbte GRDB-Methoden erreicht (`ArticleOfflineRecord.fetchOne(db, key:)`,
  `ArticleCountsRow.fetchOne(db, sql:)` u. ä.), erkennt periphery die Nutzung nicht und meldet
  den Typ fälschlich als „unused" — SourceKit indiziert den generischen Self-Type-Aufruf nicht
  als echte Referenz. Ebenso falsch gemeldet: `NSViewRepresentable`-Protokollmethoden wie
  `dismantleNSView(_:coordinator:)`, die vom AppKit/SwiftUI-Framework selbst aufgerufen werden,
  nicht von eigenem Code. Bei einem periphery-Cleanup **jeden Fund einzeln per Grep gegen den
  ganzen Produktions- **und** Test-Baum verifizieren**, bevor gelöscht wird — bei der
  Bereinigung vom 2026-07-10 waren von 221 „unused"-Funden 69 (~31 %) solche Fehlalarme.
  Ebenfalls unterscheiden: Funde, die **nur von Tests** direkt angesprochen werden (z. B.
  `ArticleStatusStore.status(articleID:)`, 16 Testreferenzen, aber 0 in der Produktions-App) —
  das ist keine mechanische Dead-Code-Löschung, sondern eine Produktentscheidung (Test
  behalten vs. beides löschen), da sonst Testabdeckung verloren geht.
- **Offline-Artikel-Download-Backend ist bewusst quarantäniert, kein Versehen:**
  `SQLiteOfflineStore`, `SQLiteOfflineDownloadService`, `OfflineArticleContentFetching`-
  Protokoll, `URLSessionOfflineArticleContentFetcher` (alle in `Stores/SQLiteOfflineStore.swift`
  / `Services/OfflineArticleContentFetching.swift`) sowie ~25 zugehörige `L10n.swift`-Keys
  (`readerOffline*`, `settingsOffline*`) haben **keine aktive UI-Anbindung** mehr, sind aber
  vollständig implementiert und getestet (`SQLiteOfflineDownloadServiceTests.swift`).
  `FeedivoAppSceneConfigurationTests.swift` enthält explizite Regressionstests, die die
  **Abwesenheit** der Offline-UI prüfen (`toggleOffline`, `saveOrRemoveOffline`,
  `NewOfflineSettingsView` dürfen nicht existieren) — die UI-Schicht wurde also gezielt entfernt,
  das Backend blieb stehen. Bei künftigen Dead-Code-Scans (periphery o. ä.) **nicht löschen**,
  ohne das vorher explizit mit dem Nutzer zu klären — siehe „Offene Entscheidungen".
- **`MenuBarExtra` (SwiftUI) verursacht in `FeedivoApp.swift` einen 100%-CPU-Endlos-Spin beim
  App-Start, auskommentiert seit 2026-07-10 (Commit `572c5b6`):** Feature 21.1 fügte eine
  `MenuBarExtra(isInserted:)`-Scene hinzu; die App startete danach nicht mehr sinnvoll (Layout-
  Thrashing, `NSView layoutSubtreeIfNeeded`-Rekursion, `AppMenuBarExtrasController.
  updateMenuBarExtras` beteiligt). Per Git-Worktree-Bisektion und Isolationstests verifiziert:
  Der Bug hängt **ausschließlich an der bloßen Existenz der Scene-Deklaration** in `body` —
  unabhängig von `.menuBarExtraStyle`, Inhalt/Label (auch mit trivialen `Text(...)`-Platzhaltern
  reproduzierbar), Scene-Reihenfolge und dem `isInserted`-Bindungswert (tritt auch bei `false`
  auf, da SwiftUI die Scene trotzdem konstruiert). Ein naheliegender Workaround — die Scene nur
  bedingt in den `SceneBuilder` aufnehmen (`if menubarIsEnabled { MenuBarExtra { … } }`), sodass
  sie bei deaktiviertem Feature gar nicht erst konstruiert wird — ist auf diesem Toolchain-Stand
  **kein gangbarer Weg**: Er löst stattdessen einen Swift-Compiler-Absturz aus ("failed to
  produce diagnostic for expression"), reproduzierbar auch isoliert in einer eigenen
  `@SceneBuilder`-Property. Vermutete Ursache: Interaktion zwischen `MenuBarExtra` und den 5
  anderen gleichzeitig deklarierten Scenes dieser App (`WindowGroup` × 2, `Window` × 3,
  `Settings`) — nicht abschließend verifiziert. Nächster Lösungsansatz (noch nicht begonnen):
  AppKit-`NSStatusItem` direkt statt SwiftUI `MenuBarExtra` (Präzedenzfall für eigene
  AppKit-Bridges: `WebContentView`, `ShortcutRecorderView`).
  **Update 2026-07-10 (Commit `e15fa7a`):** Erfolgreich durch `MenubarStatusItemController`
  ersetzt (`Feedivo/App/MenubarStatusItemController.swift`) — `NSStatusItem` + `NSPopover` +
  `NSHostingController<AnyView>` (konkreter Typ nötig, da `.environment`/`.dynamicTypeSize`/
  `.preferredColorScheme` den View-Typ bei jedem Aufruf in `ModifiedContent<...>` wandeln;
  `hostingController.rootView` muss über die Objekt-Lebensdauer denselben generischen Typ
  behalten). Reine Icon-Logik (Symbol/Badge-Text) als `nonisolated static func` ausgelagert
  (mussten explizit `nonisolated` sein, da sie sonst die `@MainActor`-Isolation der
  umschließenden Klasse erben und aus synchronen Tests heraus nicht aufrufbar sind) — testbar
  analog `AppIconBadgeService`. `NSHostingController` beobachtet externe Zustandsänderungen
  (Sprache/Textgröße/Darstellung/Ungelesen-Zähler) NICHT automatisch wie eine deklarative
  SwiftUI-Scene — `FeedivoApp.swift` muss `updateEnvironment(...)`/`updateUnreadCount(_:)`
  explizit bei jeder relevanten `.onChange` aufrufen. Verifiziert: kein CPU-Spin mehr (0,6%
  CPU nach 16s Beobachtung, vorher 98–100%).
- **Duplizierte SQL-SELECT-Listen zwischen `ArticleDatabase.swift` und `TimelineStore.swift`
  können unbemerkt auseinanderlaufen — GRDB liefert bei fehlender Spalte still `nil` statt
  eines Fehlers:** `ArticleDatabase.swift`s privater `fetchArticles`-Helper (Basis für
  `fetchArticles(feedID:/feedIDs:/articleIDs:)`, `fetchUnreadArticles`, `newestUnread`,
  `fetchTodayArticles`, `fetchStarredArticles`) und `TimelineStore.swift`s Haupt-Query bauen
  beide unabhängig voneinander dieselbe `ArticleListSnapshot`-Zeilenform aus `articles`/`feeds`/
  `article_statuses` zusammen, statt eine gemeinsame SQL-Fragment-Konstante zu teilen. Beim
  Menubar-Dropdown-Feature (2026-07-11) fehlte `f.faviconURL AS faviconURL` in der
  `ArticleDatabase`-Variante — `ArticleListSnapshot.init(row:)` (`TimelineStore.swift:784`)
  liest `row["faviconURL"]`, was GRDB bei fehlender Spalte kommentarlos zu `nil` aufwertet
  (kein Crash, keine Warnung). Der Bug war seit der SQLite/GRDB-Migration vorhanden, aber
  unsichtbar, weil kein Konsument von `newestUnread` vorher tatsächlich ein Favicon rendern
  wollte — erst `MenubarArticleRowView` deckte ihn auf. Fix: fehlende Spalte ergänzt (Commit
  `47f9ee7f`) + Regressionstest `newestUnreadLiefertFaviconURLDesFeedsMit`. Bei künftigen
  neuen `ArticleListSnapshot`-Feldern **beide** SQL-Stellen (`ArticleDatabase.swift` UND
  `TimelineStore.swift`) prüfen, nicht nur die naheliegendste.

---

## Milestone-Plan

### M1 – Foundation ✅ Abgeschlossen
Xcode-Projekt, FeedKit-Integration, 3-Spalten-Navigation, Feed hinzufügen/anzeigen — alles
umgesetzt (ursprünglich mit SwiftData, inzwischen auf GRDB/SQLite migriert, siehe ADR-007).

### M2 – Core Features ✅ Abgeschlossen
Artikelliste, Reader (nativ + WKWebView), Gelesen/Ungelesen, Stern-Markierung, Menüleisten-
Shortcuts (`Cmd+N` Feed hinzufügen, `Cmd+R`/`Cmd+Shift+R` Refresh, `Cmd+D` Stern, `Cmd+Shift+U`
Gelesen-Status, Pfeiltasten-Navigation, `Cmd+F` Suche), Feed löschen, automatischer Hintergrund-
Refresh, Favicon-Erkennung (eigene HTML-Discovery + Fallback, keine Google-S2-API).

### M3 – Tags, Regeln & Sync — größtenteils ✅, iCloud Sync offen
- [x] Tag-System (erstellen, Farbe, zuweisen, verwalten)
- [x] Smart Filter / intelligente Ordner mit eigenem Editor und Bedingungen
- [x] `RuleEngine` inkl. Regel-Assistent (Wizard) und Einstellungs-UI
- [x] Offline-Unterstützung: Artikel-Volltext wird beim Abruf in SQLite gespeichert
- [x] Background Refresh (`NSBackgroundActivityScheduler` statt `BGTaskScheduler`)
- [ ] **iCloud Sync via CloudKit** — UI-Toggle existiert ("iCloud Sync Beta"), aber ohne
      funktionales Backend auf `main`; Vorarbeit auf Branch `codex/icloud-sync-beta`
      pausiert und muss noch auf GRDB/SQLite migriert werden (siehe ADR-007)

### M4 – Polish & Release — größtenteils ✅
- [x] OPML Import (mit Vorschau/Review-Screen, Duplikat-Erkennung)
- [x] OPML Export
- [x] Einstellungen-Fenster (Refresh, Darstellung, Textgröße, Sync-Beta, Aufbewahrung, …)
- [x] App-Icon (Assets.xcassets befüllt)
- [x] Onboarding (`FirstRunWizardView`)
- [x] Artikel-Export (Markdown/PDF/DOCX/Paket, siehe `ArticleExportService` + Renderer)
- [x] Vollständige Lokalisierung (Deutsch/Englisch, `L10n.swift` + `Localizable.xcstrings`)
- [ ] Share Extension — noch nicht begonnen
- [ ] App Store Vorbereitung oder private Verteilung — noch offen

### Post-M4 — zusätzlich umgesetzt, nicht im ursprünglichen Plan vorgesehen
- Separates Artikel-Suchfenster, Organizer-Fenster, Artikel-Popout-Fenster
- Umfangreiches, mehrphasiges Code-Review-Remediation-Programm (Korrektheit, Performance,
  Wartbarkeit — siehe Memory-Einträge zu `code-review-full-codebase-2026-06` etc.)
- Vollständige Migration der Persistenzschicht von SwiftData auf GRDB/SQLite (ADR-007)
- App-Icon-Badge mit Anzahl ungelesener Artikel
- Bild-Caching mit konfigurierbarem Limit
- Artikel-Aufbewahrungsrichtlinien (globale + Feed-eigene Overrides)
- App-interne Darstellungs-Einstellung (System/Hell/Dunkel, `AppAppearance`) + Dark-Mode-Fixes
  für First-Run-Assistent (`FirstRunTheme`) und Metadaten-Inspector (Feature 19.7)
- OPML-Import-Dialog auf das "Konzept A"-Designsystem (`RuleDialogTheme`) migriert, visuelle
  Parität mit dem bereits migrierten OPML-Export-Dialog hergestellt

---

## GitHub

- **Repo:** https://github.com/martinfelder/feedivo-mac (private)
- **Branch-Strategie:** `main` = stabil, direkt bearbeitet (kein durchgängiges Feature-Branch-
  Modell mehr in der aktuellen Praxis); vereinzelt längerlebige Branches für größere,
  eigenständige Vorhaben (z. B. `codex/icloud-sync-beta`, `codex/sqlite-grdb-foundation`)
- **Push-Konvention:** Nie ohne explizite Nutzerbestätigung nach `origin/main` pushen

---

## Offene Entscheidungen

- **iCloud Sync:** Wann und wie wird `codex/icloud-sync-beta` auf GRDB/SQLite migriert und
  gemergt? Bis dahin bleibt der Settings-Toggle ein reiner UI-Platzhalter ohne Funktion.
- **Monetarisierung:** Kostenlos / einmaliger Kauf / nie im App Store? — weiterhin offen.
- **Share Extension:** Noch nicht begonnen, kein konkreter Zeitplan.
- **App Store vs. private Verteilung:** Weiterhin offen.

- **Offline-Artikel-Download-Feature:** Backend + Settings-UI-Strings existieren vollständig
  (`SQLiteOfflineStore` u. a., siehe Gotchas oben), die UI-Anbindung wurde aber gezielt entfernt
  und ist per Regressionstest blockiert. Reaktivieren (UI wieder anbinden) oder endgültig
  entfernen (Backend + Tests + L10n-Keys)? Bisher nicht entschieden, beim Dead-Code-Cleanup
  vom 2026-07-10 bewusst unangetastet gelassen.

**Bereits gelöst (zur Referenz):**
- Artikel-Detail: sowohl nativer SwiftUI-Renderer als auch WKWebView (Originalartikel) —
  beide umgesetzt, nutzerseitig umschaltbar.
- Favicon-Strategie: eigene HTML-Discovery + Fallback-Heuristik, keine Google-S2-API.

---

## Aktuell in Arbeit

- **2026-07-13 (Nachmittag): Browser-Erweiterung Popup-UX-Überarbeitung VOLLSTÄNDIG
  ABGESCHLOSSEN und auf `origin/main` gepusht.** Echte Feed-Namen, lokaler HTTP-Server
  für Abo-Status/Hinzufügen, Popup-Redesign, plus vier vom Nutzer live gefundene und
  gefixte Bugs. Details siehe „Letzte Änderungen" unten.
- **Restposten Code-Qualitäts-Review (2026-07-11er Review, Gruppen A+B+C) VOLLSTÄNDIG
  ABGESCHLOSSEN und auf `origin/main` gepusht (2026-07-12).** Details siehe „Letzte
  Änderungen" unten. Damit ist das gesamte Review vom 2026-07-11 abgearbeitet — keine
  offenen Findings mehr aus diesem Durchgang.
- **2026-07-13: Sieben kleinere Bugfixes/Features aus direkten Nutzer-Reports umgesetzt,
  committed, gepusht und vom Nutzer im laufenden Betrieb bestätigt.** Details siehe „Letzte
  Änderungen" unten.
- Ausstehend (nicht automatisierbar, kein computer-use für native macOS-Apps in dieser
  Umgebung): manuelle visuelle Verifikation zweier reiner UI-Änderungen aus Gruppe C
  (OPML-Import-Button-Spinner, Regel-Vorschau-Warnsymbol) sowie die weiterhin offene
  manuelle Verifikation von OPML-Import Hell/Dunkel (Feature 19.7-Nachgang).
- Alle Features 19.2–19.4, 19.7, 19.8 sowie Statistiken (14.1–14.3) sind abgeschlossen,
  committed und auf `origin/main` gepusht — Details siehe „Letzte Änderungen" unten und
  FEATURES.md. Feature 19.4 (Toolbar anpassen) bleibt bewusst zurückgestellt (⏸️).
- Weiterhin offen laut FEATURES.md-Entscheidung vom 2026-07-02: `codex/icloud-sync-beta` ist
  bewusst zugunsten des SQLite/GRDB-Umbaus zurückgestellt (nicht nur unentschieden) — der Umbau
  ist inzwischen abgeschlossen (ADR-007), eine erneute Bewertung des Branches steht noch aus.

---

## Letzte Änderungen

- 2026-07-13 (Nachmittag): Browser-Erweiterung Popup-UX-Überarbeitung — via
  Brainstorming+Plan+Subagent-Driven-Development (8 Tasks, alle Task-Reviews clean,
  finaler Whole-Branch-Review mit 1 Fix-Runde) umgesetzt, dann vier zusätzliche vom
  Nutzer beim Live-Testen gefundene Bugs gefixt. Spec:
  `docs/superpowers/specs/2026-07-13-browser-erweiterung-ux-design.md`, Plan:
  `docs/superpowers/plans/2026-07-13-browser-erweiterung-ux.md`. Gepusht (`619aa1ef8`..
  `36ed41745`).
  - **Echte Feed-Namen statt Seitentitel-Heuristik** — `feedDetection.mjs`/`content.js`
    holen jetzt den tatsächlichen Feed-Inhalt per `fetch()` und lesen den echten Titel
    aus dem ersten `<title>`-Tag (RSS/Atom) bzw. dem `title`-Feld (JSON Feed), statt
    `link.title || document.title || href` zu raten.
  - **Neu: lokaler HTTP-Server in der App** (`Feedivo/Services/LocalExtensionBridge/`,
    `127.0.0.1:51823`, eigenes `Network.framework`/`NWListener`-Wiring) — Popup kann
    per `GET /status` prüfen, ob ein Feed schon abonniert ist, und per `POST /add`
    direkt hinzufügen (echte Erfolgs-/Duplikat-/Fehler-Rückmeldung statt des bisherigen
    Fire-and-Forget-`feedivo://add`-Deep-Links, der bei Nichterreichbarkeit weiterhin
    als Fallback dient). Neues Entitlement `com.apple.security.network.server`.
  - **Popup-Redesign** — Status-Badges ("Bereits in Feedivo"), Favicon, URL-Zweitzeile,
    breiter (260→420px).
  - **Vier Bugs aus Live-Nutzer-Tests gefixt** (nicht Teil des ursprünglichen Plans,
    per systematic-debugging direkt im Anschluss behoben):
    1. Cross-Site-CSRF auf `/add` — beliebige Webseite konnte per `fetch()` ohne
       `Content-Type`-Header (CORS "simple request", kein Preflight) still Feeds
       einschleusen; gefunden im finalen Whole-Branch-Review. Fix: fester
       `X-Feedivo-Extension`-Header, den nur die Erweiterung setzt (umgeht CORS via
       `host_permissions`), Server lehnt alles andere mit 403 ab.
    2. **Soft-404-Fallback-Erkennung** — `probeFallbackFeedPaths()` prüfte nur den
       HTTP-Status, nicht den Inhalt; auf SPA-Seiten mit Client-Routing (z. B.
       `bluewin.ch`), die für JEDEN Pfad 200+HTML statt 404 liefern, hielt das
       `/feed`/`/rss`/`/atom.xml` faelschlich für echte Feeds. Fix: neue
       `looksLikeFeedContent()`-Prüfung validiert das tatsächliche RSS/Atom/RDF-
       Wurzelelement bzw. JSON-Feed-`items`-Array.
    3. **MV3-Service-Worker-Suspend verwarf Feed-Cache** — `background.js` hielt
       erkannte Feeds nur in einer In-Memory-`Map`; Chrome beendet Hintergrund-Service-
       Worker nach kurzer Inaktivität automatisch und verwirft dabei jeden Zustand —
       zweites Popup-Öffnen kurz nach dem ersten zeigte dann faelschlich keine Feeds
       mehr, obwohl die Seite nicht neu geladen wurde. Fix: `popup.js` fragt jetzt
       direkt das Content-Script der aktiven Seite (`chrome.tabs.sendMessage`, lebt so
       lange wie die Seite selbst) statt den Service-Worker-Cache; `background.js`
       behält nur noch die Icon-Aktivierungslogik.
    4. `/add`-Timeout (300ms, für `/status` gedacht) war für den echten serverseitigen
       Feed-Fetch zu kurz, und HTTP-400-Antworten wurden faelschlich als "App läuft
       nicht" statt als echter Fehler behandelt — beides im Task-Review vor dem Push
       gefunden und gefixt (eigenes `ADD_FEED_TIMEOUT_MS`, JSON-Body wird jetzt bei
       jeder empfangenen Antwort geparst).
  - **Neuer Gotcha:** MV3-Hintergrund-Service-Worker sind ungeeignet für persistenten
    In-Memory-Zustand über Zeit hinweg (siehe Fix 3 oben) — Zustand, der das Öffnen des
    Popups überdauern muss, gehört ins Content-Script oder `chrome.storage`, nicht in
    eine Modul-Variable im Service Worker.
- 2026-07-13: Sieben Bugfixes/Features aus direkten Nutzer-Reports, jeweils einzeln
  committed, gepusht und vom Nutzer im laufenden Betrieb bestätigt:
  - **Reader zeigt Tags/Ordner-Zuordnung sofort statt erst nach Artikelwechsel** —
    `ArticleMetadataInspectorView` mutierte Tags/Ordner direkt in SQLite, aktualisierte
    dabei aber nur seine eigene lokale Snapshot-Kopie statt `SQLiteReaderState.snapshot`
    der übergeordneten `SQLiteReaderView`. Fix: `SQLiteReaderView` beobachtet jetzt
    zusätzlich `SidebarBadgeInvalidation.directTagVersionKey` und
    `SQLiteDataInvalidation.statusVersionKey` und lädt den aktuellen Artikel bei Änderung
    neu. Zwei Commits (`e188e9240` Tags, `9760ad4e7` Ordner).
  - **Einstellungen-Fenster verbreitert (640→880pt)** — `Layout.windowWidth` war seit
    2026-07-06 (damals 7 Tabs) nicht mehr nachgezogen worden; bei inzwischen 10 Tabs
    (Artikelliste/Menubar/Shortcuts kamen dazu) lief die Tab-Leiste über den sichtbaren,
    wegen `.windowResizability(.contentSize)` nicht von Hand vergrößerbaren Bereich hinaus
    — Bereinigung/Sync/Über waren dadurch nicht mehr anklickbar. Commit `e56edbf82`.
  - **Sidebar-Einrückung Tags/Ordner/Intelligente Ordner vereinheitlicht** —
    `SidebarFolderSection` hatte `.padding(.horizontal, 0)` (bündig links) statt der von
    Feeds/Tags/Abschnitts-Überschriften genutzten 10pt; jetzt 16pt für Ordner-Zeilen,
    Tags und Intelligente Ordner (Standard + Eigene) auf `leadingIndent: 6` vereinheitlicht
    (bewusst NICHT einfach auf die alten 34pt der Intelligenten Ordner draufaddiert,
    sondern wie Tags behandelt). Zwei Commits (`591a005be` Tag-Zeilenhöhe 30pt wie
    Intelligente Ordner, `378293c7d` Einrückung).
  - **Kein aufdringlicher Modal-Alert mehr bei fehlgeschlagenem Feed-Refresh** —
    `refreshAllFeedsWithCoordinator` setzte bei Fehlern redundant sowohl
    `recentRefreshStatus`/`refreshItems` (speist das rechte-untere Status-Widget mit
    Pro-Feed-Fehlerliste, bleibt bei Fehlern dauerhaft sichtbar) als auch `errorMessage`
    (→ Modal-Alert) mit identischem Inhalt. `errorMessage`-Zuweisung entfernt. Commit
    `d7076252a`.
  - **Feed-Status-Zeile im Artikellisten-Header** — dritte Zeile bei einzelnem Feed:
    „Zuletzt aktualisiert: {Datum, Uhrzeit}" bzw. „Konnte nicht aktualisiert werden:
    {Grund}" mit dem echten Fehlertext aus `feed_logs.message`. Nutzt ausschließlich
    bereits vorhandene Felder (`FeedRecord.lastRefreshedAt`, `feed_logs` über
    `FeedLogStore`), keine neue Migration. Zeigt bewusst den festen Zeitpunkt
    (`date.formatted(date:time:)`), nicht die relative „vor X Stunden"-Formatierung —
    nach Nutzer-Korrektur direkt so angepasst. Bestehende `feedErrorBanner`-Leiste bleibt
    zusätzlich bestehen (Nutzerentscheid). Via Brainstorming+Plan umgesetzt, Spec:
    `docs/superpowers/specs/2026-07-12-artikelliste-feed-status-zeile-design.md`. Drei
    Commits (`d3d16df79` Spec, `d22e64edb` Feature, `4c9cedf48` Zeitpunkt-Korrektur).
  - **Smart Folder "Ungelesen": gelesene Artikel verschwinden nicht mehr sofort** — zwei
    parallele States (`stickyRowSnapshots`-Dictionary und
    `temporarilyVisibleReadArticleIDs`-Set) hielten denselben "trotz Gelesen-Status
    sichtbar halten"-Zustand redundant und liefen auseinander (Diagnose via
    "Gelesene anzeigen"-Test: Zeile blieb in `stickyRowSnapshots`, aber nicht in der
    zweiten Menge). Fix: redundantes Set entfernt, Sichtbarkeit direkt aus
    `Set(stickyRowSnapshots.keys)` abgeleitet — eine Quelle der Wahrheit statt zwei.
    Commit `48e29cd64`.
  - **Smart Folder "Mit Stern" zeigt standardmäßig gelesene UND ungelesene Artikel** —
    `showsReadArticles` hatte keinen scope-spezifischen Default. Neuer
    `defaultShowsReadArticles` (true bei `smartFolder.defaultKey == "starred"`), gesetzt
    sowohl im `init(smartFolder:)` (State-Seed für allererstes Erscheinen) als auch in
    `.onChange(of: scopeToken)` (für Scope-Wechsel innerhalb derselben View-Identität,
    da `@State(initialValue:)` nur beim allerersten Erscheinen greift). Commit `0a00acfb4`.
- 2026-07-12: Restposten Code-Qualitäts-Review (2026-07-11er Review) vollständig
  abgearbeitet — drei unabhängige Gruppen, jede via Subagent-Driven-Development
  (Task-Implementer → Task-Reviewer → Whole-Branch-Review) auf `main` direkt umgesetzt,
  alle drei Whole-Branch-Reviews „Ready to merge: Yes" mit 0 Critical/Important-Funden:
  - **Gruppe A (Verschluckte Fehler, Abschnitt 3):** 4 Tasks — u. a.
    `logIfThrows`/`AppLogger`-Helfer für zuvor stumme `try?`-Stellen, Retention-Cleanup-
    Fehlerlogging. Gepusht (`9dff5fed7..43befc2fa`).
  - **Gruppe B (Code-Hygiene ohne Verhaltensänderung, Findings 2.7–2.9):** 4 Tasks —
    `ArticleFetchLimits`-Konstanten statt 3 magischer Zahlen (2.7), gemeinsamer
    `SearchDebounce`-Helfer statt zweier divergierender `Task.sleep`-Implementierungen
    (2.9, mit TDD), vestigiales „New"-Präfix an 17 `SettingsView`-Typen entfernt (2.8),
    totes `RuleViewModel.swift` gelöscht (dabei `RuleConditionDraft`/`RuleMoveDirection`
    zuvor nach `Feedivo/Models/` ausgelagert, da dort noch produktiv genutzt). Gepusht
    (`43befc2fa..3b76d4023`).
  - **Gruppe C (UI-Feedback-Konsistenz, Finding 2.10 + Abschnitt 3):** 3 Tasks — OPML-
    Import-Button zeigt Spinner + „Wird importiert..." während `feedViewModel.isLoading`
    statt nur `.disabled` mit statischem Label (2.10); `SQLiteFeedSubscriptionService.
    previewOPMLFeeds` validiert URL-Syntax (Schema + Host) lokal per neuem
    `isSyntacticallyValidFeedURL`-Helper, bevor ein Netzwerk-Fetch versucht wird —
    offensichtlich kaputte OPML-`xmlUrl`-Werte werden dadurch sofort als `.unreachable`
    markiert statt einen Roundtrip zu verschwenden (Abschnitt 3, mit TDD-Test über
    `fetchCallCount`-Zähler); `RuleWizardView`s Regel-Vorschau unterscheidet neu per
    `previewLoadFailed`-State „0 Treffer" (echtes Ergebnis, Punkt-Icon + `theme.accent`)
    von „Vorschau fehlgeschlagen" (fehlende DB oder Store-Fehler, Warndreieck +
    `theme.destructiveText` + neuer L10n-Key `ruleWizard.preview.error`) — vorher setzten
    beide Fälle identisch `previewMatchingCount = 0` (Abschnitt 3). Gepusht
    (`3b76d4023..2873cfcf9`). Pläne: `docs/superpowers/plans/2026-07-12-*-restposten-
    gruppe-{a,b,c}*.md`. Ausstehend: manuelle visuelle Verifikation der beiden reinen
    UI-Änderungen aus Gruppe C (kein computer-use für native macOS-Apps verfügbar).
- 2026-07-10: Dead-Code-Bereinigung (`/ecc:refactor-clean`) — `periphery`-Scan über das
  Feedivo-Target, jeder der 221 „unused"-Funde einzeln gegen Produktions- **und** Test-Code
  verifiziert (nicht blind übernommen, siehe neuer Gotcha oben zur GRDB-Fehlalarmquote von
  periphery). Entfernt: 226 Zeilen über 8 Dateien — 2 verwaiste Typen
  (`FeedRefreshResult`/`FeedRefreshOutcome` in `FeedViewModel.swift`), 2 nie instanziierte
  View-/Style-Structs (`SidebarRow`, `FirstRunSegmentButtonStyle`), 2 ungenutzte
  Convenience-Initializer (`ArticleExportDocument.init(text:)`,
  `ReaderArticleTagMetadata.init(id:name:colorHex:)`), 3 verwaiste Helper-/Wrapper-Funktionen
  (`ArticleRetentionSettings.storedRetentionDays(in:)`/`storedMinimumArticlesPerFeed(in:)`,
  `BackgroundRefreshService.scheduleFromStoredSettings`), 1 tote Computed Property
  (`FeedOperationProgress.fractionCompleted`) und 75 tote `L10n.swift`-Lokalisierungs-Keys
  (`Localizable.xcstrings` bewusst nicht mitbereinigt — verwaiste Einträge sind harmlos,
  Xcode markiert sie beim nächsten Build automatisch als `extractionState: stale`). Bewusst
  ausgeklammert: das komplette, per Regressionstest quarantänisierte Offline-Download-Backend
  samt ~25 zugehöriger L10n-Keys (neuer Gotcha + neuer Eintrag unter „Offene Entscheidungen"),
  22 Store-/ViewModel-Methoden, die nur von Tests direkt angesprochen werden (z. B.
  `ArticleStatusStore.status(articleID:)`), sowie `SmartFilterIconColor`/`iconColor`
  (`SmartFilter.swift`) — Löschversuch von `SmartFilterTests.swift` sofort per Test-Fehlschlag
  aufgehalten und automatisch reverted. Build grün nach jeder Batch; einzige Testfehlschläge
  waren die bereits dokumentierten 2 flaky-unter-Last-Tests in `FeedViewModelTests.swift`
  (isoliert erneut grün gelaufen). Committed (`3666840`) und auf `origin/main` gepusht
  (`6f32ac4c..36668404`).
- 2026-07-09: Feature 19.2 (Sidebar anpassen) umgesetzt — neue `@AppStorage`-Keys in
  `SidebarFeedVisibilitySettings` für Ungelesen-Zähler und Favicon ein-/ausblendbar,
  `FeedRowView` conditional rendering, Settings-UI-Toggles in `NewAppearanceSettingsView`,
  L10n-Keys + `Localizable.xcstrings`-Einträge (de/en/fr/it). Build und Tests grün. Committed
  und auf `origin/main` gepusht (`70ae13e7`).
- 2026-07-09: Suchfenster (`ArticleSearchWindowView`) auf Konzept A (`RuleDialogTheme`)
  migriert — Kopfzeile + `ArticleSearchPreviewView`-Buttons auf die gleichen Design-Tokens
  wie Export-/Import-Dialog umgestellt. Build und Tests grün. Committed und gepusht
  (`d49833d3`).
- 2026-07-09: OPML-Import-Dialog auf "Konzept A" migriert (`RuleDialogTheme`) — Dialog-Rahmen/
  Header/Divider (Commit `fc26257`), Datei-Auswahlzeile/Toolbar/Buttons/Footer/Feed-Tabelle
  (Commit `03dd4f14`, gemeinsam mit dem Header-Task umgesetzt, da der Zwischenstand sonst
  nicht baut — Signaturänderung an `OPMLSecondaryButtonStyle`/`OPMLPrimaryButtonStyle` betrifft
  7 Aufrufstellen über beide Tasks). Finaler Whole-Branch-Review (Opus) fand 1 Minor-Fund
  (verbleibende `.foregroundStyle(.secondary)`-Reste statt `theme.text2`), in Commit `235a3b7`
  behoben. `OPMLImportFeedRow.swift` bewusst ausgenommen (geteilt mit First-Run-Assistent,
  eigenes `FirstRunTheme`). Plan: `docs/superpowers/plans/2026-07-09-opml-import-konzept-a.md`.
- 2026-07-09: Feature 19.7 (App-interne Darstellungs-Einstellung, echter Dark Mode) umgesetzt
  via Subagent-Driven-Development — neues `AppAppearance`-Enum (System/Hell/Dunkel) nach
  `AppLanguage`-Vorbild, `.preferredColorScheme(...)` auf allen 5 SwiftUI-Scenes
  (`FeedivoApp.swift`), neues `FirstRunTheme` (nach `RuleDialogTheme`-Vorbild) ersetzt ~14
  hartcodierte `Color.white`/RGB-Stellen im First-Run-Assistenten, Metadaten-Inspector-
  Hintergrund auf Systemsemantikfarbe umgestellt. Vor Ausführung: Selbstreview fand und
  korrigierte einen Build-Reihenfolge-Bug (L10n-Keys mussten vor `AppAppearance.swift`
  entstehen) sowie 2 Spec-Abweichungsrisiken (hartcodierte Dark-Farbwerte als bewusste
  Startwerte markiert). Finaler Whole-Branch-Review (Opus): 3 Minor-Funde, 2 direkt behoben
  (fehlendes `.preferredColorScheme` im Error-Pfad des Artikel-Popout-Fensters,
  Testabdeckung für `FirstRunTheme` Hell/Dunkel). Im selben Rutsch nebenbei entdeckt und
  gefixt: `OPMLImportReviewView.swift` (Import-Dialog) hatte ebenfalls hartcodierte
  `Color.white`-Stellen, die die ursprüngliche Dark-Mode-Bestandsaufnahme übersehen hatte
  — auf `Color.frostedCard(for:)` umgestellt (neue geteilte `Color`-Extension in
  `RuleDialogTheme.swift`), was direkt zur obigen Konzept-A-Migration führte. Spec:
  `docs/superpowers/specs/2026-07-09-dark-mode-theme-design.md`, Plan:
  `docs/superpowers/plans/2026-07-09-dark-mode-theme.md`. Neuer Gotcha zu automatischen
  `Localizable.xcstrings`-Stub-Einträgen bei `xcodebuild build` dokumentiert (siehe oben).
  Ausstehend: manuelle visuelle Verifikation durch den Nutzer (kein computer-use für native
  macOS-Apps in dieser Umgebung verfügbar).
- 2026-07-09: Feature 27 (Browser-Erweiterung Safari + Chrome, RSS-Feed hinzufügen) umgesetzt
  via Subagent-Driven-Development — geteilte, Node-getestete Feed-Erkennungslogik
  (`BrowserExtensions/Shared/feedDetection.mjs`), Chrome-Erweiterung
  (`BrowserExtensions/Chrome/`) und Safari-Erweiterung (neues Xcode-Target
  `FeedivoSafariExtension`, manuell angelegt) mit byte-identischem Code (Safari
  unterstützt den `chrome.*`-Namespace). Ein Controller-Fehler unterwegs gefunden und
  korrigiert: die `project.pbxproj`-Verdrahtung für das neue Xcode-Target wurde beim
  ersten Commit versehentlich nicht mitgenommen (nachträglich in eigenem Commit
  nachgezogen, bevor es zu Problemen führen konnte). Finaler Whole-Branch-Review
  (inkl. echtem Clean-Build zur Verifikation der Korrektur): bereit zum Mergen.
- 2026-07-09: Feature 23.2 (URL-Schema `feedivo://add`/`feedivo://article`) umgesetzt via
  Subagent-Driven-Development — `FeedivoURLSchemeParser`, physische `Info.plist` (Nachtrag,
  da `INFOPLIST_KEY_CFBundleURLTypes` als Build-Setting stillschweigend verworfen wird),
  `NSApplicationDelegateAdaptor`/`FeedivoAppDelegate` (Nachtrag, da `.onOpenURL` das
  Launch-Apple-Event beim Kaltstart verpasst). Zwei echte Bugs während manueller
  End-to-End-Verifikation gefunden und gefixt (Sheet-Race, Kaltstart). Finaler
  Whole-Branch-Review: bereit zum Mergen. Drei neue Gotchas dokumentiert (siehe oben).
- 2026-07-08: Feature 27 (Browser-Erweiterung Safari + Chrome, RSS-Feed hinzufügen) final
  entschieden und in FEATURES.md aufgenommen — Voraussetzung Feature 23.2.
- 2026-07-07: SwiftData vollständig entfernt (30-Task-Plan, Subagent-Driven-Development,
  finaler Whole-Branch-Review). Commits `575bcee23` (Löschung der 9 `@Model`-Klassen) und
  `90b7216cc` (Nachtrags-Cleanup: toter Code, veraltete Kommentare) auf `main` gepusht.
  GRDB/SQLite ist seither die alleinige Persistenzschicht.
- 2026-07-07: CLAUDE.md grundlegend überarbeitet — Tech-Stack, Datenmodell, Projektstruktur
  und Milestone-Plan an den tatsächlichen Code-Stand angeglichen (vorher seit 2026-06-19
  praktisch unverändert und stark veraltet).
- 2026-06-19: Projekt erstellt, ursprünglich mit SwiftData Modellen, NavigationSplitView,
  FeedService + FeedViewModel + SidebarView mit AddFeedSheet implementiert (seither durch
  GRDB/SQLite-Architektur abgelöst).
