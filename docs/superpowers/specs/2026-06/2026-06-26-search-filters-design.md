# Feature 9.2 Search Filters Design

## Ziel

Feature 9.2 erweitert die bestehende Artikelsuche aus Feature 9.1 um sichtbare,
kombinierbare Filter für Feed, Tag, Zeitraum und Status. Der Slice bleibt bewusst
in der mittleren Artikelliste und baut auf der vorhandenen `Cmd+F`-Suchleiste auf.

## Entscheidung

Gewählt ist Variante B: eine kompakte Filterleiste direkt bei der Suche. Die Suche
bleibt oben in der Artikelliste. Wenn sie geöffnet ist, werden zusätzliche
Filter-Menüs angeboten:

- Feed: alle Feeds oder ein konkreter Feed
- Tag: alle Tags oder ein konkreter Tag
- Zeitraum: jederzeit, heute oder diese Woche
- Status: alle, ungelesen, gelesen, mit Stern oder archiviert

## Verhalten

Der Suchtext bleibt optional. Filter können also auch ohne Suchbegriff verwendet
werden. Die Auswahl `Aktuelle Ansicht` begrenzt Suche und Filter auf die aktuell
ausgewählte Sidebar-Ansicht. Die Auswahl `Alle Artikel` nutzt alle gespeicherten
Artikel als Ausgangsmenge und wendet danach Suchtext und Filter an.

Die bestehende Listenlogik bleibt erhalten: Sortierung, der globale
Artikellistenfilter, die Anzeige gelesener Artikel und die Logik für ausgeblendete
Artikel laufen weiterhin über die bestehende Pipeline.

## Nicht Teil dieses Slices

- Kein eigener erweiterter Suchdialog.
- Keine Speicherung der Suchfilter über App-Neustarts.
- Keine Spotlight-Integration; das bleibt Feature 9.3.

## Tests

Der Kern wird ohne UI getestet. `ArticleListQueryTests` prüft:

- Feed-Filter schränkt Ergebnisse auf den gewählten Feed ein.
- Tag-Filter findet direkt getaggte Artikel und Artikel aus getaggten Feeds.
- Zeitraum-Filter unterstützt heute und diese Woche.
- Status-Filter unterstützt ungelesen, gelesen, Stern und Archiv.
- Suchtext und mehrere Filter lassen sich kombinieren.
