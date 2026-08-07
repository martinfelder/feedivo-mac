import SwiftUI

/// Eine Rangliste mit proportionalem Balken pro Zeile — geteilt zwischen Top-Feeds und
/// Top-Tags im Aufmerksamkeit-Abschnitt des Statistik-Fensters. `icon` liefert pro Zeile
/// entweder ein echtes Feed-Favicon oder einen echten Tag-Farbpunkt (kein generischer
/// Platzhalter).
struct StatisticsRankListView<Row>: View {
    let rows: [Row]
    let theme: RuleDialogTheme
    let minutes: (Row) -> Int
    let title: (Row) -> String
    let meta: (Row) -> String
    let icon: (Row) -> AnyView

    private var maxMinutes: Int {
        rows.map(minutes).max() ?? 0
    }

    var body: some View {
        VStack(spacing: 11) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let rowMinutes = minutes(row)

                HStack(spacing: 10) {
                    icon(row)
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(title(row))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(theme.text)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text(meta(row))
                                .font(.system(size: 11))
                                .foregroundStyle(theme.tertiaryText)
                        }

                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(theme.track)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(index == 0 ? theme.accent : theme.accent.opacity(0.55))
                                        .frame(width: maxMinutes > 0 ? geometry.size.width * CGFloat(rowMinutes) / CGFloat(maxMinutes) : 0)
                                }
                        }
                        .frame(height: 5)
                    }

                    Text(StatisticsRankListView.formattedMinutes(rowMinutes))
                        .font(.system(size: 12.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.text)
                        .frame(width: 58, alignment: .trailing)
                }
            }
        }
    }

    private static func formattedMinutes(_ minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: TimeInterval(minutes) * 60) ?? "0"
    }
}
