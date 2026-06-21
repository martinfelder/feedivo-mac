# M3 Rule Engine Design

## Ziel

M3 Block C fuehrt die erste automatische Tag-Zuweisung ein. Neue Artikel sollen beim
Feed-Refresh anhand gespeicherter Regeln automatisch passende Tags erhalten.

## Umfang

Implementiert wird nur die Logik, noch keine Regel-Oberflaeche:

- Eine neue `RuleEngine` wertet vorhandene `Rule`-Objekte gegen einen Artikel und
  dessen Feed aus.
- Unterstuetzte Felder: `title`, `summary`, `feedTitle`.
- Unterstuetzte Operatoren: `contains`, `startsWith`, `endsWith`.
- Vergleiche laufen case-insensitive und mit getrimmten Regelwerten.
- Deaktivierte Regeln, leere Suchwerte und Regeln ohne `assignTag` werden ignoriert.
- Tags werden nur hinzugefuegt, wenn der Artikel sie noch nicht besitzt.
- `FeedViewModel.refreshFeedContents` wendet Regeln auf neu eingefuegte Artikel an.
- Der OPML-Import profitiert automatisch, weil neue Feeds denselben Refresh-Pfad nutzen.

Nicht in diesem Block enthalten:

- Rule-UI.
- Regex.
- Mehrfachbedingungen.
- Rueckwirkendes Anwenden auf vorhandene Artikel.
- Aktionen ausser `Tag zuweisen`.
- Feed-Tags.

## Architektur

`RuleEngine` wird als kleiner Service unter `Feedivo/Services/RuleEngine.swift`
angelegt. Die Logik bleibt stateless und testbar:

- `applyRules(_:to:feed:)` nimmt Regeln, Artikel und Feed.
- Der Service prueft jede Regel auf Gueltigkeit und Treffer.
- Bei Treffern wird `rule.assignTag` dem Artikel angehaengt, sofern das Tag noch
  nicht vorhanden ist.

`FeedViewModel` bekommt keine Regel-UI-Verantwortung. Es liest beim Refresh die
gespeicherten Regeln aus SwiftData und ruft die Engine nur fuer neu erzeugte Artikel
auf. Bestehende Artikel bleiben unveraendert, damit ein Refresh keine alten
Artikelbestände unbemerkt umetikettiert.

## Datenfluss

1. Feedivo laedt einen Feed.
2. `refreshFeedContents` erkennt neue Artikel.
3. Fuer jeden neuen Artikel wird ein `Article` erzeugt und dem Feed angehaengt.
4. Aktive Regeln werden aus SwiftData gelesen.
5. `RuleEngine` prueft Feld, Operator und Wert.
6. Passende `assignTag`-Tags werden dem neuen Artikel hinzugefuegt.
7. Der normale `context.save()` speichert Artikel und Tags gemeinsam.

## Fehler- und Randfaelle

Unbekannte Felder oder Operatoren treffen nicht und erzeugen keinen Fehler. Das ist
fuer spaetere Migrationen robuster als ein harter Abbruch im Feed-Refresh.

Regeln ohne Tag, deaktivierte Regeln und Regeln mit leerem Suchwert werden ignoriert.
Artikel ohne Summary oder Feedtitel koennen nur ueber vorhandene Felder matchen.

## Tests

Die Umsetzung bekommt fokussierte Unit-Tests fuer:

- `contains`, `startsWith`, `endsWith`.
- Treffer auf Titel, Summary und Feedtitel.
- Deaktivierte Regeln, leere Werte, unbekannte Felder und Regeln ohne Tag.
- Keine doppelten Tags.
- Feed-Refresh taggt nur neu eingefuegte Artikel automatisch.

Die abschliessende Verifikation bleibt:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -skip-testing:FeedivoUITests -derivedDataPath /private/tmp/feedivo-m3-rule-engine-derived-data
```

## Dokumentation

Nach der Umsetzung werden `AGENTS.md` und `docs/FEATURES.md` aktualisiert:

- Rule Engine als M3-Basis fertig markieren.
- Klarstellen, dass die Rule-UI separat folgt.
- Rueckwirkendes Anwenden und komplexe Regeln bewusst als spaetere Schritte nennen.
