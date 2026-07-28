# Einstellungen im NetNewsWire-Stil Design

## Ziel

Feedivos Einstellungsfenster (`Feedivo/Views/Settings/SettingsView.swift`, `NewSettingsView`) soll optisch
dem Preferences-Fenster von NetNewsWire angeglichen werden: schlanker, "macOS-like", ohne die aktuelle
Karten-/Eyebrow-Optik. Referenz ist der tatsächliche NetNewsWire-Quellcode
(`Mac/Preferences/PreferencesWindowController.swift`, `Mac/Preferences/General/GeneralPreferencesViewController.swift`,
öffentlich unter github.com/Ranchero-Software/NetNewsWire).

## Was NetNewsWire tatsächlich macht (verifiziert im Quellcode)

- Fixe Fensterbreite 512pt; die Höhe wird bei jedem Reiter-Wechsel per `NSWindow.setFrame(display:animate:)`
  neu berechnet und animiert — kein Scrollen.
- `NSToolbar` mit `.iconAndLabel`-Anzeige als Reiter-Umschalter (3 Reiter: Allgemein/Accounts/Erweitert).
- Reine AppKit-Formulare: rechtsbündiges Label + linksbündiges Steuerelement (Pop-up-Button, Checkbox), kein
  Beschreibungstext unter den Zeilen, keine Karten-Hintergründe, keine Großschrift-Sektionsüberschriften.

## Design

### Reiter (unverändert)

Die bestehenden 7 Reiter (Allgemein/Darstellung/Mitteilungen/Refresh/Cleanup/Sync/Info) bleiben erhalten —
keine inhaltliche Umsortierung. `TabView(selection:)` mit `.tabItem` bleibt die Grundlage (SwiftUI rendert
das auf macOS bereits als Toolbar-artigen Umschalter, passend zum NetNewsWire-Look).

### Fenstergröße: automatische Höhenanpassung statt Scrollen

`Feedivo/App/FeedivoApp.swift:129-137` — die `Settings { }`-Szene bekommt `.windowResizability(.contentSize)`
(verfügbar ab macOS 13) statt einer festen `.defaultSize(width: 680, height: 560)`. Jede Reiter-Ansicht
meldet damit ihre natürliche Höhe ans Fenster; SwiftUI übernimmt das Resizing/die Animation selbst — kein
manuelles `NSWindow`-Handling wie im NetNewsWire-Original nötig, das ist die SwiftUI-native Entsprechung.

Voraussetzung: Der bisherige `ScrollView`-Wrapper in `settingsTab(_:)` (`SettingsView.swift:87-93`) entfällt;
stattdessen bekommt der Inhalt `.fixedSize(horizontal: false, vertical: true)`, damit er seine ideale Höhe
statt unendlicher Ausdehnung meldet. Fensterbreite sinkt von 680 auf 512, passend zum Original.

### Zeilen-Layout: rechtsbündiges Formular statt Karten

`NewSettingRow` (`SettingsView.swift:147-173`) wird umgebaut: Titel steht rechtsbündig links vom
Steuerelement (klassisches macOS-Formular-Layout), statt wie bisher linksbündig mit Titel+Beschreibung
übereinander und Control weit rechts in einer 310pt-Spalte. Die Beschreibung bleibt erhalten (Nutzer-Wunsch:
nicht komplett entfernen, da hilfreich für Einsteiger — CLAUDE.md nennt den Entwickler einen Swift-Anfänger),
wird aber kleiner/dezenter direkt unter dem Label platziert statt gleichrangig neben dem Titel.

`NewSettingsBlock` (`SettingsView.swift:122-145`) verliert die große Großschrift-Eyebrow-Überschrift
(`.textCase(.uppercase)`, `.tracking(0.7)`, bold) und die Karten-Trennlinien-Logik; Gruppierung erfolgt nur
noch über Abstand (vertikales Padding zwischen Gruppen), wie im NetNewsWire-Original. Ein schlichteres,
kleineres Label (kein Uppercase-Bold-Stil) kann als optionale Gruppenüberschrift bleiben, wenn eine Seite
mehrere thematische Blöcke hat.

`NewInfoRow` (`SettingsView.swift:175-205`, Karten mit Icon+Titel+Beschreibung, u. a. auf der Info-Seite
verwendet) wird nicht Teil dieses Redesigns — sie wird separat bewertet, falls sie nach dem Umbau der
Standard-Zeilen optisch nicht mehr passt.

## Nicht Teil dieses Designs

- Keine Reduktion der Reiter-Anzahl (Nutzer-Entscheidung: 7 Reiter bleiben).
- Kein Wechsel von SwiftUI zu AppKit — die Umsetzung bleibt vollständig in SwiftUI, nur die Optik nähert
  sich dem NetNewsWire-Original an.
- `NewInfoRow`/Info-Seiten-Sonderkomponenten werden nicht in diesem Zug angepasst.

## Tests

Reine SwiftUI-Layout-Änderung ohne neue Business-Logik. Manuelle Verifikation: Einstellungsfenster öffnen,
jeden der 7 Reiter durchklicken und prüfen, dass sich die Fensterhöhe automatisch anpasst (ohne Scrollen,
ohne abgeschnittenen Inhalt), dass Label/Control rechtsbündig ausgerichtet sind und die Beschreibungen
sichtbar, aber dezent wirken.
