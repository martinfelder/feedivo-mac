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
    @State private var feedViewModel = FeedViewModel()
    @State private var feedHealthCandidates: [ReadingStatisticsFeedHealth] = []
    @State private var feedPendingUnsubscribe: ReadingStatisticsFeedHealth?

    var body: some View {
        let theme = RuleDialogTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 0) {
            header(theme: theme)

            if let errorMessage = feedViewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.destructiveText)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 8)
            }

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
        .confirmationDialog(
            L10n.feedDeleteConfirmationTitle,
            isPresented: Binding(
                get: { feedPendingUnsubscribe != nil },
                set: { isPresented in
                    if !isPresented {
                        feedPendingUnsubscribe = nil
                    }
                }
            ),
            presenting: feedPendingUnsubscribe
        ) { candidate in
            Button(L10n.feedDeleteConfirmButton, role: .destructive) {
                unsubscribe(candidate)
            }

            Button(L10n.commonCancel, role: .cancel) {
                feedPendingUnsubscribe = nil
            }
        } message: { candidate in
            Text(L10n.feedDeleteConfirmationMessage(feedTitle: candidate.feedTitle))
        }
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
            heroSection(theme: theme)
            overviewStrip(theme: theme)
            habitsSection(theme: theme)
            attentionSection(theme: theme)
            feedHealthSection(theme: theme)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
    }

    private func habitsSection(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeader(theme: theme, title: L10n.statisticsSectionHabitsTitle, subtitle: L10n.statisticsSectionHabitsSubtitle)

            HStack(alignment: .top, spacing: 16) {
                sectionCard(theme: theme) {
                    VStack(alignment: .leading, spacing: 0) {
                        cardTitle(theme: theme, L10n.statisticsHabitsWeekdayTitle)
                        StatisticsWeekdayBarsView(weekdayCounts: statistics.weekdayCounts, theme: theme)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                sectionCard(theme: theme) {
                    VStack(alignment: .leading, spacing: 0) {
                        cardTitle(theme: theme, L10n.statisticsHabitsDaypartTitle)
                        StatisticsDaypartBarsView(daypartCounts: statistics.daypartCounts, theme: theme)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func sectionHeader(theme: RuleDialogTheme, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .tracking(-0.15)
                .foregroundStyle(theme.text)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(theme.text2)
        }
    }

    private func cardTitle(theme: RuleDialogTheme, _ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12.5, weight: .bold))
            .textCase(.uppercase)
            .tracking(0.4)
            .foregroundStyle(theme.text2)
            .padding(.bottom, 14)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(theme: RuleDialogTheme, @ViewBuilder content: () -> Content) -> some View {
        content()
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

    // Schmale 3-Werte-Leiste: gelesen im Zeitraum + Trend, Ø Artikel/Tag, Lesezeit
    private func overviewStrip(theme: RuleDialogTheme) -> some View {
        HStack(spacing: 0) {
            overviewItem(
                theme: theme,
                value: "\(statistics.articlesReadInSelectedRange)",
                label: L10n.statisticsSummarySelectedRangeCount,
                trend: trendText
            )
            overviewItem(
                theme: theme,
                value: formattedNumber(statistics.averageArticlesPerDay),
                label: L10n.statisticsOverviewAverageArticlesPerDay
            )
            overviewItem(
                theme: theme,
                value: formattedTotalReadingTime,
                label: L10n.statisticsSummaryTotalReadingTime,
                showsTrailingBorder: false
            )
        }
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
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

    private func overviewItem(
        theme: RuleDialogTheme,
        value: String,
        label: LocalizedStringKey,
        trend: (text: String, color: Color)? = nil,
        showsTrailingBorder: Bool = true
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .tracking(-0.2)
                .monospacedDigit()
                .foregroundStyle(theme.text)

            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(theme.text2)

            if let trend {
                Text(trend.text)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(trend.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(trend.color.opacity(0.14))
                    )
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            if showsTrailingBorder {
                Rectangle().fill(theme.border).frame(width: 1)
            }
        }
    }

    private func formattedNumber(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func heroSection(theme: RuleDialogTheme) -> some View {
        HStack(spacing: 0) {
            heroStreakColumn(theme: theme)
                .frame(width: 200)

            Rectangle()
                .fill(theme.border)
                .frame(width: 1)

            heroHeatmapColumn(theme: theme)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func heroStreakColumn(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.statisticsHeatmapTitle)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(theme.text2)

            Text("\(statistics.currentStreak)")
                .font(.system(size: 56, weight: .heavy))
                .tracking(-1.5)
                .foregroundStyle(theme.text)
                .monospacedDigit()

            Text(L10n.statisticsHeroStreakLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text2)

            Text(L10n.statisticsHeroLongestStreak(statistics.longestStreak))
                .font(.system(size: 12))
                .foregroundStyle(theme.text2)
                .padding(.top, 10)

            if let insight = ReadingStatisticsInsight.generate(
                weekdayCounts: statistics.weekdayCounts,
                daypartCounts: statistics.daypartCounts
            ) {
                Text(insight)
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(theme.text2)
                    .padding(.top, 16)
                    .overlay(alignment: .top) {
                        Rectangle().fill(theme.border).frame(height: 1)
                    }
            }
        }
        .padding(22)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func heroHeatmapColumn(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.statisticsHeatmapTitle)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(-0.1)
                    .foregroundStyle(theme.text)

                Spacer(minLength: 8)

                Text(L10n.statisticsHeatmapRange)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }

            StatisticsHeatmapView(dailyCounts: statistics.dailyReadCounts, theme: theme)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func attentionSection(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeader(theme: theme, title: L10n.statisticsSectionAttentionTitle, subtitle: L10n.statisticsSectionAttentionSubtitle)

            HStack(alignment: .top, spacing: 16) {
                sectionCard(theme: theme) {
                    VStack(alignment: .leading, spacing: 0) {
                        cardTitle(theme: theme, L10n.statisticsAttentionFeedsTitle)
                        if statistics.topFeedsByTime.isEmpty {
                            Text(L10n.statisticsAttentionEmpty)
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.text2)
                        } else {
                            StatisticsRankListView(
                                rows: statistics.topFeedsByTime,
                                theme: theme,
                                minutes: { $0.minutes },
                                title: { $0.feedTitle },
                                meta: { "\($0.articleCount) Artikel" },
                                icon: { feed in AnyView(feedFaviconView(feed: feed)) }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                sectionCard(theme: theme) {
                    VStack(alignment: .leading, spacing: 0) {
                        cardTitle(theme: theme, L10n.statisticsAttentionTagsTitle)
                        if statistics.topTagsByTime.isEmpty {
                            Text(L10n.statisticsAttentionEmpty)
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.text2)
                        } else {
                            StatisticsRankListView(
                                rows: statistics.topTagsByTime,
                                theme: theme,
                                minutes: { $0.minutes },
                                title: { $0.name },
                                meta: { "\($0.articleCount) Artikel" },
                                icon: { tag in
                                    AnyView(
                                        Circle()
                                            .fill(TagColorPalette.color(for: tag.colorHex))
                                    )
                                }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func feedHealthSection(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeader(theme: theme, title: L10n.statisticsSectionFeedHealthTitle, subtitle: L10n.statisticsSectionFeedHealthSubtitle)

            if feedHealthCandidates.isEmpty {
                sectionCard(theme: theme) {
                    Text(L10n.statisticsFeedHealthEmpty)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.text2)
                }
            } else {
                sectionCard(theme: theme) {
                    StatisticsFeedHealthListView(
                        candidates: feedHealthCandidates,
                        theme: theme,
                        onUnsubscribeTapped: { feedPendingUnsubscribe = $0 }
                    )
                }
            }
        }
    }

    private func unsubscribe(_ candidate: ReadingStatisticsFeedHealth) {
        feedPendingUnsubscribe = nil
        guard let feedivoDatabase else {
            return
        }
        feedViewModel.deleteFeed(feedID: candidate.feedID, sqliteDatabase: feedivoDatabase)
        // deleteFeed wirft nicht — ein Fehlschlag landet nur in feedViewModel.errorMessage.
        // Die Zeile darf deshalb nur bei tatsächlichem Erfolg entfernt werden, sonst würde
        // die UI ein gelöschtes Feed vortäuschen, das in Wahrheit noch existiert.
        if feedViewModel.errorMessage == nil {
            feedHealthCandidates.removeAll { $0.feedID == candidate.feedID }
        }
    }

    @ViewBuilder
    private func feedFaviconView(feed: ReadingStatisticsFeedTime) -> some View {
        if let faviconURL = feed.faviconURL, let url = URL(string: faviconURL) {
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } placeholder: {
                Image(systemName: "dot.radiowaves.up.forward")
            }
        } else {
            Image(systemName: "dot.radiowaves.up.forward")
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

            feedHealthCandidates = try statisticsStore.feedHealthCandidates()
        } catch {
            statistics = .empty
            feedStatistics = []
            feedHealthCandidates = []
        }
    }
}
