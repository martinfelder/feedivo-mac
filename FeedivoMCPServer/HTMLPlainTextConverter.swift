import Foundation

/// Minimaler, Foundation-only HTML-zu-Klartext-Konverter für den MCP-Server.
/// Bewusst keine Wiederverwendung von `ReaderContentRenderer` (Reader-UI-Code
/// mit zusätzlichen Bild-/Inline-Formatierungs-Abhängigkeiten) — hier reicht
/// eine einfache, deterministische Tag-Entfernung für Klartext-Ausgabe an eine KI.
enum HTMLPlainTextConverter {
    static func plainText(fromHTML html: String) -> String {
        var text = html

        let blockTags = [
            "<p>", "</p>", "<br>", "<br/>", "<br />",
            "</div>", "</li>", "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>",
        ]
        for tag in blockTags {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }

        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Benannte Entities in fester, deterministischer Reihenfolge dekodieren (statt
        // über ein Dictionary, dessen Iterationsreihenfolge nicht garantiert ist).
        // WICHTIG: "&amp;" muss ZULETZT kommen. Alle anderen Entities beginnen selbst
        // mit "&" (z. B. "&lt;") — würde "&amp;" zuerst ersetzt, könnte aus der
        // literalen Zeichenfolge "&amp;lt;" (korrekt dekodiert: die 4 literalen Zeichen
        // "&lt;", NICHT weiter zu "<" aufzulösen) fälschlich "<" werden, weil das durch
        // die &amp;-Ersetzung neu entstandene "&" anschließend nochmal als Start von
        // "&lt;" interpretiert würde. Bei "&amp;" zuletzt bleibt "&lt;" nach dem
        // (erfolglosen) &lt;-Ersetzungsversuch unverändert stehen und wird erst danach
        // korrekt zu "&" + "lt;" = "&lt;" (literale Zeichenfolge).
        let orderedNamedEntities: [(entity: String, replacement: String)] = [
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&amp;", "&"),
        ]
        for (entity, replacement) in orderedNamedEntities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        // Numerische Zeichenreferenzen (dezimal "&#8217;" und hexadezimal "&#x2019;")
        // erst NACH der HTML-Tag-Entfernung UND NACH der benannten Entity-Dekodierung
        // auflösen — sonst könnte z. B. "&#38;" (die numerische Form von "&amp;") zu
        // einem rohen "&" werden, das dann in einem späteren Schritt fälschlich als
        // Start einer weiteren Entity interpretiert würde. Da dies bereits der letzte
        // Dekodierungsschritt ist, entsteht dieses Risiko hier nicht.
        text = decodeNumericEntities(in: text)

        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n[ \\t]*\n[ \\t\\n]*", with: "\n\n", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Löst `&#8217;` (dezimal) und `&#x2019;`/`&#X2019;` (hexadezimal) in echte
    /// Unicode-Zeichen auf. Bei ungültigem Code (kein gültiges `Unicode.Scalar`,
    /// z. B. ein Surrogate-Halbpaar) bleibt die Entity unverändert stehen statt
    /// abzustürzen.
    private static func decodeNumericEntities(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#([xX][0-9A-Fa-f]+|[0-9]+);") else {
            return text
        }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var result = ""
        var lastEnd = 0
        for match in regex.matches(in: text, range: fullRange) {
            result += nsText.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let codeGroup = nsText.substring(with: match.range(at: 1))
            let code: UInt32?
            if codeGroup.hasPrefix("x") || codeGroup.hasPrefix("X") {
                code = UInt32(codeGroup.dropFirst(), radix: 16)
            } else {
                code = UInt32(codeGroup, radix: 10)
            }
            if let code, let scalar = Unicode.Scalar(code) {
                result.append(Character(scalar))
            } else {
                result += nsText.substring(with: match.range)
            }
            lastEnd = match.range.location + match.range.length
        }
        result += nsText.substring(with: NSRange(location: lastEnd, length: nsText.length - lastEnd))
        return result
    }
}
