# iCloud Sync zurücksetzen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zwei selbstbedienbare Reset-Optionen in den Sync-Einstellungen — ein "Soft Reset" (nur lokaler Sync-Zustand) und ein "Hard Reset" (zusätzlich die komplette CloudKit-Zone löschen und neu aufbauen), jeweils mit erklärendem Bestätigungsdialog.

**Architecture:** Zwei neue Methoden direkt auf `CloudSyncEngine` (`resetLocalState(database:userDefaults:)` und `resetCloudZoneAndLocalState(database:) async throws`), die auf neuen `deleteAll()`-Primitiven der bestehenden Stores (`CloudSyncPendingChangeStore`, `OrphanedArticleStatusUpdateStore`) und einer neuen `CloudSyncActivityStatus.reset()`-Methode aufbauen. UI-seitig zwei neue Buttons in `SyncSettingsView` (`Feedivo/Views/Settings/SettingsView.swift`) — normaler Bestätigungsdialog für den Soft Reset, ein Sheet mit Tipp-Bestätigung (`ZURÜCKSETZEN`) für den Hard Reset.

**Tech Stack:** Swift, GRDB (SQLite), CloudKit (`CKSyncEngine`/`CKContainer`), SwiftUI, Swift Testing (`@Test`/`#expect`, kein XCTest).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-25-icloud-sync-reset-design.md` — bei Widersprüchen zwischen Plan und Spec gilt die Spec.
- Kommentare im Code auf Deutsch (Projektkonvention).
- SDD läuft direkt auf `main`, kein Worktree (Nutzerpräferenz, siehe Memory `feedback-subagent-driven-dev-no-worktree`).
- `Localizable.xcstrings` NIEMALS per vollem `json.load`/`json.dump`-Roundtrip bearbeiten — nur textuelle Einfügung an einem stabilen Anker. Nach jedem Schritt, der diese Datei anfasst, `git diff --stat` prüfen: nur Insertions, keine/kaum Deletions.
- Jede neue `UserDefaults`-Zugriffsstelle bekommt einen injizierbaren `userDefaults: UserDefaults = .standard`-Parameter (Projektkonvention, siehe `CloudSyncSettings.isEnabled(in:)`, `CloudSyncActivityStatus.recordSuccess(at:userDefaults:)`), damit Tests eine isolierte `UserDefaults`-Suite statt `.standard` verwenden können.
- Das Bestätigungswort für den Hard Reset ist immer `ZURÜCKSETZEN` (fest, nicht lokalisiert) — Nutzervorgabe, unabhängig von der App-Sprache.
- `resetCloudZoneAndLocalState` (Hard Reset) ist NICHT sinnvoll automatisiert testbar (echter CloudKit-Netzwerkaufruf über einen laufenden `CKContainer`) — analog zu `CloudSyncEngine.start()`, das im gesamten Projekt ebenfalls keinen automatisierten Test hat. Verifikation dafür ist Build-Erfolg + die manuelle Live-Checkliste am Ende der Spec.
- Tests, die eine `CloudSyncEngine`-Instanz konstruieren oder ihre Instanzmethoden aufrufen, müssen `@MainActor` sein (`@MainActor final class CloudSyncEngine`) — siehe bestehendes Muster in `FeedivoTests/BackgroundRefreshServiceTests.swift`/`FeedViewModelTests.swift`.
- Migrationstests/Store-Tests nutzen `FeedivoDatabase.inMemoryForTests()`, keine echte Datei.
- Nach jeder Task: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'` muss `BUILD SUCCEEDED` melden.

---

### Task 1: Reset-Primitiven auf den bestehenden Stores

**Files:**
- Modify: `Feedivo/Stores/CloudSyncPendingChangeStore.swift`
- Modify: `Feedivo/Stores/OrphanedArticleStatusUpdateStore.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncActivityStatus.swift`
- Test: `FeedivoTests/CloudSyncPendingChangeStoreTests.swift`
- Test: `FeedivoTests/OrphanedArticleStatusUpdateStoreTests.swift`
- Test: `FeedivoTests/CloudSyncActivityStatusTests.swift`

**Interfaces:**
- Produces: `CloudSyncPendingChangeStore.deleteAll() throws`, `OrphanedArticleStatusUpdateStore.deleteAll() throws -> Int` (discardable), `CloudSyncActivityStatus.reset(userDefaults: UserDefaults = .standard)` — von Task 2 (`CloudSyncEngine.resetLocalState`) konsumiert.

- [ ] **Step 1: Write the failing test for `CloudSyncPendingChangeStore.deleteAll()`**

In `FeedivoTests/CloudSyncPendingChangeStoreTests.swift`, direkt vor der schließenden `}` der `struct CloudSyncPendingChangeStoreTests` (nach `pendingCountsGruppiertNachRecordType()`) einfügen:

```swift
    @Test func deleteAllLeertDieGesamteTabelle() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save)
        try store.enqueue(recordType: "Feed", recordName: "feed-1", changeType: .save)

        try store.deleteAll()

        #expect(try store.pendingChanges().isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests/deleteAllLeertDieGesamteTabelle -parallel-testing-enabled NO`
Expected: FAIL — "value of type 'CloudSyncPendingChangeStore' has no member 'deleteAll'"

- [ ] **Step 3: Implement `deleteAll()` auf `CloudSyncPendingChangeStore`**

In `Feedivo/Stores/CloudSyncPendingChangeStore.swift`, direkt nach `dequeue(recordName:)` (vor `pendingChanges()`) einfügen:

```swift
    /// Leert die komplette Warteschlange bedingungslos — genutzt vom iCloud-Sync-Reset
    /// (`CloudSyncEngine.resetLocalState`), der alle ausstehenden Änderungen verwirft, bevor ein
    /// vollständiger Backfill sie neu einreiht.
    func deleteAll() throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM cloud_sync_pending_changes")
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests/deleteAllLeertDieGesamteTabelle -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Write the failing test for `OrphanedArticleStatusUpdateStore.deleteAll()`**

In `FeedivoTests/OrphanedArticleStatusUpdateStoreTests.swift`, direkt vor der schließenden `}` der `struct OrphanedArticleStatusUpdateStoreTests` einfügen:

```swift
    @Test func deleteAllLeertDieGesamteTabelleUnabhaengigVomAlter() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = OrphanedArticleStatusUpdateStore(database: database)
        try database.write { db in
            var eintrag = OrphanedArticleStatusUpdateRecord(
                articleID: "artikel-1",
                isRead: true,
                isStarred: false,
                readAt: Date(),
                starredAt: nil,
                receivedAt: Date()
            )
            try eintrag.insert(db)
        }

        let deletedCount = try store.deleteAll()

        #expect(deletedCount == 1)
        let remaining = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchAll(db)
        }
        #expect(remaining.isEmpty)
    }
```

- [ ] **Step 6: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/OrphanedArticleStatusUpdateStoreTests/deleteAllLeertDieGesamteTabelleUnabhaengigVomAlter -parallel-testing-enabled NO`
Expected: FAIL — "value of type 'OrphanedArticleStatusUpdateStore' has no member 'deleteAll'"

- [ ] **Step 7: Implement `deleteAll()` auf `OrphanedArticleStatusUpdateStore`**

In `Feedivo/Stores/OrphanedArticleStatusUpdateStore.swift`, direkt nach `deleteOlderThan(_:)` (vor der schließenden `}` des Structs) einfügen:

```swift

    /// Leert die komplette Tabelle bedingungslos, unabhängig vom Alter — genutzt vom
    /// iCloud-Sync-Reset (`CloudSyncEngine.resetLocalState`), der alle bereits als unzustellbar
    /// erkannten Artikelstatus-Einträge verwirft, statt auf die reguläre 90-Tage-Frist
    /// (`deleteOlderThan(_:)`) zu warten.
    @discardableResult
    func deleteAll() throws -> Int {
        try database.write { db in
            try db.execute(sql: "DELETE FROM orphaned_article_status_updates")
            return db.changesCount
        }
    }
```

- [ ] **Step 8: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/OrphanedArticleStatusUpdateStoreTests/deleteAllLeertDieGesamteTabelleUnabhaengigVomAlter -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 9: Write the failing test for `CloudSyncActivityStatus.reset()`**

In `FeedivoTests/CloudSyncActivityStatusTests.swift`, direkt vor der schließenden `}` der `struct CloudSyncActivityStatusTests` (nach `recordSuccessNachRecordFailureSetztFehlerZurueck()`) einfügen:

```swift
    @Test func resetLoeschtAlleDreiKeysUndLiefertDanachWiederNilUeberall() throws {
        let defaults = try temporaryUserDefaults()
        CloudSyncActivityStatus.recordFailure("Netzwerkfehler", userDefaults: defaults)

        CloudSyncActivityStatus.reset(userDefaults: defaults)

        #expect(CloudSyncActivityStatus.lastRunAt(userDefaults: defaults) == nil)
        #expect(CloudSyncActivityStatus.lastRunSucceeded(userDefaults: defaults) == nil)
        #expect(CloudSyncActivityStatus.lastErrorMessage(userDefaults: defaults) == nil)
    }
```

- [ ] **Step 10: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncActivityStatusTests/resetLoeschtAlleDreiKeysUndLiefertDanachWiederNilUeberall -parallel-testing-enabled NO`
Expected: FAIL — "type 'CloudSyncActivityStatus' has no member 'reset'"

- [ ] **Step 11: Implement `reset(userDefaults:)` auf `CloudSyncActivityStatus`**

In `Feedivo/Services/CloudSync/CloudSyncActivityStatus.swift`, direkt nach `recordFailure(_:at:userDefaults:)` (vor der schließenden `}` des Enums) einfügen:

```swift

    /// Setzt den persistierten Sync-Aktivitätsstatus vollständig zurück — genutzt vom
    /// iCloud-Sync-Reset (`CloudSyncEngine.resetLocalState`), damit die Statusanzeige in den
    /// Einstellungen danach wieder "Noch nie synchronisiert" statt eines veralteten Standes
    /// zeigt.
    static func reset(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: lastRunDateKey)
        userDefaults.removeObject(forKey: statusKey)
        userDefaults.removeObject(forKey: lastErrorMessageKey)
    }
```

- [ ] **Step 12: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncActivityStatusTests/resetLoeschtAlleDreiKeysUndLiefertDanachWiederNilUeberall -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 13: Full build check**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 14: Commit**

```bash
git add Feedivo/Stores/CloudSyncPendingChangeStore.swift Feedivo/Stores/OrphanedArticleStatusUpdateStore.swift Feedivo/Services/CloudSync/CloudSyncActivityStatus.swift FeedivoTests/CloudSyncPendingChangeStoreTests.swift FeedivoTests/OrphanedArticleStatusUpdateStoreTests.swift FeedivoTests/CloudSyncActivityStatusTests.swift
git commit -m "Feature: deleteAll()-Primitiven für iCloud-Sync-Reset (Task 1)"
```

---

### Task 2: `CloudSyncEngine.resetLocalState(database:userDefaults:)` — Soft Reset

**Files:**
- Modify: `Feedivo/Services/CloudSync/CloudSyncEngine.swift:12-13` (Sichtbarkeit der beiden Keys)
- Modify: `Feedivo/Services/CloudSync/CloudSyncEngine.swift` (neue Methode nach `stop()`)
- Test: Create `FeedivoTests/CloudSyncEngineResetTests.swift`

**Interfaces:**
- Consumes: `CloudSyncPendingChangeStore.deleteAll()`, `OrphanedArticleStatusUpdateStore.deleteAll()`, `CloudSyncActivityStatus.reset(userDefaults:)` (Task 1); `CloudSyncSettings.isEnabled(in:)` (bereits vorhanden).
- Produces: `CloudSyncEngine.resetLocalState(database: FeedivoDatabase, userDefaults: UserDefaults = .standard)`, `CloudSyncEngine.stateSerializationKey`/`hasCreatedZoneKey` jetzt `internal` statt `private` — von Task 3 (Hard Reset) und der UI (Task 5) genutzt.

- [ ] **Step 1: Sichtbarkeit der beiden UserDefaults-Keys auf `internal` anheben**

In `Feedivo/Services/CloudSync/CloudSyncEngine.swift`, Zeilen 12-13:

```swift
    private static let stateSerializationKey = "cloudSync.stateSerialization"
    private static let hasCreatedZoneKey = "cloudSync.hasCreatedZone"
```

ersetzen durch:

```swift
    static let stateSerializationKey = "cloudSync.stateSerialization"
    static let hasCreatedZoneKey = "cloudSync.hasCreatedZone"
```

(Grund: `@testable import Feedivo` gewährt Tests Zugriff auf `internal`, nicht auf `private` — die neuen Reset-Tests müssen verifizieren können, dass diese beiden Keys nach einem Reset tatsächlich gelöscht wurden.)

- [ ] **Step 2: Write the failing test**

Create `FeedivoTests/CloudSyncEngineResetTests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import Feedivo

/// Tests für `CloudSyncEngine.resetLocalState`/`resetCloudZoneAndLocalState` (iCloud Sync
/// Reset-Feature, siehe docs/superpowers/specs/2026-07-25-icloud-sync-reset-design.md).
/// `resetCloudZoneAndLocalState` selbst ist hier bewusst NICHT automatisiert getestet — der
/// echte `CKContainer`-Netzwerkaufruf ist analog zu `CloudSyncEngine.start()` nicht sinnvoll
/// unit-testbar, siehe Global Constraints im Implementierungsplan.
@MainActor
struct CloudSyncEngineResetTests {
    @Test func resetLocalStateLoeschtLokalenZustandUndLaesstEngineAusWennSyncDeaktiviertIst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: CloudSyncEngine.hasCreatedZoneKey)
        defaults.set(Data([0x01, 0x02]), forKey: CloudSyncEngine.stateSerializationKey)
        defaults.set(false, forKey: CloudSyncSettings.isEnabledKey)

        try CloudSyncPendingChangeStore(database: database).enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save)
        try database.write { db in
            var eintrag = OrphanedArticleStatusUpdateRecord(
                articleID: "artikel-1",
                isRead: true,
                isStarred: false,
                readAt: Date(),
                starredAt: nil,
                receivedAt: Date()
            )
            try eintrag.insert(db)
        }
        CloudSyncActivityStatus.recordFailure("Alter Fehler", userDefaults: defaults)

        let engine = CloudSyncEngine(database: database)
        engine.resetLocalState(database: database, userDefaults: defaults)

        #expect(defaults.object(forKey: CloudSyncEngine.hasCreatedZoneKey) == nil)
        #expect(defaults.data(forKey: CloudSyncEngine.stateSerializationKey) == nil)
        #expect(try CloudSyncPendingChangeStore(database: database).pendingChanges().isEmpty)
        let remainingOrphans = try database.read { db in try OrphanedArticleStatusUpdateRecord.fetchAll(db) }
        #expect(remainingOrphans.isEmpty)
        #expect(CloudSyncActivityStatus.lastRunSucceeded(userDefaults: defaults) == nil)
        #expect(CloudSyncActivityStatus.lastErrorMessage(userDefaults: defaults) == nil)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.CloudSyncEngineReset.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncEngineResetTests -parallel-testing-enabled NO`
Expected: FAIL — "value of type 'CloudSyncEngine' has no member 'resetLocalState'"

- [ ] **Step 4: Implement `resetLocalState(database:userDefaults:)`**

In `Feedivo/Services/CloudSync/CloudSyncEngine.swift`, direkt nach `stop()` (vor `static func register(_:)`) einfügen:

```swift

    /// Setzt den kompletten lokalen Sync-Zustand zurück: laufende Engine anhalten, gespeicherten
    /// CKSyncEngine-Zustand + Zone-Erzeugt-Flag löschen, lokale Pending-Warteschlange und
    /// verwaiste Artikelstatus-Einträge leeren, persistenten Aktivitätsstatus zurücksetzen. Ist
    /// iCloud Sync aktiviert, wird die Engine anschließend neu gestartet — das löst automatisch
    /// einen vollständigen Backfill aus (`start()` ruft `backfillAllExistingRecords` bei jedem
    /// Start auf, kein einmaliges Flag), der alle lokalen Daten erneut als "zu senden" einreiht.
    /// Die CloudKit-Zone selbst bleibt dabei unangetastet — siehe
    /// `resetCloudZoneAndLocalState` für die zerstörerische Variante. Siehe Design-Spec
    /// docs/superpowers/specs/2026-07-25-icloud-sync-reset-design.md.
    func resetLocalState(database: FeedivoDatabase, userDefaults: UserDefaults = .standard) {
        stop()
        userDefaults.removeObject(forKey: Self.stateSerializationKey)
        userDefaults.removeObject(forKey: Self.hasCreatedZoneKey)

        do {
            try CloudSyncPendingChangeStore(database: database).deleteAll()
        } catch {
            AppLogger.dataAccess.error("iCloud Sync Reset: Pending-Warteschlange konnte nicht geleert werden: \(error.localizedDescription, privacy: .public)")
        }
        do {
            try OrphanedArticleStatusUpdateStore(database: database).deleteAll()
        } catch {
            AppLogger.dataAccess.error("iCloud Sync Reset: Verwaiste Artikelstatus-Einträge konnten nicht geleert werden: \(error.localizedDescription, privacy: .public)")
        }
        CloudSyncActivityStatus.reset(userDefaults: userDefaults)

        if CloudSyncSettings.isEnabled(in: userDefaults) {
            start()
        }
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncEngineResetTests -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 6: Full build check**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncEngine.swift FeedivoTests/CloudSyncEngineResetTests.swift
git commit -m "Feature: CloudSyncEngine.resetLocalState — Soft Reset für iCloud Sync (Task 2)"
```

---

### Task 3: `CloudSyncEngine.resetCloudZoneAndLocalState(database:)` — Hard Reset

**Files:**
- Modify: `Feedivo/Services/CloudSync/CloudSyncEngine.swift` (neue Methode nach `resetLocalState`)

**Interfaces:**
- Consumes: `resetLocalState(database:userDefaults:)` (Task 2), `CloudSyncTagMapping.zoneID()` (bereits vorhanden, liefert die gemeinsame `"FeedivoZone"`-`CKRecordZone.ID`), `CloudSyncSettings.cloudKitContainerIdentifier` (bereits vorhanden).
- Produces: `CloudSyncEngine.resetCloudZoneAndLocalState(database: FeedivoDatabase) async throws` — von der UI (Task 5) aufgerufen.

Kein automatisierter Test für diese Methode (siehe Global Constraints) — nur Implementierung + Build-Verifikation. Die manuelle Live-Verifikation steht am Ende der Spec.

- [ ] **Step 1: Implement `resetCloudZoneAndLocalState(database:)`**

In `Feedivo/Services/CloudSync/CloudSyncEngine.swift`, direkt nach der in Task 2 eingefügten `resetLocalState(database:userDefaults:)`-Methode (vor `static func register(_:)`) einfügen:

```swift

    /// Löscht zusätzlich zum lokalen Zustand (siehe `resetLocalState`) die komplette
    /// `FeedivoZone` in CloudKit und lässt sie beim nächsten `start()` komplett neu aus dem
    /// lokalen Stand aufbauen. Betrifft ALLE Geräte des Nutzers — jedes andere Gerät hat danach
    /// einen `stateSerialization`-Stand gegenüber einer nicht mehr existierenden Zone und muss
    /// sich beim nächsten eigenen Sync-Versuch eigenständig neu einrichten (siehe Design-Spec,
    /// Abschnitt "Hard Reset"). Schlägt der Netzwerkaufruf fehl (außer `.zoneNotFound`, das
    /// bereits eine gelöschte Zone bedeutet und deshalb kein Fehler ist), bleibt der lokale
    /// Zustand komplett unangetastet und die Engine wird wieder in ihren vorherigen Zustand
    /// versetzt, damit der Nutzer es erneut versuchen kann.
    func resetCloudZoneAndLocalState(database: FeedivoDatabase) async throws {
        let wasRunning = syncEngine != nil
        stop()

        let container = CKContainer(identifier: CloudSyncSettings.cloudKitContainerIdentifier)
        do {
            _ = try await container.privateCloudDatabase.deleteRecordZone(withID: CloudSyncTagMapping.zoneID())
        } catch let error as CKError where error.code == .zoneNotFound {
            // Zone existiert bereits nicht mehr (z. B. vorheriger Hard Reset ohne Neustart) —
            // aus Nutzersicht kein Fehler, einfach mit dem lokalen Reset fortfahren.
        } catch {
            if wasRunning {
                start()
            }
            throw error
        }

        resetLocalState(database: database)
    }
```

- [ ] **Step 2: Full build check**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncEngine.swift
git commit -m "Feature: CloudSyncEngine.resetCloudZoneAndLocalState — Hard Reset für iCloud Sync (Task 3)"
```

---

### Task 4: L10n-Keys + Localizable.xcstrings-Einträge

**Files:**
- Modify: `Feedivo/Resources/L10n.swift:446` (nach `settingsSyncActivityDetailsHide`)
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces: 11 neue `L10n`-Konstanten/Funktionen — von der UI (Task 5) konsumiert:
  `settingsSyncResetSection`, `settingsSyncResetSoftButton`, `settingsSyncResetSoftConfirmTitle`,
  `settingsSyncResetSoftConfirmMessage`, `settingsSyncResetHardButton`,
  `settingsSyncResetHardSheetTitle`, `settingsSyncResetHardWarning`,
  `settingsSyncResetHardConfirmFieldLabel`, `settingsSyncResetHardConfirmButton`,
  `settingsSyncResetSuccessMessage: String`, `settingsSyncResetErrorMessage(reason: String) -> String`.

- [ ] **Step 1: Neue `L10n`-Konstanten ergänzen**

In `Feedivo/Resources/L10n.swift`, Zeile 446 (`static let settingsSyncActivityDetailsHide = LocalizedStringKey("settings.sync.activity.detailsHide")`) — direkt danach einfügen:

```swift
    static let settingsSyncResetSection = LocalizedStringKey("settings.sync.reset.section")
    static let settingsSyncResetSoftButton = LocalizedStringKey("settings.sync.reset.soft.button")
    static let settingsSyncResetSoftConfirmTitle = LocalizedStringKey("settings.sync.reset.soft.confirmTitle")
    static let settingsSyncResetSoftConfirmMessage = LocalizedStringKey("settings.sync.reset.soft.confirmMessage")
    static let settingsSyncResetHardButton = LocalizedStringKey("settings.sync.reset.hard.button")
    static let settingsSyncResetHardSheetTitle = LocalizedStringKey("settings.sync.reset.hard.sheetTitle")
    static let settingsSyncResetHardWarning = LocalizedStringKey("settings.sync.reset.hard.warning")
    static let settingsSyncResetHardConfirmFieldLabel = LocalizedStringKey("settings.sync.reset.hard.confirmFieldLabel")
    static let settingsSyncResetHardConfirmButton = LocalizedStringKey("settings.sync.reset.hard.confirmButton")
    static let settingsSyncResetSuccessMessage = String(localized: "settings.sync.reset.successMessage")
    static func settingsSyncResetErrorMessage(reason: String) -> String {
        String.localizedStringWithFormat(String(localized: "settings.sync.reset.errorMessage"), reason)
    }
```

- [ ] **Step 2: Neue Katalogeinträge in `Localizable.xcstrings` ergänzen**

**Nicht per Skript mit `json.load`/`json.dump` bearbeiten** (formatiert die gesamte ~31000-Zeilen-Datei um, siehe Gotcha in CLAUDE.md). Stattdessen: die Datei an einem stabilen Textanker per gezieltem Such-Ersetzen erweitern.

Suche in `Feedivo/Resources/Localizable.xcstrings` nach dem exakten Block (bestehender letzter Eintrag der `settings.sync.*`-Gruppe):

```
    "settings.sync.activity.detailsHide" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Details ausblenden"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Hide details"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Masquer les détails"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nascondi dettagli"
          }
        }
      }
    },
```

Direkt danach (vor dem nächsten `"..." : {`-Eintrag) folgenden Block einfügen:

```
    "settings.sync.reset.section" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sync zurücksetzen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reset Sync"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Réinitialiser la synchronisation"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reimposta sincronizzazione"
          }
        }
      }
    },
    "settings.sync.reset.soft.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Lokalen Sync-Zustand zurücksetzen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reset Local Sync State"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Réinitialiser l'état de synchronisation local"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reimposta lo stato di sincronizzazione locale"
          }
        }
      }
    },
    "settings.sync.reset.soft.confirmTitle" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sync-Zustand zurücksetzen?"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reset Sync State?"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Réinitialiser l'état de synchronisation ?"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reimpostare lo stato di sincronizzazione?"
          }
        }
      }
    },
    "settings.sync.reset.soft.confirmMessage" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Setzt den Sync-Zustand auf diesem Gerät zurück und lädt alle lokalen Daten erneut zu iCloud hoch. Die iCloud-Daten selbst bleiben unverändert."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Resets the sync state on this device and re-uploads all local data to iCloud. The iCloud data itself remains unchanged."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Réinitialise l'état de synchronisation sur cet appareil et retélécharge toutes les données locales vers iCloud. Les données iCloud elles-mêmes restent inchangées."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reimposta lo stato di sincronizzazione su questo dispositivo e ricarica tutti i dati locali su iCloud. I dati su iCloud stessi rimangono invariati."
          }
        }
      }
    },
    "settings.sync.reset.hard.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "iCloud-Daten komplett zurücksetzen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Completely Reset iCloud Data"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Réinitialiser complètement les données iCloud"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reimposta completamente i dati iCloud"
          }
        }
      }
    },
    "settings.sync.reset.hard.sheetTitle" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "iCloud-Daten komplett zurücksetzen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Completely Reset iCloud Data"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Réinitialiser complètement les données iCloud"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reimposta completamente i dati iCloud"
          }
        }
      }
    },
    "settings.sync.reset.hard.warning" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Löscht sämtliche iCloud-Sync-Daten dieser App vollständig und baut sie danach komplett neu aus dem aktuellen Stand dieses Geräts auf. Das betrifft ALLE Geräte, auf denen iCloud Sync für Feedivo aktiviert ist — jedes andere Gerät muss sich danach eigenständig neu einrichten. Diese Aktion kann nicht rückgängig gemacht werden."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Completely deletes all of this app's iCloud sync data and rebuilds it from scratch using this device's current state. This affects ALL devices with iCloud Sync enabled for Feedivo — every other device will need to re-set itself up afterwards. This action cannot be undone."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Supprime entièrement toutes les données de synchronisation iCloud de cette application et les reconstruit à partir de l'état actuel de cet appareil. Cela concerne TOUS les appareils sur lesquels la synchronisation iCloud est activée pour Feedivo — chaque autre appareil devra se reconfigurer lui-même par la suite. Cette action est irréversible."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Elimina completamente tutti i dati di sincronizzazione iCloud di questa app e li ricostruisce da zero a partire dallo stato attuale di questo dispositivo. Questo riguarda TUTTI i dispositivi su cui la sincronizzazione iCloud è attiva per Feedivo: ogni altro dispositivo dovrà riconfigurarsi autonomamente in seguito. Questa azione non può essere annullata."
          }
        }
      }
    },
    "settings.sync.reset.hard.confirmFieldLabel" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Zum Bestätigen ZURÜCKSETZEN eingeben:"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Type ZURÜCKSETZEN to confirm:"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Tapez ZURÜCKSETZEN pour confirmer :"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Digita ZURÜCKSETZEN per confermare:"
          }
        }
      }
    },
    "settings.sync.reset.hard.confirmButton" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Endgültig zurücksetzen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reset Permanently"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Réinitialiser définitivement"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reimposta definitivamente"
          }
        }
      }
    },
    "settings.sync.reset.successMessage" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Zurückgesetzt."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reset complete."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Réinitialisation terminée."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reimpostazione completata."
          }
        }
      }
    },
    "settings.sync.reset.errorMessage" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Zurücksetzen fehlgeschlagen: %@"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reset failed: %@"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Échec de la réinitialisation : %@"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Reimpostazione non riuscita: %@"
          }
        }
      }
    },
```

- [ ] **Step 3: Diff-Stat-Kontrolle**

Run: `git diff --stat Feedivo/Resources/Localizable.xcstrings`
Expected: Nur Insertions (kein nennenswerter Deletion-Anteil — bestätigt, dass die Datei nicht versehentlich neu formatiert wurde).

- [ ] **Step 4: Full build check**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature: L10n-Keys für iCloud-Sync-Reset (Task 4)"
```

---

### Task 5: UI in `SyncSettingsView` — Buttons, Dialoge, Sheet

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (`SyncSettingsView`, neue private Structs)

**Interfaces:**
- Consumes: `CloudSyncEngine.resetLocalState(database:userDefaults:)` (Task 2), `CloudSyncEngine.resetCloudZoneAndLocalState(database:) async throws` (Task 3), alle `L10n.settingsSyncReset*`-Konstanten (Task 4), `L10n.commonCancel` (bereits vorhanden).

- [ ] **Step 1: Neue `@State`-Properties in `SyncSettingsView` ergänzen**

In `Feedivo/Views/Settings/SettingsView.swift`, in `SyncSettingsView` direkt nach `@State private var isSyncActivityDetailsExpanded = false` (Zeile 1071) einfügen:

```swift

    @State private var isResetting = false
    @State private var resetErrorMessage: String?
    @State private var resetSuccessMessage: String?
    @State private var isShowingSoftResetConfirmation = false
    @State private var isShowingHardResetSheet = false
    @State private var hardResetConfirmationText = ""
```

- [ ] **Step 2: Neuen "Sync zurücksetzen"-Block in `body` ergänzen**

In derselben Datei, in `SyncSettingsView.body`, den bestehenden Abschluss (nach der schließenden `}` von `CloudSyncActivityStatusBlock(...)`, vor der schließenden `}` des äußeren `SettingsBlock`) — der bestehende Code sieht so aus:

```swift
                    CloudSyncActivityStatusBlock(
                        cloudSyncIsEnabled: cloudSyncIsEnabled,
                        isAccountUnavailable: cloudSyncStatus.state == .accountUnavailable,
                        lastRunTimestamp: syncActivityLastRunTimestamp,
                        statusRaw: syncActivityStatusRaw,
                        errorMessage: syncActivityErrorMessage,
                        pendingCounts: syncActivityPendingCounts,
                        isDetailsExpanded: $isSyncActivityDetailsExpanded
                    )
                }
            }
        }
```

ersetzen durch:

```swift
                    CloudSyncActivityStatusBlock(
                        cloudSyncIsEnabled: cloudSyncIsEnabled,
                        isAccountUnavailable: cloudSyncStatus.state == .accountUnavailable,
                        lastRunTimestamp: syncActivityLastRunTimestamp,
                        statusRaw: syncActivityStatusRaw,
                        errorMessage: syncActivityErrorMessage,
                        pendingCounts: syncActivityPendingCounts,
                        isDetailsExpanded: $isSyncActivityDetailsExpanded
                    )
                }
            }

            SettingsBlock(eyebrow: L10n.settingsSyncResetSection) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Button(L10n.settingsSyncResetSoftButton) {
                            isShowingSoftResetConfirmation = true
                        }
                        .disabled(isResetting || feedivoDatabase == nil || cloudSyncEngine == nil)

                        Button(L10n.settingsSyncResetHardButton, role: .destructive) {
                            hardResetConfirmationText = ""
                            isShowingHardResetSheet = true
                        }
                        .disabled(isResetting || feedivoDatabase == nil || cloudSyncEngine == nil)

                        if isResetting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let resetErrorMessage {
                        Text(resetErrorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }

                    if let resetSuccessMessage {
                        Text(resetSuccessMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
```

- [ ] **Step 3: Confirmation-Dialog (Soft Reset) und Sheet (Hard Reset) an `body` anhängen**

In derselben Datei, direkt nach dem bestehenden `.onChange(of: syncActivityLastRunTimestamp) { ... }`-Block (vor der schließenden `}` von `var body: some View`) einfügen:

```swift
        .confirmationDialog(
            L10n.settingsSyncResetSoftConfirmTitle,
            isPresented: $isShowingSoftResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.settingsSyncResetSoftButton, role: .destructive) {
                performSoftReset()
            }
            Button(L10n.commonCancel, role: .cancel) {}
        } message: {
            Text(L10n.settingsSyncResetSoftConfirmMessage)
        }
        .sheet(isPresented: $isShowingHardResetSheet) {
            CloudSyncHardResetSheet(
                confirmationText: $hardResetConfirmationText,
                onConfirm: {
                    isShowingHardResetSheet = false
                    performHardReset()
                },
                onCancel: {
                    isShowingHardResetSheet = false
                }
            )
        }
```

- [ ] **Step 4: `performSoftReset()`/`performHardReset()` ergänzen**

In derselben Datei, direkt nach `loadSyncActivityPendingCounts()` (vor der schließenden `}` von `SyncSettingsView`) einfügen:

```swift

    private func performSoftReset() {
        guard let cloudSyncEngine, let feedivoDatabase else { return }
        isResetting = true
        resetErrorMessage = nil
        resetSuccessMessage = nil
        cloudSyncEngine.resetLocalState(database: feedivoDatabase)
        resetSuccessMessage = L10n.settingsSyncResetSuccessMessage
        loadSyncActivityPendingCounts()
        isResetting = false
    }

    private func performHardReset() {
        guard let cloudSyncEngine, let feedivoDatabase else { return }
        isResetting = true
        resetErrorMessage = nil
        resetSuccessMessage = nil
        Task {
            do {
                try await cloudSyncEngine.resetCloudZoneAndLocalState(database: feedivoDatabase)
                resetSuccessMessage = L10n.settingsSyncResetSuccessMessage
            } catch {
                resetErrorMessage = L10n.settingsSyncResetErrorMessage(reason: error.localizedDescription)
            }
            loadSyncActivityPendingCounts()
            isResetting = false
        }
    }
```

- [ ] **Step 5: Neue `CloudSyncHardResetSheet`-View ergänzen**

In derselben Datei, direkt vor `private struct CloudSyncActivityStatusBlock: View {` einfügen:

```swift
private struct CloudSyncHardResetSheet: View {
    @Binding var confirmationText: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private static let requiredConfirmationText = "ZURÜCKSETZEN"

    private var isConfirmEnabled: Bool {
        confirmationText == Self.requiredConfirmationText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.settingsSyncResetHardSheetTitle)
                .font(.system(size: 15, weight: .semibold))

            Text(L10n.settingsSyncResetHardWarning)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.settingsSyncResetHardConfirmFieldLabel)
                    .font(.system(size: 11, weight: .medium))

                TextField(Self.requiredConfirmationText, text: $confirmationText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button(L10n.commonCancel) {
                    onCancel()
                }
                Button(L10n.settingsSyncResetHardConfirmButton, role: .destructive) {
                    onConfirm()
                }
                .disabled(!isConfirmEnabled)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

```

- [ ] **Step 6: Full build check**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Gezielter Regressionslauf der berührten Test-Suiten**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests -only-testing:FeedivoTests/OrphanedArticleStatusUpdateStoreTests -only-testing:FeedivoTests/CloudSyncActivityStatusTests -only-testing:FeedivoTests/CloudSyncEngineResetTests -only-testing:FeedivoTests/CloudSyncSettingsTests -parallel-testing-enabled NO`
Expected: Alle PASS.

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift
git commit -m "Feature: Sync-zurücksetzen-UI in den Sync-Einstellungen (Task 5)"
```

---

## Nach Abschluss aller Tasks

Manuelle Live-Verifikationscheckliste (siehe Spec, Abschnitt "Manuelle Live-Verifikationscheckliste") durch den Nutzer durchgehen, bevor `CLAUDE.md` unter "Aktuell in Arbeit" als abgeschlossen vermerkt wird.
