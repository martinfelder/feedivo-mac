import AppKit
import Foundation

// Zentraler Launcher für den Artikel-Original-Link.
// Damit können wir dem Nutzer erlauben, einen installierten Browser auszuwählen,
// ohne in der Produktansicht hartkodiert auf Safari/Standardbrowser festgelegt zu sein.
enum ArticleOriginalBrowserTarget: String, CaseIterable, Identifiable {
    case systemDefault
    case safari
    case chrome
    case brave
    case edge
    case firefox

    static let storageKey = "articleOriginalBrowserTarget"
    static let defaultTarget: ArticleOriginalBrowserTarget = .systemDefault

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemDefault:
            "Standardbrowser"
        case .safari:
            "Safari"
        case .chrome:
            "Google Chrome"
        case .brave:
            "Brave"
        case .edge:
            "Microsoft Edge"
        case .firefox:
            "Firefox"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .systemDefault:
            nil
        case .safari:
            "com.apple.Safari"
        case .chrome:
            "com.google.Chrome"
        case .brave:
            "com.brave.Browser"
        case .edge:
            "com.microsoft.edgemac"
        case .firefox:
            "org.mozilla.firefox"
        }
    }

    static func resolved(from rawValue: String) -> ArticleOriginalBrowserTarget {
        ArticleOriginalBrowserTarget(rawValue: rawValue) ?? defaultTarget
    }

    var applicationURL: URL? {
        guard let bundleIdentifier else {
            return nil
        }

        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    var isAvailable: Bool {
        switch self {
        case .systemDefault:
            true
        default:
            applicationURL != nil
        }
    }

    static func availableTargets() -> [ArticleOriginalBrowserTarget] {
        var available: [ArticleOriginalBrowserTarget] = [.systemDefault]

        for target in Self.allCases where target != .systemDefault {
            if target.isAvailable {
                available.append(target)
            }
        }

        return available
    }
}

enum ArticleOriginalBrowserLauncher {
    static func open(_ url: URL) {
        open(url, using: .resolved(from: UserDefaults.standard.string(forKey: ArticleOriginalBrowserTarget.storageKey) ?? ""))
    }

    static func open(_ url: URL, using target: ArticleOriginalBrowserTarget) {
        if target == .systemDefault {
            NSWorkspace.shared.open(url)
            return
        }

        guard let applicationURL = target.applicationURL else {
            NSWorkspace.shared.open(url)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: configuration
        )
    }
}
