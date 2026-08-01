import Testing
import Foundation
@testable import Feedivo

@Suite("SparkleReleaseInfo")
struct SparkleReleaseInfoTests {
    @Test("erstellt aus den rohen Appcast-Item-Feldern korrekt")
    func erstelltAusRohenFeldernKorrekt() {
        let info = SparkleReleaseInfo(
            tagName: "v1.0-16",
            name: "Feedivo 1.0 (16)",
            htmlURL: URL(string: "https://github.com/martinfelder/feedivo-mac/releases/tag/v1.0-16")!,
            bodyHTML: "<ul><li>Fix: Beispiel</li></ul>"
        )
        #expect(info.tagName == "v1.0-16")
        #expect(info.name == "Feedivo 1.0 (16)")
        #expect(info.bodyHTML == "<ul><li>Fix: Beispiel</li></ul>")
    }

    @Test("id entspricht tagName (Identifiable-Konformität für .sheet(item:))")
    func idEntsprichtTagName() {
        let info = SparkleReleaseInfo(
            tagName: "v1.0-16",
            name: nil,
            htmlURL: URL(string: "https://example.com")!,
            bodyHTML: nil
        )
        #expect(info.id == "v1.0-16")
    }
}
