# Sparkle-Update + Homebrew-Vertrieb — Design

> Status: Approved (Nutzer, 2026-07-31)
> Vorgänger: `2026-07-31-update-installer-design.md` (der dort gebaute Eigenbau-Installer
> scheitert unter App Sandbox am Entfernen des Quarantäne-Flags — siehe Root-Cause-Analyse
> unten. Dieses Dokument ersetzt den Ansatz vollständig.)

## Kontext / Root Cause des Vorgänger-Ansatzes

Der in der Vorsession gebaute In-App-Updater (`UpdateInstaller` + `DittoUpdateArchiveExtractor`
+ `UpdateAppSwapper`) lädt ein GitHub-Release-ZIP herunter, entpackt es per `ditto -x -k` und
entfernt anschließend das Quarantäne-Flag per `xattr -dr com.apple.quarantine`, bevor das
laufende App-Bundle ersetzt und neu gestartet wird.

Live-Test durch den Nutzer (Update 1.0-14 → 1.0-15) schlug fehl mit
„Die heruntergeladene Datei konnte nicht vorbereitet werden" (`UpdateInstallError.unzipFailed`).

Root-Cause-Analyse (reproduziert mit einem eigens gebauten, identisch signierten
Sandbox-Testprogramm sowie an den echten Resten des fehlgeschlagenen Versuchs im
Feedivo-Sandbox-Container):

- Download und `ditto -x -k`-Entpacken laufen unter App Sandbox einwandfrei durch.
- Der letzte Schritt, `xattr -dr com.apple.quarantine` auf das entpackte App-Bundle,
  scheitert für **jede einzelne Datei** mit `Operation not permitted` (Exit-Code 1) —
  reproduzierbar, unabhängig von Entitlements.
- Auch die "sauberere" native API (`URLResourceValues.quarantineProperties = [:]`) entfernt
  das Flag unter Sandbox nicht wirklich (kein Fehler, aber das Flag bleibt bestehen).
- **Fazit:** App Sandbox verbietet einem gesandboxten Prozess grundsätzlich das Entfernen von
  `com.apple.quarantine` — egal ob über Subprozess oder native API. Ein vollautomatisches
  Selbst-Update auf diesem Weg ist in einer gesandboxten App architektonisch nicht möglich.
  Sparkle löst genau dieses Problem seit Jahren über eigene, nicht-gesandboxte
  XPC-Installer-Helfer.

## Ziel

1. Den kompletten Eigenbau-Installer durch Sparkle ersetzen — App Sandbox bleibt für Feedivo
   selbst vollständig erhalten.
2. Feedivo zusätzlich über einen eigenen Homebrew-Tap installierbar machen.
3. Beide Update-Kanäle (Sparkle für ZIP-Installationen, `brew upgrade` für Homebrew-
   Installationen) dürfen sich nicht gegenseitig stören.

## Architektur-Überblick

```
                    ┌─────────────────────┐
                    │  create_github_      │
                    │  release.sh           │
                    └──────────┬────────────┘
                               │ baut + signiert (EdDSA) + lädt hoch
                               ▼
              ┌────────────────────────────────┐
              │  GitHub Release (ZIP + SHA256)  │◄──────────────┐
              └────────────────────────────────┘                │
                               │                                  │ referenziert
                    aktualisiert & pusht                          │ dieselbe URL
                               ▼                                  │
        ┌───────────────────────────┐          ┌──────────────────────────────┐
        │ appcast.xml (Hauptrepo)   │          │ homebrew-feedivo (Tap-Repo)   │
        │ raw.githubusercontent.com │          │ Casks/feedivo.rb              │
        └─────────────┬─────────────┘          └───────────────┬────────────────┘
                      │ pollt/lädt                              │ brew tap + install
                      ▼                                          ▼
              ┌───────────────┐                          ┌───────────────┐
              │ Feedivo.app    │                          │ Feedivo.app    │
              │ (Sparkle aktiv)│                          │ (Sparkle AUS)  │
              └───────────────┘                          └───────────────┘
```

## 1. Sparkle-Integration

### Paket & Grundeinrichtung
- Sparkle als Swift Package (`https://github.com/sparkle-project/Sparkle`) — passt zum
  bestehenden SPM-Muster (FeedKit, GRDB.swift).
- App Sandbox (`com.apple.security.app-sandbox`) bleibt in `Feedivo.entitlements` unverändert
  `true`.

### Sandboxing-Setup
Sparkle bringt für gesandboxte Apps ein offizielles, dokumentiertes Sandboxing-Setup mit: der
in `Sparkle.framework` gebündelte, nicht-gesandboxte `Autoupdate`-Helfer übernimmt zusammen mit
mehreren zusätzlichen, kleinen XPC-Service-Targets im Xcode-Projekt den eigentlichen
Install-Schritt (Quarantäne entfernen, App-Bundle ersetzen, neu starten) außerhalb von Feedivos
eigener Sandbox. Die exakten Target-Namen, Entitlement-Einträge
(`com.apple.security.temporary-exception.mach-lookup.global-name` o. ä.) und Info.plist-Keys
sind versionsabhängig — werden während der Implementierung direkt aus Sparkles aktueller
offizieller Sandboxing-Dokumentation übernommen, nicht aus diesem Dokument.

### Signierung
- EdDSA-Schlüsselpaar via Sparkles `generate_keys`-Tool.
- Öffentlicher Schlüssel → `SUPublicEDKey` in Info.plist.
- Privater Schlüssel → macOS-Schlüsselbund, genutzt von `sign_update` im Release-Skript.
- Ersetzt die bisherige reine SHA256-Prüfsumme durch eine echte Authentizitätsprüfung
  (Integrität *und* Herkunft).

### Appcast
- `appcast.xml` liegt als Datei im Hauptrepo (z. B. `docs/appcast.xml`), abgefragt über die
  stabile `https://raw.githubusercontent.com/martinfelder/feedivo-mac/main/docs/appcast.xml`
  — kein zusätzliches Hosting nötig.
- Jeder Release-Lauf hängt einen neuen `<item>` an: Versionsnummer/Build, signierte
  Download-URL (zeigt auf dasselbe GitHub-Release-ZIP), Release-Notes-HTML (aus demselben
  CHANGELOG.md-Ausschnitt wie bisher).

### UI (bestehende Sheet-UI bleibt erhalten)
- Sparkle läuft „headless" über das `SPUUserDriver`-Protokoll.
- `UpdateAvailableSheet.swift` (Konzept-A-Design, kategorisierte Release-Notes via
  `UpdateReleaseNoteCategorizer`) bleibt die sichtbare UI, angebunden an Sparkles
  Download-/Verify-/Install-Callbacks statt an den bisherigen `UpdateInstaller`-State.
- `UpdateReleaseNoteCategorizer.swift` bleibt unverändert bestehen (arbeitet weiter auf
  HTML-Text — jetzt aus dem Appcast-Item statt der GitHub-API-Antwort).

### Entfällt (wird durch Sparkle ersetzt)
`UpdateInstaller.swift`, `UpdateArchiveExtractor.swift`, `UpdateAppSwapper.swift`,
`UpdateInstallLocationGrantor.swift`, `UpdateAssetDownloader.swift`,
`UpdateChecksumVerifier.swift`, `UpdateInstallState.swift`, `UpdateChecker.swift`,
`GitHubReleaseCheckService.swift`, `GitHubRelease.swift`, `UpdateVersionComparator.swift`
sowie die zugehörigen Tests. `AppVersionInfo`/`AboutSettingsView`/`UpdateUpToDateSheet`
werden auf Sparkles APIs umgestellt statt auf die bisherige GitHub-API-Kette.

## 2. Homebrew-Distribution

- **Eigener Tap**, kein offizielles `homebrew/cask`-Repo (bewusste Entscheidung — offizielles
  Repo erfordert Notarisierung/Popularitäts-/Reifekriterien und einen Review-Prozess, passt
  nicht zum aktuellen Beta-Stadium).
- Neues öffentliches Repo `martinfelder/homebrew-feedivo` mit `Casks/feedivo.rb`.
- Cask zeigt auf dieselbe GitHub-Release-ZIP-URL wie der Sparkle-Appcast — eine Quelle der
  Wahrheit für die Binärdatei.
- Installation für Nutzer: `brew tap martinfelder/feedivo && brew install --cask feedivo`.
- Keine Notarisierung nötig: `brew install --cask` entfernt das Quarantäne-Flag beim
  Installieren standardmäßig selbst (ebenfalls ein nicht-gesandboxter Prozess) — funktioniert
  also genauso ohne Notarisierung wie Sparkles Installer-Helfer.

## 3. Zwei-Kanal-Koexistenz

Feedivo prüft beim Start einmalig, ob `Bundle.main.bundleURL` innerhalb eines
Homebrew-Caskroom-Pfads liegt (`/opt/homebrew/Caskroom/feedivo/…` auf Apple Silicon,
`/usr/local/Caskroom/feedivo/…` auf Intel). Trifft das zu:

- Sparkles automatischer Hintergrund-Check bleibt aus.
- Der manuelle Menüpunkt „Nach Updates suchen" bleibt sichtbar, zeigt in diesem Fall aber
  einen Hinweis, der auf `brew upgrade` verweist, statt Sparkles Check auszulösen (exakte
  Formulierung/UI-Detail: Plan-Phase).

Nutzer, die die ZIP direkt von GitHub geladen haben (kein Caskroom-Pfad), behalten den vollen
Sparkle-Update-Flow inklusive automatischem Hintergrund-Check.

## 4. Release-Pipeline (`create_github_release.sh`)

Erweitert um (nach dem bestehenden `gh release create`-Schritt):

1. ZIP mit Sparkles `sign_update` signieren (EdDSA) — Signatur fließt ins Appcast-Item.
2. `appcast.xml` im Hauptrepo um den neuen `<item>` ergänzen, committen.
3. *(unverändert)* ZIP + SHA256 weiterhin als GitHub-Release-Assets hochladen — bleibt Quelle
   für Homebrew UND den bestehenden manuellen „Auf GitHub öffnen"-Fallback in der UI.
4. Tap-Repo (`homebrew-feedivo`) lokal klonen/aktualisieren (falls nicht vorhanden: klonen),
   `Casks/feedivo.rb` mit neuer Version/SHA256/Download-URL beschreiben, committen.
5. **Vor dem Push zu beiden Repos (Appcast im Hauptrepo, Cask im Tap-Repo) wie bisher explizit
   interaktiv nachfragen** — analog zur bestehenden `gh release create`-Bestätigung. Kein
   automatischer Push ohne Bestätigung.

## 5. Nicht Teil dieses Vorhabens

- **Apple-Notarisierung** — bewusst zurückgestellt. Weder Sparkles Installer-Helfer noch
  `brew install --cask` benötigen sie (beide entfernen die Quarantäne unsandboxed selbst).
  Bleibt relevant für den Fall, dass jemand die ZIP manuell lädt und ohne Rechtsklick→Öffnen
  doppelklickt — dafür existiert weiterhin der Gatekeeper-Warnhinweis wie bisher.
- **Aufnahme ins offizielle `homebrew/cask`-Repo** — bewusst zurückgestellt, s. o.

## 6. Testing-Strategie

- Reine Logik-Tests für die neue Homebrew-Caskroom-Pfaderkennung (Unit-Test, keine echte
  Installation nötig).
- Bestehende `UpdateReleaseNoteCategorizerTests` bleiben gültig, ggf. Fixtures auf
  Appcast-HTML-Form angepasst.
- **Nicht automatisierbar in dieser Umgebung** (wie bereits bei iCloud Sync/Sidebar-Features):
  kompletter Live-Test eines echten Sparkle-Updates (Download → Install → Neustart) sowie ein
  echter `brew install --cask`-Lauf gegen den neuen Tap — beides erfordert manuelle
  Verifikation durch den Nutzer.

## Offene technische Details für die Plan-Phase

- Exakte Sparkle-XPC-Target-Namen/Entitlements (aus aktueller Sparkle-Doku ziehen).
- Exakter Aufbau/Pfad der `appcast.xml` im Repo.
- Genaue UI-Formulierung des „Nutze brew upgrade"-Hinweises bei Homebrew-Installationen.
- Ob/wie das bereits bestehende `sha256`-Release-Asset neben der neuen EdDSA-Signatur noch
  gebraucht wird (vermutlich: ja, für den weiterhin bestehenden manuellen Fallback-Pfad ohne
  Sparkle).
