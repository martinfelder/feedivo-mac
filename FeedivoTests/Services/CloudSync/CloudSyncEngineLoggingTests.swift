import Foundation
import Testing
import CloudKit
@testable import Feedivo

@Suite("CloudSyncEngine Fehlerbeschreibung")
struct CloudSyncEngineLoggingTests {
    @Test("Gewoehnlicher Fehler wird unveraendert beschrieben")
    func gewoehnlicherFehlerWirdBeschrieben() {
        struct Beispielfehler: LocalizedError {
            var errorDescription: String? { "Netzwerk nicht erreichbar" }
        }

        let beschreibung = CloudSyncEngine.describeSendChangesFailure(Beispielfehler())

        #expect(beschreibung.contains("Netzwerk nicht erreichbar"))
    }

    @Test("Teilfehler nennt betroffene Records einzeln mit Fehlercode")
    func teilfehlerNenntBetroffeneRecords() {
        // Genau der Fall, der am 2026-08-15 die Diagnose blockierte: CKError.partialFailure
        // liefert ueber `localizedDescription` nur das nichtssagende "Failed to send changes",
        // waehrend die eigentliche Ursache pro Record in `partialErrorsByItemID` steckt.
        let zone = CKRecordZone.ID(zoneName: "FeedivoZone", ownerName: CKCurrentUserDefaultName)
        let ersteID = CKRecord.ID(recordName: "record-eins", zoneID: zone)
        let zweiteID = CKRecord.ID(recordName: "record-zwei", zoneID: zone)

        let teilfehler: [CKRecord.ID: Error] = [
            ersteID: CKError(.serverRecordChanged),
            zweiteID: CKError(.invalidArguments),
        ]
        let fehler = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: teilfehler])

        let beschreibung = CloudSyncEngine.describeSendChangesFailure(fehler)

        #expect(beschreibung.contains("record-eins"))
        #expect(beschreibung.contains("record-zwei"))
        // Die numerischen CKError-Codes machen den Fehler nachschlagbar, ohne dass die
        // Beschreibung von Apples lokalisierten Texten abhaengt.
        #expect(beschreibung.contains("\(CKError.Code.serverRecordChanged.rawValue)"))
        #expect(beschreibung.contains("\(CKError.Code.invalidArguments.rawValue)"))
    }

    @Test("CloudKit-Fehler ohne Teilfehler nennt den Fehlercode")
    func cloudKitFehlerOhneTeilfehlerNenntCode() {
        let fehler = CKError(.networkUnavailable)

        let beschreibung = CloudSyncEngine.describeSendChangesFailure(fehler)

        #expect(beschreibung.contains("\(CKError.Code.networkUnavailable.rawValue)"))
    }
}
