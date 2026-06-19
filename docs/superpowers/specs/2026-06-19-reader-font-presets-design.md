# Reader-Schriftarten - Design

## Ziel

Die Artikelansicht soll getrennte Schrift-Presets fuer Titel und Fliesstext anbieten.
Zusätzlich sollen Textgroesse und Zeilenabstand des Fliesstextes direkt steuerbar sein.
Der Zugriff erfolgt direkt in der Artikelansicht und zusaetzlich in den Einstellungen.

## Verhalten

- Titel und Fliesstext haben je eine eigene Auswahl.
- Presets nach UI-Referenz: System, Geist, Inter, Manrope, DM Sans, Literata,
  Newsreader, IBM Plex Sans, Atkinson Hyperlegible, Source Serif 4, Libre Franklin,
  Lora, Merriweather, Noto Sans, Noto Serif, Roboto Slab, Crimson Pro, Fraunces, Serif.
- Die Auswahl wird global via `@AppStorage` gespeichert.
- Ungueltige gespeicherte Werte fallen auf System zurueck.
- Die Reader-Toolbar bekommt einen `Aa`/`textformat` Button mit Popover.
- Die Einstellungen zeigen dieselben zwei Picker im Bereich Lesen.
- Textgroesse wird global gespeichert und auf 14...24 px begrenzt.
- Zeilenabstand wird global gespeichert und auf 1...12 px begrenzt.

## Architektur

`ReaderFontPreset` kapselt Preset-Werte, Anzeigenamen und SwiftUI-Font-Erzeugung.
`ReaderTypography` kapselt Defaults und Grenzwerte fuer Textgroesse und Zeilenabstand.
`ReaderView` nutzt die gespeicherten Werte fuer Titel und Paragraphen.
`SettingsView` nutzt dieselben AppStorage-Keys und Presets.

## Nicht enthalten

- Keine freie Auswahl installierter System-Schriften.
- Keine pro-Artikel-Schrift.
- Keine mitgelieferten Font-Dateien in diesem Schritt; Custom-Fonts werden ueber ihren
  Font-Family-Namen angesprochen und brauchen spaeter ggf. Bundling/Lizenzklaerung.
