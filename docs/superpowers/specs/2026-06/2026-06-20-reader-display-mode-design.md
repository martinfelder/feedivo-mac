# Reader-Anzeigemodus

Datum: 2026-06-20

## Ziel

Feedivo soll im Reader zwischen zwei Darstellungen wechseln koennen:

- Nativer Reader: die bestehende SwiftUI-Ansicht mit gespeicherten Feed-Inhalten,
  Typografie-Einstellungen, Artikelbildern und Metadaten.
- Originalansicht: eine Web-Ansicht des Originalartikels ueber die Artikel-URL.

Der native Reader bleibt der Standard. Die Auswahl wird global gespeichert und gilt
fuer alle Artikel. Ein spaeterer Ausbau auf artikel- oder feed-spezifische Modi bleibt
moeglich, ist aber nicht Teil dieses Schritts.

## UX

In den Einstellungen unter Lesen wird ein Picker fuer den Reader-Modus angeboten:

- Nativer Reader
- Originalansicht

Zusaetzlich erhaelt die Reader-Toolbar einen direkten Umschalter, damit der Benutzer
beim Lesen schnell zwischen beiden Modi wechseln kann. Der Umschalter veraendert dieselbe
globale Einstellung wie der Picker in den Einstellungen.

Wenn ein Artikel keinen gueltigen Originallink hat, zeigt Feedivo immer den nativen Reader.
Die Originalansicht ist in diesem Fall deaktiviert oder faellt sichtbar unaufgeregt auf den
nativen Reader zurueck.

## Architektur

Es wird ein kleiner `ReaderDisplayMode`-Typ eingefuehrt. Er kapselt die gespeicherten
Raw Values und die lokalisierbaren Labels fuer die UI. Die Auswahl wird per `@AppStorage`
unter einem stabilen Key gespeichert, zum Beispiel `readerDisplayMode`.

`ReaderView` bleibt der zentrale Einstieg fuer die Detailspalte. Die bestehende native
Ansicht wird intern als eigener Teil weiterverwendet. Fuer die Originalansicht wird ein
macOS-`WKWebView`-Wrapper als SwiftUI-View eingefuehrt, zum Beispiel `WebContentView`.
Die View erhaelt eine `URL` und laedt diese im WebView.

## Datenfluss

1. Der Benutzer waehlt den Modus in den Einstellungen oder in der Reader-Toolbar.
2. `@AppStorage` speichert den globalen Modus.
3. `ReaderView` liest den Modus und prueft, ob der aktuelle Artikel eine gueltige URL hat.
4. Bei `native` oder fehlender URL wird die bestehende native Darstellung gezeigt.
5. Bei `web` und gueltiger URL wird die Web-Ansicht geladen.

## Fehlerverhalten

Ungueltige oder fehlende Artikel-URLs verhindern die Web-Ansicht. Die App crasht nicht und
zeigt stattdessen den nativen Reader.

Ladefehler im WebView werden fuer diesen ersten Schritt nicht umfangreich behandelt. Die
WebView darf ihre Standarddarstellung zeigen. Eine eigene Fehlerseite kann spaeter folgen.

## Lokalisierung

Alle sichtbaren neuen Texte werden im String Catalog fuer Deutsch, Englisch, Franzoesisch
und Italienisch angelegt. Dazu gehoeren mindestens:

- Reader-Modus
- Nativer Reader
- Originalansicht
- Hilfetext fuer den Toolbar-Umschalter

## Tests und Verifikation

Unit-Tests pruefen den neuen Modus-Typ und die URL-Fallback-Logik, soweit sie aus der View
heraus in testbare Helper extrahiert wird.

Manuelle Verifikation:

- Standard ist nativer Reader.
- Einstellung auf Originalansicht zeigt fuer Artikel mit Link die Web-Ansicht.
- Artikel ohne Link bleiben im nativen Reader.
- Toolbar-Umschalter und Settings-Picker bleiben synchron.
- Build und bestehende Unit-Tests laufen erfolgreich.

## Nicht Teil dieses Schritts

- Reader-Modus pro Artikel oder pro Feed speichern.
- Safari-Reader-Extraktion oder Readability-Parsing.
- Erweiterte WebView-Fehlerseite.
- Offline-Speicherung kompletter Webseiten.
