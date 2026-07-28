# URL-Schema (Deep Links) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein `feedivo://`-URL-Schema registrieren, über das `feedivo://add?url=...`
einen Feed direkt hinzufügt (mit sofortiger Vorschau) und `feedivo://article?id=...`
einen Artikel in einem Popout-Fenster öffnet — nutzbar aus macOS Shortcuts,
Raycast, Alfred, Automator und (als Voraussetzung) der geplanten Browser-
Erweiterung (Feature 27).

**Architecture:** Eine reine, unabhängig testbare Parsing-Funktion
`FeedivoURLSchemeParser.action(for:)` übersetzt eine `URL` in eine
`FeedivoURLSchemeAction` (`.addFeed(urlString:)` / `.openArticle(articleID:)`).
`ContentView` empfängt URLs über den SwiftUI-Standardmechanismus `.onOpenURL`
und routet je nach Action entweder zum bestehenden `AddFeedSheet` (das einen
neuen optionalen Init-Parameter zum Vorausfüllen + Auto-Start der Vorschau
bekommt) oder öffnet über die bereits bestehende `WindowGroup(for:
ArticleWindowRequest.self)` ein Artikel-Popout-Fenster. Keine neue
Subscribe-/Artikel-Lade-Logik — reine Wiederverwendung bestehender Flows
(Feature 12.4 Vorschau, bestehende Artikel-Popout-Fenster).

**Tech Stack:** SwiftUI (`.onOpenURL`, `@Environment(\.openWindow)`),
`Foundation` (`URLComponents`), Swift Testing (`@Test`/`#expect`), Xcode-
Build-Settings (`INFOPLIST_KEY_CFBundleURLTypes` — Projekt nutzt
`GENERATE_INFOPLIST_FILE = YES`, es existiert keine physische Info.plist).

## Global Constraints

- URL-Schema: `feedivo`, registriert nur für den Haupt-App-Build (nicht für
  die Test-Targets `FeedivoTests`/`FeedivoUITests`).
- `feedivo://add?url=<url>`: öffnet `AddFeedSheet` mit vorausgefüllter URL und
  startet die bestehende Discovery-/Vorschau-Logik (Feature 12.4) automatisch
  — kein zusätzlicher Klick nötig (final entschieden, siehe FEATURES.md 23.2).
- `feedivo://article?id=<uuid>`: öffnet ein Artikel-Popout-Fenster über die
  bestehende `WindowGroup(for: ArticleWindowRequest.self)`.
- Normales, manuelles Öffnen von "Feed hinzufügen" (Sidebar-Button) bleibt
  unverändert — kein Auto-Start der Vorschau, keine übrig gebliebene URL aus
  einem vorherigen Deep Link.
- Unbekannter Host oder fehlende/kaputte Query-Parameter: URL wird still
  ignoriert (kein Alert, kein Crash).
- Kommentare im Code auf Deutsch (Projekt-Konvention).
- SourceKit-Diagnosen in der IDE sind oft veraltet/falsch — verlässlich ist
  nur ein echter `xcodebuild build`-Lauf.
- Volle Testsuite (`xcodebuild test` ohne `-only-testing`) hängt bekanntermaßen
  — immer gezielt mit `-only-testing:FeedivoTests/<SuiteName>` testen.
- Projekt nutzt Xcode-16-"File System Synchronized Groups" — neue `.swift`-
  Dateien im richtigen Ordner werden automatisch vom Target erfasst, keine
  manuelle `project.pbxproj`-Registrierung von Dateien nötig.

---

### Task 1: FeedivoURLSchemeParser (reine Parsing-Logik + Tests)

**Files:**
- Create: `Feedivo/Services/FeedivoURLSchemeParser.swift`
- Test: `FeedivoTests/FeedivoURLSchemeParserTests.swift`

**Interfaces:**
- Produces: `enum FeedivoURLSchemeAction: Equatable { case addFeed(urlString: String); case openArticle(articleID: UUID) }`
- Produces: `FeedivoURLSchemeParser.action(for url: URL) -> FeedivoURLSchemeAction?`

- [ ] **Step 1: Schreibe den fehlschlagenden Test**

Erstelle `FeedivoTests/FeedivoURLSchemeParserTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct FeedivoURLSchemeParserTests {
    @Test func addMitGueltigerURLLiefertAddFeedAction() {
        let url = URL(string: "feedivo://add?url=https://example.com/feed.xml")!

        #expect(
            FeedivoURLSchemeParser.action(for: url) ==
            .addFeed(urlString: "https://example.com/feed.xml")
        )
    }

    @Test func addOhneURLQueryItemLiefertNil() {
        let url = URL(string: "feedivo://add")!

        #expect(FeedivoURLSchemeParser.action(for: url) == nil)
    }

    @Test func addMitLeererURLLiefertNil() {
        let url = URL(string: "feedivo://add?url=")!

        #expect(FeedivoURLSchemeParser.action(for: url) == nil)
    }

    @Test func articleMitGueltigerUUIDLiefertOpenArticleAction() {
        let uuid = UUID()
        let url = URL(string: "feedivo://article?id=\(uuid.uuidString)")!

        #expect(FeedivoURLSchemeParser.action(for: url) == .openArticle(articleID: uuid))
    }

    @Test func articleMitUngueltigerUUIDLiefertNil() {
        let url = URL(string: "feedivo://article?id=not-a-uuid")!

        #expect(FeedivoURLSchemeParser.action(for: url) == nil)
    }

    @Test func unbekannterHostLiefertNil() {
        let url = URL(string: "feedivo://unknown?foo=bar")!

        #expect(FeedivoURLSchemeParser.action(for: url) == nil)
    }

    @Test func falschesSchemaLiefertNil() {
        let url = URL(string: "https://add?url=https://example.com/feed.xml")!

        #expect(FeedivoURLSchemeParser.action(for: url) == nil)
    }
}
```

- [ ] **Step 2: Test laufen lassen, um das Fehlschlagen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoURLSchemeParserTests`
Expected: FAIL — `Cannot find 'FeedivoURLSchemeParser' in scope` (bzw. `FeedivoURLSchemeAction`)

- [ ] **Step 3: Implementiere die minimale Parsing-Logik**

Erstelle `Feedivo/Services/FeedivoURLSchemeParser.swift`:

```swift
import Foundation

/// Ergebnis des Parsens einer `feedivo://`-Deep-Link-URL (Feature 23.2).
enum FeedivoURLSchemeAction: Equatable {
    case addFeed(urlString: String)
    case openArticle(articleID: UUID)
}

/// Reine Parsing-Logik für das `feedivo://`-URL-Schema. Kein SwiftUI-/App-
/// Bezug, dadurch isoliert unit-testbar. Unbekannte Hosts oder fehlende/
/// kaputte Query-Parameter liefern `nil` — der Aufrufer ignoriert die URL
/// dann still (kein Alert, kein Crash).
enum FeedivoURLSchemeParser {
    static func action(for url: URL) -> FeedivoURLSchemeAction? {
        guard url.scheme == "feedivo",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        switch url.host {
        case "add":
            guard let feedURLString = components.queryItems?.first(where: { $0.name == "url" })?.value,
                  !feedURLString.isEmpty
            else {
                return nil
            }

            return .addFeed(urlString: feedURLString)

        case "article":
            guard let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
                  let articleID = UUID(uuidString: idString)
            else {
                return nil
            }

            return .openArticle(articleID: articleID)

        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Test laufen lassen, um das Bestehen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoURLSchemeParserTests`
Expected: PASS (7 Tests grün)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/FeedivoURLSchemeParser.swift FeedivoTests/FeedivoURLSchemeParserTests.swift
git commit -m "URL-Schema: FeedivoURLSchemeParser für feedivo://add und feedivo://article"
```

---

### Task 2: `feedivo://`-URL-Schema im Xcode-Projekt registrieren

> **Korrigiert nach fehlgeschlagenem erstem Implementierungsversuch (2026-07-09):**
> Der ursprünglich geplante Ansatz — `INFOPLIST_KEY_CFBundleURLTypes` als reines
> Build-Setting bei `GENERATE_INFOPLIST_FILE = YES` — baut zwar erfolgreich,
> registriert den Schlüssel aber NICHT im generierten Info.plist (empirisch
> verifiziert: `xcodebuild -showBuildSettings -json` zeigt, dass der äußere
> Array-Wrapper beim Auswerten verloren geht; bekannte Xcode-Einschränkung,
> `INFOPLIST_KEY_*`-Synthese unterstützt nur Skalar-Werte, keine
> Array-of-Dictionary-Strukturen wie `CFBundleURLTypes`). Der folgende,
> korrigierte Ansatz (physische `Info.plist`-Datei) wurde vom Controller selbst
> gebaut, verifiziert (Debug + Release, inkl. `plutil`-Check des tatsächlich
> generierten Info.plist) und funktioniert nachweislich.

**Files:**
- Create: `Feedivo/Info.plist`
- Modify: `Feedivo.xcodeproj/project.pbxproj` (Debug + Release Build-Konfiguration des Haupt-Targets `Feedivo`, Bundle-ID `ch.martin.Feedivo` — NICHT die Test-Targets; zusätzlich eine `PBXFileSystemSynchronizedBuildFileExceptionSet`, die `Info.plist` von der Resources-Build-Phase ausschließt)

**Interfaces:**
- Konsumiert von Task 3/4: macOS aktiviert/startet Feedivo automatisch bei jedem `feedivo://…`-Aufruf und liefert die URL an `.onOpenURL`.

- [ ] **Step 1: Physische `Info.plist` anlegen**

Erstelle `Feedivo/Info.plist` mit exakt diesem Inhalt (reproduziert 1:1 die
bisher automatisch generierten Basis-Schlüssel — verifiziert per `plutil -p`
gegen das vorher generierte Info.plist — plus dem neuen `CFBundleURLTypes`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLName</key>
			<string>ch.martin.Feedivo</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>feedivo</string>
			</array>
		</dict>
	</array>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
	<key>LSMinimumSystemVersion</key>
	<string>$(MACOSX_DEPLOYMENT_TARGET)</string>
	<key>NSHumanReadableCopyright</key>
	<string></string>
</dict>
</plist>
```

- [ ] **Step 2: Build-Settings in `project.pbxproj` umstellen**

Die beiden betroffenen Blöcke (Debug-Konfiguration `C9CE9279`, Release-
Konfiguration `C9CE927A`, Haupt-Target `Feedivo`) enthalten aktuell identisch:

```
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
```

Ersetze **beide** Vorkommen (per `replace_all` — der Text ist in beiden
Konfigurationen exakt gleich und kommt in den Test-Targets nicht vor, da
`INFOPLIST_KEY_NSHumanReadableCopyright` nur im Haupt-Target existiert) durch:

```
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Feedivo/Info.plist;
```

- [ ] **Step 3: `Info.plist` von der Resources-Build-Phase ausschließen**

Da `Feedivo/Info.plist` innerhalb des file-system-synchronisierten Ordners
`Feedivo` liegt, würde Xcode es sonst zusätzlich als gewöhnliche Ressource in
die App kopieren (führt zu einer Build-Warnung + einer überflüssigen zweiten
Kopie unter `Contents/Resources/Info.plist`). Füge dazu ein neues
`PBXFileSystemSynchronizedBuildFileExceptionSet`-Objekt hinzu.

Direkt vor `/* Begin PBXFileSystemSynchronizedRootGroup section */` einfügen
(wähle eine neue, im Projekt noch nicht verwendete 24-stellige Hex-ID anstelle
von `<NEUE_ID>`):

```
/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		<NEUE_ID> /* Exceptions for "Feedivo" folder in "Feedivo" target */ = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
			);
			target = C9CE92562FE5A90700B9C79A /* Feedivo */;
		};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

```

Und den bestehenden Root-Group-Block

```
		C9CE92592FE5A90700B9C79A /* Feedivo */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Feedivo;
			sourceTree = "<group>";
		};
```

ersetzen durch (mit derselben neuen ID):

```
		C9CE92592FE5A90700B9C79A /* Feedivo */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				<NEUE_ID> /* Exceptions for "Feedivo" folder in "Feedivo" target */,
			);
			path = Feedivo;
			sourceTree = "<group>";
		};
```

- [ ] **Step 4: Clean-Build ausführen (Debug + Release)**

Run:
```bash
xcodebuild clean -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -30
xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -configuration Release 2>&1 | tail -10
```
Expected: beide `** BUILD SUCCEEDED **`, keine Warnung mehr zu
"Copy Bundle Resources build phase contains this target's Info.plist file".

- [ ] **Step 5: Registrierung im generierten Info.plist verifizieren + keine Doppel-Ressource**

Run:
```bash
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Feedivo.app" -newer Feedivo.xcodeproj/project.pbxproj 2>/dev/null | head -1)
plutil -p "$APP_PATH/Contents/Info.plist" | grep -A8 CFBundleURLTypes
ls "$APP_PATH/Contents/Resources/" | grep -i info || echo "OK: kein Info.plist in Resources"
```
Expected: Ausgabe enthält `"CFBundleURLSchemes"` mit `"feedivo"` als Eintrag,
UND die zweite Zeile druckt `OK: kein Info.plist in Resources` (kein
Duplikat). Falls `$APP_PATH` leer ist: `xcodebuild build` erneut mit
`-derivedDataPath build` laufen lassen und stattdessen
`build/Build/Products/Debug/Feedivo.app/Contents/Info.plist` prüfen.

- [ ] **Step 6: Bestehende Scene-Configuration-Tests laufen lassen (Regressions-Check)**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests 2>&1 | grep "failed on"`
Expected: Es dürfen keine ZUSÄTZLICHEN Fehlschläge auftreten gegenüber einem
Lauf auf dem Stand vor dieser Änderung (bekannte, vorbestehende Flakiness in
dieser Suite ist dokumentiert, siehe CLAUDE.md „Bekannte Gotchas"). Bei
Zweifel: `git stash`, denselben Testlauf auf dem unveränderten Stand
wiederholen, Fehlschlag-Menge vergleichen, dann `git stash pop`.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Info.plist Feedivo.xcodeproj/project.pbxproj
git commit -m "URL-Schema: feedivo:// via physischer Info.plist registriert"
```

---

### Task 3: AddFeedSheet-Vorbefüllung + ContentView-Routing

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift:811-895` (`AddFeedSheet`)
- Modify: `Feedivo/Views/ContentView.swift` (State, `.sheet`, `.onOpenURL`, `requestAddFeed`)

**Interfaces:**
- Consumes: `FeedivoURLSchemeAction` (Task 1), `ArticleWindowRequest` (bestehend, `Feedivo/Views/Reader/ArticleWindowView.swift`)
- Produces: `AddFeedSheet.init(initialURLString: String? = nil)`

- [ ] **Step 1: `AddFeedSheet` um Vorbefüllung + Auto-Start erweitern**

In `Feedivo/Views/Sidebar/SidebarView.swift`, ändere die State-Deklaration von

```swift
    @State private var urlString = ""
```

zu

```swift
    @State private var urlString: String
```

und ergänze direkt nach `private let discoveryService = FeedDiscoveryService()`:

```swift
    // Aktiviert von einem feedivo://add?url=...-Deep-Link (Feature 23.2):
    // startet die Vorschau automatisch, ohne dass der Nutzer erneut auf
    // "Suchen" klicken muss. Beim normalen, manuellen Öffnen (Sidebar-Button)
    // bleibt der Ablauf unverändert (false).
    private let shouldAutoStartDiscovery: Bool

    init(initialURLString: String? = nil) {
        self._urlString = State(initialValue: initialURLString ?? "")
        self.shouldAutoStartDiscovery = !(initialURLString ?? "").isEmpty
    }
```

Ändere `.onAppear` von

```swift
        .onAppear {
            loadAvailableFolderNames()
        }
```

zu

```swift
        .onAppear {
            loadAvailableFolderNames()

            if shouldAutoStartDiscovery {
                Task {
                    await performPrimaryAction()
                }
            }
        }
```

- [ ] **Step 2: Build ausführen (Compile-Check für Schritt 1)**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: `ContentView` um `.onOpenURL`-Routing erweitern**

In `Feedivo/Views/ContentView.swift`, ergänze nach der bestehenden Zeile
`@State private var isShowingAddFeedSheet = false`:

```swift
    @State private var pendingAddFeedURLString: String?
```

Ändere den bestehenden Sheet-Aufruf

```swift
        .sheet(isPresented: $isShowingAddFeedSheet) {
            AddFeedSheet()
        }
```

zu

```swift
        .sheet(isPresented: $isShowingAddFeedSheet) {
            AddFeedSheet(initialURLString: pendingAddFeedURLString)
        }
```

Ergänze direkt danach (vor `.sheet(isPresented: $isShowingOPMLImportReview)`)
den neuen Modifier:

```swift
        .onOpenURL(perform: handleOpenURL)
```

Ändere `requestAddFeed()` von

```swift
    private func requestAddFeed() {
        isShowingFirstRunWizard = false
        isShowingAddFeedSheet = true
    }
```

zu

```swift
    private func requestAddFeed() {
        isShowingFirstRunWizard = false
        pendingAddFeedURLString = nil
        isShowingAddFeedSheet = true
    }
```

Ergänze direkt danach die neue Handler-Funktion:

```swift
    // Feature 23.2: routet feedivo://-Deep-Links zum bestehenden Add-Feed-
    // Sheet bzw. öffnet ein Artikel-Popout-Fenster. Unbekannte/kaputte URLs
    // werden still ignoriert (kein Alert, kein Crash).
    private func handleOpenURL(_ url: URL) {
        guard let action = FeedivoURLSchemeParser.action(for: url) else {
            return
        }

        switch action {
        case .addFeed(let urlString):
            isShowingFirstRunWizard = false
            pendingAddFeedURLString = urlString
            isShowingAddFeedSheet = true

        case .openArticle(let articleID):
            openWindow(value: ArticleWindowRequest(articleID: articleID))
        }
    }
```

- [ ] **Step 4: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Bestehende AddFeedSheet-/ContentView-Tests laufen lassen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoURLSchemeParserTests`
Expected: PASS (keine Regression durch die Signatur-Änderung von `AddFeedSheet`)

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarView.swift Feedivo/Views/ContentView.swift
git commit -m "URL-Schema: AddFeedSheet-Vorbefüllung + ContentView onOpenURL-Routing"
```

---

### Task 4: Manuelle End-to-End-Verifikation + FEATURES.md-Status-Update

**Files:**
- Modify: `FEATURES.md:897-919` (Abschnitt 23.2, Status auf ✔️ Fertig)

**Interfaces:**
- Consumes: fertig gebaute Feedivo.app aus Task 1–3

- [ ] **Step 1: App starten und `feedivo://add` manuell testen**

Baue und starte die App (`xcodebuild build` + `open` auf den `.app`-Pfad aus
Task 2, Step 3, oder direkt über Xcode). Bei laufender App im Terminal:

```bash
open "feedivo://add?url=https://daringfireball.net/feeds/main"
```

Expected: Feedivo kommt in den Vordergrund, das Add-Feed-Sheet öffnet sich mit
vorausgefüllter URL, die Vorschau (Titel/Icon/Artikel) erscheint automatisch
ohne weiteren Klick.

- [ ] **Step 2: `feedivo://add` bei nicht laufender App testen**

App beenden (Cmd+Q), dann erneut:

```bash
open "feedivo://add?url=https://daringfireball.net/feeds/main"
```

Expected: macOS startet Feedivo neu, danach identisches Verhalten wie in Step 1.

- [ ] **Step 3: `feedivo://article` manuell testen**

Hole eine echte Artikel-ID aus der lokalen Datenbank:

```bash
sqlite3 ~/Library/Containers/ch.martin.Feedivo/Data/Library/Application\ Support/*.sqlite "SELECT id FROM articles LIMIT 1;"
```

(Pfad ggf. anpassen — siehe `FeedivoDatabaseLocation.databaseURL()` für den
exakten Speicherort.) Dann bei laufender App:

```bash
open "feedivo://article?id=<eingesetzte-uuid>"
```

Expected: Ein neues Artikel-Popout-Fenster öffnet sich mit dem Artikel.

- [ ] **Step 4: Fehlerfälle manuell prüfen**

```bash
open "feedivo://unknown?foo=bar"
open "feedivo://article?id=not-a-uuid"
```

Expected: Feedivo aktiviert sich (macOS-Standardverhalten bei URL-Öffnung),
aber es passiert sonst nichts — kein Crash, kein Alert, keine neue Sheet/Fenster.

- [ ] **Step 5: FEATURES.md Status aktualisieren**

Öffne `FEATURES.md`, Abschnitt `### 23.2 URL-Schema (Deep Links)`. Ändere

```
- **Status:** ✅ Entschieden — bereit zur Implementierung
```

zu

```
- **Status:** ✔️ Fertig
```

und ergänze nach den bestehenden "Implementierungsdetails"-Bullets eine neue
Zeile:

```
- **Umgesetzt 2026-07-09:** `FeedivoURLSchemeParser`, `.onOpenURL`-Routing in
  `ContentView`, `AddFeedSheet`-Vorbefüllung mit Auto-Vorschau; manuell
  End-to-End getestet (App laufend + neu gestartet, gültige + ungültige URLs)
```

- [ ] **Step 6: Commit**

```bash
git add FEATURES.md
git commit -m "FEATURES.md: Feature 23.2 (URL-Schema) als erledigt markiert"
```
