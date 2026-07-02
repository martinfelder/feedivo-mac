import SwiftUI

struct ArticleRowView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

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
    let onOpenInWindow: () -> Void
    let onExport: () -> Void
    let onSaveOrRemoveOffline: () -> Void
    let onDelete: () -> Void
    let onMarkAllRead: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            previewImage

            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.title)
                    .font(interfaceTextSize.font(size: 14, weight: snapshot.isRead ? .regular : .semibold))
                    .fontWeight(snapshot.isRead ? .regular : .semibold)
                    .foregroundStyle(snapshot.isRead ? .secondary : .primary)
                    .lineLimit(2)

                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(interfaceTextSize.font(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let summary = snapshot.summary, !summary.isEmpty {
                    Text(summary)
                        .font(interfaceTextSize.font(size: 13))
                        .foregroundStyle(snapshot.isRead ? .tertiary : .secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack {
                unreadIndicator

                offlineIndicator

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
            .frame(width: 28, height: 76, alignment: .top)
        }
        .padding(.vertical, 6)
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

            Button(snapshot.offlineState.isAvailable ? L10n.readerOfflineRemove : L10n.readerOfflineSave) {
                onSaveOrRemoveOffline()
            }

            Divider()

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
                .fill(.blue)
                .frame(width: 8, height: 8)
                .help(L10n.articleRowUnreadText)
        }
    }

    @ViewBuilder
    private var offlineIndicator: some View {
        switch snapshot.offlineState {
        case .fullText, .feedContent:
            Image(systemName: "arrow.down.circle.fill")
                .font(interfaceTextSize.font(size: 11, weight: .semibold))
                .foregroundStyle(.green)
                .help(L10n.articleRowOfflineAvailable)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(interfaceTextSize.font(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
                .help(L10n.articleRowOfflineFailed)
        case .none:
            EmptyView()
        }
    }

    private var metadataText: String {
        [
            snapshot.feedTitle,
            snapshot.publishedAt?.feedivoRelativeDisplay
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
