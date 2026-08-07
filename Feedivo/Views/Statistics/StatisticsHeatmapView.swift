import SwiftUI

/// GitHub-Stil-Heatmap der letzten 91 Tage (13 Wochen), unabhängig vom
/// Zeitraum-Picker des Statistik-Fensters (Feature 14.1). Spalten = Wochen,
/// Zeilen = Wochentage (Sonntag oben) — führende Zellen vor dem eigentlichen
/// Start werden als leere Platzhalter gerendert, damit die Wochen sauber
/// spaltenweise ausgerichtet sind.
struct StatisticsHeatmapView: View {
    let dailyCounts: [ReadingStatisticsDailyCount]
    let theme: RuleDialogTheme

    private static let dayCount = 91
    private static let cellSize: CGFloat = 18
    private static let cellSpacing: CGFloat = 4
    private static let monthLabelHeight: CGFloat = 14
    /// Stufen 1…4 (plus Stufe 0 = kein Artikel) — feste Buckets statt
    /// kontinuierlicher Opacity relativ zum Tagesmaximum, damit ein einzelner
    /// Ausreißertag nicht alle anderen Tage blass aussehen lässt.
    private static let bucketCount = 4
    /// GitHub-Stil: nur Mo/Mi/Fr beschriften, nicht jede Zeile.
    private static let labeledWeekdayRows: Set<Int> = [1, 3, 5]

    private enum HeatmapCell {
        case empty
        case day(date: Date, count: Int)
    }

    private var cells: [HeatmapCell] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let countsByDay = Dictionary(
            uniqueKeysWithValues: dailyCounts.map { (calendar.startOfDay(for: $0.date), $0.count) }
        )

        let startDate = calendar.date(byAdding: .day, value: -(Self.dayCount - 1), to: today) ?? today
        // Wochenanfang = Sonntag (weekday 1 in Calendar.current) — Platzhalter davor,
        // damit die erste Woche nicht schief in der Spalte hängt.
        let leadingPlaceholders = calendar.component(.weekday, from: startDate) - 1
        var result: [HeatmapCell] = Array(repeating: .empty, count: max(0, leadingPlaceholders))

        var date = startDate
        while date <= today {
            result.append(.day(date: date, count: countsByDay[date] ?? 0))
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? today.addingTimeInterval(1)
        }

        return result
    }

    /// Spaltenweise Gruppierung zu je 7 Zellen (eine Woche pro Spalte) — nötig,
    /// damit Monats-Labels gezielt über der richtigen Spalte platziert werden
    /// können (mit `LazyHGrid` allein ist das nicht adressierbar).
    private var columns: [[HeatmapCell]] {
        stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }

    /// Monats-Kürzel nur über der Spalte, in der ein neuer Kalendermonat
    /// beginnt (GitHub-Stil: sparsame Beschriftung, nicht pro Spalte).
    private var monthLabels: [String?] {
        var lastMonth: Int?
        let calendar = Calendar.current

        return columns.map { column in
            guard let firstDay = column.compactMap({ cell -> Date? in
                if case .day(let date, _) = cell { return date }
                return nil
            }).first else {
                return nil
            }

            let month = calendar.component(.month, from: firstDay)
            guard month != lastMonth else {
                return nil
            }
            lastMonth = month
            return calendar.shortStandaloneMonthSymbols[month - 1]
        }
    }

    private var maxCount: Int {
        dailyCounts.map(\.count).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                weekdayLabelColumn
                gridWithMonthLabels
            }

            legend
        }
    }

    private var weekdayLabelColumn: some View {
        let symbols = Calendar.current.shortWeekdaySymbols

        return VStack(alignment: .trailing, spacing: Self.cellSpacing) {
            Color.clear.frame(height: Self.monthLabelHeight)

            ForEach(0..<7, id: \.self) { row in
                Group {
                    if Self.labeledWeekdayRows.contains(row), symbols.indices.contains(row) {
                        Text(symbols[row])
                            .font(.system(size: 9))
                            .foregroundStyle(theme.text2)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: Self.cellSize)
            }
        }
    }

    private var gridWithMonthLabels: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Self.cellSpacing) {
                ForEach(Array(monthLabels.enumerated()), id: \.offset) { _, label in
                    Text(label ?? "")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.text2)
                        .frame(width: Self.cellSize, alignment: .leading)
                }
            }
            .frame(height: Self.monthLabelHeight, alignment: .bottom)

            HStack(alignment: .top, spacing: Self.cellSpacing) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: Self.cellSpacing) {
                        ForEach(Array(column.enumerated()), id: \.offset) { _, cell in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(color(for: cell))
                                .frame(width: Self.cellSize, height: Self.cellSize)
                                .help(helpText(for: cell))
                        }
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text(L10n.statisticsHeatmapLegendLess)
                .font(.system(size: 10))
                .foregroundStyle(theme.text2)

            ForEach(0...Self.bucketCount, id: \.self) { bucket in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(bucketColor(bucket))
                    .frame(width: Self.cellSize, height: Self.cellSize)
            }

            Text(L10n.statisticsHeatmapLegendMore)
                .font(.system(size: 10))
                .foregroundStyle(theme.text2)
        }
    }

    private func color(for cell: HeatmapCell) -> Color {
        switch cell {
        case .empty:
            return .clear
        case .day(_, let count):
            return bucketColor(bucketIndex(for: count))
        }
    }

    /// Feste Quartils-Buckets relativ zum Tagesmaximum im 91-Tage-Fenster
    /// (1 = leichtestes Viertel … 4 = stärkstes Viertel), statt einer
    /// kontinuierlichen Skala, die von einem einzelnen Ausreißertag dominiert wird.
    private func bucketIndex(for count: Int) -> Int {
        guard count > 0, maxCount > 0 else {
            return 0
        }

        let ratio = Double(count) / Double(maxCount)
        switch ratio {
        case ...0.25:
            return 1
        case ...0.5:
            return 2
        case ...0.75:
            return 3
        default:
            return 4
        }
    }

    private func bucketColor(_ bucket: Int) -> Color {
        guard bucket > 0 else {
            return theme.track
        }

        let intensity = Double(bucket) / Double(Self.bucketCount)
        return theme.accent.opacity(0.25 + intensity * 0.75)
    }

    private func helpText(for cell: HeatmapCell) -> String {
        guard case .day(let date, let count) = cell else {
            return ""
        }

        return L10n.statisticsHeatmapDayTooltip(
            date.formatted(date: .abbreviated, time: .omitted),
            count
        )
    }
}
