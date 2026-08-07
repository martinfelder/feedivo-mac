import SwiftUI

/// Balkendiagramm der gelesenen Artikel je Tagesabschnitt (Feature: Gewohnheiten).
struct StatisticsDaypartBarsView: View {
    let daypartCounts: [ReadingStatisticsDaypartCount]
    let theme: RuleDialogTheme

    private var totalCount: Int {
        daypartCounts.reduce(0) { $0 + $1.count }
    }

    private var maxCount: Int {
        daypartCounts.map(\.count).max() ?? 0
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(ReadingStatisticsDaypart.allCases, id: \.self) { daypart in
                let count = daypartCounts.first { $0.daypart == daypart }?.count ?? 0
                let isPeak = maxCount > 0 && count == maxCount
                let percentage = totalCount > 0 ? Double(count) / Double(totalCount) * 100 : 0

                HStack(spacing: 10) {
                    Text(label(for: daypart))
                        .font(.system(size: 12, weight: isPeak ? .semibold : .regular))
                        .foregroundStyle(isPeak ? theme.text : theme.text2)
                        .frame(width: 74, alignment: .leading)

                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(theme.track)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isPeak ? theme.accent : theme.accent.opacity(0.45))
                                    .frame(width: maxCount > 0 ? geometry.size.width * CGFloat(count) / CGFloat(maxCount) : 0)
                            }
                    }
                    .frame(height: 8)

                    Text("\(Int(percentage.rounded())) %")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                        .frame(width: 34, alignment: .trailing)
                        .monospacedDigit()
                }
            }
        }
    }

    private func label(for daypart: ReadingStatisticsDaypart) -> LocalizedStringKey {
        switch daypart {
        case .morning: L10n.statisticsDaypartMorning
        case .midday: L10n.statisticsDaypartMidday
        case .afternoon: L10n.statisticsDaypartAfternoon
        case .evening: L10n.statisticsDaypartEvening
        case .night: L10n.statisticsDaypartNight
        }
    }
}
