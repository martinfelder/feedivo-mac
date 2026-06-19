# i18n Foundation - Design

Datum: 2026-06-19

## Ziel

Feedivo wird mehrsprachig vorbereitet nach Apples aktuellem i18n-Standard fuer
Xcode 26 und SwiftUI. Die App soll als erste Sprachen Deutsch, Englisch,
Franzoesisch und Italienisch unterstuetzen.

## Entscheidung

Wir nutzen einen Swift String Catalog:

- Datei: `Feedivo/Localizable.xcstrings`
- Sprachen: `de`, `en`, `fr`, `it`
- Deutsch bleibt die primaere Arbeitssprache und Quellsprache.
- Englisch, Franzoesisch und Italienisch werden als erste Uebersetzungen gepflegt.

Grund: String Catalogs sind der moderne Apple-Standard, bleiben in Xcode gut
bearbeitbar und skalieren besser als viele separate `.strings` Dateien.

## Umfang

In Scope:

- Sichtbare UI-Texte aus SwiftUI-Views lokalisieren.
- Tooltips und Accessibility-Texte lokalisieren.
- Fehlermeldungen aus ViewModels/Services lokalisierbar machen.
- Erste Uebersetzungen fuer Deutsch, Englisch, Franzoesisch und Italienisch eintragen.
- Dokumentation in `AGENTS.md` und `docs/FEATURES.md` nachfuehren.
- Tests/Build ausfuehren.

Nicht in Scope fuer diese erste Welle:

- Artikel-, Feed- oder Webseiten-Inhalte automatisch uebersetzen.
- Dynamische Feed-Titel, Artikel-Titel, Summary oder Content veraendern.
- Sprachumschalter innerhalb der App.
- Remote-Konfiguration oder externe Translation-Services.
- Vollstaendige Marketing-/App-Store-Lokalisierung.

## Key-Strategie

Wir verwenden sprechende, stabile Keys statt deutscher UI-Texte als technische
Schluessel.

Beispiele:

- `sidebar.empty.title`
- `sidebar.addFeed.button`
- `articleList.empty.title`
- `articleRow.star.add`
- `settings.reading.markReadOnOpen.title`
- `feed.error.invalidURL`

Grund: Stabile Keys vermeiden spaetere Diff-Unruhe, wenn deutsche Formulierungen
geglattet werden.

## UI-Abdeckung

### ContentView

Lokalisieren:

- Kein Feed ausgewaehlt
- Waehle einen Feed in der Sidebar aus.
- Kein Artikel ausgewaehlt
- Waehle einen Artikel aus der Liste aus.

### SidebarView

Lokalisieren:

- Noch keine Feeds
- Feed hinzufuegen
- URL-Platzhalter und Dialog-Aktionen
- Abbrechen
- Hinzufuegen

### ArticleListView

Lokalisieren:

- Keine Artikel
- Dieser Feed hat noch keine gespeicherten Artikel.

### ArticleRowView

Lokalisieren:

- Stern entfernen
- Mit Stern markieren
- Ungelesen
- Als gelesen markieren
- Als ungelesen markieren
- Accessibility-Status "Ungelesen" und "Mit Stern"

### ReaderView

Lokalisieren:

- Original oeffnen

### SettingsView

Lokalisieren:

- Lesen
- Artikel beim Oeffnen als gelesen markieren
- Erklaertext zur Einstellung

## Fehlermeldungen

`FeedServiceError` und `FeedViewModel` sollen keine hart kodierten deutschen Texte
mehr zurueckgeben. Stattdessen werden lokalisierbare Ressourcen verwendet.

Beispiele:

- Ungueltige Feed-URL
- Feed konnte nicht gelesen werden
- Bitte gib eine Feed-URL ein.
- Der Feed konnte nicht hinzugefuegt werden.

## Datenfluss

SwiftUI bekommt lokalisierte Texte ueber String-Catalog-Keys. Dynamische Daten
bleiben wie bisher:

- `feed.title` bleibt Inhalt aus dem Feed.
- `article.title`, `article.summary`, `article.content` bleiben unveraendert.
- `Date+RelativeDisplay` nutzt weiterhin `RelativeDateTimeFormatter` und
  `DateFormatter`, die automatisch auf die System-Locale reagieren.

## Tests und Verifikation

Mindestens:

- Build/Test mit
  `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
- Sichtpruefung, dass alle statischen UI-Strings im Code entweder lokalisierbare
  Keys oder bewusst dynamische Inhalte sind.
- `rg`-Pruefung auf neue hart kodierte sichtbare deutsche Texte in `Feedivo/Views`
  und `Feedivo/ViewModels`.

## Dokumentation

Nach der Umsetzung aktualisieren:

- `AGENTS.md`: Technologie-Stack, Gotchas, aktuelle Implementierung und letzte
  Aenderungen.
- `docs/FEATURES.md`: Mehrsprachigkeit von "Spaeter" auf i18n-Foundation
  umgesetzt bzw. in Arbeit setzen.

## Offene Punkte fuer spaeter

- Sprachumschalter in der App, falls Nutzer unabhaengig von macOS umstellen wollen.
- Pluralisierung fuer Zaehler, sobald Ungelesen-Zaehler in Sidebar/Smart Filtern
  eingefuehrt werden.
- App-Store-Metadaten und Onboarding-Texte lokalisieren.
