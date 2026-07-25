import SwiftUI

struct FeedManagementOrganizerView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.colorScheme) private var colorScheme

    @State private var feeds: [FeedRecord] = []
    @State private var opmlFeeds: [OPMLFeed] = []
    @State private var searchText = ""
    @State private var selectedFeedIDs: Set<String> = []
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingOPMLExportSheet = false
    @State private var feedPendingDeletion: FeedRecord?
    @State private var errorMessage: String?

    private var theme: RuleDialogTheme {
        RuleDialogTheme(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            OrganizerSectionHeader(
                title: L10n.settingsFeedsSection,
                description: L10n.settingsFeedsDescription
            )

            FlowLayout(spacing: 10) {
                RuleDialogTextField(
                    placeholder: L10n.settingsFeedsSearchPlaceholder,
                    text: $searchText,
                    theme: theme
                )
                .frame(minWidth: 260)

                RuleDialogButton(
                    titleKey: L10n.settingsFeedsSelectVisible,
                    style: .secondary,
                    theme: theme
                ) {
                    FeedManagementSettingsState.selectVisibleFeeds(
                        visibleFeeds,
                        selectedFeedIDs: &selectedFeedIDs
                    )
                }
                .disabled(visibleFeeds.isEmpty)
                .opacity(visibleFeeds.isEmpty ? 0.45 : 1)

                RuleDialogButton(
                    titleKey: L10n.settingsFeedsClearSelection,
                    style: .secondary,
                    theme: theme
                ) {
                    FeedManagementSettingsState.clearSelection(&selectedFeedIDs)
                }
                .disabled(selectedFeedIDs.isEmpty)
                .opacity(selectedFeedIDs.isEmpty ? 0.45 : 1)

                RuleDialogButton(
                    titleKey: LocalizedStringKey(L10n.feedExportOPMLCommand),
                    style: .secondary,
                    theme: theme
                ) {
                    isShowingOPMLExportSheet = true
                }
                .disabled(feeds.isEmpty)
                .opacity(feeds.isEmpty ? 0.45 : 1)

                RuleDialogButton(
                    titleKey: L10n.settingsFeedsDeleteSelected,
                    style: .destructive(isActive: !selectedFeeds.isEmpty),
                    theme: theme,
                    systemImage: selectedFeeds.isEmpty ? nil : "trash",
                    titleSuffix: selectedFeeds.isEmpty ? nil : " (\(selectedFeeds.count))"
                ) {
                    isShowingDeleteConfirmation = true
                }
                .disabled(selectedFeeds.isEmpty)
                .opacity(selectedFeeds.isEmpty ? 0.55 : 1)

                RuleDialogButton(
                    titleKey: L10n.settingsFeedsNotifySelected,
                    style: .secondary,
                    theme: theme,
                    systemImage: selectedFeeds.isEmpty ? nil : "bell.fill",
                    titleSuffix: selectedFeeds.isEmpty ? nil : " (\(selectedFeeds.count))"
                ) {
                    setNotificationEnabled(true, for: selectedFeeds)
                }
                .disabled(selectedFeeds.isEmpty)
                .opacity(selectedFeeds.isEmpty ? 0.45 : 1)

                RuleDialogButton(
                    titleKey: L10n.settingsFeedsUnnotifySelected,
                    style: .secondary,
                    theme: theme,
                    systemImage: selectedFeeds.isEmpty ? nil : "bell.slash",
                    titleSuffix: selectedFeeds.isEmpty ? nil : " (\(selectedFeeds.count))"
                ) {
                    setNotificationEnabled(false, for: selectedFeeds)
                }
                .disabled(selectedFeeds.isEmpty)
                .opacity(selectedFeeds.isEmpty ? 0.45 : 1)
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
                            theme: theme,
                            sqliteDatabase: feedivoDatabase,
                            onDelete: { feedPendingDeletion = feed },
                            onToggleNotification: { toggleNotification(for: feed) }
                        ) { isSelected in
                            if isSelected {
                                selectedFeedIDs.insert(feed.id)
                            } else {
                                selectedFeedIDs.remove(feed.id)
                            }
                        }

                        if feed.id != visibleFeeds.last?.id {
                            Rectangle()
                                .fill(theme.border)
                                .frame(height: 1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .confirmationDialog(
            L10n.feedDeleteConfirmationTitle,
            isPresented: Binding(
                get: { feedPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        feedPendingDeletion = nil
                    }
                }
            ),
            presenting: feedPendingDeletion
        ) { feed in
            Button(L10n.feedDeleteConfirmButton, role: .destructive) {
                deleteFeed(feed)
                feedPendingDeletion = nil
            }

            Button(L10n.commonCancel, role: .cancel) {
                feedPendingDeletion = nil
            }
        } message: { feed in
            Text(L10n.feedDeleteConfirmationMessage(feedTitle: feed.title))
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
        deleteFeeds(selectedFeeds)
    }

    private func deleteFeed(_ feed: FeedRecord) {
        deleteFeeds([feed])
    }

    private func deleteFeeds(_ feedsToDelete: [FeedRecord]) {
        guard let database = feedivoDatabase else {
            errorMessage = "SQLite-Datenbank ist nicht verfügbar."
            return
        }

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

    private func toggleNotification(for feed: FeedRecord) {
        setNotificationEnabled(!feed.isNotificationEnabled, for: [feed])
    }

    private func setNotificationEnabled(_ isEnabled: Bool, for feedsToUpdate: [FeedRecord]) {
        guard let database = feedivoDatabase else {
            errorMessage = "SQLite-Datenbank ist nicht verfügbar."
            return
        }

        for feed in feedsToUpdate {
            do {
                try FeedStore(database: database).updateNotificationEnabled(id: feed.id, isEnabled: isEnabled)
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }

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
    let theme: RuleDialogTheme
    let sqliteDatabase: FeedivoDatabase?
    let onDelete: () -> Void
    let onToggleNotification: () -> Void
    let setSelected: (Bool) -> Void
    @State private var sqliteArticleMetrics = FeedPropertiesArticleMetricsSnapshot.empty

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RuleDialogCheckbox(isOn: isSelected, theme: theme)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(feed.title)
                    .font(interfaceTextSize.font(size: 14.5, weight: .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Text(feed.url)
                    .font(interfaceTextSize.font(size: 12.5))
                    .foregroundStyle(theme.linkText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(feedActivitySummary)
                    .font(interfaceTextSize.font(size: 12))
                    .foregroundStyle(theme.text2)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onToggleNotification) {
                Image(systemName: feed.isNotificationEnabled ? "bell.fill" : "bell.slash")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.text2)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(feed.isNotificationEnabled ? L10n.settingsFeedsRowDisableNotification : L10n.settingsFeedsRowEnableNotification)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.text2)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(L10n.feedDeleteConfirmButton)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? theme.selectionTint : Color.clear)
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
