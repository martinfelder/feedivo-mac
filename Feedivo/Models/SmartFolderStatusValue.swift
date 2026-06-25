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
            "ungelesen"
        case .read:
            "gelesen"
        case .starred:
            "mit Stern"
        case .archived:
            "archiviert"
        case .hidden:
            "ausgeblendet"
        }
    }
}
