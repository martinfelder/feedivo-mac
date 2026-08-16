import Foundation

/// Leitet aus dem Pfad eines Programms einen Anzeigenamen für den KI-Client ab.
///
/// Bewusst pfadbasiert statt über eine Liste bekannter Clients: So wird auch ein Client korrekt
/// benannt, den dieses Projekt gar nicht kennt, und die Ableitung kann nicht veralten.
///
/// Der Name wird ausschließlich zur Anzeige gespeichert — der vollständige Pfad NIE, er könnte
/// Verzeichnisnamen des Nutzers enthalten.
enum MCPClientNameResolver {
    /// Wird angezeigt, wenn der Elternprozess nicht ermittelt werden konnte. Bewusst nicht
    /// lokalisiert: Der Wert wird vom Serverprozess geschrieben, der die Lokalisierung des
    /// App-Bundles nicht zur Verfügung hat.
    static let unknownClientName = "Unbekannt"

    static func clientName(forExecutablePath path: String) -> String {
        let komponenten = path.split(separator: "/", omittingEmptySubsequences: true)

        // Das AEUSSERE Bundle gewinnt: bei "Cursor.app/.../Helper.app/..." ist "Cursor" die App,
        // die der Nutzer kennt — "Helper" saehe aus wie ein fremdes Programm.
        if let bundle = komponenten.first(where: { $0.hasSuffix(".app") }) {
            return String(bundle.dropLast(".app".count))
        }

        return komponenten.last.map(String.init) ?? unknownClientName
    }
}
