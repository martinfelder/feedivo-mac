# M3 Rule Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a settings-based rule management UI with a create/edit wizard, multi-condition rules, and sidebar article-context entry.

**Architecture:** Extend `Rule` with a `RuleCondition` relationship and a simple `RuleMatchMode` string value. Keep the current legacy single-condition fields on `Rule` for compatibility, then backfill them into `RuleCondition` objects and make `RuleEngine` evaluate the condition list. UI saves valid rules through a new `RuleViewModel`; Settings owns rule management, while Sidebar only shows a compact entry point.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, existing `@Observable` ViewModel style, existing localization via `L10n` and `Localizable.xcstrings`.

---

## File Map

- Create `Feedivo/Models/RuleCondition.swift`: SwiftData model for one condition.
- Create `Feedivo/Models/RuleMatchMode.swift`: `all`/`any` helpers and localized titles.
- Create `Feedivo/Models/RuleConditionField.swift`: stored values and display titles for fields.
- Create `Feedivo/Models/RuleConditionOperator.swift`: stored values and display titles for operators.
- Modify `Feedivo/Models/Rule.swift`: add `conditionMatchMode` and `conditions`.
- Modify `Feedivo/App/FeedivoApp.swift`: include `RuleCondition.self` in the model container.
- Create `Feedivo/Services/RuleConditionBackfillService.swift`: creates conditions for legacy rules.
- Modify `Feedivo/Services/RuleEngine.swift`: evaluate multiple conditions with `AND`/`OR`.
- Create `Feedivo/ViewModels/RuleViewModel.swift`: validation and persistence for rules.
- Create `Feedivo/Views/Rules/RuleWizardView.swift`: create/edit wizard.
- Create `Feedivo/Views/Rules/RuleSettingsView.swift`: Settings list and management controls.
- Modify `Feedivo/Views/Settings/SettingsView.swift`: add the rules section.
- Modify `Feedivo/Views/Sidebar/SidebarView.swift`: compact rule section and article-context entry.
- Modify `Feedivo/Views/ContentView.swift`: pass selected article context into Sidebar and present wizard.
- Modify `Feedivo/Resources/L10n.swift` and `Feedivo/Resources/Localizable.xcstrings`: add rule UI strings.
- Modify `AGENTS.md` and `docs/FEATURES.md`: update M3 status and decisions.
- Test `FeedivoTests/RuleEngineTests.swift`: multi-condition engine behavior.
- Test `FeedivoTests/RuleConditionBackfillServiceTests.swift`: legacy backfill.
- Test `FeedivoTests/RuleViewModelTests.swift`: validation and persistence.
- Modify `FeedivoTests/FeedViewModelTests.swift`: update container schemas and refresh test expectations.

---

### Task 1: Add Multi-Condition Model Types

**Files:**
- Create: `Feedivo/Models/RuleCondition.swift`
- Create: `Feedivo/Models/RuleMatchMode.swift`
- Create: `Feedivo/Models/RuleConditionField.swift`
- Create: `Feedivo/Models/RuleConditionOperator.swift`
- Modify: `Feedivo/Models/Rule.swift`
- Modify: `Feedivo/App/FeedivoApp.swift`
- Test: `FeedivoTests/RuleEngineTests.swift`

- [ ] **Step 1: Write the failing engine test for AND and OR**

Add these tests to `FeedivoTests/RuleEngineTests.swift`:

```swift
@MainActor
@Test func applyRulesUnterstuetztMehrereBedingungenMitAND() throws {
    let tag = Tag(name: "Apple", colorHex: "#3B82F6")
    let rule = Rule(name: "Apple Mac", conditionField: "title", conditionOperator: "contains", conditionValue: "Apple")
    rule.conditionMatchMode = RuleMatchMode.all.rawValue
    rule.conditions = [
        RuleCondition(field: "title", conditionOperator: "contains", value: "Apple", sortOrder: 0),
        RuleCondition(field: "feedTitle", conditionOperator: "contains", value: "Mac", sortOrder: 1)
    ]
    rule.assignTag = tag
    let feed = Feed(url: "https://example.com/feed.xml", title: "Mac News")
    let matchingArticle = Article(title: "Apple stellt Swift vor", feed: feed)
    let nonMatchingArticle = Article(title: "Apple stellt Swift vor", feed: Feed(url: "https://example.com/other.xml", title: "Other News"))

    RuleEngine.applyRules([rule], to: matchingArticle, feed: feed)
    RuleEngine.applyRules([rule], to: nonMatchingArticle, feed: nonMatchingArticle.feed!)

    #expect(matchingArticle.tags.map(\.name) == ["Apple"])
    #expect(nonMatchingArticle.tags.isEmpty)
}

@MainActor
@Test func applyRulesUnterstuetztMehrereBedingungenMitOR() throws {
    let tag = Tag(name: "Apple", colorHex: "#3B82F6")
    let rule = Rule(name: "Apple oder Mac", conditionField: "title", conditionOperator: "contains", conditionValue: "Apple")
    rule.conditionMatchMode = RuleMatchMode.any.rawValue
    rule.conditions = [
        RuleCondition(field: "title", conditionOperator: "contains", value: "Apple", sortOrder: 0),
        RuleCondition(field: "feedTitle", conditionOperator: "contains", value: "Mac", sortOrder: 1)
    ]
    rule.assignTag = tag
    let feed = Feed(url: "https://example.com/feed.xml", title: "Mac News")
    let article = Article(title: "Swift Update", feed: feed)

    RuleEngine.applyRules([rule], to: article, feed: feed)

    #expect(article.tags.map(\.name) == ["Apple"])
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleEngineTests -derivedDataPath /private/tmp/feedivo-m3-rule-wizard-derived-data
```

Expected: FAIL because `RuleCondition`, `RuleMatchMode`, and `Rule.conditions` do not exist yet.

- [ ] **Step 3: Add model helper types**

Create `Feedivo/Models/RuleMatchMode.swift`:

```swift
import SwiftUI

enum RuleMatchMode: String, CaseIterable, Identifiable {
    case all
    case any

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .all:
            L10n.ruleMatchModeAll
        case .any:
            L10n.ruleMatchModeAny
        }
    }

    static func normalized(_ rawValue: String) -> RuleMatchMode {
        RuleMatchMode(rawValue: rawValue) ?? .all
    }
}
```

Create `Feedivo/Models/RuleConditionField.swift`:

```swift
import SwiftUI

enum RuleConditionField: String, CaseIterable, Identifiable {
    case title
    case summary
    case feedTitle

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .title:
            L10n.ruleConditionFieldTitle
        case .summary:
            L10n.ruleConditionFieldSummary
        case .feedTitle:
            L10n.ruleConditionFieldFeedTitle
        }
    }
}
```

Create `Feedivo/Models/RuleConditionOperator.swift`:

```swift
import SwiftUI

enum RuleConditionOperator: String, CaseIterable, Identifiable {
    case contains
    case startsWith
    case endsWith

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .contains:
            L10n.ruleConditionOperatorContains
        case .startsWith:
            L10n.ruleConditionOperatorStartsWith
        case .endsWith:
            L10n.ruleConditionOperatorEndsWith
        }
    }
}
```

Create `Feedivo/Models/RuleCondition.swift`:

```swift
import Foundation
import SwiftData

@Model
class RuleCondition {
    var id: UUID
    var field: String
    var conditionOperator: String
    var value: String
    var sortOrder: Int

    @Relationship
    var rule: Rule?

    init(
        field: String,
        conditionOperator: String,
        value: String,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.field = field
        self.conditionOperator = conditionOperator
        self.value = value
        self.sortOrder = sortOrder
    }
}
```

- [ ] **Step 4: Extend Rule and ModelContainer**

Modify `Feedivo/Models/Rule.swift`:

```swift
@Relationship(deleteRule: .cascade, inverse: \RuleCondition.rule)
var conditions: [RuleCondition]

var conditionMatchMode: String
```

Update `init`:

```swift
self.conditionMatchMode = RuleMatchMode.all.rawValue
self.conditions = []
```

Modify `Feedivo/App/FeedivoApp.swift` so the container includes:

```swift
RuleCondition.self,
```

- [ ] **Step 5: Run focused test and fix schema compile issues**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleEngineTests -derivedDataPath /private/tmp/feedivo-m3-rule-wizard-derived-data
```

Expected after this task: compile succeeds, new tests still fail because `RuleEngine` does not yet read `conditions`.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Models/Rule.swift Feedivo/Models/RuleCondition.swift Feedivo/Models/RuleMatchMode.swift Feedivo/Models/RuleConditionField.swift Feedivo/Models/RuleConditionOperator.swift Feedivo/App/FeedivoApp.swift FeedivoTests/RuleEngineTests.swift
git commit -m "feat: add rule condition model"
```

---

### Task 2: Update RuleEngine For AND/OR Conditions

**Files:**
- Modify: `Feedivo/Services/RuleEngine.swift`
- Test: `FeedivoTests/RuleEngineTests.swift`

- [ ] **Step 1: Add failing tests for empty and invalid condition lists**

Add to `FeedivoTests/RuleEngineTests.swift`:

```swift
@MainActor
@Test func applyRulesIgnoriertRegelnOhneGueltigeConditions() throws {
    let tag = Tag(name: "Swift", colorHex: "#3B82F6")
    let rule = Rule(name: "Leer", conditionField: "title", conditionOperator: "contains", conditionValue: "Swift")
    rule.conditions = [
        RuleCondition(field: "title", conditionOperator: "contains", value: "   ", sortOrder: 0),
        RuleCondition(field: "author", conditionOperator: "contains", value: "Swift", sortOrder: 1)
    ]
    rule.assignTag = tag
    let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
    let article = Article(title: "Swift News", feed: feed)

    RuleEngine.applyRules([rule], to: article, feed: feed)

    #expect(article.tags.isEmpty)
}
```

- [ ] **Step 2: Run focused test and verify it fails**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleEngineTests -derivedDataPath /private/tmp/feedivo-m3-rule-wizard-derived-data
```

Expected: FAIL because the engine still evaluates only the legacy single fields.

- [ ] **Step 3: Replace engine matching with condition-list matching**

Modify `Feedivo/Services/RuleEngine.swift` around matching:

```swift
private static func matches(rule: Rule, article: Article, feed: Feed) -> Bool {
    let conditions = normalizedConditions(for: rule)
    guard !conditions.isEmpty else {
        return false
    }

    let mode = RuleMatchMode.normalized(rule.conditionMatchMode)
    switch mode {
    case .all:
        return conditions.allSatisfy { matches(condition: $0, article: article, feed: feed) }
    case .any:
        return conditions.contains { matches(condition: $0, article: article, feed: feed) }
    }
}

private static func normalizedConditions(for rule: Rule) -> [RuleCondition] {
    rule.conditions
        .sorted { $0.sortOrder < $1.sortOrder }
        .filter { condition in
            !condition.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
}

private static func matches(condition: RuleCondition, article: Article, feed: Feed) -> Bool {
    let value = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty,
          let fieldValue = fieldValue(for: condition.field, article: article, feed: feed)
    else {
        return false
    }

    let normalizedFieldValue = fieldValue.lowercased()
    let normalizedValue = value.lowercased()

    switch condition.conditionOperator {
    case RuleConditionOperator.contains.rawValue:
        return normalizedFieldValue.contains(normalizedValue)
    case RuleConditionOperator.startsWith.rawValue:
        return normalizedFieldValue.hasPrefix(normalizedValue)
    case RuleConditionOperator.endsWith.rawValue:
        return normalizedFieldValue.hasSuffix(normalizedValue)
    default:
        return false
    }
}

private static func fieldValue(for field: String, article: Article, feed: Feed) -> String? {
    switch field {
    case RuleConditionField.title.rawValue:
        return article.title
    case RuleConditionField.summary.rawValue:
        return article.summary
    case RuleConditionField.feedTitle.rawValue:
        return feed.title
    default:
        return nil
    }
}
```

Keep `applyRules` duplicate-tag behavior unchanged.

- [ ] **Step 4: Update legacy tests to populate conditions**

In the existing single-condition tests, after creating each `Rule`, add:

```swift
rule.conditions = [
    RuleCondition(
        field: rule.conditionField,
        conditionOperator: rule.conditionOperator,
        value: rule.conditionValue
    )
]
```

- [ ] **Step 5: Run focused test and verify it passes**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleEngineTests -derivedDataPath /private/tmp/feedivo-m3-rule-wizard-derived-data
```

Expected: TEST SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/RuleEngine.swift FeedivoTests/RuleEngineTests.swift
git commit -m "feat: evaluate multi-condition rules"
```

---

### Task 3: Add Legacy Rule Backfill

**Files:**
- Create: `Feedivo/Services/RuleConditionBackfillService.swift`
- Modify: `Feedivo/App/FeedivoApp.swift`
- Test: `FeedivoTests/RuleConditionBackfillServiceTests.swift`

- [ ] **Step 1: Write failing backfill tests**

Create `FeedivoTests/RuleConditionBackfillServiceTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct RuleConditionBackfillServiceTests {
    @MainActor
    @Test func backfillErstelltConditionAusLegacyFeldern() throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let rule = Rule(name: "Alt", conditionField: "title", conditionOperator: "contains", conditionValue: "Swift")
        context.insert(rule)
        try context.save()

        try RuleConditionBackfillService.backfillMissingConditions(context: context)

        #expect(rule.conditions.count == 1)
        #expect(rule.conditions.first?.field == "title")
        #expect(rule.conditions.first?.conditionOperator == "contains")
        #expect(rule.conditions.first?.value == "Swift")
    }

    @MainActor
    @Test func backfillUeberspringtRegelnMitVorhandenenConditions() throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let rule = Rule(name: "Neu", conditionField: "title", conditionOperator: "contains", conditionValue: "Legacy")
        rule.conditions = [RuleCondition(field: "summary", conditionOperator: "contains", value: "Modern")]
        context.insert(rule)
        try context.save()

        try RuleConditionBackfillService.backfillMissingConditions(context: context)

        #expect(rule.conditions.count == 1)
        #expect(rule.conditions.first?.field == "summary")
        #expect(rule.conditions.first?.value == "Modern")
    }
}
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleConditionBackfillServiceTests -derivedDataPath /private/tmp/feedivo-m3-rule-wizard-derived-data
```

Expected: FAIL because `RuleConditionBackfillService` does not exist.

- [ ] **Step 3: Implement the service**

Create `Feedivo/Services/RuleConditionBackfillService.swift`:

```swift
import Foundation
import SwiftData

enum RuleConditionBackfillService {
    static func backfillMissingConditions(context: ModelContext) throws {
        let rules = try context.fetch(FetchDescriptor<Rule>())

        for rule in rules where rule.conditions.isEmpty {
            let value = rule.conditionValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                continue
            }

            let condition = RuleCondition(
                field: rule.conditionField,
                conditionOperator: rule.conditionOperator,
                value: value,
                sortOrder: 0
            )
            condition.rule = rule
            rule.conditions = [condition]
        }

        try context.save()
    }
}
```

- [ ] **Step 4: Call the service at app startup**

In `Feedivo/App/FeedivoApp.swift`, after creating the model container:

```swift
let context = ModelContext(modelContainer)
try? RuleConditionBackfillService.backfillMissingConditions(context: context)
```

- [ ] **Step 5: Run backfill tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleConditionBackfillServiceTests -derivedDataPath /private/tmp/feedivo-m3-rule-wizard-derived-data
```

Expected: TEST SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/RuleConditionBackfillService.swift Feedivo/App/FeedivoApp.swift FeedivoTests/RuleConditionBackfillServiceTests.swift
git commit -m "feat: backfill legacy rule conditions"
```

---

### Task 4: Add RuleViewModel Validation And Persistence

**Files:**
- Create: `Feedivo/ViewModels/RuleViewModel.swift`
- Test: `FeedivoTests/RuleViewModelTests.swift`

- [ ] **Step 1: Write failing ViewModel tests**

Create `FeedivoTests/RuleViewModelTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct RuleViewModelTests {
    @MainActor
    @Test func createRuleSpeichertGueltigePowerUserRegel() throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let tag = Tag(name: "Swift", colorHex: "#3B82F6")
        context.insert(tag)
        let viewModel = RuleViewModel()

        viewModel.createRule(
            name: "Swift Mac",
            isEnabled: true,
            matchMode: .all,
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift"),
                RuleConditionDraft(field: .feedTitle, conditionOperator: .contains, value: "Mac")
            ],
            assignTag: tag,
            context: context
        )

        let rules = try context.fetch(FetchDescriptor<Rule>())
        #expect(rules.count == 1)
        #expect(rules.first?.name == "Swift Mac")
        #expect(rules.first?.conditionMatchMode == RuleMatchMode.all.rawValue)
        #expect(rules.first?.conditions.count == 2)
        #expect(rules.first?.assignTag?.name == "Swift")
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func createRuleVerhindertUngueltigeEingaben() throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let viewModel = RuleViewModel()

        viewModel.createRule(
            name: "   ",
            isEnabled: true,
            matchMode: .all,
            conditionDrafts: [RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift")],
            assignTag: nil,
            context: context
        )

        let rules = try context.fetch(FetchDescriptor<Rule>())
        #expect(rules.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }
}
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleViewModelTests -derivedDataPath /private/tmp/feedivo-m3-rule-wizard-derived-data
```

Expected: FAIL because `RuleViewModel` and `RuleConditionDraft` do not exist.

- [ ] **Step 3: Implement ViewModel**

Create `Feedivo/ViewModels/RuleViewModel.swift`:

```swift
import Foundation
import Observation
import SwiftData

struct RuleConditionDraft: Identifiable, Equatable {
    var id = UUID()
    var field: RuleConditionField
    var conditionOperator: RuleConditionOperator
    var value: String
}

@Observable
@MainActor
final class RuleViewModel {
    var errorMessage: String?

    func createRule(
        name: String,
        isEnabled: Bool,
        matchMode: RuleMatchMode,
        conditionDrafts: [RuleConditionDraft],
        assignTag: Tag?,
        context: ModelContext
    ) {
        guard let normalizedName = normalizedName(name),
              let assignTag,
              let conditions = normalizedConditions(from: conditionDrafts)
        else {
            errorMessage = L10n.ruleValidationError
            return
        }

        let firstCondition = conditions[0]
        let rule = Rule(
            name: normalizedName,
            conditionField: firstCondition.field,
            conditionOperator: firstCondition.conditionOperator,
            conditionValue: firstCondition.value
        )
        rule.isEnabled = isEnabled
        rule.conditionMatchMode = matchMode.rawValue
        rule.assignTag = assignTag
        rule.conditions = conditions.enumerated().map { index, condition in
            RuleCondition(
                field: condition.field,
                conditionOperator: condition.conditionOperator,
                value: condition.value,
                sortOrder: index
            )
        }

        context.insert(rule)
        save(context)
    }

    func updateRule(
        _ rule: Rule,
        name: String,
        isEnabled: Bool,
        matchMode: RuleMatchMode,
        conditionDrafts: [RuleConditionDraft],
        assignTag: Tag?,
        context: ModelContext
    ) {
        guard let normalizedName = normalizedName(name),
              let assignTag,
              let conditions = normalizedConditions(from: conditionDrafts)
        else {
            errorMessage = L10n.ruleValidationError
            return
        }

        rule.name = normalizedName
        rule.isEnabled = isEnabled
        rule.conditionMatchMode = matchMode.rawValue
        rule.assignTag = assignTag
        rule.conditionField = conditions[0].field
        rule.conditionOperator = conditions[0].conditionOperator
        rule.conditionValue = conditions[0].value
        rule.conditions.removeAll()
        rule.conditions = conditions.enumerated().map { index, condition in
            RuleCondition(
                field: condition.field,
                conditionOperator: condition.conditionOperator,
                value: condition.value,
                sortOrder: index
            )
        }

        save(context)
    }

    func deleteRule(_ rule: Rule, context: ModelContext) {
        context.delete(rule)
        save(context)
    }

    private func normalizedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedConditions(from drafts: [RuleConditionDraft]) -> [(field: String, conditionOperator: String, value: String)]? {
        let conditions = drafts.compactMap { draft -> (field: String, conditionOperator: String, value: String)? in
            let value = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return nil
            }

            return (draft.field.rawValue, draft.conditionOperator.rawValue, value)
        }

        return conditions.isEmpty ? nil : conditions
    }

    private func save(_ context: ModelContext) {
        do {
            try context.save()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Run ViewModel tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleViewModelTests -derivedDataPath /private/tmp/feedivo-m3-rule-wizard-derived-data
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/ViewModels/RuleViewModel.swift FeedivoTests/RuleViewModelTests.swift
git commit -m "feat: add rule view model"
```

---

### Task 5: Build Settings Rule List

**Files:**
- Create: `Feedivo/Views/Rules/RuleSettingsView.swift`
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [ ] **Step 1: Add localized keys**

Add to `Feedivo/Resources/L10n.swift`:

```swift
static let settingsRulesSection = LocalizedStringKey("settings.rules.section")
static let ruleCreateButton = LocalizedStringKey("rule.create.button")
static let ruleEditButton = LocalizedStringKey("rule.edit.button")
static let ruleDeleteButton = LocalizedStringKey("rule.delete.button")
static let ruleNoRules = LocalizedStringKey("rule.noRules")
static let ruleEnabled = LocalizedStringKey("rule.enabled")
static let ruleMatchModeAll = LocalizedStringKey("rule.matchMode.all")
static let ruleMatchModeAny = LocalizedStringKey("rule.matchMode.any")
static let ruleConditionFieldTitle = LocalizedStringKey("rule.condition.field.title")
static let ruleConditionFieldSummary = LocalizedStringKey("rule.condition.field.summary")
static let ruleConditionFieldFeedTitle = LocalizedStringKey("rule.condition.field.feedTitle")
static let ruleConditionOperatorContains = LocalizedStringKey("rule.condition.operator.contains")
static let ruleConditionOperatorStartsWith = LocalizedStringKey("rule.condition.operator.startsWith")
static let ruleConditionOperatorEndsWith = LocalizedStringKey("rule.condition.operator.endsWith")

static var ruleValidationError: String { String(localized: "rule.validation.error") }
```

Add matching German, English, French, and Italian entries to `Localizable.xcstrings`. Use German as source text and straightforward translations:

```text
settings.rules.section = Regeln
rule.create.button = Regel erstellen
rule.edit.button = Bearbeiten
rule.delete.button = Loeschen
rule.noRules = Noch keine Regeln
rule.enabled = Aktiv
rule.matchMode.all = Alle Bedingungen
rule.matchMode.any = Eine Bedingung reicht
rule.condition.field.title = Titel
rule.condition.field.summary = Zusammenfassung
rule.condition.field.feedTitle = Feedname
rule.condition.operator.contains = enthaelt
rule.condition.operator.startsWith = beginnt mit
rule.condition.operator.endsWith = endet mit
rule.validation.error = Bitte Name, Ziel-Tag und mindestens eine Bedingung ausfuellen.
```

- [ ] **Step 2: Create the settings list view**

Create `Feedivo/Views/Rules/RuleSettingsView.swift`:

```swift
import SwiftData
import SwiftUI

struct RuleSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Rule.name) private var rules: [Rule]
    @State private var viewModel = RuleViewModel()
    @State private var ruleEditing: Rule?
    @State private var isCreatingRule = false
    @State private var rulePendingDeletion: Rule?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.settingsRulesSection)
                    .font(.headline)
                Spacer()
                Button(L10n.ruleCreateButton) {
                    isCreatingRule = true
                }
            }

            if rules.isEmpty {
                ContentUnavailableView(L10n.ruleNoRules, systemImage: "slider.horizontal.3")
                    .frame(minHeight: 120)
            } else {
                ForEach(rules) { rule in
                    RuleSettingsRow(
                        rule: rule,
                        edit: { ruleEditing = rule },
                        delete: { rulePendingDeletion = rule }
                    )
                }
            }
        }
        .sheet(isPresented: $isCreatingRule) {
            RuleWizardView()
        }
        .sheet(item: $ruleEditing) { rule in
            RuleWizardView(rule: rule)
        }
        .confirmationDialog(
            L10n.ruleDeleteButton,
            isPresented: Binding(
                get: { rulePendingDeletion != nil },
                set: { if !$0 { rulePendingDeletion = nil } }
            ),
            presenting: rulePendingDeletion
        ) { rule in
            Button(L10n.ruleDeleteButton, role: .destructive) {
                viewModel.deleteRule(rule, context: modelContext)
                rulePendingDeletion = nil
            }
            Button(L10n.commonCancel, role: .cancel) {
                rulePendingDeletion = nil
            }
        }
    }
}

private struct RuleSettingsRow: View {
    @Environment(\.modelContext) private var modelContext
    let rule: Rule
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(L10n.ruleEnabled, isOn: Binding(
                get: { rule.isEnabled },
                set: { rule.isEnabled = $0; try? modelContext.save() }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.body)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(L10n.ruleEditButton, action: edit)
            Button(L10n.ruleDeleteButton, role: .destructive, action: delete)
        }
    }

    private var summary: String {
        let mode = RuleMatchMode.normalized(rule.conditionMatchMode) == .all ? "AND" : "OR"
        let tagName = rule.assignTag?.name ?? "-"
        return "\(rule.conditions.count) Bedingungen · \(mode) · Tag: \(tagName)"
    }
}
```

- [ ] **Step 3: Insert into SettingsView**

In `Feedivo/Views/Settings/SettingsView.swift`, add before the Reading section:

```swift
Section {
    RuleSettingsView()
}
```

- [ ] **Step 4: Build to catch UI compile errors**

Run:

```bash
xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -derivedDataPath /private/tmp/feedivo-m3-rule-wizard-derived-data
```

Expected: build may fail because `RuleWizardView` does not exist yet. If so, create a minimal placeholder:

```swift
import SwiftUI

struct RuleWizardView: View {
    var rule: Rule?

    var body: some View {
        Text("Rule Wizard")
            .padding()
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Rules/RuleSettingsView.swift Feedivo/Views/Rules/RuleWizardView.swift Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat: show rules in settings"
```

---

### Task 6: Build Rule Wizard Create/Edit Flow

**Files:**
- Modify: `Feedivo/Views/Rules/RuleWizardView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [ ] **Step 1: Add wizard localization keys**

Add keys for:

```text
ruleWizard.title.create = Regel erstellen
ruleWizard.title.edit = Regel bearbeiten
ruleWizard.mode.title = Modus
ruleWizard.mode.simple = Einfach
ruleWizard.mode.power = Power User
ruleWizard.conditions.title = Bedingungen
ruleWizard.target.title = Ziel-Tag
ruleWizard.summary.title = Zusammenfassung
ruleWizard.name.placeholder = Regelname
ruleWizard.value.placeholder = Suchwert
ruleWizard.addCondition = Bedingung hinzufuegen
ruleWizard.removeCondition = Bedingung entfernen
ruleWizard.save = Speichern
```

Expose the keys in `L10n.swift` as `LocalizedStringKey` or `String` matching existing usage.

- [ ] **Step 2: Replace placeholder with working wizard**

Implement `RuleWizardView` with local state:

```swift
enum RuleWizardMode: String, CaseIterable, Identifiable {
    case simple
    case power
    var id: String { rawValue }
}
```

Use:

```swift
@Environment(\.dismiss) private var dismiss
@Environment(\.modelContext) private var modelContext
@Query(sort: \Tag.name) private var tags: [Tag]
@State private var viewModel = RuleViewModel()
@State private var mode: RuleWizardMode = .simple
@State private var name = ""
@State private var isEnabled = true
@State private var matchMode = RuleMatchMode.all
@State private var conditionDrafts = [RuleConditionDraft(field: .title, conditionOperator: .contains, value: "")]
@State private var selectedTag: Tag?
```

In `body`, use a `VStack` with:

- Header title create/edit.
- Segmented picker for mode.
- TextField for name.
- Toggle for enabled.
- If `mode == .power`, segmented picker for matchMode.
- Conditions list with Picker field, Picker operator, TextField value.
- Add/remove condition buttons visible in power mode.
- Tag picker.
- Error text from `viewModel.errorMessage`.
- Cancel and Save buttons.

On appear, if editing an existing rule, populate state:

```swift
private func loadRuleIfNeeded() {
    guard let rule else { return }
    name = rule.name
    isEnabled = rule.isEnabled
    matchMode = RuleMatchMode.normalized(rule.conditionMatchMode)
    conditionDrafts = rule.conditions
        .sorted { $0.sortOrder < $1.sortOrder }
        .compactMap { condition in
            guard let field = RuleConditionField(rawValue: condition.field),
                  let op = RuleConditionOperator(rawValue: condition.conditionOperator)
            else { return nil }
            return RuleConditionDraft(field: field, conditionOperator: op, value: condition.value)
        }
    if conditionDrafts.isEmpty {
        conditionDrafts = [RuleConditionDraft(field: .title, conditionOperator: .contains, value: "")]
    }
    selectedTag = rule.assignTag
    mode = conditionDrafts.count > 1 ? .power : .simple
}
```

Save:

```swift
private func save() {
    let drafts = mode == .simple ? Array(conditionDrafts.prefix(1)) : conditionDrafts
    if let rule {
        viewModel.updateRule(rule, name: name, isEnabled: isEnabled, matchMode: matchMode, conditionDrafts: drafts, assignTag: selectedTag, context: modelContext)
    } else {
        viewModel.createRule(name: name, isEnabled: isEnabled, matchMode: matchMode, conditionDrafts: drafts, assignTag: selectedTag, context: modelContext)
    }

    if viewModel.errorMessage == nil {
        dismiss()
    }
}
```

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -derivedDataPath /private/tmp/feedivo-m3-rule-wizard-derived-data
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/Rules/RuleWizardView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat: add rule wizard"
```

---

### Task 7: Add Sidebar Rule Entry From Current Article

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/Views/Rules/RuleWizardView.swift`

- [ ] **Step 1: Extend RuleWizardView initializer with article context**

Add:

```swift
let rule: Rule?
let sourceArticle: Article?

init(rule: Rule? = nil, sourceArticle: Article? = nil) {
    self.rule = rule
    self.sourceArticle = sourceArticle
}
```

In load, when `rule == nil` and `sourceArticle != nil`, prefill:

```swift
private func loadSourceArticleIfNeeded() {
    guard rule == nil, let sourceArticle else { return }
    let feedTitle = sourceArticle.feed?.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if let feedTitle, !feedTitle.isEmpty {
        conditionDrafts = [
            RuleConditionDraft(field: .feedTitle, conditionOperator: .contains, value: feedTitle)
        ]
        name = feedTitle
    }
}
```

- [ ] **Step 2: Pass selected article into Sidebar**

Modify `SidebarView` initializer properties:

```swift
let selectedArticle: Article?
let onRequestCreateRuleFromArticle: (Article) -> Void
```

Modify `ContentView` call:

```swift
SidebarView(
    selection: $sidebarSelection,
    selectedArticle: selectedArticle,
    onRequestAddFeed: requestAddFeed,
    onRequestDeleteFeed: requestDeleteFeed,
    onRequestCreateRuleFromArticle: requestCreateRuleFromArticle
)
```

Add state to `ContentView`:

```swift
@State private var articleForRuleCreation: Article?
```

Add sheet:

```swift
.sheet(item: $articleForRuleCreation) { article in
    RuleWizardView(sourceArticle: article)
}
```

Add method:

```swift
private func requestCreateRuleFromArticle(_ article: Article) {
    articleForRuleCreation = article
}
```

- [ ] **Step 3: Add compact Sidebar section**

In `SidebarView`, query rules:

```swift
@Query(sort: \Rule.name) private var rules: [Rule]
```

Add `rulesSection` between tags and folders:

```swift
private var rulesSection: some View {
    SidebarActionSection(
        title: L10n.sidebarRulesSection,
        actionSystemImage: "slider.horizontal.3",
        actionHelp: L10n.ruleCreateFromArticle
    ) {
        if let selectedArticle {
            onRequestCreateRuleFromArticle(selectedArticle)
        }
    } content: {
        Text(L10n.sidebarRulesActiveCount(count: rules.filter(\.isEnabled).count))
            .font(interfaceTextSize.font(size: 13))
            .foregroundStyle(SidebarStyle.darkSecondaryText)
            .padding(.horizontal, 10)
    }
}
```

Disable or hide the action button if `selectedArticle == nil`. If `SidebarActionSection` cannot disable its action button, add an optional `isActionDisabled` parameter with default `false`.

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -derivedDataPath /private/tmp/feedivo-m3-rule-wizard-derived-data
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarView.swift Feedivo/Views/ContentView.swift Feedivo/Views/Rules/RuleWizardView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat: add sidebar rule creation entry"
```

---

### Task 8: Update Existing Containers And Feed Refresh Tests

**Files:**
- Modify: `FeedivoTests/FeedViewModelTests.swift`
- Modify: other tests that construct `ModelContainer`

- [ ] **Step 1: Update every in-memory ModelContainer schema**

Where tests use:

```swift
for: Feed.self,
Article.self,
Tag.self,
Rule.self,
FeedLogEntry.self,
```

insert:

```swift
RuleCondition.self,
```

- [ ] **Step 2: Update the refresh rule test**

In `refreshFeedWendetRegelnAufNeueArtikelAn`, after creating the rule, add:

```swift
rule.conditions = [
    RuleCondition(field: "title", conditionOperator: "contains", value: "Swift")
]
```

- [ ] **Step 3: Run unit tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -skip-testing:FeedivoUITests -derivedDataPath /private/tmp/feedivo-m3-rule-wizard-derived-data
```

Expected: TEST SUCCEEDED. If tests fail because a container missed `RuleCondition.self`, update that container and rerun.

- [ ] **Step 4: Commit**

```bash
git add FeedivoTests
git commit -m "test: update rule condition schemas"
```

---

### Task 9: Documentation And Final Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`

- [ ] **Step 1: Update project memory**

In `AGENTS.md`:

- Add `RuleCondition.swift`, `RuleMatchMode.swift`, `RuleConditionField.swift`, and `RuleConditionOperator.swift` to the model section.
- Mark `RuleListView`/`AddRuleView` replacement as `RuleWizardView` and `RuleSettingsView`.
- Update `RuleEngine.swift` description to mention multi-condition `AND`/`OR`.
- Update M3 checklist: `Regel-UI` done, multi-condition rules done.
- Update `Aktuell in Arbeit` so next focus is Feed-Tags or iCloud Sync.
- Add latest change note dated `2026-06-21`.

In `docs/FEATURES.md`:

- Mark automatic rules as UI-enabled.
- Mention Settings list and wizard.
- Keep Regex, retroactive application, nested groups, and further actions as open.

- [ ] **Step 2: Run final verification**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -skip-testing:FeedivoUITests -derivedDataPath /private/tmp/feedivo-m3-rule-wizard-derived-data
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 3: Check git status**

Run:

```bash
git status --short --branch
```

Expected: only intentional changes plus the known Xcode `UserInterfaceState.xcuserstate` file.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md docs/FEATURES.md
git commit -m "docs: update m3 rule wizard status"
```

---

## Execution Notes

- Use TDD for Tasks 1-4 and Task 8. Watch the focused test fail before writing production code.
- Keep the old single-condition fields on `Rule` during this milestone. Removing them is a later migration step.
- Avoid turning Sidebar into a management surface. Settings is the source of truth for rule management.
- Do not implement regex, nested condition groups, retroactive application, or non-tag actions in this block.
- Do not stage `Feedivo.xcodeproj/project.xcworkspace/xcuserdata/martinfelder.xcuserdatad/UserInterfaceState.xcuserstate`.

## Self-Review

- Spec coverage: The plan covers model migration, multi-condition engine behavior, wizard create/edit flow, settings list, sidebar article-context entry, tests, and documentation.
- Placeholder scan: No implementation placeholders are left in the plan; deferred features are explicitly out of scope.
- Type consistency: Stored values use `RuleMatchMode`, `RuleConditionField`, and `RuleConditionOperator` consistently; `RuleViewModel` writes both legacy fields and new conditions.
