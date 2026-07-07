import Foundation

enum FeedPropertiesFormatter {
    static func linkURL(_ urlString: String?) -> URL? {
        guard let urlString else {
            return nil
        }

        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let components = URLComponents(string: trimmedURL),
            let scheme = components.scheme?.lowercased(),
            (scheme == "http" || scheme == "https"),
            components.host != nil,
            let url = components.url
        else {
            return nil
        }

        return url
    }

    static func copyableXMLAddress(_ urlString: String) -> String? {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedURL.isEmpty ? nil : trimmedURL
    }

    static func nextRefreshDate(lastRefreshed: Date?, intervalMinutes: Int) -> Date? {
        guard let lastRefreshed else {
            return nil
        }

        return lastRefreshed.addingTimeInterval(TimeInterval(intervalMinutes * 60))
    }
}
