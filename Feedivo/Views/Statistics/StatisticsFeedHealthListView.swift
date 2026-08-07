import SwiftUI

/// Zeigt Feeds, die der Nutzer kaum liest, mit Lesequote-Balken und einem Abbestellen-
/// Button pro Zeile. Reiner Anzeige-/Auslöse-Baustein — Bestätigungsdialog und tatsächliches
/// Löschen bleiben in `StatisticsWindowView` (teilt den Dialog-Wortlaut mit dem Feed-Organizer
/// und dem Feed-Status-Fenster).
struct StatisticsFeedHealthListView: View {
    let candidates: [ReadingStatisticsFeedHealth]
    let theme: RuleDialogTheme
    let onUnsubscribeTapped: (ReadingStatisticsFeedHealth) -> Void

    private static let warningColor = Color(hex: 0xFF9F0A)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.offset) { index, candidate in
                row(candidate)
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle().fill(theme.border).frame(height: 1)
                        }
                    }
            }
        }
    }

    private func row(_ candidate: ReadingStatisticsFeedHealth) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Self.warningColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.feedTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)

                Text(L10n.statisticsFeedHealthCounts(unread: candidate.unreadCount, total: candidate.totalCount))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(L10n.statisticsFeedHealthReadPercentage(Int(candidate.readPercentage.rounded())))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Self.warningColor)
                    .monospacedDigit()

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.track)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Self.warningColor)
                            .frame(width: 120 * CGFloat(candidate.readPercentage / 100))
                    }
                    .frame(width: 120, height: 5)
            }

            Button {
                onUnsubscribeTapped(candidate)
            } label: {
                Text(L10n.statisticsFeedHealthUnsubscribeButton)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.text2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.card2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
