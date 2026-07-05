import Foundation

enum ArticleInAppWebProfile: String, CaseIterable, Identifiable {
    case webKitDefault
    case safari
    case chrome
    case edge
    case firefox

    static let storageKey = "articleInAppWebProfile"
    static let defaultProfile: ArticleInAppWebProfile = .webKitDefault

    var id: String { rawValue }

    var title: String {
        switch self {
        case .webKitDefault:
            "WebKit-Standard"
        case .safari:
            "Safari-kompatibel"
        case .chrome:
            "Chrome-kompatibel"
        case .edge:
            "Edge-kompatibel"
        case .firefox:
            "Firefox-kompatibel"
        }
    }

    var customUserAgent: String? {
        switch self {
        case .webKitDefault:
            nil
        case .safari:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        case .chrome:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        case .edge:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0"
        case .firefox:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0; rv:126.0) Gecko/20100101 Firefox/126.0"
        }
    }

    static func resolved(from rawValue: String) -> ArticleInAppWebProfile {
        ArticleInAppWebProfile(rawValue: rawValue) ?? defaultProfile
    }
}
