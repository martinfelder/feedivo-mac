import Foundation

extension Date {
    var feedivoRelativeDisplay: String {
        if Calendar.current.isDateInToday(self) {
            return Self.relativeFormatter.localizedString(for: self, relativeTo: .now)
        }

        return Self.shortDateFormatter.string(from: self)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = appLocale
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.locale = appLocale
        return formatter
    }()

    /// App-Sprache aus den Einstellungen (gleicher Key wie @AppStorage in
    /// FeedivoApp). Die Formatter sind `static let` — sie werden einmal beim
    /// ersten Zugriff aufgebaut und beachten die damals gewählte Sprache.
    /// Ein Sprachwechsel greift also erst nach App-Neustart (analog zu den
    /// `String(localized:)`-Accessoren in L10n).
    private static var appLocale: Locale {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
        return AppLanguage.resolved(from: raw).locale
    }
}
