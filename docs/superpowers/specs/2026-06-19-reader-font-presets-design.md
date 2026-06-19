# Reader-Schriftarten - Design

## Ziel

Die Artikelansicht soll getrennte Schrift-Presets fuer Titel und Fliesstext anbieten.
Der Zugriff erfolgt direkt in der Artikelansicht und zusaetzlich in den Einstellungen.

## Verhalten

- Titel und Fliesstext haben je eine eigene Auswahl.
- Presets: System, Serif, Rounded, Monospace.
- Die Auswahl wird global via `@AppStorage` gespeichert.
- Ungueltige gespeicherte Werte fallen auf System zurueck.
- Die Reader-Toolbar bekommt einen `Aa`/`textformat` Button mit Popover.
- Die Einstellungen zeigen dieselben zwei Picker im Bereich Lesen.

## Architektur

`ReaderFontPreset` kapselt Preset-Werte, Lokalisierung und `Font.Design`.
`ReaderView` nutzt die gespeicherten Werte fuer Titel und Paragraphen.
`SettingsView` nutzt dieselben AppStorage-Keys und Presets.

## Nicht enthalten

- Keine freie Auswahl installierter System-Schriften.
- Keine pro-Artikel-Schrift.
- Keine Schriftgroesse in diesem Schritt.
