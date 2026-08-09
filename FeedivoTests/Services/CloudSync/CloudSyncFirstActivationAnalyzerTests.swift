import Foundation
import CloudKit
import Testing
@testable import Feedivo

struct CloudSyncFirstActivationAnalyzerTests {
    @Test func findCollisionsFindetGleichenTagNamenCaseInsensitiv() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "local-tag-1", name: "Intune", colorHex: "#FF0000", sortIndex: 0))

        let cloudTag = TagRecord(id: "cloud-tag-1", name: "intune", colorHex: "#00FF00", sortIndex: 0)
        let cloudRecord = CloudSyncTagMapping.makeCKRecord(from: cloudTag)

        let collisions = try CloudSyncFirstActivationAnalyzer.findCollisions(database: database, tagRecords: [cloudRecord], folderRecords: [])

        #expect(collisions.count == 1)
        #expect(collisions.first?.recordType == "Tag")
        #expect(collisions.first?.name == "Intune")
        #expect(collisions.first?.localID == "local-tag-1")
    }

    @Test func findCollisionsFindetKeineKollisionBeiUnterschiedlichenNamen() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "local-tag-1", name: "Intune", colorHex: "#FF0000", sortIndex: 0))

        let cloudTag = TagRecord(id: "cloud-tag-1", name: "Anders", colorHex: "#00FF00", sortIndex: 0)
        let cloudRecord = CloudSyncTagMapping.makeCKRecord(from: cloudTag)

        let collisions = try CloudSyncFirstActivationAnalyzer.findCollisions(database: database, tagRecords: [cloudRecord], folderRecords: [])

        #expect(collisions.isEmpty)
    }

    @Test func findCollisionsFindetGleichenFeedFolderNamen() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedFolderStore(database: database).save(FeedFolderRecord(id: "local-folder-1", name: "Technik", sortIndex: 0, createdAt: Date(), updatedAt: Date()))

        let cloudFolder = FeedFolderRecord(id: "cloud-folder-1", name: "Technik", sortIndex: 0, createdAt: Date(), updatedAt: Date())
        let cloudRecord = CloudSyncFeedFolderMapping.makeCKRecord(from: cloudFolder)

        let collisions = try CloudSyncFirstActivationAnalyzer.findCollisions(database: database, tagRecords: [], folderRecords: [cloudRecord])

        #expect(collisions.count == 1)
        #expect(collisions.first?.recordType == "FeedFolder")
    }

    // Review-Fix (Task 14): Bei Re-Aktivierung (Aus→Ein-Toggle nach bereits abgeschlossenem
    // Erst-Sync) matcht ein bereits synchronisierter Tag sonst SICH SELBST über den Namen, weil
    // `CKRecord.ID.recordName` identisch mit der lokalen `id` ist — das darf NIE als Kollision
    // gemeldet werden, sonst würde die vorausgewählte „Zusammenführen"-Standardaktion den Tag
    // per Selbst-Merge vollständig löschen (siehe Doc-Comment an `findCollisions`).
    @Test func findCollisionsMeldetKeineKollisionBeiBereitsSynchronisiertemTag() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        // Lokale ID ist bewusst identisch mit der Cloud-recordName — genau der Zustand nach
        // einem bereits abgeschlossenen Erst-Sync (Tag wurde per `id` als CKRecord.ID hochgeladen).
        try TagStore(database: database).save(TagRecord(id: "already-synced-tag", name: "Intune", colorHex: "#FF0000", sortIndex: 0))

        let cloudTag = TagRecord(id: "already-synced-tag", name: "Intune", colorHex: "#FF0000", sortIndex: 0)
        let cloudRecord = CloudSyncTagMapping.makeCKRecord(from: cloudTag)

        let collisions = try CloudSyncFirstActivationAnalyzer.findCollisions(database: database, tagRecords: [cloudRecord], folderRecords: [])

        #expect(collisions.isEmpty)
    }

    // Gegenprobe zum Fix oben: eine ECHTE Kollision (unterschiedliche lokale ID, gleicher Name)
    // muss weiterhin zuverlässig erkannt werden — der Selbst-Match-Ausschluss darf nicht zu
    // breit greifen und legitime Duplikate verschlucken.
    @Test func findCollisionsMeldetWeiterhinEchteKollisionBeiUnterschiedlicherID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "local-tag-1", name: "Intune", colorHex: "#FF0000", sortIndex: 0))

        let cloudTag = TagRecord(id: "cloud-tag-1", name: "Intune", colorHex: "#00FF00", sortIndex: 0)
        let cloudRecord = CloudSyncTagMapping.makeCKRecord(from: cloudTag)

        let collisions = try CloudSyncFirstActivationAnalyzer.findCollisions(database: database, tagRecords: [cloudRecord], folderRecords: [])

        #expect(collisions.count == 1)
        #expect(collisions.first?.recordType == "Tag")
        #expect(collisions.first?.localID == "local-tag-1")
    }

    // Analoge Gegenprobe für FeedFolder: bereits synchronisierter Ordner (ID == recordName)
    // darf nicht als Kollision erscheinen, ein tatsächlich unterschiedlicher Ordner mit
    // gleichem Namen (unterschiedliche ID) weiterhin schon.
    @Test func findCollisionsMeldetKeineKollisionBeiBereitsSynchronisiertemFeedFolder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedFolderStore(database: database).save(FeedFolderRecord(id: "already-synced-folder", name: "Technik", sortIndex: 0, createdAt: Date(), updatedAt: Date()))

        let cloudFolder = FeedFolderRecord(id: "already-synced-folder", name: "Technik", sortIndex: 0, createdAt: Date(), updatedAt: Date())
        let cloudRecord = CloudSyncFeedFolderMapping.makeCKRecord(from: cloudFolder)

        let collisions = try CloudSyncFirstActivationAnalyzer.findCollisions(database: database, tagRecords: [], folderRecords: [cloudRecord])

        #expect(collisions.isEmpty)
    }

    // Bugfix (Nutzer-Report 2026-08-08): der Erst-Aktivierungs-Dialog zeigte "Prüfung nicht
    // möglich" trotz vorhandener Netzwerkverbindung. Root Cause: die FeedivoZone wird erst in
    // CloudSyncEngine.start() angelegt (siehe CloudSyncEngine.swift:122-125), dieser Dialog
    // fragt aber bewusst VOR start() ab — bei der allerersten Aktivierung existiert die Zone auf
    // dem Server deshalb noch nicht, ein CKQuery dagegen wirft CKError.zoneNotFound. Das ist kein
    // echter Fehlschlag (es bedeutet nur "keine Cloud-Daten vorhanden"), muss also von einem
    // echten Fehlschlag (z. B. Netzwerk) unterscheidbar sein.
    @Test func isMissingZoneErrorErkenntZoneNotFound() {
        let error = CKError(.zoneNotFound)
        #expect(CloudSyncFirstActivationAnalyzer.isMissingZoneError(error))
    }

    @Test func isMissingZoneErrorLehntEchteNetzwerkfehlerAb() {
        let error = CKError(.networkUnavailable)
        #expect(!CloudSyncFirstActivationAnalyzer.isMissingZoneError(error))
    }

    @Test func isMissingZoneErrorLehntNichtCKErrorsAb() {
        struct DummyError: Error {}
        #expect(!CloudSyncFirstActivationAnalyzer.isMissingZoneError(DummyError()))
    }

    // Zweiter Bugfix (Live-Log-Nachweis 2026-08-08, /usr/bin/log stream): die zoneNotFound-
    // Behandlung allein löste das Nutzer-Report-Symptom NICHT — der tatsächliche Fehler war
    // "Field 'recordName' is not marked queryable" (CKError.invalidArguments), weil im CloudKit-
    // Schema für "Tag"/"FeedFolder" kein Queryable-Index auf recordName gesetzt ist. Anders als
    // zoneNotFound darf das NICHT automatisch als Erfolg behandelt werden (wir könnten echte
    // Duplikate übersehen) — stattdessen bekommt der Nutzer eine gezielte, actionable Meldung
    // statt der generischen "Prüfung nicht möglich"-Warnung.
    @Test func isMissingQueryableIndexErrorErkenntFehlendenIndex() {
        let error = CKError(.invalidArguments, userInfo: [NSLocalizedDescriptionKey: "Field 'recordName' is not marked queryable"])
        #expect(CloudSyncFirstActivationAnalyzer.isMissingQueryableIndexError(error))
    }

    @Test func isMissingQueryableIndexErrorLehntAndereInvalidArgumentsFehlerAb() {
        let error = CKError(.invalidArguments, userInfo: [NSLocalizedDescriptionKey: "Some other invalid arguments issue"])
        #expect(!CloudSyncFirstActivationAnalyzer.isMissingQueryableIndexError(error))
    }

    @Test func isMissingQueryableIndexErrorLehntNichtCKErrorsAb() {
        struct DummyError: Error {}
        #expect(!CloudSyncFirstActivationAnalyzer.isMissingQueryableIndexError(DummyError()))
    }
}
