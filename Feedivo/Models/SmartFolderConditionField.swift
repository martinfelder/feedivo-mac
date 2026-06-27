import SwiftUI

enum SmartFolderConditionField: String, CaseIterable, Identifiable {
    case tag
    case feed
    case feedFolder
    case date
    case status
    case title
    case text
    case author

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tag:
            L10n.smartFolderFieldTag
        case .feed:
            L10n.smartFolderFieldFeed
        case .feedFolder:
            L10n.smartFolderFieldFeedFolder
        case .date:
            L10n.smartFolderFieldDate
        case .status:
            L10n.smartFolderFieldStatus
        case .title:
            L10n.smartFolderFieldTitle
        case .text:
            L10n.smartFolderFieldText
        case .author:
            L10n.smartFolderFieldAuthor
        }
    }
}
