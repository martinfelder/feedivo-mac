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
**Aktueller Milestone:** M2 – Core Features

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
2. Falls vorhanden `docs/FEATURES.md` lesen, wenn es um Planung, Roadmap oder Features geht.
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
2. `docs/FEATURES.md`:
   - Feature-Status
   - Prioritaet
   - offene Entscheidungen
   - Empfehlungen oder bewusst zurueckgestellte Punkte
3. Tests/Build:
   - Vor Abschluss mindestens den passenden `xcodebuild`-Befehl laufen lassen.
   - In der finalen Antwort exakt nennen, was geprueft wurde und ob es erfolgreich war.

### Dokumentationsprinzip

- Entscheidungen kurz begruenden, besonders wenn Features verschoben oder vereinfacht werden.
- Keine Roadmap stillschweigend aendern. Immer in `AGENTS.md` und/oder `docs/FEATURES.md` nachfuehren.
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
| iCloud Sync | CloudKit via SwiftData | `isCloudKitEnabled: true` — noch nicht aktiviert |
| Netzwerk | URLSession + async/await | Kein Alamofire, kein Combine |
| RSS-Parsing | FeedKit | Swift Package, URL: https://github.com/nmdias/FeedKit |
| Bilder | AsyncImage | Built-in SwiftUI, kein Kingfisher |
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
│   │   └── Rule.swift
│   │
│   ├── ViewModels/
│   │   ├── FeedViewModel.swift         # Feed hinzufügen, aktualisieren, loeschen ✅
│   │   ├── ArticleViewModel.swift      # Artikel gelesen/ungelesen und Stern toggeln ✅
│   │   ├── ArticleMetadataEditor.swift # Artikel-Ordner und Tags bearbeiten ✅
│   │   ├── TagViewModel.swift          # Tags verwalten (TODO)
│   │   ├── RuleEngineViewModel.swift   # Regeln auswerten und Tags auto-zuweisen (TODO)
│   │   └── SyncViewModel.swift         # iCloud Sync Status anzeigen (TODO)
│   │
│   ├── Views/
│   │   ├── ContentView.swift           # Root: NavigationSplitView (3 Spalten) ✅
│   │   ├── Sidebar/
│   │   │   ├── SidebarView.swift       # Dunkle linke Spalte: Filter, Feeds, + Button, @Query ✅
│   │   │   ├── SidebarStyle.swift      # Farb-/Auswahlwerte fuer dunkle Sidebar ✅
│   │   │   ├── FeedFolderOrganizer.swift # Einfache Ordner-Gruppierung fuer Feeds ✅
│   │   │   ├── FeedRowView.swift       # Feed-Zeile mit Favicon/Fallback ✅
│   │   │   ├── FeedPropertiesView.swift # Feed-Eigenschaften-Sheet ✅
│   │   │   ├── FeedRenameView.swift    # Feed-Anzeigename bearbeiten ✅
│   │   │   ├── FeedPropertiesFormatter.swift # Helper fuer Eigenschaften ✅
│   │   │   └── TagRowView.swift        # Eine Tag-Zeile in der Sidebar (TODO)
│   │   ├── ArticleList/
│   │   │   ├── ArticleListView.swift   # Mittlere Spalte: echte Feed-Artikel anzeigen ✅
│   │   │   └── ArticleRowView.swift    # Reichhaltige Artikel-Zeile mit Status/Stern ✅
│   │   ├── Reader/
│   │   │   ├── ReaderView.swift        # Rechte Spalte: nativer Artikel-Reader ✅
│   │   │   ├── ArticleMetadataInspectorView.swift # Rechter Artikelinfos-Inspector ✅
│   │   │   ├── ReaderContentRenderer.swift # HTML/Text zu Reader-Bloecken ✅
│   │   │   ├── ReaderMetadataFormatter.swift # Feedname/Lesezeit/Alter ✅
│   │   │   ├── ReaderFontPreset.swift  # Schrift-Presets fuer Reader ✅
│   │   │   ├── ReaderFontRegistry.swift # Gebundelte Fonts registrieren ✅
│   │   │   ├── ReaderTypography.swift  # Textgroesse/Zeilenabstand Defaults ✅
│   │   │   └── WebContentView.swift    # WKWebView-Wrapper für volle Artikel (TODO)
│   │   ├── Tags/
│   │   │   ├── TagManagerView.swift    # Tags erstellen, bearbeiten, löschen (TODO)
│   │   │   └── AddTagView.swift        # Sheet: neuen Tag erstellen (TODO)
│   │   ├── Rules/
│   │   │   ├── RuleListView.swift      # Alle Regeln anzeigen und verwalten (TODO)
│   │   │   └── AddRuleView.swift       # Sheet: neue Regel erstellen (TODO)
│   │   └── Settings/
│   │       └── SettingsView.swift      # Lesen, Sprache und Auto-Refresh ✅
│   │
│   ├── Services/
│   │   ├── FeedService.swift           # FeedKit-Wrapper: RSS/Atom/JSON Feed parsen ✅
│   │   ├── FaviconService.swift        # HTML Favicon Discovery + Fallback ✅
│   │   ├── BackgroundRefreshSettings.swift # Auto-Refresh Settings/Intervalle ✅
│   │   ├── BackgroundRefreshService.swift  # NSBackgroundActivityScheduler Adapter ✅
│   │   ├── FeedRefreshService.swift    # Alle Feeds abrufen (async, mit Fortschritt) (TODO)
│   │   ├── RuleEngine.swift            # Regeln auf neue Artikel anwenden (TODO)
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
│       ├── L10n.swift                  # Zentraler Zugriff auf lokalisierte Strings ✅
│       └── AGENTS.md                   # Diese Datei
│
├── Feedivo.xcodeproj
├── docs/
│   └── FEATURES.md                     # Produkt-Roadmap, priorisierter Feature-Backlog ✅
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
            Rule.self
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

### SidebarView.swift
- `@Query(sort: \Feed.title)` für automatische Feed-Liste aus SwiftData
- Dunkle, eigene SwiftUI-Sidebar statt Standard-`List`, damit Design 11 aus dem
  Prototyp umgesetzt ist: dunkle linke Spalte, dezente aktive Auswahl und ruhige
  Feed-/Filterzeilen
- Header mit + Button → oeffnet zentral praesentiertes `AddFeedSheet`
- `AddFeedSheet` ist eine separate Struct in derselben Datei
- Ruft `FeedViewModel.addFeed()` auf
- Kontextmenue pro Feed ruft das Feed-Loeschen mit Bestaetigung an
- Kontextmenue pro Feed oeffnet `Feed Eigenschaften...` mit Metadaten, Intervall
  und Feed-Log
- Smart-Filter behalten die bestehenden SF-Symbol-Icons (`tray.full`, `circle.fill`,
  `star.fill`, `calendar`) und ihre Farben; nur die Sidebar-Oberflaeche ist dunkler
- Feeds stehen in einer Sidebar-Section `Ordner`; neben dem Section-Titel gibt es
  einen + Button zum Anlegen neuer Ordner
- Ordner sind per Chevron auf- und zuklappbar; Feeds innerhalb eines Ordners werden
  eingerueckt angezeigt, damit die Hierarchie in der dunklen Sidebar klarer lesbar ist
- Angelegte/leere Ordner werden als `FeedFolder` gespeichert; die Zuordnung eines
  Feeds zu einem Ordner bleibt fuer v1 ueber `Feed.folderName`
- Ordner sind fuer v1 eine Ebene tief; noch kein Drag & Drop

### FeedRowView.swift
- Zeigt Feed-Titel mit kleinem Favicon aus `Feed.faviconURL`
- Nutzt `AsyncImage` fuer remote Icons
- Fallback ist das RSS-Systemsymbol, wenn kein Icon vorhanden ist oder das Laden scheitert

### FeedService.swift
- Parsed RSS 2.0, Atom und JSON Feed via FeedKit
- Nutzt FeedKit `Feed(data:)` für Parsing und `URLSession` + async/await für Download
- Gibt `ParsedFeed` mit Feed-Metadaten und `[ParsedArticle]` zurück
- Feed-Titel wird aus Metadaten gelesen, mit URL als Fallback
- Website-URL fuer Favicon Discovery wird aus Feed-Metadaten gelesen:
  RSS `channel.link`, Atom `alternate` Link, JSON Feed `home_page_url`
- Artikelbilder werden aus Media RSS, iTunes Image, Bild-Enclosures und erstem
  `<img>` in Content/Summary gelesen
- Wenn Feed-Items kein eigenes Bild enthalten, versucht `fetchFeed` als Fallback die
  verlinkte Artikelseite zu lesen und `og:image`/`twitter:image` zu uebernehmen
- Relative Artikelbild-URLs werden gegen die Feed-URL zu absoluten URLs aufgeloest,
  damit `AsyncImage` sie laden kann
- Eigene `FeedServiceError` enum: `.invalidURL`, `.parsingFailed`

### FeedViewModel.swift
- `@Observable` class
- `addFeed(urlString:context:)` — lädt Artikel, erstellt Feed, speichert in SwiftData
- Beim Hinzufuegen und Aktualisieren wird `FaviconService` genutzt, um `Feed.faviconURL`
  aus Website-HTML oder `/favicon.ico` Fallback zu speichern
- `refreshFeed(_:context:)` — aktualisiert den ausgewaehlten Feed, fuegt nur neue
  Artikel hinzu und aktualisiert Feed-Metadaten sowie `lastRefreshed`
- Beim Hinzufuegen werden `siteURL`, `followedAt` und ein Info-Log geschrieben
- Beim Aktualisieren werden Erfolg/Fehler als `FeedLogEntry` protokolliert; pro Feed
  bleiben die neuesten 20 Log-Eintraege erhalten
- `refreshAllFeeds(_:context:)` — aktualisiert alle gespeicherten Feeds nacheinander,
  laeuft bei einzelnen Fehlern weiter und meldet am Ende betroffene Feednamen
- `deleteFeed(_:context:)` — loescht einen Feed aus SwiftData; Artikel werden ueber
  die Cascade-Relationship mitgeloescht
- `renameFeed(_:displayTitle:context:)` — speichert einen benutzerdefinierten
  Anzeigenamen, ohne den urspruenglichen Feed-Namen zu verlieren
- `restoreOriginalFeedTitle(_:context:)` — setzt den Anzeigenamen wieder auf den
  gespeicherten Originalnamen zurueck
- Beim Refresh wird `Feed.originalTitle` mit dem Feed-Metadaten-Titel aktualisiert;
  ein benutzerdefinierter `Feed.title` bleibt erhalten
- Der Feed-Fetch ist als Closure injizierbar, damit Refresh-Tests ohne Netzwerk laufen
- Die Favicon-Discovery ist als Closure injizierbar, damit Tests ohne Netzwerk laufen
- Properties: `isLoading: Bool`, `errorMessage: String?`

### FaviconService.swift
- Laedt die Website-HTML-Seite eines Feeds und sucht `<link rel="...icon...">`
- Unterstuetzt `icon`, `shortcut icon`, `apple-touch-icon` und `mask-icon`
- Normalisiert relative und protokollrelative Icon-URLs zu absoluten URLs
- Priorisiert Apple-Touch-Icons und groessere `sizes` Werte vor einfachen Icons
- Fallback: Wenn HTML nicht geladen oder kein Icon gefunden wird, nutzt Feedivo
  `/favicon.ico` auf der Website-Root
- Keine externe Google-S2-API; die Favicon-Strategie bleibt eigenstaendig und
  datensparsamer

### FeedPropertiesView.swift / FeedPropertiesFormatter.swift
- Rechtsklick auf Feed → `Feed Eigenschaften...`
- Sheet nutzt einen Feed-Header mit Icon/Favicon-Fallback, Website und Statusmetriken
  fuer Aktualisierungsintervall, naechsten Abruf und sichtbare Log-Eintraege
- Darunter zeigt es gruppiert Originaltitel, Website, XML-Adresse mit Kopierbutton,
  Gefolgt-ab-Datum, editierbaren Ordner, letzten Artikel, Aktualisierungsintervall,
  naechsten Abruf, zuletzt aktualisiert und die neuesten 20 Feed-Log-Eintraege
- Aktualisierungsintervall ist direkt im Sheet editierbar und wird in SwiftData gespeichert
- Der Ordnername ist direkt im Sheet editierbar; leere Eingaben werden als `nil`
  gespeichert
- `FeedPropertiesFormatter` kapselt naechsten Abruf, neuesten Artikel, Log-Limit und
  die sichtbare Log-Anzahl, damit diese Logik ohne UI testbar bleibt

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
  Intervalle: 15, 30, 60 oder 120 Minuten.
- `BackgroundRefreshService.scheduleNextRefresh(...)` plant oder storniert den
  Auto-Refresh testbar ueber ein kleines Scheduler-Protokoll.
- `SystemBackgroundActivityRefreshScheduler` nutzt `NSBackgroundActivityScheduler`,
  weil `BGTaskScheduler` fuer native macOS Apps im SDK nicht verfuegbar ist.
- Automatischer Refresh nutzt denselben Pfad wie manueller Refresh fuer alle Feeds:
  `FeedViewModel.refreshAllFeeds(_:context:)`.
- Wichtig: macOS entscheidet den genauen Zeitpunkt. Eine vollstaendig beendete App
  wird fuer diese Basis nicht neu gestartet.

### ArticleListView.swift
- Zeigt echte Artikel des ausgewählten Feeds aus der `Feed.articles` Relationship
- Sortiert nach `publishedAt` absteigend
- Nutzt `ArticleRowView` fuer Titel, Metadaten, Summary, optionales Bild,
  Ungelesen-Punkt rechts oben und Stern rechts unten
- Markiert Artikel beim Auswaehlen automatisch als gelesen, wenn die Einstellung
  aktiv ist

### ArticleRowView.swift
- Reichhaltige Artikelzeile mit optionalem `AsyncImage`
- Platzhalterbild, wenn kein `imageURL` vorhanden ist
- Kontextmenue fuer gelesen/ungelesen und Stern
- Gelesene Artikel werden optisch ruhiger dargestellt

### ArticleViewModel.swift
- `@Observable` class
- `toggleRead(_:)`
- `toggleStarred(_:)`
- Optionale Varianten ignorieren fehlende Auswahl fuer Menue-/Shortcut-Aktionen
- `markReadIfNeeded(_:isEnabled:)`
- `sortedForList(_:)`, `previousArticle(before:in:)` und `nextArticle(after:in:)`
  kapseln die Navigation innerhalb der aktuell sichtbaren Artikelliste

### ArticleMetadataEditor.swift
- Kapselt die Bearbeitung der Artikel-Metadaten fuer den Reader-Inspector.
- `addTag(named:to:availableTags:context:)` trimmt Tag-Namen, verhindert leere oder
  doppelte Artikel-Tags und verwendet vorhandene Tags wieder, bevor neue Tags
  erstellt werden.
- `removeTag(_:from:context:)` entfernt ein Tag nur vom aktuellen Artikel.
- `setFolderName(_:for:context:)` speichert den getrimmten Ordnernamen am Feed des
  Artikels; leere Eingaben entfernen die Ordnerzuordnung.

### ArticleCommands.swift / ArticleCommandActions.swift
- macOS-Menue `Artikel` fuer Aktionen auf dem fokussierten/ausgewaehlten Artikel
- `Cmd+↑` springt zum vorherigen sichtbaren Artikel
- `Cmd+↓` springt zum naechsten sichtbaren Artikel
- `Cmd+Shift+U` toggelt gelesen/ungelesen
- `Cmd+D` toggelt Stern
- Commands sind deaktiviert, wenn kein Artikel ausgewaehlt ist oder am Listenrand
  kein vorheriger/naechster Artikel existiert
- `ContentView` stellt die Aktionen via SwiftUI `FocusedValues` bereit

### FeedCommands.swift / FeedCommandActions.swift
- macOS-Menue `Feed` fuer Aktionen auf dem fokussierten/ausgewaehlten Feed
- `Cmd+N` oeffnet `Feed hinzufügen...` und nutzt dasselbe Sheet wie der Sidebar-Plus-Button
- `OPML importieren...` oeffnet einen macOS-Dateiimport fuer `.opml`/`.xml`
- Nach dem OPML-Import werden neu angelegte Feeds direkt ueber denselben async
  Refresh-Kern aktualisiert, damit Titel, Metadaten, Favicons und Artikel gefuellt sind
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

### SettingsView.swift
- macOS Settings-Szene in `FeedivoApp.swift`
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
- Ordner und Tags werden bewusst nicht im Artikelkopf gezeigt, sondern ueber den
  sichtbaren Toolbar-Toggle `Artikelinfos` in einem rechten Inspector verwaltet.
- Toolbar-Buttons fuer vorherigen/naechsten Artikel navigieren innerhalb der aktuell
  sichtbaren Feed- oder Smart-Filter-Liste und stoppen am Listenrand
- Toolbar-Button `textformat` oeffnet ein Popover fuer Titel-Schrift,
  Fliesstext-Schrift, Textgroesse, Titel-/Fliesstext-Zeilenabstand und Artikelbreite
- Titel- und Fliesstext-Schrift sowie Textgroesse/Titel-Zeilenabstand/
  Fliesstext-Zeilenabstand/Artikelbreite werden getrennt via `@AppStorage`
  gespeichert
- Die Metazeile oberhalb des Titels nutzt die Fliesstext-Schrift proportional kleiner
- Nutzt `ReaderContentRenderer`, um Content/Summary in Absätze und Bilder zu wandeln
- Noch kein WKWebView/Vollseiten-Reader

### ArticleMetadataInspectorView.swift
- Einblendbarer rechter Inspector in der Artikelansicht.
- Zeigt den aktuellen Feed-Ordner als Menu-Picker und schreibt Aenderungen direkt auf
  `Feed.folderName`.
- Zeigt Artikel-Tags als kompakte Chips; Tags koennen hinzugefuegt oder vom Artikel
  entfernt werden.
- Neue Tags werden ueber `ArticleMetadataEditor` normalisiert und als globale
  `Tag`-Eintraege wiederverwendet oder neu erstellt.

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

### ReaderMetadataFormatter.swift
- Berechnet ungefaehre Lesezeit mit 200 Woertern pro Minute, mindestens 1 Minute
- Verwendet `Article.content` vor `Article.summary`
- Baut Metadaten-Teile so zusammen, dass fehlende Werte ausgelassen werden
- Sichtbarer Lesezeit-Text ist via `Localizable.xcstrings` und `L10n` lokalisiert

### ReaderContentRenderer.swift
- Wandelt HTML-Fragmente oder Plain Text in `ReaderContentBlock`
- Aktuelle Block-Typen: `.paragraph(String)` und `.image(urlString:)`
- Nutzt `NSAttributedString` HTML-Konvertierung fuer lesbaren Text
- Fallback: Wenn `Article.content` leer ist, wird `Article.summary` verwendet
- Fallback-Bild: Wenn kein HTML-Bild vorhanden ist, kann `Article.imageURL` als Bildblock dienen

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
    var isRead: Bool
    var isStarred: Bool
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
    var conditionField: String               // "title", "summary", "feedTitle"
    var conditionOperator: String            // "contains", "startsWith", "endsWith"
    var conditionValue: String
    @Relationship var assignTag: Tag?
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
  `FeedService.fetchFeed` reichert solche Artikel deshalb ueber die verlinkte Seite
  an; das erzeugt zusaetzliche Netzwerkrequests beim Hinzufuegen/Aktualisieren.
- **Favicons:** Nicht nur `/favicon.ico` ableiten. Zuerst Website-HTML lesen und
  `<link rel="icon">`, `apple-touch-icon`, `shortcut icon` und `mask-icon` auswerten.
  Relative Icon-URLs muessen gegen die Website-URL normalisiert werden. Wenn HTML
  nicht geladen werden kann, ist `/favicon.ico` der Fallback.
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

### M2 – Core Features ← AKTUELL
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

### M3 – Tags, Regeln & Sync
- [x] Ordner fuer Feeds als eigenes Organisationsfeature ausbauen (Basis:
  eine Ebene, Sidebar-Section `Ordner` mit + Button, leere Ordner als `FeedFolder`,
  Feed-Zuordnung editierbar in Feed-Eigenschaften)
- [ ] Tag-System ausbauen: Tags mit Farben verwalten, Feeds taggen und Sidebar-Filter
  ergaenzen; Basis fuer Artikel-Tags ist im Reader-Inspector umgesetzt
- [ ] Sidebar: Abschnitt "Tags" mit Filterung
- [ ] Erweiterte/eigene Smart Filter spaeter pruefen
- [ ] `RuleEngine`: Neue Artikel automatisch taggen basierend auf Regeln
- [ ] Regel-UI: Regeln erstellen, bearbeiten, aktivieren/deaktivieren
- [ ] iCloud Sync via CloudKit aktivieren und testen
- [ ] Offline-Unterstützung: Artikel-Content beim Abruf in SwiftData speichern
- [ ] Background Refresh erweitern: Strategie fuer Refresh nach vollstaendig beendeter
  App pruefen, falls spaeter noetig

### M4 – Polish & Release
- [x] OPML Import (Feeds aus anderem RSS Reader übernehmen)
- [x] OPML Export (Feeds portieren)
- [ ] Einstellungen-Fenster (Refresh-Intervall, Schriftgrösse, Theme)
- [ ] Share Extension (Artikel teilen via macOS Share Sheet)
- [ ] App-Icon designen
- [ ] Onboarding (erster Start ohne Feeds)
- [ ] App Store Vorbereitung oder privat verteilen

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
- [ ] CloudKit Sync-Umfang, insbesondere Artikel-Content
- [ ] Artikel-Detail: Nur nativer SwiftUI Text-Renderer oder auch WKWebView (volle Webseite)?
- [ ] Monetarisierung: Kostenlos / einmaliger Kauf / nie im App Store?

---

## Aktuell in Arbeit

- M1 abgeschlossen
- Aktuell M2/Backlog-Ausbau: Basis-Feed/Reader/Refresh/Favicons, Smart Filter,
  Link-Aktionen, globaler Reader-Anzeigemodus und strukturierte Reader-Bloecke sind
  umgesetzt; Navigation Vor/Zurueck fuer Artikel und Feed Eigenschaften sind ebenfalls
  als Basis umgesetzt. OPML Import/Export ist als Paket A umgesetzt. Paket B hat die
  einfache Ordnerverwaltung fuer Feeds umgesetzt. Der Reader-Metadaten-Inspector
  setzt die erste Artikel-Tag-Basis um; naechster sinnvoller Block ist der Ausbau von
  Tag-Verwaltung, Tag-Filtern und Regeln.
- Feature-Roadmap ist in `docs/FEATURES.md` dokumentiert und muss bei Änderungen
  zusammen mit diesem Projektgedächtnis gepflegt werden

---

## Letzte Änderungen

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
  PostScript-Kandidaten, Picker sind explizit Menues, und die Metazeile oberhalb
  des Titels folgt nun ebenfalls der Fliesstext-Schrift
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
- 2026-06-20: Feed-Eigenschaften-Sheet visuell ueberarbeitet: grosser Feed-Header
  mit Icon/Favicon-Fallback und Statusmetriken, gruppierte Detailansicht,
  abgesetzter Aktualisierungsblock und kompakter Feed-Log-Verlauf
- 2026-06-20: Artikelbild-Fallback fuer Feeds ohne Item-Bilder umgesetzt:
  `FeedService.fetchFeed` liest bei fehlendem Bild die Artikelseite und uebernimmt
  `og:image`/`twitter:image`; Refresh fuellt fehlende `Article.imageURL` Werte bei
  bereits gespeicherten Artikeln nach
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
