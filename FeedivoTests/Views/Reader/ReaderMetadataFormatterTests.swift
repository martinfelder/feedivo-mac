import Foundation
import Testing
@testable import Feedivo

struct ReaderMetadataFormatterTests {
    @Test func estimatedMinutesLiefertNilBeiLeeremContentUndSummary() {
        #expect(ReaderMetadataFormatter.estimatedMinutes(content: nil, summary: nil) == nil)
        #expect(ReaderMetadataFormatter.estimatedMinutes(content: "", summary: "   ") == nil)
    }

    @Test func estimatedMinutesBevorzugtContentVorSummary() {
        let content = Array(repeating: "wort", count: 400).joined(separator: " ")
        let summary = Array(repeating: "wort", count: 10).joined(separator: " ")

        #expect(ReaderMetadataFormatter.estimatedMinutes(content: content, summary: summary) == 2)
    }

    @Test func estimatedMinutesNutztSummaryFallsContentLeerIst() {
        let summary = Array(repeating: "wort", count: 50).joined(separator: " ")

        #expect(ReaderMetadataFormatter.estimatedMinutes(content: nil, summary: summary) == 1)
    }

    @Test func estimatedMinutesRundetAufUndMindestensEineMinute() {
        #expect(ReaderMetadataFormatter.estimatedMinutes(content: "einzelnesWort", summary: nil) == 1)
    }

    @Test func estimatedMinutesRundetAufBeiUngeraderWortzahl() {
        let content = Array(repeating: "wort", count: 201).joined(separator: " ")

        #expect(ReaderMetadataFormatter.estimatedMinutes(content: content, summary: nil) == 2)
    }
}
