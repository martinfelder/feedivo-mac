# Artikelliste: Favicon vor Feedname + konfigurierbare Bild-/Feedname-Position

## Ziel

Erweiterung von Feature 19.1 (FEATURES.md):
1. Vorschaubild in der Artikelliste: Links / Rechts / Aus (bereits als zwei
   separate Bullets in FEATURES.md gelistet, hier zu einer 3-Wege-Einstellung
   zusammengeführt).
2. Vor dem Feedname-Text erscheint ein kleines Favicon, genau so hoch wie der
   Text selbst; Platzhalter-Icon falls kein Favicon vorhanden.
3. Neue Einstellung: Feedname-Zeile (Favicon + Feedname + Zeitpunkt) erscheint
   vor oder nach dem Artikeltitel. Zeitpunkt bleibt sichtbar, auch wenn
   "Feed-Name anzeigen" ausgeschaltet ist.

## Bereits entschieden (FEATURES.md 19.1, Nachtrag 2026-07-08)

- Favicon-Fallback: generisches Platzhalter-Icon (kein Springen der Zeile).
- Position "vor dem Titel": ganz oben, linksbündig, danach erst Titel, danach
  optional Summary.
- Wird "Feed-Name anzeigen" ausgeschaltet, bleibt der Zeitpunkt alleine
  sichtbar (Favicon + Feedname verschwinden, Zeitpunkt nicht).
- Standard für die neue Positions-Einstellung: **Nach dem Titel** (aktuelles
  Verhalten, kein Bruch für Bestandsnutzer).

## Bestandsaufnahme (Code)

- `ArticleRowView.swift`: Vorschaubild aktuell fest links (`previewImage` als
  erstes HStack-Element), Metadaten-Zeile (`metadataText` = `"\(feedTitle) ·
  \(publishedAt relative)"`) aktuell fest EIN `Text(...)` direkt nach dem
  Titel, vor der Summary. Kein Favicon, keine Sichtbarkeits-/Positions-
  Einstellungen vorhanden — alles komplett neu.
- `ArticleListSnapshot.swift` (SQLite-Zeilentyp) hat noch KEIN `faviconURL`-
  Feld. Wird über GRDB `FetchableRecord` in `TimelineStore.swift:767-785`
  aus dem SQL-Row-Dictionary befüllt.
- Fünf identische SQL-`SELECT`-Blöcke bauen `ArticleListSnapshot`-Zeilen, alle
  mit `JOIN feeds f ON f.id = a.feedID` und `f.title AS feedTitle` in der
  Spaltenliste:
  - `TimelineStore.swift:87-113` (Haupt-Artikelliste)
  - `ArticleStore.swift:205-230` (`latestArticleForFeed`, erster Block)
  - `ArticleStore.swift:234-258` (`latestArticleForFeed`, Fallback-Block)
  - `ArticleStore.swift:275-302` (`searchArticles(matching:)`, kompakte Suche)
  - `ArticleStore.swift:366-392` (`searchArticles(state:)`, Suchfenster)
- `ArticleListItemSnapshot.swift` (View-Snapshot-Typ) hat genau eine Quelle:
  `init(sqliteSnapshot: ArticleListSnapshot)`, einzige Konstruktions-Stelle in
  `SQLiteFeedArticleListView.swift:299`.
- Referenz-Muster für Favicon-Rendering bereits vorhanden:
  `FeedRowView.swift` (`faviconView`/`fallbackIcon`, `CachedRemoteImageView`).
- Referenz-Muster für ein bestehendes Anzeigemodus-Enum: `ReaderDisplayMode.swift`
  (`String, CaseIterable, Identifiable`, `storageKey`, `defaultMode`, `titleKey`,
  `resolved(from:)`).
- Settings-UI-Fundstelle: `NewAppearanceSettingsView` in
  `Feedivo/Views/Settings/SettingsView.swift:318-431`, nutzt `NewSettingsBlock`/
  `NewSettingRow`-Komponenten; `interfaceTextSizeRawValue`-Picker (Zeile 356)
  ist das Referenzmuster für einen `.pickerStyle(.segmented)` mit
  `.fixedSize(horizontal: true, vertical: false)`.

## Architektur

### Neue Settings-Typen (eine neue Datei)

`Feedivo/Views/ArticleList/ArticleListDisplaySettings.swift`:

```swift
import SwiftUI

enum ArticleListImagePosition: String, CaseIterable, Identifiable {
    case left
    case right
    case hidden

    static let storageKey = "articleList.imagePosition"
    static let defaultPosition = ArticleListImagePosition.left

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .left:
            L10n.articleListImagePositionLeft
        case .right:
            L10n.articleListImagePositionRight
        case .hidden:
            L10n.articleListImagePositionHidden
        }
    }

    static func resolved(from rawValue: String) -> ArticleListImagePosition {
        ArticleListImagePosition(rawValue: rawValue) ?? defaultPosition
    }
}

enum ArticleListFeedNamePosition: String, CaseIterable, Identifiable {
    case beforeTitle
    case afterTitle

    static let storageKey = "articleList.feedNamePosition"
    static let defaultPosition = ArticleListFeedNamePosition.afterTitle

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .beforeTitle:
            L10n.articleListFeedNamePositionBeforeTitle
        case .afterTitle:
            L10n.articleListFeedNamePositionAfterTitle
        }
    }

    static func resolved(from rawValue: String) -> ArticleListFeedNamePosition {
        ArticleListFeedNamePosition(rawValue: rawValue) ?? defaultPosition
    }
}

enum ArticleListFeedNameVisibilitySettings {
    static let showsFeedNameKey = "articleList.showsFeedName"
    static let defaultShowsFeedName = true
}
```

`ArticleListImagePosition.defaultPosition = .left` und
`ArticleListFeedNamePosition.defaultPosition = .afterTitle` entsprechen exakt
dem heutigen, fest verdrahteten Verhalten — kein Bruch für Bestandsnutzer.
`ArticleListFeedNameVisibilitySettings.defaultShowsFeedName = true` ebenso
(Feedname wird heute immer gezeigt, wenn vorhanden).

### Favicon-Plumbing (SQL → Snapshot → View)

1. `ArticleListSnapshot.swift`: neues Feld `var faviconURL: String? = nil`
   (mit Default, damit bestehende Test-Konstruktionsaufrufe in
   `ArticleListItemSnapshotTests.swift`, `ArticleListQueryTests.swift`,
   `SQLiteFeedArticleListStateTests.swift` nicht brechen).
2. `TimelineStore.swift:783` (`FetchableRecord.init(row:)`): Zeile
   `faviconURL = row["faviconURL"]` ergänzen.
3. In allen 5 oben gelisteten SQL-Blöcken: `f.faviconURL AS faviconURL,`
   direkt nach `f.title AS feedTitle,` einfügen (identische Änderung, alle
   Blöcke haben bereits das `JOIN feeds f` und dieselbe Spaltenreihenfolge).
4. `ArticleListItemSnapshot.swift`: neues Feld `let faviconURL: String?`,
   befüllt aus `sqliteSnapshot.faviconURL` im bestehenden `init(sqliteSnapshot:)`.

### `ArticleRowView` Restrukturierung

- Drei neue `@AppStorage`-Properties (Image-Position, Feedname-Sichtbarkeit,
  Feedname-Position).
- `previewImage` wird nur gerendert, wenn `imagePosition != .hidden`; steht
  vor dem Text-Block bei `.left`, danach (vor der Stern-Spalte) bei `.right`.
- Neue `metadataRow`-Computed-Property ersetzt den bisherigen einzelnen
  `Text(metadataText)`:
  - Zeigt bei sichtbarem Feedname: Favicon (Höhe = 11pt, passend zur
    Metadaten-Schriftgröße) + `Text("\(feedTitle) · \(Zeitpunkt)")`.
  - Zeigt bei ausgeblendetem Feedname (oder leerem `feedTitle`): nur
    `Text(Zeitpunkt)`, kein Favicon.
  - Zeigt gar nichts, wenn auch kein Zeitpunkt vorhanden ist.
- `metadataRow` wird VOR `Text(snapshot.title)` platziert bei
  `feedNamePosition == .beforeTitle`, sonst NACH dem Titel (aktuelle Position,
  vor der Summary) bei `.afterTitle`.
- Favicon-Rendering exakt nach dem `FeedRowView.faviconView`-Muster
  (`CachedRemoteImageView` + Systemsymbol-Fallback
  `"dot.radiowaves.left.and.right"`), aber mit eigener kleinerer Größe (11pt
  statt Sidebar-Icon-Größe).

### Settings-UI

Neue `NewSettingsBlock(eyebrow: "Artikelliste")` in `NewAppearanceSettingsView`
(vor dem bestehenden Block "Oberfläche" oder danach — Reihenfolge nicht
kritisch) mit drei `NewSettingRow`s:
1. Vorschaubild-Position: `Picker` mit den 3 Fällen, `.pickerStyle(.segmented)`
   + `.fixedSize(horizontal: true, vertical: false)` (Muster wie
   `interfaceTextSizeRawValue`-Picker).
2. Feed-Name anzeigen: `Toggle`.
3. Feedname-Position: `Picker` mit den 2 Fällen, gleicher Segmented-Stil.

## Lokalisierung

Neue Keys (de/en/fr/it), Muster `settings.articleList.*` /
`articleList.imagePosition.*` / `articleList.feedNamePosition.*`:
- `articleList.imagePosition.left` = "Links" / "Left" / "Gauche" / "Sinistra"
- `articleList.imagePosition.right` = "Rechts" / "Right" / "Droite" / "Destra"
- `articleList.imagePosition.hidden` = "Aus" / "Off" / "Désactivé" / "Disattivato"
- `articleList.feedNamePosition.beforeTitle` = "Vor dem Titel" / "Before title" / "Avant le titre" / "Prima del titolo"
- `articleList.feedNamePosition.afterTitle` = "Nach dem Titel" / "After title" / "Après le titre" / "Dopo il titolo"
- `settings.articleList.imagePosition.title` = "Vorschaubild-Position"
- `settings.articleList.imagePosition.description` = "Position des Vorschaubilds in der Artikelliste."
- `settings.articleList.showsFeedName.title` = "Feed-Name anzeigen"
- `settings.articleList.showsFeedName.description` = "Zeigt den Namen des Feeds pro Artikel, z. B. in \"Alle Artikel\"."
- `settings.articleList.feedNamePosition.title` = "Feedname-Position"
- `settings.articleList.feedNamePosition.description` = "Feedname und Zeitpunkt vor oder nach dem Artikeltitel anzeigen."

(Genaue EN/FR/IT-Übersetzungen im Plan mit vollem Text je Sprache.)

## Out of Scope

- Vorschautext-Zeilen-Stepper, Summary-Toggle, Datum-Format-Einstellung,
  Ungelesen-Markierung-Stil — bleiben eigene, spätere Slices aus 19.1.
- Keine Änderung an `FeedRowView`/Sidebar-Favicons.
- Keine Änderung an der Reader-Ansicht.

## Testing

- `ArticleListImagePosition.resolved(from:)` / `titleKey` und
  `ArticleListFeedNamePosition.resolved(from:)` / `titleKey`: reine Logik,
  unit-testbar (Default-Fallback bei unbekanntem Rohwert, korrekte
  Zuordnung).
- Favicon-Plumbing: Integrationstest gegen eine In-Memory-SQLite-Datenbank
  (bestehendes Testmuster `FeedivoDatabase.inMemoryForTests()`), der einen
  Feed mit `faviconURL` anlegt, einen Artikel darüber lädt und prüft, dass
  `ArticleListSnapshot.faviconURL` korrekt befüllt ist — mindestens für den
  Haupt-Timeline-Pfad (`TimelineStore.articles(...)`).
- `ArticleRowView`-Layout selbst (SwiftUI-Views) bleibt wie bei Feature 1.12
  manuell verifiziert, nicht unit-getestet.
