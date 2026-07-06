import SwiftUI

struct FeedRowView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    enum DisplayStyle {
        case regular
        case folderChild
    }

    let snapshot: FeedSidebarSnapshot
    var displayStyle: DisplayStyle = .regular

    init(
        snapshot: FeedSidebarSnapshot,
        displayStyle: DisplayStyle = .regular
    ) {
        self.snapshot = snapshot
        self.displayStyle = displayStyle
    }

    // Die Zeile rendert ausschließlich aus dem SQLite-Snapshot. SwiftData-Feed
    // wird nicht mehr gehalten; ein Als-gelesen-markieren invalidiert nur die
    // Snapshot-Quelle (SQLiteSidebarState) und wertet die Zeile neu aus.
    private var unreadCount: Int {
        snapshot.unreadCount
    }

    private var displayTitle: String {
        snapshot.title
    }

    private var displayFaviconURL: String? {
        snapshot.faviconURL
    }

    var body: some View {
        HStack(spacing: displayStyle.horizontalSpacing) {
            faviconView
                .frame(
                    width: interfaceTextSize.scaled(displayStyle.iconSize),
                    height: interfaceTextSize.scaled(displayStyle.iconSize)
                )

            Text(displayTitle)
                .font(interfaceTextSize.font(
                    size: displayStyle.titleSize,
                    weight: displayStyle.titleWeight
                ))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let badgeText = SidebarUnreadCount.badgeText(for: unreadCount) {
                HStack(spacing: 3) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8, weight: .semibold))
                    Text(badgeText)
                        .font(interfaceTextSize.font(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(SidebarStyle.activeSelection, in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var faviconView: some View {
        if let faviconURL = displayFaviconURL,
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
