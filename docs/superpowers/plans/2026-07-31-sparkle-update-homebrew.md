# Sparkle-Update + Homebrew-Vertrieb Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Den unter App Sandbox nachweislich defekten Eigenbau-Updater durch Sparkle ersetzen (das die Quarantäne-Problematik über nicht-gesandboxte XPC-Installer-Helfer löst) und Feedivo zusätzlich über einen eigenen Homebrew-Tap installierbar machen, ohne dass sich beide Update-Kanäle gegenseitig stören.

**Architecture:** `SparkleUpdateCoordinator` (neuer `@Observable @MainActor`-Typ) kapselt `SPUUpdater` + eine eigene `SPUUserDriver`-Konformität und bridged Sparkles Callbacks in einen `SparkleUpdateState`-Enum, den die bestehende, bereits gestylte UI (`UpdateAvailableSheet`, `AboutSettingsView`, `UpdateUpToDateSheet`) konsumiert — Sparkles eigene Standard-UI wird nicht verwendet. Der komplette alte Eigenbau-Installer- und GitHub-API-Check-Stack (`UpdateInstaller`, `UpdateArchiveExtractor`, `UpdateAppSwapper`, `UpdateChecker`, `GitHubReleaseCheckService`, `GitHubRelease`, `UpdateVersionComparator`, …) entfällt vollständig. Ein neuer `HomebrewInstallationDetector` schaltet Sparkles Checks stumm, sobald Feedivo aus dem Homebrew-Caskroom-Pfad läuft. `create_github_release.sh` signiert Releases zusätzlich mit EdDSA, pflegt eine `appcast.xml` im Hauptrepo und aktualisiert eine Cask-Formel im neuen Tap-Repo `martinfelder/homebrew-feedivo`.

**Tech Stack:** Swift 6 / SwiftUI / `@Observable`, Sparkle 2.x (Swift Package Manager), Homebrew Cask (Ruby DSL), bash (Release-Skript).

## Global Constraints

- App Sandbox (`com.apple.security.app-sandbox`) bleibt in `Feedivo.entitlements` unverändert `true` — siehe Spec, Abschnitt „Sandboxing-Setup".
- Kein automatischer Push zu GitHub ohne explizite interaktive Bestätigung im Release-Skript (bestehende Konvention, gilt jetzt auch für das neue Tap-Repo) — siehe Spec, Abschnitt 4, Schritt 5.
- Keine Apple-Notarisierung als Teil dieses Plans — siehe Spec, Abschnitt 5.
- Eigener Homebrew-Tap, kein offizielles `homebrew/cask`-Repo — siehe Spec, Abschnitt 2.
- Kommentare im Code auf Deutsch (Projektkonvention, siehe CLAUDE.md).
- Neue Migrationen/Store-Änderungen sind in diesem Plan NICHT nötig — keine Datenbank-Berührung.
- Jede neue `L10n.swift`-Konstante muss zusätzlich einen Eintrag in `Feedivo/Resources/Localizable.xcstrings` bekommen (mind. `de`+`en`) — der Auto-Stub-Mechanismus von `xcodebuild build` greift NICHT bei indirekt referenzierten `L10n`-Keys (bekannter Gotcha, siehe CLAUDE.md).

---

## Task 1: Sparkle-Paket zum Xcode-Projekt hinzufügen

**Files:**
- Modify: `Feedivo.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `import Sparkle` wird ab diesem Task in jeder Feedivo-Quelldatei verfügbar (Package-Produkt `Sparkle`, gebunden an das `Feedivo`-Target).

Xcodes SPM-Integration lebt komplett in `project.pbxproj` — es gibt kein separates `Package.swift`. Die Bearbeitung erfolgt durch exaktes Nachbilden der bereits vorhandenen `FeedKit`/`GRDB`-Einträge (sechs zusammengehörige Stellen). Dieser Task fügt Sparkle nur als Abhängigkeit hinzu, ohne es zu benutzen — der Build muss danach weiterhin fehlerfrei durchlaufen.

- [ ] **Step 1: Neuen Package-Reference-Eintrag in der `XCRemoteSwiftPackageReference`-Sektion ergänzen**

In `Feedivo.xcodeproj/project.pbxproj`, direkt VOR der Zeile `/* End XCRemoteSwiftPackageReference section */` (aktuell nach der `GRDB`-Reference, ca. Zeile 803) einfügen:

```
		4905542D7DF447DCA584173C /* XCRemoteSwiftPackageReference "Sparkle" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/sparkle-project/Sparkle";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 2.6.0;
			};
		};
```

- [ ] **Step 2: Neuen Product-Dependency-Eintrag in der `XCSwiftPackageProductDependency`-Sektion ergänzen**

Direkt VOR `/* End XCSwiftPackageProductDependency section */` (nach dem `GRDB`-Eintrag) einfügen:

```
		247129D860AD47D7917A4FFE /* Sparkle */ = {
			isa = XCSwiftPackageProductDependency;
			package = 4905542D7DF447DCA584173C /* XCRemoteSwiftPackageReference "Sparkle" */;
			productName = Sparkle;
		};
```

- [ ] **Step 3: Neuen `PBXBuildFile`-Eintrag ergänzen**

Direkt VOR `/* End PBXBuildFile section */` (nach dem `GRDB in Frameworks`-Eintrag) einfügen:

```
		5EC653E1B64E4AC6B4BAA672 /* Sparkle in Frameworks */ = {isa = PBXBuildFile; productRef = 247129D860AD47D7917A4FFE /* Sparkle */; };
```

- [ ] **Step 4: Build-Datei in die `Frameworks`-Build-Phase des `Feedivo`-Targets eintragen**

In der `PBXFrameworksBuildPhase`-Sektion, im Block mit der ID `C9CE92542FE5A90700B9C79A` (dem `Feedivo`-App-Target-Frameworks-Block, NICHT dem Tests- oder Safari-Extension-Block), die `files`-Liste um eine Zeile ergänzen:

```
			C9CE92542FE5A90700B9C79A /* Frameworks */ = {
				isa = PBXFrameworksBuildPhase;
				buildActionMask = 2147483647;
				files = (
					C95F7D0A3315F04A00A1B2C3 /* GRDB in Frameworks */,
					C9102A872FE5A9A300E81C7E /* FeedKit in Frameworks */,
					C9102A892FE5A9A300E81C7E /* XMLKit in Frameworks */,
					5EC653E1B64E4AC6B4BAA672 /* Sparkle in Frameworks */,
				);
				runOnlyForDeploymentPostprocessing = 0;
			};
```

- [ ] **Step 5: Package-Product-Dependency auf dem `Feedivo`-Target ergänzen**

Im `PBXNativeTarget`-Block `C9CE92562FE5A90700B9C79A /* Feedivo */`, `packageProductDependencies` um den neuen Eintrag ergänzen:

```
			packageProductDependencies = (
				C95F7D093315F04A00A1B2C3 /* GRDB */,
				C9102A862FE5A9A300E81C7E /* FeedKit */,
				C9102A882FE5A9A300E81C7E /* XMLKit */,
				247129D860AD47D7917A4FFE /* Sparkle */,
			);
```

- [ ] **Step 6: Package-Reference auf dem Projekt-Objekt ergänzen**

Suche die Zeile `C95F7D083315F04A00A1B2C3 /* XCRemoteSwiftPackageReference "GRDB" */,` (Teil der `packageReferences`-Liste des Projekt-Objekts, ca. Zeile 302) und ergänze direkt danach:

```
				4905542D7DF447DCA584173C /* XCRemoteSwiftPackageReference "Sparkle" */,
```

- [ ] **Step 7: Package-Abhängigkeiten auflösen und Build verifizieren**

```bash
cd /Users/martinfelder/Developer/FeedivoMac
xcodebuild -resolvePackageDependencies -scheme Feedivo
xcodebuild -scheme Feedivo -configuration Debug build
```

Erwartet: `BUILD SUCCEEDED`. Prüfe zusätzlich, dass `Package.resolved` (unter `Feedivo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`) jetzt einen `sparkle-project/Sparkle`-Eintrag enthält:

```bash
grep -A2 "sparkle-project" Feedivo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

Falls die manuelle pbxproj-Bearbeitung fehlschlägt (z. B. `xcodebuild` meldet ein korruptes Projekt): als Fallback Xcode öffnen und das Paket stattdessen regulär über **File → Add Package Dependencies…** mit derselben Repository-URL hinzufügen — das ist der von Apple vorgesehene, robustere Weg und in Xcode jederzeit nachträglich möglich.

- [ ] **Step 8: Commit**

```bash
git add Feedivo.xcodeproj/project.pbxproj Feedivo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "build: Sparkle-Paket als Abhängigkeit hinzugefügt (noch ungenutzt)"
```

---

## Task 2: EdDSA-Signierschlüssel generieren (manueller Schritt)

**Files:** keine (reine Keychain-/Terminal-Aktion, kein Code)

**Interfaces:**
- Produces: einen Base64-kodierten öffentlichen Schlüssel-String, der in Task 3 als `SUPublicEDKey` ins Info.plist eingetragen wird. Der private Schlüssel bleibt im Schlüsselbund und wird in Task 11 vom Release-Skript über Sparkles `sign_update`-Tool genutzt.

Dieser Schritt kann NICHT von einem automatisierten Coding-Agenten übernommen werden — er erzeugt einen privaten Schlüssel im macOS-Schlüsselbund des ausführenden Nutzers und erfordert ggf. eine Zugriffsbestätigung am Bildschirm. **Muss vom Nutzer selbst im Terminal ausgeführt werden**, nicht Teil des automatisierten Subagent-Durchlaufs.

- [ ] **Step 1: `generate_keys`-Tool aus dem aufgelösten Sparkle-Paket lokalisieren und ausführen**

```bash
find ~/Library/Developer/Xcode/DerivedData -path "*sparkle*/artifacts/sparkle/Sparkle/bin/generate_keys" 2>/dev/null | head -1
```

Falls das Tool über diesen Pfad nicht gefunden wird (Pfad ist DerivedData-Build-abhängig), Sparkle-Release-ZIP mit den Bin-Tools direkt von `https://github.com/sparkle-project/Sparkle/releases/latest` laden (Datei `Sparkle-<Version>.tar.xz`, enthält `bin/generate_keys`).

```bash
./generate_keys
```

- [ ] **Step 2: Öffentlichen Schlüssel notieren**

Das Tool gibt den öffentlichen Schlüssel direkt in der Konsole aus (Base64-String). Diesen String für Task 3 bereithalten.

- [ ] **Step 3: Verifizieren, dass der private Schlüssel im Schlüsselbund liegt**

```bash
security find-generic-password -s "https://sparkle-project.org" -a "ed25519" 2>&1 | head -5
```

Erwartet: ein Treffer (Details variieren je Sparkle-Version — Hauptsache, `generate_keys` hat keinen Fehler gemeldet und einen öffentlichen Schlüssel ausgegeben).

---

## Task 3: Info.plist-Keys und Entitlements für Sparkle-Sandboxing

**Files:**
- Modify: `Feedivo/Info.plist`
- Modify: `Feedivo/Feedivo.entitlements`

**Interfaces:**
- Consumes: den öffentlichen Schlüssel-String aus Task 2.
- Produces: `SUFeedURL`, `SUPublicEDKey`, `SUEnableInstallerLauncherService` in Info.plist, gelesen von Sparkles `SPUUpdater` in Task 6.

- [ ] **Step 1: Info.plist um die drei Sparkle-Keys ergänzen**

In `Feedivo/Info.plist` (physische Datei, `GENERATE_INFOPLIST_FILE = NO` — bereits so eingerichtet seit Feature 23.2) innerhalb des äußersten `<dict>` ergänzen:

```xml
	<key>SUFeedURL</key>
	<string>https://raw.githubusercontent.com/martinfelder/feedivo-mac/main/docs/appcast.xml</string>
	<key>SUPublicEDKey</key>
	<string>DEIN_OEFFENTLICHER_SCHLUESSEL_AUS_TASK_2</string>
	<key>SUEnableInstallerLauncherService</key>
	<true/>
```

Ersetze `DEIN_OEFFENTLICHER_SCHLUESSEL_AUS_TASK_2` durch den in Task 2 notierten String.

- [ ] **Step 2: Entitlements um die Mach-Lookup-Ausnahme für den Installer-XPC-Service ergänzen**

In `Feedivo/Feedivo.entitlements`, innerhalb des äußersten `<dict>` ergänzen (Reihenfolge der bestehenden Keys unverändert lassen, neuen Key ans Ende):

```xml
	<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
	<array>
		<string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
		<string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
	</array>
```

- [ ] **Step 3: Build verifizieren**

```bash
cd /Users/martinfelder/Developer/FeedivoMac
xcodebuild -scheme Feedivo -configuration Debug build
plutil -p build/DerivedData/Build/Products/Debug/Feedivo.app/Contents/Info.plist | grep -A1 "SUFeedURL\|SUPublicEDKey\|SUEnableInstallerLauncherService"
```

Erwartet: `BUILD SUCCEEDED`, alle drei Keys erscheinen im tatsächlich gebauten `Info.plist`.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Info.plist Feedivo/Feedivo.entitlements
git commit -m "build: Sparkle Info.plist-Keys und Sandbox-Entitlement-Ausnahme ergänzt"
```

---

## Task 4: HomebrewInstallationDetector (reine Logik, TDD)

**Files:**
- Create: `Feedivo/Services/HomebrewInstallationDetector.swift`
- Test: `FeedivoTests/Services/HomebrewInstallationDetectorTests.swift`

**Interfaces:**
- Produces: `HomebrewInstallationDetector.isHomebrewCaskInstall(bundleURL: URL) -> Bool`, genutzt von `SparkleUpdateCoordinator` (Task 6) zur Steuerung, ob automatische/manuelle Checks aktiv sind.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

```swift
// FeedivoTests/Services/HomebrewInstallationDetectorTests.swift
import Testing
@testable import Feedivo

@Suite("HomebrewInstallationDetector")
struct HomebrewInstallationDetectorTests {
    @Test("erkennt Apple-Silicon-Caskroom-Pfad")
    func erkenntAppleSiliconCaskroomPfad() {
        let url = URL(fileURLWithPath: "/opt/homebrew/Caskroom/feedivo/1.0-15/Feedivo.app")
        #expect(HomebrewInstallationDetector.isHomebrewCaskInstall(bundleURL: url))
    }

    @Test("erkennt Intel-Caskroom-Pfad")
    func erkenntIntelCaskroomPfad() {
        let url = URL(fileURLWithPath: "/usr/local/Caskroom/feedivo/1.0-15/Feedivo.app")
        #expect(HomebrewInstallationDetector.isHomebrewCaskInstall(bundleURL: url))
    }

    @Test("erkennt normale Applications-Installation NICHT als Homebrew")
    func erkenntApplicationsInstallationNichtAlsHomebrew() {
        let url = URL(fileURLWithPath: "/Applications/Feedivo.app")
        #expect(!HomebrewInstallationDetector.isHomebrewCaskInstall(bundleURL: url))
    }

    @Test("erkennt Pfad mit 'Caskroom' als Teil eines anderen Ordnernamens NICHT")
    func erkenntAehnlichenPfadNicht() {
        let url = URL(fileURLWithPath: "/Users/martin/Downloads/NichtCaskroomOrdner/Feedivo.app")
        #expect(!HomebrewInstallationDetector.isHomebrewCaskInstall(bundleURL: url))
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

```bash
cd /Users/martinfelder/Developer/FeedivoMac
xcodebuild test -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/HomebrewInstallationDetectorTests \
  -parallel-testing-enabled NO 2>&1 | tail -30
```

Erwartet: Compile-Fehler „Cannot find 'HomebrewInstallationDetector' in scope".

- [ ] **Step 3: Minimale Implementierung schreiben**

```swift
// Feedivo/Services/HomebrewInstallationDetector.swift
import Foundation

/// Erkennt, ob die laufende App-Instanz aus einem Homebrew-Cask-verwalteten
/// Caskroom-Pfad heraus läuft (statt z. B. aus /Applications, nach ZIP-Download
/// per Hand entpackt). Steuert, ob Sparkles Update-Check aktiv ist -
/// Homebrew-Installationen aktualisieren ausschließlich über `brew upgrade`,
/// siehe SparkleUpdateCoordinator.
enum HomebrewInstallationDetector {
    static func isHomebrewCaskInstall(bundleURL: URL) -> Bool {
        let pathComponents = bundleURL.standardizedFileURL.pathComponents
        return pathComponents.contains("Caskroom")
    }
}
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/HomebrewInstallationDetectorTests \
  -parallel-testing-enabled NO 2>&1 | tail -30
```

Erwartet: alle 4 Tests grün.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/HomebrewInstallationDetector.swift FeedivoTests/Services/HomebrewInstallationDetectorTests.swift
git commit -m "feat: HomebrewInstallationDetector erkennt Caskroom-Installationen"
```

---

## Task 5: appcast.xml-Grundgerüst im Repo anlegen

**Files:**
- Create: `docs/appcast.xml`

**Interfaces:**
- Produces: die Datei, auf die `SUFeedURL` (Task 3) zeigt und die `create_github_release.sh` (Task 11) bei jedem Release um ein `<item>` ergänzt.

- [ ] **Step 1: Leeres, valides Appcast-Grundgerüst anlegen**

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Feedivo</title>
        <link>https://raw.githubusercontent.com/martinfelder/feedivo-mac/main/docs/appcast.xml</link>
        <description>Feedivo Release-Updates</description>
        <language>de</language>
        <!-- create_github_release.sh fügt hier bei jedem Release ein neues <item> ein -->
    </channel>
</rss>
```

- [ ] **Step 2: Committen und pushen (Voraussetzung dafür, dass die raw.githubusercontent.com-URL live erreichbar ist)**

```bash
cd /Users/martinfelder/Developer/FeedivoMac
git add docs/appcast.xml
git commit -m "feat: Sparkle-Appcast-Grundgerüst angelegt"
git push
```

- [ ] **Step 3: Erreichbarkeit der finalen URL verifizieren**

```bash
curl -sf https://raw.githubusercontent.com/martinfelder/feedivo-mac/main/docs/appcast.xml | head -10
```

Erwartet: die gerade committete XML wird ausgegeben (kann nach dem Push 1-2 Minuten dauern, bis GitHubs CDN es zeigt — bei Fehlschlag kurz erneut versuchen).

---

## Task 6: SparkleUpdateState + SparkleReleaseInfo (reine Datentypen)

**Files:**
- Create: `Feedivo/Services/SparkleUpdateState.swift`
- Create: `Feedivo/Services/SparkleReleaseInfo.swift`
- Test: `FeedivoTests/Services/SparkleReleaseInfoTests.swift`

**Interfaces:**
- Produces: `SparkleUpdateState` (Enum) und `SparkleReleaseInfo` (Struct), konsumiert von `SparkleUpdateCoordinator` (Task 7) und der UI (Task 8-9). `SparkleReleaseInfo` ersetzt `GitHubRelease` als das von der UI konsumierte Release-Datenmodell.

- [ ] **Step 1: `SparkleReleaseInfo` mit Test schreiben**

```swift
// FeedivoTests/Services/SparkleReleaseInfoTests.swift
import Testing
import Foundation
@testable import Feedivo

@Suite("SparkleReleaseInfo")
struct SparkleReleaseInfoTests {
    @Test("erstellt aus den rohen Appcast-Item-Feldern korrekt")
    func erstelltAusRohenFeldernKorrekt() {
        let info = SparkleReleaseInfo(
            tagName: "v1.0-16",
            name: "Feedivo 1.0 (16)",
            htmlURL: URL(string: "https://github.com/martinfelder/feedivo-mac/releases/tag/v1.0-16")!,
            bodyHTML: "<ul><li>Fix: Beispiel</li></ul>"
        )
        #expect(info.tagName == "v1.0-16")
        #expect(info.name == "Feedivo 1.0 (16)")
        #expect(info.bodyHTML == "<ul><li>Fix: Beispiel</li></ul>")
    }

    @Test("id entspricht tagName (Identifiable-Konformität für .sheet(item:))")
    func idEntsprichtTagName() {
        let info = SparkleReleaseInfo(
            tagName: "v1.0-16",
            name: nil,
            htmlURL: URL(string: "https://example.com")!,
            bodyHTML: nil
        )
        #expect(info.id == "v1.0-16")
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

```bash
cd /Users/martinfelder/Developer/FeedivoMac
xcodebuild test -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/SparkleReleaseInfoTests \
  -parallel-testing-enabled NO 2>&1 | tail -20
```

Erwartet: Compile-Fehler „Cannot find 'SparkleReleaseInfo' in scope".

- [ ] **Step 3: `SparkleReleaseInfo` implementieren**

```swift
// Feedivo/Services/SparkleReleaseInfo.swift
import Foundation

/// Reiner Wertetyp für ein Sparkle-Appcast-Item, so wie ihn die UI
/// (UpdateAvailableSheet, UpdateUpToDateSheet) konsumiert - absichtlich ohne
/// Sparkle-Import, damit die UI nicht direkt von SUAppcastItem abhängt
/// (Snapshot-Pattern-Konvention, siehe CLAUDE.md "Kernarchitektur").
struct SparkleReleaseInfo: Equatable, Sendable, Identifiable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let bodyHTML: String?

    var id: String { tagName }
}
```

- [ ] **Step 4: `SparkleUpdateState` implementieren (kein eigener Test - reines Enum ohne Logik)**

```swift
// Feedivo/Services/SparkleUpdateState.swift
import Foundation

/// Zustand des Sparkle-gestützten Update-Vorgangs - Pendant zum entfernten
/// UpdateInstallState/UpdateCheckOutcome, jetzt als eine gemeinsame
/// Zustandsmaschine für Check UND Installation.
enum SparkleUpdateState: Equatable {
    case idle
    case checking
    case updateAvailable(SparkleReleaseInfo)
    case downloading(fractionCompleted: Double, downloadedBytes: Int64, totalBytes: Int64)
    case extracting(progress: Double)
    case readyToInstall
    case installing
    case upToDate
    case failed(String)
}
```

- [ ] **Step 5: Tests ausführen, Erfolg verifizieren**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/SparkleReleaseInfoTests \
  -parallel-testing-enabled NO 2>&1 | tail -20
```

Erwartet: beide Tests grün.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/SparkleUpdateState.swift Feedivo/Services/SparkleReleaseInfo.swift FeedivoTests/Services/SparkleReleaseInfoTests.swift
git commit -m "feat: SparkleUpdateState/SparkleReleaseInfo als neue Update-Datentypen"
```

---

## Task 7: SparkleUpdateCoordinator (SPUUserDriver-Konformität)

**Files:**
- Create: `Feedivo/Services/SparkleUpdateCoordinator.swift`
- Create: `Feedivo/Services/SparkleUpdateCoordinatorEnvironment.swift`

**Interfaces:**
- Consumes: `SparkleUpdateState`/`SparkleReleaseInfo` (Task 6), `HomebrewInstallationDetector.isHomebrewCaskInstall(bundleURL:)` (Task 4).
- Produces: `SparkleUpdateCoordinator` mit `private(set) var state: SparkleUpdateState`, `private(set) var hasUnseenUpdate: Bool`, `let isHomebrewInstall: Bool`, `func start()`, `func checkForUpdatesManually()`, `func installUpdate()`, `func cancelDownload()`. Umgebungswert `\.sparkleUpdateCoordinator`, konsumiert von Task 8/9.

Dies ist die zentrale, komplexeste Datei dieses Plans - sie implementiert `SPUUserDriver`. **Wichtiger Hinweis für den Implementierer:** Die exakten Methodensignaturen des `SPUUserDriver`-Protokolls können sich zwischen Sparkle-Versionen leicht unterscheiden. Die unten gezeigte Implementierung basiert auf der aktuellen offiziellen Sparkle-2-API-Referenz (async/await-Stil, passend zu diesem Projekt, siehe ADR-003). Schlägt der Build mit „Type does not conform to protocol 'SPUUserDriver'" fehl, zeigt Xcodes Fehlermeldung/Quick-Fix die exakt erwartete Signatur der installierten Sparkle-Version - danach die betroffene Methode entsprechend anpassen (Signatur exakt aus dem Compiler-Fehler übernehmen, Body-Logik unverändert lassen).

- [ ] **Step 1: `SparkleUpdateCoordinator` mit `SPUUserDriver`-Konformität implementieren**

```swift
// Feedivo/Services/SparkleUpdateCoordinator.swift
import Foundation
import Observation
import Sparkle
import OSLog

/// Ersetzt den entfernten UpdateInstaller/UpdateChecker-Stack vollständig.
/// Kapselt SPUUpdater + eine eigene SPUUserDriver-Konformität, damit die
/// bereits gestylte UI (UpdateAvailableSheet etc.) erhalten bleibt, statt auf
/// Sparkles eigene Standardfenster zu wechseln. EIN Coordinator pro
/// App-Prozess - wird in FeedivoApp.swift als einziges @State erzeugt und
/// per Environment durchgereicht, da SPUUpdater selbst als Singleton pro
/// Prozess gedacht ist.
@Observable
@MainActor
final class SparkleUpdateCoordinator: NSObject {
    private(set) var state: SparkleUpdateState = .idle
    private(set) var hasUnseenUpdate = false
    let isHomebrewInstall: Bool

    private var updater: SPUUpdater?
    private var pendingUpdateChoice: ((SPUUserUpdateChoice) -> Void)?
    private var pendingInstallChoice: ((SPUUserUpdateChoice) -> Void)?
    private var pendingCancellation: (() -> Void)?

    override init() {
        self.isHomebrewInstall = HomebrewInstallationDetector.isHomebrewCaskInstall(
            bundleURL: Bundle.main.bundleURL
        )
        super.init()
    }

    /// Muss einmalig beim App-Start aufgerufen werden (FeedivoApp.swift).
    /// Bei Homebrew-Installationen bewusst KEIN SPUUpdater erzeugt - Sparkle
    /// bleibt in dem Fall komplett inaktiv, Updates laufen ausschließlich
    /// über `brew upgrade` (siehe Spec, Abschnitt 3).
    func start() {
        guard !isHomebrewInstall else {
            AppLogger.dataAccess.info("SparkleUpdateCoordinator: Homebrew-Installation erkannt, Sparkle bleibt inaktiv.")
            return
        }
        let updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: self,
            delegate: nil
        )
        self.updater = updater
        // object(forKey:) != nil-Guard statt defaultValue-Kurzschluss - reiner
        // .bool(forKey:) würde bei fehlendem gespeichertem Wert immer `false`
        // liefern statt UpdateCheckSettings.defaultIsAutomaticCheckEnabled
        // (bekannter Gotcha, siehe CLAUDE.md zu retentionDays).
        let storedIsAutomaticCheckEnabled = UserDefaults.standard.object(forKey: UpdateCheckSettings.isAutomaticCheckEnabledKey) as? Bool
            ?? UpdateCheckSettings.defaultIsAutomaticCheckEnabled
        updater.automaticallyChecksForUpdates = storedIsAutomaticCheckEnabled
        do {
            try updater.start()
        } catch {
            AppLogger.dataAccess.error("SparkleUpdateCoordinator: SPUUpdater konnte nicht gestartet werden: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    func checkForUpdatesManually() {
        guard !isHomebrewInstall else { return }
        hasUnseenUpdate = false
        state = .checking
        updater?.checkForUpdates()
    }

    /// Bindet den bestehenden "Automatischer Check"-Schalter (AboutSettingsView,
    /// @AppStorage(UpdateCheckSettings.isAutomaticCheckEnabledKey)) an Sparkles
    /// eigenes automatisches-Check-Verhalten - ohne diesen Aufruf würde der
    /// Schalter nach der Umstellung wirkungslos bleiben, da SPUUpdater seine
    /// automatischen Checks über eine eigene Property steuert, nicht über
    /// unsere UserDefaults. Wird beim Start (aus dem aktuell gespeicherten
    /// Wert) UND bei jeder Toggle-Änderung in AboutSettingsView aufgerufen.
    func setAutomaticChecksEnabled(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
    }

    func installUpdate() {
        pendingInstallChoice?(.install)
        pendingInstallChoice = nil
    }

    func cancelDownload() {
        pendingCancellation?()
        pendingCancellation = nil
        state = .idle
    }
}

// MARK: - SPUUserDriver

extension SparkleUpdateCoordinator: SPUUserDriver {
    nonisolated func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        // Automatische Checks sind über Sparkles SUEnableAutomaticChecks-
        // Verhalten gesteuert - wir erlauben pauschal, ohne eigenen Dialog
        // (entspricht dem bisherigen Verhalten: automatischer, stiller
        // Start-Check ohne Rückfrage an den Nutzer).
        SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state updateState: SPUUserUpdateState) async -> SPUUserUpdateChoice {
        let info = SparkleReleaseInfo(
            tagName: appcastItem.displayVersionString,
            name: appcastItem.title,
            htmlURL: appcastItem.infoURL ?? URL(string: "https://github.com/martinfelder/feedivo-mac/releases")!,
            bodyHTML: appcastItem.itemDescription
        )
        self.state = .updateAvailable(info)
        hasUnseenUpdate = true
        return await withCheckedContinuation { continuation in
            pendingUpdateChoice = { choice in continuation.resume(returning: choice) }
        }
    }

    nonisolated func showDownloadInitiated(cancellation: @escaping () -> Void) {
        Task { @MainActor in
            self.pendingCancellation = cancellation
            self.state = .downloading(fractionCompleted: 0, downloadedBytes: 0, totalBytes: 0)
        }
    }

    nonisolated func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        Task { @MainActor in
            if case .downloading(_, let downloaded, _) = self.state {
                self.state = .downloading(fractionCompleted: 0, downloadedBytes: downloaded, totalBytes: Int64(expectedContentLength))
            }
        }
    }

    nonisolated func showDownloadDidReceiveData(ofLength length: UInt64) {
        Task { @MainActor in
            guard case .downloading(_, let downloaded, let total) = self.state else { return }
            let newDownloaded = downloaded + Int64(length)
            let fraction = total > 0 ? Double(newDownloaded) / Double(total) : 0
            self.state = .downloading(fractionCompleted: fraction, downloadedBytes: newDownloaded, totalBytes: total)
        }
    }

    nonisolated func showDownloadDidStartExtractingUpdate() {
        Task { @MainActor in self.state = .extracting(progress: 0) }
    }

    nonisolated func showExtractionReceivedProgress(_ progress: Double) {
        Task { @MainActor in self.state = .extracting(progress: progress) }
    }

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        state = .readyToInstall
        return await withCheckedContinuation { continuation in
            pendingInstallChoice = { choice in continuation.resume(returning: choice) }
        }
    }

    nonisolated func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        Task { @MainActor in self.state = .installing }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        state = .idle
    }

    func showUpdaterError(_ error: any Error) async {
        state = .failed(error.localizedDescription)
    }

    func showUpdateNotFoundWithError(_ error: any Error) async {
        state = .upToDate
    }

    nonisolated func dismissUpdateInstallation() {
        Task { @MainActor in self.state = .idle }
    }
}
```

- [ ] **Step 2: Environment-Key ergänzen (exakt nach dem Muster von `FeedivoDatabaseEnvironment.swift`)**

```swift
// Feedivo/Services/SparkleUpdateCoordinatorEnvironment.swift
import SwiftUI

private struct SparkleUpdateCoordinatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: SparkleUpdateCoordinator? = nil
}

extension EnvironmentValues {
    var sparkleUpdateCoordinator: SparkleUpdateCoordinator? {
        get { self[SparkleUpdateCoordinatorEnvironmentKey.self] }
        set { self[SparkleUpdateCoordinatorEnvironmentKey.self] = newValue }
    }
}
```

- [ ] **Step 3: Build verifizieren, Signaturen bei Bedarf korrigieren**

```bash
cd /Users/martinfelder/Developer/FeedivoMac
xcodebuild -scheme Feedivo -configuration Debug build 2>&1 | grep -A5 "does not conform to protocol\|error:"
```

Erwartet: entweder `BUILD SUCCEEDED`, oder eine Liste konkreter Signatur-Diffs, die Zeile für Zeile in Step 1 korrigiert werden (siehe Hinweis oben) - danach erneut bauen, bis `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Services/SparkleUpdateCoordinator.swift Feedivo/Services/SparkleUpdateCoordinatorEnvironment.swift
git commit -m "feat: SparkleUpdateCoordinator kapselt SPUUpdater hinter eigenem SPUUserDriver"
```

---

## Task 8: FeedivoApp.swift auf SparkleUpdateCoordinator umstellen

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift:8-473` (Update-bezogene `@AppStorage`/`@State`-Properties, `.sheet`/`.alert`-Modifier, `CommandGroup`, `runUpdateCheck()`, `performManualUpdateCheck()`, `performSilentUpdateCheckIfNeeded()`)

**Interfaces:**
- Consumes: `SparkleUpdateCoordinator` (Task 7).
- Produces: `\.sparkleUpdateCoordinator` wird ab hier in der View-Hierarchie befüllt, konsumiert von `UpdateAvailableSheet`/`AboutSettingsView`/`UpdateUpToDateSheet` (Task 9).

- [ ] **Step 1: Alte Update-Check-`@AppStorage`/`@State`-Properties (Zeilen 38-54) durch einen einzigen Coordinator ersetzen**

Entferne:
```swift
    @AppStorage(UpdateCheckSettings.isAutomaticCheckEnabledKey)
    private var updateCheckIsAutomaticCheckEnabled = UpdateCheckSettings.defaultIsAutomaticCheckEnabled

    @AppStorage(UpdateCheckSettings.hasUnseenUpdateKey)
    private var updateCheckHasUnseenUpdate = UpdateCheckSettings.defaultHasUnseenUpdate

    @State private var updateCheckReleasePresentation: GitHubRelease?
    @State private var showsUpdateCheckUpToDateAlert = false
    @State private var updateCheckUpToDateRelease: GitHubRelease?
    @State private var updateCheckErrorMessage: String?
    @State private var isUpdateCheckInFlight = false
```

Ersetze durch:
```swift
    @State private var sparkleUpdateCoordinator = SparkleUpdateCoordinator()
```

- [ ] **Step 2: `.sheet`/`.alert`-Modifier (Zeilen 188-222) auf den Coordinator-State umstellen**

Ersetze den kompletten Block (`.sheet(item: $updateCheckReleasePresentation)` bis zum Ende des `.alert(...)`-Blocks) durch:

```swift
                .sheet(
                    isPresented: Binding(
                        get: {
                            if case .updateAvailable = sparkleUpdateCoordinator.state { return true }
                            if case .downloading = sparkleUpdateCoordinator.state { return true }
                            if case .extracting = sparkleUpdateCoordinator.state { return true }
                            if case .readyToInstall = sparkleUpdateCoordinator.state { return true }
                            if case .installing = sparkleUpdateCoordinator.state { return true }
                            return false
                        },
                        set: { isPresented in
                            if !isPresented { sparkleUpdateCoordinator.cancelDownload() }
                        }
                    )
                ) {
                    if case .updateAvailable(let release) = sparkleUpdateCoordinator.state {
                        UpdateAvailableSheet(
                            release: release,
                            onOpenOnGitHub: { NSWorkspace.shared.open(release.htmlURL) },
                            onDismiss: { sparkleUpdateCoordinator.cancelDownload() }
                        )
                    }
                }
                .sheet(isPresented: Binding(
                    get: { sparkleUpdateCoordinator.state == .upToDate },
                    set: { _ in }
                )) {
                    UpdateUpToDateSheet(
                        installedVersion: "\(AppVersionInfo.marketingVersion) (\(AppVersionInfo.buildNumber))",
                        onDismiss: { sparkleUpdateCoordinator.cancelDownload() }
                    )
                }
                .alert(
                    L10n.updateCheckErrorTitle,
                    isPresented: Binding(
                        get: {
                            if case .failed = sparkleUpdateCoordinator.state { return true }
                            return false
                        },
                        set: { isPresented in
                            if !isPresented { sparkleUpdateCoordinator.cancelDownload() }
                        }
                    )
                ) {
                    Button(L10n.commonOK, role: .cancel) {}
                } message: {
                    if case .failed(let message) = sparkleUpdateCoordinator.state {
                        Text(message)
                    }
                }
                .environment(\.sparkleUpdateCoordinator, sparkleUpdateCoordinator)
```

Hinweis: `UpdateAvailableSheet`/`UpdateUpToDateSheet` bekommen ihre Sparkle-Anbindung ab jetzt über `\.sparkleUpdateCoordinator` aus dem Environment (Task 9), nicht mehr über direkt übergebene Closures für den Installationsvorgang - `release`/`onOpenOnGitHub`/`onDismiss` bleiben als Init-Parameter erhalten, da sie reine Anzeige-/Navigations-Belange sind, keine Installationslogik.

- [ ] **Step 3: `CommandGroup`-Button (Zeile 240) umstellen**

Ersetze:
```swift
                Button(L10n.updateCheckMenuItem) {
                    performManualUpdateCheck()
                }
```

Durch:
```swift
                Button(L10n.updateCheckMenuItem) {
                    openWindow(id: "main")
                    sparkleUpdateCoordinator.checkForUpdatesManually()
                }
```

- [ ] **Step 4: `runUpdateCheck()`/`performManualUpdateCheck()`/`performSilentUpdateCheckIfNeeded()` (Zeilen 415-472) entfernen**

Diese drei Methoden entfallen komplett - `SparkleUpdateCoordinator.start()` übernimmt den automatischen Start-Check (Sparkles eigener `SUEnableAutomaticChecks`-Mechanismus), `checkForUpdatesManually()` den manuellen Check.

- [ ] **Step 5: `sparkleUpdateCoordinator.start()` beim App-Start aufrufen**

Suche die Stelle, an der bisher `performSilentUpdateCheckIfNeeded()` aufgerufen wurde:

```bash
grep -n "performSilentUpdateCheckIfNeeded()" Feedivo/App/FeedivoApp.swift
```

und ersetze den Aufruf durch:

```swift
        sparkleUpdateCoordinator.start()
```

- [ ] **Step 6: Build verifizieren**

```bash
cd /Users/martinfelder/Developer/FeedivoMac
xcodebuild -scheme Feedivo -configuration Debug build
```

Erwartet: Compile-Fehler in `UpdateAvailableSheet.swift`/`AboutSettingsView.swift`/`UpdateUpToDateSheet.swift` (erwartet an dieser Stelle - werden in Task 9 behoben). `FeedivoApp.swift` selbst darf keine Fehler mehr melden.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/App/FeedivoApp.swift
git commit -m "refactor: FeedivoApp.swift auf SparkleUpdateCoordinator umgestellt"
```

---

## Task 9: UI-Dateien (UpdateAvailableSheet, AboutSettingsView, UpdateUpToDateSheet) umstellen

**Files:**
- Modify: `Feedivo/Views/Settings/UpdateAvailableSheet.swift`
- Modify: `Feedivo/Views/Settings/AboutSettingsView.swift`
- Modify: `Feedivo/Views/Settings/UpdateUpToDateSheet.swift`

**Interfaces:**
- Consumes: `\.sparkleUpdateCoordinator` (Task 7/8), `SparkleReleaseInfo`/`SparkleUpdateState` (Task 6).

- [ ] **Step 1: `UpdateAvailableSheet.swift` - `installer`-State durch Environment-Coordinator ersetzen**

Ersetze:
```swift
    @State private var installer = UpdateInstaller()
```
durch:
```swift
    @Environment(\.sparkleUpdateCoordinator) private var coordinator
```

Ersetze jedes `installer.state` durch `coordinator?.state ?? .idle`, jedes `installer.cancelDownload()` durch `coordinator?.cancelDownload()`, jedes `Task { await installer.startDownloadAndVerify(release: release) }` durch `coordinator?.checkForUpdatesManually()`, und jedes `Task { await installer.install() }` durch `coordinator?.installUpdate()`.

Der `release: GitHubRelease`-Parameter des Inits wird zu `release: SparkleReleaseInfo`. `installedVersion`-Berechnung, `blocks`/`categorizedGroups`-Logik (Release-Notes-Rendering) bleiben vollständig unverändert - sie arbeiten bereits rein auf `release.bodyHTML`, unabhängig vom konkreten Release-Typ.

- [ ] **Step 2: `AboutSettingsView.swift` umstellen**

Ersetze die lokalen `@State`-Properties (`isChecking`, `releasePresentation`, `showsUpToDateAlert`, `upToDateRelease`, `errorMessage`) und `performCheck()` durch direktes Lesen von `coordinator.state`:

```swift
    @Environment(\.sparkleUpdateCoordinator) private var coordinator
    @AppStorage(UpdateCheckSettings.isAutomaticCheckEnabledKey)
    private var isAutomaticCheckEnabled = UpdateCheckSettings.defaultIsAutomaticCheckEnabled
```

Der manuelle Check-Button ruft `coordinator?.checkForUpdatesManually()` auf; `isChecking` wird durch `coordinator?.state == .checking` ersetzt; `hasUnseenUpdate` liest `coordinator?.hasUnseenUpdate ?? false` statt der bisherigen `@AppStorage`. Die `.sheet`/`.alert`-Modifier dieser View werden komplett entfernt - Sheet/Alert-Präsentation läuft jetzt zentral über `FeedivoApp.swift` (Task 8), damit nicht zwei unabhängige Präsentationsorte um denselben `SparkleUpdateCoordinator`-State konkurrieren.

Der bestehende Toggle (`Toggle("", isOn: $isAutomaticCheckEnabled)`) bleibt bestehen, bekommt aber zusätzlich einen `.onChange`-Handler, damit die Änderung tatsächlich bei Sparkle ankommt (siehe neue `setAutomaticChecksEnabled(_:)`-Methode aus Task 7):

```swift
                Toggle("", isOn: $isAutomaticCheckEnabled)
                    .labelsHidden()
                    .onChange(of: isAutomaticCheckEnabled) { _, newValue in
                        coordinator?.setAutomaticChecksEnabled(newValue)
                    }
```

Bei `isHomebrewInstall == true` (aus `coordinator?.isHomebrewInstall`) zeigt der Block statt des Such-Buttons einen Hinweistext mit dem neuen L10n-Key `L10n.updateCheckHomebrewHint` (siehe Step 4).

- [ ] **Step 3: `UpdateUpToDateSheet.swift` - `latestKnownRelease`-Parameter entfernen**

Sparkles `showUpdateNotFoundWithError` liefert keine „zuletzt bekannte Version" mehr (das war eine GitHub-API-Spezialität). Entferne den Parameter `latestKnownRelease: GitHubRelease?` und die zugehörige zweite Text-Zeile (Zeilen 32-37); die View zeigt nur noch die installierte Version:

```swift
struct UpdateUpToDateSheet: View {
    let installedVersion: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.updateCheckUpToDateTitle)
                .font(.system(size: 15, weight: .semibold))

            (
                Text(L10n.updateCheckInstalledLabelPrefix)
                    + Text(installedVersion).foregroundColor(.green).fontWeight(.semibold)
            )
            .font(.system(size: 13))

            HStack {
                Spacer()
                Button(L10n.commonOK) {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 320, minHeight: 140)
    }
}
```

- [ ] **Step 4: Neuen L10n-Key für den Homebrew-Hinweis ergänzen**

In `Feedivo/Resources/L10n.swift`, in der Nähe der bestehenden `updateCheck*`-Keys (ca. Zeile 1145) ergänzen:

```swift
    static let updateCheckHomebrewHint = LocalizedStringKey("updateCheck.homebrewHint")
```

In `Feedivo/Resources/Localizable.xcstrings`, direkt nach dem stabilen Anker `"strings" : {` einen neuen Eintrag einfügen (NICHT die gesamte Datei per JSON-Roundtrip neu schreiben - siehe bekannter Gotcha zu `json.dump` auf diese Datei):

```json
    "updateCheck.homebrewHint" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Über Homebrew installiert — aktualisiere mit „brew upgrade --cask feedivo“."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Installed via Homebrew — update with “brew upgrade --cask feedivo”."
          }
        }
      }
    },
```

Verifizieren:
```bash
grep -c "updateCheck.homebrewHint" /Users/martinfelder/Developer/FeedivoMac/Feedivo/Resources/Localizable.xcstrings
```
Erwartet: `1` (oder mehr).

- [ ] **Step 5: Build verifizieren**

```bash
cd /Users/martinfelder/Developer/FeedivoMac
xcodebuild -scheme Feedivo -configuration Debug build
```

Erwartet: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Settings/UpdateAvailableSheet.swift Feedivo/Views/Settings/AboutSettingsView.swift Feedivo/Views/Settings/UpdateUpToDateSheet.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "refactor: Update-UI liest jetzt SparkleUpdateCoordinator statt GitHub-API-Stack"
```

---

## Task 10: Alten Eigenbau-Stack entfernen

**Files:**
- Delete: `Feedivo/Services/UpdateInstaller.swift`
- Delete: `Feedivo/Services/UpdateArchiveExtractor.swift`
- Delete: `Feedivo/Services/UpdateAppSwapper.swift`
- Delete: `Feedivo/Services/UpdateInstallLocationGrantor.swift`
- Delete: `Feedivo/Services/UpdateAssetDownloader.swift`
- Delete: `Feedivo/Services/UpdateChecksumVerifier.swift`
- Delete: `Feedivo/Services/UpdateInstallState.swift`
- Delete: `Feedivo/Services/UpdateChecker.swift`
- Delete: `Feedivo/Services/GitHubReleaseCheckService.swift`
- Delete: `Feedivo/Services/GitHubRelease.swift`
- Delete: `Feedivo/Services/UpdateVersionComparator.swift`
- Delete: zugehörige Testdateien (per `find`, siehe Step 3)

**Interfaces:** keine (reine Löschung, keine neuen Schnittstellen)

- [ ] **Step 1: Alle Referenzen auf die zu löschenden Typen finden**

```bash
cd /Users/martinfelder/Developer/FeedivoMac
grep -rl "UpdateInstaller\|UpdateArchiveExtractor\|UpdateAppSwapper\|UpdateInstallLocationGrantor\|UpdateAssetDownloader\|UpdateChecksumVerifier\|UpdateInstallState\|UpdateInstallError\b\|\bUpdateChecker\b\|GitHubReleaseCheckService\|GitHubRelease\b\|GitHubReleaseAsset\|UpdateVersionComparator\|UpdateCheckOutcome" Feedivo FeedivoTests --include="*.swift"
```

Jede zurückgegebene Datei außerhalb der unten gelisteten Lösch-Kandidaten muss vor dem Löschen geprüft und ggf. separat angepasst werden. `UpdateCheckSettings.swift` bleibt bestehen (wird weiterhin für den `isAutomaticCheckEnabled`-Toggle gebraucht) und darf NICHT gelöscht werden, auch wenn es im Grep auftaucht.

- [ ] **Step 2: Produktionscode löschen**

```bash
rm Feedivo/Services/UpdateInstaller.swift
rm Feedivo/Services/UpdateArchiveExtractor.swift
rm Feedivo/Services/UpdateAppSwapper.swift
rm Feedivo/Services/UpdateInstallLocationGrantor.swift
rm Feedivo/Services/UpdateAssetDownloader.swift
rm Feedivo/Services/UpdateChecksumVerifier.swift
rm Feedivo/Services/UpdateInstallState.swift
rm Feedivo/Services/UpdateChecker.swift
rm Feedivo/Services/GitHubReleaseCheckService.swift
rm Feedivo/Services/GitHubRelease.swift
rm Feedivo/Services/UpdateVersionComparator.swift
```

- [ ] **Step 3: Zugehörige Tests finden und löschen**

```bash
find FeedivoTests \( -iname "UpdateInstaller*Tests.swift" -o -iname "UpdateArchiveExtractor*Tests.swift" \
  -o -iname "UpdateAppSwapper*Tests.swift" -o -iname "UpdateInstallLocationGrantor*Tests.swift" \
  -o -iname "UpdateAssetDownloader*Tests.swift" -o -iname "UpdateChecksumVerifier*Tests.swift" \
  -o -iname "UpdateChecker*Tests.swift" -o -iname "GitHubReleaseCheckService*Tests.swift" \
  -o -iname "GitHubRelease*Tests.swift" -o -iname "UpdateVersionComparator*Tests.swift" \) \
  -exec rm {} \;
```

- [ ] **Step 4: Vollständigen Build + gezielten Testlauf verifizieren**

```bash
cd /Users/martinfelder/Developer/FeedivoMac
xcodebuild -scheme Feedivo -configuration Debug build
xcodebuild test -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/HomebrewInstallationDetectorTests \
  -only-testing:FeedivoTests/SparkleReleaseInfoTests \
  -only-testing:FeedivoTests/UpdateReleaseNoteCategorizerTests \
  -parallel-testing-enabled NO 2>&1 | tail -40
```

Erwartet: `BUILD SUCCEEDED`, alle Tests grün. Falls `UpdateReleaseNoteCategorizerTests` fehlschlägt, weil seine Fixtures noch `GitHubRelease`-Typen referenzieren: Fixtures auf reine HTML-Strings umstellen (der Categorizer arbeitet bereits auf `[ReaderInlineRun]`/HTML-Text, nicht auf `GitHubRelease` selbst - `UpdateReleaseNoteCategorizer.swift` selbst sollte unverändert bleiben).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: alten Eigenbau-Update-Installer und GitHub-API-Check-Stack entfernt (durch Sparkle ersetzt)"
```

---

## Task 11: create_github_release.sh um Sparkle-Signierung + Appcast-Update erweitern

**Files:**
- Modify: `scripts/create_github_release.sh`

**Interfaces:**
- Consumes: Sparkles `sign_update`-Tool (Task 2 lokalisiert, gleicher Pfad hier wiederverwendet).
- Produces: aktualisierte `docs/appcast.xml` bei jedem Release-Lauf.

- [ ] **Step 1: Sparkle-`sign_update`-Pfad-Ermittlung + Appcast-Update nach dem bestehenden `gh release create`-Aufruf ergänzen**

In `scripts/create_github_release.sh`, direkt nach der Zeile `echo "create_github_release.sh: Release $TAG veroeffentlicht."` (aktuell letzte Zeile vor `rm -f "$NOTES_FILE"`) folgenden Block einfügen:

```bash
echo "Signiere ZIP für Sparkle (EdDSA)..."
SIGN_UPDATE_TOOL="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*sparkle*/artifacts/sparkle/Sparkle/bin/sign_update" 2>/dev/null | head -1)"
if [ -z "$SIGN_UPDATE_TOOL" ]; then
  echo "create_github_release.sh: sign_update-Tool nicht gefunden - Appcast wird NICHT aktualisiert. Bitte Xcode-Build einmal ausführen (löst SPM-Artefakte auf) und erneut versuchen." >&2
  exit 1
fi
ED_SIGNATURE_LINE="$("$SIGN_UPDATE_TOOL" "$ZIP_PATH")"
ED_SIGNATURE="$(echo "$ED_SIGNATURE_LINE" | grep -oE 'sparkle:edSignature="[^"]*"' | sed -E 's/sparkle:edSignature="([^"]*)"/\1/')"
ZIP_LENGTH="$(stat -f%z "$ZIP_PATH")"

echo "Aktualisiere docs/appcast.xml..."
APPCAST_PATH="$REPO_ROOT/docs/appcast.xml"
NEW_ITEM="    <item>
      <title>${TAG}</title>
      <pubDate>$(date -u +"%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <description><![CDATA[$(cat "$NOTES_FILE")]]></description>
      <enclosure url=\"https://github.com/martinfelder/feedivo-mac/releases/download/${TAG}/$(basename "$ZIP_PATH")\"
                 sparkle:version=\"${BUILD_NUMBER}\"
                 sparkle:shortVersionString=\"${MARKETING_VERSION}\"
                 sparkle:edSignature=\"${ED_SIGNATURE}\"
                 length=\"${ZIP_LENGTH}\"
                 type=\"application/octet-stream\"/>
    </item>"
# Fügt das neue <item> direkt nach dem stabilen Kommentar-Anker in der
# channel-Sektion ein (siehe docs/appcast.xml-Grundgerüst, Task 5) - nicht
# per XML-Parser-Roundtrip, um das Formatierungs-Risiko aus dem bekannten
# Localizable.xcstrings-Gotcha nicht zu wiederholen.
python3 - "$APPCAST_PATH" "$NEW_ITEM" <<'PYEOF'
import sys
path, new_item = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()
anchor = "<!-- create_github_release.sh fügt hier bei jedem Release ein neues <item> ein -->"
content = content.replace(anchor, anchor + "\n" + new_item)
with open(path, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF

git -C "$REPO_ROOT" add docs/appcast.xml
git -C "$REPO_ROOT" commit -m "chore: Appcast-Eintrag für ${TAG}"

read -r -p "Appcast-Commit nach origin/main pushen? [y/N] " PUSH_CONFIRM
if [[ "$PUSH_CONFIRM" =~ ^[Yy]$ ]]; then
  git -C "$REPO_ROOT" push
  echo "create_github_release.sh: Appcast gepusht."
else
  echo "create_github_release.sh: Appcast-Commit lokal, NICHT gepusht (manuell nachholen: git push)."
fi
```

- [ ] **Step 2: Syntax-Check**

```bash
cd /Users/martinfelder/Developer/FeedivoMac
bash -n scripts/create_github_release.sh
```

Erwartet: keine Ausgabe. Ein echter End-to-End-Test dieses Skripts erfordert einen tatsächlichen neuen Release-Lauf - das ist bewusst NICHT Teil dieses automatisierten Tasks (siehe Global Constraints: kein automatischer Push ohne Bestätigung, und ein echter Release-Lauf ist eine sichtbare, öffentliche Aktion).

- [ ] **Step 3: Commit**

```bash
git add scripts/create_github_release.sh
git commit -m "feat: create_github_release.sh signiert Releases für Sparkle und pflegt appcast.xml"
```

---

## Task 12: Homebrew-Tap-Repository anlegen

**Files:**
- Create (in neuem, separatem Repo `martinfelder/homebrew-feedivo`): `Casks/feedivo.rb`, `README.md`

**Interfaces:** keine Code-Schnittstelle - reine Repo-/Dateistruktur, konsumiert von `brew tap`/`brew install --cask`.

**Hinweis:** Das Anlegen eines neuen ÖFFENTLICHEN GitHub-Repos ist eine sichtbare, öffentliche Aktion - dieser Task darf nur mit expliziter Bestätigung des Nutzers zum Ausführungszeitpunkt laufen (nicht automatisch von einem Subagenten ohne Rückfrage gestartet werden).

- [ ] **Step 1: Repo anlegen (nach Nutzerbestätigung)**

```bash
gh repo create martinfelder/homebrew-feedivo --public --description "Homebrew Tap für Feedivo (macOS RSS Reader)" --clone
cd homebrew-feedivo
mkdir -p Casks
```

- [ ] **Step 2: Werte des aktuellsten Release ermitteln und Cask-Datei anlegen**

```bash
cd /Users/martinfelder/Developer/FeedivoMac
LATEST_TAG="$(gh release list --limit 1 --json tagName --jq '.[0].tagName')"
LATEST_SHA256="$(gh release view "$LATEST_TAG" --json assets --jq '.assets[] | select(.name | endswith(".sha256")) | .url' | xargs curl -sL)"
MARKETING_VERSION="$(echo "$LATEST_TAG" | sed -E 's/^v([0-9.]+)-([0-9]+)$/\1/')"
BUILD_NUMBER="$(echo "$LATEST_TAG" | sed -E 's/^v([0-9.]+)-([0-9]+)$/\2/')"
echo "Version: $MARKETING_VERSION,$BUILD_NUMBER  SHA256: $LATEST_SHA256"
```

Mit den ausgegebenen Werten `~/Developer/homebrew-feedivo/Casks/feedivo.rb` anlegen:

```ruby
cask "feedivo" do
  version "MARKETING_VERSION,BUILD_NUMBER"
  sha256 "SHA256_WERT"

  url "https://github.com/martinfelder/feedivo-mac/releases/download/v#{version.csv[0]}-#{version.csv[1]}/Feedivo-v#{version.csv[0]}-#{version.csv[1]}.zip"
  name "Feedivo"
  desc "Nativer macOS RSS Reader mit Tags, Regeln und intelligenten Ordnern"
  homepage "https://github.com/martinfelder/feedivo-mac"

  app "Feedivo.app"

  zap trash: [
    "~/Library/Containers/ch.martin.Feedivo",
    "~/Library/Preferences/ch.martin.Feedivo.plist",
  ]
end
```

Ersetze `MARKETING_VERSION`, `BUILD_NUMBER`, `SHA256_WERT` durch die in diesem Step ausgegebenen echten Werte (Homebrews `version`-DSL unterstützt kommagetrennte Mehrteil-Versionen über `version.csv[N]` - passend zu Feedivos `MARKETING_VERSION-BUILD_NUMBER`-Tag-Schema).

- [ ] **Step 3: README ergänzen**

```markdown
# homebrew-feedivo

Homebrew-Tap für [Feedivo](https://github.com/martinfelder/feedivo-mac), einen nativen macOS RSS Reader.

## Installation

\`\`\`bash
brew tap martinfelder/feedivo
brew install --cask feedivo
\`\`\`

## Aktualisieren

\`\`\`bash
brew upgrade --cask feedivo
\`\`\`

Diese Cask-Formel wird automatisch von `create_github_release.sh` im Hauptrepo
(`martinfelder/feedivo-mac`) bei jedem neuen Release aktualisiert.
```

- [ ] **Step 4: Committen und pushen (mit Bestätigung)**

```bash
cd ~/Developer/homebrew-feedivo
git add Casks/feedivo.rb README.md
git commit -m "feat: initiale Feedivo-Cask-Formel"
git push -u origin main
```

- [ ] **Step 5: Lokal testen**

```bash
brew tap martinfelder/feedivo
brew install --cask feedivo
brew audit --cask feedivo
```

Erwartet: Installation erfolgreich, `brew audit` meldet keine harten Fehler (Warnungen zu fehlender Notarisierung sind erwartet und akzeptiert, siehe Spec Abschnitt 5).

---

## Task 13: create_github_release.sh um Tap-Repo-Update erweitern

**Files:**
- Modify: `scripts/create_github_release.sh`

**Interfaces:**
- Consumes: das in Task 12 angelegte Tap-Repo unter `~/Developer/homebrew-feedivo` (lokaler Klon).

- [ ] **Step 1: Tap-Repo-Update-Block direkt nach dem Appcast-Push-Block (Task 11) ergänzen**

```bash
TAP_REPO_DIR="$HOME/Developer/homebrew-feedivo"
if [ ! -d "$TAP_REPO_DIR" ]; then
  echo "Klone Tap-Repo nach $TAP_REPO_DIR..."
  git clone https://github.com/martinfelder/homebrew-feedivo.git "$TAP_REPO_DIR"
fi

echo "Aktualisiere Homebrew-Cask-Formel..."
cd "$TAP_REPO_DIR"
git pull --ff-only
NEW_SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
python3 - "$TAP_REPO_DIR/Casks/feedivo.rb" "$MARKETING_VERSION,$BUILD_NUMBER" "$NEW_SHA256" <<'PYEOF'
import re
import sys
path, version, sha256 = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()
content = re.sub(r'version "[^"]*"', f'version "{version}"', content, count=1)
content = re.sub(r'sha256 "[^"]*"', f'sha256 "{sha256}"', content, count=1)
with open(path, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF
git add Casks/feedivo.rb
git commit -m "feat: Feedivo ${VERSION_LABEL}"

read -r -p "Homebrew-Cask-Update nach martinfelder/homebrew-feedivo pushen? [y/N] " TAP_PUSH_CONFIRM
if [[ "$TAP_PUSH_CONFIRM" =~ ^[Yy]$ ]]; then
  git push
  echo "create_github_release.sh: Homebrew-Cask-Formel gepusht."
else
  echo "create_github_release.sh: Cask-Commit lokal in $TAP_REPO_DIR, NICHT gepusht (manuell nachholen: cd $TAP_REPO_DIR && git push)."
fi
cd "$REPO_ROOT"
```

- [ ] **Step 2: Syntax-Check**

```bash
cd /Users/martinfelder/Developer/FeedivoMac
bash -n scripts/create_github_release.sh
```

Erwartet: keine Ausgabe.

- [ ] **Step 3: Commit**

```bash
git add scripts/create_github_release.sh
git commit -m "feat: create_github_release.sh aktualisiert Homebrew-Cask-Formel im Tap-Repo"
```

---

## Task 14: Vollständige Regressionsprüfung + CLAUDE.md-Dokumentation

**Files:**
- Modify: `CLAUDE.md` (Tech-Stack-Tabelle, neuer ADR-Eintrag, neuer Gotcha-Eintrag zur App-Sandbox-Quarantäne-Root-Cause, „Aktuell in Arbeit"-Eintrag)

**Interfaces:** keine

- [ ] **Step 1: Vollständigen Build (Debug + Release) und gezielten Testlauf über alle in diesem Plan berührten Suiten**

```bash
cd /Users/martinfelder/Developer/FeedivoMac
xcodebuild -scheme Feedivo -configuration Debug build
xcodebuild -scheme Feedivo -configuration Release build
xcodebuild test -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/HomebrewInstallationDetectorTests \
  -only-testing:FeedivoTests/SparkleReleaseInfoTests \
  -only-testing:FeedivoTests/UpdateReleaseNoteCategorizerTests \
  -parallel-testing-enabled NO 2>&1 | tail -40
```

Erwartet: beide Builds `BUILD SUCCEEDED`, alle Tests grün.

- [ ] **Step 2: Grep-Kontrolle, dass keine toten Referenzen mehr existieren**

```bash
grep -rn "UpdateInstaller\|GitHubReleaseCheckService\|\bUpdateChecker\b" Feedivo FeedivoTests --include="*.swift"
```

Erwartet: keine Treffer.

- [ ] **Step 3: CLAUDE.md aktualisieren**

Füge einen neuen Gotcha-Eintrag unter „Bekannte Gotchas & Fallstricke" hinzu (Root-Cause-Zusammenfassung: App Sandbox verbietet `xattr -dr com.apple.quarantine` kategorisch, egal ob per Subprozess oder `URLResourceValues.quarantineProperties` — reproduziert per eigenem, identisch signiertem Sandbox-Testprogramm am 2026-07-31), einen neuen ADR-Eintrag (Sparkle statt Eigenbau-Installer, Begründung: App-Sandbox-Inkompatibilität des Eigenbaus) und aktualisiere die Tech-Stack-Tabelle um eine neue Zeile „App-Update" mit Sparkle 2.x + Homebrew Cask. Aktualisiere „Aktuell in Arbeit" mit dem Status dieses Plans (welche Tasks automatisiert abgeschlossen wurden, welche - Task 2 Schlüsselgenerierung, Task 12 Repo-Anlage, echte Live-Verifikation eines Sparkle-Updates - manuell ausstehend bleiben).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: CLAUDE.md um Sparkle-Update/Homebrew-Vertrieb ergänzt"
```
