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
- Sprache für Kommentare im Code: Deutsch
- IDE: Xcode 26
- Versionskontrolle: Git + GitHub
- Workflow: Codex CLI + Codex.ai (dieses File als Kontext)

> **Für Codex:** Erkläre Entscheidungen immer kurz. Kein "magic code" ohne Erklärung.
> Kommentare im Code auf Deutsch. Lieber ein bisschen mehr erklären als zu wenig.

---

## Codex-Arbeitsregeln und Projektgedächtnis

> **Wichtig:** Diese Regeln gelten fuer jede neue Codex-/Codex.ai-Session. Ziel ist,
> dass der Projektstand nicht nur im Chat, sondern dauerhaft im Repo-Gedaechtnis bleibt.

### Session-Start-Checkliste

Bei jeder neuen Session zuerst:

1. `AGENTS.md` vollstaendig lesen.
2. Falls vorhanden `FEATURES.md` im Root lesen, wenn es um Planung, Roadmap oder Features geht.
3. `git status --short --branch` pruefen.
4. Relevante Swift-Dateien lesen, bevor Code geaendert wird.
5. Den aktuellen Milestone und "Aktuell in Arbeit" gegen den Code abgleichen.

### Bei jeder Code- oder Feature-Aenderung

Nach jeder relevanten Aenderung pruefen und bei Bedarf aktualisieren:

1. `AGENTS.md`:
   - Implementierter Code
   - Milestone-Plan
   - Aktuell in Arbeit
   - Letzte Aenderungen
   - Bekannte Gotchas / ADRs
2. `FEATURES.md`:
   - Feature-Status
   - Prioritaet
   - offene Entscheidungen
   - Empfehlungen oder bewusst zurueckgestellte Punkte
3. Tests/Build:
   - Vor Abschluss mindestens den passenden `xcodebuild`-Befehl laufen lassen.
   - In der finalen Antwort exakt nennen, was geprueft wurde und ob es erfolgreich war.

### Dokumentationsprinzip

- Entscheidungen kurz begruenden, besonders wenn Features verschoben oder vereinfacht werden.
- Keine Roadmap stillschweigend aendern. Immer in `AGENTS.md` und/oder `FEATURES.md` nachfuehren.
- Wenn eine User-Entscheidung faellt, diese als Entscheidung dokumentieren, nicht nur im Chat beantworten.
- Wenn der Code vom Projektgedaechtnis abweicht, zuerst das Projektgedaechtnis korrigieren oder die Abweichung klar melden.

---

## Technologie-Stack

| Bereich | Technologie | Version / Hinweis |
|---|---|---|
| UI Framework | SwiftUI (macOS) | Kein AppKit direkt |
| Architektur | MVVM | `@Observable` Macro (kein ObservableObject) |
| Navigation | NavigationSplitView | 3-Spalten: Sidebar / Liste / Detail |
| Persistenz | SwiftData | Kein Core Data |
| iCloud Sync | CloudKit via SwiftData | Geplant fuer M4 — noch nicht aktiviert |
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
│   │   ├── ArticleCommands.swift       # macOS Artikel-Menue + Tastaturkuerzel ✅
│   │   ├── ArticleCommandActions.swift # FocusedValues fuer Artikelaktionen ✅
│   │   ├── FeedCommands.swift          # macOS Feed-Menue ✅
│   │   └── FeedCommandActions.swift    # FocusedValues fuer Feedaktionen ✅
│   │
│   ├── Models/                         # SwiftData @Model Klassen — alle fertig ✅
│   │   ├── Feed.swift
│   │   ├── FeedFolder.swift            # Leere/angelegte Sidebar-Ordner ✅
│   │   ├── FeedLogEntry.swift          # Feed-Abruf- und Fehlerlog ✅
│   │   ├── Article.swift
│   │   ├── Tag.swift
│   │   ├── Rule.swift
│   │   ├── RuleCondition.swift         # Mehrfachbedingungen fuer Regeln ✅
│   │   ├── RuleMatchMode.swift         # AND/OR-Auswertung fuer Regeln ✅
│   │   ├── RuleConditionField.swift    # Regel-Felder title/summary/feedTitle ✅
│   │   └── RuleConditionOperator.swift # Regel-Operatoren ✅
│   │
│   ├── ViewModels/
│   │   ├── FeedViewModel.swift         # Feed hinzufügen, aktualisieren, loeschen ✅
│   │   ├── ArticleViewModel.swift      # Artikel gelesen/ungelesen und Stern toggeln ✅
│   │   ├── ArticleNavigationState.swift # Sichtbare Artikel-Navigation effizient berechnen ✅
│   │   ├── ArticleMetadataEditor.swift # Artikel-Ordner und Tags bearbeiten ✅
│   │   ├── TagViewModel.swift          # Tags verwalten ✅
│   │   └── RuleViewModel.swift         # Regeln erstellen, bearbeiten, loeschen ✅
│   │
│   ├── Views/
│   │   ├── ContentView.swift           # Root: NavigationSplitView (3 Spalten) ✅
│   │   ├── FirstRun/
│   │   │   ├── FirstRunWizardView.swift # Erster-Start-Wizard fuer Feed/OPML/Defaults ✅
│   │   │   └── FirstRunWizardState.swift # Anzeige-/Abschlusslogik fuer Wizard ✅
│   │   ├── Sidebar/
│   │   │   ├── SidebarView.swift       # Linke Spalte: Filter, Tags, Regeln, Feeds, + Button, @Query ✅
│   │   │   ├── SidebarStyle.swift      # Farb-/Auswahlwerte fuer helle System-Sidebar ✅
│   │   │   ├── SidebarUnreadCount.swift # Ungelesen-Zaehler fuer Sidebar-Badges ✅
│   │   │   ├── FeedFolderOrganizer.swift # Einfache Ordner-Gruppierung fuer Feeds ✅
│   │   │   ├── FeedRowView.swift       # Feed-Zeile mit Favicon/Fallback ✅
│   │   │   ├── FeedPropertiesView.swift # Feed-Eigenschaften-Sheet ✅
│   │   │   ├── FeedRenameView.swift    # Feed-Anzeigename bearbeiten ✅
│   │   │   └── FeedPropertiesFormatter.swift # Helper fuer Eigenschaften ✅
│   │   ├── ArticleList/
│   │   │   ├── ArticleListView.swift   # Mittlere Spalte: echte Feed-Artikel anzeigen ✅
│   │   │   ├── ArticleListQuery.swift  # SwiftData-Queries fuer Feed-/Artikel-Listen ✅
│   │   │   └── ArticleRowView.swift    # Reichhaltige Artikel-Zeile mit Status/Stern ✅
│   │   ├── Reader/
│   │   │   ├── ReaderView.swift        # Rechte Spalte: nativer Artikel-Reader ✅
│   │   │   ├── ArticleMetadataInspectorView.swift # Rechter Artikelinfos-Inspector ✅
│   │   │   ├── ReaderPreparedArticle.swift # Vorbereitete Reader-Daten pro Artikel ✅
│   │   │   ├── ReaderContentRenderer.swift # HTML/Text zu Reader-Bloecken ✅
│   │   │   ├── ReaderMetadataFormatter.swift # Feedname/Lesezeit/Alter ✅
│   │   │   ├── ReaderFontPreset.swift  # Schrift-Presets fuer Reader ✅
│   │   │   ├── ReaderFontRegistry.swift # Gebundelte Fonts registrieren ✅
│   │   │   ├── ReaderTypography.swift  # Textgroesse/Zeilenabstand Defaults ✅
│   │   │   └── WebContentView.swift    # WKWebView-Wrapper fuer Originalansicht ✅
│   │   ├── Tags/
│   │   │   ├── TagManagerView.swift    # Tags erstellen, bearbeiten, loeschen ✅
│   │   │   └── AddTagView.swift        # bleibt vorerst nicht separat noetig; TagManagerView erstellt Tags direkt
│   │   ├── OPMLImport/
│   │   │   └── OPMLImportReviewView.swift # Erweiterter OPML-Import-Dialog ✅
│   │   ├── Shared/
│   │   │   └── CachedRemoteImageView.swift # Gemeinsame gecachte Remote-Bild-View ✅
│   │   ├── Rules/
│   │   │   ├── RuleSettingsView.swift  # Alle Regeln in Einstellungen verwalten ✅
│   │   │   └── RuleWizardView.swift    # Wizard fuer einfache/Power-User-Regeln ✅
│   │   └── Settings/
│   │       ├── SettingsView.swift      # Strukturierte Settings-Shell mit linker Navigation ✅
│   │       └── FeedManagementSettingsState.swift # Suche/Auswahl fuer Feed-Verwaltung ✅
│   │
│   ├── Services/
│   │   ├── FeedService.swift           # FeedKit-Wrapper: RSS/Atom/JSON Feed parsen ✅
│   │   ├── FaviconService.swift        # HTML Favicon Discovery + Fallback ✅
│   │   ├── BackgroundRefreshSettings.swift # Auto-Refresh Settings/Intervalle ✅
│   │   ├── BackgroundRefreshService.swift  # NSBackgroundActivityScheduler Adapter ✅
│   │   ├── ArticleFeedIDBackfillService.swift # feedID fuer alte Artikel nachfuellen ✅
│   │   ├── OrphanedArticleCleanupService.swift # verwaiste Artikel ohne existierenden Feed entfernen ✅
│   │   ├── FeedUnreadCountBackfillService.swift # unreadCount einmalig korrigieren ✅
│   │   ├── RuleConditionBackfillService.swift # alte Rule-Felder in Conditions migrieren ✅
│   │   ├── OfflineDownloadService.swift # Manueller Offline-Download pro Artikel ✅
│   │   ├── ImageCacheService.swift     # Memory-/Disk-Cache fuer Bilder und Favicons ✅
│   │   ├── ImageCacheSettings.swift    # Cache-Limits und Groessenformatierung ✅
│   │   ├── RuleEngine.swift            # Mehrfach-Regeln auf neue Artikel anwenden ✅
│   │   ├── OPMLService.swift           # OPML Import und Export ✅
│   │   └── OPMLDocument.swift          # FileDocument fuer OPML Export ✅
│   │
│   ├── Extensions/
│   │   └── Date+RelativeDisplay.swift  # Datum fuer Artikelzeilen formatieren ✅
│   │
│   └── Resources/
│       ├── Assets.xcassets
│       ├── AppLanguage.swift           # Sprachauswahl + Locale-Mapping ✅
│       ├── InterfaceTextSize.swift     # App-weite UI-Schriftgroesse ✅
│       ├── Localizable.xcstrings       # String Catalog fuer de/en/fr/it ✅
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

## Implementierter Code (Stand 2026-06-21)

### FeedivoApp.swift
```swift
import SwiftUI
import SwiftData

@main
struct FeedivoApp: App {
    private let modelContainer: ModelContainer
    private let backgroundRefreshScheduler: SystemBackgroundActivityRefreshScheduler

    init() {
        let modelContainer = try! ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self
        )
        self.modelContainer = modelContainer
        self.backgroundRefreshScheduler = SystemBackgroundActivityRefreshScheduler(
            modelContainer: modelContainer
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
```

### ContentView.swift
NavigationSplitView mit 3 Spalten. Verwaltet `selectedFeed` und `selectedArticle` als
`@State`. Zeigt `ContentUnavailableView` wenn nichts ausgewählt ist.
Spaltenbreiten: Sidebar 200–300px, ArticleList 280–400px, Detail flexibel.
Praesentiert `AddFeedSheet` zentral, damit Sidebar-Plus und macOS-Menue `Feed`
dieselbe Feed-hinzufuegen-Oberflaeche verwenden.
Haelt keine pauschale `@Query` auf alle Artikel mehr; `ArticleListView` meldet nur
noch einen kleinen `ArticleNavigationState` mit vorherigem/naechstem Artikel nach
oben, statt die komplette sichtbare Artikelliste in `ContentView` zu kopieren.
Praesentiert ausserdem den Regel-Wizard fuer den aktuell ausgewaehlten Artikel,
wenn die Sidebar-Aktion `Regel aus Artikel erstellen...` genutzt wird.
Haelt den offenen/geschlossenen Zustand des rechten Artikelinfos-Inspectors auf
Root-Ebene, damit die eingeblendete Seitenleiste beim Feed- oder Artikelwechsel
sichtbar bleibt.
Zeigt beim Start automatisch den First-Run-Wizard, sobald keine Feeds vorhanden
sind. Ein frueheres Abschluss-Flag blockiert eine wieder vollstaendig leere App
nicht mehr; `Später` blendet den Wizard nur fuer die aktuelle Sitzung aus.
Zeigt unten rechts im Hauptfenster einen dezenten Online-/Offline-Indikator ueber
`NWPathMonitor`. Dieser Netzwerkstatus ist bewusst getrennt vom Artikel-Status fuer
manuell offline gespeicherte Inhalte.

### FirstRunWizardView.swift / FirstRunWizardState.swift
- First-Run-Wizard nach Prototyp Variante A fuer leere App-Starts ohne Feeds.
- Die echte SwiftUI-Oberflaeche bildet die Prototyp-Struktur nach: macOS-artige
  Titlebar mit Traffic-Lights, linke Step-Rail, rechts H1/Lead-Inhalt und Footer
  mit `Später`, `Zurück` und Primaeraktion.
- Startscreen bietet `Feed hinzufügen`, `OPML importieren` und `Später einrichten`.
- Einzelner Feed und OPML-Datei laufen zuerst in dieselbe Import-Oberflaeche:
  Feed-Pruefung, Statusfilter, Auswahl einzelner Feeds, Ordnerzuordnung,
  Ordneranlage, Duplikat-Import und Import nicht erreichbarer Feeds.
- Die Review ist bewusst nur eine Zusammenfassung der vorherigen Auswahl und bietet
  einen Link zurueck zur Import-Oberflaeche; die Feed-Liste wird dort nicht erneut
  gezeigt.
- Die Wizard-Texte sind bewusst handlungsorientiert formuliert: Sie erklaeren pro
  Schritt, was der Benutzer sieht, was geaendert werden kann und was beim naechsten
  Klick passiert. Interne Begriffe wie `Review`, `Defaults` oder `Import-Engine`
  werden in der sichtbaren UI vermieden.
- OPML-Dateien koennen im Wizard ausgewaehlt oder direkt per Drag & Drop ins Fenster
  gezogen werden.
- Abschlussschritt setzt erste Defaults wie `Artikel beim Öffnen als gelesen
  markieren` und automatischen Background Refresh.
- Nach erfolgreichem Import zeigt der Wizard einen Fertig-Screen mit importierten
  Feeds, verwendeten Ordnern und Hinweisen zu Duplikaten, nicht erreichbaren Feeds
  oder Refresh-/Speicherproblemen; das Fenster schliesst erst bei `Starten`.
- `FirstRunWizardState` kapselt die Anzeigeentscheidung, das
  `@AppStorage`-Abschluss-Flag `firstRunWizard.completed` und die Sitzungslogik:
  leerer Feedbestand zeigt den Wizard wieder, ausser er wurde in der aktuellen
  Sitzung bewusst per `Später` ausgeblendet. Ein bereits sichtbarer Wizard bleibt
  nach dem Import offen, auch wenn dadurch Feeds entstehen und ein frueheres
  Abschluss-Flag bereits gesetzt war; geschlossen wird erst durch `Starten`.

### SidebarView.swift
- `@Query(sort: \Feed.title)` für automatische Feed-Liste aus SwiftData
- Eigene SwiftUI-Sidebar statt Standard-`List`, aber wieder mit hellem,
  systemnahem Hintergrund, damit sie zur klassischen macOS-Sidebar passt.
- Header mit + Button → oeffnet zentral praesentiertes `AddFeedSheet`
- `AddFeedSheet` ist eine separate Struct in derselben Datei
- Ruft `FeedViewModel.addFeed()` auf
- Kontextmenue pro Feed ruft das Feed-Loeschen mit Bestaetigung an
- Kontextmenue pro Feed oeffnet `Feed Eigenschaften...` mit Metadaten, Intervall
  und Feed-Log
- Smart-Filter behalten die bestehenden SF-Symbol-Icons (`tray.full`, `circle.fill`,
  `star.fill`, `calendar`) und ihre Farben.
- Die Hauptbereiche `Filter`, `Tags`, `Regeln` und `Ordner` sind per Chevron
  einklappbar; der Zustand wird per `@AppStorage` gespeichert und bleibt damit
  ueber Feedwechsel und App-Neustarts erhalten.
- Der Smart-Filter `Ungelesen` zeigt rechts die Gesamtzahl aller ungelesenen Artikel
  ueber alle Feeds
- Ungelesen-Badges basieren auf `Feed.unreadCount`, damit die Sidebar beim Rendern
  keine separate Query auf alle ungelesenen Artikel mehr materialisieren muss
- Die Sidebar zeigt eine eigene `Tags`-Section mit Tag-Icon; der Button oeffnet den
  zentralen `TagManagerView`.
- Vorhandene Tags werden in der Sidebar als klickbare Zeilen mit Farbindikator aus
  `Tag.colorHex` angezeigt; ein Klick filtert die Artikelliste feeduebergreifend
  auf Artikel mit diesem Tag. Der Filter umfasst direkt getaggte Artikel und Artikel
  aus Feeds, denen das Tag zugewiesen ist.
- Neu erstellte Tags werden nach erfolgreichem Anlegen direkt als Sidebar-Auswahl
  gesetzt, damit der schnelle Tag-Filter sofort sichtbar und nutzbar ist.
- Tag-Zeilen zeigen rechts eine dezente Badge mit der Anzahl passender Artikel;
  direkt getaggte Artikel und Artikel aus getaggten Feeds werden ohne Duplikate
  gezaehlt.
- Die Sidebar zeigt Regeln nur kompakt als eigenen Abschnitt mit Anzahl aktiver
  Regeln und einem Link, um aus dem aktuell ausgewaehlten Artikel eine neue Regel zu
  erstellen. Die komplette Regelverwaltung liegt bewusst in den Einstellungen.
- Feeds stehen in einer Sidebar-Section `Ordner`; neben dem Section-Titel gibt es
  einen + Button zum Anlegen neuer Ordner
- Ordner sind per Chevron auf- und zuklappbar; Feeds innerhalb eines Ordners werden
  eingerueckt angezeigt, damit die Hierarchie klarer lesbar ist
- Angelegte/leere Ordner werden als `FeedFolder` gespeichert; die Zuordnung eines
  Feeds zu einem Ordner bleibt fuer v1 ueber `Feed.folderName`
- Ordner sind fuer v1 eine Ebene tief; noch kein Drag & Drop

### FeedRowView.swift
- Zeigt Feed-Titel mit kleinem Favicon aus `Feed.faviconURL`
- Nutzt `AsyncImage` fuer remote Icons
- Fallback ist das RSS-Systemsymbol, wenn kein Icon vorhanden ist oder das Laden scheitert
- Zeigt rechts eine dezente Badge mit der Anzahl ungelesener Artikel, wenn der Feed
  mindestens einen ungelesenen Artikel hat

### SidebarUnreadCount.swift
- Kapselt die Sidebar-Zaehllogik fuer ungelesene Artikel pro Feed und ueber alle Feeds.
- Liest vorberechnete `Feed.unreadCount` Werte, damit die Sidebar weder komplette
  Feed-Relationships noch alle ungelesenen Artikel laden muss.
- Liefert nur fuer positive Zaehler einen sichtbaren Badge-Text, damit Feeds ohne
  ungelesene Artikel ruhig bleiben.
- `SidebarTagCount` zaehlt direkt getaggte Artikel und Artikel aus getaggten Feeds
  zusammen, entfernt Duplikate ueber `Article.id` und liefert daraus die Tag-Badge.

### FeedService.swift
- Parsed RSS 2.0, Atom und JSON Feed via FeedKit
- Nutzt FeedKit `Feed(data:)` für Parsing und `URLSession` + async/await für Download
- Gibt `ParsedFeed` mit Feed-Metadaten und `[ParsedArticle]` zurück
- Feed-Titel wird aus Metadaten gelesen, mit URL als Fallback
- Website-URL fuer Favicon Discovery wird aus Feed-Metadaten gelesen:
  RSS `channel.link`, Atom `alternate` Link, JSON Feed `home_page_url`
- Artikelbilder werden aus Media RSS, iTunes Image, Bild-Enclosures und erstem
  `<img>` in Content/Summary gelesen
- `fetchFeed` bleibt ein reiner Feed-Abruf und laedt keine verlinkten Artikelseiten
  mehr automatisch; fehlende Artikelbilder koennen explizit ueber
  `enrichArticleImagesIfNeeded` aus `og:image`/`twitter:image` der Artikelseite
  nachgezogen werden
- Relative Artikelbild-URLs werden gegen die Feed-URL zu absoluten URLs aufgeloest,
  damit `AsyncImage` sie laden kann
- HTML-Regulaerausdruecke fuer Artikelbilder und Meta-Tags werden als statische
  `NSRegularExpression` Instanzen gecacht, damit sie nicht pro Artikel oder Refresh
  neu kompiliert werden muessen
- Eigene `FeedServiceError` enum: `.invalidURL`, `.parsingFailed`

### FeedViewModel.swift
- `@Observable` class
- `addFeed(urlString:context:)` — lädt Artikel, erstellt Feed, speichert in SwiftData
- Beim Hinzufuegen und Aktualisieren wird `FaviconService` genutzt, um `Feed.faviconURL`
  aus Website-HTML oder `/favicon.ico` Fallback zu speichern
- `refreshFeed(_:context:)` — aktualisiert den ausgewaehlten Feed, fuegt nur neue
  Artikel hinzu und aktualisiert Feed-Metadaten sowie `lastRefreshed`
- Beim Hinzufuegen werden `siteURL`, `followedAt` und ein Info-Log geschrieben
- Beim Hinzufuegen und Aktualisieren wird `Feed.unreadCount` fuer Sidebar-Badges
  gepflegt; neue Artikel starten als ungelesen
- Beim Aktualisieren werden Erfolg/Fehler als `FeedLogEntry` protokolliert; pro Feed
  bleiben die neuesten 20 Log-Eintraege erhalten
- `refreshAllFeeds(_:context:)` — aktualisiert alle gespeicherten Feeds per
  `withTaskGroup` parallel; Netzwerk-awaits koennen sich ueberlappen, SwiftData-
  Aenderungen bleiben durch `@MainActor` serialisiert
- Der Sammel-Refresh laeuft bei einzelnen Fehlern weiter und meldet am Ende
  betroffene Feednamen
- `operationProgress` liefert fuer Sammel-Refresh und OPML-Import einen sichtbaren
  Fortschritt mit Titel, erledigten Feeds, Gesamtzahl und Prozentwert; `ContentView`
  zeigt daraus ein kompaktes Overlay.
- `deleteFeed(_:context:)` — loescht einen Feed aus SwiftData; Artikel werden ueber
  die Cascade-Relationship mitgeloescht
- `renameFeed(_:displayTitle:context:)` — speichert einen benutzerdefinierten
  Anzeigenamen, ohne den urspruenglichen Feed-Namen zu verlieren
- `restoreOriginalFeedTitle(_:context:)` — setzt den Anzeigenamen wieder auf den
  gespeicherten Originalnamen zurueck
- Beim Refresh wird `Feed.originalTitle` mit dem Feed-Metadaten-Titel aktualisiert;
  ein benutzerdefinierter `Feed.title` bleibt erhalten
- Beim Refresh werden Summary und fehlender `Article.content` fuer bestehende Artikel
  aus spaeter gelieferten Feed-Daten nachgetragen, damit Offline-Content nicht nur
  fuer neue Artikel gespeichert wird
- Der Feed-Fetch ist als Closure injizierbar, damit Refresh-Tests ohne Netzwerk laufen
- Die Favicon-Discovery ist als Closure injizierbar, damit Tests ohne Netzwerk laufen
- Die Artikelbild-Anreicherung ist als Closure injizierbar; beim Refresh wird sie nur
  fuer neue Artikel ohne Feed-Bild und fuer bereits gespeicherte, noch bildlose
  Artikel aufgerufen, damit bestehende Artikel mit Bild keine unnoetigen
  Netzwerkrequests mehr ausloesen
- Der OPML-Import arbeitet zweiphasig: Feed-URL-Deduplizierung und Feed-Anlage laufen
  kontrolliert sequenziell, danach werden die neuen Feeds per `withTaskGroup`
  parallel aktualisiert
- Beim Refresh werden gespeicherte Regeln ueber `RuleEngine` auf neu eingefuegte
  Artikel angewendet; bestehende Artikel koennen in den Einstellungen manuell
  rueckwirkend getaggt werden.
- Properties: `isLoading: Bool`, `errorMessage: String?`

### FaviconService.swift
- Laedt die Website-HTML-Seite eines Feeds und sucht `<link rel="...icon...">`
- Unterstuetzt `icon`, `shortcut icon`, `apple-touch-icon` und `mask-icon`
- Normalisiert relative und protokollrelative Icon-URLs zu absoluten URLs
- Priorisiert Apple-Touch-Icons und groessere `sizes` Werte vor einfachen Icons
- HTML-Regulaerausdruecke fuer Link-Tags und Attribute werden statisch gecacht;
  Attributwerte werden in einem Durchlauf mit Capture Groups gelesen
- Fallback: Wenn HTML nicht geladen oder kein Icon gefunden wird, nutzt Feedivo
  `/favicon.ico` auf der Website-Root
- Keine externe Google-S2-API; die Favicon-Strategie bleibt eigenstaendig und
  datensparsamer

### ArticleFeedIDBackfillService.swift / FeedUnreadCountBackfillService.swift
- `ArticleFeedIDBackfillService` fuellt `Article.feedID` fuer alte Artikel nach, die
  vor der Denormalisierung gespeichert wurden; die Abfrage sucht gezielt nur Artikel
  mit `feedID == nil`.
- `FeedUnreadCountBackfillService` korrigiert `Feed.unreadCount` fuer vorhandene Feeds
  einmalig und setzt danach das UserDefaults-Flag `feedUnreadCountBackfillDone_v1`.
- Das UserDefaults-Objekt ist injizierbar, damit der einmalige Backfill in Tests
  kontrolliert werden kann.
- Nach erfolgreichem Durchlauf wird beim App-Start nicht mehr pro Feed die komplette
  `articles`-Relationship geladen, nur um den Sidebar-Zaehler zu verifizieren.

### RuleEngine.swift
- Stateless Service fuer automatische Tag-Zuweisung.
- Unterstuetzt mehrere Bedingungen pro Regel und wertet sie je nach
  `RuleMatchMode` als `all` (AND) oder `any` (OR) aus.
- Unterstuetzt die Felder `title`, `summary` und `feedTitle`.
- Unterstuetzt die Operatoren `contains`, `startsWith` und `endsWith`.
- Vergleicht case-insensitive und ignoriert deaktivierte Regeln, leere Suchwerte,
  unbekannte Felder/Operatoren, Regeln ohne Bedingungen sowie Regeln ohne `assignTag`.
- Fuegt Tags nur hinzu, wenn der Artikel das Tag noch nicht besitzt.
- Gibt die Anzahl neu gesetzter Tags zurueck und kann Regeln gesammelt auf vorhandene
  Artikel mit Feed-Bezug anwenden.
- Zaehlt fuer den Regel-Wizard vorab, wie viele vorhandene Artikel zu den aktuellen
  Bedingungsentwuerfen passen wuerden, ohne dabei Tags zu setzen.

### RuleViewModel.swift
- Kapselt Erstellen, Bearbeiten und Loeschen von Regeln fuer den Wizard.
- Validiert Name, Ziel-Tag und mindestens eine nichtleere Bedingung.
- Speichert neue Mehrfachbedingungen als `RuleCondition` und pflegt die alten
  `conditionField`/`conditionOperator`/`conditionValue` Felder fuer Kompatibilitaet
  mit bestehenden Daten weiter.

### RuleConditionBackfillService.swift
- Migriert alte Regeln mit nur einem gespeicherten Legacy-Bedingungsfeld beim
  App-Start in die neue `Rule.conditions` Relationship.
- Ueberspringt Regeln mit bereits vorhandenen Conditions oder leerem Suchwert.

### RuleSettingsView.swift / RuleWizardView.swift
- Einstellungen zeigen eine Liste aller Regeln mit Status, Ziel-Tag und
  Bedingungszusammenfassung; Regeln koennen geoeffnet, bearbeitet oder geloescht
  werden.
- Einstellungen bieten einen Button `Auf vorhandene Artikel anwenden`, der aktive
  Regeln manuell auf den gespeicherten Artikelbestand anwendet und danach die Anzahl
  neu gesetzter Tag-Zuweisungen anzeigt.
- Neue Regeln werden ueber einen Wizard erstellt. Der Benutzer waehlt zwischen
  einfacher Regel und Power-User-Regel.
- Einfache Regeln verwenden eine Bedingung; Power-User-Regeln erlauben mehrere
  Bedingungen mit AND- oder OR-Verknuepfung.
- Der Wizard zeigt live eine Vorschau, wie viele vorhandene Artikel die aktuelle
  Regel treffen wuerde. Leere Suchwerte zeigen stattdessen einen Hinweis.
- Der Wizard kann aus der Sidebar mit dem aktuell ausgewaehlten Artikel gestartet
  werden und fuellt dann einen passenden ersten Vorschlag vor.

### FeedPropertiesView.swift / FeedPropertiesFormatter.swift
- Rechtsklick auf Feed → `Feed Eigenschaften...`
- Sheet nutzt einen Feed-Header mit Icon/Favicon-Fallback, Website und Statusmetriken
  fuer Aktualisierungsintervall, naechsten Abruf und sichtbare Log-Eintraege
- Darunter zeigt es gruppiert Originaltitel, Website, XML-Adresse mit Kopierbutton,
  Gefolgt-ab-Datum, editierbaren Ordner, letzten Artikel, Aktualisierungsintervall,
  naechsten Abruf, zuletzt aktualisiert und die neuesten 20 Feed-Log-Eintraege
- Website und XML-Adresse werden als echte Links im Standardbrowser geoeffnet,
  sofern sie gueltige `http`/`https`-URLs sind; der XML-Kopierbutton bleibt erhalten
- Aktualisierungsintervall ist direkt im Sheet editierbar und wird in SwiftData gespeichert
- Der Ordnername ist direkt im Sheet editierbar; leere Eingaben werden als `nil`
  gespeichert
- Feed-Tags sind direkt im Sheet editierbar: Vorhandene globale Tags koennen per
  Plus-Chip zugewiesen, neue Tags per Eingabe erstellt und zugewiesene Tags wieder
  entfernt werden.
- `FeedPropertiesFormatter` kapselt naechsten Abruf, neuesten Artikel, Log-Limit und
  die sichtbare Log-Anzahl sowie gueltige Link-URLs, damit diese Logik ohne UI
  testbar bleibt

### FeedRenameView.swift
- Rechtsklick auf Feed → `Feed umbenennen...`
- Links oben im Sheet wird das gespeicherte Feed-Favicon angezeigt; fehlt es oder
  laedt es nicht, erscheint das RSS-Systemsymbol als Fallback.
- Sheet zeigt editierbaren Anzeigenamen, gespeicherten urspruenglichen Feed-Namen
  und einen Button zum Wiederherstellen des Originalnamens.
- Speichern nutzt `FeedViewModel.renameFeed`, damit Trim, Leerwert-Pruefung und
  Originalnamen-Erhalt zentral testbar bleiben.

### FeedFolderOrganizer.swift
- Kapselt die einfache Feed-Ordnerlogik fuer die Sidebar.
- Normalisiert Ordnernamen per Trim; leere Namen werden als fehlender Ordner behandelt.
- Liefert eindeutige, alphabetisch sortierte Ordnernamen und sortierte Feed-Listen
  pro Ordner beziehungsweise ohne Ordner.

### BackgroundRefreshSettings.swift / BackgroundRefreshService.swift
- `BackgroundRefreshSettings` kapselt `@AppStorage` Keys, Defaults und erlaubte
  Intervalle: 15, 30, 60 oder 120 Minuten sowie Statuswerte fuer letzten
  automatischen Refresh, letzten Fehler und naechsten geschaetzten Lauf.
- `BackgroundRefreshService.scheduleNextRefresh(...)` plant oder storniert den
  Auto-Refresh testbar ueber ein kleines Scheduler-Protokoll.
- Beim Planen, nach erfolgreichem Lauf und nach Fehlern speichert der Service
  Statusdaten in UserDefaults; die Einstellungen zeigen diese kompakt an.
- `SystemBackgroundActivityRefreshScheduler` nutzt `NSBackgroundActivityScheduler`,
  weil `BGTaskScheduler` fuer native macOS Apps im SDK nicht verfuegbar ist.
- Automatischer Refresh nutzt denselben Pfad wie manueller Refresh fuer alle Feeds:
  `FeedViewModel.refreshAllFeeds(_:context:)`.
- Wichtig: macOS entscheidet den genauen Zeitpunkt. Eine vollstaendig beendete App
  wird fuer diese Basis nicht neu gestartet.

### ArticleListView.swift
- Zeigt echte Artikel des ausgewählten Feeds ueber eine gezielte SwiftData-Query
  statt ueber die komplette `Feed.articles` Relationship
- Feed-Listen laden nicht mehr automatisch alle Artikel per globaler `@Query`;
  Smart-Filter-Listen nutzen gezielte SwiftData-Queries fuer Alle, Ungelesen,
  Mit Stern und Heute statt alle Artikel im Speicher zu filtern
- Tag-Listen nutzen ebenfalls eine gezielte SwiftData-Query und zeigen
  feeduebergreifend direkt getaggte Artikel sowie Artikel aus getaggten Feeds.
- Sortiert nach `publishedAt` absteigend
- Meldet nur den `ArticleNavigationState` an `ContentView`, damit Reader-Navigation
  und Menue-Status ohne Kopie der gesamten Artikelliste aktualisiert werden
- Reagiert mit `.onChange(of: articles)` auf Listen-Aenderungen und erzeugt kein
  separates `articleIDs = articles.map(\.id)` Array mehr pro SwiftUI-Renderdurchlauf
- Nutzt `ArticleRowView` fuer Titel, Metadaten, Summary, optionales Bild,
  Ungelesen-Punkt rechts oben und Stern rechts unten
- Markiert Artikel beim Auswaehlen automatisch als gelesen, wenn die Einstellung
  aktiv ist
- Gelesene Artikel werden in Feed-, Tag- und Smartfilter-Listen standardmaessig
  ausgeblendet; am Listenende blendet ein Button `X gelesene Artikel anzeigen`
  die versteckten gelesenen Artikel fuer die aktuelle Liste ein.
- Der aktuell ausgewaehlte Artikel bleibt sichtbar, auch wenn er beim Oeffnen
  automatisch als gelesen markiert wird. So verschwindet die ausgewaehlte Zeile
  nicht direkt nach dem Klick.

### ArticleListQuery.swift
- Buendelt Sortierung und Feed-Predicate fuer Artikel-Listen.
- Feed-Listen filtern ueber `Article.feedID`, damit der Feed-Wechsel nicht ueber die
  `Article.feed`-Relationship predicated werden muss.
- Tag-Listen filtern ueber `Article.tags.contains { tag.id == selectedTagID }` und
  zusaetzlich ueber die denormalisierte `Article.feedID` fuer getaggte Feeds; diese
  Predicates sind durch `ArticleListQueryTests` abgesichert.
- `ArticleListDisplayState` kapselt die sichtbaren Artikel, die Anzahl versteckter
  gelesener Artikel und die Button-Entscheidung fuer Feature 2.5 testbar ohne UI.
- `ArticleListDisplayState` blendet `isHidden`-Artikel aus normalen Listen aus; die
  Regel-Aktion zum Setzen dieses Status bleibt ein eigener Feature-16.3-Schritt.

### ArticleNavigationState.swift
- Berechnet vorherigen und naechsten Artikel aus der aktuell sichtbaren Liste.
- Speichert nur die beiden Nachbar-Artikel und nicht mehr die komplette Liste, damit
  `ContentView` beim Feed-Wechsel weniger State kopieren muss.

### ArticleRowView.swift
- Reichhaltige Artikelzeile mit optionalem `AsyncImage`
- Platzhalterbild, wenn kein `imageURL` vorhanden ist
- Kontextmenue fuer gelesen/ungelesen, Stern, Archivieren, Tag zuweisen,
  Regel erstellen, Link kopieren, Original oeffnen, Teilen, Offline speichern/
  entfernen, Artikel loeschen und alle sichtbaren Artikel als gelesen markieren
- Gelesene Artikel werden optisch ruhiger dargestellt

### ArticleViewModel.swift
- `@Observable` class
- `toggleRead(_:)`
- `toggleStarred(_:)`
- `toggleArchived(_:)`
- Optionale Varianten ignorieren fehlende Auswahl fuer Menue-/Shortcut-Aktionen
- `markReadIfNeeded(_:isEnabled:)`
- `markAllRead(_:)` markiert eine sichtbare Artikelliste als gelesen und pflegt
  dabei die Feed-Zaehler.
- `deleteArticle(_:context:)` loescht einen Artikel aus SwiftData und korrigiert
  bei ungelesenen Artikeln den Feed-Zaehler.
- `copyLink`, `openOriginal` und `shareOriginal` kapseln Link-Aktionen testbar ueber
  kleine Protokolle fuer Pasteboard, URL-Oeffnen und Share-Picker.
- Gelesen/Ungelesen-Aenderungen aktualisieren `Feed.unreadCount`, damit Sidebar-Badges
  ohne eigene Artikel-Query aktuell bleiben
- `sortedForList(_:)`, `previousArticle(before:in:)` und `nextArticle(after:in:)`
  kapseln die Navigation innerhalb der aktuell sichtbaren Artikelliste

### ArticleMetadataEditor.swift
- Kapselt die Bearbeitung der Artikel-Metadaten fuer den Reader-Inspector.
- `addTag(named:to:availableTags:context:)` trimmt Tag-Namen, verhindert leere oder
  doppelte Artikel-Tags und verwendet vorhandene Tags wieder, bevor neue Tags
  erstellt werden.
- `availableTagsToAdd(to:availableTags:)` liefert vorhandene globale Tags, die dem
  aktuellen Artikel noch nicht zugewiesen sind, alphabetisch sortiert fuer den
  rechten Inspector.
- `removeTag(_:from:context:)` entfernt ein Tag nur vom aktuellen Artikel.
- `setFolderName(_:for:context:)` speichert den getrimmten Ordnernamen am Feed des
  Artikels; leere Eingaben entfernen die Ordnerzuordnung.

### TagViewModel.swift
- `@Observable` `@MainActor` class fuer zentrale Tag-Verwaltung.
- Erstellt Tags mit normalisiertem Namen und normalisierter Hex-Farbe und gibt das
  neu erstellte Tag fuer direkte UI-Auswahl zurueck.
- Verhindert leere und doppelte Tag-Namen case-insensitive beim Erstellen und
  Umbenennen.
- Aktualisiert Tag-Farben und loescht Tags inklusive vorhandener Artikel- und
  Feed-Verknuepfungen.

### TagManagerView.swift
- Zentrales Sheet zum Erstellen, Umbenennen, farblichen Markieren und Loeschen von
  Tags.
- Nutzt eine SwiftData-`@Query` auf `Tag.name`, wiederverwendet `TagViewModel` fuer
  Validierung und Speichern und zeigt Fehler direkt in der jeweiligen Eingabe.
- Wird aus der Sidebar-Section `Tags` geoeffnet; dieselbe Section zeigt auch
  klickbare Tag-Filterzeilen.
- Nach dem erfolgreichen Erstellen eines Tags schliesst sich das Sheet und die
  Sidebar waehlt das neue Tag als aktuellen Filter aus.

### ArticleCommands.swift / ArticleCommandActions.swift
- macOS-Menue `Artikel` fuer Aktionen auf dem fokussierten/ausgewaehlten Artikel
- `Cmd+↑` springt zum vorherigen sichtbaren Artikel
- `Cmd+↓` springt zum naechsten sichtbaren Artikel
- `Cmd+Shift+U` toggelt gelesen/ungelesen
- `Cmd+D` toggelt Stern
- Archivieren und Teilen sind ebenfalls im Artikel-Menue verfuegbar; Exportieren
  bleibt fuer Feature 2.4 noch als eigener Export-Slice offen.
- Commands sind deaktiviert, wenn kein Artikel ausgewaehlt ist oder am Listenrand
  kein vorheriger/naechster Artikel existiert
- `ContentView` stellt die Aktionen via SwiftUI `FocusedValues` bereit

### FeedCommands.swift / FeedCommandActions.swift
- macOS-Menue `Feed` fuer Aktionen auf dem fokussierten/ausgewaehlten Feed
- `Cmd+N` oeffnet `Feed hinzufügen...` und nutzt dasselbe Sheet wie der Sidebar-Plus-Button
- `OPML importieren...` oeffnet den erweiterten OPML-Import-Dialog: Datei waehlen,
  erkannte Feeds pruefen, einzelne Feeds auswaehlen, Ordner zuweisen, neue Ordner
  anlegen, Duplikate optional erlauben und entscheiden, ob direkt aktualisiert wird
- Vor dem Import prueft Feedivo neue Feed-URLs ueber denselben Feed-Abrufpfad und
  markiert Duplikate sowie nicht erreichbare/problematische Feeds in der Review-Liste
- Nach dem OPML-Import koennen neu angelegte Feeds direkt ueber denselben async
  Refresh-Kern aktualisiert werden, damit Titel, Metadaten, Favicons und Artikel
  gefuellt sind; dieser Schritt ist im Dialog abschaltbar
- `OPML exportieren...` schreibt die aktuelle Feed-Liste als `Feedivo.opml`
- `Cmd+Shift+R` aktualisiert alle Feeds
- `Cmd+R` aktualisiert den ausgewaehlten Feed
- Feed aktualisieren und Feed loeschen sind deaktiviert, wenn kein Feed ausgewaehlt ist
- OPML Export ist deaktiviert, solange keine Feeds vorhanden sind
- Kein Shortcut fuer Loeschen, damit eine destruktive Aktion bewusst bleibt
- `ContentView` zeigt vor dem Loeschen einen Bestaetigungsdialog und setzt die
  Feed-/Artikel-Auswahl nach erfolgreichem Loeschen zurueck

### OPMLService.swift / OPMLDocument.swift
- `OPMLService.parseFeeds(from:)` liest OPML 2.0 mit verschachtelten `outline`-Eintraegen
  ueber `XMLParser`.
- Feed-Outlines werden aus `xmlUrl`/`xmlURL`, `title`/`text`, `htmlUrl`/`htmlURL`
  in `OPMLFeed` umgewandelt.
- Verschachtelte OPML-Gruppen werden fuer v1 als `Feed.folderName` uebernommen,
  damit die Information erhalten bleibt und importierte Feeds direkt gruppiert sind.
- `OPMLService.exportFeeds(_:)` schreibt gueltiges OPML mit gruppierten Feeds und
  XML-escaping fuer Titel, Feed-URL und Website.
- `OPMLDocument` kapselt den SwiftUI `FileDocument` Export fuer `.opml` und `.xml`.

### OPMLImportReviewView.swift
- Eigenstaendiger SwiftUI-Dialog fuer den erweiterten OPML-Import nach Prototyp
  Variante A.
- Die OPML-Datei wird im Dialog ausgewaehlt und geparst; danach werden Feed-Titel,
  Feed-URL, Website, Ordner und Status in einer intern scrollenden Review-Tabelle
  angezeigt.
- Alternativ zur Datei-Auswahl kann eine `.opml`- oder `.xml`-Datei direkt auf das
  Importfenster gezogen werden; der Drop nutzt denselben Preview- und Pruefpfad wie
  der Button `Datei auswählen...`.
- Lange Feednamen und URLs werden einzeilig gekuerzt, damit das Dialogfenster auch
  bei vielen oder langen Feeds stabil bleibt.
- Der Benutzer kann nur ausgewaehlte Feeds importieren, vorhandene/neu erstellte
  Ordner pro Feed zuweisen, Duplikate und nicht erreichbare Feeds bewusst erlauben
  und den Refresh nach Import ein- oder ausschalten.
- Ein Status-Dropdown filtert die sichtbare Tabelle nach allen, neuen, doppelten
  oder nicht erreichbaren Feeds. Der Filter veraendert nur die Sichtbarkeit; Auswahl
  und Ordner-Aenderungen an Zeilen bleiben beim Zurueckstellen auf alle erhalten.
- Waehrend die Import-Vorschau vorbereitet wird, zeigt die Tabellenflaeche selbst
  einen mittig platzierten Ladezustand mit konkretem Prueffortschritt
  (`Feed x von y wird geprueft: ...`), damit der Benutzer sieht, dass Feedivo
  weiterhin arbeitet.
- Nach dem Import bleibt eine Zusammenfassung im Dialog sichtbar.

### SettingsView.swift
- macOS Settings-Szene in `FeedivoApp.swift`
- Nutzt eine linke Kategorienavigation nach Prototyp Variante A statt eines langen
  Formulars. Bereiche: Allgemein, Darstellung, Feeds, Cache, Offline-Lesen,
  Aktualisierung, Tags & Regeln und Sync.
- Bestehende Optionen wurden aufgeteilt: Sprache/Standardverhalten unter
  Allgemein, UI-/Reader-Darstellung unter Darstellung, Auto-Refresh unter
  Aktualisierung und Regelverwaltung unter Tags & Regeln.
- Der Bereich `Feeds` zeigt eine Feed-Verwaltung mit Suche, Mehrfachauswahl,
  `Alle sichtbaren auswählen`, `Auswahl aufheben` und destruktiver
  Loeschbestaetigung fuer die ausgewaehlten Feeds.
- Der Bereich `Cache` zeigt aktuelle Bild-/Favicon-Cache-Groesse, ein Speicherlimit
  mit erlaubten Werten 100 MB, 250 MB, 500 MB, 1 GB und 2 GB, sowie Aktionen zum
  Aktualisieren der Groessenanzeige und zum Leeren des Cache.
- Der Bereich `Offline-Lesen` trennt bewusst zwischen Cache, normal lokal
  gespeichertem Feed-Inhalt und echten Offline-Kopien: Offline ist eine manuelle
  Artikelaktion, Feed-Content ist Basisinhalt, Automatik bleibt ein spaeterer M4-
  Folgepunkt.
- `@AppStorage("markArticleReadOnSelection")`
- Standard: Artikel beim Oeffnen automatisch als gelesen markieren
- `@AppStorage("appLanguage")`
- Sprachauswahl: Nach System, Deutsch, Englisch, Französisch, Italienisch
- `@AppStorage("interfaceTextSize")`
- Oberflaechenschrift: Klein, Standard, Gross, Sehr gross; wirkt app-weit ueber
  eine eigene `InterfaceTextSize`-Environment und zusaetzlich ueber SwiftUI
  `DynamicTypeSize`
- `@AppStorage("backgroundRefresh.isEnabled")`
- `@AppStorage("backgroundRefresh.intervalMinutes")`
- Automatischer Refresh ist standardmaessig deaktiviert und kann auf 15, 30, 60
  oder 120 Minuten gestellt werden
- Reader-Schriftwahl: `readerTitleFontPreset` und `readerBodyFontPreset`
- Reader-Typografie: `readerBodyFontSize`, `readerTitleLineSpacing`,
  `readerLineSpacing` und `readerContentWidth`
- Presets: System, Geist, Inter, Manrope, DM Sans, Literata, Newsreader,
  IBM Plex Sans, Atkinson Hyperlegible, Source Serif 4, Libre Franklin, Lora,
  Merriweather, Noto Sans, Noto Serif, Roboto Slab, Crimson Pro, Fraunces, Serif

### InterfaceTextSize.swift
- Kapselt die app-weite UI-Schriftgroesse getrennt von der Reader-Typografie.
- Gespeicherter Wert: `interfaceTextSize`; Default: `standard`.
- Werte: Klein, Standard, Gross, Sehr gross; unbekannte gespeicherte Werte fallen
  auf Standard zurueck.
- Mapping auf SwiftUI `DynamicTypeSize` plus eigene konkrete Skalierungswerte fuer
  fest gestaltete UI-Bereiche.
- Sidebar, Feed-Zeilen, Artikelzeilen und Settings lesen `interfaceTextSize` aus
  der SwiftUI-Environment und skalieren Font- sowie wichtige Icon-/Zeilenmasse
  sichtbar mit.

### ReaderView.swift
- Zeigt Metazeile, Titel, native Reader-Bloecke und Link zum Original
- Metazeile: Feedname, ungefaehre Lesezeit und Artikelalter, linksbuendig oberhalb
  des Titels
- Nach dem Lead-Bild erscheint ein feiner Trenner, bevor der Fliesstext beginnt.
- Nutzt einen ruhigeren Editorial-Rhythmus: etwas kleinerer semibold Titel,
  groessere Blockabstaende, kontrollierte Lead-Bildhoehe und dezenter Footer fuer
  `Original öffnen`.
- Ordner und Tags werden direkt unter dem Titel als dezente Chips angezeigt; die
  Bearbeitung bleibt ueber den sichtbaren Toolbar-Toggle `Artikelinfos` im rechten
  Inspector.
- Der offene/geschlossene Inspector-Zustand kommt als Binding aus `ContentView`,
  damit die rechte Seitenleiste beim Feed- oder Artikelwechsel erhalten bleibt.
- Die rechte Seitenleiste wird ueber SwiftUIs native `.inspector`-Spalte angezeigt;
  dadurch verschiebt sich die Reader-Toolbar beim Einblenden nach links wie bei
  einer normalen macOS-Inspector-Leiste.
- Der native Artikel-Reader blendet seine vertikale Scrollbar aus, damit der
  Uebergang zur rechten Inspector-Leiste ruhiger wirkt; Scrollen bleibt unveraendert
  moeglich.
- Wenn ein Feed nur eine Summary, aber keinen Volltext liefert, zeigt der native
  Reader die vorhandene Zusammenfassung direkt ohne zusaetzliche Hinweisbox.
  Volltexte aus der Original-Webseite bleiben ueber `Original oeffnen` erreichbar.
- Toolbar-Buttons fuer vorherigen/naechsten Artikel navigieren innerhalb der aktuell
  sichtbaren Feed- oder Smart-Filter-Liste und stoppen am Listenrand
- Seltenere Aktionen wie `Link kopieren` liegen im Reader-Mehr-Menue, damit die
  Toolbar ruhiger bleibt.
- Toolbar-Button `textformat` oeffnet ein Popover fuer Titel-Schrift,
  Fliesstext-Schrift, Textgroesse, Titel-/Fliesstext-Zeilenabstand und Artikelbreite
- Titel- und Fliesstext-Schrift sowie Textgroesse/Titel-Zeilenabstand/
  Fliesstext-Zeilenabstand/Artikelbreite werden getrennt via `@AppStorage`
  gespeichert
- Die Metazeile oberhalb des Titels sowie Ordner-/Tag-Chips nutzen die App-
  Oberflaechenschrift (`interfaceTextSize`) statt der Reader-Schriftwahl, damit sie
  optisch zur restlichen App passen.
- Toolbar-Button `arrow.down.circle` speichert den aktuellen Artikel manuell fuer
  Offline-Lesen oder entfernt die Offline-Kopie wieder. Waehrend des Downloads zeigt
  der Button einen Fortschrittsindikator.
- Der Reader zeigt einen kompakten Offline-Status nur fuer bewusst gespeicherte
  Artikel: Feed-Inhalt lokal verfuegbar, Volltext offline verfuegbar oder Fehler
  inklusive Fehlermeldung.
- Produktbegriff: Normaler Feed-Content ist nicht automatisch eine Offline-Kopie.
  Nur ein bewusst per Reader-Button gespeicherter Artikel zeigt einen Offline-
  Status am Artikel; vorhandener Feed-Content wird im Reader als lokal verfuegbarer
  Basisinhalt beschrieben.
- Nutzt `ReaderPreparedArticle`, damit Content/Summary, Metadaten und Original-URL
  pro ausgewaehltem Artikel einmal vorbereitet werden und SwiftUI-Redraws kein
  erneutes HTML-Rendering ausloesen
- Aktualisiert `ReaderPreparedArticle` bei Wechsel von `article.persistentModelID`,
  damit Bild, Text, Metadaten und Original-Link nicht vom zuvor ausgewaehlten
  Artikel im SwiftUI-`@State` haengen bleiben
- Bilder werden mit `scaledToFit` und begrenzter Maximalhoehe gerendert, damit grosse
  Feedbilder ruhiger und performanter bleiben
- Noch kein eigener Vollartikel-Lade-/Extraktionsmodus fuer den nativen Reader.
  `WKWebView` existiert bereits als Originalansicht; Vollartikel-Laden mit fair
  erhaltener Anbieterstruktur bleibt ein eigener M4/v1-Produktpunkt.

### ReaderPreparedArticle.swift
- Kapselt die vorbereiteten, teureren Reader-Daten fuer einen Artikel.
- Berechnet native Content-Bloecke, Metazeile und gueltige Original-URL einmal beim
  Erzeugen von `ReaderView`, statt diese Werte bei jedem SwiftUI-Redraw neu aufzubauen.
- Bevorzugt explizit gespeicherten `Article.offlineContent` vor Feed-Content und
  Summary, damit manuell offline gespeicherte Artikel direkt im nativen Reader
  erscheinen.
- Erkennt, ob offline geladener Volltext, Feed-Content, nur eine Summary oder gar
  kein Text verfuegbar ist; der Reader nutzt diese Information fuer Statushinweise.

### OfflineDownloadService.swift
- Speichert Artikel manuell fuer Offline-Lesen.
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
- Offline-Automatik ist absichtlich nicht Teil dieses Services. Sie soll spaeter
  als eigene Strategie mit Feed-/Zeit-/Stern-/Ungelesen-Regeln und Speichergrenzen
  gebaut werden.

### ArticleFeedIDBackfillService.swift / OrphanedArticleCleanupService.swift
- `ArticleFeedIDBackfillService` fuellt bei alten Artikeln die direkte `feedID`
  aus einer noch vorhandenen `Article.feed`-Relationship nach.
- `OrphanedArticleCleanupService` laeuft danach beim App-Start und entfernt Artikel,
  deren `feedID` zu keinem existierenden Feed mehr gehoert oder ganz fehlt.
- Hintergrund: Smart-Filter fragen Artikel direkt ab. Verwaiste Altartikel koennen
  sonst sichtbar bleiben, obwohl links keine Feeds mehr vorhanden sind.
- `FeedViewModel.deleteFeed` loescht zusaetzlich explizit alle Artikel mit passender
  `feedID`, damit kuenftige Feed-Loeschungen nicht nur von SwiftData-Cascade
  abhaengen.

### ImageCacheService.swift / ImageCacheSettings.swift
- `ImageCacheService` ist der zentrale lokale Cache fuer Artikelbilder und Favicons.
- Nutzt `NSCache<NSURL, NSImage>` fuer schnelle Wiederverwendung waehrend der App-
  Laufzeit und einen Disk-Cache unter dem macOS-Caches-Verzeichnis fuer Neustarts.
- Cache-Dateinamen werden aus einem SHA-256-Hash der Bild-URL gebildet, damit
  Sonderzeichen, Query-Parameter und lange URLs keine Dateisystemprobleme machen.
- Netzwerkabrufe laufen ueber ein kleines `ImageDataLoading`-Protokoll, damit der
  Cache ohne echtes Netzwerk getestet werden kann.
- Cache-Groesse, Leeren und Trimmen nach Limit sind testbar und werden in den
  Einstellungen verwendet.
- `ImageCacheSettings` kapselt erlaubte Speicherlimits, Default 500 MB und
  formatierte Groessenanzeige.
- Feedivo raeumt den Bildcache beim App-Start auf das aktuell gesetzte Limit auf,
  nach jeder Limit-Aenderung in den Einstellungen und nach jedem erfolgreichen
  neuen Bilddownload.
- Der Cache ist bewusst ein Performance-Cache. Er macht Bilder schneller und
  netzwerksparender, ist aber keine Garantie fuer eine echte Offline-Kopie.

### CachedRemoteImageView.swift
- Gemeinsame SwiftUI-Bildkomponente fuer remote Bilder mit lokalem Cache.
- Ersetzt direkte `AsyncImage`-Nutzung in Artikelliste, Reader, Sidebar-Favicons,
  Feed-Eigenschaften und Feed-Umbenennen-Sheet.
- Views liefern nur Darstellung und Platzhalter; Laden, Memory-Cache und Disk-Cache
  bleiben im `ImageCacheService`.

### ArticleMetadataInspectorView.swift
- Einblendbarer rechter Inspector in der Artikelansicht.
- Nutzt denselben hellen, systemnahen Sidebar-Stil wie die linke Seitenleiste und
  teilt sich die Farbwerte aus `SidebarStyle`.
- Nutzt seit 2026-06-23 die gewaehlte Product-Design-Richtung
  `Calm Actions` aus den interaktiven Inspector-Prototypen: Oben stehen kompakt
  `Artikelinfos`, der Artikeltitel und ein Status-Strip fuer gelesen/ungelesen und
  Favorit; direkt darunter liegt eine vierteilige Aktionsleiste fuer Favorit,
  Gelesen/Ungelesen, Offline-Speichern und Link-Kopieren.
- Die Inspector-Typografie ist bewusst kompakter als der Reader-Text; zentrale
  Groessen liegen in `ArticleInspectorTypography`, damit die rechte Leiste ruhig
  und uebersichtlich bleibt. Die aktuelle Skala nutzt 11 pt fuer Labels/Chips,
  11.5 pt fuer Controls, 12 pt fuer Werte, 13 pt fuer Section-Titel und 15 pt nur
  fuer den Artikelkopf.
- Zeigt den aktuellen Feed-Ordner in einer eigenen weissen Karten-Section als
  Menu-Picker, schreibt Aenderungen direkt auf `Feed.folderName` und kann neue
  Feed-Ordner direkt anlegen und auswaehlen.
- Zeigt globale Tags in einer eigenen weissen Karten-Section als Toggle-Pills wie
  im Prototyp; aktive Tags sind getoent, inaktive Tags bleiben weiss. Ein Klick
  setzt oder entfernt das Tag direkt am Artikel.
- Nutzt einklappbare weisse Karten-Sections mit Chevron und ohne zusaetzliche
  Section-Icons fuer `Feed-Ordner`, `Tags`, `Kontext` und `Quelle`. Der Kontext
  zeigt Feed, Quelle, Veroeffentlichung, Lesezeit und Offline-Status in einer
  kompakten Metadatenliste.
- Die Quelle ist standardmaessig eingeklappt und folgt dem Prototyp als reine
  Aktions-Section mit zwei breiten Zeilen fuer `Link kopieren` und `Original
  oeffnen`; die URL selbst wird dort bewusst nicht mehr als Textbox gezeigt.
- Neue interaktive Product-Design-Exploration fuer eine ruhigere, staerker
  bedienbare Inspector-Seitenleiste liegt unter
  `docs/design/article-info-interactive-sidebar-prototypes/`: drei React/Vite-
  Prototypen testen Favorit-, Gelesen-, Offline-, Tag-, Ordner- und Link-Aktionen
  direkt in der rechten Seitenleiste; Tags koennen im Prototyp mit eigener Farbe
  neu erstellt und sofort dem Artikel zugewiesen werden. Der Ordner wird dort
  bewusst als `Feed-Ordner` bezeichnet, weil er die Feed-Zuordnung und nicht eine
  einzelne Artikelablage veraendert; neue Feed-Ordner koennen im Prototyp direkt
  erstellt und sofort fuer den Feed ausgewaehlt werden. Feed-Ordner und Tags sind
  im Prototyp bewusst als getrennte Sections angelegt.
- Umgesetzte Richtung in SwiftUI ist Variante 1 `Calm Actions`: ruhige weisse
  Karten-Sections mit runden Ecken, separatem Feed-Ordner und Tags-Bereich sowie
  direkter Aktionsleiste oben. Die fruehere Hero-/Timeline-Anmutung wurde entfernt,
  damit die native App dem ausgewaehlten Prototyp klarer entspricht.
- `ArticleInspectorFormatter` kapselt die Anzeigeaufbereitung fuer Status, URL,
  Titel-/Summary-Kontext, Lesezeit und Verfuegbarkeit, damit die Inspector-View
  keine Fachlogik verteilt.
- Neue Tags werden ueber `ArticleMetadataEditor` normalisiert und als globale
  `Tag`-Eintraege wiederverwendet oder neu erstellt.
- Stellt `FlowLayout` modulweit bereit, damit Reader und Inspector dieselbe
  umbruchfaehige Chip-Anordnung verwenden.

### ReaderFontPreset.swift
- Kuratierte Font-Presets fuer die Artikelansicht aus der UI-Referenz:
  System, Geist, Inter, Manrope, DM Sans, Literata, Newsreader, IBM Plex Sans,
  Atkinson Hyperlegible, Source Serif 4, Libre Franklin, Lora, Merriweather,
  Noto Sans, Noto Serif, Roboto Slab, Crimson Pro, Fraunces, Serif
- Kapselt Anzeigenamen, bekannte PostScript-Kandidaten, SwiftUI-Font-Erzeugung und
  Fallback fuer unbekannte gespeicherte Werte
- Custom-Fonts werden per PostScript-Namen angesprochen und als TTF-Dateien in
  `Feedivo/Resources/Fonts/` gebundelt

### ReaderFontRegistry.swift
- Registriert die gebundelten TTF-Dateien beim App-Start via CoreText
- Sucht Fonts zuerst unter `Fonts/` und danach flach im App-Resource-Bundle, weil Xcode
  synchronized groups Ressourcen flach kopieren kann

### ReaderTypography.swift
- Kapselt Defaults und Grenzwerte fuer Reader-Typografie
- Fliesstext-Groesse: Default 17 px, Wertebereich 14...24 px
- Titel-Zeilenabstand: Default 2 px, Wertebereich 0...10 px
- Fliesstext-Zeilenabstand: Default 5 px, Wertebereich 1...12 px
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

### ReaderContentRenderer.swift
- Wandelt HTML-Fragmente oder Plain Text in `ReaderContentBlock`
- Aktuelle Block-Typen: `.paragraph(String)` und `.image(urlString:)`
- Erkennt Absätze, Ueberschriften, Zitate, Listenpunkte und Bildbloecke
- Nutzt `NSAttributedString` HTML-Konvertierung fuer lesbaren Text
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
- `Feedivo/Resources/L10n.swift` bündelt lokalisierte Strings fuer ViewModels,
  Services und Tests
- SwiftUI-Views verwenden lokalisierte `LocalizedStringKey`/`String(localized:)`
- Feed- und Parser-Fehlermeldungen sind lokalisiert
- Benutzer koennen in den Einstellungen `Nach System` oder eine feste Sprache waehlen

---

## Datenmodell (SwiftData)

> **Wichtig für CloudKit:** Alle Properties müssen `Optional` sein ODER einen Default-Wert
> haben — sonst crasht die CloudKit-Synchronisation.
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
    var unreadCount: Int                     // Vorberechneter Sidebar-Zaehler
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
    var feedID: UUID?                        // Direkter Query-Key fuer schnelle Feed-Listen
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
- **Entscheidung:** Artikel werden standardmaessig beim Oeffnen als gelesen markiert.
- **Benutzerkontrolle:** Einstellung `markArticleReadOnSelection` in `SettingsView`
- **Grund:** Entspricht vielen RSS Readern, bleibt aber Geschmackssache und daher abschaltbar.
- **Datum:** 2026-06-19

### ADR-008: i18n via String Catalog
- **Entscheidung:** App-Texte werden ueber `Localizable.xcstrings` lokalisiert.
- **Sprachen:** Deutsch, Englisch, Französisch, Italienisch.
- **Sprachauswahl:** Default `Nach System`; Benutzer koennen in den Einstellungen
  Deutsch, Englisch, Französisch oder Italienisch erzwingen.
- **Grund:** Xcode String Catalog ist der native Weg fuer moderne SwiftUI/macOS Apps
  und skaliert besser als verstreute harte Strings.
- **Datum:** 2026-06-19

### ADR-009: Auto-Refresh mit NSBackgroundActivityScheduler
- **Entscheidung:** Automatischer Feed-Refresh nutzt auf macOS
  `NSBackgroundActivityScheduler`, nicht `BGTaskScheduler`.
- **Grund:** `BGTaskScheduler`, `BGTask` und `BGAppRefreshTaskRequest` sind im
  macOS SDK fuer native macOS Apps als unavailable markiert. `NSBackgroundActivityScheduler`
  ist der passende systemfreundliche Mechanismus fuer periodische Arbeit waehrend die
  App laeuft oder im Hintergrund ist.
- **Einschraenkung:** Eine vollstaendig beendete App wird fuer diese Basis nicht neu
  gestartet; macOS bestimmt den exakten Ausfuehrungszeitpunkt.
- **Datum:** 2026-06-20

---

## Bekannte Gotchas & Fallstricke

> Diese Liste wächst während der Entwicklung. Immer ergänzen!

- **FeedKit Name Collision:** Das SwiftData-Modell `Feed` kollidiert namentlich mit
  `FeedKit.Feed`. Im Service deshalb explizit `FeedKit.Feed(data:)` verwenden.
- **CloudKit + SwiftData:** Alle `@Model`-Properties müssen `Optional` sein ODER einen
  Default-Wert haben — sonst crasht die CloudKit-Synchronisation
- **FeedKit Parsing:** FeedKit 10.4.0 kann direkt mit `FeedKit.Feed(data:)` parsen.
  Download bleibt bei uns über `URLSession` + async/await.
- **Artikelbilder in Feeds:** Nicht nur `enclosure` auswerten. Viele Feeds nutzen
  `media:thumbnail`, `media:content`, `itunes:image` oder ein erstes `<img>` in
  Summary/Content. Bild-URLs koennen relativ sein und muessen gegen die Feed-URL
  normalisiert werden.
- **WordPress-Feeds ohne Item-Bilder:** Manche Feeds, z.B.
  `https://stadt-bremerhaven.de/feed/`, liefern im RSS-Item gar keine Bilder aus.
  Die Bilder stehen nur auf der Artikelseite als `og:image`/`twitter:image`.
  `FeedService.fetchFeed` bleibt deshalb bewusst leichtgewichtig; `FeedViewModel`
  ruft die explizite Artikelbild-Anreicherung nur fuer neue oder noch bildlose
  bestehende Artikel auf. Das vermeidet zusaetzliche Netzwerkrequests fuer bereits
  bekannte Artikel mit Bild.
- **Favicons:** Nicht nur `/favicon.ico` ableiten. Zuerst Website-HTML lesen und
  `<link rel="icon">`, `apple-touch-icon`, `shortcut icon` und `mask-icon` auswerten.
  Relative Icon-URLs muessen gegen die Website-URL normalisiert werden. Wenn HTML
  nicht geladen werden kann, ist `/favicon.ico` der Fallback.
- **Performance bei Feed-Wechsel:** Keine komplette `Feed.articles` Relationship fuer
  Listen oder Sidebar-Zaehler laden. Feed-Listen ueber `Article.feedID` filtern,
  Sidebar-Zaehler aus `Feed.unreadCount` lesen und SwiftUI-Renderpfade nicht mit
  neuen ID-Arrays oder neu kompilierten Regexes belasten.
- **NavigationView ist deprecated:** Immer `NavigationSplitView` oder `NavigationStack`
- **WKWebView in SwiftUI:** Braucht einen `NSViewRepresentable`-Wrapper für macOS
- **Background Refresh macOS:** `BGTaskScheduler`/`BGTask` sind fuer native macOS Apps
  unavailable. Fuer Feedivo deshalb `NSBackgroundActivityScheduler` verwenden. Dieser
  plant systemfreundlich, garantiert aber keinen exakten Zeitpunkt und startet eine
  vollstaendig beendete App nicht neu.
- **macOS Menüleiste:** Commands werden mit `.commands { }` an die WindowGroup gehängt,
  nicht an eine View
- **iCloud Capability:** Muss in Xcode Target → Signing & Capabilities aktiviert sein,
  plus CloudKit Container in developer.apple.com anlegen
- **Sandbox Netzwerk:** Feed-Downloads brauchen `com.apple.security.network.client` in
  `Feedivo/Feedivo.entitlements`. Nur ein Build-Setting reicht nicht als Nachweis.
- **SwiftUI Settings auf macOS:** App-weite Einstellungen als eigene `Settings { }`
  Szene in `FeedivoApp.swift` registrieren; Werte koennen mit `@AppStorage` global
  geteilt werden.
- **Lokalisierung:** Neue sichtbare UI-Texte nicht hart in Views/Services schreiben,
  sondern zuerst als Key in `Localizable.xcstrings` erfassen und bei Bedarf in `L10n.swift`
  zentral bereitstellen.
- **Sprachauswahl:** `AppLanguage.system` muss Default bleiben. Unbekannte gespeicherte
  Werte immer mit `AppLanguage.resolved(from:)` auf `.system` zurueckfallen lassen.
- **UI-Tests lokal:** Am 2026-06-19 blockierte `xcodebuild test` fuer den UI-Test-Runner
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
- [x] ReaderView ausbauen: nativer Artikel-Renderer fuer Absätze, Ueberschriften,
  Zitate, Listenpunkte und Bilder (Basis)
- [x] ArticleRowView: Titel, Datum, gelesen/ungelesen Indikator
- [x] Gelesen/Ungelesen markieren (Basis per Kontextmenue + Auto-gelesen beim Oeffnen)
- [x] Artikel mit Stern markieren (Basis per Button/Kontextmenue)
- [x] i18n Foundation: String Catalog und erste Lokalisierung fuer de/en/fr/it
- [x] Einstellung fuer App-Sprache: Nach System, Deutsch, Englisch, Französisch, Italienisch
- [x] Reader-Typografie: Titel-/Fliesstext-Schriften, Fliesstext-Groesse,
  Titel-/Fliesstext-Zeilenabstand und Artikelbreite
- [x] Tastaturkuerzel: `Cmd+Shift+U` gelesen/ungelesen, `Cmd+D` Stern
- [x] macOS Artikel-Menue fuer gelesen/ungelesen und Stern
- [x] Feed löschen (Rechtsklick und macOS-Menue `Feed`, mit Bestätigung)
- [x] Manueller Refresh fuer ausgewaehlten Feed (`Cmd+R`, macOS-Menue `Feed`)
- [x] macOS Menüleiste: `Cmd+N` = Feed hinzufügen
- [x] Manueller Refresh fuer alle Feeds (`Cmd+Shift+R`, macOS-Menue `Feed`)
- [x] Automatischer Refresh (konfigurierbares Intervall via Settings,
  `NSBackgroundActivityScheduler`)
- [x] Favicons laden und in Sidebar anzeigen
- [x] Smart Filter in Sidebar: Alle Artikel, Ungelesen, Mit Stern, Heute
- [x] Artikel-Link kopieren und Original im Browser öffnen
- [x] Reader-Anzeigemodus: global zwischen nativem Reader und Originalansicht wechseln
- [x] Native Reader Rendering erweitert: Ueberschriften, Zitate und Listenpunkte
- [x] Navigation Vor/Zurueck fuer Artikel innerhalb der aktuell sichtbaren Liste
- [x] Feed Eigenschaften per Rechtsklick: Metadaten, editierbares Refresh-Intervall
  und Feed-Log mit Feed-Header und Statusmetriken als Basis
- [x] Reader-Metadaten-Inspector: Ordner und Artikel-Tags rechts einblendbar und
  dort bearbeitbar; Feedname, Lesezeit und Zeitpunkt bleiben oben im Artikelkopf

### M3 – Tags, Regeln & Sync ✅ ABGESCHLOSSEN
- [x] Ordner fuer Feeds als eigenes Organisationsfeature ausbauen (Basis:
  eine Ebene, Sidebar-Section `Ordner` mit + Button, leere Ordner als `FeedFolder`,
  Feed-Zuordnung editierbar in Feed-Eigenschaften)
- [x] Tag-System ausbauen: Tags mit Farben zentral verwalten ist als Basis umgesetzt
- [x] Sidebar: Abschnitt "Tags" zeigt den Tag-Manager
- [x] Sidebar: Tags filtern Artikel feeduebergreifend
- [x] Feed-Tags ergaenzen: Zuweisung in Feed-Eigenschaften, Tag-Filter umfasst
  Artikel aus getaggten Feeds
- [x] Tag-Zaehler in der Sidebar anzeigen
- [x] Erweiterte/eigene Smart Filter fuer M3 geprueft und bewusst zurueckgestellt:
  bestehende Smart Filter bleiben Alle, Ungelesen, Mit Stern und Heute; eigene Smart
  Filter bleiben im Backlog fuer spaeter.
- [x] `RuleEngine`: Neue Artikel automatisch taggen basierend auf einfachen Regeln
- [x] Regel-UI: Wizard fuer einfache/Power-User-Regeln, Einstellungen-Liste,
  Bearbeiten, Loeschen und Aktivieren/Deaktivieren
- [x] Regel-Mehrfachbedingungen mit AND/OR fuer Power-User-Regeln
- [x] Regeln manuell auf vorhandene Artikel anwenden
- [x] Background Refresh erweitert: macOS-native Strategie bestaetigt,
  Statusanzeige fuer letzten/naechsten automatischen Refresh ergaenzt
- [x] Sichtbarer Fortschritt fuer Sammel-Refresh und OPML-Import
- [x] Offline-Unterstützung: Feed-gelieferten Artikel-Content in SwiftData speichern,
  spaeter gelieferten Content fuer bestehende Artikel nachtragen und Summary-only
  Artikel im Reader kennzeichnen

### M4 – Polish & Release ← AKTUELL
- [x] OPML Import (Feeds aus anderem RSS Reader übernehmen)
- [x] OPML Export (Feeds portieren)
- [ ] iCloud Sync via CloudKit aktivieren und testen
- [x] Erweiterter OPML-Import-Dialog: ausgelesene Feeds und Ordner vor dem Import
  anzeigen, OPML-Datei direkt im selben Dialog auswählen/wechseln,
  Ordnerzugehörigkeit bearbeiten/Ordner erstellen, optionalen Refresh nach Import
  wählen, Duplikate/nicht erreichbare Feeds sichtbar markieren, optionalen
  Duplikat- und Problemfeed-Import erlauben, Statusfilter im Review-Table nutzen
  und Import-Zusammenfassung anzeigen
- [x] Offline Mode Phase 1: Artikel manuell offline speichern/entfernen, Status im
  Reader und in der Artikelliste anzeigen, Feed-Content oder geladene Originalseite
  als `offlineContent` speichern
- [ ] Einstellungen-Fenster final diskutieren und polishen: Struktur, Gewichtung,
  Sync-/Offline-/Cache-Bereiche und macOS-Gefuehl erneut pruefen
- [ ] Vollartikel laden, wenn Feed/Quelle es erlauben; Grundstruktur, Werbung und
  Anbieterlinks fair erhalten und Darstellungsumfang im nativen Reader definieren
- [ ] Theme System/Hell/Dunkel als Settings-Polish
- [x] Bild- und Favicon-Cache: geladene Bilder lokal cachen, damit Artikelbilder
  und Favicons nach App-Neustart nicht jedes Mal neu geladen werden muessen;
  Speicherlimit wird beim App-Start, nach Limit-Aenderung und nach neuen Downloads
  automatisch eingehalten
- [ ] Artikel teilen via macOS Share Sheet
- [ ] App-Icon designen
- [x] Onboarding (erster Start ohne Feeds): Wizard mit Feed hinzufügen,
  OPML-Import, gemeinsamem Review/Statusfilter und Start-Defaults
- [ ] Release-Vorbereitung: App Store oder private Verteilung entscheiden,
  Build/Test/QA abschliessen

---

## GitHub

- **Repo:** https://github.com/martinfelder/feedivo-mac
- **Issues:** GitHub Issues mit Milestones M1–M4
- **Labels:** `feature` `bug` `chore` `ui` `networking` `data` `sync` `tags`
- **Branch-Strategie:** `main` = stabil, `feature/[name]` für neue Features

---

## Offene Entscheidungen

- [x] Reader-Modus global oder pro Artikel speichern? Entscheidung fuer v1: global per
  Einstellung `readerDisplayMode`; spaeter bei Bedarf pro Artikel/Feed pruefen
- [ ] Stern und Archiv getrennt halten oder für v1 nur Stern?
- [x] OPML-Gruppen spaeter als Ordner oder Tags importieren? Entscheidung fuer v1:
  als `Feed.folderName` speichern; sichtbare Ordnerverwaltung ist als Basis umgesetzt.
- [ ] CloudKit Sync-Umfang, insbesondere Artikel-Content und Offline-Content
- [ ] Vollartikel-Laden: Was wird im nativen Reader angezeigt, wenn Feedivo den
  ganzen Artikel von der Quelle laden darf?
- [x] Artikel-Detail: Nativer SwiftUI Reader bleibt Standard, Originalansicht per
  `WKWebView` ist als globaler Reader-Modus verfuegbar.
- [ ] Monetarisierung: Kostenlos / einmaliger Kauf / nie im App Store?

---

## Aktuell in Arbeit

- M1, M2 und M3 sind abgeschlossen.
- Aktuell M4: Polish & Release. iCloud Sync wurde bewusst aus M3 nach M4 verschoben,
  damit Tags, Regeln, Background-Refresh-Status und Offline-Basis als abgeschlossene
  M3-Basis stabil bleiben. M4 umfasst jetzt iCloud Sync, erweiterten OPML-Import,
  manuellen Offline Mode, Settings-Polish, Artikel-Teilen, App-Icon und Release-
  Vorbereitung. Bild-/Favicon-Cache und Onboarding sind als M4-Basis umgesetzt.
- Naechster sinnvoller Fokus: Settings-Fenster gemeinsam neu bewerten und als
  M4-Polish sauber festziehen; danach CloudKit-Sync-Umfang klaeren und Sync
  technisch aktivieren/testen.
- Neuer offener M4/v1-Punkt: Vollartikel laden, wenn moeglich und erlaubt. Dabei
  bleibt Feedivo fair gegenueber Feed-Anbietern: Artikelstruktur, Werbung und
  Anbieterlinks duerfen nicht pauschal entfernt werden; die konkrete Reader-
  Darstellung muss noch gemeinsam definiert werden.
- Feature-Roadmap ist in `FEATURES.md` im Root dokumentiert und muss bei Änderungen
  zusammen mit diesem Projektgedächtnis gepflegt werden

---

## Letzte Änderungen

- 2026-06-24: Feature 22.1 abgeschlossen: Archivieren ist jetzt mit explizitem
  Offline-Content verknuepft, Archiv entfernen loescht nur lokale Offline-Daten
  und setzt `isArchived` zurueck, und `isHidden` wird aus normalen Artikellisten
  ausgeblendet. Die Regel-Aktion zum Ausblenden bleibt Phase 2.
- 2026-06-24: Feature 2.4 als erster Kontextmenue-Slice umgesetzt: Artikelzeilen
  bieten jetzt Archivieren, Tag-Zuweisung, Regel-Erstellung aus Artikel, Teilen,
  Offline speichern/entfernen, Artikel loeschen und alle sichtbaren Artikel als
  gelesen markieren. Exportieren nach PDF/DOCX bleibt bewusst als eigener sauberer
  Restpunkt in Feature 2.4 offen.
- 2026-06-24: Feature 2.5 umgesetzt: Artikel-Listen zeigen ungelesene Artikel
  standardmaessig weiter und blenden gelesene Artikel aus. Ein Button am Listenende
  zeigt die gelesenen Artikel fuer die aktuelle Liste an; ausgewaehlte Artikel
  bleiben sichtbar, wenn sie automatisch als gelesen markiert werden.
- 2026-06-24: Phase 1 fuer Archiv-/Aufraeum-Basis umgesetzt:
  `Article` speichert jetzt `isArchived` und `isHidden` mit Default `false`.
  Die Felder sind bewusst nur Modellgrundlage; UI, Filterlogik und Archivkonzept
  folgen in spaeteren Phasen.
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
- 2026-06-23: User-Entscheidung erfasst: Feedivo soll ganze Artikel laden koennen,
  wenn Feed/Quelle es erlauben. Dabei sollen Grundstruktur, Werbung und Anbieterlinks
  fair erhalten bleiben; offen ist noch, welche geladenen Inhalte der native Reader
  konkret anzeigen soll.
- 2026-06-19: Projekt erstellt, SwiftData Modelle, NavigationSplitView,
  FeedService + FeedViewModel + SidebarView mit AddFeedSheet implementiert
- 2026-06-19: FeedService auf FeedKit 10.4.0 umgesetzt, Feed-Titel aus Metadaten,
  ArticleListView/ReaderView mit echten Daten verbunden, macOS Deployment Target auf 14.0
  korrigiert, Netzwerk-Client-Entitlement aktiviert
- 2026-06-19: Feature-Liste als priorisierte Roadmap in `docs/FEATURES.md`
  dokumentiert; Codex-Arbeitsregeln fuer Session-Start, Verifikation und
  Gedaechtnis-Pflege in `AGENTS.md` ergaenzt
- 2026-06-19: `Feedivo/Feedivo.entitlements` ergaenzt, damit Sandbox-Netzwerkzugriff
  fuer Feed-Downloads explizit als `com.apple.security.network.client` gesetzt ist
- 2026-06-19: ArticleRowView umgesetzt: reichhaltige Artikelzeile mit optionalem Bild,
  Ungelesen-Punkt rechts oben, Stern rechts unten, Kontextmenue fuer gelesen/ungelesen
  und Stern; Auto-gelesen beim Oeffnen ist per Settings-Option konfigurierbar
- 2026-06-19: FeedService liest Artikelbilder robuster aus Media RSS, iTunes Image,
  Bild-Enclosures und HTML-Content; Parser-Tests fuer `media:thumbnail` und
  HTML-`img` ergaenzt
- 2026-06-19: i18n Foundation umgesetzt: String Catalog `Localizable.xcstrings`,
  `L10n.swift`, UI-/Fehlertexte fuer Deutsch, Englisch, Französisch und Italienisch;
  Build und Unit-Tests erfolgreich, UI-Test-Runner lokal durch alte Feedivo-PID blockiert
- 2026-06-19: Sprachauswahl in den Einstellungen ergaenzt: `Nach System` als Default,
  feste Auswahl fuer Deutsch, Englisch, Französisch und Italienisch; Locale wird in
  `FeedivoApp` auf Hauptfenster und Settings angewendet
- 2026-06-19: Nativer Reader-Renderer ergaenzt: `ReaderContentRenderer` wandelt
  HTML/Plain-Text in Absätze und Bildbloecke; `ReaderView` rendert diese Bloecke
  nativ mit SwiftUI statt rohen HTML-/Content-Text anzuzeigen
- 2026-06-19: Artikelbild-Parsing verbessert: Relative Bild-URLs aus HTML und Media RSS
  werden beim Feed-Import gegen die Feed-URL zu absoluten URLs normalisiert, damit
  Artikelliste und Reader die Bilder via `AsyncImage` laden koennen
- 2026-06-19: Reader-Metazeile ergaenzt: Oberhalb des Titels zeigt die Artikelansicht
  Feedname, ungefaehre Lesezeit und Artikelalter; Lesezeit ist testbar und lokalisiert
- 2026-06-19: Reader-Schrift-Presets ergaenzt: Titel- und Fliesstext-Schrift koennen
  direkt im Reader-Popover und in den Einstellungen getrennt gewaehlt werden
- 2026-06-19: Reader-Typografie erweitert: Schriftliste nach UI-Referenz ergaenzt
  sowie Fliesstext-Groesse und Fliesstext-Zeilenabstand als Slider im
  Reader-Popover und in den Einstellungen umgesetzt
- 2026-06-20: Feed-hinzufuegen-Befehl umgesetzt: macOS-Menue `Feed > Feed hinzufügen...`
  mit `Cmd+N` oeffnet dasselbe `AddFeedSheet` wie der Sidebar-Plus-Button
- 2026-06-20: Manueller Refresh fuer alle Feeds umgesetzt: `Cmd+Shift+R` und
  macOS-Menue `Feed > Alle Feeds aktualisieren`; einzelne Feed-Fehler stoppen den
  Gesamtlauf nicht und werden gesammelt gemeldet
- 2026-06-19: Reader-Font-Aufloesung verbessert: Presets nutzen bekannte
  PostScript-Kandidaten und Picker sind explizit Menues.
- 2026-06-19: Reader-Fonts gebundelt: TTF-Dateien fuer die kuratierte Fontliste in
  `Feedivo/Resources/Fonts/` aufgenommen und per `ReaderFontRegistry` beim App-Start
  registriert; Font-Herkunft/Lizenzen in `docs/THIRD_PARTY_FONTS.md`
- 2026-06-19: Reader-Titel-Zeilenabstand ergaenzt: Titel und Fliesstext haben nun
  separate Zeilenabstand-Slider im Reader-Popover und in den Einstellungen
- 2026-06-19: Reader-Artikelbreite ergaenzt: Maximale Artikelbreite kann im
  Reader-Popover und in den Einstellungen zwischen 520...980 px eingestellt werden
- 2026-06-20: Artikel-Commands ergaenzt: macOS-Menue `Artikel`, `Cmd+Shift+U`
  fuer gelesen/ungelesen und `Cmd+D` fuer Stern; Commands nutzen SwiftUI FocusedValues
- 2026-06-20: Feed loeschen als Basis umgesetzt: Rechtsklick in der Sidebar und
  macOS-Menue `Feed`, jeweils mit Bestaetigungsdialog; `FeedViewModelTests`
  pruefen Loeschen und fehlende Auswahl
- 2026-06-20: Manueller Refresh fuer ausgewaehlten Feed umgesetzt: `FeedViewModel`
  aktualisiert Metadaten, `lastRefreshed` und neue Artikel ohne Duplikate; macOS-Menue
  `Feed` bietet `Cmd+R` fuer Feed aktualisieren
- 2026-06-20: Automatischer Refresh als macOS-native Basis umgesetzt:
  `NSBackgroundActivityScheduler` plant periodische Aktualisierungen, Settings bieten
  Ein/Aus und Intervalle 15/30/60/120 Minuten; `BGTaskScheduler` ist fuer native macOS
  unavailable und wird bewusst nicht verwendet
- 2026-06-20: Favicons in der Sidebar umgesetzt: `FaviconService` erkennt Icons per
  HTML Discovery, priorisiert Icon-Kandidaten, faellt auf `/favicon.ico` zurueck und
  `FeedRowView` zeigt gespeicherte Icons mit RSS-Symbol als Fallback
- 2026-06-20: Smart Filter in der Sidebar umgesetzt: Alle Artikel, Ungelesen,
  Mit Stern und Heute nutzen `SidebarSelection` und filtern feeduebergreifend ueber
  alle gespeicherten Artikel
- 2026-06-21: Ungelesen-Zaehler in der Sidebar umgesetzt: Feed-Zeilen zeigen rechts
  die Anzahl ungelesener Artikel, der Smart-Filter `Ungelesen` zeigt die
  feeduebergreifende Summe und aktualisiert ueber `Article.isRead` automatisch mit.
- 2026-06-20: App-weite Oberflaechenschriftgroesse ergaenzt: Einstellungen bieten
  Klein, Standard, Gross und Sehr gross; `InterfaceTextSize` mappt diese Werte auf
  SwiftUI `DynamicTypeSize` und `FeedivoApp` wendet sie auf Hauptfenster und Settings an
- 2026-06-20: Oberflaechenschriftgroesse korrigiert: `InterfaceTextSize` liefert nun
  eigene Skalierungswerte, die Sidebar, Feed-Zeilen, Artikelzeilen und Settings direkt
  fuer konkrete Font-/Icon-/Zeilenmasse verwenden; dadurch ist die Einstellung sichtbar
- 2026-06-20: Smart-Filter-Icons farbig gemacht: Alle Artikel blau, Ungelesen tuerkis,
  Mit Stern gelb und Heute gruen; die Farbzuordnung liegt testbar an `SmartFilter`
- 2026-06-20: Reader-Redesign-Prototyp Design 11 in der echten App umgesetzt:
  linke Sidebar ist dunkel, aktive Auswahl ist dezent, bestehende Smart-Filter-Icons
  bleiben erhalten; Liste und Reader bleiben im bisherigen hellen 3-Spalten-Aufbau
- 2026-06-20: Artikel-Link-Aktionen umgesetzt: Link kopieren und Original öffnen
  sind im Artikel-Kontextmenue, Reader-Toolbar und macOS-Menue `Artikel` verfuegbar
- 2026-06-20: Reader-Titel klickbar gemacht: Klick auf den Artikeltitel oeffnet
  bei gueltigem Originallink den Artikel im Standardbrowser
- 2026-06-20: Reader-Anzeigemodus umgesetzt: globale Einstellung `readerDisplayMode`
  wechselt zwischen nativem SwiftUI-Reader und Originalansicht per `WKWebView`, mit
  Fallback auf den nativen Reader bei fehlendem Originallink
- 2026-06-20: Native Reader Rendering erweitert: `ReaderContentRenderer` erkennt
  Ueberschriften, Zitate und Listenpunkte als eigene Bloecke; `ReaderView` rendert sie
  mit nativer SwiftUI-Darstellung und faellt bei kaputten Inhalten auf Absätze zurueck
- 2026-06-21: Reader-Bildreihenfolge angepasst: Das Artikelbild erscheint im nativen
  Reader immer als erster Content-Block direkt unter dem Titel. `Article.imageURL`
  gewinnt vor HTML-Bildern; fehlt es, wird das erste HTML-`img` nach vorne gezogen.
- 2026-06-21: Reader-Trenner ergaenzt: feiner Querstrich zwischen Lead-Bild und
  erstem Fliesstext.
- 2026-06-21: Ordner und Artikel-Tags wieder direkt im Reader unter dem Titel
  sichtbar gemacht; Bearbeitung bleibt im rechten Artikelinfos-Inspector.
- 2026-06-21: Reader-Metadaten optisch an die App angepasst: Feedname/Lesezeit/Alter
  und Ordner-/Tag-Chips nutzen die App-Oberflaechenschrift statt der Reader-
  Schriftwahl.
- 2026-06-20: Navigation Vor/Zurueck fuer Artikel umgesetzt: Reader-Toolbar und
  macOS-Menue `Artikel` navigieren mit `Cmd+↑`/`Cmd+↓` innerhalb der aktuell
  sichtbaren Feed- oder Smart-Filter-Liste und stoppen am Listenrand
- 2026-06-20: Feed Eigenschaften umgesetzt: Rechtsklick auf Feed oeffnet ein
  lokalisiertes Sheet mit Feed-Metadaten, editierbarem Aktualisierungsintervall,
  naechstem Abruf, letztem Artikel und den neuesten 20 Feed-Log-Eintraegen; Feed-Adds
  und Refresh-Erfolge/-Fehler werden in SwiftData protokolliert
- 2026-06-20: Feed umbenennen umgesetzt: Rechtsklick auf Feed oeffnet ein eigenes
  Sheet fuer den Anzeigenamen; der urspruengliche Feed-Name wird in `Feed.originalTitle`
  gespeichert und kann wiederhergestellt werden, Refresh ueberschreibt manuelle Namen nicht
- 2026-06-20: Feed-Eigenschaften-Sheet ergaenzt: Neben der XML-Adresse gibt es einen
  Icon-Button, der die XML-Adresse in die macOS-Zwischenablage kopiert
- 2026-06-21: Feed-Eigenschaften-Sheet ergaenzt: Website- und XML-Adresse werden bei
  gueltigen `http`/`https`-URLs als anklickbare Links im Standardbrowser geoeffnet
- 2026-06-20: Feed-Eigenschaften-Sheet visuell ueberarbeitet: grosser Feed-Header
  mit Icon/Favicon-Fallback und Statusmetriken, gruppierte Detailansicht,
  abgesetzter Aktualisierungsblock und kompakter Feed-Log-Verlauf
- 2026-06-20: Artikelbild-Fallback fuer Feeds ohne Item-Bilder umgesetzt:
  Feedivo kann bei fehlendem Bild die Artikelseite lesen und `og:image`/
  `twitter:image` uebernehmen; Refresh fuellt fehlende `Article.imageURL` Werte bei
  bereits gespeicherten Artikeln nach
- 2026-06-21: P1-Performance umgesetzt: `FeedService.fetchFeed` laedt keine
  Artikelseiten mehr automatisch; `FeedViewModel` reichert Seitenbilder nur noch fuer
  neue oder bildlose bestehende Artikel an. Smart-Filter nutzen gezielte SwiftData-
  Queries; Sidebar-Ungelesen-Badges wurden spaeter auf gespeicherte `Feed.unreadCount`
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
  Ordners werden in der Sidebar eingerueckt, und neu importierte OPML-Feeds werden
  direkt nach dem Import ueber den normalen Refresh-Kern aktualisiert.
- 2026-06-20: Sidebar-Ordner aufklappbar gemacht: Ordnerzeilen haben einen Chevron,
  bleiben standardmaessig geoeffnet und klappen ihre eingerueckten Feeds per Klick
  ein oder aus.
- 2026-06-20: Interaktive Artikel-Reader-Prototypen erstellt:
  `docs/design/article-reader-prototypes/index.html` zeigt zehn moegliche
  Reader-Darstellungen fuer die spaetere Ueberarbeitung der Artikelansicht.
- 2026-06-21: Reduzierte Step-by-Step-Reader-Prototypen ergaenzt:
  `docs/design/article-reader-minimal-step/index.html` fokussiert auf drei ruhige
  Varianten fuer die Positionierung von Feedname, Lesezeit, Ordner und Tags:
  Meta oben, Meta nach Titel und Meta kompakt.
- 2026-06-21: Minimal-Reader-Prototyp verfeinert: Ordner und Tags wurden aus dem
  Artikelkopf entfernt und liegen jetzt in einem einblendbaren rechten Inspector,
  in dem Ordner und Tags bearbeitet werden koennen.
- 2026-06-21: Reader-Metadaten-Inspector in der App umgesetzt: Feedname, Lesezeit
  und Zeitpunkt bleiben oben im Artikelkopf; Ordner und Artikel-Tags werden rechts
  eingeblendet und koennen dort bearbeitet werden.
- 2026-06-21: Reader-Darstellung ruhiger gesetzt: kleinerer semibold Titel,
  groessere redaktionelle Abstaende, kontrolliertes Lead-Bild, dezenter Original-Link
  im Footer und `Link kopieren` ins Reader-Mehr-Menue verschoben.
- 2026-06-21: Reader-Performance verbessert: Teure Reader-Daten werden pro Artikel
  ueber `ReaderPreparedArticle` vorbereitet und grosse Bilder wieder mit leichterem
  `scaledToFit` statt Zuschnitt gerendert.
- 2026-06-21: Artikel-/Reader-Performance nachgezogen: `ContentView` beobachtet
  nicht mehr pauschal alle Artikel; Feed-Listen vermeiden globale Artikel-Queries
  und die Reader-Navigation nutzt `ArticleNavigationState` mit der bereits sortierten
  sichtbaren Artikelliste.
- 2026-06-21: Feed-Wechsel-Performance verbessert: `Article.feedID` ersetzt das
  Relationship-Predicate fuer Feed-Listen, `ContentView` speichert nur noch
  vorherigen/naechsten Artikel statt der sichtbaren Artikelliste, und Sidebar-Badges
  lesen `Feed.unreadCount` statt alle ungelesenen Artikel zu materialisieren. Alte
  Datensaetze werden beim App-Start per Backfill nachgezogen.
- 2026-06-21: Weitere Performance-Optimierungen nachgefuehrt: Feed-/Favicon-Regexes
  werden statisch gecacht, `refreshAllFeeds` und der OPML-Nachimport aktualisieren
  Feeds parallel per `withTaskGroup`, `ArticleListView` nutzt `.onChange(of: articles)`
  statt eines pro Render neu erzeugten ID-Arrays, und `FeedUnreadCountBackfillService`
  laeuft per UserDefaults-Flag `feedUnreadCountBackfillDone_v1` nur einmal.
- 2026-06-21: Reader-Inspector-Layout korrigiert: Bei geoeffnetem Artikelinfos-Panel
  fuellt der Reader-Bereich die verbleibende Detailbreite, damit rechts neben dem
  Inspector keine leere weisse Restflaeche bleibt.
- 2026-06-21: M2 offiziell abgeschlossen und aktiven Milestone auf M3 Tags, Regeln
  und Sync umgestellt; naechster Fokus ist Tag-Verwaltung, Tag-Sidebar und danach
  automatische Regeln.
- 2026-06-21: Tag-Manager in der Sidebar verdrahtet: Die neue Section `Tags` oeffnet
  das zentrale Tag-Verwaltungs-Sheet; die eigentliche Tag-Filterung wurde danach als
  eigener M3-Schritt umgesetzt.
- 2026-06-21: Sidebar-Tag-Filter umgesetzt: Tags erscheinen als klickbare Zeilen mit
  Farbindikator und filtern `ArticleListView` ueber eine gezielte SwiftData-Query auf
  `Article.tags`; Feed-Tags und Regeln wurden danach als separate M3-Schritte
  umgesetzt.
- 2026-06-21: Tag-Erstellung verfeinert: Neue Tags werden nach dem Anlegen direkt in
  der Sidebar als aktueller Tag-Filter ausgewaehlt, damit sie sofort sichtbar und
  schnell nutzbar sind.
- 2026-06-21: Sidebar-Tag-Zaehler umgesetzt: Tags zeigen rechts eine dezente Badge
  mit der Anzahl passender Artikel.
- 2026-06-21: Feed-Tags umgesetzt: Tags koennen in den Feed-Eigenschaften an Feeds
  gehaengt werden; Sidebar-Tag-Filter und Tag-Badges beruecksichtigen direkt
  getaggte Artikel sowie Artikel aus getaggten Feeds ohne Duplikate.
- 2026-06-21: Rechter Artikelinfos-Inspector erweitert: Vorhandene globale Tags, die
  dem Artikel noch nicht zugewiesen sind, erscheinen nun als Plus-Chips und koennen
  direkt angeklickt werden.
- 2026-06-21: Erste RuleEngine-Basis umgesetzt: Neue Artikel werden beim Refresh
  anhand einfacher Regeln (`title`/`summary`/`feedTitle` plus `contains`/
  `startsWith`/`endsWith`) automatisch getaggt; Rule-UI, Regex und
  Mehrfachbedingungen bleiben offen.
- 2026-06-21: Rueckwirkendes Anwenden von Regeln umgesetzt: In den Einstellungen
  koennen aktive Regeln manuell auf vorhandene Artikel angewendet werden; bereits
  gesetzte Tags werden nicht dupliziert.
- 2026-06-21: Background Refresh M3 erweitert: Feedivo bleibt bei
  `NSBackgroundActivityScheduler`, speichert letzten automatischen Lauf, Status,
  optionale Fehlermeldung und naechsten geschaetzten Lauf und zeigt diese Werte in
  den Einstellungen.
- 2026-06-21: Sichtbaren Fortschritt fuer Sammel-Refresh und OPML-Import umgesetzt:
  `FeedViewModel.operationProgress` zaehlt abgeschlossene Feeds und `ContentView`
  zeigt waehrend laengerer Feed-Operationen ein kompaktes Fortschritts-Overlay.
- 2026-06-21: Regel-Wizard und Regelverwaltung umgesetzt: Regeln werden in den
  Einstellungen gelistet, koennen dort erstellt, bearbeitet, geloescht und
  aktiviert/deaktiviert werden. Der Wizard bietet einfache Regeln oder
  Power-User-Regeln mit mehreren Bedingungen und AND/OR. In der Sidebar werden
  Regeln bewusst nur kompakt mit aktivem Zaehler und einem Link `Regel aus Artikel
  erstellen...` fuer den aktuell ausgewaehlten Artikel angezeigt.
- 2026-06-21: Regel-Wizard um Live-Preview erweitert: Feedivo zaehlt vorhandene
  Artikel, die zu den aktuellen Bedingungen passen wuerden, und verwendet dafuer
  dieselbe Matching-Logik wie die echte RuleEngine ohne Tags zu setzen.
- 2026-06-21: Glass-Design-Prototypen fuer den rechten Artikelinfos-Inspector
  erstellt: `docs/design/article-info-glass-sidebar-prototypes/index.html` zeigt
  fuenf konkrete Varianten, wie die Seitenleiste an eine moderne macOS-Glass-
  Oberflaeche angepasst werden kann.
- 2026-06-21: Glass-Prototyp Variante A wurde kurzzeitig fuer den rechten
  Artikelinfos-Inspector umgesetzt und spaeter durch die native macOS-Inspector-
  Spalte im hellen Sidebar-Stil ersetzt.
- 2026-06-21: Native Reader-Scrollbar ausgeblendet, damit der Artikelbereich
  fliessender in die rechte Inspector-Leiste uebergeht.
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
  Mehrfachauswahl und Loeschen ausgewaehlter Feeds mit Bestaetigungsdialog.
- 2026-06-22: Settings-Feedverwaltung korrigiert: Das macOS-Settings-Scene bekommt
  nun denselben SwiftData-`modelContainer` wie das Hauptfenster, damit abonnierte
  Feeds in den Einstellungen per `@Query` sichtbar sind.
- 2026-06-22: Bild- und Favicon-Caching als M4-Thema aufgenommen. Empfehlung:
  eigener Disk-Cache plus kleiner Memory-Cache fuer Artikelbilder und Favicons,
  keine Bild-BLOBs in SwiftData.
- 2026-06-22: Erweiterter OPML-Import-Dialog als M4-Thema aufgenommen: Import soll
  Feeds/Ordner vorab zeigen, Ordnerzuweisung und neue Ordner erlauben, optionalen
  Feed-Refresh anbieten und nach dem Import eine Zusammenfassung anzeigen.
- 2026-06-22: M3-Offline-Basis umgesetzt: Feedivo speichert Feed-gelieferten
  Artikel-Content weiter in SwiftData und traegt spaeter gelieferten Volltext fuer
  bestehende Artikel nach.
- 2026-06-22: iCloud Sync bewusst von M3 nach M4 verschoben. M3 gilt damit als
  abgeschlossen; M4 ist nun der aktive Milestone fuer Polish, Sync und Release-
  Vorbereitung.
- 2026-06-22: Letzten offenen M3-Restpunkt abgeschlossen: Erweiterte/eigene Smart
  Filter wurden fuer M3 geprueft und bewusst auf spaeter verschoben. M3 bleibt damit
  vollstaendig abgeschlossen.
- 2026-06-22: Fuenf interaktive Prototypen fuer den erweiterten OPML-Import-Dialog
  erstellt: `docs/design/opml-import-dialog-prototypes/index.html` zeigt Review
  Table, Guided Wizard, Split Inspector, Batch Editor und Import Center.
- 2026-06-22: OPML-Import-Prototyp Variante A erweitert: Die Datei-Auswahl ist nun
  Teil desselben Dialogs; danach folgen Preview, Ordnerbearbeitung, optionale
  Aktualisierung und Zusammenfassung in einem durchgehenden Sheet.
- 2026-06-22: OPML-Import-Prototyp Variante A interaktiv gemacht: Ausgewaehlte
  OPML-Dateien werden lokal gelesen, Feed-Outlines dynamisch in der Review-Tabelle
  angezeigt, Duplikate und nicht erreichbare/problematische Feeds markiert und nur
  ausgewaehlte importierbare Feeds in der Zusammenfassung gezaehlt.
- 2026-06-22: OPML-Import-Prototyp Variante A fuer grosse Imports verfeinert:
  Die Feed-Tabelle scrollt intern, damit das Dialogfenster nicht mitwaechst; lange
  Feednamen und URLs werden einzeilig mit Ellipsis gekuerzt.
- 2026-06-22: OPML-Import-Prototyp Variante A um Option `Duplikate importieren`
  erweitert. Standardmaessig bleiben Duplikate uebersprungen; aktiviert der
  Benutzer die Option, werden ausgewaehlte Duplikat-Zeilen in der Import-Anzahl und
  Zusammenfassung mitgezaehlt.
- 2026-06-22: Erweiterter OPML-Import-Dialog in der App umgesetzt:
  `OPMLImportReviewView` ersetzt den direkten Dateiimport durch Datei-Auswahl im
  Dialog, dynamische Feed-Pruefung, Auswahl einzelner Feeds, Ordnerzuordnung,
  Ordneranlage, optionalen Refresh, optionalen Duplikat- und Problemfeed-Import
  und sichtbare Import-Zusammenfassung.
- 2026-06-22: `OPMLImportReviewView` visuell naeher an Prototyp Variante A
  nachgezogen: macOS-Sheet-Container, ruhiger Header mit Status-Badge, Datei-Kachel,
  Toolbar im Review-Table-Stil, feste Tabellenspalten, kompakte Status-Pills und
  Footer-Optionen im gleichen Layout wie der HTML-Prototyp.
- 2026-06-22: Statusfilter im OPML-Import-Dialog ergaenzt: Dropdown fuer alle, neue,
  doppelte und nicht erreichbare Feeds; der Filter arbeitet nur auf sichtbaren IDs,
  damit Auswahl- und Ordner-Mutationen beim Entfernen des Filters erhalten bleiben.
- 2026-06-22: OPML-Import-Preview mit konkretem Prueffortschritt verbessert:
  `FeedViewModel.opmlImportPreviewRows` kann Fortschritt pro Feed melden, und
  `OPMLImportReviewView` zeigt diesen Zustand horizontal und vertikal zentriert in
  der spaeteren Feed-Tabelle.
- 2026-06-22: OPML-Import-Dialog erweitert: Nicht erreichbare Feeds bleiben
  standardmaessig abgewählt, koennen aber ueber eine eigene Checkbox bewusst
  ausgewaehlt und importiert werden.
- 2026-06-22: OPML-Import-Dialog um Drag & Drop erweitert: `.opml`- und `.xml`-
  Dateien koennen direkt auf das Importfenster gezogen werden und starten dieselbe
  Preview wie die manuelle Datei-Auswahl.
- 2026-06-23: First-Run-Wizard nach Prototyp Variante A umgesetzt: Bei leerem
  Feedbestand zeigt Feedivo einen Wizard mit Auswahl zwischen einzelner Feed-URL,
  OPML-Import oder spaeterem Einrichten. Feed- und OPML-Pfad nutzen denselben
  Review-Flow wie der erweiterte OPML-Import inklusive Statusfilter, Ordnern,
  Duplikat-/Problemfeed-Optionen, optionalem Refresh und Start-Defaults.
- 2026-06-23: First-Run-Wizard-Abschlussflow verfeinert: Die Feed-Liste bleibt im
  Import-/Pruefschritt, die Review zeigt nur eine Zusammenfassung mit Link zurueck,
  und der Fertig-Screen bleibt nach dem Import sichtbar, bis der Benutzer aktiv
  `Starten` drueckt. Importierte Feeds, verwendete Ordner und Hinweise zu
  Duplikaten, nicht erreichbaren Feeds oder Refresh-/Speicherproblemen werden dort
  angezeigt.
- 2026-06-23: First-Run-Wizard-Schliesslogik korrigiert: Ein sichtbarer Wizard wird
  nicht mehr automatisch geschlossen, wenn nach `Import starten` Feeds angelegt
  werden und `firstRunWizard.completed` aus einem frueheren Lauf bereits true ist.
- 2026-06-23: First-Run-Wizard-Copy geschaerft: Sichtbare Texte erklaeren nun
  direkt, was der Benutzer einstellt, sieht und mit dem naechsten Schritt ausloest.
  Prototyp-/Implementierungsbegriffe wie `Review`, `Defaults` und `Import-Engine`
  wurden aus der UI entfernt.
- 2026-06-23: Offline-Begriffe geschaerft: Cache, normal gespeicherter Feed-Inhalt
  und bewusste Offline-Kopien sind nun in UI und Settings getrennt. Die neue
  Settings-Rubrik `Offline-Lesen` erklaert den manuellen Artikel-Flow und haelt
  Offline-Automatik als spaeteren M4-Folgepunkt sichtbar zurueck.
- 2026-06-23: Reader-Summary-Hinweis entfernt: Artikel ohne Feed-Volltext zeigen
  die vorhandene Feed-Zusammenfassung direkt ohne zusaetzliche Hinweisbox. Der
  interne Reader-Zustand heisst `contentAvailability`, damit normaler Feed-Inhalt
  und bewusste Offline-Kopien getrennt bleiben.
- 2026-06-23: Fensterweiter Online-/Offline-Indikator ergaenzt: `ContentView`
  beobachtet den Netzwerkpfad per `NWPathMonitor` und zeigt unten rechts Online
  oder Offline an. Der Status beschreibt nur die aktuelle Netzwerkverbindung, nicht
  den Artikel-Offline-Speicher.
- 2026-06-23: Rechten Artikelinfos-Inspector zunaechst nach Product-Design-
  Variante 3 `Editorial Companion` umgebaut; spaeter am selben Tag wurde die
  interaktive Variante 1 `Calm Actions` als aktuelle SwiftUI-Richtung umgesetzt.
  Die Anzeigeaufbereitung liegt weiter in `ArticleInspectorFormatter`.
- 2026-06-23: Typografie der rechten Artikelinfos-Seitenleiste verkleinert und in
  `ArticleInspectorTypography` zentralisiert, damit die Sidebar weniger dominant
  wirkt und besser zum ruhigen Reader passt. Die Skala ist nun auf 11 pt
  Labels/Chips, 11.5 pt Controls, 12 pt Werte, 13 pt Section-Titel und 15 pt
  Artikelkopf vereinheitlicht.
- 2026-06-23: Drei neue interaktive Product-Design-Prototypen fuer eine ruhigere
  und bedienbarere rechte Artikelinfos-Seitenleiste erstellt:
  `docs/design/article-info-interactive-sidebar-prototypes/` enthaelt die Varianten
  `Calm Actions`, `Section Studio` und `Command Inspector` mit klickbarem Status,
  Favorit, Offline, Tags, Ordner, Link-Kopieren sowie Tag-Erstellung mit
  Farbauswahl. Die Ordnerauswahl wurde im Prototyp als `Feed-Ordner` gekennzeichnet,
  damit klar ist, dass sie den Feed und nicht nur den Artikel betrifft; ausserdem
  koennen neue Feed-Ordner direkt aus dem Inspector-Prototyp angelegt werden.
  Feed-Ordner und Tags wurden als eigene Sections getrennt, damit Feed-Eigenschaften
  und Artikel-Tags nicht vermischt werden.
- 2026-06-23: Prototyp-Variante 1 `Calm Actions` in der echten SwiftUI-
  Inspector-Seitenleiste nachgeschaerft: kompakter Kopf mit Titel und Status-Strip,
  obere Aktionsleiste fuer Favorit, Gelesen/Ungelesen, Offline und Link-Kopieren,
  einklappbare weisse Karten-Sections fuer Feed-Ordner, Tags, Kontext und Quelle.
  Die Quelle ist als reine Zwei-Button-Section fuer Link-Kopieren und
  Original-Oeffnen ohne URL-Textbox umgesetzt.
  Die Section-Header nutzen wie der Prototyp nur Chevron und Titel; Tags
  sind eine gemeinsame Toggle-Pill-Liste statt getrennten aktuellen/verfuegbaren
  Chips. Neue Feed-Ordner koennen direkt angelegt werden, neue Tags koennen beim
  Anlegen eine Farbe bekommen.
- 2026-06-23: Cache Mode vervollstaendigt: `ImageCacheService` raeumt nach
  erfolgreichen Bilddownloads automatisch auf das eingestellte Speicherlimit auf;
  `FeedivoApp` wendet dasselbe Limit beim App-Start an. Cache bleibt bewusst ein
  Performance-Cache, echte automatische Offline-Pakete bleiben ein separater
  M4-Folgepunkt.
- 2026-06-22: Offline Mode Phase 1 umgesetzt: Artikel koennen im Reader manuell
  offline gespeichert oder wieder entfernt werden. Vorhandener Feed-Volltext kann
  dafuer als manuelle Offline-Kopie genutzt werden; falls kein Feed-Content
  vorhanden ist, wird die Original-URL geladen und in `Article.offlineContent`
  gespeichert. Reader und Artikelliste zeigen Offline-Status beziehungsweise Fehler
  sichtbar an.
