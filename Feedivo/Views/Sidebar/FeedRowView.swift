import SwiftUI

struct FeedRowView: View {
    let feed: Feed

    var body: some View {
        HStack(spacing: 8) {
            faviconView
                .frame(width: 16, height: 16)

            Text(feed.title)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var faviconView: some View {
        if let faviconURL = feed.faviconURL,
           let url = URL(string: faviconURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                case .empty:
                    fallbackIcon
                case .failure:
                    fallbackIcon
                @unknown default:
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
    }
}
