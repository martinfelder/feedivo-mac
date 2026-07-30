# Design: Update-Prüfung über GitHub Releases

**Datum:** 2026-07-30
**Status:** Vom Nutzer genehmigt, bereit für Implementierungsplan

## Problem

Feedivo wird aktuell manuell per `scripts/create_github_release.sh` als GitHub Pre-Release
veröffentlicht (siehe CLAUDE.md, „GitHub"-Abschnitt). Es gibt keine Möglichkeit, innerhalb
der laufenden App zu prüfen, ob eine neuere Version existiert — der Nutzer müsste manuell
die GitHub-Releases-Seite besuchen. Da die App weder über den App Store noch über Sparkle
vertrieben wird, fehlt jeder eingebaute Update-Mechanismus.

Das Repo `martinfelder/feedivo-mac` ist während dieses Brainstormings bewusst auf **Public**
umgestellt worden (verifiziert per `gh repo view`), wodurch die GitHub-REST-API ohne Token
unauthentifiziert abgefragt werden kann (Rate-Limit: 60 Anfragen/Stunde pro IP — für
gelegentliche manuelle/Start-Checks ausreichend).

## Umfang

**Enthalten:**
- Manueller Update-Check über einen neuen Menüpunkt im App-Menü „Feedivo"
- Manueller Update-Check über einen neuen Settings-Tab „Über"
- Stiller, automatischer Check beim App-Start (abschaltbar), zeigt bei Fund nur einen
  dezenten Hinweis am Menüpunkt, kein Sheet/Alert
- Anzeige der Release-Notes als gerenderter Mini-Reader (Wiederverwendung von
  `ReaderContentRenderer`/`ReaderInlineRun`)
- Direkter „Auf GitHub öffnen"-Link zur Release-Seite (kein In-App-Download/Installer)

**Bewusst außerhalb des Umfangs:**
- Kein automatischer Download/Installer (kein Sparkle-Äquivalent) — der Nutzer lädt die
  `.zip` weiterhin manuell von GitHub, öffnet sie über den bekannten Gatekeeper-Workaround
- Keine Authentifizierung/kein Token nötig, da das Repo public ist
- Kein Throttling/Mindestabstand zwischen Checks (YAGNI für einen Solo-Nutzer, der nicht
  60×/Stunde klickt)
- Keine Persistenz des zuletzt geladenen Release-Inhalts über Neustarts hinweg — jeder
  manuelle Klick holt ohnehin frisch

## Architektur

### 1. `GitHubReleaseCheckService` (`Feedivo/Services/GitHubReleaseCheckService.swift`)

Reiner Netzwerk-Client, folgt dem Projektmuster injizierbarer HTTP-Clients (analog
`FaviconService`/`FeedService`) für Testbarkeit ohne echten Netzwerk-Call.

```swift
struct GitHubRelease: Equatable, Sendable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let bodyHTML: String?
    let publishedAt: Date?
}

protocol GitHubReleaseFetching: Sendable {
    func fetchReleases() async throws -> [GitHubRelease]
}

struct GitHubReleaseCheckService: GitHubReleaseFetching {
    // GET https://api.github.com/repos/martinfelder/feedivo-mac/releases
    // Header: Accept: application/vnd.github.html+json
    //   -> GitHub liefert body_html (server-seitig aus Markdown gerendert) zusätzlich zum
    //      rohen body-Feld mit - kein eigener Markdown-Parser im Client nötig.
    // WICHTIG: die Liste, NICHT /releases/latest - create_github_release.sh markiert JEDES
    //   Release als --prerelease, und /releases/latest ignoriert Pre-Releases (liefert 404).
    //   Die Liste ist laut GitHub-API nach created_at absteigend sortiert, erstes Element
    //   = neuestes Release.

    // Netzwerk-Aufruf (URLSession.shared.data(for:)) und JSON-Decoding sind bewusst
    // getrennt: fetchReleases() ist ein dünner Wrapper, die eigentliche Decoding-Logik
    // liegt in einer separaten, reinen, statischen Funktion
    // decodeReleases(from: Data) throws -> [GitHubRelease]. Grund: Das Projekt hat
    // aktuell KEINE URLSession-Mocking-Infrastruktur (FeedService/FaviconService rufen
    // URLSession.shared direkt auf, deren Tests decken nur reine Parsing-Funktionen ab,
    // nicht den Netzwerk-Aufruf selbst) - eine neue Mock-Schicht nur für dieses eine
    // Feature wäre unverhältnismäßig. Die Trennung erlaubt trotzdem echte Unit-Tests
    // für die Decoding-Logik (per Fixture-JSON), ohne Netzwerk-Mocking einzuführen.
}
```

Fehlerfälle (HTTP-Fehler, Rate-Limit 403, leere Liste, Decoding-Fehler) werden als
`GitHubReleaseCheckError`-Enum nach oben gereicht, keine stillen Fallbacks im Service selbst.

### 2. `UpdateVersionComparator` (`Feedivo/Services/UpdateVersionComparator.swift`)

Reine, pure, isoliert testbare Funktion (Muster: `SidebarFeedOrder`, `ReaderArrowKeyNavigation`).

```swift
enum UpdateCheckResult: Equatable {
    case upToDate
    case updateAvailable(GitHubRelease)
    case unknown // Tag entspricht nicht dem erwarteten Muster - kein Vergleich möglich
}

enum UpdateVersionComparator {
    // Parst "v{MARKETING_VERSION}-{BUILD_NUMBER}" (exakt das Tag-Format aus
    // create_github_release.sh: TAG="v${MARKETING_VERSION}-${BUILD_NUMBER}").
    // Vergleich zuerst über MARKETING_VERSION (Komponenten-Tupel-Vergleich, z.B. "1.2" > "1.0"),
    // BUILD_NUMBER als Tiebreaker bei gleicher Marketing-Version - zukunftssicher, falls die
    // Marketing-Version irgendwann über "1.0" hinaus erhöht wird.
    static func compare(
        latestRelease: GitHubRelease,
        currentMarketingVersion: String,
        currentBuildNumber: Int
    ) -> UpdateCheckResult
}
```

Ein nicht parsbarer Tag (z. B. ein von Hand angelegtes Release ohne das Schema) liefert
`.unknown` - wird von der aufrufenden Seite wie "kein Update" behandelt (keine
falsch-positive Update-Meldung), nur ein Debug-Log-Eintrag.

### 3. `UpdateCheckCoordinator` (`Feedivo/Services/UpdateCheckCoordinator.swift`)

`@Observable @MainActor`, orchestriert Service + Comparator, hält den flüchtigen
UI-Zustand (`isChecking: Bool`, `lastError: String?`, `latestRelease: GitHubRelease?` -
nur für die Dauer der aktuellen Sheet-Anzeige gehalten, nicht persistiert).

```swift
@Observable @MainActor
final class UpdateCheckCoordinator {
    var isChecking = false
    var lastError: String?
    var latestRelease: GitHubRelease?      // gesetzt, sobald ein Update gefunden wurde
    var showsUpToDateAlert = false

    // Stiller Start-Check: setzt nur UpdateCheckSettings.hasUnseenUpdate (AppStorage),
    // zeigt kein Sheet/Alert, Fehler werden nur geloggt (AppLogger).
    func checkSilently(currentMarketingVersion: String, currentBuildNumber: Int) async

    // Manueller Check (Menü/Settings-Button): löscht hasUnseenUpdate sofort (Nutzer schaut
    // ja gerade hin), holt IMMER frisch, setzt bei Erfolg latestRelease (Sheet) ODER
    // showsUpToDateAlert ODER lastError (Alert).
    func checkManually(currentMarketingVersion: String, currentBuildNumber: Int) async
}
```

### 4. `UpdateCheckSettings` (`Feedivo/Services/UpdateCheckSettings.swift`)

Folgt dem etablierten `*Settings`-Muster (`BackgroundRefreshSettings`,
`SpotlightIndexingSettings`) mit statischen `AppStorage`-Keys:

```swift
enum UpdateCheckSettings {
    static let isAutomaticCheckEnabledKey = "updateCheckIsAutomaticCheckEnabled"
    static let defaultIsAutomaticCheckEnabled = true

    static let hasUnseenUpdateKey = "updateCheckHasUnseenUpdate"
    static let defaultHasUnseenUpdate = false
}
```

**Wichtiger Konsistenz-Punkt:** `hasUnseenUpdateKey` ist bewusst ein einfacher
`@AppStorage`-Bool statt eines Felds auf dem `@Observable`-Coordinator. Grund: Es gibt in
der Projekt-Historie einen dokumentierten, nie abschließend verifizierten Zweifel, ob
`@Observable`-Zustand zuverlässig ein `CommandGroup`-Menüitem in `.commands { }` neu
rendert (siehe Shortcuts-Feature, Task 6 Review). `FeedivoApp.swift` bindet bereits
mehrere Verhaltens-Flags (`backgroundRefreshIsEnabled` u. a.) über `@AppStorage` direkt in
die View-Struct ein — dasselbe, erprobte Muster wird hier für die Menü-Titel-Reaktivität
übernommen, um dieses offene Risiko gar nicht erst zu berühren.

## Datenfluss

**App-Start** (`FeedivoApp.body`, neuer `.task` neben den bestehenden Start-Aufgaben):
Nur wenn `isAutomaticCheckEnabled` (AppStorage) an ist →
`coordinator.checkSilently(...)` → Service holt Release-Liste → Comparator vergleicht →
`.updateAvailable` → `hasUnseenUpdateKey = true`; `.upToDate`/`.unknown` →
`hasUnseenUpdateKey = false`. Netzwerkfehler werden nur geloggt (`AppLogger.dataAccess`),
niemals eine UI-Unterbrechung beim Start.

**Manueller Klick** (App-Menü-Button ODER Button im „Über"-Tab, beide rufen dieselbe
Coordinator-Methode auf):
1. `hasUnseenUpdateKey = false` sofort (Nutzer schaut gerade hin)
2. Frischer Fetch (kein Cache, auch wenn der Start-Check schon gelaufen ist - hält die
   State-Verwaltung einfach, kein Zwischenspeichern des Release-Inhalts nötig)
3. Ergebnis:
   - `.updateAvailable(release)` → `coordinator.latestRelease` gesetzt → `UpdateAvailableSheet`
     wird angezeigt
   - `.upToDate`/`.unknown` → `coordinator.showsUpToDateAlert = true` → einfacher Alert
     „Du verwendest bereits die neueste Version"
   - Fehler (Netzwerk/Decoding/Rate-Limit) → `coordinator.lastError` gesetzt → Alert mit
     Klartext-Fehlermeldung

„Auf GitHub öffnen" im Sheet → `NSWorkspace.shared.open(release.htmlURL)` (Standardbrowser,
kein In-App-WebView nötig für diesen Zweck).

## UI-Details

### App-Menü (`FeedivoApp.swift`, `.commands`)

```swift
CommandGroup(after: .appInfo) {
    Button(hasUnseenUpdateKey ? "• \(L10n.updateCheckMenuItem)" : L10n.updateCheckMenuItem) {
        Task { await updateCheckCoordinator.checkManually(...) }
    }
}
```

Ein führender Punkt „• " im Titel-String ist die gewählte Lösung für den
"Update verfügbar"-Hinweis: Echte Badge-Kreise auf `NSMenuItem`s sind über SwiftUIs
`CommandGroup`-API nicht ansteuerbar (reine Text+Icon-Items), ein Text-Präfix ist robust
und braucht keine AppKit-Bridge.

### Neuer Settings-Tab „Über" (`SettingsTab.about`, 11. Tab)

Neue Datei `Feedivo/Views/Settings/AboutSettingsView.swift`, eingehängt in
`SettingsView.swift`s bestehendes `SettingsTab`-Enum (analog den anderen 10 Tabs):

- App-Icon, „Feedivo", Version+Build aus `Bundle.main` (z. B. „1.0 (11)"), Copyright
- Button „Nach Updates suchen" → ruft `coordinator.checkManually(...)` auf (identisch zum
  Menüpunkt)
- Toggle „Beim Start automatisch nach Updates suchen" (`UpdateCheckSettings.isAutomaticCheckEnabledKey`,
  Default an) - passt zum bestehenden Muster abschaltbarer Hintergrund-Verhalten
  (Hintergrund-Refresh, Benachrichtigungen)

### `UpdateAvailableSheet` (neue Datei, `Feedivo/Views/Settings/UpdateAvailableSheet.swift`)

Mini-Reader-Sheet, präsentiert über `.sheet(item:)` (bestehendes Projekt-Idiom für
Sheets mit assoziierten Daten, siehe `RuleCreationRequest`-Gotcha - `GitHubRelease`
selbst wird `Identifiable` über `tagName`):

- Titel „Neue Version verfügbar: {tagName}" + `release.name` als Unterüberschrift
- Release-Notes gerendert über `ReaderContentRenderer.blocks(summary: nil, content: release.bodyHTML,
  fallbackImageURL: nil)` → `ReaderContentBlockEntry.entries(from:)` → `ForEach` mit einer
  neuen, schlanken Block-zu-View-Funktion (reduzierte Variante von `SQLiteReaderView.contentBlock(_:)`,
  ohne Reader-spezifisches Chrome wie Sticky-Header/Bilder-Zoom - nur Absatz/Überschrift/Liste/Zitat
  mit `Text(AttributedString)` über die bestehende `[ReaderInlineRun] -> AttributedString`-Konvertierung)
- Buttons: „Auf GitHub öffnen" (primär, öffnet `release.htmlURL`), „Später" (schließt das Sheet)
- Explizites `.frame(minWidth: 420, minHeight: 320)` - bekannter Gotcha: Sheets mit
  asynchron befülltem Inhalt bleiben ohne festen Frame winzig/leer

## Fehlerbehandlung

| Fall | Stiller Start-Check | Manueller Check |
|---|---|---|
| Netzwerkfehler/Timeout | Nur Log (`AppLogger.dataAccess`), `hasUnseenUpdateKey` unverändert | Alert mit Fehlertext |
| Leere Release-Liste | Wie `.upToDate` behandelt | „Bereits aktuell"-Alert |
| Rate-Limit (HTTP 403) | Nur Log | Alert („Bitte später erneut versuchen") |
| Tag entspricht nicht `v{Version}-{Build}` | `.unknown`, `hasUnseenUpdateKey = false` | „Bereits aktuell"-Alert (konservativ, keine Falsch-Meldung) |

## Tests

- **`UpdateVersionComparatorTests`** (reine Logik, volle Abdeckung): neuerer Build gleiche
  Marketing-Version, gleicher Build, älterer Build, Marketing-Version-Sprung (z. B. "1.1"
  vs. laufend "1.0", Build dabei egal), kaputter/unerwarteter Tag → `.unknown`
- **`GitHubReleaseCheckServiceTests`**: testet `decodeReleases(from: Data)` gegen
  Fixture-JSON (Erfolgsfall, leere Liste, kaputtes JSON) - kein echter Netzwerk-Call,
  kein URLSession-Mocking (siehe Architektur-Abschnitt zur bewussten Trennung
  Netzwerk-Wrapper/reine Decoding-Funktion)
- **`UpdateCheckCoordinatorTests`**: mit gemocktem `GitHubReleaseFetching` (das reine
  Protokoll, nicht URLSession selbst) - verifiziert
  korrekte Zustandsübergänge (`hasUnseenUpdateKey`, `latestRelease`,
  `showsUpToDateAlert`, `lastError`) für alle Comparator-Ergebnisse
- Kein UI-Test für das Sheet selbst (kein computer-use für native macOS-Apps in dieser
  Umgebung) - manuelle Live-Verifikation nötig (siehe Plan-Abschluss)
