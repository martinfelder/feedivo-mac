# Native Reader Rendering Design

## Ziel

Feedivo rendert gespeicherte Feed-Inhalte nicht mehr als rohen HTML-/Textblock,
sondern als einfache native Reader-Bloecke fuer SwiftUI.

## Umfang dieser Iteration

- HTML-Fragmente aus `Article.content` oder `Article.summary` werden in lesbare
  Absätze umgewandelt.
- `<img src="...">` wird als eigener Bildblock erkannt.
- Wenn kein Content vorhanden ist, faellt der Renderer auf Summary zurueck.
- Wenn kein Bild im HTML vorkommt, kann `Article.imageURL` als Bildblock genutzt werden.
- Der Reader bleibt ein nativer SwiftUI-Reader. WebView und Readability kommen spaeter.

## Architektur

- `ReaderContentBlock` beschreibt native Reader-Bloecke: Absatz oder Bild.
- `ReaderContentRenderer` ist eine kleine, testbare Rendering-Schicht ohne SwiftData-Abhaengigkeit.
- `ReaderView` fragt den Renderer ab und rendert die Bloecke mit SwiftUI.

## Tests

- HTML mit Absätzen und Inline-Formatierung wird zu sauberen Absätzen.
- HTML-Bilder werden als Bildblock erkannt.
- Summary-Fallback greift, wenn Content leer ist.
