import SwiftUI

enum ReaderFontPreset: String, CaseIterable, Identifiable {
    case system
    case geist
    case inter
    case manrope
    case dmSans
    case literata
    case newsreader
    case ibmPlexSans
    case atkinsonHyperlegible
    case sourceSerif4
    case libreFranklin
    case lora
    case merriweather
    case notoSans
    case notoSerif
    case robotoSlab
    case crimsonPro
    case fraunces
    case serif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .geist:
            return "Geist"
        case .inter:
            return "Inter"
        case .manrope:
            return "Manrope"
        case .dmSans:
            return "DM Sans"
        case .literata:
            return "Literata"
        case .newsreader:
            return "Newsreader"
        case .ibmPlexSans:
            return "IBM Plex Sans"
        case .atkinsonHyperlegible:
            return "Atkinson Hyperlegible"
        case .sourceSerif4:
            return "Source Serif 4"
        case .libreFranklin:
            return "Libre Franklin"
        case .lora:
            return "Lora"
        case .merriweather:
            return "Merriweather"
        case .notoSans:
            return "Noto Sans"
        case .notoSerif:
            return "Noto Serif"
        case .robotoSlab:
            return "Roboto Slab"
        case .crimsonPro:
            return "Crimson Pro"
        case .fraunces:
            return "Fraunces"
        case .serif:
            return "Serif"
        }
    }

    var fontNames: [String] {
        switch self {
        case .system, .serif:
            return []
        case .geist:
            return ["Geist-Regular", "Geist"]
        case .inter:
            return ["Inter-Regular", "Inter"]
        case .manrope:
            return ["Manrope-Regular", "Manrope"]
        case .dmSans:
            return ["DMSans-Regular", "DM Sans"]
        case .literata:
            return ["Literata-Regular", "Literata"]
        case .newsreader:
            return ["Newsreader-Regular", "Newsreader"]
        case .ibmPlexSans:
            return ["IBMPlexSans-Regular", "IBM Plex Sans"]
        case .atkinsonHyperlegible:
            return ["AtkinsonHyperlegible-Regular", "Atkinson Hyperlegible"]
        case .sourceSerif4:
            return ["SourceSerif4-Regular", "Source Serif 4"]
        case .libreFranklin:
            return ["LibreFranklin-Regular", "Libre Franklin"]
        case .lora:
            return ["Lora-Regular", "Lora"]
        case .merriweather:
            return ["Merriweather-Regular", "Merriweather"]
        case .notoSans:
            return ["NotoSans-Regular", "Noto Sans"]
        case .notoSerif:
            return ["NotoSerif-Regular", "Noto Serif"]
        case .robotoSlab:
            return ["RobotoSlab-Regular", "Roboto Slab"]
        case .crimsonPro:
            return ["CrimsonPro-Regular", "Crimson Pro"]
        case .fraunces:
            return ["Fraunces-Regular", "Fraunces"]
        }
    }

    func font(size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        switch self {
        case .system:
            return .system(size: size)
        case .serif:
            return .system(size: size, design: .serif)
        default:
            return .custom(fontNames.first ?? title, size: size, relativeTo: textStyle)
        }
    }

    static func resolved(from rawValue: String) -> ReaderFontPreset {
        ReaderFontPreset(rawValue: rawValue) ?? .system
    }
}
