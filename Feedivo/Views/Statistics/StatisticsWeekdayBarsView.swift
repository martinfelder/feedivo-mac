import SwiftUI

/// Balkendiagramm der gelesenen Artikel je Wochentag (Feature: Gewohnheiten). Zeigt
/// Montag zuerst (deutsche Konvention), unabhängig von `Calendar.current.firstWeekday`.
struct StatisticsWeekdayBarsView: View {
    let weekdayCounts: [ReadingStatisticsWeekdayCount]
    let theme: RuleDialogTheme

    /// Anzeigereihenfolge Mo…So, gemappt auf Calendar-`.weekday`-Komponenten (1=So…7=Sa).
    private static let displayOrder = [2, 3, 4, 5, 6, 7, 1]

    private var countsByWeekday: [Int: Int] {
        Dictionary(uniqueKeysWithValues: weekdayCounts.map { ($0.weekday, $0.count) })
    }

    private var maxCount: Int {
        weekdayCounts.map(\.count).max() ?? 0
    }

    var body: some View {
        let symbols = Calendar.current.shortWeekdaySymbols

        HStack(alignment: .bottom, spacing: 7) {
            ForEach(Self.displayOrder, id: \.self) { weekday in
                let count = countsByWeekday[weekday] ?? 0
                let isPeak = maxCount > 0 && count == maxCount

                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isPeak ? theme.accent : theme.accent.opacity(0.4))
                        .frame(height: maxCount > 0 ? max(4, CGFloat(count) / CGFloat(maxCount) * 76) : 4)
                        .frame(maxHeight: 76, alignment: .bottom)

                    Text(symbols[weekday - 1])
                        .font(.system(size: 10, weight: isPeak ? .bold : .medium))
                        .foregroundStyle(isPeak ? theme.text : theme.tertiaryText)
                }
            }
        }
        .frame(height: 92, alignment: .bottom)
    }
}
