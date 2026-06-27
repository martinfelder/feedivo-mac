enum SmartFolderStatusValue: String, CaseIterable, Identifiable {
    case unread
    case read
    case starred
    case archived
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unread:
            L10n.smartFolderStatusUnread
        case .read:
            L10n.smartFolderStatusRead
        case .starred:
            L10n.smartFolderStatusStarred
        case .archived:
            L10n.smartFolderStatusArchived
        case .hidden:
            L10n.smartFolderStatusHidden
        }
    }
}
