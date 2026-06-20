import SwiftData
import SwiftUI

struct FeedPropertiesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let feed: Feed

    @State private var selectedRefreshInterval = BackgroundRefreshSettings.defaultIntervalMinutes

    private var latestArticle: Article? {
        FeedPropertiesFormatter.latestArticle(in: feed.articles)
    }

    private var nextRefreshDate: Date? {
        FeedPropertiesFormatter.nextRefreshDate(
            lastRefreshed: feed.lastRefreshed,
            intervalMinutes: feed.refreshIntervalMinutes
        )
    }

    private var latestLogEntries: [FeedLogEntry] {
        FeedPropertiesFormatter.latestLogEntries(feed.logEntries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    propertiesGrid
                    logSection
                }
                .padding(.trailing, 2)
            }

            HStack {
                Spacer()

                Button(L10n.commonDone) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 680, height: 620)
        .onAppear {
            selectedRefreshInterval = BackgroundRefreshSettings.clampedIntervalMinutes(
                feed.refreshIntervalMinutes
            )
        }
        .onChange(of: selectedRefreshInterval) {
            feed.refreshIntervalMinutes = selectedRefreshInterval
            try? modelContext.save()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.feedPropertiesTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(feed.title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var propertiesGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 12) {
            propertyRow(L10n.feedPropertiesOriginalTitle, value: feed.title)
            propertyRow(L10n.feedPropertiesWebsite, value: feed.siteURL)
            propertyRow(L10n.feedPropertiesXMLAddress, value: feed.url)
            propertyRow(L10n.feedPropertiesFollowedAt, value: formattedDate(feed.followedAt))
            propertyRow(L10n.feedPropertiesFolder, value: feed.folderName ?? L10n.feedPropertiesNoFolder)
            propertyRow(L10n.feedPropertiesLatestArticle, value: formattedLatestArticle)

            GridRow {
                propertyLabel(L10n.feedPropertiesRefreshInterval)

                Picker(L10n.feedPropertiesRefreshInterval, selection: $selectedRefreshInterval) {
                    ForEach(BackgroundRefreshSettings.allowedIntervalMinutes, id: \.self) { minutes in
                        Text(L10n.settingsAutomaticRefreshInterval(minutes: minutes))
                            .tag(minutes)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220, alignment: .leading)
            }

            propertyRow(L10n.feedPropertiesNextFetch, value: formattedDate(nextRefreshDate))
            propertyRow(L10n.feedPropertiesLastRefreshed, value: formattedDate(feed.lastRefreshed))
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.feedPropertiesLogTitle)
                .font(.headline)

            if latestLogEntries.isEmpty {
                Text(L10n.feedPropertiesNoLogEntries)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(latestLogEntries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: entry.kind == "error" ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(entry.kind == "error" ? .red : .green)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.message)
                                    .lineLimit(2)

                                Text(formattedDate(entry.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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

    private func propertyRow(_ title: LocalizedStringKey, value: String?) -> some View {
        GridRow {
            propertyLabel(title)
            propertyValue(value)
        }
    }

    private func propertyLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func propertyValue(_ value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(value)
                .textSelection(.enabled)
        } else {
            Text(L10n.feedPropertiesUnavailable)
                .foregroundStyle(.secondary)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func formattedDate(_ date: Date?) -> String? {
        date.map(formattedDate)
    }
}
