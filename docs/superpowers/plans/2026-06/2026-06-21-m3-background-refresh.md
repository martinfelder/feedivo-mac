# M3 Background Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Improve Feedivo's macOS-native automatic refresh by storing clear status metadata and showing it in Settings.

**Architecture:** Keep `NSBackgroundActivityScheduler` as the only scheduler. Add small UserDefaults-backed status helpers to `BackgroundRefreshSettings`, write status from `BackgroundRefreshService`, and render compact status rows in `SettingsView`.

**Tech Stack:** Swift, SwiftUI, SwiftData, UserDefaults, NSBackgroundActivityScheduler, Swift Testing, Xcode `xcodebuild`.

---

### Task 1: Add Background Refresh Status Model

**Files:**
- Modify: `Feedivo/Services/BackgroundRefreshSettings.swift`
- Test: `FeedivoTests/BackgroundRefreshSettingsTests.swift`

- [x] **Step 1: Write failing tests**

Add tests that expect:

```swift
#expect(BackgroundRefreshSettings.statusText(for: "success") == "Erfolgreich")
#expect(BackgroundRefreshSettings.statusText(for: "failed") == "Fehlgeschlagen")
#expect(BackgroundRefreshSettings.statusText(for: nil) == "Noch nicht gelaufen")
```

And:

```swift
let next = BackgroundRefreshSettings.nextScheduledRefreshDate(
    intervalMinutes: 44,
    now: Date(timeIntervalSince1970: 1_000)
)
#expect(next == Date(timeIntervalSince1970: 2_800))
```

- [x] **Step 2: Run failing tests**

Run:

```bash
xcodebuild -quiet test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS,arch=arm64' -only-testing:FeedivoTests/BackgroundRefreshSettingsTests -derivedDataPath /private/tmp/feedivo-background-refresh-derived-data
```

Expected: fails because status keys/helpers do not exist.

- [x] **Step 3: Implement status helpers**

Add to `BackgroundRefreshSettings`:

```swift
static let lastAutomaticRefreshDateKey = "backgroundRefresh.lastAutomaticRefreshDate"
static let lastAutomaticRefreshStatusKey = "backgroundRefresh.lastAutomaticRefreshStatus"
static let lastAutomaticRefreshErrorKey = "backgroundRefresh.lastAutomaticRefreshError"
static let nextAutomaticRefreshDateKey = "backgroundRefresh.nextAutomaticRefreshDate"

static let statusSuccess = "success"
static let statusFailed = "failed"

static func nextScheduledRefreshDate(intervalMinutes: Int, now: Date = Date()) -> Date {
    now.addingTimeInterval(TimeInterval(clampedIntervalMinutes(intervalMinutes) * 60))
}

static func statusText(for status: String?) -> String {
    switch status {
    case statusSuccess:
        return "Erfolgreich"
    case statusFailed:
        return "Fehlgeschlagen"
    default:
        return "Noch nicht gelaufen"
    }
}
```

- [x] **Step 4: Run tests**

Run the same `xcodebuild` command. Expected: pass.

### Task 2: Store Scheduling and Run Status

**Files:**
- Modify: `Feedivo/Services/BackgroundRefreshService.swift`
- Test: `FeedivoTests/BackgroundRefreshServiceTests.swift`

- [x] **Step 1: Write failing tests**

Add tests that call `BackgroundRefreshService.scheduleNextRefresh(..., userDefaults:)` and verify:

```swift
#expect(defaults.object(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey) as? Date == now.addingTimeInterval(30 * 60))
```

Add success/failure status tests:

```swift
BackgroundRefreshService.recordRefreshSuccess(now: now, intervalMinutes: 30, userDefaults: defaults)
#expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey) == BackgroundRefreshSettings.statusSuccess)
#expect(defaults.object(forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey) as? Date == now)
#expect(defaults.object(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey) as? Date == now.addingTimeInterval(30 * 60))
```

```swift
BackgroundRefreshService.recordRefreshFailure("Netzwerkfehler", now: now, intervalMinutes: 30, userDefaults: defaults)
#expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey) == BackgroundRefreshSettings.statusFailed)
#expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey) == "Netzwerkfehler")
```

- [x] **Step 2: Implement UserDefaults-backed scheduling/status**

Extend `scheduleNextRefresh` with `userDefaults: UserDefaults = .standard`. On disabled refresh, remove next date. On enabled refresh, store the next date.

Add:

```swift
static func recordRefreshSuccess(now: Date = Date(), intervalMinutes: Int, userDefaults: UserDefaults = .standard)
static func recordRefreshFailure(_ message: String, now: Date = Date(), intervalMinutes: Int, userDefaults: UserDefaults = .standard)
```

Call success/failure recording from `refreshAllFeeds(modelContainer:intervalMinutes:userDefaults:)`.

- [x] **Step 3: Run service tests**

Run:

```bash
xcodebuild -quiet test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS,arch=arm64' -only-testing:FeedivoTests/BackgroundRefreshServiceTests -derivedDataPath /private/tmp/feedivo-background-refresh-derived-data
```

Expected: pass.

### Task 3: Show Status in Settings

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [x] **Step 1: Add AppStorage bindings**

Add `@AppStorage` values for:

```swift
BackgroundRefreshSettings.lastAutomaticRefreshDateKey
BackgroundRefreshSettings.lastAutomaticRefreshStatusKey
BackgroundRefreshSettings.lastAutomaticRefreshErrorKey
BackgroundRefreshSettings.nextAutomaticRefreshDateKey
```

- [x] **Step 2: Add compact status UI**

Under the automatic refresh description, show:

```swift
LabeledContent("Letzter automatischer Refresh", value: formattedDate(lastAutomaticRefreshDate))
LabeledContent("Status", value: BackgroundRefreshSettings.statusText(for: lastAutomaticRefreshStatus))
LabeledContent("Naechster geplanter Refresh", value: formattedDate(nextAutomaticRefreshDate))
```

Show the last error as secondary text only when the status is `failed`.

- [x] **Step 3: Add localized keys**

Add keys for last refresh, status, next refresh, no date, success, failed, never run, and last error.

### Task 4: Wire App Scheduling and Documentation

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift`
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`

- [x] **Step 1: Pass interval into background execution**

Make `SystemBackgroundActivityRefreshScheduler` pass the active interval to `BackgroundRefreshService.refreshAllFeeds`.

- [x] **Step 2: Update docs**

Mark M3 Background Refresh as implemented and document:

- macOS-native scheduler remains the decision.
- Settings show last/next automatic refresh status.
- Completely quit app is still out of scope.

### Task 5: Verification and Commit

- [x] **Step 1: Run diff check**

```bash
git diff --check
```

Expected: no output.

- [x] **Step 2: Run targeted tests**

```bash
xcodebuild -quiet test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS,arch=arm64' -only-testing:FeedivoTests/BackgroundRefreshSettingsTests -only-testing:FeedivoTests/BackgroundRefreshServiceTests -derivedDataPath /private/tmp/feedivo-background-refresh-derived-data
```

Expected: pass.

- [x] **Step 3: Run full unit tests**

```bash
xcodebuild -quiet test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS,arch=arm64' -skip-testing:FeedivoUITests -derivedDataPath /private/tmp/feedivo-background-refresh-derived-data
```

Expected: pass.

- [x] **Step 4: Commit**

```bash
git add Feedivo FeedivoTests AGENTS.md docs/FEATURES.md docs/superpowers/plans/2026-06-21-m3-background-refresh.md
git commit -m "Improve background refresh status"
```
