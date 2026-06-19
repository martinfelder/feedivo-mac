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
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}
