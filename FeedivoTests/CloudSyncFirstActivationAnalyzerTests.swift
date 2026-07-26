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
}
