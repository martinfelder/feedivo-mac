import Foundation

/// Zentrale, einzeln dokumentierte Obergrenzen für die drei unterschiedlichen
/// "Artikel laden"-Anwendungsfälle der App. Bewusst DREI separate Werte statt
/// einer gemeinsamen Konstante — die Anwendungsfälle sind unterschiedlich
/// genug (volle Snapshots vs. reine IDs, Haupt-Liste vs. Suche), dass ein
/// gemeinsamer Wert die falsche Kopplung suggerieren würde.
enum ArticleFetchLimits {
    /// Haupt-Timeline-Load der 3-Spalten-Artikelliste
    /// (`SQLiteFeedArticleListState.defaultTimelineLoader`).
    static let mainArticlePage = 200

    /// Artikel-Popout-Fenster: lädt NUR Artikel-IDs (nicht die vollen
    /// Snapshots) für die Vor-/Zurück-Navigation über alle Artikel hinweg
    /// (`scope: .all`) — bewusst höher als eine einzelne `mainArticlePage`,
    /// weil hier nur IDs statt kompletter Inhalte geladen werden.
    static let popoutNavigationIDs = 1000

    /// Obergrenze für angezeigte Ergebnisse im separaten Artikel-Suchfenster.
    static let searchResults = 200
}
