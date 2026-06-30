import SwiftUI

enum ReaderDisplayMode: String, CaseIterable, Identifiable {
    case native
    case readability
    case web

    static let storageKey = "readerDisplayMode"
    static let defaultMode = ReaderDisplayMode.native

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .native:
            return L10n.readerDisplayModeNative
        case .readability:
            return L10n.readerDisplayModeReadability
        case .web:
            return L10n.readerDisplayModeWeb
        }
    }

    static func resolved(from rawValue: String) -> ReaderDisplayMode {
        ReaderDisplayMode(rawValue: rawValue) ?? defaultMode
    }
}
