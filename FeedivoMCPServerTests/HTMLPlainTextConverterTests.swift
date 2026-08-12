import Testing
@testable import FeedivoMCPServer

@Suite("HTMLPlainTextConverter")
struct HTMLPlainTextConverterTests {
    @Test("Entfernt HTML-Tags und wandelt Absätze in Zeilenumbrüche um")
    func entferntHTMLTagsUndAbsaetze() {
        let html = "<p>Erster Absatz mit <strong>fettem</strong> Text.</p><p>Zweiter Absatz &amp; mehr.</p>"
        let result = HTMLPlainTextConverter.plainText(fromHTML: html)
        #expect(result == "Erster Absatz mit fettem Text.\n\nZweiter Absatz & mehr.")
    }

    @Test("Wandelt <br> in Zeilenumbrüche um")
    func wandeltBrInZeilenumbruecheUm() {
        let html = "Zeile eins<br>Zeile zwei<br/>Zeile drei"
        let result = HTMLPlainTextConverter.plainText(fromHTML: html)
        #expect(result == "Zeile eins\nZeile zwei\nZeile drei")
    }

    @Test("Gibt leeren String bei leerem HTML zurück")
    func gibtLeerenStringBeiLeeremHTMLZurueck() {
        #expect(HTMLPlainTextConverter.plainText(fromHTML: "") == "")
    }

    @Test("Normalisiert mehrfache Leerzeilen auf maximal eine")
    func normalisiertMehrfacheLeerzeilen() {
        let html = "<p>Eins</p><p></p><p></p><p>Zwei</p>"
        let result = HTMLPlainTextConverter.plainText(fromHTML: html)
        #expect(result == "Eins\n\nZwei")
    }
}
