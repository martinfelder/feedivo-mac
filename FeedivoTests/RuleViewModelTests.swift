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
        #expect(rules.first?.actionRaw == RuleAction.assignTag.rawValue)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func createRuleSetztNaechsteSortierreihenfolge() throws {
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
        let firstRule = Rule(name: "Vorhanden")
        firstRule.sortOrder = 4
        context.insert(firstRule)
        let viewModel = RuleViewModel()

        viewModel.createRule(
            name: "Neu",
            isEnabled: true,
            matchMode: .all,
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Mac")
            ],
            assignTag: tag,
            existingRules: [firstRule],
            context: context
        )

        let rules = try context.fetch(FetchDescriptor<Rule>())
        let newRule = try #require(rules.first { $0.name == "Neu" })
        #expect(newRule.sortOrder == 5)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func duplicateRuleFuegtKopieDirektNachOriginalEin() throws {
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
        let firstRule = Rule(name: "Erste Regel")
        firstRule.sortOrder = 0
        firstRule.assignTag = tag
        firstRule.conditions = [
            RuleCondition(
                field: RuleConditionField.title.rawValue,
                conditionOperator: RuleConditionOperator.contains.rawValue,
                value: "Swift",
                sortOrder: 0
            )
        ]
        let secondRule = Rule(name: "Zweite Regel")
        secondRule.sortOrder = 1
        context.insert(firstRule)
        context.insert(secondRule)
        let viewModel = RuleViewModel()

        viewModel.duplicateRule(firstRule, existingRules: [firstRule, secondRule], context: context)

        let rules = try context.fetch(FetchDescriptor<Rule>())
        let orderedNames = RuleViewModel.sortedRules(rules).map(\.name)
        #expect(orderedNames == ["Erste Regel", "Erste Regel Kopie", "Zweite Regel"])
        let duplicate = try #require(rules.first { $0.name == "Erste Regel Kopie" })
        #expect(duplicate.sortOrder == 1)
        #expect(duplicate.assignTag?.name == "Swift")
        #expect(duplicate.conditions.count == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func moveRuleAktualisiertSortierreihenfolge() throws {
        let firstRule = Rule(name: "A")
        firstRule.sortOrder = 0
        let secondRule = Rule(name: "B")
        secondRule.sortOrder = 1
        let thirdRule = Rule(name: "C")
        thirdRule.sortOrder = 2
        let viewModel = RuleViewModel()

        viewModel.moveRule(
            secondRule,
            direction: .up,
            existingRules: [firstRule, secondRule, thirdRule],
            context: nil
        )

        #expect(firstRule.sortOrder == 1)
        #expect(secondRule.sortOrder == 0)
        #expect(thirdRule.sortOrder == 2)
        #expect(RuleViewModel.sortedRules([firstRule, secondRule, thirdRule]).map(\.name) == ["B", "A", "C"])
    }

    @MainActor
    @Test func createRuleSpeichertHideAktionOhneZielTag() throws {
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
            name: "Spoiler ausblenden",
            isEnabled: true,
            action: .hideArticle,
            matchMode: .all,
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Spoiler")
            ],
            assignTag: nil,
            context: context
        )

        let rules = try context.fetch(FetchDescriptor<Rule>())
        #expect(rules.count == 1)
        #expect(rules.first?.actionRaw == RuleAction.hideArticle.rawValue)
        #expect(rules.first?.assignTag == nil)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func createRuleSpeichertBenachrichtigungsAktionMitTextUndPrioritaet() throws {
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
            context: context
        )

        let rules = try context.fetch(FetchDescriptor<Rule>())
        let rule = try #require(rules.first)
        #expect(rule.actionRaw == RuleAction.notify.rawValue)
        #expect(rule.assignTag == nil)
        #expect(rule.notificationTemplate == "Breaking: {Titel}")
        #expect(rule.notificationPriorityRaw == RuleNotificationPriority.critical.rawValue)
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
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift")
            ],
            assignTag: nil,
            context: context
        )

        let rules = try context.fetch(FetchDescriptor<Rule>())
        #expect(rules.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    @MainActor
    @Test func deleteRuleEntferntZugehoerigeConditions() throws {
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
        let rule = Rule(name: "Regel")
        rule.conditions = [
            RuleCondition(
                field: RuleConditionField.title.rawValue,
                conditionOperator: RuleConditionOperator.contains.rawValue,
                value: "Swift",
                sortOrder: 0
            ),
            RuleCondition(
                field: RuleConditionField.summary.rawValue,
                conditionOperator: RuleConditionOperator.contains.rawValue,
                value: "Mac",
                sortOrder: 1
            )
        ]
        context.insert(rule)
        try context.save()
        let viewModel = RuleViewModel()

        viewModel.deleteRule(rule, context: context)

        let rules = try context.fetch(FetchDescriptor<Rule>())
        #expect(rules.isEmpty)
        // Mit .nullify statt .cascade würde SwiftData die Conditions nur
        // verwaisten lassen — das manuelle Cascade im Code muss sie löschen.
        let conditions = try context.fetch(FetchDescriptor<RuleCondition>())
        #expect(conditions.isEmpty, "Conditions müssen mit der Regel gelöscht werden")
    }
}
