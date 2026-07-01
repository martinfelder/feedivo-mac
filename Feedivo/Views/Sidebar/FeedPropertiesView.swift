import AppKit
import SwiftData
import SwiftUI

struct FeedPropertiesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var tags: [Tag]

    @AppStorage(ArticleRetentionSettings.isEnabledKey)
    private var globalArticleRetentionIsEnabled = ArticleRetentionSettings.defaultIsEnabled

    @AppStorage(ArticleRetentionSettings.retentionDaysKey)
    private var globalArticleRetentionDays = ArticleRetentionSettings.defaultRetentionDays

    @AppStorage(ArticleRetentionSettings.includesProtectedArticlesKey)
    private var globalArticleRetentionIncludesProtectedArticles = ArticleRetentionSettings.defaultIncludesProtectedArticles

    let feed: Feed

    @State private var selectedRefreshInterval = BackgroundRefreshSettings.defaultIntervalMinutes
    @State private var feedRetentionOverridesGlobalSetting = false
    @State private var feedRetentionIsEnabled = false
    @State private var feedRetentionDays = ArticleRetentionSettings.defaultRetentionDays
    @State private var feedRetentionIncludesProtectedArticles = ArticleRetentionSettings.defaultIncludesProtectedArticles
    @State private var folderName = ""
    @State private var newTagName = ""
    @State private var tagViewModel = TagViewModel()

    private var latestArticle: Article? {
        // P7: Nur eine einzige Artikelzeile per fetchLimit laden statt
        // alle feed.articles in den Speicher zu faulten.
        FeedPropertiesQuery.latestArticle(in: modelContext, for: feed)
    }

    private var nextRefreshDate: Date? {
        FeedPropertiesFormatter.nextRefreshDate(
            lastRefreshed: feed.lastRefreshed,
            intervalMinutes: feed.refreshIntervalMinutes
        )
    }

    private var latestLogEntries: [FeedLogEntry] {
        // P7: Maximal 20 Log-Einträge per fetchLimit laden statt alle
        // feed.logEntries in den Speicher zu faulten.
        FeedPropertiesQuery.latestLogEntries(in: modelContext, for: feed)
    }

    private var articlesLastWeek: Int {
        FeedPropertiesQuery.recentArticleCount(
            in: modelContext,
            for: feed,
            since: Date().addingTimeInterval(-7 * 24 * 60 * 60)
        )
    }

    private var sortedFeedTags: [Tag] {
        (feed.tags ?? []).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var availableTagsToAdd: [Tag] {
        let assignedTagIDs = Set((feed.tags ?? []).map(\.id))
        return tags
            .filter { !assignedTagIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    feedHeader
                    detailsSection
                    activitySection
                    logSection
                }
                .padding(24)
            }

            Divider()

            HStack {
                Spacer()

                Button(L10n.commonDone) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 760, height: 650)
        .onAppear {
            selectedRefreshInterval = BackgroundRefreshSettings.clampedIntervalMinutes(
                feed.refreshIntervalMinutes
            )
            feedRetentionOverridesGlobalSetting = feed.articleRetentionOverridesGlobalSetting
            feedRetentionIsEnabled = feed.articleRetentionIsEnabled
            feedRetentionDays = ArticleRetentionSettings.clampedRetentionDays(feed.articleRetentionDays)
            feedRetentionIncludesProtectedArticles = feed.articleRetentionIncludesProtectedArticles
            folderName = feed.folderName ?? ""
        }
        .onChange(of: selectedRefreshInterval) {
            feed.refreshIntervalMinutes = selectedRefreshInterval
            try? modelContext.save()
        }
        .onChange(of: folderName) {
            feed.folderName = FeedFolderOrganizer.normalizedFolderName(folderName)
            try? modelContext.save()
        }
        .onChange(of: feedRetentionOverridesGlobalSetting) {
            syncFeedRetentionSettings()
        }
        .onChange(of: feedRetentionIsEnabled) {
            syncFeedRetentionSettings()
        }
        .onChange(of: feedRetentionDays) {
            feedRetentionDays = ArticleRetentionSettings.clampedRetentionDays(feedRetentionDays)
            syncFeedRetentionSettings()
        }
        .onChange(of: feedRetentionIncludesProtectedArticles) {
            syncFeedRetentionSettings()
        }
    }

    private var feedHeader: some View {
        HStack(alignment: .center, spacing: 20) {
            feedIcon

            VStack(alignment: .leading, spacing: 6) {
                Text(feed.title)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(feed.siteURL ?? feed.url)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 24)

            HStack(spacing: 18) {
                statusMetric(
                    icon: "clock",
                    value: "\(selectedRefreshInterval) Min.",
                    title: L10n.feedPropertiesRefreshInterval,
                    tint: .orange
                )

                metricDivider

                statusMetric(
                    icon: "calendar",
                    value: formattedHeaderTime(nextRefreshDate),
                    title: L10n.feedPropertiesNextFetch,
                    tint: .blue
                )

                metricDivider

                statusMetric(
                    icon: "checkmark.circle",
                    value: "\(FeedPropertiesQuery.latestLogEntryCount(in: modelContext, for: feed))",
                    title: L10n.feedPropertiesLogEntries,
                    tint: .green
                )
            }
        }
        .padding(.bottom, 12)
    }

    private var feedIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)

            if let faviconURL = feed.faviconURL, let url = URL(string: faviconURL) {
                CachedRemoteImageView(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                } placeholder: {
                    fallbackFeedIcon
                }
            } else {
                fallbackFeedIcon
            }
        }
        .frame(width: 64, height: 64)
    }

    private var fallbackFeedIcon: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.orange)
            .overlay {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(10)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 44)
    }

    private func statusMetric(
        icon: String,
        value: String,
        title: LocalizedStringKey,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tint)

                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 96, alignment: .leading)
    }

    private var detailsSection: some View {
        sectionContainer(title: L10n.feedPropertiesDetailsTitle) {
            propertyRow(L10n.feedPropertiesOriginalTitle, value: feed.originalTitle ?? feed.title)
            propertyDivider
            propertyRow(L10n.feedPropertiesWebsite, value: feed.siteURL, isLink: true)
            propertyDivider
            xmlAddressRow
            propertyDivider
            propertyRow(L10n.feedPropertiesFollowedAt, value: formattedDate(feed.followedAt))
            propertyDivider
            editableFolderRow
            propertyDivider
            editableTagsRow
            propertyDivider
            notificationToggleRow
            propertyDivider
            articleRetentionRow
            propertyDivider
            propertyRow(L10n.feedPropertiesLatestArticle, value: formattedLatestArticle)

            refreshDetailsGroup
                .padding(.top, 12)
        }
    }

    private var activitySection: some View {
        sectionContainer(title: L10n.feedPropertiesActivityTitle) {
            propertyRow(
                L10n.feedPropertiesArticlesLastWeek,
                value: L10n.feedPropertiesArticlesLastWeekCount(articlesLastWeek)
            )
            propertyDivider
            propertyRow(L10n.feedPropertiesLastRefreshed, value: formattedDate(feed.lastRefreshed))
        }
    }

    private var xmlAddressRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            propertyLabel(L10n.feedPropertiesXMLAddress)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                propertyValue(feed.url, isLink: true)

                Button {
                    copyXMLAddress()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(L10n.feedPropertiesCopyXMLAddress)
                .accessibilityLabel(Text(L10n.feedPropertiesCopyXMLAddress))
                .disabled(FeedPropertiesFormatter.copyableXMLAddress(feed.url) == nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }

    private var editableFolderRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            propertyLabel(L10n.feedPropertiesFolder)

            TextField(
                L10n.feedPropertiesNoFolder,
                text: $folderName,
                prompt: Text(L10n.feedPropertiesNoFolder)
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 280)
        }
        .padding(.vertical, 9)
    }

    private var editableTagsRow: some View {
        HStack(alignment: .top, spacing: 18) {
            propertyLabel(L10n.readerInspectorTags)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 10) {
                if sortedFeedTags.isEmpty {
                    Text(L10n.readerInspectorNoTags)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(sortedFeedTags) { tag in
                            feedTagPill(tag)
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField(
                        L10n.readerInspectorAddTagPlaceholder,
                        text: $newTagName,
                        prompt: Text(L10n.readerInspectorAddTagPlaceholder)
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .onSubmit(addTypedTag)

                    Button {
                        addTypedTag()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(TagViewModel.normalizedTagName(newTagName) == nil)
                }

                if !availableTagsToAdd.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(availableTagsToAdd) { tag in
                            availableFeedTagButton(tag)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }

    private var refreshDetailsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            propertyRow(L10n.feedPropertiesRefreshInterval) {
                Picker(L10n.feedPropertiesRefreshInterval, selection: $selectedRefreshInterval) {
                    ForEach(BackgroundRefreshSettings.allowedIntervalMinutes, id: \.self) { minutes in
                        Text(L10n.settingsAutomaticRefreshInterval(minutes: minutes))
                            .tag(minutes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 180, alignment: .leading)
            }

            propertyDivider
            propertyRow(L10n.feedPropertiesNextFetch, value: formattedDate(nextRefreshDate))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7))
        }
    }

    private var notificationToggleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            propertyLabel(L10n.feedPropertiesNotificationsEnabled)

            VStack(alignment: .leading, spacing: 5) {
                Toggle(
                    L10n.feedPropertiesNotificationsEnabled,
                    isOn: Binding(
                        get: {
                            feed.isNotificationEnabled
                        },
                        set: { isEnabled in
                            feed.isNotificationEnabled = isEnabled
                            try? modelContext.save()
                        }
                    )
                )
                .labelsHidden()

                Text(L10n.feedPropertiesNotificationsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }

    private var articleRetentionRow: some View {
        HStack(alignment: .top, spacing: 18) {
            propertyLabel(L10n.feedPropertiesArticleRetention)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    L10n.feedPropertiesArticleRetentionOverride,
                    isOn: $feedRetentionOverridesGlobalSetting
                )

                if feedRetentionOverridesGlobalSetting {
                    Toggle(
                        L10n.feedPropertiesArticleRetentionEnabled,
                        isOn: $feedRetentionIsEnabled
                    )

                    Picker(L10n.settingsArticleRetentionIntervalPicker, selection: $feedRetentionDays) {
                        ForEach(ArticleRetentionSettings.allowedRetentionDays, id: \.self) { days in
                            Text(L10n.settingsArticleRetentionInterval(days: days))
                                .tag(days)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!feedRetentionIsEnabled)
                    .frame(width: 180, alignment: .leading)

                    Toggle(
                        L10n.settingsArticleRetentionIncludesProtectedArticles,
                        isOn: $feedRetentionIncludesProtectedArticles
                    )
                    .disabled(!feedRetentionIsEnabled)
                } else {
                    Text(L10n.feedPropertiesArticleRetentionInherited)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }

    private func feedTagPill(_ tag: Tag) -> some View {
        let tagColor = TagColorPalette.color(for: tag.colorHex)

        return HStack(spacing: 6) {
            Text("#\(tag.name)")
                .lineLimit(1)

            Button {
                removeTag(tag)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(tagColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tagColor.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tagColor.opacity(0.22), lineWidth: 1)
        }
    }

    private func availableFeedTagButton(_ tag: Tag) -> some View {
        let tagColor = TagColorPalette.color(for: tag.colorHex)

        return Button {
            addTag(tag)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.caption2)

                Text("#\(tag.name)")
                    .lineLimit(1)
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(tagColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tagColor.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tagColor.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func addTypedTag() {
        guard let normalizedName = TagViewModel.normalizedTagName(newTagName) else {
            return
        }

        if let existingTag = tags.first(where: {
            $0.name.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
        }) {
            addTag(existingTag)
        } else if let createdTag = tagViewModel.createTag(
            name: normalizedName,
            colorHex: TagColorPalette.defaultColorHex,
            availableTags: tags,
            context: modelContext
        ) {
            addTag(createdTag)
        }

        newTagName = ""
    }

    private func addTag(_ tag: Tag) {
        guard !(feed.tags ?? []).contains(where: { $0.id == tag.id }) else {
            return
        }

        var tags = feed.tags ?? []
        tags.append(tag)
        feed.tags = tags
        try? modelContext.save()
    }

    private func removeTag(_ tag: Tag) {
        var tags = feed.tags ?? []
        tags.removeAll { $0.id == tag.id }
        feed.tags = tags
        try? modelContext.save()
    }

    private func syncFeedRetentionSettings() {
        feed.articleRetentionOverridesGlobalSetting = feedRetentionOverridesGlobalSetting
        feed.articleRetentionIsEnabled = feedRetentionIsEnabled
        feed.articleRetentionDays = ArticleRetentionSettings.clampedRetentionDays(feedRetentionDays)
        feed.articleRetentionIncludesProtectedArticles = feedRetentionIncludesProtectedArticles
        try? modelContext.save()

        _ = try? ArticleRetentionCleanupService.removeExpiredArticles(
            in: modelContext,
            isEnabled: globalArticleRetentionIsEnabled,
            retentionDays: globalArticleRetentionDays,
            includeProtectedArticles: globalArticleRetentionIncludesProtectedArticles
        )
    }

    private var logSection: some View {
        sectionContainer(title: L10n.feedPropertiesLogTitle) {
            if latestLogEntries.isEmpty {
                Text(L10n.feedPropertiesNoLogEntries)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(latestLogEntries.enumerated()), id: \.element.id) { index, entry in
                        logRow(entry)

                        if index < latestLogEntries.count - 1 {
                            propertyDivider
                                .padding(.leading, 38)
                        }
                    }
                }
            }
        }
    }

    private var formattedLatestArticle: String {
        guard let latestArticle else {
            return L10n.feedPropertiesUnavailable
        }

        if let publishedAt = latestArticle.publishedAt {
            return "\(latestArticle.title) · \(formattedDate(publishedAt))"
        }

        return latestArticle.title
    }

    private var propertyDivider: some View {
        Divider()
    }

    private func sectionContainer<Content: View>(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.8))
            }
        }
    }

    private func propertyRow(
        _ title: LocalizedStringKey,
        value: String?,
        isLink: Bool = false
    ) -> some View {
        propertyRow(title) {
            propertyValue(value, isLink: isLink)
        }
    }

    private func propertyRow<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder value: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            propertyLabel(title)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }

    private func propertyLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(width: 180, alignment: .leading)
    }

    @ViewBuilder
    private func propertyValue(_ value: String?, isLink: Bool = false) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if isLink, let url = FeedPropertiesFormatter.linkURL(value) {
                Link(destination: url) {
                    Text(value)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .textSelection(.enabled)
            } else {
                Text(value)
                    .foregroundStyle(isLink ? Color.accentColor : Color.primary)
                    .textSelection(.enabled)
            }
        } else {
            Text(L10n.feedPropertiesUnavailable)
                .foregroundStyle(.secondary)
        }
    }

    private func logRow(_ entry: FeedLogEntry) -> some View {
        let isError = entry.kindEnum == .error
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isError ? .red : .green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.message)
                    .lineLimit(2)

                Text(formattedDate(entry.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    private func copyXMLAddress() {
        guard let xmlAddress = FeedPropertiesFormatter.copyableXMLAddress(feed.url) else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(xmlAddress, forType: .string)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func formattedDate(_ date: Date?) -> String? {
        date.map(formattedDate)
    }

    private func formattedHeaderTime(_ date: Date?) -> String {
        date?.formatted(date: .omitted, time: .shortened) ?? "–"
    }
}
