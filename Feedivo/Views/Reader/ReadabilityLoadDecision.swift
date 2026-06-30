import Foundation

enum ReadabilityLoadDecision {
    static func shouldStartExtraction(
        mode: ReaderDisplayMode,
        originalURL: URL?,
        requestedURL: URL?,
        loadedURL: URL?,
        isInProgress: Bool
    ) -> Bool {
        guard mode == .readability, let originalURL else {
            return false
        }

        if isInProgress || requestedURL == originalURL || loadedURL == originalURL {
            return false
        }

        return true
    }
}
