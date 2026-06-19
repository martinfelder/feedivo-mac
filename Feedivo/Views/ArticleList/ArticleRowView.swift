import SwiftUI

struct ArticleRowView: View {
    let article: Article
    let onToggleRead: () -> Void
    let onToggleStarred: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            previewImage

            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(.headline)
                    .fontWeight(article.isRead ? .regular : .semibold)
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(2)

                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(article.isRead ? .tertiary : .secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack {
                unreadIndicator

                Spacer(minLength: 8)

                Button(action: onToggleStarred) {
                    Image(systemName: article.isStarred ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(article.isStarred ? .yellow : .secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(article.isStarred ? "Stern entfernen" : "Mit Stern markieren")
            }
            .frame(width: 28, height: 76, alignment: .top)
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button(article.isRead ? "Als ungelesen markieren" : "Als gelesen markieren") {
                onToggleRead()
            }

            Button(article.isStarred ? "Stern entfernen" : "Mit Stern markieren") {
                onToggleStarred()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var previewImage: some View {
        if let imageURL = article.imageURL, let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholderImage
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            placeholderImage
                .frame(width: 56, height: 56)
        }
    }

    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.12))
            .overlay {
                Image(systemName: "doc.text")
                    .font(.system(size: 20))
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
                .help("Ungelesen")
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
            parts.append("Ungelesen")
        }

        if article.isStarred {
            parts.append("Mit Stern")
        }

        return parts.joined(separator: ", ")
    }
}
