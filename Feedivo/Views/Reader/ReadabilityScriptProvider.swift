import Foundation

enum ReadabilityScriptProvider {
    static func bundledReadabilitySource(bundle: Bundle = .main) throws -> String {
        guard let url = bundle.url(forResource: "Readability", withExtension: "js") else {
            throw ReadabilityExtractionError.missingReadabilityResource
        }

        return try String(contentsOf: url, encoding: .utf8)
    }

    static func extractionScript(readabilitySource: String) -> String {
        """
        (() => {
        \(readabilitySource)
        const article = new Readability(document.cloneNode(true)).parse();
        if (!article || !article.content) {
            return null;
        }
        return JSON.stringify(article);
        })();
        """
    }
}

enum ReadabilityExtractionError: LocalizedError {
    case missingReadabilityResource
    case emptyResult
    case invalidResult

    var errorDescription: String? {
        switch self {
        case .missingReadabilityResource:
            String(localized: "reader.readability.error.missingResource")
        case .emptyResult:
            String(localized: "reader.readability.error.emptyResult")
        case .invalidResult:
            String(localized: "reader.readability.error.invalidResult")
        }
    }
}
