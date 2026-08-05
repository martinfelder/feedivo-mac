import Foundation

/// Cell-Reuse-sichere Lade-Token-Prüfung für die native Produktivliste —
/// bewusst eine eigene, unabhängige Kopie der gleichnamigen Logik im
/// #if DEBUG-gated Render-Benchmark-Spike (`RenderBenchmark/
/// NativeArticleImageLoadGuard.swift`), NICHT eine Wiederverwendung davon:
/// die Spike-Datei ist DEBUG-only und bleibt laut Plan unangetastet, aber
/// diese Produktivzelle muss auch im Release-Build funktionieren.
enum NativeArticleListImageLoadGuard {
    static func shouldApplyLoadedImage(requestedToken: Int, currentToken: Int) -> Bool {
        requestedToken == currentToken
    }
}
