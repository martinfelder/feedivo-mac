import Foundation
import GRDB

struct SQLiteRuleStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func save(_ rule: RuleRecord, conditions: [RuleConditionRecord]) throws {
        try database.write { db in
            var rule = rule
            try rule.save(db)

            try db.execute(
                sql: """
                    DELETE FROM rule_conditions
                    WHERE ruleID = ?
                    """,
                arguments: [rule.id]
            )

            for condition in conditions {
                var condition = condition
                condition.ruleID = rule.id
                try condition.insert(db)
            }
        }
    }

    func rules() throws -> [RuleRecord] {
        try database.read { db in
            try Self.fetchRules(db)
        }
    }

    func conditions(ruleID: String) throws -> [RuleConditionRecord] {
        try database.read { db in
            try Self.fetchConditions(db, ruleID: ruleID)
        }
    }

    func delete(id: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM rules
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
    }

    func ruleSnapshots() throws -> [RuleEngine.RuleSnapshot] {
        try database.read { db in
            let rules = try Self.fetchRules(db)

            return try rules.compactMap { rule in
                guard let id = UUID(uuidString: rule.id) else {
                    return nil
                }

                let conditions = try Self.fetchConditions(db, ruleID: rule.id)
                let tag = try rule.assignTagID.flatMap { tagID in
                    try TagRecord.fetchOne(db, sql: """
                        SELECT *
                        FROM tags
                        WHERE id = ?
                        """, arguments: [tagID])
                }

                return RuleEngine.RuleSnapshot(
                    id: id,
                    name: rule.name,
                    isEnabled: rule.isEnabled,
                    conditionMatchMode: rule.matchMode,
                    actionRaw: rule.action,
                    notificationTemplate: rule.notificationTemplate,
                    notificationPriorityRaw: rule.notificationPriority,
                    sortOrder: rule.sortOrder,
                    conditions: conditions.map { condition in
                        RuleEngine.RuleConditionSnapshot(
                            field: condition.field,
                            conditionOperator: condition.conditionOperator,
                            value: condition.value,
                            sortOrder: condition.sortOrder
                        )
                    },
                    assignTag: tag.map { tag in
                        RuleEngine.TagSnapshot(
                            id: tag.id,
                            name: tag.name,
                            colorHex: tag.colorHex
                        )
                    }
                )
            }
        }
    }

    private static func fetchRules(_ db: Database) throws -> [RuleRecord] {
        try RuleRecord.fetchAll(db, sql: """
            SELECT *
            FROM rules
            ORDER BY sortOrder, name COLLATE NOCASE, id COLLATE NOCASE
            """)
    }

    private static func fetchConditions(_ db: Database, ruleID: String) throws -> [RuleConditionRecord] {
        try RuleConditionRecord.fetchAll(db, sql: """
            SELECT *
            FROM rule_conditions
            WHERE ruleID = ?
            ORDER BY sortOrder, id COLLATE NOCASE
            """, arguments: [ruleID])
    }
}
