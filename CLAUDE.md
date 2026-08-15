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

Feedivo ist ein nativer macOS RSS Reader mit Tags, automatischen Regeln, intelligenten Ordnern
und OPML-Import/-Export. Ziel ist eine schöne, schnelle Mac-App die sich "mac-like"
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
| iCloud Sync | Phase 2b implementiert (Tags/Feeds/Ordner/Regeln/benutzerdefinierte Intelligente Ordner/Artikelstatus) + Sync-Reset-UI | `CKSyncEngine`-Fundament (`Feedivo/Services/CloudSync/`), seit 2026-07-24 schrittweise ausgebaut — Phase 1 synct `tags`, Phase 2a erweitert das Registry-basierte `CloudSyncEngine` zusätzlich um `feeds` (nur Konfigurationsfelder, keine Refresh-Metadaten/`unreadCount`), `feed_folders`, `rules`+`rule_conditions` sowie benutzerdefinierte `smart_folders`+`smart_folder_conditions` (eingebaute Standard-Ordner bleiben bewusst ausgeschlossen), Phase 2b (2026-07-25) ergänzt Artikelstatus (Gelesen/Stern) inkl. Löschpropagierung — dafür war ein Nachfolge-Fix nötig, da `article_statuses.articleID` pro Gerät zufällig ist (siehe Gotcha zur ArticleStatus-Sync-Identität unten), Fix nutzt stattdessen eine deterministische `syncStableID`. Zusätzlich eine Soft-/Hard-Reset-UI für den Sync-Zustand. Toggle wirkt weiterhin sofort ohne Neustart. Automatisierte Tests + Release-Build für alle Phasen grün; Live-Verifikation über das CloudKit Dashboard steht für Phase 2a/2b weiterhin aus (Push-Richtung), Pull-Richtung app-weit ungetestet mangels Zweitgerät. Phase 3 (Feld-Ebene-Konfliktauflösung + Merge-Dialog) und Phase 4 (Härtung) noch nicht begonnen. Der ursprünglich für iCloud Sync vorgesehene, SwiftData-basierte Alt-Branch ist überholt und wurde gelöscht (ADR-007) |
| Netzwerk | URLSession + async/await | Kein Alamofire, kein Combine |
| RSS-Parsing | FeedKit | Swift Package, URL: https://github.com/nmdias/FeedKit |
| Datenbank-Package | GRDB.swift | Swift Package, URL: https://github.com/groue/GRDB.swift |
| Bilder | AsyncImage + eigener `ImageCacheService` | Built-in SwiftUI + eigenes Disk-Caching, kein Kingfisher |
| Artikel-Rendering | Nativer SwiftUI-Renderer (`ReaderContentRenderer`) **und** `WKWebView` (`WebContentView`) | Native Ansicht für den Lesefluss, WKWebView für "Originalartikel" |
| Background Refresh | `NSBackgroundActivityScheduler` (`SystemBackgroundActivityRefreshScheduler`) | Kein `BGTaskScheduler` (das ist iOS-fokussiert) |
| App-Update | Sparkle 2.x (Swift Package, `SparkleUpdateCoordinator`) | Ersetzt seit 2026-07-31 den kompletten Eigenbau-Installer (siehe ADR-009) — Grund war ein reproduzierter App-Sandbox-Root-Cause-Fund, kein reiner Komfort-Umstieg. Appcast unter `docs/appcast.xml`, ausgeliefert über `https://raw.githubusercontent.com/martinfelder/feedivo-mac/main/docs/appcast.xml`. Zusätzlicher Vertriebskanal: Homebrew Cask (`martinfelder/homebrew-feedivo`, `Casks/feedivo.rb`) — bei einer per Cask erkannten Installation (`HomebrewInstallationDetector`) wird bewusst gar kein `SPUUpdater` erzeugt, Updates laufen dort ausschließlich über `brew upgrade`. **Seit 2026-08-02 (ADR-010) nutzt `SparkleUpdateCoordinator` Sparkles eigenen `SPUStandardUserDriver` statt einer komplett selbstgebauten `SPUUserDriver`-Konformität** — derselbe erste, echte End-to-End-Update-Zyklus (Developer-ID-signiert, notarisiert, gestapelt, Download→Installation→Neustart) ist damit live verifiziert erfolgreich. `create_github_release.sh` signiert seit demselben Datum mit "Developer ID Application" (`method: developer-id`-Export) statt "Apple Development" und notarisiert/staplet jeden Release automatisch (App-Store-Connect-API-Key, nicht `--keychain-profile`). Details siehe ADR-009, ADR-010 und die neuen Gotchas zu Notarisierung/Signing sowie „Aktuell in Arbeit" unten |
| MCP-Anbindung | `FeedivoMCPServer` (separates Command-Line-Tool-Target, `modelcontextprotocol/swift-sdk`, stdio) | Seit 2026-08-14 (v1, read-only, 7 Tools): eigenes Xcode-Target `FeedivoMCPServer` teilt sich per Target Membership Quellcode mit dem Haupt-Target (kein separates Swift Package), öffnet die produktive SQLite-DB direkt und unabhängig davon, ob die Feedivo-App läuft. Ins `Feedivo.app`-Bundle eingebettet (Copy-Files-Phase, Destination „Executables", Code Sign On Copy). **Standardmäßig deaktiviert (Opt-in)** — Nutzer aktiviert den Zugriff explizit über den neuen Settings-Tab „KI-Zugriff" (`MCPServerSettingsView`, `MCPServerSettingsStore`, Migration v31 legt die Tabelle `mcp_server_settings` an); der Server prüft das Flag fail-closed direkt nach dem Öffnen der DB, vor jeder Tool-Registrierung — fehlende Tabelle/Zeile wird identisch wie „deaktiviert" behandelt. Derselbe Tab zeigt einen kopierbaren Claude-Desktop-Config-Snippet. Details siehe ADR-011 und der neue Gotcha zu GRDBs `PRAGMA query_only`-Verhalten unten |
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
│   │       └── ArticleIdentityHistoryRecord.swift
│   │
│   ├── Stores/                         # Query-/Mutation-Layer über den Records (ein Store pro Tabelle/Domäne)
│   │   ├── FeedStore.swift, ArticleStore.swift, ArticleStatusStore.swift
│   │   ├── TagStore.swift, FeedFolderStore.swift, FeedLogStore.swift
│   │   ├── SQLiteRuleStore.swift, SQLiteRuleEvaluationStore.swift
│   │   ├── SQLiteSmartFolderStore.swift
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
│   │   │   └── SidebarOutlineView.swift  # NSViewRepresentable-Bridge auf AppKit NSOutlineView (ersetzt seit
│   │   │       2026-07-15 die alte SwiftUI-native `.draggable`/`.dropDestination`-Implementierung, siehe ADR-008)
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
├── FeedivoTests/                       # Swift-Testing-Suiten (kein XCTest), 126 Testdateien in
│                                        # Unterordnern, die Feedivo/ spiegeln (App/, Database/,
│                                        # Extensions/, Models/, Snapshots/, Stores/, Services/
│                                        # inkl. Services/CloudSync/, ViewModels/, Views/) - seit
│                                        # 2026-07-28 (vorher komplett flach)
├── FeedivoMCPServer/                    # Command-Line-Tool-Target: read-only MCP-Server (stdio,
│                                        # modelcontextprotocol/swift-sdk), teilt sich Quellcode mit
│                                        # Feedivo/ per Xcode Target Membership statt eigenem Package.
│                                        # FeedivoMCPServerDatabase.swift (readonly-DatabaseQueue-Öffnen,
│                                        # siehe ADR-011 + Gotcha zu PRAGMA query_only unten),
│                                        # FeedivoContainerDatabaseLocation.swift (DB-Pfad im App-
│                                        # Sandbox-Container aus einem unsandboxed Prozess heraus),
│                                        # HTMLPlainTextConverter.swift, main.swift (Bootstrap),
│                                        # Tools/ (list_feeds, list_folders, list_tags, search_articles,
│                                        # get_article, list_smart_folders, get_smart_folder_articles)
├── FeedivoMCPServerTests/               # Swift-Testing-Suiten für FeedivoMCPServer — NICHT per
│                                        # `xcodebuild test` ausführbar (TEST_HOST-Limitation bei
│                                        # Command-Line-Tool-Targets, siehe Gotcha unten), nur
│                                        # build-verifiziert + per Live-stdio-Smoke-Test abgesichert
├── Feedivo.xcodeproj
├── scripts/                            # Repo-Automatisierung (Versionierung/Release) + l10n/
├── docs/                               # Design-Prototypen/-Handoffs, superpowers-Plans/Specs
│                                        # (nach Monat sortiert), Performance-Audits
├── README.md, CHANGELOG.md             # GitHub-Landingpage + automatisch gepflegte Versionshistorie
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

### Datenbank-Schema (GRDB-Migrationen, Stand: v14)
| Migration | Inhalt |
|---|---|
| v1_create_core_tables | `feeds`, `articles`, `article_status`, `feed_logs` |
| v2_create_tag_tables | `tags`, `article_tags` |
| v3_create_feed_tag_table | `feed_tags` |
| v4_create_article_search_index | Volltextsuche für Artikel |
| v6_create_admin_definition_tables | Regeln, Regelbedingungen, intelligente Ordner + deren Bedingungen |
| v7_add_feed_admin_fields | Zusätzliche Feed-Verwaltungsfelder |
| v8_drop_unique_feed_url_index | Lockert Eindeutigkeits-Constraint auf Feed-URLs |
| v9_create_article_identity_history | Historie für Artikel-Identitätswechsel (z. B. bei URL-Änderungen) |
| v10_add_feed_retention_minimum_articles | Mindestanzahl Artikel pro Feed bei Aufbewahrungs-Cleanup |
| v11_add_article_statuses_hidden_read_index | Composite-Index `(isHidden, isRead)` auf `article_statuses` |
| v12_add_articles_published_coalesce_index | Expression-Index auf `COALESCE(publishedAt, arrivedAt)` |
| v13_add_article_statuses_foreign_key | `article_statuses` neu mit echtem Fremdschlüssel auf `articles` |
| v14_add_article_identity_history_retention_flag | `wasRemovedByRetention`-Flag auf `article_identity_history` |
| v15_add_feed_and_folder_sort_index | `sortIndex`-Spalte auf `feeds` + `feed_folders`, für manuelle Drag&Drop-Sortierung in der NSOutlineView-Sidebar |
| v16_add_tag_sort_index | `sortIndex`-Spalte auf `tags`, analog zu v15 — macht Tags in der Sidebar erstmals per Drag&Drop sortierbar |
| v19_drop_article_offline_table | Entfernt `article_offline` (Feature "Offline-Artikel-Download" vollständig entfernt, 2026-07-20) — Hinweis: v17/v18 fehlen in dieser Tabelle, das ist eine vorbestehende Dokumentationslücke außerhalb des Scopes dieser Änderung |
| v33_create_cloud_sync_settings | Single-Row-Tabelle `cloud_sync_settings` — DB-Spiegel des iCloud-Sync-Aktiv-Flags, damit der unsandboxed `FeedivoMCPServer`-Prozess den echten Wert sieht (UserDefaults bleibt Quelle der Wahrheit, Abgleich bei App-Start + Schalter-Umlegen) — Hinweis: v20–v32 fehlen ebenfalls in dieser Tabelle, dieselbe vorbestehende Dokumentationslücke wie bei v17/v18 |

**Achtung bei neuen Migrationen:** Vor dem Anlegen einer neuen Migration IMMER den
tatsächlichen letzten Eintrag in `FeedivoDatabaseMigrator.swift` prüfen (`grep -n
registerMigration`), nicht diese Tabelle oder eine ältere Design-Spec als Quelle der
Wahrheit nehmen — beim Bereinigung-dauerhaft-Feature (2026-07-14) ging eine Design-Spec
noch von `v10` als letztem Stand aus und schlug `v11` vor, obwohl v11–v13 zu diesem
Zeitpunkt bereits existierten; der Implementierungsplan hat das korrigiert (`v14`).

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
  `isCloudKitEnabled` an SwiftData hing, existiert dadurch nicht mehr. Ein neuer,
  GRDB-kompatibler Sync-Mechanismus wurde am 2026-07-24 als Phase 1 (CKSyncEngine-Fundament,
  nur Tags) umgesetzt — siehe den entsprechenden Eintrag unter „Aktuell in Arbeit" weiter
  unten. Der ursprünglich hierfür vorgesehene, SwiftData-basierte Branch ist dadurch
  vollständig überholt und wurde gelöscht (nicht mehr weiterverfolgt).
- **Datum:** 2026-07-07

### ADR-008: Sidebar auf AppKit NSOutlineView statt SwiftUI-natives Drag & Drop umgestellt
- **Entscheidung:** Die komplette Sidebar (Smart Folders, Tags, Ordner/Feeds) läuft seit
  2026-07-15 über eine einzige `NSOutlineView` (`SidebarOutlineView.swift`,
  `NSViewRepresentable` + Coordinator als DataSource/Delegate), nach dem Vorbild von
  NetNewsWire. Zeilen bleiben unveränderte, bestehende SwiftUI-Views (`FeedRowView` etc.),
  eingebettet per `NSHostingView`.
- **Grund:** SwiftUIs natives `.draggable`/`.dropDestination` (Feature 15.2) war
  intermittierend unzuverlässig — `dropDestination` feuerte manchmal gar nicht, oder die
  Datei-Promise-/Pasteboard-Verhandlung hing fest. Per Live-Diagnose reproduzierbar,
  keine SwiftUI-seitige Lösung gefunden.
- **Kern-Invariante:** `NSOutlineView` verwaltet NIE eigene Auswahl (`shouldSelectItem`
  immer `false`, `selectionHighlightStyle = .none`) — Auswahl/Ein-Ausklappen bleiben rein
  SwiftUI-/`@AppStorage`-gesteuert, nur per `expandItem`/`collapseItem` in die Outline
  gespiegelt.
- **Nebeneffekt:** Tags und Smart Folders sind dadurch jetzt erstmals auch per Drag & Drop
  sortierbar (vorher nur Feeds/Ordner) — neue Migrationen v15/v16 (`sortIndex` auf
  `feeds`/`feed_folders`/`tags`).
- **Wichtiger Gotcha zur automatischen Drag-Erkennung:** siehe unten.
- **Datum:** 2026-07-15. Umgesetzt via Brainstorming→Spec→Plan→Subagent-Driven-Development
  (6 Tasks + Whole-Branch-Fix-Runde + Live-Fix-Runde). Commits `3cc693c1f..7344983d2` auf
  `main` und auf `origin/main`. Live-Verifikation für Drag & Drop
  Feed↔Ordner vom Nutzer bestätigt; Tag-/Smart-Folder-Reordering und restliche Punkte des
  13-Punkte-Testprotokolls noch NICHT explizit durchgetestet.

### ADR-009: Eigenbau-Update-Installer durch Sparkle ersetzt
- **Entscheidung:** Der komplett selbst gebaute Update-Installer (`UpdateInstaller`,
  `UpdateArchiveExtractor`, `UpdateAppSwapper`, `UpdateChecker`, `GitHubRelease` u. a. —
  11 Produktions- + 7 Testdateien, vollständig gelöscht) ist seit 2026-07-31 durch das
  etablierte Sparkle-Framework (2.9.4, Swift Package) ersetzt. Neuer
  `SparkleUpdateCoordinator` (`Feedivo/Services/SparkleUpdateCoordinator.swift`) kapselt
  `SPUUpdater` + eine eigene `SPUUserDriver`-Konformität, damit die bereits gestylte UI
  (`UpdateAvailableSheet`, `UpdateUpToDateSheet` etc.) erhalten bleibt.
- **Grund:** Kein reiner Komfort-/Wartungsaufwand-Umstieg, sondern ein per Live-Debugging
  reproduzierter Architekturfehler des Eigenbaus: **App Sandbox verbietet einem
  sandboxed Prozess kategorisch, das `com.apple.quarantine`-Extended-Attribute von der
  frisch heruntergeladenen, entpackten Update-`.app` zu entfernen** — weder per
  `xattr -dr`-Subprozess noch über die native `URLResourceValues.quarantineProperties`-API
  gelingt das unter Sandbox, verifiziert durch Reproduktion mit einem eigenen, identisch
  signierten Sandbox-Testprogramm (Details siehe neuer Gotcha unten). Der alte
  `UpdateAppSwapper` konnte die selbst heruntergeladene neue Version deshalb nie
  quarantäne-frei an die Stelle der laufenden App setzen — ein struktureller, nicht
  code-seitig behebbarer Defekt, kein Bug im eigentlichen Sinn. Sparkle löst das über
  seinen eigenen, bewusst NICHT sandboxed `Autoupdate`-Hilfsprozess plus
  `SUEnableInstallerLauncherService`/eine gezielte mach-lookup-Entitlement-Ausnahme
  (`-spks`/`-spki`) — die App-Sandbox der Haupt-App selbst bleibt dabei unangetastet.
- **Zusätzlicher Vertriebskanal:** Parallel zur Sparkle-Anbindung wurde ein Homebrew Cask
  (`martinfelder/homebrew-feedivo`, `Casks/feedivo.rb`) eingerichtet. Eine per
  `HomebrewInstallationDetector.isHomebrewCaskInstall(bundleURL:)` erkannte
  Caskroom-Installation unterdrückt bewusst die Erzeugung eines `SPUUpdater` überhaupt —
  Homebrew-Nutzer aktualisieren ausschließlich über `brew upgrade`, ein gleichzeitig
  laufender Sparkle-Updater hätte dort zu konkurrierenden, sich gegenseitig
  überschreibenden Update-Pfaden geführt.
- **Umsetzung:** 14-Task-Plan via Brainstorming→Spec→Plan→Subagent-Driven-Development.
  Details, Status und die dabei gefundenen Bugs siehe „Aktuell in Arbeit" unten.
- **Datum:** 2026-07-31.

### ADR-010: Eigener SPUUserDriver durch Sparkles SPUStandardUserDriver ersetzt
- **Entscheidung:** `SparkleUpdateCoordinator` implementiert seit 2026-08-02 nicht mehr
  selbst das komplette `SPUUserDriver`-Protokoll (eigene SwiftUI-Sheets für "Update
  gefunden"/"Bereit zur Installation"/"Wird installiert", eigener `SparkleUpdateState`-
  Enum, eigene Continuation-Verwaltung) — stattdessen wird Sparkles eigener,
  produktiv erprobter `SPUStandardUserDriver` verwendet (`SPUStandardUserDriver(
  hostBundle:delegate:)`), exakt nach dem Vorbild von NetNewsWires echter,
  produktiver Sparkle-Integration (`AppDelegate.swift`, lokal geklont unter
  `/Users/martinfelder/Developer/NetNewsWire-main`).
- **Grund:** Nach dem ersten erfolgreichen Aufbau der Developer-ID-Signing- und
  Notarisierungs-Pipeline (siehe Nachtrag zu ADR-009 unten) blieb der eigentliche
  Update-Installationsvorgang live reproduzierbar hängen bzw. relaunchte die App
  nicht zuverlässig. Root-Cause-Kette über mehrere Live-Debugging-Runden (2026-08-02):
  (1) Ein eigenes SwiftUI-`.sheet`, das auch im `.installing`-Zustand sichtbar blieb,
  blockierte AppKits automatische App-Terminierung, die Sparkle per Quit-AppleEvent
  auslöst, damit der externe Relauncher den Dateitausch abschließen kann — per
  Unified-Log wortwörtlich verifiziert: `"App termination blocked by modal sheet"`.
  (2) Ein erster Fix (Sheet-Sichtbarkeit per State-Ausschluss von `.installing`) linderte
  das Symptom nur teilweise — der Dateitausch gelang danach zwar (installierte Version
  auf der Platte änderte sich korrekt), aber die App relaunchte sich nicht zuverlässig.
  (3) Ein zweiter, gezielterer Fix (synchroner, direkter `NSWindow.endSheet(_:)`-Aufruf
  statt der asynchron über `Task { @MainActor in ... }` laufenden SwiftUI-State-
  Aktualisierung — exakt das Muster, das Sparkles eigener `SPUStandardUserDriver` intern
  selbst nutzt, siehe `SPUStandardUserDriver.m: showInstallingUpdateWithApplicationTerminated:`)
  löste auch das nicht zuverlässig. Der Vergleich mit NetNewsWires tatsächlicher
  Produktions-Codebase zeigte: NetNewsWire deklariert zwar Konformität zu
  `SPUStandardUserDriverDelegate`/`SPUUpdaterDelegate`, implementiert davon aber NICHT
  EINE EINZIGE optionale Methode — die komplette UI/Fensterlebenszyklus-Verantwortung
  liegt vollständig bei Sparkles eigenem, von den Maintainern gegen genau diese Klasse
  von Terminierungs-/Fensterlebenszyklus-Fallstricken abgesicherten Code. Nach der
  Umstellung war der erste komplette End-to-End-Zyklus (Download → Notarisierungs-
  Gatekeeper-Check → Installation → App-Terminierung → Dateitausch → Neustart) live
  sofort erfolgreich.
- **Konsequenz:** `UpdateAvailableSheet.swift`, `UpdateUpToDateSheet.swift`,
  `SparkleUpdateState.swift`, `SparkleReleaseInfo.swift` sowie die zugehörigen Tests
  wurden komplett entfernt (kompletter eigener Sheet-/State-Code unnötig geworden).
  `AboutSettingsView` zeigt keinen eigenen Lade-Spinner/Update-Badge mehr beim manuellen
  Check — Sparkle zeigt Fortschritt/Ergebnis jetzt in seinen eigenen nativen Fenstern,
  analog zu NetNewsWires Einfachheit. `SparkleUpdateCoordinator` bleibt als dünner
  Wrapper bestehen (Homebrew-Erkennung, `checkForUpdatesManually()`,
  `setAutomaticChecksEnabled(_:)`, ein einfacher `NSAlert`-Hinweis für Homebrew-Nutzer
  statt eines eigenen Sheets).
- **Lehre:** Bei jedem künftigen "eigene UI über eine fremde, komplexe System-API legen"-
  Vorhaben (hier: eigene SwiftUI-Präsentation über Sparkles Callback-Protokoll) zuerst
  prüfen, ob eine echte, produktiv laufende Referenz-Implementierung (nicht nur
  Beispiel-/Demo-Code) existiert, die dieselbe Aufgabe bereits löst — ein Abgleich
  gegen NetNewsWires tatsächliche Codebase (nicht nur deren Doku) haette die spätere,
  mehrstufige Fehlersuche an Fensterlebenszyklus-/Terminierungs-Timing-Details von
  Anfang an vermeidbar gemacht. Zwei aufeinanderfolgende, jeweils plausible und einzeln
  live verifizierte Detail-Fixes reichten nicht aus, weil das grundsätzliche
  Architektur-Risiko (komplett eigener `SPUUserDriver` statt Sparkles eigenem Standard-
  Driver) bestehen blieb — passend zum "3+ fehlgeschlagene Fixversuche → Architektur
  hinterfragen"-Prinzip.
- **Datum:** 2026-08-02.

### ADR-011: Read-only MCP-Server als separates Command-Line-Tool-Target (kein eigenes Package)
- **Entscheidung:** `FeedivoMCPServer` ist ein eigenes, neu angelegtes Xcode-Target vom Typ
  `com.apple.product-type.tool` (Command-Line-Tool) — **kein** separates Swift Package. Es teilt
  sich seinen gesamten benötigten Quellcode (Records, Stores, Snapshots, `FeedivoDatabase`) über
  Xcode-Target-Membership mit dem Haupt-Target `Feedivo`, statt eine eigene Modul-Grenze/eigenen
  Package-Manifest-Baum zu pflegen. Kommunikation läuft über stdio-Transport des offiziellen
  `modelcontextprotocol/swift-sdk` (Produkt `MCP`). Der Server verbindet sich direkt und
  eigenständig mit der bereits vorhandenen SQLite-Datenbank im App-Sandbox-Container von Feedivo
  (`FeedivoContainerDatabaseLocation.swift` rekonstruiert den Container-Pfad manuell, da ein
  unsandboxed Prozess FileManagers automatische Container-Umleitung nicht bekommt) — unabhängig
  davon, ob die Feedivo-App gerade läuft. Führt bewusst NIE `FeedivoDatabaseMigrator` aus, setzt
  eine bereits existierende, aktuelle Datenbank voraus. v1 (2026-08-14) ist read-only und
  umfasst 7 Tools: `list_feeds`, `list_folders`, `list_tags`, `search_articles`, `get_article`,
  `list_smart_folders`, `get_smart_folder_articles`.
- **Grund für Target-Membership statt eigenem Package:** Direkter Zugriff auf denselben,
  bereits etablierten GRDB-Store-/Record-/Snapshot-Code, ohne diesen in eine gemeinsame,
  eigens zu pflegende Bibliothek extrahieren zu müssen — bei einem reinen Lese-Client, der
  nie eigenständig weiterentwickelt wird, war der Package-Split-Aufwand (eigenes Manifest,
  eigene Versionierung, API-Sichtbarkeits-Disziplin) laut Nutzerentscheidung nicht
  gerechtfertigt. Kehrseite: Target 2 [MANUELL] (das eigentliche Anlegen des Targets in
  Xcodes GUI, inkl. sukzessivem Ergänzen der Target-Membership für jede fehlende Symbol-
  Abhängigkeit) und Task 11 [MANUELL] (Einbetten ins App-Bundle per Copy-Files-Build-Phase)
  konnten nicht automatisiert werden — reine Xcode-Projektdatei-Bearbeitung, vom Nutzer
  selbst anhand präziser, per Grep identifizierter fehlender Symbole durchgeführt.
- **Bekannte, akzeptierte Einschränkung:** `xcodebuild test` kann `FeedivoMCPServerTests`
  strukturell nicht ausführen — Xcodes Build-System akzeptiert `com.apple.product-type.tool`-
  Targets nicht als gültigen `TEST_HOST` für die `test`-Aktion, unabhängig von der Konfiguration
  (verifiziert über mehrere unabhängige Diagnosewinkel: Scheme-XML, Test-Plan-JSON, Build-
  Settings, `PRODUCT_NAME` — kein Fix gefunden, als projektweite Standardgrenze akzeptiert).
  Nutzerentscheidung: Tests werden als echter Swift-Testing-Quellcode mitgeschrieben und bei
  jeder Task per `xcodebuild build` kompilierverifiziert, aber nicht laufzeitverifiziert über
  `xcodebuild test` — Absicherung stattdessen über echte Live-stdio-JSON-RPC-Smoke-Tests
  (manuell gestarteter, gebauter Prozess + echter `initialize`/`tools/call`-Roundtrip) durch
  Implementierer und Reviewer.
- **Umsetzung:** 12-Task-Plan via Brainstorming→Spec→Plan→Subagent-Driven-Development (Tasks
  1, 3–10 automatisiert; Tasks 2, 11, 12 `[MANUELL]`, vom Nutzer selbst ausgeführt). Finaler
  Whole-Branch-Review (opus) fand 1 Critical (Haupt-App-Scheme referenzierte versehentlich das
  Test-Target und brach dadurch `xcodebuild test` für das GESAMTE Hauptprojekt) + 5 Important +
  3 Minor — alle in einer Fix-Runde behoben. Ein scoped Re-Review dieser Fix-Runde deckte einen
  weiteren, eigenständigen kritischen Folgefehler auf (siehe neuer Gotcha zu GRDBs
  `PRAGMA query_only`-Verhalten direkt unten) — nach einer zweiten Fix-/Re-Review-Runde
  vollständig behoben und unabhängig bestätigt. Live-Verifikation in Claude Desktop (Task 12)
  erfolgreich, inkl. des entscheidenden Tests „funktioniert auch ohne jeden laufenden
  Feedivo-Prozess" (sowohl `/Applications`-Instanz als auch eine zusätzlich gefundene,
  an einen `debugserver` gehängte Xcode-Debug-Build-Instanz beendet, Abfragen liefen
  weiterhin korrekt). Spec: `docs/superpowers/specs/2026-08-12-feedivo-mcp-server-design.md`,
  Plan: `docs/superpowers/plans/2026-08-12-feedivo-mcp-server.md`. Commits `4ed7498..ac2a3eb`
  auf `main`, gepusht (`d586d01..ac2a3eb`).
- **Datum:** 2026-08-14.

---

## Bekannte Gotchas & Fallstricke

> Diese Liste wächst während der Entwicklung. Immer ergänzen!

- **GRDB-Datenbankzugriffe sind nicht reentrant — ein `database.read`/`database.write` von
  innerhalb eines bestehenden `db: Database`-Blocks crasht zur Laufzeit:** GRDB erzwingt das
  mit `GRDBPrecondition(currentReader == nil, "Database methods are not reentrant.")`
  (`DatabasePool.swift:340`, für `DatabaseQueue` in `DatabaseQueue.swift:445` dokumentiert).
  Aufgefallen beim Planen der iCloud-Sync-Settings-DB-Spiegelung (2026-08-15): die Design-Spec
  schlug vor, die 8 `enqueuePendingSync`-Gates auf
  `CloudSyncSettingsStore(database: self.database).isEnabled()` umzustellen, und nannte das
  „rein mechanisch" — tatsächlich laufen alle diese Gates bereits INNERHALB einer offenen
  `database.write`-Transaktion (Parameter `db: Database`), der Vorschlag wäre in jedem Test
  (`inMemoryForTests()` = `DatabaseQueue`, eine einzige serialisierte Verbindung) sofort
  gecrasht. **Lehre:** Bei jeder neuen Hilfsfunktion, die aus einer bestehenden Store-Methode
  heraus die Datenbank lesen will, zuerst prüfen, ob die aufrufende Methode einen
  `db: Database`-Parameter hat — wenn ja, MUSS die Hilfsfunktion diesen `db` entgegennehmen
  (`static func isEnabled(in db: Database)`) statt sich eine eigene Verbindung zu holen. Das
  ist zugleich fachlich richtiger: der Lesevorgang sieht garantiert denselben Zustand wie die
  Mutation, die er begleitet.
- **GRDBs `DatabaseQueue`/`DatabasePool` setzen `PRAGMA query_only` bei JEDEM `.read()`-Block
  intern selbst wieder zurück — eine manuell per `configuration.prepareDatabase` gesetzte
  `PRAGMA query_only = ON` bietet dadurch KEINEN belastbaren Schreibschutz, sobald
  `configuration.readonly` nicht gesetzt ist:** Beim `FeedivoMCPServer`-Whole-Branch-Review
  (2026-08-14, siehe ADR-011) ersetzte ein erster Fix-Versuch das ursprüngliche
  `configuration.readonly = true` durch `DatabasePool` + manuell gesetzte
  `PRAGMA query_only = ON` (Begründung: SQLite kann eine WAL-Datenbank nicht read-only öffnen,
  wenn die zugehörige `-shm`-Datei fehlt — ein Zustand, der eintreten kann, wenn Feedivo
  komplett beendet ist). Ein Re-Review fand daraufhin einen ersten Bug (`DatabasePool.init`
  führt beim Öffnen zwingend ein WAL-Setup aus, das bei fehlender/leerer `-wal`-Datei selbst
  einen Schreibvorgang ausführt, den `PRAGMA query_only` ablehnt — der Server startete dadurch
  NIE, wenn Feedivo nicht lief, exakt der Fall, den der Fix beheben sollte). Der naheliegende
  Folgefix (`DatabaseQueue` statt `DatabasePool`, `PRAGMA query_only` beibehalten, vermeidet den
  WAL-Setup-Schreibzugriff) behob das Öffnungsproblem, enthielt aber einen ZWEITEN,
  unabhängigen und schwerwiegenderen Bug: GRDBs `Database.beginReadOnly()`/`endReadOnly()`
  (`GRDB/Core/Database.swift`, aufgerufen aus `DatabaseQueue.read`/`.write`) verwalten
  `PRAGMA query_only` intern selbst — `beginReadOnly()` setzt es auf `1`, `endReadOnly()` setzt
  es nach jedem `.read()`-Block automatisch wieder auf `0` zurück, sofern
  `configuration.readonly == false` (beide Methoden haben ein frühes `if configuration.readonly
  { return }`, das diesen internen Mechanismus komplett deaktiviert, wenn die Config selbst
  bereits readonly ist). Empirisch reproduziert (isoliertes SwiftPM-Testharness mit GRDB aus
  demselben Checkout, echte Kopien der Produktions-DB): ein `queue.read { … }` gefolgt von
  `queue.write { CREATE TABLE … }` legte tatsächlich eine Tabelle an, obwohl vorher
  `PRAGMA query_only = ON` per `prepareDatabase` gesetzt worden war — die gesamte Absicherung
  war wirkungslos, sobald irgendein `.read()` gelaufen war. **Tatsächlicher, korrekter Fix:**
  `configuration.readonly = true` mit `DatabaseQueue` (NICHT `DatabasePool`) — liefert echten,
  über `SQLITE_OPEN_READONLY` durchgesetzten Schreibschutz (GRDBs interne Read-Only-Verwaltung
  greift dann von vornherein gar nicht erst ein) UND öffnet erfolgreich in allen praktisch
  erreichbaren Zuständen (laufende App mit aktivem `-wal`, sauber beendete App mit leerem,
  aber vorhandenem `-wal`, sowie — ein beim zweiten Re-Review zusätzlich entdeckter, dritter
  funktionierender Fall — vorhandenes `-wal` OHNE `-shm`, was die ursprüngliche Prämisse des
  ersten Fix-Versuchs widerlegt: fehlendes `-shm` allein ist unkritisch, nur ein komplett
  fehlendes `-wal` scheitert). Ein komplett fehlendes `-wal` ist für Feedivo praktisch
  unerreichbar, da das Haupt-Target seit dem `DatabasePool`-Umstieg (2026-08-05, siehe unten)
  durchgehend WAL-Modus nutzt und SQLite die `-wal`/`-shm`-Sidecar-Dateien beim normalen
  Schließen nicht löscht (empirisch verifiziert: sowohl `close()` als auch reines `deinit`
  lassen ein 0-Byte-`-wal` zurück). **Lehre:** Bei JEDEM künftigen Versuch, eine GRDB-
  Datenbankverbindung nachträglich per `PRAGMA query_only` statt über `configuration.readonly`
  hart auf Lesen zu beschränken, davon ausgehen, dass GRDBs eigene interne Read-Only-Buchhaltung
  diese manuelle Pragma-Setzung bei jedem regulären `.read()`-Aufruf stillschweigend wieder
  aufhebt — ein Test, der nur „öffnet die Verbindung erfolgreich" und „ein isolierter
  `.write()`-Aufruf OHNE vorheriges `.read()` schlägt fehl" prüft, deckt genau diese Lücke
  NICHT auf (der ursprüngliche Task-4-Test `schreibversucheSchlagenFehl` hätte unter der
  `query_only`-Variante als Fehlalarm-Grün durchlaufen, da er kein `.read()` vor dem `.write()`
  ausführt). Nur `configuration.readonly = true` ist als echte, robuste Schreibsperre
  verifiziert.
- **`xcodebuild test` kann ein Command-Line-Tool-Target (`com.apple.product-type.tool`) NICHT
  als `TEST_HOST` für die zugehörige Test-Suite akzeptieren, unabhängig von der Konfiguration —
  betrifft `FeedivoMCPServerTests`, siehe ADR-011:** Egal wie Scheme (`.xcscheme`-XML), Test-
  Plan (`.xctestplan`-JSON), Build-Settings oder `PRODUCT_NAME` konfiguriert werden — `xcodebuild
  test` bricht mit „Could not find test host" ab. Über mehrere unabhängige Diagnosewinkel
  verifiziert, kein Fix gefunden; als projektweite, strukturelle Xcode-Einschränkung akzeptiert
  (Entscheidung des Nutzers). Konsequenz für dieses Target: Tests werden weiterhin als echter
  Swift-Testing-Quellcode geschrieben und bei jeder Änderung per `xcodebuild build` (reine
  Kompilierverifikation) abgesichert, aber nie per `xcodebuild test` laufzeitverifiziert — echte
  Laufzeitabsicherung läuft stattdessen über manuell gestartete, echte stdio-JSON-RPC-Smoke-Tests
  gegen den gebauten Prozess (`initialize`→`notifications/initialized`→`tools/call`), auch gegen
  die echte, laufende Produktions-Datenbank des Nutzers. **Ein zusätzlich in derselben Session
  gefundener, davon unabhängiger Bug desselben Symptoms:** `Feedivo.xcscheme` (das Scheme des
  HAUPT-Targets, nicht von `FeedivoMCPServer`) hatte versehentlich eine `TestableReference` auf
  `FeedivoMCPServerTests` erhalten — das brach dadurch `xcodebuild test` für das GESAMTE
  Hauptprojekt (nicht nur den MCP-Server), da dieselbe strukturelle TEST_HOST-Einschränkung dort
  ebenfalls griff. Fix: `TestableReference` aus `Feedivo.xcscheme` entfernt — bei künftigen
  „warum bricht `xcodebuild test` für `Feedivo` plötzlich komplett ab"-Fällen als Erstes
  `git diff -- '*.xcscheme'` prüfen, nicht nur den offensichtlichsten Verdächtigen (das
  zuletzt geänderte Target selbst). **Nachtrag (2026-08-14/15, MCP-Server V2 Phase 1 —
  Schreibzugriff-Fundament, siehe „Aktuell in Arbeit"):** die Lücke ist noch größer als
  ursprünglich dokumentiert — nicht nur `xcodebuild test`/`build-for-testing` scheitern
  strukturell an `FeedivoMCPServerTests` (Abbruch mit „Could not find test host", noch
  bevor irgendetwas kompiliert wird), sondern auch das eigentlich naheliegende
  `xcodebuild build -scheme FeedivoMCPServer` kompiliert `FeedivoMCPServerTests` GAR
  NICHT erst mit — per direktem Blick in die Scheme-XML verifiziert: die `BuildAction`
  des `FeedivoMCPServer`-Schemes listet ausschließlich das `FeedivoMCPServer`-Produkt
  selbst, keine `BuildActionEntry` für das Test-Target. Es gibt damit in diesem Projekt
  KEINEN einzigen `xcodebuild`-Aufruf, der eine `FeedivoMCPServerTests`-Quelldatei
  compile-verifizieren kann. Alle Testdateien, die im Zuge dieses Plans neu zu
  `FeedivoMCPServerTests` hinzukamen (Tasks 3–6: `FeedivoMCPServerWritableDatabaseTests`,
  Tool-Tests für `update_article_status`/`assign_tag`/`remove_tag`,
  `MCPWriteNotifierTests`) wurden deshalb NICHT durch einen Build-Lauf abgesichert,
  sondern ausschließlich durch sorgfältiges manuelles Gegenlesen gegen bereits
  kompilierende, bewährte Code-Muster im selben Target (API-Signaturen jeweils direkt
  gegen die aufgerufenen echten Quelldateien abgeglichen). **Lehre:** Bei diesem Target
  nicht nur davon ausgehen, dass `test`/`build-for-testing` nicht funktionieren, sondern
  explizit prüfen (Scheme-XML oder ein Testlauf-Versuch), ob überhaupt IRGENDEIN
  `xcodebuild`-Befehl die Testdatei kompiliert, bevor man sich auf „der Build war ja
  grün" als Testabsicherung verlässt.

- **„Field 'recordName' is not marked queryable" ist NICHT nur eine Dashboard-Records-Browser-
  Eigenheit — der Fehler tritt auch bei echten `CKQuery`-Aufrufen aus App-Code auf, wenn im
  CloudKit-Schema für den betroffenen Record-Type kein Queryable-Index auf dem Systemfeld
  `recordName` gesetzt ist:** Bisher (siehe die beiden Live-Verifikations-Einträge vom
  2026-07-24/26 weiter unten) war dieser exakte Fehlertext nur beim manuellen Nachschauen im
  CloudKit-Dashboard-Records-Browser aufgetreten und wurde dort korrekt als reine
  Tooling-Eigenheit eingeordnet (Queryable-Index muss erst per „Deploy Schema Changes…"
  propagiert werden, bevor der Browser zuverlässig Treffer findet). Beim Erst-Aktivierungs-
  Dialog (`CloudSyncFirstActivationView`/`-Analyzer`) zeigte sich am 2026-08-08 per
  Nutzer-Report + `/usr/bin/log stream`-Live-Diagnose: derselbe Fehler tritt auch bei einem
  ganz gewöhnlichen `CKQuery(recordType:predicate: NSPredicate(value: true))`-Aufruf
  (`database.records(matching:inZoneWith:)`) aus echtem App-Code auf, wirft dabei
  `CKError.invalidArguments` und lässt die Abfrage komplett scheitern — kein Browser-Rendering-
  Problem, sondern ein reales, für App-seitige Queries wirksames Schema-Konfigurationsdefizit.
  Root Cause: für die Record-Types „Tag"/„FeedFolder" fehlt im CloudKit-Schema (Development-
  Umgebung) ein Queryable-Index auf `recordName` — muss einmalig manuell im CloudKit Dashboard
  ergänzt werden (Schema → Record Type → Indexes → „Record Name" als Queryable hinzufügen),
  vor einem Live-Release zusätzlich per „Deploy Schema Changes" auf Production übertragen. Kein
  Code-Fix möglich, kein `cktool` auf diesem Rechner installiert (`which cktool` → not found),
  also nur über die Dashboard-UI behebbar. **Lehre:** Bei künftigen CloudKit-Query-Fehlern mit
  genau diesem Fehlertext nicht vorschnell als "nur Dashboard-Anzeige-Eigenheit" abtun — echte
  App-Queries können denselben fehlenden Index genauso treffen. `CloudSyncFirstActivationAnalyzer.
  isMissingQueryableIndexError(_:)` erkennt den Fehler jetzt gezielt und zeigt eine actionable
  Meldung statt einer generischen "Prüfung fehlgeschlagen (Netzwerk?)"-Warnung. **Live-
  Verifikation (2026-08-08):** Fix bestätigt — der „Add Index"-Dialog im aktuellen CloudKit
  Dashboard hat 4 Felder (nicht 3, wie zunächst vermutet): „Record Type" (Dropdown, z. B. „Tag"),
  „Name" (freier Text, reine Bezeichnung des Index selbst — nicht der indizierte Feldname), „Type"
  (Dropdown, hier „QUERYABLE" wählen), und erst NACH Auswahl von „Type" erscheint ein viertes
  Feld „Field" (Dropdown mit den tatsächlichen Feldern des Record-Type, u. a. den Systemfeldern
  `createdTimestamp`/`modifiedTimestamp`/`recordName` sowie den eigenen Feldern wie `name`/
  `colorHex`/`sortIndex`) — dort `recordName` auswählen. Für „Tag" UND „FeedFolder" je einen
  solchen Index ergänzt, direkt danach zeigte der Dialog in der App keine Fehlermeldung mehr.
- **`xcodebuild test -only-testing:...` kann nach einer reinen Testdatei-Änderung (neue Test-
  Methode, kein Produktivcode geändert) den ALTEN, gecachten Test-Bundle ohne jeden Rebuild-
  Versuch wiederverwenden und trotzdem „TEST SUCCEEDED" melden — mit der VORHERIGEN Testanzahl,
  ohne die neuen Tests überhaupt auszuführen, und OHNE jede Fehlermeldung, selbst wenn der neue
  Testcode gar nicht kompilieren würde:** Beim TDD-RED-Schritt für
  `CloudSyncFirstActivationAnalyzer.isMissingQueryableIndexError` (2026-08-08) meldete ein
  direkt nach dem Hinzufügen der (bewusst noch fehlschlagenden) Tests ausgeführtes
  `xcodebuild test -only-testing:...` fälschlich „TEST SUCCEEDED" mit der alten Testanzahl (9
  statt der erwarteten 12) — keine Compile-Fehler im Log, keine Erwähnung der geänderten
  Testdatei im Build-Log überhaupt (kein `SwiftCompile`-Eintrag dafür). Reproduzierbar über zwei
  aufeinanderfolgende identische Aufrufe. Erst `xcodebuild clean` gefolgt von
  `build-for-testing` deckte den tatsächlichen, erwarteten Compile-Fehler auf
  (`has no member 'isMissingQueryableIndexError'`). Nach der eigentlichen Implementierung lief
  ein normaler (nicht-cleaner) `build-for-testing` dann wieder korrekt und erkannte
  Änderungen zuverlässig — der Aussetzer trat nur bei diesem einen RED-Schritt auf, Ursache
  nicht abschließend geklärt (vermutlich ein Timing-/Dateisystem-Event-Problem des neuen
  Build-Systems, ähnlich der bereits dokumentierten SourceKit-Diagnose-Unzuverlässigkeit, hier
  aber den tatsächlichen `xcodebuild`-Testlauf selbst betreffend, nicht nur die IDE-Anzeige).
  **Lehre:** Bei einem verdächtig unveränderten Testergebnis nach einer Testdatei-Änderung
  (gleiche Testanzahl, keine neuen Tests in der Ausgabe sichtbar) nicht blind auf „TEST
  SUCCEEDED" vertrauen — mit `xcodebuild clean` + `build-for-testing` gegenprüfen, bevor man
  eine RED-Bestätigung oder ein GREEN-Ergebnis als echt akzeptiert.
- **`xcodebuild test -only-testing:<Target>/<Suite>/<einzelne Testmethode>` (Einzelmethoden-
  Selektor) kann „TEST SUCCEEDED" melden, obwohl `totalTestCount: 0` ist — ein davon
  UNABHÄNGIGER Fehlalarm als der oben dokumentierte „stale test bundle"-Gotcha:** Gefunden und
  von zwei unabhängigen Seiten bestätigt (Task-Implementierer UND Task-Reviewer, jeweils
  eigener Lauf) beim MCP-Server-Schalter-Feature (2026-08-14, Task 1, Migration v31). Der
  Aufruf `xcodebuild test -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests/
  migrationV31...` liefert `** TEST SUCCEEDED **`, aber `xcrun xcresulttool get test-results
  summary` auf das erzeugte `.xcresult`-Bundle zeigt `"totalTestCount" : 0` — der einzelne Test
  lief in Wirklichkeit gar nicht. Der volle Suiten-Selektor
  (`-only-testing:FeedivoTests/FeedivoDatabaseMigratorTests`, ohne die letzte Methoden-Ebene)
  funktioniert dagegen zuverlässig korrekt. **Lehre:** Bei einem `-only-testing`-Aufruf mit
  Einzelmethoden-Granularität IMMER zusätzlich `xcrun xcresulttool get test-results summary`
  auf das `.xcresult`-Bundle prüfen (oder direkt den vollen Suiten-Selektor verwenden) — ein
  bloßes „TEST SUCCEEDED" allein ist bei dieser Granularität kein verlässlicher Nachweis, dass
  überhaupt ein Test gelaufen ist.
- **Sparkle-Updates NIEMALS aus einer von Xcode gestarteten/debuggten App testen —
  weder Debug- noch ein einfacher lokaler Release-Build genügen:** Live-Debugging
  (2026-08-01/02) zeigte per `codesign -dv`: bei einem via Xcode gestarteten Build
  (egal ob Debug oder ein simples `xcodebuild -configuration Release build` in
  DerivedData) hat der eingebettete `Autoupdate`-Hilfsprozess (Sparkle.framework)
  `TeamIdentifier=not set` — Xcodes normaler lokaler Build-/Codesign-Schritt signiert
  die von Sparkle mitgelieferten Hilfs-Binaries (Autoupdate/Installer.xpc/Updater.app)
  NICHT mit der vollen Developer-ID-Identität nach, unabhängig vom sonstigen
  Signing-Setup des Haupt-Targets. Sparkle erkennt das (`SUPlainInstaller.m`, Vergleich
  von `installerTeamIdentifier` gegen die Team-ID des neu heruntergeladenen Updates)
  und überspringt bewusst den atomaren Dateitausch (`"Skipping atomic rename/swap and
  gatekeeper scan because Autoupdate is not signed with same identity..."`) — das ist
  offizielles, dokumentiertes Sparkle-Verhalten (macOS 13+, siehe Kommentar in
  `SUPlainInstaller.m: performInitialInstallation`), kein Bug. Ein echter, im Feld
  laufender Selbst-Update-Test braucht immer eine über die volle `archive` +
  `-exportArchive`-Kette (`method: developer-id`) gebaute, Developer-ID-signierte
  UND notarisierte `.app`, eigenständig gestartet (Doppelklick/`open`), niemals über
  den Xcode-"Run"-Knopf oder einen angehängten Debugger.
- **`xcrun notarytool --keychain-profile` funktioniert zuverlässig bei interaktiven/
  inline getippten Aufrufen, schlägt aber reproduzierbar mit "No Keychain password
  item found for profile" fehl, sobald derselbe Aufruf aus einer AUSGEFÜHRTEN
  Skriptdatei (`./datei.sh`) kommt:** Live isoliert (2026-08-01/02) über mehrere
  Kontrollversuche — Warp UND Terminal.app ausgeschlossen (identischer Fehler in
  beiden), Smart-Quotes-Verunreinigung beim Copy-Paste ausgeschlossen (auch von Hand
  getippt reproduzierbar), Session-Scoping der macOS Data-Protection-Keychain
  vermutet, aber nicht abschließend bewiesen. Sauber reproduziert mit einer
  minimalen, isolierten Testdatei: `xcrun notarytool history --keychain-profile
  NAME` direkt getippt → Erfolg; dieselbe Zeile in eine ausführbare `.sh`-Datei
  geschrieben und per `./datei.sh` ausgeführt → zuverlässig derselbe "nicht
  gefunden"-Fehler. **Lösung/Empfehlung (auch Apples eigene für CI/Automatisierung):**
  App-Store-Connect-API-Key-Authentifizierung (`--key <Pfad-zur-.p8-Datei> --key-id
  <ID> --issuer <Issuer-ID>`) statt `--keychain-profile` — liest nur eine Datei direkt
  ein, keinerlei Keychain-Zugriff, funktioniert dadurch identisch in jedem Kontext.
  `.p8`-Datei liegt projektweit unter `~/.appstoreconnect/private_keys/
  AuthKey_<KeyID>.p8` (chmod 600), Key-ID/Issuer-ID sind in `create_github_release.sh`
  fest hinterlegt (keine Geheimnisse für sich genommen, nur zusammen mit der
  `.p8`-Datei nutzbar).
- **`xcodebuild -exportArchive` mit `method: developer-id` + `signingStyle: automatic`
  kann auf der Kommandozeile ein BESTEHENDES, passendes Provisioning-Profil finden,
  aber kein neues erzeugen — dafür ist einmalig die Xcode-GUI nötig:** Beim allerersten
  Export dieser Art schlug der Export mit `error: exportArchive No profiles for
  'ch.martin.Feedivo' were found` fehl, obwohl `~/Library/MobileDevice/Provisioning
  Profiles/` schlicht noch nie befüllt worden war (`ls` bestätigte: Ordner existierte
  nicht). Fix: einmalig in Xcode **Product → Archive** + im Organizer **Distribute
  App → Developer ID/Direct Distribution** komplett durchlaufen lassen — das legt das
  passende Profil an, aber unter dem NEUEREN Speicherort
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`, nicht dem klassischen
  `~/Library/MobileDevice/Provisioning Profiles/`, den `xcodebuild -exportArchive`
  auf der Kommandozeile durchsucht — das passende `.provisionprofile` (zu erkennen am
  Namen "Mac Team **Direct** Provisioning Profile", nicht am regulären "Mac Team
  Provisioning Profile") muss deshalb zusätzlich manuell an den klassischen Ort
  kopiert werden, bevor Kommandozeilen-Exports funktionieren.
- **Beim Toggeln einer Capability (z. B. iCloud) in Xcodes Signing-&-Capabilities-UI
  IMMER per `git diff` prüfen, was sich tatsächlich in den `.entitlements`-Dateien
  geändert hat — Xcode kann dabei sowohl bestehende Container-Zuordnungen leeren als
  auch stillschweigend eine ZWEITE, Konfigurations-spezifische Entitlements-Datei
  anlegen:** Ein Aus-/wieder-Anschalten der iCloud-Capability (2026-08-02, zur
  Fehlersuche beim fehlenden Provisioning-Profil) leerte `com.apple.developer.
  icloud-container-identifiers`/`icloud-services` in der bestehenden `Feedivo.
  entitlements` (Debug-Konfiguration) komplett UND legte parallel eine neue
  `FeedivoRelease.entitlements` (Release-Konfiguration, `CODE_SIGN_ENTITLEMENTS`-
  Pointer im `.pbxproj` entsprechend umgebogen) an, deren Container-Liste ebenfalls
  leer blieb — nur der reine CloudKit-Service-Haken war gesetzt. Für dieses Projekt
  mit CKSyncEngine-basiertem iCloud Sync (siehe M3-Abschnitt) ein potenziell
  datenkritischer Vorgang. Immer `git diff -- '*.entitlements'` nach JEDER
  Capability-Interaktion in Xcode prüfen, nicht nur nach einem Build-Fehler.
- **`find -path "*sparkle*/artifacts/sparkle/Sparkle/bin/sign_update"` matcht NIE,
  wenn "sparkle" nur innerhalb des bereits fest im Muster stehenden Suffix-Teils
  vorkommt, nicht davor:** `find -path` verlangt, dass der GESAMTE gefundene Pfad
  gegen das komplette Glob-Muster passt — `*sparkle*` braucht eine EIGENE, vom Rest
  des Musters unabhängige Fundstelle für den Substring "sparkle" irgendwo VOR
  `/artifacts/sparkle/Sparkle/bin/sign_update`. Der tatsächliche, reale Pfad
  (`.../SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update`) hat aber genau
  davor nur "SourcePackages" stehen — kein zweites "sparkle" — wodurch das Muster
  nie traf und `create_github_release.sh` bei JEDEM echten Release-Lauf mit
  "sign_update-Tool nicht gefunden" abbrach (Appcast blieb dadurch unaktualisiert,
  obwohl GitHub-Release + Notarisierung bereits erfolgreich durchgelaufen waren).
  Fix: Muster auf `*/Sparkle/bin/sign_update` vereinfacht (matcht den tatsächlichen
  Pfad korrekt UND schließt die parallel existierende Legacy-Variante
  `.../Sparkle/bin/old_dsa_scripts/sign_update` weiterhin sauber aus, da dort direkt
  vor `sign_update` "old_dsa_scripts" statt "bin" steht). **Lehre:** Bei jedem
  `find -path`-Muster mit einem Wildcard-Segment, das denselben Substring enthält
  wie ein bereits fest im Muster stehender späterer Teil, den tatsächlichen
  Ziel-Pfad einmal konkret ausgeben lassen und das Muster dagegen verifizieren,
  statt aus der Musterlogik allein auf Korrektheit zu schließen.
- **`raw.githubusercontent.com` setzt `Cache-Control: max-age=300` auf `docs/
  appcast.xml` — ein frisch gepushter neuer Appcast-Eintrag kann bis zu 5 Minuten
  lang von einer bereits vorher fetchenden App/einem lokalen URL-Cache als "nicht
  gefunden" erscheinen, obwohl der Server längst die neue Version ausliefert**
  (`curl -sI` zeigt das via `cache-control`-Header direkt). Kein Bug, reines
  Timing — bei einem "Update wird nicht gefunden, obwohl der Appcast doch aktuell
  ist"-Verdacht immer zuerst den Cache-Header prüfen und ein paar Minuten warten,
  bevor an der eigentlichen Update-Logik gesucht wird.
- **`article_statuses.articleID` ist pro Gerät zufällig — eine iCloud-Sync-Identität, die
  direkt darauf aufbaut, kann geräteübergreifend NIE matchen:** Beim Whole-Branch-Review von
  iCloud Sync Phase 2b (Artikelstatus-Sync, 2026-07-25) fand der Reviewer einen kritischen
  Architekturfehler, den keiner der 9 Einzel-Task-Reviews sehen konnte: Artikel selbst werden
  in keiner Phase synct — jedes Gerät entdeckt denselben RSS-Artikel unabhängig per eigenem
  Feed-Refresh und vergibt dabei via `ArticleStore.upsert()` eine eigene, zufällige
  `UUID().uuidString` als `articles.id`. Der ursprüngliche `CloudSyncArticleStatusMapping`
  keyte den `ArticleStatus`-`CKRecord` direkt über diese lokale `articleID` — dadurch konnte
  ein von Gerät A hochgeladener Status auf Gerät B NIE gefunden werden (Gerät B hat denselben
  logischen Artikel unter einer anderen UUID), landete dauerhaft in
  `orphaned_article_status_updates` und wurde nach 90 Tagen kommentarlos verworfen.
  Gelesen/Stern-Sync zwischen zwei Geräten funktionierte dadurch faktisch nicht — trotz
  86/86 grüner Tests in allen 9 Einzel-Tasks, da jeder Test dieselbe In-Memory-DB mit
  derselben `articleID` auf "Sender"- und "Empfänger"-Seite nutzte und damit exakt die
  Falschannahme mit-testete. **Fix:** neue, aus `feedID`+`sourceID`/`link`/`titleHash`
  abgeleitete `syncStableID` (SHA256-Hash, siehe `CloudSyncArticleStatusMapping.
  stableRecordName`) — dieselbe Priorisierung wie die bereits bestehende
  `ArticleStore.findExistingArticleID`/`findIdentityHistory`-Identitätslogik, `feedID` ist
  bereits geräteübergreifend stabil (Feeds werden per CloudKit-Sync-ID übernommen, nicht
  unabhängig neu erzeugt). Wird für JEDE neu eingefügte `article_statuses`-Zeile berechnet
  (nicht nur berührte — sonst könnte ein Gerät, das einen Status nie selbst berührt hat,
  einen eingehenden Status trotzdem nicht zuordnen), Migration v26 backfillt Bestandszeilen
  per Swift-Loop (SQLite hat keine SHA256-Funktion). **Zweiter, beim ersten Fix-Review
  gefundener Folgefehler:** `ArticleStatusStore.enqueuePendingSync` (der primäre Live-Sync-
  Pfad über `setRead`/`setStarred`/`markAllUnreadAsRead`) blieb zunächst auf der alten
  lokalen `articleID` hängen, während `makeCKRecord(fromLocalID:)` bereits auf `syncStableID`
  umgestellt war — jedes `.save` wäre dadurch stillschweigend als `nil` verworfen worden und
  hätte den gesamten Fix wirkungslos gemacht. Sofort in derselben Fix-Runde behoben (per
  Round-Trip-Test verifiziert: `setRead` → Pending-Change lesen → echtes
  `makeCKRecord(fromLocalID:)` → nicht-`nil`). **Dritter Fund:** `applyIncomingDeletion`
  nullte `syncStableID` beim Zurücksetzen einer Zeile auf Defaults — da nirgends sonst
  `syncStableID` nachträglich neu berechnet wird, hätte das die Zeile dauerhaft aus jeder
  künftigen Sync-Betrachtung ausgeschlossen, selbst nach erneutem Lesen/Stern-Setzen durch
  den Nutzer. Ebenfalls sofort behoben (Reset lässt `syncStableID` jetzt unangetastet).
  **Lehre:** Bei JEDEM künftigen Sync-Mapping für eine Tabelle, deren Zeilen auf MEHREREN
  Geräten unabhängig voneinander neu entstehen können (nicht nur auf einem Gerät erzeugt und
  dann verteilt, wie bei Tags/Feeds/Regeln), reicht die lokale Primärschlüssel-Spalte NICHT
  als `CKRecord.ID`-Basis — und Tests müssen das Zwei-Geräte-Szenario mit zwei UNABHÄNGIGEN
  In-Memory-Datenbanken und zwei UNTERSCHIEDLICHEN lokalen IDs für denselben logischen
  Datensatz abbilden, sonst bleibt genau diese Klasse von Fehlern für jeden Einzel-Task-
  Review unsichtbar. Zusätzlich: bei einer Identitäts-Umstellung IMMER alle Enqueue-Pfade
  durchsuchen (nicht nur den, den der aktuelle Task explizit ändert) — der Live-Sync-Pfad
  (`enqueuePendingSync`) lag außerhalb des ursprünglich geänderten Dateiumfangs und wäre
  fast unentdeckt geblieben.

- **`CKSyncEngine`s manueller `sendChanges()`-Aufruf per einfachem `Task { }` stürzt ab, sobald
  er aus einem Delegate-Callback heraus (z. B. Konfliktauflösung) erneut ausgelöst wird —
  braucht zwingend `Task.detached`:** Beim Live-Testen der Sync-Status-Übersicht (2026-07-24)
  meldete die App wiederholt `Fatal error: BUG IN CLIENT OF CLOUDKIT: Cannot await a call into
  CKSyncEngine from within a delegate callback if that function will end up calling back into
  the delegate. ... Try performing this in a detached Task.` Root Cause: `CloudSyncEngine.
  notifyPendingChangesAvailable(database:)` (aus Phase 1, `Feedivo/Services/CloudSync/
  CloudSyncEngine.swift`) löst nach `state.add(pendingRecordZoneChanges:)` bewusst zusätzlich
  `syncEngine.sendChanges()` manuell aus (Apples eigene "manual override" gegen die
  System-Scheduler-Verzögerung von `automaticallySync`), verpackt in einen gewöhnlichen,
  nicht-detachten `Task { ... }`. Diese Methode wird von drei Stellen aufgerufen — zwei davon
  unkritisch (`start()`, Store-Mutationen nach UI-Aktionen), die dritte aber aus
  `handleFailedSave(_:)` heraus, dem Last-Write-Wins-Konfliktauflösungspfad, der selbst
  innerhalb von `CKSyncEngineDelegate.handleEvent(_:syncEngine:)` läuft. `sendChanges()` ruft
  intern wieder in den Delegate zurück (`nextRecordZoneChangeBatch`) — ein normaler,
  nicht-detachter `Task {}` erbt dabei den Ausführungskontext des aufrufenden Delegate-Callbacks
  und wird von CKSyncEngine deshalb weiterhin als "innerhalb des Callbacks" gewertet, was den
  Fatal Error auslöst. Das Muster existierte unverändert seit Phase 1, ohne je zu crashen — erst
  das wiederholte Live-Testen der neuen Status-Übersicht (schnell hintereinander Tags/Feeds
  anlegen/löschen) erzeugte offenbar zum ersten Mal echte Server-Konflikte und traf damit den
  betroffenen Pfad. Fix: `Task.detached { ... }` statt `Task { ... }` — genau die von der
  Fehlermeldung selbst empfohlene Lösung, sicher an allen drei Aufrufstellen dieser Methode.
  **Lehre:** Bei JEDEM manuellen `CKSyncEngine`-Methodenaufruf (`sendChanges()`,
  `fetchChanges()`), der aus einer Funktion heraus erfolgen könnte, die auch von innerhalb eines
  `CKSyncEngineDelegate`-Callbacks aufgerufen wird, immer `Task.detached` statt eines einfachen
  `Task {}` verwenden — unabhängig davon, ob der jeweilige Aufrufpfad beim Schreiben des Codes
  gerade harmlos aussieht, da CKSyncEngines Reentrancy-Prüfung nicht zwischen "aktuell sicherem"
  und "später unsicher werdendem" Aufrufkontext unterscheidet.
- **GRDBs `.alter(table:) { $0.add(column:...).defaults(sql: "CURRENT_TIMESTAMP") }` scheitert
  auf einer nicht-leeren Tabelle:** Bei iCloud Sync Phase 2a (2026-07-24, Task 1: Migration
  v22, `updatedAt` auf `rule_conditions`/`smart_folder_conditions`) hätte der ursprünglich vom
  Implementierungsplan wörtlich vorgeschlagene Migrationscode
  (`.defaults(sql: "CURRENT_TIMESTAMP")`) bei JEDEM Bestandsnutzer mit vorhandenen Regeln oder
  Intelligenten Ordnern einen Migrations-Crash beim nächsten App-Start ausgelöst — SQLite lehnt
  `ALTER TABLE ... ADD COLUMN` mit einem Nicht-Konstanten-Default ab (`CURRENT_TIMESTAMP` ist
  ein Funktionsaufruf, kein echtes SQL-Literal) mit `"Cannot add a column with non-constant
  default"`, sobald die Tabelle bereits Zeilen enthält (auf einer leeren Tabelle funktioniert
  es unauffällig, was den Fehler in einem frischen Test-Setup leicht übersehen lässt). Per
  direktem `sqlite3`-CLI-Test verifiziert, noch vor dem eigentlichen Task-Review vom
  Implementierer selbst gefunden und behoben (dieselbe Falle wäre in Task 2, Migration v23,
  `feeds.configUpdatedAt`, identisch aufgetreten und wurde dort gleich mitgefixt). Fix:
  `.defaults(to: Date())` statt `.defaults(sql: "CURRENT_TIMESTAMP")` — erzeugt ein echtes,
  einmalig zum Migrationszeitpunkt berechnetes SQL-Literal, backfillt damit gleichzeitig alle
  Bestandszeilen korrekt mit "jetzt". **Lehre:** Bei JEDER künftigen `ALTER TABLE ADD COLUMN`-
  Migration mit einem Datums-/Zeitstempel-Default IMMER `.defaults(to: <Swift-Wert>)`
  verwenden, nie `.defaults(sql: "CURRENT_TIMESTAMP")` — und einen neuen Migrationstest
  IMMER gegen eine Tabelle mit mindestens einer vorab eingefügten Bestandszeile schreiben
  (nicht nur gegen eine leere Tabelle), da der Fehler sonst unbemerkt bleibt.
- **`NSBackgroundActivityScheduler` (Foundation) kennt kein `earliestBeginDate` —
  anders als `BGTaskRequest` aus dem hier bewusst nicht genutzten, iOS-fokussierten
  `BackgroundTasks`-Framework:** Nutzer-Report (2026-07-23): der Feed-Fehler-Alert
  „Eine Aktualisierung läuft bereits" erschien bei praktisch jedem App-Start, auch
  bei komplett frischem Kaltstart. Root-Cause per systematic-debugging: `Background
  RefreshService.scheduleNextRefresh(...)` berechnete korrekt eine
  `earliestBeginDate = jetzt + intervalMinutes` und reichte sie über
  `BackgroundRefreshRequest` weiter — der ursprüngliche erste Fix-Versuch setzte
  diesen Wert dann per `scheduler.earliestBeginDate = request.earliestBeginDate` auf
  den echten `NSBackgroundActivityScheduler`, was **nicht kompiliert**
  (`NSBackgroundActivityScheduler` hat dieses Property schlicht nicht — verifiziert
  per `NSBackgroundActivityScheduler.h`-Header direkt aus dem SDK). Der eigene
  Apple-Doc-Kommentar der Klasse beschreibt für den ersten Tick nur "run by the OS
  at a time that best accommodates system-wide factors" ohne untere Zeitschranke —
  in der Praxis feuerte dieser erste Tick teils fast sofort nach `schedule(...)`
  und kollidierte dadurch mit dem separaten, ebenfalls beim App-Start laufenden
  "Feeds beim App-Start aktualisieren"-Refresh (`ContentView.
  refreshFeedsOnLaunchIfNeeded()`) — beide riefen dieselbe `FeedViewModel.
  refreshAllFeeds(sqliteDatabase:)` auf einem geteilten `FeedViewModel` auf, dessen
  einfache `isLoading`-Sperre den zweiten, praktisch zeitgleichen Aufruf mit der
  nutzersichtbaren Fehlermeldung quittierte. **Tatsächlicher Fix** (Commit
  `cb60943`): die bereits berechnete `earliestBeginDate` selbst im Scheduler-
  Callback durchsetzen (`BackgroundRefreshService.isPrematureTick(earliestBeginDate:
  now:)`, eine bewusst ausgelagerte, pure und direkt unit-testbare Entscheidung) —
  ein zu früher Tick schließt sofort ohne Refresh ab, der nächste natürliche Tick
  (nach `interval`) übernimmt. Als zweite, unabhängige Absicherung unterscheidet
  `FeedViewModel.refreshAllFeeds(sqliteDatabase:isAutomatic:)` jetzt automatische
  von nutzerausgelösten Aufrufen — kollidiert ein automatischer Aufruf trotzdem mit
  einem laufenden Refresh, tritt er still zurück statt eine Fehlermeldung zu
  setzen; manuelle Aufrufe (Menü, Menubar-Button) zeigen sie weiterhin. **Lehre:**
  Bei JEDER künftigen Verwechslungsgefahr zwischen `NSBackgroundActivityScheduler`
  (macOS, Foundation, XPC-Activity-API) und `BGTaskScheduler`/`BGTaskRequest`
  (iOS-fokussiertes `BackgroundTasks`-Framework, das dieses Projekt bewusst nicht
  nutzt) die tatsächliche Property-Liste direkt im SDK-Header verifizieren
  (`NSBackgroundActivityScheduler.h`), nicht aus API-Ähnlichkeit zu `BGTaskRequest`
  raten — ein Compile-Fehler deckte das hier sofort auf, aber die zugrunde
  liegende Fehlannahme hätte auch subtiler (falscher Property-Name, der zufällig
  existiert) unentdeckt bleiben können.
- **`WKWebView.printOperation(with:)` stürzt auf macOS zuverlässig ab — niemals für
  echtes Drucken verwenden, stattdessen `createPDF(...)` + PDFKit:** Beim Live-Test von
  Feature 25.1 (Artikel drucken, 2026-07-17) zeigte der Drucken-Button zunächst den
  System-Alert „Diese App unterstützt Drucken nicht" (in beiden Reader-Ansichten, nativ
  und Web). Root-Cause-Kette per systematic-debugging über mehrere Runden aufgelöst:
  (1) Fehlendes Entitlement `com.apple.security.print` — App Sandbox
  (`com.apple.security.app-sandbox`) blockiert jeden Druckversuch systemweit ohne dieses
  Entitlement und zeigt dafür genau diesen generischen Alert, unabhängig vom
  Druck-Code. Nach Ergänzen des Entitlements in `Feedivo.entitlements` änderte sich das
  Verhalten zu einem echten Absturz. (2) Per `lldb`-Backtrace zweifelsfrei verifiziert
  (`bt all` nach manuellem Reproduzieren, da kein computer-use für native macOS-Apps
  verfügbar ist): `webView.printOperation(with:).run()`/`.runModal(for:...)` stürzt in
  AppKits eigener Seitenaufteilungs-Validierung ab
  (`-[NSConcretePrintOperation(NSInternal) _validatePagination]` →
  `AppKitBreakInDebugger`, Fehlermeldung „The NSPrintOperation view's frame was not
  initialized properly before knowsPageRange: returned") — ein seit 2017 bekanntes,
  bis heute ungelöstes WKWebView/AppKit-Race (WebKit muss die Seitenaufteilung
  asynchron mit dem Web-Content-Prozess abstimmen, AppKits Druckpanel fragt sie aber
  synchron ab). Reproduzierbar identisch unabhängig von WKWebView-Instanz (offscreen
  vs. sichtbar/im Fenster), Fenster-Zuordnung und `NSPrintInfo.shared` vs. frisch
  konstruiert — alle diese Fixversuche änderten nichts. (3) Versuch, stattdessen
  `printDocument:` über die Standard-Responder-Chain durchzureichen (Vorbild:
  NetNewsWire, das laut `gh api`-Code-Suche über den gesamten Quellbaum keine einzige
  Zeile eigenen Druck-Codes hat) scheiterte hart:
  `NSInvalidArgumentException: -[WKWebView printDocument:]: unrecognized selector` —
  `WKWebView` implementiert diesen Selector auf macOS schlicht nicht (NetNewsWires
  Ansatz funktioniert nur, weil dessen Artikelansicht selbst *immer* eine WKWebView
  ist und irgendein anderer, nicht direkt sichtbarer Mechanismus dort greift, nicht
  weil `printDocument:` universal auf jeder WKWebView beantwortet würde). **Tatsächlicher
  Fix:** `WKWebView.createPDF(configuration: WKPDFConfiguration())` (Apples separate,
  asynchrone PDF-Export-API, seit macOS 11, umgeht die kaputte Print-Operation-Integration
  komplett) erzeugt zuverlässig echte PDF-`Data`; ein gewöhnlicher, altbewährter
  PDFKit-Druckvorgang (`PDFDocument(data:)` → `PDFView` → `NSPrintOperation(view:
  pdfView)` → `.runModal(for:...)`) zeigt dafür den Druckdialog — komplett unabhängig
  von WKWebViews eigener Druck-Integration. Vom Nutzer live in beiden Ansichten
  bestätigt funktionierend. Siehe `Feedivo/Views/Reader/SQLiteReaderView.swift`
  (`printCurrentArticle()`, `presentPrintDialog(forPDFData:)`, `ArticlePrintCoordinator`).
  **Lehre:** Bei JEDEM künftigen Feature, das `NSPrintOperation` in Kombination mit
  `WKWebView` verwenden will, direkt mit `createPDF(...)` + PDFKit starten — der
  naheliegende, von Apples eigener API (`webView.printOperation(with:)`) suggerierte
  direkte Weg ist auf macOS nicht zuverlässig nutzbar, unabhängig vom sonstigen
  Code drumherum.
  **Nachtrag (2026-07-17, drei weitere Live-Bug-Funde direkt im Anschluss):**
  (1) `WKPDFConfiguration()` erfasst standardmäßig (`rect == nil`) nur den aktuell
  *sichtbaren* Ausschnitt der WebView, nicht das gesamte scrollbare Dokument — Artikel
  wurden dadurch nach der ersten Bildschirmseite abgeschnitten. `rect` muss explizit
  gesetzt werden, `document.documentElement.scrollHeight` (per `evaluateJavaScript`)
  liefert die echte Inhaltshöhe. (2) Ein einzelner, auf die volle Inhaltshöhe
  vergrößerter `rect` behebt zwar das Abschneiden, erzeugt aber nur EINE überlange
  PDF-Seite — `createPDF(...)` paginiert nicht automatisch in mehrere Standard-Seiten.
  Eine solche Einzelseite beim Drucken auf ein normales Blatt herunterzuskalieren
  (`scalingMode: .pageScaleToFit` mit `PDFDocument.printOperation(for:)`, das dafür
  eigentlich korrekt vorgesehene PDFKit-API statt `NSPrintOperation(view: pdfView)`,
  das ebenfalls nur "Seite 1" gedruckt hätte) macht den Text bei längeren Artikeln
  praktisch unlesbar klein — echte Mehrseiten-Paginierung muss selbst gebaut werden:
  Inhalt in seitenhohe Abschnitte zerlegen, jeden Abschnitt einzeln per `createPDF(...)`
  erfassen, zu einem mehrseitigen `PDFDocument` zusammenfügen (`generatePDF`/
  `appendPage` in `SQLiteReaderView.swift`) — dabei JEDE Seite (auch die letzte) mit
  derselben vollen Seitenhöhe rechnen, eine kürzere letzte Seite hätte eine abweichende
  PDF-Seitengröße und dadurch eine falsch ausgerichtete letzte Druckseite zur Folge.
  (3) Der Artikeltitel erschien im nativen Modus doppelt: `ArticleExportService.text(
  for:options: .html)` wickelt seinen Body bereits in ein eigenes
  `<article>...</article>`, `ArticlePDFExportRenderer` baut außen selbst ein neues
  `<article>`-Element darum — dadurch verschachtelte `<article>`-Elemente, wodurch die
  bestehende `removingFirstH1()`-Regex (verankert auf Stringanfang) das Titel-`<h1>`
  nicht mehr fand. Fix: neue `removingOuterArticleWrapper(from:)` entfernt den inneren
  Wrapper vor der H1-Entfernung — ein alter Bug, der durch den vorherigen
  CGContext-Renderer nie sichtbar geworden war. **Zusätzlich verifiziert:** NetNewsWire
  (Design-Spec-Vorbild für dieses Feature) hat entgegen der ursprünglichen Annahme
  gar keinen Drucken-Menüpunkt (per `gh api`-Code-Suche im kompletten Quellbaum UND
  `Main.storyboard` bestätigt: null Treffer für „print") — kein tatsächliches Vorbild,
  die ursprüngliche Design-Spec-Behauptung dazu war schlicht falsch.
- **`json.dump()` auf die komplette `Localizable.xcstrings` anwenden formatiert die
  gesamte ~31000-Zeilen-Datei um, statt nur neue Einträge chirurgisch einzufügen:**
  Bei der Shortcuts-Erweiterung (2026-07-16, Task 2) nutzte das ursprüngliche
  Python-Skript `json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)`,
  um 9 neue Katalogeinträge zu ergänzen. Das Ergebnis: ein Diff über praktisch die
  gesamte Datei (~41000 geänderte Zeilen statt ~200), selbst entdeckt per
  Diff-Stat-Kontrolle VOR dem Reviewer-Dispatch (`git diff --stat` zeigte 20653
  Insertions/20527 Deletions für eine Datei, in der inhaltlich nur 9 Einträge
  hinzukamen). Root Cause: Pythons `json.dump` mit Standard-`separators` erzeugt
  `"key": value` (Leerzeichen nur nach dem Doppelpunkt), Xcodes eigenes
  String-Catalog-Format nutzt aber durchgängig `"key" : value` (Leerzeichen VOR
  UND nach dem Doppelpunkt) — zusätzlich sortierte `sort_keys=True` alle
  bestehenden Schlüssel alphabetisch neu um. Xcodes Formatierung ist mit Pythons
  `json`-Modul dabei grundsätzlich nicht byte-genau reproduzierbar (z. B. rendert
  Xcode ein leeres Objekt als `{\n\n    }` über drei Zeilen, `json.dump` immer als
  `{}` auf einer Zeile) — ein voller `json.load`/`json.dump`-Roundtrip der ganzen
  Datei kann deshalb NIE eine chirurgische Einfügung liefern, unabhängig von den
  gewählten Parametern. Fix: Datei per `git show <BASE>:...` auf den
  Ursprungszustand zurückgesetzt, die neuen Einträge dann als reiner Text-Block
  (mit exakt passendem `"key" : value`-Stil, per Hand bzw. per
  `json.dumps(value, ensure_ascii=False)` nur für die einzelnen String-Werte)
  direkt nach einem stabilen Textanker (`  "strings" : {`) eingefügt — Ergebnis:
  253 Insertions, 0 Deletions. **Lehre:** Bei JEDER künftigen Ergänzung von
  `Localizable.xcstrings` per Skript NIEMALS die gesamte Datei durch
  `json.load`/`json.dump` roundtripen — immer per reiner Text-Segment-Einfügung an
  einem eindeutigen, stabilen Anker arbeiten und per `git diff --stat` VOR dem
  Commit verifizieren, dass nur Insertions (keine oder kaum Deletions) entstehen.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` ist für das App-Target gesetzt
  — ein naives `Task.detached` um eine unveränderte synchrone Funktion
  entlastet NICHT den MainActor:** Beim finalen Whole-Branch-Review der
  Spotlight-Integration (Feature 9.3, 2026-07-16) wurde bemängelt, dass der
  Erst-Start-Backfill (`SpotlightIndexingService.ensureBackfillIfNeeded`)
  synchron auf dem MainActor lief und bei großen Artikel-Beständen den
  App-Start sichtbar blockieren konnte. Der naheliegende Fix-Vorschlag
  (`Task.detached { ... }` um den bestehenden synchronen Aufruf) hätte NICHT
  funktioniert: Da das App-Target `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
  setzt, bleiben unannotierte Funktionen implizit MainActor-isoliert — auch
  innerhalb eines `Task.detached`, sobald man mit `await` wieder in eine
  solche Funktion hineinspringt, springt die Ausführung zurück auf den
  MainActor und blockiert genau wie vorher. Tatsächlicher Fix (Commit
  `70a0cedae`): die Funktion selbst von `throws` auf `async throws`
  umgestellt und intern `FeedivoDatabase.readAsync(_:)` (GRDBs echte
  asynchrone Lese-API, dispatcht auf GRDBs eigene Hintergrund-Queue,
  unabhängig von Swift-Aktor-Isolation) statt des synchronen `database.read`
  verwendet — für BEIDE DB-Zugriffe (ID-Liste UND Pro-Chunk-Snapshot-Fetch).
  Aufrufer feuert die Funktion seither über ein einfaches `Task { }` ab,
  ohne auf den Abschluss zu warten. **Lehre:** Bei JEDEM Versuch, eine
  Funktion "vom MainActor wegzubekommen", zuerst prüfen, ob die Funktion
  selbst noch synchron/unannotiert ist — reines Verpacken in `Task`/
  `Task.detached` reicht in diesem Projekt wegen des projektweiten
  Default-Isolation-Settings NICHT aus, wenn die Funktion später erneut
  `await`-basiert betreten wird; die Funktion muss echt `async` sein und
  intern eine echt asynchrone Primitive (`readAsync`, nicht `read`)
  verwenden. Bekannter Nebeneffekt dieser Umstellung: ein schmales,
  benignes TOCTOU-Race auf dem `hasBackfilled`-Flag bei zwei nahezu
  gleichzeitigen Aufrufen (z. B. App-Start + fast zeitgleicher
  Einstellungs-Toggle) — Worst Case ist eine harmlose doppelte, aber
  idempotente Re-Indexierung, kein Datenverlust. Bewusst nicht behoben
  (Whole-Branch-Re-Review als Minor eingestuft, kein Merge-Blocker).

- **Ohne eigenen `UNUserNotificationCenterDelegate` unterdrückt macOS
  Benachrichtigungs-Banner standardmäßig, solange die App im Vordergrund ist:**
  Beim Live-Test der Benachrichtigungs-Einstellungen (2026-07-16) meldete der
  Nutzer, dass weder echte Feed-Benachrichtigungen noch die neue
  Test-Benachrichtigung sichtbar erschienen — trotz erteilter macOS-Erlaubnis.
  Per TEMPDEBUG-`OSLog`-Diagnose in `FeedNotificationService.swift` verifiziert:
  `authorizationStatus()` lieferte korrekt `.authorized`, und
  `UNUserNotificationCenter.add(request)` schlug NIE fehl — die Zustellung an
  das System gelang also vollständig fehlerfrei. Root Cause: Feedivo hatte gar
  keinen `UNUserNotificationCenterDelegate` gesetzt. Ohne einen registrierten
  Delegate mit `willPresent(...)`-Implementierung entscheidet macOS
  eigenständig, ob eine erfolgreich zugestellte Notification als Banner
  angezeigt wird — und unterdrückt sie standardmäßig, solange die anfragende
  App selbst gerade im Vordergrund/aktiv ist (ein reiner Vordergrund-Effekt,
  kein Fehler und kein Berechtigungsproblem). Da der Test-Button naturgemäß nur
  bei aktiver App geklickt werden kann, schlug er dadurch *immer* fehl, obwohl
  der komplette Code-Pfad korrekt war. Fix (Commit `abda1f6`):
  `FeedivoAppDelegate` konformiert jetzt zusätzlich zu
  `UNUserNotificationCenterDelegate`, setzt sich in
  `applicationDidFinishLaunching` als `UNUserNotificationCenter.current().delegate`
  und implementiert `willPresent(...)` mit `completionHandler([.banner, .sound,
  .list])`. **Lehre:** Bei JEDER Diagnose von "Notification wird nicht
  zugestellt" zuerst per Logging verifizieren, ob `add(request)` tatsächlich
  einen Fehler wirft — wirft es keinen, liegt das Problem nicht in der
  Zustell-Pipeline, sondern typischerweise im fehlenden
  `UNUserNotificationCenterDelegate`/`willPresent`, insbesondere wenn der
  Test/Trigger nur bei aktiver App ausgelöst werden kann.
- **`NSOutlineView`s automatische Drag-Erkennung funktioniert NIE mit gehostetem
  interaktivem SwiftUI-Zeileninhalt (Button/`.onTapGesture` in einer `NSHostingView`):**
  Bei der Sidebar-Migration auf `NSOutlineView` (ADR-008, `SidebarOutlineView.swift`,
  2026-07-15) deckte der erste echte Live-Test auf, dass Drag & Drop trotz korrekt
  implementiertem `pasteboardWriterForItem`/`validateDrop`/`acceptDrop` beim tatsächlichen
  Ziehen nie feuerte. Per Diagnose-Override von `NSOutlineView.mouseDown` +
  `/usr/bin/log show`-Auswertung (Achtung: `log` ist ein zsh-Builtin, IMMER `/usr/bin/log`
  explizit verwenden) zweifelsfrei verifiziert: SwiftUI übersetzt seine Gesten intern in
  eigene AppKit-Gesture-Recognizer, die `mouseDown` am Blattelement abfangen, BEVOR es je
  bei einem `mouseDown`-Override eines Vorfahren (auch der `NSOutlineView` selbst)
  ankommt. Genau deshalb verwendet NetNewsWire (unser architektonisches Vorbild für diese
  Migration) rein native `NSTableCellView`s ohne SwiftUI-Hosting — dort tritt das Problem
  gar nicht erst auf (per `gh api`-Fetch des echten NetNewsWire-Quellcodes verifiziert:
  `SidebarCell` ist purer `NSTableCellView` mit `NSTextField`/eigenen AppKit-Views). Fix:
  eigener `NSPanGestureRecognizer` pro Zeile (angehängt in `viewFor:item:`), der bei
  tatsächlicher Zugbewegung (State `.began`, unterschreitet einen einfachen Klick) manuell
  `beginDraggingSession` auslöst — läuft parallel zu SwiftUIs eigenen Recognizern, da
  AppKit-Gesture-Recognizer sich nicht gegenseitig blockieren, sofern keine explizite
  Exklusivität gesetzt ist. Weitere in derselben Live-Diagnose gefundene Bugs: (1)
  `NSDraggingItem.setDraggingFrame` muss Outline-View-globale statt zeilen-lokale
  Koordinaten nutzen (`cellView.convert(bounds, to: outlineView)`), sonst erscheint das
  Vorschaubild am falschen Ort; (2) eine Zeilenhöhe von 24pt war als Drop-Zone zu
  klein/unzuverlässig treffbar, 30pt behebt es; (3) native AppKit-Drop-Hervorhebung wird
  von gehostetem SwiftUI-Zeileninhalt optisch überdeckt — braucht eine eigene
  SwiftUI-Drop-Hervorhebung (State im Coordinator + gezieltes Neurendern nur der
  betroffenen Zeile statt vollem `reloadData()`). **Lehre:** Bei JEDER künftigen
  `NSOutlineView`/AppKit-Bridge in diesem Projekt, die gehosteten interaktiven
  SwiftUI-Inhalt verwendet, sofort den `NSPanGestureRecognizer`-Workaround einplanen,
  nicht erst bei "Drag geht nicht" neu entdecken.
- **Neues App-Icon zeigt nach dem Rebuild noch das alte an (macOS-Icon-Cache,
  kein Build-Fehler):** Nach Ersetzen der PNGs in
  `Feedivo/Assets.xcassets/AppIcon.appiconset/` zeigten Dock/Finder trotz
  `BUILD SUCCEEDED` und korrekt konfiguriertem `CFBundleIconFile`/
  `CFBundleIconName`/`ASSETCATALOG_COMPILER_APPICON_NAME` weiterhin das alte
  Icon (gefunden 2026-07-13, keine laufende Alt-Instanz als Ursache). `killall
  Dock`/`killall Finder` allein reichte nicht — erst ein tieferer Reset des
  systemweiten IconServices-Caches behob es:
  `sudo rm -rf /Library/Caches/com.apple.iconservices.store` plus Löschen von
  `com.apple.dock.iconcache`/`com.apple.iconservices` unter
  `/private/var/folders/`, danach `killall Dock`/`Finder`/`SystemUIServer`.
  Erfordert `sudo` (Passwort-Prompt) — vom Nutzer selbst auszuführen, nicht
  automatisierbar. Falls das immer noch nicht reicht: Ab-/Anmelden oder
  Neustart, da IconServices auf aktuellem macOS den Cache teils erst dann
  vollständig verwirft.
- **SourceKit-Diagnosen sind oft falsch:** Nach praktisch jedem Edit zeigt die IDE/das
  Diagnose-System teils dutzende Fehler wie "Cannot find type X in scope" oder "No such module
  'GRDB'/'Testing'". Das sind in aller Regel veraltete/gecachte SourceKit-Zustände, KEINE echten
  Fehler. Verlässlich ist ausschließlich ein echter `xcodebuild build`-Lauf.
- **Volle Testsuite hängt:** Ein unscoped `xcodebuild test` über alle Testdateien hängt/deadlockt
  reproduzierbar (bekanntes, ungelöstes Infrastrukturproblem). Immer gezielt mit
  `-only-testing:FeedivoTests/<SuiteName>` testen.
- **Bekannte, dauerhaft vorbestehende Testfehlschläge** (nicht neu einführen, aber auch nicht
  grundlos als eigenen Bug behandeln): 17 Tests in `FeedivoAppSceneConfigurationTests.swift`
  (Zahl am 2026-07-23 korrigiert — vorher hier „15" dokumentiert, Stand 2026-07-14. Beim
  Offline-Feature-Entfernen-Plan fanden zwei unabhängige Untersuchungen im selben
  Subagent-Driven-Development-Durchgang — der Task-4-Implementer per `git stash`/`git stash
  pop` gegen den Basis-Commit vor dem Task, und der Task-4-Reviewer erneut per isoliertem
  `git worktree add` auf demselben Basis-Commit — exakt dieselben 17, byte-identischen
  Testnamen bereits VOR diesem Feature fehlschlagend. Reine Dokumentations-Drift seit
  2026-07-14, vermutlich durch dazwischenliegende Feature-Durchgänge angewachsen — keine
  Regression durch das Offline-Feature-Entfernen selbst, das die beiden einzigen Tests, die
  es an dieser Suite änderte, sauber zum Bestehen brachte), 2 flaky-unter-Last Tests in
  `FeedViewModelTests.swift` (`refreshAllFeedsMitSQLiteDatabaseNutztSQLiteFirstOhneDoppeltenAbruf`,
  `refreshAllFeedsMitSQLiteDatabaseMeldetFeedBenachrichtigungen`), sowie ein dritter,
  unabhängig davon flaky-unter-Last Test `listStateToggeltReadUndAktualisiertRows` in
  `SQLiteFeedArticleListStateTests.swift` (gefunden während iCloud Sync Phase 2b Task 8,
  2026-07-25 — per `git stash`-Baseline-Vergleich sowohl vom Implementierer als auch vom
  Task-Reviewer unabhängig als bereits vor diesem Feature bestehend verifiziert, keine
  Regression durch die Artikelstatus-Sync-Löschpropagierung).
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
- **Ein macOS-`.sheet` ohne expliziten `.frame(minWidth:minHeight:)` kann bei asynchron
  geladenem Inhalt (z. B. `List` + `.task { lädt @State }`) komplett leer erscheinen, obwohl
  die Daten korrekt geladen werden:** Beim Live-Test von iCloud Sync Phase 3
  (`SyncConflictResolutionView`, 2026-07-26) meldete der Nutzer, dass das „Sync-Konflikte"-
  Sheet trotz nachweislich vorhandener Zeilen in `pending_sync_conflicts` (per direktem
  `sqlite3`-Read bestätigt) komplett leer blieb — nur Titel + „Fertig"-Button, keine einzige
  Konfliktzeile, reproduzierbar über mehrere Versuche. Per systematic-debugging (Live-
  Reproduktion mit synthetisch per `sqlite3` eingefügter Testzeile statt echtem CloudKit-
  Konflikt, computer-use-Screenshot des tatsächlich winzigen Sheets) verifiziert: macOS
  berechnet die Sheet-Fenstergröße einmalig anhand des allerersten Layout-Durchlaufs — der
  findet statt, BEVOR das asynchrone `.task` `conflicts` befüllt (Startzustand: leeres
  Array). Ohne eigenen `.frame`-Modifier ergibt das eine winzige/leere Idealgröße, die auch
  nach dem Befüllen der Liste NICHT automatisch nachwächst — die Zeilen existieren technisch
  in der View-Hierarchie, sind aber innerhalb des eingefrorenen kleinen Sheet-Fensters nicht
  sichtbar. `CloudSyncFirstActivationView` (dieselbe Sheet-Präsentationsstelle in
  `SyncSettingsView`) hatte dieses Problem bereits erkannt und trägt deshalb
  `.frame(minWidth: 420, minHeight: 300)` — `SyncConflictResolutionView` hatte diesen Frame
  schlicht vergessen. Fix: denselben `.frame(minWidth: 420, minHeight: 300)` ergänzt, dazu
  ein `isLoading`-State (Default `true`) mit `ProgressView`, damit die Sheet-Größe von Anfang
  an stabil ist und der Nutzer „lädt noch" von „0 Konflikte" unterscheiden kann. Live erneut
  gegen eine synthetische Testzeile verifiziert (inkl. „Dieses Gerät"/„Anderes Gerät"-Buttons,
  die den Server-Wert korrekt in die Tabelle schreiben) — Fix bestätigt. **Lehre:** Bei JEDEM
  künftigen `.sheet`, dessen Inhalt asynchron/verzögert befüllt wird (nicht sofort beim ersten
  Layout vorhanden), IMMER einen expliziten `.frame(minWidth:minHeight:)` setzen — unabhängig
  davon, ob der Inhalt eine `List`, ein `VStack` oder sonstiges ist. Ein fehlender Frame äußert
  sich NICHT als Absturz oder Fehlermeldung, sondern als scheinbar leerer/winziger Sheet-Inhalt
  trotz korrekt geladener Daten — schwer von einem echten Daten-/Query-Bug zu unterscheiden,
  ohne die Fenstergröße selbst zu inspizieren.
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
- **Der automatische Stub-Mechanismus (siehe Gotcha oben) greift NICHT bei neuen `L10n.swift`-
  Konstanten, die nur indirekt referenziert werden:** Wird ein neuer `L10n`-Key (z. B.
  `L10n.settingsAutomaticCleanupLastRun = LocalizedStringKey("settings.automaticCleanup.lastRun")`)
  angelegt und ausschließlich über die Konstante verwendet (`Text(L10n.settingsAutomaticCleanupLastRun)`
  statt eines direkten String-Literals in `Text("...")`), erkennt Xcodes String-Catalog-
  Extraktor den Key beim Build NICHT und legt auch keinen leeren Stub in
  `Localizable.xcstrings` an — im Gegensatz zu einem direkten Literal bleibt der Key dort
  komplett unsichtbar, `xcodebuild build` meldet trotzdem anstandslos `BUILD SUCCEEDED`
  (gefunden im Whole-Branch-Review des Bereinigungsstatus-Features, 2026-07-14: 7 neue
  `L10n`-Keys für einen neuen Settings-Status-Block wurden in `L10n.swift` angelegt, aber erst
  im finalen Review als im Katalog fehlend entdeckt — zur Laufzeit hätten sie als rohe
  Punkt-Keys wie `settings.automaticCleanup.lastRun` gerendert). Fix ex post: Katalogeinträge
  manuell per Python-Skript (`json.load`/`json.dump`, exaktes bestehendes Format beibehalten)
  ergänzt. **Lehre:** Bei jedem neuen `L10n.swift`-Key, der nicht 1:1 einem bereits
  vorhandenen, wortgleichen String-Literal entspricht, sofort danach `grep -c "<der neue
  Punkt-Key>" Feedivo/Resources/Localizable.xcstrings` prüfen (muss > 0 sein) — nicht auf den
  Build-Erfolg verlassen, der diese Lücke nicht aufdeckt.
- **`periphery` (Dead-Code-Scanner) hat in diesem Projekt eine hohe Fehlalarmquote bei
  GRDB-Record-Typen:** Wird ein Typ ausschließlich über generische, aus Protokoll-Extensions
  geerbte GRDB-Methoden erreicht (`ArticleCountsRow.fetchOne(db, sql:)` u. ä.), erkennt periphery die Nutzung nicht und meldet
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
- **Bei erneut zugestelltem Artikel ist `arrivedAt` das frische Jetzt, nicht das
  ursprüngliche Erstsichtungsdatum:** `ArticleStore.upsert()` erhält bei jedem Feed-Refresh
  ein neues `ArticleUpsertInput` mit `arrivedAt: refreshedAt`/`now()` (siehe
  `SQLiteFeedRefreshService.swift`/`SQLiteFeedSubscriptionService.swift`) — auch für einen
  Artikel, der schon lange bekannt ist und nur erneut vom Feed geliefert wird. Ein Fallback
  wie `input.publishedAt ?? input.arrivedAt` liefert für publishedAt-lose Artikel deshalb
  praktisch immer "jetzt", NIE ein altes Datum. Beim Bereinigung-dauerhaft-Feature
  (2026-07-14) übernahm der Implementierungsplan genau diesen Fallback wörtlich aus der
  Design-Spec-Pseudocode für die neue Wiedereinfüge-Sperre (`ArticleStore.swift:415`) — dadurch
  entkamen publishedAt-lose, bereits bereinigte Artikel der Sperre und wurden trotz gesetztem
  `wasRemovedByRetention`-Flag sofort wieder eingefügt. Im finalen Whole-Branch-Review gefunden,
  Fix (Commit `88db711`): `history.firstSeenAt` (das beim allerersten Sehen einmalig gesetzte,
  seither stabile Datum aus `article_identity_history`) statt `input.arrivedAt` als Fallback —
  konsistent zur `effectiveDate`-Semantik der periodischen Bereinigung selbst
  (`SQLiteArticleRetentionCandidate` in `ArticleRetentionCleanupService.swift`). **Lehre:** Bei
  jeder neuen Logik, die ein "wie alt ist dieser Artikel wirklich"-Datum aus einem frischen
  `ArticleUpsertInput` ableiten will, `input.arrivedAt` nur für einen tatsächlich neuen Artikel
  verwenden — für einen wiederkehrenden/erneut zugestellten Artikel muss stattdessen ein
  gespeichertes, set-once-Datum (`history.firstSeenAt`, `status.dateArrived`) herangezogen
  werden.
- **`SQLiteFeedArticleListView.articleContent` hatte zwei unabhängige, widersprüchliche
  "Liste ist leer"-Prüfungen — nur eine davon war sticky-row-bewusst:** Die äußere
  `switch state.loadState`-Weiche prüfte `case .loaded where state.rows.isEmpty` — die
  ROHEN SQL-Zeilen, OHNE `stickyRowSnapshots` zu berücksichtigen. `articleList` selbst
  prüft dagegen korrekt `displayState.filteredRows.isEmpty` (sticky-bewusst). Solange in
  einem Smart Folder wie "Ungelesen" (SQL-Bedingung "Status ist ungelesen") noch mehrere
  ungelesene Artikel übrig waren, blieb `state.rows` nach dem Lesen eines einzelnen
  Artikels nicht leer, sodass die äußere Weiche nie griff und der korrekte,
  sticky-bewusste `articleList`-Pfad gerendert wurde. Wurde aber der LETZTE
  verbleibende ungelesene Artikel gelesen, wurde `state.rows` tatsächlich leer, obwohl
  `stickyRowSnapshots` den Artikel noch hielt — die äußere Weiche griff dadurch zuerst
  und zeigte einen komplett anderen, generischen "Keine Artikel"-Platzhalter
  (`emptyTitle`/`emptyDescription`, eigene L10n-Keys), unter vollständiger Umgehung des
  korrekten Pfads (Nutzer-Report 2026-07-14, gefunden nach fehlgeschlagener rein
  logik-basierter Reproduktion per Live-`OSLog`-Diagnose + `log show`). Fix: Weiche auf
  `case .loaded where effectiveRows.isEmpty` umgestellt (Commit `18da80d`). **Lehre:**
  Bei mehreren Stellen, die "ist die Liste leer?" unabhängig voneinander beantworten,
  IMMER dieselbe (sticky-/filter-bewusste) Quelle nutzen — ein Konsistenz-Check per Grep
  auf alle `.isEmpty`-Vorkommen im selben View lohnt sich bei ähnlichen Bugs.
- **Rein logik-/State-Ebene-Tests können einen View-Rendering-Bug übersehen, der eine
  Ebene höher liegt:** Zwei gezielte Reproduktionstests (Fixture-Ebene und echte
  asynchrone DB-Ebene) für genau das "letzter Artikel"-Szenario bestanden anstandslos,
  obwohl der Bug real war — weil sie nur `SQLiteArticleListDisplayState`/`effectiveRows`
  testeten, nicht die `articleContent`-Weiche, die diese Daten in bestimmten Fällen gar
  nicht erst konsultierte. Bei einem "Daten sehen korrekt aus, aber UI zeigt trotzdem
  falsch"-Verdacht: gezielt nach *mehreren* unabhängigen Entscheidungspunkten für
  dieselbe Frage suchen (Grep auf `.isEmpty`/ähnliche Bedingungen im selben View), nicht
  nur die naheliegendste Stelle prüfen.
- **ÜBERHOLT/korrigiert (2026-08-15): `FeedStore.sidebarFeeds()`/`unreadCount`-Testlücke ist
  längst behoben, nicht mehr aktuell.** Dieser Eintrag behauptete ursprünglich (2026-07-14),
  `sidebarSnapshotsAreSortedByTitle` und `sidebarSnapshotsCanHideReadFeeds` in
  `SQLiteFeedStoreTests.swift` würden fehlschlagen, weil sie `FeedRecord.unreadCount` direkt
  setzen, ohne passende `articles`/`article_statuses`-Zeilen einzufügen. Beim Task-7-Abschluss
  der iCloud-Sync-Settings-DB-Spiegelung (2026-08-15) per direktem Blick in die aktuelle
  Testdatei UND per echtem Testlauf verifiziert: beide Tests sind heute grün — sie nutzen
  inzwischen einen `seedUnreadArticles(database:feedID:count:)`-Helfer (Datei-Zeile 5), der
  echte `article_statuses`-Zeilen anlegt, statt nur das `unreadCount`-Feld direkt zu setzen.
  Wann genau der Fix passierte, ist aus dem aktuellen Code allein nicht ersichtlich (keine
  Git-Archäologie im Rahmen dieser Session betrieben) — reine Dokumentations-Korrektur, kein
  neuer Fix. **Lehre:** Auch als „bewusst nicht gefixt" dokumentierte Vorab-Fehlschläge
  können durch spätere, unabhängige Änderungen stillschweigend behoben werden — bei jedem
  Verdacht auf einen dokumentierten Altfehlschlag lohnt sich ein kurzer Blick in die
  aktuelle Testdatei, bevor man den Eintrag als weiterhin gültig übernimmt.
- **`UTType(exportedAs:)` braucht trotzdem einen `Info.plist`-Eintrag, auch bei rein
  appinterner `Transferable`-Nutzung:** Beim Feeds-Drag-&-Drop-Feature (2026-07-14) ging
  sowohl die ursprüngliche Design-Spec als auch — nach eigener "Korrektur" während der
  Plan-Erstellung — der Implementierungsplan davon aus, `UTType(exportedAs:)` genüge für
  rein prozessinternes Drag & Drop (Feed-/Ordner-Zeilen innerhalb derselben Sidebar) ganz
  ohne `UTExportedTypeDeclarations`-Eintrag, mit der Begründung, dieser sei nur für
  Interoperabilität mit anderen Apps/Finder/Spotlight nötig. Das ist falsch: macOS
  validiert beim tatsächlichen Drag-Betrieb trotzdem gegen die im `Info.plist`
  deklarierten `UTExportedTypeDeclarations` — ohne passenden Eintrag meldet das System
  zur Laufzeit `"Type ... was expected to be declared and exported in the Info.plist ...
  but it was not found."` (per Nutzer-Report entdeckt, NICHT durch die
  Subagent-Driven-Development-Reviews, da keiner der Reviewer die App tatsächlich
  gestartet und eine echte Drag-Geste ausgeführt hat — reiner Build+Test-Check deckt das
  nicht auf). Fix: zwei `UTExportedTypeDeclarations`-Einträge (`UTTypeIdentifier`,
  `UTTypeDescription`, `UTTypeConformsTo: ["public.data"]`) in `Feedivo/Info.plist`
  ergänzt, per `plutil -p` auf dem tatsächlich gebauten App-Bundle verifiziert (nicht nur
  auf `BUILD SUCCEEDED` verlassen — deckt sich mit dem bereits bestehenden Gotcha zu
  physischen `Info.plist`-Änderungen bei `CFBundleURLTypes`). **Lehre:** Bei jedem
  eigenen `UTType(exportedAs:)` IMMER einen passenden `Info.plist`-Eintrag ergänzen,
  unabhängig davon, ob Interoperabilität mit anderen Apps gebraucht wird — die Annahme
  "nur für Cross-App-Interop nötig" war ein reiner Trugschluss, nicht durch Apples
  Dokumentation gedeckt.
- **Kollisions-/Duplikaterkennung gegen eine Menge, die bereits synchronisierte, mit dem
  lokalen Datensatz IDENTISCHE Einträge enthalten kann, muss Selbst-Treffer per ID
  ausschließen — sonst Datenverlust bei erneuter Sync-Aktivierung:** Der schwerwiegendste
  Fund des gesamten iCloud-Sync-Phase-3-Plans (Task-14-Review, 2026-07-26, siehe „Aktuell
  in Arbeit"): `CloudSyncFirstActivationAnalyzer.findCollisions` (Task 12) verglich lokale
  Tags/FeedFolders gegen bereits in CloudKit vorhandene Datensätze rein nach
  Groß-/Kleinschreibungs-unabhängigem Namen, ohne vorher Datensätze auszuschließen, deren
  lokale ID bereits exakt der `recordID.recordName` des passenden Cloud-Datensatzes
  entspricht. Schaltet ein Nutzer iCloud Sync AUS und dann wieder EIN (nachdem der erste
  Sync-Durchlauf längst gelaufen war), matchte dadurch JEDER bereits synchronisierte
  Tag/Ordner fälschlich als „Kollision" mit sich selbst. Da „Zusammenführen" in der neuen
  `CloudSyncFirstActivationView`-UI standardmäßig vorausgewählt ist, hätte ein Nutzer, der
  den Dialog einfach bestätigt, `CloudSyncFirstActivationMerger.mergeTag(X, X)` ausgelöst
  — den Tag/Ordner mit sich selbst zusammengeführt, was den lokalen Ausgangsdatensatz samt
  ALLER `article_tags`/`feed_tags`-Zuordnungen unwiederbringlich gelöscht hätte. **Weder
  Task 12s (Analyzer) noch Task 13s (Merger) eigener, isolierter Task-Review fand das** —
  beide Bausteine waren für sich genommen tatsächlich korrekt; der Fehler wurde erst
  sichtbar, als Task 14 beide in einen echten Re-Aktivierungs-Flow gegen ein lokales
  `TagStore`/`FeedFolderStore` verdrahtete, das bereits zuvor synchronisierte Zeilen
  enthielt — exakt das Szenario, das ein rein Fixture-basierter Unit-Test mit frischen,
  noch nie synchronisierten Test-IDs nicht abdeckt. Fix (Commit `1a01ca65`):
  `findCollisions` schließt jetzt Kandidaten aus, deren lokale ID bereits dem
  `recordID.recordName` des Cloud-Treffers entspricht, bevor der Namensvergleich
  überhaupt läuft. **Lehre:** Bei JEDER künftigen Duplikat-/Kollisionserkennung, die gegen
  eine Menge läuft, die bereits synchronisierte, dem lokalen Datensatz per ID
  entsprechende Einträge enthalten kann, IMMER zuerst nach ID ausschließen, nicht nur nach
  Inhalts-/Namens-Gleichheit vergleichen — und ein aufgeteilter Task-Review von Bausteinen,
  die erst gemeinsam in einem späteren Task verdrahtet werden, kann diese Klasse von
  Fehlern strukturell nicht sehen; ein finaler Whole-Branch-Review sollte solche
  Foundation-Bausteine (hier: die Tasks 12/13) gezielt noch einmal im Licht der später
  hinzugekommenen echten Verdrahtung neu prüfen, nicht nur erneut die bestehenden Tests
  laufen lassen. **Zweiter, unabhängiger CRITICAL-Fund derselben Review-Runde (Ordnungs-
  Lücke, kein Datenverlust, aber dieselbe Sicherheitsklasse):** `FeedivoApp.swift` rief
  `cloudSyncEngine.start()` bei jedem App-Start bedingungslos auf, sobald `isEnabled`
  bereits als `true` persistiert war — umging das komplette Erst-Aktivierungs-Gate, falls
  die App beendet wurde, während der Merge-Dialog noch offen war (`@AppStorage` setzt
  `isEnabled` sofort beim Umlegen des Schalters, noch bevor der Dialog abgeschlossen ist).
  Gefixt über ein neues, persistiertes `pendingFirstActivationKey`-Flag (gesetzt beim
  Erscheinen des Sheets, nur bei echtem Abschluss gelöscht), das eine neue
  `shouldAutoStartSyncEngineAtLaunch(...)`-Prüfung an beiden tatsächlichen
  `start()`-Aufrufstellen gated.

- **App Sandbox verbietet einem sandboxed Prozess kategorisch, `com.apple.quarantine`
  von einer selbst heruntergeladenen Datei zu entfernen — weder per `xattr`-Subprozess
  noch über die native API, unabhängig vom gewählten Weg:** Root-Cause-Fund einer
  Live-Debugging-Session (2026-07-31), der den alten Eigenbau-Update-Installer
  (`UpdateInstaller`/`UpdateAppSwapper` u. a., siehe ADR-009) strukturell unreparierbar
  machte und den Umstieg auf Sparkle auslöste: eine vom Eigenbau selbst heruntergeladene
  und entpackte neue App-Version trägt das vom Download vergebene
  `com.apple.quarantine`-Extended-Attribute — ohne dessen Entfernung verweigert
  Gatekeeper beim nächsten Start der geswapten App den Start mit einem
  "nicht verifizierter Entwickler"-artigen Dialog, unabhängig davon, dass die App
  korrekt signiert ist. Zwei naheliegende Entfernungswege wurden geprüft, **beide
  scheitern unter App Sandbox kategorisch, nicht nur gelegentlich:** (1) ein
  `Process`/`xattr -dr com.apple.quarantine <Pfad>`-Subprozessaufruf (App Sandbox
  erlaubt zwar das Starten des Subprozesses selbst, der Subprozess erbt aber keine
  erweiterten Rechte auf fremde Extended Attributes und scheitert mit einem
  Berechtigungsfehler), (2) die dafür vorgesehene native Cocoa-API
  `URLResourceValues.quarantineProperties` (dieselbe Sandbox-Beschränkung gilt
  identisch für die native API — kein reiner Subprozess-Artefakt). Verifiziert durch
  Reproduktion mit einem eigenen, minimalen, identisch signierten und identisch
  sandboxed Testprogramm, das ausschließlich diese eine Operation versucht — beide Wege
  schlagen dort isoliert und reproduzierbar fehl, ohne jede weitere Eigenbau-Logik als
  mögliche Fehlerquelle. **Lehre:** Ein selbst gebauter Update-Installer, der die eigene
  App unter App Sandbox in-place ersetzen will, ist kein lösbares Implementierungsproblem,
  sondern ein grundsätzlicher Plattform-Constraint — die einzige praktikable Lösung ist
  ein etabliertes Framework wie Sparkle, dessen `Autoupdate`-Hilfsprozess bewusst
  außerhalb der Sandbox der Haupt-App läuft (siehe ADR-009). Bei jedem künftigen
  „selbst gebauten Installer/Updater unter App Sandbox"-Vorhaben zuerst genau diese
  Quarantäne-Entfernung isoliert gegenprüfen, bevor Zeit in die übrige Installer-Logik
  investiert wird.

- **Ein im Implementierungsplan wörtlich vorgegebener Codeblock kann selbst einen echten
  Bug enthalten — „übernimm dieses Draft-Code unverändert" ersetzt nicht die eigene
  Korrektheitsprüfung:** Beim Sparkle-Umstieg (2026-07-31) fanden sich in genau zwei
  Tasks, deren Implementierung stellenweise wörtlich aus dem Plandokument übernommen
  werden sollte, je ein eigenständiger, plan-autorierter (nicht implementierer-
  verursachter) Bug, beide erst im jeweiligen Task-Review gefunden: (1) Task 7
  (`SparkleUpdateCoordinator`): die im Plan vorgegebene `installUpdate()`-Logik löste
  nur `pendingInstallChoice` auf (die von `showReadyToInstallAndRelaunch` gesetzte
  Continuation), niemals aber `pendingUpdateChoice` (die von `showUpdateFound` gesetzte,
  frühere Continuation) — ein Klick auf „Installieren" bei einem gerade gefundenen
  Update wäre dadurch ein stiller, dauerhafter No-Op mit einer geleakten
  Sparkle-Continuation gewesen, exakt die erste echte Interaktion, die ein Nutzer mit
  dem neuen Update-Flow hätte. Fix: `installUpdate()` löst jetzt das jeweils aktuell
  gesetzte der beiden Closures auf. (2) Task 11 (`scripts/create_github_release.sh`):
  die geplante Einfügestelle für den neuen Appcast-Signier-/Update-Code lag NACH der
  bereits bestehenden `rm -f "$NOTES_FILE"`-Zeile, obwohl der neue Code den Inhalt von
  `$NOTES_FILE` weiterhin braucht — jeder echte Release-Lauf wäre direkt nach dem
  bereits öffentlich sichtbaren, nicht mehr rückgängig zu machenden GitHub-Release-
  Schritt abgestürzt, noch bevor der Appcast überhaupt aktualisiert wurde. Fix: Notiz-
  Inhalt vor dem Löschen in eine Variable zwischenspeichern. **Lehre:** Eine
  Plan-Anweisung wie „übernimm diesen Codeblock unverändert" beschreibt nur die
  gewünschte Herkunft/den gewünschten Umfang des Codes, nicht dessen Korrektheit — der
  Draft-Code selbst muss beim Implementieren genauso unabhängig verifiziert werden wie
  selbst geschriebener Code, insbesondere bei Zustandsverwaltung (welche von mehreren
  Continuations/Variablen gerade „die aktuelle" ist) und bei Einfügereihenfolge relativ
  zu bestehenden, bereits ausgeführten Zeilen.

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
- [x] Background Refresh (`NSBackgroundActivityScheduler` statt `BGTaskScheduler`)
- [ ] **iCloud Sync via CloudKit** — Phase 1 (CKSyncEngine-Fundament, nur Tags), Phase 2a
      (Feeds/Ordner/Regeln+Bedingungen/benutzerdefinierte Intelligente Ordner), Phase 2b
      (Artikelstatus — Gelesen/Stern) und seit 2026-07-26 auch Phase 3 (Feld-Ebene-
      Konfliktauflösung + Erst-Aktivierungs-Merge-Dialog) sind auf `main` implementiert
      (automatisierte Tests grün, Release-Build grün), dazu eine Soft-/Hard-Reset-UI für
      den Sync-Zustand. Push-Richtung für Feed, Rule/RuleCondition,
      SmartFolder/SmartFolderCondition und ArticleStatus seit 2026-07-26 live gegen das
      echte CloudKit Dashboard bestätigt, ebenso die Löschpropagierung für
      Feed→ArticleStatus, Rule→RuleCondition und SmartFolder→SmartFolderCondition (siehe
      „Aktuell in Arbeit"); FeedFolder-Push, tatsächliche Reset-Ausführung und die
      Pull-Richtung app-weit weiterhin ausstehend. Phase 3s Feld-Ebene-Konfliktauflösung
      und Erst-Aktivierungs-Kollisionserkennung sind bislang ausschließlich durch
      automatisierte Tests (In-Memory-GRDB + gemockte `CKRecord`s) abgesichert, NICHT
      live gegen zwei echte Geräte bzw. einen echten CKContainer verifiziert. Phase 4
      (Härtung) steht als eigener, noch nicht begonnener Zyklus weiterhin aus —
      Checkbox bleibt deshalb offen

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
- Read-only MCP-Server (`FeedivoMCPServer`, 7 Tools) für Zugriff aus Claude Desktop/Claude Code
  auf die echten Feedivo-Daten, ins App-Bundle eingebettet, siehe ADR-011

---

## GitHub

- **Repo:** https://github.com/martinfelder/feedivo-mac (private)
- **Branch-Strategie:** `main` = stabil, direkt bearbeitet (kein durchgängiges Feature-Branch-
  Modell mehr in der aktuellen Praxis); vereinzelt längerlebige Branches für größere,
  eigenständige Vorhaben (z. B. `codex/sqlite-grdb-foundation`)
- **Push-Konvention:** Nie ohne explizite Nutzerbestätigung nach `origin/main` pushen
- **Versions-Bump/Changelog/Release-Konvention (seit Build 9, 2026-07-29):** Build-Nummer
  (`scripts/bump_version.sh`) und `CHANGELOG.md`-Eintrag werden NICHT mehr automatisch bei
  jedem Push aktualisiert (der frühere PostToolUse-Hook in `.claude/settings.json` wurde
  entfernt) — nur noch, wenn der Nutzer explizit einen Bump verlangt. So können mehrere
  Pushes/Änderungen unter derselben Build-Nummer gesammelt werden. Verlangt der Nutzer
  einen Bump, danach zusätzlich `scripts/create_github_release.sh` ausführen (baut Release-
  Konfiguration, veröffentlicht als GitHub Release) — dieses Skript markiert das Release
  seit demselben Datum IMMER als Pre-Release (`--prerelease`), nie als "Latest Release".

---

## Offene Entscheidungen

- **iCloud Sync:** Phase 1 (nur Tags), Phase 2a (Feeds/Ordner/Regeln/benutzerdefinierte
  Intelligente Ordner), Phase 2b (Artikelstatus — Gelesen/Stern, inkl. Löschpropagierung)
  und seit 2026-07-26 auch Phase 3 (Feld-Ebene-Konfliktauflösung + Erst-Aktivierungs-
  Merge-Dialog) sind implementiert (siehe „Aktuell in Arbeit"), dazu eine Soft-/Hard-
  Reset-UI für den Sync-Zustand. Push-Richtung für Feed, Rule/RuleCondition,
  SmartFolder/SmartFolderCondition und ArticleStatus seit 2026-07-26 live gegen das echte
  CloudKit Dashboard bestätigt, ebenso die Löschpropagierung für Feed→ArticleStatus,
  Rule→RuleCondition und SmartFolder→SmartFolderCondition. Offen: Phase 3s Feld-Ebene-
  Konfliktauflösung und Erst-Aktivierungs-Kollisionserkennung sind bislang NUR
  automatisiert getestet (In-Memory-GRDB + gemockte `CKRecord`s), nicht live gegen zwei
  echte Geräte bzw. einen echten CKContainer verifiziert — dafür bräuchte es entweder ein
  zweites Testgerät (ein echter, gleichzeitig auf beiden Seiten laufender Feld-Konflikt)
  oder ein CloudKit-Dashboard-seitig manuell angelegtes Namens-Duplikat
  (Erst-Aktivierungs-Kollisionserkennung). Phase 4 (Härtung) steht als eigener, noch
  nicht begonnener Zyklus weiterhin aus — wann wird das angegangen? Zusätzlich weiterhin
  offen für Phase 2a/2b: FeedFolder-Push separat verifizieren, tatsächliche Ausführung
  von Soft-/Hard-Reset, sowie die Pull-Richtung app-weit weiterhin ungetestet mangels
  Zweitgerät. Der alte, SwiftData-basierte Sync-Beta-Branch war bereits überholt und
  wurde am 2026-07-24 gelöscht.
- **Bewusste, dokumentierte Limitation aus Phase 3 (kein Bug, siehe „Aktuell in
  Arbeit"):** `RuleCondition`/`SmartFolderCondition`-Zeilen werden bei jedem Speichern
  der übergeordneten Rule/SmartFolder komplett gelöscht und neu eingefügt — kein Task im
  Phase-3-Plan verdrahtet `changedFields`-Tracking für diese Kind-Zeilen. Die in Task 3
  definierte `askFields`/`autoFields`-Policy für `RuleCondition`/`SmartFolderCondition`
  ist dadurch aktuell unerreichbarer Code — Bedingungszeilen fallen bei einem Konflikt
  weiterhin auf das alte, ganze-Zeile-Last-Write-Wins zurück statt auf Feld-Ebene zu
  mergen. Sicher (kein Datenverlust), nur weniger granular als bei
  Tag/FeedFolder/Feed/Rule/SmartFolder/ArticleStatus selbst. Müsste in einem eigenen
  Folge-Task (analog zu Tasks 9/10 für Rule/SmartFolder selbst) nachgezogen werden, falls
  Feld-Ebene-Genauigkeit auch für einzelne Bedingungszeilen gewünscht ist.
- **Bekanntes, bewusst noch nicht behobenes Risiko aus dem Phase-2a-Whole-Branch-Review:**
  `FeedFolderStore.materializeImplicitFolders()` kann bei Multi-Geräte-Pull doppelte,
  gleichnamige `feed_folders`-Zeilen erzeugen (frische Zufalls-UUID pro Gerät, nicht
  sync-eingereiht, kollidiert mit der ID-basierten Ordner-Synchronisierung aus Task 5).
  Betrifft nur Pull-Richtung, die ohnehin noch unverifiziert ist — muss vor/während der
  Pull-Verifikation oder in Phase 2b adressiert werden (Dedupe nach Name beim Anwenden
  eingehender Records, oder deterministische statt zufällige UUID-Ableitung). Details
  siehe „Aktuell in Arbeit" (Whole-Branch-Review-Eintrag).
- **Monetarisierung:** Kostenlos / einmaliger Kauf / nie im App Store? — weiterhin offen.
- **Share Extension:** Noch nicht begonnen, kein konkreter Zeitplan.
- **App Store vs. private Verteilung:** Weiterhin offen.

**Bereits gelöst (zur Referenz):**
- Artikel-Detail: sowohl nativer SwiftUI-Renderer als auch WKWebView (Originalartikel) —
  beide umgesetzt, nutzerseitig umschaltbar.
- Favicon-Strategie: eigene HTML-Discovery + Fallback-Heuristik, keine Google-S2-API.

---

## Aktuell in Arbeit

- **2026-08-15: iCloud-Sync-Settings-DB-Spiegelung (Cross-Process-Fix für MCP-Schreibzugriff)
  — Implementierung ABGESCHLOSSEN, automatisierte Verifikation grün, manuelle 4-Punkte-
  Live-Checkliste NOCH AUSSTEHEND.** Root Cause: `FeedivoMCPServer` ist ein separater,
  unsandboxed Prozess und sieht dadurch eine ANDERE `UserDefaults`-Domäne als die sandboxed
  App — `CloudSyncSettings.isEnabled()` liefert dort praktisch immer `false`, egal was der
  Nutzer in den App-Einstellungen tatsächlich eingeschaltet hat. Konkrete Folge: MCP-
  Schreibvorgänge (`update_article_status`, `assign_tag`, `remove_tag`, siehe MCP-Server-V2-
  Phase-1-Eintrag direkt darunter) landeten NIE in der lokalen iCloud-Sync-Warteschlange
  (`cloud_sync_pending_changes`), obwohl der Nutzer Sync in der App aktiv hatte — schlimmer
  noch: `statusSyncUpdatedAt` wurde bei jedem MCP-Schreibvorgang trotzdem aktualisiert,
  wodurch der Last-Write-Wins-Vergleich der Phase-3-Konfliktauflösung eine später
  eintreffende, echte Remote-Änderung für diesen Datensatz dauerhaft als „älter" verworfen
  hätte — ein stiller Datenverlust-Pfad, nicht nur eine fehlende Synchronisierung. Umgesetzt
  via Brainstorming→Spec→Plan→Subagent-Driven-Development (7 Tasks): Task 1 Migration
  `v33_create_cloud_sync_settings` + neuer `CloudSyncSettingsStore`
  (`Feedivo/Stores/CloudSyncSettingsStore.swift`, Single-Row-Tabelle, hart mit `0`
  initialisiert) + Target-Membership für `FeedivoMCPServer`; Task 2 verdrahtet die
  Spiegelung — `FeedivoApp.init` ruft `mirrorFromUserDefaults()` unbedingt auf (vor dem
  Start des `LocalExtensionBridgeServer`, der selbst schon Feeds anlegen kann),
  `SyncSettingsView.onChange` spiegelt zusätzlich jedes Umlegen des Schalters live, Fehler
  laufen über den bestehenden `logIfThrows`-Helfer. Tasks 3–6 stellen insgesamt **8 Gates**
  (nicht 7 wie ursprünglich in der Design-Spec angenommen — `FeedFolderStore` hat tatsächlich
  zwei unabhängige Gate-Stellen) von `CloudSyncSettings.isEnabled()` auf
  `CloudSyncSettingsStore.isEnabled(in: db)` um: `TagStore` (Task 3), `ArticleStatusStore` +
  `CloudSyncArticleStatusMapping` (Task 4), `FeedStore` + `FeedFolderStore` (Task 5),
  `SQLiteRuleStore` + `SQLiteSmartFolderStore` (Task 6) — dabei **15** (nicht 17)
  Testdateien von direktem `UserDefaults`-Zugriff auf
  `CloudSyncSettingsStore(database:).setEnabled(true)` migriert, die übrigen ursprünglich in
  der Spec genannten Kandidaten waren nachweislich unbetroffen. **Bewusst NICHT umgestellt**
  (laufen nur im App-Prozess, wo `UserDefaults` weiterhin die Quelle der Wahrheit bleibt):
  `FeedivoApp.swift:116` (`shouldAutoStartSyncEngineAtLaunch`-Aufruf) und
  `CloudSyncEngine.swift:179` (`isEnabled(in: userDefaults)`).
  **Drei Abweichungen von der ursprünglichen Design-Spec:**
  1. Die Gates lesen über die statische, nicht werfende `CloudSyncSettingsStore.
     isEnabled(in: db)` statt über die von der Spec vorgeschlagene Instanz-API — alle Gates
     laufen bereits innerhalb einer offenen `database.write`-Transaktion, in der GRDB einen
     erneuten Datenbankzugriff mit `GRDBPrecondition(currentReader == nil, "Database methods
     are not reentrant.")` verbietet (siehe neuer Gotcha oben). Der Spec-Vorschlag wäre in
     jedem Test sofort gecrasht.
  2. Der Backfill des bestehenden `UserDefaults`-Werts läuft beim App-Start
     (`FeedivoApp.init` → `mirrorFromUserDefaults()`) statt wie ursprünglich geplant in der
     Migration selbst (Nutzerentscheidung) — hält die Database-Schicht frei von
     `UserDefaults`-Wissen und macht `inMemoryForTests()` deterministisch.
  3. 15 statt 17 Testdateien, 8 statt 7 Gates (s. o.).
  Regressionslauf über alle 3 Task-7-Testbatches grün (61+59+72 = 192 Tests, inkl. der als
  flaky-unter-Last bekannten `SQLiteFeedArticleListStateTests`-Suite, die in diesem Lauf
  ohne jeden Fehlschlag durchlief), Release-Build für beide Schemes (`Feedivo` UND
  `FeedivoMCPServer`) grün. **Ausstehende manuelle Live-Verifikation (4 Punkte, braucht die
  echte Produktions-DB + Claude Desktop + CloudKit-Dashboard-Zugriff, nicht in dieser
  Umgebung automatisierbar):**
  1. iCloud Sync in den Einstellungen einschalten → `sqlite3` auf die Produktions-DB:
     `SELECT isEnabled FROM cloud_sync_settings;` muss `1` liefern; ausschalten → `0`.
  2. App **beenden**, MCP-Schreibzugriff aktiv, über Claude Desktop `update_article_status`
     auf einen Artikel → danach `SELECT COUNT(*) FROM cloud_sync_pending_changes WHERE
     recordType = 'ArticleStatus';` muss > 0 sein (vor diesem Fix: immer 0).
  3. App starten → CloudKit-Dashboard-„Logs"-Tab zeigt ein `RecordSave` mit
     `overallStatus: SUCCESS` für den Record-Typ `ArticleStatus`.
  4. Bestandsnutzer-/Selbstheilungs-Fall: Sync eingeschaltet lassen, App beenden,
     `UPDATE cloud_sync_settings SET isEnabled = 0;` von Hand setzen, App starten → Wert
     steht danach wieder auf `1`.
  Spec: `docs/superpowers/specs/2026-08/2026-08-15-cloud-sync-settings-db-spiegelung-
  design.md`, Plan: `docs/superpowers/plans/2026-08-15-cloud-sync-settings-db-
  spiegelung.md`. Commits `d114218a..a72af588` (Tasks 1–6) + ein Doku-Commit (Task 7) lokal
  auf `main`, NICHT gepusht (Nutzerbestätigung vor Push laut Projektkonvention ausstehend).

- **2026-08-14/15: MCP-Server V2 Phase 1 (Schreibzugriff-Fundament) — Implementierung
  ABGESCHLOSSEN, automatisierte Verifikation grün, manuelle 9-Punkte-Live-Checkliste
  NOCH AUSSTEHEND.** Erste Ausbaustufe nach dem read-only v1-Server (siehe Eintrag
  direkt darunter): `FeedivoMCPServer` bekommt einen zweiten, vom Hauptschalter
  unabhängigen Schalter „Schreibzugriff erlauben" (Migration v32,
  `mcp_server_settings.writeAccessIsEnabled`, Standard `false` — bewusst separates
  Opt-in mit größerer Vertrauensgrenze als reines Lesen) sowie drei neue Schreib-Tools
  (`update_article_status` — Gelesen/Stern/Versteckt setzen, `assign_tag`,
  `remove_tag`). Eine zweite, tatsächlich schreibende `DatabasePool`-Verbindung
  (`FeedivoMCPServerWritableDatabase`) wird nur geöffnet, wenn der Schreibzugriff-
  Schalter aktiv ist — `main.swift` registriert die drei Schreib-Tools dann zusätzlich
  zu den bestehenden 7 Lese-Tools (10 statt 7 in `tools/list`). Da Feedivo selbst
  Statusänderungen nur über `SQLiteDataInvalidation`/`SidebarBadgeInvalidation`
  (in-process `@Observable`-Zähler, siehe bestehender Gotcha weiter unten) erfährt,
  die ein externer Prozess wie der MCP-Server nicht auslösen kann, ergänzt Task 6
  einen Cross-Process-Live-Refresh-Mechanismus über Darwin-Notifications
  (`MCPWriteNotifier`/`MCPWriteObserver`, geteilte Namenskonstante
  `Feedivo/Services/MCPWriteNotificationName.swift`) — nach jedem erfolgreichen
  Schreib-Tool-Aufruf postet der Server eine Darwin-Notification, die die laufende
  Feedivo-App (falls geöffnet) beobachtet und daraufhin ihre eigenen
  Invalidierungs-Zähler bumpt, damit Artikelliste/Sidebar sich ohne Ordnerwechsel
  oder Neustart aktualisieren. Umgesetzt via Brainstorming→Spec→Plan→
  Subagent-Driven-Development (7 Tasks, alle Task-Reviews clean/„Approved" im ersten
  Anlauf). Spec: `docs/superpowers/specs/2026-08/2026-08-14-mcp-server-v2-phase1-
  schreibzugriff-design.md`, Plan: `docs/superpowers/plans/2026-08-14-mcp-server-v2-
  phase1-schreibzugriff.md`.
  **Sanktionierte Abweichung in Task 6:** der Plan sah für das neue geteilte File
  `Feedivo/Services/MCPWriteNotificationName.swift` eine manuelle Xcode-GUI-Target-
  Membership-Ergänzung vor (Schritt 2) — ohne interaktive Xcode-GUI in dieser
  autonomen Ausführung stattdessen über einen direkten, minimalen Ein-Zeilen-Edit an
  `Feedivo.xcodeproj/project.pbxproj` gelöst (neue Datei alphabetisch korrekt in
  dasselbe `membershipExceptions`-Array eingefügt, das bereits Commit `af9a8a2` als
  exaktes historisches Vorbild nutzt) — vom Task-Reviewer als korrekt verifiziert
  (alphabetische Platzierung, einzelne Zeile, keine sonstigen Änderungen, Build
  referenziert das Symbol erfolgreich).
  **Automatisierte Verifikation (Task 7, dieser Eintrag):** voller Debug-Build für
  beide Schemes (`Feedivo` UND `FeedivoMCPServer`) grün, gezielter Regressionslauf
  über `FeedivoDatabaseMigratorTests`/`MCPServerSettingsStoreTests`/
  `MCPWriteObserverTests` (18 Tests in 3 Suiten, `-parallel-testing-enabled NO`)
  grün, voller Release-Build grün. **Live-stdio-Smoke-Test:** das im Plan
  vorgesehene Vorgehen (Scratch-Kopie der Produktions-DB, Schreibzugriff-Schalter
  dort aktivieren, gebauten Prozess dagegen starten) ist für den fertig kompilierten
  Binary NICHT durchführbar — `FeedivoContainerDatabaseLocation.databaseURL()`
  baut den Datenbankpfad fest aus `FileManager.default.homeDirectoryForCurrentUser`
  zusammen, ohne CLI-Argument- oder Umgebungsvariablen-Override; per isoliertem
  Testprogramm empirisch verifiziert, dass `homeDirectoryForCurrentUser` die
  `$HOME`-Umgebungsvariable NICHT berücksichtigt (liefert immer den echten
  Account-Home-Pfad aus der Passwortdatenbank, unabhängig vom Prozessumfeld) — der
  Binary lässt sich dadurch ohne Quellcode-Änderung (außerhalb des Scopes dieser
  reinen CLAUDE.md-Aufgabe) nicht auf eine Scratch-DB umleiten. Statt ersatzweise
  den Schreibzugriff-Schalter kurzzeitig in der ECHTEN Produktions-DB umzulegen
  (riskant, auch mit exaktem Restore vermeidbar — die reale DB zeigte beim
  Vorab-Check bereits `isEnabled = 1`, der Server also potenziell aktiv im Einsatz),
  wurde bewusst die konservativere Variante gewählt: ein echter, gebauter
  `FeedivoMCPServer`-Prozess (Debug-Build) wurde per echter newline-delimitierter
  `initialize`→`notifications/initialized`→`tools/list`-JSON-RPC-Sequenz gegen die
  echte, UNVERÄNDERTE Produktions-DB gestartet — rein lesend, `tools/call` wurde zu
  keinem Zeitpunkt aufgerufen. Ergebnis: Handshake erfolgreich, `tools/list` liefert
  korrekt genau 7 Tools (passend zum realen, unangetasteten
  `writeAccessIsEnabled = 0`) — verifiziert damit den kompletten Protokoll-/
  Gating-Pfad des tatsächlich kompilierten Binarys end-to-end, OHNE jede Daten-
  mutation. Vorher-/Nachher-Check per `sqlite3` bestätigt: `mcp_server_settings`
  in der echten Produktions-DB unverändert (`isEnabled = 1, writeAccessIsEnabled =
  0`, identisch zum Ausgangszustand). Der im Plan vorgesehene positive Fall (Schalter
  AN → 10 Tools, echter `update_article_status`-Schreibvorgang verifiziert per
  `sqlite3`) konnte dadurch NICHT gegen den echten Binary demonstriert werden — diese
  Lücke ist durch die code-seitige Testabdeckung aus Tasks 4–6
  (`FeedivoMCPServerWritableDatabaseTests`, Tool-Tests, `MCPWriteObserverTests`,
  siehe auch der erweiterte Gotcha zu `FeedivoMCPServerTests`/TEST_HOST weiter unten)
  sowie durch die ausstehende manuelle Live-Checkliste unten abgedeckt.
  **Zurückgestellte Minor-Funde aus den 6 Task-Reviews** (keiner blockierend, keine
  Aktion jetzt nötig): fehlende `isHidden`-Testabdeckung in Task 4 (aus dem
  Plan-Text geerbt), fehlende Testabdeckung für „`remove_tag` mit unbekannter
  `articleID`" in Task 5 (ebenfalls aus dem Plan-Text geerbt), ein akzeptierter
  TOCTOU-Hinweis zwischen Existenz-Check und Schreibverbindung (geringes Risiko bei
  einem lokalen Single-User-Server), ein leicht zu weit gefasster Doc-Kommentar in
  `FeedivoMCPServerWritableDatabase.swift` zum Schreibmodus-Abgleich mit der
  Haupt-App, sowie ein `saveErrorMessage`-Überschreibungs-Randfall in der Settings-UI,
  wenn die Speicher-Aufrufe beider Schalter verkettet werden (Task 2, aus dem
  wörtlichen Plan-Code geerbt). **Ausstehend:** die manuelle 9-Punkte-Live-
  Verifikationscheckliste aus Plan-Task 7/Schritt 5 (Schalter-Sichtbarkeit/
  -Abhängigkeit, Persistenz nach Neustart, echte Schreibvorgänge aus Claude Desktop
  inkl. sichtbarem Live-Refresh in der geöffneten App, Fehlerverhalten bei falscher
  `articleID`, Tool-Liste nach Deaktivierung) erfordert eine laufende Feedivo-App +
  Claude Desktop am eigenen Mac und ist vom Nutzer selbst durchzuführen (kein
  computer-use für native macOS-Apps in dieser Umgebung verfügbar). **Phasen 2–4
  (Feed-Verwaltung, neue Lese-Tools, Such-Verbesserungen) sind eigene, noch nicht
  begonnene Folge-Zyklen.** Commits `6765127..cc03628` (Tasks 1–7, 8 Commits) lokal
  auf `main`, NICHT gepusht (Nutzerbestätigung vor Push laut Projektkonvention
  ausstehend).

- **2026-08-12 bis 2026-08-14: Read-only MCP-Server für Feedivo (v1) — VOLLSTÄNDIG
  ABGESCHLOSSEN, gepusht, live in Claude Desktop verifiziert.** Neues Command-Line-
  Tool-Target `FeedivoMCPServer` (stdio-`MCP`-SDK, Target-Membership-Sharing mit dem
  Haupt-Target statt eigenem Package, siehe ADR-011) — 7 read-only Tools
  (`list_feeds`, `list_folders`, `list_tags`, `search_articles`, `get_article`,
  `list_smart_folders`, `get_smart_folder_articles`), funktioniert unabhängig davon,
  ob Feedivo läuft. Umgesetzt via Brainstorming→Spec→Plan→Subagent-Driven-Development
  (12 Tasks, davon Tasks 2/11/12 `[MANUELL]` vom Nutzer selbst ausgeführt — Xcode-
  Target-Membership-Einrichtung per präzisen, vom Controller ermittelten fehlenden
  Symbolen; Copy-Files-Einbettung ins App-Bundle; Live-Verifikation in Claude Desktop).
  **Zwei aufeinanderfolgende, jeweils per Re-Review gefundene Bugs in der finalen
  Fix-Runde des Whole-Branch-Reviews, beide behoben und unabhängig bestätigt:** (1)
  ein Critical-Fund brach versehentlich `xcodebuild test` für das GESAMTE
  Hauptprojekt (`Feedivo.xcscheme` referenzierte fälschlich `FeedivoMCPServerTests`);
  (2) der ursprüngliche Fix für „Server öffnet auch ohne laufende Feedivo-App" erwies
  sich selbst als kaputt (`DatabasePool` + `PRAGMA query_only`), ein Zwischenfix
  (`DatabaseQueue` + `PRAGMA query_only`) als wirkungslos für echten Schreibschutz —
  siehe der neue, ausführliche Gotcha zu GRDBs `PRAGMA query_only`-Reset-Verhalten
  weiter unten. Finaler, korrekter Fix: `configuration.readonly = true` mit
  `DatabaseQueue`. **Live-Verifikation (Task 12) durch den Nutzer UND parallel
  unabhängig durch den Controller über dieselben MCP-Tools:** echte, aktuelle
  Artikel korrekt zurückgegeben, sauberer Klartext statt rohem HTML, korrektes
  Datum. Entscheidender Test bestanden: sowohl die produktive `/Applications`-
  Instanz als auch eine zusätzlich beim Gegenchecken entdeckte, an einen
  `debugserver`/LLDB gehängte Xcode-Debug-Build-Instanz (ignorierte normales Beenden
  und `SIGTERM`, nur per Kill des `debugserver`-Prozesses selbst lösbar) vollständig
  beendet — Abfragen funktionierten weiterhin fehlerfrei. Bekannte, akzeptierte
  Einschränkung: `xcodebuild test` kann Command-Line-Tool-Targets strukturell nicht
  als `TEST_HOST` verwenden — Tests existieren als echter, kompilierverifizierter
  Swift-Testing-Quellcode, laufzeitverifiziert stattdessen über echte stdio-Smoke-
  Tests (siehe Gotchas). Spec: `docs/superpowers/specs/2026-08-12-feedivo-mcp-
  server-design.md`, Plan: `docs/superpowers/plans/2026-08-12-feedivo-mcp-server.md`.
  Commits `4ed7498..ac2a3eb` auf `main`, gepusht (`d586d01..ac2a3eb`).

- **2026-08-05: Feed-Status-Fenster als dichte Tabelle mit sichtbaren Aktionen —
  VOLLSTÄNDIG ABGESCHLOSSEN (4 Tasks + Whole-Branch-Review-Fix-Welle, alle clean
  reviewed bzw. re-verifiziert), automatisierte Tests + Debug- + Release-Build
  grün, manuelle Live-Verifikation NOCH AUSSTEHEND.**
  Redesign des mit Feature 32 (`FeedRefreshDiagnosticsWindowView`, siehe die drei
  Einträge direkt darüber vom selben Tag) neu eingeführten Feed-Status-Fensters: von
  einer schlichten Liste mit ausschließlich per Rechtsklick-Kontextmenü erreichbaren
  Aktionen auf eine dichte Tabelle im „Konzept A"-Design (`RuleDialogTheme`, das
  bereits Export-/Import-Dialog und Suchfenster prägt) umgestellt — alle fünf zuvor
  nur im Kontextmenü versteckten Aktionen (Aktualisieren, Eigenschaften, Website
  öffnen, XML-Adresse kopieren, Löschen) sind jetzt als permanent sichtbare
  Icon-Buttons pro Zeile vorhanden. Umgesetzt via Brainstorming→Spec→Plan→
  Subagent-Driven-Development (4 Tasks): Task 1 reine, isoliert getestete
  Filter-/Sortier-/Schweregrad-Logik (`FeedStatusTableLogicTests`, 9 Tests: Suche
  nach Titel/URL case-insensitive, Sortierung nach Fehlschlägen absteigend,
  Schweregrad neutral/amber/rot bei 1/2-4/≥5 Fehlschlägen), Task 2 neue L10n-Keys
  für Spaltenköpfe/Suche/Fußzeile, Task 3 View-Umbau auf die dichte Tabelle selbst.
  Alle drei Implementierungs-Tasks kamen mit clean Task-Reviews zurück (0
  Critical/Important) — **sechs Minor-Funde aus Task 3s Review wurden bewusst NICHT
  gefixt, sondern für eine spätere Whole-Branch-Review-Triage zurückgestellt** (Eigenschaften
  des Plan-Designs selbst, keine Implementierungsfehler):
  1. Deaktivierter Wiederholen-Icon-Button hat während eines laufenden „Alle erneut
     versuchen" kein abgedunkeltes visuelles Feedback (`FeedRefreshDiagnosticsWindowView.swift`
     ~Zeile 457/616-628) — das alte, native Kontextmenü bekam Greyed-out-Styling
     kostenlos, der neue Icon-Button dimmt nicht.
  2. Die Tabellen-`ScrollView` ist fest auf `.frame(maxHeight: 360)` gedeckelt
     (~Zeile 195), unabhängig von der Fenstergröße — ein größeres Fenster zeigt
     keine zusätzlichen Zeilen.
  3. Fußzeilen-Feed-Anzahl und „Alle erneut versuchen" nutzen die volle
     `diagnostics`-Liste statt der suchgefilterten `visibleDiagnostics`
     (~Zeile 295, 350) — die Fußzeilen-Anzahl spiegelt einen aktiven Suchfilter
     nicht wider.
  4. Das rein dekorative Sortier-Chevron neben „Fehlschläge" ist akzentgefärbt
     (~Zeile 219), wirkt dadurch optisch klickbar, obwohl die Sortierung fest/nicht
     interaktiv ist.
  5. `retry(_:)` setzt `isBusy` nicht (~Zeile 329-335) — schnelle Klicks über mehrere
     Zeilen hinweg können gegen `FeedViewModel.refreshFeed`s internen
     Reentrancy-Schutz still verpuffen; vorbestehendes Verhalten, jetzt aber
     sichtbarer, da Wiederholen nicht mehr im Kontextmenü versteckt ist.
  6. Ein reiner Prozess-Hinweis (kein Code-Defekt): der ursprüngliche Task-3-Report
     zeigte zunächst elidierte/abgeschnittene Build-Log-Belege statt des vollen Logs
     rund um die Erfolgsmeldung.
  **Finaler Whole-Branch-Review (direkt im Anschluss) korrigierte drei dieser
  sechs Task-3-Einstufungen und fand zwei weitere, komplett neue Important-Funde
  — alle fünf in einer gemeinsamen Fix-Welle behoben:**
  1. Veraltete `.defaultSize(width: 520, height: 480)` in `FeedivoApp.swift`
     (Zeile 278, Stand vor der Tabellen-Umstellung) liegt UNTER dem neuen
     Tabellen-Content-Minimum von 700pt (`.frame(minWidth: 700, ...)`,
     `FeedRefreshDiagnosticsWindowView.swift` Zeile 67) — macOS klemmt das
     Fenster beim Öffnen dadurch auf exakt 700pt, bei denen der flexiblen
     Fehler-Spalte nach den vier festen Spalten (170+90+118+150pt) + Abständen/
     Padding nur noch ~36pt bleiben. Die Fehlermeldung — der eigentliche Zweck
     des Fensters — war dadurch bis zum manuellen Vergrößern praktisch
     unlesbar, ein neuer Important-Fund, den keiner der drei Einzel-Task-
     Reviews sehen konnte (Task 1/2 berühren `FeedivoApp.swift` gar nicht,
     Task 3 änderte nur die View-Datei). Fix: `960×620`.
  2. `.background(theme.bg)` stand vor `.frame(minWidth:minHeight:)`
     (Zeile 66-67) statt danach — malt dadurch nur die natürliche Content-
     Größe des VStack, nicht den durch die Mindestgröße erzwungenen
     Zusatzraum. Im „Keine Treffer"-Zustand (fixer ~150pt-Block, deutlich
     unter der 420pt-Mindesthöhe) waren unthemed Systemhintergrund-Bänder
     oben/unten sichtbar — OHNE dass der Nutzer das Fenster überhaupt
     vergrößern musste, ein eigenständiger, über Fund 2 (ScrollView-Deckel)
     hinausgehender Bug. Fix: Reihenfolge getauscht + `maxWidth: .infinity,
     maxHeight: .infinity, alignment: .top` ergänzt; zusätzlich die
     Tabellen-`ScrollView` (Fund 2 oben, Zeile 195) von `.frame(maxHeight:
     360)` auf `.frame(maxHeight: .infinity)` umgestellt, damit die Tabelle
     den jetzt korrekt gefüllten Platz auch tatsächlich nutzt statt bei
     fixer Deckelhöhe stehenzubleiben — beide Änderungen waren nur gemeinsam
     wirksam.
  3. Fund 5 (`retry(_:)` setzt `isBusy` nicht) war in der Task-3-Review als
     „vorbestehendes Verhalten, jetzt nur sichtbarer" unterbewertet — der
     Whole-Branch-Reviewer stellte richtig: es ist kein stilles No-op mehr,
     sondern ein sichtbarer, störender roter Fehlerbanner. Da die Zeilen-
     Wiederholen-Buttons jetzt permanent sichtbar sind statt im Kontextmenü
     versteckt, ist „Wiederholen bei Zeile A klicken, während A noch läuft
     sofort Wiederholen bei Zeile B klicken" eine ganz natürliche, einen
     Klick entfernte Interaktion — `FeedViewModel.refreshFeed`s interner
     Reentrancy-Guard (`guard !isLoading else { errorMessage =
     L10n.feedErrorAlreadyRunning; return }`) quittiert den zweiten Klick mit
     genau diesem Banner, der bis zur nächsten erfolgreichen Aktion stehen
     bleibt. Fix: `retry(_:)` setzt jetzt `isBusy = true`/
     `defer { isBusy = false }`, exakt wie `retryAll()` es bereits tut — die
     pro Zeile bereits vorhandene `.disabled(isRetryDisabled)`-Bindung
     (`isRetryDisabled: isBusy`) greift dadurch jetzt auch beim
     Einzel-Retry.
  4. (Minor, im selben Rutsch mitgefixt) Die Hälfte von Fund 3, die die
     Fußzeilen-Anzahl betrifft (Zeile 295): `footerStatusText` nutzte
     `diagnostics.count` statt `visibleDiagnostics.count` — bei aktivem
     Suchfilter mit 0 Treffern zeigte die Fläche darüber „Keine Treffer", die
     Fußzeile direkt darunter aber weiterhin die volle ungefilterte Anzahl
     (z. B. „12 Feeds mit Fehlern") — zwei widersprüchliche Aussagen
     übereinander auf einen Blick. Fix: `visibleDiagnostics.count`.
     `retryAll()`s Verhalten (wiederholt bewusst ALLE Feeds, nicht nur die
     sichtbaren) bleibt unverändert — „alle erneut versuchen" ist als
     Aktion sinnvoll auf die komplette Liste bezogen, nicht nur auf den
     gerade aktiven Suchfilter, das ist kein Bug.
  **Weiterhin bewusst zurückgestellt** (reine Kosmetik-/Robustheitsfunde ohne
  Verhaltensrisiko, nicht Teil dieser Fix-Welle): Fund 1 (deaktivierter
  Wiederholen-Icon-Button dimmt während eines laufenden „Alle erneut
  versuchen" nicht ab — fehlendes visuelles Feedback, kein Funktionsfehler,
  der Button ist korrekt disabled), Fund 4 (das rein dekorative
  Sortier-Chevron neben „Fehlschläge" ist akzentgefärbt, wirkt dadurch
  optisch klickbar, obwohl die Sortierung fest ist), sowie zwei vom
  Whole-Branch-Reviewer neu gefundene Minor-Punkte: `FeedStatusTableLogic.
  sortedByFailureCountDescending` hat keinen Tiebreaker bei gleicher
  Fehlschlagszahl (Reihenfolge zwischen zwei Feeds mit z. B. je 3
  Fehlschlägen ist instabil/implementierungsabhängig), und die festen
  Spaltenbreiten (170/90/118/150pt) sind gegen die deutschen/englischen
  Spaltenkopf-Texte bemessen — längere französische/italienische
  Übersetzungen könnten umbrechen oder abgeschnitten werden.
  Task 4 (dieser Eintrag) deckt nur die automatisierbaren Abschlussschritte ab:
  gezielter Testlauf `FeedStatusTableLogicTests` (9/9 grün), voller
  `xcodebuild build -configuration Debug` (BUILD SUCCEEDED) und voller
  `xcodebuild build -configuration Release` (BUILD SUCCEEDED, 0 Fehler — deckt u. a.
  ab, dass die in Task 2 ergänzten `Localizable.xcstrings`-Einträge korrekt
  formatiert sind, da der String-Catalog-Compile-Schritt in beiden Konfigurationen
  läuft). **Weiterhin unverifiziert, da kein computer-use für native macOS-Apps in
  dieser Umgebung verfügbar ist — 7-Punkte-Live-Checkliste, vom Nutzer selbst
  abzuarbeiten:** 1. Feed-Menü → „Feed-Status…" öffnet das Fenster im neuen
  Tabellen-Layout. 2. Ist kein Feed fehlgeschlagen: grüner Erfolgs-Leerzustand wie
  bisher. 3. Bei fehlgeschlagenen Feeds: Spalten Feed/Fehler/Zuletzt/Fehlschläge/
  Aktionen befüllt, Fehlschläge-Badge-Farbe passt zur jeweiligen Anzahl (1 neutral,
  2-4 amber, ≥5 rot). 4. Tippen ins Suchfeld filtert sichtbar nach Titel und nach
  URL; bei keinem Treffer erscheint „Keine Treffer" statt einer leeren Fläche. 5.
  Alle fünf Icon-Buttons pro Zeile funktionieren identisch zum bisherigen
  Rechtsklick-Menü: Aktualisieren, Eigenschaften (öffnet Sheet), Website öffnen (nur
  sichtbar wenn URL vorhanden), XML-Adresse kopieren, Löschen (fragt nach
  Bestätigung). 6. Fußzeile zeigt korrekte Anzahl + „zuletzt geprüft vor …" nach
  „Neu laden" bzw. nach jeder Aktion. 7. Hell-/Dunkelmodus: Farben stimmen in beiden
  Darstellungen (Fenster einmal bei Hell- und einmal bei Dunkelmodus öffnen). 8.
  **Neu (deckt Whole-Branch-Review-Fund 1 ab):** Fenster ohne manuelles Vergrößern
  öffnen — ist die Fehlerspalte lesbar (nicht auf ~36pt zusammengequetscht)? Spec/
  Plan: `docs/superpowers/specs/2026-08/2026-08-05-feed-status-tabellenansicht-design.md`,
  `docs/superpowers/plans/2026-08/2026-08-05-feed-status-tabellenansicht.md`. Commits
  `ae4be66..3bac82d` (4 Tasks) + ein separater Whole-Branch-Review-Fix-Commit
  (Fenstergröße, Hintergrund/Frame-Reihenfolge, Retry-Reentrancy, Fußzeile) auf
  `main` (lokal, Push-Status siehe `git log`/`git merge-base --is-ancestor
  origin/main` zum Lesezeitpunkt prüfen statt diesen Vermerk ungeprüft zu
  übernehmen — siehe bestehende Lehre zu Push-Status-Aussagen weiter unten in
  diesem Dokument). Fix-Welle: Build (Debug) BUILD SUCCEEDED,
  `FeedStatusTableLogicTests` erneut 9/9 grün (keine der vier Code-Fixes berührt
  diese Testdatei, reiner Regressions-Check).

- **2026-08-05: `@AppStorage`/`UserDefaults`→`@Observable`-Migration der SQLite-
  Invalidierungssignale — VOLLSTÄNDIG ABGESCHLOSSEN (Tasks 1-8, alle reviewed),
  Live-Perf-Verifikation NOCH AUSSTEHEND.** Direkte Folgearbeit zum darunter
  dokumentierten Reader-Ladeverzögerung-Fund vom selben Tag: dort wurde als
  verbleibende, nicht behobene Ursache identifiziert, dass SwiftUIs
  `@AppStorage`/`UserDefaults`-Änderungsbenachrichtigung auf diesem System eine
  konsistente ~220-250ms-Latenz hat, bevor `.onChange`/`.task(id:)`-Observer
  reagieren — verschärft durch mindestens 7 app-weit gleichzeitig auf denselben
  `sqliteData.statusVersion`-Key registrierte `@AppStorage`-Beobachter. Diese
  Session ersetzt den zentralen, seit dem SwiftData-Ausbau (ADR-007) app-weiten
  Reaktivitätsmechanismus (`SQLiteDataInvalidation.bumpStatusVersion()` +
  `SidebarBadgeInvalidation.bumpDirectTagVersion()`, beide vormals
  `UserDefaults`-basiert) durch zwei native `@MainActor`/`@Observable`-Singletons
  mit identischer Methoden-/Property-Semantik (`shared.statusVersion`/
  `shared.bumpStatusVersion()` bzw. `shared.directTagVersion`/
  `shared.bumpDirectTagVersion()`), die SwiftUIs eigene, deutlich schnellere
  Observation-Machinerie nutzen statt `UserDefaults`-Notifications. Umgesetzt
  via Brainstorming→Spec→Plan→Subagent-Driven-Development (8 Tasks): Task 1
  legte beide neuen `@Observable`-Typen bewusst als Koexistenz NEBEN der alten
  `enum`-API an (unter den Zwischennamen `SQLiteDataInvalidationSignal`/
  `SidebarBadgeInvalidationSignal`, da die Zielnamen noch von der alten API
  belegt waren), Tasks 2-7 migrierten alle Aufrufer schichtweise (Reader-/
  Artikelliste-Views, Sidebar-/Feed-Verwaltungs-Views, Settings-/SmartFolder-/
  Sync-Views, Store-/Service-/ViewModel-Schicht, `MenubarStatusItemController`
  — von KVO auf `UserDefaults` auf `withObservationTracking` umgestellt —,
  sowie `CloudSyncEngine.swift` als Actor-Isolations-Sonderfall). **Task 8
  (dieser Eintrag)** entfernte die alte `UserDefaults`-basierte `enum`-API
  vollständig (ersatzlos gelöscht aus `Feedivo/Database/
  SQLiteDataInvalidation.swift` und den Zeilen 33-45 von `Feedivo/Views/
  Sidebar/SidebarUnreadCount.swift`) und benannte die beiden `@Observable`-
  Klassen final von `SQLiteDataInvalidationSignal`/
  `SidebarBadgeInvalidationSignal` auf die jetzt freien Namen
  `SQLiteDataInvalidation`/`SidebarBadgeInvalidation` um — reine, mechanische
  Textersetzung über 30 Dateien (`Feedivo` + `FeedivoTests`), keine
  Logikänderung. Die beiden zugehörigen Testklassen-NAMEN
  (`SidebarBadgeInvalidationSignalTests`, `SQLiteDataInvalidationTests`) blieben
  dabei bewusst unverändert (nur der jeweils getestete Typ wurde umbenannt,
  nicht die Testklasse selbst — deckt sich mit der Spec-Vorgabe). Beim
  finalen Verifikations-Grep (Step 1, exakt wie im Plan vorgegeben) fanden
  sich vier reine Kommentar-Fundstellen (`FeedivoDatabase.swift`,
  `SettingsView.swift`, `CloudSyncEngine.swift`, `ArticleTagAssignmentView.swift`),
  die noch auf die alten, jetzt nicht mehr existierenden `UserDefaults`-Key-
  Symbolnamen (`.statusVersionKey`/`.directTagVersionKey`) bzw. auf die alte,
  parameterlose statische Aufrufsyntax verwiesen — kein Kompilierfehler (reine
  Prosa-Kommentare), aber seit der Umbenennung fachlich veraltet/irreführend;
  bei dieser Gelegenheit auf die korrekte `shared.`-Instanzsyntax korrigiert
  (kein eigener Task-Scope-Verstoß, da unmittelbare Konsequenz der
  Umbenennung selbst). Build (`xcodebuild build -scheme Feedivo -configuration
  Debug`) grün. Gezielter Regressionslauf (Step 6, `-parallel-testing-enabled
  NO`, 8 Suiten) zeigte auf den ersten Blick 26 fehlschlagende Tests (25 in
  `FeedivoAppSceneConfigurationTests`, 1 in `SQLiteFeedArticleListStateTests`)
  — da das in CLAUDE.md zuletzt am 2026-07-23 dokumentierte „17"
  vorbestehende Fehlschläge in `FeedivoAppSceneConfigurationTests.swift" davon
  abweicht (bereits damals als driftende, nicht bei jeder Session
  nachgezogene Zahl bekannt, siehe bestehender Gotcha-Eintrag „15"→„17"),
  wurde die tatsächliche Baseline nicht aus der Doku übernommen, sondern per
  `git worktree add` gegen den Commit unmittelbar VOR Task 1 (`7b28690`) neu
  gemessen: identischer Testlauf dort lieferte exakt dieselben 25
  fehlschlagenden Testnamen (byte-identisch, „38 issues" in beiden Läufen) in
  `FeedivoAppSceneConfigurationTests` sowie 5 (statt 1) fehlschlagende Tests
  in der bereits als flaky-unter-Last dokumentierten
  `SQLiteFeedArticleListStateTests`-Suite — die Migration führt also
  nachweislich ZU KEINEN neuen Testfehlschlägen, die Differenz bei
  `SQLiteFeedArticleListStateTests` liegt im bekannten Flakiness-Rahmen
  (diesmal sogar weniger Fehlschläge als Baseline). Alle übrigen sechs
  benannten Suiten (`CloudSyncEngineRegistryTests`, `FeedViewModelTests`,
  `MenubarStatusItemControllerTests`, `SQLiteReaderStateTests`, sowie die
  beiden neuen `SQLiteDataInvalidationTests`/`SidebarBadgeInvalidationSignalTests`)
  liefen grün. Nebenbefund (kein Regressions-, sondern ein bereits vor Task 1
  bestehender Tooling-Befund, identisch in Baseline- und Nachher-Lauf
  reproduziert): der direktoriumsbasierte Selektor
  `-only-testing:FeedivoTests/Services/CloudSync` wählt in diesem Xcode-Stand
  0 Tests aus (vermutlich eine Pfad-/Suite-Namens-Eigenheit von
  `xcodebuild`/Swift Testing bei Verzeichnis- statt Klassen-Selektoren) — die
  darin enthaltene, explizit im Plan benannte `CloudSyncEngineRegistryTests`-
  Suite lief über ihren eigenen, separaten `-only-testing:`-Eintrag trotzdem
  korrekt und grün; keine der ~18 CloudSync-Testdateien referenziert die
  umbenannte API direkt (per Grep verifiziert), sodass hieraus kein
  Blindspot für diese Migration entsteht. **Ausstehend (bewusst nicht Teil
  dieser Session, siehe Scope-Anpassung im Task-8-Auftrag):** die ursprünglich
  als Step 7 geplante Live-Verifikation der Reader-Ladezeit (per temporärer
  `OSLog`-Instrumentierung soll geprüft werden, ob die Zeit von Artikelauswahl
  bis sichtbarem Inhalt sich jetzt auch bei Selektionen, die einen
  Status-Bump auslösen, der zuvor nur bei „kein Bump nötig"-Selektionen
  erreichten ~120-140ms-Bestzeit annähert, statt der vorher gemessenen
  ~415-690ms) — das erfordert einen Nutzer, der in der laufenden, echten
  App 2-3 ungelesene Artikel auswählt, während parallel `log stream`
  mitläuft; als Subagent ohne Möglichkeit, mit einer laufenden nativen
  macOS-GUI-App zu interagieren, nicht durchführbar. Muss vom Nutzer selbst
  nachgeholt werden, analog zu den zahlreichen anderen „manuelle
  Live-Verifikation ausstehend"-Einträgen in diesem Dokument. Betroffene
  Dateien (Auswahl, vollständige Liste per `git show --stat` auf dem
  Task-8-Commit): `Feedivo/Database/SQLiteDataInvalidation.swift`,
  `Feedivo/Views/Sidebar/SidebarUnreadCount.swift` (beide Kern-Umbenennung),
  plus 28 weitere Aufrufer-Dateien in `Feedivo/` und `FeedivoTests/` (reine
  Textersetzung `...Signal` → ohne `...Signal`) sowie die vier oben genannten
  Kommentar-Korrekturen.
  **Nachtrag (finale Whole-Branch-Review-Fixes, direkt im Anschluss, ein
  gemeinsamer Commit):** fünf veraltete/falsche Kommentare korrigiert (kein
  Verhaltensunterschied) — u. a. der Doc-Kommentar über
  `CloudSyncEngine.backfillAllExistingRecords` behauptete noch, die Methode
  sei `nonisolated`; das ist seit Task 7 falsch (implizit `@MainActor`-
  isoliert, weil sie `SQLiteDataInvalidation.shared.bumpStatusVersion()`
  aufruft) und wurde entsprechend korrigiert. Zwei Klarstellungen dazu, die
  beim Lesen dieses Eintrags leicht übersehen werden:
  a) Die beiden neuen Singleton-Zähler (`SQLiteDataInvalidation.shared.
  statusVersion`, `SidebarBadgeInvalidation.shared.directTagVersion`)
  persistieren NICHT mehr über App-Neustarts hinweg (reiner In-Memory-
  Zustand, anders als die alte `UserDefaults`-basierte Version) — das ist
  sicher, weil alle Konsumenten die Zähler nur als relative Änderungs-
  Erkennung nutzen, verglichen gegen eigenen `@State`, der ebenfalls bei
  jedem Prozessstart bei 0 beginnt; nirgends wird ein Versionsstand über
  einen App-Start hinweg persistiert verglichen (per Grep verifiziert).
  b) Für die oben noch offene Live-Perf-Verifikation: `SQLiteFeedArticleListView`
  hat weiterhin ihre eigene, unabhängige 200ms-Debounce-Logik (aus dem
  NetNewsWire-Batching-Feature vom 2026-07-27,
  `statusVersionDebounceMilliseconds`) BEVOR sie `loadToken` neu aufbaut —
  die Artikelliste bleibt deshalb bewusst weiterhin ~200ms hinter einer
  Statusänderung zurück, das ist KEINE fehlgeschlagene Migration. Der
  Reader-Pfad (`SQLiteReaderView.swift`, `.onChange` auf `statusVersion`,
  undebounced) ist der Pfad, den diese Migration tatsächlich sichtbar
  beschleunigen sollte — dort sollte die Verbesserung beim Live-Test
  sichtbar werden.
  **Nachtrag 2 (2026-08-05, Live-Perf-Messung NACHGEHOLT — ÜBERRASCHENDES,
  NICHT wie erwartet positives Ergebnis, neue offene Frage):** Die oben als
  „vom Nutzer nachzuholen" dokumentierte Live-Verifikation wurde direkt im
  Anschluss durchgeführt — TEMP-DEBUG-`OSLog`-Instrumentierung an denselben
  vier Messpunkten wie in der 2026-08-05er Reader-Ladeverzögerung-Diagnose
  unten (T0 `markSelectedArticleReadIfNeeded()`, T1 unmittelbar nach
  `SQLiteDataInvalidation.shared.bumpStatusVersion()`, T2 im Feuern von
  `SQLiteReaderView`s `.onChange(of: SQLiteDataInvalidation.shared.
  statusVersion)`, T3/T4 Start/Ende von `SQLiteReaderState.load()`), Nutzer
  wählte in der frisch gebauten, instrumentierten App live 6 ungelesene
  Artikel aus, danach Instrumentierung wieder vollständig entfernt (nie
  committet, wie beim vorherigen Mal). **Ergebnis bei vier sauberen,
  isolierten Einzelmessungen:** T0→T1 (Artikelauswahl bis DB-Write+Bump)
  durchgehend sehr schnell (3-9ms) — das ist die erwartete, bereits durch
  die DatabasePool-Migration und diese `@Observable`-Migration abgesicherte
  Strecke. **Aber T1→T2 (Bump bis `.onChange` im Reader feuert) lag bei
  ALLEN vier Messungen konsistent bei 225-228ms** — praktisch identisch zur
  ursprünglich für die alte `@AppStorage`/`UserDefaults`-Mechanik gemessenen
  ~220-250ms-Latenz, die diese gesamte Migration eigentlich beheben sollte.
  Gesamtzeit T0→T4 (Artikelauswahl bis sichtbarer Reader-Inhalt): 498-681ms
  — in derselben Größenordnung wie der bereits VOR dieser Migration
  gemessene Zwischenstand (~415-690ms nach DatabasePool-Fix, siehe Eintrag
  unten), NICHT die erhoffte Annäherung an die ~120-140ms-Bestzeit. **Die
  `@Observable`-Migration selbst ist nach doppelter unabhängiger Code-Review
  (Task-5-Actor-Isolations-Check + finale Whole-Branch-Review) nachweislich
  architektonisch korrekt und lückenlos umgesetzt** — alle 15 Lesestellen
  von `.statusVersion`/`.directTagVersion` wurden als korrekt innerhalb von
  `body`/`.onChange(of:)`/`.task(id:)` verifiziert, echte SwiftUI-
  Observation-Tracking-Aktivierung bestätigt. Die konsistente ~225ms-
  Verzögerung liegt deshalb vermutlich NICHT (mehr) an der
  `UserDefaults`-Benachrichtigung selbst, sondern an einer bislang
  unidentifizierten anderen Ursache mit zufällig sehr ähnlicher
  Größenordnung — mögliche Kandidaten, jeweils NICHT verifiziert, nur als
  Ausgangshypothesen für eine künftige Diagnose-Session notiert: (a)
  `SearchDebounce.delayMilliseconds = 250`
  (`Feedivo/Extensions/SearchDebounce.swift`) oder
  `SQLiteFeedArticleListView.statusVersionDebounceMilliseconds = 200`
  könnten trotz ihrer eigentlich anderen Zuständigkeit indirekt die
  MainActor-Verarbeitungsreihenfolge beeinflussen; (b) SwiftUIs
  Update-Koaleszierung könnte bei `SQLiteReaderView`s ungewöhnlich großem
  `body` (bereits an anderer Stelle als Typechecker-Problem dokumentiert,
  siehe Kommentar dort zu „~15 Controls") langsamer greifen als erwartet;
  (c) ein noch unbekannter dritter Effekt. **Lehre, konsistent mit dem
  bestehenden Gotcha zu SourceKit-Fehldiagnosen und dem Grundsatz
  „Verifikation vor Behauptung":** eine architektonisch korrekt verifizierte
  Migration kann trotzdem das gemessene Nutzerproblem nicht lösen, wenn die
  ursprüngliche Root-Cause-Diagnose (hier: „`UserDefaults`-Notification-
  Latenz ist die Ursache") unvollständig oder falsch war — nur eine echte
  Vorher-/Nachher-Messung deckt das auf, keine Code-Review, egal wie
  gründlich. **Nächster Schritt (bewusst NICHT in dieser Session begonnen):**
  eigener neuer systematic-debugging-Durchgang mit frischer TEMP-DEBUG-
  Instrumentierung, die gezielt zwischen T1 und T2 weitere Zwischenpunkte
  setzt (z. B. unmittelbar vor/nach `CloudSyncEngine.
  notifyPendingChangesAvailable(database:)`, das nach jedem Bump
  synchron aufgerufen wird, sowie ein Zeitstempel direkt beim Betreten von
  `SQLiteReaderView.body`), um die 225ms-Lücke tatsächlich einzugrenzen statt
  weiter zu vermuten.
  **Nachtrag 3 (2026-08-05, direkte Folgesitzung — ROOT CAUSE GEFUNDEN UND
  BEHOBEN, live verifiziert):** Der oben skizzierte nächste Schritt wurde
  direkt im Anschluss umgesetzt. Feinere TEMP-DEBUG-Instrumentierung (u. a.
  ein Zeitstempel beim Betreten von `SQLiteReaderView.body` sowie an Start/
  Ende von `SidebarView`s `.task(id: sqliteSidebarReloadToken)`) zeigte:
  `SQLiteReaderView.body` wurde bereits ~28ms nach dem Bump mit dem NEUEN
  `statusVersion`-Wert neu ausgewertet — die `@Observable`-Kette selbst war
  also nie das Problem. Das `.onChange(of: statusVersion)`-Callback feuerte
  aber erst exakt in dem Moment, in dem `SidebarView`s eigener Reload-Task
  fertig wurde (konstant 178-188ms Dauer). **Root Cause:** `SQLiteSidebarState.
  load(database:showsReadFeeds:)` (`Feedivo/ViewModels/SQLiteSidebarState.swift`)
  führte bis dahin 6-7 SQL-Abfragen — inkl. einer Schleife mit einer weiteren
  Abfrage PRO Smart Folder — komplett SYNCHRON auf dem MainActor aus, ohne
  ein einziges `await`/`readAsync` in der ganzen Datei. Ausgelöst wird das von
  `.task(id: sqliteSidebarReloadToken)` in `SidebarView.swift`, das bei JEDER
  `SQLiteDataInvalidation`/`SidebarBadgeInvalidation`-Änderung feuert — also
  bei praktisch jeder Nutzerinteraktion (Gelesen markieren, Stern setzen,
  Tag ändern, …). Diese Kaskade blockierte den MainActor jedes Mal für
  ~180-230ms, wodurch ALLES andere auf dem MainActor (u. a. der Readers
  `.onChange`) so lange warten musste — unabhängig vom darunterliegenden
  Reaktivitätsmechanismus. **Das erklärt, warum weder die DatabasePool-
  Migration noch die `@AppStorage`→`@Observable`-Migration diese Latenz
  beheben konnten: die ursprüngliche Diagnose („`UserDefaults`-Notification-
  Latenz") war von Anfang an unvollständig — der eigentliche Blocker war
  diese synchrone Sidebar-Reload-Kaskade, ein strukturell identisches Problem
  zu dem bereits einmal bei der Spotlight-Backfill behobenen Muster (siehe
  Gotcha zu `SWIFT_DEFAULT_ACTOR_ISOLATION`/`readAsync` weiter oben), hier
  aber nie nachgezogen.** **Fix:** `load()` von synchron auf `async`
  umgestellt, die komplette Lese-Kaskade in `Task.detached(priority:
  .userInitiated)` ausgelagert (exakt das bereits etablierte Muster aus
  `SQLiteReaderState.load()`) — nur die finale Ergebnisübernahme in die
  `@Observable`-Properties bleibt auf dem MainActor. Neue private
  `Sendable`-Hilfsstruct `LoadedSidebarData` trägt das Ergebnis über die
  Task-Grenze zurück. Aufrufer in `SidebarView.swift` mit `await` versehen,
  alle 8 bestehenden Tests in `SQLiteSidebarStateTests.swift` auf `async
  throws`/`await` umgestellt (reine Mechanik, keine Assertion geändert).
  **Live-Verifikation nach dem Fix (gleiche Instrumentierung, 5 unabhängige
  Artikelauswahlen):** T1→T2 (Bump bis `.onChange` im Reader feuert) sank
  von konstant 225-228ms auf konstant 58-67ms — eine Verbesserung um
  ~170ms pro Interaktion, reproduzierbar über alle 5 Messungen. Der
  Sidebar-Reload-Task selbst braucht jetzt zwar tendenziell etwas länger in
  absoluter Wall-Clock-Zeit (läuft ja jetzt auf einem Hintergrund-Thread
  statt exklusiv auf dem MainActor), blockiert aber nicht mehr den Reader.
  **Regressionslauf:** 36/36 Tests grün (`SQLiteSidebarStateTests`,
  `SQLiteReaderStateTests`, `SQLiteFeedArticleListStateTests`,
  `ArticleStatusStoreTests`, `-parallel-testing-enabled NO`) — inkl. des
  sonst gelegentlich flaky `listStateToggeltReadUndAktualisiertRows`, das in
  diesem Lauf grün war. Der Source-Sniffing-Test
  `sidebarViewLaedtSQLiteSidebarState` hat einen vorbestehenden, per direktem
  A/B-Vergleich (Stash gegen sauberen committeten Stand) als NICHT durch
  diesen Fix verursacht verifizierten Fehlschlag bei einer völlig anderen,
  unveränderten Assertion (`FeedRowView(snapshot:snapshot,`) — Teil der
  bereits bekannten 25 vorbestehenden Fehlschläge in
  `FeedivoAppSceneConfigurationTests`. **Lehre, ergänzend zum bereits
  dokumentierten Grundsatz „Verifikation vor Behauptung":** eine
  architektonisch korrekt verifizierte Migration (hier: die
  `@Observable`-Umstellung) kann komplett wirkungslos bleiben, wenn die
  ursprüngliche Root-Cause-Diagnose unvollständig war — erst eine WEITERE
  Runde granularerer Live-Instrumentierung (nicht mehr nur an den Endpunkten
  T1/T2, sondern auch an den dazwischenliegenden `.task`/`.onChange`-Stellen
  paralleler Beobachter desselben Signals) deckte den tatsächlichen
  MainActor-Blocker auf. Bei jeder künftigen "warum reagiert View X nicht
  sofort auf ein @Observable-Signal"-Frage lohnt sich der Blick auf ALLE
  anderen gleichzeitig auf dasselbe Signal reagierenden Views/Tasks im
  selben Fenster, nicht nur auf die Observation-Kette der einen betroffenen
  View selbst — ein einzelner synchroner MainActor-Blocker irgendwo im
  selben Fenster kann jede noch so korrekte Observation-Implementierung
  unbrauchbar erscheinen lassen. **Status:** Fix committed und gepusht
  (Commit `133bf17`, Teil von v1.0-27) — der ursprüngliche „noch NICHT
  gepusht"-Vermerk hier war veraltet.
  **Nachtrag 4 (2026-08-05, Re-Verifikation nach v1.0-27):** dieselbe
  T1→T2-Messung (Bump bis Reader-`.onChange` feuert) mit frischer, danach
  wieder vollständig entfernter TEMP-DEBUG-Instrumentierung erneut live
  durchgeführt — diesmal per `computer-use`-Tool selbst durch mehrere
  ungelesene Artikel geklickt statt den Nutzer dafür zu bitten. Zwei saubere
  Messungen (echter Bump, kein bereits-gelesen-No-op): **69ms und 68ms** —
  deckungsgleich mit der nach dem Fix dokumentierten 58-67ms-Spanne, kein
  Rückfall auf die alten ~225ms. Bestätigt: der Sidebar-Async-Fix hält auch
  nach dem Release stand. Nebenbefund beim Aufsetzen der Instrumentierung:
  `log stream` filtert `Logger.debug(...)`-Zeilen standardmäßig heraus,
  auch mit passendem `--predicate`— braucht zusätzlich `--level debug`,
  sonst bleibt der Stream trotz korrekt feuernder Log-Aufrufe leer.

- **2026-08-05: Reader-Ladeverzögerung (~1s bei Artikelauswahl) — TEILWEISE BEHOBEN
  (GRDB DatabaseQueue → DatabasePool), Rest-Ursache identifiziert, Fix für nächste
  Session zurückgestellt.** Nutzer-Report: Artikel erscheint nach Auswahl in der
  Artikelliste erst nach ~1 Sekunde im Reader. Per systematic-debugging mit
  temporärer `OSLog`-Instrumentierung (TEMP-DEBUG-Pattern, `log stream`) live
  gemessen statt geraten — zwei unabhängige Root Causes gefunden und einer davon
  behoben:
  1. **Redundante Dreifach-Ladevorgänge (behoben, Commit siehe unten):**
     `SQLiteReaderState.load(articleID:database:force:)`s Schutzlogik gegen
     SwiftUI-Re-Render-Schleifen erlaubte einen Abbruch+Neustart, sobald ein
     bereits laufender Ladevorgang für dieselbe `articleID` erneut angestoßen
     wurde (`activeLoadTask != nil` im alten Guard) — per Live-Log verifiziert,
     dass bei praktisch jeder Artikelauswahl `.task(id: articleID)` ein zweites
     Mal für dieselbe ID feuerte, während der erste Ladevorgang noch lief, und
     dadurch einen kompletten dritten, redundanten DB-Read+Prepare-Durchlauf
     auslöste. `Task.detached`-Cancellation stoppt eine bereits gestartete
     synchrone GRDB-Abfrage nicht mehr — alle drei Reads liefen tatsächlich zu
     Ende, nur das letzte Ergebnis wurde angewendet. Fix:
     `guard force || loadedArticleID != articleID else { return }` (entfernt
     `activeLoadTask != nil` aus der Bedingung) — ein bereits laufender
     Ladevorgang für dieselbe ID darf jetzt einfach zu Ende laufen statt neu zu
     starten. Reduziert 3 Reads auf 1, hatte für sich allein aber kaum Einfluss
     auf die wahrgenommene Gesamtzeit (~650-750ms statt ~600-950ms) — der
     eigentliche Flaschenhals lag woanders (Punkt 2).
  2. **GRDB `DatabaseQueue`-Read-Kontention (behoben):** Selbst mit nur einem
     Read blieb ein trivialer, indexierter Einzelzeilen-Read
     (`ArticleStore.readerArticle(id:)`, PK-Join über `articles`/`feeds`/
     `article_statuses`) bei ~350-500ms hängen, statt der erwarteten <10ms. Ursache:
     `FeedivoDatabase.open(at:)` nutzte eine GRDB `DatabaseQueue` — eine EINZIGE,
     vollständig serialisierte SQLite-Verbindung, die JEDEN Lese- und
     Schreibzugriff app-weit nacheinander abarbeitet. Markiert der Nutzer beim
     Auswählen einen Artikel als gelesen, löst das
     `SQLiteDataInvalidation.bumpStatusVersion()` aus — die Artikelliste lädt
     sich daraufhin selbst komplett neu (mit 200ms-Debounce,
     `SQLiteFeedArticleListView.swift:1155`), eine deutlich teurere Abfrage als
     der triviale Einzelartikel-Read des Readers, der zur exakt gleichen Zeit in
     derselben Warteschlange steckenblieb. Fix: `DatabaseQueue` durch
     `DatabasePool` ersetzt (`FeedivoDatabase.swift:36`) — aktiviert automatisch
     SQLites WAL-Journal-Modus (verifiziert im lokal ausgecheckten
     GRDB.swift-Quellcode, `DatabasePool.swift`, `setUpWALMode`) und erlaubt
     dadurch mehrere ECHT PARALLELE Lesezugriffe gleichzeitig zu einem laufenden
     Schreibzugriff (WAL-Snapshot-Isolation) — Schreibzugriffe bleiben weiterhin
     serialisiert (ein Writer), nur Reads müssen nicht mehr hintereinander
     warten. Da `FeedivoDatabase` bereits `any DatabaseWriter` kapselt (dem
     gemeinsamen GRDB-Protokoll von `DatabaseQueue` UND `DatabasePool`), musste
     KEIN Aufrufer in Stores/Services angepasst werden — reine, lokal
     eingegrenzte Änderung an zwei Zeilen. `inMemoryForTests()` bleibt bewusst
     auf `DatabaseQueue`: `DatabasePool` benötigt eine echte Datei, da jede
     `:memory:`-Verbindung sonst ihre eigene, isolierte Datenbank wäre (~126
     Testdateien nutzen `inMemoryForTests()`, keine Anpassung nötig). Live
     verifiziert per `lsof` auf den laufenden Prozess: `feedivo.sqlite-wal`/
     `-shm`-Dateien sowie mehrere parallele offene Connections zum
     sandboxed-Container-DB-Pfad bestätigt aktiv. Nach diesem Fix sank die
     eigentliche DB-Read-Zeit auf ~150-200ms, Gesamtzeit bis sichtbarem Artikel
     auf ~415-690ms (vorher ~650-950ms) — vom Nutzer live bestätigt als „viel
     schneller".
  3. **VERBLEIBENDE, NICHT BEHOBENE Restursache (für neue Session
     zurückgestellt):** eine sehr konstante ~220-250ms-Lücke zwischen dem
     Abschluss des Gelesen-Markierens (`ArticleStatusStore.
     updateBooleanStatus`, `bumpStatusVersion()`) und dem Moment, in dem
     IRGENDEINE View auf die Statusänderung reagiert — live zweifelsfrei
     nachgewiesen, dass sowohl die Artikelliste (`.task(id:
     sqliteStatusVersion)`) als auch der Reader (`.onChange(of:
     sqliteStatusVersion)`) exakt zur gleichen Millisekunde feuern, sich also
     NICHT gegenseitig blockieren — beide warten stattdessen auf denselben,
     vorgelagerten Effekt. Bei einem erneuten Auswählen eines BEREITS gelesenen
     Artikels (kein `bumpStatusVersion()`-Aufruf nötig, kein Status-Schreiben)
     sinkt die Gesamtzeit auf ~120-140ms — exakt der erreichbare Bestwert ohne
     diese Lücke. Root Cause: SwiftUIs `@AppStorage`/`UserDefaults`-
     Änderungsbenachrichtigung selbst hat auf diesem System eine konsistente
     ~220-250ms-Latenz, bevor `.onChange`/`.task(id:)`-Observer reagieren —
     vermutlich verschärft durch die Zahl der gleichzeitig auf denselben
     `sqliteStatusVersion`-Key registrierten `@AppStorage`-Beobachter (mindestens
     7 Views app-weit: `ContentView`, `SidebarView`,
     `SQLiteFeedArticleListView`, `SQLiteReaderView`, `ReaderTabBarView`,
     `SettingsView`, `CleanupHistoryWindowView`). **Nächster Schritt (Nutzer-
     Entscheidung: in einer NEUEN Session angehen, nicht in dieser):**
     `SQLiteDataInvalidation` (aktuell `@AppStorage`/`UserDefaults`-basiert) auf
     ein natives `@Observable`-Signal umstellen, das SwiftUIs eigene, deutlich
     schnellere Observation-Machinerie nutzt statt UserDefaults-Notifications.
     **Achtung, großer Umfang:** `bumpStatusVersion()`/`directTagVersionKey` sind
     der zentrale, app-weite Reaktivitätsmechanismus seit dem SwiftData-Ausbau
     (ADR-007) — „Keine @Query/Observation-Automatik — UI-Updates nach
     Mutationen laufen explizit über SQLiteDataInvalidation.
     bumpStatusVersion() + .onChange(...) in den Views" — eine Umstellung
     betrifft potenziell JEDEN Mutations-Pfad der App, nicht nur den Reader.
     Braucht einen eigenen Brainstorming→Spec→Plan-Zyklus, kein Direktfix.
  Betroffene Dateien (Fix, nicht Diagnose): `Feedivo/Database/FeedivoDatabase.swift`
  (`DatabaseQueue` → `DatabasePool`), `Feedivo/ViewModels/SQLiteReaderState.swift`
  (Guard-Fix). Temporäre `PerfDebugTemp.swift`-Instrumentierung (OSLog-Zeitstempel,
  TEMP-DEBUG-Pattern) wieder vollständig entfernt, nie committed. Build + gezielter
  Regressionslauf grün (`FeedivoDatabaseMigratorTests`, `SQLiteDatabaseMigrationTests`,
  `SQLiteArticleDatabaseTests`, `SQLiteArticleStoreTests`, `ArticleStatusStoreTests`,
  `SQLiteArticleStatusStoreTests`, `SQLiteReaderStateTests`, 94/94 Tests). Dabei
  bestätigt: `SQLiteFeedArticleListStateTests` ist bereits auf dem unveränderten
  Baseline-Commit flaky (mehr fehlgeschlagene Tests OHNE diesen Fix als mit) — keine
  neue Regression, siehe bestehender Gotcha-Eintrag zu
  `listStateToggeltReadUndAktualisiertRows`, der offenbar nur die Spitze eines
  größeren, vorbestehenden Flakiness-Problems dieser Suite ist.

- **2026-08-05: Native Artikelliste (NSTableView-Migration) — VOLLSTÄNDIG ABGESCHLOSSEN,
  gemergt nach `main`, gepusht, Standard jetzt AN.** Direkte Folge des Render-Benchmark-
  Spikes vom Vortag (siehe Eintrag darunter) — echte Produktiv-Migration statt reinem
  Prototyp. Sowohl die Hauptartikelliste (`SQLiteFeedArticleListView`) als auch die
  Suchfenster-Ergebnisliste (`ArticleSearchWindowView`) bekommen eine NSTableView-basierte,
  reine-AppKit-Zellen-Implementierung (`Feedivo/Views/ArticleList/Native/`, kein
  `#if DEBUG` — bewusst eigenständiger Code, kein Umbau des Spikes, der unverändert als
  Regressionswächter bestehen bleibt) hinter einem gemeinsamen Settings-Schalter
  (`NativeArticleListSettings`, Tab „Artikelliste"). Umgesetzt via
  Brainstorming→Spec→Plan→Subagent-Driven-Development (9 Tasks), eigener Branch
  `feature/native-article-list-nstableview`, per Fast-Forward nach `main` gemergt. Spec:
  `docs/superpowers/specs/2026-08/2026-08-04-native-article-list-nstableview-design.md`,
  Plan: `docs/superpowers/plans/2026-08/2026-08-04-native-article-list-nstableview.md`.
  **Architekturentscheidung:** reine AppKit-Zellen statt gehosteter SwiftUI-Zeilen
  (`NSHostingView`), um den eigentlichen Performance-Zweck der Migration nicht durch
  erneuten SwiftUI-Render-Overhead pro Zeile zu unterlaufen — Kontextmenüs laufen über
  `NSMenuDelegate` + `tableView.clickedRow`.
  **Drei echte Bugs während der Task-Umsetzung selbst gefunden und behoben** (alle vor
  dem finalen Review): (1) Xcode-Build-Kollision — zwei gleichnamige
  `NativeArticleRowCellView.swift`-Dateien (Spike + neue Produktivklasse) kollidierten
  über identische `.stringsdata`-Zwischendateinamen, unabhängig vom Ordner; Fix: neue
  Klasse in `NativeArticleListRowCellView` umbenannt (Spike blieb unangetastet). (2)
  Crash bei Rechtsklick außerhalb einer Zeile — `NativeArticleListCoordinator.
  rowKind(atRow:)` prüfte nicht auf negative Indizes, `NSTableView.clickedRow == -1`
  führte zu `rows[-1]`; Fix: `guard row >= 0`. (3) Release-Build schlug fehl — die
  wiederverwendete `NativeArticleImageLoadGuard`-Hilfsklasse lag `#if DEBUG`-gated im
  Spike-Ordner, wurde aber von der Produktivzelle unbedingt gebraucht; Fix: eigene,
  nicht-DEBUG-gated Kopie `NativeArticleListImageLoadGuard` in `Native/` (Spike-Ordner
  blieb unangetastet — dieselbe Umbenennungs-Strategie wie bei Fund 1).
  **Finaler Whole-Branch-Review (Opus, mit empirisch kompilierten AppKit-Testprogrammen
  statt reiner Inferenz) fand 2 Critical + 4 Important, alle in einer Fix-Welle behoben
  und unabhängig re-verifiziert:** Kontextmenü crashte bei JEDEM Rechtsklick
  (`NSMenu.addItem` lehnt Items ab, die bereits einem anderen Menü gehören —
  `buildContextMenu` gab ein fertiges `NSMenu` zurück, dessen Items erneut in das echte
  Menü eingefügt wurden; Fix: reiner `contextMenuItems(for:) -> [NSMenuItem]`-Builder);
  deaktivierte Menüeinträge wurden von AppKits `NSMenu.autoenablesItems` (Standard
  `true`) automatisch wieder aktiviert, unabhängig vom manuell gesetzten `isEnabled`
  (Fix: `autoenablesItems = false`); native Hauptliste zeigte KEINEN Leerzustand, wenn
  der Filter (nicht die Suche) null Treffer ergab — ein Analysefehler im Plan selbst
  (`effectiveRows` ≠ `filteredRows`); programmatische Selektions-Synchronisierung
  (`deselectAll`) schrieb `nil` in die SwiftUI-Bindung zurück und konnte dadurch den
  automatischen „nächster Feed mit ungelesenen Artikeln"-Sprung sabotieren (Fix:
  `isApplyingProgrammaticSelection`-Sperre); Return-Taste im Suchfenster öffnete nach
  Pfeiltasten-Navigation den falschen (zuletzt angeklickten, nicht den aktuell
  ausgewählten) Artikel; `state.loadMore()` feuerte synchron während SwiftUIs eigenem
  View-Update-Durchlauf. Re-Review bestätigte alle 9 Findings behoben, keine neue
  Breakage, Spike-Ordner nachweislich unangetastet (`git diff --name-only` geprüft).
  **Nach dem Merge, in derselben Session, vier weitere echte Bugs durch direkte
  Live-Nutzung (Nutzer-Screenshots Alt- vs. Neu-Design) gefunden und sofort behoben**
  (kein neuer Plan-Zyklus, direkte Fixes auf `main`): (1) Titel/Zusammenfassung wurden
  einzeilig abgeschnitten statt mehrzeilig umzubrechen — `titleField`/`summaryField`
  nutzten `.byTruncatingTail` statt `.byWordWrapping`, ein Fehler im ursprünglichen
  Plan-Code selbst, der durch alle Reviews rutschte (`.byTruncatingTail` kürzt nur EINE
  Zeile, bricht nie um). (2) Ungelesen-Punkt saß links am Zeilenanfang statt wie in
  `ArticleRowView` rechts über dem Stern — neue `accessoryStack`-Spalte (Punkt oben,
  Stern unten, dazwischen ein spacer mit niedriger Content-Hugging-Priorität) behebt
  das, zusätzlich Stern-Gelbfärbung, Bild-Platzhalter mit abgerundeten Ecken, Favicon-
  Fallback-Symbol und tertiäre statt sekundäre Zusammenfassungsfarbe bei gelesenen
  Artikeln ergänzt. (3) `NSTableView` zeichnet anders als SwiftUIs `List` standardmäßig
  KEINE Trennlinien zwischen Zeilen — `gridStyleMask = .solidHorizontalGridLineMask` +
  `gridColor = .separatorColor` ergänzt (bisher nur für die Hauptliste, Suchfenster
  noch offen, siehe unten). (4) Die Zusammenfassung zeigte rohe HTML-Tags wie `<p>` —
  die Zelle las `snapshot.summary` direkt aus dem SQL-Snapshot, während der SwiftUI-Pfad
  über `ArticleListItemSnapshot.init` immer durch `ReaderContentRenderer.
  htmlToPlainText` läuft; Fix: dieselbe Umwandlung jetzt auch in der Zelle. Danach noch
  ein reiner Polish-Wunsch umgesetzt: oberer Zeilenabstand von 6pt auf 10pt erhöht
  (`NativeArticleListRowCellView.topInset`/`.extraHeightForTopInset`), ohne die geteilte
  `ArticleRowHeightMetrics` anzufassen (die auch die alte SwiftUI-Liste nutzt).
  **Ergebnis:** Nutzer hat nach Live-Test bestätigt, dass die native Liste „einen
  Unterschied macht" — `NativeArticleListSettings.defaultIsEnabled` von `false` auf
  `true` gestellt, ohne weitere mehrtägige Testphase (ursprünglich in der Spec
  vorgesehen, aber laut Nutzerentscheid nicht mehr nötig). Alte SwiftUI-`List`-
  Implementierung bleibt vollständig als Rückfalloption im Code bestehen (nicht
  gelöscht). Alle 20 Commits (Spec, Plan, 9 Tasks, Fix-Welle, 4 Live-Fixes) gepusht nach
  `origin/main` (`060c8d7..e7025e9`). **Offen:** Trennlinien im Suchfenster (separate
  `NativeArticleSearchResultTableView`-Implementierung) sind noch nicht ergänzt — nur
  auf der Hauptliste gefixt, da nur die dort live getestet wurde; ein paar aus dem
  finalen Review als „ship as-is" triagierte Minor-Funde bleiben bewusst offen (u. a.
  fehlende `isStarred`/`isArchived`-Kontextmenü-Test-Abdeckung, keine rote Einfärbung
  des „Löschen"-Menüeintrags — AppKit-`NSMenuItem` kennt kein `role: .destructive`-
  Äquivalent, kein Test für `NativeArticleSearchResultCellView.configure(...)` selbst).
  **Lehre:** Gleich zwei der insgesamt neun während dieser Session gefundenen Bugs
  (Zeilenumbruch-Modus, fehlende HTML-Umwandlung) waren AppKit/SwiftUI-Parität-Lücken,
  die kein automatisierter Test und kein noch so gründlicher Code-Review (auch nicht der
  mit empirisch kompilierten AppKit-Testprogrammen) aufdecken konnte, weil sie sich nur
  im tatsächlich gerenderten Ergebnis zeigen — bestätigt erneut den bereits mehrfach in
  diesem Dokument festgehaltenen Grundsatz, dass rein visuelle/Rendering-Aspekte einer
  AppKit-Bridge ohne echte Live-Verifikation durch den Nutzer nicht als abgesichert
  gelten dürfen, unabhängig davon, wie viele automatisierte Reviews vorher grün waren.

- **2026-08-04: NSTableView-vs-List-Render-Benchmark — Spike-Infrastruktur UND manuelle
  Live-Verifikation ABGESCHLOSSEN, qualitatives Ergebnis: Prototyp wirkt flüssiger, aber
  OHNE Instruments-Messung (Nutzerentscheid).** Rein `#if DEBUG`-gated, von Produktivcode
  komplett isolierter Prototyp unter `Feedivo/Views/ArticleList/RenderBenchmark/` (+ ein
  kleiner Debug-Fenster/Menüeintrag-Zusatz in `FeedivoApp.swift`), der die aktuelle
  SwiftUI-`List`-Artikelliste einer echten `NSTableView`-Umsetzung nebeneinanderstellt —
  Zweck ist ausschließlich, eine belastbare Entscheidungsgrundlage zu sammeln, ob eine
  künftige Migration der Artikelliste auf AppKit lohnt. Design/Plan:
  `docs/superpowers/specs/2026-08/2026-08-04-nstableview-vs-list-render-benchmark-design.md`,
  `docs/superpowers/plans/2026-08/2026-08-04-nstableview-vs-list-render-benchmark.md`. Alle
  7 Implementierungs-Tasks (synthetisches Fixture, Stale-Load-Guard, native AppKit-Zelle,
  NSTableView-Wrapper+Coordinator, SwiftUI-Baseline+Umschalter, Debug-Fenster+Menüeintrag,
  automatisierte Proxy-Metrik) sind umgesetzt, alle mit sauberen Task-Reviews. Ein
  einzelner headless AppKit-Layout-Test (`FeedivoTests/ArticleListRenderBenchmarkTests.swift`,
  Task 7) dient als reiner Regressions-Wächter für den Prototyp selbst — **kein A/B-Beweis
  gegen die SwiftUI-Baseline**, da `List` ihren internen Render-Server erst mit echtem
  Fenster/Compositor aufbaut und dafür headless nicht fair gemessen werden kann. Gemessener
  Referenzwert (Debug-Build, dieser Rechner): `PERF_METRIC native_table_view_layout_1000_rows
  ≈ 51 ms` bei 1.000 synthetischen Zeilen — weit unter der als reine Absturz-/Hänger-
  Absicherung gedachten 2-Sekunden-Testschwelle, taugt aber ausdrücklich nur als grober
  Anhaltspunkt für die AppKit-Seite, nicht als Vergleichszahl. Nebenfund bei Task 7: der im
  Plan wörtlich vorgegebene Testcode crashte reproduzierbar mit einem vom Main Thread
  Checker erzwungenen `SIGABRT` beim `NSWindow`-Aufbau, da Swift-Testing-`@Test`-Funktionen
  (anders als das alte XCTest) standardmäßig auf einem Hintergrund-Thread laufen und das
  `FeedivoTests`-Target (im Gegensatz zum App-Target) kein
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` gesetzt hat — behoben durch eine zusätzliche
  `@MainActor`-Annotation an der Testfunktion.
  **Finaler Whole-Branch-Review (Opus) fand drei Important-Funde, alle in einer Fix-Welle
  behoben und per Re-Review bestätigt:** (1) `NativeArticleTableViewCoordinatorTests`
  (Task 4) hatte dieselbe `@MainActor`-Lücke wie oben, nur bislang folgenlos, weil der
  Main Thread Checker `NSTableView`-Zugriffe (anders als `NSWindow`) nicht instrumentiert —
  latent, aber real; ergänzt. (2) Die Fixture (Task 1) verwendete unerreichbare
  `https://example.com/...`-Bild-URLs — da `ImageCacheService` Fehlschläge nicht negativ
  cacht, hätte JEDE Zellwiederverwendung beim Scrollen einen erneuten, ewig fehlschlagenden
  Netzwerk-Request ausgelöst, wodurch nie ein Bild sichtbar wurde und die eigentlich zu
  testende Flacker-Hypothese gar nicht beobachtbar gewesen wäre — behoben durch eine einmalig
  zur Laufzeit erzeugte 8×8-PNG-Datei unter einer `file://`-URL. (3) Der native Prototyp
  ignorierte die echten Anzeige-Einstellungen des Nutzers (`interfaceTextSize`,
  `ArticleListImagePosition`, `ArticleListSummaryLineCount`) und nutzte stattdessen feste
  Standardwerte, während die SwiftUI-Baseline (`ArticleRowView`) diese Einstellungen ganz
  normal berücksichtigt — bei Abweichung von den Standardwerten hätten beide Seiten
  unterschiedliche Zeilenhöhen/Schriftgrößen gehabt, was den Vergleich verzerrt hätte;
  behoben, indem `NativeArticleTableView` dieselben Environment-/`@AppStorage`-Werte liest
  und in die Zellen durchreicht. Zusätzlich zwei Minor-Fixes (unnötiges `reloadData()` bei
  reiner Auswahländerung; ein Kommentar-Platzierungsfehler in `FeedivoApp.swift`).
  **Live-Verifikation durch den Nutzer (2026-08-04):** Debug-Build gestartet, Render-
  Benchmark-Fenster über „Ansicht → Render-Benchmark öffnen" geöffnet (Hinweis: Xcodes
  „Product → Profile" baut standardmäßig die Release-Konfiguration, in der der
  `#if DEBUG`-Menüeintrag fehlt — Instruments muss stattdessen an den bereits per ⌘R
  laufenden Debug-Prozess angehängt werden, nicht neu darüber starten), zwischen Baseline
  und Prototyp umgeschaltet und in beiden Varianten gescrollt. **Ergebnis: der
  NSTableView-Prototyp fühlte sich beim Scrollen spürbar flüssiger an als die SwiftUI-
  List-Baseline.** Keine Instruments-Messung durchgeführt — der Nutzer hat den subjektiven
  Eindruck bewusst als für sich ausreichend erklärt, statt die im Design-Dokument als
  primäres Signal vorgesehene Instruments-Zahl noch einzuholen. **Wichtig: Das ist ein
  qualitatives, nicht quantitativ belegtes Positiv-Signal für einen Umstieg — die
  eigentliche Architekturentscheidung (Migration der produktiven Artikelliste auf
  `NSTableView`, ja/nein/Umfang) ist damit NICHT automatisch getroffen**, sondern müsste in
  einem eigenen, neuen Brainstorming/Plan-Zyklus separat entschieden und umgesetzt werden,
  falls gewünscht. Der komplette Spike bleibt bis zu dieser Entscheidung unverändert im
  Code liegen (rückstandsfrei entfernbar: Ordner `Feedivo/Views/ArticleList/RenderBenchmark/`
  + zwei Stellen in `FeedivoApp.swift` + vier Testdateien unter `FeedivoTests/`).

- **2026-08-02: Sparkle-Update-Zyklus erstmals vollständig End-to-End verifiziert
  (Notarisierung, Developer-ID-Signing, SPUStandardUserDriver) — ABGESCHLOSSEN.**
  Direkte Folge-Session zu den 2026-07-31er Sparkle/Homebrew-Grundlagen: der dort
  bewusst offen gelassene "echter Update-Zyklus noch nie live getestet"-Punkt wurde
  in dieser Session vollständig geschlossen, nach einem langen, mehrstufigen
  Live-Debugging-Marathon über den kompletten Vormittag. Ausgangspunkt: Nutzer
  testete "Nach Updates suchen" zum ersten Mal live — Update wurde gefunden,
  Download lief, Installation blieb aber dauerhaft bei "Wird installiert" hängen.
  **Drei voneinander unabhängige, nacheinander gefundene Root Causes, jede einzeln
  live per Unified-Log/codesign/spctl verifiziert:**
  1. **Signing-Pipeline lieferte nie Developer-ID-signierte, notarisierte Releases.**
     `create_github_release.sh` baute bisher mit einfachem `xcodebuild build` statt
     `archive`+`-exportArchive`, wodurch selbst das bereits veröffentlichte,
     offizielle v1.0-16-Release nur mit "Apple Development" signiert und von
     Gatekeeper abgelehnt wurde (`spctl -a -vv` → `rejected`) — ein Problem, das
     auch echte Endnutzer beim ersten Öffnen getroffen hätte, nicht nur Sparkles
     Selbst-Update. Ursache: kein "Developer ID Application"-Zertifikat im
     Schlüsselbund (nur "Apple Development") — der Account hatte zu diesem
     Zeitpunkt gerade erst eine bezahlte Apple-Developer-Program-Mitgliedschaft
     erhalten. Nutzer erstellte das Zertifikat live über Xcodes Accounts-UI.
     `create_github_release.sh` umgestellt auf `archive` + `-exportArchive`
     (`method: developer-id`, neue `scripts/release_export_options.plist`) +
     `notarytool submit --wait` + `stapler staple`, jeweils VOR dem Verteil-Zip.
     Unterwegs zwei weitere, eigenständige Blocker gefunden und behoben: fehlendes
     lokales Provisioning-Profil (brauchte einmaligen Xcode-GUI-Archive-Durchlauf,
     neues Profil lag am neueren Xcode-Speicherort, musste an den klassischen für
     Kommandozeilen-Exports kopiert werden) und eine versehentlich durch
     Capability-Toggling in Xcode geleerte iCloud-Container-Zuordnung in gleich
     ZWEI Entitlements-Dateien (Debug + der dabei neu entstandenen
     `FeedivoRelease.entitlements`) — beide wiederhergestellt.
  2. **`notarytool --keychain-profile` versagt spezifisch bei Ausführung aus einer
     Skriptdatei, nicht bei interaktiven Aufrufen** (siehe neuer Gotcha oben) —
     durch eine lange Kette einzeln widerlegter Hypothesen isoliert (Smart Quotes,
     Warp- vs. Terminal.app-Unterschiede, Session-Scoping, versteckte
     Autorisierungs-Dialoge — alle einzeln per Log/Kontrollversuch ausgeschlossen),
     bis eine minimale, isolierte Reproduktionsdatei den Unterschied klar zeigte:
     inline getippt → Erfolg, als `.sh`-Datei ausgeführt → zuverlässig derselbe
     Fehler. Fix: Umstellung von `--keychain-profile` auf App-Store-Connect-API-Key-
     Authentifizierung (liest nur eine `.p8`-Datei, kein Keychain-Zugriff mehr
     nötig) — dieselbe Methode, die Apple für CI/Automatisierung selbst empfiehlt.
  3. **Der eigentliche Installations-Hänger war ein Architektur-Problem im eigenen
     Code, kein Signing-/Notarisierungs-Thema mehr** — siehe ADR-010 oben für die
     volle Herleitung. Kurzfassung: eigenes SwiftUI-`.sheet` blockierte AppKits
     automatische App-Terminierung während Sparkles Installationsschritt
     ("App termination blocked by modal sheet", live im Unified Log). Zwei
     aufeinanderfolgende, gezielte Detail-Fixes (State-Ausschluss von
     `.installing`, dann ein synchroner direkter `NSWindow.endSheet(_:)`-Aufruf)
     linderten das Symptom nur graduell (Dateitausch gelang, Neustart blieb
     unzuverlässig) — erst der Architektur-Wechsel auf Sparkles eigenen
     `SPUStandardUserDriver` (exakt nach dem Vorbild von NetNewsWires echter
     Produktions-Codebase, lokal unter `/Users/martinfelder/Developer/
     NetNewsWire-main` verglichen) behob es beim ersten Versuch vollständig.
  **Ergebnis:** v1.0-21 ist der erste Release, bei dem der komplette Zyklus
  (Appcast-Fund → Download → Notarisierungs-/Gatekeeper-Prüfung → Installation →
  App-Terminierung → Dateitausch → automatischer Neustart als neue Version) vom
  Nutzer live am eigenen Mac bestätigt vollständig funktioniert hat — bislang
  ausschließlich `/Applications`-Installation getestet (kein Homebrew-Cask-Zyklus
  in dieser Session). `SparkleUpdateCoordinator` ist dadurch strukturell deutlich
  kleiner geworden (kein eigener State/Continuation-Code mehr), `UpdateAvailableSheet`/
  `UpdateUpToDateSheet`/`SparkleUpdateState`/`SparkleReleaseInfo` komplett entfernt.
  Alle Commits auf `main`, gepusht. M3-Milestone-Checkbox zu Sparkle/Update bleibt
  unangetastet (betrifft primär iCloud Sync, nicht App-Update), aber der lange
  offene "echter Update-Zyklus ungetestet"-Punkt aus dem 2026-07-31er Eintrag ist
  hiermit geschlossen.

- **2026-07-31: Sparkle-Update + Homebrew-Vertrieb — VOLLSTÄNDIG ABGESCHLOSSEN, Debug- und
  Release-Build grün, gezielter Testlauf grün, echte Live-Verifikation eines Update-Zyklus
  NOCH AUSSTEHEND.** Ersetzt den kompletten Eigenbau-Update-Installer durch Sparkle 2.9.4
  und ergänzt Homebrew Cask als zweiten Vertriebskanal — Details/Begründung
  (App-Sandbox-Quarantäne-Root-Cause) siehe ADR-009 und der neue Gotcha dazu oben. 14-Task-
  Plan via Brainstorming→Spec→Plan→Subagent-Driven-Development, alle Commits bereits auf
  `main`.
  - **Automatisiert abgeschlossen und verifiziert:** Task 1 (Sparkle-SPM-Paket, manueller
    pbxproj-Edit an 6 Stellen), Task 3 (`SUFeedURL`/`SUPublicEDKey`/
    `SUEnableInstallerLauncherService` in Info.plist, mach-lookup-Entitlement-Ausnahme —
    die App-Sandbox selbst bleibt unangetastet), Task 4
    (`HomebrewInstallationDetector.isHomebrewCaskInstall(bundleURL:)`, TDD), Task 5
    (`docs/appcast.xml`, ausgeliefert über `raw.githubusercontent.com` — die CDN-
    Propagierung brauchte nach dem ersten Push ein paar Minuten und lieferte kurzzeitig
    404, erwartetes Verhalten, kein Bug), Task 6 (neue reine Werttypen
    `SparkleUpdateState`/`SparkleReleaseInfo` statt `GitHubRelease`/`UpdateInstallState`),
    Task 7 (`SparkleUpdateCoordinator` als `SPUUserDriver` — das tatsächlich installierte
    Sparkle 2.9.4 verlangte 3 Methoden mehr als der ursprüngliche Plan-Entwurf annahm,
    gegen den echten installierten `SPUUserDriver.h`-Header verifiziert, nicht nur aus
    einem Build-Fehler geraten; **hier auch ein Critical-Fund, siehe neuer Gotcha zu
    plan-autorierten Bugs oben**), Task 8 (`FeedivoApp.swift` umgestellt — Implementierer
    wich bewusst von der geplanten wörtlichen `.sheet`/`.alert`-Inline-Kette ab und
    extrahierte einen `SparkleUpdatePresentationModifier: ViewModifier`, da die geplante
    Inline-Fassung einen echten, reproduzierten Swift-Typchecker-Timeout auslöste — als
    verhaltensgleich verifiziert), Task 9 (`UpdateAvailableSheet`/`AboutSettingsView`/
    `UpdateUpToDateSheet` umgestellt, neuer `L10n.updateCheckHomebrewHint`-Key; der
    `.updateAvailable`-Primärbutton ruft bewusst `coordinator?.installUpdate()` auf, nicht
    `checkForUpdatesManually()` — nur das löst die in Task 7 gefixte Continuation korrekt
    aus), Task 10 (11 Produktions- + 7 Testdateien des alten Eigenbau-Stacks vollständig
    gelöscht, `UpdateCheckSettings.swift` bewusst erhalten — wird weiterhin für den
    Automatisch-prüfen-Schalter gebraucht), Task 11 (`scripts/create_github_release.sh`
    signiert Releases jetzt mit `sign_update` und pflegt `docs/appcast.xml` — **zweiter
    Critical-Fund, siehe neuer Gotcha oben**, zusätzlich eine Absicherung gegen einen
    stillen Pipeline-Fehlschlag ergänzt, falls sich `sign_update`s Ausgabeformat je
    ändert), Task 13 (Release-Skript aktualisiert bei jedem künftigen Release zusätzlich
    die Cask-Formel im Tap-Repo, eigenes Bestätigungsgate getrennt von Task 11s;
    gezielt auf dieselbe Variablen-Lebenszyklus-Bugklasse wie Tasks 7/11 re-geprüft —
    hier keine gefunden). Alle drei projektspezifischen neuen Testsuiten
    (`HomebrewInstallationDetectorTests`: 4 Tests, `SparkleReleaseInfoTests`: 2 Tests)
    plus die unverändert bestehende `UpdateReleaseNoteCategorizerTests` (6 Tests) grün,
    12/12 insgesamt. Debug- UND Release-Build grün (Task 14, dieser Eintrag). Grep-
    Kontrolle bestätigt: keine Code-Referenzen auf `UpdateInstaller`/
    `GitHubReleaseCheckService`/`UpdateChecker` mehr — die drei verbleibenden Treffer sind
    ausschließlich erklärende Kommentare, die den entfernten Alt-Stack als historischen
    Kontext benennen.
  - **Manuell durchgeführt und vom Nutzer/Controller bestätigt:** Task 2
    (EdDSA-Signierschlüsselpaar per Sparkles `generate_keys`, lief unerwartet ohne
    GUI-Prompt durch — Public Key `tMoZQKDmZhEFAyf8qPNY2bW22SYHEippirJTrOy4Si0=`, privater
    Schlüssel im Login-Keychain bestätigt, korrekterweise nirgends committed). Task 12
    (neues öffentliches Repo `martinfelder/homebrew-feedivo` nach expliziter
    Nutzerbestätigung angelegt, `Casks/feedivo.rb` mit der echten v1.0-15-Version/SHA256/
    URL befüllt — **vollständiger echter End-to-End-Zyklus auf diesem Rechner
    durchgeführt und unabhängig bestätigt:** `brew tap` → `brew install --cask feedivo` →
    `brew audit --cask feedivo` (sauber, keine Funde) → `brew uninstall --cask feedivo` →
    `brew untap`, danach die bereits vorhandene entwicklerseitige `/Applications/
    Feedivo.app` (Build 14) unverändert wiederhergestellt. Zwei reine
    Umgebungs-Eigenheiten dabei notiert, kein Code-Änderungsbedarf: Homebrews
    Tap-Trust-on-first-use-Abfrage (lokal, pro Nutzer, einmalig) und eine bereits
    vorhandene Dev-Build-App am Installationsziel (von Homebrews eigener
    „existiert bereits"-Ablehnung korrekt abgefangen, erwartetes Verhalten).
  - **Weiterhin unverifiziert, explizit nicht Teil dieses Plans/dieser Session:** ein
    echter, kompletter Sparkle-Update-Zyklus (echter Download → echte Installation →
    echter Neustart über die neue Version) wurde NICHT durchgeführt — bislang
    ausschließlich build-/unit-test-verifiziert plus der eine echte
    `brew install --cask`-Zyklus oben. Ebenso unverifiziert: dass ein per Homebrew
    installierter Nutzer tatsächlich NIE einen In-App-Update-Prompt sieht (die
    `HomebrewInstallationDetector`-Gate-Logik selbst ist per TDD abgesichert, aber nicht
    live gegen eine echte Cask-Installation der laufenden App durchgespielt). Dieselbe
    Kategorie „manuelle Live-Verifikation ausstehend, braucht ein echtes Zweitszenario"
    wie bei etlichen früheren Features in diesem Dokument (z. B. iCloud Sync Pull-
    Richtung) — nicht simulierbar, nicht vorgetäuscht.

- **2026-07-26 (Folge-Session): iCloud Sync Phase 3 (Feld-Ebene-Konfliktauflösung +
  Erst-Aktivierungs-Merge-Dialog) — VOLLSTÄNDIG ABGESCHLOSSEN, automatisierte Tests grün,
  Release-Build grün, Live-Verifikation NOCH AUSSTEHEND.** Baut auf dem in Phase 1/2a/2b
  etablierten `CKSyncEngine`-Fundament auf und schließt zwei in der ursprünglichen
  Planung bewusst zurückgestellte Lücken: (1) bisher war JEDE Konfliktauflösung reines
  Last-Write-Wins auf ganzer-Datensatz-Ebene — ein Konflikt zwischen zwei Geräten verlor
  immer die komplette Änderung der unterlegenen Seite, selbst wenn beide Seiten
  unterschiedliche, nicht überlappende Felder geändert hatten; (2) eine Erst-Aktivierung
  von iCloud Sync auf einem Gerät mit bereits vorhandenen lokalen Tags/Ordnern und einem
  bereits zuvor synchronisierten zweiten Gerät konnte gleichnamige, aber ID-verschiedene
  Duplikate erzeugen, ohne dass der Nutzer je darauf hingewiesen wurde. Umgesetzt via
  Brainstorming→Spec→Plan→Subagent-Driven-Development (15 Tasks), Spec:
  `docs/superpowers/specs/2026-07-26-icloud-sync-phase3-design.md`, Plan:
  `docs/superpowers/plans/2026-07-26-icloud-sync-phase3.md`.
  - **Feld-Ebene-Konfliktauflösung (Tasks 1–10):** Task 1 macht Bedingungs-IDs
    (`RuleCondition`/`SmartFolderCondition`) über einen Speicher-Lade-Speicher-Zyklus
    stabil (Voraussetzung für sinnvolles Feld-Diffing auf Bedingungsebene, siehe
    dokumentierte Limitation weiter unten) — reine Code-Änderungen, keine Migration.
    Migration v27 legt das `changedFields`-Feld auf `cloud_sync_pending_changes` an (Task 2),
    Migration v28 legt eine neue `PendingSyncConflictStore`-Tabelle an. Jeder `CloudSyncRecordMapping`-Typ bekommt eine
    neue `askFields`/`autoFields`-Policy (welche Felder bei einem Konflikt den Nutzer
    fragen vs. automatisch zusammenführen) — für Tag, FeedFolder, Feed, Rule, SmartFolder
    und ArticleStatus. `CloudSyncEngine.handleFailedSave` komplett neu geschrieben: statt
    reinem Server- oder Client-Wins vergleicht es jetzt Feld für Feld anhand eines neuen
    `changedFields`-Trackings (JSON-Array, das `TagStore`/`FeedFolderStore`/`FeedStore`/
    `SQLiteRuleStore`/`SQLiteSmartFolderStore` bei jeder Mutation zusätzlich zur
    Pending-Change-Warteschlange mitschreiben — z. B. markiert `renameFolder` NUR `name`
    als geändert, `moveFolder`/`sortAlphabetically` NUR `sortIndex`); automatisch
    zusammenführbare Felder (`autoFields`) werden ohne Rückfrage gemerged, für
    `askFields`-Felder mit echtem Konflikt entsteht ein `PendingSyncConflictRecord` zur
    späteren Nutzerentscheidung. Task 5 durchlief 3 Fix-Runden — u. a. wurde eine
    "Server gewinnt"-Entscheidung durch ein erneutes lokales Senden stillschweigend
    wieder überschrieben, bevor der Fix (`applyIncomingRecord(mergedRecord)` zusätzlich
    lokal anwenden) das behob.
  - **Konflikt-UI (Task 11):** neue `SyncConflictResolutionView` + ein Konflikte-Badge
    in `SyncSettingsView` — zeigt jeden offenen `askFields`-Konflikt mit dem tatsächlichen
    Anzeigenamen des betroffenen Datensatzes (Tag-/Feed-/Ordner-/Regel-/Smart-Folder-Name,
    bei Bedingungszeilen der Name des übergeordneten Datensatzes) statt nur dem rohen
    `recordType` (Fix-Round-Finding — war im Implementierungsplan selbst so
    vorgeschrieben, widersprach aber der eigentlichen Design-Spec; Nutzerentscheid:
    sofort fixen statt dokumentieren).
  - **Erst-Aktivierungs-Duplikat-Erkennung + Merge (Tasks 12–14):** neuer
    `CloudSyncFirstActivationAnalyzer` (rein lesend, keine Seiteneffekte) erkennt
    Groß-/Kleinschreibungs-unabhängige Namens-Duplikate zwischen lokalen und bereits in
    CloudKit vorhandenen Tags/FeedFolders; `CloudSyncFirstActivationMerger` bietet pro
    Duplikat „Zusammenführen" (PK-Rename der lokalen Zeile auf die Cloud-ID unter
    `PRAGMA defer_foreign_keys = ON`, dedupe-geschütztes Nachziehen aller
    `article_tags`/`feed_tags`-Zuordnungen in einer Transaktion — der ursprünglich vom
    Plan wörtlich vorgeschlagene FK-Remap-Code war nachweislich fehlerhaft, unter diesem
    Projekts `PRAGMA foreign_keys = ON` reproduzierbar ein echter SQLite-Fehler 19, vom
    Implementierer selbst noch vor dem Review gefunden und ersetzt) oder „Beide
    behalten"; `CloudSyncFirstActivationView` verdrahtet beides in den Sync-Toggle.
  - **Zwei CRITICAL-Funde im Task-14-Review — die schwerwiegendsten des gesamten
    15-Task-Plans, sofort gefixt, Commit `1a01ca65`:** (1) eine echte
    Datenverlust-Falle durch fehlende Selbst-Kollisions-Ausschluss beim erneuten
    Aktivieren von Sync, (2) eine Start-Reihenfolge-Lücke, die das komplette
    Erst-Aktivierungs-Gate umgehen konnte, falls die App beendet wurde, während der
    Merge-Dialog noch offen war. Beide Details siehe neuer Gotcha oben
    („Kollisions-/Duplikaterkennung..."). Bemerkenswert: Tasks 12 UND 13 hatten jeweils
    einen eigenen, saubere Task-Review (0 Findings, keine Fix-Runde) — der Fehler war
    nur aus der Verdrahtungsperspektive von Task 14 sichtbar, nicht aus der isolierten
    Analyzer-/Merger-Logik selbst.
  - **Bewusste, dokumentierte Limitation (KEIN Bug):** `RuleCondition`/
    `SmartFolderCondition`-Zeilen werden bei jedem Speichern der übergeordneten
    Rule/SmartFolder komplett gelöscht und neu eingefügt — kein Task in diesem Plan
    verdrahtet `changedFields`-Tracking für diese Kind-Zeilen. Die in Task 3 definierte
    `askFields`/`autoFields`-Policy für `RuleCondition`/`SmartFolderCondition` ist dadurch
    aktuell unerreichbarer Code — Bedingungszeilen fallen bei einem Konflikt weiterhin auf
    das alte, ganze-Zeile-Last-Write-Wins zurück statt auf Feld-Ebene zu mergen. Sicher
    (kein Datenverlust), nur weniger granular. Siehe auch „Offene Entscheidungen".
  - **Task 15 (dieser Eintrag) deckt nur die automatisierbaren Abschlussschritte ab:**
    gezielter Testlauf über alle 24 in diesem Plan berührten/neuen Suiten (aufgeteilt in
    3 `xcodebuild test`-Aufrufe zur Übersichtlichkeit, alle 24 `-only-testing:`-Flags
    wurden korrekt berücksichtigt — keine Suite fehlte in den drei Teilläufen), 48+47+94
    = 189/189 Tests grün, sowie ein voller `xcodebuild build -configuration Release`
    (BUILD SUCCEEDED). Die bereits bekannten, vorbestehenden 17 Fehlschläge in
    `FeedivoAppSceneConfigurationTests.swift` und die 2-3 flaky-unter-Last-Tests waren
    laut Plan bewusst NICHT Teil dieser gezielten Suiten-Auswahl — diese Session macht
    keine Aussage über deren aktuellen Status.
  - **Weiterhin unverifiziert (nicht automatisierbar in dieser Umgebung):** Feld-Ebene-
    Konfliktauflösung UND Erst-Aktivierungs-Kollisionserkennung sind ausschließlich gegen
    In-Memory-GRDB-Datenbanken und gemockte `CKRecord`-Objekte getestet — nie gegen einen
    echten `CKContainer`/zwei echte Geräte. Für eine echte Live-Verifikation bräuchte es
    entweder ein zweites Testgerät (für einen echten, gleichzeitig auf beiden Seiten
    laufenden Feld-Konflikt) oder ein CloudKit-Dashboard-seitig manuell angelegtes
    Namens-Duplikat (für die Erst-Aktivierungs-Kollisionserkennung). Ebenso
    unverifiziert: sämtliches visuelles/interaktives SwiftUI-Verhalten der drei neuen
    Views (`SyncConflictResolutionView`, `CloudSyncFirstActivationView`, das neue
    Konflikte-Badge) — kein computer-use für native macOS-Apps in dieser Umgebung
    verfügbar. M3-Checkbox „iCloud Sync via CloudKit" bleibt deshalb weiterhin offen
    (Phase 4 — Härtung — steht als eigener, noch nicht begonnener Zyklus aus).

- **2026-07-26: Live-Verifikation iCloud Sync Phase 2a/2b (Push-Richtung) gegen echtes
  CloudKit-Dashboard — ERSTMALS DURCHGEFÜHRT, ALLE VIER GEPRÜFTEN RECORD-TYPES BESTÄTIGT.**
  Bisher war die Push-Richtung für Phase 2a/2b ausschließlich über automatisierte Tests
  abgesichert (siehe Einträge unten) — dieser Durchgang war die erste tatsächliche
  Live-Verifikation gegen den echten CloudKit-Server (Development-Environment, Zone
  `FeedivoZone`, Container `iCloud.ch.martin.Feedivo`). Vorgehen: aktueller `main`-Stand
  gebaut (`xcodebuild -scheme Feedivo -configuration Debug build`, BUILD SUCCEEDED) und
  gestartet, dann live in der laufenden App: einen Artikel als gelesen markiert, einen
  zweiten mit Stern versehen, einen neuen Feed abonniert und umbenannt
  („ZZZ-SyncTest-Feed"), über den Feed-Menüpunkt „Verwaltung…" einen benutzerdefinierten
  Intelligenten Ordner mit Bedingung sowie eine Regel mit Bedingung + Tag-Zuweisung
  angelegt. Direkt im Anschluss im CloudKit-Dashboard „Logs"-Tab nachgeprüft (die im
  Records-Browser dokumentierte „Field 'recordName' is not marked queryable"-Eigenheit
  trat auch hier wieder auf — Verifikation deshalb bewusst über den zuverlässigeren
  Logs-Tab statt Records-Browser, siehe Gotcha zu Dashboard-Tooling weiter unten). Vier
  frische `RecordSave`-Events mit `overallStatus: SUCCESS`, jeweils zeitlich exakt passend
  zur ausgelösten App-Aktion, bestätigten die Push-Richtung erstmals live für genau die
  Record-Types, die bisher nur automatisiert getestet waren: `Feed` (mehrere Saves,
  Anlegen + Umbenennen), `RuleCondition` (`recordInsertCount: 5`), `SmartFolderCondition`
  (`recordInsertCount: 4`, `recordUpdateCount: 1`), `ArticleStatus` (`recordInsertCount: 3`
  — Gelesen- und Stern-Markierung). Die Sync-Status-Übersicht in den Einstellungen zeigte
  während des gesamten Durchgangs durchgehend „Synchron" mit aktuellem Zeitstempel.
  **Bewusst nicht abgedeckt in diesem Durchgang** (Zeit-/Kostengründe dieser Session,
  keine technischen Blocker): `FeedFolder`-Push separat (Ordner-Anlage über das
  Kontextmenü der Sidebar bot in dieser Session keine direkte „Neuer Ordner"-Option an —
  Feed-Push ist aber strukturell identisch, gilt als indirekt mitverifiziert),
  Löschpropagierung (nur Anlegen/Ändern getestet, kein Löschen), tatsächliche Ausführung
  von Soft-/Hard-Reset (nur UI-Sichtbarkeit der Buttons bestätigt, siehe Sync-Tab-
  Screenshot), sowie die Pull-Richtung (weiterhin app-weit ungetestet, braucht ein
  zweites Gerät). **Ergebnis:** Push-Richtung für alle in Phase 2a/2b neu hinzugekommenen
  Tabellen ist damit erstmals nicht mehr nur testabgesichert, sondern live gegen den
  echten CloudKit-Server bestätigt.
- **2026-07-26 (direkte Folge-Session): Live-Verifikation Löschpropagierung gegen echtes
  CloudKit-Dashboard — ERSTMALS DURCHGEFÜHRT UND BESTÄTIGT.** Direkter Anschluss an den
  obigen Push-Verifikations-Durchgang, deckt die dort offen gelassene Lücke. In der
  laufenden App: den zuvor angelegten Test-Feed („ZZZ-SyncTest-Feed"/„Apple Newsroom",
  siehe Nebenfund unten) gelöscht (nachdem zuvor ein Artikel daraus als gelesen + mit
  Stern markiert wurde, um einen zugehörigen `ArticleStatus`-Datensatz zu erzeugen), dann
  die Test-Regel „ZZZ-SyncTest-Rule" über die Organizer-Verwaltung sowie den
  Test-Smart-Folder „ZZZ-SyncTest-SmartFolder" über das Sidebar-Kontextmenü gelöscht. Alle
  drei Löschungen erzeugten je einen frischen `RecordDelete`-Log-Eintrag mit
  `overallStatus: SUCCESS` und exakt `recordDeleteCount: 2` — passend zum erwarteten
  Eltern+Kind-Kaskadenmuster: Feed-Löschung → `Feed` + propagierter `ArticleStatus`;
  Regel-Löschung → `Rule` + `RuleCondition`; Smart-Folder-Löschung → `SmartFolder` +
  `SmartFolderCondition`. Damit ist auch die Löschpropagierung (nicht nur Anlegen/Ändern)
  für alle drei getesteten Pfade live gegen den echten CloudKit-Server bestätigt.
  **Nebenfund (dokumentiert, nicht weiter verfolgt):** Der zuvor manuell umbenannte
  Test-Feed zeigte beim erneuten Ansehen (~1 Std. später) wieder seinen ursprünglichen
  Titel „Apple Newsroom" statt „ZZZ-SyncTest-Feed" — „Original Titel" und URL in den
  Feed-Eigenschaften bestätigten, dass es derselbe Feed war (keine Dublette). Zeitlich
  passend zu einem zwischenzeitlich gelaufenen automatischen Refresh-Zyklus (Feed-Log
  zeigte bereits 5 Einträge) — spricht dafür, dass ein regulärer Feed-Refresh den
  manuell gesetzten Titel überschreibt, nicht für einen iCloud-Sync-Fehler. Nicht
  root-caused, keine Reproduktion mit exaktem Zeitpunkt — falls das erneut aussagekräftig
  beobachtet wird, als eigenen Bug-Report mit systematic-debugging aufgreifen statt hier
  weiterzuspekulieren.
- **2026-07-25 (Folge-Session): iCloud Sync zurücksetzen (Soft-/Hard-Reset-UI) — VOLLSTÄNDIG
  ABGESCHLOSSEN, gepusht.** Neuer Bereich in den Sync-Einstellungen: „Sync zurücksetzen"
  bietet einen Soft-Reset (nur lokale Sync-Metadaten/Warteschlange leeren, nächster Sync
  synct alles neu ab) und einen Hard-Reset (zusätzlich die komplette CloudKit-Zone
  `FeedivoZone` serverseitig löschen — für den Fall, dass der Cloud-Zustand selbst
  kaputt/inkonsistent ist). Umgesetzt via Brainstorming→Spec→Plan→Subagent-Driven-
  Development (4 Tasks): Task 1 `deleteAll()`-Primitiven auf den relevanten Pending-
  Change-/Mapping-Stores, Task 2 `CloudSyncEngine.resetLocalState()` (Soft Reset),
  Task 3 `CloudSyncEngine.resetCloudZoneAndLocalState()` (Hard Reset), Task 4 L10n-Keys
  + UI-Anbindung. Whole-Branch-Review fand mehrere Findings, direkt gefixt: ein
  Cache-Leak (`knownServerRecordsByID` wurde beim Reset nicht geleert — ein
  Hard-Reset hätte dadurch stale Server-Record-Referenzen überlebt), ein fehlendes
  Gate gegen einen Hard-Reset während eines laufenden Syncs, eine veraltete
  Pending-Anzeige nach dem Reset, eine `wasRunning`-Race beim Neustart des
  `CKSyncEngine` nach dem Reset, sowie veraltete Reset-Erfolgsmeldungen im UI. Spec/
  Plan: `docs/superpowers/specs/2026-07-25-icloud-sync-reset-design.md`,
  `docs/superpowers/plans/2026-07-25-icloud-sync-reset.md`. Commits `26bc06b7..
  a1ab3f02` auf `main`, gepusht. Ausstehend: manuelle Live-Verifikation (Soft-Reset
  dann erneuter Sync, Hard-Reset dann Zone im CloudKit-Dashboard tatsächlich
  leer/neu angelegt).
- **2026-07-25: iCloud Sync Phase 2b (Artikelstatus-Sync — Gelesen/Stern) — VOLLSTÄNDIG
  ABGESCHLOSSEN inkl. kritischem Nachfolge-Fix, gepusht.** Erstmals wird auch der
  Lese-/Stern-Status einzelner Artikel über `CKSyncEngine` synchronisiert (bisher nur
  Tags/Feeds/Ordner/Regeln/benutzerdefinierte Intelligente Ordner). Spec/Plan:
  `docs/superpowers/specs/2026-07-25-icloud-sync-phase2b-design.md`,
  `docs/superpowers/plans/2026-07-25-icloud-sync-phase2b.md`. Umgesetzt via
  Brainstorming→Spec→Plan→Subagent-Driven-Development (10 Tasks: Migration v24
  `statusSyncUpdatedAt`, Migration v25 + `OrphanedArticleStatusUpdateRecord`/-Store,
  `CloudSyncArticleStatusMapping` + Registry-Eintrag, `ArticleStatusStore` markiert
  Gelesen/Stern-Änderungen als sync-relevant, Reconciliation-Hook für verwaiste
  Artikelstatus in `ArticleStore.upsert`, Bereinigung alter verwaister Updates in
  `runAutomaticCleanup`, Löschpropagierung bei Retention-Cleanup/Einzel-Artikel-
  Löschung/Feed-Löschung-Kaskade, Task 10 voller Regressionslauf + Release-Build ohne
  eigenen Diff). **Kritischer, erst im Whole-Branch-Review gefundener
  Architekturfehler:** `article_statuses.articleID` ist pro Gerät zufällig (jedes
  Gerät entdeckt denselben RSS-Artikel unabhängig per eigenem Feed-Refresh und vergibt
  eine eigene `UUID().uuidString`) — der ursprüngliche `CloudSyncArticleStatusMapping`
  keyte den `CKRecord` direkt über diese lokale ID, wodurch ein von Gerät A
  hochgeladener Status auf Gerät B NIE gefunden werden konnte. Details, Root Cause und
  alle drei Teilfunde (Mapping selbst, `enqueuePendingSync` blieb auf der alten ID
  hängen, `applyIncomingDeletion` nullte `syncStableID`) siehe Gotcha
  „`article_statuses.articleID` ist pro Gerät zufällig" oben. Behoben in einem
  eigenen Stable-Identity-Fix-Nachfolgeplan (Tasks 11–13,
  `docs/superpowers/plans/2026-07-25-icloud-sync-phase2b-stable-identity-fix.md`):
  neue `syncStableID` (SHA256-Hash aus `feedID`+`sourceID`/`link`/`titleHash`),
  Migration v26 backfillt Bestandszeilen per Swift-Loop. Tests grün (mit dem bereits
  bekannten, vorbestehenden Flaky-Test `listStateToggeltReadUndAktualisiertRows` als
  einzigem Ausreißer, siehe bestehender Gotcha-Eintrag zu bekannten
  Vorabfehlschlägen), Release-Build grün. Commits `6ca98a4b..a9c36107` auf `main`,
  gepusht. **Ausstehend:** Live-Verifikation gegen echtes CloudKit (Push-Richtung),
  Pull-Richtung app-weit weiterhin ungetestet mangels Zweitgerät.
- **2026-07-24 (weitere Folge-Session): iCloud Sync Status-Übersicht + Konfliktauflösungs-Fix —
  BEIDE VOLLSTÄNDIG ABGESCHLOSSEN UND NACH `origin/main` GEPUSHT (`1c6cc393..d55da333`).**
  Zwei zusammenhängende Durchgänge in derselben Session:
  1. **Sync-Status-Übersicht** (neuer Block im Sync-Tab: globale Statuszeile
     "Synchron"/"Ausstehend (N)"/"Fehler: …" + Zeitpunkt, aufklappbare Aufschlüsselung nach
     Datenart) — via Brainstorming→Spec→Plan→Subagent-Driven-Development (5 Tasks + ein
     Whole-Branch-Review-Fix-Durchgang: stale Pending-Count nach erfolgreichem Sync, fehlende
     Statusfarbe laut Spec, "Synchron" fälschlich vor dem allerersten Lauf, stille
     Fehlerbehandlung). Neue Typen: `CloudSyncActivityStatus` (persistent, UserDefaults),
     `CloudSyncActivityCategory` (7 rohe recordTypes → 5 Anzeige-Kategorien),
     `CloudSyncPendingChangeStore.pendingCounts()`. Spec:
     `docs/superpowers/specs/2026-07-24-icloud-sync-status-uebersicht-design.md`, Plan:
     `docs/superpowers/plans/2026-07-24-icloud-sync-status-uebersicht.md`.
  2. **Live-Testen dieser neuen Übersicht deckte zwei echte, vorbestehende Bugs auf** (kein
     Zusammenhang mit der neuen UI selbst, beide aus Phase 1/2a geerbt):
     - Ein `CKSyncEngine`-Reentrancy-Absturz (`Fatal error: BUG IN CLIENT OF CLOUDKIT`), wenn
       `notifyPendingChangesAvailable`s manueller `sendChanges()`-Aufruf aus dem
       Konfliktauflösungspfad (`handleFailedSave`, selbst innerhalb des
       `CKSyncEngineDelegate`-Callbacks) heraus lief — Fix: `Task.detached` statt `Task {}`,
       siehe neuer Gotcha oben. Direkt gefixt, gepusht.
     - Ein tieferliegender Konfliktauflösungs-Bug: `makeCKRecord(fromLocalID:database:)` baute
       bei JEDEM Sendeversuch ein jungfräuliches `CKRecord` ohne Server-Systemfelder — jeder
       bereits serverseitig existierende Datensatz (94 Stück live per SQLite-Abfrage verifiziert)
       scheiterte dadurch garantiert und dauerhaft mit `.serverRecordChanged` ("record to insert
       already exists"). Zusätzlich dequeued `handleFailedSave` nie bei "Server gewinnt", und
       `.sentRecordZoneChanges` löste pro Konflikt einen eigenen `sendChanges()`-Aufruf aus
       (plausible Mit-Ursache einer live beobachteten CloudKit-429-Drosselung). Eigener
       Brainstorming→Spec→Plan→Subagent-Driven-Development-Zyklus (2 Tasks): `existing:
       CKRecord?`-Parameter durch alle 7 `CloudSyncRecordMapping`-Typen durchgereicht (der dafür
       bereits vorbereitete, aber nie genutzte Parameter auf `makeCKRecord(from:existing:)`),
       neuer In-Memory-Cache `knownServerRecordsByID` in `CloudSyncEngine`, `applyIncomingRecord`/
       `handleFailedSave` liefern jetzt `Bool`, gebündelter Resend-Trigger. Whole-Branch-Review
       (Opus): "Ready to merge: Yes", 0 Critical/Important — verifizierte die komplette
       Cache→`existing:`-Datenflusskette Ende-zu-Ende über beide Tasks hinweg. Spec:
       `docs/superpowers/specs/2026-07-24-icloud-sync-konfliktaufloesung-fix-design.md`, Plan:
       `docs/superpowers/plans/2026-07-24-icloud-sync-konfliktaufloesung-fix.md`.
  **Live-Verifikation des Konfliktauflösungs-Fixes vom Nutzer bestätigt erfolgreich:** nach
  erneutem Sync-Anstoß sind die 94 zuvor dauerhaft hängenden Elemente auf "Ausstehend: 0"
  gesunken, keine wiederholten `.serverRecordChanged`-Fehler mehr in der Konsole. Beide
  Durchgänge dieser Session sind damit vollständig abgeschlossen und bestätigt funktionsfähig.

- **2026-07-24 (weitere Folge-Session): iCloud Sync Phase 2a (Feeds/Ordner/Regeln/
  benutzerdefinierte Intelligente Ordner) — Implementierung ABGESCHLOSSEN, automatisierte
  Verifikation grün, manuelle Live-Verifikation NOCH AUSSTEHEND.** Baut auf dem in Phase 1
  etablierten `CKSyncEngine`-Fundament auf und baut `CloudSyncEngine` von einer Tag-spezifischen
  Klasse zu einer generischen, Registry-basierten Engine um (neues `CloudSyncRecordMapping`-
  Protokoll, ein Mapping-Typ pro syncbarer Tabelle). Umgesetzt via Brainstorming→Spec→Plan→
  Subagent-Driven-Development (7 Tasks, jeder mit eigenem Task-Review — alle im ersten Anlauf
  clean, keine Fix-Runde nötig): Task 1 Migration v22 (`updatedAt` auf `rule_conditions`/
  `smart_folder_conditions`, Backfill), Task 2 Migration v23 (`feeds.configUpdatedAt` als von
  `updatedAt` bewusst getrenntes Konfliktauflösungsfeld — `updatedAt` wird auch von jedem reinen
  Feed-Refresh gesetzt, ein rein lokaler Refresh alle 30 Min. hätte das Feed sonst immer "neuer"
  als den CloudKit-Server-Stand erscheinen lassen), Task 3 `CloudSyncRecordMapping`-Protokoll +
  Umbau von `CloudSyncEngine` auf Registry-Dispatch (verhaltenserhaltender Refactor für Tags,
  per unveränderter Phase-1-Testsuite verifiziert) + abhängigkeitsbewusste Sortierung
  eingehender Records (Eltern vor Kind-Bedingungszeilen, wegen aktivem
  `PRAGMA foreign_keys = ON`), Task 4 Feed-Sync (`CloudSyncFeedMapping`, syncbare Teilmenge NUR
  Konfigurationsfelder — `lastRefreshedAt`/`lastETag`/`lastModified`/`lastBodyHash`/
  `lastHTTPStatusCode`/`unreadCount` bleiben bewusst rein lokal/gerätespezifisch), Task 5
  Feed-Ordner-Sync (`CloudSyncFeedFolderMapping`, inkl. Feed-Requeue bei Ordner-Umbenennung),
  Task 6 Regel-Sync (`CloudSyncRuleMapping`/`CloudSyncRuleConditionMapping`, kaskadenbewusstes
  Enqueue vor kaskadierendem `DELETE`), Task 7 Intelligente-Ordner-Sync
  (`CloudSyncSmartFolderMapping`/`CloudSyncSmartFolderConditionMapping`, **nur für
  `isDefault == false`** — eingebaute Standard-Ordner wie „Ungelesen" werden nie synct, um
  Duplikate zu vermeiden; `restoreDefaultFolders()` bleibt unangetastet). Alle Records teilen
  sich weiterhin dieselbe CloudKit-Zone `"FeedivoZone"`, Konfliktauflösung bleibt Last-Write-Wins
  wie in Phase 1.
  **Zwei während der Task-Implementierung selbst gefundene und behobene Bugs (kein separater
  Whole-Branch-Review nötig, da jeder Task bereits durch seine eigene Regressionssuite
  abgesichert war):** (1) Task 1: der ursprünglich vom Plan wörtlich vorgeschlagene
  `ALTER TABLE ... DEFAULT CURRENT_TIMESTAMP`-Migrationscode hätte bei jedem Bestandsnutzer mit
  vorhandenen Regeln/Intelligenten Ordnern einen Migrations-Crash ausgelöst (SQLite lehnt
  `ADD COLUMN` mit einem Nicht-Konstanten-Default auf einer nicht-leeren Tabelle ab, siehe neuer
  Gotcha oben) — noch vor dem Task-Review selbst gefunden und in beiden neuen Migrationen (v22
  UND v23) einheitlich per `.defaults(to: Date())` gefixt. (2) Task 7: der Plan-Code für
  `SQLiteSmartFolderStore.save()` hätte bei `isDefault == true`-Ordnern die Bedingungspersistenz
  stillschweigend übersprungen (zu breites `isDefault`-Gate) — beim Ausführen der VOLLEN
  Regressionssuite (nicht nur der neuen Task-7-Tests) vor dem Commit aufgefallen und korrigiert.
  **Task 8 (dieser Eintrag) deckt nur die automatisierbaren Abschlussschritte ab:** gezielter
  Testlauf über alle 15 CloudSync-/Store-/Migrations-relevanten Suiten
  (`CloudSyncEngineRegistryTests`, `CloudSyncTagMappingTests`, `CloudSyncFeedMappingTests`,
  `CloudSyncFeedFolderMappingTests`, `CloudSyncRuleMappingTests`,
  `CloudSyncRuleConditionMappingTests`, `CloudSyncSmartFolderMappingTests`,
  `CloudSyncPendingChangeStoreTests`, `CloudSyncSettingsTests`, `SQLiteTagStoreTests`,
  `SQLiteFeedStoreTests`, `FeedFolderStoreTests`, `SQLiteRuleStoreTests`,
  `SQLiteSmartFolderStoreTests`, `FeedivoDatabaseMigratorTests`), 162/162 Tests grün (mit
  `-parallel-testing-enabled NO`, siehe bestehender Parallel-Testing-Gotcha), sowie ein voller
  `xcodebuild build -configuration Release` (BUILD SUCCEEDED, 0 Fehler). **Die manuelle
  Live-Verifikation gegen echtes CloudKit (analog zu Phase 1: Feed anlegen/umbenennen/
  verschieben/löschen, Ordner umbenennen, Regel mit Bedingungen anlegen/bearbeiten/löschen,
  benutzerdefinierten Intelligenten Ordner mit Bedingungen anlegen/löschen — jeweils im
  CloudKit-Dashboard unter `https://icloud.developer.apple.com/dashboard/` gegenprüfen, sowie
  die Bestätigung, dass eingebaute Intelligente Ordner dort NICHT erscheinen) ist NICHT
  durchgeführt worden** — das erfordert wie in Phase 1 einen Nutzer am eigenen Mac mit
  angemeldetem iCloud-Konto und Browser-Zugriff auf das Dashboard, außerhalb dieser Umgebung.
  Die Push-Richtung ist damit für alle 4 neuen Tabellen (Feeds/Ordner/Regeln+Bedingungen/
  benutzerdefinierte Intelligente Ordner+Bedingungen) bislang nur durch automatisierte Tests,
  NICHT live gegen den echten CloudKit-Server abgesichert. Die Pull-Richtung (Cloud → lokal)
  bleibt wie in Phase 1 bis zu einem zweiten Testgerät grundsätzlich unverifiziert, unabhängig
  vom Stand der übrigen Checkliste. Spec:
  `docs/superpowers/specs/2026-07-24-icloud-sync-phase2a-design.md`, Plan:
  `docs/superpowers/plans/2026-07-24-icloud-sync-phase2a.md`. Commits `a6620711..47eb6057`
  (Tasks 1–7) lokal auf `main`, Push-Status siehe `git log`/`git status` zum Lesezeitpunkt (hier
  bewusst keine Momentaufnahme dupliziert, siehe Lehre im 2026-07-20er CLAUDE.md-Korrektur-
  Eintrag zu veralteten Push-Status-Vermerken).

- **2026-07-24 (Folge-Session): iCloud Sync Phase 2a — finaler Whole-Branch-Review, 0
  Critical, 1 Important (dokumentiert statt code-gefixt), 1 Minor-Testlücke geschlossen.**
  Der finale Whole-Branch-Review fand keinen mergeblockierenden Fehler, aber einen echten,
  nur aus Gesamtsicht sichtbaren **Important-Befund zum Multi-Geräte-Verhalten beim Pull,
  der laut ausdrücklicher Reviewer-Empfehlung für diesen push-only/Ein-Geräte-Meilenstein
  nur dokumentiert, nicht code-gefixt werden muss:** `FeedFolderStore.
  materializeImplicitFolders()` (aufgerufen aus `SQLiteSidebarState.swift` bei jedem
  Sidebar-Load) legt für jeden nur implizit über `feeds.folderName` existierenden
  Ordnernamen eine neue `feed_folders`-Zeile mit einer frischen zufälligen UUID an — und
  reiht diese bewusst NICHT in die CloudSync-Warteschlange ein (für sich genommen korrekt,
  da Ordner-Identität in dieser App namensbasiert ist, nicht ID-basiert). Das kollidiert
  aber mit Task 5s neuer, ID-basierter Ordner-Synchronisierung: legt Gerät A einen Ordner
  „Technik" an und synct ihn (ID `UUID-A`), während Gerät B unabhängig davon seine eigene
  „Technik"-Zeile materialisiert (ID `UUID-B`), bevor `UUID-A` per Pull ankommt, fügt der
  eingehende Record beim Upsert-nach-Primärschlüssel eine ZWEITE „Technik"-Zeile in
  `feed_folders` auf Gerät B ein — die Sidebar würde danach zwei „Technik"-Ordner
  anzeigen. Dieses Risiko betrifft ausschließlich die Multi-Geräte-PULL-Richtung, die
  diese Phase laut Spec ohnehin schon bewusst als unverifiziert zurückstellt (nur
  Push-Richtung live-getestet, Single-Device). **Kein Merge-Blocker für diesen
  Meilenstein, aber als bekannte Limitation zu tracken statt stillschweigend
  mitzuschiffen** — vor bzw. während der Pull-Richtung-Live-Verifikation oder spätestens
  in Phase 2b muss das behoben werden, z. B. durch Dedupe eingehender `FeedFolder`-Records
  nach Name beim Anwenden, oder durch eine deterministische (statt zufällige) UUID-
  Ableitung aus dem Ordnernamen bei `materializeImplicitFolders()`. Siehe auch neuer
  Eintrag unter „Offene Entscheidungen" unten.
  **Zusätzlich unabhängig behoben (1 der 3 Minor-Funde, die anderen 2 — verwaiste
  Pending-Change-Zeile bei Rollback-Fehlschlag in `SQLiteFeedSubscriptionService.swift`,
  O(n)-Ordner-Lookup in `CloudSyncFeedFolderMapping` — vom Reviewer selbst als
  geringwertig/unwesentlich eingestuft und bewusst nicht angefasst):**
  `CloudSyncEngineRegistryTests.swift` prüfte bisher nur 2 der 7 registrierten
  Record-Types (`Tag`, `Feed`) gegen `CloudSyncEngine.mapping(forRecordType:)` — um 5
  neue Tests ergänzt (`FeedFolder`, `Rule`, `RuleCondition`, `SmartFolder`,
  `SmartFolderCondition`), je eine Assertion pro Typ, im bereits etablierten Stil der
  Datei. 167/167 Tests grün, Release-Build grün.

- **2026-07-24: iCloud Sync Phase 1 (CKSyncEngine-Fundament, nur Tags) — Implementierung
  ABGESCHLOSSEN, automatisierte Verifikation grün, manuelle Live-Verifikation NOCH
  AUSSTEHEND.** Baut ein erstes, bewusst eingeschränktes Sync-Fundament auf `CKSyncEngine`
  (seit iOS 17/macOS 14 Apples empfohlener Nachfolger zum älteren `CKDatabaseSubscription`+
  manueller Fetch-Change-Token-Verwaltung) — synchronisiert in dieser Phase ausschließlich
  die `tags`-Tabelle, alle anderen Tabellen (Feeds/Ordner/Regeln/Smart Folders/Artikel-Status)
  bleiben bewusst außen vor. Umgesetzt via Brainstorming→Spec→Plan→Subagent-Driven-Development
  (6 Tasks): Task 1 `CloudSyncPendingChangeStore` + Migration v21 (lokale Warteschlange für
  noch nicht hochgeladene Änderungen), Task 2 `CloudSyncTagMapping` (reine, zustandslose
  `TagRecord`↔`CKRecord`-Übersetzung), Task 3 `CloudSyncEngine`/`CloudSyncStatus` (der
  eigentliche `CKSyncEngine`-Wrapper), Task 4 `CloudSyncSettings`-Refactor (`isAvailable`
  jetzt fest `true`, das alte „App-Neustart nötig"-Konzept vollständig entfernt) +
  `TagStore`-Verdrahtung (alle 5 Mutationsmethoden markieren betroffene Tags jetzt als
  pending-sync), Task 5 Settings-UI (`SyncSettingsView`) live an `CloudSyncEngine`/
  `CloudSyncStatus` angebunden — Start/Stop beim Umlegen des Schalters wirkt sofort, kein
  Neustart mehr nötig. **Task 3 durchlief zwei Fix-Runden im Review, beide behoben und
  re-verifiziert:** einmal fehlende Fehlerprotokollierung an mehreren zuvor stumm
  verschluckenden `try?`-Stellen (Commits `3530e440`/`5859347d`, analog zum bereits
  etablierten `logIfThrows`/`AppLogger`-Muster aus dem 2026-07-12er Restposten-Review), und
  eine Race Condition zwischen `start()`/`stop()` (ebenfalls in `3530e440` behoben). Task 6
  (dieser Eintrag) deckt nur die automatisierbaren Schritte ab: gezielter Testlauf
  (`CloudSyncPendingChangeStoreTests`, `CloudSyncTagMappingTests`, `CloudSyncSettingsTests`,
  `SQLiteTagStoreTests`, 31/31 grün — bei Standard-Parallelisierung ein einzelner
  Fehlschlag durch eine `UserDefaults.standard`-Race zwischen zwei Tests, mit
  `-parallel-testing-enabled NO` reproduzierbar sauber grün, siehe bestehender
  Parallel-Testing-Gotcha weiter unten) sowie ein voller `xcodebuild build` (BUILD
  SUCCEEDED). **Die manuelle Live-Verifikation aus Spec/Plan Task 6 Schritt 3 (App
  starten, „iCloud Sync Beta" aktivieren, Tag anlegen/umbenennen/löschen, im
  CloudKit-Dashboard unter `https://icloud.developer.apple.com/dashboard/` gegenprüfen,
  ob die `CKRecord`s in der `FeedivoZone` korrekt erscheinen) ist NICHT durchgeführt
  worden** — das erfordert einen Nutzer am eigenen Mac mit angemeldetem iCloud-Konto und
  Browser-Zugriff auf das Dashboard, außerhalb dieser Umgebung. **Zusätzliche, ebenfalls
  ungeklärte Voraussetzung dafür: ob Task 0 (die iCloud/CloudKit-Capability in Xcodes
  Signing & Capabilities einmalig manuell aktivieren) bereits erledigt wurde, ist von
  hier aus nicht feststellbar** — auch das eine reine Xcode-UI-Aktion ohne
  Kommandozeilen-Spur. Die Pull-Richtung (Cloud → lokal) bleibt laut Spec ohnehin bis zu
  einem zweiten Testgerät grundsätzlich unverifiziert, unabhängig vom Stand der übrigen
  Checkliste. **Phase 2 (restliche Tabellen: Feeds/Ordner/Regeln/Smart Folders/
  Artikel-Status), Phase 3 (Feld-Ebene-Konfliktauflösung + Merge-Dialog bei
  Erst-Aktivierung mit bereits vorhandenen lokalen Daten) und Phase 4 (Härtung) sind
  jeweils eigene, separate künftige Brainstorming/Plan-Zyklen — nicht Teil dieses Plans.**
  Spec: `docs/superpowers/specs/2026-07-24-icloud-sync-phase1-design.md`, Plan:
  `docs/superpowers/plans/2026-07-24-icloud-sync-phase1.md`. Commits `584e0482..4f04da81`
  lokal auf `main`, Push-Status siehe `git log`/`git status` zum Zeitpunkt der Lektüre
  dieses Eintrags (hier bewusst keine Momentaufnahme dupliziert, siehe Lehre im
  CLAUDE.md-Korrektur-Eintrag vom 2026-07-20 zu veralteten Push-Status-Vermerken).

- **2026-07-24 (Folge-Session): iCloud Sync Phase 1 — finaler Whole-Branch-Review-Fix +
  Live-Verifikation VOLLSTÄNDIG ABGESCHLOSSEN UND BESTÄTIGT ERFOLGREICH.** Direkter
  Anschluss an den obigen Eintrag, drei Teile:
  1. **Finaler Whole-Branch-Review (Opus) fand einen echten, nur aus Gesamtsicht
     sichtbaren Critical-Bug** (Commit `061b4715`): Laufzeit-`TagStore`-Mutationen
     markierten Tags zwar korrekt in der lokalen `CloudSyncPendingChangeStore`-Warteschlange,
     benachrichtigten aber nie die LAUFENDE `CKSyncEngine`-Instanz —
     `engine.state.add(pendingRecordZoneChanges:)` lief nur einmalig in `start()`. Während
     einer laufenden Session wäre dadurch NICHTS live gesynct worden, sondern erst nach
     einem Neustart/Toggle-Aus-An. Kein Einzel-Task-Review hätte das sehen können (Task 3
     sah nur `CloudSyncEngine.swift`, Task 4 nur `TagStore.swift`, beide Dateien für sich
     genommen korrekt). Fix: neue `CloudSyncEngine.current`-Referenz (statisch, per neuer
     `register(_:)`-Methode einmalig in `FeedivoApp.init()` gesetzt) +
     `notifyPendingChangesAvailable(database:)`, von allen 5 `TagStore`-Mutationsmethoden
     nach dem jeweiligen `database.write` sowie vom Konflikt-Retry-Pfad in
     `handleFailedSave` aufgerufen. Re-Review (Opus) verifizierte den kompletten
     Laufzeit-Pfad Ende-zu-Ende und bestätigte: „Ready to merge: Yes". Zusätzlich 4
     veraltete CLAUDE.md-Abschnitte (Tech-Stack-Tabelle, ADR-007, M3-Checkbox, Offene
     Entscheidungen) im selben Fix korrigiert, die noch den überholten Zustand des
     alten SwiftData-basierten Sync-Beta-Branches beschrieben.
  2. **Manuelle Live-Verifikation deckte einen ZWEITEN, davon unabhängigen Bug auf, den
     kein Review finden konnte** (Commit `91f1179`, per systematic-debugging gefunden):
     Trotz Statuszeile „iCloud Sync aktiv" und einem frisch angelegten Testtag erschien
     zunächst kein Record im CloudKit Dashboard. Root Cause: `automaticallySync = true`
     verlässt sich laut Apples eigener WWDC23-Session „Sync to iCloud with CKSyncEngine"
     auf den System-Task-Scheduler, der erst Systembedingungen (Akku, Netzwerk, …)
     konsultiert, bevor er tatsächlich sendet — das kann beliebig lange dauern und ist für
     eine interaktive App, bei der der Nutzer eine zeitnahe Bestätigung erwartet, nicht
     ausreichend. Fix: `notifyPendingChangesAvailable(database:)` ruft nach
     `state.add(...)` jetzt zusätzlich explizit `syncEngine.sendChanges()` in einem eigenen
     `Task` auf (Apples dokumentierte „manual override" für genau diesen Fall). Ein
     zweiter, kleinerer Diagnose-Umweg dabei: der CloudKit-Dashboard-Records-Browser
     meldete nach dem Fix zunächst „No records found" bzw. „Field 'recordName' is not
     marked queryable" — beides reine Tooling-Eigenheiten des Dashboards (Queryable-Indexe
     für neu angelegte Record-Types müssen erst über „Deploy Schema Changes…" bestätigt
     werden, bevor Browser-Abfragen sie zuverlässig finden), **kein** Zeichen eines
     fehlgeschlagenen Syncs. Der tatsächliche Beweis kam aus dem Dashboard-„Logs"-Tab
     (Operation-Filter `RecordSave`): ein einzelnes, echtes `RecordSave`-Ereignis mit
     `overallStatus: SUCCESS`, `recordInsertCount: 5`, `returnedRecordTypes: "Tag"`,
     `zone: "FeedivoZone"` — die App hatte den kompletten, seit Sync-Aktivierung
     angesammelten Rückstand (inkl. des allerersten, vor dem Fix erfolglos angelegten
     Testtags, der die ganze Zeit korrekt in der lokalen Warteschlange lag) in einem
     einzigen Batch erfolgreich hochgeladen — genau das erwartete Verhalten der
     Warteschlangen-Architektur aus Task 1.
  3. **Damit ist die Push-Richtung (lokal → CloudKit) der komplette Phase-1-Sync-Pipeline
     live bestätigt funktionsfähig** (Toggle aktivieren → Tag anlegen → Record erscheint
     in CloudKit, ohne Neustart). Task 0 (iCloud/CloudKit-Capability in Xcode) war beim
     Live-Test bereits korrekt eingerichtet (Signing Identity/Provisioning Profile im
     Build-Log bestätigt). **Weiterhin unverifiziert, wie von Anfang an geplant:** die
     Pull-Richtung (Cloud → lokal) — dafür wird ein zweites Testgerät benötigt. Phase 2
     (restliche Tabellen), Phase 3 (Feld-Ebene-Konfliktauflösung + Merge-Dialog) und
     Phase 4 (Härtung) bleiben eigene, künftige Zyklen. Commits `61b4715` (sic:
     `061b4715`) und `91f1179` lokal auf `main`, Push-Status siehe `git log`/`git status`
     zum Lesezeitpunkt.

- **2026-07-24 (Folge-Session, Teil 2): iCloud Sync Phase 1 — Löschrichtung ebenfalls live
  bestätigt, ein reproduzierter Fehlalarm und ein offenes Rätsel dokumentiert.**
  - **Löschen live verifiziert:** Tag in Feedivo gelöscht → CloudKit-Dashboard-„Logs"-Tab
    zeigte ein neues `RecordDelete`-Ereignis, `overallStatus: SUCCESS`,
    `recordDeleteCount: 1`, `operationGroupName: CKSyncEngine-SendChanges-Manual` — exakt
    dieselbe Push-Pipeline (`notifyPendingChangesAvailable` → `sendChanges()`) wie beim
    Anlegen, nur mit `.deleteRecord` statt `.saveRecord`. Damit sind Anlegen UND Löschen
    für die Push-Richtung live bestätigt.
  - **Lehre zur eigenen Verifikationsdisziplin:** Ein erster Versuch, den Nutzer-Tag-Namen
    „SyncTest" im Dashboard-Records-Browser exakt zu finden, schlug fehl
    („No records found"), obwohl der Sync laut Logs erfolgreich war — der Nutzer fragte
    zu Recht nach, woher die Behauptung „der Tag war dabei" eigentlich kam, und die
    ehrliche Antwort war: aus zeitlicher Nähe geraten, nicht direkt belegt. Eine gezielte
    Nachfrage mit `FILTER BY name = SyncTest` (statt eines pauschalen `sortIndex`-Sortier-
    Workarounds) fand die Records dann tatsächlich — der Records-Browser selbst ist also
    grundsätzlich nutzbar, reagiert aber inkonsistent je nach genauer Abfrageform
    (vermutlich weiterhin die bereits notierte Index-Deployment-Verzögerung). **Für
    künftige Live-Verifikation gilt deshalb: Aggregat-Zahlen aus den Logs (`recordInsertCount`
    etc.) beweisen NUR, dass irgendetwas Passendes gesendet wurde — für eine Aussage über
    einen KONKRETEN Datensatz ist ein expliziter `FILTER BY <Feld> = <Wert>`-Records-Query
    nötig, keine Annahme aus Timing.**
  - **Ein zweiter, scheinbarer Fehlalarm klärte sich als Nutzeraktion:** Nach dem Löschen
    zeigte eine Nachfrage 0 statt der erwarteten 1 verbleibenden „SyncTest"-Records — der
    Nutzer hatte den zweiten, redundanten Testeintrag zwischenzeitlich selbst manuell im
    Dashboard entfernt. Kein App-seitiger Bug, aber ein Beispiel dafür, dass der
    CloudKit-Zustand während einer Live-Debugging-Session auch von außerhalb der App
    verändert werden kann — bei künftigen Unstimmigkeiten diese Möglichkeit aktiv
    mit-abfragen, nicht nur App-seitige Bugs vermuten.
  - **Offenes, unbestätigtes Rätsel (kein Blocker, aber im Blick behalten):** Bei einem der
    App-Neustarts (⌘R in Xcode, kein Clean/Erase) war der iCloud-Sync-Toggle
    „komischerweise" deaktiviert, obwohl `CloudSyncSettings.isEnabledKey` über
    `UserDefaults.standard` persistiert wird und ein normaler Neustart das eigentlich nicht
    zurücksetzen sollte. Nicht reproduziert, nicht root-caused — falls das erneut auftritt,
    gezielt untersuchen (z. B. ob sich Signing Identity/Bundle-Kontext zwischen Builds
    geändert hat, oder ob eine App-Sandbox-Container-Neuzuweisung durch Xcode dahinter
    steckt).

- **2026-07-20: Reader-Toolbar frei anpassbar (Feature 19.4) — VOLLSTÄNDIG ABGESCHLOSSEN
  und auf `origin/main` gepusht, Live-Verifikation vom Nutzer bestätigt.** Feature 19.4
  stand seit 2026-07-10 auf ⏸️ Zurückgestellt, da der ursprünglich geplante native
  macOS-Ansatz (`.toolbar(id:)`/`ToolbarItem(id:)` per Rechtsklick-„Symbolleiste
  anpassen…") vor dem Commit wieder verworfen worden war (siehe `FEATURES.md:884-886`).
  Umgesetzt via Brainstorming→Spec→Plan→Subagent-Driven-Development (4 Tasks, alle
  Task-Reviews clean im ersten Anlauf) — bewusst **ohne** die verworfene native API,
  stattdessen ein neuer Settings-Tab „Toolbar" mit `List`+`.onMove`-Drag&Drop-
  Umsortierung und Sichtbarkeits-Toggle für alle 14 Reader-Toolbar-Icons. Architektur:
  `ReaderToolbarItem`-Enum (Registry, Task 1) + `ReaderToolbarLayout`-Struct
  (Task 2, JSON-codierter String in einem `@AppStorage`-Key, analog
  `KeyboardShortcutOverrides` — inkl. Vorwärtskompatibilität: künftig neue Toolbar-Items
  erscheinen bei Bestandsnutzern automatisch sichtbar am Ende statt zu verschwinden) +
  Settings-UI (Task 3) + `SQLiteReaderView.readerToolbarContent`-Umbau (Task 4): rendert
  jetzt dynamisch über `ForEach` + einen exhaustiven `switch`, bleibt dabei aber bewusst
  **eine einzige** `ToolbarItemGroup(placement: .primaryAction)` — der bereits
  dokumentierte `NSToolbar`-Icon-Overlap-Bug (siehe Gotcha unten) hätte bei mehreren
  Toolbar-Items sonst erneut zugeschlagen. Whole-Branch-Review (Opus) fand 1
  Important-Finding: der neue 11. Settings-Tab bei der bis dahin fixen, nicht
  größenveränderbaren 880pt-Fensterbreite reproduzierte exakt das bereits einmal
  aufgetretene Tab-Leisten-Überlauf-Problem (640→880pt-Fix bei 10 Tabs, 2026-07-12) —
  keiner der 4 Einzel-Task-Reviews konnte das sehen, da keine Task die Fensterbreite
  „besitzt". Fix: `windowWidth` 880→960pt (Commit `5beab9ab`), Re-Review bestätigt.
  Pre-Flight-Check vor Task-Start fand zusätzlich einen Plan/Spec-Widerspruch beim
  Reset-Button-Label (Plan wollte den bestehenden Key „Alle zurücksetzen"
  wiederverwenden, Spec verlangt explizit „Standard wiederherstellen") — per
  Nutzerentscheid vor Task 3 korrigiert, Spec-Wortlaut gilt. Spec:
  `docs/superpowers/specs/2026-07-18-reader-toolbar-anpassen-design.md`, Plan:
  `docs/superpowers/plans/2026-07-18-reader-toolbar-anpassen.md`. Alle Commits `18557ba`
  (Start) .. `5beab9ab` (Whole-Branch-Fix), gepusht `ada4d48d..5beab9ab`.
- **2026-07-17: Automatischer Feed-Sprung am Listenende — VOLLSTÄNDIG ABGESCHLOSSEN,
  gepusht, komplette Live-Verifikationscheckliste abgehakt (siehe Nachtrag weiter unten
  im selben Themenblock — Korrektur 2026-07-20: der ursprünglich hier vermerkte
  "NICHT gepusht"-Status war veraltet, tatsächlich längst auf `origin/main`).**
  Nutzerwunsch: Pfeil-Runter am Ende der
  ungelesenen Artikel eines Feeds springt zum nächsten Feed mit ungelesenen Artikeln
  (Sidebar-Reihenfolge inkl. Ordner), wählt dort automatisch den ersten ungelesenen
  Artikel; Pfeil-Hoch symmetrisch rückwärts (letzter ungelesener Artikel). Nur bei
  Einzel-Feed-Auswahl, kein Wraparound. Umgesetzt via Brainstorming→Spec→Plan→
  Subagent-Driven-Development (2 Tasks, beide Reviews clean) + einem vom finalen
  Whole-Branch-Review (Opus) gefundenen Race-Fix. Architektur: neue reine, isoliert
  getestete `SidebarFeedOrder.swift` (delegiert an bestehende `FeedFolderOrganizer`-
  Bausteine, dieselben, die auch die echte NSOutlineView-Sidebar nutzt — beweisbar
  reihenfolge-treu), verdrahtet in `ContentView.swift` über zwei neue
  `.onKeyPress(.downArrow)`/`.onKeyPress(.upArrow)`-Handler am selben Wurzel-Container
  wie die bestehende Rechts-/Links-/Eingabetaste-Navigation. Race-Fix beim
  Feed-Wechsel: `handleSidebarSelectionChange()` setzte `selectedSQLiteArticleID` bei
  jeder `sidebarSelection`-Änderung bedingungslos auf `nil` zurück — ein direkter
  Sprung hätte die gerade gesetzte Zielartikel-Auswahl sofort wieder verloren (analog
  zum bereits dokumentierten AddFeedSheet-Race). Gelöst über einen neuen
  `pendingArticleIDAfterFeedJump`-State, den `handleSidebarSelectionChange()` selbst
  konsumiert statt blind zu überschreiben — deterministisch, ohne
  Reihenfolge-Annahmen über SwiftUIs Update-Zyklus. **Zweiter Fix aus dem
  Whole-Branch-Review (Commit `58fbd05`):** plausible (nicht bestätigte, aber am
  Datenfluss verifizierte) Race bei gehaltener Pfeiltaste über eine Feed-Grenze
  hinweg — der Ziel-Feed lädt seine Navigationsdaten asynchron nach
  (`sqliteArticleNavigationState` bleibt bis dahin `.empty`, ununterscheidbar vom
  "Ende der Liste"-Zustand), ein zweiter Tastendruck in dieser Lücke hätte den gerade
  erreichten Feed komplett übersprungen. Neues `isJumpingToFeedWithUnread`-Flag sperrt
  einen erneuten Sprung, bis `sqliteArticleNavigationState` per `.onChange` erstmals
  wieder echte (nicht-leere) Daten liefert. **Technisches Risiko aus der Spec LIVE
  BESTÄTIGT (2026-07-17):** Pfeil-Runter am Ende der ungelesenen Artikel tut nichts —
  natives `List`-Verhalten konsumiert Hoch/Runter auch am Rand der Liste komplett,
  bevor der `.onKeyPress`-Handler am Wurzel-Container das Ereignis überhaupt sieht.
  Anders als bei Rechts/Links (bereits live bestätigt funktionierend), da List
  Hoch/Runter selbst aktiv für die Zeilennavigation nutzt und den Tastendruck deshalb
  auch am Rand nicht durchreicht. **Nächster Schritt (NICHT in dieser Session
  begonnen, bewusst auf eine neue Session mit frischem Kontext verschoben — diese
  Session war bei Abschluss bei ~80 % Kontextfüllung und sehr hohen Kosten):**
  dokumentierter Fallback über einen App-weiten `NSEvent.addLocalMonitorForEvents
  (matching: .keyDown)`-Tastatur-Monitor, der Pfeil-Hoch/-Runter VOR der `List`
  abfängt. Braucht eine neue Brücke zwischen AppKit-Ebene und SwiftUI-`@State`
  (ähnliches Muster wie der bestehende `TextEditingFocusMonitor`, aber komplexer, da
  der Monitor die eigentliche Sprung-Logik in `ContentView` auslösen muss, nicht nur
  einen Bool-Flag lesen). Eigener Brainstorming→Spec→Plan-Zyklus empfohlen, kein
  reiner Live-Fix — die Architektur-Entscheidung (wie die Brücke genau aussieht) ist
  nicht trivial genug für eine Direktkorrektur. Spec:
  `docs/superpowers/specs/2026-07-17-naechster-feed-mit-ungelesenen-design.md`, Plan:
  `docs/superpowers/plans/2026-07-17-naechster-feed-mit-ungelesenen.md`. **Ausstehende
  manuelle Live-Verifikationscheckliste:** 1. Feed mit genau einem ungelesenen Artikel
  lesen, dann nochmal Pfeil-Runter — springt zum nächsten Feed mit ungelesenen
  Artikeln, Sidebar-Auswahl wechselt sichtbar, erster ungelesener Artikel dort
  ausgewählt. 2. **Entscheidender Test für das technische Risiko:** falls das NICHT
  funktioniert, ist das der Auslöser für den NSEvent-Monitor-Fallback. 3. Symmetrisch
  mit Pfeil-Hoch. 4. **Priorisierter Test für den zweiten Fix:** Pfeil-Runter über eine
  Feed-Grenze hinweg GEHALTEN drücken — darf den Ziel-Feed nicht überspringen. 5.
  Normales Durchnavigieren innerhalb eines Feeds mit mehreren ungelesenen Artikeln
  bleibt unverändert. 6. Letzter Feed mit ungelesenen Artikeln: kein Wraparound. 7.
  Ordner-Reihenfolge wird respektiert, nicht nur alphabetisch. 8. Smart Folder/Tag-
  Auswahl: kein Feed-Sprung.
- **2026-07-17 (Folge-Session): NSEvent-Monitor-Fallback für den automatischen
  Feed-Sprung — VOLLSTÄNDIG ABGESCHLOSSEN, gepusht, komplette
  Live-Verifikationscheckliste abgehakt (Korrektur 2026-07-20: "NICHT gepusht" war
  veraltet).** Der oben dokumentierte `.onKeyPress(.downArrow)`/`.onKeyPress(.upArrow)`-
  Primäransatz war live bestätigt wirkungslos (natives `List`-Verhalten verschluckt
  Pfeil-Hoch/-Runter am Rand der Liste, bevor `.onKeyPress` das Ereignis sieht) — dieser
  Durchgang ersetzt ihn durch den bereits angekündigten `NSEvent`-Monitor-Fallback.
  Umgesetzt via Brainstorming→Spec→Plan→Subagent-Driven-Development (2 Tasks, beide
  Reviews clean) + finalem Whole-Branch-Review (Opus): „Ready to merge: Yes", 0
  Critical/Important. Architektur: neuer `@Observable @MainActor`-Singleton
  `FeedJumpKeyMonitor` (`Feedivo/Services/FeedJumpKeyMonitor.swift`, strukturell analog
  zu `TextEditingFocusMonitor`) installiert einen
  `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` — fängt Tastendrücke ab, BEVOR
  irgendeine View (auch `List`s interne `NSTableView`) sie sieht. Prüft der Reihe nach:
  reine Pfeiltaste ohne Modifier (`nonisolated static func direction(for:modifierFlagsAreEmpty:)`,
  isoliert unit-getestet — 5 neue Tests), `!TextEditingFocusMonitor.shared.isEditingText`,
  richtiges Fenster (`event.window === contentWindow`, gesetzt von einer neuen unsichtbaren
  `ContentWindowObserver`-Bridge-View nach dem `FullScreenTransitionObserver`-Muster —
  schließt Suchfenster/Organizer/Einstellungen/Artikel-Popout automatisch aus), First
  Responder NICHT innerhalb von `WKWebView` oder `NSOutlineView`
  (`firstResponderIsExcluded(in:)`, Aufstieg durch die `superview`-Kette — schließt sowohl
  Web-Ansicht-Scrollen als auch Sidebar-Zeilennavigation aus, Letzteres ein beim Entwerfen
  zusätzlich gefundenes, analoges Kollisionsrisiko zum bereits vom Nutzer entschiedenen
  WKWebView-Fall), zuletzt die bereits bestehende `isEligible`-Logik. Ersetzt (nicht
  ergänzt) die alten `.onKeyPress(.downArrow)`/`.onKeyPress(.upArrow)`-Blöcke in
  `ContentView.swift` vollständig (waren nach dem Live-Befund ohnehin toter Code).
  `@MainActor`-Closure-Annotation auf dem Monitor-Handler (dieselbe Brücke wie
  `TextEditingFocusMonitor.startObserving()`), `startMonitoring()` idempotent per
  `guard monitor == nil`. 4 Minor-Funde im Whole-Branch-Review, keiner fix-bedürftig
  (u. a.: Kommentar-Analogie zu Button-Action-Closures ungenau — richtige Begründung ist
  `ContentView`s stabile Root-Identität als `Window("main")`-Singleton-Szene, nicht die
  Button-Analogie; `feedivoDatabase` via `@Environment` wird beim einmaligen
  Closure-Capture eingefroren statt live gelesen wie `@State`, aktuell unkritisch da der
  Environment-Wert sich nie ändert). Spec:
  `docs/superpowers/specs/2026-07-17-feed-sprung-nsevent-monitor-design.md`, Plan:
  `docs/superpowers/plans/2026-07-17-feed-sprung-nsevent-monitor.md`. **Ausstehende
  manuelle Live-Verifikationscheckliste (ergänzt die obige, ersetzt sie nicht):** 1.
  Feed mit genau einem ungelesenen Artikel lesen, dann nochmal Pfeil-Runter — springt
  jetzt tatsächlich zum nächsten Feed mit ungelesenen Artikeln (der entscheidende, beim
  Primäransatz fehlgeschlagene Test). 2. Symmetrisch mit Pfeil-Hoch. 3. **Neu:** in der
  Sidebar mit Pfeiltasten durch die Feed-Liste blättern, während irgendein anderer Feed
  zufällig „am Ende seiner ungelesenen Artikel" ist — Sidebar-Navigation bleibt normal,
  kein Feed-Sprung. 4. **Neu:** Artikel in Web-Ansicht öffnen, in den Artikeltext klicken
  (WKWebView hat Fokus), Pfeil-Runter drücken — Seite scrollt normal, kein Feed-Sprung.
  5. **Neu:** Suchfenster/Organizer-Fenster öffnen, dort navigieren, während im
  Hintergrund das Hauptfenster am Ende der ungelesenen Artikel ist — kein Feed-Sprung im
  Hintergrundfenster. 6.-9. restliche Punkte der ursprünglichen Checkliste (normales
  Durchnavigieren, kein Wraparound, Ordner-Reihenfolge, kein Sprung bei Smart-Folder/
  Tag-Auswahl) unverändert gültig. 10. Rechts-/Links-Pfeil und Eingabetaste
  (Reader-Ansichtswechsel/Original öffnen) verhalten sich weiterhin exakt wie zuvor —
  keine Regression durch die neue globale `NSEvent`-Abfangung.
- **2026-07-17 (Live-Fix-Runde nach obigem Fallback): Fünf Root Causes per
  systematischem Live-Debugging behoben — VOM NUTZER ALS FUNKTIONIEREND
  BESTÄTIGT, gepusht (Korrektur 2026-07-20: "NICHT gepusht" war veraltet).** Der
  NSEvent-Monitor-Fallback tat trotz „Ready to
  merge: Yes" live weiterhin nichts. Iterative Diagnose per TEMP-DEBUG-`OSLog`
  + `/usr/bin/log show` (Nutzer führte die eigentlichen Tastendrücke aus, da
  kein computer-use-Zugriff auf native macOS-Apps verfügbar ist) deckte fünf
  unabhängige Ursachen auf, jede einzeln gefixt und neu verifiziert:
  1. **Pfeiltasten setzen immer `.numericPad`/`.function`** in
     `event.modifierFlags`, auch ohne gedrückte Modifier-Taste —
     `.deviceIndependentFlagsMask` enthält beide, wodurch die
     Modifier-Prüfung für JEDEN Pfeiltastendruck fälschlich zuschlug. Fix:
     nur gegen `[.command, .option, .control, .shift]` prüfen.
  2. **SwiftUIs `List` ist auf macOS selbst intern über eine
     `NSOutlineView`-Subklasse (`SwiftUIOutlineListView`) realisiert** — ein
     generischer `is NSOutlineView`-Check in `firstResponderIsExcluded`
     schloss dadurch auch die Artikelliste selbst fälschlich als „Sidebar"
     aus. Fix: `SidebarOutlineViewControl` (die konkrete Sidebar-Klasse aus
     `SidebarOutlineView.swift`, ADR-008) von `private` auf `internal`
     angehoben, Check darauf umgestellt statt auf die Basisklasse.
  3. **`sqliteArticleNavigationState.nextArticleID`/`.previousArticleID`
     bilden „nächste/vorherige Zeile in der GESAMTEN Feed-Artikelliste
     (gelesen + ungelesen)" ab, nicht „nächster ungelesener Artikel"** —
     gelesene Artikel bleiben in `SQLiteFeedArticleListState.rows` stehen
     (siehe bestehender Kommentar bei `toggleRead()`). `nextArticleID` wurde
     dadurch nie `nil` am Ende der ungelesenen Artikel, sondern erst am
     literal letzten Artikel der gesamten Feed-Historie — ein Konzeptfehler
     aus der ursprünglichen Feature-Planung (Feature „Automatischer
     Feed-Sprung"), nie zuvor live testbar, weil der Auslösemechanismus vorher
     nie feuerte. Fix: `feedSnapshots.unreadCount` (derselbe Wert, der auch
     das Sidebar-Badge speist) als Eligibility-Signal statt Positions-Navigation.
  4. **`markSelectedArticleReadIfNeeded()` racete gegen den asynchronen
     Reload des Ziel-Feeds:** `.onChange(of: selectedArticleID)` feuerte beim
     Sprung, bevor `state.rows` für den neuen Feed geladen waren, fand keine
     passende Zeile und gab still auf, ohne erneut zu versuchen — der
     Zielartikel wurde nicht als gelesen markiert. Fix: zusätzlicher Aufruf
     in `.onChange(of: state.navigationState)` (feuert exakt dann, wenn der
     Reload abgeschlossen ist; `markReadIfNeeded()` ist intern idempotent).
  5. **`SQLiteReaderView.reloadCurrentArticleSnapshot()` lud `state.snapshot?.id`
     (den ZULETZT geladenen, alten Artikel) statt `self.articleID` (den
     AKTUELL ausgewählten)** — ausgelöst durch den Status-Version-Bump aus
     Fund 4, race gegen den regulären `.task(id: articleID)`-Ladevorgang für
     den neuen Artikel. Je nach Timing gewann der alte oder der neue
     Ladevorgang ("mal geht's, mal nicht" — Nutzer-Report). Fix:
     `self.articleID` statt `state.snapshot?.id` als Quelle.
  Alle Diagnose-Logs nach Bestätigung entfernt, die Erklärkommentare zu den
  fünf Funden bleiben im Code stehen. Commit `89c6680`. 80/80 Tests grün,
  Build grün. **Damit ist die entscheidende, zuvor offene Live-Verifikation
  aus dem Eintrag oben (Punkt 1–2, 6–10) vom Nutzer bestätigt bestanden.**
  **Nachtrag (2026-07-17, separate Session):** die restlichen drei Punkte
  (3–5: Sidebar-Fokus-Ausschluss, Web-Ansicht-Fokus-Ausschluss,
  Hintergrundfenster) wurden gezielt nachgetestet und ebenfalls vom Nutzer
  bestätigt — kein Feed-Sprung bei Sidebar-Navigation, kein Feed-Sprung
  beim Scrollen in der Web-Ansicht, kein Feed-Sprung im unsichtbaren
  Hintergrund-Hauptfenster bei Suchfenster/Organizer im Vordergrund. **Damit
  ist die komplette Live-Verifikationscheckliste für den automatischen
  Feed-Sprung (beide Spec-Dokumente) vollständig abgehakt.**
- **2026-07-17: Ein-/Ausschalter für automatischen Feed-Sprung in den
  Einstellungen — VOLLSTÄNDIG ABGESCHLOSSEN, gepusht (Korrektur 2026-07-20:
  "NICHT gepusht" war veraltet).** Nutzerwunsch
  direkt im Anschluss an die obige Live-Fix-Bestätigung: Möglichkeit, das
  Feature wieder auszuschalten. Leichtgewichtiges Brainstorming (eine
  Rückfrage zur Platzierung) + Direktimplementierung, kein voller Plan
  nötig (reine Wiederverwendung bestehender Bausteine). Neue
  `FeedJumpNavigationSettings` (`Feedivo/Views/ArticleList/
  ArticleListDisplaySettings.swift`, Standard AN) nach dem etablierten
  `ArticleList*Settings`-Muster; Toggle im Tab „Artikelliste" (Nutzerwahl,
  da thematisch näher an bestehenden Listen-Einstellungen als am
  Shortcuts-Tab). Gate sitzt in `ContentView.configureFeedJumpKeyMonitor()`s
  `isEligible`-Closure (`guard feedJumpNavigationIsEnabled, ...`) — der
  `NSEvent`-Monitor selbst bleibt installiert, wird bei Deaktivierung aber
  zum reinen No-Op, kein Neustart nötig, Umschalten wirkt sofort. 2 neue
  L10n-Keys manuell in `Localizable.xcstrings` ergänzt (Auto-Stub-Mechanismus
  greift bei indirekten `L10n`-Keys nicht, siehe Gotcha oben), per
  `grep -c` verifiziert. Commit `608630f`. 80/80 Tests grün, Build grün.
- **2026-07-16/17: Pfeiltasten-Navigation (Artikelliste + Reader-Zustandswechsel) —
  VOLLSTÄNDIG ABGESCHLOSSEN INKL. LIVE-FIX, gepusht (Korrektur 2026-07-20:
  "NICHT gepusht" war veraltet), komplette Live-Verifikationscheckliste vom Nutzer
  bestätigt durchgetestet.** Nutzerwunsch: reine (modifier-freie) Pfeiltasten für grundlegende
  Navigation — Hoch/Runter zum vorherigen/nächsten Artikel, Rechts-Pfeil steuert
  den Reader-Ansichtswechsel. Umgesetzt via Brainstorming→Spec→Plan→
  Subagent-Driven-Development (2 Tasks, beide Reviews clean im ersten Anlauf,
  0 Critical/Important) + anschließendem Live-Fix nach Nutzer-Test.
  **Rechercheergebnis vor der Implementierung:** Hoch/Runter brauchen KEINEN
  Code — `SQLiteFeedArticleListView`s `List(selection:)` ist über eine
  durchgängige `@Binding`-Kette an denselben State gebunden wie die bestehenden
  ⌘↑/⌘↓-Menübefehle, macOS' native `List`-Tastatursteuerung bewegt diese
  Selektion bei Fokus bereits per Pfeiltaste, alle bestehenden `.onChange`-
  Seiteneffekte (Gelesen-Markierung, Sticky-Row) feuern identisch zu Mausklick.
  Architektur bewusst NICHT über das gerade zuvor gebaute
  `CustomizableShortcut`/`Commands`-Menüsystem (hätte das noch ungeklärte
  `.disabled`-Reaktivitätsrisiko in `Commands`-Bodies geerbt), sondern reine,
  isoliert getestete Zustandsübergangs-Logik (`ReaderArrowKeyNavigation.swift`)
  plus `.onKeyPress(...)` am Wurzel-Container von `ContentView.body` (oberhalb
  der `NavigationSplitView`) — nutzt SwiftUIs Tastatur-Event-Bubbling, ein
  fokussiertes Textfeld konsumiert die Tasten selbst für Cursor-Bewegung/
  Bestätigung, bevor das Event dorthin blubbert (kollisionsfrei, kein
  `TextEditingFocusMonitor`-Äquivalent nötig). Erster Whole-Branch-Review (Opus)
  auf dem ursprünglichen Design: „Ready to merge: Yes", 0 Critical/Important.
  **Live-Fix (2026-07-17, Commit `0d88a37`):** Nutzer-Report nach dem ersten
  Live-Test — die ursprünglich gebaute Vorwärts-Kette (Rechts: nativ → Web →
  Browser, Links: Web → nativ als einziger Rückweg) fühlte sich falsch an: aus
  der Web-Ansicht führte Rechts nicht zurück zu nativ, sondern weiter zum
  Browser. Nutzerentscheid (per Rückfrage): Rechts wird ein reiner
  Umschalter nativ↔Web in beide Richtungen, das Öffnen im externen Browser
  läuft stattdessen über die Eingabetaste (Return). `ReaderArrowKeyNavigation.
  rightArrowResult(currentMode:)`/`.leftArrowShouldSwitchToNative(currentMode:)`
  durch eine einzige `toggleMode(currentMode:) -> ReaderDisplayMode` ersetzt;
  Links-Pfeil-Handler in `ContentView.swift` komplett entfernt (redundant, da
  Rechts jetzt beide Richtungen abdeckt); neuer `.onKeyPress(.return)`-Handler
  ruft die bereits bestehende `openSelectedSQLiteArticleOriginal()` auf. Direkt
  ohne neuen vollen Brainstorming-Zyklus umgesetzt (kleine, klar umrissene
  Korrektur an bereits reviewtem Code, analog zu früheren „Live-Fix"-Einträgen
  in diesem Dokument), aber weiterhin mit TDD und Build-Verifikation.
  **Zweiter Live-Fix (2026-07-17, Commit `d30336d`):** Der erste Live-Fix ging
  zu weit — Nutzer-Report: Rechts-Pfeil in der Web-Ansicht wechselte
  erwartungsgemäß den Zustand, aber der Nutzer wollte eigentlich mit LINKS aus
  der Web-Ansicht zurück zu nativ, was nach dem ersten Fix nicht mehr ging
  (Links-Handler war komplett entfernt worden). Per Rückfrage geklärt:
  klassisches Vorwärts-/Rückwärts-Paar gewünscht, nicht ein einzelner
  Umschalter. Endgültiges Verhalten: Rechts wechselt NUR vorwärts (nativ→Web,
  no-op wenn bereits Web), Links geht zurück (Web→nativ, no-op wenn bereits
  nativ), Eingabetaste öffnet weiterhin unabhängig vom Zustand im externen
  Browser. `ReaderArrowKeyNavigation.toggleMode` ersetzt durch
  `rightArrowShouldSwitchToWeb(currentMode:)`/`leftArrowShouldSwitchToNative(currentMode:)`,
  Links-Handler in `ContentView.swift` wieder ergänzt. 69/69 Tests grün, Build
  grün. **Lehre:** Bei einem reinen Text-Beschreibung eines Tastatur-
  Interaktionsmusters (kein Mockup/keine Skizze) reicht eine einzelne
  Rückfrage nicht immer aus, um das exakt gewünschte Verhalten zu treffen —
  hier waren zwei Iterationen nötig, jeweils erst nach echtem Live-Test
  aufgedeckt, nicht vorher aus der Beschreibung ableitbar. Spec/Plan-Dokumente
  (`docs/superpowers/specs/2026-07-16-pfeiltasten-navigation-design.md`,
  `docs/superpowers/plans/2026-07-16-pfeiltasten-navigation.md`) beschreiben
  bewusst noch den ursprünglichen (durch beide Live-Fixes überholten)
  Drei-Stufen-Entwurf — historisches Dokument des Entscheidungsprozesses, nicht
  nachträglich umgeschrieben; dieser CLAUDE.md-Eintrag ist die aktuelle Quelle
  der Wahrheit. **Ausstehende manuelle Live-Verifikationscheckliste (Stand nach
  beiden Fixes):** 1. Artikel anklicken, dann Pfeil-Runter/-Hoch — Artikelliste
  navigiert, Reader aktualisiert sich. 2. Bei ausgewähltem Artikel in nativer
  Ansicht Rechts-Pfeil — wechselt zur Web-Ansicht. 3. Links-Pfeil im
  Web-Zustand — wechselt zurück zur nativen Ansicht. 4. Eingabetaste bei
  ausgewähltem Artikel — öffnet im externen Standard-Browser, unabhängig vom
  aktuellen Ansicht-Zustand. 5. **Entscheidender, laut Review priorisierter
  Fokus-Test:** Rechts-/Links-Pfeil/Eingabetaste sowohl bei fokussierter
  Artikelliste ALS AUCH nach Klick in den Reader-Bereich testen — insbesondere
  während die eingebettete Web-Ansicht (WKWebView) den Tastaturfokus hat
  (höchstes Fehlschlagrisiko laut ursprünglichem Review, durch beide Fixes
  nicht berührt). 6. Ohne ausgewählten Artikel bzw. bei einem Artikel ohne
  nutzbaren Link: alle drei Tasten tun nichts, kein Absturz. 7. Rechts-/
  Links-Pfeil/Eingabetaste bei fokussiertem Textfeld (Suche, Umbenennen)
  bewegen weiterhin nur den Text-Cursor bzw. bestätigen das Feld, lösen keinen
  Reader-Zustandswechsel aus.
- **2026-07-16: Shortcuts-Erweiterung (modifier-freie Kombinationen + 8 fehlende
  Menü-Funktionen) — VOLLSTÄNDIG ABGESCHLOSSEN, gepusht (Korrektur 2026-07-20:
  "NICHT gepusht" war veraltet), komplette Live-Verifikationscheckliste vom Nutzer
  bestätigt durchgetestet.** Nutzer-Report: In den Einstellungen unter „Shortcuts" (Feature 19.8)
  ließen sich keine Ein-Zeichen-/Leertasten-Shortcuts hinterlegen, und für Artikel
  archivieren/exportieren/Link kopieren/Original öffnen/Teilen sowie OPML Import/
  Export/Verwaltung öffnen gab es gar keinen Shortcut-Eintrag. Umgesetzt via
  Brainstorming→Spec→Plan→Subagent-Driven-Development (8 Tasks, alle Task-Reviews
  clean im ersten Anlauf bis auf Task 2, siehe unten). Architektur: `CustomizableShortcut.
  defaultSpec` von `KeyboardShortcutSpec` auf `KeyboardShortcutSpec?` umgestellt, 8 neue
  Fälle ohne Default (`feedImportOPML`, `feedExportOPML`, `feedOrganizerOpen`,
  `articleToggleArchived`, `articleCopyLink`, `articleOpenOriginal`,
  `articleShareOriginal`, `articleExport`); `RecorderNSView.keyDown` verliert die
  Modifier-Pflicht; neuer `TextEditingFocusMonitor` (`@MainActor`/`@Observable`
  Singleton, `NSControl.textDidBeginEditingNotification`/`textDidEndEditingNotification`,
  registriert in `FeedivoAppDelegate.applicationDidFinishLaunching`) plus
  `KeyboardShortcutsSettings.needsTextFieldGuard(for:)` — `customizableKeyboardShortcut`
  deaktiviert modifier-freie Shortcuts jetzt, während ein Textfeld editiert wird (sonst
  würde ein solcher Shortcut als echtes `NSMenuItem`-Tastenkürzel jede Texteingabe
  blockieren, siehe neuer Gotcha unten). Neue Warnzeile in den Shortcut-Einstellungen.
  „Feed löschen" bekommt bewusst keinen Shortcut (destruktive Aktion, Nutzerentscheidung).
  **Task 2 hatte einen selbst gefundenen und im selben Zyklus behobenen Formatierungsbug**
  (Commit `65cbdd4c2` → Fix `f120a027b`): das ursprüngliche Python-Skript nutzte
  `json.dump(sort_keys=True, indent=2)` ohne zu Xcodes Stil passende `separators`, was
  die komplette ~31000-Zeilen-`Localizable.xcstrings` umformatierte/neu sortierte statt
  nur 9 Einträge chirurgisch einzufügen — vor dem Reviewer-Dispatch per Diff-Stat-Kontrolle
  entdeckt, per reiner Text-Segment-Einfügung an einem stabilen Anker (direkt nach
  `"strings" : {`) korrigiert, Netto-Diff danach 253 Insertions/0 Deletions. Finaler
  Whole-Branch-Review (Opus): „Ready to merge: With fixes" — die einzigen „Fixes" sind
  Prozess, kein Code: die untenstehende Live-Checkliste abarbeiten und diesen Eintrag
  hier führen (bereits erledigt). Kernrisiko laut Review: ob `.disabled(TextEditingFocusMonitor.
  shared.isEditingText)` innerhalb von `CommandMenu`/`Commands`-Bodies (nicht nur in
  normalen View-Bodies) tatsächlich reaktiv neu ausgewertet wird — automatisiert nicht
  prüfbar (kein ViewInspector im Projekt), einziger Prüfstein ist Live-Test Punkt 3
  unten. Fallback falls das fehlschlägt: `isEditingText` über einen echten SwiftUI-
  Graph-Seam (`@Environment`/`@FocusedValue`) statt eines rohen Singleton-Reads
  durchreichen. Spec: `docs/superpowers/specs/2026-07-16-shortcuts-modifierfrei-
  erweiterung-design.md`, Plan: `docs/superpowers/plans/2026-07-16-shortcuts-
  modifierfrei-erweiterung.md`. **Ausstehende manuelle Live-Verifikationscheckliste:**
  1. Einen der 8 neuen Einträge (z. B. „Archivieren") mit Modifier-Taste belegen —
     Menübefehl reagiert korrekt. 2. Denselben Eintrag stattdessen modifier-frei (nur
     „J") belegen — Warnzeile erscheint, Shortcut funktioniert außerhalb von Textfeldern.
     3. **Entscheidender Test:** bei aktivem modifier-freiem Shortcut in ein Textfeld
     (Suche, Feed-/Ordner-Umbenennen, Tag-Name, Regel-Name) klicken und „J" tippen — der
     Buchstabe muss im Feld ankommen, der Menübefehl darf NICHT auslösen, und nach
     Verlassen des Feldes muss der Shortcut zügig wieder aktiv werden. 4. Leertaste als
     modifier-freien Shortcut belegen — Badge zeigt „␣". 5. Bekannte, bewusst
     nicht behobene Grenze gegenprüfen: Formularfeld innerhalb eines im WKWebView
     geladenen Original-Artikels (löst keine `NSControl`-Notification aus) — falls
     hier tatsächlich eine Kollision auftritt, als eigenen Punkt in den Gotchas unten
     ergänzen statt stillschweigend zu ignorieren.
- **2026-07-16: Spotlight-Integration (Feature 9.3) — VOLLSTÄNDIG ABGESCHLOSSEN,
  gepusht (Korrektur 2026-07-20: "NICHT gepusht" war veraltet).** Artikel werden
  als Core Spotlight Items indexiert, ein Klick auf
  ein Spotlight-Resultat öffnet Feedivo direkt beim Artikel, neuer Einstellungen-
  Schalter "Artikel in Spotlight indexieren" (Standard AN). Umgesetzt via
  Brainstorming→Spec→Plan→Subagent-Driven-Development (7 Tasks, direkt auf main,
  kein Worktree — etablierte Nutzerpräferenz). Architektur: neuer
  `SpotlightIndexingService` kapselt `CSSearchableIndex` hinter injizierbarem
  `SpotlightIndexWriting`-Protokoll (Tests berühren nie den echten System-Index),
  `SpotlightIndexingSettings` (Schalter + Backfill-Flag, `NotificationSettings`-
  Muster), `SpotlightContinuationParser` speist Spotlight-Klicks in die bereits
  bestehende `feedivo://article`-Deep-Link-Pipeline (`PendingURLSchemeAction`) ein.
  Injizierbare Closure-Hooks (`indexForSpotlight`/`deindexForSpotlight`, additive
  Default-Parameter) in `SQLiteFeedRefreshService`, `SQLiteFeedSubscriptionService`,
  `SQLiteFeedArticleListState.deleteArticle`, `ArticleRetentionCleanupService.
  removeExpiredSQLiteArticles`. **Cross-Task-Design-Entscheidung nach Task-2-Review
  (Nutzerentscheid via AskUserQuestion):** versteckte Artikel (`isHidden`) werden NIE
  in Spotlight indexiert — `includeHidden: false` an allen drei Insert-Stellen,
  Indexierungs-Hook in `SQLiteFeedRefreshService` bewusst NACH `applyRules(...)`
  platziert, damit ein sofort per Regel ausgeblendeter Artikel korrekt ausgeschlossen
  bleibt. Alle 7 Task-Reviews clean im ersten Anlauf (0 Critical/Important), bis auf
  Task 2 (1 ⚠️-Punkt zur Hidden-Artikel-Frage, durch Nutzerentscheid + Fix-Runde
  aufgelöst). Finaler Whole-Branch-Review (Opus): Ready to merge: With fixes — 1
  Important-Finding (Erst-Start-Backfill blockierte synchron den MainActor bei
  Standardschalter AN, betrifft jeden Bestandsnutzer beim Update), gefixt (Commit
  `70a0cedae`, `async throws` + `FeedivoDatabase.readAsync` statt synchronem `read`
  — siehe neuer Gotcha zu `SWIFT_DEFAULT_ACTOR_ISOLATION` oben) und per Re-Review
  bestätigt. 5 Minor dokumentiert, keiner fix-bedürftig (u. a.: Hidden-Exclusion nur
  beim Backfill unit-getestet nicht bei Refresh/Subscription; nachträglich per Regel
  versteckte, bereits indexierte Artikel bleiben bis zur nächsten Löschung/Bereinigung
  in Spotlight auffindbar — bewusste Limitation außerhalb des Insert/Delete-Hook-
  Scopes; schmales benignes TOCTOU-Race auf `hasBackfilled` aus dem Concurrency-Fix).
  Spec: `docs/superpowers/specs/2026-07-16-spotlight-integration-design.md`, Plan:
  `docs/superpowers/plans/2026-07-16-spotlight-integration.md`. Ausstehend: manuelle
  7-Punkte-Live-Verifikationscheckliste (Plan Task 7, Step 7) durch den Nutzer —
  insbesondere ob Spotlight-Suche Artikel tatsächlich findet, ob der Klick auf ein
  Resultat den richtigen Artikel öffnet, und ob das ohne zusätzlichen Info.plist-
  Eintrag unter der App-Sandbox funktioniert.
- **2026-07-16: Bulk-Benachrichtigungsverwaltung im Feed-Organizer — VOLLSTÄNDIG
  ABGESCHLOSSEN, gepusht (Korrektur 2026-07-20: "NICHT gepusht" war veraltet).**
  Nutzerwunsch: "Benachrichtigen" nicht mehr für jeden
  Feed einzeln über die Feed-Eigenschaften umschalten müssen. Umgesetzt via leichtgewichtigem
  Brainstorming+Spec (kein voller Plan/Subagent-Driven-Development-Prozess, da reine
  Wiederverwendung bestehender Bausteine): `FeedManagementOrganizerView.swift` bekommt
  einen Glocken-Button pro Feed-Zeile (`bell.fill`/`bell.slash` je nach
  `feed.isNotificationEnabled`, reiner `.plain`-Icon-Button-Stil wie der bestehende
  Papierkorb-Button) sowie zwei neue Toolbar-Buttons "Benachrichtigen (N)"/
  "Nicht benachrichtigen (N)" für die Mehrfachauswahl, exakt nach dem Muster des
  bestehenden "Ausgewählte löschen"-Buttons (Anzahl-Suffix, `.disabled`/`.opacity(0.45)`
  bei leerer Auswahl). Kein neuer Store-Code — nutzt die bereits vorhandene
  `FeedStore.updateNotificationEnabled(id:isEnabled:)` an drei neuen Stellen. Keine
  Bestätigungs-Dialoge (jederzeit reversible Einstellungsänderung, kein Löschen). "Alle
  Feeds" bewusst nicht separat implementiert — durch "Sichtbare auswählen" (bei leerer
  Suche = alle Feeds) + Bulk-Button bereits abgedeckt. 4 neue L10n-Keys manuell in
  `Localizable.xcstrings` ergänzt (Xcodes Auto-Stub-Mechanismus greift bei indirekten
  `L10n`-Keys nicht, siehe bestehender Gotcha). `xcodebuild build` grün. Bestehende
  Source-Sniffing-Assertion `feedPropertiesMetrikenLaufenUeberSQLite` in
  `FeedivoAppSceneConfigurationTests.swift` (prüft per Substring-Match auf
  whitespace-bereinigtem Quelltext, ob `FeedManagementOrganizerRow(...)` bestimmte
  Parameter enthält) war schon vor dieser Änderung nicht erfüllbar, da `theme:theme,`
  zwischen den geprüften Parametern liegt — keine Regression, bereits Teil der
  vorbestehenden Testfehlschläge in dieser Datei. Spec:
  `docs/superpowers/specs/2026-07-16-organizer-bulk-notify-design.md`. Ausstehend: manuelle
  Live-Verifikation im laufenden Betrieb (Zeilen-Button + beide Toolbar-Buttons).
- **2026-07-15: Benachrichtigungs-Einstellungen überarbeitet (Master-Schalter, Standard
  für neue Feeds, Test-Benachrichtigung, Systemeinstellungen-Link) — Implementierung
  abgeschlossen, gepusht (Korrektur 2026-07-20: "NICHT gepusht" war veraltet).**
  Bisherige Einstellungsseite zeigte nur den
  macOS-Berechtigungsstatus plus zwei reine Info-Zeilen ohne echte Einstellungen. Neu:
  `NotificationSettings.swift` (Master-Schalter default an, Standard-für-neue-Feeds
  default aus, beide mit sicherem `object(forKey:) != nil`-Guard gegen den bekannten
  UserDefaults-Default-Bug, siehe Gotcha zu `retentionDays`); Master-Schalter-Gate in
  `FeedNotificationService.present(...)` bewusst vor `isAuthorized()`, damit kein
  unnötiger Berechtigungs-Prompt bei ausgeschaltetem Schalter ausgelöst wird; neues
  `presentTest()` umgeht bewusst nur den Master-Schalter, respektiert aber weiterhin die
  macOS-Berechtigung; `SQLiteFeedSubscriptionService` verdrahtet den Neue-Feeds-Default
  in `addFeed(...)` und `importOPMLFeeds(...)` über einen neuen injizierbaren
  `userDefaults`-Parameter; UI-Erweiterung in `SettingsView.swift` (`NotificationSettingsView`)
  inkl. "Systemeinstellungen öffnen"-Button bei blockierter Erlaubnis
  (`x-apple.systempreferences:com.apple.Notifications-Settings.extension?ch.martin.Feedivo`,
  undokumentiertes Deep-Link-Schema, Fallback-Konstante vorbereitet). Via
  Brainstorming→Spec→Plan→Subagent-Driven-Development (5 Tasks, 1 Fix-Runde bei Task 1:
  fehlender expliziter-false-Test bei `isEnabledForNewFeeds`, plan-mandated Finding).
  Whole-Branch-Review (Opus): Ready to merge: Yes, 0 Critical/Important, 3 rein
  informative Minor-Punkte (dritte `FeedRecord`-Konstruktionsstelle im
  Refresh-Recovery-Pfad bewusst ausgenommen, Master-Schalter-Gate selbst ungetestet
  mangels Mock-Seam für `UNUserNotificationCenter`, kosmetische xcstrings-Reihenfolge).
  Spec: `docs/superpowers/specs/2026-07-15-benachrichtigungs-einstellungen-design.md`,
  Plan: `docs/superpowers/plans/2026-07-15-benachrichtigungs-einstellungen.md`.
  Nutzerentscheid: vor dem Push erst die 6-Punkte-Live-Verifikationscheckliste (Plan
  Task 5, Step 5) manuell durchklicken — insbesondere ob der Master-Schalter tatsächlich
  eine Benachrichtigung unterdrückt und ob der Systemeinstellungen-Deep-Link wirklich auf
  Feedivos eigener Seite landet statt nur der allgemeinen Übersicht.
  **Live-Fix (2026-07-16, Commit `56670c4`):** Nutzer-Report — nach Erteilen der
  macOS-Erlaubnis blieb der Status in den Einstellungen auf "noch nicht gefragt" hängen,
  erst Schließen+Wiederöffnen des Einstellungsfensters zeigte den korrekten Stand. Via
  systematic-debugging Root Cause gefunden: `refreshNotificationAuthorizationStatus()`
  fragte direkt nach `requestAuthorization()` erneut `notificationSettings()` ab — macOS
  propagiert die frisch erteilte Erlaubnis nicht synchron, die sofortige Nachfrage konnte
  noch den alten Stand liefern. Fix: Status direkt aus dem bereits maßgeblichen
  `Bool`-Rückgabewert von `requestAuthorization()` ableiten, keine erneute Abfrage mehr.
  Kein automatisierter Regressionstest möglich (kein Mock-Seam für
  `UNUserNotificationCenter` im Projekt, wie schon bei Task 3 dokumentiert) — Fix per
  `xcodebuild build` verifiziert, Verhalten selbst bleibt manuell zu bestätigen.
- **2026-07-15: Sidebar komplett auf AppKit NSOutlineView umgestellt (ADR-008) + Ordner-
  Sortier-Menü — Implementierung und Feed-/Ordner-Live-Verifikation abgeschlossen und
  gepusht.** Ersetzt das unzuverlässige SwiftUI-native `.draggable`/
  `.dropDestination` aus Feature 15.2. Details (Architektur, Kern-Invariante,
  Nebeneffekt Tag-/Smart-Folder-Sortierbarkeit) siehe ADR-008 oben, kritischer
  NSOutlineView+SwiftUI-Drag-Gotcha siehe „Bekannte Gotchas" oben. Umgesetzt via
  Brainstorming→Spec→Plan→Subagent-Driven-Development (6 Tasks), danach zwei
  Live-Fix-Runden direkt im Anschluss an die Verifikation durch den Nutzer. Neues Feature
  auf Nutzerwunsch nach der ersten Live-Testrunde: Menü neben der „Ordner"-Kopfzeile mit
  „Alphabetisch sortieren (A-Z)" (`FeedFolderStore.sortAlphabetically()`), um eine
  versehentliche manuelle Drag&Drop-Umsortierung einfach rückgängig machen zu können.
  Danach TEMPDEBUG-Diagnose-Logging (Live-Log-Analyse zur Drag-Fehlersuche) wieder
  vollständig aus `SidebarOutlineView.swift` entfernt. Commits `3cc693c1f..7344983d2`
  auf `main`. Whole-Branch-Review (Opus) fand 4 Important-Findings, 3 gefixt (fehlende
  Empty-State-Platzhalter, zu knappes `.frame(minHeight: 200)` um die NSOutlineView,
  Ordner-Löschen-Regression bei nicht-leeren Ordnern); 1 Finding (natives
  Doppelklick-Expand-Verhalten) bewusst NICHT gefixt, da ein `shouldExpandItem`/
  `shouldCollapseItem`-Fix ohne laufende App nicht verifizierbar gewesen wäre. Spec:
  `docs/superpowers/specs/2026-07-15-sidebar-nsoutlineview-design.md`, Plan:
  `docs/superpowers/plans/2026-07-15-sidebar-nsoutlineview.md`. Ausstehend: Tag-/
  Smart-Folder-Reordering und restliche Punkte des 13-Punkte-Testprotokolls noch nicht
  explizit live durchgetestet.
- **2026-07-14 (Vormittag): Bereinigte Artikel bleiben dauerhaft weg + Start-Reihenfolge-Fix —
  VOLLSTÄNDIG ABGESCHLOSSEN und auf `origin/main` gepusht.** Folge-Diagnose nach den
  Befund-A/B/C-Fixes: Nutzer meldete weiterhin, dass bereinigte Artikel beim nächsten
  Feed-Refresh sofort wieder auftauchten, und dass die automatische Bereinigung beim
  App-Start gelegentlich vom Start-Refresh überholt wurde. Via Brainstorming+Spec+
  Plan+Subagent-Driven-Development (4 Tasks + 1 Fix-Runde) behoben. Details siehe
  „Letzte Änderungen" unten.
- **2026-07-13/14 (Nacht): Drei Bugfixes automatische Artikel-Bereinigung —
  VOLLSTÄNDIG ABGESCHLOSSEN und auf `origin/main` gepusht (alle Befund-A/B/C-Fixes,
  inzwischen im selben Rutsch wie das obige Feature gepusht).** Nutzer-Report: "Alte
  Artikel bleiben trotz aktivierter Bereinigung liegen, auch nach Tagen im
  Hintergrund." Root-Cause-Analyse via systematic-debugging fand drei
  unabhängige Befunde, alle drei behoben:
  - **Befund A (Fix, Commit `99ed5fe`, gepusht):** `ArticleRetentionCleanupService`
    wurde nur beim App-Start und bei Retention-Einstellungsänderungen
    aufgerufen, nie erneut während einer laufenden Session — der periodische
    Hintergrund-Refresh (`BackgroundRefreshService.refreshAllFeeds`, einziger
    Aufrufpfad des `NSBackgroundActivityScheduler`) löste nie eine Bereinigung
    aus. Fix (TDD, 3 neue Regressionstests): neue
    `cleanupExpiredArticlesIfNeeded(database:userDefaults:now:)`, wird jetzt am
    Ende jedes `refreshAllFeeds`-Durchlaufs aufgerufen. Ein Test deckt
    gezielt einen naiven `UserDefaults.integer/bool(forKey:)`-Fallback-Bug ab
    (fehlender gespeicherter Wert hätte sonst `retentionDays: 0` statt des
    korrekten 90-Tage-Standards ergeben).
  - **Befund B (Fix, Commit `b10d641`, gepusht):** Artikel ohne parsbares
    `publishedAt` waren dauerhaft von der Bereinigung ausgenommen,
    unabhängig vom tatsächlichen Alter. Fix (TDD, 3 neue Regressionstests):
    `SQLiteArticleRetentionCandidate` liest zusätzlich `articles.arrivedAt`
    (NOT NULL) und bietet `effectiveDate` (`publishedAt ?? arrivedAt`) als
    Fallback — dieselbe `COALESCE(publishedAt, arrivedAt)`-Idiomatik, die in
    `ArticleStore.swift` für die Sortierung bereits etabliert ist. Sowohl die
    Löschentscheidung (`shouldRemove`) als auch der
    Mindestanzahl-pro-Feed-Schutz (`sqliteRetentionSort`) nutzen jetzt
    `effectiveDate` konsistent.
  - **Befund C (Feature, Commits `b902998..61b4cb3`, 4 Commits, NICHT
    gepusht):** Der automatische Bereinigungspfad hatte keinerlei
    UI-Feedback — Fehler landeten nur im Apple-Systemlog
    (`SilentErrorLogging.swift`/`AppLogger.dataAccess`). Via
    Brainstorming+Plan+Subagent-Driven-Development (3 Tasks) behoben: neuer
    gemeinsamer Einstiegspunkt `ArticleRetentionCleanupService.
    runAutomaticCleanup(...)` (ersetzt die zuvor dreifach duplizierte
    `logIfThrows { removeExpiredSQLiteArticles(...) }`-Stelle in allen drei
    automatischen Aufrufern — App-Start, Feed-Einstellungsänderung,
    Hintergrund-Refresh), schreibt Ergebnis/Fehler in neue
    `UserDefaults`-Keys; neuer "Automatischer Bereinigungsstatus"-Block in
    den Einstellungen (Tab "Alte Artikel"), analog zum bestehenden
    Aktualisierungsstatus-Block für den Feed-Refresh. Dafür wurden
    `statusLine`/`formattedRefreshDate` (→ `formattedAutomaticStatusDate`)
    aus `RefreshSettingsView` zu file-privaten freien Funktionen angehoben,
    damit beide Status-Blöcke sie teilen. Manueller "Jetzt
    bereinigen"-Button bleibt bewusst getrennt (Nutzerentscheidung: kein
    gemeinsamer Status). Whole-Branch-Review (Opus) fand 1 Important-Finding
    (siehe neuer Gotcha unten zu Xcodes String-Catalog-Auto-Stub bei
    indirekten `L10n`-Keys), behoben und re-verifiziert. Details siehe
    „Letzte Änderungen" unten. Gepusht (`3401236..61b4cb3`, im selben Rutsch
    wie das Bereinigung-dauerhaft-Feature).
- **2026-07-13 (spät Abend): Tags direkt im Reader-Header hinzufügen —
  VOLLSTÄNDIG ABGESCHLOSSEN und auf `origin/main` gepusht.** Neuer "+"-Button
  neben Ordner-/Tag-Chips im Reader-Header öffnet ein Popover mit denselben
  Zuweisungs-/Erstellungs-Optionen wie der bestehende Metadaten-Inspector.
  Details siehe „Letzte Änderungen" unten.
- **2026-07-13 (Abend): Mehrfach-Tag-Filterung in der Artikelsuche —
  VOLLSTÄNDIG ABGESCHLOSSEN und auf `origin/main` gepusht.** Suche erlaubt
  jetzt Auswahl mehrerer Tags gleichzeitig (Popover mit Checkboxen), mit
  wählbarem Any/All-Verknüpfungsmodus. Details siehe „Letzte Änderungen" unten.
- **2026-07-13 (Mittag): Feeds in der Sidebar umbenennbar — VOLLSTÄNDIG
  ABGESCHLOSSEN und auf `origin/main` gepusht.** Überträgt den Doppelklick-
  Inline-Umbenennen-Mechanismus von Ordnern auf Feeds. Bestehender
  `FeedRenameView`-Dialog (Original-Titel + Wiederherstellen) bleibt über das
  Kontextmenü unverändert erreichbar. Details siehe „Letzte Änderungen" unten.
- **2026-07-13 (später Vormittag): Ordner in der Sidebar umbenennbar — VOLLSTÄNDIG
  ABGESCHLOSSEN und auf `origin/main` gepusht.** Doppelklick auf den Ordnernamen bzw.
  neuer Kontextmenü-Eintrag „Ordner umbenennen" startet Inline-Bearbeitung. Details
  siehe „Letzte Änderungen" unten.
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
- Der laut FEATURES.md-Entscheidung vom 2026-07-02 zugunsten des SQLite/GRDB-Umbaus
  zurückgestellte alte iCloud-Sync-Beta-Branch (SwiftData-basiert) ist nach Abschluss des
  Umbaus (ADR-007) endgültig überholt und wurde am 2026-07-24 gelöscht — keine erneute
  Bewertung mehr nötig.

---

## Letzte Änderungen

- 2026-08-14 (Folge-Session): MCP-Server Ein/Aus-Schalter + Verbindungs-Hilfe —
  VOLLSTÄNDIG ABGESCHLOSSEN, Whole-Branch-Review „Ready to merge: Yes" nach einer
  Fix-Runde. Neuer Settings-Tab „KI-Zugriff": Schalter (Standard AUS, Opt-in — der
  Server exponiert ohne aktives Einschalten keinerlei Daten) + kopierbarer Claude-
  Desktop-Config-Snippet (`Bundle.main.bundlePath`-basiert, funktioniert für Debug-
  und Release-Installationen gleichermaßen). Neue Tabelle `mcp_server_settings`
  (Migration v31, Single-Row) statt `UserDefaults` — bewusste Abweichung von der
  sonstigen Projekt-Konvention, da `UserDefaults`/`cfprefsd` keine Cross-Process-
  Konsistenzgarantie bietet, GRDB/WAL dagegen schon (siehe Gotcha zu GRDBs
  `PRAGMA query_only`-Verhalten). `FeedivoMCPServer/main.swift` prüft das Flag
  fail-closed direkt nach dem Öffnen der DB, vor jeder Tool-Registrierung und vor
  dem Start des stdio-Transports — Server startet erst gar nicht, wenn deaktiviert.
  Whole-Branch-Review (opus) fand nach den 5 Einzel-Tasks zwei Important-Funde: der
  Fail-closed-Test hatte keine tatsächlich ausführbare Testabdeckung (lag nur im
  strukturell nie laufenden `FeedivoMCPServerTests`-Target — jetzt zusätzlich nach
  `FeedivoTests/Stores/MCPServerSettingsStoreTests.swift` gespiegelt, läuft dort
  echt); die 6 rohen deutschen Strings im neuen Tab hätten bei jedem Build
  automatische xcstrings-Stubs erzeugt UND dabei beobachtbar zwei bereits
  vollständig übersetzte Bestandskeys (`reader.youTubeVideoHint.message`/`.button`)
  gelöscht — auf L10n-Keys umgestellt, behebt beides zugleich. Spec:
  `docs/superpowers/specs/2026-08/2026-08-14-mcp-server-schalter-design.md`, Plan:
  `docs/superpowers/plans/2026-08-14-mcp-server-schalter.md`. Commits
  `de2306d..6d27bd7` auf `main`, Push-Status siehe `git log`/`git status` zum
  Lesezeitpunkt. Bewusst zurückgestellt für v1.1 (kein Merge-Blocker): kein Live-
  Reconnect bei „Aus" während einer bereits laufenden Client-Sitzung — ein
  bestehender Server-Prozess liest das Flag nur einmal beim Start, ein Abschalten
  wirkt erst nach Neustart des MCP-Clients (im UI-Hilfetext bereits kommuniziert).
- 2026-08-14: Read-only MCP-Server für Feedivo (v1, 7 Tools) — vollständige Details
  siehe „Aktuell in Arbeit" und ADR-011 oben, hier nicht dupliziert. Commits
  `4ed7498..ac2a3eb` auf `main`, gepusht (`d586d01..ac2a3eb`).
- 2026-08-04: Netzwerk-basierte Bild-Anreicherung deaktiviert (Nutzerentscheidung, minimaler
  Umfang). Die erst im Verlauf desselben Tages gebaute Bild-Anreicherung
  (`FeedService.enrichArticleImagesIfNeeded` — ruft bei fehlendem RSS-eigenem Bild die
  Original-Artikelseite per Netzwerk ab und sucht dort nach `og:image`/`twitter:image`,
  siehe Commits `bc6a753`/`7d5e3ee` und `docs/superpowers/specs/2026-08/
  2026-08-04-feed-refresh-bild-anreicherung-hintergrund-design.md`) hatte den Effekt, dass
  Artikel ohne Bild im Feed trotzdem oft ein Bild zeigten — vom Nutzer als unerwünscht
  eingestuft: Artikel sollen exakt so dargestellt werden, wie sie vom Feed ausgeliefert
  werden, ohne zusätzlichen Netzwerkabruf zum "Erraten" eines fehlenden Bildes. Statt der
  besprochenen vollständigen Entfernung (Code + Tests + Doku) bewusst die minimale,
  reversible Variante gewählt: die beiden einzigen produktiven Verdrahtungsstellen, die den
  echten Enricher statt des sonst projektweit üblichen No-Op-Defaults (`{ $0 }`) gesetzt
  hatten, umgestellt — `FeedViewModel.init` ([FeedViewModel.swift:102](Feedivo/ViewModels/FeedViewModel.swift:102),
  deckt alle App-UI-Pfade ab) und `SQLiteFeedActionService.init`
  ([SQLiteFeedActionService.swift:32](Feedivo/Services/SQLiteFeedActionService.swift:32), Fallback für
  `LocalExtensionBridgeServer`, den Browser-Erweiterungs-HTTP-Server). Die Feed-eigene
  Bildextraktion (`media:content`, RSS-`enclosure`, `<img>` in `content:encoded`/
  `description`, Atom-Content/Summary, JSON-Feed-`image` — alles direkt aus dem bereits
  ausgelieferten Feed-Inhalt, kein zusätzlicher Request) bleibt unverändert. `FeedService.
  enrichArticleImagesIfNeeded` selbst samt Helfern und eigener Testsuite bleibt im Code
  bestehen (aktuell ungenutzte, aber dokumentierte Fähigkeit) — bei Bedarf jederzeit durch
  Rückgängigmachen dieser zwei Default-Änderungen reaktivierbar. Build (Debug) und die vier
  betroffenen Testsuiten (`FeedViewModelTests`, `SQLiteFeedSubscriptionServiceTests`,
  `SQLiteFeedRefreshCoordinatorTests`, `FeedServiceConditionalFetchTests`, 45/45) grün.
- 2026-07-28: Reader Inline-Formatierung (Fett/Kursiv/Links/Farben aus Artikel-HTML)
  — VOLLSTÄNDIG ABGESCHLOSSEN, gepusht (`b54818a9..5c35e57b`), vom Nutzer nach
  eigener manueller Live-Verifikation als funktionierend bestätigt. Der native
  SwiftUI-Reader (`ReaderContentRenderer`/`SQLiteReaderView`) reduzierte Artikel-HTML
  bisher beim Parsen pauschal auf reinen Block-Text — `<a href>`, `<b>`/`<strong>`,
  `<i>`/`<em>` gingen dabei komplett verloren (die WKWebView-„Originalartikel"-Ansicht
  war davon nie betroffen). Umgesetzt via Brainstorming→Spec→Plan→
  Subagent-Driven-Development (4 Tasks + Whole-Branch-Review), Spec:
  `docs/superpowers/specs/2026-07-28-reader-inline-formatierung-design.md`, Plan:
  `docs/superpowers/plans/2026-07-28-reader-inline-formatierung.md`. Architektur:
  `ReaderContentBlock`-Fälle tragen jetzt `[ReaderInlineRun]` (neuer reiner
  Sendable-Werttyp: Text + Fett/Kursiv-Flags + optionale Link-URL + optionaler
  Hex-Farbwert) statt `String` — bewusst NICHT direkt `AttributedString` im Modell,
  da Attribut-Gleichheitsvergleiche in Tests brüchig wären. Neuer rekursiver
  Regex-Parser `ReaderContentRenderer.inlineRuns(fromHTML:)` erkennt `<a href>` (nur
  `http`/`https`-Schema, `javascript:`/`data:`/`file:` werden verworfen),
  `<b>`/`<strong>`, `<i>`/`<em>` sowie `style="color:...\"` auf diesen Tags PLUS
  zusätzlich auf `<span>` (Nachtrag vor Plan-Erstellung — `<span style="color:...">`
  ist der in echtem Artikel-HTML weit überwiegende Fall für farbigen Text). Neuer,
  pure Policy-Typ `ReaderInlineColorSafety` prüft geparste Hex-Farben zur Render-Zeit
  gegen eine vereinfachte Kontrast-Kennzahl (Hell-/Dunkelmodus-Referenzhelligkeit,
  Schwelle 2.5:1) — bei zu wenig Kontrast bleibt die Standard-Textfarbe erhalten.
  Neue `[ReaderInlineRun] -> AttributedString`-Konvertierung
  (`ReaderInlineRun+AttributedString.swift`) speist `Text(AttributedString)` statt
  `Text(String)`; `SQLiteReaderView` bekommt `.environment(\.openURL, ...)` mit
  explizitem `NSWorkspace.shared.open(url)`, damit Links garantiert im
  Standardbrowser statt in-App öffnen. **Zwei echte Funde unterwegs:** (1) Task 3
  (Plan-Bug, nicht Implementierer-Fehler): beim Schreiben des Plans wurde ein
  bestehender `where paragraph != "•"`-Filter (entfernt verwaiste
  Bullet-Zeichen-Artefakte aus `<ul>`-Resten) versehentlich weggelassen — im
  Task-Review gefunden, in derselben Fix-Runde restauriert samt Regressionstest.
  (2) Whole-Branch-Review (Opus) fand über alle 4 Tasks hinweg zwei Important-Funde:
  einen irreführenden Kommentar auf `splitIntoParagraphRuns` (behauptete
  fälschlich, sie erkenne Inline-Formatierung — der Text ist an dieser Stelle
  bereits zu Plain-Text reduziert, betrifft v. a. den `summary`-Fallback/RSS
  `<description>` sowie jeden Text außerhalb von `<p>`/`<div>`/`<h*>`/`<li>`/
  `<blockquote>`, korrigiert + als bewusst akzeptierte Limitation dokumentiert),
  und dass Fett/Kursiv nie gegen eine gebündelte Reader-Schriftart getestet wurde
  (die gebündelten Fonts liefern nur eine Regular-`.ttf` pro Familie, kein echter
  Bold/Italic-Schnitt — nur `.system`/`.serif` haben garantiert echte Schnitte).
  Letzteres wurde NICHT code-gefixt, sondern als priorisierter Schritt in die
  manuelle Live-Verifikationscheckliste aufgenommen. **Nachträglicher
  Nutzerwunsch (separater Durchgang, direkt im Anschluss):** Links sollten beim
  Hovern unterstrichen werden — SwiftUI `Text(AttributedString)` unterstützt aber
  kein Hover-Tracking für einzelne Textbereiche innerhalb eines Fließtext-Absatzes
  (nur ganze Views können `.onHover`); echtes Hover-only hätte einen Umbau auf
  AppKit `NSTextView` gebraucht (analog ADR-008). Nutzerentscheid nach Rückfrage:
  Links stattdessen durchgängig unterstreichen (`segment.underlineStyle = .single`
  in der AttributedString-Konvertierung), kein größerer Umbau. Alle Tests grün
  (109 zuletzt), Debug- und Release-Build grün.
- 2026-07-28: Zwei kleinere Bugfixes aus direkten Nutzer-Reports, jeweils gepusht:
  (1) Gelesen-/Ungelesen-Zahlen bei benutzerdefinierten Intelligenten Ordnern —
  `SQLiteSidebarState.load()` berechnete `mixedCounts` (die zwei Kreis-Badges)
  bisher nur für die 6 eingebauten Standard-Ordner (hartcodierte
  `defaultKey`-Liste `SmartFolderDefaultDisplayPolicy.mixedCountKeys`), obwohl die
  zugrundeliegende `TimelineStore.readUnreadCounts(scope:includeHidden:)`-Query
  längst generisch für jeden Smart Folder funktioniert — Schleife läuft jetzt über
  ALLE geladenen Smart-Folder-Snapshots, Dictionary-Schlüssel von `defaultKey` auf
  `folder.id` umgestellt (`mixedCountsByDefaultKey` → `mixedCountsByFolderID`).
  (2) Ordner-Bezeichnung in der Sidebar skalierte nicht mit der
  Oberflächenschrift-Größe-Einstellung — `SidebarOutlineFolderRow` war als
  einzige Sidebar-Zeilenart ohne `@Environment(\.interfaceTextSize)`, Fonts/
  Icon-Frames waren fest verdrahtet statt wie bei Feed-/Tag-/Smart-Folder-Zeilen
  über `interfaceTextSize.font(...)`/`.scaled(...)` zu skalieren — auf dasselbe
  etablierte Muster umgestellt.
- 2026-07-27 (direkte Folge-Session): Refresh-Throttling + zwei Perf-Nachzügler aus dem
  obigen NetNewsWire-Vergleich umgesetzt — VOLLSTÄNDIG ABGESCHLOSSEN, gezielter
  Regressionslauf und Debug-Build grün (`xcodebuild build`, ohne `-configuration Release`),
  NICHT gepusht. Deckt genau die drei
  im Eintrag direkt darunter als "noch offen" gelisteten Punkte ab. Umgesetzt via
  Brainstorming→Spec→Plan→Subagent-Driven-Development (6 Tasks + Abschluss-Task 7): (1)
  **Refresh-Throttling** (Tasks 1–3): neue, reine `FeedRefreshThrottle.shouldSkip(...)`-
  Entscheidungsfunktion (Mindestabstand 9 Minuten, analog NetNewsWires
  `LocalAccountRefresher`), gespeist aus einer neuen `FeedLogStore.latestAttemptTimes()`
  (letzter Versuchszeitpunkt je Feed aus `feed_logs`, kein neues Schema/keine Migration
  nötig), in `SQLiteFeedRefreshCoordinator.refreshAllFeeds(...)` verdrahtet — greift
  bewusst NUR beim "alle Feeds aktualisieren"-Pfad, nicht bei einem gezielten
  Einzel-Feed-Refresh. (2) **`rebuildAllFeedUnreadCounts()`-CTE-Fix** (Task 4): dieselbe
  `GROUP BY`-CTE-Umstellung wie beim bereits gefixten `sidebarFeeds()`-Performance-Bug vom
  2026-07-16 (siehe Gotcha-artiger Eintrag dort), jetzt auch für den globalen
  Ungelesen-Zähler-Rebuild-Pfad — ersetzt N korrelierte Pro-Feed-Subqueries durch eine
  einzige gruppierte Aggregation. (3) **Favicon-Single-Flight-Dedup** (Tasks 5–6): neuer
  `FaviconDiscoveryCoordinator`-Actor dedupliziert gleichzeitige Favicon-Discovery-Anfragen
  für dieselbe Site-URL (mehrere Feeds vom selben Host lösten bisher unabhängige, redundante
  Netzwerk-Roundtrips aus), in `SQLiteFeedRefreshCoordinator` verdrahtet. Alle 6 Task-
  Reviews kamen mit „Spec ✅ / Task quality: Approved" zurück, 0 Critical/Important-Funde —
  nur einige Minor-Findings ins Ledger geparkt, kein Fix-Loop nötig: (a) ein theoretisches,
  praktisch unerreichbares Silent-Swallow-Muster in `FeedLogStore.latestAttemptTimes`, (b)
  eine vorbestehende, nicht durch Task 3 verursachte dreifache Summary-Konstruktion in
  `SQLiteFeedRefreshCoordinator`, (c) ein fehlender expliziter Test für den Fail-Open-Pfad
  bei einem `latestAttemptTimes()`-Fehler, (d) eine brief-vorgegebene, rein theoretische
  Timing-Annahme in einem `FaviconDiscoveryCoordinator`-Test (kein Code-Defekt), (e) die
  `SQLiteFeedRefreshCoordinatorTests`-Suite ist nicht netzwerk-hermetisch (echte
  `FaviconService`-Discovery-Aufrufe in Tests, vorbestehend seit vor diesem Plan). Task 7
  (dieser Eintrag) deckt nur die automatisierbaren Abschlussschritte ab: gezielter
  Testlauf über alle 6 berührten Suiten (`FeedRefreshThrottleTests`,
  `SQLiteFeedLogStoreTests`, `SQLiteFeedRefreshCoordinatorTests`,
  `SQLiteUnreadCountServiceTests`, `FaviconDiscoveryCoordinatorTests`,
  `SQLiteFeedRefreshServiceTests`, mit `-parallel-testing-enabled NO`), 28/28 Tests grün,
  sowie ein voller `xcodebuild build` (BUILD SUCCEEDED). Spec:
  `docs/superpowers/specs/2026-07-27-refresh-throttling-perf-nachzuegler-design.md`, Plan:
  `docs/superpowers/plans/2026-07-27-refresh-throttling-perf-nachzuegler.md`. Commits
  `7ab3774` (Task 1), `d5c5591` (Task 2), `62f7ee13` (Task 3), `82af009d` (Task 4),
  `239c2b77` (Task 5), `9681ae1e` (Task 6) auf `main`, gepusht (Korrektur 2026-07-28:
  "NICHT gepusht" war veraltet — per `git merge-base --is-ancestor` gegen `origin/main`
  verifiziert, alle sechs Commits waren bereits enthalten). Manuelle Live-Verifikation (Throttling bei
  wiederholtem "Alle aktualisieren" innerhalb der 9-Minuten-Schwelle, Ungelesen-Zähler nach
  Rebuild, Favicon-Dedup bei mehreren Feeds desselben Hosts) noch nicht durchgeführt.

- 2026-07-27: Zwei Performance-Fixes aus einem aktualisierten NetNewsWire-Vergleich
  umgesetzt (TDD), Details siehe `docs/performance/` (ältere Audits vom 15./16.07.) plus
  frischer Recherche im lokalen NetNewsWire-Klon (`/Users/martinfelder/Developer/
  NetNewsWire-main`): (1) `PRAGMA synchronous = NORMAL` in `FeedivoDatabase.swift`
  ergänzt (bislang GRDB-Default FULL) — NetNewsWire setzt dieselbe Pragma bei ebenfalls
  einer einzigen, serialisierten `DatabaseQueue`-Verbindung bewusst explizit, mit der
  Begründung, dass WAL bei diesem Zugriffsmuster nichts bringt, FULL-Synchronität aber
  unnötig viele fsyncs pro Transaktion erzwingt — GRDBs `DatabasePool`/WAL-Wechsel wurde
  daher bewusst NICHT verfolgt (identische NetNewsWire-eigene Begründung im Quellcode-
  Kommentar von `FMDatabase+Extras.swift` gefunden). (2) `SQLiteFeedRefreshService.
  applyRules()` schrieb bisher für jeden Regel-Treffer eines Feed-Refreshs eine eigene
  GRDB-Transaktion (je ein `setHidden`- bzw. `tagStore.save`/`assignTag`-Aufruf pro
  Artikel — 3N Commits statt 1). Neue `in db:`-Batch-Overloads auf `ArticleStatusStore.
  setHidden`/`TagStore.save`/`TagStore.assignTag` (GRDBs `DatabaseWriter.write` ist nicht
  reentrant, ein zweiter `database.write`-Aufruf von innerhalb einer laufenden Transaktion
  würde abstürzen) erlauben jetzt eine einzige `database.write`-Transaktion für den
  gesamten Batch — dasselbe Muster, das `SQLiteRuleEvaluationStore.
  applyRulesToExistingArticles` (Regel rückwirkend auf Bestandsartikel anwenden) bereits
  vorher nutzte, hier aber für den Refresh-Pfad fehlte. Regressionstest (GRDB-SQL-Trace
  zählt `COMMIT TRANSACTION`-Anweisungen) verifiziert, dass die Commit-Zahl jetzt
  unabhängig von der Trefferzahl konstant bleibt (vorher 42 vs. 58 Commits bei 1 vs. 5
  Treffern, nachher identisch). Betroffene Testsuiten (`ArticleStatusStoreTests`,
  `SQLiteArticleStatusStoreTests`, `SQLiteTagStoreTests`, `TagStoreChangedFieldsTests`,
  `RuleEngineTests`, `SQLiteRuleEvaluationStoreTests`, `SQLiteFeedRefreshServiceTests`)
  grün, Debug-Build grün (`xcodebuild build`, ohne `-configuration Release`). Noch offen aus demselben Vergleich (nicht in
  dieser Session umgesetzt): Refresh-Throttling/Host-Blocklist analog NetNewsWires
  `LocalAccountRefresher` (Mindestabstand pro Feed, bekannte Nicht-Feed-Hosts), Favicon-
  Single-Flight-Dedup, `rebuildAllFeedUnreadCounts()` auf gruppierte CTE umstellen.

- 2026-07-26: iCloud Sync Phase 3 (Feld-Ebene-Konfliktauflösung + Erst-Aktivierungs-
  Merge-Dialog) — vollständige Details siehe „Aktuell in Arbeit" oben, hier nicht
  dupliziert. 15 Tasks via Brainstorming→Spec→Plan→Subagent-Driven-Development, Task 14
  fand die zwei schwerwiegendsten Findings des gesamten Plans (Selbst-Kollisions-
  Datenverlust-Falle + Start-Reihenfolge-Lücke bei der Erst-Aktivierungssperre, beide
  sofort gefixt). Task 15 (Regressionslauf + Release-Build): 189/189 gezielte Tests
  grün, Release-Build grün. Spec: `docs/superpowers/specs/2026-07-26-icloud-sync-phase3-
  design.md`, Plan: `docs/superpowers/plans/2026-07-26-icloud-sync-phase3.md`. Commits
  `d1abdbd5..1a01ca65` auf `main`, NICHT gepusht (Nutzerbestätigung vor Push laut
  Projektkonvention ausstehend). Ausstehend: Live-Verifikation gegen echtes CloudKit/ein
  zweites Testgerät, sämtliche visuelle/interaktive Verifikation der drei neuen Views.
- 2026-07-24: Feature „Freie Gruppierung von Regel-Bedingungen (UND/ODER)" im
  Power-User-Modus des Regel-Assistenten — VOLLSTÄNDIG ABGESCHLOSSEN und gepusht
  (`77d13d74..0b83521a`). Ersetzt den bisherigen globalen „Treffer bei: Alle
  Bedingungen / Eine reicht"-Umschalter durch explizite, umrandete Gruppen-Boxen:
  jede Box intern UND-verknüpft, die Boxen untereinander ODER-verknüpft (z. B.
  `(A UND B) ODER (C UND D) ODER E`), eine Verschachtelungsebene. Umgesetzt via
  Brainstorming→Spec→Plan→Subagent-Driven-Development (7 Tasks, alle Task-Reviews
  clean im ersten Anlauf, 0 Critical/Important) + finaler Whole-Branch-Review
  (Opus). Architektur: neues `groupIndex: Int`-Feld (Default 0) auf
  `RuleConditionRecord`/`RuleConditionDraft`, Migration `v20_add_rule_condition_
  group_index` mit Backfill aus dem bisherigen `rules.matchMode` (`"all"` → eine
  gemeinsame Gruppe, `"any"` → je eigene Gruppe pro Bedingung in
  `sortOrder`-Reihenfolge — bestehende Regeln verhalten sich nach dem Update
  identisch weiter). `RuleEngine.matches()` gruppiert per
  `Dictionary(grouping:by:\.groupIndex)` + `.contains { allSatisfy }` statt den
  globalen `matchMode`-Parameter zu befragen; neue, reine und isoliert getestete
  `RuleConditionGroupLayout.swift` kapselt die Gruppierungs-/Entfernungslogik
  (Muster wie `SidebarFeedOrder.swift`). `RuleSettingsFormatter.conditionSummary`
  setzt Klammern nur bei mehr als einer Gruppe UND mehr als einer Bedingung pro
  Gruppe. `RuleMatchMode` (der Typ) bleibt vollständig bestehen — wird weiterhin
  unabhängig von Smart Folders genutzt, nur die *Regeln*-Seite verlor ihre
  Abhängigkeit davon. **Whole-Branch-Review fand einen echten, nur aus
  Gesamtsicht sichtbaren Integrationsfehler:** `RuleSettingsView.
  matchingCountsReloadToken` (eine Datei außerhalb aller 6 Task-Diffs)
  berücksichtigte `groupIndex` nicht — nach reinem Umgruppieren einer Regel
  (identische Feld/Operator/Wert/sortOrder-Tupel, nur `groupIndex` unterschiedlich)
  feuerte der `.task(id:)`-Reload nicht, die angezeigte Trefferzahl blieb veraltet
  stehen (der Zusammenfassungstext selbst war korrekt, da er direkt aus
  `conditions` liest). Sofort per 1-Wort-Fix behoben (Commit `0b83521a`). Zwei
  weitere während der Umsetzung gefundene Stolpersteine: `extension RuleMatchMode:
  RuleSelectOption {}` musste von `RuleWizardView.swift` nach
  `SmartFolderEditorView.swift` verschoben (nicht gelöscht) werden, da
  `SmartFolderEditorView.swift`s eigener Match-Mode-Umschalter modulweit auf
  dieser Konformität aufbaut; ein Source-Sniffing-Test in
  `FeedivoAppSceneConfigurationTests.swift` prüfte die exakte alte
  Aufrufsyntax und musste mitgeändert werden. 120/120 relevante Tests grün,
  Build (Debug + Release) grün, genau die bekannten 17 vorbestehenden
  `FeedivoAppSceneConfigurationTests`-Fehlschläge unverändert (keine neuen
  Regressionen). Ausstehend: manuelle 13-Punkte-Live-Verifikationscheckliste
  (Gruppen anlegen/löschen, ODER-Trenner, Migration bei Bestandsregeln,
  Simple-Modus unverändert) durch den Nutzer. Spec:
  `docs/superpowers/specs/2026-07-24-regel-bedingungen-gruppierung-design.md`,
  Plan: `docs/superpowers/plans/2026-07-24-regel-bedingungen-gruppierung.md`.
- 2026-07-24: CLAUDE.md-Korrektur — der Push-Status-Vermerk „lokal auf main,
  NICHT gepusht" beim Eintrag vom 2026-07-23 (Commit `cb60943`, Kollision
  App-Start-Refresh/Hintergrund-Scheduler) war veraltet — der Commit ist
  längst auf `origin/main` (per `git merge-base --is-ancestor` verifiziert).
  Reiner Dokumentations-Nachtrag, keine Code-Änderung.
- 2026-07-23: Bugfix — Kollision zwischen App-Start-Refresh und Hintergrund-Scheduler
  behoben (Nutzer-Report: "Feed-Fehler: Aktualisierung läuft bereits" bei praktisch
  jedem App-Start). Via systematic-debugging: `NSBackgroundActivityScheduler` kennt
  kein `earliestBeginDate`, der allererste Tick feuerte dadurch praktisch sofort und
  kollidierte mit dem separaten "Feeds beim App-Start aktualisieren"-Refresh. Neue,
  direkt testbare `BackgroundRefreshService.isPrematureTick(...)` erzwingt die
  Wartezeit selbst; `FeedViewModel.refreshAllFeeds(sqliteDatabase:isAutomatic:)`
  unterscheidet zusätzlich automatische von nutzerausgelösten Aufrufen als zweite,
  unabhängige Absicherung. TDD (5 neue Tests), 17 bekannte Vorabfehlschläge in
  `FeedivoAppSceneConfigurationTests` unverändert. Details siehe neuer Gotcha oben.
  Commit `cb60943`, gepusht (siehe Korrektur oben).
- 2026-07-23: CLAUDE.md-Korrektur — Zahl der bekannten, vorbestehenden Testfehlschläge in
  `FeedivoAppSceneConfigurationTests.swift` von „15" auf „17" korrigiert (siehe Gotcha oben).
  Fund entstand aus dem Offline-Feature-Entfernen-Plan (Task 4), wo der tatsächliche Lauf
  17 statt der dokumentierten 15 Fehlschläge zeigte — per isoliertem Vorher/Nachher-Vergleich
  gegen den Basis-Commit als reine, unabhängig von diesem Feature entstandene Doku-Drift
  bestätigt, keine Regression.
- 2026-07-20: Offline-Artikel-Download-Feature vollständig entfernt (Backend, DB-Tabelle
  `article_offline` per neuer Migration `v19_drop_article_offline_table`, Kopplung an
  Artikel-Export entkoppelt, 23 unbenutzte L10n-Keys + 3 zugehörige xcstrings-Fehlermeldungs-
  Keys entfernt, Offline-spezifische Tests gelöscht/angepasst). Vier Tasks via
  Brainstorming→Spec→Plan→Subagent-Driven-Development. Entscheidung: endgültig entfernen
  statt reaktivieren (siehe ehemaliger Eintrag unter „Offene Entscheidungen"). Whole-Branch-
  Review (Opus): Ready to merge: Yes, 0 Critical/Important. 3 Minor-Nachbesserungen direkt
  im Anschluss umgesetzt: About-Panel bewarb noch „Offline-Lesen" als Feature (entfernt),
  toter `"article_offline"`-Whitelist-Eintrag in `FeedivoDatabase.debugForeignKeys(for:)`
  entfernt, verbliebene Offline-Erwähnungen in dieser Datei (Projektübersicht, periphery-
  Gotcha-Beispiel `ArticleOfflineRecord.fetchOne`, M3-Milestone-Checkbox) bereinigt. Ein
  vierter Reviewer-Fund war ein Fehlalarm: `L10n.articleExportSourceOffline` ist laut
  Plan-Global-Constraint bewusst unangetastet geblieben (Design-Spec-Entscheidung, die
  Konstante bleibt stehen, nur ihre eine Verwendungsstelle entfiel in Task 1).
- 2026-07-20: CLAUDE.md-Korrektur — 9 veraltete „NICHT gepusht"-Vermerke in „Aktuell in
  Arbeit" (Automatischer Feed-Sprung, NSEvent-Monitor-Fallback + Live-Fix-Runde,
  Ein-/Ausschalter, Pfeiltasten-Navigation, Shortcuts-Erweiterung, Spotlight-Integration,
  Bulk-Benachrichtigungsverwaltung, Benachrichtigungs-Einstellungen) berichtigt — alle
  zugehörigen Commits waren tatsächlich längst auf `origin/main`, per
  `git merge-base --is-ancestor` gegen jeden einzelnen Commit verifiziert. Fund entstand
  dadurch, dass eine frühere Antwort in dieser Session diese Notizen unreflektiert
  übernommen hatte, statt sie gegen den echten Git-Stand zu prüfen — vom Nutzer
  zurecht hinterfragt. **Lehre:** Push-Status-Aussagen aus CLAUDE.md-Notizen nie ungeprüft
  wiedergeben, immer gegen `git log`/`git merge-base --is-ancestor origin/main` verifizieren,
  bevor sie als aktueller Stand kommuniziert werden — Notizen in diesem Dokument werden
  offenbar nicht in jeder Session konsequent nachgezogen, sobald tatsächlich gepusht wird.
- 2026-07-20: Reader-Toolbar frei anpassbar (Feature 19.4) — vollständige Details siehe
  „Aktuell in Arbeit" oben, hier nicht dupliziert. Commits `18557ba..5beab9ab` auf `main`,
  gepusht (`ada4d48d..5beab9ab`). FEATURES.md 19.4 von „⏸️ Zurückgestellt" auf
  „✔️ Fertig" aktualisiert.
- 2026-07-16: Shortcuts-Erweiterung (modifier-freie Kombinationen + 8 fehlende
  Menü-Funktionen) — vollständige Details siehe „Aktuell in Arbeit" oben, hier nicht
  dupliziert. Commits `eca8f5e..928b4c6` (9 Commits, davon 1 Selbstkorrektur-Fix in
  Task 2) auf `main`, NICHT gepusht. Ausstehend: 5-Punkte-Live-Verifikationscheckliste.
- 2026-07-16: `FeedStore.sidebarFeeds()`-Performance-Fix + feed_logs-
  Bereinigung (Retention) — VOLLSTÄNDIG ABGESCHLOSSEN, gepusht auf
  `origin/main` (`ee7aef28d..1b1662db8`). Ausgangspunkt: Performance-Lasttest
  vom 2026-07-15 fand einen 10,9-Sekunden-Flaschenhals bei 500 Feeds in
  `FeedStore.sidebarFeeds()` (`Feedivo/Stores/FeedStore.swift`) — Ungelesen-
  Zähler und letzter Feed-Fehler wurden je als korrelierte Subquery pro Feed
  neu berechnet. Via Brainstorming→Spec→Plan→Subagent-Driven-Development
  (1 Task) behoben: zwei `WITH`-CTEs (`unread_counts` via `GROUP BY`,
  `latest_feed_logs` via `ROW_NUMBER() OVER (PARTITION BY feedID ORDER BY
  createdAt DESC)`) ersetzen die Subqueries — Laufzeit auf ~26 ms gesenkt.
  Whole-Branch-Review (Opus): „Ready to merge: With fixes" — 1 Important-
  Finding: die Tabelle `feed_logs` wird nirgends bereinigt (kein `DELETE FROM
  feed_logs` im gesamten Code), wächst dadurch unbegrenzt; die neue
  `latest_feed_logs`-CTE liest bei jedem Aufruf die komplette Tabelle
  (O(Gesamtzahl Zeilen)) statt wie die alte Subquery nur einen indexierten
  Pro-Feed-Zugriff (O(log n)) — der Benchmark-Seed legte zudem gar keine
  `feed_logs`-Zeilen an, das Risiko war komplett ungemessen. Nutzerentscheid:
  statt Query zurückzurollen oder nur den Benchmark zu erweitern, echtes
  `feed_logs`-Pruning einführen — eigener Brainstorming→Spec→Plan→
  Subagent-Driven-Development-Zyklus (4 Tasks): neue
  `FeedLogRetentionSettings` (Standard 30 Tage, Werte 7/14/30/60/90
  konfigurierbar), `FeedLogStore.deleteOlderThan(_:)` (reines `DELETE`),
  Integration in `ArticleRetentionCleanupService.runAutomaticCleanup(...)` —
  läuft bewusst **unabhängig** von `articleRetentionIsEnabled` (das
  standardmäßig AUS ist; sonst bliebe das Wachstumsproblem für die meisten
  Nutzer ungelöst), kein Eintrag in `CleanupRunHistoryStore`/Toast (reines
  internes Housekeeping), neue Einstellungs-Zeile in `CleanupSettingsView`.
  Wirksamkeitsnachweis: neuer Performance-Test seedet 500 Feeds/100'000
  `feed_logs`-Zeilen, bereinigt auf 500 (1 pro Feed), misst `sidebarFeeds()`
  danach bei ~1,9 ms. Finaler Whole-Branch-Review (Opus): „Ready to merge:
  Yes", 0 Critical/Important, 2 Minor (dokumentiert, kein Fix nötig: `?? now`-
  Fallback bei theoretischem `Calendar`-Fehler semantisch verkehrt aber
  praktisch unerreichbar; feed_logs-Pruning bleibt an die bestehenden
  Zeitplan-Trigger aus Feature 17.3a gekoppelt — bei komplett deaktivierten
  Triggern wächst die Tabelle zwischen manuellen Bereinigungen weiter, sicher
  solange App-Start-Trigger Standard AN bleibt). Spec/Plan:
  `docs/superpowers/specs/2026-07-16-sidebar-feeds-performance-design.md`,
  `docs/superpowers/plans/2026-07-16-sidebar-feeds-performance.md`,
  `docs/superpowers/specs/2026-07-16-feed-logs-retention-design.md`,
  `docs/superpowers/plans/2026-07-16-feed-logs-retention.md`. Manuelle
  Live-Verifikation des neuen Aufbewahrungsdauer-Pickers in den
  Einstellungen vom Nutzer bestätigt (2026-07-16): funktioniert.
- 2026-07-16: Feature 17.3a (Bereinigung — History, Zeitplan und Hinweis) —
  VOLLSTÄNDIG ABGESCHLOSSEN inkl. 2 Nachträge, gepusht auf `origin/main`
  (`92a02b478..ee7aef28d`). Kern-Feature via Brainstorming→Spec→Plan→
  Subagent-Driven-Development umgesetzt: History der letzten 10
  Bereinigungsläufe (neue Tabelle `cleanup_runs`, Migration v18,
  `CleanupRunHistoryStore`), konfigurierbarer Zeitplan mit drei unabhängig
  kombinierbaren Auslösern (App-Start, Wochentag+Uhrzeit mit Nachhol-Prüfung,
  App-Beenden best-effort), In-App-Toast (`CleanupToastSignal`) bei
  tatsächlich gelöschten Artikeln. **Nachtrag 1** (Brainstorming→Spec→Plan→
  Inline-Ausführung): Wochentag-Auswahl von Einzel- auf Mehrfachauswahl per
  Checkboxen umgestellt. **Nachtrag 2** (Brainstorming→Spec→Plan→Inline-
  Ausführung): die drei Zeitplan-Auslöser als Button+Popover mit Checkboxen
  zusammengefasst (`.menuActionDismissBehavior(.disabled)` ist auf macOS
  nicht verfügbar — deshalb Popover statt `Menu`, analog zum bestehenden
  Tag-Filter-Popover in `ArticleSearchWindowView`), Bereinigungsverlauf aus
  den Einstellungen in ein eigenes Fenster verlagert
  (`CleanupHistoryWindowView`, `Window`-Scene analog zum Statistik-Fenster).
  Direkt im Anschluss drei kleine Live-Nachbesserungen am Wochentag-Layout
  (Montag zuerst statt Sonntag, 3 Wochentage pro Zeile statt einer pro Zeile,
  linksbündig statt durch zwei konkurrierende flexible Spacer zur Mitte
  gedrängt). Ausstehend: manuelle Live-Verifikation (Popover-Mehrfachauswahl,
  Wochentag-Layout, Verlaufsfenster-Inhalt) durch den Nutzer.
- 2026-07-15: Benachrichtigungs-Einstellungen überarbeitet — via Brainstorming +
  Spec + Plan + Subagent-Driven-Development (5 Tasks) umgesetzt. Details siehe
  „Aktuell in Arbeit" oben, hier nicht dupliziert. Commits `8997a0bed..c9bc761f0`
  auf `main`, NICHT gepusht (Nutzerentscheid: erst manuelle Live-Verifikation).
- 2026-07-15: Automatisierbaren Sidebar- und M4-Regressionslauf durchgeführt.
  Sidebar-Baum, Drop-Policy, Pasteboard, Tag-/Ordner-Sortierung und Smart-Folder-
  Gruppengrenzen sind grün; ebenso Feed-Anlage/Refresh, Timeline/Status, Reader,
  Tags/Regeln, Bereinigung, OPML, Export, Onboarding, URL-Schema, Menubar,
  Migrationen, Offline-Unterbau und Benachrichtigungen. Sechs veraltete
  Store-Test-Fixtures an die produktive SQLite-Wahrheit angepasst: Status-Tests
  legen wegen des Fremdschlüssels zuerst Feed und Artikel an; Sidebar-Tests
  erzeugen echte Artikelstatusdaten statt nur `feeds.unreadCount` zu setzen.
  Zwei Refresh-Tests verwenden aktuelle Publikationsdaten, weil nur tatsächlich
  neue Artikel im Refresh-Status und in Benachrichtigungen zählen. Der manuelle
  13-Punkte-Sidebar-Livetest bleibt ausstehend.

- 2026-07-15: Performance-Zielbestand mit 500 Feeds und 100'000 Artikeln im
  Debug- und optimierten Release-Testprofil sowie mit Instruments Time Profiler
  gemessen. Timeline, FTS, Count und tiefste Pagination liegen bei etwa 5–133 ms;
  Keyset-Pagination ist damit vorerst nicht nötig. Neuer Blocker ist
  `FeedStore.sidebarFeeds()` mit rund 10,9 s: Die korrelierte Ungelesen-
  Unterabfrage wird pro Feed wiederholt. Nächster Schritt ist ein einmalig nach
  `feedID` gruppierter Count-Join, danach UI-Messung. Bericht:
  `docs/performance/sqlite-large-dataset-results.md`.

- 2026-07-15: Pflichtlücken aus dem Performance-/Integrationsaudit umgesetzt:
  Datenbankfehler blockieren den Produktivinhalt statt einen scheinbar leeren
  In-Memory-Start zu erlauben; die Timeline lädt asynchron über GRDB in
  SQL-sortierten 200er-Seiten mit vollständigem Ungelesen-Zähler nach;
  Tag-Zuweisung und Artikelfenster sind im Zeilen-Kontextmenü verdrahtet;
  Smart-Folder-Badge-/Lese-Defaults nutzen eine gemeinsame Policy; iCloud Sync
  bleibt bis zu einem echten Backend sichtbar deaktiviert. Relevante Store-,
  State-, Policy- und Source-Integrationstests ergänzt.
- 2026-07-15: Performance- und Feature-Integrationsaudit des produktiven
  SQLite-/GRDB-Pfads dokumentiert und mit der lokalen NetNewsWire-Referenz
  verglichen. Bericht:
  `docs/performance/feedivo-performance-feature-integration-audit-2026-07-15.md`.
  Priorisierte Befunde: stiller In-Memory-Fallback bei Datenbankfehlern, globales
  500-Artikel-Limit ohne Pagination, Sortierung erst nach dem SQL-Limit,
  synchroner GRDB-Read im Main-Actor-Loader, unverdrahtete Kontextaktionen,
  irreführender iCloud-Status sowie uneinheitliche Smart-Folder-Policies. Der
  bestehende NetNewsWire-Mechanikvergleich wurde auf den aktuellen SQLite-only-
  Stand eingeordnet. Keine Produktivcode-Änderung in diesem Arbeitsschritt.
- 2026-07-15: Sidebar auf AppKit NSOutlineView umgestellt (ADR-008) + Ordner-Sortier-Menü
  + TEMPDEBUG-Cleanup — vollständige Details siehe „Aktuell in Arbeit" oben, hier nicht
  dupliziert. Commits `3cc693c1f..7344983d2` auf `main`, NICHT gepusht.
- 2026-07-14 (später Vormittag): Nutzer-Report — letzter ungelesener Artikel in Smart
  Folder "Ungelesen" verschwand beim Lesen sofort komplett aus der Liste, statt wie
  gewohnt sticky bis zum Ordnerwechsel sichtbar zu bleiben. Via systematic-debugging
  behoben: rein logik-basierte Reproduktionsversuche (Fixture- und State-Ebene, beide
  bestanden anstandslos) fanden den Bug NICHT — erst Live-`OSLog`-Diagnose-Logging
  (TEMP-DEBUG-Pattern) + `log show`-Auswertung + ein vom Nutzer geschickter Screenshot
  deckten auf, dass `articleContent`s äußere Zustandsweiche eine zweite, nicht
  sticky-bewusste "Liste leer?"-Prüfung (`state.rows.isEmpty`) enthielt, die den
  korrekten `articleList`-Pfad in genau diesem Fall überging. Fix (Commit `18da80d`):
  Weiche auf `effectiveRows.isEmpty` umgestellt, ein Wort. Zwei neue Regressionstests
  (`ArticleListQueryTests`, `SQLiteFeedArticleListStateTests`) dokumentieren das
  korrekte Merge-Verhalten für dieses Szenario. Neuer Gotcha oben. Vom Nutzer im
  laufenden Betrieb bestätigt behoben. Lokal auf main, NICHT gepusht.
- 2026-07-14 (Vormittag): Bereinigte Artikel bleiben dauerhaft weg +
  Start-Reihenfolge-Fix — via Brainstorming + Spec + Plan +
  Subagent-Driven-Development (4 Tasks + 1 Fix-Runde) umgesetzt. Spec:
  `docs/superpowers/specs/2026-07-14-bereinigung-dauerhaft-design.md`, Plan:
  `docs/superpowers/plans/2026-07-14-bereinigung-dauerhaft.md`. Zwei
  zusammenhängende Bugs behoben, beide Folge-Diagnosen nach den
  Befund-A/B/C-Fixes:
  - **Komponente 1 (Start-Reihenfolge, Task 4):** `cleanupExpiredArticlesIfNeeded()`
    lief bisher in einem eigenen, unabhängigen `.task`-Block in `FeedivoApp.swift`,
    ungeordnet relativ zu einem möglichen Start-Refresh (`ContentView.
    refreshFeedsOnLaunchIfNeeded()`) — der Start-Refresh konnte gerade bereinigte
    Artikel sofort wieder einfügen, bevor der Nutzer sie als gelöscht sah. Fix:
    Aufruf aus dem `.task`-Block entfernt, stattdessen als allererster Schritt in
    `ContentView.handleContentAppear()` aufgerufen (beide laufen synchron auf dem
    MainActor, damit ist die Reihenfolge garantiert).
  - **Komponente 2 (dauerhaftes Wiedereinfügen, Tasks 1-3):** `ArticleStore.upsert()`
    prüfte nur, ob ein Artikel aktuell in der `articles`-Tabelle existiert — ein
    von der Bereinigung gelöschter Artikel fehlt dort, also fügte jeder folgende
    Feed-Refresh ihn erneut ein, sobald der Feed ihn weiterhin lieferte. Fix: neue
    Migration v14 + Flag `wasRemovedByRetention` auf `article_identity_history`
    (Task 1); `ArticleRetentionCleanupService` setzt das Flag beim Bereinigen auf
    `true`, `ArticleRetentionConfiguration` modulweit sichtbar gemacht (Task 2);
    `ArticleStore.upsert()` prüft das Flag vor dem Insert eines "neuen" Artikels
    gegen die *aktuellen* Bereinigungs-Einstellungen (global oder Feed-Override)
    und überspringt den Insert, falls der Artikel weiterhin abgelaufen wäre —
    ändert der Nutzer später die Einstellungen, erscheint der Artikel regulär
    wieder (Task 3).
  - Alle vier Task-Reviews clean im ersten Anlauf (0 Critical/Important/Minor
    je Task). Finaler Whole-Branch-Review (Opus) fand 1 Important-Finding: der
    Plan übernahm aus der Design-Spec-Pseudocode `input.publishedAt ??
    input.arrivedAt` als Datumsfallback — bei publishedAt-losen, erneut
    zugestellten Artikeln ist `arrivedAt` aber das frische Jetzt des aktuellen
    Refreshs, nicht das ursprüngliche Erstsichtungsdatum, wodurch diese Kategorie
    der Sperre entkam (neuer Gotcha oben). Nutzerentscheidung: sofort fixen. Fix
    (Commit `88db711`): `history.firstSeenAt` statt `input.arrivedAt`, neuer
    Regressionstest. Re-Review (Opus) bestätigt: „Ready to merge: Yes". Nebenbefund
    (2 unabhängige Untersuchungen, siehe korrigierter Gotcha oben): `CLAUDE.md`
    dokumentierte 9 vorbestehende Fehlschläge in
    `FeedivoAppSceneConfigurationTests.swift`, tatsächlich sind es 15 — reine
    Dokumentations-Drift, keine Regression. Commits `d4909eb75..88db7116f`
    (5 Commits) — gepusht (`88db7116f`), zusammen mit den zuvor unpushed
    Befund-C-Commits (siehe unten).
- 2026-07-13/14 (Nacht): Befund C (persistenter Status für automatische
  Bereinigung) — via Brainstorming + Plan + Subagent-Driven-Development
  (3 Tasks) umgesetzt. Spec:
  `docs/superpowers/specs/2026-07-14-bereinigung-automatischer-status-design.md`,
  Plan: `docs/superpowers/plans/2026-07-14-bereinigung-automatischer-status.md`.
  Details siehe „Aktuell in Arbeit" oben (Befund-C-Absatz) — vollständige
  Beschreibung von Datenschicht (`runAutomaticCleanup`), umgestellten
  Aufrufern und UI-Status-Block dort bereits festgehalten, hier nicht
  dupliziert. Alle drei Tasks clean im ersten Anlauf. Whole-Branch-Review
  (Opus) fand 1 Important-Finding (fehlende L10n-Katalogeinträge für 7 neue
  indirekte `L10n`-Keys, siehe neuer Gotcha oben), Fix-Runde behoben und
  re-verifiziert. Commits `b902998..61b4cb3` (4 Commits) — gepusht
  (zusammen mit dem obigen Bereinigung-dauerhaft-Feature).
- 2026-07-13 (spät Abend): Tags direkt im Reader-Header hinzufügen — via
  Brainstorming + Plan + Subagent-Driven-Development (3 Tasks) umgesetzt.
  Spec: `docs/superpowers/specs/2026-07-13-reader-tags-hinzufuegen-design.md`,
  Plan: `docs/superpowers/plans/2026-07-13-reader-tags-hinzufuegen.md`.
  - Die komplette Tag-Zuweisungs-/Erstellungs-UI (Toggle-Pillen für bestehende
    Tags + Namensfeld/Farbauswahl für neue Tags), die bisher nur im
    Metadaten-Inspector existierte, wurde in einen neuen wiederverwendbaren
    Baustein `ArticleTagAssignmentView` extrahiert (Task 1). Der Inspector
    nutzt ihn seither selbst (Task 2, reiner Refactor, keine
    Verhaltensänderung).
  - Reader-Header (`SQLiteReaderView.swift`) bekommt einen neuen "+"-Button
    am Ende der Ordner-/Tag-Chip-Zeile, der `ArticleTagAssignmentView` in
    einem Popover öffnet (Task 3). Die Chip-Zeile wird dafür bewusst jetzt
    immer gerendert (vorher: gar keine Zeile bei fehlendem Ordner/Tags) —
    sonst könnte kein erster Tag direkt aus dem Header heraus angelegt
    werden. Tooltip nutzt den bereits vorhandenen L10n-Key
    `L10n.articleAssignTagCommand` statt eines neuen Keys.
  - Alle drei Tasks clean im ersten Anlauf (keine Fix-Runde nötig). Finaler
    Whole-Branch-Review (Opus) fand 1 Important-Finding: `snapshotTags` ist
    ein unveränderlicher Prop, der erst asynchron über den Elternview
    nachlädt — nach dem Entfernen eines Tags blieb dessen Toggle-Pille im
    Popover/Inspector fälschlich als "aktiv" markiert (Chip-Zeile im Header
    selbst war davon nicht betroffen, da sie direkt `snapshot.tags` liest).
    Fix: `.onChange(of: snapshotTags) { loadTags() }` ergänzt, Re-Review
    (Opus) bestätigt behoben, kein Zyklus. Gepusht (`e81d4a3e0..848e60037`).
- 2026-07-13 (Abend): Mehrfach-Tag-Filterung in der Artikelsuche — via
  Brainstorming (inkl. Mockup-Vergleich über den Visual-Companion-Server für
  die Popover-UI) + Plan + Subagent-Driven-Development (2 Tasks) umgesetzt.
  Spec: `docs/superpowers/specs/2026-07-13-tag-suche-design.md`, Plan:
  `docs/superpowers/plans/2026-07-13-tag-suche.md`.
  - Bestehende Einzelauswahl-Tag-Filterung (`tagID: UUID?`) in
    `ArticleSearchWindowState`/`ArticleSearchFilters`/`ArticleSearchQuery`
    verallgemeinert auf `tagIDs: Set<UUID>` + neues
    `ArticleSearchTagMatchMode`-Enum (`.any`/`.all`).
  - **SQL-Schicht** (`ArticleStore.searchArticles(state:)`) nutzt eine
    gemeinsame Subquery (Tags aus `article_tags` UNION `feed_tags` — erhält
    die bestehende "Tag hängt am Artikel ODER am Feed"-Semantik), nur der
    äußere Vergleich unterscheidet sich: `EXISTS` für "Mind. einer",
    `COUNT(DISTINCT tagID) = N` für "Alle".
  - **UI:** Der bisherige Einzel-`Picker` wird durch einen "Tags"/"Tags (N)"
    -Button mit Popover ersetzt (Any/All-Segmented-Control oben, Checkbox pro
    Tag darunter, Popover bleibt beim Toggeln offen).
  - Cross-Task-Besonderheit: Task 1 (Datenmodell-Umbenennung) musste
    zusätzlich einen minimalen, bewusst temporären Kompatibilitäts-Adapter in
    der UI-Datei ergänzen, damit die App zwischen den beiden Commits
    kompilierfähig blieb — von Task 2 vollständig durch die finale Popover-UI
    ersetzt, vom Whole-Branch-Reviewer als korrekte Sequenzierungsentscheidung
    bestätigt (erhält "jeder Commit baut"-Invariante).
  - Beide Tasks clean im ersten Anlauf (keine Fix-Runde nötig). Finale
    Whole-Branch-Review (Opus): Ready to merge: Yes, 0 Critical/Important,
    SQL-Injection- und Argument-Bindungsreihenfolge explizit verifiziert.
    Gepusht (`77ce3072e..f592d644c`).
- 2026-07-13 (Nachmittag): App-Icon erneuert. Vom Nutzer per Icon-Kitchen-Export
  (ZIP mit `macos/AppIcon16.png` … `AppIcon1024.png` + `.icns`) bereitgestellt,
  alle 10 in `Feedivo/Assets.xcassets/AppIcon.appiconset/Contents.json`
  referenzierten Größen (16px–1024px) 1:1 ersetzt — Dateinamen passten exakt,
  `Contents.json` selbst unverändert. Nach dem Rebuild zeigte Dock/Finder
  zunächst weiterhin das alte Icon (kein Build-Fehler — `CFBundleIconFile`/
  `CFBundleIconName`/`ASSETCATALOG_COMPILER_APPICON_NAME` zeigten korrekt auf
  den Asset-Catalog, keine laufende Alt-Instanz gefunden), klassischer
  macOS-Icon-Cache-Effekt: `killall Dock`/`killall Finder` allein reichte
  nicht, erst ein tieferer, sudo-basierter Reset des systemweiten
  IconServices-Caches (`~/Library/Caches/com.apple.iconservices.store` +
  `com.apple.dock.iconcache`/`com.apple.iconservices` unter
  `/private/var/folders/`) behob es — vom Nutzer bestätigt. Committed und
  gepusht (`05425bbf3`).
- 2026-07-13 (Mittag): Feeds in der Sidebar umbenennbar — via
  Brainstorming+Plan+Subagent-Driven-Development (2 Tasks) umgesetzt, direkter
  Nachfolger des Ordner-Umbenennen-Features vom selben Tag. Spec:
  `docs/superpowers/specs/2026-07-13-feed-umbenennen-design.md`, Plan:
  `docs/superpowers/plans/2026-07-13-feed-umbenennen.md`.
  - **`FeedStoreError` bekommt `LocalizedError`-Konformität** —
    `.emptyTitle` liefert jetzt `L10n.feedRenameEmptyName` statt einer
    generischen Systemmeldung. Das behebt nebenbei einen Bestandsfehler im
    schon länger existierenden `FeedRenameView`-Dialog (zeigte bei leerem
    Namen bisher ebenfalls die hässliche generische Meldung, da niemand
    `errorDescription` konsumierte). Neuer `.databaseUnavailable`-Fall als
    Pendant zum Ordner-Feature.
  - **`FeedRowView` verliert den umschließenden `Button`** — dasselbe
    Kollisionsproblem wie bei Ordnern (ein Klick ins Inline-TextField
    während der Bearbeitung würde sonst vom `Button` mit abgefangen).
    Übernimmt Auswahl (Einzelklick) und Bearbeitungsstart (Doppelklick auf
    den Namen) jetzt selbst, baut die Auswahl-/Rahmen-Optik von
    `SidebarRowButtonStyle` manuell nach (inkl. eines zuvor nur implizit
    ererbten `.foregroundStyle` auf dem Titel-Text, das beim Button-Wegfall
    sonst ersatzlos verloren gegangen wäre). `SidebarRowButtonStyle` selbst
    bleibt unverändert und wird weiterhin von Tags/Intelligenten Ordnern
    genutzt. Bewusste kosmetische Einbuße (mit dem Nutzer abgestimmt): die
    kurze Press-Flash-Hover-Animation beim Klicken-und-Halten entfällt für
    Feed-Zeilen (Tags/Smart-Folders behalten sie, da sie weiterhin über
    `SidebarRowButtonStyle` laufen).
  - Bestehender „Feed umbenennen…"-Kontextmenü-Eintrag bleibt inhaltlich
    unverändert und öffnet weiterhin den vollen `FeedRenameView`-Dialog
    (Original-Titel-Anzeige + „Ursprung wiederherstellen") — kein
    zusätzlicher Menüpunkt, um das Kontextmenü nicht zu überladen.
  - Beide Tasks clean im ersten Anlauf (kein Fix-Round nötig, anders als
    beim Ordner-Feature). Finale Whole-Branch-Review (Opus): Ready to merge:
    Yes, 0 Critical/Important. Ein vom Reviewer empfohlener, noch
    ausstehender visueller Sanity-Check: dass die Auswahl-Hervorhebung bei
    Feeds weiterhin die volle Zeilenbreite einnimmt (per SwiftUI-
    Layout-Logik als korrekt eingeschätzt, aber nicht live beobachtet — kein
    computer-use für native macOS-Apps in dieser Umgebung verfügbar).
    Gepusht (`8bb906f32..062635939`).
- 2026-07-13 (später Vormittag): Ordner in der Sidebar umbenennbar — via
  Brainstorming+Plan+Subagent-Driven-Development (2 Tasks) umgesetzt. Spec:
  `docs/superpowers/specs/2026-07-13-ordner-umbenennen-design.md`, Plan:
  `docs/superpowers/plans/2026-07-13-ordner-umbenennen.md`.
  - **Neue Store-Methode `FeedFolderStore.renameFolder(from:to:)`** — aktualisiert
    transaktional beide Speicherorte des namensbasierten Ordner-Modells
    (`feed_folders`-Datensatz UND alle `feeds.folderName`-Werte), case-insensitive
    Kollisionsprüfung (Duplikat wird abgelehnt, kein automatisches Zusammenführen),
    reine Großschreibungskorrektur des eigenen Namens ist erlaubt. Neuer Fehlertyp
    `FeedFolderRenameError` (`.emptyName`, `.duplicateName`, `.databaseUnavailable`),
    6 Unit-Tests gegen echte In-Memory-GRDB-DB.
  - **Inline-Umbenennen-UI in `SidebarFolderSection`** — Doppelklick auf den
    Ordnernamen (Einzelklick klappt weiter ein/aus, beide Gesten sitzen bewusst auf
    derselben View, damit SwiftUI sie korrekt disambiguiert) sowie neuer
    Kontextmenü-Eintrag „Ordner umbenennen" starten ein natives `TextField`
    (`.textFieldStyle(.roundedBorder)`, sieht wie ein richtiges Eingabefeld aus —
    Nutzer-Nachbesserung nach der ersten Umsetzung, die noch einen selbstgebauten
    Hintergrund/Rahmen hatte). Enter und Fokusverlust bestätigen gleichwertig,
    Escape bricht ab; bei ungültigem Namen (leer/Duplikat) bleibt die Bearbeitung
    mit rotem Rahmen + Fehlertext aktiv. `collapsedFolderNames` wird beim
    Umbenennen migriert, damit ein eingeklappter Ordner nicht überraschend wieder
    aufklappt.
  - Zwei Task-Reviews: Task 1 clean im ersten Anlauf, Task 2 nach 1 Fix-Runde
    (fehlender roter Rahmen ums TextField + eine konkurrierende Tap-Geste, die
    Klicks im TextField während der Bearbeitung fälschlich als Ein-/Ausklapp-Klick
    abgefangen hätte — beides plan-mandated Lücken, keine Nutzer-Design-Entscheidung
    nötig). Finale Whole-Branch-Review (Opus): Ready to merge: Yes, 0
    Critical/Important. Gepusht (`b9d10255e..a0ee3db11`).
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
