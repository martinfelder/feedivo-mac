import Foundation
import Testing
@testable import Feedivo

/// Whole-Branch-Review-Fix zu Task 11 (iCloud Sync Phase 3): der Gruppen-Header im
/// Konflikt-Sheet zeigte bisher nur den rohen `recordType` ("Rule"), wodurch zwei Konflikte
/// auf unterschiedlichen Regeln/Feeds/etc. optisch nicht unterscheidbar waren. Diese Tests
/// decken die beiden dafür neu testbar gemachten, `internal` statischen Helfer in
/// `SyncConflictResolutionView` ab — `groupHeaderTitle(for:)` selbst bleibt `private`
/// (reine View-Glue-Logik ohne eigenen Testwert, siehe Task-11-Report).
struct SyncConflictResolutionViewTests {
    // MARK: - recordTypeLabel(forRecordType:) — reine, DB-freie Switch-Logik

    @Test func recordTypeLabelLiefertNutzerverstaendlicheBezeichnungenFuerAlleBekanntenTypen() {
        #expect(SyncConflictResolutionView.recordTypeLabel(forRecordType: "Tag") == L10n.syncConflictsRecordTypeTag)
        #expect(SyncConflictResolutionView.recordTypeLabel(forRecordType: "Feed") == L10n.syncConflictsRecordTypeFeed)
        #expect(SyncConflictResolutionView.recordTypeLabel(forRecordType: "FeedFolder") == L10n.syncConflictsRecordTypeFeedFolder)
        #expect(SyncConflictResolutionView.recordTypeLabel(forRecordType: "Rule") == L10n.syncConflictsRecordTypeRule)
        #expect(SyncConflictResolutionView.recordTypeLabel(forRecordType: "RuleCondition") == L10n.syncConflictsRecordTypeRuleCondition)
        #expect(SyncConflictResolutionView.recordTypeLabel(forRecordType: "SmartFolder") == L10n.syncConflictsRecordTypeSmartFolder)
        #expect(SyncConflictResolutionView.recordTypeLabel(forRecordType: "SmartFolderCondition") == L10n.syncConflictsRecordTypeSmartFolderCondition)
    }

    @Test func recordTypeLabelFaelltBeiUnbekanntemTypAufDenRohenNamenZurueck() {
        #expect(SyncConflictResolutionView.recordTypeLabel(forRecordType: "Irgendwas") == "Irgendwas")
    }

    // MARK: - displayName(forRecordType:recordName:database:) — echte In-Memory-DB

    @Test func displayNameLiestDenTagNamen() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "tag-1", name: "Intune Artikel", colorHex: "#FF0000"))

        let name = SyncConflictResolutionView.displayName(forRecordType: "Tag", recordName: "tag-1", database: database)

        #expect(name == "Intune Artikel")
    }

    @Test func displayNameLiestDenFeedTitel() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Apple Newsroom"))

        let name = SyncConflictResolutionView.displayName(forRecordType: "Feed", recordName: "feed-1", database: database)

        #expect(name == "Apple Newsroom")
    }

    @Test func displayNameLiestDenOrdnerNamen() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedFolderStore(database: database).save(FeedFolderRecord(id: "folder-1", name: "Technik"))

        let name = SyncConflictResolutionView.displayName(forRecordType: "FeedFolder", recordName: "folder-1", database: database)

        #expect(name == "Technik")
    }

    @Test func displayNameLiestDenRegelNamen() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteRuleStore(database: database).save(RuleRecord(id: "rule-1", name: "Intune Artikel", sortOrder: 0), conditions: [])

        let name = SyncConflictResolutionView.displayName(forRecordType: "Rule", recordName: "rule-1", database: database)

        #expect(name == "Intune Artikel")
    }

    @Test func displayNameLiestBeiRegelBedingungDenNamenDerUebergeordnetenRegel() throws {
        // Der entscheidende Fall aus dem Review: RuleCondition hat selbst keinen Namen —
        // `recordName` ist die ID der Bedingungszeile, nicht der Regel.
        let database = try FeedivoDatabase.inMemoryForTests()
        let condition = RuleConditionRecord(
            id: "cond-1",
            ruleID: "rule-1",
            field: "title",
            conditionOperator: "contains",
            value: "Intune"
        )
        try SQLiteRuleStore(database: database).save(
            RuleRecord(id: "rule-1", name: "Intune Artikel", sortOrder: 0),
            conditions: [condition]
        )

        let name = SyncConflictResolutionView.displayName(forRecordType: "RuleCondition", recordName: "cond-1", database: database)

        #expect(name == "Intune Artikel")
    }

    @Test func displayNameLiestDenSmartFolderNamen() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteSmartFolderStore(database: database).save(
            SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", isDefault: false),
            conditions: []
        )

        let name = SyncConflictResolutionView.displayName(forRecordType: "SmartFolder", recordName: "folder-1", database: database)

        #expect(name == "Meine Auswahl")
    }

    @Test func displayNameLiestBeiSmartFolderBedingungDenNamenDesUebergeordnetenOrdners() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let condition = SmartFolderConditionRecord(
            id: "cond-1",
            smartFolderID: "folder-1",
            field: "status",
            conditionOperator: "is",
            value: "unread"
        )
        try SQLiteSmartFolderStore(database: database).save(
            SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", isDefault: false),
            conditions: [condition]
        )

        let name = SyncConflictResolutionView.displayName(forRecordType: "SmartFolderCondition", recordName: "cond-1", database: database)

        #expect(name == "Meine Auswahl")
    }

    @Test func displayNameLiefertNilFallsDerDatensatzNichtMehrExistiert() throws {
        // Kernszenario aus dem Review-Finding: das Gerät hat den Datensatz zwischenzeitlich
        // lokal gelöscht (z. B. Regel gelöscht, bevor der Konflikt aufgelöst wurde) — der
        // Aufrufer (`groupHeaderTitle(for:)`) muss dann auf den reinen Typ-Namen zurückfallen,
        // statt abzustürzen oder eine leere Zeile zu zeigen.
        let database = try FeedivoDatabase.inMemoryForTests()

        let name = SyncConflictResolutionView.displayName(forRecordType: "Rule", recordName: "rule-existiert-nicht", database: database)

        #expect(name == nil)
    }

    @Test func displayNameLiefertNilFuerUnbekanntenRecordType() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let name = SyncConflictResolutionView.displayName(forRecordType: "Irgendwas", recordName: "egal", database: database)

        #expect(name == nil)
    }
}
