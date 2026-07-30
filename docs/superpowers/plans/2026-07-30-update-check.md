# Update-Prüfung über GitHub Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feedivo kann über das App-Menü und einen neuen Settings-Tab „Über" prüfen, ob
eine neuere Version auf GitHub veröffentlicht wurde, zeigt die Release-Notes als
gerenderten Mini-Reader an und bietet zusätzlich einen abschaltbaren, stillen
Update-Check beim App-Start mit dezentem Badge-Hinweis.

**Architektur:** Vier kleine, pure/isoliert testbare Bausteine (`GitHubRelease`-Modell,
`UpdateVersionComparator`, `GitHubReleaseCheckService`, `UpdateChecker`) plus zwei
unabhängige UI-Aufrufstellen (App-Menü in `FeedivoApp.swift`, neuer Settings-Tab
„Über"), die beide denselben stateless `UpdateChecker` direkt aufrufen und ihre
Sheet-/Alert-Präsentation **jeweils lokal** verwalten — siehe Abweichung von der Spec
unten.

**Tech Stack:** Swift 6, SwiftUI, `URLSession` (unauthentifizierte GitHub-REST-API,
Repo ist public), Swift Testing (`import Testing`, kein XCTest), Wiederverwendung von
`ReaderContentRenderer`/`ReaderInlineRun` für die Release-Notes-Darstellung.

## Global Constraints

- Repo `martinfelder/feedivo-mac` ist **public** (verifiziert per `gh repo view`) — GitHub-API
  ohne Token/Authentifizierung abfragen.
- GitHub-Endpoint: `GET https://api.github.com/repos/martinfelder/feedivo-mac/releases`
  (die **Liste**, NICHT `/releases/latest` — `create_github_release.sh` markiert JEDES
  Release als `--prerelease`, `/releases/latest` ignoriert Pre-Releases).
- Header `Accept: application/vnd.github.html+json` setzen — liefert `body_html`
  (server-seitig aus Markdown gerendertes HTML) zusätzlich zum rohen `body`-Feld.
- Tag-Format: `v{MARKETING_VERSION}-{BUILD_NUMBER}` (exakt wie in
  `scripts/create_github_release.sh`, Zeile `TAG="v${MARKETING_VERSION}-${BUILD_NUMBER}"`).
- Kein automatischer Download/Installer — nur „Auf GitHub öffnen" (`NSWorkspace.shared.open`).
- Kein Token, kein Throttling zwischen Checks (YAGNI für Solo-Nutzer).
- Kommentare im Code auf Deutsch (Projektkonvention).
- Direkt auf `main` committen, kein Feature-Branch/Worktree (Nutzerpräferenz).
- Tests: Swift Testing (`@Test`, `#expect`), keine neue URLSession-Mocking-Infrastruktur
  einführen — nur reine Decoding-/Vergleichs-Logik wird isoliert getestet (siehe Spec-
  Selbstreview).
- `xcodebuild build`/`test`-Läufe: `-scheme Feedivo -destination 'platform=macOS'`,
  bei Tests zusätzlich `-only-testing:FeedivoTests/<SuiteName> -parallel-testing-enabled NO`
  (bekannter Parallel-Testing-Gotcha).
- Neue `L10n.swift`-Keys, die nicht 1:1 einem direkten String-Literal entsprechen, werden
  vom automatischen xcstrings-Stub-Mechanismus NICHT erkannt — nach jedem neuen Key per
  `grep -c "<punkt.key>" Feedivo/Resources/Localizable.xcstrings` prüfen (muss > 0 sein)
  und den Katalogeintrag manuell als reine Text-Segment-Einfügung nach dem stabilen Anker
  `"strings" : {` ergänzen (NIEMALS die gesamte Datei per `json.load`/`json.dump`
  roundtripen — siehe CLAUDE.md-Gotcha).

**Abweichung von der genehmigten Spec (Architektur-Vereinfachung, kein
Verhaltens-/Scope-Wechsel):** Die Spec sah einen einzelnen `@Observable
UpdateCheckCoordinator` vor, der von beiden UI-Stellen (App-Menü, Settings-Tab) geteilt
wird. Bei der Datei-Analyse stellte sich heraus: App-Menü (`.commands`-Block in
`FeedivoApp.swift`) und Settings-Tab (`Settings { }`-Scene) sind zwei UNABHÄNGIGE
SwiftUI-Szenen/Fenster — ein einzelnes gemeinsames Observable-Objekt mit geteiltem
`latestRelease`/`showsUpToDateAlert`-Zustand hätte riskiert, dass ein in EINEM Fenster
ausgelöster Check das Sheet/Alert in BEIDEN offenen Fenstern gleichzeitig zeigt (falls
beide Fenster offen sind). Stattdessen: ein **stateless** `UpdateChecker` (reine
async-Funktion, kein geteilter UI-Zustand) wird von BEIDEN Stellen unabhängig
aufgerufen, jede Stelle hält ihre eigene lokale `@State`-Präsentation. Einziger geteilter
Zustand bleibt der `@AppStorage`-Bool `hasUnseenUpdateKey` für das Menü-Badge — exakt wie
in der Spec vorgesehen. Verhalten für den Nutzer ist identisch zum genehmigten Design,
nur die interne Umsetzung ist robuster/einfacher.

---

### Task 1: Datenmodell + Versionsvergleich

**Files:**
- Create: `Feedivo/Services/GitHubRelease.swift`
- Create: `Feedivo/Services/UpdateVersionComparator.swift`
- Create: `Feedivo/Services/AppVersionInfo.swift`
- Test: `FeedivoTests/Services/UpdateVersionComparatorTests.swift`

**Interfaces:**
- Produces: `struct GitHubRelease: Equatable, Sendable, Decodable, Identifiable` mit
  `tagName: String`, `name: String?`, `htmlURL: URL`, `bodyHTML: String?`,
  `publishedAt: Date?`, `id: String { tagName }`.
- Produces: `enum UpdateCheckResult: Equatable { case upToDate, updateAvailable(GitHubRelease), unknown }`
- Produces: `enum UpdateVersionComparator` mit
  `static func compare(latestRelease: GitHubRelease, currentMarketingVersion: String, currentBuildNumber: Int) -> UpdateCheckResult`
  und `static func parseTag(_ tagName: String) -> (marketingVersion: String, buildNumber: Int)?`
- Produces: `enum AppVersionInfo` mit `static var marketingVersion: String`,
  `static var buildNumber: Int` (liest `Bundle.main.infoDictionary`).

- [ ] **Step 1: `GitHubRelease`-Modell anlegen**

```swift
// Feedivo/Services/GitHubRelease.swift
import Foundation

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

    var id: String { tagName }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case bodyHTML = "body_html"
        case publishedAt = "published_at"
    }
}
```

- [ ] **Step 2: Schreibe den fehlschlagenden Test für `parseTag`**

```swift
// FeedivoTests/Services/UpdateVersionComparatorTests.swift
import Testing
@testable import Feedivo

struct UpdateVersionComparatorTests {

    @Test func parseTagLiestMarketingVersionUndBuildNummer() {
        let parsed = UpdateVersionComparator.parseTag("v1.0-11")

        #expect(parsed?.marketingVersion == "1.0")
        #expect(parsed?.buildNumber == 11)
    }

    @Test func parseTagLiefertNilBeiFehlendemVPraefix() {
        #expect(UpdateVersionComparator.parseTag("1.0-11") == nil)
    }

    @Test func parseTagLiefertNilBeiNichtNumerischerBuildNummer() {
        #expect(UpdateVersionComparator.parseTag("v1.0-elf") == nil)
    }

    @Test func parseTagLiefertNilOhneBindestrich() {
        #expect(UpdateVersionComparator.parseTag("v1.0") == nil)
    }
}
```

- [ ] **Step 3: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/UpdateVersionComparatorTests -parallel-testing-enabled NO`
Expected: FAIL — "Cannot find 'UpdateVersionComparator' in scope"

- [ ] **Step 4: `UpdateVersionComparator` implementieren**

```swift
// Feedivo/Services/UpdateVersionComparator.swift
import Foundation

/// Ergebnis eines Versionsvergleichs gegen ein GitHub-Release.
enum UpdateCheckResult: Equatable {
    case upToDate
    case updateAvailable(GitHubRelease)
    /// Tag entspricht nicht dem erwarteten Schema `v{Version}-{Build}` — kein
    /// verlässlicher Vergleich möglich, wird von Aufrufern konservativ wie
    /// "kein Update" behandelt (keine Falsch-Meldung).
    case unknown
}

/// Vergleicht ein GitHub-Release-Tag (Format `v{MARKETING_VERSION}-{BUILD_NUMBER}`,
/// siehe scripts/create_github_release.sh) gegen die laufende App-Version.
enum UpdateVersionComparator {
    static func compare(
        latestRelease: GitHubRelease,
        currentMarketingVersion: String,
        currentBuildNumber: Int
    ) -> UpdateCheckResult {
        guard let parsed = parseTag(latestRelease.tagName) else {
            return .unknown
        }

        let latestComponents = versionComponents(parsed.marketingVersion)
        let currentComponents = versionComponents(currentMarketingVersion)

        if isVersion(latestComponents, greaterThan: currentComponents) {
            return .updateAvailable(latestRelease)
        }
        if isVersion(currentComponents, greaterThan: latestComponents) {
            return .upToDate
        }
        // Gleiche Marketing-Version -> Build-Nummer entscheidet als Tiebreaker.
        return parsed.buildNumber > currentBuildNumber
            ? .updateAvailable(latestRelease)
            : .upToDate
    }

    /// Zerlegt z. B. "v1.0-11" in ("1.0", 11). Liefert nil bei jeder Abweichung
    /// vom erwarteten Schema (fehlendes "v", fehlender Bindestrich, nicht-
    /// numerische Build-Nummer, leere Marketing-Version).
    static func parseTag(_ tagName: String) -> (marketingVersion: String, buildNumber: Int)? {
        guard tagName.hasPrefix("v") else { return nil }
        let withoutPrefix = tagName.dropFirst()

        guard let lastDashIndex = withoutPrefix.lastIndex(of: "-") else { return nil }

        let marketingVersion = String(withoutPrefix[withoutPrefix.startIndex..<lastDashIndex])
        let buildNumberString = String(withoutPrefix[withoutPrefix.index(after: lastDashIndex)...])

        guard !marketingVersion.isEmpty, let buildNumber = Int(buildNumberString) else {
            return nil
        }

        return (marketingVersion, buildNumber)
    }

    private static func versionComponents(_ version: String) -> [Int] {
        version.split(separator: ".").compactMap { Int($0) }
    }

    /// Komponentenweiser Vergleich, fehlende Komponenten zählen als 0
    /// (z. B. "1.0" vs. "1.0.1").
    private static func isVersion(_ lhs: [Int], greaterThan rhs: [Int]) -> Bool {
        let maxCount = max(lhs.count, rhs.count)
        for index in 0..<maxCount {
            let lhsComponent = index < lhs.count ? lhs[index] : 0
            let rhsComponent = index < rhs.count ? rhs[index] : 0
            if lhsComponent != rhsComponent {
                return lhsComponent > rhsComponent
            }
        }
        return false
    }
}
```

- [ ] **Step 5: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/UpdateVersionComparatorTests -parallel-testing-enabled NO`
Expected: PASS (4/4 Tests grün)

- [ ] **Step 6: Weitere Tests für `compare(...)` ergänzen (TDD, Rot→Grün pro Fall)**

Ergänze in derselben Testdatei (jeweils erst hinzufügen, `xcodebuild test` laufen lassen,
verifizieren dass alle bereits grün sind — `compare` ist bereits vollständig implementiert,
diese Tests dokumentieren/verifizieren also das existierende Verhalten):

```swift
    private func makeRelease(tag: String) -> GitHubRelease {
        GitHubRelease(
            tagName: tag,
            name: "Test Release",
            htmlURL: URL(string: "https://github.com/martinfelder/feedivo-mac/releases/tag/\(tag)")!,
            bodyHTML: "<p>Notes</p>",
            publishedAt: nil
        )
    }

    @Test func compareErkenntNeuerenBuildBeiGleicherMarketingVersion() {
        let result = UpdateVersionComparator.compare(
            latestRelease: makeRelease(tag: "v1.0-12"),
            currentMarketingVersion: "1.0",
            currentBuildNumber: 11
        )

        #expect(result == .updateAvailable(makeRelease(tag: "v1.0-12")))
    }

    @Test func compareErkenntGleichenBuildAlsAktuell() {
        let result = UpdateVersionComparator.compare(
            latestRelease: makeRelease(tag: "v1.0-11"),
            currentMarketingVersion: "1.0",
            currentBuildNumber: 11
        )

        #expect(result == .upToDate)
    }

    @Test func compareErkenntAelterenBuildAlsAktuell() {
        let result = UpdateVersionComparator.compare(
            latestRelease: makeRelease(tag: "v1.0-9"),
            currentMarketingVersion: "1.0",
            currentBuildNumber: 11
        )

        #expect(result == .upToDate)
    }

    @Test func compareErkenntMarketingVersionSprungUnabhaengigVomBuild() {
        let result = UpdateVersionComparator.compare(
            latestRelease: makeRelease(tag: "v1.1-1"),
            currentMarketingVersion: "1.0",
            currentBuildNumber: 999
        )

        #expect(result == .updateAvailable(makeRelease(tag: "v1.1-1")))
    }

    @Test func compareLiefertUnknownBeiKaputtemTag() {
        let result = UpdateVersionComparator.compare(
            latestRelease: makeRelease(tag: "nightly-build"),
            currentMarketingVersion: "1.0",
            currentBuildNumber: 11
        )

        #expect(result == .unknown)
    }
```

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/UpdateVersionComparatorTests -parallel-testing-enabled NO`
Expected: PASS (9/9 Tests grün)

- [ ] **Step 7: `AppVersionInfo` implementieren (kein eigener Test nötig — liest nur
  `Bundle.main`, in Tests ohnehin nicht sinnvoll gegen einen anderen Wert zu prüfen)**

```swift
// Feedivo/Services/AppVersionInfo.swift
import Foundation

/// Liest die aktuell laufende App-Version aus dem Bundle — dieselben Felder,
/// die `scripts/create_github_release.sh` zum Bauen des Release-Tags
/// (`v{MARKETING_VERSION}-{BUILD_NUMBER}`) verwendet.
enum AppVersionInfo {
    static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var buildNumber: Int {
        let raw = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return Int(raw) ?? 0
    }
}
```

- [ ] **Step 8: Vollen Build verifizieren**

Run: `xcodebuild -scheme Feedivo -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Services/GitHubRelease.swift Feedivo/Services/UpdateVersionComparator.swift Feedivo/Services/AppVersionInfo.swift FeedivoTests/Services/UpdateVersionComparatorTests.swift
git commit -m "Feat: GitHubRelease-Modell + Versionsvergleich für Update-Prüfung (Task 1)"
```

---

### Task 2: GitHub-Release-Fetching-Service

**Files:**
- Create: `Feedivo/Services/GitHubReleaseCheckService.swift`
- Test: `FeedivoTests/Services/GitHubReleaseCheckServiceTests.swift`

**Interfaces:**
- Consumes: `GitHubRelease` (Task 1, `Decodable`)
- Produces: `protocol GitHubReleaseFetching: Sendable { func fetchReleases() async throws -> [GitHubRelease] }`
- Produces: `enum GitHubReleaseCheckError: Error, LocalizedError, Equatable { case invalidResponse, httpError(statusCode: Int), decodingFailed }`
- Produces: `struct GitHubReleaseCheckService: GitHubReleaseFetching` mit
  `init(repositoryPath: String = "martinfelder/feedivo-mac", urlSession: URLSession = .shared)`
  und `static func decodeReleases(from data: Data) throws -> [GitHubRelease]` (intern
  testbar, kein Netzwerk-Mocking nötig).

- [ ] **Step 1: Schreibe den fehlschlagenden Test für `decodeReleases(from:)`**

```swift
// FeedivoTests/Services/GitHubReleaseCheckServiceTests.swift
import Testing
import Foundation
@testable import Feedivo

struct GitHubReleaseCheckServiceTests {

    private static let sampleReleaseListJSON = """
    [
      {
        "html_url": "https://github.com/martinfelder/feedivo-mac/releases/tag/v1.0-11",
        "tag_name": "v1.0-11",
        "name": "Feedivo 1.0 (11)",
        "draft": false,
        "prerelease": true,
        "published_at": "2026-07-30T18:21:00Z",
        "body": "- Feat: Sidebar-Header in Blau",
        "body_html": "<ul>\\n<li>Feat: Sidebar-Header in Blau</li>\\n</ul>"
      },
      {
        "html_url": "https://github.com/martinfelder/feedivo-mac/releases/tag/v1.0-10",
        "tag_name": "v1.0-10",
        "name": "Feedivo 1.0 (10)",
        "draft": false,
        "prerelease": true,
        "published_at": "2026-07-20T09:00:00Z",
        "body": "- Chore: Version 1.0 (10)",
        "body_html": "<ul>\\n<li>Chore: Version 1.0 (10)</li>\\n</ul>"
      }
    ]
    """.data(using: .utf8)!

    @Test func decodeReleasesLiestTagNameHTMLUndBodyHTML() throws {
        let releases = try GitHubReleaseCheckService.decodeReleases(from: Self.sampleReleaseListJSON)

        #expect(releases.count == 2)
        #expect(releases[0].tagName == "v1.0-11")
        #expect(releases[0].name == "Feedivo 1.0 (11)")
        #expect(releases[0].htmlURL.absoluteString == "https://github.com/martinfelder/feedivo-mac/releases/tag/v1.0-11")
        #expect(releases[0].bodyHTML == "<ul>\n<li>Feat: Sidebar-Header in Blau</li>\n</ul>")
        #expect(releases[0].publishedAt != nil)
    }

    @Test func decodeReleasesLiefertLeeresArrayBeiLeererListe() throws {
        let releases = try GitHubReleaseCheckService.decodeReleases(from: "[]".data(using: .utf8)!)

        #expect(releases.isEmpty)
    }

    @Test func decodeReleasesWirftDecodingFailedBeiKaputtemJSON() {
        let garbage = "not valid json".data(using: .utf8)!

        #expect(throws: GitHubReleaseCheckError.decodingFailed) {
            try GitHubReleaseCheckService.decodeReleases(from: garbage)
        }
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/GitHubReleaseCheckServiceTests -parallel-testing-enabled NO`
Expected: FAIL — "Cannot find 'GitHubReleaseCheckService' in scope"

- [ ] **Step 3: `GitHubReleaseCheckService` implementieren**

```swift
// Feedivo/Services/GitHubReleaseCheckService.swift
import Foundation

/// Abstraktion über das tatsächliche Netzwerk-Fetching, damit Aufrufer
/// (UpdateChecker) austauschbar/testbar bleiben, ohne eine eigene
/// URLSession-Mocking-Infrastruktur einführen zu müssen (das Projekt hat
/// aktuell keine — FeedService/FaviconService rufen URLSession.shared direkt
/// auf und testen nur ihre reinen Parsing-Funktionen, nicht den Netzwerk-Call
/// selbst; dasselbe Muster wird hier übernommen).
protocol GitHubReleaseFetching: Sendable {
    func fetchReleases() async throws -> [GitHubRelease]
}

enum GitHubReleaseCheckError: Error, LocalizedError, Equatable {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "updateCheck.error.invalidResponse")
        case .httpError(let statusCode):
            String.localizedStringWithFormat(String(localized: "updateCheck.error.httpError"), statusCode)
        case .decodingFailed:
            String(localized: "updateCheck.error.decodingFailed")
        }
    }
}

struct GitHubReleaseCheckService: GitHubReleaseFetching {
    private let repositoryPath: String
    private let urlSession: URLSession

    init(repositoryPath: String = "martinfelder/feedivo-mac", urlSession: URLSession = .shared) {
        self.repositoryPath = repositoryPath
        self.urlSession = urlSession
    }

    func fetchReleases() async throws -> [GitHubRelease] {
        guard let url = URL(string: "https://api.github.com/repos/\(repositoryPath)/releases") else {
            throw GitHubReleaseCheckError.invalidResponse
        }

        var request = URLRequest(url: url)
        // Liefert body_html zusätzlich zum rohen body-Feld - GitHub rendert das
        // Markdown server-seitig, wir brauchen dafür keinen eigenen Parser.
        request.setValue("application/vnd.github.html+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubReleaseCheckError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw GitHubReleaseCheckError.httpError(statusCode: httpResponse.statusCode)
        }

        return try Self.decodeReleases(from: data)
    }

    /// Reine Decoding-Logik, getrennt vom Netzwerk-Aufruf - dadurch per
    /// Fixture-JSON testbar, ohne URLSession zu mocken.
    static func decodeReleases(from data: Data) throws -> [GitHubRelease] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([GitHubRelease].self, from: data)
        } catch {
            throw GitHubReleaseCheckError.decodingFailed
        }
    }
}
```

- [ ] **Step 4: Keine neuen `L10n.swift`-Konstanten für diese drei Fehlertexte nötig**

`GitHubReleaseCheckError.errorDescription` (Step 3) ruft `String(localized:)` bereits
direkt mit dem fertigen Punkt-Key auf (analog `FeedStoreError`) — eine zusätzliche
`L10n`-Konstante wäre nie verwendeter toter Code (YAGNI). Trotzdem müssen die drei
Katalog-Einträge selbst existieren, damit `String(localized:)` etwas findet — siehe
Step 5.

- [ ] **Step 5: Katalogeinträge in `Localizable.xcstrings` ergänzen (Text-Segment-Einfügung,
  NICHT `json.load`/`json.dump`)**

Füge direkt nach der Zeile `"strings" : {` (ganz am Dateianfang) folgenden Block ein:

```json
    "updateCheck.error.invalidResponse" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ungültige Antwort vom Server."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Invalid response from the server."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Réponse invalide du serveur."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Risposta non valida dal server."
          }
        }
      }
    },
    "updateCheck.error.httpError" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Der Server antwortete mit Fehlercode %d."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "The server responded with error code %d."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Le serveur a répondu avec le code d'erreur %d."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Il server ha risposto con il codice di errore %d."
          }
        }
      }
    },
    "updateCheck.error.decodingFailed" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Die Antwort konnte nicht gelesen werden."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Couldn't read the response."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Impossible de lire la réponse."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Impossibile leggere la risposta."
          }
        }
      }
    },
```

Danach verifizieren:
```bash
grep -c "updateCheck.error.invalidResponse" Feedivo/Resources/Localizable.xcstrings
grep -c "updateCheck.error.httpError" Feedivo/Resources/Localizable.xcstrings
grep -c "updateCheck.error.decodingFailed" Feedivo/Resources/Localizable.xcstrings
git diff --stat Feedivo/Resources/Localizable.xcstrings
```
Expected: jedes `grep -c` > 0, `git diff --stat` zeigt NUR Insertions, keine/kaum Deletions.

- [ ] **Step 6: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/GitHubReleaseCheckServiceTests -parallel-testing-enabled NO`
Expected: PASS (3/3 Tests grün)

- [ ] **Step 7: Vollen Build verifizieren**

Run: `xcodebuild -scheme Feedivo -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Services/GitHubReleaseCheckService.swift FeedivoTests/Services/GitHubReleaseCheckServiceTests.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feat: GitHubReleaseCheckService für Update-Prüfung (Task 2)"
```

---

### Task 3: Stateless UpdateChecker-Orchestrator + Settings-Keys

**Files:**
- Create: `Feedivo/Services/UpdateChecker.swift`
- Create: `Feedivo/Services/UpdateCheckSettings.swift`
- Test: `FeedivoTests/Services/UpdateCheckerTests.swift`

**Interfaces:**
- Consumes: `GitHubReleaseFetching` (Task 2), `UpdateVersionComparator.compare` (Task 1),
  `GitHubRelease` (Task 1)
- Produces: `enum UpdateCheckOutcome: Equatable { case updateAvailable(GitHubRelease), upToDate, failed(String) }`
- Produces: `struct UpdateChecker` mit
  `init(releaseFetching: GitHubReleaseFetching = GitHubReleaseCheckService())` und
  `func check(currentMarketingVersion: String, currentBuildNumber: Int) async -> UpdateCheckOutcome`
- Produces: `enum UpdateCheckSettings` mit `isAutomaticCheckEnabledKey`,
  `defaultIsAutomaticCheckEnabled`, `hasUnseenUpdateKey`, `defaultHasUnseenUpdate`

- [ ] **Step 1: Schreibe den fehlschlagenden Test mit einem Fake-Fetcher**

```swift
// FeedivoTests/Services/UpdateCheckerTests.swift
import Testing
@testable import Feedivo

private struct FakeReleaseFetcher: GitHubReleaseFetching {
    let releases: [GitHubRelease]
    let error: Error?

    func fetchReleases() async throws -> [GitHubRelease] {
        if let error {
            throw error
        }
        return releases
    }
}

struct UpdateCheckerTests {

    private func makeRelease(tag: String) -> GitHubRelease {
        GitHubRelease(
            tagName: tag,
            name: "Test",
            htmlURL: URL(string: "https://github.com/martinfelder/feedivo-mac/releases/tag/\(tag)")!,
            bodyHTML: "<p>Notes</p>",
            publishedAt: nil
        )
    }

    @Test func checkLiefertUpdateAvailableBeiNeuerReleaseListe() async {
        let fetcher = FakeReleaseFetcher(releases: [makeRelease(tag: "v1.0-12")], error: nil)
        let checker = UpdateChecker(releaseFetching: fetcher)

        let outcome = await checker.check(currentMarketingVersion: "1.0", currentBuildNumber: 11)

        #expect(outcome == .updateAvailable(makeRelease(tag: "v1.0-12")))
    }

    @Test func checkLiefertUpToDateBeiGleicherVersion() async {
        let fetcher = FakeReleaseFetcher(releases: [makeRelease(tag: "v1.0-11")], error: nil)
        let checker = UpdateChecker(releaseFetching: fetcher)

        let outcome = await checker.check(currentMarketingVersion: "1.0", currentBuildNumber: 11)

        #expect(outcome == .upToDate)
    }

    @Test func checkLiefertUpToDateBeiLeererReleaseListe() async {
        let fetcher = FakeReleaseFetcher(releases: [], error: nil)
        let checker = UpdateChecker(releaseFetching: fetcher)

        let outcome = await checker.check(currentMarketingVersion: "1.0", currentBuildNumber: 11)

        #expect(outcome == .upToDate)
    }

    @Test func checkLiefertUpToDateBeiUnknownVergleichsergebnis() async {
        let fetcher = FakeReleaseFetcher(releases: [makeRelease(tag: "nightly")], error: nil)
        let checker = UpdateChecker(releaseFetching: fetcher)

        let outcome = await checker.check(currentMarketingVersion: "1.0", currentBuildNumber: 11)

        #expect(outcome == .upToDate)
    }

    @Test func checkLiefertFailedBeiFehlerImFetcher() async {
        let fetcher = FakeReleaseFetcher(releases: [], error: GitHubReleaseCheckError.httpError(statusCode: 403))
        let checker = UpdateChecker(releaseFetching: fetcher)

        let outcome = await checker.check(currentMarketingVersion: "1.0", currentBuildNumber: 11)

        guard case .failed(let message) = outcome else {
            Issue.record("Erwartete .failed, bekam \(outcome)")
            return
        }
        #expect(!message.isEmpty)
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/UpdateCheckerTests -parallel-testing-enabled NO`
Expected: FAIL — "Cannot find 'UpdateChecker' in scope"

- [ ] **Step 3: `UpdateChecker` implementieren**

```swift
// Feedivo/Services/UpdateChecker.swift
import Foundation

/// Ergebnis eines vollständigen Update-Checks (Netzwerk + Versionsvergleich),
/// als flaches Enum statt als throws — Aufrufer (App-Menü, Settings-Tab)
/// wollen für JEDEN Fall (Update da / aktuell / Fehler) eine sichtbare
/// Reaktion zeigen, kein einfaches "still fehlgeschlagen" per throw.
enum UpdateCheckOutcome: Equatable {
    case updateAvailable(GitHubRelease)
    case upToDate
    case failed(String)
}

/// Stateless - hält keinen UI-Zustand, kann von mehreren unabhängigen
/// Aufrufstellen (App-Menü, Settings-Tab "Über") gleichzeitig verwendet
/// werden, ohne dass sich deren Präsentationszustand überschneidet.
struct UpdateChecker {
    private let releaseFetching: GitHubReleaseFetching

    init(releaseFetching: GitHubReleaseFetching = GitHubReleaseCheckService()) {
        self.releaseFetching = releaseFetching
    }

    func check(currentMarketingVersion: String, currentBuildNumber: Int) async -> UpdateCheckOutcome {
        do {
            let releases = try await releaseFetching.fetchReleases()
            guard let latest = releases.first else {
                return .upToDate
            }

            switch UpdateVersionComparator.compare(
                latestRelease: latest,
                currentMarketingVersion: currentMarketingVersion,
                currentBuildNumber: currentBuildNumber
            ) {
            case .updateAvailable(let release):
                return .updateAvailable(release)
            case .upToDate, .unknown:
                return .upToDate
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/UpdateCheckerTests -parallel-testing-enabled NO`
Expected: PASS (5/5 Tests grün)

- [ ] **Step 5: `UpdateCheckSettings` anlegen (kein eigener Test — reine Konstanten,
  analog `BackgroundRefreshSettings`)**

```swift
// Feedivo/Services/UpdateCheckSettings.swift
import Foundation

/// AppStorage-Keys für den Update-Check, analog BackgroundRefreshSettings/
/// SpotlightIndexingSettings.
enum UpdateCheckSettings {
    static let isAutomaticCheckEnabledKey = "updateCheckIsAutomaticCheckEnabled"
    static let defaultIsAutomaticCheckEnabled = true

    /// Wird von einem stillen Start-Check auf true gesetzt, sobald eine
    /// neuere Version gefunden wurde - zeigt einen dezenten Punkt am
    /// Menüpunkt "Nach Updates suchen". Jeder manuelle Check (Menü ODER
    /// Settings-Tab) setzt das sofort wieder auf false zurück, sobald der
    /// Nutzer selbst hinschaut.
    static let hasUnseenUpdateKey = "updateCheckHasUnseenUpdate"
    static let defaultHasUnseenUpdate = false
}
```

- [ ] **Step 6: Vollen Build verifizieren**

Run: `xcodebuild -scheme Feedivo -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/UpdateChecker.swift Feedivo/Services/UpdateCheckSettings.swift FeedivoTests/Services/UpdateCheckerTests.swift
git commit -m "Feat: Stateless UpdateChecker-Orchestrator + UpdateCheckSettings (Task 3)"
```

---

### Task 4: `UpdateAvailableSheet` (Mini-Reader für Release-Notes)

**Files:**
- Create: `Feedivo/Views/Settings/UpdateAvailableSheet.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `GitHubRelease` (Task 1, `Identifiable` über `tagName` — direkt für
  `.sheet(item:)` nutzbar), `ReaderContentRenderer.blocks(summary:content:fallbackImageURL:)`,
  `ReaderContentBlockEntry.entries(from:)`, `[ReaderInlineRun].attributedString(colorScheme:)`
  (alle bereits bestehend in `Feedivo/Views/Reader/ReaderContentRenderer.swift` /
  `ReaderInlineRun+AttributedString.swift`)
- Produces: `struct UpdateAvailableSheet: View` mit
  `init(release: GitHubRelease, onOpenOnGitHub: @escaping () -> Void, onDismiss: @escaping () -> Void)`
  — wird von Task 5 (FeedivoApp.swift) UND Task 6 (AboutSettingsView) verwendet.

Kein Unit-Test für diese Task (reine SwiftUI-View, kein computer-use für native
macOS-Apps in dieser Umgebung verfügbar — manuelle Live-Verifikation siehe Task 7).

- [ ] **Step 1: Neue L10n-Keys ergänzen**

Füge in `Feedivo/Resources/L10n.swift` ans Ende der Datei an:

```swift
    static func updateCheckAvailableTitle(tagName: String) -> String {
        String.localizedStringWithFormat(String(localized: "updateCheck.available.title"), tagName)
    }
    static let updateCheckOpenOnGitHubButton = LocalizedStringKey("updateCheck.openOnGitHub.button")
    static let updateCheckDismissButton = LocalizedStringKey("updateCheck.dismiss.button")
```

- [ ] **Step 2: Katalogeinträge ergänzen (Text-Segment-Einfügung nach `"strings" : {`)**

```json
    "updateCheck.available.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Neue Version verfügbar: %@"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "New version available: %@"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nouvelle version disponible : %@"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nuova versione disponibile: %@"
          }
        }
      }
    },
    "updateCheck.openOnGitHub.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Auf GitHub öffnen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Open on GitHub"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ouvrir sur GitHub"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Apri su GitHub"
          }
        }
      }
    },
    "updateCheck.dismiss.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Später"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Later"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Plus tard"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Più tardi"
          }
        }
      }
    },
```

Verifizieren:
```bash
grep -c "updateCheck.available.title" Feedivo/Resources/Localizable.xcstrings
grep -c "updateCheck.openOnGitHub.button" Feedivo/Resources/Localizable.xcstrings
grep -c "updateCheck.dismiss.button" Feedivo/Resources/Localizable.xcstrings
git diff --stat Feedivo/Resources/Localizable.xcstrings
```
Expected: jedes `grep -c` > 0, nur Insertions im Diff.

- [ ] **Step 3: `UpdateAvailableSheet` implementieren**

```swift
// Feedivo/Views/Settings/UpdateAvailableSheet.swift
import SwiftUI

/// Mini-Reader-Sheet für Release-Notes eines gefundenen Updates.
/// Rendert release.bodyHTML über dieselbe ReaderContentRenderer/
/// ReaderInlineRun-Pipeline wie der Artikel-Reader (Fett/Kursiv/Links
/// funktionieren automatisch) - bewusst eine schlanke, eigene
/// Block-zu-View-Funktion statt SQLiteReaderView.contentBlock(_:)
/// wiederzuverwenden, da diese Reader-spezifisches Chrome (konfigurierbare
/// Schriftgrösse, Sticky-Header, Bild-Zoom) mitbringt, das hier nicht passt.
struct UpdateAvailableSheet: View {
    let release: GitHubRelease
    let onOpenOnGitHub: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var blocks: [ReaderContentBlock] {
        ReaderContentRenderer.blocks(summary: nil, content: release.bodyHTML, fallbackImageURL: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.updateCheckAvailableTitle(tagName: release.tagName))
                    .font(.system(size: 15, weight: .semibold))

                if let name = release.name, !name.isEmpty {
                    Text(name)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ReaderContentBlockEntry.entries(from: blocks)) { entry in
                        releaseNoteBlock(entry.block)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button(L10n.updateCheckDismissButton) {
                    onDismiss()
                }

                Spacer()

                Button(L10n.updateCheckOpenOnGitHubButton) {
                    onOpenOnGitHub()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 320)
    }

    @ViewBuilder
    private func releaseNoteBlock(_ block: ReaderContentBlock) -> some View {
        switch block {
        case .paragraph(let runs):
            Text(runs.attributedString(colorScheme: colorScheme))
                .font(.system(size: 13))
        case .heading(let runs):
            Text(runs.attributedString(colorScheme: colorScheme))
                .font(.system(size: 14, weight: .semibold))
        case .quote(let runs):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 3)
                Text(runs.attributedString(colorScheme: colorScheme))
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(.secondary)
            }
        case .listItem(let runs):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "•")
                    .foregroundStyle(.secondary)
                Text(runs.attributedString(colorScheme: colorScheme))
                    .font(.system(size: 13))
            }
        case .image:
            // Release-Notes dieses Projekts sind reiner CHANGELOG-Text (Bullet-
            // Listen aus Commit-Nachrichten) - Bilder kommen hier praktisch nie vor,
            // bewusst nicht gerendert statt CachedRemoteImageView-Komplexität
            // für diesen einmaligen Anwendungsfall zu übernehmen.
            EmptyView()
        }
    }
}
```

- [ ] **Step 4: Vollen Build verifizieren**

Run: `xcodebuild -scheme Feedivo -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Settings/UpdateAvailableSheet.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feat: UpdateAvailableSheet (Mini-Reader für Release-Notes) (Task 4)"
```

---

### Task 5: App-Menü-Integration + stiller Start-Check (`FeedivoApp.swift`)

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift:126` (bestehender `.task { }`-Block),
  `Feedivo/App/FeedivoApp.swift:159-173` (bestehender `.commands { }`-Block),
  Ende der `Window("Feedivo", id: "main")`-Modifier-Kette (nach Zeile 158)
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `UpdateChecker` (Task 3), `AppVersionInfo` (Task 1),
  `UpdateCheckSettings` (Task 3), `UpdateAvailableSheet` (Task 4), `AppLogger.dataAccess`
  (bestehend, `Feedivo/Extensions/SilentErrorLogging.swift`)
- Produces: Menüpunkt "Nach Updates suchen…" im App-Menü, stiller Start-Check,
  Sheet-/Alert-Präsentation im Hauptfenster

- [ ] **Step 1: Neue L10n-Keys ergänzen**

Füge in `Feedivo/Resources/L10n.swift` ans Ende der Datei an:

```swift
    static let updateCheckMenuItem = String(localized: "updateCheck.menuItem")
    static let updateCheckUpToDateTitle = LocalizedStringKey("updateCheck.upToDate.title")
    static let updateCheckErrorTitle = LocalizedStringKey("updateCheck.error.title")
```

- [ ] **Step 2: Katalogeinträge ergänzen**

```json
    "updateCheck.menuItem" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nach Updates suchen…"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Check for Updates…"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Rechercher des mises à jour…"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Cerca aggiornamenti…"
          }
        }
      }
    },
    "updateCheck.upToDate.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Du verwendest bereits die neueste Version"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "You're already using the latest version"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Tu utilises déjà la dernière version"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Stai già usando la versione più recente"
          }
        }
      }
    },
    "updateCheck.error.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Update-Prüfung fehlgeschlagen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Update Check Failed"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Échec de la vérification des mises à jour"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Controllo aggiornamenti non riuscito"
          }
        }
      }
    },
```

Verifizieren:
```bash
grep -c "updateCheck.menuItem" Feedivo/Resources/Localizable.xcstrings
grep -c "updateCheck.upToDate.title" Feedivo/Resources/Localizable.xcstrings
grep -c "updateCheck.error.title" Feedivo/Resources/Localizable.xcstrings
git diff --stat Feedivo/Resources/Localizable.xcstrings
```
Expected: jedes `grep -c` > 0, nur Insertions.

- [ ] **Step 3: `@AppStorage`/`@State`-Properties in `FeedivoApp` ergänzen**

Füge direkt nach der bestehenden `spotlightIndexingIsEnabled`-Property (Zeile 35-36) ein:

```swift
    @AppStorage(UpdateCheckSettings.isAutomaticCheckEnabledKey)
    private var updateCheckIsAutomaticCheckEnabled = UpdateCheckSettings.defaultIsAutomaticCheckEnabled

    @AppStorage(UpdateCheckSettings.hasUnseenUpdateKey)
    private var updateCheckHasUnseenUpdate = UpdateCheckSettings.defaultHasUnseenUpdate

    @State private var updateCheckReleasePresentation: GitHubRelease?
    @State private var showsUpdateCheckUpToDateAlert = false
    @State private var updateCheckErrorMessage: String?
```

- [ ] **Step 4: Silent-Check in den bestehenden Start-`.task { }`-Block einhängen**

Ändere den bestehenden Block (Zeile 126-134):

```swift
                .task {
                    guard databaseLoadState.initializationError == nil else {
                        return
                    }
                    backfillStoredArticleMetadataIfNeeded()
                    trimImageCacheToSelectedLimit()
                    ensureSpotlightBackfillIfNeeded()
                    scheduleBackgroundRefresh()
                    performSilentUpdateCheckIfNeeded()
                }
```

(einzige Änderung: neuer Aufruf `performSilentUpdateCheckIfNeeded()` als letzte Zeile)

- [ ] **Step 5: Sheet/Alert-Modifier an dieselbe Modifier-Kette anhängen**

Füge direkt nach dem bestehenden `.onChange(of: spotlightIndexingIsEnabled) { ... }`
(Zeile 156-158, letzter Modifier vor der schließenden `}` der `Window(...)`-Definition
in Zeile 159) folgendes ein:

```swift
                .sheet(item: $updateCheckReleasePresentation) { release in
                    UpdateAvailableSheet(
                        release: release,
                        onOpenOnGitHub: {
                            NSWorkspace.shared.open(release.htmlURL)
                        },
                        onDismiss: {
                            updateCheckReleasePresentation = nil
                        }
                    )
                }
                .alert(L10n.updateCheckUpToDateTitle, isPresented: $showsUpdateCheckUpToDateAlert) {
                    Button(L10n.commonOK, role: .cancel) {}
                }
                .alert(
                    L10n.updateCheckErrorTitle,
                    isPresented: Binding(
                        get: { updateCheckErrorMessage != nil },
                        set: { isPresented in
                            if !isPresented {
                                updateCheckErrorMessage = nil
                            }
                        }
                    )
                ) {
                    Button(L10n.commonOK, role: .cancel) {}
                } message: {
                    Text(updateCheckErrorMessage ?? "")
                }
```

- [ ] **Step 6: Menüpunkt in den bestehenden `.commands { }`-Block einhängen**

Ändere den bestehenden Block (Zeile 160-173):

```swift
        .commands {
            ArticleCommands()
            FeedCommands()
            ViewCommands()
            CommandGroup(after: .appInfo) {
                Button(
                    updateCheckHasUnseenUpdate
                        ? "• \(L10n.updateCheckMenuItem)"
                        : L10n.updateCheckMenuItem
                ) {
                    performManualUpdateCheck()
                }
            }
            // Entfernt den von SwiftUI automatisch bereitgestellten, aber funktionslosen
            // "Drucken..."-Menuepunkt (Datei-Menue, Standard-Tastenkombination Cmd+P).
            // Ohne diese Entfernung kollidiert er mit dem neuen Drucken-Button in
            // SQLiteReaderView.swift (Feature 25.1), der ebenfalls Cmd+P beansprucht —
            // das Standard-NSMenuItem gewinnt den Tastenkombinations-Konflikt und zeigt
            // beim Ausloesen den generischen AppKit-Fallback-Alert "Diese App
            // unterstuetzt Drucken nicht", statt dass unser Drucken-Button reagiert
            // (Live-Bug-Fund 2026-07-17, Nutzer-Report).
            CommandGroup(replacing: .printItem) {}
        }
```

(einzige Änderung: neuer `CommandGroup(after: .appInfo) { ... }`-Block zwischen
`ViewCommands()` und dem bestehenden `CommandGroup(replacing: .printItem)`)

- [ ] **Step 7: Zwei private Methoden am Ende von `FeedivoApp` ergänzen**

Füge direkt nach `private func ensureSpotlightBackfillIfNeeded()` (endet Zeile 333) ein:

```swift
    private func performManualUpdateCheck() {
        // Nutzer schaut gerade hin - Badge sofort weg, unabhängig vom Ergebnis.
        updateCheckHasUnseenUpdate = false
        Task {
            let outcome = await UpdateChecker().check(
                currentMarketingVersion: AppVersionInfo.marketingVersion,
                currentBuildNumber: AppVersionInfo.buildNumber
            )
            switch outcome {
            case .updateAvailable(let release):
                updateCheckReleasePresentation = release
            case .upToDate:
                showsUpdateCheckUpToDateAlert = true
            case .failed(let message):
                updateCheckErrorMessage = message
            }
        }
    }

    private func performSilentUpdateCheckIfNeeded() {
        guard updateCheckIsAutomaticCheckEnabled else {
            return
        }
        Task {
            let outcome = await UpdateChecker().check(
                currentMarketingVersion: AppVersionInfo.marketingVersion,
                currentBuildNumber: AppVersionInfo.buildNumber
            )
            switch outcome {
            case .updateAvailable:
                updateCheckHasUnseenUpdate = true
            case .upToDate:
                updateCheckHasUnseenUpdate = false
            case .failed(let message):
                // Bewusst keine UI-Unterbrechung beim stillen Start-Check - nur Log.
                AppLogger.dataAccess.error("Update-Check (Start): \(message, privacy: .public)")
            }
        }
    }
```

- [ ] **Step 8: Vollen Build verifizieren**

Run: `xcodebuild -scheme Feedivo -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
git add Feedivo/App/FeedivoApp.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feat: App-Menü + stiller Start-Check für Update-Prüfung (Task 5)"
```

---

### Task 6: Neuer Settings-Tab „Über"

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (Enum `SettingsSection`, `TabView`,
  `settingsContent(for:)`-Switch, Sichtbarkeit von `SettingsBlock`/`SettingRow`/`InfoRow`)
- Create: `Feedivo/Views/Settings/AboutSettingsView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `UpdateChecker`, `AppVersionInfo`, `UpdateCheckSettings` (Task 3),
  `UpdateAvailableSheet` (Task 4), `SettingsBlock`/`SettingRow` (bestehend in
  `SettingsView.swift`, Sichtbarkeit wird in dieser Task von `private` auf `internal`
  (Standard-Zugriffsebene) angehoben, damit `AboutSettingsView.swift` sie nutzen kann)
- Produces: 11. Settings-Tab „Über" mit App-Icon, Version, Update-Check-Button, Toggle

- [ ] **Step 1: `SettingsBlock`/`SettingRow`/`InfoRow`-Sichtbarkeit lockern**

In `Feedivo/Views/Settings/SettingsView.swift`, entferne das `private`-Schlüsselwort bei
allen drei Struct-Deklarationen (Zeilen 148, 164, 195):

```swift
struct SettingsBlock<Content: View>: View {
```
```swift
struct SettingRow<Control: View>: View {
```
```swift
struct InfoRow: View {
```

(Alle drei bleiben ansonsten unverändert - reine Sichtbarkeits-Änderung von file-privat
auf modulweit, damit `AboutSettingsView.swift` sie wiederverwenden kann statt Styling zu
duplizieren.)

- [ ] **Step 2: `SettingsSection`-Enum um `.about` erweitern**

In `Feedivo/Views/Settings/SettingsView.swift`, füge `case about` NACH `case sync`
(Zeile 14) ein:

```swift
private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case articleList
    case menubar
    case shortcuts
    case readerToolbar
    case notifications
    case refresh
    case cleanup
    case sync
    case about
```

Füge in `var title` (nach `case .sync: L10n.settingsSyncSection`, um Zeile 37-38) ein:

```swift
        case .about:
            L10n.settingsAboutSection
```

Füge in `var systemImage` (nach `case .sync: "icloud"`, um Zeile 61-62) ein:

```swift
        case .about:
            "info.circle"
```

- [ ] **Step 3: Neuen Tab in `TabView` und `settingsContent(for:)` verdrahten**

Füge in `body` (nach `settingsTab(.sync)`, Zeile 99) ein:

```swift
            settingsTab(.about)
```

Füge in `settingsContent(for:)` (nach `case .sync: SyncSettingsView()`, Zeile 142-143)
ein:

```swift
        case .about:
            AboutSettingsView()
```

- [ ] **Step 4: Neue L10n-Keys ergänzen**

Füge in `Feedivo/Resources/L10n.swift` ans Ende der Datei an:

```swift
    static let settingsAboutSection = LocalizedStringKey("settings.about.section")
    static let updateCheckAutomaticCheckTitle = LocalizedStringKey("updateCheck.automaticCheck.title")
    static let updateCheckAutomaticCheckDescription = LocalizedStringKey("updateCheck.automaticCheck.description")
    // Bewusst String (nicht LocalizedStringKey) wie updateCheckMenuItem selbst -
    // beide werden in AboutSettingsView im selben Ternary-Ausdruck verwendet
    // (isChecking ? updateCheckCheckingButton : updateCheckMenuItem), Swift
    // verlangt dafür identische Typen in beiden Zweigen.
    static let updateCheckCheckingButton = String(localized: "updateCheck.checking.button")
    static func updateCheckVersionLabel(marketingVersion: String, buildNumber: Int) -> String {
        String.localizedStringWithFormat(String(localized: "updateCheck.versionLabel"), marketingVersion, buildNumber)
    }
```

- [ ] **Step 5: Katalogeinträge ergänzen**

```json
    "settings.about.section" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Über"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "About"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "À propos"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Informazioni"
          }
        }
      }
    },
    "updateCheck.automaticCheck.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Beim Start automatisch nach Updates suchen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Automatically check for updates on launch"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Rechercher automatiquement les mises à jour au démarrage"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Cerca automaticamente aggiornamenti all'avvio"
          }
        }
      }
    },
    "updateCheck.automaticCheck.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Prüft beim App-Start still im Hintergrund, ob eine neuere Version verfügbar ist."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Silently checks in the background on launch whether a newer version is available."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Vérifie silencieusement en arrière-plan au démarrage si une nouvelle version est disponible."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Controlla silenziosamente in background all'avvio se è disponibile una versione più recente."
          }
        }
      }
    },
    "updateCheck.checking.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Suche läuft…"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Checking…"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Recherche en cours…"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ricerca in corso…"
          }
        }
      }
    },
    "updateCheck.versionLabel" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Version %@ (%d)"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Version %@ (%d)"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Version %@ (%d)"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Versione %@ (%d)"
          }
        }
      }
    },
```

Verifizieren:
```bash
grep -c "settings.about.section" Feedivo/Resources/Localizable.xcstrings
grep -c "updateCheck.automaticCheck.title" Feedivo/Resources/Localizable.xcstrings
grep -c "updateCheck.automaticCheck.description" Feedivo/Resources/Localizable.xcstrings
grep -c "updateCheck.checking.button" Feedivo/Resources/Localizable.xcstrings
grep -c "updateCheck.versionLabel" Feedivo/Resources/Localizable.xcstrings
git diff --stat Feedivo/Resources/Localizable.xcstrings
```
Expected: jedes `grep -c` > 0, nur Insertions.

- [ ] **Step 6: `AboutSettingsView` implementieren**

```swift
// Feedivo/Views/Settings/AboutSettingsView.swift
import AppKit
import SwiftUI

/// Neuer Settings-Tab "Über": App-Icon, Version, manueller Update-Check-
/// Button und ein Schalter für den stillen Start-Check. Ruft denselben
/// stateless UpdateChecker wie das App-Menü auf, hält aber bewusst eigenen,
/// lokalen Präsentationszustand (siehe Abweichung von der Spec im Plan-Header) -
/// vermeidet, dass ein hier ausgelöster Check gleichzeitig im Hauptfenster
/// ein Sheet öffnet, falls beide Fenster offen sind.
struct AboutSettingsView: View {
    @AppStorage(UpdateCheckSettings.isAutomaticCheckEnabledKey)
    private var isAutomaticCheckEnabled = UpdateCheckSettings.defaultIsAutomaticCheckEnabled

    @AppStorage(UpdateCheckSettings.hasUnseenUpdateKey)
    private var hasUnseenUpdate = UpdateCheckSettings.defaultHasUnseenUpdate

    @State private var isChecking = false
    @State private var releasePresentation: GitHubRelease?
    @State private var showsUpToDateAlert = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: L10n.settingsAboutSection) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Feedivo")
                            .font(.system(size: 15, weight: .semibold))
                        Text(L10n.updateCheckVersionLabel(
                            marketingVersion: AppVersionInfo.marketingVersion,
                            buildNumber: AppVersionInfo.buildNumber
                        ))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)

                SettingRow(
                    title: L10n.updateCheckAutomaticCheckTitle,
                    description: L10n.updateCheckAutomaticCheckDescription
                ) {
                    Toggle("", isOn: $isAutomaticCheckEnabled)
                        .labelsHidden()
                }

                HStack(spacing: 8) {
                    Button(isChecking ? L10n.updateCheckCheckingButton : L10n.updateCheckMenuItem) {
                        performCheck()
                    }
                    .disabled(isChecking)

                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }
        }
        .sheet(item: $releasePresentation) { release in
            UpdateAvailableSheet(
                release: release,
                onOpenOnGitHub: { NSWorkspace.shared.open(release.htmlURL) },
                onDismiss: { releasePresentation = nil }
            )
        }
        .alert(L10n.updateCheckUpToDateTitle, isPresented: $showsUpToDateAlert) {
            Button(L10n.commonOK, role: .cancel) {}
        }
        .alert(
            L10n.updateCheckErrorTitle,
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button(L10n.commonOK, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func performCheck() {
        hasUnseenUpdate = false
        isChecking = true
        Task {
            let outcome = await UpdateChecker().check(
                currentMarketingVersion: AppVersionInfo.marketingVersion,
                currentBuildNumber: AppVersionInfo.buildNumber
            )
            isChecking = false
            switch outcome {
            case .updateAvailable(let release):
                releasePresentation = release
            case .upToDate:
                showsUpToDateAlert = true
            case .failed(let message):
                errorMessage = message
            }
        }
    }
}
```

- [ ] **Step 7: Vollen Build verifizieren**

Run: `xcodebuild -scheme Feedivo -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/Views/Settings/AboutSettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feat: Neuer Settings-Tab „Über" mit Update-Check (Task 6)"
```

---

### Task 7: Regressionslauf + Release-Build-Verifikation

**Files:** Keine neuen/geänderten Dateien — reiner Verifikationsschritt.

**Interfaces:** Keine.

- [ ] **Step 1: Alle neuen/betroffenen Test-Suiten gezielt laufen lassen**

Run:
```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/UpdateVersionComparatorTests \
  -only-testing:FeedivoTests/GitHubReleaseCheckServiceTests \
  -only-testing:FeedivoTests/UpdateCheckerTests \
  -parallel-testing-enabled NO
```
Expected: alle Tests PASS (17/17: 9 Comparator + 3 Service + 5 Checker)

- [ ] **Step 2: Vollen Debug-Build verifizieren**

Run: `xcodebuild -scheme Feedivo -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Vollen Release-Build verifizieren (deckt Signing/Entitlements-Probleme
  auf, die ein Debug-Build übersieht)**

Run: `xcodebuild -scheme Feedivo -configuration Release build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: L10n-Vollständigkeit für alle 14 neuen Keys final verifizieren**

Run:
```bash
for key in \
  "settings.about.section" \
  "updateCheck.menuItem" \
  "updateCheck.checking.button" \
  "updateCheck.automaticCheck.title" \
  "updateCheck.automaticCheck.description" \
  "updateCheck.upToDate.title" \
  "updateCheck.error.title" \
  "updateCheck.openOnGitHub.button" \
  "updateCheck.dismiss.button" \
  "updateCheck.available.title" \
  "updateCheck.versionLabel" \
  "updateCheck.error.invalidResponse" \
  "updateCheck.error.httpError" \
  "updateCheck.error.decodingFailed"; do
  count=$(grep -c "\"$key\"" Feedivo/Resources/Localizable.xcstrings)
  echo "$key: $count"
done
```
Expected: jeder Key genau 1 (kein Key mit 0 Treffern)

- [ ] **Step 5: `git status`/`git log` über alle 6 Tasks hinweg gegenprüfen**

Run: `git log --oneline -7` und `git status --short`
Expected: 6 saubere Commits (Task 1-6, dieser Verifikationsschritt hat keinen eigenen
Commit nötig, da keine Dateien geändert wurden), Working Tree clean.

- [ ] **Step 6: Manuelle Live-Verifikationscheckliste dokumentieren (nicht automatisierbar
  in dieser Umgebung — kein computer-use für native macOS-Apps)**

Kein Code-Schritt — trage folgende Checkliste als Kommentar in die finale
Zusammenfassung ein, damit der Nutzer sie nach dem Merge manuell abarbeiten kann:

1. App-Menü → "Nach Updates suchen…" klicken → zeigt entweder das Release-Notes-Sheet
   (falls eine neuere Version auf GitHub existiert) oder "Du verwendest bereits die
   neueste Version".
2. Sheet: "Auf GitHub öffnen" öffnet die richtige Release-Seite im Standardbrowser,
   "Später" schließt das Sheet.
3. Einstellungen → Tab "Über" zeigt App-Icon, korrekte Version/Build-Nummer, denselben
   Update-Check-Button (unabhängig vom Menü-Klick nutzbar) und den Toggle für den
   automatischen Start-Check.
4. Toggle "Beim Start automatisch nach Updates suchen" ausschalten → App neu starten →
   kein automatischer Check (kein Menü-Badge-Punkt, selbst wenn ein Update existiert).
5. Toggle wieder einschalten, App neu starten, mit einer künstlich älteren
   `CURRENT_PROJECT_VERSION` testen (oder ein neues Test-Release auf GitHub anlegen) →
   Menüpunkt zeigt "• Nach Updates suchen…" (Badge-Punkt), verschwindet nach Klick.
6. Netzwerk währenddessen deaktivieren, manuellen Check auslösen → Fehler-Alert mit
   verständlichem Text statt Absturz/stillem Nichtstun.

---
