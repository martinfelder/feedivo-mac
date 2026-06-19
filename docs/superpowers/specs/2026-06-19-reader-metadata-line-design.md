# Reader-Metazeile - Design

## Ziel

Die Artikelansicht zeigt oberhalb des Titels eine ruhige, linksbuendige Metazeile mit
Kontext zum Artikel:

`Feedname · ca. 3 Min. Lesezeit · vor 2 Std.`

## Verhalten

- Der Feedname kommt aus `article.feed?.title`.
- Die ungefaehre Lesezeit wird aus `article.content` berechnet, mit `article.summary`
  als Fallback.
- Die Berechnung nutzt 200 Woerter pro Minute und zeigt mindestens 1 Minute.
- Das Artikelalter nutzt die bestehende `Date.feedivoRelativeDisplay` Darstellung.
- Fehlende Teile werden ausgelassen; die Trennpunkte werden nur zwischen vorhandenen
  Teilen gesetzt.

## Architektur

`ReaderMetadataFormatter` kapselt Lesezeit- und Metadaten-Formatierung. `ReaderView`
bleibt fuer das Layout verantwortlich und zeigt nur die fertige Metazeile an.

Der sichtbare Lesezeit-Text laeuft ueber `Localizable.xcstrings` und `L10n`, damit die
i18n-Grundlage erhalten bleibt.

## Tests

Unit-Tests pruefen:

- kurze Texte ergeben mindestens `ca. 1 Min. Lesezeit`
- laengere Texte werden auf Minuten aufgerundet
- `content` wird vor `summary` verwendet
