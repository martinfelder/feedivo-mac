import AppKit
import SwiftData
import SwiftUI

struct FeedPropertiesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let feed: Feed

    @State private var selectedRefreshInterval = BackgroundRefreshSettings.defaultIntervalMinutes
    @State private var folderName = ""

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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    feedHeader
                    detailsSection
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
                    value: "\(FeedPropertiesFormatter.latestLogEntryCount(feed.logEntries))",
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
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                    default:
                        fallbackFeedIcon
                    }
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
            propertyRow(L10n.feedPropertiesLatestArticle, value: formattedLatestArticle)

            refreshDetailsGroup
                .padding(.top, 12)
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
            propertyDivider
            propertyRow(L10n.feedPropertiesLastRefreshed, value: formattedDate(feed.lastRefreshed))
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.kind == "error" ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(entry.kind == "error" ? .red : .green)
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
