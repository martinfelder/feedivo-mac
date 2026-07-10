import SwiftUI

/// Zeitraum-Filter für das Lese-Statistiken-Fenster (Feature 14.1). Steuert nur die
/// Zahlen-Kacheln (gelesen heute/Woche/gesamt, Top-Feeds, Ø Lesezeit, Top-Tags) —
/// die Heatmap zeigt unabhängig davon immer die letzten 91 Tage (GitHub-Stil).
enum StatisticsTimeRange: String, CaseIterable, Identifiable, RuleSelectOption {
    case last7Days
    case last30Days
    case all

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .last7Days:
            L10n.statisticsTimeRangeLast7Days
        case .last30Days:
            L10n.statisticsTimeRangeLast30Days
        case .all:
            L10n.statisticsTimeRangeAll
        }
    }

    /// `nil` bedeutet "seit jeher" (Feature 14.1: "Gesamt" nutzt den frühesten
    /// vorhandenen Artikel als Startpunkt, nicht ein Festdatum).
    func startDate(relativeTo now: Date) -> Date? {
        switch self {
        case .last7Days:
            Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .last30Days:
            Calendar.current.date(byAdding: .day, value: -30, to: now)
        case .all:
            nil
        }
    }

    /// Unmittelbar vorausgehender, gleich langer Zeitraum für den Trend-Vergleich
    /// (Feature 14, Vorperiode-Vergleich). `nil` für `.all` — "seit jeher" hat
    /// keine sinnvolle Vorperiode gleicher Länge.
    func previousPeriodRange(relativeTo now: Date) -> (start: Date, end: Date)? {
        let calendar = Calendar.current

        switch self {
        case .last7Days:
            guard let end = calendar.date(byAdding: .day, value: -7, to: now),
                  let start = calendar.date(byAdding: .day, value: -7, to: end)
            else {
                return nil
            }
            return (start, end)
        case .last30Days:
            guard let end = calendar.date(byAdding: .day, value: -30, to: now),
                  let start = calendar.date(byAdding: .day, value: -30, to: end)
            else {
                return nil
            }
            return (start, end)
        case .all:
            return nil
        }
    }
}
