import SwiftUI

/// Einzelne Artikelzeile im Menubar-Dropdown: Favicon (leading) + Titel
/// (max. 2 Zeilen) + Feedname/relative Zeit, optional Thumbnail (trailing),
/// wenn der Artikel ein Bild hat. Ersetzt die zuvor rein textuelle Zeile in
/// `MenubarDropdownView`.
struct MenubarArticleRowView: View {
    let article: ArticleListItemSnapshot

    var body: some View {
        HStack(spacing: 8) {
            faviconView
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(article.title)
                    .lineLimit(2)

                subtitleView
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if Self.showsThumbnail(imageURL: article.imageURL) {
                Spacer(minLength: 8)
                thumbnailView
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var subtitleView: some View {
        switch (article.feedTitle, article.publishedAt) {
        case let (feedTitle?, publishedAt?):
            HStack(spacing: 4) {
                Text(feedTitle)
                Text("·")
                Text(publishedAt, style: .relative)
            }
        case let (feedTitle?, nil):
            Text(feedTitle)
        case let (nil, publishedAt?):
            Text(publishedAt, style: .relative)
        case (nil, nil):
            EmptyView()
        }
    }

    @ViewBuilder
    private var faviconView: some View {
        if let faviconURL = article.faviconURL, let url = URL(string: faviconURL) {
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } placeholder: {
                fallbackFaviconIcon
            }
        } else {
            fallbackFaviconIcon
        }
    }

    private var fallbackFaviconIcon: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let imageURLString = article.imageURL, let url = URL(string: imageURLString) {
            CachedRemoteImageView(
                url: url,
                targetPixelSize: CGSize(width: 80, height: 80)
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Color.clear
            }
        }
    }

    /// Reine Entscheidung "zeige Thumbnail?" — testbar ohne View-Rendering,
    /// analog `MenubarStatusItemController.symbolName(forUnreadCount:)`.
    /// `nonisolated`, da rein wertbasiert.
    nonisolated static func showsThumbnail(imageURL: String?) -> Bool {
        guard let imageURL, URL(string: imageURL) != nil else { return false }
        return true
    }
}
