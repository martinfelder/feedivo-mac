# Language Selection Design

## Ziel

Feedivo bietet in den Einstellungen eine Sprachauswahl an. Standard ist `Nach System`,
daneben stehen Deutsch, Englisch, Französisch und Italienisch zur Auswahl.

## Verhalten

- Die Auswahl wird dauerhaft in `@AppStorage("appLanguage")` gespeichert.
- `Nach System` folgt der aktuellen macOS-Systemsprache.
- Eine konkrete Sprache setzt die SwiftUI-Locale fuer Hauptfenster und Einstellungen.
- Die App nutzt weiter den bestehenden String Catalog `Localizable.xcstrings`.

## Architektur

- `AppLanguage` kapselt die moeglichen Werte, Locale-Identifier und Picker-Titel.
- `FeedivoApp` liest `appLanguage` und setzt `.environment(\.locale, ...)`.
- `SettingsView` zeigt einen Picker im bestehenden Formular.
- Neue sichtbare Texte werden in `Localizable.xcstrings` gepflegt.

## Tests

- Unit-Test fuer `AppLanguage`: gueltige Werte, Fallback, Locale-Identifier.
- Build-Test prueft die Integration in SwiftUI und String Catalog.
