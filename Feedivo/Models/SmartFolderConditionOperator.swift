enum SmartFolderConditionOperator: String, CaseIterable, Identifiable {
    case `is`
    case isNot
    case contains
    case olderThanDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .is:
            L10n.smartFolderOperatorIs
        case .isNot:
            L10n.smartFolderOperatorIsNot
        case .contains:
            L10n.smartFolderOperatorContains
        case .olderThanDays:
            L10n.smartFolderOperatorOlderThanDays
        }
    }
}
