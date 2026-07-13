import SwiftUI

struct FeedRowView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @FocusState private var isNameFieldFocused: Bool

    @AppStorage(SidebarFeedVisibilitySettings.showsUnreadCountKey)
    private var showsUnreadCount = SidebarFeedVisibilitySettings.defaultShowsUnreadCount

    @AppStorage(SidebarFeedVisibilitySettings.showsFaviconsKey)
    private var showsFavicons = SidebarFeedVisibilitySettings.defaultShowsFavicons

    enum DisplayStyle {
        case regular
        case folderChild
    }

    let snapshot: FeedSidebarSnapshot
    var displayStyle: DisplayStyle = .regular
    let isSelected: Bool
    let select: () -> Void
    let renameFeed: (String) throws -> Void

    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var renameErrorMessage: String?

    init(
        snapshot: FeedSidebarSnapshot,
        displayStyle: DisplayStyle = .regular,
        isSelected: Bool,
        select: @escaping () -> Void,
        renameFeed: @escaping (String) throws -> Void
    ) {
        self.snapshot = snapshot
        self.displayStyle = displayStyle
        self.isSelected = isSelected
        self.select = select
        self.renameFeed = renameFeed
    }

    // Die Zeile rendert ausschließlich aus dem SQLite-Snapshot. Ein
    // Als-gelesen-markieren invalidiert nur die Snapshot-Quelle
    // (SQLiteSidebarState) und wertet die Zeile neu aus.
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
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: displayStyle.horizontalSpacing) {
                faviconView
                    .frame(
                        width: interfaceTextSize.scaled(displayStyle.iconSize),
                        height: interfaceTextSize.scaled(displayStyle.iconSize)
                    )

                if snapshot.hasRecentError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(interfaceTextSize.font(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .help(L10n.feedErrorBadgeTooltip)
                        .accessibilityLabel(Text(L10n.feedErrorBadgeTooltip))
                }

                if isEditingName {
                    TextField(displayTitle, text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .font(interfaceTextSize.font(
                            size: displayStyle.titleSize,
                            weight: displayStyle.titleWeight
                        ))
                        .focused($isNameFieldFocused)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(renameErrorMessage != nil ? Color.red : Color.clear, lineWidth: 1)
                        }
                        .onSubmit {
                            commitOrShowError()
                        }
                        .onExitCommand {
                            cancelEditing()
                        }
                        .onChange(of: isNameFieldFocused) { wasFocused, isFocused in
                            // Fokusverlust (z. B. Klick woanders hin) verhält sich wie
                            // Enter. Die Guard-Bedingung verhindert ein doppeltes
                            // Auslösen, wenn commitOrShowError()/cancelEditing() den
                            // Bearbeitungsmodus bereits beendet haben, bevor der Fokus
                            // tatsächlich wechselt.
                            if wasFocused, !isFocused, isEditingName {
                                commitOrShowError()
                            }
                        }
                } else {
                    Text(displayTitle)
                        .font(interfaceTextSize.font(
                            size: displayStyle.titleSize,
                            weight: displayStyle.titleWeight
                        ))
                        .foregroundStyle(isSelected ? SidebarStyle.primaryText : SidebarStyle.primaryText.opacity(0.82))
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            beginEditing()
                        }
                        .onTapGesture(count: 1) {
                            select()
                        }
                }

                Spacer(minLength: 8)

                if showsUnreadCount, let badgeText = SidebarUnreadCount.badgeText(for: unreadCount) {
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
            .padding(.horizontal, 10)
            .frame(height: interfaceTextSize.scaled(displayStyle.rowHeight))
            .padding(.leading, displayStyle.leadingIndent)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? SidebarStyle.activeSelection : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? SidebarStyle.activeBorder : Color.clear, lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                // Fängt Klicks auf Favicon/Fehler-Icon/Badge/Leerraum ab, damit die
                // gesamte Zeile weiterhin wie zuvor klickbar bleibt. Während der
                // Bearbeitung (isEditingName) ist dieser Handler bewusst ein No-op,
                // damit ein Klick ins TextField (Fokussieren/Cursor positionieren)
                // nicht stattdessen die Auswahl auslöst.
                if !isEditingName {
                    select()
                }
            }

            if let renameErrorMessage {
                Text(renameErrorMessage)
                    .font(interfaceTextSize.font(size: 11))
                    .foregroundStyle(.red)
                    .padding(.leading, displayStyle.leadingIndent + 10)
            }
        }
    }

    private func beginEditing() {
        editedName = displayTitle
        renameErrorMessage = nil
        isEditingName = true
        isNameFieldFocused = true
    }

    private func cancelEditing() {
        editedName = displayTitle
        renameErrorMessage = nil
        isEditingName = false
    }

    private func commitOrShowError() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName != displayTitle else {
            isEditingName = false
            renameErrorMessage = nil
            return
        }

        do {
            try renameFeed(trimmedName)
            isEditingName = false
            renameErrorMessage = nil
        } catch {
            renameErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var faviconView: some View {
        if showsFavicons,
           let faviconURL = displayFaviconURL,
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

    var leadingIndent: CGFloat {
        switch self {
        case .regular:
            0
        case .folderChild:
            46
        }
    }

    var rowHeight: CGFloat {
        switch self {
        case .regular:
            30
        case .folderChild:
            28
        }
    }
}
