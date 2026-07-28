import Foundation
import CoreSpotlight
import Testing
@testable import Feedivo

struct SpotlightContinuationParserTests {
    @Test func liestArtikelIDAusGueltigerSpotlightAktivitaet() {
        let articleID = UUID()
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: articleID.uuidString]

        #expect(SpotlightContinuationParser.articleID(from: activity) == articleID)
    }

    @Test func liefertNilBeiFalschemAktivitaetsTyp() {
        let activity = NSUserActivity(activityType: "com.example.other")
        activity.userInfo = [CSSearchableItemActivityIdentifier: UUID().uuidString]

        #expect(SpotlightContinuationParser.articleID(from: activity) == nil)
    }

    @Test func liefertNilBeiFehlenderID() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)

        #expect(SpotlightContinuationParser.articleID(from: activity) == nil)
    }

    @Test func liefertNilBeiKaputterUUID() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "not-a-uuid"]

        #expect(SpotlightContinuationParser.articleID(from: activity) == nil)
    }
}
