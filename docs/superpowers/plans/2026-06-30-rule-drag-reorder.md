# Rule Drag Reorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete feature 5.2 by adding Drag & Drop reordering and the Regex operator to automatic rules in Settings.

**Architecture:** Reuse the Smart Folder drag reorder pattern for rules. `RuleViewModel` owns reorder and validation, `RuleSettingsView` wires SwiftUI drag/drop to that operation, and `RuleEngine` evaluates Regex with the same matching path as preview and retrospective rule application.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing.

---

### Task 1: Rule Reorder Model Behavior

**Files:**
- Modify: `Feedivo/ViewModels/RuleViewModel.swift`
- Test: `FeedivoTests/RuleViewModelTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that drag a rule down and up by moving it to the position of a target rule.

- [ ] **Step 2: Run focused tests**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleViewModelTests`

- [ ] **Step 3: Implement minimal model method**

Add `moveRule(_:toPositionOf:existingRules:context:)`, sorted by existing `sortOrder`, remove the source rule, insert at the target index, normalize sort order, and save when a context exists.

- [ ] **Step 4: Verify focused tests pass**

Run the same focused test command and confirm `RuleViewModelTests` passes.

### Task 2: Rule Settings Drag & Drop UI

**Files:**
- Modify: `Feedivo/Views/Rules/RuleSettingsView.swift`

- [ ] **Step 1: Add drag state and drop delegate**

Add `draggedRuleID` state and a `RuleRowDropDelegate` mirroring the Smart Folder implementation.

- [ ] **Step 2: Attach drag/drop to rows**

Use `.onDrag` with the rule ID, a compact preview, and `.onDrop(of: [.text], delegate:)` per row.

- [ ] **Step 3: Verify full test target**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests`

### Task 3: Roadmap Docs

**Files:**
- Modify: `FEATURES.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Mark Drag & Drop as implemented in 5.2**

Move the Drag & Drop bullet from “Noch offen” to the implemented rule-list bullets.

- [ ] **Step 2: Record the change in project memory**

Update the implemented-code and latest-changes sections in `AGENTS.md`.

### Task 4: Regex Operator

**Files:**
- Modify: `Feedivo/Models/RuleConditionOperator.swift`
- Modify: `Feedivo/Services/RuleEngine.swift`
- Modify: `Feedivo/ViewModels/RuleViewModel.swift`
- Modify: `Feedivo/Views/Rules/RuleSettingsView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Test: `FeedivoTests/RuleEngineTests.swift`
- Test: `FeedivoTests/RuleViewModelTests.swift`
- Test: `FeedivoTests/RuleConditionTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests for a case-insensitive Regex match, invalid Regex patterns returning zero preview matches, and invalid Regex rules being rejected before saving.

- [ ] **Step 2: Implement Regex support**

Add `.regex` to `RuleConditionOperator`, localized titles, `NSRegularExpression` matching in `RuleEngine`, and Regex validation in `RuleViewModel`.

- [ ] **Step 3: Verify**

Run focused rule tests and the full `FeedivoTests` test suite.
