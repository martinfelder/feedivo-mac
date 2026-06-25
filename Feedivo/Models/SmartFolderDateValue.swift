enum SmartFolderDateValue: String, CaseIterable, Identifiable {
    case today
    case thisWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            "heute"
        case .thisWeek:
            "diese Woche"
        }
    }
}
