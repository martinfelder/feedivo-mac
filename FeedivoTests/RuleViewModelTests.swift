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
        let firstRule = Rule(
            name: "Vorhanden",
            conditionField: RuleConditionField.title.rawValue,
            conditionOperator: RuleConditionOperator.contains.rawValue,
            conditionValue: "Swift"
        )
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
        let firstRule = Rule(
            name: "Erste Regel",
            conditionField: RuleConditionField.title.rawValue,
            conditionOperator: RuleConditionOperator.contains.rawValue,
            conditionValue: "Swift"
        )
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
        let secondRule = Rule(
            name: "Zweite Regel",
            conditionField: RuleConditionField.summary.rawValue,
            conditionOperator: RuleConditionOperator.contains.rawValue,
            conditionValue: "Mac"
        )
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
        let firstRule = Rule(
            name: "A",
            conditionField: RuleConditionField.title.rawValue,
            conditionOperator: RuleConditionOperator.contains.rawValue,
            conditionValue: "A"
        )
        firstRule.sortOrder = 0
        let secondRule = Rule(
            name: "B",
            conditionField: RuleConditionField.title.rawValue,
            conditionOperator: RuleConditionOperator.contains.rawValue,
            conditionValue: "B"
        )
        secondRule.sortOrder = 1
        let thirdRule = Rule(
            name: "C",
            conditionField: RuleConditionField.title.rawValue,
            conditionOperator: RuleConditionOperator.contains.rawValue,
            conditionValue: "C"
        )
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
}
