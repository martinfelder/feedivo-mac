import Foundation
import GRDB

struct SQLiteRuleStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    /// Markiert eine lokale Regel- oder Bedingungszeile als ausstehende Sync-Änderung, falls
    /// iCloud Sync aktiv ist. Läuft bewusst INNERHALB derselben `database.write`-Transaktion
    /// wie die fachliche Mutation — analog zu `FeedStore`/`FeedFolderStore`/`TagStore`.
    private func enqueuePendingSync(_ db: Database, recordType: String, recordName: String, changeType: CloudSyncChangeType) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: recordType, recordName: recordName, changeType: changeType)
    }

    // `rule_conditions.ruleID` hat `ON DELETE CASCADE` (`PRAGMA foreign_keys = ON` ist aktiv,
    // siehe FeedivoDatabase.swift) — die alten Bedingungs-IDs müssen deshalb VOR dem
    // `DELETE FROM rule_conditions` ermittelt und als `.delete` enqueued werden, sonst sind sie
    // danach nicht mehr abfragbar.
    func save(_ rule: RuleRecord, conditions: [RuleConditionRecord]) throws {
        try database.write { db in
            var rule = rule
            try rule.save(db)
            try enqueuePendingSync(db, recordType: CloudSyncRuleMapping.recordType, recordName: rule.id, changeType: .save)

            let existingConditionIDs = try String.fetchAll(db, sql: "SELECT id FROM rule_conditions WHERE ruleID = ?", arguments: [rule.id])
            for conditionID in existingConditionIDs {
                try enqueuePendingSync(db, recordType: CloudSyncRuleConditionMapping.recordType, recordName: conditionID, changeType: .delete)
            }

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
                try enqueuePendingSync(db, recordType: CloudSyncRuleConditionMapping.recordType, recordName: condition.id, changeType: .save)
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
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

    func rule(id: String) throws -> RuleRecord? {
        try database.read { db in
            try RuleRecord.fetchOne(db, sql: """
                SELECT *
                FROM rules
                WHERE id = ?
                """, arguments: [id])
        }
    }

    func updateEnabled(id: String, isEnabled: Bool) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE rules
                    SET isEnabled = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [isEnabled, Date(), id]
            )
            try enqueuePendingSync(db, recordType: CloudSyncRuleMapping.recordType, recordName: id, changeType: .save)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func duplicate(id: String, copyName: String) throws -> RuleRecord {
        // `database.write { ... }` reicht hier den Rückgabewert des Closures (`RuleRecord`)
        // durch — `notifyPendingChangesAvailable` steht deshalb NACH dem `write`-Aufruf, nicht
        // darin.
        let duplicate = try database.write { db -> RuleRecord in
            guard let source = try RuleRecord.fetchOne(db, sql: """
                SELECT *
                FROM rules
                WHERE id = ?
                """, arguments: [id])
            else {
                throw SQLiteRuleStoreError.missingRule
            }

            let maxSortOrder = (try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM rules") ?? -1) + 1
            let duplicateID = UUID().uuidString
            var duplicate = RuleRecord(
                id: duplicateID,
                name: copyName,
                isEnabled: source.isEnabled,
                matchMode: source.matchMode,
                action: source.action,
                assignTagID: source.assignTagID,
                notificationTemplate: source.notificationTemplate,
                notificationPriority: source.notificationPriority,
                sortOrder: maxSortOrder
            )
            try duplicate.insert(db)
            try enqueuePendingSync(db, recordType: CloudSyncRuleMapping.recordType, recordName: duplicateID, changeType: .save)

            let conditions = try Self.fetchConditions(db, ruleID: source.id)
            for (index, condition) in conditions.enumerated() {
                var copiedCondition = RuleConditionRecord(
                    id: UUID().uuidString,
                    ruleID: duplicateID,
                    field: condition.field,
                    conditionOperator: condition.conditionOperator,
                    value: condition.value,
                    sortOrder: index,
                    groupIndex: condition.groupIndex
                )
                try copiedCondition.insert(db)
                try enqueuePendingSync(db, recordType: CloudSyncRuleConditionMapping.recordType, recordName: copiedCondition.id, changeType: .save)
            }

            return duplicate
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
        return duplicate
    }

    func move(id sourceID: String, toPositionOf targetID: String) throws {
        try database.write { db in
            var rules = try Self.fetchRules(db)
            guard sourceID != targetID,
                  let sourceIndex = rules.firstIndex(where: { $0.id == sourceID }),
                  let targetIndex = rules.firstIndex(where: { $0.id == targetID })
            else {
                return
            }

            let movedRule = rules.remove(at: sourceIndex)
            rules.insert(movedRule, at: targetIndex)

            for (index, rule) in rules.enumerated() {
                try db.execute(
                    sql: """
                        UPDATE rules
                        SET sortOrder = ?, updatedAt = ?
                        WHERE id = ?
                        """,
                    arguments: [index, Date(), rule.id]
                )
                try enqueuePendingSync(db, recordType: CloudSyncRuleMapping.recordType, recordName: rule.id, changeType: .save)
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    // `rule_conditions.ruleID` hat `ON DELETE CASCADE` — die betroffenen Bedingungs-IDs müssen
    // VOR dem `DELETE FROM rules`-Statement ermittelt und als `.delete` enqueued werden, weil
    // SQLite ihre Zeilen bei diesem einen Statement bereits mitlöscht (siehe Doku oben bei
    // `save`).
    func delete(id: String) throws {
        try database.write { db in
            let conditionIDs = try String.fetchAll(db, sql: "SELECT id FROM rule_conditions WHERE ruleID = ?", arguments: [id])
            for conditionID in conditionIDs {
                try enqueuePendingSync(db, recordType: CloudSyncRuleConditionMapping.recordType, recordName: conditionID, changeType: .delete)
            }
            try enqueuePendingSync(db, recordType: CloudSyncRuleMapping.recordType, recordName: id, changeType: .delete)

            try db.execute(
                sql: """
                    DELETE FROM rules
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
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
                    actionRaw: rule.action,
                    notificationTemplate: rule.notificationTemplate,
                    notificationPriorityRaw: rule.notificationPriority,
                    sortOrder: rule.sortOrder,
                    conditions: conditions.map { condition in
                        RuleEngine.RuleConditionSnapshot(
                            field: condition.field,
                            conditionOperator: condition.conditionOperator,
                            value: condition.value,
                            sortOrder: condition.sortOrder,
                            groupIndex: condition.groupIndex
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

enum SQLiteRuleStoreError: Error, Equatable {
    case missingRule
}
