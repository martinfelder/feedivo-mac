import CoreText
import Foundation

enum ReaderFontRegistry {
    static let fontResourceSubdirectory = "Fonts"

    static let fontResourceNames: [String] = ReaderFontPreset.allCases.compactMap(\.bundledFontFileName)

    private static var didRegisterFonts = false

    static func fontURL(for resourceName: String, in bundle: Bundle = .main) -> URL? {
        if let url = bundle.url(
            forResource: resourceName,
            withExtension: nil,
            subdirectory: fontResourceSubdirectory
        ) {
            return url
        }

        return bundle.url(forResource: resourceName, withExtension: nil)
    }

    static func registerBundledFonts(in bundle: Bundle = .main) {
        guard !didRegisterFonts else { return }

        for resourceName in fontResourceNames {
            guard let url = fontURL(for: resourceName, in: bundle) else {
                continue
            }

            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }

        didRegisterFonts = true
    }
}
