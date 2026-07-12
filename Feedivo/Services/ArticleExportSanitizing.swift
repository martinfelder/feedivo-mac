import Foundation

/// Gemeinsamer HTML-Escaping-/Link-Filter-/Datums-Helfer für den Artikel-Export
/// (HTML/PDF-Pfad). Vorher war `escapedHTML`/`escapedHTMLAttribute`/`isSafeLinkTarget`/
/// `publishedDateFormatter` 3-fach unabhängig implementiert und teilweise bereits
/// auseinandergelaufen: `ArticleDocumentExportRenderers.swift`s alte lokale Kopie escapte
/// zusätzlich `"` in normalem Text-Content. Diese kanonische Version übernimmt bewusst das
/// schlankere Verhalten (Attribut-Escaping bleibt `escapedHTMLAttribute` vorbehalten).
enum ArticleExportSanitizing {
    static func escapedHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapedHTMLAttribute(_ text: String) -> String {
        escapedHTML(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func isSafeLinkTarget(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased()
        else {
            return false
        }

        return ["http", "https", "mailto"].contains(scheme)
    }

    static let publishedDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
