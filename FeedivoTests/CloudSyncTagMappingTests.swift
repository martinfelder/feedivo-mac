import Foundation
import CloudKit
import Testing
@testable import Feedivo

struct CloudSyncTagMappingTests {
    @Test func recordIDNutztTagIDAlsRecordNameInnerhalbDerFeedivoZone() {
        let recordID = CloudSyncTagMapping.recordID(forTagID: "tag-1")

        #expect(recordID.recordName == "tag-1")
        #expect(recordID.zoneID.zoneName == "FeedivoZone")
    }

    @Test func makeCKRecordMapptAlleFelder() {
        let tag = TagRecord(id: "tag-1", name: "Wichtig", colorHex: "#FF0000", sortIndex: 3)

        let record = CloudSyncTagMapping.makeCKRecord(from: tag)

        #expect(record.recordType == "Tag")
        #expect(record.recordID.recordName == "tag-1")
        #expect(record["name"] as? String == "Wichtig")
        #expect(record["colorHex"] as? String == "#FF0000")
        #expect(record["sortIndex"] as? Int == 3)
    }

    @Test func makeCKRecordAktualisiertBestehendesRecordStattEinNeuesZuErzeugen() {
        let tag = TagRecord(id: "tag-1", name: "Wichtig", colorHex: "#FF0000", sortIndex: 3)
        let existing = CKRecord(recordType: "Tag", recordID: CloudSyncTagMapping.recordID(forTagID: "tag-1"))

        let record = CloudSyncTagMapping.makeCKRecord(from: tag, existing: existing)

        #expect(record === existing)
        #expect(record["name"] as? String == "Wichtig")
    }

    @Test func tagRecordFromCKRecordMapptZurueck() {
        let source = TagRecord(id: "tag-1", name: "Wichtig", colorHex: "#FF0000", sortIndex: 3)
        let ckRecord = CloudSyncTagMapping.makeCKRecord(from: source)

        let mapped = CloudSyncTagMapping.tagRecord(from: ckRecord)

        #expect(mapped?.id == "tag-1")
        #expect(mapped?.name == "Wichtig")
        #expect(mapped?.colorHex == "#FF0000")
        #expect(mapped?.sortIndex == 3)
    }

    @Test func tagRecordFromCKRecordLiefertNilBeiFehlendenPflichtfeldern() {
        let ckRecord = CKRecord(recordType: "Tag", recordID: CloudSyncTagMapping.recordID(forTagID: "tag-1"))
        // Absichtlich keine Felder gesetzt.

        #expect(CloudSyncTagMapping.tagRecord(from: ckRecord) == nil)
    }
}
