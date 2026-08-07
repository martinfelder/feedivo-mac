import SwiftUI
import UniformTypeIdentifiers

struct StatisticsWindowView: View {
    static let windowID = "statistics-window"

    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.colorScheme) private var colorScheme

    @State private var timeRange: StatisticsTimeRange = .last7Days
    @State private var statistics = ReadingStatisticsSnapshot.empty
    @State private var feedStatistics: [(feedTitle: String, statistics: FeedReadingStatisticsSnapshot)] = []
    @State private var isExporting = false
    @State private var exportDocument: StatisticsCSVDocument?

    var body: some View {
        let theme = RuleDialogTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 0) {
            header(theme: theme)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            ScrollView {
                bodyContent(theme: theme)
            }

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            footer(theme: theme)
        }
        .background(theme.bg)
        .task {
            loadStatistics()
        }
        .onChange(of: timeRange) {
            loadStatistics()
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument ?? StatisticsCSVDocument(text: ""),
            contentType: .commaSeparatedText,
            defaultFilename: StatisticsExportService.defaultExportFilename()
        ) { _ in }
    }

    private func header(theme: RuleDialogTheme) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.statisticsWindowTitle)
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(theme.text)

                Text(L10n.statisticsSubtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(theme.text2)
            }

            Spacer(minLength: 0)

            RuleSegmentedControl(
                options: StatisticsTimeRange.allCases.map { ($0, $0.titleKey) },
                selection: $timeRange,
                theme: theme
            )
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private func bodyContent(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            summaryTiles(theme: theme)
            heatmapCard(theme: theme)

            HStack(alignment: .top, spacing: 20) {
                topFeedsCard(theme: theme)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                topTagsCard(theme: theme)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
    }

    // 6 Kacheln statt 4 (Gesamt-Lesezeit + Trend zur Vorperiode ergänzt) — dafür
    // Umbau von einer HStack auf ein 3-spaltiges Grid, damit es bei der
    // Fensterbreite (defaultSize 820pt) nicht zu eng wird.
    private func summaryTiles(theme: RuleDialogTheme) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
            summaryTile(theme: theme, title: L10n.statisticsSummaryToday, value: "\(statistics.articlesReadToday)")
            summaryTile(theme: theme, title: L10n.statisticsSummaryThisWeek, value: "\(statistics.articlesReadThisWeek)")
            summaryTile(theme: theme, title: L10n.statisticsSummaryTotal, value: "\(statistics.articlesReadTotal)")
            summaryTile(
                theme: theme,
                title: L10n.statisticsSummaryAverageReadingTime,
                value: L10n.statisticsMinutesPerDay(Int(statistics.averageReadingMinutesPerDay.rounded()))
            )
            summaryTile(
                theme: theme,
                title: L10n.statisticsSummaryTotalReadingTime,
                value: formattedTotalReadingTime
            )
            summaryTile(
                theme: theme,
                title: L10n.statisticsSummarySelectedRangeCount,
                value: "\(statistics.articlesReadInSelectedRange)",
                trend: trendText
            )
        }
    }

    private var formattedTotalReadingTime: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 2

        return formatter.string(from: TimeInterval(statistics.totalReadingMinutesAllTime) * 60) ?? "0"
    }

    /// `nil` bei Zeitraum "Gesamt" oder wenn die Vorperiode 0 Artikel hatte —
    /// ein Prozentwert wäre dort unendlich/irreführend.
    private var trendText: (text: String, color: Color)? {
        guard let trendPercentage = statistics.trendPercentage else {
            return nil
        }

        let roundedPercentage = Int(trendPercentage.rounded())

        if roundedPercentage >= 0 {
            return (L10n.statisticsTrendIncrease(roundedPercentage), .green)
        }

        return (L10n.statisticsTrendDecrease(abs(roundedPercentage)), .red)
    }

    private func summaryTile(
        theme: RuleDialogTheme,
        title: LocalizedStringKey,
        value: String,
        trend: (text: String, color: Color)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.text2)

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.text)
                .monospacedDigit()

            if let trend {
                Text(trend.text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(trend.color)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func heatmapCard(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.statisticsHeatmapTitle)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.1)
                    .foregroundStyle(theme.text)

                Spacer(minLength: 8)

                Text(L10n.statisticsStreakText(current: statistics.currentStreak, longest: statistics.longestStreak))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.text2)
            }

            StatisticsHeatmapView(dailyCounts: statistics.dailyReadCounts, theme: theme)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func topFeedsCard(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.statisticsTopFeedsTitle)
                .font(.system(size: 14, weight: .bold))
                .tracking(-0.1)
                .foregroundStyle(theme.text)
                .padding(.bottom, 12)

            if statistics.topFeedsByTime.isEmpty {
                Text(L10n.statisticsTopFeedsEmpty)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.text2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(statistics.topFeedsByTime.enumerated()), id: \.offset) { index, feed in
                        topFeedRow(theme: theme, feed: feed, showTopBorder: index > 0)
                    }
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func topFeedRow(theme: RuleDialogTheme, feed: ReadingStatisticsFeedTime, showTopBorder: Bool) -> some View {
        HStack(spacing: 10) {
            feedFaviconView(feed: feed)
                .frame(width: 16, height: 16)

            Text(feed.feedTitle)
                .font(.system(size: 13))
                .foregroundStyle(theme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("\(feed.minutes) min")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.text)
                .monospacedDigit()
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            if showTopBorder {
                Rectangle().fill(theme.border).frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func feedFaviconView(feed: ReadingStatisticsFeedTime) -> some View {
        if let faviconURL = feed.faviconURL, let url = URL(string: faviconURL) {
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } placeholder: {
                Image(systemName: "dot.radiowaves.up.forward")
            }
        } else {
            Image(systemName: "dot.radiowaves.up.forward")
        }
    }

    private func topTagsCard(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.statisticsTopTagsTitle)
                .font(.system(size: 14, weight: .bold))
                .tracking(-0.1)
                .foregroundStyle(theme.text)
                .padding(.bottom, 12)

            if statistics.topTagsByTime.isEmpty {
                Text(L10n.statisticsTopTagsEmpty)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.text2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(statistics.topTagsByTime.enumerated()), id: \.offset) { index, tag in
                        topTagRow(theme: theme, tag: tag, showTopBorder: index > 0)
                    }
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func topTagRow(theme: RuleDialogTheme, tag: ReadingStatisticsTagTime, showTopBorder: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(TagColorPalette.color(for: tag.colorHex))
                .frame(width: 10, height: 10)

            Text(tag.name)
                .font(.system(size: 13))
                .foregroundStyle(theme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("\(tag.minutes) min")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.text)
                .monospacedDigit()
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            if showTopBorder {
                Rectangle().fill(theme.border).frame(height: 1)
            }
        }
    }

    private func footer(theme: RuleDialogTheme) -> some View {
        HStack {
            Spacer(minLength: 0)

            RuleDialogButton(
                titleKey: L10n.statisticsExportButton,
                style: .primary,
                theme: theme
            ) {
                exportDocument = StatisticsCSVDocument(
                    text: StatisticsExportService.buildCSV(
                        readingStatistics: statistics,
                        feedStatistics: feedStatistics
                    )
                )
                isExporting = true
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
    }

    private func loadStatistics() {
        guard let feedivoDatabase else {
            return
        }

        let statisticsStore = StatisticsStore(database: feedivoDatabase)

        do {
            statistics = try statisticsStore.readingStatistics(range: timeRange)

            let feeds = try FeedStore(database: feedivoDatabase).feeds()
            feedStatistics = try feeds.map { feed in
                (feed.title, try statisticsStore.feedReadingStatistics(feedID: feed.id))
            }
        } catch {
            statistics = .empty
            feedStatistics = []
        }
    }
}
