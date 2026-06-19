# Artikelbilder laden - Design

## Ziel

Artikelbilder sollen zuverlaessiger erscheinen. Die bestehende UI nutzt bereits
`AsyncImage` in Artikelliste und Reader; die fehlende Stelle ist deshalb vor allem
das Speichern einer brauchbaren `Article.imageURL` beim Feed-Import.

## Umfang

- Relative Bild-URLs aus Feed-Inhalten werden gegen die Feed-URL zu absoluten URLs
  aufgeloest.
- Bereits erkannte Quellen bleiben erhalten: Media RSS, iTunes Image, Enclosures,
  JSON Feed Bilder und erstes `<img>` in HTML-Inhalten.
- HTML-Bilder aus `content` oder `description` werden weiterhin bevorzugt, wenn kein
  explizites Feed-Bild vorhanden ist.
- Die UI bleibt bei `AsyncImage`; Caching oder eigene Download-Logik kommt spaeter.

## Architektur

`FeedService` bekommt eine kleine Normalisierungsschicht fuer Bild-URLs. Alle Parser
geben die jeweilige `sourceURL` bis zur Bild-Erkennung weiter. Relative Werte wie
`/assets/image.jpg` oder `bilder/teaser.jpg` werden mit `URL(string:relativeTo:)`
gegen die Feed-URL aufgeloest.

## Tests

Unit-Tests pruefen, dass relative Bild-URLs aus RSS-HTML und Media RSS beim Parsen als
absolute URLs in `ParsedArticle.imageURL` landen.

## Nicht enthalten

- Kein persistenter Image-Cache.
- Keine manuelle Bildauswahl pro Artikel.
- Keine Migration bestehender Artikel; bereits gespeicherte Artikel erhalten Bilder
  erst nach erneutem Feed-Abruf oder spaeterer Refresh-Logik.
