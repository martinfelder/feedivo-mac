import Foundation

/// Ein Feed, dessen letzter Aktualisierungsversuch fehlgeschlagen ist —
/// Grundlage für das Feed-Status-Diagnose-Fenster
/// (`FeedRefreshDiagnosticsWindowView`). Wird ausschließlich über
/// `FeedLogStore.failureDiagnostics()`/`failureDiagnosticsAsync()` befüllt.
struct FeedFailureDiagnostic: Equatable, Identifiable, Sendable {
    var feedID: String
    var feedTitle: String
    var feedURL: String
    var feedWebsiteURL: String?
    var feedFaviconURL: String?
    var lastAttemptAt: Date
    var errorMessage: String
    var httpStatusCode: Int?
    var consecutiveFailureCount: Int

    var id: String { feedID }
}
