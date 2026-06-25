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
            "Tag"
        case .feed:
            "Feed"
        case .feedFolder:
            "Feed-Ordner"
        case .date:
            "Datum"
        case .status:
            "Status"
        case .title:
            "Titel"
        case .text:
            "Text"
        case .author:
            "Autor"
        }
    }
}
