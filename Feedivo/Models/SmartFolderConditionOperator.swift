enum SmartFolderConditionOperator: String, CaseIterable, Identifiable {
    case `is`
    case isNot
    case contains
    case olderThanDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .is:
            "ist"
        case .isNot:
            "ist nicht"
        case .contains:
            "enthaelt"
        case .olderThanDays:
            "aelter als Tage"
        }
    }
}
