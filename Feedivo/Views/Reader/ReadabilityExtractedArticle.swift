import Foundation

struct ReadabilityExtractedArticle: Decodable, Equatable {
    let title: String?
    let byline: String?
    let dir: String?
    let content: String?
    let textContent: String?
    let length: Int?
    let excerpt: String?
    let siteName: String?

    var normalizedContentHTML: String? {
        normalizedText(content)
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
