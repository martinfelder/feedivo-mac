import SwiftUI

struct ArticleRowView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let article: Article
    let availableTags: [Tag]
    let onToggleRead: () -> Void
    let onToggleStarred: () -> Void
    let onToggleArchived: () -> Void
    let onAssignTag: (Tag) -> Void
    let onCreateRule: () -> Void
    let onCopyLink: () -> Void
    let onOpenOriginal: () -> Void
    let onShareOriginal: () -> Void
    let onSaveOrRemoveOffline: () -> Void
    let onDelete: () -> Void
    let onMarkAllRead: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            previewImage

            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(interfaceTextSize.font(size: 14, weight: article.isRead ? .regular : .semibold))
                    .fontWeight(article.isRead ? .regular : .semibold)
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(2)

                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(interfaceTextSize.font(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(interfaceTextSize.font(size: 13))
                        .foregroundStyle(article.isRead ? .tertiary : .secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack {
                unreadIndicator

                offlineIndicator

                Spacer(minLength: 8)

                Button(action: onToggleStarred) {
                    Image(systemName: article.isStarred ? "star.fill" : "star")
                        .font(interfaceTextSize.font(size: 14, weight: .semibold))
                        .foregroundStyle(article.isStarred ? .yellow : .secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(article.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd)
            }
            .frame(width: 28, height: 76, alignment: .top)
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button(article.isRead ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead) {
                onToggleRead()
            }

            Button(article.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd) {
                onToggleStarred()
            }

            Divider()

            Button(article.isArchived ? L10n.articleUnarchiveCommand : L10n.articleArchiveCommand) {
                onToggleArchived()
            }

            Menu(L10n.articleAssignTagCommand) {
                ForEach(availableTags) { tag in
                    Button(tag.name) {
                        onAssignTag(tag)
                    }
                }
            }
            .disabled(availableTags.isEmpty)

            Button(L10n.articleCreateRuleCommand) {
                onCreateRule()
            }

            Divider()

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

            Button(article.offlineState.isAvailable ? L10n.readerOfflineRemove : L10n.readerOfflineSave) {
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
        if let imageURL = article.imageURL, let url = URL(string: imageURL) {
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholderImage
            }
            .frame(
                width: interfaceTextSize.scaled(56),
                height: interfaceTextSize.scaled(56)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            placeholderImage
                .frame(
                    width: interfaceTextSize.scaled(56),
                    height: interfaceTextSize.scaled(56)
                )
        }
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
        if article.isRead {
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
        switch article.offlineState {
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
            article.feed?.title,
            article.publishedAt?.feedivoRelativeDisplay
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
        var parts = [article.title]

        if !article.isRead {
            parts.append(L10n.articleRowUnreadText)
        }

        if article.isStarred {
            parts.append(L10n.articleRowStarredText)
        }

        return parts.joined(separator: ", ")
    }

    private var hasOriginalURL: Bool {
        ArticleViewModel().originalURL(for: article) != nil
    }
}
