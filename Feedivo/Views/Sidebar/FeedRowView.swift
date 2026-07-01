import SwiftUI

struct FeedRowView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    enum DisplayStyle {
        case regular
        case folderChild
    }

    let feed: Feed
    var displayStyle: DisplayStyle = .regular

    // unreadCount wird bewusst hier im Body aus feed gelesen, nicht vom Parent
    // übergeben. Dadurch beobachtet nur diese Zeile feed.unreadCount — ein
    // Als-gelesen-markieren wertet nur die eine Feed-Zeile neu aus, nicht die
    // gesamte Sidebar (inkl. O(n)-Badge-Signatur über alle Artikel).
    private var unreadCount: Int {
        SidebarUnreadCount.unreadArticleCount(for: feed)
    }

    var body: some View {
        HStack(spacing: displayStyle.horizontalSpacing) {
            faviconView
                .frame(
                    width: interfaceTextSize.scaled(displayStyle.iconSize),
                    height: interfaceTextSize.scaled(displayStyle.iconSize)
                )

            Text(feed.title)
                .font(interfaceTextSize.font(
                    size: displayStyle.titleSize,
                    weight: displayStyle.titleWeight
                ))
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
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: displayStyle.iconCornerRadius))
            } placeholder: {
                fallbackIcon
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(interfaceTextSize.font(size: displayStyle.fallbackIconSize))
            .foregroundStyle(.secondary)
    }
}

private extension FeedRowView.DisplayStyle {
    var horizontalSpacing: CGFloat {
        switch self {
        case .regular:
            8
        case .folderChild:
            8
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .regular:
            16
        case .folderChild:
            16
        }
    }

    var fallbackIconSize: CGFloat {
        switch self {
        case .regular:
            13
        case .folderChild:
            13
        }
    }

    var iconCornerRadius: CGFloat {
        switch self {
        case .regular:
            3
        case .folderChild:
            3
        }
    }

    var titleSize: CGFloat {
        switch self {
        case .regular:
            12
        case .folderChild:
            12
        }
    }

    var titleWeight: Font.Weight {
        switch self {
        case .regular:
            .semibold
        case .folderChild:
            .medium
        }
    }
}
