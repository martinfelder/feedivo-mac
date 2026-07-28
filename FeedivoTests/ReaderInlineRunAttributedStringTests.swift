import SwiftUI
import Testing
@testable import Feedivo

struct ReaderInlineRunAttributedStringTests {
    @Test func attributedStringSetztLinkAttribut() {
        let runs = [
            ReaderInlineRun(text: "Text", isBold: false, isItalic: false, linkURL: URL(string: "https://example.com"), colorHex: nil)
        ]

        let attributed = runs.attributedString(colorScheme: .light)

        #expect(attributed.link == URL(string: "https://example.com"))
    }

    @Test func attributedStringSetztFettUndKursivIntent() {
        let runs = [
            ReaderInlineRun(text: "Text", isBold: true, isItalic: true, linkURL: nil, colorHex: nil)
        ]

        let attributed = runs.attributedString(colorScheme: .light)
        let intent = attributed.runs.first?.inlinePresentationIntent

        #expect(intent == [.stronglyEmphasized, .emphasized])
    }

    @Test func attributedStringVerwirftFarbeOhneAusreichendenKontrast() {
        let runs = [
            ReaderInlineRun(text: "Text", isBold: false, isItalic: false, linkURL: nil, colorHex: "#1A1A2E")
        ]

        let attributed = runs.attributedString(colorScheme: .dark)

        #expect(attributed.runs.first?.foregroundColor == nil)
    }

    @Test func attributedStringUebernimmtFarbeMitAusreichendemKontrast() {
        let runs = [
            ReaderInlineRun(text: "Text", isBold: false, isItalic: false, linkURL: nil, colorHex: "#FF0000")
        ]

        let attributed = runs.attributedString(colorScheme: .light)

        #expect(attributed.runs.first?.foregroundColor != nil)
    }

    @Test func attributedStringVerkettetMehrereRunsZuEinemString() {
        let runs = [
            ReaderInlineRun(text: "Vor ", isBold: false, isItalic: false, linkURL: nil, colorHex: nil),
            ReaderInlineRun(text: "fett", isBold: true, isItalic: false, linkURL: nil, colorHex: nil),
            ReaderInlineRun(text: " danach", isBold: false, isItalic: false, linkURL: nil, colorHex: nil)
        ]

        let attributed = runs.attributedString(colorScheme: .light)

        #expect(String(attributed.characters) == "Vor fett danach")
    }
}
