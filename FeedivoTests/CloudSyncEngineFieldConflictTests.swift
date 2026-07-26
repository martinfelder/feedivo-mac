import Foundation
import CloudKit
import GRDB
import Testing
@testable import Feedivo

@MainActor
struct CloudSyncEngineFieldConflictTests {
    @Test func mergeDecisionOhneUnterschiedIstNoConflict() {
        let decision = CloudSyncEngine.mergeDecision(
            fieldName: "name", localValue: "Gleich" as CKRecordValue, serverValue: "Gleich" as CKRecordValue,
            askFields: ["name"], autoFields: []
        )
        #expect(decision == .noConflict)
    }

    @Test func mergeDecisionBeiAskFieldMitUnterschiedIstNeedsUserDecision() {
        let decision = CloudSyncEngine.mergeDecision(
            fieldName: "name", localValue: "Neu-A" as CKRecordValue, serverValue: "Neu-B" as CKRecordValue,
            askFields: ["name"], autoFields: []
        )
        #expect(decision == .needsUserDecision)
    }

    @Test func mergeDecisionBeiAutoFieldMitUnterschiedIstAutoResolved() {
        let decision = CloudSyncEngine.mergeDecision(
            fieldName: "sortIndex", localValue: 1 as CKRecordValue, serverValue: 2 as CKRecordValue,
            askFields: ["name"], autoFields: ["sortIndex"]
        )
        #expect(decision == .autoResolved)
    }

    @Test func pendingChangeOhneChangedFieldsNutztWeiterhinGanzRecordLWW() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let tag = TagRecord(id: "tag-1", name: "Alt", colorHex: "#FF0000", sortIndex: 0)
        try TagStore(database: database).save(tag)

        // Ohne CloudSyncSettings.isEnabled() wird kein changedFields gesetzt — simuliert
        // Altbestand von vor Phase 3.
        try CloudSyncPendingChangeStore(database: database).enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save)

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "tag-1")
        #expect(change?.changedFields == nil)
    }

    // MARK: - C4: nil-vs-Wert ist eine ECHTE Differenz, kein .noConflict

    @Test func mergeDecisionBeiBeidenNilIstNoConflict() {
        let decision = CloudSyncEngine.mergeDecision(
            fieldName: "name", localValue: nil, serverValue: nil,
            askFields: ["name"], autoFields: []
        )
        #expect(decision == .noConflict)
    }

    @Test func mergeDecisionBeiAutoFieldMitNilLokalUndWertServerIstAutoResolved() {
        // Lokal wurde das Feld zurückgesetzt (z. B. Feed aus Ordner entfernt, folderName = nil).
        let decision = CloudSyncEngine.mergeDecision(
            fieldName: "sortIndex", localValue: nil, serverValue: 2 as CKRecordValue,
            askFields: ["name"], autoFields: ["sortIndex"]
        )
        #expect(decision == .autoResolved)
    }

    @Test func mergeDecisionBeiAskFieldMitWertLokalUndNilServerIstNeedsUserDecision() {
        let decision = CloudSyncEngine.mergeDecision(
            fieldName: "name", localValue: "Neu" as CKRecordValue, serverValue: nil,
            askFields: ["name"], autoFields: []
        )
        #expect(decision == .needsUserDecision)
    }

    @Test func mergeDecisionBeiUnbekanntemFeldOhnePolicyIstAutoResolved() {
        // I2: ein Feldname, der weder in askFields noch in autoFields auftaucht, fällt
        // defensiv auf .autoResolved zurück (der Aufrufer loggt das zusätzlich).
        let decision = CloudSyncEngine.mergeDecision(
            fieldName: "unbekanntesFeld", localValue: "A" as CKRecordValue, serverValue: "B" as CKRecordValue,
            askFields: ["name"], autoFields: ["sortIndex"]
        )
        #expect(decision == .autoResolved)
    }

    // MARK: - resolveFieldMerge: gemischte Auto-/Ask-Felder in einem Record

    @Test func resolveFieldMergeBeiGemischtenFeldernMeldetUngeloestenKonfliktUndLaesstRecordsUnangetastet() {
        let recordID = CKRecord.ID(recordName: "tag-1")
        let localRecord = CKRecord(recordType: "Tag", recordID: recordID)
        localRecord["colorHex"] = "#FF0000" as CKRecordValue
        localRecord["name"] = "Lokal-Neu" as CKRecordValue

        let serverRecord = CKRecord(recordType: "Tag", recordID: recordID)
        serverRecord["colorHex"] = "#00FF00" as CKRecordValue
        serverRecord["name"] = "Server-Neu" as CKRecordValue

        let resolution = CloudSyncEngine.resolveFieldMerge(
            changedFields: ["colorHex", "name"],
            localRecord: localRecord,
            serverRecord: serverRecord,
            askFields: ["name"],
            autoFields: ["colorHex"]
        )

        #expect(resolution.hasUnresolvedConflict == true)
        #expect(resolution.unresolvedFields.map(\.fieldName) == ["name"])
        // Das Auto-Feld wird zwar BERECHNET (steckt im Ergebnis), aber ...
        #expect(resolution.autoOverlays.keys.contains("colorHex"))
        // ... die Records selbst dürfen dabei NICHT mutiert worden sein — erst der Aufrufer
        // (handleFailedSave) entscheidet anhand von hasUnresolvedConflict, ob überhaupt etwas
        // angewendet wird (Review-Fund I1).
        #expect(serverRecord["colorHex"] as? String == "#00FF00")
        #expect(localRecord["colorHex"] as? String == "#FF0000")
        #expect(serverRecord["name"] as? String == "Server-Neu")
    }

    @Test func resolveFieldMergeMitNurAutoFeldernHatKeinenUngeloestenKonflikt() {
        let recordID = CKRecord.ID(recordName: "tag-1")
        let localRecord = CKRecord(recordType: "Tag", recordID: recordID)
        localRecord["colorHex"] = "#FF0000" as CKRecordValue
        let serverRecord = CKRecord(recordType: "Tag", recordID: recordID)
        serverRecord["colorHex"] = "#00FF00" as CKRecordValue

        let resolution = CloudSyncEngine.resolveFieldMerge(
            changedFields: ["colorHex"],
            localRecord: localRecord,
            serverRecord: serverRecord,
            askFields: ["name"],
            autoFields: ["colorHex"]
        )

        #expect(resolution.hasUnresolvedConflict == false)
        #expect(resolution.autoOverlays.keys.contains("colorHex"))
    }

    @Test func resolveFieldMergeMarkiertUnbekanntesFeldAlsUnrecognized() {
        let recordID = CKRecord.ID(recordName: "tag-1")
        let localRecord = CKRecord(recordType: "Tag", recordID: recordID)
        localRecord["mysteryField"] = "A" as CKRecordValue
        let serverRecord = CKRecord(recordType: "Tag", recordID: recordID)
        serverRecord["mysteryField"] = "B" as CKRecordValue

        let resolution = CloudSyncEngine.resolveFieldMerge(
            changedFields: ["mysteryField"],
            localRecord: localRecord,
            serverRecord: serverRecord,
            askFields: ["name"],
            autoFields: ["colorHex"]
        )

        #expect(resolution.unrecognizedFieldNames == ["mysteryField"])
        #expect(resolution.hasUnresolvedConflict == false)
    }

    // MARK: - C2: ArticleStatus Pro-Feld-Zeitstempel mit Gesamt-Record-Fallback

    @Test func articleStatusFieldLocalWinsFaelltBeiFehlendemFeldZeitstempelAufGesamtRecordZeitstempelZurueck() {
        // Lokal wurde "ungelesen" markiert (readAt = nil, das Feld-Datum wird beim Zurücksetzen
        // gelöscht). Server hat noch isRead=true mit einem ECHTEN, aber ÄLTEREN readAt-Datum als
        // der lokale "ungelesen"-Klick selbst. Ohne Fallback auf den Gesamt-Record-Zeitstempel
        // würde `nil ?? .distantPast` das lokale "ungelesen" IMMER verlieren lassen, egal wie neu
        // die lokale Aktion tatsächlich war (Review-Fund C2).
        let serverFieldTimestamp = Date(timeIntervalSince1970: 1000)
        let localWholeRecordUpdatedAt = Date(timeIntervalSince1970: 5000)
        let serverWholeRecordModificationDate = Date(timeIntervalSince1970: 2000)

        let localWins = CloudSyncEngine.articleStatusFieldLocalWins(
            fieldTimestampLocal: nil,
            fieldTimestampServer: serverFieldTimestamp,
            wholeRecordLocalUpdatedAt: localWholeRecordUpdatedAt,
            wholeRecordServerModificationDate: serverWholeRecordModificationDate
        )

        #expect(localWins == true)
    }

    // MARK: - NEW-1: ArticleStatus-Merge muss auch bei "Server gewinnt" lokal ankommen

    @Test func handleArticleStatusConflictWendetServerGewonneneFelderTatsaechlichLokalAn() async throws {
        // Reproduziert exakt den vom Round-2-Re-Review gefundenen Folgefehler des C1-Fixes —
        // ruft `handleArticleStatusConflict` DIREKT auf (Sichtbarkeit dafür bewusst
        // `internal`, siehe dort). Ein früherer Testversuch rief stattdessen nur
        // `mergeArticleStatusRecords` + `CloudSyncArticleStatusMapping.applyIncoming`
        // einzeln auf — das testete zwar dieselben Bausteine, hätte aber NICHT bemerkt, wenn
        // `handleArticleStatusConflict` selbst (z. B. durch Entfernen der
        // `applyIncomingRecord`-Zeile) wieder kaputtginge, da der Test nie den eigentlichen
        // Produktionscode-Pfad durchlief. Dieser Test ruft jetzt die echte Methode über eine
        // echte `CloudSyncEngine`-Instanz auf. Beide `readAt`-Zeitstempel sind hier ECHT
        // vorhanden (kein `nil`) — der deterministische Pro-Feld-Vergleichszweig aus
        // `articleStatusFieldLocalWins`, unabhängig vom bereits separat getesteten
        // Gesamt-Record-Fallback.
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed-1", title: "Feed"))
        let articleID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-1", title: "Titel", arrivedAt: Date(timeIntervalSince1970: 100))
        )
        // `syncStableID` wird bereits beim Insert in `ArticleStore.upsert` vergeben,
        // unabhängig vom Sync-Berührt-Status — kein vorheriger `setRead`-Aufruf nötig.
        let localStatus = try ArticleStatusStore(database: database).status(articleID: articleID)!
        let stableID = localStatus.syncStableID!

        let recordID = CloudSyncArticleStatusMapping.recordID(forLocalID: stableID)
        let localRecord = CKRecord(recordType: "ArticleStatus", recordID: recordID)
        localRecord["isRead"] = false as CKRecordValue
        localRecord["isStarred"] = false as CKRecordValue
        localRecord["readAt"] = Date(timeIntervalSince1970: 1000) as CKRecordValue // AELTER

        let serverRecord = CKRecord(recordType: "ArticleStatus", recordID: recordID)
        let serverReadAt = Date(timeIntervalSince1970: 5000) // NEUER — Server muss gewinnen
        serverRecord["isRead"] = true as CKRecordValue
        serverRecord["isStarred"] = false as CKRecordValue
        serverRecord["readAt"] = serverReadAt as CKRecordValue

        let engine = CloudSyncEngine(database: database)
        _ = await engine.handleArticleStatusConflict(localRecord: localRecord, serverRecord: serverRecord)

        // Die LOKALE Datenbank-Zeile muss jetzt das Server-Ergebnis widerspiegeln — nicht nur
        // ein gecachter/erneut eingereihter CKRecord.
        let updated = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(updated?.isRead == true)
        #expect(updated?.readAt == serverReadAt)
    }

    @Test func articleStatusFieldLocalWinsNutztFeldZeitstempelWennBeideVorhanden() {
        // Sind beide Feld-Zeitstempel gesetzt, entscheidet NUR der Feld-Vergleich — der
        // Gesamt-Record-Zeitstempel wird ignoriert (auch wenn er das Gegenteil nahelegen würde).
        let localWins = CloudSyncEngine.articleStatusFieldLocalWins(
            fieldTimestampLocal: Date(timeIntervalSince1970: 100),
            fieldTimestampServer: Date(timeIntervalSince1970: 200),
            wholeRecordLocalUpdatedAt: Date(timeIntervalSince1970: 9000),
            wholeRecordServerModificationDate: Date(timeIntervalSince1970: 1)
        )

        #expect(localWins == false)
    }

    // MARK: - I3: changedFields-Vereinigung + Backfill-Erhaltung

    @Test func enqueueVereinigtChangedFieldsBeiWiederholtemAufrufFuerDieselbeID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save, changedFields: ["name"])
        try store.enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save, changedFields: ["colorHex"])

        let change = try store.pendingChange(recordName: "tag-1")
        #expect(Set(change?.changedFields ?? []) == Set(["name", "colorHex"]))
    }

    @Test func enqueueOhneChangedFieldsBehaeltBestehendeChangedFieldsBei() throws {
        // Simuliert backfillAllExistingRecords, das bei JEDEM start() jede lokale Zeile ohne
        // changedFields erneut enqueued — das darf ein bereits Feld-Ebene-getracktes Pending
        // NICHT auf nil zurücksetzen.
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save, changedFields: ["name"])
        try store.enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save)

        let change = try store.pendingChange(recordName: "tag-1")
        #expect(change?.changedFields == ["name"])
    }
}
