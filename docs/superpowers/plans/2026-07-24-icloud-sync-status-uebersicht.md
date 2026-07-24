# iCloud Sync Status-Übersicht Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Der Sync-Tab in den Einstellungen zeigt einen neuen Status-Block: eine globale Statuszeile ("Synchron"/"Ausstehend (N)"/"Fehler: …" + letzter Zeitpunkt) plus eine aufklappbare Aufschlüsselung nach Datenart (Tags/Feeds/Ordner/Regeln/Intelligente Ordner).

**Architecture:** Neuer persistenter `CloudSyncActivityStatus` (UserDefaults, nach dem Muster von `ArticleRetentionSettings`/`BackgroundRefreshSettings`) wird in `CloudSyncEngine.handleEvent` bei jedem abgeschlossenen Sende-/Abrufversuch aktualisiert. Eine neue `CloudSyncPendingChangeStore.pendingCounts()`-Methode liefert live die Anzahl ausstehender Änderungen je `recordType`. Ein neues `CloudSyncActivityCategory`-Enum fasst die 7 rohen `recordType`-Werte zu 5 Anzeige-Kategorien zusammen. `SyncSettingsView` bindet den persistenten Status direkt per `@AppStorage` (automatische Reaktivität, kein manuelles Reload nötig) und lädt die Pending-Counts bei Erscheinen sowie bei Änderung von `SQLiteDataInvalidation.statusVersionKey` neu (bestehendes Muster aus `CleanupHistoryWindowView`).

**Tech Stack:** Swift, SwiftUI, GRDB (SQLite), CloudKit (`CKSyncEngine`), Swift Testing.

## Global Constraints

- Erfolgsdefinition ("Synchron"): Pending-Warteschlange aktuell vollständig leer UND letzter tatsächlicher Sende-/Abrufversuch war fehlerfrei.
- `.serverRecordChanged`-Konflikte zählen NICHT als Fehler (werden bereits automatisch aufgelöst, siehe bestehende `handleFailedSave`).
- Kategorien-Mapping (7 `recordType` → 5 Anzeige-Kategorien):

  | Kategorie | `recordType`(s) |
  |---|---|
  | Tags | `Tag` |
  | Feeds | `Feed` |
  | Ordner | `FeedFolder` |
  | Regeln | `Rule`, `RuleCondition` |
  | Intelligente Ordner | `SmartFolder`, `SmartFolderCondition` |

- Platzierung: Erweiterung des bestehenden Sync-Tabs (`SyncSettingsView` in `Feedivo/Views/Settings/SettingsView.swift`), kein neues Fenster.
- Bekannte, bewusst nicht behobene Limitation: Ein einzelner fehlgeschlagener eingehender Record bei `.fetchedRecordZoneChanges` wird weiterhin als "erfolgreich" gewertet, da `applyIncomingRecord`/`applyIncomingDeletion` Fehler pro Record bereits heute nur loggen, nicht weitermelden (bestehender Code, nicht Teil dieses Plans).
- Sprache für Code-Kommentare: Deutsch.
- Tests: Swift Testing (`@Test`/`#expect`), kein XCTest. Gezielt mit `-only-testing:FeedivoTests/<SuiteName>` laufen lassen, `-parallel-testing-enabled NO` bei mehreren Suiten gleichzeitig.
- `Localizable.xcstrings`-Ergänzungen NIEMALS per vollem `json.load`/`json.dump`-Roundtrip — nur als reine Text-Segment-Einfügung an einem stabilen Anker, danach `git diff --stat` prüfen (nur Insertions, keine/kaum Deletions).
- Design-Referenz: `docs/superpowers/specs/2026-07-24-icloud-sync-status-uebersicht-design.md`.

---

### Task 1: `CloudSyncActivityStatus` — persistenter Sync-Aktivitätsstatus

**Files:**
- Create: `Feedivo/Services/CloudSync/CloudSyncActivityStatus.swift`
- Test: `FeedivoTests/CloudSyncActivityStatusTests.swift`

**Interfaces:**
- Produces: `CloudSyncActivityStatus.recordSuccess(at:userDefaults:)`, `.recordFailure(_:at:userDefaults:)`, `.lastRunAt(userDefaults:) -> Date?`, `.lastRunSucceeded(userDefaults:) -> Bool?`, `.lastErrorMessage(userDefaults:) -> String?`, sowie die öffentlichen Keys `lastRunDateKey`, `statusKey`, `lastErrorMessageKey`, `statusSuccess`, `statusFailed` — genutzt von Task 4 (Engine-Wiring) und Task 5 (UI-Bindings via `@AppStorage`).

- [ ] **Step 1: Write the failing tests**

Erstelle `FeedivoTests/CloudSyncActivityStatusTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct CloudSyncActivityStatusTests {
    @Test func nochNieGelaufenLiefertNilUeberall() throws {
        let defaults = try temporaryUserDefaults()

        #expect(CloudSyncActivityStatus.lastRunAt(userDefaults: defaults) == nil)
        #expect(CloudSyncActivityStatus.lastRunSucceeded(userDefaults: defaults) == nil)
        #expect(CloudSyncActivityStatus.lastErrorMessage(userDefaults: defaults) == nil)
    }

    @Test func recordSuccessSchreibtUndLiestZurueck() throws {
        let defaults = try temporaryUserDefaults()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        CloudSyncActivityStatus.recordSuccess(at: date, userDefaults: defaults)

        #expect(CloudSyncActivityStatus.lastRunAt(userDefaults: defaults) == date)
        #expect(CloudSyncActivityStatus.lastRunSucceeded(userDefaults: defaults) == true)
        #expect(CloudSyncActivityStatus.lastErrorMessage(userDefaults: defaults) == nil)
    }

    @Test func recordFailureSchreibtUndLiestZurueck() throws {
        let defaults = try temporaryUserDefaults()
        let date = Date(timeIntervalSince1970: 1_700_000_100)

        CloudSyncActivityStatus.recordFailure("Netzwerkfehler", at: date, userDefaults: defaults)

        #expect(CloudSyncActivityStatus.lastRunAt(userDefaults: defaults) == date)
        #expect(CloudSyncActivityStatus.lastRunSucceeded(userDefaults: defaults) == false)
        #expect(CloudSyncActivityStatus.lastErrorMessage(userDefaults: defaults) == "Netzwerkfehler")
    }

    @Test func recordSuccessNachRecordFailureSetztFehlerZurueck() throws {
        let defaults = try temporaryUserDefaults()

        CloudSyncActivityStatus.recordFailure("Netzwerkfehler", userDefaults: defaults)
        CloudSyncActivityStatus.recordSuccess(userDefaults: defaults)

        #expect(CloudSyncActivityStatus.lastRunSucceeded(userDefaults: defaults) == true)
        #expect(CloudSyncActivityStatus.lastErrorMessage(userDefaults: defaults) == nil)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.CloudSyncActivityStatus.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncActivityStatusTests 2>&1 | tail -40`
Expected: FAIL — `CloudSyncActivityStatus` existiert noch nicht (Compile-Fehler).

- [ ] **Step 3: Implement `CloudSyncActivityStatus`**

Erstelle `Feedivo/Services/CloudSync/CloudSyncActivityStatus.swift`:

```swift
import Foundation

/// Persistenter (UserDefaults-backed) Status des letzten tatsächlichen iCloud-Sync-Versuchs —
/// im Gegensatz zu `CloudSyncStatus` (rein In-Memory, geht bei jedem App-Neustart verloren)
/// überlebt dieser Stand einen Neustart. Nach dem Muster von `ArticleRetentionSettings`s
/// `lastAutomaticCleanup*`-Keys aufgebaut (siehe `ArticleRetentionCleanupService.
/// recordAutomaticCleanupSuccess/-Failure`). Siehe Design-Spec
/// `docs/superpowers/specs/2026-07-24-icloud-sync-status-uebersicht-design.md`.
enum CloudSyncActivityStatus {
    static let lastRunDateKey = "cloudSync.activity.lastRunDate"
    static let statusKey = "cloudSync.activity.status"
    static let lastErrorMessageKey = "cloudSync.activity.lastErrorMessage"

    static let statusSuccess = "success"
    static let statusFailed = "failed"

    static func lastRunAt(userDefaults: UserDefaults = .standard) -> Date? {
        let timestamp = userDefaults.double(forKey: lastRunDateKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    static func lastRunSucceeded(userDefaults: UserDefaults = .standard) -> Bool? {
        switch userDefaults.string(forKey: statusKey) {
        case statusSuccess: true
        case statusFailed: false
        default: nil
        }
    }

    static func lastErrorMessage(userDefaults: UserDefaults = .standard) -> String? {
        userDefaults.string(forKey: lastErrorMessageKey)
    }

    static func recordSuccess(at date: Date = Date(), userDefaults: UserDefaults = .standard) {
        userDefaults.set(date.timeIntervalSince1970, forKey: lastRunDateKey)
        userDefaults.set(statusSuccess, forKey: statusKey)
        userDefaults.removeObject(forKey: lastErrorMessageKey)
    }

    static func recordFailure(_ message: String, at date: Date = Date(), userDefaults: UserDefaults = .standard) {
        userDefaults.set(date.timeIntervalSince1970, forKey: lastRunDateKey)
        userDefaults.set(statusFailed, forKey: statusKey)
        userDefaults.set(message, forKey: lastErrorMessageKey)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncActivityStatusTests 2>&1 | tail -60`
Expected: PASS

- [ ] **Step 5: Full build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncActivityStatus.swift FeedivoTests/CloudSyncActivityStatusTests.swift
git commit -m "Feature: CloudSyncActivityStatus persistenter Sync-Status (iCloud Sync Status-Übersicht Task 1)"
```

---

### Task 2: `CloudSyncPendingChangeStore.pendingCounts()` — Live-Zähler je Datenart

**Files:**
- Modify: `Feedivo/Stores/CloudSyncPendingChangeStore.swift`
- Test: `FeedivoTests/CloudSyncPendingChangeStoreTests.swift`

**Interfaces:**
- Produces: `func pendingCounts() throws -> [String: Int]` (recordType → Anzahl) — genutzt von Task 5 (UI).

- [ ] **Step 1: Write the failing tests**

Ergänze in `FeedivoTests/CloudSyncPendingChangeStoreTests.swift` (lies die Datei zuerst, um Stil/Imports exakt zu übernehmen) am Ende des `struct`-Bodys:

```swift
    @Test func pendingCountsLeereTabelleLiefertLeeresDictionary() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        #expect(try store.pendingCounts().isEmpty)
    }

    @Test func pendingCountsGruppiertNachRecordType() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save)
        try store.enqueue(recordType: "Tag", recordName: "tag-2", changeType: .save)
        try store.enqueue(recordType: "Feed", recordName: "feed-1", changeType: .save)

        let counts = try store.pendingCounts()
        #expect(counts["Tag"] == 2)
        #expect(counts["Feed"] == 1)
        #expect(counts.count == 2)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests 2>&1 | tail -40`
Expected: FAIL — `pendingCounts()` existiert noch nicht.

- [ ] **Step 3: Implement `pendingCounts()`**

In `Feedivo/Stores/CloudSyncPendingChangeStore.swift`, ergänze nach `pendingChange(recordName:)` (vor der schließenden `}` des Structs):

```swift

    /// Anzahl ausstehender Änderungen je `recordType`, für die Sync-Status-Übersicht in den
    /// Einstellungen (siehe Design-Spec
    /// `docs/superpowers/specs/2026-07-24-icloud-sync-status-uebersicht-design.md`).
    func pendingCounts() throws -> [String: Int] {
        struct RecordTypeCount: FetchableRecord, Decodable {
            let recordType: String
            let count: Int
        }
        return try database.read { db in
            let rows = try RecordTypeCount.fetchAll(db, sql: """
                SELECT recordType, COUNT(*) AS count FROM cloud_sync_pending_changes GROUP BY recordType
                """)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.recordType, $0.count) })
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests 2>&1 | tail -60`
Expected: PASS

- [ ] **Step 5: Full build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Stores/CloudSyncPendingChangeStore.swift FeedivoTests/CloudSyncPendingChangeStoreTests.swift
git commit -m "Feature: CloudSyncPendingChangeStore.pendingCounts je recordType (iCloud Sync Status-Übersicht Task 2)"
```

---

### Task 3: `CloudSyncActivityCategory` — Kategorien-Mapping + L10n-Keys

**Files:**
- Create: `Feedivo/Services/CloudSync/CloudSyncActivityCategory.swift`
- Test: `FeedivoTests/CloudSyncActivityCategoryTests.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: nichts aus vorherigen Tasks.
- Produces: `enum CloudSyncActivityCategory: CaseIterable, Hashable` mit `.recordTypes: [String]`, `.localizedTitle: LocalizedStringKey`, `.pendingCount(in: [String: Int]) -> Int` — genutzt von Task 5 (UI-Detailzeilen).

- [ ] **Step 1: Write the failing tests**

Erstelle `FeedivoTests/CloudSyncActivityCategoryTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct CloudSyncActivityCategoryTests {
    @Test func einzelKategorienUmfassenGenauIhrenEigenenRecordType() {
        #expect(CloudSyncActivityCategory.tags.recordTypes == ["Tag"])
        #expect(CloudSyncActivityCategory.feeds.recordTypes == ["Feed"])
        #expect(CloudSyncActivityCategory.folders.recordTypes == ["FeedFolder"])
    }

    @Test func rulesKategorieUmfasstRuleUndRuleCondition() {
        #expect(CloudSyncActivityCategory.rules.recordTypes == ["Rule", "RuleCondition"])
    }

    @Test func smartFoldersKategorieUmfasstSmartFolderUndSmartFolderCondition() {
        #expect(CloudSyncActivityCategory.smartFolders.recordTypes == ["SmartFolder", "SmartFolderCondition"])
    }

    @Test func pendingCountSummiertAlleZugehoerigenRecordTypes() {
        let counts = ["Rule": 2, "RuleCondition": 3, "Tag": 5]
        #expect(CloudSyncActivityCategory.rules.pendingCount(in: counts) == 5)
        #expect(CloudSyncActivityCategory.tags.pendingCount(in: counts) == 5)
    }

    @Test func pendingCountIstNullWennKeineEintraege() {
        #expect(CloudSyncActivityCategory.feeds.pendingCount(in: [:]) == 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncActivityCategoryTests 2>&1 | tail -40`
Expected: FAIL — `CloudSyncActivityCategory` existiert noch nicht.

- [ ] **Step 3: Add the 5 L10n-Keys for category titles**

Lies zuerst `Feedivo/Resources/L10n.swift` um Zeile 435 herum, um die exakte aktuelle Umgebung zu bestätigen. Ersetze dann:

```swift
    static let settingsSyncBetaScopeHint = LocalizedStringKey("settings.sync.beta.scopeHint")
    static let feedProgressRefreshAllTitle = String(localized: "feed.progress.refreshAll.title")
```

durch:

```swift
    static let settingsSyncBetaScopeHint = LocalizedStringKey("settings.sync.beta.scopeHint")
    static let settingsSyncActivityCategoryTags = LocalizedStringKey("settings.sync.activity.category.tags")
    static let settingsSyncActivityCategoryFeeds = LocalizedStringKey("settings.sync.activity.category.feeds")
    static let settingsSyncActivityCategoryFolders = LocalizedStringKey("settings.sync.activity.category.folders")
    static let settingsSyncActivityCategoryRules = LocalizedStringKey("settings.sync.activity.category.rules")
    static let settingsSyncActivityCategorySmartFolders = LocalizedStringKey("settings.sync.activity.category.smartFolders")
    static let feedProgressRefreshAllTitle = String(localized: "feed.progress.refreshAll.title")
```

- [ ] **Step 4: Insert the 5 xcstrings entries**

Lies zuerst `Feedivo/Resources/Localizable.xcstrings` um die Zeile mit `"settings.sync.beta.description"` herum (per `grep -n '"settings.sync.beta.description"' Feedivo/Resources/Localizable.xcstrings`), um den exakten aktuellen Text zu bestätigen. Ersetze dann NUR den Anker-Zeilenanfang (keine andere Stelle in der Datei anfassen):

Alt:
```
    "settings.sync.beta.description" : {
```

Neu (5 neue Blöcke davor eingefügt, Anker-Zeile unverändert danach):
```
    "settings.sync.activity.category.feeds" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feeds"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feeds"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Flux"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed"
          }
        }
      }
    },
    "settings.sync.activity.category.folders" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ordner"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Folders"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Dossiers"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Cartelle"
          }
        }
      }
    },
    "settings.sync.activity.category.rules" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Regeln"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Rules"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Règles"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Regole"
          }
        }
      }
    },
    "settings.sync.activity.category.smartFolders" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Intelligente Ordner"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Smart Folders"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Dossiers intelligents"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Cartelle intelligenti"
          }
        }
      }
    },
    "settings.sync.activity.category.tags" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Tags"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Tags"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Tags"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Tag"
          }
        }
      }
    },
    "settings.sync.beta.description" : {
```

Verifiziere danach per `git diff --stat Feedivo/Resources/Localizable.xcstrings`: nur Insertions, keine/kaum Deletions.

- [ ] **Step 5: Implement `CloudSyncActivityCategory`**

Erstelle `Feedivo/Services/CloudSync/CloudSyncActivityCategory.swift`:

```swift
import SwiftUI

/// Fasst die 7 rohen `CloudSyncRecordMapping.recordType`-Werte zu 5 nutzerverständlichen
/// Kategorien für die Sync-Status-Übersicht zusammen — die Bedingungs-Tabellen (`RuleCondition`,
/// `SmartFolderCondition`) haben für den Nutzer keine eigene Identität. Siehe Design-Spec
/// `docs/superpowers/specs/2026-07-24-icloud-sync-status-uebersicht-design.md`.
enum CloudSyncActivityCategory: CaseIterable, Hashable {
    case tags
    case feeds
    case folders
    case rules
    case smartFolders

    var recordTypes: [String] {
        switch self {
        case .tags: ["Tag"]
        case .feeds: ["Feed"]
        case .folders: ["FeedFolder"]
        case .rules: ["Rule", "RuleCondition"]
        case .smartFolders: ["SmartFolder", "SmartFolderCondition"]
        }
    }

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .tags: L10n.settingsSyncActivityCategoryTags
        case .feeds: L10n.settingsSyncActivityCategoryFeeds
        case .folders: L10n.settingsSyncActivityCategoryFolders
        case .rules: L10n.settingsSyncActivityCategoryRules
        case .smartFolders: L10n.settingsSyncActivityCategorySmartFolders
        }
    }

    func pendingCount(in counts: [String: Int]) -> Int {
        recordTypes.reduce(0) { $0 + (counts[$1] ?? 0) }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncActivityCategoryTests 2>&1 | tail -60`
Expected: PASS

- [ ] **Step 7: Full build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncActivityCategory.swift FeedivoTests/CloudSyncActivityCategoryTests.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature: CloudSyncActivityCategory Kategorien-Mapping (iCloud Sync Status-Übersicht Task 3)"
```

---

### Task 4: `CloudSyncActivityStatus` in `CloudSyncEngine.handleEvent` verdrahten

**Files:**
- Modify: `Feedivo/Services/CloudSync/CloudSyncEngine.swift`

**Interfaces:**
- Consumes: `CloudSyncActivityStatus.recordSuccess(at:userDefaults:)` / `.recordFailure(_:at:userDefaults:)` (Task 1).

**Hinweis zur Testbarkeit:** Diese Änderung sitzt innerhalb von `handleEvent(_:syncEngine:)`, gegattert durch `CKSyncEngine.Event`-Fälle — dieser CloudKit-Framework-Typ ist in diesem Projekt (und nach aktuellem Kenntnisstand generell) nicht synthetisch konstruierbar, kein bestehender Test in `FeedivoTests/` simuliert `CKSyncEngine.Event` (per `grep -rn "CKSyncEngine.Event" FeedivoTests/` verifizierbar — leeres Ergebnis). Dieser Task hat deshalb bewusst KEINEN TDD-Test-first-Zyklus — Verifikation läuft über volle Kompilierung + die bestehende CloudSync-Regressionssuite (keine Signatur-Regression) sowie die manuelle Live-Verifikation am Ende dieses Plans. Das ist konsistent mit der im Design-Spec dokumentierten, bekannten Grenze.

- [ ] **Step 1: Read the current file**

Lies `Feedivo/Services/CloudSync/CloudSyncEngine.swift` vollständig, insbesondere den `CKSyncEngineDelegate`-Extension-Block (`handleEvent`, `handleFailedSave`), um die exakte Einfügestelle zu bestätigen.

- [ ] **Step 2: Wire `.fetchedRecordZoneChanges`**

Ersetze:

```swift
        case .fetchedRecordZoneChanges(let changes):
            for modification in Self.sortedByDependencyOrder(changes.modifications.map(\.record)) {
                await applyIncomingRecord(modification)
            }
            for deletion in changes.deletions {
                await applyIncomingDeletion(deletion.recordID)
            }
```

durch:

```swift
        case .fetchedRecordZoneChanges(let changes):
            for modification in Self.sortedByDependencyOrder(changes.modifications.map(\.record)) {
                await applyIncomingRecord(modification)
            }
            for deletion in changes.deletions {
                await applyIncomingDeletion(deletion.recordID)
            }
            CloudSyncActivityStatus.recordSuccess()
```

- [ ] **Step 3: Wire `.sentRecordZoneChanges`**

Ersetze:

```swift
        case .sentRecordZoneChanges(let changes):
            for saved in changes.savedRecords {
                dequeuePendingChange(recordName: saved.recordID.recordName)
            }
            for deletedID in changes.deletedRecordIDs {
                dequeuePendingChange(recordName: deletedID.recordName)
            }
            for failedSave in changes.failedRecordSaves {
                await handleFailedSave(failedSave)
            }
```

durch:

```swift
        case .sentRecordZoneChanges(let changes):
            for saved in changes.savedRecords {
                dequeuePendingChange(recordName: saved.recordID.recordName)
            }
            for deletedID in changes.deletedRecordIDs {
                dequeuePendingChange(recordName: deletedID.recordName)
            }
            for failedSave in changes.failedRecordSaves {
                await handleFailedSave(failedSave)
            }
            recordSyncActivityOutcome(failedRecordSaves: changes.failedRecordSaves)
```

- [ ] **Step 4: Add the outcome helper**

Ergänze in derselben `extension CloudSyncEngine: CKSyncEngineDelegate { ... }`, direkt nach `handleFailedSave(_:)`:

```swift

    /// Aktualisiert den persistenten Sync-Aktivitätsstatus nach einem abgeschlossenen
    /// Sende-Batch. `.serverRecordChanged`-Konflikte zählen NICHT als Fehler — die werden
    /// bereits automatisch aufgelöst (siehe `handleFailedSave` oben), das ist normaler
    /// Multi-Geräte-Betrieb. Siehe Design-Spec
    /// `docs/superpowers/specs/2026-07-24-icloud-sync-status-uebersicht-design.md`.
    private func recordSyncActivityOutcome(failedRecordSaves: [CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave]) {
        let realFailureMessages = failedRecordSaves
            .filter { $0.error.code != .serverRecordChanged }
            .map(\.error.localizedDescription)
        if let firstFailureMessage = realFailureMessages.first {
            CloudSyncActivityStatus.recordFailure(firstFailureMessage)
        } else {
            CloudSyncActivityStatus.recordSuccess()
        }
    }
```

- [ ] **Step 5: Full build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Run the full CloudSync regression suite**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncEngineRegistryTests -only-testing:FeedivoTests/CloudSyncTagMappingTests -only-testing:FeedivoTests/CloudSyncFeedMappingTests -only-testing:FeedivoTests/CloudSyncFeedFolderMappingTests -only-testing:FeedivoTests/CloudSyncRuleMappingTests -only-testing:FeedivoTests/CloudSyncRuleConditionMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderMappingTests -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests -only-testing:FeedivoTests/CloudSyncSettingsTests -only-testing:FeedivoTests/CloudSyncActivityStatusTests -only-testing:FeedivoTests/CloudSyncActivityCategoryTests -parallel-testing-enabled NO 2>&1 | tail -100`
Expected: alle PASS — keine Regression durch das Engine-Wiring.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncEngine.swift
git commit -m "Feature: CloudSyncActivityStatus in CloudSyncEngine.handleEvent verdrahten (iCloud Sync Status-Übersicht Task 4)"
```

---

### Task 5: UI-Block in `SyncSettingsView`

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CloudSyncActivityStatus.lastRunDateKey/statusKey/lastErrorMessageKey/statusSuccess/statusFailed` (Task 1, direkt als `@AppStorage`-Keys), `CloudSyncPendingChangeStore.pendingCounts()` (Task 2), `CloudSyncActivityCategory` (Task 3), `SQLiteDataInvalidation.statusVersionKey` (bestehend).

**Hinweis zur Testbarkeit:** Reiner SwiftUI-View-Code ohne eigene Geschäftslogik über das bereits in Task 1–3 getestete hinaus — dieses Projekt hat kein UI-Test-Setup (kein computer-use für native macOS-Apps, siehe CLAUDE.md-Konvention bei praktisch jedem bisherigen UI-Feature). Verifikation über Build + volle Regressionssuite + manuelle Live-Verifikation (letzter Abschnitt dieses Plans).

- [ ] **Step 1: Add the 6 L10n-Keys for the status block**

Lies zuerst `Feedivo/Resources/L10n.swift` um die (durch Task 3 bereits leicht verschobene) `settingsSyncActivityCategory*`-Zeilen herum. Ersetze dann:

```swift
    static let settingsSyncActivityCategorySmartFolders = LocalizedStringKey("settings.sync.activity.category.smartFolders")
    static let feedProgressRefreshAllTitle = String(localized: "feed.progress.refreshAll.title")
```

durch:

```swift
    static let settingsSyncActivityCategorySmartFolders = LocalizedStringKey("settings.sync.activity.category.smartFolders")
    static let settingsSyncActivityTitle = LocalizedStringKey("settings.sync.activity.title")
    static let settingsSyncActivityDescription = LocalizedStringKey("settings.sync.activity.description")
    static let settingsSyncActivityStatusRow = LocalizedStringKey("settings.sync.activity.statusRow")
    static let settingsSyncActivityLastRunRow = LocalizedStringKey("settings.sync.activity.lastRunRow")
    static let settingsSyncActivityDetailsShow = LocalizedStringKey("settings.sync.activity.detailsShow")
    static let settingsSyncActivityDetailsHide = LocalizedStringKey("settings.sync.activity.detailsHide")
    static let feedProgressRefreshAllTitle = String(localized: "feed.progress.refreshAll.title")
```

- [ ] **Step 2: Insert the 13 xcstrings entries**

Lies zuerst `Feedivo/Resources/Localizable.xcstrings` um `"settings.sync.beta.description"` herum (per `grep -n '"settings.sync.beta.description"' Feedivo/Resources/Localizable.xcstrings`), um den exakten aktuellen Text nach Task 3 zu bestätigen. Ersetze dann NUR den Anker-Zeilenanfang:

Alt:
```
    "settings.sync.beta.description" : {
```

Neu (13 neue Blöcke davor eingefügt, Anker-Zeile unverändert danach):
```
    "settings.sync.activity.category.pending" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%lld ausstehend"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%lld pending"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%lld en attente"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%lld in attesa"
          }
        }
      }
    },
    "settings.sync.activity.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Letzter Sync-Versuch und Status je Datenart."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Last sync attempt and status per data type."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Dernière tentative de synchronisation et état par type de données."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ultimo tentativo di sincronizzazione e stato per tipo di dati."
          }
        }
      }
    },
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
    "settings.sync.activity.detailsShow" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Details anzeigen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Show details"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Afficher les détails"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Mostra dettagli"
          }
        }
      }
    },
    "settings.sync.activity.lastRunRow" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Zuletzt synchronisiert"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Last synced"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Dernière synchronisation"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ultima sincronizzazione"
          }
        }
      }
    },
    "settings.sync.activity.neverRun" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Noch nie synchronisiert"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Never synced"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Jamais synchronisé"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Mai sincronizzato"
          }
        }
      }
    },
    "settings.sync.activity.state.accountUnavailable" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "iCloud-Konto nicht verfügbar"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "iCloud account unavailable"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Compte iCloud indisponible"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Account iCloud non disponibile"
          }
        }
      }
    },
    "settings.sync.activity.state.disabled" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sync ist deaktiviert"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sync is disabled"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "La synchronisation est désactivée"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "La sincronizzazione è disattivata"
          }
        }
      }
    },
    "settings.sync.activity.state.error" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Fehler: %@"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Error: %@"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Erreur : %@"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Errore: %@"
          }
        }
      }
    },
    "settings.sync.activity.state.pending" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ausstehend (%lld)"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Pending (%lld)"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "En attente (%lld)"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "In attesa (%lld)"
          }
        }
      }
    },
    "settings.sync.activity.state.synced" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Synchron"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Synced"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Synchronisé"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sincronizzato"
          }
        }
      }
    },
    "settings.sync.activity.statusRow" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Status"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Status"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "État"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Stato"
          }
        }
      }
    },
    "settings.sync.activity.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sync-Status"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sync Status"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "État de la synchronisation"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Stato sincronizzazione"
          }
        }
      }
    },
    "settings.sync.beta.description" : {
```

Verifiziere danach per `git diff --stat Feedivo/Resources/Localizable.xcstrings`: nur Insertions, keine/kaum Deletions.

- [ ] **Step 3: Read the current `SyncSettingsView`**

Lies `Feedivo/Views/Settings/SettingsView.swift` um `private struct SyncSettingsView` herum (Zeilen ca. 1056–1128), um die exakte aktuelle Fassung zu bestätigen.

- [ ] **Step 4: Extend `SyncSettingsView` with the new state + reload wiring**

Ersetze:

```swift
private struct SyncSettingsView: View {
    @Environment(DatabaseLoadState.self) private var databaseLoadState
    @Environment(CloudSyncStatus.self) private var cloudSyncStatus
    @Environment(\.cloudSyncEngine) private var cloudSyncEngine

    @AppStorage(CloudSyncSettings.isEnabledKey)
    private var cloudSyncIsEnabled = CloudSyncSettings.defaultIsEnabled

    private var hasDatabaseError: Bool {
        databaseLoadState.initializationError != nil
    }

    private var statusLocalizationKey: String {
        CloudSyncSettings.statusLocalizationKey(
            isEnabled: cloudSyncIsEnabled,
            syncState: cloudSyncStatus.state,
            hasDatabaseError: hasDatabaseError
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: L10n.settingsSyncSection) {
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

                    SettingRow(
                        title: L10n.settingsSyncBetaTitle,
                        description: L10n.settingsSyncBetaScopeHint
                    ) {
                        Toggle("", isOn: $cloudSyncIsEnabled)
                            .toggleStyle(.switch)
                    }

                    InfoRow(
                        iconName: hasDatabaseError ? "exclamationmark.triangle" : "icloud",
                        title: L10n.settingsSyncStatusTitle,
                        description: LocalizedStringKey(statusLocalizationKey)
                    )

                    if hasDatabaseError {
                        InfoRow(
                            iconName: "internaldrive",
                            title: L10n.settingsSyncDatabaseTitle,
                            description: L10n.settingsSyncDatabaseErrorHint
                        )
                    }
                }
            }
        }
        .onChange(of: cloudSyncIsEnabled) {
            if cloudSyncIsEnabled {
                cloudSyncEngine?.start()
            } else {
                cloudSyncEngine?.stop()
            }
        }
    }
}
```

durch:

```swift
private struct SyncSettingsView: View {
    @Environment(DatabaseLoadState.self) private var databaseLoadState
    @Environment(CloudSyncStatus.self) private var cloudSyncStatus
    @Environment(\.cloudSyncEngine) private var cloudSyncEngine
    @Environment(\.feedivoDatabase) private var feedivoDatabase

    @AppStorage(CloudSyncSettings.isEnabledKey)
    private var cloudSyncIsEnabled = CloudSyncSettings.defaultIsEnabled

    @AppStorage(CloudSyncActivityStatus.lastRunDateKey)
    private var syncActivityLastRunTimestamp = 0.0

    @AppStorage(CloudSyncActivityStatus.statusKey)
    private var syncActivityStatusRaw = ""

    @AppStorage(CloudSyncActivityStatus.lastErrorMessageKey)
    private var syncActivityErrorMessage = ""

    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersionForSyncActivity = 0

    @State private var syncActivityPendingCounts: [String: Int] = [:]
    @State private var isSyncActivityDetailsExpanded = false

    private var hasDatabaseError: Bool {
        databaseLoadState.initializationError != nil
    }

    private var statusLocalizationKey: String {
        CloudSyncSettings.statusLocalizationKey(
            isEnabled: cloudSyncIsEnabled,
            syncState: cloudSyncStatus.state,
            hasDatabaseError: hasDatabaseError
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: L10n.settingsSyncSection) {
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

                    SettingRow(
                        title: L10n.settingsSyncBetaTitle,
                        description: L10n.settingsSyncBetaScopeHint
                    ) {
                        Toggle("", isOn: $cloudSyncIsEnabled)
                            .toggleStyle(.switch)
                    }

                    InfoRow(
                        iconName: hasDatabaseError ? "exclamationmark.triangle" : "icloud",
                        title: L10n.settingsSyncStatusTitle,
                        description: LocalizedStringKey(statusLocalizationKey)
                    )

                    if hasDatabaseError {
                        InfoRow(
                            iconName: "internaldrive",
                            title: L10n.settingsSyncDatabaseTitle,
                            description: L10n.settingsSyncDatabaseErrorHint
                        )
                    }

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
        .onChange(of: cloudSyncIsEnabled) {
            if cloudSyncIsEnabled {
                cloudSyncEngine?.start()
            } else {
                cloudSyncEngine?.stop()
            }
        }
        .onAppear(perform: loadSyncActivityPendingCounts)
        .onChange(of: sqliteStatusVersionForSyncActivity) {
            loadSyncActivityPendingCounts()
        }
    }

    private func loadSyncActivityPendingCounts() {
        guard let feedivoDatabase else {
            syncActivityPendingCounts = [:]
            return
        }
        syncActivityPendingCounts = (try? CloudSyncPendingChangeStore(database: feedivoDatabase).pendingCounts()) ?? [:]
    }
}
```

- [ ] **Step 5: Add the `CloudSyncActivityStatusBlock` view**

Direkt nach der schließenden `}` von `SyncSettingsView` (vor `private struct CleanupSettingsView`), ergänze:

```swift

private struct CloudSyncActivityStatusBlock: View {
    let cloudSyncIsEnabled: Bool
    let isAccountUnavailable: Bool
    let lastRunTimestamp: Double
    let statusRaw: String
    let errorMessage: String
    let pendingCounts: [String: Int]
    @Binding var isDetailsExpanded: Bool

    private var isActiveAndAvailable: Bool {
        cloudSyncIsEnabled && !isAccountUnavailable
    }

    private var totalPendingCount: Int {
        pendingCounts.values.reduce(0, +)
    }

    private var stateText: String {
        guard isActiveAndAvailable else {
            return cloudSyncIsEnabled
                ? String(localized: "settings.sync.activity.state.accountUnavailable")
                : String(localized: "settings.sync.activity.state.disabled")
        }
        if statusRaw == CloudSyncActivityStatus.statusFailed {
            return String.localizedStringWithFormat(String(localized: "settings.sync.activity.state.error"), errorMessage)
        }
        if totalPendingCount > 0 {
            return String.localizedStringWithFormat(String(localized: "settings.sync.activity.state.pending"), totalPendingCount)
        }
        return String(localized: "settings.sync.activity.state.synced")
    }

    private var lastRunText: String {
        guard lastRunTimestamp > 0 else {
            return String(localized: "settings.sync.activity.neverRun")
        }
        return Date(timeIntervalSince1970: lastRunTimestamp).formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.settingsSyncActivityTitle)
                    .font(.system(size: 14))
                Text(L10n.settingsSyncActivityDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 5) {
                statusLine(title: L10n.settingsSyncActivityStatusRow, value: stateText)
                statusLine(title: L10n.settingsSyncActivityLastRunRow, value: lastRunText)
            }
            .frame(maxWidth: .infinity)
            .opacity(isActiveAndAvailable ? 1 : 0.55)

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isDetailsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(isDetailsExpanded ? L10n.settingsSyncActivityDetailsHide : L10n.settingsSyncActivityDetailsShow)
                    Image(systemName: isDetailsExpanded ? "chevron.down" : "chevron.right")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isDetailsExpanded {
                VStack(spacing: 5) {
                    ForEach(CloudSyncActivityCategory.allCases, id: \.self) { category in
                        statusLine(title: category.localizedTitle, value: categoryValueText(for: category))
                    }
                }
                .frame(maxWidth: .infinity)
                .opacity(isActiveAndAvailable ? 1 : 0.55)
            }
        }
    }

    private func categoryValueText(for category: CloudSyncActivityCategory) -> String {
        let count = category.pendingCount(in: pendingCounts)
        guard count > 0 else {
            return String(localized: "settings.sync.activity.state.synced")
        }
        return String.localizedStringWithFormat(String(localized: "settings.sync.activity.category.pending"), count)
    }
}
```

> **Wichtig für den Implementierer:** `statusLine(title:value:)` (die `String`-Wert-Überladung) ist bereits als `private func` auf Datei-Ebene definiert (oberhalb von `SyncSettingsView`, genutzt von `RefreshSettingsView`) — Swifts `private` auf oberster Datei-Ebene ist file-scoped, `CloudSyncActivityStatusBlock` kann sie deshalb direkt verwenden, ohne einen neuen Import oder eine neue Definition.

- [ ] **Step 6: Full build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -80`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Run the full CloudSync + Settings-relevant regression suite**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncEngineRegistryTests -only-testing:FeedivoTests/CloudSyncTagMappingTests -only-testing:FeedivoTests/CloudSyncFeedMappingTests -only-testing:FeedivoTests/CloudSyncFeedFolderMappingTests -only-testing:FeedivoTests/CloudSyncRuleMappingTests -only-testing:FeedivoTests/CloudSyncRuleConditionMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderMappingTests -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests -only-testing:FeedivoTests/CloudSyncSettingsTests -only-testing:FeedivoTests/CloudSyncActivityStatusTests -only-testing:FeedivoTests/CloudSyncActivityCategoryTests -parallel-testing-enabled NO 2>&1 | tail -100`
Expected: alle PASS.

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature: Sync-Status-Übersicht im Sync-Tab (iCloud Sync Status-Übersicht Task 5)"
```

---

## Live-Verifikation (nach diesem Plan, manuell durch den Nutzer)

1. Sync aktivieren → Statuszeile zeigt zunächst "Noch nie synchronisiert" bzw. kurz danach "Ausstehend (N)", sobald der Backfill (Phase 2a) greift.
2. Nach erfolgreichem Senden zeigt die Statuszeile "Synchron" mit dem aktuellen Zeitpunkt unter "Zuletzt synchronisiert".
3. Einen Feed/ein Tag/eine Regel anlegen → Statuszeile wechselt kurz auf "Ausstehend (1)", "Details anzeigen" aufklappen → die betroffene Kategorie zeigt "1 ausstehend", die übrigen "Synchron".
4. Sync-Toggle ausschalten → der Block dämpft sich (reduzierte Opazität), zeigt "Sync ist deaktiviert" als Status, der zuletzt bekannte Zeitpunkt bleibt sichtbar.
5. Sync wieder einschalten → Block normalisiert sich wieder.
6. Falls reproduzierbar (z. B. Netzwerk kurz trennen + Änderung vornehmen): Fehlerzustand zeigt "Fehler: {Meldung}" in Rot/Fehlerfarbe und bleibt nach einem App-Neustart erhalten (Beweis der Persistenz über `@AppStorage`/UserDefaults).
7. Bereits bekannte, weiterhin gültige Limitation gegenprüfen (siehe Global Constraints): ein einzelner fehlgeschlagener eingehender Record führt NICHT zu einer sichtbaren Fehleranzeige — das ist erwartetes, dokumentiertes Verhalten dieses Plans, kein neuer Bug.
