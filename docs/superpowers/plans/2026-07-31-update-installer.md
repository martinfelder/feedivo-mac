# In-App-Update-Download und -Installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aus dem "Update verfügbar"-Dialog heraus ein GitHub-Release direkt herunterladen,
per SHA256 verifizieren, entpacken, die laufende Installation ersetzen und die App neu
starten — ohne Sparkle, ohne neue Entitlements.

**Architecture:** Ein neuer `@Observable`-State-Machine-Service (`UpdateInstaller`)
orchestriert vier kleine, injizierbare I/O-Protokolle (Download, Entpacken+Quarantäne,
Ordnerzugriff, App-Austausch). `UpdateAvailableSheet` bindet seinen Footer an
`UpdateInstaller.state`. `scripts/create_github_release.sh` veröffentlicht zusätzlich eine
`.sha256`-Datei je Release.

**Tech Stack:** Swift 6 / SwiftUI (macOS 14+), URLSession, CryptoKit, Foundation
`FileManager`/`Process`, AppKit (`NSOpenPanel`, `NSWorkspace`), Swift Testing (kein XCTest),
GRDB-fremd (dieses Feature berührt keine Datenbank).

## Global Constraints

- Kein Sparkle-Framework, keine neuen Xcode-Targets/Entitlements/Signier-Schlüssel — nur die
  bereits vorhandenen `com.apple.security.files.user-selected.read-write` und
  `com.apple.security.network.client` werden genutzt.
- "Herunterladen & installieren" ist der einzige Button im Normalfall — kein permanenter
  zweiter "Auf GitHub öffnen"-Button. Der Fallback-Link "Stattdessen auf GitHub öffnen"
  erscheint ausschließlich im `.failed`-Zustand.
- Download startet nur auf expliziten Klick, nie automatisch beim Öffnen des Dialogs.
- SHA256-Prüfsumme ist verpflichtend — ohne passendes `.sha256`-Asset gilt der Download als
  nicht verifizierbar (`.checksumMismatch`).
- Vor dem eigentlichen Austausch der laufenden Installation erscheint immer die
  "Bereit zu installieren"-Bestätigung mit "Jetzt neu starten"-Button — kein automatischer
  Austausch direkt nach dem Download.
- Die alte App-Version wird nach erfolgreichem Austausch nicht aufbewahrt (kein Rollback).
- "Abbrechen" während des Downloads bricht ihn ab und setzt den Zustand auf `.idle` zurück,
  ohne automatische Fortsetzung.
- Dieses Feature ist erst *ab* dem Build nutzbar, der es einführt — nicht rückwirkend für den
  Sprung dorthin.
- Alle neuen Sprachschlüssel brauchen vollständige de/en/fr/it-Einträge in
  `Localizable.xcstrings` (chirurgische Text-Einfügung am `"strings" : {`-Anker, niemals
  `json.dump()`/vollständiges Roundtrip der Datei — siehe CLAUDE.md-Gotcha).
- Tests folgen dem Projektmuster: reine Logik wird mit Swift Testing (`@testable import
  Feedivo`) getestet; I/O-Grenzen (Netzwerk, `Process`, `NSOpenPanel`, `FileManager`) werden
  hinter Protokollen injiziert und in Tests durch Fakes ersetzt, ihre *reale* Implementierung
  bleibt wie bei `FaviconService`/`FeedService` ungetestet und wird stattdessen manuell
  live verifiziert.

---

### Task 1: `GitHubReleaseAsset` + `GitHubRelease.assets`

**Files:**
- Modify: `Feedivo/Services/GitHubRelease.swift`
- Modify: `FeedivoTests/Services/GitHubReleaseCheckServiceTests.swift:7-30` (Fixture bekommt
  optional `assets`-Beispiel für einen Release, bleibt für den anderen absichtlich weg, um
  den Fallback zu testen)
- Test: `FeedivoTests/Services/GitHubReleaseCheckServiceTests.swift`

**Interfaces:**
- Produces: `struct GitHubReleaseAsset: Equatable, Sendable, Decodable { let name: String; let
  browserDownloadURL: URL }`; `GitHubRelease.assets: [GitHubReleaseAsset]` (Default `[]`,
  fehlt der Schlüssel im JSON wird kein Fehler geworfen).

- [ ] **Step 1: Write the failing test**

Füge in `FeedivoTests/Services/GitHubReleaseCheckServiceTests.swift` einen neuen Test und
erweitere die Fixture ans Ende der Datei (vor der schließenden `}`):

```swift
    @Test func decodeReleasesLiestAssetsUndFaelltAufLeeresArrayZurueckWennAssetsFehlt() throws {
        let releases = try GitHubReleaseCheckService.decodeReleases(from: Self.sampleReleaseListJSON)

        #expect(releases[0].assets.count == 2)
        #expect(releases[0].assets[0].name == "Feedivo-v1.0-11.zip")
        #expect(releases[0].assets[0].browserDownloadURL.absoluteString == "https://github.com/martinfelder/feedivo-mac/releases/download/v1.0-11/Feedivo-v1.0-11.zip")
        #expect(releases[0].assets[1].name == "Feedivo-v1.0-11.zip.sha256")
        // Zweiter Release in der Fixture hat bewusst KEIN "assets"-Feld im JSON - muss
        // trotzdem sauber auf ein leeres Array zurueckfallen statt einen Decoding-Fehler zu werfen.
        #expect(releases[1].assets.isEmpty)
    }
```

Erweitere dafür die bestehende `sampleReleaseListJSON`-Fixture: dem ERSTEN Release-Objekt
(v1.0-11) ein `"assets"`-Array hinzufügen, das ZWEITE Release-Objekt (v1.0-10) bleibt
unverändert ohne `"assets"`-Feld (testet den Fallback). Ersetze in
`GitHubReleaseCheckServiceTests.swift` das erste Release-Objekt:

```swift
      {
        "html_url": "https://github.com/martinfelder/feedivo-mac/releases/tag/v1.0-11",
        "tag_name": "v1.0-11",
        "name": "Feedivo 1.0 (11)",
        "draft": false,
        "prerelease": true,
        "published_at": "2026-07-30T18:21:00Z",
        "body": "- Feat: Sidebar-Header in Blau",
        "body_html": "<ul>\\n<li>Feat: Sidebar-Header in Blau</li>\\n</ul>",
        "assets": [
          {
            "name": "Feedivo-v1.0-11.zip",
            "browser_download_url": "https://github.com/martinfelder/feedivo-mac/releases/download/v1.0-11/Feedivo-v1.0-11.zip"
          },
          {
            "name": "Feedivo-v1.0-11.zip.sha256",
            "browser_download_url": "https://github.com/martinfelder/feedivo-mac/releases/download/v1.0-11/Feedivo-v1.0-11.zip.sha256"
          }
        ]
      },
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/GitHubReleaseCheckServiceTests -parallel-testing-enabled NO`
Expected: FAIL — `value of type 'GitHubRelease' has no member 'assets'`

- [ ] **Step 3: Implement `GitHubReleaseAsset` und `GitHubRelease.assets`**

Ersetze den kompletten Inhalt von `Feedivo/Services/GitHubRelease.swift`:

```swift
import Foundation

/// Ein einzelnes Release-Asset (z. B. die gepackte .app als ZIP, oder die
/// begleitende .sha256-Prüfsummen-Datei), wie von der GitHub-REST-API im
/// `assets`-Array eines Releases geliefert.
struct GitHubReleaseAsset: Equatable, Sendable, Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

extension GitHubReleaseAsset {
    /// Findet das ZIP-Release-Asset (case-insensitiver Namens-Suffix-Vergleich).
    static func zipAsset(in assets: [GitHubReleaseAsset]) -> GitHubReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".zip") }
    }

    /// Findet die begleitende SHA256-Prüfsummen-Datei desselben Releases.
    static func checksumAsset(in assets: [GitHubReleaseAsset]) -> GitHubReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".sha256") }
    }
}

/// Ein einzelnes GitHub-Release, wie von der GitHub-REST-API geliefert
/// (`GET /repos/{owner}/{repo}/releases`). Mit dem Header
/// `Accept: application/vnd.github.html+json` liefert GitHub zusätzlich
/// `body_html` — server-seitig aus Markdown gerendertes HTML, das wir direkt
/// in `ReaderContentRenderer` weiterreichen (kein eigener Markdown-Parser nötig).
struct GitHubRelease: Equatable, Sendable, Decodable, Identifiable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let bodyHTML: String?
    let publishedAt: Date?
    let assets: [GitHubReleaseAsset]

    var id: String { tagName }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case bodyHTML = "body_html"
        case publishedAt = "published_at"
        case assets
    }

    // Handgeschriebener statt synthetisierter Initializer: `assets` bekommt hier
    // einen echten Default-Parameter (`= []`), damit bestehende Testaufrufstellen wie
    // `GitHubRelease(tagName:name:htmlURL:bodyHTML:publishedAt:)` (siehe
    // UpdateCheckerTests.swift) ohne Änderung weiter kompilieren.
    init(
        tagName: String,
        name: String?,
        htmlURL: URL,
        bodyHTML: String?,
        publishedAt: Date?,
        assets: [GitHubReleaseAsset] = []
    ) {
        self.tagName = tagName
        self.name = name
        self.htmlURL = htmlURL
        self.bodyHTML = bodyHTML
        self.publishedAt = publishedAt
        self.assets = assets
    }

    // Eigene Decodable-Implementierung statt Synthese: `assets` fehlt in manchen
    // (z. B. selbst geschriebenen Test-)Fixtures - decodeIfPresent + Fallback auf
    // [] statt eines harten Decoding-Fehlers.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        bodyHTML = try container.decodeIfPresent(String.self, forKey: .bodyHTML)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        assets = try container.decodeIfPresent([GitHubReleaseAsset].self, forKey: .assets) ?? []
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/GitHubReleaseCheckServiceTests -parallel-testing-enabled NO`
Expected: PASS (alle Tests dieser Suite, inkl. der bereits bestehenden)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/GitHubRelease.swift FeedivoTests/Services/GitHubReleaseCheckServiceTests.swift
git commit -m "Feat: GitHubRelease liest Release-Assets (ZIP + Prüfsumme)"
```

---

### Task 2: Asset-Auswahl-Tests

**Files:**
- Test: `FeedivoTests/Services/GitHubReleaseAssetSelectionTests.swift` (neu)

**Interfaces:**
- Consumes: `GitHubReleaseAsset.zipAsset(in:)`, `GitHubReleaseAsset.checksumAsset(in:)` (aus
  Task 1)

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import Feedivo

struct GitHubReleaseAssetSelectionTests {

    private func asset(_ name: String) -> GitHubReleaseAsset {
        GitHubReleaseAsset(name: name, browserDownloadURL: URL(string: "https://example.com/\(name)")!)
    }

    @Test func zipAssetFindetDieZipDateiUnabhaengigVonGrossKleinschreibung() {
        let assets = [asset("Feedivo-v1.0-14.ZIP"), asset("Feedivo-v1.0-14.zip.sha256")]

        #expect(GitHubReleaseAsset.zipAsset(in: assets)?.name == "Feedivo-v1.0-14.ZIP")
    }

    @Test func checksumAssetFindetDieSha256Datei() {
        let assets = [asset("Feedivo-v1.0-14.zip"), asset("Feedivo-v1.0-14.zip.sha256")]

        #expect(GitHubReleaseAsset.checksumAsset(in: assets)?.name == "Feedivo-v1.0-14.zip.sha256")
    }

    @Test func liefertNilBeiFehlendemAsset() {
        #expect(GitHubReleaseAsset.zipAsset(in: []) == nil)
        #expect(GitHubReleaseAsset.checksumAsset(in: []) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/GitHubReleaseAssetSelectionTests -parallel-testing-enabled NO`
Expected: Datei existiert noch nicht als Test-Target-Mitglied — dieser Schritt legt sie neu an,
daher direkt Step 3 abwarten und dann gemeinsam bauen/testen (Xcode nimmt neue Dateien im
file-system-synchronisierten Ordner automatisch ins Target auf, siehe
`PBXFileSystemSynchronizedRootGroup` in `project.pbxproj`).

- [ ] **Step 3: Datei anlegen (siehe Step 1 Code) und Tests laufen lassen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/GitHubReleaseAssetSelectionTests -parallel-testing-enabled NO`
Expected: PASS (die Implementierung aus Task 1 existiert bereits, dieser Task fügt nur die
fehlende Testabdeckung nach)

- [ ] **Step 4: Commit**

```bash
git add FeedivoTests/Services/GitHubReleaseAssetSelectionTests.swift
git commit -m "Test: Asset-Auswahl (ZIP/Prüfsumme) isoliert abgedeckt"
```

---

### Task 3: `UpdateChecksumVerifier`

**Files:**
- Create: `Feedivo/Services/UpdateChecksumVerifier.swift`
- Test: `FeedivoTests/Services/UpdateChecksumVerifierTests.swift`

**Interfaces:**
- Produces: `UpdateChecksumVerifier.sha256Hex(of: Data) -> String`,
  `UpdateChecksumVerifier.matches(computedHex: String, expectedHex: String) -> Bool`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import Feedivo

struct UpdateChecksumVerifierTests {

    @Test func sha256HexLiefertBekanntenTestvektorFuerABC() {
        let hex = UpdateChecksumVerifier.sha256Hex(of: "abc".data(using: .utf8)!)

        #expect(hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func matchesIgnoriertGrossKleinschreibung() {
        #expect(UpdateChecksumVerifier.matches(computedHex: "AbCd1234", expectedHex: "abcd1234"))
    }

    @Test func matchesIgnoriertUmgebendenWhitespace() {
        #expect(UpdateChecksumVerifier.matches(computedHex: "abcd1234", expectedHex: "  abcd1234\n"))
    }

    @Test func matchesLiefertFalseBeiUnterschiedlichenHashes() {
        #expect(!UpdateChecksumVerifier.matches(computedHex: "abcd1234", expectedHex: "1234abcd"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/UpdateChecksumVerifierTests -parallel-testing-enabled NO`
Expected: FAIL — `Cannot find 'UpdateChecksumVerifier' in scope`

- [ ] **Step 3: Implement `UpdateChecksumVerifier`**

```swift
import Foundation
import CryptoKit

/// Reine, zustandslose SHA256-Prüfsummen-Logik für heruntergeladene Update-Assets.
/// Kein eigenes I/O - Daten/Hex-Strings kommen von außen (siehe UpdateInstaller).
enum UpdateChecksumVerifier {
    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Vergleicht zwei Hex-Strings tolerant gegenüber Groß-/Kleinschreibung und
    /// umgebendem Whitespace (`.sha256`-Textdateien enthalten oft ein
    /// abschließendes Newline).
    static func matches(computedHex: String, expectedHex: String) -> Bool {
        normalized(computedHex) == normalized(expectedHex)
    }

    private static func normalized(_ hex: String) -> String {
        hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/UpdateChecksumVerifierTests -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/UpdateChecksumVerifier.swift FeedivoTests/Services/UpdateChecksumVerifierTests.swift
git commit -m "Feat: UpdateChecksumVerifier für SHA256-Verifikation von Update-Downloads"
```

---

### Task 4: `UpdateInstallState` + `UpdateInstallError` + L10n

**Files:**
- Create: `Feedivo/Services/UpdateInstallState.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Test: `FeedivoTests/Services/UpdateInstallErrorTests.swift`

**Interfaces:**
- Produces: `enum UpdateInstallState: Equatable { case idle, downloading(fractionCompleted:
  Double, downloadedBytes: Int64, totalBytes: Int64), verifying, readyToInstall, installing,
  failed(UpdateInstallError) }`; `enum UpdateInstallError: Equatable, LocalizedError { case
  downloadFailed, checksumMismatch, unzipFailed, folderAccessDenied, replaceFailed }` mit
  `var requiresFullRedownload: Bool`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import Feedivo

struct UpdateInstallErrorTests {

    @Test func downloadUndChecksumUndUnzipFehlerBrauchenKompletttenNeustart() {
        #expect(UpdateInstallError.downloadFailed.requiresFullRedownload)
        #expect(UpdateInstallError.checksumMismatch.requiresFullRedownload)
        #expect(UpdateInstallError.unzipFailed.requiresFullRedownload)
    }

    @Test func ordnerZugriffUndAustauschFehlerBrauchenKeinenNeuenDownload() {
        #expect(!UpdateInstallError.folderAccessDenied.requiresFullRedownload)
        #expect(!UpdateInstallError.replaceFailed.requiresFullRedownload)
    }

    @Test func jederFehlerHatEineNichtLeereBeschreibung() {
        for error in [
            UpdateInstallError.downloadFailed,
            .checksumMismatch,
            .unzipFailed,
            .folderAccessDenied,
            .replaceFailed
        ] {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/UpdateInstallErrorTests -parallel-testing-enabled NO`
Expected: FAIL — `Cannot find type 'UpdateInstallError' in scope`

- [ ] **Step 3: `Feedivo/Services/UpdateInstallState.swift` anlegen**

```swift
import Foundation

/// Zustand des In-App-Update-Installationsvorgangs, siehe `UpdateInstaller`.
enum UpdateInstallState: Equatable {
    case idle
    case downloading(fractionCompleted: Double, downloadedBytes: Int64, totalBytes: Int64)
    case verifying
    case readyToInstall
    case installing
    case failed(UpdateInstallError)
}

enum UpdateInstallError: Equatable, LocalizedError {
    case downloadFailed
    case checksumMismatch
    case unzipFailed
    case folderAccessDenied
    case replaceFailed

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            String(localized: "updateInstall.error.downloadFailed")
        case .checksumMismatch:
            String(localized: "updateInstall.error.checksumMismatch")
        case .unzipFailed:
            String(localized: "updateInstall.error.unzipFailed")
        case .folderAccessDenied:
            String(localized: "updateInstall.error.folderAccessDenied")
        case .replaceFailed:
            String(localized: "updateInstall.error.replaceFailed")
        }
    }

    /// `true`: "Erneut versuchen" muss den kompletten Download neu starten.
    /// `false`: Download/Verifikation/Entpacken waren bereits erfolgreich - "Erneut
    /// versuchen" wiederholt nur den Installationsschritt (Ordnerzugriff + Austausch).
    var requiresFullRedownload: Bool {
        switch self {
        case .downloadFailed, .checksumMismatch, .unzipFailed:
            true
        case .folderAccessDenied, .replaceFailed:
            false
        }
    }
}
```

- [ ] **Step 4: L10n-Keys ergänzen**

Füge in `Feedivo/Resources/L10n.swift` direkt vor der schließenden `}` des `enum L10n` (nach
den in dieser Session bereits ergänzten `updateCheckCategory*`-Keys) ein:

```swift
    static let updateInstallErrorDownloadFailed = "updateInstall.error.downloadFailed"
    static let updateInstallErrorChecksumMismatch = "updateInstall.error.checksumMismatch"
    static let updateInstallErrorUnzipFailed = "updateInstall.error.unzipFailed"
    static let updateInstallErrorFolderAccessDenied = "updateInstall.error.folderAccessDenied"
    static let updateInstallErrorReplaceFailed = "updateInstall.error.replaceFailed"
```

(Diese fünf Keys werden NICHT als `L10n`-Konstanten in SwiftUI-Views gebraucht — sie werden
direkt per `String(localized:)` in `UpdateInstallState.swift` oben referenziert. Sie sind hier
nur als Dokumentations-/Grep-Anker aufgeführt, kein Code verwendet `L10n.updateInstallError*`.)

- [ ] **Step 5: Fünf neue Einträge in `Localizable.xcstrings` ergänzen**

Öffne `Feedivo/Resources/Localizable.xcstrings` und füge direkt nach der Zeile
`  "strings" : {` (Zeile 3) folgenden Block ein (chirurgische Text-Einfügung, KEIN
`json.load`/`json.dump`-Roundtrip):

```json
    "updateInstall.error.checksumMismatch" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Verifikation fehlgeschlagen — die Datei scheint beschädigt oder unvollständig zu sein"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Verification failed — the file seems to be corrupted or incomplete"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Échec de la vérification — le fichier semble corrompu ou incomplet"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Verifica non riuscita — il file sembra danneggiato o incompleto"
          }
        }
      }
    },
    "updateInstall.error.downloadFailed" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Download fehlgeschlagen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Download failed"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Échec du téléchargement"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Download non riuscito"
          }
        }
      }
    },
    "updateInstall.error.folderAccessDenied" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ohne diese Erlaubnis kann Feedivo sich nicht selbst aktualisieren"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Without this permission, Feedivo can't update itself"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sans cette autorisation, Feedivo ne peut pas se mettre à jour lui-même"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Senza questa autorizzazione, Feedivo non può aggiornarsi da solo"
          }
        }
      }
    },
    "updateInstall.error.replaceFailed" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Die Installation konnte nicht abgeschlossen werden"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "The installation couldn't be completed"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "L'installation n'a pas pu être terminée"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Non è stato possibile completare l'installazione"
          }
        }
      }
    },
    "updateInstall.error.unzipFailed" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Die heruntergeladene Datei konnte nicht vorbereitet werden"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "The downloaded file couldn't be prepared"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Le fichier téléchargé n'a pas pu être préparé"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Non è stato possibile preparare il file scaricato"
          }
        }
      }
    },
```

Verifiziere danach mit `git diff --stat Feedivo/Resources/Localizable.xcstrings`, dass NUR
Insertions entstanden sind (keine/kaum Deletions) — sonst wurde versehentlich die ganze Datei
neu formatiert statt chirurgisch eingefügt.

- [ ] **Step 6: Run test to verify it passes**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/UpdateInstallErrorTests -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/UpdateInstallState.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings FeedivoTests/Services/UpdateInstallErrorTests.swift
git commit -m "Feat: UpdateInstallState/-Error State-Machine-Vokabular"
```

---

### Task 5: `UpdateAssetDownloading` + reale URLSession-Implementierung

**Files:**
- Create: `Feedivo/Services/UpdateAssetDownloader.swift`

**Interfaces:**
- Produces: `protocol UpdateAssetDownloading: Sendable { func download(from url: URL,
  onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void) async throws -> URL }`;
  `final class URLSessionUpdateAssetDownloader: UpdateAssetDownloading`

Kein Unit-Test in diesem Task — reiner Netzwerk-I/O-Wrapper, folgt demselben Muster wie
`FaviconService`/`FeedService` (siehe Global Constraints). Wird über das Protokoll in Task 9
mit einer Fake-Implementierung getestet; die reale `URLSession`-Anbindung selbst wird über die
manuelle Live-Verifikationscheckliste am Ende dieses Plans abgedeckt.

- [ ] **Step 1: Datei anlegen**

```swift
import Foundation

protocol UpdateAssetDownloading: Sendable {
    /// Lädt die Datei unter `url` herunter und liefert eine lokale, dauerhafte Datei-URL
    /// (im temporären Verzeichnis) zurück. `onProgress` wird wiederholt mit
    /// (Fortschrittsanteil 0...1, geladene Bytes, erwartete Gesamt-Bytes) aufgerufen -
    /// bei unbekannter Gesamtgröße (z. B. sehr kleine Textdateien) kann `onProgress`
    /// auch gar nicht aufgerufen werden, Aufrufer dürfen sich darauf nicht verlassen.
    func download(from url: URL, onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void) async throws -> URL
}

/// Lädt ein Release-Asset per URLSession-Download-Task herunter. Reiner I/O-Wrapper
/// ohne eigene Geschäftslogik - siehe UpdateInstaller für die eigentliche Sequenzierung.
final class URLSessionUpdateAssetDownloader: NSObject, UpdateAssetDownloading, URLSessionDownloadDelegate, @unchecked Sendable {
    private var progressHandler: (@Sendable (Double, Int64, Int64) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?

    func download(from url: URL, onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void) async throws -> URL {
        progressHandler = onProgress
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(fraction, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // `location` wird von URLSession geloescht, sobald diese Methode zurueckkehrt -
        // sofort in ein eigenes, stabiles Temp-File verschieben.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(location.pathExtension.isEmpty ? "download" : location.pathExtension)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
```

- [ ] **Step 2: Build verifizieren**

Run: `xcodebuild -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add Feedivo/Services/UpdateAssetDownloader.swift
git commit -m "Feat: URLSession-Download mit Fortschritt für Update-Assets"
```

---

### Task 6: `UpdateArchiveExtracting` + `ditto`/`xattr`-Implementierung

**Files:**
- Create: `Feedivo/Services/UpdateArchiveExtractor.swift`

**Interfaces:**
- Produces: `protocol UpdateArchiveExtracting: Sendable { func extractAndUnquarantine(zipURL:
  URL) throws -> URL }`; `struct DittoUpdateArchiveExtractor: UpdateArchiveExtracting`

Kein Unit-Test (Prozess-Shell-out, siehe Global Constraints) — manuell live verifiziert.

- [ ] **Step 1: Datei anlegen**

```swift
import Foundation

protocol UpdateArchiveExtracting: Sendable {
    /// Entpackt die ZIP-Datei in ein neues temporäres Verzeichnis, entfernt das
    /// Quarantäne-Flag von der enthaltenen .app und liefert deren URL zurück.
    func extractAndUnquarantine(zipURL: URL) throws -> URL
}

/// Nutzt `ditto` (dasselbe Tool, mit dem `scripts/create_github_release.sh` die ZIP
/// packt) zum Entpacken sowie `xattr` zum Entfernen des macOS-Quarantäne-Flags. Die
/// Quarantäne-Entfernung ist bewusst Teil dieses Schritts, nicht optional: die ZIP wurde
/// zuvor bereits per SHA256 gegen eine vom eigenen, privaten Release-Prozess
/// veröffentlichte Prüfsumme verifiziert (siehe UpdateInstaller) - das ist der
/// Vertrauensanker, der die Quarantäne-Entfernung rechtfertigt.
struct DittoUpdateArchiveExtractor: UpdateArchiveExtracting {
    func extractAndUnquarantine(zipURL: URL) throws -> URL {
        let destinationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        try run("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, destinationDirectory.path])

        let contents = try FileManager.default.contentsOfDirectory(at: destinationDirectory, includingPropertiesForKeys: nil)
        guard let appURL = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateInstallError.unzipFailed
        }

        try run("/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", appURL.path])

        return appURL
    }

    private func run(_ executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateInstallError.unzipFailed
        }
    }
}
```

- [ ] **Step 2: Build verifizieren**

Run: `xcodebuild -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add Feedivo/Services/UpdateArchiveExtractor.swift
git commit -m "Feat: Entpacken + Quarantäne-Entfernung für heruntergeladene Updates"
```

---

### Task 7: `UpdateInstallLocationGranting` + Security-Scoped-Bookmark + L10n

**Files:**
- Create: `Feedivo/Services/UpdateInstallLocationGrantor.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces: `protocol UpdateInstallLocationGranting: Sendable { func
  grantedInstallDirectory(currentAppDirectory: URL) async throws -> URL }`; `final class
  SecurityScopedInstallLocationGrantor: UpdateInstallLocationGranting`

Kein Unit-Test (echtes `NSOpenPanel`, siehe Global Constraints) — manuell live verifiziert.

- [ ] **Step 1: L10n-Keys + xcstrings-Einträge zuerst ergänzen**

Füge in `Feedivo/Resources/L10n.swift` (an derselben Stelle wie in Task 4) hinzu:

```swift
    static let updateInstallFolderPickerMessage = "updateInstall.folderPicker.message"
    static let updateInstallFolderPickerPrompt = "updateInstall.folderPicker.prompt"
```

Füge in `Feedivo/Resources/Localizable.xcstrings` direkt nach `"strings" : {` ein:

```json
    "updateInstall.folderPicker.message" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feedivo braucht einmalig deine Erlaubnis, sich selbst zu aktualisieren. Wähle den Ordner, in dem Feedivo aktuell liegt (meist „Programme“)."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feedivo needs your permission once to update itself. Choose the folder where Feedivo currently lives (usually \"Applications\")."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feedivo a besoin, une seule fois, de votre autorisation pour se mettre à jour. Choisissez le dossier où se trouve actuellement Feedivo (généralement « Applications »)."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feedivo ha bisogno, una sola volta, del tuo permesso per aggiornarsi da solo. Scegli la cartella in cui si trova attualmente Feedivo (di solito \"Applicazioni\")."
          }
        }
      }
    },
    "updateInstall.folderPicker.prompt" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Zugriff erlauben"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Allow Access"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Autoriser l'accès"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Consenti accesso"
          }
        }
      }
    },
```

Verifiziere mit `git diff --stat Feedivo/Resources/Localizable.xcstrings`: nur Insertions.

- [ ] **Step 2: `UpdateInstallLocationGrantor.swift` anlegen**

```swift
import AppKit
import Foundation

protocol UpdateInstallLocationGranting: Sendable {
    /// Liefert einen Ordner-URL mit Schreibzugriff, der `currentAppDirectory` enthält -
    /// aus einem gespeicherten Security-Scoped-Bookmark, falls vorhanden und gültig,
    /// sonst über eine einmalige `NSOpenPanel`-Berechtigungsabfrage. Wirft
    /// `.folderAccessDenied`, falls der Nutzer die Abfrage abbricht/ablehnt.
    func grantedInstallDirectory(currentAppDirectory: URL) async throws -> URL
}

@MainActor
final class SecurityScopedInstallLocationGrantor: UpdateInstallLocationGranting {
    private static let bookmarkDefaultsKey = "updateInstall.applicationsFolderBookmark"

    func grantedInstallDirectory(currentAppDirectory: URL) async throws -> URL {
        if let bookmarkedURL = Self.resolveStoredBookmark() {
            return bookmarkedURL
        }
        return try await requestFolderAccess(defaultDirectory: currentAppDirectory)
    }

    private static func resolveStoredBookmark() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkDefaultsKey) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isStale, url.startAccessingSecurityScopedResource() else {
            return nil
        }

        return url
    }

    private func requestFolderAccess(defaultDirectory: URL) async throws -> URL {
        let panel = NSOpenPanel()
        panel.message = String(localized: "updateInstall.folderPicker.message")
        panel.prompt = String(localized: "updateInstall.folderPicker.prompt")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = defaultDirectory

        let response = await withCheckedContinuation { (continuation: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            panel.begin { result in
                continuation.resume(returning: result)
            }
        }

        guard response == .OK, let url = panel.url, url.startAccessingSecurityScopedResource() else {
            throw UpdateInstallError.folderAccessDenied
        }

        if let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmarkData, forKey: Self.bookmarkDefaultsKey)
        }

        return url
    }
}
```

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Services/UpdateInstallLocationGrantor.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feat: Einmalige Programme-Ordner-Berechtigung für Update-Installation"
```

---

### Task 8: `UpdateAppSwapping` + Austausch/Neustart-Implementierung

**Files:**
- Create: `Feedivo/Services/UpdateAppSwapper.swift`

**Interfaces:**
- Produces: `protocol UpdateAppSwapping: Sendable { func replaceCurrentApp(at: URL,
  withNewAppAt: URL) throws; func relaunchAndQuit(appURL: URL) }`; `struct
  FileManagerUpdateAppSwapper: UpdateAppSwapping`

Kein Unit-Test (echter Dateisystem-Austausch + App-Beenden, siehe Global Constraints) —
manuell live verifiziert (letzter, riskantester Schritt der gesamten Kette).

- [ ] **Step 1: Datei anlegen**

```swift
import AppKit
import Foundation

protocol UpdateAppSwapping: Sendable {
    /// Ersetzt den Inhalt der App am Pfad `currentAppURL` atomar durch den Inhalt von
    /// `newAppURL` - Pfad/Name von `currentAppURL` bleiben erhalten. Braucht
    /// Schreibzugriff auf das übergeordnete Verzeichnis (siehe
    /// `UpdateInstallLocationGranting`).
    func replaceCurrentApp(at currentAppURL: URL, withNewAppAt newAppURL: URL) throws

    /// Startet die App an `appURL` neu und beendet den aktuellen Prozess.
    func relaunchAndQuit(appURL: URL)
}

struct FileManagerUpdateAppSwapper: UpdateAppSwapping {
    func replaceCurrentApp(at currentAppURL: URL, withNewAppAt newAppURL: URL) throws {
        do {
            _ = try FileManager.default.replaceItemAt(currentAppURL, withItemAt: newAppURL)
        } catch {
            throw UpdateInstallError.replaceFailed
        }
    }

    func relaunchAndQuit(appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

- [ ] **Step 2: Build verifizieren**

Run: `xcodebuild -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add Feedivo/Services/UpdateAppSwapper.swift
git commit -m "Feat: Atomarer App-Austausch + Neustart für Update-Installation"
```

---

### Task 9: `UpdateInstaller`-Orchestrator + Sequenzierungs-Tests

**Files:**
- Create: `Feedivo/Services/UpdateInstaller.swift`
- Test: `FeedivoTests/Services/UpdateInstallerTests.swift`

**Interfaces:**
- Consumes: `UpdateAssetDownloading`, `UpdateArchiveExtracting`,
  `UpdateInstallLocationGranting`, `UpdateAppSwapping` (Tasks 5-8), `UpdateChecksumVerifier`
  (Task 3), `GitHubReleaseAsset.zipAsset(in:)`/`.checksumAsset(in:)` (Task 1)
- Produces: `@Observable @MainActor final class UpdateInstaller { private(set) var state:
  UpdateInstallState; func startDownloadAndVerify(release: GitHubRelease) async; func
  cancelDownload(); func install() async }`

Dies ist der zentrale, per Fakes vollständig testbare Baustein — hier liegt der Kern der
Testabdeckung dieses Plans.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import Feedivo

private struct FakeDownloader: UpdateAssetDownloading {
    var resultsByURLSuffix: [String: Result<URL, Error>]
    var progressReports: [(Double, Int64, Int64)] = [(1.0, 100, 100)]

    func download(from url: URL, onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void) async throws -> URL {
        for report in progressReports {
            onProgress(report.0, report.1, report.2)
        }
        for (suffix, result) in resultsByURLSuffix where url.absoluteString.hasSuffix(suffix) {
            return try result.get()
        }
        throw UpdateInstallError.downloadFailed
    }
}

private struct FakeExtractor: UpdateArchiveExtracting {
    var result: Result<URL, Error>

    func extractAndUnquarantine(zipURL: URL) throws -> URL {
        try result.get()
    }
}

private struct FakeLocationGrantor: UpdateInstallLocationGranting {
    var result: Result<URL, Error>

    func grantedInstallDirectory(currentAppDirectory: URL) async throws -> URL {
        try result.get()
    }
}

private final class FakeSwapper: UpdateAppSwapping, @unchecked Sendable {
    var replaceError: Error?
    var didRelaunch = false

    func replaceCurrentApp(at currentAppURL: URL, withNewAppAt newAppURL: URL) throws {
        if let replaceError { throw replaceError }
    }

    func relaunchAndQuit(appURL: URL) {
        didRelaunch = true
    }
}

@MainActor
struct UpdateInstallerTests {

    private let zipURL = URL(fileURLWithPath: "/tmp/fake-download.zip")
    private let checksumFileURL = URL(fileURLWithPath: "/tmp/fake-download.sha256")
    private let extractedAppURL = URL(fileURLWithPath: "/tmp/extracted/Feedivo.app")
    private let currentAppURL = URL(fileURLWithPath: "/Applications/Feedivo.app")

    private func makeRelease(zipContent: Data, checksumContent: String) -> (GitHubRelease, [String: Result<URL, Error>]) {
        let release = GitHubRelease(
            tagName: "v1.0-14",
            name: "Test",
            htmlURL: URL(string: "https://github.com/martinfelder/feedivo-mac/releases/tag/v1.0-14")!,
            bodyHTML: nil,
            publishedAt: nil,
            assets: [
                GitHubReleaseAsset(name: "Feedivo-v1.0-14.zip", browserDownloadURL: URL(string: "https://example.com/Feedivo-v1.0-14.zip")!),
                GitHubReleaseAsset(name: "Feedivo-v1.0-14.zip.sha256", browserDownloadURL: URL(string: "https://example.com/Feedivo-v1.0-14.zip.sha256")!)
            ]
        )

        try? zipContent.write(to: zipURL)
        try? checksumContent.write(to: checksumFileURL, atomically: true, encoding: .utf8)

        let results: [String: Result<URL, Error>] = [
            ".zip": .success(zipURL),
            ".sha256": .success(checksumFileURL)
        ]
        return (release, results)
    }

    @Test func kompletterErfolgspfadLandetBeiReadyToInstall() async {
        let zipContent = "fake-zip-bytes".data(using: .utf8)!
        let expectedHex = UpdateChecksumVerifier.sha256Hex(of: zipContent)
        let (release, downloadResults) = makeRelease(zipContent: zipContent, checksumContent: expectedHex)

        let installer = UpdateInstaller(
            downloader: FakeDownloader(resultsByURLSuffix: downloadResults),
            extractor: FakeExtractor(result: .success(extractedAppURL)),
            locationGrantor: FakeLocationGrantor(result: .success(currentAppURL.deletingLastPathComponent())),
            swapper: FakeSwapper(),
            currentAppURL: currentAppURL
        )

        await installer.startDownloadAndVerify(release: release)

        #expect(installer.state == .readyToInstall)
    }

    @Test func falscheChecksumFuehrtZuChecksumMismatch() async {
        let zipContent = "fake-zip-bytes".data(using: .utf8)!
        let (release, downloadResults) = makeRelease(zipContent: zipContent, checksumContent: "0000000000000000000000000000000000000000000000000000000000000000")

        let installer = UpdateInstaller(
            downloader: FakeDownloader(resultsByURLSuffix: downloadResults),
            extractor: FakeExtractor(result: .success(extractedAppURL)),
            locationGrantor: FakeLocationGrantor(result: .success(currentAppURL.deletingLastPathComponent())),
            swapper: FakeSwapper(),
            currentAppURL: currentAppURL
        )

        await installer.startDownloadAndVerify(release: release)

        #expect(installer.state == .failed(.checksumMismatch))
    }

    @Test func fehlendesZipAssetFuehrtSofortZuDownloadFailedOhneNetzwerkAufruf() async {
        let release = GitHubRelease(
            tagName: "v1.0-14",
            name: nil,
            htmlURL: URL(string: "https://github.com/martinfelder/feedivo-mac/releases/tag/v1.0-14")!,
            bodyHTML: nil,
            publishedAt: nil,
            assets: []
        )

        let installer = UpdateInstaller(
            downloader: FakeDownloader(resultsByURLSuffix: [:]),
            extractor: FakeExtractor(result: .success(extractedAppURL)),
            locationGrantor: FakeLocationGrantor(result: .success(currentAppURL.deletingLastPathComponent())),
            swapper: FakeSwapper(),
            currentAppURL: currentAppURL
        )

        await installer.startDownloadAndVerify(release: release)

        #expect(installer.state == .failed(.downloadFailed))
    }

    @Test func installNachErfolgreicherVerifikationLoestAustauschUndNeustartAus() async {
        let zipContent = "fake-zip-bytes".data(using: .utf8)!
        let expectedHex = UpdateChecksumVerifier.sha256Hex(of: zipContent)
        let (release, downloadResults) = makeRelease(zipContent: zipContent, checksumContent: expectedHex)
        let swapper = FakeSwapper()

        let installer = UpdateInstaller(
            downloader: FakeDownloader(resultsByURLSuffix: downloadResults),
            extractor: FakeExtractor(result: .success(extractedAppURL)),
            locationGrantor: FakeLocationGrantor(result: .success(currentAppURL.deletingLastPathComponent())),
            swapper: swapper,
            currentAppURL: currentAppURL
        )

        await installer.startDownloadAndVerify(release: release)
        await installer.install()

        #expect(swapper.didRelaunch)
    }

    @Test func abgelehnterOrdnerZugriffFuehrtZuFolderAccessDenied() async {
        let zipContent = "fake-zip-bytes".data(using: .utf8)!
        let expectedHex = UpdateChecksumVerifier.sha256Hex(of: zipContent)
        let (release, downloadResults) = makeRelease(zipContent: zipContent, checksumContent: expectedHex)

        let installer = UpdateInstaller(
            downloader: FakeDownloader(resultsByURLSuffix: downloadResults),
            extractor: FakeExtractor(result: .success(extractedAppURL)),
            locationGrantor: FakeLocationGrantor(result: .failure(UpdateInstallError.folderAccessDenied)),
            swapper: FakeSwapper(),
            currentAppURL: currentAppURL
        )

        await installer.startDownloadAndVerify(release: release)
        await installer.install()

        #expect(installer.state == .failed(.folderAccessDenied))
    }

    @Test func cancelWaehrendDesDownloadsSetztZustandAufIdleZurueck() async {
        let installer = UpdateInstaller(
            downloader: FakeDownloader(resultsByURLSuffix: [:]),
            extractor: FakeExtractor(result: .success(extractedAppURL)),
            locationGrantor: FakeLocationGrantor(result: .success(currentAppURL.deletingLastPathComponent())),
            swapper: FakeSwapper(),
            currentAppURL: currentAppURL
        )

        installer.cancelDownload()

        #expect(installer.state == .idle)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/UpdateInstallerTests -parallel-testing-enabled NO`
Expected: FAIL — `Cannot find 'UpdateInstaller' in scope`

- [ ] **Step 3: `UpdateInstaller.swift` implementieren**

```swift
import Foundation
import Observation

/// Orchestriert Download -> Verifikation -> Entpacken -> Installation eines
/// GitHub-Releases. Alle I/O-Grenzen sind injizierbare Protokolle (siehe
/// UpdateAssetDownloading/UpdateArchiveExtracting/UpdateInstallLocationGranting/
/// UpdateAppSwapping) - macht die komplette Sequenzierungslogik hier ohne echtes
/// Netzwerk/Dateisystem/GUI testbar (siehe UpdateInstallerTests).
@Observable
@MainActor
final class UpdateInstaller {
    private(set) var state: UpdateInstallState = .idle

    private let downloader: UpdateAssetDownloading
    private let extractor: UpdateArchiveExtracting
    private let locationGrantor: UpdateInstallLocationGranting
    private let swapper: UpdateAppSwapping
    private let currentAppURL: URL

    private var extractedAppURL: URL?
    private var isCancelled = false

    init(
        downloader: UpdateAssetDownloading = URLSessionUpdateAssetDownloader(),
        extractor: UpdateArchiveExtracting = DittoUpdateArchiveExtractor(),
        locationGrantor: UpdateInstallLocationGranting = SecurityScopedInstallLocationGrantor(),
        swapper: UpdateAppSwapping = FileManagerUpdateAppSwapper(),
        currentAppURL: URL = Bundle.main.bundleURL
    ) {
        self.downloader = downloader
        self.extractor = extractor
        self.locationGrantor = locationGrantor
        self.swapper = swapper
        self.currentAppURL = currentAppURL
    }

    func startDownloadAndVerify(release: GitHubRelease) async {
        isCancelled = false
        extractedAppURL = nil

        guard let zipAsset = GitHubReleaseAsset.zipAsset(in: release.assets) else {
            state = .failed(.downloadFailed)
            return
        }

        state = .downloading(fractionCompleted: 0, downloadedBytes: 0, totalBytes: 0)

        do {
            let zipURL = try await downloader.download(from: zipAsset.browserDownloadURL) { [weak self] fraction, downloaded, total in
                guard let self else { return }
                Task { @MainActor in
                    guard !self.isCancelled else { return }
                    self.state = .downloading(fractionCompleted: fraction, downloadedBytes: downloaded, totalBytes: total)
                }
            }
            guard !isCancelled else { return }

            state = .verifying
            try await verifyChecksum(zipURL: zipURL, release: release)
            guard !isCancelled else { return }

            let appURL = try extractor.extractAndUnquarantine(zipURL: zipURL)
            guard !isCancelled else { return }

            extractedAppURL = appURL
            state = .readyToInstall
        } catch let error as UpdateInstallError {
            state = .failed(error)
        } catch {
            state = .failed(.downloadFailed)
        }
    }

    func cancelDownload() {
        isCancelled = true
        state = .idle
    }

    func install() async {
        guard let extractedAppURL else { return }
        state = .installing

        do {
            _ = try await locationGrantor.grantedInstallDirectory(
                currentAppDirectory: currentAppURL.deletingLastPathComponent()
            )
            try swapper.replaceCurrentApp(at: currentAppURL, withNewAppAt: extractedAppURL)
            swapper.relaunchAndQuit(appURL: currentAppURL)
        } catch let error as UpdateInstallError {
            state = .failed(error)
        } catch {
            state = .failed(.replaceFailed)
        }
    }

    private func verifyChecksum(zipURL: URL, release: GitHubRelease) async throws {
        guard let checksumAsset = GitHubReleaseAsset.checksumAsset(in: release.assets) else {
            throw UpdateInstallError.checksumMismatch
        }

        let checksumFileURL = try await downloader.download(from: checksumAsset.browserDownloadURL) { _, _, _ in }
        guard let expectedHex = try? String(contentsOf: checksumFileURL, encoding: .utf8) else {
            throw UpdateInstallError.checksumMismatch
        }

        let zipData = try Data(contentsOf: zipURL)
        let computedHex = UpdateChecksumVerifier.sha256Hex(of: zipData)

        guard UpdateChecksumVerifier.matches(computedHex: computedHex, expectedHex: expectedHex) else {
            throw UpdateInstallError.checksumMismatch
        }
    }
}
```

Hinweis zur bewussten Abweichung vom Spec-Grobentwurf: `readyToInstall` trägt in
`UpdateInstallState` KEINEN assoziierten Wert mehr (Spec-Skizze hatte
`readyToInstall(extractedAppURL:)`) - der Pfad wird stattdessen als private Property
`extractedAppURL` gehalten, damit er auch nach einem `folderAccessDenied`/`replaceFailed`-
Fehler für einen erneuten `install()`-Versuch erhalten bleibt, ohne ihn erneut aus dem
Enum-Zustand herauspulen zu müssen.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/UpdateInstallerTests -parallel-testing-enabled NO`
Expected: PASS (alle 6 Tests)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/UpdateInstaller.swift FeedivoTests/Services/UpdateInstallerTests.swift
git commit -m "Feat: UpdateInstaller-Orchestrator (Download→Verifikation→Installation)"
```

---

### Task 10: `UpdateAvailableSheet` UI-Wiring + verbleibende L10n-Keys

**Files:**
- Modify: `Feedivo/Views/Settings/UpdateAvailableSheet.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `UpdateInstaller` (Task 9) — `UpdateAvailableSheet` bekommt ein
  `@State private var installer = UpdateInstaller()`

- [ ] **Step 1: L10n-Keys ergänzen**

Füge in `Feedivo/Resources/L10n.swift` (an derselben Stelle wie in Task 4) hinzu:

```swift
    static let updateCheckDownloadButton = LocalizedStringKey("updateCheck.download.button")
    static func updateCheckDownloadProgress(percent: Int, downloaded: String, total: String) -> String {
        String.localizedStringWithFormat(String(localized: "updateCheck.download.progressFormat"), percent, downloaded, total)
    }
    static let updateCheckVerifyingLabel = LocalizedStringKey("updateCheck.verifying.label")
    static let updateCheckReadyToInstallMessage = LocalizedStringKey("updateCheck.readyToInstall.message")
    static let updateCheckReadyToInstallButton = LocalizedStringKey("updateCheck.readyToInstall.button")
    static let updateCheckRetryButton = LocalizedStringKey("updateCheck.retry.button")
```

- [ ] **Step 2: xcstrings-Einträge ergänzen**

Füge in `Feedivo/Resources/Localizable.xcstrings` direkt nach `"strings" : {` ein:

```json
    "updateCheck.download.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Herunterladen & installieren"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Download & Install"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Télécharger et installer"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Scarica e installa"
          }
        }
      }
    },
    "updateCheck.download.progressFormat" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%1$d %% (%2$@ von %3$@)"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%1$d%% (%2$@ of %3$@)"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%1$d %% (%2$@ sur %3$@)"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%1$d%% (%2$@ di %3$@)"
          }
        }
      }
    },
    "updateCheck.readyToInstall.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Jetzt neu starten"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Restart Now"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Redémarrer maintenant"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Riavvia ora"
          }
        }
      }
    },
    "updateCheck.readyToInstall.message" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Bereit zu installieren"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ready to install"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Prêt à installer"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Pronto per l'installazione"
          }
        }
      }
    },
    "updateCheck.retry.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Erneut versuchen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Try Again"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Réessayer"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Riprova"
          }
        }
      }
    },
    "updateCheck.verifying.label" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Wird überprüft…"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Verifying…"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Vérification…"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Verifica in corso…"
          }
        }
      }
    },
```

Verifiziere mit `git diff --stat Feedivo/Resources/Localizable.xcstrings`: nur Insertions.

- [ ] **Step 3: `UpdateAvailableSheet.swift` footer umbauen**

Ersetze in `Feedivo/Views/Settings/UpdateAvailableSheet.swift` die bestehende `private func
footer(theme: RuleDialogTheme) -> some View`-Methode sowie ergänze am Strukturkopf ein neues
`@State`. Füge direkt nach der Zeile `@Environment(\.colorScheme) private var colorScheme`
ein:

```swift
    @State private var installer = UpdateInstaller()
```

Ersetze die komplette `footer(theme:)`-Methode durch:

```swift
    @ViewBuilder
    private func footer(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch installer.state {
            case .idle:
                EmptyView()
            case .downloading(let fraction, let downloaded, let total):
                downloadProgressView(fraction: fraction, downloaded: downloaded, total: total, theme: theme)
            case .verifying:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.updateCheckVerifyingLabel)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.text2)
                }
            case .readyToInstall:
                Text(L10n.updateCheckReadyToInstallMessage)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
            case .installing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.updateCheckReadyToInstallMessage)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.text2)
                }
            case .failed(let error):
                VStack(alignment: .leading, spacing: 6) {
                    Text(error.errorDescription ?? "")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.destructiveText)

                    Button(L10n.updateCheckOpenOnGitHubButton) {
                        onOpenOnGitHub()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.linkText)
                }
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                footerButtons(theme: theme)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func downloadProgressView(fraction: Double, downloaded: Int64, total: Int64, theme: RuleDialogTheme) -> some View {
        let formatter: ByteCountFormatter = {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter
        }()

        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: fraction)
            Text(L10n.updateCheckDownloadProgress(
                percent: Int(fraction * 100),
                downloaded: formatter.string(fromByteCount: downloaded),
                total: formatter.string(fromByteCount: total)
            ))
            .font(.system(size: 11.5))
            .foregroundStyle(theme.text2)
        }
    }

    @ViewBuilder
    private func footerButtons(theme: RuleDialogTheme) -> some View {
        switch installer.state {
        case .idle:
            RuleDialogButton(titleKey: L10n.updateCheckDownloadButton, style: .primary, theme: theme) {
                Task { await installer.startDownloadAndVerify(release: release) }
            }
        case .downloading:
            RuleDialogButton(titleKey: L10n.commonCancel, style: .secondary, theme: theme) {
                installer.cancelDownload()
            }
        case .verifying, .installing:
            EmptyView()
        case .readyToInstall:
            RuleDialogButton(titleKey: L10n.updateCheckReadyToInstallButton, style: .primary, theme: theme) {
                Task { await installer.install() }
            }
        case .failed(let error):
            RuleDialogButton(titleKey: L10n.updateCheckRetryButton, style: .primary, theme: theme) {
                Task {
                    if error.requiresFullRedownload {
                        await installer.startDownloadAndVerify(release: release)
                    } else {
                        await installer.install()
                    }
                }
            }
        }
    }
```

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Settings/UpdateAvailableSheet.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feat: Update-Dialog um Herunterladen & installieren erweitert"
```

---

### Task 11: `scripts/create_github_release.sh` — SHA256-Begleitdatei

**Files:**
- Modify: `scripts/create_github_release.sh`

**Interfaces:**
- Keine Swift-Interfaces — reines Bash-Skript.

- [ ] **Step 1: Prüfsummen-Erzeugung + zusätzlicher Upload ergänzen**

Suche in `scripts/create_github_release.sh` die Zeile:

```bash
echo "Packe $APP_PATH -> $ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
```

Ersetze sie durch:

```bash
echo "Packe $APP_PATH -> $ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

CHECKSUM_PATH="${ZIP_PATH}.sha256"
echo "Berechne SHA256-Prüfsumme -> $CHECKSUM_PATH"
shasum -a 256 "$ZIP_PATH" | awk '{print $1}' > "$CHECKSUM_PATH"
```

Suche danach die Zeile:

```bash
gh release create "$TAG" "$ZIP_PATH" \
  --title "Feedivo ${VERSION_LABEL}" \
  --notes-file "$NOTES_FILE" \
  --prerelease
```

Ersetze sie durch:

```bash
gh release create "$TAG" "$ZIP_PATH" "$CHECKSUM_PATH" \
  --title "Feedivo ${VERSION_LABEL}" \
  --notes-file "$NOTES_FILE" \
  --prerelease
```

Ergänze außerdem im Dry-Run-Vorschau-Block direkt vor der Zeile `echo "--- DRY RUN: kein
Build, keine Bestaetigungsfrage, kein Release veroeffentlicht ---"` eine Info-Zeile:

```bash
echo "  Zusätzliches Asset: $(basename "$ZIP_PATH").sha256 (SHA256-Prüfsumme)"
```

- [ ] **Step 2: Dry-Run verifizieren**

Run: `./scripts/create_github_release.sh --dry-run`
Expected: Zeigt Tag/Titel/Notes-Vorschau wie bisher plus die neue Prüfsummen-Asset-Zeile,
keine Fehler, keine tatsächliche Ausführung.

- [ ] **Step 3: Commit**

```bash
git add scripts/create_github_release.sh
git commit -m "Feat: Release-Skript veröffentlicht zusätzlich eine SHA256-Prüfsummen-Datei"
```

---

### Task 12: Regressionslauf + finale Verifikation

**Files:** Keine Änderungen — reiner Verifikationsschritt.

- [ ] **Step 1: Alle neuen/berührten Suiten gezielt laufen lassen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/GitHubReleaseCheckServiceTests -only-testing:FeedivoTests/GitHubReleaseAssetSelectionTests -only-testing:FeedivoTests/UpdateChecksumVerifierTests -only-testing:FeedivoTests/UpdateInstallErrorTests -only-testing:FeedivoTests/UpdateInstallerTests -only-testing:FeedivoTests/UpdateCheckerTests -parallel-testing-enabled NO`
Expected: Alle Tests PASS (die bereits bestehenden `UpdateCheckerTests` müssen nach den
Task-1-Änderungen an `GitHubRelease` weiterhin unverändert grün sein - falls nicht, deutet
das auf eine vergessene Anpassung an der `assets`-Default-Behandlung hin).

- [ ] **Step 2: Vollständigen Debug-Build verifizieren**

Run: `xcodebuild -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: `Localizable.xcstrings`-Diffs über den gesamten Plan hinweg prüfen**

Run: `git log --oneline -13 -- Feedivo/Resources/Localizable.xcstrings`
Erwartung: mehrere kleine Commits mit ausschließlich Insertions (keine großflächige
Neuformatierung) — bei Zweifel `git show <commit> --stat` je Commit gegenprüfen.

- [ ] **Step 4: Manuelle Live-Verifikationscheckliste dokumentieren (kein automatisierbarer Schritt)**

Diese Punkte NICHT automatisch abhaken — sie brauchen einen echten Nutzer-Durchlauf, da kein
computer-use für native macOS-Apps in dieser Umgebung verfügbar ist:

1. `scripts/create_github_release.sh` einmal real ausführen (nicht `--dry-run`) und im
   GitHub-Release tatsächlich zwei Assets sehen (`.zip` + `.zip.sha256`).
2. Auf einem älteren, bereits installierten Build den neuen Dialog öffnen, "Herunterladen &
   installieren" klicken - Fortschrittsbalken erscheint, wächst sichtbar.
3. Nach Abschluss erscheint "Bereit zu installieren" mit "Jetzt neu starten".
4. Klick auf "Jetzt neu starten" - beim allerersten Mal erscheint der `NSOpenPanel` mit dem
   Programme-Ordner vorausgewählt; nach Erlauben ersetzt sich die App und startet neu mit der
   neuen Versionsnummer (in den Einstellungen → "Über" prüfen).
5. Erneutes Update ein zweites Mal durchführen - der `NSOpenPanel` darf NICHT erneut
   erscheinen (Security-Scoped-Bookmark wird wiederverwendet).
6. Absichtlich eine falsche `.sha256`-Datei im Release hochladen (Testszenario) und
   verifizieren, dass "Verifikation fehlgeschlagen" erscheint statt eines stillen Erfolgs.
7. Während eines laufenden Downloads "Abbrechen" klicken - Dialog kehrt sauber in den
   Ausgangszustand zurück, erneuter Klick auf "Herunterladen & installieren" funktioniert.
8. Im `NSOpenPanel`-Schritt bewusst "Abbrechen" klicken - Fehlermeldung
   "Ohne diese Erlaubnis kann Feedivo sich nicht selbst aktualisieren" erscheint, "Erneut
   versuchen" zeigt den Panel erneut (ohne erneuten Download).

- [ ] **Step 5: Abschluss-Check**

```bash
git status --short
# Falls leer: nichts zu committen, Plan abgeschlossen.
```
