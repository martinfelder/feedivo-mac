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
}
