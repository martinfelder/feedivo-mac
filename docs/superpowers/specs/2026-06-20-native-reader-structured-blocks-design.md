# Native Reader Structured Blocks

Datum: 2026-06-20

## Ziel

Der native Feedivo Reader soll einfache HTML-Strukturen besser erhalten. Aktuell rendert
`ReaderContentRenderer` gespeicherte Feed-Inhalte als Bilder und flache Absätze. Dieser
Ausbau fuehrt strukturierte Reader-Bloecke fuer Ueberschriften, Zitate und Listenpunkte ein.

Damit wirken Feed-Inhalte im nativen SwiftUI Reader naeher am Originalartikel, ohne direkt
eine vollstaendige HTML-/Readability-Engine einzubauen.

## Umfang

Neue oder erweiterte Blocktypen:

- `paragraph(String)` bleibt fuer normalen Fliesstext.
- `heading(String)` fuer `h1` bis `h6`.
- `quote(String)` fuer `blockquote`.
- `listItem(String)` fuer `li`.
- `image(urlString: String)` bleibt fuer Artikelbilder.

Links werden in diesem Schritt nicht als eigene klickbare Inline-Elemente umgesetzt. Sie
bleiben Teil des bereinigten Textes. Klickbare Links folgen spaeter als eigener Ausbau,
weil dafuer `AttributedString`, Link-Ziele und UI-Verhalten sauber zusammen geplant werden
sollten.

## UX

`ReaderView` rendert die neuen Bloecke nativ:

- Ueberschriften erscheinen groesser und semibold, aber kleiner als der Artikeltitel.
- Zitate werden links leicht eingerueckt und mit einer dezenten vertikalen Linie markiert.
- Listenpunkte erhalten einen einfachen Bullet und verwenden dieselbe Fliesstext-Typografie.
- Absätze und Bilder behalten ihr bisheriges Verhalten.

Alle neuen Textbloecke folgen weiterhin den vorhandenen Reader-Einstellungen fuer
Fliesstext-Schrift, Textgroesse, Zeilenabstand und Artikelbreite. Der Ausbau fuegt keine
neuen Einstellungen hinzu.

## Architektur

`ReaderContentBlock` wird um die neuen Cases erweitert. `ReaderContentRenderer` bleibt der
zentrale Ort fuer die Umwandlung von Feed-HTML/Text in Reader-Bloecke.

Der Renderer soll einfache HTML-Struktur erkennen, bevor HTML zu Plain Text reduziert wird.
Die Umsetzung darf konservativ sein:

- Bekannte Block-Tags werden in Reihenfolge verarbeitet.
- Unbekannte oder kaputte HTML-Strukturen fallen auf normale Absätze zurueck.
- Bilder werden weiterhin als eigene Bildbloecke vor Textbloecken ausgegeben, wie bisher.

Diese konservative Strategie verhindert, dass schlecht geformte Feed-Inhalte den Reader
leer oder unlesbar machen.

## Datenfluss

1. `ReaderView` ruft `ReaderContentRenderer.blocks(summary:content:fallbackImageURL:)` auf.
2. Der Renderer waehlt wie bisher `content` vor `summary`.
3. Bilder werden extrahiert.
4. Textstruktur wird in `heading`, `quote`, `listItem` und `paragraph` aufgeteilt.
5. `ReaderView` rendert jeden Blocktyp mit passender SwiftUI-Darstellung.

## Fehlerverhalten

Wenn HTML nicht sauber gelesen werden kann, gibt der Renderer normale Absätze aus. Leere
Blockinhalte werden verworfen. Die App crasht nicht bei kaputten Tags, leeren Listen oder
verschachtelten Elementen.

## Tests

Unit-Tests erweitern die bestehende `ReaderContentRenderer`-Abdeckung:

- Ueberschriften werden als `heading` erkannt.
- `blockquote` wird als `quote` erkannt.
- `li` wird als `listItem` erkannt.
- Gemischte Inhalte behalten die Reihenfolge der Textbloecke.
- Leere/kaputte Inhalte erzeugen keine leeren Bloecke.

Build und bestehende Unit-Tests muessen weiterhin erfolgreich laufen.

## Nicht Teil dieses Schritts

- Klickbare Inline-Links.
- Vollstaendige HTML-Layout-Engine.
- Readability-Extraktion aus Webseiten.
- Verschachtelte Listen mit mehreren Ebenen.
- Neue Reader-Einstellungen.
