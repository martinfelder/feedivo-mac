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
  grundlos als eigenen Bug behandeln): 5 Tests in `FeedivoAppSceneConfigurationTests.swift`,
  2 flaky-unter-Last Tests in `FeedViewModelTests.swift`
  (`refreshAllFeedsMitSQLiteDatabaseNutztSQLiteFirstOhneDoppeltenAbruf`,
  `refreshAllFeedsMitSQLiteDatabaseMeldetFeedBenachrichtigungen`).
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

**Bereits gelöst (zur Referenz):**
- Artikel-Detail: sowohl nativer SwiftUI-Renderer als auch WKWebView (Originalartikel) —
  beide umgesetzt, nutzerseitig umschaltbar.
- Favicon-Strategie: eigene HTML-Discovery + Fallback-Heuristik, keine Google-S2-API.

---

## Aktuell in Arbeit

- Feature 23.2 (URL-Schema `feedivo://`) ist abgeschlossen und auf `origin/main` gepusht.
- Feature 27 (Browser-Erweiterung Safari + Chrome) ist abgeschlossen und auf `origin/main`
  gepusht — neuer Ordner `BrowserExtensions/Chrome/` + neues Xcode-Target
  `FeedivoSafariExtension`.
- Nächster sinnvoller Schritt laut offenen Punkten: Entscheidung über `codex/icloud-sync-beta`
  treffen (migrieren+mergen vs. verwerfen), da der Branch sonst weiter divergiert.

---

## Letzte Änderungen

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
