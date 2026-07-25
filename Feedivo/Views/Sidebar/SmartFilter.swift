import Foundation
import SwiftUI

enum SmartFilterIconColor: Hashable {
    case blue
    case teal
    case yellow
    case green
    case gray

    var color: Color {
        switch self {
        case .blue:
            return .blue
        case .teal:
            return .teal
        case .yellow:
            return .yellow
        case .green:
            return .green
        case .gray:
            return .gray
        }
    }
}

enum SmartFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case allArticles
    case unread
    case starred
    case today
    case hidden

    var id: String {
        rawValue
    }

    var iconColor: SmartFilterIconColor {
        switch self {
        case .allArticles:
            return .blue
        case .unread:
            return .teal
        case .starred:
            return .yellow
        case .today:
            return .green
        case .hidden:
            return .gray
        }
    }
}
