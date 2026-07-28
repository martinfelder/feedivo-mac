import Testing
@testable import Feedivo

struct ReaderInlineColorSafetyTests {
    @Test func isSafeColorAkzeptiertDunklenTextAufHellemHintergrund() {
        #expect(ReaderInlineColorSafety.isSafeColor(
            hex: "#000000",
            againstBackgroundLuminance: ReaderInlineColorSafety.lightBackgroundLuminance
        ))
    }

    @Test func isSafeColorVerwirftDunkleFarbeAufDunklemHintergrund() {
        #expect(!ReaderInlineColorSafety.isSafeColor(
            hex: "#1A1A2E",
            againstBackgroundLuminance: ReaderInlineColorSafety.darkBackgroundLuminance
        ))
    }

    @Test func isSafeColorAkzeptiertHelleFarbeAufDunklemHintergrund() {
        #expect(ReaderInlineColorSafety.isSafeColor(
            hex: "#FFFFFF",
            againstBackgroundLuminance: ReaderInlineColorSafety.darkBackgroundLuminance
        ))
    }

    @Test func isSafeColorUnterstuetztKurzformHex() {
        #expect(ReaderInlineColorSafety.isSafeColor(
            hex: "#000",
            againstBackgroundLuminance: ReaderInlineColorSafety.lightBackgroundLuminance
        ))
    }

    @Test func isSafeColorVerwirftNichtParsebareHexWerte() {
        #expect(!ReaderInlineColorSafety.isSafeColor(
            hex: "notacolor",
            againstBackgroundLuminance: ReaderInlineColorSafety.lightBackgroundLuminance
        ))
        #expect(!ReaderInlineColorSafety.isSafeColor(
            hex: "#12345",
            againstBackgroundLuminance: ReaderInlineColorSafety.lightBackgroundLuminance
        ))
    }

    @Test func colorFromHexLiefertNilBeiUngueltigemWert() {
        #expect(ReaderInlineColorSafety.color(fromHex: "notacolor") == nil)
    }

    @Test func colorFromHexLiefertWertBeiGueltigemHex() {
        #expect(ReaderInlineColorSafety.color(fromHex: "#FF0000") != nil)
    }
}
