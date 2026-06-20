import SwiftUI

enum InterfaceTextSize: String, CaseIterable, Identifiable {
    static let storageKey = "interfaceTextSize"
    static let defaultSize: InterfaceTextSize = .standard

    case small
    case standard
    case large
    case extraLarge

    var id: String {
        rawValue
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .small:
            L10n.settingsInterfaceTextSizeSmall
        case .standard:
            L10n.settingsInterfaceTextSizeStandard
        case .large:
            L10n.settingsInterfaceTextSizeLarge
        case .extraLarge:
            L10n.settingsInterfaceTextSizeExtraLarge
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small:
            .medium
        case .standard:
            .large
        case .large:
            .xLarge
        case .extraLarge:
            .xxLarge
        }
    }

    static func resolved(from rawValue: String) -> InterfaceTextSize {
        InterfaceTextSize(rawValue: rawValue) ?? defaultSize
    }
}
