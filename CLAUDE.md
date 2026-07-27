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

---

## Bekannte Gotchas & Fallstricke

> Diese Liste wächst während der Entwicklung. Immer ergänzen!

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
- **`FeedStore.sidebarFeeds()` ignoriert den gespeicherten `feeds.unreadCount`-Wert
  vollständig — berechnet stattdessen immer per Subquery neu:** Zwei bestehende Tests,
  `sidebarSnapshotsAreSortedByTitle` und `sidebarSnapshotsCanHideReadFeeds` in
  `SQLiteFeedStoreTests.swift`, konstruieren `FeedRecord`s mit einem gesetzten
  `unreadCount`-Feld, ohne passende `articles`/`article_statuses`-Zeilen einzufügen — die
  live per Subquery berechnete `unreadCount` in der Snapshot-Antwort ist deshalb immer 0,
  nicht der im Test erwartete Wert, wodurch beide Tests fehlschlagen. Gefunden und per
  Vorher/Nachher-Worktree-Vergleich als bereits vor dem Feeds-Drag-&-Drop-Feature (2026-07-14)
  bestehend verifiziert (Task-3-Review, Commit `873c00231` als Basis) — keine Regression
  durch `sortIndex`/`moveFeed`. Noch nicht gefixt, bewusst als bekannter, unabhängiger
  Vorab-Fehlschlag dokumentiert (analog zu den 15 vorbestehenden Fehlschlägen in
  `FeedivoAppSceneConfigurationTests.swift` und den 2 flaky-unter-Last-Tests in
  `FeedViewModelTests.swift`).
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

---

## GitHub

- **Repo:** https://github.com/martinfelder/feedivo-mac (private)
- **Branch-Strategie:** `main` = stabil, direkt bearbeitet (kein durchgängiges Feature-Branch-
  Modell mehr in der aktuellen Praxis); vereinzelt längerlebige Branches für größere,
  eigenständige Vorhaben (z. B. `codex/sqlite-grdb-foundation`)
- **Push-Konvention:** Nie ohne explizite Nutzerbestätigung nach `origin/main` pushen

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
  grün, Release-relevanter Debug-Build grün. Noch offen aus demselben Vergleich (nicht in
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
