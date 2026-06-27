enum SmartFolderDateValue: String, CaseIterable, Identifiable {
    case today
    case thisWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            L10n.smartFolderDateToday
        case .thisWeek:
            L10n.smartFolderDateThisWeek
        }
    }
}
