import Foundation

protocol OfflineArticleContentFetching: Sendable {
    func content(from url: URL) async throws -> String
}

struct URLSessionOfflineArticleContentFetcher: OfflineArticleContentFetching, Sendable {
    func content(from url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw OfflineDownloadError.unreachable(statusCode: httpResponse.statusCode)
        }

        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}

enum OfflineDownloadError: LocalizedError {
    case missingOriginalURL
    case emptyDownloadedContent
    case unreachable(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingOriginalURL:
            return String(localized: "offline.error.missingOriginalURL")
        case .emptyDownloadedContent:
            return String(localized: "offline.error.emptyDownloadedContent")
        case .unreachable(let statusCode):
            return String.localizedStringWithFormat(
                String(localized: "offline.error.unreachable"),
                statusCode
            )
        }
    }
}

@MainActor
final class OfflineDownloadService {
    private let fetcher: OfflineArticleContentFetching

    init() {
        self.fetcher = URLSessionOfflineArticleContentFetcher()
    }

    init(fetcher: OfflineArticleContentFetching) {
        self.fetcher = fetcher
    }

    func saveForOffline(_ article: Article) async {
        article.offlineRequestedAt = Date()
        article.offlineErrorMessage = nil

        if let feedContent = normalizedText(article.content) {
            markSaved(article, state: .feedContent, content: feedContent)
            return
        }

        guard let url = originalURL(for: article) else {
            markFailed(article, error: OfflineDownloadError.missingOriginalURL)
            return
        }

        do {
            let downloadedContent = try await fetcher.content(from: url)
            guard let normalizedContent = normalizedText(downloadedContent) else {
                markFailed(article, error: OfflineDownloadError.emptyDownloadedContent)
                return
            }

            markSaved(article, state: .fullText, content: normalizedContent)
        } catch {
            markFailed(article, error: error)
        }
    }

    func removeOfflineContent(from article: Article) {
        article.offlineState = .none
        article.offlineContent = nil
        article.offlineRequestedAt = nil
        article.offlineSavedAt = nil
        article.offlineErrorMessage = nil
    }

    private func markSaved(_ article: Article, state: ArticleOfflineState, content: String) {
        article.offlineState = state
        article.offlineContent = content
        article.offlineSavedAt = Date()
        article.offlineErrorMessage = nil
    }

    private func markFailed(_ article: Article, error: Error) {
        article.offlineState = .failed
        article.offlineContent = nil
        article.offlineSavedAt = nil
        article.offlineErrorMessage = error.localizedDescription
    }

    private func originalURL(for article: Article) -> URL? {
        guard
            let link = article.link,
            let url = URL(string: link),
            url.scheme != nil
        else {
            return nil
        }

        return url
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
