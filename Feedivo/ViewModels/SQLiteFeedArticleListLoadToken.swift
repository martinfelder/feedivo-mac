import Foundation

/// Baut den `.task(id:)`-Trigger-String fuer `SQLiteFeedArticleListView` aus reinen
/// Werten zusammen — bewusst OHNE `selectedArticleID`. Ein Artikel-Klick soll die
/// Vor-/Zurueck-Navigation lokal aus den bereits geladenen Zeilen ableiten
/// (`SQLiteArticleNavigationState.init(articleIDs:selectedArticleID:)`) statt einen
/// kompletten SQL-Reload der Liste auszuloesen.
enum SQLiteFeedArticleListLoadToken {
    static func make(
        scopeToken: String,
        directTagVersion: Int,
        sqliteStatusVersion: Int,
        debouncedSearchText: String
    ) -> String {
        "\(scopeToken)#\(directTagVersion)#\(sqliteStatusVersion)#\(debouncedSearchText)"
    }
}
