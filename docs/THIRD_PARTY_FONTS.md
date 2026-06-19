# Third Party Fonts

Feedivo bundles reader fonts so the typography choices work even when the fonts are
not installed on the user's Mac.

## Source

Fonts were downloaded from the Google Fonts GitHub repository:
https://github.com/google/fonts

## Bundled Font Files

The following fonts are bundled from `ofl/*` and are licensed under the SIL Open Font
License 1.1:

- Atkinson Hyperlegible
- Crimson Pro
- DM Sans
- Fraunces
- Geist
- IBM Plex Sans
- Inter
- Libre Franklin
- Literata
- Lora
- Manrope
- Merriweather
- Newsreader
- Noto Sans
- Noto Serif
- Source Serif 4

Roboto Slab is bundled from `apache/robotoslab` and is licensed under the Apache
License 2.0.

## Notes

- Font files live in `Feedivo/Resources/Fonts/`.
- License files live in the same directory as `OFL.txt` and `RobotoSlab-LICENSE.txt`.
- `ReaderFontRegistry` registers the bundled fonts at app startup.
- `ReaderFontPreset` uses the actual PostScript names exposed by the bundled files.
- Future font updates should re-check the license and PostScript names before commit.
