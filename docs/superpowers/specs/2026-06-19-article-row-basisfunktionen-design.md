# ArticleRow und erste Reader-Basisfunktionen - Design

Datum: 2026-06-19

## Ziel

Die erste M2-Implementierungswelle macht die Artikel-Liste deutlich nutzbarer.
Feedivo bekommt eine echte `ArticleRowView` mit visueller Hierarchie und direkten
Statussignalen fuer ungelesen/gelesen und Stern/Favorit.

## Umfang

In Scope:
- Reichhaltige Artikelzeile mit optionalem Vorschaubild links.
- Titel, Feed-Name oder Quelle, Datum/relative Zeit und kurze Zusammenfassung.
- Ungelesen-Punkt rechts oben.
- Stern rechts unten.
- Gelesene Artikel visuell ruhiger als ungelesene Artikel.
- Direkte Statusaktionen fuer gelesen/ungelesen und Stern.
- Dokumentation in `AGENTS.md` und `docs/FEATURES.md` nach der Umsetzung.

Nicht in Scope fuer diese erste Welle:
- OPML Import.
- Smart Filter.
- Feed Refresh.
- WebView Reader.
- Archiv-Funktion.
- Lesedauer-Berechnung, falls dafuer erst Textanalyse noetig waere.

## Visuelle Entscheidung

Aus drei Varianten wurde die reichhaltige Zeile gewaehlt.

Die finale Richtung:
- Bild links, falls `Article.imageURL` vorhanden ist.
- Textblock mittig mit Titel, Metadaten und Summary.
- Ungelesen-Punkt ganz rechts oben.
- Stern ganz rechts unten.

Grund: Die Zeile wirkt mehr wie ein moderner RSS Reader und weniger wie eine reine
Mail-Inbox. Statuspunkt und Stern sind rechts sauber getrennt; dadurch bleibt die
linke Seite fuer Inhalt und Bild reserviert.

## Datenmodell

Das bestehende `Article`-Modell reicht fuer die erste Welle aus:
- `isRead`
- `isStarred`
- `imageURL`
- `title`
- `summary`
- `publishedAt`
- `feed`

Es ist keine Migration noetig.

## UI-Komponenten

### ArticleRowView

Neue View unter `Feedivo/Views/ArticleList/ArticleRowView.swift`.

Aufgaben:
- Artikelzeile rendern.
- Optionales Bild mit `AsyncImage` anzeigen.
- Fallback-Platzhalter zeigen, wenn kein Bild vorhanden ist.
- Statuspunkt rechts oben nur fuer ungelesene Artikel.
- Stern rechts unten immer anzeigen, gefuellt bei `isStarred`.
- Gelesene Artikel dezenter darstellen.

### ArticleListView

`ArticleListView` nutzt `ArticleRowView` statt inline `VStack`.

## Interaktionen

Basis fuer diese Welle:
- Klick auf Stern toggelt `isStarred`.
- Kontextmenue oder Button-Aktion fuer gelesen/ungelesen toggelt `isRead`.
- Auswahl eines Artikels kann ihn als gelesen markieren, wenn diese Entscheidung
  beim Implementieren bestaetigt wird.

## Fehlerfaelle

- Kein Bild: neutraler Platzhalter.
- Kein Summary: Zeile zeigt nur Titel und Metadaten.
- Kein Datum: Datumsteil wird ausgelassen.
- Kein Feed-Name: Metadaten zeigen nur vorhandene Werte.

## Tests

Mindestens:
- Unit-Test fuer Status-Toggle-Logik, falls eine kleine Hilfsfunktion/ViewModel-Methode
  entsteht.
- Build/Test mit `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`.

## Offene Entscheidung vor Implementierung

Soll ein Artikel automatisch als gelesen markiert werden, sobald er in der Liste
ausgewaehlt und im Reader angezeigt wird?

Empfehlung: Ja, weil das dem Verhalten vieler RSS Reader entspricht. Spaeter kann
das als Einstellung konfigurierbar werden.
