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

        let entities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n[ \\t]*\n[ \\t\\n]*", with: "\n\n", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
