import Foundation

protocol OfflineArticleContentFetching: Sendable {
    func content(from url: URL) async throws -> String
}

protocol OfflineArticleImageCaching: Sendable {
    func cacheImages(from urls: [URL]) async
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

struct OfflineArticleStorageSummary: Equatable {
    var articleCount: Int
    var sizeInBytes: Int64
}

extension ImageCacheService: OfflineArticleImageCaching {}
