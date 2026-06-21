import SwiftUI

struct FeedRowView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let feed: Feed
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 8) {
            faviconView
                .frame(
                    width: interfaceTextSize.scaled(16),
                    height: interfaceTextSize.scaled(16)
                )

            Text(feed.title)
                .font(interfaceTextSize.font(size: 13, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let badgeText = SidebarUnreadCount.badgeText(for: unreadCount) {
                Text(badgeText)
                    .font(interfaceTextSize.font(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(SidebarStyle.activeSelection, in: Capsule())
            }
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
            .font(interfaceTextSize.font(size: 13))
            .foregroundStyle(.secondary)
    }
}
