#if DEBUG
/// Verhindert, dass ein asynchron geladenes Bild noch auf eine
/// `NativeArticleRowCellView` angewendet wird, die inzwischen (durch
/// `NSTableView`-Zellwiederverwendung) für eine andere Zeile/URL
/// wiederverwendet wurde. Analog zum bestehenden Stale-URL-Guard in
/// `CachedRemoteImageView.loadImage()` (SwiftUI-Seite), hier als reine,
/// isoliert testbare Funktion für die AppKit-Seite des Benchmarks.
enum NativeArticleImageLoadGuard {
    static func shouldApplyLoadedImage(requestedToken: Int, currentToken: Int) -> Bool {
        requestedToken == currentToken
    }
}
#endif
