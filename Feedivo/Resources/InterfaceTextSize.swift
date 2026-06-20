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

    var scaleFactor: Double {
        switch self {
        case .small:
            0.92
        case .standard:
            1.0
        case .large:
            1.14
        case .extraLarge:
            1.28
        }
    }

    func scaled(_ value: Double) -> Double {
        (value * scaleFactor).rounded(.toNearestOrAwayFromZero)
    }

    func scaled(_ value: CGFloat) -> CGFloat {
        CGFloat(scaled(Double(value)))
    }

    func font(size: Double, weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size), weight: weight)
    }

    static func resolved(from rawValue: String) -> InterfaceTextSize {
        InterfaceTextSize(rawValue: rawValue) ?? defaultSize
    }
}

private struct InterfaceTextSizeEnvironmentKey: EnvironmentKey {
    static let defaultValue = InterfaceTextSize.defaultSize
}

extension EnvironmentValues {
    var interfaceTextSize: InterfaceTextSize {
        get { self[InterfaceTextSizeEnvironmentKey.self] }
        set { self[InterfaceTextSizeEnvironmentKey.self] = newValue }
    }
}
