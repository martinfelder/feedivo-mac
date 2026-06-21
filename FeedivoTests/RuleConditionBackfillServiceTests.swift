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
        let rule = Rule(
            name: "Alt",
            conditionField: "title",
            conditionOperator: "contains",
            conditionValue: "Swift"
        )
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
        let rule = Rule(
            name: "Neu",
            conditionField: "title",
            conditionOperator: "contains",
            conditionValue: "Legacy"
        )
        rule.conditions = [
            RuleCondition(field: "summary", conditionOperator: "contains", value: "Modern")
        ]
        context.insert(rule)
        try context.save()

        try RuleConditionBackfillService.backfillMissingConditions(context: context)

        #expect(rule.conditions.count == 1)
        #expect(rule.conditions.first?.field == "summary")
        #expect(rule.conditions.first?.value == "Modern")
    }
}
