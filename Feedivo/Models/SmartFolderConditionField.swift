import SwiftUI

enum SmartFolderConditionField: String, CaseIterable, Identifiable {
    case title
    case text
    case author
    case feed
    case tag
    case date
    case feedFolder
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title:
            L10n.smartFolderFieldTitle
        case .text:
            L10n.smartFolderFieldText
        case .author:
            L10n.smartFolderFieldAuthor
        case .feed:
            L10n.smartFolderFieldFeed
        case .tag:
            L10n.smartFolderFieldTag
        case .date:
            L10n.smartFolderFieldDate
        case .feedFolder:
            L10n.smartFolderFieldFeedFolder
        case .status:
            L10n.smartFolderFieldStatus
        }
    }
}
