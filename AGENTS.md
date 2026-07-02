# AGENTS.md — Feedivo macOS

> Diese Datei ist das Projektgedächtnis für Codex und Codex.ai.
> Sie wird bei jedem Gespräch automatisch geladen.
> **Immer aktuell halten wenn sich Entscheidungen ändern!**

---

## Projektübersicht

**App-Name:** Feedivo
**Root-Ordner:** FeedivoMac
**Entry Point:** FeedivoApp.swift
**Bundle ID:** ch.martin.Feedivo
**Typ:** Nativer macOS RSS Reader
**Entwickler:** Solo (Martin)
**Plattform:** macOS 14 Sonoma+
**Status:** In Development
**Aktueller Milestone:** M4 – Polish & Release

Feedivo ist ein nativer macOS RSS Reader mit Tags, automatischen Regeln und iCloud Sync.
Ziel ist eine schöne, schnelle Mac-App die sich "mac-like" anfühlt — kein iOS-Port, keine
Electron-App. Echtes AppKit-Feeling via SwiftUI für macOS.

---

## Entwickler-Kontext

- Entwickler-Hintergrund: PowerShell / IT-Administration (kein App-Entwickler)
- Swift/Xcode-Level: Anfänger — hat bereits Timivo (iOS) gebaut
- Sprache für Kommentare im Code: Deutsch mit echten Umlauten (`ä`, `ö`, `ü`, `ß`);
  keine Umschreibungen wie `ae`, `oe`, `ue`, `ss`, außer technische Namen/Identifier
  erzwingen es.
- IDE: Xcode 26
- Versionskontrolle: Git + GitHub
- Workflow: Codex CLI + Codex.ai (dieses File als Kontext)

> **Für Codex:** Erkläre Entscheidungen immer kurz. Kein "magic code" ohne Erklärung.
> Kommentare im Code auf Deutsch. Lieber ein bisschen mehr erklären als zu wenig.

---

## Codex-Arbeitsregeln und Projektgedächtnis

> **Wichtig:** Diese Regeln gelten für jede neue Codex-/Codex.ai-Session. Ziel ist,
> dass der Projektstand nicht nur im Chat, sondern dauerhaft im Repo-Gedaechtnis bleibt.

### Session-Start-Checkliste

Bei jeder neuen Session zuerst:

1. `AGENTS.md` vollständig lesen.
2. Falls vorhanden `FEATURES.md` im Root lesen, wenn es um Planung, Roadmap oder Features geht.
3. `git status --short --branch` prüfen.
4. Relevante Swift-Dateien lesen, bevor Code geaendert wird.
5. Den aktuellen Milestone und "Aktuell in Arbeit" gegen den Code abgleichen.

### Bei jeder Code- oder Feature-Änderung

Nach jeder relevanten Änderung prüfen und bei Bedarf aktualisieren:

1. `AGENTS.md`:
   - Implementierter Code
   - Milestone-Plan
   - Aktuell in Arbeit
   - Letzte Änderungen
   - Bekannte Gotchas / ADRs
2. `FEATURES.md`:
   - Feature-Status
   - Prioritaet
   - offene Entscheidungen
   - Empfehlungen oder bewusst zurückgestellte Punkte
3. Tests/Build:
   - Vor Abschluss mindestens den passenden `xcodebuild`-Befehl laufen lassen.
   - In der finalen Antwort exakt nennen, was geprüft wurde und ob es erfolgreich war.
4. Git:
   - Nach abgeschlossenen, verifizierten Code-/Feature-Änderungen automatisch einen
     Commit erstellen, sofern der User nicht ausdrücklich etwas anderes sagt.
   - Lokale Xcode-Zustände wie `xcuserdata/.../UserInterfaceState.xcuserstate`
     nicht committen.

### Dokumentationsprinzip

- Entscheidungen kurz begruenden, besonders wenn Features verschoben oder vereinfacht werden.
- Keine Roadmap stillschweigend ändern. Immer in `AGENTS.md` und/oder `FEATURES.md` nachfuehren.
- Wenn eine User-Entscheidung fällt, diese als Entscheidung dokumentieren, nicht nur im Chat beantworten.
- Wenn der Code vom Projektgedaechtnis abweicht, zuerst das Projektgedaechtnis korrigieren oder die Abweichung klar melden.

---

## Technologie-Stack

| Bereich | Technologie | Version / Hinweis |
|---|---|---|
| UI Framework | SwiftUI (macOS) | Kein AppKit direkt |
| Architektur | MVVM | `@Observable` Macro (kein ObservableObject) |
| Navigation | NavigationSplitView | 3-Spalten: Sidebar / Liste / Detail |
| Persistenz | SwiftData | Kein Core Data |
| iCloud Sync | CloudKit via SwiftData | Beta in Arbeit; Aktivierung per Einstellung + Neustart |
| Netzwerk | URLSession + async/await | Kein Alamofire, kein Combine |
| RSS-Parsing | FeedKit | Swift Package, URL: https://github.com/nmdias/FeedKit |
| Bilder | CachedRemoteImageView + ImageCacheService | Lokaler Disk-Cache + NSCache, kein Kingfisher |
| Lokalisierung | String Catalog + `String(localized:)` | Deutsch, Englisch, Französisch, Italienisch |
| Background Refresh | NSBackgroundActivityScheduler | Basis implementiert; läuft systemfreundlich solange App läuft/im Hintergrund ist |
| Mindest-macOS | macOS 14.0 Sonoma | SwiftData + @Observable Macro |

---

## Projektstruktur

```
FeedivoMac/
├── Feedivo/
│   ├── App/
│   │   ├── FeedivoApp.swift            # @main Entry Point, .modelContainer Setup ✅
│   │   ├── ArticleCommands.swift       # macOS Artikel-Menü + Tastaturkuerzel ✅
│   │   ├── ArticleCommandActions.swift # FocusedValues für Artikelaktionen ✅
│   │   ├── ViewCommands.swift          # macOS Darstellung-Menü für Artikelsortierung ✅
│   │   ├── FeedCommands.swift          # macOS Feed-Menü ✅
│   │   └── FeedCommandActions.swift    # FocusedValues für Feedaktionen ✅
│   │
│   ├── Models/                         # SwiftData @Model Klassen — alle fertig ✅
│   │   ├── Feed.swift
│   │   ├── FeedFolder.swift            # Leere/angelegte Sidebar-Ordner ✅
│   │   ├── FeedLogEntry.swift          # Feed-Abruf- und Fehlerlog ✅
│   │   ├── Article.swift
│   │   ├── Tag.swift
│   │   ├── Rule.swift                 # Regeln inkl. sortOrder für Auswertungsreihenfolge ✅
│   │   ├── RuleAction.swift            # Regel-Aktionen Tag zuweisen / Artikel ausblenden / Benachrichtigung ✅
│   │   ├── RuleNotificationPriority.swift # Priorität für Regel-Benachrichtigungen ✅
│   │   ├── RuleCondition.swift         # Mehrfachbedingungen für Regeln ✅
│   │   ├── RuleMatchMode.swift         # AND/OR-Auswertung für Regeln ✅
│   │   ├── RuleConditionField.swift    # Regel-Felder title/summary/feedTitle ✅
│   │   ├── RuleConditionOperator.swift # Regel-Operatoren ✅
│   │   ├── SmartFolder.swift           # Intelligente Ordner inkl. Reihenfolge/Sidebar/Darstellung ✅
│   │   ├── SmartFolderAppearance.swift # Icon-/Farbauswahl für intelligente Ordner ✅
│   │   ├── SmartFolderCondition.swift  # Bedingungen für intelligente Ordner ✅
│   │   ├── SmartFolderConditionField.swift # Smart-Folder-Felder ✅
│   │   ├── SmartFolderConditionOperator.swift # Smart-Folder-Operatoren ✅
│   │   ├── SmartFolderDateValue.swift  # Datumswerte heute/diese Woche ✅
│   │   └── SmartFolderStatusValue.swift # Statuswerte gelesen/Stern/Archiv/Ausgeblendet ✅
│   │
│   ├── ViewModels/
│   │   ├── FeedViewModel.swift         # Feed hinzufügen, aktualisieren, löschen ✅
│   │   ├── ArticleViewModel.swift      # Artikel gelesen/ungelesen und Stern toggeln ✅
│   │   ├── ArticleNavigationState.swift # Sichtbare Artikel-Navigation effizient berechnen ✅
│   │   ├── ArticleMetadataEditor.swift # Artikel-Ordner und Tags bearbeiten ✅
│   │   ├── TagViewModel.swift          # Tags verwalten ✅
│   │   ├── RuleViewModel.swift         # Regeln erstellen, duplizieren, sortieren, löschen ✅
│   │   └── SmartFolderViewModel.swift  # Intelligente Ordner verwalten/Defaults/Sortierung ✅
│   │
│   ├── Views/
│   │   ├── ContentView.swift           # Root: NavigationSplitView (3 Spalten) ✅
│   │   ├── FirstRun/
│   │   │   ├── FirstRunWizardView.swift # Erster-Start-Wizard für Feed/OPML/Defaults ✅
│   │   │   └── FirstRunWizardState.swift # Anzeige-/Abschlusslogik für Wizard ✅
│   │   ├── Sidebar/
│   │   │   ├── SidebarView.swift       # Linke Spalte: Intelligente Ordner, Tags, Feeds, + Button, @Query ✅
│   │   │   ├── SidebarStyle.swift      # Farb-/Auswahlwerte für helle System-Sidebar ✅
│   │   │   ├── SidebarUnreadCount.swift # Ungelesen-Zähler für Sidebar-Badges ✅
│   │   │   ├── FeedFolderOrganizer.swift # Einfache Ordner-Gruppierung für Feeds ✅
│   │   │   ├── FeedRowView.swift       # Feed-Zeile mit Favicon/Fallback ✅
│   │   │   ├── FeedPropertiesView.swift # Feed-Eigenschaften-Sheet ✅
│   │   │   ├── FeedRenameView.swift    # Feed-Anzeigename bearbeiten ✅
│   │   │   └── FeedPropertiesFormatter.swift # Helper für Eigenschaften ✅
│   │   ├── ArticleList/
│   │   │   ├── ArticleListView.swift   # Mittlere Spalte: echte Feed-Artikel anzeigen ✅
│   │   │   ├── ArticleListQuery.swift  # SwiftData-Queries für Feed-/Artikel-Listen ✅
│   │   │   ├── ArticleSortOption.swift # Globale Artikellisten-Sortierung ✅
│   │   │   ├── ArticleFilterOption.swift # Globale Artikellisten-Filterung ✅
│   │   │   ├── ArticleMarkReadOption.swift # Zeitbereiche für Massenaktion "Als gelesen markieren" ✅
│   │   │   ├── ArticleExportSheet.swift # Zweistufiger Artikel-Exportdialog mit Vorschau ✅
│   │   │   └── ArticleRowView.swift    # Reichhaltige Artikel-Zeile mit Status/Stern ✅
│   │   ├── Reader/
│   │   │   ├── ReaderView.swift        # Rechte Spalte: nativer Artikel-Reader inkl. Vollartikel-Modus ✅
│   │   │   ├── ArticleMetadataInspectorView.swift # Rechter Artikelinfos-Inspector ✅
│   │   │   ├── ArticleWindowView.swift # Eigenes Artikelfenster mit Reader + Inspector ✅
│   │   │   ├── ReadabilityExtractionView.swift # WKWebView-basierte Vollartikel-Extraktion ✅
│   │   │   ├── ReadabilityExtractedArticle.swift # Dekodiertes Readability-Ergebnis ✅
│   │   │   ├── ReadabilityFailureNotice.swift # Respektvoller Hinweis bei blockiertem Vollartikel ✅
│   │   │   ├── ReadabilityLoadDecision.swift # Startlogik für automatisches Vollartikel-Laden ✅
│   │   │   ├── ReadabilityScriptProvider.swift # Gebündeltes Readability.js + Extraktionsscript ✅
│   │   │   ├── ReaderPreparedArticle.swift # Vorbereitete Reader-Daten pro Artikel ✅
│   │   │   ├── ReaderContentRenderer.swift # HTML/Text zu Reader-Bloecken ✅
│   │   │   ├── ReaderMetadataFormatter.swift # Feedname/Lesezeit/Alter ✅
│   │   │   ├── ReaderFontPreset.swift  # Schrift-Presets für Reader ✅
│   │   │   ├── ReaderFontRegistry.swift # Gebundelte Fonts registrieren ✅
│   │   │   ├── ReaderTypography.swift  # Textgroesse/Zeilenabstand Defaults ✅
│   │   │   ├── ReaderTypographySettings.swift # Reader-Schriftgroesse als Settings-Rubrik ✅
│   │   │   └── WebContentView.swift    # WKWebView-Wrapper für Originalansicht ✅
│   │   ├── Tags/
│   │   │   ├── TagManagerView.swift    # Tags erstellen, bearbeiten, löschen ✅
│   │   │   └── AddTagView.swift        # bleibt vorerst nicht separat noetig; TagManagerView erstellt Tags direkt
│   │   ├── OPMLImport/
│   │   │   ├── OPMLImportPreviewController.swift # Gemeinsamer Preview-Controller für Wizard + Review ✅
│   │   │   ├── OPMLImportFeedRow.swift # Einheitliche Feed-Zeile für Wizard + Review ✅
│   │   │   └── OPMLImportReviewView.swift # Erweiterter OPML-Import-Dialog ✅
│   │   ├── OPMLExport/
│   │   │   └── OPMLExportSheet.swift # OPML-Exportdialog mit Optionen ✅
│   │   ├── Shared/
│   │   │   └── CachedRemoteImageView.swift # Gemeinsame gecachte Remote-Bild-View ✅
│   │   ├── Rules/
│   │   │   ├── RuleSettingsView.swift  # Alle Regeln in Einstellungen verwalten ✅
│   │   │   └── RuleWizardView.swift    # Wizard für einfache/Power-User-Regeln ✅
│   │   ├── SmartFolders/
│   │   │   ├── SmartFolderEditorView.swift # Sheet für intelligente Ordner ✅
│   │   │   ├── SmartFolderSettingsView.swift # Settings-Liste für intelligente Ordner ✅
│   │   │   └── SmartFolderFormatter.swift # Bedingungszusammenfassung/Helpers ✅
│   │   └── Settings/
│   │       ├── SettingsView.swift      # Strukturierte Settings-Shell mit linker Navigation ✅
│   │       └── FeedManagementSettingsState.swift # Suche/Auswahl für Feed-Verwaltung ✅
│   │
│   ├── Services/
│   │   ├── FeedService.swift           # FeedKit-Wrapper: RSS/Atom/JSON Feed parsen ✅
│   │   ├── FeedDiscoveryService.swift  # Website-/Feed-URL-Erkennung für Feed hinzufügen ✅
│   │   ├── FaviconService.swift        # HTML Favicon Discovery + Fallback ✅
│   │   ├── AppIconBadgeSettings.swift  # App-Icon-Badge Settings-Key ✅
│   │   ├── AppIconBadgeService.swift   # Dock-Badge für ungelesene Artikel ✅
│   │   ├── FeedNotificationService.swift # Feed-Benachrichtigungen pro Refresh ✅
│   │   ├── BackgroundRefreshSettings.swift # Auto-Refresh Settings/Intervalle ✅
│   │   ├── BackgroundRefreshService.swift  # NSBackgroundActivityScheduler Adapter ✅
│   │   ├── FeedBackgroundRefreshService.swift # Sammel-Refresh mit eigenem SwiftData-Kontext pro Feed ✅
│   │   ├── ArticleFeedIDBackfillService.swift # feedID für alte Artikel nachfuellen ✅
│   │   ├── ArticleExportService.swift # Markdown/Text/HTML-Export; PDF/DOCX prototypisiert/zurückgestellt ✅
│   │   ├── ArticleExportDocument.swift # FileDocument für Artikel-/ZIP-/Binärdateiexport ✅
│   │   ├── ArticleDocumentExportRenderers.swift # PDF- und DOCX-Datenrenderer ✅
│   │   ├── ArticleExportPackageBuilder.swift # ZIP-Paket mit Offline-Bildern ✅
│   │   ├── ArticleRetentionSettings.swift # Artikel-Aufbewahrung Settings-Keys ✅
│   │   ├── ArticleRetentionCleanupService.swift # Automatisches Löschen alter Artikel ✅
│   │   ├── ArticleWindowSettings.swift # Artikelfenster-Wiederherstellung Settings/IDs ✅
│   │   ├── OrphanedArticleCleanupService.swift # verwaiste Artikel ohne existierenden Feed entfernen ✅
│   │   ├── FeedUnreadCountBackfillService.swift # unreadCount einmalig korrigieren ✅
│   │   ├── SmartFolderDefaultKeyBackfillService.swift # defaultKey für alte SmartFolder migrieren ✅
│   │   ├── OfflineDownloadService.swift # Manueller Offline-Download pro Artikel ✅
│   │   ├── ImageCacheService.swift     # Memory-/Disk-Cache für Bilder und Favicons ✅
│   │   ├── ImageCacheSettings.swift    # Cache-Limits und Groessenformatierung ✅
│   │   ├── RuleEngine.swift            # Mehrfach-Regeln auf neue Artikel anwenden ✅
│   │   ├── SmartFolderEngine.swift     # Artikel gegen intelligente Ordner auswerten ✅
│   │   ├── OPMLService.swift           # OPML Import und Export ✅
│   │   └── OPMLDocument.swift          # FileDocument für OPML Export ✅
│   │
│   ├── Extensions/
│   │   └── Date+RelativeDisplay.swift  # Datum für Artikelzeilen formatieren ✅
│   │
│   └── Resources/
│       ├── Assets.xcassets
│       ├── AppLanguage.swift           # Sprachauswahl + Locale-Mapping ✅
│       ├── InterfaceTextSize.swift     # App-weite UI-Schriftgroesse ✅
│       ├── Localizable.xcstrings       # String Catalog für de/en/fr/it ✅
│       └── L10n.swift                  # Zentraler Zugriff auf lokalisierte Strings ✅
│
├── Feedivo.xcodeproj
├── FEATURES.md                         # Massgebliche Produkt-Roadmap und Implementierungs-Reihenfolge ✅
├── docs/
│   └── archive/
│       └── FEATURES-legacy-2026-06-24.md # Alte Roadmap, nur Archiv/Referenz
└── AGENTS.md                           # Kopie im Root (für Codex CLI)
```

---

## Implementierter Code (Stand 2026-06-28)

### FeedivoApp.swift
```swift
import SwiftUI
import SwiftData

@main
struct FeedivoApp: App {
    @AppStorage("appLanguage")
    private var appLanguageRawValue = AppLanguage.system.rawValue

    @AppStorage(InterfaceTextSize.storageKey)
    private var interfaceTextSizeRawValue = InterfaceTextSize.defaultSize.rawValue

    @AppStorage(BackgroundRefreshSettings.isEnabledKey)
    private var backgroundRefreshIsEnabled = BackgroundRefreshSettings.defaultIsEnabled

    @AppStorage(BackgroundRefreshSettings.intervalMinutesKey)
    private var backgroundRefreshIntervalMinutes = BackgroundRefreshSettings.defaultIntervalMinutes

    private let modelContainer: ModelContainer
    private let backgroundRefreshScheduler: SystemBackgroundActivityRefreshScheduler

    init() {
        ReaderFontRegistry.registerBundledFonts()

        let modelContainer = try! ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            SmartFolder.self,
            SmartFolderCondition.self,
            FeedLogEntry.self
        )
        self.modelContainer = modelContainer
        self.backgroundRefreshScheduler = SystemBackgroundActivityRefreshScheduler(
            modelContainer: modelContainer
        )
    }

    var body: some Scene {
        let appLanguage = AppLanguage.resolved(from: appLanguageRawValue)
        let interfaceTextSize = InterfaceTextSize.resolved(from: interfaceTextSizeRawValue)

        WindowGroup {
            ContentView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .task {
                    backfillStoredArticleMetadataIfNeeded()
                    trimImageCacheToSelectedLimit()
                    scheduleBackgroundRefresh()
                }
        }
        .modelContainer(modelContainer)

        WindowGroup(for: ArticleWindowRequest.self) { $request in
            if let request {
                ArticleWindowView(request: request)
                    .environment(\.locale, appLanguage.locale)
                    .environment(\.interfaceTextSize, interfaceTextSize)
                    .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
            }
        }
        .defaultSize(width: 900, height: 720)
        .modelContainer(modelContainer)

        Settings {
            NewSettingsView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
        }
        .defaultSize(width: 1040, height: 640)
        .modelContainer(modelContainer)
    }
}
```
- Registriert neben Feeds, Artikeln, Tags und Regeln auch `SmartFolder` und
  `SmartFolderCondition` im SwiftData-Container.
- Beim App-Start laufen Backfills für alte Artikel-/Regeldaten und die drei
  Default-Ordner `Heute`, `Diese Woche` und `Gespeichert` werden bei Bedarf wieder
  angelegt.
- Registriert zusätzlich eine `WindowGroup(for: ArticleWindowRequest.self)` für
  dedizierte Artikelfenster. Diese öffnen `ArticleWindowView` mit gemeinsamem
  ModelContainer, Locale und Interface-Textgröße.

### ContentView.swift
NavigationSplitView mit 3 Spalten. Verwaltet `selectedFeed` und `selectedArticle` als
`@State`. Zeigt `ContentUnavailableView` wenn nichts ausgewählt ist.
Spaltenbreiten: Sidebar 200–420px, ArticleList 280–400px, Detail flexibel.
Präsentiert `AddFeedSheet` zentral, damit Sidebar-Plus und macOS-Menü `Feed`
dieselbe Feed-hinzufuegen-Oberflaeche verwenden.
Haelt keine pauschale `@Query` auf alle Artikel mehr; `ArticleListView` meldet nur
noch einen kleinen `ArticleNavigationState` mit vorherigem/naechstem Artikel nach
oben, statt die komplette sichtbare Artikelliste in `ContentView` zu kopieren.
Präsentiert außerdem den Regel-Wizard für den aktuell geöffneten Artikel,
wenn in der Artikelansicht `Regel erstellen...` genutzt wird.
Startet den Artikel-Export zentral auf Root-Ebene als kurzlebiges SwiftUI-Sheet und
erst im nächsten Main-Runloop. Das Sheet dient als stabiler Präsentationsanker für
SwiftUIs `.fileExporter`, damit der Export nicht direkt aus einer Kontextmenü-Aktion
oder einer kurzlebigen Listen-Unteransicht geöffnet wird.
Haelt den offenen/geschlossenen Zustand des rechten Artikelinfos-Inspectors auf
Root-Ebene, damit die eingeblendete Seitenleiste beim Feed- oder Artikelwechsel
sichtbar bleibt.
Zeigt beim Start automatisch den First-Run-Wizard, sobald keine Feeds vorhanden
sind. Ein frueheres Abschluss-Flag blockiert eine wieder vollständig leere App
nicht mehr; `Später` blendet den Wizard nur für die aktuelle Sitzung aus.
Zeigt unten rechts im Hauptfenster einen dezenten Online-/Offline-Indikator über
`NWPathMonitor`. Dieser Netzwerkstatus ist bewusst getrennt vom Artikel-Status für
manuell offline gespeicherte Inhalte.
Neben diesem Online-/Offline-Indikator erscheint beim Sammel-Refresh ein zweiter
Status: während `Alle Feeds aktualisieren` läuft mit Fortschritt `erledigt/gesamt`,
nach Abschluss mit Anzahl neuer Artikel oder knapper Fehler-Markierung. Der Status
hat einen Chevron und kann zu einem Detailpanel aufgeklappt werden, das pro Feed
wartend, aktualisierend, erfolgreich (grünes Checkmark) oder fehlgeschlagen
(rotes X) zeigt. Fehlerfreie Ergebnisse verschwinden nach 2 Minuten; Ergebnisse
mit Fehlern bleiben stehen, bis der User sie schließt oder ein neuer
Sammel-Refresh startet. Damit der Fortschritt auch bei sehr schnellen Feeds
sichtbar wird, hält `FeedViewModel` den laufenden Status mindestens kurz offen.
Aktualisiert außerdem den Dock-Badge für ungelesene Artikel über
`AppIconBadgeService`, sobald Feed-Zähler oder die Einstellung
`notifications.appIconBadge.isEnabled` geändert werden.

### FirstRunWizardView.swift / FirstRunWizardState.swift
- First-Run-Wizard nach Prototyp Variante A für leere App-Starts ohne Feeds.
- Die echte SwiftUI-Oberflaeche bildet die Prototyp-Struktur nach: macOS-artige
  Titlebar mit Traffic-Lights, linke Step-Rail, rechts H1/Lead-Inhalt und Footer
  mit `Später`, `Zurück` und Primaeraktion.
- Startscreen bietet `Feed hinzufügen`, `OPML importieren` und `Später einrichten`.
- Einzelner Feed und OPML-Datei laufen zuerst in dieselbe Import-Oberflaeche:
  Feed-Prüfung, Statusfilter, Auswahl einzelner Feeds, Ordnerzuordnung,
  Ordneranlage, Duplikat-Import und Import nicht erreichbarer Feeds.
- Die Review ist bewusst nur eine Zusammenfassung der vorherigen Auswahl und bietet
  einen Link zurück zur Import-Oberflaeche; die Feed-Liste wird dort nicht erneut
  gezeigt.
- Die Wizard-Texte sind bewusst handlungsorientiert formuliert: Sie erklaeren pro
  Schritt, was der Benutzer sieht, was geaendert werden kann und was beim nächsten
  Klick passiert. Interne Begriffe wie `Review`, `Defaults` oder `Import-Engine`
  werden in der sichtbaren UI vermieden.
- OPML-Dateien können im Wizard ausgewählt oder direkt per Drag & Drop ins Fenster
  gezogen werden.
- Abschlussschritt setzt erste Defaults wie `Artikel beim Öffnen als gelesen
  markieren` und automatischen Background Refresh; das gewählte
  Aktualisierungsintervall wird direkt auf per OPML importierte Feeds übernommen.
- Nach erfolgreichem Import zeigt der Wizard einen Fertig-Screen mit importierten
  Feeds, verwendeten Ordnern und Hinweisen zu Duplikaten, nicht erreichbaren Feeds
  oder Refresh-/Speicherproblemen; das Fenster schliesst erst bei `Starten`.
- `FirstRunWizardState` kapselt die Anzeigeentscheidung, das
  `@AppStorage`-Abschluss-Flag `firstRunWizard.completed` und die Sitzungslogik:
  leerer Feedbestand zeigt den Wizard wieder, außer er wurde in der aktuellen
  Sitzung bewusst per `Später` ausgeblendet. Ein bereits sichtbarer Wizard bleibt
  nach dem Import offen, auch wenn dadurch Feeds entstehen und ein frueheres
  Abschluss-Flag bereits gesetzt war; geschlossen wird erst durch `Starten`.

### SidebarView.swift
- `@Query(sort: \Feed.title)` für automatische Feed-Liste aus SwiftData
- Eigene SwiftUI-Sidebar statt Standard-`List`, aber wieder mit hellem,
  systemnahem Hintergrund, damit sie zur klassischen macOS-Sidebar passt.
- Header mit + Button → öffnet zentral praesentiertes `AddFeedSheet`
- `AddFeedSheet` ist eine separate Struct in derselben Datei
- `AddFeedSheet` nutzt `FeedDiscoveryService`: Der Benutzer kann eine Website oder
  Feed-URL eingeben, per `Suchen` Feeds erkennen lassen, einen gefundenen Feed aus
  der Liste auswählen und anschließend im gleichen Sheet eine Vorschau mit Feed-
  Icon, Titel, Website und den letzten fünf Artikeln prüfen. Nach erfolgreicher
  Suche heißt die Primäraktion `Abonnieren`.
- Ruft für das eigentliche Speichern weiterhin `FeedViewModel.addFeed()` auf
- Kontextmenü pro Feed ruft das Feed-Löschen mit Bestätigung an
- Kontextmenü pro Feed öffnet `Feed Eigenschaften...` mit Metadaten, Intervall
  und Feed-Log
- Smart-Filter behalten die bestehenden SF-Symbol-Icons (`tray.full`, `circle.fill`,
  `star.fill`, `calendar`) und ihre Farben.
- Die Hauptbereiche `Tags`, `Intelligente Ordner` und `Ordner` sind per Chevron
  einklappbar; der Zustand wird per `@AppStorage` gespeichert und bleibt damit
  über Feedwechsel und App-Neustarts erhalten.
- Der Smart-Filter `Ungelesen` zeigt rechts die Gesamtzahl aller ungelesenen Artikel
  über alle Feeds
- Ungelesen-Badges basieren auf `Feed.unreadCount`, damit die Sidebar beim Rendern
  keine separate Query auf alle ungelesenen Artikel mehr materialisieren muss
- Die Sidebar nutzt keine globale Artikel-Query mehr für Badge-Signaturen.
  `Ungelesen` basiert weiter auf `Feed.unreadCount`; Status-Badges beobachten
  nur Stern-/Archiv-/Hidden-Artikel, damit normales Lesen keine komplette
  Sidebar-Badge-Invalidierung mehr auslöst.
- Tag-Badges und Status-Badges sind getrennt gecacht: Stern-/Archiv-/Hidden-
  Änderungen aktualisieren nur die günstigen Status-Zähler, während die teurere
  Artikel→Tag-Auswertung nachgelagert per `fetchCount` nur bei Tag-,
  Feed-Tag- oder Feed-Refresh-relevanten Änderungen läuft.
- Per Darstellungseinstellung `sidebar.showsReadFeeds` können Feeds ohne
  ungelesene Artikel in der Sidebar ausgeblendet werden; Standard bleibt anzeigen.
- Die Sidebar zeigt eine eigene `Tags`-Section mit Tag-Icon; der Button öffnet den
  zentralen `TagManagerView`.
- Vorhandene Tags werden in der Sidebar als klickbare Zeilen mit Farbindikator aus
  `Tag.colorHex` angezeigt; ein Klick filtert die Artikelliste feedübergreifend
  auf Artikel mit diesem Tag. Der Filter umfasst direkt getaggte Artikel und Artikel
  aus Feeds, denen das Tag zugewiesen ist.
- Neu erstellte Tags werden nach erfolgreichem Anlegen direkt als Sidebar-Auswahl
  gesetzt, damit der schnelle Tag-Filter sofort sichtbar und nutzbar ist.
- Tag-Zeilen zeigen rechts eine dezente Badge mit der Anzahl passender Artikel;
  direkt getaggte Artikel und Artikel aus getaggten Feeds werden ohne Duplikate
  gezählt.
- Die Sidebar zeigt keine eigene `Regeln`-Section mehr. Die komplette
  Regelverwaltung liegt bewusst in den Einstellungen; der schnelle Einstieg
  `Regel erstellen...` sitzt im Menü der Artikelansicht.
- Feeds stehen in einer Sidebar-Section `Ordner`; neben dem Section-Titel gibt es
  einen + Button zum Anlegen neuer Ordner
- Ordner sind per Chevron auf- und zuklappbar; Ordnernamen werden mit etwas
  größerer, aber nicht fetter Schrift dezent markanter als Gruppenköpfe
  dargestellt. Feeds innerhalb eines Ordners werden deutlich eingerückt angezeigt,
  damit die Hierarchie klarer lesbar ist.
- Angelegte/leere Ordner werden als `FeedFolder` gespeichert; die Zuordnung eines
  Feeds zu einem Ordner bleibt für v1 über `Feed.folderName`
- Ordner sind für v1 eine Ebene tief; noch kein Drag & Drop
- Ganz oben zeigt die Sidebar den Abschnitt `Intelligente Ordner` mit den per
  `SmartFolder.sortOrder` sortierten Ordnern, sofern sie für die Seitenleiste
  aktiviert sind.
- Die früheren festen Smart Filter werden nicht mehr als eigene Sidebar-Section
  angezeigt. Standardansichten wie `Alle Artikel`, `Ungelesen`, `Mit Stern`,
  `Heute`, `Ausgeblendet`, `Archiviert`, `Diese Woche` und `Gespeichert` laufen
  als normale vordefinierte intelligente Ordner.
- Intelligente Ordner zeigen ihr gespeichertes Icon und ihre gespeicherte Farbe,
  rechts eine Treffer-Badge, werden über das Kontextmenü bearbeitet, dupliziert
  oder gelöscht und nutzen dieselbe helle, kompakte Sidebar-Optik wie Feeds und
  Tags.

### FeedRowView.swift
- Zeigt Feed-Titel mit kleinem Favicon aus `Feed.faviconURL`
- Nutzt `AsyncImage` für remote Icons
- Fallback ist das RSS-Systemsymbol, wenn kein Icon vorhanden ist oder das Laden scheitert
- Zeigt rechts eine dezente Badge mit der Anzahl ungelesener Artikel, wenn der Feed
  mindestens einen ungelesenen Artikel hat

### SidebarUnreadCount.swift
- Kapselt die Sidebar-Zähllogik für ungelesene Artikel pro Feed und über alle Feeds.
- Liest vorberechnete `Feed.unreadCount` Werte, damit die Sidebar weder komplette
  Feed-Relationships noch alle ungelesenen Artikel laden muss.
- Liefert nur für positive Zähler einen sichtbaren Badge-Text, damit Feeds ohne
  ungelesene Artikel ruhig bleiben.
- `SidebarTagCount` zählt direkt getaggte Artikel und Artikel aus getaggten Feeds
  per SwiftData-`fetchCount` über denselben Tag-Predicate wie die Artikelliste,
  statt Tag-/Feed-Artikel-Relationships bei jedem Sidebar-Render zu traversieren.
- `SmartFolderSidebarBadge` nutzt für `Ungelesen` weiterhin die summierten
  `Feed.unreadCount` Werte; `Mit Stern`, `Ausgeblendet` und `Gespeichert`
  werden im Sidebar-Render aus den gebündelten Status-Zählern gelesen, inklusive
  gelesener und ungelesener Treffer.
- `SidebarBadgeSignatureBuilder` trennt Status-Signatur und Tag-Signatur. Damit
  löst ein reiner Stern-/Archiv-Klick keine neue Tag-Badge-Berechnung und keine
  Artikel→Tag-Relationship-Faults aus; ein Feed-Tag-Wechsel mit gleicher
  Tag-Anzahl invalidiert den Tag-Cache trotzdem korrekt. Reine
  Gelesen/Ungelesen-Wechsel gehen nicht mehr in die Tag-Signatur ein.

### FeedService.swift
- Parsed RSS 2.0, Atom und JSON Feed via FeedKit
- Nutzt FeedKit `Feed(data:)` für Parsing und `URLSession` + async/await für Download
- Gibt `ParsedFeed` mit Feed-Metadaten und `[ParsedArticle]` zurück
- Feed-Titel wird aus Metadaten gelesen, mit URL als Fallback
- Website-URL für Favicon Discovery wird aus Feed-Metadaten gelesen:
  RSS `channel.link`, Atom `alternate` Link, JSON Feed `home_page_url`
- Artikel erhalten zusätzlich eine stabile Quellen-ID aus RSS `guid`, Atom `id`
  beziehungsweise JSON-Feed `id`, wenn der Feed diese liefert. Diese ID wird für
  die Wiedererkennung beim Refresh genutzt, weil manche Feeds ihre Artikel-Links
  oder Tracking-Parameter nachträglich ändern.
- Artikelbilder werden aus Media RSS, iTunes Image, Bild-Enclosures und erstem
  `<img>` in Content/Summary gelesen
- `fetchFeed` bleibt ein reiner Feed-Abruf und laedt keine verlinkten Artikelseiten
  mehr automatisch; fehlende Artikelbilder können explizit über
  `enrichArticleImagesIfNeeded` aus `og:image`/`twitter:image` der Artikelseite
  nachgezogen werden
- Relative Artikelbild-URLs werden gegen die Feed-URL zu absoluten URLs aufgeloest,
  damit `AsyncImage` sie laden kann
- HTML-Regulaerausdruecke für Artikelbilder und Meta-Tags werden als statische
  `NSRegularExpression` Instanzen gecacht, damit sie nicht pro Artikel oder Refresh
  neu kompiliert werden müssen
- Eigene `FeedServiceError` enum: `.invalidURL`, `.parsingFailed`

### FeedDiscoveryService.swift
- Erkennt beim Hinzufügen neuer Feeds direkte Feed-URLs und normale Website-URLs.
- Versucht zuerst, die Eingabe direkt mit `FeedService.fetchFeed` zu parsen.
- Wenn das kein Feed ist, lädt der Service die Website und sucht
  `<link rel="alternate">` Einträge für RSS, Atom und JSON Feed.
- Relative Feed-URLs werden gegen die Website-URL aufgelöst, doppelte URLs werden
  entfernt und die gefundenen Feeds werden zur Auswahl im Add-Feed-Sheet
  zurückgegeben.
- Jedes Discovery-Ergebnis enthält außerdem eine Vorschau: Favicon-Fallback,
  Website, Feed-Titel und maximal fünf Artikel, nach Veröffentlichungsdatum
  absteigend sortiert.
- Eingaben ohne Schema werden als `https://...` interpretiert. Wenn keine Feeds
  gefunden werden, liefert der Service eine lokalisierte Fehlermeldung.

### FeedViewModel.swift
- `@Observable` class
- `addFeed(urlString:context:)` — lädt Artikel, erstellt Feed, speichert in SwiftData
- Beim Hinzufuegen und Aktualisieren wird `FaviconService` genutzt, um `Feed.faviconURL`
  aus Website-HTML oder `/favicon.ico` Fallback zu speichern
- `refreshFeed(_:context:)` — aktualisiert den ausgewählten Feed, fügt nur neue
  Artikel hinzu und aktualisiert Feed-Metadaten sowie `lastRefreshed`
- Beim Refresh werden bestehende Artikel über mehrere Schlüssel wiedererkannt:
  stabile Quellen-ID, Link und als migrationsfreundlicher Fallback Titel plus
  Veröffentlichungsdatum. Dadurch bleiben Lesestatus und Stern/Archiv erhalten,
  auch wenn ein Feed denselben Artikel später mit leicht geändertem Link liefert.
- Der Refresh lädt den Altbestand eines Feeds nicht mehr über die komplette
  `feed.articles`-Relationship, sondern per gezieltem `FetchDescriptor<Article>`
  über `Article.feedID` mit schlankem `propertiesToFetch`. Das vermeidet große
  Relationship-Faults während der Aktualisierung und hält die UI reaktionsfähiger.
  Für den Refresh-Abgleich bleibt `Article.content` ebenfalls aus diesem Lookup
  draußen; der Volltext wird nur noch gefaultet, wenn der Feed tatsächlich neuen
  Volltext für einen bestehenden Artikel nachliefert.
- Beim Hinzufuegen werden `siteURL`, `followedAt` und ein Info-Log geschrieben
- Beim Hinzufuegen und Aktualisieren wird `Feed.unreadCount` für Sidebar-Badges
  gepflegt; neue Artikel starten als ungelesen
- Beim Aktualisieren liefert `FeedViewModel` pro Feed ein
  `FeedRefreshNotificationResult` mit Feed-Titel, Anzahl neuer Artikel und
  `Feed.isNotificationEnabled`; `FeedNotificationService` entscheidet daraus, ob
  eine macOS-Benachrichtigung angezeigt wird.
- Beim Aktualisieren werden Erfolg/Fehler als `FeedLogEntry` protokolliert; pro Feed
  bleiben die neuesten 20 Log-Eintraege erhalten
- `refreshAllFeeds(_:modelContainer:)` — aktualisiert alle gespeicherten Feeds
  über `FeedBackgroundRefreshService`. `FeedViewModel` erstellt dafür nur leichte
  `FeedRefreshSnapshot` Werte aus der UI-Query, verwaltet MainActor-Progress und
  verarbeitet am Ende Ergebnis- und Benachrichtigungsdaten.
- Der Sammel-Refresh nutzt pro Feed einen eigenen SwiftData-`ModelContext` im
  Hintergrundservice. Dadurch laufen Netzwerk, Artikel-Abgleich, Regelanwendung,
  Log-Schreiben und Speichern nicht mehr auf dem UI-`modelContext`; die UI erhält
  nur grobe Batch-/Feed-Status-Events zurück.
- `refreshAllFeeds(_:context:)` bleibt als Legacy-/Testpfad bestehen und speichert
  weiterhin pro Feed-Batch. Einzel-Feed-Refresh und OPML-Import nutzen vorerst
  bewusst den bestehenden Kontextpfad.
- Der Sammel-Refresh laeuft bei einzelnen Fehlern weiter und meldet am Ende
  betroffene Feednamen
- `operationProgress` liefert für Sammel-Refresh und OPML-Import einen sichtbaren
  Fortschritt mit Titel, erledigten Feeds, Gesamtzahl und Prozentwert. Für
  `refreshAllFeeds` setzt `FeedViewModel` nach Abschluss zusätzlich
  `recentRefreshStatus` mit Anzahl neuer Artikel, Fehleranzahl und Gesamtzahl.
  `refreshItems` hält die Live-Zeilen pro Feed mit Status `pending`, `refreshing`,
  `succeeded` oder `failed`; `ContentView` zeigt daraus unten rechts neben dem
  Online-/Offline-Status ein aufklappbares Detailpanel. Fehlerfreie Ergebnisse
  verschwinden nach 2 Minuten automatisch, Fehler-Ergebnisse bleiben sichtbar.
  Der laufende Refresh-Status hat eine minimale Sichtbarkeitsdauer, damit schnelle
  Refreshes nicht nur als unsichtbarer State-Wechsel durchlaufen. Feed-Batches
  werden in einer gemeinsamen `refreshItems`-Transformation auf `refreshing`
  gesetzt, und der laufende `operationProgress` wird nicht mehr global animiert,
  damit häufige Fortschrittsänderungen weniger UI-Arbeit auslösen.
- `deleteFeed(_:context:)` — löscht einen Feed aus SwiftData; Artikel werden über
  die Cascade-Relationship mitgelöscht
- `renameFeed(_:displayTitle:context:)` — speichert einen benutzerdefinierten
  Anzeigenamen, ohne den urspruenglichen Feed-Namen zu verlieren
- `restoreOriginalFeedTitle(_:context:)` — setzt den Anzeigenamen wieder auf den
  gespeicherten Originalnamen zurück
- Beim Refresh wird `Feed.originalTitle` mit dem Feed-Metadaten-Titel aktualisiert;
  ein benutzerdefinierter `Feed.title` bleibt erhalten
- Beim Refresh werden Summary und fehlender `Article.content` für bestehende Artikel
  aus später gelieferten Feed-Daten nachgetragen, damit Offline-Content nicht nur
  für neue Artikel gespeichert wird. Unveränderte Werte werden nicht erneut
  zugewiesen, damit SwiftData während Sammel-Refreshes weniger unnötige
  Änderungs-Invalidierungen auslöst.
- Der Feed-Fetch ist als Closure injizierbar, damit Refresh-Tests ohne Netzwerk laufen
- Die Favicon-Discovery ist als Closure injizierbar, damit Tests ohne Netzwerk laufen
- Die Artikelbild-Anreicherung ist als Closure injizierbar; beim Refresh wird sie nur
  für neue Artikel ohne Feed-Bild und für bereits gespeicherte, noch bildlose
  Artikel aufgerufen, damit bestehende Artikel mit Bild keine unnoetigen
  Netzwerkrequests mehr ausloesen
- Der OPML-Import arbeitet zweiphasig: Feed-URL-Deduplizierung und Feed-Anlage laufen
  kontrolliert sequenziell, danach werden die neuen Feeds begrenzt parallel
  aktualisiert. `FeedViewModel.maxConcurrentFeedRefreshes` verhindert, dass große
  OPML-Imports alle Feed-Abrufe gleichzeitig starten. Neu angelegte OPML-Feeds
  erhalten das gewählte bzw. gespeicherte Aktualisierungsintervall, begrenzt auf
  erlaubte Werte.
- Beim Refresh werden gespeicherte Regeln über `RuleEngine` auf neu eingefügte
  Artikel angewendet; Benachrichtigungs-Regeln werden für neue Artikel gesammelt
  und nach erfolgreichem Speichern an `FeedNotificationService` gemeldet.
  Bestehende Artikel können in den Einstellungen manuell rückwirkend verarbeitet
  werden, ohne macOS-Benachrichtigungen auszulösen.
- Der Refresh respektiert die Artikel-Aufbewahrung bereits beim Import: Wenn ein
  Feed-Eintrag älter als die aktive globale oder Feed-eigene Aufbewahrungsgrenze
  ist, wird er nicht erneut gespeichert. So tauchen zuvor bereinigte alte Artikel
  nicht wieder als ungelesene Artikel auf, solange sie noch im RSS-Feed stehen.
- Properties: `isLoading: Bool`, `errorMessage: String?`

### FaviconService.swift
- Laedt die Website-HTML-Seite eines Feeds und sucht `<link rel="...icon...">`
- Unterstützt `icon`, `shortcut icon`, `apple-touch-icon` und `mask-icon`
- Normalisiert relative und protokollrelative Icon-URLs zu absoluten URLs
- Priorisiert Apple-Touch-Icons und größere `sizes` Werte vor einfachen Icons
- HTML-Regulaerausdruecke für Link-Tags und Attribute werden statisch gecacht;
  Attributwerte werden in einem Durchlauf mit Capture Groups gelesen
- Fallback: Wenn HTML nicht geladen oder kein Icon gefunden wird, nutzt Feedivo
  `/favicon.ico` auf der Website-Root
- Keine externe Google-S2-API; die Favicon-Strategie bleibt eigenstaendig und
  datensparsamer

### ArticleFeedIDBackfillService.swift / FeedUnreadCountBackfillService.swift
- `ArticleFeedIDBackfillService` füllt `Article.feedID` für alte Artikel nach, die
  vor der Denormalisierung gespeichert wurden; die Abfrage sucht gezielt nur Artikel
  mit `feedID == nil`.
- `FeedUnreadCountBackfillService` korrigiert `Feed.unreadCount` für vorhandene Feeds
  einmalig und setzt danach das aktuelle UserDefaults-Flag
  `feedUnreadCountBackfillDone_v3`.
- Der Backfill zählt ungelesene Artikel per direktem `Article.feedID`-Fetch und
  baut daraus eine kleine Feed-ID-Map, statt pro Feed die komplette
  `feed.articles`-Relationship zu faulten.
- Das UserDefaults-Objekt ist injizierbar, damit der einmalige Backfill in Tests
  kontrolliert werden kann.
- Nach erfolgreichem Durchlauf wird beim App-Start nicht mehr pro Feed die komplette
  `articles`-Relationship geladen, nur um den Sidebar-Zähler zu verifizieren.

### RuleEngine.swift
- Stateless Service für automatische Regel-Aktionen.
- Unterstützt mehrere Bedingungen pro Regel und wertet sie je nach
  `RuleMatchMode` als `all` (AND) oder `any` (OR) aus.
- Unterstützt die Felder `title`, `summary` und `feedTitle`.
- Unterstützt die Operatoren `contains`, `startsWith`, `endsWith` und `regex`.
- Regex-Bedingungen werden case-insensitive per `NSRegularExpression` ausgewertet;
  ungültige Patterns matchen nicht und werden beim Speichern im `RuleViewModel`
  abgelehnt.
- Vergleicht case-insensitive und ignoriert deaktivierte Regeln, leere Suchwerte,
  unbekannte Felder/Operatoren und Regeln ohne Bedingungen.
- Unterstützt `RuleAction.assignTag`, `RuleAction.hideArticle` und
  `RuleAction.notify`; unbekannte oder alte Regeln fallen auf `assignTag` zurück.
- Wertet Regeln deterministisch nach `Rule.sortOrder` von oben nach unten aus; bei
  gleicher Reihenfolge dient der Name als stabiler Fallback.
- Fuegt Tags nur hinzu, wenn der Artikel das Tag noch nicht besitzt, und setzt
  `Article.isHidden` nur, wenn der Artikel noch nicht ausgeblendet ist.
- Bei rückwirkendem Anwenden von Hide-Regeln synchronisiert die Engine die
  betroffenen `Feed.unreadCount` Werte neu, damit Sidebar-Badges versteckte
  ungelesene Artikel nicht weiter mitzählen.
- Gibt die Anzahl neu angewendeter Aktionen zurück; der neue
  `applyRulesWithNotifications` Pfad liefert zusätzlich
  `RuleNotificationResult` Werte für Benachrichtigungs-Regeln.
- Regeln können gesammelt auf vorhandene Artikel mit Feed-Bezug angewendet werden;
  dieser rückwirkende Pfad zählt Benachrichtigungs-Aktionen mit, zeigt aber keine
  macOS-Benachrichtigungen an.
- Zaehlt für den Regel-Wizard vorab, wie viele vorhandene Artikel zu den aktuellen
  Bedingungsentwuerfen passen würden, ohne dabei Tags zu setzen.

### RuleViewModel.swift
- Kapselt Erstellen, Bearbeiten und Löschen von Regeln für den Wizard.
- Validiert Name, Aktion und mindestens eine nichtleere Bedingung; ein Ziel-Tag ist
  nur für die Aktion `Tag zuweisen` Pflicht.
- Regex-Bedingungen müssen ein gültiges Pattern enthalten; ungültige Regexe werden
  nicht still als Teilregel gespeichert.
- Speichert für `Benachrichtigung auslösen` zusätzlich Textvorlage und Priorität;
  leere Textvorlagen fallen auf `{Titel}` zurück.
- Neue Regeln bekommen die nächste `sortOrder`; vorhandene Regeln können über
  das ViewModel dupliziert und per Hoch-/Runter-Aktion oder Drag & Drop
  umsortiert werden.
- Speichert neue Mehrfachbedingungen als `RuleCondition` und pflegt die alten
  `conditionField`/`conditionOperator`/`conditionValue` Felder für Kompatibilitaet
  mit bestehenden Daten weiter.

### SmartFolderDefaultKeyBackfillService.swift
- Einmaliger Backfill beim App-Start: bestehende Default-Ordner (`isDefault==true`)
  ohne `defaultKey` erhalten anhand ihres deutschen Namens den passenden `defaultKey`
  (8 bekannte Namen wie `Alle Artikel` -> `all`, `Ungelesen` -> `unread`).
- Läuft nur einmal pro Gerät (`smartFolderDefaultKeyBackfillDone_v1`); überspringt
  Ordner, die bereits einen `defaultKey` besitzen.
- Ersetzt den früheren `RuleConditionBackfillService`, der mit der M2-Entfernung
  der Legacy-Regelspalten überflüssig wurde und gelöscht wurde.

### RuleSettingsView.swift / RuleWizardView.swift
- Einstellungen zeigen eine kompakte Tabellenliste aller Regeln mit Reihenfolge,
  Status, Name, Bedingungszusammenfassung, Aktion und Trefferanzahl.
- Regeln können per Hoch-/Runter-Button oder Drag & Drop umsortiert werden;
  Doppelklick öffnet den Wizard, Rechtsklick bietet Bearbeiten, Duplizieren und
  Löschen.
- Der Wizard zeigt je nach Aktion entweder Ziel-Tag-Felder oder
  Benachrichtigungsfelder. Benachrichtigungstexte unterstützen die Platzhalter
  `{Titel}`, `{Feed}` und `{Regel}` sowie die Prioritäten `Normal` und `Kritisch`.
- Einstellungen bieten einen Button `Auf vorhandene Artikel anwenden`, der aktive
  Regeln manuell auf den gespeicherten Artikelbestand anwendet und danach die Anzahl
  neu angewendeter Regelaktionen anzeigt.
- Neue Regeln werden über einen Wizard erstellt. Der Benutzer wählt zwischen
  einfacher Regel und Power-User-Regel.
- Der Wizard bietet als Aktion `Tag zuweisen` oder `Artikel ausblenden`; bei
  Ausblenden wird kein Ziel-Tag benoetigt.
- Einfache Regeln verwenden eine Bedingung; Power-User-Regeln erlauben mehrere
  Bedingungen mit AND- oder OR-Verknuepfung.
- Wenn im Operator-Dropdown `Regex` gewählt ist, zeigt der Wizard rechts oberhalb
  des Eingabefelds den Textbutton `Regex Beispiele` mit kurzer Regex-Hilfe.
- Der Wizard zeigt live eine Vorschau, wie viele vorhandene Artikel die aktuelle
  Regel treffen wuerde. Leere Suchwerte zeigen stattdessen einen Hinweis.
- Der Wizard kann aus der Sidebar mit dem aktuell ausgewählten Artikel gestartet
  werden und füllt dann einen passenden ersten Vorschlag vor.

### SmartFolderEngine.swift
- Stateless Service für intelligente Ordner.
- Wertet `SmartFolderCondition` gegen gespeicherte Artikel aus und nutzt
  `RuleMatchMode` als globale Verknüpfung: `Alle Bedingungen` entspricht UND,
  `Eine Bedingung` entspricht ODER.
- Ein intelligenter Ordner ohne Bedingungen gilt als `Alle Artikel`; das ist keine
  Sonderlogik pro Ordner, sondern die allgemeine Bedeutung eines leeren
  Bedingungssatzes.
- V1-Entscheidung: Gemischte Operatoren oder Bedingungsgruppen innerhalb eines
  intelligenten Ordners werden bewusst noch nicht angeboten.
- Unterstützte Felder: Tag, Feed, Feed-Ordner, Datum, Status, Titel, Artikeltext
  und Autor.
- Unterstützte Spezialwerte: Datum `heute`/`diese Woche` und Status `ungelesen`,
  `gelesen`, `mit Stern`, `archiviert`, `ausgeblendet`.
- Textvergleiche laufen case-insensitive; der Artikeltext umfasst Titel, Summary,
  Content und Offline-Content.
- `SmartFolderPreparedMatcher` sortiert Bedingungen einmal pro Ordner-Auswertung
  und wird von `matchingArticles`/`matchingArticleCount` verwendet, damit komplexe
  Ordner im Artikel-Loop nicht pro Artikel dieselben Conditions neu sortieren.

### SmartFolderViewModel.swift
- Kapselt Erstellen, Bearbeiten, Löschen, Duplizieren und Umsortieren
  intelligenter Ordner.
- Legt die nächste `sortOrder` deterministisch an und normalisiert nach
  Sortieraktionen die Reihenfolge. Für Drag & Drop gibt es gezielte Methoden zum
  Einfügen vor einem Zielordner und zum Verschieben ans Listenende.
- Speichert Icon und Farbe pro intelligentem Ordner und kopiert diese Darstellung
  beim Duplizieren.
- Erstellt und sortiert die Default-Ordner `Alle Artikel`, `Ungelesen`,
  `Mit Stern`, `Heute`, `Ausgeblendet`, `Archiviert`, `Diese Woche` und
  `Gespeichert` inklusive vordefiniertem Icon und vordefinierter Farbe, wenn sie
  fehlen; vorhandene Benutzerordner bleiben dabei unangetastet.

### SmartFolderSettingsView.swift / SmartFolderEditorView.swift
- Einstellungen zeigen intelligente Ordner im Stil der Regelverwaltung: kompakte
  Liste mit Reihenfolge, Sidebar-Schalter, Name, Bedingungszusammenfassung,
  Trefferanzahl und Aktionen.
- Die Reihenfolge wird in den Einstellungen per Hamburger-Handle und
  Live-Drag-&-Drop geändert: Beim Überfahren einer Zielzeile rutscht die ganze
  Zeile sichtbar an die neue Position. Pfeilbuttons werden bewusst nicht verwendet.
- Ordner können in den Einstellungen und per Sidebar-Kontextmenü bearbeitet,
  dupliziert und gelöscht werden; die Defaults können wiederhergestellt werden.
- Der Editor nutzt ein größeres macOS-Sheet mit Name, Sidebar-Toggle,
  Darstellungsauswahl für Icon/Farbe, UND/ODER-Segment, Bedingungszeilen mit
  sichtbaren UND/ODER-Verbindern und Live-Vorschau der Treffer.
- Der grafische Prototyp liegt unter
  `docs/design/smart-folders-prototype/index.html` und orientiert sich bewusst am
  Design der Regelverwaltung.

### FeedPropertiesView.swift / FeedPropertiesFormatter.swift
- Rechtsklick auf Feed → `Feed Eigenschaften...`
- Sheet nutzt einen Feed-Header mit Icon/Favicon-Fallback, Website und Statusmetriken
  für Aktualisierungsintervall, nächsten Abruf und sichtbare Log-Eintraege
- Darunter zeigt es gruppiert Originaltitel, Website, XML-Adresse mit Kopierbutton,
  Gefolgt-ab-Datum, editierbaren Ordner, letzten Artikel, Aktualisierungsintervall,
  nächsten Abruf und die neuesten 20 Feed-Log-Eintraege
- Eine eigene Section `Aktivität` zeigt, wie viele Artikel der Feed in den letzten
  7 Tagen veröffentlicht hat, sowie wann der Feed zuletzt aktualisiert wurde.
- Website und XML-Adresse werden als echte Links im Standardbrowser geöffnet,
  sofern sie gueltige `http`/`https`-URLs sind; der XML-Kopierbutton bleibt erhalten
- Aktualisierungsintervall ist direkt im Sheet editierbar und wird in SwiftData gespeichert
- Der Ordnername ist direkt im Sheet editierbar; leere Eingaben werden als `nil`
  gespeichert
- Feed-Tags sind direkt im Sheet editierbar: Vorhandene globale Tags können per
  Plus-Chip zugewiesen, neue Tags per Eingabe erstellt und zugewiesene Tags wieder
  entfernt werden.
- Die globale Artikel-Aufbewahrung kann pro Feed überschrieben werden: Standard
  ist `Globale Einstellung verwenden`; bei aktiver Überschreibung kann der Feed
  eigene Aktivierung, eigene Aufbewahrungstage und das Mitlöschen von Stern-/
  Archivartikeln speichern.
- `FeedPropertiesFormatter` kapselt nächsten Abruf, neuesten Artikel, Artikelanzahl
  der letzten 7 Tage, Log-Limit und die sichtbare Log-Anzahl sowie gueltige
  Link-URLs, damit diese Logik ohne UI testbar bleibt

### FeedRenameView.swift
- Rechtsklick auf Feed → `Feed umbenennen...`
- Links oben im Sheet wird das gespeicherte Feed-Favicon angezeigt; fehlt es oder
  laedt es nicht, erscheint das RSS-Systemsymbol als Fallback.
- Sheet zeigt editierbaren Anzeigenamen, gespeicherten urspruenglichen Feed-Namen
  und einen Button zum Wiederherstellen des Originalnamens.
- Speichern nutzt `FeedViewModel.renameFeed`, damit Trim, Leerwert-Prüfung und
  Originalnamen-Erhalt zentral testbar bleiben.

### FeedFolderOrganizer.swift
- Kapselt die einfache Feed-Ordnerlogik für die Sidebar.
- Normalisiert Ordnernamen per Trim; leere Namen werden als fehlender Ordner behandelt.
- Liefert eindeutige, alphabetisch sortierte Ordnernamen und sortierte Feed-Listen
  pro Ordner beziehungsweise ohne Ordner.

### BackgroundRefreshSettings.swift / BackgroundRefreshService.swift
- `BackgroundRefreshSettings` kapselt `@AppStorage` Keys, Defaults und erlaubte
  Intervalle: 15, 30, 60 oder 120 Minuten sowie Statuswerte für letzten
  automatischen Refresh, letzten Fehler, nächsten geschaetzten Lauf und die
  separate Option `Feeds beim Start aktualisieren` (Standard aus).
- `BackgroundRefreshService.scheduleNextRefresh(...)` plant oder storniert den
  Auto-Refresh testbar über ein kleines Scheduler-Protokoll.
- Beim Planen, nach erfolgreichem Lauf und nach Fehlern speichert der Service
  Statusdaten in UserDefaults; die Einstellungen zeigen diese kompakt an.
- `SystemBackgroundActivityRefreshScheduler` nutzt `NSBackgroundActivityScheduler`,
  weil `BGTaskScheduler` für native macOS Apps im SDK nicht verfuegbar ist.
- Automatischer Refresh nutzt denselben Pfad wie manueller Refresh für alle Feeds:
  `FeedViewModel.refreshAllFeeds(_:modelContainer:)`. `FeedivoApp` teilt ein
  `FeedViewModel` zwischen Hauptfenster und Background-Scheduler, damit
  automatische Refreshes bei offenem Hauptfenster dieselbe sichtbare
  Fortschrittsanzeige nutzen, während die SwiftData-Schreibarbeit in eigenen
  Kontexten des `FeedBackgroundRefreshService` läuft.
- Wichtig: macOS entscheidet den genauen Zeitpunkt. Eine vollständig beendete App
  wird für diese Basis nicht neu gestartet.

### AppIconBadgeSettings.swift / AppIconBadgeService.swift
- `AppIconBadgeSettings` kapselt den `@AppStorage` Key
  `notifications.appIconBadge.isEnabled`; Default ist aktiv.
- `AppIconBadgeService.unreadCount(in:)` summiert `Feed.unreadCount` und nutzt damit
  dieselbe vorberechnete Zählerbasis wie Sidebar-Badges.
- `updateBadge` setzt `NSApp.dockTile.badgeLabel` über einen kleinen
  `AppIconBadgeUpdating` Adapter; dadurch ist die Entscheidung `Zahl anzeigen` oder
  `Badge leeren` ohne AppKit testbar.
- Der Dock-Badge ist bewusst Feature 10.3 und getrennt von echten
  System-Benachrichtigungen.

### FeedNotificationService.swift
- `FeedRefreshNotificationResult` beschreibt ein Refresh-Ergebnis pro Feed:
  Feed-Titel, Anzahl neuer Artikel und ob Feed-Benachrichtigungen aktiv sind.
- `FeedNotificationService.summary(from:)` filtert deaktivierte Feeds und Feeds
  ohne neue Artikel heraus und fasst mehrere Feeds zu einer Benachrichtigung
  zusammen, z.B. Titel `5 neue Artikel`, Body `Heise, Mac & i`.
- `presentRefreshSummary(for:)` nutzt `UNUserNotificationCenter`, fragt bei Bedarf
  einmalig die macOS-Erlaubnis an und zeigt danach eine lokale Benachrichtigung.
  Wenn macOS die Erlaubnis verweigert oder keine passenden neuen Artikel vorhanden
  sind, bleibt Feedivo still.
- `RuleNotificationResult` und `ruleSummary(from:)` fassen Regel-Treffer zusammen:
  ein einzelner Treffer nutzt den Regeltext direkt, mehrere Treffer derselben Regel
  werden z.B. zu `3 neue Apple-Artikel` gruppiert.
- `presentRuleSummary(for:)` zeigt regelbasierte lokale Benachrichtigungen. Kritisch
  markierte Regeln werden aktuell als zeitkritisch vorbereitet; eine echte
  Critical-Alert-Entitlement-Entscheidung bleibt bewusst später.
- Klick auf die Benachrichtigung öffnet aktuell Feedivo. Präzise Navigation zu
  Feed oder Artikel bleibt für Deep-Linking/Command-Routing später.

### ArticleListView.swift
- Zeigt echte Artikel des ausgewählten Feeds über eine gezielte SwiftData-Query
  statt über die komplette `Feed.articles` Relationship
- Feed-Listen laden nicht mehr automatisch alle Artikel per globaler `@Query`;
  Smart-Filter-Listen nutzen gezielte SwiftData-Queries für Alle, Ungelesen,
  Mit Stern, Heute und Ausgeblendet statt alle Artikel im Speicher zu filtern
- Feed-, Tag-, Smart-Filter- und einfache Smart-Folder-Listen nutzen leichte
  `FetchDescriptor` mit `propertiesToFetch`, damit große Volltextfelder
  `Article.content` und `Article.offlineContent` beim normalen Listenrender nicht
  vorgeladen werden. Volltexte faulten erst bei Suche, Reader, Export oder
  Offline-Aktionen nach.
- Artikellisten laden initial nur 50 Artikel über `FetchDescriptor.fetchLimit`.
  Am Listenende erhöht eine Nachlade-Zeile das Limit in 50er-Schritten, sodass
  große Feeds nicht komplett beim ersten Öffnen materialisiert werden. Feed-,
  Tag-, Smart-Filter- und Smart-Folder-Scopes behalten jeweils ihr eigenes Limit
  und setzen es beim Scope-Wechsel zurück.
- Tag-Listen nutzen ebenfalls eine gezielte SwiftData-Query und zeigen
  feedübergreifend direkt getaggte Artikel sowie Artikel aus getaggten Feeds.
- Intelligente Ordner nutzen für einfache/vordefinierte Fälle gezielte
  SwiftData-Queries statt pauschal alle Artikel zu laden: Alle Artikel,
  Ungelesen, Gelesen, Mit Stern, Archiviert, Ausgeblendet, Gespeichert, Heute und
  Diese Woche. Komplexere benutzerdefinierte Ordner fallen weiterhin auf
  `SmartFolderEngine` mit In-Memory-Filterung zurück.
- Der intelligente Ordner `Ungelesen` lädt bewusst dieselbe Artikelauswahl wie
  `Alle Artikel`; `ArticleListDisplayState` blendet gelesene Artikel aus und hält
  gerade automatisch gelesene Artikel sichtbar. Dadurch verhält sich `Ungelesen`
  beim Lesen wie normale Feed-Listen.
- Die intelligenten Ordner `Mit Stern`, `Ausgeblendet` und `Gespeichert` starten
  in der Artikelliste mit gelesenen und ungelesenen Artikeln sichtbar. Der
  vorhandene Filter-Menüpunkt kann danach weiterhin manuell umgeschaltet werden.
- Die Anzeige-Logik berechnet sichtbare Artikel und die Anzahl ausgeblendeter
  gelesener Artikel gemeinsam in `ArticleListDisplaySnapshot`, damit große Listen
  nicht mehrfach durchlaufen werden.
- Sortierung und Filterung werden gemeinsam über `ArticleListPreparedArticles`
  vorbereitet, damit die Artikelliste pro SwiftUI-Render nur einmal sortiert und
  danach auf derselben sortierten Liste filtert.
- Der Reader-Prefetch der Artikelliste bleibt bewusst leichtgewichtig: Er faultet
  keine `Article.content`-/`Article.offlineContent`-Volltexte, keine
  `Article.feed`-Relationship und decodiert keine Nachbarartikel-Bilder mehr. Die
  teure Vorbereitung passiert nur für den wirklich geöffneten Artikel im
  asynchronen Reader-Build.
- Feednamen für Artikelzeilen kommen aus einem einmal pro Render gebauten
  `feedID -> Feed.title` Lookup über die leichte Feed-Query. `ArticleRowView`
  liest den Feednamen nicht mehr über `article.feed?.title`, damit das Lesen in
  `Alle Artikel` keine Relationship-Faults pro sichtbarer Zeile auslöst.
- Beim automatischen Als-gelesen-markieren setzt die Liste den Artikel sofort
  in-memory auf gelesen, aktualisiert `Feed.unreadCount` aber nicht pro Auswahl.
  Stattdessen sammelt sie betroffene Feed-IDs und synchronisiert die Zähler beim
  debounced Flush per SwiftData-`fetchCount`, damit schnelle Artikelwechsel keine
  Feed-/Sidebar-/Badge-Invalidierung pro Artikel auslösen.
- Die Artikelliste bietet nur noch eine einfache, kompakte Suche oberhalb der
  mittleren Spalte. Sie durchsucht bewusst nur die bereits geladenen Artikel der
  aktuell ausgewählten Liste und nutzt dafür den Bereich `Alles` (Titel,
  Zusammenfassung und Inhalt). Die frühere große Suchmaske wurde aus der
  Artikelliste entfernt, damit die mittlere Spalte leicht bleibt.
- `Cmd+F` öffnet ein separates Artikelsuche-Fenster. Dort liegen die erweiterte
  Suche über alle gespeicherten Artikel, Suchbereiche, Feed-/Tag-/Zeitraum- und
  Statusfilter sowie eine eigene Ergebnisliste.
- Beim Wechsel des ausgewählten Artikels nutzt die Navigation die bereits sichtbare
  Artikelliste aus dem aktuellen Render und stößt keine neue Sortierung/Filterung
  an.
- Tag-Zuweisungsoptionen pro Artikelzeile werden erst beim Öffnen des
  Kontextmenüs berechnet; die Liste filtert nicht mehr für jede sichtbare Zeile
  vorab alle verfügbaren Tags.
- Normale Feed-, Tag- und Smart-Filter-Listen blenden `Article.isHidden` aus; der
  Smart-Filter `Ausgeblendet` zeigt diese Artikel explizit wieder.
- Sortierung ist global per `@AppStorage(ArticleSortOption.storageKey)` gespeichert
  und gilt für Feed-, Tag- und Smartfilter-Listen.
- Toolbar-Menü `Sortieren nach` ist der primaere Einstieg für die Sortierung;
  die Menueleiste bietet dieselben Optionen unter `Darstellung > Sortieren nach`.
- Unterstützte Sortierungen: Neueste zuerst, Aelteste zuerst, Nach Feed, Nach
  Titel A-Z und Nach Lesezeit kurze zuerst.
- Filterung ist global per `@AppStorage(ArticleFilterOption.storageKey)` gespeichert
  und wird nach der Sortierung auf Feed-, Tag- und Smartfilter-Listen angewendet.
- Toolbar-Menü `Filtern` bietet als Schnellzugriff Alle, Ungelesen, Mit Stern,
  Archiviert und Heute. Die Sidebar bleibt weiterhin der primaere Einstieg für
  dauerhafte Smartfilter.
- Im Filtermenue gibt es zusätzlich die Leseanzeige `Gelesene ausblenden` bzw.
  `Gelesene und ungelesene anzeigen`; diese Umschaltung gilt für die aktuelle
  Liste.
- Toolbar-Menü `Als gelesen markieren` bietet Massenaktionen für die aktuell
  sichtbare Liste: älter als ein Tag, zwei Tage, drei Tage, vier Tage, eine Woche,
  zwei Wochen oder alle sichtbaren Artikel. Die Aktion wirkt nur auf den aktuell
  ausgewählten Feed beziehungsweise den aktuell ausgewählten intelligenten Ordner.
- Meldet nur den `ArticleNavigationState` an `ContentView`, damit Reader-Navigation
  und Menü-Status ohne Kopie der gesamten Artikelliste aktualisiert werden
- Reagiert mit `.onChange(of: articles)` auf Listen-Änderungen und erzeugt kein
  separates `articleIDs = articles.map(\.id)` Array mehr pro SwiftUI-Renderdurchlauf
- Nutzt `ArticleRowView` für Titel, Metadaten, Summary, optionales Bild,
  Ungelesen-Punkt rechts oben und Stern rechts unten
- Meldet `Exportieren...` aus dem Artikel-Kontextmenü nach oben an `ContentView`;
  `ArticleExportSheet` erzeugt daraus format- und optionsgesteuert Markdown,
  Plain Text oder HTML über `ArticleExportService`.
- Markiert Artikel beim Auswaehlen automatisch als gelesen, wenn die Einstellung
  aktiv ist
- Gelesene Artikel werden in Feed-, Tag- und Smartfilter-Listen standardmäßig
  ausgeblendet; am Listenende blendet ein Button `X gelesene Artikel anzeigen`
  die versteckten gelesenen Artikel für die aktuelle Liste ein.
- Artikel, die durch `Artikel beim Oeffnen als gelesen markieren` automatisch
  gelesen werden, bleiben in der aktuellen Liste sichtbar, bis der Feed, Tag oder
  Smartfilter gewechselt wird. So verschwindet die gelesene Zeile nicht direkt nach
  dem Klick, raeumt sich aber beim Listenwechsel wieder auf.
- Die sichtbare Suchleiste der Artikelliste nutzt den gemeinsamen Suchkern im
  leichten Modus: Sie durchsucht Titel und Zusammenfassung, aber nicht
  `Article.content` oder `Article.offlineContent`, damit große Volltextfelder beim
  Tippen nicht aus SwiftData gefaultet werden.

### ArticleListQuery.swift
- Buendelt Sortierung und Feed-Predicate für Artikel-Listen.
- Kapselt die leichten Listen-`FetchDescriptor` und verwendet dafür dieselbe
  Property-Liste wie `Article.lightFetchDescriptor`. Tests sichern ab, dass
  `content` und `offlineContent` nicht im Standard-Listenfetch enthalten sind.
- Stellt `initialFetchLimit` und `fetchBatchSize` (je 50) bereit; alle Listen-
  Descriptoren akzeptieren optional `fetchLimit` und setzen es direkt am
  SwiftData-`FetchDescriptor`.
- Feed-Listen filtern über `Article.feedID`, damit der Feed-Wechsel nicht über die
  `Article.feed`-Relationship predicated werden muss.
- Tag-Listen filtern über `Article.tags.contains { tag.id == selectedTagID }` und
  zusätzlich über die denormalisierte `Article.feedID` für getaggte Feeds; diese
  Predicates sind durch `ArticleListQueryTests` abgesichert.
- `ArticleListDisplayState` kapselt die sichtbaren Artikel, die Anzahl versteckter
  gelesener Artikel und die Button-Entscheidung für Feature 2.5 testbar ohne UI.
- `ArticleListDisplayState` blendet `isHidden`-Artikel aus normalen Listen aus; die
  Regel-Aktion zum Setzen dieses Status bleibt ein eigener Feature-16.3-Schritt.
- `ArticleSearchQuery`, `ArticleSearchField`, `ArticleSearchScope` und
  `ArticleSearchFilters` kapseln den testbaren Core-Slice der Artikelsuche
  inklusive case-/diakritik-insensitiver Textsuche sowie Filterung nach Feed, Tag,
  Zeitraum und Status. `ArticleSearchQuery.includesHeavyContent` kann
  Volltext-/Offline-Inhalt bewusst ausblenden; die Artikelliste nutzt das für die
  schnelle Inline-Suche, globale Suchpfade behalten den vollständigen Suchumfang.
- `ArticleSearchWindowState` kapselt die globale Suchfenster-Logik und sortiert
  Treffer standardmäßig nach neuesten Artikeln zuerst. Die Artikelliste selbst
  nutzt denselben Suchkern nur noch mit `scope: .currentView`.
- `ArticleListPreparedArticles` kapselt die gemeinsame Vorbereitung aus Sortierung,
  Filterung und aktiver Suche und ist mit Tests gegen doppelte Sortierungen sowie
  für Suchkombinationen abgesichert.

### ArticleSortOption.swift
- Kapselt die globale Sortierauswahl für Artikellisten inklusive `@AppStorage`-Key,
  Labels und testbarer Sortierlogik.
- `newestFirst` ist der Default und Fallback für unbekannte gespeicherte Werte.
- Sortiert optionale Datumswerte so, dass Artikel ohne Datum nach datierten
  Artikeln stehen; Lesezeit basiert auf Content, sonst Summary, mit 200 Woertern
  pro Minute.

### ArticleFilterOption.swift
- Kapselt die globale Filterauswahl für Artikellisten inklusive `@AppStorage`-Key,
  Labels, SF-Symbolen und testbarer Filterlogik.
- `all` ist der Default und Fallback für unbekannte gespeicherte Werte.
- Unterstützt Alle, Ungelesen, Mit Stern, Archiviert und Heute; der Heute-Filter
  vergleicht den `publishedAt`-Tag gegen das aktuelle Datum.

### ArticleNavigationState.swift
- Berechnet vorherigen und nächsten Artikel aus der aktuell sichtbaren Liste.
- Speichert nur die beiden Nachbar-Artikel und nicht mehr die komplette Liste, damit
  `ContentView` beim Feed-Wechsel weniger State kopieren muss.

### ArticleRowView.swift
- Reichhaltige Artikelzeile mit optionalem Bild aus `CachedRemoteImageView`
- Platzhalterbild, wenn kein `imageURL` vorhanden ist
- Artikelbilder werden in der Liste als größenbegrenzte Thumbnails geladen, damit
  lange Listen keine großen Originalbilder im Memory-Cache halten müssen.
- Kontextmenü für gelesen/ungelesen, Stern, Archivieren, Tag zuweisen,
  Regel erstellen, Link kopieren, Original oeffnen, Teilen, Offline speichern/
  entfernen, Artikel löschen und alle sichtbaren Artikel als gelesen markieren
- Prüft, ob Link-Aktionen verfügbar sind, über `ArticleOriginalURLResolver` und
  erzeugt dafür keine eigene `ArticleViewModel`-Instanz pro Kontextmenü-Aufbau.
- Erhält den Feednamen als einfachen String aus `ArticleListView` statt ihn über
  `article.feed?.title` zu faulten. Das hält Zeilen-Redraws beim schnellen Lesen
  frei von Feed-Relationship-Ladevorgängen.
- Gelesene Artikel werden optisch ruhiger dargestellt

### ArticleViewModel.swift
- `@Observable` class
- `toggleRead(_:)`
- `toggleStarred(_:)`
- `toggleArchived(_:)`
- Optionale Varianten ignorieren fehlende Auswahl für Menü-/Shortcut-Aktionen
- `markReadIfNeeded(_:isEnabled:)`
- `markAllRead(_:)` markiert eine sichtbare Artikelliste als gelesen und pflegt
  dabei die Feed-Zähler.
- `markRead(_:matching:now:calendar:)` markiert nur die sichtbaren Artikel als
  gelesen, die zur gewählten Zeitoption aus `ArticleMarkReadOption` passen, und
  pflegt ebenfalls die Feed-Zähler.
- Die context-basierten Lesestatus-Varianten korrigieren `Feed.unreadCount` über
  `Article.feedID`, wenn die `Article.feed`-Relationship im schnellen Query-Pfad
  nicht geladen ist.
- `markReadIfNeeded(_:isEnabled:updatesUnreadCount:context:)` kann den
  Feed-Zähler bewusst auslassen. Die Artikelliste nutzt das für Auto-Lesen und
  ruft danach `synchronizeUnreadCounts(forFeedIDs:context:)` gebündelt auf.
- Bulk-Lesestatus-Aktionen synchronisieren die betroffenen Feed-Zähler nach dem
  Markieren per SwiftData-`fetchCount`, damit bereits falsch gespeicherte
  `Feed.unreadCount` Werte wieder dem echten ungelesenen Bestand entsprechen.
- Die `ArticleMarkReadOption.allVisible`-Option wird in der Artikelansicht als
  `Alle als gelesen markieren` angezeigt, damit sie als Bulk-Aktion klar erkennbar
  ist.
- `deleteArticle(_:context:)` löscht einen Artikel aus SwiftData und korrigiert
  bei ungelesenen Artikeln den Feed-Zähler.
- `ArticleOriginalURLResolver` kapselt die stateless Validierung absoluter
  Artikel-Links. `ArticleViewModel.originalURL(for:)` nutzt denselben Helper, damit
  UI-Status und Aktionen dieselbe Logik teilen.
- `copyLink`, `openOriginal` und `shareOriginal` kapseln Link-Aktionen testbar über
  kleine Protokolle für Pasteboard, URL-Oeffnen und Share-Picker.
- Gelesen/Ungelesen-Änderungen aktualisieren `Feed.unreadCount`, damit Sidebar-Badges
  ohne eigene Artikel-Query aktuell bleiben
- `sortedForList(_:)` nutzt `ArticleSortOption.newestFirst`; `previousArticle(before:in:)`
  und `nextArticle(after:in:)` kapseln die Navigation innerhalb der aktuell sichtbaren
  Artikelliste.

### ArticleMetadataEditor.swift
- Kapselt die Bearbeitung der Artikel-Metadaten für den Reader-Inspector.
- `addTag(named:to:availableTags:context:)` trimmt Tag-Namen, verhindert leere oder
  doppelte Artikel-Tags und verwendet vorhandene Tags wieder, bevor neue Tags
  erstellt werden.
- `availableTagsToAdd(to:availableTags:)` liefert vorhandene globale Tags, die dem
  aktuellen Artikel noch nicht zugewiesen sind, alphabetisch sortiert für den
  rechten Inspector.
- `removeTag(_:from:context:)` entfernt ein Tag nur vom aktuellen Artikel.
- `setFolderName(_:for:context:)` speichert den getrimmten Ordnernamen am Feed des
  Artikels; leere Eingaben entfernen die Ordnerzuordnung.

### TagViewModel.swift
- `@Observable` `@MainActor` class für zentrale Tag-Verwaltung.
- Erstellt Tags mit normalisiertem Namen und normalisierter Hex-Farbe und gibt das
  neu erstellte Tag für direkte UI-Auswahl zurück.
- Verhindert leere und doppelte Tag-Namen case-insensitive beim Erstellen und
  Umbenennen.
- Aktualisiert Tag-Farben und löscht Tags inklusive vorhandener Artikel- und
  Feed-Verknuepfungen.

### TagManagerView.swift
- Zentrales Sheet zum Erstellen, Umbenennen, farblichen Markieren und Löschen von
  Tags.
- Nutzt eine SwiftData-`@Query` auf `Tag.name`, wiederverwendet `TagViewModel` für
  Validierung und Speichern und zeigt Fehler direkt in der jeweiligen Eingabe.
- Wird aus der Sidebar-Section `Tags` geöffnet; dieselbe Section zeigt auch
  klickbare Tag-Filterzeilen.
- Nach dem erfolgreichen Erstellen eines Tags schliesst sich das Sheet und die
  Sidebar wählt das neue Tag als aktuellen Filter aus.

### ArticleCommands.swift / ArticleCommandActions.swift
- macOS-Menü `Artikel` für Aktionen auf dem fokussierten/ausgewählten Artikel
- `Cmd+↑` springt zum vorherigen sichtbaren Artikel
- `Cmd+↓` springt zum nächsten sichtbaren Artikel
- `Cmd+Shift+U` toggelt gelesen/ungelesen
- `Cmd+D` toggelt Stern
- Archivieren, Teilen und Exportieren sind ebenfalls im Artikel-Menü verfuegbar.
- `Cmd+Return` öffnet den ausgewählten Artikel in einem dedizierten
  Artikelfenster.
- Der Exportdialog aus Feature 18.1a läuft über `ContentView` und ist über
  Artikel-Menü, Artikel-Kontextmenü sowie Reader-Toolbar erreichbar; Export via
  Share Sheet bleibt ein späterer Export-Slice.
- Commands sind deaktiviert, wenn kein Artikel ausgewählt ist oder am Listenrand
  kein vorheriger/nächster Artikel existiert
- `ContentView` stellt die Aktionen via SwiftUI `FocusedValues` bereit

### FeedCommands.swift / FeedCommandActions.swift
- macOS-Menü `Feed` für Aktionen auf dem fokussierten/ausgewählten Feed
- `Cmd+N` öffnet `Feed hinzufügen...` und nutzt dasselbe Sheet wie der Sidebar-Plus-Button
- `OPML importieren...` öffnet den erweiterten OPML-Import-Dialog: Datei wählen,
  erkannte Feeds prüfen, einzelne Feeds auswaehlen, Ordner zuweisen, neue Ordner
  anlegen, Duplikate optional erlauben und entscheiden, ob direkt aktualisiert wird
- Vor dem Import prueft Feedivo neue Feed-URLs über denselben Feed-Abrufpfad und
  markiert Duplikate sowie nicht erreichbare/problematische Feeds in der Review-Liste
- Nach dem OPML-Import können neu angelegte Feeds direkt über denselben async
  Refresh-Kern aktualisiert werden, damit Titel, Metadaten, Favicons und Artikel
  gefüllt sind; dieser Schritt ist im Dialog abschaltbar
- `OPML exportieren...` öffnet den OPML-Exportdialog mit Optionen für Ordner,
  Tags und Feed-Beschreibungen und verwendet den Dateinamen
  `Feedivo-Export-YYYY-MM-DD.opml`
- `Cmd+Shift+R` aktualisiert alle Feeds
- `Cmd+R` aktualisiert den ausgewählten Feed
- Feed aktualisieren und Feed löschen sind deaktiviert, wenn kein Feed ausgewählt ist
- OPML Export ist deaktiviert, solange keine Feeds vorhanden sind
- Kein Shortcut für Löschen, damit eine destruktive Aktion bewusst bleibt
- `ContentView` zeigt vor dem Löschen einen Bestätigungsdialog und setzt die
  Feed-/Artikel-Auswahl nach erfolgreichem Löschen zurück

### OPMLService.swift / OPMLDocument.swift
- `OPMLService.parseFeeds(from:)` liest OPML 2.0 mit verschachtelten `outline`-Eintraegen
  über `XMLParser`.
- Feed-Outlines werden aus `xmlUrl`/`xmlURL`, `title`/`text`, `htmlUrl`/`htmlURL`
  in `OPMLFeed` umgewandelt.
- Verschachtelte OPML-Gruppen werden für v1 als `Feed.folderName` übernommen,
  damit die Information erhalten bleibt und importierte Feeds direkt gruppiert sind.
- `OPMLService.exportFeeds(_:options:)` schreibt gueltiges OPML mit optionalen
  OPML-Gruppen, optionalen Feed-Tags als `category`, optionaler Feed-Beschreibung
  als `description` und XML-escaping für alle Attributwerte.
- `OPMLService.defaultExportFilename(date:)` erzeugt den v1-Dateinamen
  `Feedivo-Export-YYYY-MM-DD.opml`.
- `OPMLDocument` kapselt den SwiftUI `FileDocument` Export für `.opml` und `.xml`.

### OPMLExportSheet.swift
- Wiederverwendbarer SwiftUI-Dialog für den OPML-Export, ausgelöst aus dem
  Feed-Menü und aus Einstellungen → Feeds.
- Bildet den freigegebenen Product-Design-Prototyp ab: Header mit Feed-Anzahl,
  links Checkbox-Optionen, rechts Live-Zusammenfassung und unten `Abbrechen` /
  `Sichern...`.
- `Feed-URLs und Titel` ist sichtbar, aber immer aktiv; Ordner-Struktur, Tags und
  Feed-Beschreibungen können einzeln ein- oder ausgeschaltet werden.
- Der Dialog exportiert nur Abonnements, keine Artikel und keine Favoriten.

### OPMLImportReviewView.swift
- Eigenstaendiger SwiftUI-Dialog für den erweiterten OPML-Import nach Prototyp
  Variante A.
- Die OPML-Datei wird im Dialog ausgewählt und geparst; danach werden Feed-Titel,
  Feed-URL, Website, Ordner und Status in einer intern scrollenden Review-Tabelle
  angezeigt.
- Alternativ zur Datei-Auswahl kann eine `.opml`- oder `.xml`-Datei direkt auf das
  Importfenster gezogen werden; der Drop nutzt denselben Preview- und Pruefpfad wie
  der Button `Datei auswählen...`.
- Lange Feednamen und URLs werden einzeilig gekuerzt, damit das Dialogfenster auch
  bei vielen oder langen Feeds stabil bleibt.
- Der Benutzer kann nur ausgewählte Feeds importieren, vorhandene/neu erstellte
  Ordner pro Feed zuweisen, Duplikate und nicht erreichbare Feeds bewusst erlauben
  und den Refresh nach Import ein- oder ausschalten.
- Neu importierte Feeds übernehmen das aktuell gespeicherte globale
  Aktualisierungsintervall, damit der OPML-Import nicht unbemerkt auf den
  Feed-Default von 60 Minuten zurückfällt.
- Ein Status-Dropdown filtert die sichtbare Tabelle nach allen, neuen, doppelten
  oder nicht erreichbaren Feeds. Der Filter veraendert nur die Sichtbarkeit; Auswahl
  und Ordner-Änderungen an Zeilen bleiben beim Zurueckstellen auf alle erhalten.
- Waehrend die Import-Vorschau vorbereitet wird, zeigt die Tabellenflaeche selbst
  einen mittig platzierten Ladezustand mit konkretem Prueffortschritt
  (`Feed x von y wird geprüft: ...`), damit der Benutzer sieht, dass Feedivo
  weiterhin arbeitet.
- Nach dem Import bleibt eine Zusammenfassung im Dialog sichtbar.

### SettingsView.swift / NewSettingsView.swift
- `FeedivoApp.swift` nutzt nur noch die systemeigene SwiftUI-`Settings`-Scene.
  Diese öffnet direkt `NewSettingsView` mit der neuen Toolbar-Oberfläche.
- Die alte Sidebar-/Form-Fassung wurde am 2026-06-29 entfernt, nachdem alle
  Inhalte in die neue Settings-Oberfläche migriert wurden. Es gibt kein
  zusätzliches `SettingsCommands`-Menü und kein separates Fenster
  `Einstellungen alt` mehr.
- Nutzt eine kompakte macOS-Toolbar statt eines langen Formulars oder einer linken
  Kategorienavigation.
- `NewSettingsView` nutzt die Bereiche Allgemein, Anzeige, Feeds, Ordner, Cache,
  Offline, Benachrichtigungen, Aktualisierung, Automatisierung, Sync und Über.
  Die Oberfläche verwendet die echten Settings-Bindings und Verwaltungsviews.
- Allgemein enthält zusätzlich den Toggle `Artikelfenster beim Start
  wiederherstellen`, gebunden an
  `ArticleWindowSettings.restoreOpenArticleWindowsOnLaunchKey`; Standard ist aus.
- Die neue Fassung rendert die Kernbereiche nicht mehr über die alten
  `Form`-Views, sondern über screenshot-nahe `NewSettingsBlock`- und
  `NewSettingRow`-Bausteine mit kompakter Toolbar, ausgewählter Kachel,
  linksbündigem Titel/Subtext und rechts stehenden Controls. Die neue Fassung ist
  breit genug für Toolbar und Feed-/Ordnerverwaltung, behält aber die kleine
  macOS-Settings-Skalierung des Referenzscreenshots bei.
- Bestehende Optionen wurden aufgeteilt: Sprache/Standardverhalten unter
  Allgemein, UI-/Reader-Darstellung unter Darstellung, Auto-Refresh unter
  Aktualisierung, Artikel-Aufbewahrung unter Bereinigung sowie Regelverwaltung
  separat unter Regeln.
- Der Bereich `Feeds` zeigt eine Feed-Verwaltung mit Suche, Mehrfachauswahl,
  `Alle sichtbaren auswählen`, `Auswahl aufheben` und destruktiver
  Löschbestätigung für die ausgewählten Feeds. Jede Feed-Zeile zeigt zusätzlich
  die Artikelanzahl der letzten 7 Tage und den Zeitpunkt der letzten
  Aktualisierung.
- Der Bereich `Cache` zeigt aktuelle Bild-/Favicon-Cache-Groesse, ein Speicherlimit
  mit erlaubten Werten 100 MB, 250 MB, 500 MB, 1 GB und 2 GB, sowie Aktionen zum
  Aktualisieren der Groessenanzeige und zum Leeren des Cache. Zusätzlich zeigt er
  die Anzahl bewusst offline gespeicherter Artikel und deren Textspeicherbedarf
  aus `Article.offlineContent`; diese Offline-Kopien können dort getrennt vom
  normalen Bild-/Favicon-Cache gelöscht werden.
- Der Bereich `Bereinigung` enthält als ersten Slice von Feature 17.3 eine globale
  Artikel-Aufbewahrung: Alte Artikel können nach 30, 60, 90, 180 oder 365 Tagen
  automatisch gelöscht werden. Die Einstellung ist standardmäßig ausgeschaltet.
  Artikel mit Stern oder Archivstatus bleiben standardmäßig geschützt; in derselben
  Einstellung kann bewusst aktiviert werden, dass auch diese Artikel mitgelöscht
  werden. Ein Button `Jetzt bereinigen` startet dieselbe Logik manuell. Einzelne
  Feeds können diese globale Einstellung in `Feed Eigenschaften...` überschreiben.
- Geplanter späterer Ausbau für `Bereinigung`: History der letzten 10
  Bereinigungen mit Zeitpunkt und Anzahl gelöschter Artikel, konfigurierbarer
  automatischer Ausführungszeitpunkt (Wochentag/Uhrzeit, App-Start oder
  App-Beenden) und ein sichtbarer In-App-Hinweis, wenn eine Bereinigung
  ausgeführt wurde.
- Der Bereich `Regeln` enthält ausschließlich die Regelverwaltung.
- Der Bereich `Offline-Lesen` trennt bewusst zwischen Cache, normal lokal
  gespeichertem Feed-Inhalt und echten Offline-Kopien: Offline ist eine manuelle
  Artikelaktion, Feed-Content ist Basisinhalt, Automatik bleibt ein späterer M4-
  Folgepunkt.
- Der Bereich `Benachrichtigungen` enthält den Toggle
  `Badge-Zähler am App-Icon anzeigen`, einen Hinweis auf Feed-Benachrichtigungen
  pro Feed, den macOS-Erlaubnisstatus für Benachrichtigungen und einen Button zum
  Anfragen der Erlaubnis, solange macOS noch nicht gefragt wurde. Regel-
  Benachrichtigungen nutzen dieselbe macOS-Erlaubnis.
- `@AppStorage("markArticleReadOnSelection")`
- Standard: Artikel beim Oeffnen automatisch als gelesen markieren
- `@AppStorage("appLanguage")`
- Sprachauswahl: Nach System, Deutsch, Englisch, Französisch, Italienisch
- `@AppStorage("interfaceTextSize")`
- Oberflaechenschrift: Klein, Standard, Gross, Sehr groß; wirkt app-weit über
  eine eigene `InterfaceTextSize`-Environment und zusätzlich über SwiftUI
  `DynamicTypeSize`
- `@AppStorage("sidebar.showsReadFeeds")`
- Standard: Gelesene Feeds in der Seitenleiste anzeigen; ausgeschaltet bleiben
  Feeds ohne ungelesene Artikel in der Sidebar verborgen
- `@AppStorage("backgroundRefresh.isEnabled")`
- `@AppStorage("backgroundRefresh.refreshOnLaunchIsEnabled")`
- `@AppStorage("backgroundRefresh.intervalMinutes")`
- Automatischer Refresh ist standardmäßig deaktiviert und kann auf 15, 30, 60
  oder 120 Minuten gestellt werden
- `Feeds beim Start aktualisieren` ist eine separate, standardmäßig deaktivierte
  Option in `Einstellungen → Aktualisierung`. Wenn aktiv, startet Feedivo nach
  dem Öffnen des Hauptfensters einmalig einen sichtbaren Sammel-Refresh mit der
  aufklappbaren Fortschrittsanzeige aus Feature 4.6.
- Reader-Schriftwahl: `readerTitleFontPreset` und `readerBodyFontPreset`
- Reader-Fettoptionen: `readerTitleFontIsBold` und `readerBodyFontIsBold`
- Reader-Typografie: `readerBodyFontSize`, `readerTitleLineSpacing`,
  `readerLineSpacing` und `readerContentWidth`
- Presets: System, Geist, Inter, Manrope, DM Sans, Literata, Newsreader,
  IBM Plex Sans, Atkinson Hyperlegible, Source Serif 4, Libre Franklin, Lora,
  Merriweather, Noto Sans, Noto Serif, Roboto Slab, Crimson Pro, Fraunces, Serif

### InterfaceTextSize.swift
- Kapselt die app-weite UI-Schriftgroesse getrennt von der Reader-Typografie.
- Gespeicherter Wert: `interfaceTextSize`; Default: `standard`.
- Werte: Klein, Standard, Gross, Sehr groß; unbekannte gespeicherte Werte fallen
  auf Standard zurück.
- Mapping auf SwiftUI `DynamicTypeSize` plus eigene konkrete Skalierungswerte für
  fest gestaltete UI-Bereiche.
- Sidebar, Feed-Zeilen, Artikelzeilen und Settings lesen `interfaceTextSize` aus
  der SwiftUI-Environment und skalieren Font- sowie wichtige Icon-/Zeilenmasse
  sichtbar mit.

### ReaderView.swift
- Zeigt Metazeile, Titel, native Reader-Bloecke und Link zum Original
- Metazeile: Feedname, ungefaehre Lesezeit und Artikelalter, linksbuendig oberhalb
  des Titels
- Nach dem Lead-Bild erscheint ein feiner Trenner, bevor der Fließtext beginnt.
- Nutzt einen ruhigeren Editorial-Rhythmus: etwas kleinerer semibold Titel,
  größere Blockabstaende, kontrollierte Lead-Bildhoehe und dezenter Footer für
  `Original öffnen`.
- Ordner und Tags werden direkt unter dem Titel als dezente Chips angezeigt. Hinter
  den Tags sitzt ein dezenter + Button, der ein Inline-Popover zum Zuweisen,
  Entfernen und Erstellen von Tags öffnet. Die Logik nutzt wie der rechte Inspector
  `ArticleMetadataEditor`, damit Tag-Erstellung und Tag-Zuweisung konsistent
  bleiben.
- Der offene/geschlossene Inspector-Zustand kommt als Binding aus `ContentView`,
  damit die rechte Seitenleiste beim Feed- oder Artikelwechsel erhalten bleibt.
- Die rechte Seitenleiste wird über SwiftUIs native `.inspector`-Spalte angezeigt;
  dadurch verschiebt sich die Reader-Toolbar beim Einblenden nach links wie bei
  einer normalen macOS-Inspector-Leiste.
- Der native Artikel-Reader blendet seine vertikale Scrollbar aus, damit der
  Übergang zur rechten Inspector-Leiste ruhiger wirkt; Scrollen bleibt unveraendert
  moeglich.
- Native Reader-ScrollViews sind an `article.persistentModelID` gebunden, damit
  ein Artikelwechsel immer oben im neuen Artikel startet und nicht den
  Scroll-Offset des vorherigen Artikels übernimmt.
- Native Reader- und Readability-Inhalte nutzen `LazyVStack`, damit lange Artikel
  beim Öffnen oder Wechseln nicht sofort alle Text-/Bild-Blöcke als SwiftUI-Views
  materialisieren. Das reduziert CPU-Zeit beim Lesen spürbar.
- Wenn ein Feed nur eine Summary, aber keinen Volltext liefert, zeigt der native
  Reader die vorhandene Zusammenfassung direkt ohne zusaetzliche Hinweisbox.
- Reader-Modi: `Nativer Reader`, `Vollartikel` und `Originalansicht`. Der
  Vollartikel-Modus nutzt Readability.js in einem versteckten `WKWebView`, startet
  automatisch beim Auswählen des Modus und beim Artikelwechsel, solange für die
  aktuelle URL noch kein Vollartikel geladen wird oder geladen ist.
- Entscheidung 2026-06-30: Der per Readability extrahierte Vollartikel wird nur
  temporär im Reader angezeigt. Er wird nicht als `Article.content` oder
  `offlineContent` gespeichert; dauerhaftes Speichern bleibt der manuellen
  Offline-Funktion vorbehalten.
- Entscheidung 2026-06-30: Wenn ein Vollartikel nicht geladen werden kann, zeigt
  der Reader einen respektvollen Hinweis, dass der Anbieter das Laden nicht
  zulässt und Feedivo diese Vorgabe respektiert. Technische Fehlerdetails stehen
  nicht im Vordergrund der UI.
- Toolbar-Buttons für vorherigen/nächsten Artikel navigieren innerhalb der aktuell
  sichtbaren Feed- oder Smart-Filter-Liste und stoppen am Listenrand
- Seltenere Aktionen wie `Link kopieren` liegen im Reader-Mehr-Menü, damit die
  Toolbar ruhiger bleibt.
- Toolbar-Button `textformat` öffnet ein Popover für Titel-Schrift,
  Titel-Fett, Fließtext-Schrift, Fließtext-Fett, Textgroesse,
  Titel-/Fließtext-Zeilenabstand und Artikelbreite
- Titel- und Fließtext-Schrift sowie Textgroesse/Titel-Zeilenabstand/
  Fließtext-Zeilenabstand/Artikelbreite werden getrennt via `@AppStorage`
  gespeichert. Titel und Artikeltext haben zusätzlich getrennte Fett-Schalter.
- Die Metazeile oberhalb des Titels sowie Ordner-/Tag-Chips nutzen die App-
  Oberflaechenschrift (`interfaceTextSize`) statt der Reader-Schriftwahl, damit sie
  optisch zur restlichen App passen.
- Toolbar-Button `arrow.down.circle` speichert den aktuellen Artikel manuell für
  Offline-Lesen oder entfernt die Offline-Kopie wieder. Waehrend des Downloads zeigt
  der Button einen Fortschrittsindikator.
- Der Reader zeigt einen kompakten Offline-Status nur für bewusst gespeicherte
  Artikel: Feed-Inhalt lokal verfuegbar, Volltext offline verfuegbar oder Fehler
  inklusive Fehlermeldung.
- Produktbegriff: Normaler Feed-Content ist nicht automatisch eine Offline-Kopie.
  Nur ein bewusst per Reader-Button gespeicherter Artikel zeigt einen Offline-
  Status am Artikel; vorhandener Feed-Content wird im Reader als lokal verfuegbarer
  Basisinhalt beschrieben.
- Nutzt `ReaderPreparedArticle`, damit Content/Summary, Metadaten und Original-URL
  pro ausgewähltem Artikel einmal vorbereitet werden und SwiftUI-Redraws kein
  erneutes HTML-Rendering auslösen
- Aktualisiert `ReaderPreparedArticle` über eine leichte Beobachtungssignatur
  statt über `article.content`/`article.offlineContent`, damit ein Artikelwechsel
  nicht schon beim SwiftUI-View-Aufbau schwere SwiftData-Faults auslöst.
- Lädt den eigentlichen Volltext-Snapshot über `ReaderArticleContentLoader` mit
  eigenem SwiftData-`ModelContext` anhand der Artikel-ID. Dadurch faultet
  `Article.content`/`Article.offlineContent` nicht mehr aus dem UI-`Article` im
  MainActor-Pfad, sondern in einem Hintergrund-Task.
- Startet den Reader mit einem leichten Preview-Snapshot inklusive Feedname sowie
  einem separaten Relationship-Metadata-Snapshot für Feed-Ordner und Tags. Die
  Header-Chips halten nur einfache Werte (`id`, Name, Farbe) statt lebender
  `Tag`-Modelle, damit Feedname, Ordner und Tags beim Artikelwechsel nicht sichtbar
  nachlaufen. Nach Inline-Tag-Aktionen wird dieser Snapshot sofort aktualisiert.
- Reicht Feedname, Ordnername, Content-Verfügbarkeit und vorbereitete Lesezeit an
  den rechten Inspector weiter, damit dessen SwiftUI-Body nicht erneut
  `Article.content`, `Article.offlineContent` oder `article.feed?.title` faultet.
- Zeigt beim Artikelwechsel sofort eine leichte Reader-Vorschau aus Summary und
  Bild-URL, statt den nativen Reader auf einen blanken Ladezustand zu setzen.
  Reader-Bilder verwenden keinen sichtbaren Spinner mehr.
- Aktualisiert `ReaderPreparedArticle` bei Wechsel von `article.persistentModelID`,
  damit Bild, Text, Metadaten und Original-Link nicht vom zuvor ausgewählten
  Artikel im SwiftUI-`@State` hängen bleiben
- Bilder werden mit `scaledToFit`, begrenzter Maximalhöhe und Ziel-Pixelgröße
  gerendert, damit große Feedbilder ruhiger und performanter bleiben
### ReaderPreparedArticle.swift
- Kapselt die vorbereiteten, teureren Reader-Daten für einen Artikel.
- Berechnet native Content-Bloecke, Metazeile, Lesezeit, Content-Verfügbarkeit und
  gueltige Original-URL einmal beim Erzeugen von `ReaderView`, statt diese Werte
  bei jedem SwiftUI-Redraw neu aufzubauen.
- `ReaderArticleCacheKey` speichert keine kompletten `content`-/
  `offlineContent`-Strings mehr, sondern kompakte Text-Fingerprints. Der Cache
  hält dadurch keine zusätzlichen Kopien langer Artikeltexte.
- Bevorzugt explizit gespeicherten `Article.offlineContent` vor Feed-Content und
  Summary, damit manuell offline gespeicherte Artikel direkt im nativen Reader
  erscheinen.
- Erkennt, ob offline geladener Volltext, Feed-Content, nur eine Summary oder gar
  kein Text verfuegbar ist; der Reader nutzt diese Information für Statushinweise.

### ArticleExportService.swift / ArticleExportDocument.swift
- `ArticleExportService` erzeugt Markdown, Plain Text und HTML für einzelne
  Artikel. Der Export ist format- und optionsgesteuert; Metadaten können ein- oder
  ausgeblendet werden. PDF und DOCX sind technisch prototypisiert, werden aber im
  Exportdialog bewusst nicht angeboten und bleiben ein späterer Slice.
- `ArticleExportSnapshot` loest die benoetigten Primitive vor dem Dateidialog aus dem
  SwiftData-Modell, damit der Export nicht an späteren Model-Faults oder
  Relationships haengt. Er enthält Titel, Autor, Datum, Feedname, Link, Tags sowie
  die verfügbaren Artikeltexte.
- Der Export nutzt bewusst keinen AppKit-/WebKit-HTML-Importer, sondern einfache
  sichere HTML-Konvertierung und Sanitizing-Helpers, damit fremdes Feed-HTML beim
  Export keinen harten AppKit-Trap ausloest. Unsichere Links werden im HTML-Export
  nicht als klickbare Links ausgegeben.
- Der Export bevorzugt gespeicherten Offline-Content vor Feed-Content und Summary.
- `ArticleExportFormat.dialogFormats` ist die Produkt-Freigabeliste für den
  Exportdialog und enthält aktuell nur Markdown, Plain Text und HTML.
- `defaultFilename(for:format:)` erzeugt kurze, dateisystemtaugliche Dateinamen
  aus dem Artikeltitel.
- `ArticleExportDocument` kapselt den SwiftUI-`FileDocument` für den nativen
  Speichern-Dialog und unterstützt Markdown, Plain Text, HTML, PDF, DOCX und
  ZIP-Daten. Text-, Binär- und ZIP-Export laufen bewusst über denselben
  FileDocument-Pfad, damit das Export-Sheet nicht mehrere `.fileExporter`
  Präsentationen gegeneinander schaltet.
- `ArticleDocumentExportRenderers` erzeugt PDF-Daten über native macOS-
  PDF-Erzeugung und DOCX-Daten als minimales OpenXML-ZIP. Der PDF-Renderer baut
  aus dem sicheren Artikel-HTML einen Reader-nahen Dokumentkopf mit kompakter
  Feed-/Lesezeit-/Datum-Zeile, Reader-Titel und bei aktivierter Metadaten-Option
  einem eigenen sichtbaren Metadatenblock. Geladene Artikelbilder werden als
  `data:`-URLs eingebettet, die Reader-Typografie aus den Darstellungseinstellungen
  wird übernommen und der komplette Artikel wird über mehrere Seiten paginiert.
  DOCX ist im ersten Slice textbasiert und editierbar; Bilder im DOCX bleiben
  bewusst späterer Ausbau.
- `ArticleExportPackageBuilder` baut für Markdown-/HTML-Exporte optional ein
  ZIP-Paket: Die Artikeldatei liegt im ZIP-Root, Bilder liegen im festen
  Unterordner `Pictures`, und Bildpfade in Markdown/HTML werden relativ auf diese
  Dateien umgeschrieben. Nicht ladbare Bilder blockieren
  den Export nicht und werden im Paket-Ergebnis für den Dialog mitgezählt. Der
  Builder meldet Fortschritt für Dokumentvorbereitung, Bild-Download und
  ZIP-Erstellung, damit der Dialog den aktuellen Arbeitsschritt anzeigen kann.
  Für PDF lädt derselbe Builder Artikelbilder automatisch, bettet sie direkt in
  das PDF-HTML ein und gibt weiterhin eine einzelne `.pdf` statt eines ZIPs aus.
  Die Vorschau bettet geladene Paketbilder temporär als `data:`-URLs ein, damit
  relative Exportpfade wie `Pictures/image-1.jpg` in WebKit sichtbar sind, ohne
  den eigentlichen Markdown-/HTML-Export zu verändern.
- `ArticleExportSheet` ist ein zweistufiger Exportdialog nach Product-Design-
  Variante B: zuerst Format und Metadaten wählen, dann Vorschau prüfen und mit
  `Sichern...` den nativen `.fileExporter` öffnen. Markdown und HTML werden in
  der Vorschau gerendert, Plain Text bleibt als monospaced Textvorschau sichtbar.
  PDF und DOCX werden im GUI vorerst nicht angeboten. Im Vorschau-Schritt kann die
  vorbereitete Exportdatei außerdem über `Teilen...` an das macOS Share Sheet
  übergeben werden.
  Die Markdown-Vorschau läuft über `ArticleExportPreviewRenderer`, der den
  Markdown-Export für die Vorschau in ein kleines, sicheres HTML-Dokument
  übersetzt und dieses wie die HTML-Vorschau in WebKit rendert.
  Die Präsentation bleibt über `ContentView` stabil, damit der Export nicht direkt
  aus kurzlebigen Kontextmenüs oder Unteransichten gestartet wird.

### OfflineDownloadService.swift
- Speichert Artikel manuell für Offline-Lesen.
- Nutzt vorhandenen `Article.content` sofort als Offline-Content, wenn der Feed
  bereits Volltext liefert.
- Laedt andernfalls die Original-URL per `URLSession` und speichert den geladenen
  HTML/Text in `Article.offlineContent`.
- Schreibt Status, Zeitpunkt und Fehlermeldung direkt auf den Artikel:
  `none`, `feedContent`, `fullText` oder `failed`.
- Sammelt beim Offline-Speichern die bekannte Lead-Bild-URL (`Article.imageURL`)
  und Inline-Bilder aus dem gespeicherten Content und gibt sie an den lokalen
  Bildcache weiter.
- Entfernt Offline-Daten bewusst getrennt von normalem Feed-Content, damit Feedivo
  die vom Feed gelieferten Inhalte nicht verliert.
- `archiveForOffline(_:)` speichert eine explizite Offline-Kopie und setzt
  `Article.isArchived` nur, wenn Offline-Content verfuegbar ist.
- `removeArchive(from:)` entfernt Archivstatus und Offline-Kopie, laesst den Artikel
  selbst aber in SwiftData bestehen.
- `removeOfflineContent(from:)` setzt ebenfalls `isArchived = false`, damit kein
  Archivstatus ohne lokale Kopie stehen bleibt.
- `OfflineArticleStorage` kapselt die Zaehllogik und das Sammel-Loeschen fuer die
  neuen Cache-Einstellungen. Es zaehlt nur Artikel mit verfuegbarem
  Offline-Status (`feedContent`/`fullText`) und misst bewusst nur
  `Article.offlineContent`, nicht den gemeinsamen Bild-/Favicon-Cache.
- Offline-Automatik ist absichtlich nicht Teil dieses Services. Sie soll später
  als eigene Strategie mit Feed-/Zeit-/Stern-/Ungelesen-Regeln und Speichergrenzen
  gebaut werden.

### ArticleFeedIDBackfillService.swift / OrphanedArticleCleanupService.swift
- `ArticleFeedIDBackfillService` füllt bei alten Artikeln die direkte `feedID`
  aus einer noch vorhandenen `Article.feed`-Relationship nach.
- `OrphanedArticleCleanupService` laeuft danach beim App-Start und entfernt Artikel,
  deren `feedID` zu keinem existierenden Feed mehr gehoert. Artikel ohne `feedID`
  bleiben erhalten, wenn ihre alte `Article.feed`-Relationship noch auf einen
  existierenden Feed zeigt.
- Der Cleanup nutzt einen schlanken `FetchDescriptor<Article>` mit `id` und
  `feedID`; die Relationship wird nur als Fallback für migrationsnahen Altbestand
  berührt.
- Hintergrund: Smart-Filter fragen Artikel direkt ab. Verwaiste Altartikel können
  sonst sichtbar bleiben, obwohl links keine Feeds mehr vorhanden sind.
- `FeedViewModel.deleteFeed` löscht zusätzlich explizit alle Artikel mit passender
  `feedID`, damit kuenftige Feed-Loeschungen nicht nur von SwiftData-Cascade
  abhaengen.

### ImageCacheService.swift / ImageCacheSettings.swift
- `ImageCacheService` ist der zentrale lokale Cache für Artikelbilder und Favicons.
- Nutzt `NSCache<NSURL, NSImage>` für schnelle Wiederverwendung während der App-
  Laufzeit und einen Disk-Cache unter dem macOS-Caches-Verzeichnis für Neustarts.
- Für Listen-Thumbnails nutzt der Cache einen separaten Memory-Cache mit Zielgröße:
  Der Disk-Cache bleibt originaldatenbasiert, während Artikelzeilen nur kleine
  `NSImage`-Instanzen halten.
- Cache-Dateinamen werden aus einem SHA-256-Hash der Bild-URL gebildet, damit
  Sonderzeichen, Query-Parameter und lange URLs keine Dateisystemprobleme machen.
- Netzwerkabrufe laufen über ein kleines `ImageDataLoading`-Protokoll, damit der
  Cache ohne echtes Netzwerk getestet werden kann.
- Cache-Groesse, Leeren und Trimmen nach Limit sind testbar und werden in den
  Einstellungen verwendet.
- `ImageCacheSettings` kapselt erlaubte Speicherlimits, Default 500 MB und
  formatierte Groessenanzeige.
- Feedivo raeumt den Bildcache beim App-Start auf das aktuell gesetzte Limit auf,
  nach jeder Limit-Änderung in den Einstellungen und nach jedem erfolgreichen
  neuen Bilddownload.
- Der Cache ist bewusst ein Performance-Cache. Er macht Bilder schneller und
  netzwerksparender, ist aber keine Garantie für eine echte Offline-Kopie.

### CachedRemoteImageView.swift
- Gemeinsame SwiftUI-Bildkomponente für remote Bilder mit lokalem Cache.
- Ersetzt direkte `AsyncImage`-Nutzung in Artikelliste, Reader, Sidebar-Favicons,
  Feed-Eigenschaften und Feed-Umbenennen-Sheet.
- Kann optional ein `targetPixelSize` an den Cache weitergeben; genutzt wird das
  aktuell für Artikelzeilen-Thumbnails, während Reader und andere Detailansichten
  weiterhin die Originalgröße laden.
- Views liefern nur Darstellung und Platzhalter; Laden, Memory-Cache und Disk-Cache
  bleiben im `ImageCacheService`.

### ArticleMetadataInspectorView.swift
- Einblendbarer rechter Inspector in der Artikelansicht.
- Nutzt denselben hellen, systemnahen Sidebar-Stil wie die linke Seitenleiste und
  teilt sich die Farbwerte aus `SidebarStyle`.
- Nutzt seit 2026-06-23 die gewählte Product-Design-Richtung
  `Calm Actions` aus den interaktiven Inspector-Prototypen: Oben stehen kompakt
  `Artikelinfos`, der Artikeltitel und ein Status-Strip für gelesen/ungelesen und
  Favorit; direkt darunter liegt eine vierteilige Aktionsleiste für Favorit,
  Gelesen/Ungelesen, Offline-Speichern und Link-Kopieren.
- Die Inspector-Typografie ist bewusst kompakter als der Reader-Text; zentrale
  Groessen liegen in `ArticleInspectorTypography`, damit die rechte Leiste ruhig
  und übersichtlich bleibt. Die aktuelle Skala nutzt 11 pt für Labels/Chips,
  11.5 pt für Controls, 12 pt für Werte, 13 pt für Section-Titel und 15 pt nur
  für den Artikelkopf.
- Zeigt den aktuellen Feed-Ordner in einer eigenen weissen Karten-Section als
  Menu-Picker, schreibt Änderungen direkt auf `Feed.folderName` und kann neue
  Feed-Ordner direkt anlegen und auswaehlen.
- Zeigt globale Tags in einer eigenen weissen Karten-Section als Toggle-Pills wie
  im Prototyp; aktive Tags sind getoent, inaktive Tags bleiben weiss. Ein Klick
  setzt oder entfernt das Tag direkt am Artikel.
- Nutzt einklappbare weisse Karten-Sections mit Chevron und ohne zusaetzliche
  Section-Icons für `Feed-Ordner`, `Tags`, `Kontext` und `Quelle`. Der Kontext
  zeigt Feed, Quelle, Veroeffentlichung, Lesezeit und Offline-Status in einer
  kompakten Metadatenliste.
- Nutzt für Feedname, Ordnername, Lesezeit und Content-Verfügbarkeit die von
  `ReaderView` vorbereiteten Snapshot-Werte. Der Inspector greift im Body dadurch
  nicht mehr direkt auf Volltext-/Offline-Textfelder des SwiftData-Artikels zu.
- Die Ordnerauswahl hält keine `@Query` auf alle Feeds mehr. Beim Erscheinen des
  Inspectors werden vorhandene Feed-Ordnernamen einmal als leichter Snapshot mit
  `propertiesToFetch` geladen und danach mit explizit angelegten `FeedFolder`-
  Namen kombiniert.
- Die Quelle ist standardmäßig eingeklappt und folgt dem Prototyp als reine
  Aktions-Section mit zwei breiten Zeilen für `Link kopieren` und `Original
  oeffnen`; die URL selbst wird dort bewusst nicht mehr als Textbox gezeigt.
- Neue interaktive Product-Design-Exploration für eine ruhigere, staerker
  bedienbare Inspector-Seitenleiste liegt unter
  `docs/design/article-info-interactive-sidebar-prototypes/`: drei React/Vite-
  Prototypen testen Favorit-, Gelesen-, Offline-, Tag-, Ordner- und Link-Aktionen
  direkt in der rechten Seitenleiste; Tags können im Prototyp mit eigener Farbe
  neu erstellt und sofort dem Artikel zugewiesen werden. Der Ordner wird dort
  bewusst als `Feed-Ordner` bezeichnet, weil er die Feed-Zuordnung und nicht eine
  einzelne Artikelablage veraendert; neue Feed-Ordner können im Prototyp direkt
  erstellt und sofort für den Feed ausgewählt werden. Feed-Ordner und Tags sind
  im Prototyp bewusst als getrennte Sections angelegt.
- Umgesetzte Richtung in SwiftUI ist Variante 1 `Calm Actions`: ruhige weisse
  Karten-Sections mit runden Ecken, separatem Feed-Ordner und Tags-Bereich sowie
  direkter Aktionsleiste oben. Die fruehere Hero-/Timeline-Anmutung wurde entfernt,
  damit die native App dem ausgewählten Prototyp klarer entspricht.
- `ArticleInspectorFormatter` kapselt die Anzeigeaufbereitung für Status, URL,
  Titel-/Summary-Kontext, Lesezeit und Verfuegbarkeit, damit die Inspector-View
  keine Fachlogik verteilt.
- Neue Tags werden über `ArticleMetadataEditor` normalisiert und als globale
  `Tag`-Eintraege wiederverwendet oder neu erstellt.
- Stellt `FlowLayout` modulweit bereit, damit Reader und Inspector dieselbe
  umbruchfaehige Chip-Anordnung verwenden.

### ArticleWindowView.swift / ArticleWindowSettings.swift
- `ArticleWindowView` ist das dedizierte Mehrfenster-Reader-Fenster für einzelne
  Artikel. Es nutzt `ReaderView` wieder, hält den rechten Artikel-Inspector als
  fensterlokalen Zustand und zeigt einen leeren Zustand, wenn der Artikel nicht
  mehr existiert.
- Das Fenster wird über `ArticleWindowRequest(articleID:)` geöffnet; `FeedivoApp`
  registriert dafür `WindowGroup(for: ArticleWindowRequest.self)`. Gleiche
  Artikel-IDs laufen über denselben SwiftUI-WindowGroup-Wert, damit macOS
  bestehende Artikelfenster fokussieren kann.
- Vorheriger/nächster Artikel funktioniert im Artikelfenster über die globale
  Artikel-Sortierung aus `ArticleListQuery.sortDescriptors`.
- `ArticleWindowSettings` speichert die zuletzt offenen Artikelfenster als
  Artikel-UUIDs und stellt den Settings-Key für die optionale Wiederherstellung
  bereit. Beim Navigieren im Artikelfenster wird die gespeicherte ID vom alten auf
  den neuen Artikel umgezogen.

### ReaderFontPreset.swift
- Kuratierte Font-Presets für die Artikelansicht aus der UI-Referenz:
  System, Geist, Inter, Manrope, DM Sans, Literata, Newsreader, IBM Plex Sans,
  Atkinson Hyperlegible, Source Serif 4, Libre Franklin, Lora, Merriweather,
  Noto Sans, Noto Serif, Roboto Slab, Crimson Pro, Fraunces, Serif
- Kapselt Anzeigenamen, bekannte PostScript-Kandidaten, SwiftUI-Font-Erzeugung und
  Fallback für unbekannte gespeicherte Werte
- System- und Serif-Presets nehmen optionales Font-Weight direkt in der Font-
  Erzeugung an; Custom-Fonts bleiben über PostScript-Namen adressiert und werden
  zusätzlich per SwiftUI-`fontWeight` gewichtet.
- Custom-Fonts registrieren die gebündelten Fonts beim Erzeugen der SwiftUI-Font
  sicherheitshalber erneut und wählen den ersten tatsächlich verfügbaren
  PostScript-Namen aus der Kandidatenliste. Dadurch bleibt die Schriftwahl robust,
  wenn die App nach Neustart/Build zuerst einen Reader mit gespeicherter Custom-
  Schrift öffnet.
- Custom-Fonts werden per PostScript-Namen angesprochen und als TTF-Dateien in
  `Feedivo/Resources/Fonts/` gebundelt

### ReaderFontRegistry.swift
- Registriert die gebundelten TTF-Dateien beim App-Start via CoreText
- Sucht Fonts zuerst unter `Fonts/` und danach flach im App-Resource-Bundle, weil Xcode
  synchronized groups Ressourcen flach kopieren kann

### ReaderTypography.swift
- Kapselt Defaults und Grenzwerte für Reader-Typografie
- Fett-Defaults: Titel und Artikeltext sind standardmässig nicht auf Bold gestellt;
  der Titel bleibt ohne Option semibold, der Artikeltext regular.
- Fließtext-Groesse: Default 17 px, Wertebereich 14...24 px
- Titel-Zeilenabstand: Default 2 px, Wertebereich 0...10 px
- Fließtext-Zeilenabstand: Default 5 px, Wertebereich 1...12 px
- Artikelbreite: Default 720 px, Wertebereich 520...980 px, Schrittweite 20 px
- Artikelabstand: oben 44 px, unten 28 px, damit der Artikelkopf ruhiger unter der
  Toolbar startet.
- Reader-Trenner: feine Linie mit 0.18 Opazitaet; Abstand zwischen Lead-Bild und
  Bild/Text-Trenner 14 px.

### ReaderMetadataFormatter.swift
- Berechnet ungefaehre Lesezeit mit 200 Woertern pro Minute, mindestens 1 Minute
- Verwendet `Article.content` vor `Article.summary`
- Baut Metadaten-Teile so zusammen, dass fehlende Werte ausgelassen werden
- Sichtbarer Lesezeit-Text ist via `Localizable.xcstrings` und `L10n` lokalisiert
- Produktentscheidung 2026-06-29: Die Lesezeit bleibt im Reader sichtbar, wird aber
  bewusst nicht in der Artikelliste angezeigt, weil sie dort kein relevantes
  Scanning-Signal fuer den User ist.

### ReaderContentRenderer.swift
- Wandelt HTML-Fragmente oder Plain Text in `ReaderContentBlock`
- Aktuelle Block-Typen: `.paragraph(String)`, `.heading(String)`, `.quote(String)`,
  `.listItem(String)` und `.image(urlString:)`
- Erkennt Absätze, Überschriften, Zitate, Listenpunkte und Bildbloecke
- Cacht die verwendeten `NSRegularExpression` Instanzen statisch, damit beim
  Artikelwechsel keine Regexes neu kompiliert werden.
- Die Erkennung, ob ein bereits per Regex gefundenes HTML-Segment ein Bildblock
  ist, nutzt eine einfache case-insensitive Suche nach `<img` statt einer weiteren
  Regex-Auswertung im Loop.
- Wandelt HTML-Textblöcke mit einem schnellen Tag-Stripper und Entity-Decoder in
  Plain Text um; der frühere `NSAttributedString`/WebKit-Pfad pro Textblock wird
  nicht mehr genutzt.
- Setzt das Lead-Bild immer als ersten Content-Block direkt unter den Titel:
  `Article.imageURL` gewinnt, sonst wird das erste HTML-`img` aus dem Inhalt nach
  vorne gezogen.
- Fallback: Wenn `Article.content` leer ist, wird `Article.summary` verwendet
- Doppelte Bilder mit derselben URL wie `Article.imageURL` werden aus dem restlichen
  Content entfernt.

### Lokalisierung / i18n
- `Feedivo/Resources/Localizable.xcstrings` ist die zentrale String Catalog Datei
- Erste Sprachen: Deutsch (`de`), Englisch (`en`), Französisch (`fr`), Italienisch (`it`)
- `Feedivo/Resources/AppLanguage.swift` kapselt System-/Sprachauswahl und Locale-Mapping
- `Feedivo/Resources/L10n.swift` bündelt lokalisierte Strings für ViewModels,
  Services und Tests
- SwiftUI-Views verwenden lokalisierte `LocalizedStringKey`/`String(localized:)`
- Feed- und Parser-Fehlermeldungen sind lokalisiert
- Benutzer können in den Einstellungen `Nach System` oder eine feste Sprache wählen

---

## Datenmodell (SwiftData)

> **Wichtig für CloudKit:** Alle Properties müssen `Optional` sein ODER einen Default-Wert
> haben — sonst crasht die CloudKit-Synchronisation.
> Alle SwiftData-Relationships, die in den CloudKit-Sync laufen, müssen optional
> sein (`[Article]?`, `[Tag]?`, ...). CloudKit lädt den Store sonst mit
> `SwiftDataError 1` / CoreData `134060` nicht.
> URLs werden als `String` gespeichert (CloudKit unterstützt keinen nativen URL-Typ).

```swift
@Model class Feed {
    var id: UUID
    var url: String
    var title: String                         // Anzeigename in Feedivo
    var originalTitle: String?                // Urspruenglicher Titel aus Feed-Metadaten
    var feedDescription: String?
    var faviconURL: String?
    var siteURL: String?
    var followedAt: Date?
    var folderName: String?
    var lastRefreshed: Date?
    var refreshIntervalMinutes: Int          // Default: 60
    var articleRetentionOverridesGlobalSetting: Bool // Default: false
    var articleRetentionIsEnabled: Bool      // Feed-eigene Aufbewahrung aktiv
    var articleRetentionDays: Int            // Feed-eigene Tage, Default: 90
    var articleRetentionIncludesProtectedArticles: Bool // Stern/Archiv mitlöschen
    var unreadCount: Int                     // Vorberechneter Sidebar-Zähler
    @Relationship(deleteRule: .cascade) var articles: [Article]
    @Relationship(deleteRule: .cascade, inverse: \FeedLogEntry.feed) var logEntries: [FeedLogEntry]
    @Relationship var tags: [Tag]
}

@Model class FeedFolder {
    var id: UUID
    var name: String
    var createdAt: Date
}

@Model class FeedLogEntry {
    var id: UUID
    var createdAt: Date
    var kind: String                         // "info" oder "error"
    var message: String
    @Relationship var feed: Feed?
}

@Model class Article {
    var id: UUID
    var title: String
    var link: String?
    var summary: String?
    var content: String?                     // Volltext für Offline-Lesen
    var publishedAt: Date?
    var imageURL: String?
    var feedID: UUID?                        // Direkter Query-Key für schnelle Feed-Listen
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool                     // Archivstatus, Default: false
    var isHidden: Bool                       // Aus Listen ausblendbar, Default: false
    var offlineStateRaw: String              // none/feedContent/fullText/failed
    var offlineContent: String?
    var offlineRequestedAt: Date?
    var offlineSavedAt: Date?
    var offlineErrorMessage: String?
    @Relationship var feed: Feed?
    @Relationship var tags: [Tag]
}

@Model class Tag {
    var id: UUID
    var name: String
    var colorHex: String                     // z.B. "#FF5733"
    @Relationship(inverse: \Feed.tags) var feeds: [Feed]
    @Relationship(inverse: \Article.tags) var articles: [Article]
}

@Model class Rule {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var conditionField: String               // Legacy: erste Bedingung
    var conditionOperator: String            // Legacy: erste Bedingung
    var conditionValue: String               // Legacy: erste Bedingung
    var conditionMatchMode: String           // "all" oder "any"
    @Relationship var assignTag: Tag?
    @Relationship(deleteRule: .cascade, inverse: \RuleCondition.rule) var conditions: [RuleCondition]
}

@Model class RuleCondition {
    var id: UUID
    var field: String                        // "title", "summary", "feedTitle"
    var comparisonOperator: String           // "contains", "startsWith", "endsWith"
    var value: String
    var sortOrder: Int
    @Relationship var rule: Rule?
}
```

---

## Architektur-Entscheidungen (ADR)

### ADR-001: SwiftData statt Core Data
- **Entscheidung:** SwiftData
- **Grund:** Moderner, weniger Boilerplate, native CloudKit-Integration via `isCloudKitEnabled`
- **Datum:** 2026-06-19

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

### ADR-006: URL als String in SwiftData speichern
- **Entscheidung:** URLs als `String` speichern, bei Verwendung mit `URL(string:)` konvertieren
- **Grund:** CloudKit unterstützt keinen nativen URL-Typ
- **Datum:** 2026-06-19

### ADR-007: Automatisch gelesen beim Oeffnen, aber konfigurierbar
- **Entscheidung:** Artikel werden standardmäßig beim Oeffnen als gelesen markiert.
- **Benutzerkontrolle:** Einstellung `markArticleReadOnSelection` in `SettingsView`
- **Grund:** Entspricht vielen RSS Readern, bleibt aber Geschmackssache und daher abschaltbar.
- **Datum:** 2026-06-19

### ADR-008: i18n via String Catalog
- **Entscheidung:** App-Texte werden über `Localizable.xcstrings` lokalisiert.
- **Sprachen:** Deutsch, Englisch, Französisch, Italienisch.
- **Sprachauswahl:** Default `Nach System`; Benutzer können in den Einstellungen
  Deutsch, Englisch, Französisch oder Italienisch erzwingen.
- **Grund:** Xcode String Catalog ist der native Weg für moderne SwiftUI/macOS Apps
  und skaliert besser als verstreute harte Strings.
- **Datum:** 2026-06-19

### ADR-009: Auto-Refresh mit NSBackgroundActivityScheduler
- **Entscheidung:** Automatischer Feed-Refresh nutzt auf macOS
  `NSBackgroundActivityScheduler`, nicht `BGTaskScheduler`.
- **Grund:** `BGTaskScheduler`, `BGTask` und `BGAppRefreshTaskRequest` sind im
  macOS SDK für native macOS Apps als unavailable markiert. `NSBackgroundActivityScheduler`
  ist der passende systemfreundliche Mechanismus für periodische Arbeit während die
  App laeuft oder im Hintergrund ist.
- **Einschränkung:** Eine vollständig beendete App wird für diese Basis nicht neu
  gestartet; macOS bestimmt den exakten Ausfuehrungszeitpunkt.
- **Datum:** 2026-06-20

### ADR: Reader-/Listen-Performance — Parsing entkoppeln, Persistenz debouncen, Sidebar-Beobachtung isolieren
- **Kontext:** Beim Wechseln zum nächsten Artikel (nativer Reader) und beim
  Scrollen der Artikelliste ruckelte die App; bei grossem Datenbestand stark.
- **Entscheidung:**
  1. Der Reader parst HTML/Reader-Vorbereitung asynchron in `Task.detached`
     (ausserhalb des MainActors), gestartet über `.task(id:)`. `ReaderView.init`
     hält nur einen leeren Platzhalter (`ReaderPreparedArticle.empty`), kein
     synchrones Parse im Init (früher via `State(initialValue:)` pro Body-Eval
     verworfen mitgelaufen). Geparste Ergebnisse werden pro Artikel gecacht.
  2. `markReadIfNeeded(_:context:)` sichert den Kontext nicht mehr selbst.
     Die Artikelliste persistiert Lese-Markierungen debounced (~0.6s) statt
     pro Auswahl, damit schnelles Navigieren keine @Query-Refetch-Kaskade
     (feeds/articles/Sidebar-allArticles) pro Artikelwechsel auslöst. UI-
     Updates (Zeile, Sidebar-Unread-Badge) kommen über `@Model`-Beobachtung
     der In-Memory-Mutation. Flush auf `.onDisappear` verhindert Datenverlust.
  3. `feed.unreadCount` wird nur in Blatt-Zeilen (`FeedRowView`,
     `SmartFolderSidebarRow`) gelesen, nicht im `SidebarView`-Body. Damit
     triggert ein Als-gelesen-markieren nicht die gesamte Sidebar-Body-
     Neuauswertung inkl. `sidebarBadgeSignature` (O(n) über alle Artikel).
  4. Cache-Key für `makePreparedArticles` enthält nur die zum aktiven Filter
     relevante Status-Zählung (Standard `Alle` → unabhängig vom Lese-Status),
     damit eine Auswahl keinen Cache-Miss und keine synchrone Neu-Sortierung
     im Body auslöst.
  5. `ReaderView` beobachtet für Inhaltsänderungen nur leichte Felder
     (`summary`, Bild-URL und Offline-Status-Metadaten), nicht mehr
     `content`/`offlineContent`. Ordner-/Tag-Beziehungen werden nach dem ersten
     Render nachgeladen. Der Nachbarartikel-Prefetch bleibt leichtgewichtig und
     faultet keine Volltexte/Bilder mehr, damit schnelles Lesen nicht nebenbei
     teure Text- und Bildarbeit auslöst.
  6. Reader-Content wird in `LazyVStack` gerendert. Dadurch materialisiert SwiftUI
     lange Artikel nicht vollständig beim Öffnen, sondern baut nur den sichtbaren
     Bereich plus Puffer.
  7. Schwere Reader-Inhalte werden über `ReaderArticleContentLoader` in einem
     separaten SwiftData-`ModelContext` geladen. Der UI-Pfad behält nur den
     leichten Preview-Snapshot; `ReaderArticleCacheKey` verwendet Text-
     Fingerprints statt Volltext-Strings.
  8. Artikelzeilen bekommen Feednamen aus einem einmal pro Render gebauten
     `feedID -> Feed.title` Lookup. Weder `ArticleRowView` noch der
     Nachbarartikel-Prefetch lesen `article.feed?.title`; dadurch entstehen beim
     schnellen Lesen in `Alle Artikel` keine Feed-Relationship-Faults pro Zeile.
  9. Auto-Lesen aktualisiert `Feed.unreadCount` nicht mehr pro Artikelauswahl.
     `ArticleListView` sammelt betroffene Feed-IDs und synchronisiert die Zähler
     beim debounced Persistenz-Flush per `fetchCount`; damit feuern Feed-Queries,
     Sidebar-Badges und Dock-Badge nicht mehr bei jedem schnellen Artikelwechsel.
  10. Die Sidebar beobachtet keine globale `allArticles`-Query mehr. Ein Sample
      am 2026-07-02 zeigte beim schnellen Lesen hohe CPU in `SidebarView` →
      SwiftData/CoreData-Faulting; deshalb beobachtet die Sidebar nur noch eine
      kleine Status-Query für Stern/Archiv/Hidden und berechnet Tag-Badges
      nachgelagert per `fetchCount`.
  11. `ArticleMetadataInspectorView` bekommt Feedname, Ordnername, Lesezeit und
      Content-Verfügbarkeit von `ReaderView`/`ReaderPreparedArticle`, statt diese
      Werte im Body nochmals über `article.feed`, `Article.content` oder
      `Article.offlineContent` zu berechnen.
- **Konsequenz:** Navigation bleibt auch bei großem Datenbestand flüssig;
  Lese-Status und Feed-Zähler werden verzögert (≤0.6s) persistiert bzw.
  synchronisiert, was für einen RSS-Reader akzeptabel ist und auf `.onDisappear`
  sofort geflusht wird.
- **Datum:** 2026-06-28, ergänzt 2026-07-01 und 2026-07-02

---

## Bekannte Gotchas & Fallstricke

> Diese Liste wächst während der Entwicklung. Immer ergänzen!

- **FeedKit Name Collision:** Das SwiftData-Modell `Feed` kollidiert namentlich mit
  `FeedKit.Feed`. Im Service deshalb explizit `FeedKit.Feed(data:)` verwenden.
- **CloudKit + SwiftData:** Alle `@Model`-Properties müssen `Optional` sein ODER einen
  Default-Wert haben — sonst crasht die CloudKit-Synchronisation
- **CloudKit + SwiftData Relationships:** Syncbare Relationships müssen optional
  sein. Nicht-optionale To-Many-Beziehungen wie `Feed.articles: [Article]`
  verhindern das Laden des CloudKit-Stores (`SwiftDataError 1`, CoreData 134060).
  Im App-Code deshalb immer mit `relationship ?? []` lesen und beim Anhängen eine
  lokale Kopie zurückschreiben.
- **FeedKit Parsing:** FeedKit 10.4.0 kann direkt mit `FeedKit.Feed(data:)` parsen.
  Download bleibt bei uns über `URLSession` + async/await.
- **Artikelbilder in Feeds:** Nicht nur `enclosure` auswerten. Viele Feeds nutzen
  `media:thumbnail`, `media:content`, `itunes:image` oder ein erstes `<img>` in
  Summary/Content. Bild-URLs können relativ sein und müssen gegen die Feed-URL
  normalisiert werden.
- **WordPress-Feeds ohne Item-Bilder:** Manche Feeds, z.B.
  `https://stadt-bremerhaven.de/feed/`, liefern im RSS-Item gar keine Bilder aus.
  Die Bilder stehen nur auf der Artikelseite als `og:image`/`twitter:image`.
  `FeedService.fetchFeed` bleibt deshalb bewusst leichtgewichtig; `FeedViewModel`
  ruft die explizite Artikelbild-Anreicherung nur für neue oder noch bildlose
  bestehende Artikel auf. Das vermeidet zusaetzliche Netzwerkrequests für bereits
  bekannte Artikel mit Bild.
- **Favicons:** Nicht nur `/favicon.ico` ableiten. Zuerst Website-HTML lesen und
  `<link rel="icon">`, `apple-touch-icon`, `shortcut icon` und `mask-icon` auswerten.
  Relative Icon-URLs müssen gegen die Website-URL normalisiert werden. Wenn HTML
  nicht geladen werden kann, ist `/favicon.ico` der Fallback.
- **Performance bei Feed-Wechsel:** Keine komplette `Feed.articles` Relationship für
  Listen oder Sidebar-Zähler laden. Feed-Listen über `Article.feedID` filtern,
  Sidebar-Zähler aus `Feed.unreadCount` lesen und SwiftUI-Renderpfade nicht mit
  neuen ID-Arrays oder neu kompilierten Regexes belasten.
- **NavigationView ist deprecated:** Immer `NavigationSplitView` oder `NavigationStack`
- **WKWebView in SwiftUI:** Braucht einen `NSViewRepresentable`-Wrapper für macOS
- **Background Refresh macOS:** `BGTaskScheduler`/`BGTask` sind für native macOS Apps
  unavailable. Für Feedivo deshalb `NSBackgroundActivityScheduler` verwenden. Dieser
  plant systemfreundlich, garantiert aber keinen exakten Zeitpunkt und startet eine
  vollständig beendete App nicht neu.
- **macOS Menüleiste:** Commands werden mit `.commands { }` an die WindowGroup gehängt,
  nicht an eine View
- **iCloud Capability:** Muss in Xcode Target → Signing & Capabilities
  aktiviert sein, plus CloudKit Container `iCloud.ch.martin.Feedivo` in
  developer.apple.com anlegen. Feedivo nutzt für die erste Beta SwiftData
  `ModelConfiguration` mit CloudKit und liest den Beta-Schalter beim App-Start;
  Umschalten benötigt einen Neustart. Ohne aktualisiertes
  Provisioning-Profil schlagen signierte Builds mit CloudKit-Entitlements fehl.
- **Sandbox Netzwerk:** Feed-Downloads brauchen `com.apple.security.network.client` in
  `Feedivo/Feedivo.entitlements`. Nur ein Build-Setting reicht nicht als Nachweis.
- **Sandbox Dateiexport:** OPML- und Artikel-Export brauchen
  `com.apple.security.files.user-selected.read-write`. `read-only` reicht nur für
  Import/Dateiauswahl und deckt Speichern-Dialoge nicht korrekt ab. In
  `Feedivo.xcodeproj` muss `ENABLE_USER_SELECTED_FILES = readwrite` gesetzt sein,
  sonst generiert Xcode zusätzlich ein widerspruechliches `read-only` Entitlement.
- **SwiftUI Settings auf macOS:** App-weite Einstellungen als eigene `Settings { }`
  Szene in `FeedivoApp.swift` registrieren; Werte können mit `@AppStorage` global
  geteilt werden.
- **Lokalisierung:** Neue sichtbare UI-Texte nicht hart in Views/Services schreiben,
  sondern zuerst als Key in `Localizable.xcstrings` erfassen und bei Bedarf in `L10n.swift`
  zentral bereitstellen.
- **Sprachauswahl:** `AppLanguage.system` muss Default bleiben. Unbekannte gespeicherte
  Werte immer mit `AppLanguage.resolved(from:)` auf `.system` zurückfallen lassen.
- **UI-Tests lokal:** Am 2026-06-19 blockierte `xcodebuild test` für den UI-Test-Runner
  vor dem App-Launch an einer alten Feedivo-PID (`Failed to terminate ch.martin.Feedivo:75492`).
  Build und Unit-Tests waren erfolgreich; UI-Test-Runner bei Bedarf in Xcode/LaunchServices
  separat bereinigen.
- **OPML-Format:** XML-basiert — `XMLParser` (built-in) reicht, kein 3rd-Party nötig

---

## Milestone-Plan

### M1 – Foundation ✅ ABGESCHLOSSEN
- [x] Xcode-Projekt erstellen (macOS App, SwiftUI, Bundle ID: `ch.martin.Feedivo`)
- [x] FeedKit via Swift Package Manager einbinden
- [x] SwiftData Modelle anlegen: `Feed`, `Article`, `Tag`, `Rule`
- [x] `NavigationSplitView` Grundstruktur aufsetzen (3 Spalten)
- [x] `FeedService.swift` — Feed parsen mit FeedKit
- [x] `FeedViewModel.swift` — Feed hinzufügen und in SwiftData speichern
- [x] `SidebarView.swift` — Feed-Liste mit @Query + AddFeedSheet
- [x] Feed-Titel aus RSS-Metadaten lesen (nicht URL als Titel)
- [x] GitHub Repo erstellen und ersten Commit machen
- [x] AGENTS.md ins Repo committen

### M2 – Core Features ✅ ABGESCHLOSSEN
- [x] ArticleListView ausbauen: echte Artikel aus SwiftData anzeigen
- [x] ReaderView ausbauen: nativer Artikel-Renderer für Absätze, Überschriften,
  Zitate, Listenpunkte und Bilder (Basis)
- [x] ArticleRowView: Titel, Datum, gelesen/ungelesen Indikator
- [x] Gelesen/Ungelesen markieren (Basis per Kontextmenü + Auto-gelesen beim Oeffnen)
- [x] Artikel mit Stern markieren (Basis per Button/Kontextmenü)
- [x] i18n Foundation: String Catalog und erste Lokalisierung für de/en/fr/it
- [x] Einstellung für App-Sprache: Nach System, Deutsch, Englisch, Französisch, Italienisch
- [x] Reader-Typografie: Titel-/Fließtext-Schriften, Fließtext-Groesse,
  Titel-/Fließtext-Zeilenabstand und Artikelbreite
- [x] Tastaturkuerzel: `Cmd+Shift+U` gelesen/ungelesen, `Cmd+D` Stern
- [x] macOS Artikel-Menü für gelesen/ungelesen und Stern
- [x] Feed löschen (Rechtsklick und macOS-Menü `Feed`, mit Bestätigung)
- [x] Manueller Refresh für ausgewählten Feed (`Cmd+R`, macOS-Menü `Feed`)
- [x] macOS Menüleiste: `Cmd+N` = Feed hinzufügen
- [x] Manueller Refresh für alle Feeds (`Cmd+Shift+R`, macOS-Menü `Feed`)
- [x] Automatischer Refresh (konfigurierbares Intervall via Settings,
  `NSBackgroundActivityScheduler`)
- [x] Favicons laden und in Sidebar anzeigen
- [x] Smart Filter in Sidebar: Alle Artikel, Ungelesen, Mit Stern, Heute
- [x] Artikel-Link kopieren und Original im Browser öffnen
- [x] Reader-Anzeigemodus: global zwischen nativem Reader und Originalansicht wechseln
- [x] Native Reader Rendering erweitert: Überschriften, Zitate und Listenpunkte
- [x] Navigation Vor/Zurück für Artikel innerhalb der aktuell sichtbaren Liste
- [x] Feed Eigenschaften per Rechtsklick: Metadaten, editierbares Refresh-Intervall
  und Feed-Log mit Feed-Header und Statusmetriken als Basis
- [x] Reader-Metadaten-Inspector: Ordner und Artikel-Tags rechts einblendbar und
  dort bearbeitbar; Feedname, Lesezeit und Zeitpunkt bleiben oben im Artikelkopf

### M3 – Tags, Regeln & Sync ✅ ABGESCHLOSSEN
- [x] Ordner für Feeds als eigenes Organisationsfeature ausbauen (Basis:
  eine Ebene, Sidebar-Section `Ordner` mit + Button, leere Ordner als `FeedFolder`,
  Feed-Zuordnung editierbar in Feed-Eigenschaften)
- [x] Tag-System ausbauen: Tags mit Farben zentral verwalten ist als Basis umgesetzt
- [x] Sidebar: Abschnitt "Tags" zeigt den Tag-Manager
- [x] Sidebar: Tags filtern Artikel feedübergreifend
- [x] Feed-Tags ergaenzen: Zuweisung in Feed-Eigenschaften, Tag-Filter umfasst
  Artikel aus getaggten Feeds
- [x] Tag-Zähler in der Sidebar anzeigen
- [x] Erweiterte/eigene Smart Filter für M3 geprüft und bewusst zurückgestellt:
  bestehende Smart Filter bleiben Alle, Ungelesen, Mit Stern und Heute; eigene Smart
  Filter bleiben im Backlog für später.
- [x] `RuleEngine`: Neue Artikel automatisch taggen basierend auf einfachen Regeln
- [x] Regel-UI: Wizard für einfache/Power-User-Regeln, Einstellungen-Liste,
  Bearbeiten, Löschen und Aktivieren/Deaktivieren
- [x] Regel-Mehrfachbedingungen mit AND/OR für Power-User-Regeln
- [x] Regeln manuell auf vorhandene Artikel anwenden
- [x] Background Refresh erweitert: macOS-native Strategie bestaetigt,
  Statusanzeige für letzten/nächsten automatischen Refresh ergänzt
- [x] Sichtbarer Fortschritt für Sammel-Refresh und OPML-Import
- [x] Offline-Unterstützung: Feed-gelieferten Artikel-Content in SwiftData speichern,
  später gelieferten Content für bestehende Artikel nachtragen und Summary-only
  Artikel im Reader kennzeichnen

### M4 – Polish & Release ← AKTUELL
- [x] OPML Import (Feeds aus anderem RSS Reader übernehmen)
- [x] OPML Export (Feeds portieren)
- [x] OPML-Exportdialog mit Optionen für Ordner, Tags und Feed-Beschreibungen
- [ ] iCloud Sync via CloudKit Beta aktivieren (`iCloud Sync aktivieren`),
  strukturierte Daten aus `Feed`, `FeedFolder`, `Tag`, `Rule`, `SmartFolder` und
  Artikelstatus synchronisieren.
- [x] Erweiterter OPML-Import-Dialog: ausgelesene Feeds und Ordner vor dem Import
  anzeigen, OPML-Datei direkt im selben Dialog auswählen/wechseln,
  Ordnerzugehörigkeit bearbeiten/Ordner erstellen, optionalen Refresh nach Import
  wählen, Duplikate/nicht erreichbare Feeds sichtbar markieren, optionalen
  Duplikat- und Problemfeed-Import erlauben, Statusfilter im Review-Table nutzen
  und Import-Zusammenfassung anzeigen
- [x] Offline Mode Phase 1: Artikel manuell offline speichern/entfernen, Status im
  Reader und in der Artikelliste anzeigen, Feed-Content oder geladene Originalseite
  als `offlineContent` speichern
- [x] Einstellungen-Fenster final diskutiert und übernommen: Struktur, Gewichtung,
  Sync-/Offline-/Cache-Bereiche und macOS-Gefuehl passen für v1
- [x] Vollartikel laden, wenn Feed/Quelle es erlauben: dritter Reader-Modus
  `Vollartikel`, Readability.js via WKWebView, automatischer Start beim Auswählen
  des Modus und temporäre Anzeige im nativen Reader ohne Speicherung im Artikelmodell
- [ ] Theme System/Hell/Dunkel als Settings-Polish
- [x] Mehrfenster-Unterstützung für Artikel: `Cmd+Return` und Kontextmenü öffnen
  einen Artikel in einem eigenen Reader-Fenster mit optionalem rechten
  Artikel-Inspector. Vorheriger/nächster Artikel soll im Artikelfenster
  funktionieren; bereits geöffnete Artikelfenster werden fokussiert statt
  dupliziert. Die Wiederherstellung offener Artikelfenster beim App-Start wird in
  Einstellungen → Allgemein gesteuert und ist standardmäßig ausgeschaltet.
- [x] Bild- und Favicon-Cache: geladene Bilder lokal cachen, damit Artikelbilder
  und Favicons nach App-Neustart nicht jedes Mal neu geladen werden müssen;
  Speicherlimit wird beim App-Start, nach Limit-Änderung und nach neuen Downloads
  automatisch eingehalten
- [x] Artikel-Link teilen via macOS Share Sheet; Export via Share Sheet bleibt
  späterer Export-Slice
- [ ] App-Icon designen
- [x] Onboarding (erster Start ohne Feeds): Wizard mit Feed hinzufügen,
  OPML-Import, gemeinsamem Review/Statusfilter und Start-Defaults
- [x] Lokalisierung abgeschlossen: de/en/fr/it String Catalog vollständig;
  defaultKey-Modell für lokalisierte Default-SmartFolder-Namen, Plural-Varianten
  für Count-Strings und cluster-weise Lokalisierung der verbliebenen Literale
- [x] CloudKit-Vorbereitung (Blocker B2/B3): `.cascade` durch `.nullify` +
  manuelles Cascade ersetzt, explizite inverse-Referenzen ergänzt (Voraussetzung
  für iCloud Sync; Sync selbst bleibt offen)
- [x] OPML-Import-Dedup-Refactor: gemeinsamer `OPMLImportPreviewController` +
  einheitliche Feed-Zeile für Wizard und Settings-Import, testbar abgesichert
- [x] Reader-/Listen-Navigations-Performance: asynchroner Reader-Parse
  ausserhalb des MainActors, geparste Blocks cachen, Lese-Persistenz debouncen,
  Sidebar-`feed.unreadCount`-Beobachtung in Zeilen isolieren, Cache-Key nur
  mit filterrelevanter Status-Zählung
- [ ] Release-Vorbereitung: App Store oder private Verteilung entscheiden,
  Build/Test/QA abschliessen (Build/Tests laut Inventar grün, Xcode-Verifikation
  noch offen)

---

## GitHub

- **Repo:** https://github.com/martinfelder/feedivo-mac
- **Issues:** GitHub Issues mit Milestones M1–M4
- **Labels:** `feature` `bug` `chore` `ui` `networking` `data` `sync` `tags`
- **Branch-Strategie:** `main` = stabil, `feature/[name]` für neue Features

---

## Offene Entscheidungen

- [x] Reader-Modus global oder pro Artikel speichern? Entscheidung für v1: global per
  Einstellung `readerDisplayMode`; später bei Bedarf pro Artikel/Feed prüfen
- [ ] Stern und Archiv getrennt halten oder für v1 nur Stern?
- [x] OPML-Gruppen später als Ordner oder Tags importieren? Entscheidung für v1:
  als `Feed.folderName` speichern; sichtbare Ordnerverwaltung ist als Basis umgesetzt.
- [ ] CloudKit Sync-Umfang, insbesondere Artikel-Content und Offline-Content
- [x] Vollartikel-Laden: Entscheidung 2026-06-30: Readability.js extrahiert den
  Hauptinhalt aus der Originalseite; angezeigt wird das Ergebnis im nativen
  Reader-Layout, temporär und ohne Persistenz.
- [x] Artikel-Detail: Nativer SwiftUI Reader bleibt Standard, Originalansicht per
  `WKWebView` ist als globaler Reader-Modus verfuegbar.
- [ ] Monetarisierung: Kostenlos / einmaliger Kauf / nie im App Store?

---

## Aktuell in Arbeit

- M1, M2 und M3 sind abgeschlossen.
- 2026-06-27/28 abgeschlossen: OPML-Import-Dedup-Refactor (gemeinsamer
  `OPMLImportPreviewController`), Review-Followup-Fixes (7 Tasks) und
  L10n-Abschluss (defaultKey-Modell, Plural-Varianten, Cluster-Lokalisierung,
  Katalog-Lücken). Build und Tests sind laut `docs/superpowers/l10n/inventar.md`
  grün; eine unabhängige Verifikation in Xcode steht noch aus, da die Codex-
  Sandbox die Swift-Toolchain nicht laden kann.
- Aktuell M4: Polish & Release. iCloud Sync Beta ist aktiv in Arbeit.
  Struktur- und Statussync sind Kernumfang der ersten Beta; die Umsetzung wird über
  eine bewusst aktivierbare Beta-Option in den Einstellungen gesteuert und
  greift nach Neustart.
- Feature 17.3 Automatisches Löschen ist umgesetzt: globale Einstellung,
  Stern-/Archiv-Schutz mit Zusatzoption und pro-Feed-Überschreibung in den
  Feed-Eigenschaften.
- Neuer zurückgestellter Roadmap-Punkt 17.3a: Bereinigungs-History, planbare
  automatische Bereinigung nach Wochentag/Uhrzeit oder beim Starten/Beenden der
  App sowie sichtbarer In-App-Hinweis bei ausgeführter Bereinigung.
- Feature 17.1 Automatisches Offline-Speichern bei Stern ist umgesetzt:
  Einstellungen → Offline-Lesen bietet einen standardmäßig deaktivierten Toggle;
  Stern-Aktionen aus Artikelzeile, Inspector und Menü/Shortcut stoßen bei aktivem
  Toggle `OfflineDownloadService.saveForOffline` an. Entsternen löscht die
  Offline-Kopie bewusst nicht automatisch.
- Feature 18.1 Einzelnen Artikel exportieren ist für Markdown, Plain Text und HTML
  umgesetzt: zweistufiger Dialog mit Metadaten-Option, gerenderter Markdown-/HTML-
  Vorschau, monospaced Textvorschau und optionalem ZIP-Paket für Offline-Bilder
  bei Markdown/HTML. Im ZIP liegt die Artikeldatei im Root, Bilder liegen im festen
  Unterordner `Pictures`, und die Bildpfade werden relativ umgeschrieben. Der
  Dialog zeigt Statusmeldungen für Vorbereitung, Bild-Download, Datei-/ZIP-
  Erstellung und Öffnen des Speichern-Dialogs. Im Vorschau-Schritt kann die
  vorbereitete Exportdatei außerdem über `Teilen...` ans macOS Share Sheet
  übergeben werden. PDF, DOCX und Batch-Export bleiben spätere Export-Slices.
- Feature 11.1 Lesedauer pro Artikel ist abgeschlossen: Die Lesezeit bleibt im
  Reader sichtbar und lokalisiert. Eine Anzeige in der Artikelliste wird bewusst
  nicht umgesetzt, weil die Liste kompakt bleiben und bessere Scanning-Signale
  priorisieren soll.
- Feature 11.2 Lesefortschritt ist zurückgestellt: Der erste SwiftUI/AppKit-
  Scrollbeobachter-Ansatz hat das Scrollgefühl im Reader verschlechtert und wurde
  wieder entfernt. Für v1 bleibt der Reader ohne Lesefortschritt.
- Nächster sinnvoller Fokus: Batch-Export, Suche, Start-Refresh oder ein kleiner
  Export-Polish-Slice.
- Feature-Roadmap ist in `FEATURES.md` im Root dokumentiert und muss bei Änderungen
  zusammen mit diesem Projektgedächtnis gepflegt werden

---

## Letzte Änderungen

- 2026-07-02: CPU-Last beim Lesen reduziert. Der Reader-Prefetch in
  `ArticleListView` faultet keine schweren Artikeltexte (`Article.content`,
  `Article.offlineContent`), keine Feed-Relationships und decodiert keine
  Nachbarartikel-Bilder mehr. Artikelzeilen lesen Feednamen nicht mehr über
  `article.feed?.title`, sondern über einen einmal pro Render gebauten
  `feedID -> Feed.title` Lookup.
  Die eigentliche Reader-Vorbereitung bleibt asynchron beim aktuell geöffneten
  Artikel. Zusätzlich rendert `ReaderView` native Reader- und Readability-Inhalte
  per `LazyVStack`, damit lange Artikel nicht komplett als View-Baum aufgebaut
  werden, sobald sie geöffnet werden. Der Volltext-Snapshot wird nun über einen
  eigenen SwiftData-`ModelContext` im Hintergrund geladen; Cache-Keys halten
  Fingerprints statt Volltextkopien, Detailbilder nutzen eine Ziel-Pixelgröße und
  Lesestatus-Zähler vermeiden den direkten `article.feed`-Relationship-Fault.
  Auto-Lesen aktualisiert `Feed.unreadCount` zudem nicht mehr pro Artikelauswahl,
  sondern bündelt betroffene Feed-IDs und synchronisiert die Zähler erst beim
  debounced Persistenz-Flush. Nach einem heißen Prozess-Sample wurde zusätzlich
  die Sidebar von ihrer globalen Artikel-Query entkoppelt: Tag-Badges laufen
  nicht mehr im Body über alle Artikel, Status-Badges beobachten nur noch
  Stern-/Archiv-/Hidden-Artikel. Der rechte Artikel-Inspector nutzt nun die von
  `ReaderView` vorbereiteten Snapshot-Werte für Feed, Ordner, Lesezeit und
  Content-Verfügbarkeit und faultet im Body keine Volltext-/Offline-Textfelder
  mehr. Die Ordnerauswahl im Inspector hält außerdem keine `@Query` auf alle
  Feeds mehr, sondern arbeitet mit einem leichten Namens-Snapshot.

- 2026-07-01: Reader-Artikelwechsel weiter entkoppelt. `ReaderView` beobachtet
  für Reader-Rebuilds keine schweren Textfelder (`Article.content`,
  `Article.offlineContent`) mehr beim SwiftUI-View-Aufbau, lädt Ordner-/Tag-Chips
  nach dem ersten Render und die Artikelliste hält den Reader-Prefetch
  inzwischen leichtgewichtig. Als Nachbesserung zeigt der Reader
  beim Wechsel sofort eine leichte Summary-/Bild-Vorschau statt eines blanken
  Ladezustands.

- 2026-07-01: Artikellisten-Suche leichter gemacht. `ArticleSearchQuery` kann
  schwere Inhalte (`Article.content` und `Article.offlineContent`) aus der
  Textsuche ausnehmen; `ArticleListView` nutzt diesen Modus für die sichtbare
  Suchleiste, damit Tippen in großen Listen keine Volltext-Faults auslöst.
  Globale Suchpfade behalten den vollständigen Suchumfang.

- 2026-07-01: Artikelzeilen-Bilder für große Listen optimiert. `ImageCacheService`
  kann nun größenbegrenzte Thumbnails aus den original gecachten Bilddaten
  erzeugen und hält diese getrennt vom Originalbild-Memory-Cache. `ArticleRowView`
  nutzt diese Thumbnail-API über `CachedRemoteImageView`, damit lange Listen beim
  Scrollen weniger große `NSImage`-Instanzen behalten.

- 2026-07-01: Artikellisten-Paginierung umgesetzt. Feed-, Tag-, Smart-Filter- und
  Smart-Folder-Listen setzen jetzt ein initiales SwiftData-`fetchLimit` von 50
  Artikeln und erhöhen es beim Scrollen ans Listenende in 50er-Schritten. Die
  Descriptoren bleiben dabei auf das leichte Listen-Property-Set beschränkt.

- 2026-07-01: Lesefortschritt wieder entfernt und Feature 11.2 zurückgestellt.
  Der erste Ansatz mit Fortschrittsbalken, gespeicherter Scrollposition und
  Scrollbeobachtung im Reader hat das Scrollgefühl verschlechtert. Entfernt wurden
  `Article.readingProgress`, der Settings-Toggle für automatisches Fortsetzen,
  die Scrollbeobachtung und die zugehörigen Tests/Helper-Dateien.

- 2026-07-01: Reader-Artikelwechsel beschleunigt. `ReaderContentBlock.id` nutzt
  jetzt kompakte, inhaltsbasierte IDs aus Blocktyp, Textlänge und Hash, statt den
  kompletten Absatztext als SwiftUI-ID zu duplizieren. Das reduziert unnötige
  Arbeit beim Wechsel zwischen Artikeln, besonders bei langen Texten.

- 2026-07-01: Reader-Font-Auswahl nach Mac-Neustart gehärtet. `ReaderFontPreset`
  registriert die gebündelten TTF-Dateien jetzt auch beim tatsächlichen
  Font-Erzeugen idempotent und nutzt nur einen aktuell verfügbaren
  PostScript-Namen. Regressionstests prüfen, dass die Font-Dateien im App-Bundle
  liegen, registriert werden und jedes Custom-Preset einen registrierten Namen
  findet.

- 2026-07-01: Datenbank-Ladefehler bei aktivem iCloud Sync behoben.
  Ursache war, dass SwiftData/CloudKit nicht-optionale Relationships
  (`Feed.articles`, `Article.tags`, `Rule.conditions`, `SmartFolder.conditions`,
  `Tag.feeds` usw.) ablehnt. Diese Beziehungen sind jetzt optional und alle
  App-/Test-Zugriffe sind nil-sicher. Ein Regressionstest stellt sicher, dass
  syncbare Relationships optional bleiben.

- 2026-07-01: Sidebar-Ordner optisch stärker an die macOS-Quellenlisten-
  Darstellung angeglichen. Ordnerzeilen zeigen Chevron, blaues Ordner-Symbol und
  einen kompakten Ordnernamen; Feeds innerhalb eines Ordners bleiben eingerückt,
  nutzen aber wieder normale Sidebar-Icongrößen, eine kleinere Feed-Schrift,
  dichtere Zeilenhöhe und einen reduzierten Einzug, damit das Menü nicht zu groß
  wirkt. Der Sidebar-Kopf zeigt keinen App-Namen mehr; die Sidebar-Toolbar zeigt
  direkt rechts neben dem macOS-Sidebar-Schalter einen Refresh-Button und das
  Plus-Menü für Feed und Ordner.

- 2026-07-01: Hauptfenster-Toolbar optisch an die gewünschte transparente
  macOS-Toolbar angepasst. Der Toolbar-Hintergrund nutzt nativ
  `.ultraThinMaterial`, damit Inhalt beim Hochscrollen leicht unscharf unter die
  Toolbar läuft und die Icons lesbar bleiben; eigene Content-Overlays in
  Artikelliste oder Reader werden bewusst vermieden.

- 2026-07-01: Interaktiver Product-Design-Prototyp für eine kompaktere Reader-
  Toolbar unter `docs/design/reader-toolbar-compact-prototype/` in eine zweite
  Designrunde überführt. Die erste Richtung Balance/Kompakt/Fokus wurde verworfen;
  die neue Version zeigt stattdessen die Ansätze Modus-Pill, Zwei Gruppen und
  Command-Bar mit klickbaren Lesemodus-, Inspector- und Offline-Zuständen. Noch
  keine Produktiv-UI-Umsetzung.

- 2026-07-01: iCloud Sync wieder aufgenommen: Entscheidung für Ansatz 1
  (SwiftData + CloudKit) als bewusst aktivierbare Beta. Erster Produktumfang ist
  Struktur- und Statussync; große Offline-Inhalte, Cache-Dateien und Feed-Logs
  bleiben außerhalb des ersten Sync-Versprechens. Der SwiftData-Container wird
  über `FeedivoModelContainerFactory` konfiguriert; Tests für CloudKitDatabase
  prüfen eine eigene `StoreMode`-Repräsentation, weil SwiftDatas
  `CloudKitDatabase` im aktuellen SDK nicht `Equatable` ist.

- 2026-07-02: Reader-Metadaten-Nachlauf reduziert. `ReaderView` startet nun mit
  einem leichten Preview-Snapshot inklusive Feedname und initialisiert Feed-Ordner
  sowie Tags als einfache Snapshot-Werte statt als lebende SwiftData-`Tag`-
  Modelle im Header. Der Hauptfenster-Reader nutzt wie das Artikelfenster eine
  `.id(article.id)`, damit Reader-State beim Artikelwechsel sauber neu startet.

- 2026-07-02: Inline-Tag-Bearbeitung in der Artikelansicht ergänzt. Hinter den
  Ordner-/Tag-Chips sitzt nun ein + Button mit Popover; vorhandene Tags können wie
  im rechten Inspector zugewiesen oder entfernt werden, neue Tags werden mit Name
  und Farbe erstellt und direkt dem Artikel zugewiesen.

- 2026-07-02: Großer Refresh-Performance-Schritt umgesetzt. Sammel-Refreshes aus
  Hauptfenster, Start-Refresh und periodischem Background-Scheduler laufen nun
  über `FeedBackgroundRefreshService` mit eigenem SwiftData-`ModelContext` pro
  Feed. `FeedViewModel` gibt nur leichte Feed-Snapshots hinein und erhält Batch-/
  Feed-Status-Events sowie eine Ergebnis-Summary zurück; der UI-`modelContext`
  wird nicht mehr für die Refresh-Schreibarbeit verwendet.

- 2026-07-01: Refresh-Performance optimiert. `FeedViewModel.refreshFeedContents`
  baut den bestehenden Artikelbestand jetzt per gezieltem `Article.feedID`-Fetch
  statt über `feed.articles` auf; `refreshAllFeeds` speichert Änderungen nur noch
  pro Batch statt pro Feed. Ziel: weniger MainActor-Faulting und weniger SwiftData-
  Query-Invalidierungen, damit die App während Feed-Aktualisierungen bedienbarer
  bleibt. Am 2026-07-02 nachgeschärft: Der Refresh-Lookup lädt bestehende Artikel
  ohne `Article.content`/`Article.offlineContent`, und gespeicherte Artikelwerte
  werden nur noch bei echten Änderungen bzw. fehlenden Nachträgen gesetzt. Außerdem
  werden `refreshItems` beim Batch-Start gesammelt aktualisiert und laufende
  Progress-Änderungen nicht mehr global animiert.

- 2026-07-01: Feature 4.7 Feeds beim App-Start aktualisieren umgesetzt. In
  `Einstellungen → Aktualisierung` gibt es nun die separate Option `Feeds beim
  Start aktualisieren` (Standard aus). Wenn aktiv, startet Feedivo nach dem
  Öffnen des Hauptfensters einmalig einen Sammel-Refresh und nutzt dieselbe
  aufklappbare Fortschrittsanzeige wie manuelle und periodische Sammel-Refreshes.
  `FeedivoApp` teilt dafür ein `FeedViewModel` zwischen Hauptfenster und
  Background-Scheduler.

- 2026-06-30: Feature 4.6 Refresh-Status im unteren Statusbereich umgesetzt.
  Beim Sammel-Refresh erscheint unten rechts neben dem Online-/Offline-Status ein
  kompakter Fortschrittsstatus mit Chevron. Aufgeklappt zeigt Feedivo live jeden
  Feed mit Wartestatus, Spinner, grünem Checkmark oder rotem X. Nach fehlerfreiem
  Abschluss bleibt die Summary 2 Minuten sichtbar; bei Teilfehlern bleibt sie
  stehen, bis der User sie schließt oder der nächste Sammel-Refresh startet.
  Nach User-Feedback bleibt der laufende Status auch bei sehr schnellen Refreshes
  mindestens kurz sichtbar.

- 2026-06-30: Feature 1.8 Vollartikel-Extraktion umgesetzt. Der Reader hat nun
  neben `Nativer Reader` und `Originalansicht` den Modus `Vollartikel`; beim
  Auswählen dieses Modus wird die Originalseite automatisch in einem versteckten
  `WKWebView` geladen, mit gebündeltem Mozilla Readability.js extrahiert und
  temporär im nativen Reader-Layout angezeigt. Der extrahierte Inhalt wird bewusst
  nicht im Artikelmodell gespeichert. Wenn der Anbieter das Laden nicht zulässt,
  zeigt Feedivo einen respektvollen Hinweis statt eines technischen Fehlertexts.

- 2026-06-30: Regelliste in den Einstellungen um Drag & Drop für die Reihenfolge
  erweitert. Die bestehende `sortOrder`-Logik bleibt die Quelle der Wahrheit;
  Hoch-/Runter-Buttons bleiben als präzise Alternative erhalten.

- 2026-06-30: Regex als letzter offener 5.2-Operator umgesetzt. RuleWizard,
  RuleEngine, Live-Vorschau und rückwirkendes Anwenden verwenden nun denselben
  case-insensitive Regex-Pfad; ungültige Patterns werden beim Speichern
  abgelehnt. Bei ausgewähltem Regex-Operator zeigt der RuleWizard oberhalb des
  Eingabefelds `Regex Beispiele` mit den wichtigsten Regex-Regeln.

- 2026-06-30: Einstellungen-Fenster für v1 übernommen. Die neue Toolbar-
  Oberfläche gilt nach Review als ausreichend final; der offene M4-Punkt
  `Einstellungen-Fenster final diskutieren und polishen` ist abgeschlossen.

- 2026-06-29: Mehrfenster-Unterstützung für Artikel umgesetzt. `Cmd+Return` und
  das Artikel-Kontextmenü öffnen den ausgewählten Artikel in einem eigenen
  `ArticleWindowView` über `WindowGroup(for: ArticleWindowRequest.self)`. Das
  Fenster nutzt den bestehenden `ReaderView` mit optionalem rechten
  Artikel-Inspector, unterstützt Vor/Zurück-Navigation, merkt die zuletzt offenen
  Artikelfenster über `ArticleWindowSettings` und bietet unter Einstellungen →
  Allgemein den standardmäßig ausgeschalteten Toggle
  `Artikelfenster beim Start wiederherstellen`.

- 2026-06-29: Mehrfenster-Entscheidung konkretisiert: Feedivo öffnet keine
  zusätzlichen Hauptfenster, sondern dedizierte Artikelfenster mit Reader und
  optionalem rechten Artikel-Inspector. `Cmd+Return` und Kontextmenü öffnen den
  Artikel; Vor/Zurück im Artikelfenster, Duplikat-Fokus und optionale
  Wiederherstellung offener Artikelfenster sind Teil des ersten Slices. Die
  Einstellung `Artikelfenster beim Start wiederherstellen` liegt unter
  Allgemein und ist standardmäßig ausgeschaltet.

- 2026-06-29: Feed-Verwaltung und Feed-Eigenschaften um Aktivitätsinfos erweitert:
  Einstellungen → Feeds zeigt pro Feed Artikel der letzten 7 Tage und letzte
  Aktualisierung; `Feed Eigenschaften...` zeigt dieselben Werte in einer eigenen
  Section `Aktivität`.

- 2026-06-29: Roadmap-Konsistenz bereinigt: iCloud Sync ist nicht mehr M4-offen,
  sondern bewusst nach v1 zurückgestellt. Die CloudKit-Vorbereitung bleibt als
  erledigte technische Vorarbeit dokumentiert.

- 2026-06-29: Produktentscheidung zur Lesedauer dokumentiert: Lesezeit bleibt im
  Reader sichtbar, wird aber nicht in der Artikelliste angezeigt, weil sie dort für
  den User nicht relevant genug ist.

- 2026-06-29: Neue Einstellungen → Allgemein → Cache zeigt jetzt zusätzlich
  `Offline-Artikel` mit Anzahl und Speichergrösse der bewusst offline gespeicherten
  Artikelinhalte. Der Button `Offline-Kopien löschen` entfernt diese lokalen
  Kopien gesammelt, ohne normale Feed-Inhalte oder den Bild-/Favicon-Cache zu
  löschen.

- 2026-06-29: Roadmap um Refresh-Status und Start-Refresh erweitert: Beim
  Aktualisieren aller Feeds soll unten rechts neben dem Online-/Offline-Status ein
  Fortschrittsstatus erscheinen und nach Abschluss die Gesamtzahl neu geladener
  Artikel anzeigen. Zusätzlich ist für Einstellungen → Allgemein eine Option
  `Feeds beim Start aktualisieren` vorgemerkt, getrennt vom periodischen
  Auto-Refresh.

- 2026-06-29: Fehler in Sidebar-Ungelesen-Badges behoben: Wenn bestehende
  ungelesene Artikel durch rückwirkend angewendete Regeln ausgeblendet werden,
  synchronisiert `RuleEngine.applyRulesToExistingArticles` nun die betroffenen
  `Feed.unreadCount` Werte. Der einmalige `FeedUnreadCountBackfillService` wurde
  auf `feedUnreadCountBackfillDone_v3` erhöht, damit bereits falsch gespeicherte
  Zähler beim nächsten App-Start korrigiert werden.

- 2026-06-29: Roadmap für Bereinigung erweitert: Die neue Settings-Toolbar trennt
  Artikel-Aufbewahrung in den eigenen Menüpunkt `Bereinigung` und die bisherige
  Kombirubrik `Tags & Regeln` wird künftig als `Regeln` geführt. Für später ist
  Feature 17.3a vorgemerkt: History der letzten 10 Bereinigungen mit Zeitpunkt
  und Anzahl gelöschter Artikel, automatische Bereinigung nach Wochentag/Uhrzeit
  oder beim Starten/Beenden der App sowie ein sichtbarer In-App-Hinweis, wenn eine
  Bereinigung ausgeführt wurde.

- 2026-06-29: Alte Settings-Fassung entfernt. Die systemeigene SwiftUI-
  `Settings`-Scene öffnet jetzt ausschließlich `NewSettingsView`; das frühere
  Zusatzfenster `Einstellungen alt`, `SettingsCommands` und die alten
  Form-basierten Settings-Views wurden gelöscht, weil alle Inhalte in die neue
  Toolbar-Oberfläche migriert sind.

- 2026-06-28: Settings-Polish als Parallelbetrieb umgesetzt: Im App-Menü gibt es
  vorübergehend `Einstellungen alt` und `Einstellungen neu`. Dieser
  Parallelbetrieb wurde am 2026-06-29 wieder entfernt; die neue Toolbar-Fassung
  (`NewSettingsView`) ist nun die einzige Settings-Oberfläche.

- 2026-06-28: Reader-/Listen-Navigation-Performance (Branch
  `perf/native-reader-navigation`, gemerged nach main). Hebt Trägheit und
  Ruckeln beim Wechseln zum nächsten Artikel (nativer Reader) und beim
  Scrollen der Artikelliste auf:
  - Reader: HTML-Parse aus `ReaderView.init` raus und asynchron in
    `Task.detached` ausserhalb des MainActors; geparste Blocks pro Artikel
    cachen (`ReaderPreparedArticleCache`); `originalURL` direkt aus
    `article.link`, Loading-Placeholder beim ersten Build.
  - Artikelliste: Cache-Key für `makePreparedArticles` nur noch mit der
    filterrelevanten Status-Zählung (Standardfilter `Alle` → kein Cache-Miss
    pro Auswahl → keine synchrone Neu-Sortierung beim Scrollen).
  - Persistenz: `markReadIfNeeded(_:context:)` sichert nicht mehr selbst;
    Artikelliste sichert Lese-Markierungen debounced (~0.6s) statt pro Auswahl,
    Flush auf `.onDisappear`. UI-Updates kommen über `@Model`-Beobachtung der
    In-Memory-Mutation, ohne Save.
  - Sidebar: `feed.unreadCount` wird nur noch in den Blatt-Zeilen gelesen
    (`FeedRowView`, `SmartFolderSidebarRow`), nicht im Sidebar-Body. Ein
    Als-gelesen-markieren wertet damit nur die betroffenen Badge-Zeilen neu
    aus, nicht die gesamte Sidebar inkl. O(n)-Badge-Signatur über alle
    Artikel. Das war der Hauptverursacher des Ruckelns bei grossem Datenbestand.
  - `build/` zur `.gitignore` hinzugefügt.
  Build + Tests grün.

- 2026-06-28: L10n-Abschluss abgeschlossen (16 Commits, Subagent-Driven nach
  Design-Spec). Neues `defaultKey`-Modell + `localizedDisplayName` + Migration für
  die 8 Default-SmartFolder-Namen, damit Standardordner pro Sprache korrekt
  angezeigt werden, ohne den gespeicherten deutschen Namen zu verändern. Plural-
  Varianten für 24 Count-Strings. Cluster-weise Lokalisierung der verbliebenen
  hartcodierten Literale (Sidebar, SmartFolderSettings, SmartFolderEditor,
  RuleSettings, FirstRun, OPMLImportReview, OPMLImportPreviewController). Folge-
  Task: 26 Katalog-Lücken geschlossen, 5 DE-only-Keys übersetzt, 16 leere
  Ghost-Einträge bereinigt. Werkzeugbau: `tools/l10n_inject.py` + TSV-Cluster +
  `docs/superpowers/l10n/inventar.md`. Build und Tests laut Inventar grün.

- 2026-06-28: M12 Lokalisierungslücken geschlossen (SmartFolder/OPML/Rule plus
  Datum-Formatter) als Vorarbeit zum L10n-Abschluss.

- 2026-06-27: Review-Followup-Fixes abgeschlossen (7 TDD-Tasks nach Code-Review
  des OPML-Refactors). Verwaiste Conditions werden bei `updateRule`/`updateFolder`
  gelöscht; OPML-Vorschau-Task ist abbruchbar und sperrt die UI, der Cancel-Guard
  setzt `isPreparingPreview` zurück; `Feed.unreadCount`-Increment ist konsistent
  mit dem `isRead`-Filter; `addFeed` hat einen `!isLoading`-Reentrancy-Guard;
  Vorschau-Zeilen sind parallelisiert mit Phase-2-Progress; typsichere Getter für
  `RuleCondition`/`SmartFolderCondition`; Accessibility/Reset/Sentinel nachgezogen.

- 2026-06-27: M1 OPML-Import-Dedup (Refactor): Der OPML-Preview-Flow wurde aus
  `OPMLImportReviewView` und `FirstRunWizardView` in einen gemeinsamen
  `OPMLImportPreviewController` plus einheitlicher `OPMLImportFeedRow` extrahiert,
  damit Wizard und Settings-Import dieselbe Vorschau-, Auswahl- und
  Ordnerlogik nutzen. Controller-Logik ist über `OPMLImportPreviewControllerTests`
  testbar abgesichert.

- 2026-06-27: M2 Legacy-Regel-Spalten entfernt (eine Source of Truth): Die alten
  einzelnen `conditionField`/`conditionOperator`/`conditionValue` Spalten an
  `Rule` wurden gelöscht; Regeln nutzen ausschließlich die `Rule.conditions`
  Relationship. Der davon überflüssige `RuleConditionBackfillService` wurde
  entfernt.

- 2026-06-27: CloudKit-Blocker B2/B3 als Vorbereitung auf iCloud Sync behoben:
  `.cascade`-Delete-Regeln wurden durch `.nullify` + manuelles Cascade ersetzt
  (CloudKit verträgt keine `.cascade`), und es wurden explizite inverse-Referenzen
  ergänzt. iCloud Sync selbst bleibt bis nach v1 zurückgestellt.


- 2026-06-26: Such-UX nach Nutzerfeedback getrennt: Die Artikelliste zeigt nur
  noch ein einzelnes kompaktes Suchfeld und filtert ausschließlich die aktuell
  geladene Feed-/Tag-/Smartfolder-Liste. Die bisherige große Suchmaske mit
  Suchbereich, Feed, Tag, Zeitraum und Status wurde in ein eigenes
  Artikelsuche-Fenster verschoben, das per `Cmd+F` geöffnet wird und eine eigene
  Ergebnisliste über alle gespeicherten Artikel zeigt.

- 2026-06-26: Feature 18.1a umgesetzt: Einzelartikel können jetzt über
  Kontextmenü, Reader-Toolbar und macOS-Menü `Artikel` exportiert werden. Der neue
  zweistufige Dialog nach Product-Design-Variante B bietet Markdown (`.md`),
  Plain Text (`.txt`) und HTML (`.html`), optional einschließbare Metadaten und
  eine gerenderte Markdown-/HTML-Vorschau vor dem nativen Speichern-Dialog; Plain
  Text bleibt als monospaced Textvorschau sichtbar. `ArticleExportService` arbeitet
  format- und optionsgesteuert, bevorzugt gespeicherten Offline-Content und schützt
  HTML-Metadatenlinks gegen unsichere Linkziele. `ArticleExportDocument` ersetzt
  das frühere Markdown-spezifische FileDocument.

- 2026-06-26: Feature 18.1b umgesetzt: Markdown- und HTML-Export können optional
  Offline-Bilder als ZIP-Paket mitliefern. Die Artikeldatei liegt im ZIP-Root,
  Bilder liegen im festen Unterordner `Pictures`, und alle Bildpfade in
  Markdown/HTML werden relativ auf diesen Unterordner umgeschrieben. Nicht ladbare
  Bilder blockieren den Export nicht; die Vorschau-Zusammenfassung zeigt
  gespeicherte und fehlgeschlagene Bilder. Bugfix: ZIP- und Text-Export laufen
  über einen gemeinsamen `ArticleExportDocument` Datenpfad statt über zwei
  konkurrierende `.fileExporter`; der Dialog zeigt nun Statusmeldungen für
  Dokumentvorbereitung, Bild-Download, ZIP-Erstellung und Speichern-Dialog.
  Bugfix: Die Markdown-/HTML-Vorschau ersetzt relative Paketbildpfade in-memory
  durch `data:`-URLs, damit Offline-Bilder bereits in der Vorschau sichtbar sind.

- 2026-06-26: Feature 18.1c umgesetzt: Der Artikel-Exportdialog unterstützt nun
  zusätzlich PDF (`.pdf`) und Word-Dokument (`.docx`). PDF wird als native
  macOS-PDF-Datei aus dem lesbaren Artikeltext erzeugt, DOCX als minimales
  OpenXML-Dokument für Word/Pages. Beide Formate laufen über denselben
  `ArticleExportPackageBuilder`/`ArticleExportDocument` Datenpfad wie die
  bisherigen Exporte. Im Vorschau-Schritt gibt es nun `Teilen...`, das die
  vorbereitete Exportdatei temporär schreibt und an das macOS Share Sheet
  übergibt.

- 2026-06-26: Bugfix/Polish für PDF-Export: PDF nutzt nun nicht mehr den
  Plain-Text-Fallback, sondern rendert das sichere Artikel-HTML mit den gewählten
  Reader-Schriften, lädt Artikelbilder automatisch und bettet sie direkt ins PDF
  ein. Lange Artikel werden über mehrere PDF-Seiten paginiert, damit nicht nur die
  erste Seite exportiert wird. Die PDF-Vorschau im Exportdialog ist entsprechend
  gerendert und die Zusammenfassung zeigt geladene bzw. fehlgeschlagene Bilder.

- 2026-06-26: Nachbesserung für PDF-Seitenlayout: Der native PDF-Renderer nutzt
  jetzt die geprüfte Kombination aus CoreGraphics-Seitentransformation,
  geflipptem AppKit-Graphics-Context und Top-Y-Koordinaten. Dadurch startet der
  Artikel visuell oben auf der ersten Seite, die Seiten erscheinen in
  Lesereihenfolge und der Text wird nicht gespiegelt. Ein Regressionstest prüft
  Seitenreihenfolge und Top-Position des Titels; zusätzlich wurde der
  Renderpfad isoliert als PNG geprüft.

- 2026-06-26: Nachbesserung für PDF-Exportlayout: Das PDF übernimmt den Reader-
  Kopf jetzt explizit statt nur die generische HTML-Exportstruktur zu stylen.
  Oben stehen Feed-/Lesezeit-/Datum-Metazeile, der Artikeltitel im Reader-Stil
  und bei aktivierter Option ein eigener Metadatenblock für Autor,
  Veröffentlichungsdatum, Feed, Link und Tags. Ein Regressionstest prüft die
  erzeugte PDF-HTML-Struktur inklusive Metadaten.

- 2026-06-26: Produktentscheidung Exportformate: PDF und DOCX werden aus dem
  Artikel-Exportdialog wieder ausgeblendet und als spätere Export-Slices
  zurückgestellt. Der Dialog bietet aktuell nur Markdown, Plain Text und HTML an;
  `ArticleExportFormat.dialogFormats` kapselt diese Freigabeliste und wird per
  Regressionstest abgesichert.

- 2026-06-26: Feature 17.1 umgesetzt: In Einstellungen → Offline-Lesen gibt es
  jetzt den Toggle `Artikel mit Stern automatisch offline speichern`. Wenn aktiv,
  speichern Stern-Aktionen aus Artikelzeile, Inspector und Menü/Shortcut den
  Artikel über `OfflineDownloadService.saveForOffline` offline. Beim Entfernen des
  Sterns bleibt eine vorhandene Offline-Kopie erhalten; Löschen bleibt eine
  explizite Offline-Aktion.

- 2026-06-26: Bugfix für Artikel-Aufbewahrung und Refresh: Abgelaufene Feed-
  Einträge werden bei aktiver globaler oder Feed-eigener Aufbewahrung nicht mehr
  erneut importiert. Damit erscheinen alte, bereits bereinigte Artikel nach dem
  nächsten Feed-Abruf nicht wieder als neue ungelesene Artikel.

- 2026-06-26: Refresh-Deduplizierung für Feeds mit wechselnden Artikel-Links
  korrigiert: Feedivo speichert nun stabile Artikel-Quellen-IDs aus RSS `guid`,
  Atom `id` und JSON-Feed `id`. Der Refresh vergleicht Altbestand über Quellen-ID,
  Link und bei bestehenden Daten ohne Quellen-ID über Titel plus
  Veröffentlichungsdatum. Damit werden bereits gelesene Artikel nicht erneut als
  neue ungelesene Artikel angelegt, wenn ein Feed Tracking-Parameter oder Links
  verändert.

- 2026-06-26: Automatisches Löschen pro Feed fertiggestellt: `Feed` speichert nun
  optionale Aufbewahrungs-Overrides. `Feed Eigenschaften...` bietet dafür direkt
  im Details-Bereich `Globale Einstellung überschreiben`, eigene Aktivierung,
  eigene Tage und die Stern-/Archiv-Mitlöschoption. Der Cleanup-Service wertet pro
  Artikel zuerst den Feed-Override und sonst die globale Einstellung aus; ein Feed
  kann seine Aufbewahrung auch aktivieren, wenn die globale Einstellung aus ist.

- 2026-06-26: Automatisches Löschen erweitert: In den Einstellungen unter
  `Tags & Regeln` gibt es jetzt direkt bei der Artikel-Aufbewahrung eine
  Zusatzoption, um auch Artikel mit Stern und archivierte Artikel in die
  Bereinigung einzubeziehen. Standard bleibt geschützt; ohne die Zusatzoption
  werden Stern- und Archivartikel weiterhin nicht automatisch gelöscht.

- 2026-06-25: Feed-Badge-Zähler nach „Als gelesen markieren“ korrigiert:
  `ArticleViewModel` kann den zugehörigen Feed jetzt über `Article.feedID` aus dem
  SwiftData-Kontext holen, wenn `Article.feed` nicht geladen ist. Die Menü-,
  Toolbar-, Zeilen-, Inspector- und Auto-gelesen-Aktionen nutzen diesen
  context-basierten Pfad und speichern die Änderung sofort. Bulk-Aktionen
  synchronisieren betroffene Feed-Zähler zusätzlich per `fetchCount`, damit auch
  bereits falsch gespeicherte Badges wieder korrigiert werden. Die entsprechende
  Menüoption in der Artikelansicht heißt explizit `Alle als gelesen markieren`.

- 2026-06-25: Performance Paket 5 umgesetzt: Tag-Badges in der Sidebar zählen
  passende Artikel jetzt per SwiftData-`fetchCount` und wiederverwenden den
  Tag-Predicate der Artikelliste. Dadurch traversiert die Sidebar beim Rendern
  nicht mehr die Artikel-Relationships von Tags und getaggten Feeds.

- 2026-06-25: Performance Paket 4 umgesetzt: Artikelwechsel in der Liste
  aktualisieren die Navigation ohne erneutes Sortieren/Filtern,
  `SmartFolderPreparedMatcher` sortiert Conditions komplexer intelligenter Ordner
  nur einmal vor dem Artikel-Loop, und `ReaderContentRenderer` erkennt Bildblöcke
  im Loop ohne zusätzliche Regex-Auswertung.

- 2026-06-25: Performance Paket 3 umgesetzt: `ArticleRowView` erzeugt für die
  Original-Link-Prüfung im Kontextmenü keine neue `ArticleViewModel`-Instanz mehr.
  Die gemeinsame URL-Validierung liegt jetzt in `ArticleOriginalURLResolver`, den
  auch `ArticleViewModel.originalURL(for:)` verwendet.

- 2026-06-25: Performance Paket 2 umgesetzt: `ArticleListContent` nutzt
  `ArticleListPreparedArticles`, damit Sortierung und Filterung aus einem
  vorbereiteten Ergebnis kommen. Dadurch wird pro Render nur einmal sortiert und
  die Navigation arbeitet mit der tatsächlich sichtbaren gefilterten Liste.

- 2026-06-25: Reader-Performance Paket 1 umgesetzt: `ReaderContentRenderer`
  kompiliert seine HTML-/Bild-RegExes nicht mehr pro Artikel neu, sondern nutzt
  gecachte statische `NSRegularExpression` Instanzen. `htmlToPlainText` startet
  keinen `NSAttributedString`/WebKit-HTML-Parser mehr pro Textblock, sondern nutzt
  einen schnellen Tag-Stripper plus HTML-Entity-Decoder für benannte, dezimale und
  hexadezimale Entities.

- 2026-06-25: Performance-Slice für Artikel-Navigation nach großen Imports
  umgesetzt: `ArticleListDisplayState` erzeugt jetzt einen gemeinsamen Snapshot
  für sichtbare Artikel und ausgeblendete gelesene Artikel, `ArticleRowView`
  berechnet mögliche Tag-Zuweisungen erst im Kontextmenü, und einfache
  intelligente Ordner nutzen gezielte SwiftData-Queries statt alle Artikel über
  `SmartFolderEngine` im Speicher zu filtern. Feature 26.2 bleibt weiterhin offen
  für echte Paginierung und weitere Reader-/Bild-Lazy-Loading-Arbeit.

- 2026-06-25: Bugfix für intelligente Ordner: `Ungelesen` verhält sich beim
  automatischen Gelesen-Markieren jetzt wie Feed-Listen und hält den gerade
  geöffneten Artikel sichtbar, bis die Liste gewechselt wird. Außerdem zeigen
  `Mit Stern`, `Ausgeblendet` und `Gespeichert` Sidebar-Badges und Artikellisten
  für alle passenden Artikel, also gelesene und ungelesene Treffer.

- 2026-06-25: Performance-Slice für große OPML-Imports umgesetzt: Das mitgelieferte
  Inoreader-OPML enthält 75 Feed-URLs. `importOPMLFeeds` und `refreshAllFeeds`
  aktualisieren Feeds jetzt in begrenzten Gruppen statt alle Feeds gleichzeitig
  anzustoßen. Außerdem lädt `SidebarView` keine globale Artikelliste mehr nur für
  Smart-Folder-Badges; die `Ungelesen`-Badge nutzt stattdessen die gespeicherten
  `Feed.unreadCount` Werte. Das vollständige Performance-Ziel 26.2 bleibt
  weiterhin offen für Paginierung und weitere Query-Optimierungen.

- 2026-06-25: Feature 12.4 umgesetzt: `FeedDiscoveryService` liefert pro
  gefundenem Feed jetzt eine Vorschau mit Favicon-Fallback und maximal fünf
  Artikeln, nach Veröffentlichungsdatum absteigend sortiert. `AddFeedSheet` zeigt
  nach der Suche im gleichen Sheet eine Feed-Vorschau mit Icon, Titel, Website und
  letzten Artikeln; bei mehreren gefundenen Feeds wechselt die Vorschau mit der
  Auswahl. Die Primäraktion heißt nach erfolgreicher Suche `Abonnieren`.

- 2026-06-25: Feature 4.1 umgesetzt: `FeedDiscoveryService` erkennt direkte
  Feed-URLs und Website-URLs, liest RSS-/Atom-/JSON-Feed-Links aus
  `<link rel="alternate">`, löst relative URLs auf und entfernt Duplikate.
  `AddFeedSheet` bietet nun eine `Suchen`-Aktion, zeigt gefundene Feeds als
  auswählbare Liste und fügt den ausgewählten Feed über den bestehenden
  `FeedViewModel.addFeed` Pfad hinzu. Die Suche läuft bewusst nicht automatisch
  bei jedem Tastendruck, um unnötige Netzwerkabrufe zu vermeiden.

- 2026-06-25: Feature 10.2 umgesetzt: Regeln haben jetzt die dritte Aktion
  `Benachrichtigung auslösen`. Der RuleWizard zeigt dafür eine Textvorlage mit
  `{Titel}`, `{Feed}` und `{Regel}` sowie die Priorität `Normal`/`Kritisch`.
  `RuleEngine.applyRulesWithNotifications` liefert Regel-Treffer zurück, und
  `FeedViewModel.refreshFeed`/`refreshAllFeeds` melden diese Treffer nach dem
  Speichern an `FeedNotificationService`, der einzelne oder gruppierte lokale
  macOS-Benachrichtigungen vorbereitet. Rückwirkendes Anwenden bestehender Regeln
  löst bewusst keine macOS-Benachrichtigungen aus.

- 2026-06-25: Feature 10.1 umgesetzt: Feeds haben `isNotificationEnabled`
  mit Default `false`; `FeedPropertiesView` zeigt den Toggle `Benachrichtigung`.
  `FeedViewModel.refreshFeed` und `refreshAllFeeds` melden neue Artikel nach
  erfolgreichem Speichern an `FeedNotificationService`, der aktive Feeds zu einer
  lokalen macOS-Benachrichtigung zusammenfasst. Die Einstellungen zeigen zusätzlich
  den macOS-Erlaubnisstatus und können die Benachrichtigungs-Erlaubnis anfragen.

- 2026-06-25: Feature 10.3 umgesetzt: Einstellungen haben eine neue Kategorie
  `Benachrichtigungen` mit Toggle `Badge-Zähler am App-Icon anzeigen`. Der Dock-
  Badge zeigt die Summe aus `Feed.unreadCount`, aktualisiert sich beim App-Start,
  bei geänderten Feed-Zählern und beim Umschalten der Einstellung, und wird bei 0
  ungelesenen Artikeln oder deaktivierter Einstellung geleert. Die testbare Logik
  liegt in `AppIconBadgeService`.

- 2026-06-25: Artikellisten-Toolbar um `Als gelesen markieren` erweitert. Die
  Massenaktion wirkt nur auf die aktuell sichtbare Liste des ausgewählten Feeds
  oder intelligenten Ordners und bietet die Optionen `Älter als ein Tag`, `Älter
  als zwei Tage`, `Älter als drei Tage`, `Älter als vier Tage`, `Älter als eine
  Woche`, `Älter als zwei Wochen` und `Alle sichtbaren Artikel`. Die Logik liegt
  in `ArticleMarkReadOption`, die Statusänderung inklusive Feed-Zählerpflege in
  `ArticleViewModel`.

- 2026-06-25: Feature 16.1/16.2 umgesetzt: Intelligente Ordner haben eigene
  SwiftData-Modelle, Default-Ordner (`Alle Artikel`, `Ungelesen`, `Mit Stern`,
  `Heute`, `Ausgeblendet`, `Archiviert`, `Diese Woche`, `Gespeichert`),
  Sidebar-Integration ganz oben, dynamische Artikellisten, Settings-Verwaltung
  und einen Editor mit globaler UND/ODER-Auswahl und Live-Vorschau. Die frühere
  Smart-Filter-Sektion wird dadurch in der Sidebar ersetzt. Gemischte
  Operatoren/Bedingungsgruppen bleiben bewusst außerhalb von v1. Der Prototyp liegt unter
  `docs/design/smart-folders-prototype/index.html`.
  Ergänzung: Intelligente Ordner speichern jetzt Icon und Farbe, Defaults bringen
  passende Werte mit, und die Reihenfolge wird in den Einstellungen per
  Hamburger-Handle und Live-Drag-&-Drop geändert, sodass die ganze Zeile sichtbar
  an die neue Position rutscht.

- 2026-06-24: Darstellungseinstellung für die Sidebar ergänzt: Unter
  `Einstellungen > Darstellung` kann nun gesteuert werden, ob Feeds ohne
  ungelesene Artikel in der Seitenleiste sichtbar bleiben. Die Filterlogik liegt in
  `FeedFolderOrganizer.visibleFeeds`, nutzt `Feed.unreadCount` und ist per Test
  abgesichert.

- 2026-06-24: OPML-Import-Bug behoben: Wenn im First-Run-Wizard ein
  Aktualisierungsintervall wie 15 Minuten gewählt wird, wird dieses Intervall nun
  an `FeedViewModel.importOPMLFeeds` übergeben und beim Anlegen der importierten
  Feeds gespeichert. Der normale OPML-Dialog übernimmt analog das gespeicherte
  globale Intervall.

- 2026-06-24: Feature 16.3 umgesetzt: Regeln haben jetzt `RuleAction` mit
  `Tag zuweisen` und `Artikel ausblenden`. Die RuleEngine setzt je nach Aktion Tags
  oder `Article.isHidden`, rueckwirkendes Anwenden zählt allgemein Regelaktionen,
  normale Artikellisten blenden ausgeblendete Artikel aus, und der neue Smart-Filter
  `Ausgeblendet` zeigt sie gezielt wieder an.

- 2026-06-24: Feature 2.4 abgeschlossen: Das Artikel-Kontextmenü bietet jetzt
  `Exportieren...` als Einstieg in den Artikel-Export. Der Export bevorzugt
  gespeicherten Offline-Content und nutzt eine sichere Konvertierung ohne
  AppKit-HTML-Importer. Die Exportdaten werden vor dem Dateidialog als Snapshot aus
  dem SwiftData-Artikel geloest. Der Dialog laeuft für Artikel über ein kurzlebiges
  Export-Sheet mit SwiftUI `.fileExporter`, nicht mehr direkt aus dem Kontextmenü.
  Das App-Sandbox-Entitlement wurde für Benutzerdateien von `read-only` auf
  `read-write` korrigiert und `ENABLE_USER_SELECTED_FILES` auf `readwrite` gesetzt,
  damit Exporte speichern dürfen. Feature 18.1a erweitert diesen Einstieg jetzt
  auf Markdown, Plain Text und HTML mit Vorschau; Offline-Bilder für Markdown/HTML
  und Datei-Teilen sind inzwischen ebenfalls umgesetzt. PDF und DOCX bleiben
  spätere Export-Slices.
- 2026-06-24: Feature 2.3 abgeschlossen: Artikellisten haben jetzt ein globales
  Filter-Menü in der Toolbar mit Alle, Ungelesen, Mit Stern, Archiviert und Heute.
  Die Auswahl wird per `@AppStorage` gespeichert und `ArticleFilterOption` kapselt
  Labels, Symbole und Filterlogik testbar.
- 2026-06-24: Feature 2.2 abgeschlossen: Artikellisten haben jetzt eine globale
  Sortierung per Toolbar-Menü und Menueleiste `Darstellung > Sortieren nach`.
  Die Auswahl wird per `@AppStorage` gespeichert; `ArticleSortOption` kapselt
  Neueste zuerst, Aelteste zuerst, Feed, Titel A-Z und kurze Lesezeit zuerst.
- 2026-06-24: Feature 22.1 abgeschlossen: Archivieren ist jetzt mit explizitem
  Offline-Content verknuepft, Archiv entfernen löscht nur lokale Offline-Daten
  und setzt `isArchived` zurück, und `isHidden` wird aus normalen Artikellisten
  ausgeblendet. Die Regel-Aktion zum Ausblenden wurde danach mit Feature 16.3
  umgesetzt.
- 2026-06-24: Feature 2.4 als erster Kontextmenü-Slice umgesetzt: Artikelzeilen
  bieten jetzt Archivieren, Tag-Zuweisung, Regel-Erstellung aus Artikel, Teilen,
  Offline speichern/entfernen, Artikel löschen und alle sichtbaren Artikel als
  gelesen markieren. Der spätere Artikel-Exportdialog schliesst den Export-
  Einstieg aus Feature 2.4 ab.
- 2026-06-24: Feature 2.5 umgesetzt: Artikel-Listen zeigen ungelesene Artikel
  standardmäßig weiter und blenden gelesene Artikel aus. Ein Button am Listenende
  zeigt die gelesenen Artikel für die aktuelle Liste an; das Filtermenue bietet
  dieselbe Umschaltung. Automatisch beim Oeffnen gelesene Artikel bleiben bis zum
  Feed-/Listenwechsel sichtbar.
- 2026-06-24: Phase 1 für Archiv-/Aufraeum-Basis umgesetzt:
  `Article` speichert jetzt `isArchived` und `isHidden` mit Default `false`.
  Die Felder sind bewusst nur Modellgrundlage; UI, Filterlogik und Archivkonzept
  folgen in späteren Phasen.
- 2026-06-24: User-Entscheidung erfasst: Die von Claude erstellte
  `FEATURES.md` im Root ist ab jetzt die massgebliche Produkt-Roadmap und
  Implementierungs-Reihenfolge. Die bisherige `docs/FEATURES.md` wurde als
  `docs/archive/FEATURES-legacy-2026-06-24.md` archiviert.
- 2026-06-23: Roadmap/Projektgedaechtnis bereinigt: nicht vorhandene TODO-Dateien
  aus der Projektstruktur entfernt, WebContentView und Settings-Status an den Code
  angepasst, M4-Restpunkte auf CloudKit Sync, Theme-Polish, Artikel-Teilen, App-Icon
  und Release-Vorbereitung geschaerft.
- 2026-06-23: User-Entscheidung nachgezogen: Das Settings-Fenster gilt nicht als
  abgeschlossen. Es wird in M4 nochmals gemeinsam diskutiert und gepolisht, bevor
  Sync- und Release-Arbeiten daran anschliessen.
- 2026-06-23: User-Entscheidung erfasst: Feedivo soll ganze Artikel laden können,
  wenn Feed/Quelle es erlauben. Dabei sollen Grundstruktur, Werbung und Anbieterlinks
  fair erhalten bleiben; offen ist noch, welche geladenen Inhalte der native Reader
  konkret anzeigen soll.
- 2026-06-19: Projekt erstellt, SwiftData Modelle, NavigationSplitView,
  FeedService + FeedViewModel + SidebarView mit AddFeedSheet implementiert
- 2026-06-19: FeedService auf FeedKit 10.4.0 umgesetzt, Feed-Titel aus Metadaten,
  ArticleListView/ReaderView mit echten Daten verbunden, macOS Deployment Target auf 14.0
  korrigiert, Netzwerk-Client-Entitlement aktiviert
- 2026-06-19: Feature-Liste als priorisierte Roadmap in `docs/FEATURES.md`
  dokumentiert; Codex-Arbeitsregeln für Session-Start, Verifikation und
  Gedaechtnis-Pflege in `AGENTS.md` ergänzt
- 2026-06-19: `Feedivo/Feedivo.entitlements` ergänzt, damit Sandbox-Netzwerkzugriff
  für Feed-Downloads explizit als `com.apple.security.network.client` gesetzt ist
- 2026-06-19: ArticleRowView umgesetzt: reichhaltige Artikelzeile mit optionalem Bild,
  Ungelesen-Punkt rechts oben, Stern rechts unten, Kontextmenü für gelesen/ungelesen
  und Stern; Auto-gelesen beim Oeffnen ist per Settings-Option konfigurierbar
- 2026-06-19: FeedService liest Artikelbilder robuster aus Media RSS, iTunes Image,
  Bild-Enclosures und HTML-Content; Parser-Tests für `media:thumbnail` und
  HTML-`img` ergänzt
- 2026-06-19: i18n Foundation umgesetzt: String Catalog `Localizable.xcstrings`,
  `L10n.swift`, UI-/Fehlertexte für Deutsch, Englisch, Französisch und Italienisch;
  Build und Unit-Tests erfolgreich, UI-Test-Runner lokal durch alte Feedivo-PID blockiert
- 2026-06-19: Sprachauswahl in den Einstellungen ergänzt: `Nach System` als Default,
  feste Auswahl für Deutsch, Englisch, Französisch und Italienisch; Locale wird in
  `FeedivoApp` auf Hauptfenster und Settings angewendet
- 2026-06-19: Nativer Reader-Renderer ergänzt: `ReaderContentRenderer` wandelt
  HTML/Plain-Text in Absätze und Bildbloecke; `ReaderView` rendert diese Bloecke
  nativ mit SwiftUI statt rohen HTML-/Content-Text anzuzeigen
- 2026-06-19: Artikelbild-Parsing verbessert: Relative Bild-URLs aus HTML und Media RSS
  werden beim Feed-Import gegen die Feed-URL zu absoluten URLs normalisiert, damit
  Artikelliste und Reader die Bilder via `AsyncImage` laden können
- 2026-06-19: Reader-Metazeile ergänzt: Oberhalb des Titels zeigt die Artikelansicht
  Feedname, ungefaehre Lesezeit und Artikelalter; Lesezeit ist testbar und lokalisiert
- 2026-06-19: Reader-Schrift-Presets ergänzt: Titel- und Fließtext-Schrift können
  direkt im Reader-Popover und in den Einstellungen getrennt gewählt werden
- 2026-06-19: Reader-Typografie erweitert: Schriftliste nach UI-Referenz ergänzt
  sowie Fließtext-Groesse und Fließtext-Zeilenabstand als Slider im
  Reader-Popover und in den Einstellungen umgesetzt
- 2026-06-20: Feed-hinzufuegen-Befehl umgesetzt: macOS-Menü `Feed > Feed hinzufügen...`
  mit `Cmd+N` öffnet dasselbe `AddFeedSheet` wie der Sidebar-Plus-Button
- 2026-06-20: Manueller Refresh für alle Feeds umgesetzt: `Cmd+Shift+R` und
  macOS-Menü `Feed > Alle Feeds aktualisieren`; einzelne Feed-Fehler stoppen den
  Gesamtlauf nicht und werden gesammelt gemeldet
- 2026-06-19: Reader-Font-Aufloesung verbessert: Presets nutzen bekannte
  PostScript-Kandidaten und Picker sind explizit Menues.
- 2026-06-19: Reader-Fonts gebundelt: TTF-Dateien für die kuratierte Fontliste in
  `Feedivo/Resources/Fonts/` aufgenommen und per `ReaderFontRegistry` beim App-Start
  registriert; Font-Herkunft/Lizenzen in `docs/THIRD_PARTY_FONTS.md`
- 2026-06-19: Reader-Titel-Zeilenabstand ergänzt: Titel und Fließtext haben nun
  separate Zeilenabstand-Slider im Reader-Popover und in den Einstellungen
- 2026-06-19: Reader-Artikelbreite ergänzt: Maximale Artikelbreite kann im
  Reader-Popover und in den Einstellungen zwischen 520...980 px eingestellt werden
- 2026-06-20: Artikel-Commands ergänzt: macOS-Menü `Artikel`, `Cmd+Shift+U`
  für gelesen/ungelesen und `Cmd+D` für Stern; Commands nutzen SwiftUI FocusedValues
- 2026-06-20: Feed löschen als Basis umgesetzt: Rechtsklick in der Sidebar und
  macOS-Menü `Feed`, jeweils mit Bestätigungsdialog; `FeedViewModelTests`
  prüfen Löschen und fehlende Auswahl
- 2026-06-20: Manueller Refresh für ausgewählten Feed umgesetzt: `FeedViewModel`
  aktualisiert Metadaten, `lastRefreshed` und neue Artikel ohne Duplikate; macOS-Menü
  `Feed` bietet `Cmd+R` für Feed aktualisieren
- 2026-06-20: Automatischer Refresh als macOS-native Basis umgesetzt:
  `NSBackgroundActivityScheduler` plant periodische Aktualisierungen, Settings bieten
  Ein/Aus und Intervalle 15/30/60/120 Minuten; `BGTaskScheduler` ist für native macOS
  unavailable und wird bewusst nicht verwendet
- 2026-06-20: Favicons in der Sidebar umgesetzt: `FaviconService` erkennt Icons per
  HTML Discovery, priorisiert Icon-Kandidaten, fällt auf `/favicon.ico` zurück und
  `FeedRowView` zeigt gespeicherte Icons mit RSS-Symbol als Fallback
- 2026-06-20: Smart Filter in der Sidebar umgesetzt: Alle Artikel, Ungelesen,
  Mit Stern und Heute nutzen `SidebarSelection` und filtern feedübergreifend über
  alle gespeicherten Artikel
- 2026-06-21: Ungelesen-Zähler in der Sidebar umgesetzt: Feed-Zeilen zeigen rechts
  die Anzahl ungelesener Artikel, der Smart-Filter `Ungelesen` zeigt die
  feedübergreifende Summe und aktualisiert über `Article.isRead` automatisch mit.
- 2026-06-20: App-weite Oberflaechenschriftgroesse ergänzt: Einstellungen bieten
  Klein, Standard, Gross und Sehr groß; `InterfaceTextSize` mappt diese Werte auf
  SwiftUI `DynamicTypeSize` und `FeedivoApp` wendet sie auf Hauptfenster und Settings an
- 2026-06-20: Oberflaechenschriftgroesse korrigiert: `InterfaceTextSize` liefert nun
  eigene Skalierungswerte, die Sidebar, Feed-Zeilen, Artikelzeilen und Settings direkt
  für konkrete Font-/Icon-/Zeilenmasse verwenden; dadurch ist die Einstellung sichtbar
- 2026-06-20: Smart-Filter-Icons farbig gemacht: Alle Artikel blau, Ungelesen tuerkis,
  Mit Stern gelb und Heute gruen; die Farbzuordnung liegt testbar an `SmartFilter`
- 2026-06-20: Reader-Redesign-Prototyp Design 11 in der echten App umgesetzt:
  linke Sidebar ist dunkel, aktive Auswahl ist dezent, bestehende Smart-Filter-Icons
  bleiben erhalten; Liste und Reader bleiben im bisherigen hellen 3-Spalten-Aufbau
- 2026-06-20: Artikel-Link-Aktionen umgesetzt: Link kopieren und Original öffnen
  sind im Artikel-Kontextmenü, Reader-Toolbar und macOS-Menü `Artikel` verfuegbar
- 2026-06-20: Reader-Titel klickbar gemacht: Klick auf den Artikeltitel öffnet
  bei gueltigem Originallink den Artikel im Standardbrowser
- 2026-06-20: Reader-Anzeigemodus umgesetzt: globale Einstellung `readerDisplayMode`
  wechselt zwischen nativem SwiftUI-Reader und Originalansicht per `WKWebView`, mit
  Fallback auf den nativen Reader bei fehlendem Originallink
- 2026-06-20: Native Reader Rendering erweitert: `ReaderContentRenderer` erkennt
  Überschriften, Zitate und Listenpunkte als eigene Bloecke; `ReaderView` rendert sie
  mit nativer SwiftUI-Darstellung und fällt bei kaputten Inhalten auf Absätze zurück
- 2026-06-21: Reader-Bildreihenfolge angepasst: Das Artikelbild erscheint im nativen
  Reader immer als erster Content-Block direkt unter dem Titel. `Article.imageURL`
  gewinnt vor HTML-Bildern; fehlt es, wird das erste HTML-`img` nach vorne gezogen.
- 2026-06-21: Reader-Trenner ergänzt: feiner Querstrich zwischen Lead-Bild und
  erstem Fließtext.
- 2026-06-21: Ordner und Artikel-Tags wieder direkt im Reader unter dem Titel
  sichtbar gemacht; Bearbeitung bleibt im rechten Artikelinfos-Inspector.
- 2026-06-21: Reader-Metadaten optisch an die App angepasst: Feedname/Lesezeit/Alter
  und Ordner-/Tag-Chips nutzen die App-Oberflaechenschrift statt der Reader-
  Schriftwahl.
- 2026-06-20: Navigation Vor/Zurück für Artikel umgesetzt: Reader-Toolbar und
  macOS-Menü `Artikel` navigieren mit `Cmd+↑`/`Cmd+↓` innerhalb der aktuell
  sichtbaren Feed- oder Smart-Filter-Liste und stoppen am Listenrand
- 2026-06-20: Feed Eigenschaften umgesetzt: Rechtsklick auf Feed öffnet ein
  lokalisiertes Sheet mit Feed-Metadaten, editierbarem Aktualisierungsintervall,
  naechstem Abruf, letztem Artikel und den neuesten 20 Feed-Log-Eintraegen; Feed-Adds
  und Refresh-Erfolge/-Fehler werden in SwiftData protokolliert
- 2026-06-20: Feed umbenennen umgesetzt: Rechtsklick auf Feed öffnet ein eigenes
  Sheet für den Anzeigenamen; der urspruengliche Feed-Name wird in `Feed.originalTitle`
  gespeichert und kann wiederhergestellt werden, Refresh überschreibt manuelle Namen nicht
- 2026-06-20: Feed-Eigenschaften-Sheet ergänzt: Neben der XML-Adresse gibt es einen
  Icon-Button, der die XML-Adresse in die macOS-Zwischenablage kopiert
- 2026-06-21: Feed-Eigenschaften-Sheet ergänzt: Website- und XML-Adresse werden bei
  gültigen `http`/`https`-URLs als anklickbare Links im Standardbrowser geöffnet
- 2026-06-20: Feed-Eigenschaften-Sheet visuell überarbeitet: großer Feed-Header
  mit Icon/Favicon-Fallback und Statusmetriken, gruppierte Detailansicht,
  abgesetzter Aktualisierungsblock und kompakter Feed-Log-Verlauf
- 2026-06-20: Artikelbild-Fallback für Feeds ohne Item-Bilder umgesetzt:
  Feedivo kann bei fehlendem Bild die Artikelseite lesen und `og:image`/
  `twitter:image` übernehmen; Refresh füllt fehlende `Article.imageURL` Werte bei
  bereits gespeicherten Artikeln nach
- 2026-06-21: P1-Performance umgesetzt: `FeedService.fetchFeed` laedt keine
  Artikelseiten mehr automatisch; `FeedViewModel` reichert Seitenbilder nur noch für
  neue oder bildlose bestehende Artikel an. Smart-Filter nutzen gezielte SwiftData-
  Queries; Sidebar-Ungelesen-Badges wurden später auf gespeicherte `Feed.unreadCount`
  Werte umgestellt.
- 2026-06-21: P2-Performance umgesetzt: Feed-Artikellisten nutzen eine gezielte
  SwiftData-Query pro Feed statt `feed.articles`, und die gemeinsame Artikelsortierung
  liegt in `ArticleListQuery`.
- 2026-06-20: Paket B einfache Ordnerverwaltung umgesetzt: Sidebar gruppiert Feeds
  nach `Feed.folderName`, Ordnernamen sind in den Feed-Eigenschaften editierbar und
  `FeedFolderOrganizerTests` sichern Trimmen, Sortierung und leere Ordnernamen ab
- 2026-06-20: Ordnerverwaltung verfeinert: Feeds stehen jetzt in der Sidebar-Section
  `Ordner`, der Section-Titel hat einen + Button zum Erstellen neuer Ordner und
  `FeedFolder` speichert angelegte/leere Ordner persistent.
- 2026-06-20: Ordner- und OPML-Import-Verhalten nachgezogen: Feeds innerhalb eines
  Ordners werden in der Sidebar eingerückt, und neu importierte OPML-Feeds werden
  direkt nach dem Import über den normalen Refresh-Kern aktualisiert.
- 2026-06-20: Sidebar-Ordner aufklappbar gemacht: Ordnerzeilen haben einen Chevron,
  bleiben standardmäßig geöffnet und klappen ihre eingerückten Feeds per Klick
  ein oder aus.
- 2026-06-20: Interaktive Artikel-Reader-Prototypen erstellt:
  `docs/design/article-reader-prototypes/index.html` zeigt zehn moegliche
  Reader-Darstellungen für die spätere Überarbeitung der Artikelansicht.
- 2026-06-21: Reduzierte Step-by-Step-Reader-Prototypen ergänzt:
  `docs/design/article-reader-minimal-step/index.html` fokussiert auf drei ruhige
  Varianten für die Positionierung von Feedname, Lesezeit, Ordner und Tags:
  Meta oben, Meta nach Titel und Meta kompakt.
- 2026-06-21: Minimal-Reader-Prototyp verfeinert: Ordner und Tags wurden aus dem
  Artikelkopf entfernt und liegen jetzt in einem einblendbaren rechten Inspector,
  in dem Ordner und Tags bearbeitet werden können.
- 2026-06-21: Reader-Metadaten-Inspector in der App umgesetzt: Feedname, Lesezeit
  und Zeitpunkt bleiben oben im Artikelkopf; Ordner und Artikel-Tags werden rechts
  eingeblendet und können dort bearbeitet werden.
- 2026-06-21: Reader-Darstellung ruhiger gesetzt: kleinerer semibold Titel,
  größere redaktionelle Abstaende, kontrolliertes Lead-Bild, dezenter Original-Link
  im Footer und `Link kopieren` ins Reader-Mehr-Menü verschoben.
- 2026-06-25: Reader-Typografie erweitert: Titel und Artikeltext haben getrennte
  Bold-Schalter in Reader-Popover und Darstellungseinstellungen. Die Werte werden
  über `readerTitleFontIsBold` und `readerBodyFontIsBold` gespeichert.
- 2026-06-21: Reader-Performance verbessert: Teure Reader-Daten werden pro Artikel
  über `ReaderPreparedArticle` vorbereitet und grosse Bilder wieder mit leichterem
  `scaledToFit` statt Zuschnitt gerendert.
- 2026-06-21: Artikel-/Reader-Performance nachgezogen: `ContentView` beobachtet
  nicht mehr pauschal alle Artikel; Feed-Listen vermeiden globale Artikel-Queries
  und die Reader-Navigation nutzt `ArticleNavigationState` mit der bereits sortierten
  sichtbaren Artikelliste.
- 2026-06-21: Feed-Wechsel-Performance verbessert: `Article.feedID` ersetzt das
  Relationship-Predicate für Feed-Listen, `ContentView` speichert nur noch
  vorherigen/nächsten Artikel statt der sichtbaren Artikelliste, und Sidebar-Badges
  lesen `Feed.unreadCount` statt alle ungelesenen Artikel zu materialisieren. Alte
  Datensaetze werden beim App-Start per Backfill nachgezogen.
- 2026-06-21: Weitere Performance-Optimierungen nachgefuehrt: Feed-/Favicon-Regexes
  werden statisch gecacht, `refreshAllFeeds` und der OPML-Nachimport aktualisieren
  Feeds parallel per `withTaskGroup`, `ArticleListView` nutzt `.onChange(of: articles)`
  statt eines pro Render neu erzeugten ID-Arrays, und `FeedUnreadCountBackfillService`
  laeuft per UserDefaults-Flag `feedUnreadCountBackfillDone_v1` nur einmal.
- 2026-06-21: Reader-Inspector-Layout korrigiert: Bei geöffnetem Artikelinfos-Panel
  füllt der Reader-Bereich die verbleibende Detailbreite, damit rechts neben dem
  Inspector keine leere weisse Restflaeche bleibt.
- 2026-06-21: M2 offiziell abgeschlossen und aktiven Milestone auf M3 Tags, Regeln
  und Sync umgestellt; nächster Fokus ist Tag-Verwaltung, Tag-Sidebar und danach
  automatische Regeln.
- 2026-06-21: Tag-Manager in der Sidebar verdrahtet: Die neue Section `Tags` öffnet
  das zentrale Tag-Verwaltungs-Sheet; die eigentliche Tag-Filterung wurde danach als
  eigener M3-Schritt umgesetzt.
- 2026-06-21: Sidebar-Tag-Filter umgesetzt: Tags erscheinen als klickbare Zeilen mit
  Farbindikator und filtern `ArticleListView` über eine gezielte SwiftData-Query auf
  `Article.tags`; Feed-Tags und Regeln wurden danach als separate M3-Schritte
  umgesetzt.
- 2026-06-21: Tag-Erstellung verfeinert: Neue Tags werden nach dem Anlegen direkt in
  der Sidebar als aktueller Tag-Filter ausgewählt, damit sie sofort sichtbar und
  schnell nutzbar sind.
- 2026-06-21: Sidebar-Tag-Zähler umgesetzt: Tags zeigen rechts eine dezente Badge
  mit der Anzahl passender Artikel.
- 2026-06-21: Feed-Tags umgesetzt: Tags können in den Feed-Eigenschaften an Feeds
  gehaengt werden; Sidebar-Tag-Filter und Tag-Badges beruecksichtigen direkt
  getaggte Artikel sowie Artikel aus getaggten Feeds ohne Duplikate.
- 2026-06-21: Rechter Artikelinfos-Inspector erweitert: Vorhandene globale Tags, die
  dem Artikel noch nicht zugewiesen sind, erscheinen nun als Plus-Chips und können
  direkt angeklickt werden.
- 2026-06-21: Erste RuleEngine-Basis umgesetzt: Neue Artikel werden beim Refresh
  anhand einfacher Regeln (`title`/`summary`/`feedTitle` plus `contains`/
  `startsWith`/`endsWith`) automatisch getaggt. Regel-UI, Regex und
  Mehrfachbedingungen wurden später in M3/M4 ergänzt.
- 2026-06-21: Rueckwirkendes Anwenden von Regeln umgesetzt: In den Einstellungen
  können aktive Regeln manuell auf vorhandene Artikel angewendet werden; bereits
  gesetzte Tags werden nicht dupliziert.
- 2026-06-21: Background Refresh M3 erweitert: Feedivo bleibt bei
  `NSBackgroundActivityScheduler`, speichert letzten automatischen Lauf, Status,
  optionale Fehlermeldung und nächsten geschaetzten Lauf und zeigt diese Werte in
  den Einstellungen.
- 2026-06-21: Sichtbaren Fortschritt für Sammel-Refresh und OPML-Import umgesetzt:
  `FeedViewModel.operationProgress` zählt abgeschlossene Feeds und `ContentView`
  zeigt während laengerer Feed-Operationen ein kompaktes Fortschritts-Overlay.
- 2026-06-21: Regel-Wizard und Regelverwaltung umgesetzt: Regeln werden in den
  Einstellungen gelistet, können dort erstellt, bearbeitet, gelöscht und
  aktiviert/deaktiviert werden. Der Wizard bietet einfache Regeln oder
  Power-User-Regeln mit mehreren Bedingungen und AND/OR. Die frühere
  Sidebar-Section für Regeln wurde am 2026-06-25 entfernt; `Regel erstellen...`
  für den aktuell geöffneten Artikel liegt jetzt im Menü der Artikelansicht.
- 2026-06-21: Regel-Wizard um Live-Preview erweitert: Feedivo zählt vorhandene
  Artikel, die zu den aktuellen Bedingungen passen würden, und verwendet dafür
  dieselbe Matching-Logik wie die echte RuleEngine ohne Tags zu setzen.
- 2026-06-21: Glass-Design-Prototypen für den rechten Artikelinfos-Inspector
  erstellt: `docs/design/article-info-glass-sidebar-prototypes/index.html` zeigt
  fuenf konkrete Varianten, wie die Seitenleiste an eine moderne macOS-Glass-
  Oberflaeche angepasst werden kann.
- 2026-06-21: Glass-Prototyp Variante A wurde kurzzeitig für den rechten
  Artikelinfos-Inspector umgesetzt und später durch die native macOS-Inspector-
  Spalte im hellen Sidebar-Stil ersetzt.
- 2026-06-21: Native Reader-Scrollbar ausgeblendet, damit der Artikelbereich
  fließender in die rechte Inspector-Leiste übergeht.
- 2026-06-21: Linke Sidebar wieder auf einen hellen, systemnahen macOS-Look
  umgestellt; die dunkle Design-11-Flaeche wurde entfernt, farbige Smart-Filter-
  Icons und dezente Auswahl bleiben erhalten.
- 2026-06-21: Rechten Artikelinfos-Inspector auf SwiftUIs native `.inspector`-
  Seitenleiste umgestellt und visuell an die helle linke Sidebar angepasst; beim
  Einblenden rueckt der Reader inklusive Toolbar nach links.
- 2026-06-21: Linke Sidebar-Sections einklappbar gemacht: `Filter`, `Tags`,
  `Regeln` und `Ordner` nutzen einen gemeinsamen Chevron-Header und merken ihren
  offenen/geschlossenen Zustand per `@AppStorage`.
- 2026-06-21: Fuenf interaktive Settings-Struktur-Prototypen erstellt:
  `docs/design/settings-structure-prototypes/index.html` vergleicht klassische
  Settings-Sidebar, Toolbar-Tabs, Icon-Rail, suchzentrierte Einstellungen und
  setup-orientierte Kategorien.
- 2026-06-21: Settings-Struktur Variante A umgesetzt: Das macOS-Settings-Fenster
  hat nun eine linke Kategorienavigation mit Allgemein, Darstellung, Feeds,
  Aktualisierung, Tags & Regeln und Sync. Der neue Bereich `Feeds` bietet Suche,
  Mehrfachauswahl und Löschen ausgewählter Feeds mit Bestätigungsdialog.
- 2026-06-22: Settings-Feedverwaltung korrigiert: Das macOS-Settings-Scene bekommt
  nun denselben SwiftData-`modelContainer` wie das Hauptfenster, damit abonnierte
  Feeds in den Einstellungen per `@Query` sichtbar sind.
- 2026-06-22: Bild- und Favicon-Caching als M4-Thema aufgenommen. Empfehlung:
  eigener Disk-Cache plus kleiner Memory-Cache für Artikelbilder und Favicons,
  keine Bild-BLOBs in SwiftData.
- 2026-06-22: Erweiterter OPML-Import-Dialog als M4-Thema aufgenommen: Import soll
  Feeds/Ordner vorab zeigen, Ordnerzuweisung und neue Ordner erlauben, optionalen
  Feed-Refresh anbieten und nach dem Import eine Zusammenfassung anzeigen.
- 2026-06-22: M3-Offline-Basis umgesetzt: Feedivo speichert Feed-gelieferten
  Artikel-Content weiter in SwiftData und traegt später gelieferten Volltext für
  bestehende Artikel nach.
- 2026-06-22: iCloud Sync bewusst von M3 nach M4 verschoben. M3 gilt damit als
  abgeschlossen; M4 ist nun der aktive Milestone für Polish, Sync und Release-
  Vorbereitung.
- 2026-06-22: Letzten offenen M3-Restpunkt abgeschlossen: Erweiterte/eigene Smart
  Filter wurden für M3 geprüft und bewusst auf später verschoben. M3 bleibt damit
  vollständig abgeschlossen.
- 2026-06-22: Fuenf interaktive Prototypen für den erweiterten OPML-Import-Dialog
  erstellt: `docs/design/opml-import-dialog-prototypes/index.html` zeigt Review
  Table, Guided Wizard, Split Inspector, Batch Editor und Import Center.
- 2026-06-22: OPML-Import-Prototyp Variante A erweitert: Die Datei-Auswahl ist nun
  Teil desselben Dialogs; danach folgen Preview, Ordnerbearbeitung, optionale
  Aktualisierung und Zusammenfassung in einem durchgehenden Sheet.
- 2026-06-22: OPML-Import-Prototyp Variante A interaktiv gemacht: Ausgewählte
  OPML-Dateien werden lokal gelesen, Feed-Outlines dynamisch in der Review-Tabelle
  angezeigt, Duplikate und nicht erreichbare/problematische Feeds markiert und nur
  ausgewählte importierbare Feeds in der Zusammenfassung gezählt.
- 2026-06-22: OPML-Import-Prototyp Variante A für grosse Imports verfeinert:
  Die Feed-Tabelle scrollt intern, damit das Dialogfenster nicht mitwaechst; lange
  Feednamen und URLs werden einzeilig mit Ellipsis gekuerzt.
- 2026-06-22: OPML-Import-Prototyp Variante A um Option `Duplikate importieren`
  erweitert. Standardmaessig bleiben Duplikate übersprungen; aktiviert der
  Benutzer die Option, werden ausgewählte Duplikat-Zeilen in der Import-Anzahl und
  Zusammenfassung mitgezaehlt.
- 2026-06-22: Erweiterter OPML-Import-Dialog in der App umgesetzt:
  `OPMLImportReviewView` ersetzt den direkten Dateiimport durch Datei-Auswahl im
  Dialog, dynamische Feed-Prüfung, Auswahl einzelner Feeds, Ordnerzuordnung,
  Ordneranlage, optionalen Refresh, optionalen Duplikat- und Problemfeed-Import
  und sichtbare Import-Zusammenfassung.
- 2026-06-22: `OPMLImportReviewView` visuell naeher an Prototyp Variante A
  nachgezogen: macOS-Sheet-Container, ruhiger Header mit Status-Badge, Datei-Kachel,
  Toolbar im Review-Table-Stil, feste Tabellenspalten, kompakte Status-Pills und
  Footer-Optionen im gleichen Layout wie der HTML-Prototyp.
- 2026-06-22: Statusfilter im OPML-Import-Dialog ergänzt: Dropdown für alle, neue,
  doppelte und nicht erreichbare Feeds; der Filter arbeitet nur auf sichtbaren IDs,
  damit Auswahl- und Ordner-Mutationen beim Entfernen des Filters erhalten bleiben.
- 2026-06-22: OPML-Import-Preview mit konkretem Prueffortschritt verbessert:
  `FeedViewModel.opmlImportPreviewRows` kann Fortschritt pro Feed melden, und
  `OPMLImportReviewView` zeigt diesen Zustand horizontal und vertikal zentriert in
  der späteren Feed-Tabelle.
- 2026-06-22: OPML-Import-Dialog erweitert: Nicht erreichbare Feeds bleiben
  standardmäßig abgewählt, können aber über eine eigene Checkbox bewusst
  ausgewählt und importiert werden.
- 2026-06-22: OPML-Import-Dialog um Drag & Drop erweitert: `.opml`- und `.xml`-
  Dateien können direkt auf das Importfenster gezogen werden und starten dieselbe
  Preview wie die manuelle Datei-Auswahl.
- 2026-06-23: First-Run-Wizard nach Prototyp Variante A umgesetzt: Bei leerem
  Feedbestand zeigt Feedivo einen Wizard mit Auswahl zwischen einzelner Feed-URL,
  OPML-Import oder späterem Einrichten. Feed- und OPML-Pfad nutzen denselben
  Review-Flow wie der erweiterte OPML-Import inklusive Statusfilter, Ordnern,
  Duplikat-/Problemfeed-Optionen, optionalem Refresh und Start-Defaults.
- 2026-06-23: First-Run-Wizard-Abschlussflow verfeinert: Die Feed-Liste bleibt im
  Import-/Pruefschritt, die Review zeigt nur eine Zusammenfassung mit Link zurück,
  und der Fertig-Screen bleibt nach dem Import sichtbar, bis der Benutzer aktiv
  `Starten` drueckt. Importierte Feeds, verwendete Ordner und Hinweise zu
  Duplikaten, nicht erreichbaren Feeds oder Refresh-/Speicherproblemen werden dort
  angezeigt.
- 2026-06-23: First-Run-Wizard-Schliesslogik korrigiert: Ein sichtbarer Wizard wird
  nicht mehr automatisch geschlossen, wenn nach `Import starten` Feeds angelegt
  werden und `firstRunWizard.completed` aus einem frueheren Lauf bereits true ist.
- 2026-06-23: First-Run-Wizard-Copy geschaerft: Sichtbare Texte erklaeren nun
  direkt, was der Benutzer einstellt, sieht und mit dem nächsten Schritt ausloest.
  Prototyp-/Implementierungsbegriffe wie `Review`, `Defaults` und `Import-Engine`
  wurden aus der UI entfernt.
- 2026-06-23: Offline-Begriffe geschaerft: Cache, normal gespeicherter Feed-Inhalt
  und bewusste Offline-Kopien sind nun in UI und Settings getrennt. Die neue
  Settings-Rubrik `Offline-Lesen` erklaert den manuellen Artikel-Flow und hält
  Offline-Automatik als späteren M4-Folgepunkt sichtbar zurück.
- 2026-06-23: Reader-Summary-Hinweis entfernt: Artikel ohne Feed-Volltext zeigen
  die vorhandene Feed-Zusammenfassung direkt ohne zusaetzliche Hinweisbox. Der
  interne Reader-Zustand heisst `contentAvailability`, damit normaler Feed-Inhalt
  und bewusste Offline-Kopien getrennt bleiben.
- 2026-06-23: Fensterweiter Online-/Offline-Indikator ergänzt: `ContentView`
  beobachtet den Netzwerkpfad per `NWPathMonitor` und zeigt unten rechts Online
  oder Offline an. Der Status beschreibt nur die aktuelle Netzwerkverbindung, nicht
  den Artikel-Offline-Speicher.
- 2026-06-23: Rechten Artikelinfos-Inspector zunaechst nach Product-Design-
  Variante 3 `Editorial Companion` umgebaut; später am selben Tag wurde die
  interaktive Variante 1 `Calm Actions` als aktuelle SwiftUI-Richtung umgesetzt.
  Die Anzeigeaufbereitung liegt weiter in `ArticleInspectorFormatter`.
- 2026-06-23: Typografie der rechten Artikelinfos-Seitenleiste verkleinert und in
  `ArticleInspectorTypography` zentralisiert, damit die Sidebar weniger dominant
  wirkt und besser zum ruhigen Reader passt. Die Skala ist nun auf 11 pt
  Labels/Chips, 11.5 pt Controls, 12 pt Werte, 13 pt Section-Titel und 15 pt
  Artikelkopf vereinheitlicht.
- 2026-06-23: Drei neue interaktive Product-Design-Prototypen für eine ruhigere
  und bedienbarere rechte Artikelinfos-Seitenleiste erstellt:
  `docs/design/article-info-interactive-sidebar-prototypes/` enthaelt die Varianten
  `Calm Actions`, `Section Studio` und `Command Inspector` mit klickbarem Status,
  Favorit, Offline, Tags, Ordner, Link-Kopieren sowie Tag-Erstellung mit
  Farbauswahl. Die Ordnerauswahl wurde im Prototyp als `Feed-Ordner` gekennzeichnet,
  damit klar ist, dass sie den Feed und nicht nur den Artikel betrifft; außerdem
  können neue Feed-Ordner direkt aus dem Inspector-Prototyp angelegt werden.
  Feed-Ordner und Tags wurden als eigene Sections getrennt, damit Feed-Eigenschaften
  und Artikel-Tags nicht vermischt werden.
- 2026-06-23: Prototyp-Variante 1 `Calm Actions` in der echten SwiftUI-
  Inspector-Seitenleiste nachgeschaerft: kompakter Kopf mit Titel und Status-Strip,
  obere Aktionsleiste für Favorit, Gelesen/Ungelesen, Offline und Link-Kopieren,
  einklappbare weisse Karten-Sections für Feed-Ordner, Tags, Kontext und Quelle.
  Die Quelle ist als reine Zwei-Button-Section für Link-Kopieren und
  Original-Oeffnen ohne URL-Textbox umgesetzt.
  Die Section-Header nutzen wie der Prototyp nur Chevron und Titel; Tags
  sind eine gemeinsame Toggle-Pill-Liste statt getrennten aktuellen/verfuegbaren
  Chips. Neue Feed-Ordner können direkt angelegt werden, neue Tags können beim
  Anlegen eine Farbe bekommen.
- 2026-06-23: Cache Mode vervollstaendigt: `ImageCacheService` raeumt nach
  erfolgreichen Bilddownloads automatisch auf das eingestellte Speicherlimit auf;
  `FeedivoApp` wendet dasselbe Limit beim App-Start an. Cache bleibt bewusst ein
  Performance-Cache, echte automatische Offline-Pakete bleiben ein separater
  M4-Folgepunkt.
- 2026-06-22: Offline Mode Phase 1 umgesetzt: Artikel können im Reader manuell
  offline gespeichert oder wieder entfernt werden. Vorhandener Feed-Volltext kann
  dafür als manuelle Offline-Kopie genutzt werden; falls kein Feed-Content
  vorhanden ist, wird die Original-URL geladen und in `Article.offlineContent`
  gespeichert. Reader und Artikelliste zeigen Offline-Status beziehungsweise Fehler
  sichtbar an.
