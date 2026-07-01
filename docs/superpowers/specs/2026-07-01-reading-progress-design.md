# Lesefortschritt im Reader

## Ziel

Feedivo zeigt im Reader einen ruhigen Lesefortschritt und kann Artikel beim erneuten
Öffnen an der zuletzt gelesenen Position fortsetzen. Das Feature soll sich
mac-like, unaufdringlich und zuverlässig anfühlen.

## Produktentscheidungen

- Die Fortschrittsanzeige ist eine dünne horizontale Linie direkt unter der
  Reader-Toolbar.
- Die Linie ist 2 px hoch, nutzt die Akzentfarbe und bleibt visuell leise.
- Feedivo speichert den Fortschritt pro Artikel als normalisierten Wert von
  `0.0...1.0`.
- Automatisches Fortsetzen ist standardmäßig aktiv.
- Benutzer können das automatische Fortsetzen per Einstellung deaktivieren.
- Auch bei deaktiviertem Fortsetzen wird der Fortschritt weiter angezeigt und
  gespeichert.
- Der native Reader und der Vollartikel-Modus bekommen Fortschritt und
  Wiederaufnahme.
- Die Original-Webseite in `WKWebView` bleibt für v1 außen vor.

## Einstellung

Neue Einstellung:

- Bereich: `Einstellungen -> Darstellung`
- Titel: `Artikel an letzter Leseposition fortsetzen`
- Standard: an
- Wirkung:
  - an: Beim Öffnen eines Artikels springt der Reader ungefähr zur gespeicherten
    Position.
  - aus: Der Reader startet oben, zeigt und speichert aber weiterhin den
    Fortschritt.

Die Einstellung gehört zu `ReaderTypographySettings` oder einer kleinen
benachbarten Reader-Settings-Struktur, damit Reader-nahe Defaults zusammenbleiben.

## Datenmodell

`Article` erhält ein neues Feld:

- `readingProgress: Double = 0`

Der Wert wird geklemmt:

- Werte kleiner als 0 werden als 0 behandelt.
- Werte größer als 1 werden als 1 behandelt.
- Am Artikelende darf 1 gespeichert werden.

Für CloudKit/SwiftData bleibt das Feld ein Skalar mit Default-Wert. Es ist keine
Relationship und kein Blob.

## Reader-Verhalten

### Fortschritt berechnen

Der Reader berechnet den Fortschritt aus Scroll-Position und Inhaltshöhe:

- `progress = visibleTop / max(scrollableHeight, 1)`
- Der Wert wird auf `0...1` geklemmt.
- Kurze Artikel ohne echten Scrollbereich gelten als `0`, bis eine robuste
  Enderkennung vorhanden ist.

### Fortschritt speichern

Der Reader speichert gedrosselt:

- nicht bei jeder Pixelbewegung
- nur bei sinnvoller Änderung, z. B. ab ca. 1 Prozentpunkt Unterschied
- zusätzlich beim Verschwinden des Readers, sofern sich der Wert geändert hat

Das vermeidet unnötige SwiftData-Schreiblast während des Scrollens.

### Position wiederherstellen

Beim Öffnen eines Artikels:

- Wenn die Einstellung aktiv ist und `readingProgress > 0`, scrollt Feedivo nach
  dem Layoutaufbau ungefähr an diese Position.
- Der Sprung passiert erst, wenn Inhalt und Scroll-Geometrie verfügbar sind.
- Der Sprung wird pro Reader-Instanz nur einmal automatisch ausgeführt, damit
  spätere Layoutänderungen den Benutzer nicht zurückreißen.

Beim Wechsel zwischen Artikeln bekommt jede `ReaderView` über die bestehende
`.id(article.id)`-Logik eine frische Instanz.

## Vollartikel-Modus

Der Vollartikel-Modus nutzt dieselbe UI-Linie und dieselbe gespeicherte
Artikelposition.

Für v1 ist das ausreichend, auch wenn nativer Feed-Inhalt und extrahierter
Vollartikel unterschiedlich lang sein können. Der gespeicherte Prozentwert ist
absichtlich ein ungefährer Lesestand, kein exakter Absatzanker.

## Originalansicht

Die `WKWebView`-Originalansicht bekommt in v1 keine Fortschrittslinie und keine
Wiederaufnahme. Grund: WebView-Scrollposition, Seiten-Reloads und fremde Layouts
brauchen eine eigene robuste Lösung und sind für den ersten Slice nicht nötig.

## UI-Platzierung

Die Linie liegt in einem Overlay/Container oberhalb des scrollenden Inhalts und
unterhalb der Toolbar. Sie darf:

- keine Reader-Inhalte verschieben
- nicht in der Artikelliste erscheinen
- nicht in der Sidebar erscheinen
- nicht im Inspector erscheinen

Wenn kein scrollbarer Reader-Inhalt aktiv ist, bleibt sie unsichtbar oder bei 0.

## Tests

Automatisierte Tests decken die testbaren Teile ab:

- Fortschrittswerte werden auf `0...1` geklemmt.
- Speicherung wird nur bei sinnvollem Unterschied empfohlen.
- Die Fortsetzen-Einstellung hat den richtigen Default.
- `Article.lightFetchDescriptor` berücksichtigt das neue Skalarfeld, sofern es für
  bestehende schnelle Query-Pfade relevant ist.
- Das Modell hat für CloudKit einen Default-Wert.

Manuell zu prüfen:

- Linie bewegt sich beim Scrollen im nativen Reader.
- Öffnen eines Artikels springt bei aktivem Toggle an die gespeicherte Position.
- Toggle aus startet oben, speichert aber weiter.
- Vollartikel-Modus zeigt und nutzt den Fortschritt.
- Originalansicht bleibt unverändert.

## Nicht in diesem Slice

- Absatzgenaue Wiederaufnahme
- Fortschritt für `WKWebView`
- Sync-Konfliktlogik für paralleles Lesen auf mehreren Geräten
- Prozentanzeige als Text
- Fortsetzen-Hinweis/Chip
