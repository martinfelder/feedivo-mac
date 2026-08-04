# Changelog

Alle nennenswerten Änderungen an Feedivo werden hier dokumentiert. Format lose
angelehnt an [Keep a Changelog](https://keepachangelog.com/de/1.0.0/).

Diese Datei wird NICHT mehr automatisch nach jedem Push aktualisiert (der
frühere PostToolUse-Hook in `.claude/settings.json` wurde ab Build 9 entfernt).
Ein neuer Eintrag entsteht nur noch, wenn explizit ein Versions-Bump gewünscht
wird (`scripts/bump_version.sh`, manuell aufgerufen) — dadurch können mehrere
Pushes/Änderungen unter derselben Build-Nummer gesammelt werden. Die Einträge
listen die Commit-Nachrichten seit dem letzten Versions-Bump — für Details
siehe `git log`.

<!-- versions -->

## [1.0 (26)] - 2026-08-04

- docs: Spec/Plan/Optimierungsliste für Punkt 3 (Bild-Anreicherung im Hintergrund)
- fix: Bild-Anreicherung — COALESCE schützt bestehende Bilder vor Reset bei erneutem Refresh
- perf: Feed-Refresh — Bild-Anreicherung läuft nicht mehr blockierend
- feat: ArticleStore.updateImageURL für gezieltes Nachtragen einzelner Artikelbilder
- perf: Feed-Refresh — echte Warteschlange statt fester Batches, kürzerer Fetch-Timeout
- chore: Appcast-Eintrag für v1.0-25
- docs: Changelog-Eintrag für v1.0-25 in einfacher Sprache umformuliert

## [1.0 (25)] - 2026-08-02

- Verbesserung: Die Sync-Übersicht in den Einstellungen bleibt jetzt auch bei
  vielen wartenden Änderungen schnell

## [1.0 (24)] - 2026-08-02

- Verbesserung: Die Tab-Leiste beim Lesen von Artikeln passt jetzt besser zum
  restlichen Erscheinungsbild der App
- Verbesserung: Der Plus-Knopf oben in der Seitenleiste sieht im dunklen
  Modus jetzt richtig aus
- Verbesserung: Die Liste der Neuerungen im Update-Fenster wird jetzt
  übersichtlicher mit Überschrift und Absätzen angezeigt

## [1.0 (23)] - 2026-08-02

- Neu: Artikel lassen sich jetzt in Tabs öffnen, ähnlich wie im Browser —
  so können mehrere Artikel gleichzeitig offen bleiben
- Neu: Ein Artikel kann per Rechtsklick oder ⌘-Klick in einem neuen Tab
  geöffnet werden, statt den aktuell angezeigten zu ersetzen
- Neu: Tabs lassen sich per Tastenkürzel öffnen, schließen und wechseln
- Neu: In den Einstellungen kann festgelegt werden, ob offene Tabs beim
  nächsten Start der App wiederhergestellt werden sollen
- Verbesserung: Die Tab-Leiste sieht jetzt aus wie in Safari
- Verschiedene kleinere Korrekturen rund um die neue Tab-Funktion

## [1.0 (22)] - 2026-08-02

- feat: Einstellungen-Fenster auf Design D ("Formular") umgestellt — alle 11 Tabs
- docs: README-Screenshots aktualisiert (Hauptansicht, Regel-Editor, Intelligenter Ordner, Einstellungen)
- docs: README um Sparkle-Auto-Update-Feature und Homebrew-Installationsanleitung ergänzt
- chore: geteiltes Feedivo-Xcode-Scheme eingecheckt
- feat: create_github_release.sh signiert mit Developer ID, notarisiert und staplet
- docs: Sparkle-Notarisierung + SPUStandardUserDriver-Umstellung in CLAUDE.md dokumentiert
- chore: Appcast-Eintrag für v1.0-21

## [1.0 (21)] - 2026-08-02

- refactor: Sparkle-Integration auf SPUStandardUserDriver umgestellt (wie NetNewsWire)
- chore: Appcast-Eintrag für v1.0-20

## [1.0 (20)] - 2026-08-02

- fix: Sheet schließt synchron per AppKit statt über asynchrone SwiftUI-Bindung
- chore: Appcast-Eintrag für v1.0-19

## [1.0 (19)] - 2026-08-02

- fix: Update-Sheet blockiert AppKit-Terminierung während Sparkle-Installation
- chore: Appcast-Eintrag für v1.0-18

## [1.0 (18)] - 2026-08-02

- chore: Appcast-Eintrag für v1.0-17

## [1.0 (17)] - 2026-08-01

- fix: sign_update-Suche berücksichtigt eigenen -derivedDataPath des Release-Builds
- chore: Appcast-Eintrag für v1.0-16 (manuell nachgetragen)

## [1.0 (16)] - 2026-08-01

- fix: showUpdateFound() wartet nicht mehr auf nie kommende Continuation bei stillem Fund
- fix: Whole-Branch-Review-Funde für Sparkle/Homebrew-Migration behoben
- docs: CLAUDE.md um Sparkle-Update/Homebrew-Vertrieb ergänzt
- feat: create_github_release.sh aktualisiert Homebrew-Cask-Formel im Tap-Repo
- fix: NOTES_FILE-Race und stille ED_SIGNATURE-Extraktion in create_github_release.sh behoben
- feat: create_github_release.sh signiert Releases für Sparkle und pflegt appcast.xml
- refactor: alten Eigenbau-Update-Installer und GitHub-API-Check-Stack entfernt (durch Sparkle ersetzt)
- refactor: Update-UI liest jetzt SparkleUpdateCoordinator statt GitHub-API-Stack
- refactor: FeedivoApp.swift auf SparkleUpdateCoordinator umgestellt
- fix: installUpdate() löst pendingUpdateChoice statt es zu ignorieren
- feat: SparkleUpdateCoordinator kapselt SPUUpdater hinter eigenem SPUUserDriver
- feat: SparkleUpdateState/SparkleReleaseInfo als neue Update-Datentypen
- feat: Sparkle-Appcast-Grundgerüst angelegt
- feat: HomebrewInstallationDetector erkennt Caskroom-Installationen
- build: Sparkle Info.plist-Keys und Sandbox-Entitlement-Ausnahme ergänzt
- build: Sparkle-Paket als Abhängigkeit hinzugefügt (noch ungenutzt)
- docs: Implementierungsplan für Sparkle-Update + Homebrew-Vertrieb
- docs: Design-Spec für Sparkle-Update + Homebrew-Vertrieb

## [1.0 (15)] - 2026-07-31

- chore: Xcode-Workspace-State

## [1.0 (14)] - 2026-07-31

- Fix: @concurrent statt nonisolated - MainActor-Blockade tatsächlich behoben
- Fix: Whole-Branch-Review-Befunde behoben (Neustart-Fehler, App-Aktivierung, MainActor-Blockade, Cancel-Race)
- Docs: Plan-Nachtrag nach finaler Whole-Branch-Review (4 Befunde)
- Feat: Release-Skript veröffentlicht zusätzlich eine SHA256-Prüfsummen-Datei
- Fix: Eigener Text für laufenden Installationsschritt statt "Bereit zu installieren"
- Fix: Plan-Korrektur nach Task-10-Review (eigener Text für .installing)
- Fix: Dialog jederzeit über "Später"-Button schließbar
- Fix: Plan-Korrektur nach Task-10-Review (Später-Button ergänzt)
- Feat: Update-Dialog um Herunterladen & installieren erweitert
- Design: Update-Dialog auf Konzept-A-Theme umgestellt + Changelog kategorisiert
- Test: Echter Abbruch-während-Download-Test statt trivialem Idle-Check
- Fix: Plan-Korrektur nach Task-9-Review (echter Abbruch-Test statt trivialem Test)
- Feat: UpdateInstaller-Orchestrator (Download→Verifikation→Installation)
- Fix: relaunchAndQuit meldet Neustart-Erfolg zurück statt bedingungslos zu beenden
- Fix: Plan-Korrektur nach Task-8-Review (relaunchAndQuit meldet Erfolg zurück)
- Feat: Atomarer App-Austausch + Neustart für Update-Installation
- Feat: Einmalige Programme-Ordner-Berechtigung für Update-Installation
- Feat: Entpacken + Quarantäne-Entfernung für heruntergeladene Updates
- Feat: URLSession-Download mit Fortschritt für Update-Assets
- Feat: UpdateInstallState/-Error State-Machine-Vokabular
- Feat: UpdateChecksumVerifier für SHA256-Verifikation von Update-Downloads
- Test: Asset-Auswahl (ZIP/Prüfsumme) isoliert abgedeckt
- Feat: GitHubRelease liest Release-Assets (ZIP + Prüfsumme)
- Docs: Implementierungsplan für In-App-Update-Download/-Installation
- Docs: Design-Spec für In-App-Update-Download/-Installation

## [1.0 (13)] - 2026-07-31

- chore: Xcode-Workspace-State
- Design: Artikelinfos-Button in der Reader-Toolbar auf normale Schriftgröße gebracht
- Design: Schrift im Artikelinfos-Panel vergrößert
- Design: App-Name, Ungelesen-Zähler und Plus-Button in der Sidebar vergrößert
- Design: Einheitliches Blau in der ganzen App

## [1.0 (12)] - 2026-07-31

- chore: Xcode-Workspace-State
- Text: "Aktuell verfügbare Version" statt Fehlertext bei leerer Release-Liste
- Fix: "Kein Update"-Dialog auf eigenes Sheet umgestellt (Farbe + Zeile fehlten)
- Feat: Versionsnummer in Update-Dialogen grün/rot einfärben
- Text: "Neuste verfügbare Version" statt "Neueste Version auf GitHub"
- Feat: "Kein Update"-Dialog zeigt installierte + aktuelle GitHub-Version
- Fix: AppKit-Absturz durch dynamischen Menü-Titel behoben (Nutzer-Report)
- Fix: Whole-Branch-Review-Befunde behoben (Fenster-Fallback, Re-Entrancy-Guard, Decoding-Fehler-Logging)
- Feat: Neuer Settings-Tab „Über" mit Update-Check (Task 6)
- Refactor: Duplizierten UpdateChecker-Aufruf in FeedivoApp.swift zusammengeführt (Task 5 Review-Fix)
- Feat: App-Menü + stiller Start-Check für Update-Prüfung (Task 5)
- Fix: Links in UpdateAvailableSheet öffnen zuverlässig im Standardbrowser (Task 4 Review-Fix)
- Feat: UpdateAvailableSheet (Mini-Reader für Release-Notes) (Task 4)
- Feat: Stateless UpdateChecker-Orchestrator + UpdateCheckSettings (Task 3)
- Feat: GitHubReleaseCheckService für Update-Prüfung (Task 2)
- Feat: GitHubRelease-Modell + Versionsvergleich für Update-Prüfung (Task 1)
- Docs: Implementierungsplan für Update-Prüfung über GitHub Releases
- Docs: Design-Spec für Update-Prüfung über GitHub Releases

## [1.0 (11)] - 2026-07-30

- Feat: Sidebar-Header in Blau + graue Zähler-Badges mit dunklerem Rahmen

## [1.0 (10)] - 2026-07-29

- Feat: Sidebar-Kopfzeile auf minimalen Ein-Symbol-Stil umgestellt
- Chore: Versions-Bump/Changelog/Release nur noch manuell auf Anfrage

## [1.0 (9)] - 2026-07-29

- Fix: Schriftgrösse in den Einstellungen um 1pt erhöht

## [1.0 (8)] - 2026-07-28

- Docs: Screenshots und Screenshots-Sektion im README ergänzt

## [1.0 (7)] - 2026-07-28

- Docs: Projektstruktur-Diagramm in CLAUDE.md an die aufgeräumte Ablage angepasst
- Cleanup: Projekt-Ablage aufgeraeumt (Punkte 2-6 aus Struktur-Review)

## [1.0 (6)] - 2026-07-28

- Cleanup: Versehentlich committete xcresult-Testartefakte entfernt

## [1.0 (5)] - 2026-07-28

- Feat: --dry-run fuer create_github_release.sh ergaenzt

## [1.0 (4)] - 2026-07-28

- Fix: Bump-Hook auf echten Git-Zustand statt Text-Matching umgestellt

## [1.0 (3)] - 2026-07-28

- Fix: Bump-Skript ließ Commit-Nachricht des allerersten Bumps aus

## [1.0 (2)] - 2026-07-28

- Feat: README, Changelog und automatische Versionierung eingerichtet

## [1.0 (1)] - 2026-07-28

Erste getrackte Version. Ab hier zählt die Build-Nummer bei jedem Push nach
`origin/main` automatisch hoch; die Marketing-Version (`1.0`) bleibt fix, bis
sie bewusst manuell geändert wird.
