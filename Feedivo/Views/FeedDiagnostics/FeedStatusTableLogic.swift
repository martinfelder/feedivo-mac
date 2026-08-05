import Foundation

/// Reine, isoliert testbare Logik für die Feed-Status-Tabelle — Filterung nach
/// Suchtext, feste Sortierung nach Fehlschlägen und Schweregrad-Ableitung. Kein
/// neues Datenfeld: alles wird aus dem bereits vorhandenen `FeedFailureDiagnostic`
/// abgeleitet (analog `FeedManagementSettingsState.filteredFeeds`). Siehe
/// docs/superpowers/specs/2026-08/2026-08-05-feed-status-tabellenansicht-design.md.
enum FeedStatusTableLogic {
    static func filtered(_ diagnostics: [FeedFailureDiagnostic], matching searchText: String) -> [FeedFailureDiagnostic] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return diagnostics
        }
        return diagnostics.filter {
            $0.feedTitle.localizedCaseInsensitiveContains(trimmed)
                || $0.feedURL.localizedCaseInsensitiveContains(trimmed)
        }
    }

    static func sortedByFailureCountDescending(_ diagnostics: [FeedFailureDiagnostic]) -> [FeedFailureDiagnostic] {
        diagnostics.sorted { $0.consecutiveFailureCount > $1.consecutiveFailureCount }
    }
}

/// Rein visuelle Schweregrad-Einstufung für die Fehlschläge-Badge in der Zeile —
/// kein gespeicherter Zustand, nur eine Ableitung aus `consecutiveFailureCount`.
enum FeedFailureSeverity: Equatable {
    case new
    case warning
    case critical

    static func forConsecutiveFailureCount(_ count: Int) -> FeedFailureSeverity {
        switch count {
        case ..<2:
            .new
        case 2..<5:
            .warning
        default:
            .critical
        }
    }
}
