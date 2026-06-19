# Reader-Schriftarten - Design

## Ziel

Die Artikelansicht soll getrennte Schrift-Presets fuer Titel und Fliesstext anbieten.
Zusätzlich sollen Textgroesse des Fliesstextes, Titel- und Fliesstext-
Zeilenabstand sowie die maximale Artikelbreite direkt steuerbar sein.
Der Zugriff erfolgt direkt in der Artikelansicht und zusaetzlich in den Einstellungen.

## Verhalten

- Titel und Fliesstext haben je eine eigene Auswahl.
- Die Metazeile oberhalb des Titels nutzt ebenfalls die Fliesstext-Schrift, aber
  proportional kleiner.
- Presets nach UI-Referenz: System, Geist, Inter, Manrope, DM Sans, Literata,
  Newsreader, IBM Plex Sans, Atkinson Hyperlegible, Source Serif 4, Libre Franklin,
  Lora, Merriweather, Noto Sans, Noto Serif, Roboto Slab, Crimson Pro, Fraunces, Serif.
- Die Auswahl wird global via `@AppStorage` gespeichert.
- Ungueltige gespeicherte Werte fallen auf System zurueck.
- Die Reader-Toolbar bekommt einen `Aa`/`textformat` Button mit Popover.
- Die Einstellungen zeigen dieselben zwei Picker im Bereich Lesen.
- Textgroesse wird global gespeichert und auf 14...24 px begrenzt.
- Titel-Zeilenabstand wird global gespeichert und auf 0...10 px begrenzt.
- Fliesstext-Zeilenabstand wird global gespeichert und auf 1...12 px begrenzt.
- Artikelbreite wird global gespeichert und auf 520...980 px begrenzt.

## Architektur

`ReaderFontPreset` kapselt Preset-Werte, Anzeigenamen, bekannte PostScript-Kandidaten,
gebundelte Fontdateien und SwiftUI-Font-Erzeugung.
`ReaderFontRegistry` registriert gebundelte TTF-Dateien beim App-Start via CoreText.
`ReaderTypography` kapselt Defaults und Grenzwerte fuer Textgroesse, Titel- und
Fliesstext-Zeilenabstand sowie Artikelbreite.
`ReaderView` nutzt die gespeicherten Werte fuer Titel und Paragraphen.
`SettingsView` nutzt dieselben AppStorage-Keys und Presets.

## Nicht enthalten

- Keine freie Auswahl installierter System-Schriften.
- Keine pro-Artikel-Schrift.
- Keine Schnitte ausser Regular/Variable Regular in diesem Schritt; Fett/Italic kann
  spaeter gezielter ergänzt werden.
