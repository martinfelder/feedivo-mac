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
