import Foundation

/// Entscheidet, ob der "Zurück"-Button in der Original-Ansicht aktiv sein darf.
/// `WebContentView` behält seine WKWebView bewusst über Artikelwechsel hinweg
/// bei (siehe Commit eca556f93 — Fix für den Reader-Spinner-Flash), daher
/// enthält `webView.backForwardList` nach einem Artikelwechsel weiterhin
/// Einträge des vorherigen Artikels. `isAtBoundary` markiert, ob der aktuelle
/// `WKBackForwardListItem` noch der beim Laden des aktuellen Artikels
/// gemerkte Startpunkt ist — solange das der Fall ist, hat der User innerhalb
/// dieses Artikels noch nicht weiternavigiert, und "Zurück" bleibt gesperrt,
/// auch wenn WKWebView selbst `canGoBack == true` meldet (weil älterer
/// Verlauf aus einem anderen Artikel existiert).
enum WebNavigationBoundary {
    static func canGoBack(webViewCanGoBack: Bool, isAtBoundary: Bool) -> Bool {
        webViewCanGoBack && !isAtBoundary
    }
}
