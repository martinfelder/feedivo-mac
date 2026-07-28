# iCloud Sync Beta Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add iCloud Sync as a deliberate beta setting using SwiftData + CloudKit while preserving the existing local-store and In-Memory fallback behavior.

**Architecture:** Keep Feedivo's single SwiftData schema, but move container configuration into a small testable factory. The app reads a persisted beta toggle before building the `ModelContainer`; settings show the current launch mode, restart requirement, and database fallback errors.

**Tech Stack:** SwiftUI, SwiftData `ModelConfiguration`, CloudKit entitlements, Swift Testing, String Catalog localization.

---

## File Structure

- Create: `Feedivo/Services/CloudSyncSettings.swift`
  - Stores UserDefaults keys, CloudKit container identifier, and helper functions for the beta toggle.
- Create: `Feedivo/App/FeedivoModelContainerFactory.swift`
  - Owns `ModelConfiguration` creation for local, CloudKit, and In-Memory fallback modes.
- Modify: `Feedivo/App/FeedivoApp.swift`
  - Uses the factory, records launch sync state in `DatabaseLoadState`, and injects the load state into Settings.
- Modify: `Feedivo/Feedivo.entitlements`
  - Adds iCloud/CloudKit entitlements for `iCloud.ch.martin.Feedivo`.
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
  - Replaces the Sync placeholder with a beta toggle, status, and restart notice.
- Modify: `Feedivo/Resources/L10n.swift`
  - Adds typed localized keys for the Sync settings UI.
- Modify: `Feedivo/Resources/Localizable.xcstrings`
  - Adds German/English/French/Italian values for the new visible strings.
- Create: `FeedivoTests/CloudSyncSettingsTests.swift`
  - Tests keys, defaults, and UserDefaults helper behavior.
- Create: `FeedivoTests/FeedivoModelContainerFactoryTests.swift`
  - Tests local, CloudKit, and fallback configuration without creating a real CloudKit-backed database.
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`
  - Adds source-level checks for app wiring and settings UI wiring.
- Modify: `FEATURES.md`
  - Moves Feature 6.1 from postponed to in progress beta.
- Modify: `AGENTS.md`
  - Updates project memory, ADR/gotchas, and current work.

---

### Task 1: Add Cloud Sync Settings Keys

**Files:**
- Create: `Feedivo/Services/CloudSyncSettings.swift`
- Create: `FeedivoTests/CloudSyncSettingsTests.swift`

- [ ] **Step 1: Write the failing settings tests**

Create `FeedivoTests/CloudSyncSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct CloudSyncSettingsTests {
    @Test func defaultsSindBewusstAus() {
        #expect(CloudSyncSettings.isEnabledKey == "cloudSync.isEnabled")
        #expect(CloudSyncSettings.defaultIsEnabled == false)
        #expect(CloudSyncSettings.cloudKitContainerIdentifier == "iCloud.ch.martin.Feedivo")
    }

    @Test func isEnabledLiestGespeichertenWert() {
        let defaults = UserDefaults(suiteName: "CloudSyncSettingsTests.isEnabled")!
        defaults.removePersistentDomain(forName: "CloudSyncSettingsTests.isEnabled")

        #expect(CloudSyncSettings.isEnabled(in: defaults) == false)

        defaults.set(true, forKey: CloudSyncSettings.isEnabledKey)

        #expect(CloudSyncSettings.isEnabled(in: defaults) == true)
    }

    @Test func statusTextBeschreibtLaunchZustand() {
        #expect(
            CloudSyncSettings.statusText(
                isEnabledAtLaunch: false,
                currentIsEnabled: false,
                hasDatabaseError: false
            ) == "Lokal gespeichert"
        )
        #expect(
            CloudSyncSettings.statusText(
                isEnabledAtLaunch: false,
                currentIsEnabled: true,
                hasDatabaseError: false
            ) == "iCloud Sync nach Neustart aktiv"
        )
        #expect(
            CloudSyncSettings.statusText(
                isEnabledAtLaunch: true,
                currentIsEnabled: true,
                hasDatabaseError: false
            ) == "iCloud Sync aktiv"
        )
        #expect(
            CloudSyncSettings.statusText(
                isEnabledAtLaunch: true,
                currentIsEnabled: true,
                hasDatabaseError: true
            ) == "Datenbank konnte nicht geladen werden"
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncSettingsTests
```

Expected: FAIL because `CloudSyncSettings` does not exist.

- [ ] **Step 3: Implement `CloudSyncSettings`**

Create `Feedivo/Services/CloudSyncSettings.swift`:

```swift
import Foundation

enum CloudSyncSettings {
    static let isEnabledKey = "cloudSync.isEnabled"
    static let defaultIsEnabled = false
    static let cloudKitContainerIdentifier = "iCloud.ch.martin.Feedivo"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isEnabledKey) != nil else {
            return defaultIsEnabled
        }

        return defaults.bool(forKey: isEnabledKey)
    }

    static func statusText(
        isEnabledAtLaunch: Bool,
        currentIsEnabled: Bool,
        hasDatabaseError: Bool
    ) -> String {
        if hasDatabaseError {
            return "Datenbank konnte nicht geladen werden"
        }

        if isEnabledAtLaunch == currentIsEnabled {
            return isEnabledAtLaunch ? "iCloud Sync aktiv" : "Lokal gespeichert"
        }

        return currentIsEnabled
            ? "iCloud Sync nach Neustart aktiv"
            : "iCloud Sync nach Neustart deaktiviert"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncSettingsTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/CloudSyncSettings.swift FeedivoTests/CloudSyncSettingsTests.swift
git commit -m "feat: add cloud sync settings"
```

---

### Task 2: Add Testable Model Container Factory

**Files:**
- Create: `Feedivo/App/FeedivoModelContainerFactory.swift`
- Create: `FeedivoTests/FeedivoModelContainerFactoryTests.swift`

- [ ] **Step 1: Write the failing factory tests**

Create `FeedivoTests/FeedivoModelContainerFactoryTests.swift`:

```swift
import SwiftData
import Testing
@testable import Feedivo

struct FeedivoModelContainerFactoryTests {
    @Test func localConfigurationVerwendetKeinCloudKit() {
        let configuration = FeedivoModelContainerFactory.persistentConfiguration(
            schema: Schema([Feed.self]),
            isCloudSyncEnabled: false
        )

        #expect(configuration.isStoredInMemoryOnly == false)
        #expect(configuration.cloudKitDatabase == .none)
    }

    @Test func cloudConfigurationVerwendetPrivateCloudKitDatenbank() {
        let configuration = FeedivoModelContainerFactory.persistentConfiguration(
            schema: Schema([Feed.self]),
            isCloudSyncEnabled: true
        )

        #expect(configuration.isStoredInMemoryOnly == false)
        #expect(configuration.cloudKitDatabase != .none)
        #expect(configuration.cloudKitContainerIdentifier == CloudSyncSettings.cloudKitContainerIdentifier)
    }

    @Test func fallbackConfigurationBleibtImmerInMemoryUndCloudKitFrei() {
        let configuration = FeedivoModelContainerFactory.inMemoryFallbackConfiguration()

        #expect(configuration.isStoredInMemoryOnly == true)
        #expect(configuration.cloudKitDatabase == .none)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoModelContainerFactoryTests
```

Expected: FAIL because `FeedivoModelContainerFactory` does not exist.

- [ ] **Step 3: Implement the factory**

Create `Feedivo/App/FeedivoModelContainerFactory.swift`:

```swift
import SwiftData

enum FeedivoModelContainerFactory {
    static func persistentConfiguration(
        schema: Schema,
        isCloudSyncEnabled: Bool
    ) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            cloudKitDatabase: isCloudSyncEnabled
                ? .private(CloudSyncSettings.cloudKitContainerIdentifier)
                : .none
        )
    }

    static func inMemoryFallbackConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
    }

    static func makePersistentContainer(
        schema: Schema,
        isCloudSyncEnabled: Bool
    ) throws -> ModelContainer {
        let configuration = persistentConfiguration(
            schema: schema,
            isCloudSyncEnabled: isCloudSyncEnabled
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    static func makeInMemoryFallbackContainer(schema: Schema) -> ModelContainer {
        let configuration = inMemoryFallbackConfiguration()
        return try! ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoModelContainerFactoryTests
```

Expected: PASS. If `cloudKitContainerIdentifier` is `nil` for `.private(...)` in this SDK, change the assertion to `#expect(configuration.cloudKitDatabase != .none)` and document the SDK behavior in `AGENTS.md` during Task 6.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/App/FeedivoModelContainerFactory.swift FeedivoTests/FeedivoModelContainerFactoryTests.swift
git commit -m "feat: add model container factory"
```

---

### Task 3: Wire Cloud Sync Into App Startup

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [ ] **Step 1: Write failing app wiring tests**

Append these tests to `FeedivoTests/FeedivoAppSceneConfigurationTests.swift` before the helper methods:

```swift
    @Test func appUsesCloudSyncSettingsForModelContainer() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)

        #expect(appSource.contains("CloudSyncSettings.isEnabled()"))
        #expect(appSource.contains("FeedivoModelContainerFactory.makePersistentContainer"))
        #expect(appSource.contains("FeedivoModelContainerFactory.makeInMemoryFallbackContainer"))
        #expect(appSource.contains("databaseLoadState.isCloudSyncEnabledAtLaunch"))
    }

    @Test func settingsSceneReceivesDatabaseLoadState() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)

        let settingsScene = try #require(appSource.range(of: "Settings {"))
        let settingsSource = appSource[settingsScene.lowerBound...]

        #expect(settingsSource.contains(".environment(databaseLoadState)"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/appUsesCloudSyncSettingsForModelContainer -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/settingsSceneReceivesDatabaseLoadState
```

Expected: FAIL because the app still creates the container inline and Settings does not receive `databaseLoadState`.

- [ ] **Step 3: Update app initialization**

In `Feedivo/App/FeedivoApp.swift`, replace this block:

```swift
        do {
            // Normalfall: on-disk-Container für die persistente Datenbank.
            loadedContainer = try ModelContainer(for: Self.schema)
        } catch {
            // Lässt sich die Datenbank nicht öffnen (z. B. beschädigt oder
            // inkompatibles Schema nach einem Update), stürzen wir nicht mehr
            // per `try!` ohne Erklärung ab. Stattdessen starten wir mit einem
            // leeren In-Memory-Container, damit die App benutzbar bleibt, und
            // zeigen den Fehler in der UI als Alarm an (M11). Die echten Daten
            // bleiben unangetastet auf der Platte und sind nach einem Neustart
            // (oder nach Reparatur) wieder verfügbar.
            let inMemoryConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
            // In-Memory-Konfiguration ohne Datei-Backing kann nicht fehlschlagen.
            loadedContainer = try! ModelContainer(for: Self.schema, configurations: [inMemoryConfiguration])
            loadError = error.localizedDescription
        }
```

with:

```swift
        let cloudSyncIsEnabled = CloudSyncSettings.isEnabled()

        do {
            // Normalfall: persistenter Store. Je nach Beta-Schalter lokal oder
            // mit CloudKit-Konfiguration; der Schalter wirkt beim App-Start.
            loadedContainer = try FeedivoModelContainerFactory.makePersistentContainer(
                schema: Self.schema,
                isCloudSyncEnabled: cloudSyncIsEnabled
            )
        } catch {
            // Lässt sich die Datenbank nicht öffnen (z. B. beschädigt,
            // inkompatibles Schema oder CloudKit-Konfigurationsproblem), stürzen
            // wir nicht ohne Erklärung ab. Stattdessen startet Feedivo mit einem
            // leeren In-Memory-Container; die echten Daten bleiben unangetastet.
            loadedContainer = FeedivoModelContainerFactory.makeInMemoryFallbackContainer(
                schema: Self.schema
            )
            loadError = error.localizedDescription
        }
```

After:

```swift
        self.databaseLoadState.initializationError = loadError
```

add:

```swift
        self.databaseLoadState.isCloudSyncEnabledAtLaunch = cloudSyncIsEnabled && loadError == nil
```

In the `Settings` scene, change:

```swift
            NewSettingsView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
```

to:

```swift
            NewSettingsView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(databaseLoadState)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
```

At the bottom, change `DatabaseLoadState` to:

```swift
@Observable
final class DatabaseLoadState {
    var initializationError: String?
    var isCloudSyncEnabledAtLaunch = false
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/appUsesCloudSyncSettingsForModelContainer -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/settingsSceneReceivesDatabaseLoadState
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/App/FeedivoApp.swift FeedivoTests/FeedivoAppSceneConfigurationTests.swift
git commit -m "feat: wire cloud sync app startup"
```

---

### Task 4: Add CloudKit Entitlements

**Files:**
- Modify: `Feedivo/Feedivo.entitlements`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [ ] **Step 1: Write failing entitlement source test**

Append this test to `FeedivoTests/FeedivoAppSceneConfigurationTests.swift` before the helper methods:

```swift
    @Test func entitlementsDeclareCloudKitContainer() throws {
        let projectRoot = projectRootURL()
        let entitlementsSource = try source(at: "Feedivo/Feedivo.entitlements", projectRoot: projectRoot)

        #expect(entitlementsSource.contains("com.apple.developer.icloud-services"))
        #expect(entitlementsSource.contains("<string>CloudKit</string>"))
        #expect(entitlementsSource.contains("com.apple.developer.icloud-container-identifiers"))
        #expect(entitlementsSource.contains("<string>iCloud.ch.martin.Feedivo</string>"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/entitlementsDeclareCloudKitContainer
```

Expected: FAIL because the entitlements do not declare CloudKit.

- [ ] **Step 3: Add the entitlement keys**

In `Feedivo/Feedivo.entitlements`, inside `<dict>`, after the app sandbox key/value pair, add:

```xml
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.ch.martin.Feedivo</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
	</array>
```

Keep these existing keys:

```xml
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/entitlementsDeclareCloudKitContainer
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Feedivo.entitlements FeedivoTests/FeedivoAppSceneConfigurationTests.swift
git commit -m "feat: add cloudkit entitlements"
```

---

### Task 5: Replace Sync Settings Placeholder

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [ ] **Step 1: Write failing settings UI source test**

Append this test to `FeedivoTests/FeedivoAppSceneConfigurationTests.swift` before the helper methods:

```swift
    @Test func syncSettingsExposeBetaToggleAndRestartHint() throws {
        let projectRoot = projectRootURL()
        let settingsSource = try source(at: "Feedivo/Views/Settings/SettingsView.swift", projectRoot: projectRoot)

        #expect(settingsSource.contains("@Environment(DatabaseLoadState.self)"))
        #expect(settingsSource.contains("@AppStorage(CloudSyncSettings.isEnabledKey)"))
        #expect(settingsSource.contains("L10n.settingsSyncBetaTitle"))
        #expect(settingsSource.contains("L10n.settingsSyncRestartHint"))
        #expect(settingsSource.contains("CloudSyncSettings.statusText"))
        #expect(settingsSource.contains("Toggle(\"\", isOn: $cloudSyncIsEnabled)"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/syncSettingsExposeBetaToggleAndRestartHint
```

Expected: FAIL because the settings view still uses the unavailable placeholder.

- [ ] **Step 3: Add L10n keys**

In `Feedivo/Resources/L10n.swift`, below the existing sync keys:

```swift
    static let settingsSyncSection = LocalizedStringKey("settings.sync.section")
    static let settingsSyncDescription = LocalizedStringKey("settings.sync.description")
    static let settingsSyncUnavailableTitle = LocalizedStringKey("settings.sync.unavailable.title")
    static let settingsSyncUnavailableDescription = LocalizedStringKey("settings.sync.unavailable.description")
```

add:

```swift
    static let settingsSyncBetaTitle = LocalizedStringKey("settings.sync.beta.title")
    static let settingsSyncBetaDescription = LocalizedStringKey("settings.sync.beta.description")
    static let settingsSyncStatusTitle = LocalizedStringKey("settings.sync.status.title")
    static let settingsSyncRestartHint = LocalizedStringKey("settings.sync.restart.hint")
    static let settingsSyncDatabaseErrorHint = LocalizedStringKey("settings.sync.databaseError.hint")
```

In `Feedivo/Resources/Localizable.xcstrings`, add entries for these keys using the existing JSON structure:

```json
"settings.sync.beta.title" : {
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "iCloud Sync Beta" } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "iCloud Sync Beta" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Synchronisation iCloud bêta" } },
    "it" : { "stringUnit" : { "state" : "translated", "value" : "Sincronizzazione iCloud beta" } }
  }
},
"settings.sync.beta.description" : {
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Synchronisiert Feeds, Ordner, Tags, Regeln, intelligente Ordner und Artikelstatus über iCloud." } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Syncs feeds, folders, tags, rules, smart folders, and article status through iCloud." } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Synchronise les flux, dossiers, tags, règles, dossiers intelligents et l’état des articles via iCloud." } },
    "it" : { "stringUnit" : { "state" : "translated", "value" : "Sincronizza feed, cartelle, tag, regole, cartelle smart e stato degli articoli tramite iCloud." } }
  }
},
"settings.sync.status.title" : {
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Status" } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Status" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "État" } },
    "it" : { "stringUnit" : { "state" : "translated", "value" : "Stato" } }
  }
},
"settings.sync.restart.hint" : {
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Änderungen werden nach einem Neustart von Feedivo wirksam." } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Changes take effect after restarting Feedivo." } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Les changements prennent effet après le redémarrage de Feedivo." } },
    "it" : { "stringUnit" : { "state" : "translated", "value" : "Le modifiche hanno effetto dopo il riavvio di Feedivo." } }
  }
},
"settings.sync.databaseError.hint" : {
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Feedivo läuft gerade mit einer temporären leeren Datenbank. Der ursprüngliche Store bleibt auf der Platte." } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Feedivo is currently running with a temporary empty database. The original store remains on disk." } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Feedivo utilise actuellement une base de données temporaire vide. Le store d’origine reste sur le disque." } },
    "it" : { "stringUnit" : { "state" : "translated", "value" : "Feedivo sta usando un database temporaneo vuoto. Lo store originale resta sul disco." } }
  }
}
```

Preserve the existing top-level `version` and `sourceLanguage` fields.

- [ ] **Step 4: Replace `NewSyncSettingsView`**

In `Feedivo/Views/Settings/SettingsView.swift`, replace the current `NewSyncSettingsView` with:

```swift
private struct NewSyncSettingsView: View {
    @Environment(DatabaseLoadState.self) private var databaseLoadState

    @AppStorage(CloudSyncSettings.isEnabledKey)
    private var cloudSyncIsEnabled = CloudSyncSettings.defaultIsEnabled

    private var hasDatabaseError: Bool {
        databaseLoadState.initializationError != nil
    }

    private var statusText: String {
        CloudSyncSettings.statusText(
            isEnabledAtLaunch: databaseLoadState.isCloudSyncEnabledAtLaunch,
            currentIsEnabled: cloudSyncIsEnabled,
            hasDatabaseError: hasDatabaseError
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewSettingsBlock(eyebrow: L10n.settingsSyncSection) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "icloud")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.settingsSyncBetaTitle)
                                .font(.system(size: 14, weight: .semibold))
                            Text(L10n.settingsSyncBetaDescription)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    NewSettingRow(
                        title: L10n.settingsSyncBetaTitle,
                        description: L10n.settingsSyncRestartHint
                    ) {
                        Toggle("", isOn: $cloudSyncIsEnabled)
                            .toggleStyle(.switch)
                    }

                    NewInfoRow(
                        iconName: hasDatabaseError ? "exclamationmark.triangle" : "checkmark.icloud",
                        title: L10n.settingsSyncStatusTitle,
                        description: LocalizedStringKey(statusText)
                    )

                    if hasDatabaseError {
                        NewInfoRow(
                            iconName: "internaldrive",
                            title: L10n.settingsSyncStatusTitle,
                            description: L10n.settingsSyncDatabaseErrorHint
                        )
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/syncSettingsExposeBetaToggleAndRestartHint
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings FeedivoTests/FeedivoAppSceneConfigurationTests.swift
git commit -m "feat: add iCloud sync beta settings"
```

---

### Task 6: Update Roadmap and Project Memory

**Files:**
- Modify: `FEATURES.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Update `FEATURES.md`**

Replace Feature 6.1:

```markdown
### 6.1 Sync via CloudKit
- **Status:** ⏸️ Zurückgestellt — nach v1
- **Grund:** Core-Features haben Vorrang — nach v1
```

with:

```markdown
### 6.1 Sync via CloudKit
- **Status:** 🔨 In Arbeit — iCloud Sync Beta
- **Ansatz:** SwiftData + CloudKit über eine bewusst aktivierbare Beta-Option in
  den Einstellungen.
- **Erster Umfang:** Feeds, Ordner, Tags, Regeln, intelligente Ordner und
  Artikelstatus. Große Offline-Inhalte, Cache-Dateien, Bilder/Favicons und
  Feed-Logs sind kein Produktversprechen der ersten Beta.
- **Hinweis:** Änderung des Sync-Schalters wird erst nach einem Neustart wirksam,
  weil der SwiftData-Container beim App-Start konfiguriert wird.
```

In `## Zurückgestellt (nach v1)`, remove:

```markdown
- **Feature 6.1** — iCloud Sync via CloudKit
```

- [ ] **Step 2: Update `AGENTS.md`**

In the technology stack row for iCloud Sync, change:

```markdown
| iCloud Sync | CloudKit via SwiftData | Nach v1 zurückgestellt; CloudKit-Vorbereitung erledigt |
```

to:

```markdown
| iCloud Sync | CloudKit via SwiftData | Beta in Arbeit; Aktivierung per Einstellung + Neustart |
```

In "Bekannte Gotchas & Fallstricke", update the iCloud capability bullet to:

```markdown
- **iCloud Capability:** Muss in Xcode Target → Signing & Capabilities aktiviert
  sein, plus CloudKit Container `iCloud.ch.martin.Feedivo` in developer.apple.com
  anlegen. Feedivo nutzt für die erste Beta SwiftData `ModelConfiguration` mit
  CloudKit und liest den Beta-Schalter beim App-Start; Umschalten benötigt einen
  Neustart.
```

Add a "Letzte Änderungen" entry near the existing dated entries:

```markdown
- 2026-07-01: iCloud Sync wieder aufgenommen: Entscheidung für Ansatz 1
  (SwiftData + CloudKit) als bewusst aktivierbare Beta. Erster Produktumfang ist
  Struktur- und Statussync; große Offline-Inhalte, Cache-Dateien und Feed-Logs
  bleiben außerhalb des ersten Sync-Versprechens.
```

- [ ] **Step 3: Review docs for stale contradiction**

Run:

```bash
rg -n "iCloud Sync.*zurückgestellt|CloudKit.*nach v1|Feature 6\\.1.*Zurückgestellt" AGENTS.md FEATURES.md
```

Expected: No stale statement claiming iCloud Sync is still postponed after v1. If the command returns historical archive notes that are explicitly dated as old context, leave them only if they cannot confuse the current roadmap; otherwise update the wording.

- [ ] **Step 4: Commit**

```bash
git add FEATURES.md AGENTS.md
git commit -m "docs: mark iCloud sync beta in progress"
```

---

### Task 7: Full Verification

**Files:**
- No source edits expected unless verification exposes a real issue.

- [ ] **Step 1: Run focused tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncSettingsTests -only-testing:FeedivoTests/FeedivoModelContainerFactoryTests -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests
```

Expected: PASS.

- [ ] **Step 2: Run the full test suite**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: PASS. Existing localization warnings about plural `%lld` may still appear; do not treat those as new failures unless the build exits non-zero.

- [ ] **Step 3: Inspect git diff**

Run:

```bash
git status --short
git diff --stat
```

Expected: Only intended files from this plan are modified, plus any pre-existing unrelated dirty files that were already present before implementation. Do not revert unrelated work.

- [ ] **Step 4: Manual Xcode capability note**

Open Xcode manually and confirm the target has iCloud/CloudKit enabled and the container `iCloud.ch.martin.Feedivo` exists in the Apple Developer account. This cannot be fully proven by unit tests because provisioning and developer portal state are outside the repo.

- [ ] **Step 5: Final commit if verification required fixes**

If verification required any fixes, commit them:

```bash
git add <fixed-files>
git commit -m "fix: stabilize iCloud sync beta wiring"
```

---

## Self-Review

- Spec coverage: The plan covers settings, model-container configuration, entitlements, error fallback, tests, and documentation from the approved spec.
- Placeholder scan: No task contains unresolved placeholder markers. The only conditional branch is the explicit SDK behavior check for `cloudKitContainerIdentifier`.
- Type consistency: `CloudSyncSettings`, `FeedivoModelContainerFactory`, and `DatabaseLoadState.isCloudSyncEnabledAtLaunch` are introduced before later tasks reference them.
- Scope check: The plan intentionally does not split models, build custom CloudKit records, or implement live store switching; those are non-goals from the spec.
