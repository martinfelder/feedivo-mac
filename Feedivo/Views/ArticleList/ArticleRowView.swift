import SwiftUI

struct ArticleRowView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    @AppStorage(ArticleListImagePosition.storageKey)
    private var imagePositionRawValue = ArticleListImagePosition.defaultPosition.rawValue

    @AppStorage(ArticleListFeedNameVisibilitySettings.showsFeedNameKey)
    private var showsFeedName = ArticleListFeedNameVisibilitySettings.defaultShowsFeedName

    @AppStorage(ArticleListFeedNamePosition.storageKey)
    private var feedNamePositionRawValue = ArticleListFeedNamePosition.defaultPosition.rawValue

    @AppStorage(ArticleListSummaryLineCount.storageKey)
    private var summaryLineCount = ArticleListSummaryLineCount.defaultValue

    @AppStorage(ArticleDateDisplayMode.storageKey)
    private var dateDisplayModeRawValue = ArticleDateDisplayMode.defaultMode.rawValue

    private var imagePosition: ArticleListImagePosition {
        ArticleListImagePosition.resolved(from: imagePositionRawValue)
    }

    private var feedNamePosition: ArticleListFeedNamePosition {
        ArticleListFeedNamePosition.resolved(from: feedNamePositionRawValue)
    }

    private var dateDisplayMode: ArticleDateDisplayMode {
        ArticleDateDisplayMode.resolved(from: dateDisplayModeRawValue)
    }

    private var resolvedSummaryLineCount: Int {
        ArticleListSummaryLineCount.resolved(from: summaryLineCount)
    }

    // Feste, aus den Anzeige-Einstellungen berechnete Zeilenhöhe statt
    // natürlicher Inhaltsgröße (NetNewsWire-Vergleich, 2026-07-28) — macht
    // jede Zeile innerhalb derselben Einstellungs-Kombination exakt gleich
    // hoch, damit SwiftUIs List nicht pro sichtbarer Zeile Text-Layout neu
    // berechnen muss. Siehe ArticleRowHeightMetrics.
    private var rowHeight: CGFloat {
        ArticleRowHeightMetrics.height(
            interfaceTextSize: interfaceTextSize,
            imagePosition: imagePosition,
            summaryLineCount: resolvedSummaryLineCount
        )
    }

    private var rowContentHeight: CGFloat {
        ArticleRowHeightMetrics.contentHeight(
            interfaceTextSize: interfaceTextSize,
            imagePosition: imagePosition,
            summaryLineCount: resolvedSummaryLineCount
        )
    }

    let snapshot: ArticleListItemSnapshot
    let hasAvailableTags: Bool
    let onToggleRead: () -> Void
    let onToggleStarred: () -> Void
    let onToggleArchived: () -> Void
    let onRequestAssignTag: () -> Void
    let onCreateRule: () -> Void
    let onCopyLink: () -> Void
    let onOpenOriginal: () -> Void
    let onShareOriginal: () -> Void
    let onOpenInNewTab: () -> Void
    let onOpenInWindow: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    let onMarkAllRead: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if imagePosition == .left {
                previewImage
            }

            VStack(alignment: .leading, spacing: 6) {
                if feedNamePosition == .beforeTitle {
                    metadataRow
                }

                Text(snapshot.title)
                    .font(interfaceTextSize.font(size: 14, weight: snapshot.isRead ? .regular : .semibold))
                    .fontWeight(snapshot.isRead ? .regular : .semibold)
                    .foregroundStyle(snapshot.isRead ? .secondary : .primary)
                    .lineLimit(2)

                if feedNamePosition == .afterTitle {
                    metadataRow
                }

                if resolvedSummaryLineCount > 0, let summary = snapshot.summary, !summary.isEmpty {
                    Text(summary)
                        .font(interfaceTextSize.font(size: 13))
                        .foregroundStyle(snapshot.isRead ? .tertiary : .secondary)
                        .lineLimit(resolvedSummaryLineCount)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if imagePosition == .right {
                previewImage
            }

            VStack {
                unreadIndicator

                Spacer(minLength: 8)

                Button(action: onToggleStarred) {
                    Image(systemName: snapshot.isStarred ? "star.fill" : "star")
                        .font(interfaceTextSize.font(size: 14, weight: .semibold))
                        .foregroundStyle(snapshot.isStarred ? .yellow : .secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(snapshot.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd)
            }
            .frame(width: 28, height: rowContentHeight, alignment: .top)
        }
        .padding(.vertical, 6)
        .padding(.leading, 8)
        .frame(height: rowHeight, alignment: .top)
        .contextMenu {
            Button(snapshot.isRead ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead) {
                onToggleRead()
            }

            Button(snapshot.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd) {
                onToggleStarred()
            }

            Divider()

            Button(snapshot.isArchived ? L10n.articleUnarchiveCommand : L10n.articleArchiveCommand) {
                onToggleArchived()
            }

            Button(L10n.articleAssignTagCommand) {
                onRequestAssignTag()
            }
            .disabled(!hasAvailableTags)

            Button(L10n.articleCreateRuleCommand) {
                onCreateRule()
            }

            Divider()

            Button(L10n.articleOpenInNewTabCommand) {
                onOpenInNewTab()
            }

            Button(L10n.articleOpenInWindowCommand) {
                onOpenInWindow()
            }

            Button(L10n.articleCopyLinkCommand) {
                onCopyLink()
            }
            .disabled(!hasOriginalURL)

            Button(L10n.articleOpenOriginalCommand) {
                onOpenOriginal()
            }
            .disabled(!hasOriginalURL)

            Button(L10n.articleShareCommand) {
                onShareOriginal()
            }
            .disabled(!hasOriginalURL)

            Button(L10n.articleExportCommand) {
                onExport()
            }

            Button(L10n.articleDeleteCommand, role: .destructive) {
                onDelete()
            }

            Divider()

            Button(L10n.articleMarkAllReadCommand) {
                onMarkAllRead()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var previewImage: some View {
        if let imageURL = snapshot.imageURL, let url = URL(string: imageURL) {
            CachedRemoteImageView(url: url, targetPixelSize: previewImageTargetPixelSize) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholderImage
            }
            .frame(
                width: previewImageSide,
                height: previewImageSide
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            placeholderImage
                .frame(
                    width: previewImageSide,
                    height: previewImageSide
                )
        }
    }

    private var previewImageSide: CGFloat {
        interfaceTextSize.scaled(56)
    }

    private var previewImageTargetPixelSize: CGSize {
        let retinaScale: CGFloat = 2
        return CGSize(
            width: previewImageSide * retinaScale,
            height: previewImageSide * retinaScale
        )
    }

    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.12))
            .overlay {
                Image(systemName: "doc.text")
                    .font(interfaceTextSize.font(size: 20))
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private var unreadIndicator: some View {
        if snapshot.isRead {
            Circle()
                .fill(.clear)
                .frame(width: 8, height: 8)
        } else {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
                .help(L10n.articleRowUnreadText)
        }
    }

    @ViewBuilder
    private var metadataRow: some View {
        if !metadataText.isEmpty {
            HStack(spacing: 4) {
                if showsFeedNameAndFavicon {
                    metadataFavicon
                        .frame(
                            width: interfaceTextSize.scaled(11),
                            height: interfaceTextSize.scaled(11)
                        )
                }

                Text(metadataText)
                    .font(interfaceTextSize.font(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var metadataFavicon: some View {
        if let faviconURLString = snapshot.faviconURL, let url = URL(string: faviconURLString) {
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                metadataFaviconFallback
            }
        } else {
            metadataFaviconFallback
        }
    }

    private var metadataFaviconFallback: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
    }

    // Favicon nur zeigen, wenn auch tatsächlich ein Feedname angezeigt wird —
    // ist der Feedname ausgeblendet, bleibt nur der Zeitpunkt sichtbar, ohne
    // Favicon davor (siehe FEATURES.md 19.1, Entscheidung 2026-07-08).
    private var showsFeedNameAndFavicon: Bool {
        showsFeedName && snapshot.feedTitle?.isEmpty == false
    }

    private var metadataText: String {
        let feedNamePart = showsFeedNameAndFavicon ? snapshot.feedTitle : nil

        return [
            feedNamePart,
            snapshot.publishedAt?.feedivoDisplay(mode: dateDisplayMode)
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else {
                return nil
            }

            return value
        }
        .joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        var parts = [snapshot.title]

        if !snapshot.isRead {
            parts.append(L10n.articleRowUnreadText)
        }

        if snapshot.isStarred {
            parts.append(L10n.articleRowStarredText)
        }

        return parts.joined(separator: ", ")
    }

    private var hasOriginalURL: Bool {
        snapshot.hasOriginalURL
    }
}
