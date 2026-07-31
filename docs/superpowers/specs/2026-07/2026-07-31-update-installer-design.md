# Design: In-App-Download und -Installation von App-Updates

**Datum:** 2026-07-31
**Status:** Vom Nutzer genehmigt, bereit für Implementierungsplan

## Problem

Der bestehende Update-Check (`docs/superpowers/specs/2026-07/2026-07-30-update-check-design.md`)
erkennt neue GitHub-Releases und zeigt sie im "Update verfügbar"-Dialog
(`UpdateAvailableSheet.swift`) an, bietet aber nur "Auf GitHub öffnen" — der Nutzer muss die
ZIP-Datei manuell herunterladen, entpacken, das Quarantäne-Flag umgehen (Rechtsklick →
"Öffnen") und die alte Version selbst im Programme-Ordner ersetzen. Gewünscht ist ein direkter
"Herunterladen & installieren"-Weg aus dem Dialog heraus.

Feedivo ist sandboxed (`com.apple.security.app-sandbox = true`, siehe `Feedivo.entitlements`),
aber weder App-Store- noch Sparkle-vertrieben. Das Repo ist privat.

## Umfang

**Enthalten:**
- Neuer Button "Herunterladen & installieren" im "Update verfügbar"-Dialog (ersetzt den
  bisherigen "Auf GitHub öffnen"-Button vollständig, kein zweiter permanenter Button)
- Download des ZIP-Release-Assets mit Fortschrittsbalken (Prozent + MB)
- SHA256-Prüfsummen-Verifikation gegen eine zusätzlich veröffentlichte Prüfsummen-Datei
- Entpacken + Entfernen des Quarantäne-Flags
- Bestätigungsschritt "Bereit zu installieren" mit "Jetzt neu starten"-Button, bevor die
  laufende Installation angefasst wird
- Einmalige, persistierte Sicherheits-Bookmark-Berechtigung für den Programme-Ordner
- Atomarer Austausch der App-Version + automatischer Neustart
- Erweiterung von `scripts/create_github_release.sh` um eine `.sha256`-Begleitdatei
- Fehlerzustände mit "Erneut versuchen" + Fallback-Link "Stattdessen auf GitHub öffnen"

**Bewusst außerhalb des Umfangs:**
- Kein Sparkle-Framework, keine neuen Xcode-Targets/Entitlements/Signier-Schlüssel
- Keine rückwirkende Nutzbarkeit für den Sprung *auf* das Build, das dieses Feature
  einführt — nur für Updates *ab* diesem Build (Bootstrapping-Problem jedes Self-Updaters)
- Kein automatischer Download beim Öffnen des Dialogs (nur auf expliziten Klick)
- Kein Delta-/Differential-Update, immer die volle ZIP
- Keine erneute Nutzung des Fallback-Links außerhalb echter Fehlerzustände

## Architektur

### 1. `GitHubRelease` erweitert um Assets (`Feedivo/Services/GitHubRelease.swift`)

```swift
struct GitHubReleaseAsset: Equatable, Sendable, Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct GitHubRelease: Equatable, Sendable, Decodable, Identifiable {
    // ... bestehende Felder unverändert ...
    let assets: [GitHubReleaseAsset]
}
```

GitHub liefert `assets` bereits standardmäßig in der Releases-Liste mit — keine zusätzliche
Anfrage nötig. Reine, pure Hilfsfunktion (z. B. `GitHubReleaseAsset.zipAsset(in:)` /
`.checksumAsset(in:)`, Suche per Namens-Suffix `.zip`/`.sha256`) wird isoliert unit-getestet.

### 2. `UpdateInstaller` (`Feedivo/Services/UpdateInstaller.swift`)

`@Observable`-State-Machine, die den gesamten Vorgang orchestriert:

```swift
enum UpdateInstallState: Equatable {
    case idle
    case downloading(progress: Double, downloadedBytes: Int64, totalBytes: Int64)
    case verifying
    case readyToInstall(extractedAppURL: URL)
    case installing
    case failed(UpdateInstallError)
}

enum UpdateInstallError: Equatable {
    case downloadFailed
    case checksumMismatch
    case unzipFailed
    case folderAccessDenied
    case replaceFailed
}
```

I/O-Grenzen (Download, Entpacken/Quarantäne, Ordnerzugriff, Dateiaustausch) laufen hinter
kleinen, injizierbaren Protokollen (Projektmuster wie `SpotlightIndexWriting`), damit die
Sequenzierungslogik selbst ohne echtes Netzwerk/Dateisystem/GUI testbar bleibt:

```swift
protocol UpdateAssetDownloading: Sendable {
    func download(url: URL, onProgress: @escaping (Double, Int64, Int64) -> Void) async throws -> URL
}

protocol UpdateArchiveExtracting: Sendable {
    func extractAndUnquarantine(zipURL: URL) async throws -> URL // liefert Pfad zur .app
}

protocol UpdateInstallLocationGranting: Sendable {
    func grantedApplicationsFolderAccess() async throws -> URL // nutzt/erneuert Security-Scoped-Bookmark
}

protocol UpdateAppSwapping: Sendable {
    func replace(currentAppURL: URL, with newAppURL: URL, in grantedFolderURL: URL) throws
}
```

### 3. Ablauf (siehe bereits genehmigter Grobentwurf)

1. Klick "Herunterladen & installieren" → `.downloading` (Fortschrittsbalken)
2. Download abgeschlossen → SHA256 berechnen (`CryptoKit.SHA256`) → Vergleich mit
   heruntergeladener `.sha256`-Datei → bei Mismatch `.failed(.checksumMismatch)`
3. `ditto -x -k` entpackt in temporären Ordner im eigenen App-Container,
   `xattr -dr com.apple.quarantine` auf die entpackte `.app`
4. `.readyToInstall` → Sheet zeigt "Bereit zu installieren" + "Jetzt neu starten"
5. Klick "Jetzt neu starten" → `.installing`:
   - `UpdateInstallLocationGranting` liefert (evtl. erstmalig per `NSOpenPanel`, danach aus
     gespeichertem Security-Scoped-Bookmark in `UserDefaults`) Zugriff auf den Ordner, in dem
     `Bundle.main.bundleURL` aktuell liegt
   - `FileManager.replaceItemAt` tauscht die App-Version atomar aus
   - `NSWorkspace.shared.openApplication(at:configuration:)` startet die neue Version,
     `NSApplication.shared.terminate(nil)` beendet die aktuelle

### 4. UI (`UpdateAvailableSheet.swift`)

Footer bindet an `UpdateInstaller.state`:
- `.idle`: "Herunterladen & installieren" (primär, einziger Button)
- `.downloading`: Fortschrittsbalken + Prozent/MB, "Abbrechen" (sekundär)
- `.verifying`: kurzer Spinner "Wird vorbereitet…"
- `.readyToInstall`: "Jetzt neu starten" (primär)
- `.failed`: Fehlermeldung (spezifisch je `UpdateInstallError`) + "Erneut versuchen" (primär)
  + Text-Link "Stattdessen auf GitHub öffnen" (nur hier sichtbar)

## Fehlerbehandlung

| Fehler | Meldung | "Erneut versuchen"-Verhalten |
|---|---|---|
| `downloadFailed` | "Download fehlgeschlagen" | Download komplett neu starten |
| `checksumMismatch` | "Verifikation fehlgeschlagen — Datei scheint beschädigt/unvollständig" | Download komplett neu starten |
| `unzipFailed` | Generische Fehlermeldung | Download komplett neu starten |
| `folderAccessDenied` | "Ohne diese Erlaubnis kann Feedivo sich nicht selbst aktualisieren" | Nur Ordner-Dialog erneut zeigen (kein Re-Download) |
| `replaceFailed` | Generische Fehlermeldung | Nur Austausch-Schritt erneut versuchen |

`FileManager.replaceItemAt` ist atomar — ein Fehler dabei lässt die alte, funktionierende
Installation unangetastet zurück.

**Zwei bewusst getroffene Annahmen, um Mehrdeutigkeit zu vermeiden:** Die alte App-Version
wird nach erfolgreichem Austausch nicht aufbewahrt (kein Rollback-Mechanismus) — bei Bedarf
ließe sich das später als eigenes Feature ergänzen. "Abbrechen" während `.downloading` bricht
den laufenden Download-Task ab und setzt den Zustand zurück auf `.idle` (keine Teilreste,
keine automatische Fortsetzung).

## Sicherheit

- Keine neuen Entitlements/Xcode-Capabilities — `files.user-selected.read-write` und
  `network.client` (bereits vorhanden) decken alles ab.
- Quarantäne-Entfernung ausschließlich auf eine Datei, deren SHA256 zuvor gegen eine vom
  eigenen, privaten Release-Prozess veröffentlichte Prüfsumme verifiziert wurde — bewusster
  Vertrauensschritt anstelle von Notarisierung, dokumentiert als Trade-off.
- Security-Scoped-Bookmark landet in `UserDefaults` (kein Geheimnis, reiner Ordner-Zugriffs-
  Token); wird das Bookmark ungültig (z. B. nach macOS-Reset), wird die Berechtigungsabfrage
  einfach automatisch erneut gezeigt.

## `scripts/create_github_release.sh`

Nach dem `ditto`-Packschritt:
```bash
shasum -a 256 "$ZIP_PATH" | awk '{print $1}' > "${ZIP_PATH}.sha256"
```
Beide Dateien werden als Release-Assets hochgeladen:
```bash
gh release create "$TAG" "$ZIP_PATH" "${ZIP_PATH}.sha256" --title "..." --notes-file "$NOTES_FILE" --prerelease
```
Dry-Run-Vorschau wird um die Prüfsummen-Datei ergänzt.

## Tests

- Reine Logik mit Swift Testing (`@testable import Feedivo`):
  - Asset-Auswahl (`.zip`/`.sha256` aus `[GitHubReleaseAsset]` finden)
  - Prüfsummen-Vergleich (Groß-/Kleinschreibung, Whitespace-Trimming, Mismatch-Fall)
  - `UpdateInstaller`-Sequenzierung mit injizierten Fake-Protokollimplementierungen
    (Download/Entpacken/Ordnerzugriff/Austausch je als Erfolgs- und Fehlerfall simuliert)
- Manuelle Live-Verifikationscheckliste (nicht automatisierbar): echter Download eines echten
  Releases, absichtlich falsche Prüfsumme zum Testen des Mismatch-Pfads, Ordner-Berechtigung
  ablehnen und erneut zulassen, kompletter Austausch+Neustart auf dem eigenen Mac.

## Bekannte Limitation

Dieses Feature kann naturgemäß erst *ab* dem Build genutzt werden, der es einführt — ein
Nutzer auf einem älteren Build sieht weiterhin nur den alten Dialog ohne Download-Button, bis
er einmal manuell aktualisiert hat.
