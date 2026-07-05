import SwiftUI

struct FeedManagementOrganizerView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @Environment(\.feedivoDatabase) private var feedivoDatabase

    @State private var feeds: [FeedRecord] = []
    @State private var opmlFeeds: [OPMLFeed] = []
    @State private var searchText = ""
    @State private var selectedFeedIDs: Set<String> = []
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingOPMLExportSheet = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OrganizerSectionHeader(
                title: L10n.settingsFeedsSection,
                description: L10n.settingsFeedsDescription
            )

            HStack(spacing: 10) {
                TextField(L10n.settingsFeedsSearchPlaceholder, text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Button(L10n.settingsFeedsSelectVisible) {
                    FeedManagementSettingsState.selectVisibleFeeds(
                        visibleFeeds,
                        selectedFeedIDs: &selectedFeedIDs
                    )
                }
                .disabled(visibleFeeds.isEmpty)

                Button(L10n.settingsFeedsClearSelection) {
                    FeedManagementSettingsState.clearSelection(&selectedFeedIDs)
                }
                .disabled(selectedFeedIDs.isEmpty)

                Button(L10n.feedExportOPMLCommand) {
                    isShowingOPMLExportSheet = true
                }
                .disabled(feeds.isEmpty)
            }

            if feeds.isEmpty {
                ContentUnavailableView(L10n.settingsFeedsNoFeeds, systemImage: "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if visibleFeeds.isEmpty {
                ContentUnavailableView(L10n.settingsFeedsNoMatches, systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleFeeds) { feed in
                        FeedManagementOrganizerRow(
                            feed: feed,
                            isSelected: selectedFeedIDs.contains(feed.id),
                            sqliteDatabase: feedivoDatabase
                        ) { isSelected in
                            if isSelected {
                                selectedFeedIDs.insert(feed.id)
                            } else {
                                selectedFeedIDs.remove(feed.id)
                            }
                        }

                        if feed.id != visibleFeeds.last?.id {
                            Divider()
                                .padding(.leading, 36)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }

            HStack {
                Text(L10n.settingsFeedsSelectedCount(count: selectedFeeds.count))
                    .font(interfaceTextSize.font(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(L10n.settingsFeedsDeleteSelected, role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                .disabled(selectedFeeds.isEmpty)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog(
            L10n.settingsFeedsDeleteConfirmationTitle,
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.settingsFeedsDeleteSelected, role: .destructive) {
                deleteSelectedFeeds()
            }

            Button(L10n.commonCancel, role: .cancel) {}
        } message: {
            Text(L10n.settingsFeedsDeleteConfirmationMessage(count: selectedFeeds.count))
        }
        .sheet(isPresented: $isShowingOPMLExportSheet) {
            OPMLExportSheet(opmlFeeds: opmlFeeds) {
                isShowingOPMLExportSheet = false
            }
        }
        .task {
            loadFeeds()
        }
    }

    private var visibleFeeds: [FeedRecord] {
        FeedManagementSettingsState.filteredFeeds(feeds, searchText: searchText)
    }

    private var selectedFeeds: [FeedRecord] {
        feeds.filter { feed in
            selectedFeedIDs.contains(feed.id)
        }
    }

    private func deleteSelectedFeeds() {
        guard let database = feedivoDatabase else {
            errorMessage = "SQLite-Datenbank ist nicht verfügbar."
            return
        }

        let feedsToDelete = selectedFeeds

        for feed in feedsToDelete {
            do {
                try FeedStore(database: database).delete(id: feed.id)
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }

        selectedFeedIDs.subtract(feedsToDelete.map(\.id))
        if errorMessage == nil {
            SQLiteDataInvalidation.bumpStatusVersion()
            loadFeeds()
        }
    }

    private func loadFeeds() {
        guard let database = feedivoDatabase else {
            feeds = []
            opmlFeeds = []
            errorMessage = "SQLite-Datenbank ist nicht verfügbar."
            return
        }

        do {
            feeds = try FeedStore(database: database).feeds()
            opmlFeeds = try FeedStore(database: database).opmlFeedsForExport()
            selectedFeedIDs.formIntersection(Set(feeds.map(\.id)))
            errorMessage = nil
        } catch {
            feeds = []
            opmlFeeds = []
            errorMessage = error.localizedDescription
        }
    }
}

private struct FeedManagementOrganizerRow: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let feed: FeedRecord
    let isSelected: Bool
    let sqliteDatabase: FeedivoDatabase?
    let setSelected: (Bool) -> Void
    @State private var sqliteArticleMetrics = FeedPropertiesArticleMetricsSnapshot.empty

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: setSelected
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(feed.title)
                    .font(interfaceTextSize.font(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(feed.url)
                    .font(interfaceTextSize.font(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(feedActivitySummary)
                    .font(interfaceTextSize.font(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
        .onTapGesture {
            setSelected(!isSelected)
        }
        .onAppear {
            loadSQLiteArticleMetrics()
        }
        .onChange(of: feed.id) {
            loadSQLiteArticleMetrics()
        }
    }

    private var feedActivitySummary: String {
        let articlesLastWeek = sqliteArticleMetrics.recentArticleCount
        let articleText = L10n.feedPropertiesArticlesLastWeekCount(articlesLastWeek)
        let lastRefreshed = feed.lastRefreshedAt?.formatted(date: .abbreviated, time: .shortened)
            ?? L10n.feedPropertiesUnavailable

        return "\(articleText) · \(String(localized: "feed.properties.lastRefreshed")): \(lastRefreshed)"
    }

    private func loadSQLiteArticleMetrics(now: Date = Date()) {
        guard let database = sqliteDatabase else {
            sqliteArticleMetrics = .empty
            return
        }

        sqliteArticleMetrics = (
            try? ArticleStore(database: database).feedPropertiesMetrics(
                feedID: feed.id,
                recentCutoffDate: now.addingTimeInterval(-7 * 24 * 60 * 60),
                now: now
            )
        ) ?? .empty
    }
}
