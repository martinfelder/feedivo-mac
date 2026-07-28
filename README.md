# Feedivo

Ein nativer RSS-Reader für macOS — schnell, „mac-like" und ohne Electron oder
iOS-Portierung. Echtes AppKit-Feeling via SwiftUI, mit Tags, automatischen
Regeln, intelligenten Ordnern und OPML-Import/-Export.

> Privates Solo-Projekt in aktiver Entwicklung.

## Features

- **3-Spalten-Navigation** (Sidebar / Artikelliste / Reader) via
  `NavigationSplitView`, plus separate Fenster für Suche, Feed-/Ordner-
  Verwaltung ("Organizer") und Artikel-Popouts
- **Tags & automatische Regeln** — Artikel per Regelwerk taggen, ausblenden
  oder benachrichtigen lassen
- **Intelligente Ordner** (Smart Folders) mit eigenem Bedingungs-Editor,
  inkl. UND/ODER-Gruppierung
- **OPML-Import/-Export** mit Vorschau, Review-Screen und Duplikat-Erkennung
- **Artikel-Reader** wahlweise nativ (SwiftUI, inkl. Fett/Kursiv/Links/Farben
  aus dem Artikel-HTML) oder als Original-Ansicht (WKWebView)
- **Artikel-Export** nach Markdown, PDF, DOCX oder als Paket
- **Automatische Aufbewahrungsrichtlinien** (global + pro Feed) mit
  konfigurierbarem Zeitplan und Verlaufs-Historie
- **Hintergrund-Refresh** über `NSBackgroundActivityScheduler`
- **Browser-Erweiterungen** für Safari und Chrome zum Erkennen und
  Hinzufügen von Feeds direkt aus dem Browser
- **Menüleisten-Icon** mit Ungelesen-Badge und Artikel-Dropdown
- **iCloud Sync (Beta)** über `CKSyncEngine` — Tags, Feeds, Ordner, Regeln,
  benutzerdefinierte Intelligente Ordner und Artikelstatus (Gelesen/Stern)
  inkl. Feld-Ebene-Konfliktauflösung; noch nicht abschließend gehärtet
  (siehe [`CLAUDE.md`](CLAUDE.md))
- Vollständig lokalisiert (Deutsch/Englisch)

## Tech-Stack

| Bereich | Technologie |
|---|---|
| UI | SwiftUI (macOS), punktuell `NSViewRepresentable` (z. B. `WKWebView`, Sidebar via `NSOutlineView`) |
| Architektur | MVVM mit `@Observable` |
| Persistenz | [GRDB](https://github.com/groue/GRDB.swift) (SQLite) — eigene Datenschicht, kein SwiftData/Core Data |
| RSS-Parsing | [FeedKit](https://github.com/nmdias/FeedKit) |
| Netzwerk | `URLSession` + async/await |
| iCloud Sync | `CKSyncEngine` (CloudKit) |
| Mindest-macOS | macOS 14 Sonoma |

Details zu Architektur-Entscheidungen und Datenbank-Migrationen stehen in
[`CLAUDE.md`](CLAUDE.md).

## Projekt öffnen

```bash
open Feedivo.xcodeproj
```

Xcode löst die Swift-Package-Abhängigkeiten (GRDB, FeedKit) automatisch auf.
Build & Run über das Schema `Feedivo`.

### Tests

Die volle Testsuite kann in dieser Umgebung hängen bleiben — gezielt mit
`-only-testing:` und `-parallel-testing-enabled NO` ausführen, z. B.:

```bash
xcodebuild -scheme Feedivo -destination 'platform=macOS' test \
  -only-testing:FeedivoTests/FeedStoreTests \
  -parallel-testing-enabled NO
```

## Versionierung & Releases

Die Marketing-Version steht fest bei `1.0`; die **Build-Nummer** zählt bei
jedem erfolgreichen `git push` nach `origin/main` automatisch hoch (siehe
[`.claude/settings.json`](.claude/settings.json) und
[`scripts/bump_version.sh`](scripts/bump_version.sh)). Jeder Bump ergänzt
gleichzeitig einen Eintrag in [`CHANGELOG.md`](CHANGELOG.md) mit den seit dem
letzten Bump gepushten Commit-Nachrichten.

Ein kompilierter Release wird **nie automatisch** hochgeladen — nur auf
expliziten Wunsch, per:

```bash
bash scripts/create_github_release.sh
```

Das Skript baut die Release-Konfiguration, packt die `.app`, liest den
obersten Eintrag aus `CHANGELOG.md` als Release-Notes und veröffentlicht
über die `gh` CLI ein GitHub Release (Tag `v<Version>-<Build>`) — nach
interaktiver Bestätigung.

## Lizenz

Privates Projekt, kein öffentliches Lizenzmodell.
