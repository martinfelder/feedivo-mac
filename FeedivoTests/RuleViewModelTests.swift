import Foundation
import Testing
@testable import Feedivo

struct RuleViewModelTests {
    @MainActor
    @Test func createRuleSpeichertGueltigePowerUserRegel() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let tagStore = TagStore(database: database)
        let ruleStore = SQLiteRuleStore(database: database)
        let viewModel = RuleViewModel()

        let tag = TagRecord(id: "tag-1", name: "Swift", colorHex: "#3B82F6")
        try tagStore.save(tag)

        viewModel.createRule(
            name: "Swift Mac",
            isEnabled: true,
            matchMode: .all,
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift"),
                RuleConditionDraft(field: .feedTitle, conditionOperator: .contains, value: "Mac")
            ],
            assignTag: tag,
            database: database
        )

        let rules = try ruleStore.rules()
        #expect(rules.count == 1)
        let rule = try #require(rules.first { $0.name == "Swift Mac" })
        #expect(rule.matchMode == RuleMatchMode.all.rawValue)
        #expect(rule.action == RuleAction.assignTag.rawValue)
        #expect(rule.assignTagID == tag.id)
        #expect(viewModel.errorMessage == nil)

        let conditions = try ruleStore.conditions(ruleID: rule.id)
        #expect(conditions.count == 2)
        #expect(conditions.map(\.value).sorted() == ["Mac", "Swift"])
    }

    @MainActor
    @Test func createRuleSetztNaechsteSortierreihenfolge() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let ruleStore = SQLiteRuleStore(database: database)
        let viewModel = RuleViewModel()

        try ruleStore.save(RuleRecord(id: "rule-1", name: "Vorhanden", sortOrder: 4), conditions: [])

        viewModel.createRule(
            name: "Neu",
            isEnabled: true,
            action: .notify,
            matchMode: .all,
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Mac")
            ],
            assignTag: nil,
            existingRules: try ruleStore.rules(),
            database: database
        )

        let newRule = try #require(try ruleStore.rules().first { $0.name == "Neu" })
        #expect(newRule.sortOrder == 5)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func duplicateRuleFuegtKopieHintenAn() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let ruleStore = SQLiteRuleStore(database: database)
        let viewModel = RuleViewModel()

        let firstRule = RuleRecord(id: "rule-1", name: "Erste Regel", sortOrder: 0)
        let secondRule = RuleRecord(id: "rule-2", name: "Zweite Regel", sortOrder: 1)
        try ruleStore.save(
            firstRule,
            conditions: [
                RuleConditionRecord(
                    ruleID: firstRule.id,
                    field: RuleConditionField.title.rawValue,
                    conditionOperator: RuleConditionOperator.contains.rawValue,
                    value: "Swift",
                    sortOrder: 0
                )
            ]
        )
        try ruleStore.save(secondRule, conditions: [])

        viewModel.duplicateRule(firstRule, existingRules: [firstRule, secondRule], database: database)

        let orderedNames = RuleViewModel.sortedRules(try ruleStore.rules()).map(\.name)
        #expect(orderedNames == ["Erste Regel", "Zweite Regel", "Erste Regel Kopie"])

        let duplicate = try #require(try ruleStore.rules().first { $0.name == "Erste Regel Kopie" })
        #expect(duplicate.sortOrder == 2)
        #expect(try ruleStore.conditions(ruleID: duplicate.id).count == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func moveRuleAktualisiertSortierreihenfolge() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let ruleStore = SQLiteRuleStore(database: database)
        let viewModel = RuleViewModel()
        let firstRule = RuleRecord(id: "rule-a", name: "A", sortOrder: 0)
        let secondRule = RuleRecord(id: "rule-b", name: "B", sortOrder: 1)
        let thirdRule = RuleRecord(id: "rule-c", name: "C", sortOrder: 2)
        try ruleStore.save(firstRule, conditions: [])
        try ruleStore.save(secondRule, conditions: [])
        try ruleStore.save(thirdRule, conditions: [])

        viewModel.moveRule(secondRule, direction: .up, existingRules: [firstRule, secondRule, thirdRule], database: database)

        let orderedNames = RuleViewModel.sortedRules(try ruleStore.rules()).map(\.name)
        #expect(orderedNames == ["B", "A", "C"])
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func moveRuleToPositionOfTargetVerschiebtZeileBeimDragNachUnten() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let ruleStore = SQLiteRuleStore(database: database)
        let viewModel = RuleViewModel()
        let firstRule = RuleRecord(id: "rule-a", name: "A", sortOrder: 0)
        let secondRule = RuleRecord(id: "rule-b", name: "B", sortOrder: 1)
        let thirdRule = RuleRecord(id: "rule-c", name: "C", sortOrder: 2)
        try ruleStore.save(firstRule, conditions: [])
        try ruleStore.save(secondRule, conditions: [])
        try ruleStore.save(thirdRule, conditions: [])

        viewModel.moveRule(firstRule, toPositionOf: thirdRule, existingRules: [firstRule, secondRule, thirdRule], database: database)

        let orderedNames = RuleViewModel.sortedRules(try ruleStore.rules()).map(\.name)
        #expect(orderedNames == ["B", "C", "A"])
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func moveRuleToPositionOfTargetVerschiebtZeileBeimDragNachOben() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let ruleStore = SQLiteRuleStore(database: database)
        let viewModel = RuleViewModel()
        let firstRule = RuleRecord(id: "rule-a", name: "A", sortOrder: 0)
        let secondRule = RuleRecord(id: "rule-b", name: "B", sortOrder: 1)
        let thirdRule = RuleRecord(id: "rule-c", name: "C", sortOrder: 2)
        try ruleStore.save(firstRule, conditions: [])
        try ruleStore.save(secondRule, conditions: [])
        try ruleStore.save(thirdRule, conditions: [])

        viewModel.moveRule(thirdRule, toPositionOf: firstRule, existingRules: [firstRule, secondRule, thirdRule], database: database)

        let orderedNames = RuleViewModel.sortedRules(try ruleStore.rules()).map(\.name)
        #expect(orderedNames == ["C", "A", "B"])
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func createRuleSpeichertHideAktionOhneZielTag() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let ruleStore = SQLiteRuleStore(database: database)
        let viewModel = RuleViewModel()

        viewModel.createRule(
            name: "Spoiler ausblenden",
            isEnabled: true,
            action: .hideArticle,
            matchMode: .all,
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Spoiler")
            ],
            assignTag: nil,
            database: database
        )

        let rules = try ruleStore.rules()
        #expect(rules.count == 1)
        let rule = try #require(rules.first)
        #expect(rule.action == RuleAction.hideArticle.rawValue)
        #expect(rule.assignTagID == nil)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func createRuleSpeichertBenachrichtigungsAktionMitTextUndPrioritaet() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let ruleStore = SQLiteRuleStore(database: database)
        let viewModel = RuleViewModel()

        viewModel.createRule(
            name: "Breaking",
            isEnabled: true,
            action: .notify,
            matchMode: .all,
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift")
            ],
            assignTag: nil,
            notificationTemplate: "Breaking: {Titel}",
            notificationPriority: .critical,
            database: database
        )

        let rule = try #require(try ruleStore.rules().first)
        #expect(rule.action == RuleAction.notify.rawValue)
        #expect(rule.assignTagID == nil)
        #expect(rule.notificationTemplate == "Breaking: {Titel}")
        #expect(rule.notificationPriority == RuleNotificationPriority.critical.rawValue)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func createRuleVerhindertUngueltigeEingaben() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let ruleStore = SQLiteRuleStore(database: database)
        let viewModel = RuleViewModel()

        viewModel.createRule(
            name: "   ",
            isEnabled: true,
            matchMode: .all,
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift")
            ],
            assignTag: nil,
            database: database
        )

        #expect((try ruleStore.rules()).isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    @MainActor
    @Test func createRuleVerhindertUngueltigeRegexBedingung() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let tagStore = TagStore(database: database)
        let ruleStore = SQLiteRuleStore(database: database)
        let viewModel = RuleViewModel()
        let tag = TagRecord(id: "tag-1", name: "Swift", colorHex: "#3B82F6")
        try tagStore.save(tag)

        viewModel.createRule(
            name: "Regex",
            isEnabled: true,
            matchMode: .all,
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .regex, value: "[")
            ],
            assignTag: tag,
            database: database
        )

        #expect((try ruleStore.rules()).isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    @MainActor
    @Test func deleteRuleEntferntZugehoerigeConditions() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let ruleStore = SQLiteRuleStore(database: database)
        let viewModel = RuleViewModel()
        let rule = RuleRecord(id: "rule-1", name: "Regel")
        let firstCondition = RuleConditionRecord(
            id: "condition-1",
            ruleID: rule.id,
            field: RuleConditionField.title.rawValue,
            conditionOperator: RuleConditionOperator.contains.rawValue,
            value: "Swift",
            sortOrder: 0
        )
        let secondCondition = RuleConditionRecord(
            id: "condition-2",
            ruleID: rule.id,
            field: RuleConditionField.summary.rawValue,
            conditionOperator: RuleConditionOperator.contains.rawValue,
            value: "Mac",
            sortOrder: 1
        )
        try ruleStore.save(rule, conditions: [firstCondition, secondCondition])

        viewModel.deleteRule(rule, database: database)

        #expect((try ruleStore.rules()).isEmpty)
        #expect(try ruleStore.conditions(ruleID: rule.id).isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func updateRuleLoeschtAlteConditionsStattSieZuVerwaisten() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let tagStore = TagStore(database: database)
        let ruleStore = SQLiteRuleStore(database: database)
        let viewModel = RuleViewModel()
        let tag = TagRecord(id: "tag-1", name: "Swift", colorHex: "#3B82F6")
        try tagStore.save(tag)
        let rule = RuleRecord(id: "rule-1", name: "Alt")
        let originalConditions = [
            RuleConditionRecord(
                id: "condition-1",
                ruleID: rule.id,
                field: RuleConditionField.title.rawValue,
                conditionOperator: RuleConditionOperator.contains.rawValue,
                value: "A",
                sortOrder: 0
            ),
            RuleConditionRecord(
                id: "condition-2",
                ruleID: rule.id,
                field: RuleConditionField.title.rawValue,
                conditionOperator: RuleConditionOperator.contains.rawValue,
                value: "B",
                sortOrder: 1
            )
        ]
        try ruleStore.save(rule, conditions: originalConditions)

        viewModel.updateRule(
            rule,
            name: "Neu",
            isEnabled: true,
            matchMode: .all,
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "C")
            ],
            assignTag: tag,
            database: database
        )

        #expect(try ruleStore.conditions(ruleID: rule.id).count == 1)
        let updatedRule = try #require(try ruleStore.rule(id: rule.id))
        #expect(updatedRule.name == "Neu")
        #expect(updatedRule.assignTagID == tag.id)
        #expect(viewModel.errorMessage == nil)
    }
}
