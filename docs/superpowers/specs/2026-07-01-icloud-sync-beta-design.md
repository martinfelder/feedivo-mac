# iCloud Sync Beta Design

## Ziel

Feedivo bekommt iCloud Sync als bewusst aktivierbare Beta-Option. Die erste Version nutzt SwiftData mit CloudKit, bleibt eng an der bestehenden Architektur und verspricht produktseitig nur den Sync von Struktur- und Statusdaten: Feeds, Ordner, Tags, Regeln, intelligente Ordner und Artikelstatus.

## Entscheidungen

- Gewählter Ansatz: SwiftData + CloudKit direkt über `ModelConfiguration`.
- Aktivierung: Beta-Schalter in den Einstellungen, nicht automatisch für alle Benutzer.
- Store-Wechsel: Änderung des Schalters wirkt erst nach Neustart der App, weil der SwiftData-Container beim App-Start gebaut wird.
- Datenumfang: Der erste Produktumfang ist Struktur und Status. Offline-Inhalte, Caches, Bilder, Favicons und Feed-Logs sind nicht Teil des Produktversprechens für die erste Sync-Version.
- Konflikte: Kein eigener Konfliktdialog in Version 1. SwiftData/CloudKit übernimmt Merge-Verhalten; praktisch gilt bei konkurrierenden Änderungen "letzte Änderung gewinnt".

## Kontext

Feedivo nutzt bereits SwiftData und hält alle Models in einer zentralen `Schema`-Definition in `Feedivo/App/FeedivoApp.swift`. Der bestehende Datenbankstart ist robust: Wenn der normale on-disk-Container nicht geöffnet werden kann, startet Feedivo mit einem In-Memory-Fallback und zeigt den Fehler über `DatabaseLoadState`.

Die Models sind bereits weitgehend CloudKit-tauglich vorbereitet:

- persistierte Properties sind optional oder haben Default-Werte,
- URLs werden als `String` gespeichert,
- problematische `.cascade`-Relationships wurden weitgehend durch `.nullify` ersetzt,
- große Cache-Dateien liegen außerhalb von SwiftData.

Noch nicht vorhanden sind iCloud/CloudKit-Entitlements, eine echte Sync-Konfiguration und eine nutzbare Sync-Einstellungsseite.

## Architektur

### CloudSyncSettings

Ein neuer kleiner Settings-Typ kapselt die Sync-Keys und Defaults:

- `CloudSyncSettings.isEnabledKey`
- `CloudSyncSettings.defaultIsEnabled = false`
- `CloudSyncSettings.requiresRestartAfterChangeKey`

Der Schalter bleibt in `UserDefaults`/`@AppStorage`, weil die Entscheidung vor dem Erstellen des `ModelContainer` gelesen werden muss.

### ModelContainer-Erzeugung

`FeedivoApp` baut den SwiftData-Container über eine kleine Factory-Funktion, damit Tests die Konfiguration prüfen können.

Sync aus:

```swift
let configuration = ModelConfiguration(
    schema: Self.schema,
    cloudKitDatabase: .none
)
```

Sync an:

```swift
let configuration = ModelConfiguration(
    schema: Self.schema,
    cloudKitDatabase: .private("iCloud.ch.martin.Feedivo")
)
```

Falls sich im Build zeigt, dass `.automatic` mit den Xcode-Capabilities stabiler ist, wird `.automatic` statt `.private(...)` verwendet. Die Entscheidung wird im Code kommentiert und in `AGENTS.md` dokumentiert.

Der In-Memory-Fallback bleibt immer CloudKit-frei:

```swift
let inMemoryConfiguration = ModelConfiguration(
    isStoredInMemoryOnly: true,
    cloudKitDatabase: .none
)
```

### Entitlements

`Feedivo/Feedivo.entitlements` erhält die CloudKit-relevanten Keys:

- `com.apple.developer.icloud-container-identifiers`
- `com.apple.developer.icloud-services`

Der Container-Name wird an die Bundle-ID angelehnt: `iCloud.ch.martin.Feedivo`.

Die bestehenden Entitlements für Sandbox, Netzwerk und Datei-Export bleiben unverändert.

### Settings-UI

`NewSyncSettingsView` ersetzt den Platzhalter durch:

- iCloud-Symbol und kurze Beta-Erklärung,
- Toggle "iCloud Sync Beta",
- Statuszeile:
  - "Lokal gespeichert", wenn Sync aus ist,
  - "iCloud Sync beim nächsten Start aktiv", wenn der Schalter geändert wurde,
  - "iCloud Sync aktiv", wenn die App mit CloudKit-Konfiguration gestartet wurde,
  - "Datenbank konnte nicht geladen werden", wenn `DatabaseLoadState.initializationError` gesetzt ist,
- kurzer Hinweis, dass ein Neustart nötig ist.

Die UI darf keine technischen Begriffe wie `ModelConfiguration` zeigen. Sie darf aber klar sagen, dass Sync eine Beta ist und nach einer Änderung ein Neustart nötig ist.

### Datenumfang und bekannte Einschränkung

Da Ansatz 1 denselben SwiftData-Store verwendet, kann SwiftData technisch alle persistierten Model-Felder synchronisieren. Das Produktversprechen bleibt enger:

- Erwartet synchronisiert:
  - Feeds und Feed-Ordner,
  - Tags und Feed-/Artikel-Zuordnung,
  - Regeln und Bedingungen,
  - intelligente Ordner und Bedingungen,
  - Artikel-Metadaten und Statusfelder wie gelesen, Stern, archiviert und ausgeblendet.
- Lokal oder nicht garantiert:
  - Bild-/Favicon-/HTML-Caches auf Disk,
  - Feed-Abruf-Logs als produktseitige Sync-Zusage,
  - Offline-Volltexte und große Artikelinhalte.

Wenn Tests oder manuelle Prüfung zeigen, dass große Inhalte den Sync spürbar belasten, wird als Folgearbeit ein Modell-Splitting geplant: Artikel-Metadaten bleiben syncbar, große Inhalte wandern in ein lokales Model oder in lokalen Dateispeicher.

## Fehlerbehandlung

Feedivo darf durch CloudKit-Aktivierung nicht ohne Erklärung abstürzen.

- Container-Fehler laufen weiter über den bestehenden In-Memory-Fallback.
- Der Fehlertext wird in `DatabaseLoadState.initializationError` gehalten.
- Die Sync-Settings-Seite zeigt bei Fallback einen verständlichen Hinweis.
- Feedivo versucht nicht, während einer laufenden Sitzung zwischen lokalem Store und CloudKit-Store umzuschalten.

## Tests

Neue oder angepasste Tests prüfen:

- Sync aus erzeugt eine Konfiguration mit `cloudKitDatabase: .none`.
- Sync an erzeugt eine CloudKit-Konfiguration.
- In-Memory-Fallback-Konfiguration bleibt `isStoredInMemoryOnly == true` und CloudKit-frei.
- `CloudSyncSettings` nutzt Default `false`.
- Die Settings-UI schreibt den Toggle-Wert in den erwarteten `@AppStorage`-Key.

Abschlussprüfung:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

## Dokumentation

`FEATURES.md` wird aktualisiert:

- Feature 6.1 wechselt von "Zurückgestellt nach v1" zu "In Arbeit — iCloud Sync Beta".
- Der erste Umfang wird als Struktur- und Statussync beschrieben.

`AGENTS.md` wird aktualisiert:

- Technologie-Stack nennt iCloud Sync als Beta in Arbeit.
- ADR/Gotchas dokumentieren den gewählten Ansatz, den Neustart-Hinweis und die Einschränkung großer Inhalte.

## Nicht-Ziele

- Kein eigener CloudKit-Record-Sync in dieser Version.
- Keine Zwei-Store-Architektur in dieser Version.
- Kein Live-Umschalten des Stores ohne Neustart.
- Kein eigener Konfliktdialog.
- Kein garantiert synchronisierter Offline-Volltext.
- Keine iOS-/iPadOS-Umsetzung in diesem Schritt.

## Offene Folgearbeit nach der Beta

- Manuelle End-to-End-Prüfung mit zwei Macs oder zwei lokalen Test-Accounts.
- Bewertung, ob große Artikelinhalte den Sync belasten.
- Entscheidung über mögliches Modell-Splitting für lokale große Inhalte.
- Bessere Sync-Diagnose, falls SwiftData/CloudKit-Fehler im Alltag schwer verständlich sind.
