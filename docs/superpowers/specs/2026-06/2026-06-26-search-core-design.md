# Suche 9.1/9.2 — Core Slice Design

Datum: 2026-06-26
Status: Freigegeben für Implementierungsplanung

## Ziel

Der erste Such-Slice bringt eine schnelle, macOS-nahe Suche in die bestehende
Artikelliste. Der Benutzer kann per `Cmd+F` ein Suchfeld öffnen, Artikel nach
Text finden und entscheiden, ob in der aktuellen Ansicht oder über alle Artikel
gesucht wird.

Dieser Slice bildet den Kern von Feature 9.1/9.2. Erweiterte Filter nach Feed,
Tag, Zeitraum und Status bleiben ein zweiter Slice.

## Umfang

Umgesetzt werden:

- Suchleiste oberhalb der Artikelliste.
- `Cmd+F` öffnet und fokussiert die Suchleiste.
- Suchbereiche: Alles, Titel, Zusammenfassung, Inhalt.
- Suchumfang: Aktuelle Ansicht oder Alle Artikel.
- Treffer werden in der bestehenden Artikelliste angezeigt.
- Bestehende Sortierung, bestehender Filter und die Logik für gelesene Artikel
  bleiben erhalten.
- Empty State für eine Suche ohne Treffer mit sichtbarem Suchbegriff.

Nicht umgesetzt werden:

- Erweiterte Suchfilter nach Feed, Tag, Zeitraum und Status.
- Spotlight-Index.
- Hervorhebung einzelner Suchtreffer im Artikeltext.
- Persistente Speicherung des letzten Suchbegriffs.

## UX

Die Suche ist Teil der Artikelliste und kein eigenes Fenster. Ohne aktive Suche
bleibt die Liste ruhig. Nach `Cmd+F` erscheint eine kompakte Suchleiste oben in
der mittleren Spalte. Der Cursor steht direkt im Suchfeld.

Der Standardumfang ist `Aktuelle Ansicht`, damit Suche in Feed, Tag oder
intelligentem Ordner nicht überraschend globale Ergebnisse zeigt. `Alle Artikel`
wechselt auf eine globale Artikelsuche, ohne die Sidebar-Auswahl zu verändern.

Versteckte Artikel bleiben aus normalen Suchergebnissen ausgeschlossen. Wenn die
aktuelle Ansicht explizit ausgeblendete Artikel zeigt, dürfen sie auch in der
Suche erscheinen.

## Architektur

Die Suchlogik wird als kleine, testbare Einheit in der Artikellisten-Schicht
modelliert:

- `ArticleSearchQuery` beschreibt Suchtext, Suchbereich und Umfang.
- `ArticleSearchField` beschreibt Alles, Titel, Zusammenfassung oder Inhalt.
- `ArticleSearchScope` beschreibt Aktuelle Ansicht oder Alle Artikel.
- `ArticleListPreparedArticles.prepare(...)` filtert zusätzlich nach aktiver
  Suche, nachdem sortiert und der bestehende Artikel-Filter angewendet wurde.

Für den globalen Umfang lädt die Artikelliste eine zweite, einfache SwiftData-
Query auf alle Artikel. Sie wird nur für die Suchauswertung genutzt, wenn der
Suchumfang auf `Alle Artikel` steht.

`ContentView` bleibt für Auswahl und Menüaktionen zuständig. Die Artikelliste
stellt über FocusedValues eine Aktion bereit, die von `Cmd+F` ausgelöst wird.

## Datenfluss

1. User drückt `Cmd+F`.
2. Die Artikelliste zeigt/fokussiert die Suchleiste.
3. User gibt Suchtext ein und wählt Bereich oder Umfang.
4. Die Liste bereitet Artikel wie bisher vor:
   - Quelle bestimmen: aktuelle Ansicht oder alle Artikel.
   - Sortierung anwenden.
   - bestehenden Listenfilter anwenden.
   - Suchfilter anwenden.
   - versteckte/gelesene Artikel nach bestehender Anzeige-Logik behandeln.
5. Navigation mit `Cmd+↑` / `Cmd+↓` arbeitet auf den sichtbaren Treffern.

## Fehler- und Leerzustände

Ein leerer Suchtext bedeutet: keine Suche aktiv.

Wenn die zugrunde liegende Ansicht leer ist, bleibt der bestehende Empty State.
Wenn die Ansicht Artikel enthält, aber die Suche keine Treffer liefert, erscheint
ein Such-Empty-State mit dem Suchbegriff und dem Hinweis, den Suchbereich oder den
Umfang zu ändern.

## Tests

Vor Produktivcode werden Tests ergänzt für:

- Suche nach Titel, Zusammenfassung und Inhalt.
- `Alles` findet über alle Suchfelder.
- Suche ist case-insensitive und ignoriert führende/trailing Leerzeichen.
- Leerer Suchtext filtert nicht.
- Suche kombiniert sich mit bestehendem Artikelfilter und Sortierung.

Der erste Implementierungsplan startet mit diesen Tests und lässt sie zuerst
fehlschlagen.
