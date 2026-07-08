enum SmartFolderConditionOperator: String, CaseIterable, Identifiable {
    case contains
    case notContains
    case `is`
    case isNot
    case startsWith
    case endsWith
    case olderThanDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contains:
            L10n.smartFolderOperatorContains
        case .notContains:
            L10n.smartFolderOperatorNotContains
        case .is:
            L10n.smartFolderOperatorIs
        case .isNot:
            L10n.smartFolderOperatorIsNot
        case .startsWith:
            L10n.smartFolderOperatorStartsWith
        case .endsWith:
            L10n.smartFolderOperatorEndsWith
        case .olderThanDays:
            L10n.smartFolderOperatorOlderThanDays
        }
    }
}
