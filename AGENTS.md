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
| Background Refresh | BackgroundTasks Framework | BGTaskScheduler — noch nicht implementiert |
| Mindest-macOS | macOS 14.0 Sonoma | SwiftData + @Observable Macro |

---

## Projektstruktur

```
FeedivoMac/
├── Feedivo/
│   ├── App/
│   │   ├── FeedivoApp.swift            # @main Entry Point, .modelContainer Setup ✅
│   │   └── ContentView.swift           # Root: NavigationSplitView (3 Spalten) ✅
│   │
│   ├── Models/                         # SwiftData @Model Klassen — alle fertig ✅
│   │   ├── Feed.swift
│   │   ├── Article.swift
│   │   ├── Tag.swift
│   │   └── Rule.swift
│   │
│   ├── ViewModels/
│   │   ├── FeedViewModel.swift         # Feed hinzufügen ✅
│   │   ├── ArticleViewModel.swift      # Artikel gelesen/ungelesen und Stern toggeln ✅
│   │   ├── TagViewModel.swift          # Tags verwalten (TODO)
│   │   ├── RuleEngineViewModel.swift   # Regeln auswerten und Tags auto-zuweisen (TODO)
│   │   └── SyncViewModel.swift         # iCloud Sync Status anzeigen (TODO)
│   │
│   ├── Views/
│   │   ├── Sidebar/
│   │   │   ├── SidebarView.swift       # Linke Spalte: Feeds, + Button, @Query ✅
│   │   │   ├── FeedRowView.swift       # Eine Feed-Zeile in der Sidebar (TODO)
│   │   │   └── TagRowView.swift        # Eine Tag-Zeile in der Sidebar (TODO)
│   │   ├── ArticleList/
│   │   │   ├── ArticleListView.swift   # Mittlere Spalte: echte Feed-Artikel anzeigen ✅
│   │   │   └── ArticleRowView.swift    # Reichhaltige Artikel-Zeile mit Status/Stern ✅
│   │   ├── Reader/
│   │   │   ├── ReaderView.swift        # Rechte Spalte: nativer Artikel-Reader ✅
│   │   │   ├── ReaderContentRenderer.swift # HTML/Text zu Reader-Bloecken ✅
│   │   │   ├── ReaderMetadataFormatter.swift # Feedname/Lesezeit/Alter ✅
│   │   │   ├── ReaderFontPreset.swift  # Schrift-Presets fuer Reader ✅
│   │   │   ├── ReaderTypography.swift  # Textgroesse/Zeilenabstand Defaults ✅
│   │   │   └── WebContentView.swift    # WKWebView-Wrapper für volle Artikel (TODO)
│   │   ├── Tags/
│   │   │   ├── TagManagerView.swift    # Tags erstellen, bearbeiten, löschen (TODO)
│   │   │   └── AddTagView.swift        # Sheet: neuen Tag erstellen (TODO)
│   │   ├── Rules/
│   │   │   ├── RuleListView.swift      # Alle Regeln anzeigen und verwalten (TODO)
│   │   │   └── AddRuleView.swift       # Sheet: neue Regel erstellen (TODO)
│   │   └── Settings/
│   │       └── SettingsView.swift      # Erste Einstellung fuer Auto-gelesen ✅
│   │
│   ├── Services/
│   │   ├── FeedService.swift           # FeedKit-Wrapper: RSS/Atom/JSON Feed parsen ✅
│   │   ├── FeedRefreshService.swift    # Alle Feeds abrufen (async, mit Fortschritt) (TODO)
│   │   ├── RuleEngine.swift            # Regeln auf neue Artikel anwenden (TODO)
│   │   ├── OPMLService.swift           # OPML Import und Export (TODO)
│   │   └── BackgroundRefreshService.swift  # BGTaskScheduler (TODO)
│   │
│   ├── Extensions/
│   │   ├── Date+RelativeDisplay.swift  # Datum fuer Artikelzeilen formatieren ✅
│   │   └── URL+Favicon.swift           # Favicon-URL aus Feed-URL ableiten (TODO)
│   │
│   └── Resources/
│       ├── Assets.xcassets
│       ├── AppLanguage.swift           # Sprachauswahl + Locale-Mapping ✅
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

## Implementierter Code (Stand 2026-06-19)

### FeedivoApp.swift
```swift
import SwiftUI
import SwiftData

@main
struct FeedivoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Feed.self,
            Article.self,
            Tag.self,
            Rule.self
        ])
    }
}
```

### ContentView.swift
NavigationSplitView mit 3 Spalten. Verwaltet `selectedFeed` und `selectedArticle` als
`@State`. Zeigt `ContentUnavailableView` wenn nichts ausgewählt ist.
Spaltenbreiten: Sidebar 200–300px, ArticleList 280–400px, Detail flexibel.

### SidebarView.swift
- `@Query(sort: \Feed.title)` für automatische Feed-Liste aus SwiftData
- Toolbar mit + Button → Sheet `AddFeedSheet`
- `AddFeedSheet` ist eine separate Struct in derselben Datei
- Ruft `FeedViewModel.addFeed()` auf

### FeedService.swift
- Parsed RSS 2.0, Atom und JSON Feed via FeedKit
- Nutzt FeedKit `Feed(data:)` für Parsing und `URLSession` + async/await für Download
- Gibt `ParsedFeed` mit Feed-Metadaten und `[ParsedArticle]` zurück
- Feed-Titel wird aus Metadaten gelesen, mit URL als Fallback
- Artikelbilder werden aus Media RSS, iTunes Image, Bild-Enclosures und erstem
  `<img>` in Content/Summary gelesen
- Relative Artikelbild-URLs werden gegen die Feed-URL zu absoluten URLs aufgeloest,
  damit `AsyncImage` sie laden kann
- Eigene `FeedServiceError` enum: `.invalidURL`, `.parsingFailed`

### FeedViewModel.swift
- `@Observable` class
- `addFeed(urlString:context:)` — lädt Artikel, erstellt Feed, speichert in SwiftData
- Properties: `isLoading: Bool`, `errorMessage: String?`

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
- `markReadIfNeeded(_:isEnabled:)`

### SettingsView.swift
- macOS Settings-Szene in `FeedivoApp.swift`
- `@AppStorage("markArticleReadOnSelection")`
- Standard: Artikel beim Oeffnen automatisch als gelesen markieren
- `@AppStorage("appLanguage")`
- Sprachauswahl: Nach System, Deutsch, Englisch, Französisch, Italienisch
- Reader-Schriftwahl: `readerTitleFontPreset` und `readerBodyFontPreset`
- Reader-Typografie: `readerBodyFontSize` und `readerLineSpacing`
- Presets: System, Geist, Inter, Manrope, DM Sans, Literata, Newsreader,
  IBM Plex Sans, Atkinson Hyperlegible, Source Serif 4, Libre Franklin, Lora,
  Merriweather, Noto Sans, Noto Serif, Roboto Slab, Crimson Pro, Fraunces, Serif

### ReaderView.swift
- Zeigt Metazeile, Titel, native Reader-Bloecke und Link zum Original
- Metazeile: Feedname, ungefaehre Lesezeit und Artikelalter, linksbuendig oberhalb
  des Titels
- Toolbar-Button `textformat` oeffnet ein Popover fuer Titel-Schrift,
  Fliesstext-Schrift, Textgroesse und Zeilenabstand
- Titel- und Fliesstext-Schrift sowie Textgroesse/Zeilenabstand werden getrennt
  via `@AppStorage` gespeichert
- Die Metazeile oberhalb des Titels nutzt die Fliesstext-Schrift proportional kleiner
- Nutzt `ReaderContentRenderer`, um Content/Summary in Absätze und Bilder zu wandeln
- Noch kein WKWebView/Vollseiten-Reader

### ReaderFontPreset.swift
- Kuratierte Font-Presets fuer die Artikelansicht aus der UI-Referenz:
  System, Geist, Inter, Manrope, DM Sans, Literata, Newsreader, IBM Plex Sans,
  Atkinson Hyperlegible, Source Serif 4, Libre Franklin, Lora, Merriweather,
  Noto Sans, Noto Serif, Roboto Slab, Crimson Pro, Fraunces, Serif
- Kapselt Anzeigenamen, bekannte PostScript-Kandidaten, SwiftUI-Font-Erzeugung und
  Fallback fuer unbekannte gespeicherte Werte
- Hinweis: Custom-Fonts werden per PostScript-Namen angesprochen; falls sie auf dem
  Mac nicht vorhanden sind, braucht es spaeter Font-Bundling mit Lizenzklaerung

### ReaderTypography.swift
- Kapselt Defaults und Grenzwerte fuer Reader-Typografie
- Fliesstext-Groesse: Default 17 px, Wertebereich 14...24 px
- Zeilenabstand: Default 5 px, Wertebereich 1...12 px

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
    var title: String
    var feedDescription: String?
    var faviconURL: String?
    var lastRefreshed: Date?
    var refreshIntervalMinutes: Int          // Default: 60
    @Relationship(deleteRule: .cascade) var articles: [Article]
    @Relationship var tags: [Tag]
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
- **NavigationView ist deprecated:** Immer `NavigationSplitView` oder `NavigationStack`
- **WKWebView in SwiftUI:** Braucht einen `NSViewRepresentable`-Wrapper für macOS
- **Background Refresh macOS:** `BGTaskScheduler` muss in `Info.plist` unter
  `BGTaskSchedulerPermittedIdentifiers` registriert sein
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
- [x] ReaderView ausbauen: nativer Artikel-Renderer fuer Absätze und Bilder (Basis)
- [x] ArticleRowView: Titel, Datum, gelesen/ungelesen Indikator
- [x] Gelesen/Ungelesen markieren (Basis per Kontextmenue + Auto-gelesen beim Oeffnen)
- [x] Artikel mit Stern markieren (Basis per Button/Kontextmenue)
- [x] i18n Foundation: String Catalog und erste Lokalisierung fuer de/en/fr/it
- [x] Einstellung fuer App-Sprache: Nach System, Deutsch, Englisch, Französisch, Italienisch
- [x] Reader-Typografie: Titel-/Fliesstext-Schriften, Fliesstext-Groesse und Zeilenabstand
- [ ] Tastaturkuerzel: `Cmd+Shift+U` gelesen/ungelesen, `Cmd+D` Stern
- [ ] macOS Menüleiste: `Cmd+R` = Refresh, `Cmd+N` = Feed hinzufügen
- [ ] Feed löschen (Rechtsklick → Delete, mit Bestätigung)
- [ ] Automatischer Refresh (konfigurierbares Intervall)
- [ ] Favicons laden und in Sidebar anzeigen

### M3 – Tags, Regeln & Sync
- [ ] Tag-System: Tags erstellen (Name + Farbe), Feeds und Artikeln manuell zuweisen
- [ ] Sidebar: Abschnitt "Tags" mit Filterung
- [ ] Smart Filter in Sidebar: "Alle ungelesen", "Gestern", "Mit Stern"
- [ ] `RuleEngine`: Neue Artikel automatisch taggen basierend auf Regeln
- [ ] Regel-UI: Regeln erstellen, bearbeiten, aktivieren/deaktivieren
- [ ] iCloud Sync via CloudKit aktivieren und testen
- [ ] Offline-Unterstützung: Artikel-Content beim Abruf in SwiftData speichern
- [ ] Background Refresh: `BGTaskScheduler` einrichten

### M4 – Polish & Release
- [ ] OPML Import (Feeds aus anderem RSS Reader übernehmen)
- [ ] OPML Export (Feeds portieren)
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

- [ ] Reader-Modus global oder pro Artikel speichern?
- [ ] Stern und Archiv getrennt halten oder für v1 nur Stern?
- [ ] OPML-Gruppen später als Ordner oder Tags importieren?
- [ ] CloudKit Sync-Umfang, insbesondere Artikel-Content
- [ ] Artikel-Detail: Nur nativer SwiftUI Text-Renderer oder auch WKWebView (volle Webseite)?
- [ ] Monetarisierung: Kostenlos / einmaliger Kauf / nie im App Store?
- [ ] Favicon-Strategie: Google S2 API (`https://www.google.com/s2/favicons?domain=`) oder eigene Lösung?

---

## Aktuell in Arbeit

- M1 abgeschlossen
- Aktuell M2: Tastaturkuerzel, Menü-Commands, Feed löschen und manuellen Refresh ausbauen
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
  sowie Fliesstext-Groesse und Zeilenabstand als Slider im Reader-Popover und in
  den Einstellungen umgesetzt
- 2026-06-19: Reader-Font-Aufloesung verbessert: Presets nutzen bekannte
  PostScript-Kandidaten, Picker sind explizit Menues, und die Metazeile oberhalb
  des Titels folgt nun ebenfalls der Fliesstext-Schrift
