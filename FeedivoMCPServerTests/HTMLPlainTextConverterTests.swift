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

    @Test("Dekodiert dezimale und hexadezimale numerische Entities")
    func dekodiertNumerischeEntities() {
        // &#8217; = RIGHT SINGLE QUOTATION MARK (’), &#8211; = EN DASH (–),
        // &#x2019; = dieselbe RIGHT SINGLE QUOTATION MARK hexadezimal notiert.
        let html = "It&#8217;s a test &#8211; really &#x2019;nuff said."
        let result = HTMLPlainTextConverter.plainText(fromHTML: html)
        #expect(result == "It’s a test – really ’nuff said.")
    }

    @Test("Ungültige numerische Entity bleibt unverändert stehen")
    func ungueltigeNumerischeEntityBleibtUnveraendert() {
        // Kein gültiges Unicode.Scalar (Surrogate-Halbpaar) — darf nicht abstürzen.
        let html = "Kaputt: &#xD800; Ende."
        let result = HTMLPlainTextConverter.plainText(fromHTML: html)
        #expect(result == "Kaputt: &#xD800; Ende.")
    }

    @Test("Verschachtelte Entity &amp;lt; wird nicht doppelt dekodiert")
    func verschachtelteEntityWirdNichtDoppeltDekodiert() {
        // Korrektes Einzeldurchlauf-Verhalten: &amp;lt; steht für die literale
        // Zeichenfolge "&lt;" (4 Zeichen), NICHT für "<".
        let html = "&amp;lt;"
        let result = HTMLPlainTextConverter.plainText(fromHTML: html)
        #expect(result == "&lt;")
    }

    @Test("Numerische Form von &amp; (&#38;) wird nicht zu einer weiteren Entity")
    func numerischeAmpFormWirdNichtWeiterInterpretiert() {
        // &#38; dekodiert zu "&", danach folgt literal "amp;" — darf NICHT
        // nochmal als &amp; interpretiert werden, da die numerische Dekodierung
        // bereits der letzte Schritt ist.
        let html = "&#38;amp;"
        let result = HTMLPlainTextConverter.plainText(fromHTML: html)
        #expect(result == "&amp;")
    }
}
