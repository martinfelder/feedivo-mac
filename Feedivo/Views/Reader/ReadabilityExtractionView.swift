import SwiftUI
import WebKit

struct ReadabilityExtractionView: NSViewRepresentable {
    let url: URL
    let onCompletion: (Result<ReadabilityExtractedArticle, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onCompletion = onCompletion

        guard context.coordinator.loadedURL != url else {
            return
        }

        context.coordinator.loadedURL = url
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?
        var onCompletion: (Result<ReadabilityExtractedArticle, Error>) -> Void

        init(onCompletion: @escaping (Result<ReadabilityExtractedArticle, Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onCompletion(.failure(error))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onCompletion(.failure(error))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            do {
                let readabilitySource = try ReadabilityScriptProvider.bundledReadabilitySource()
                let script = ReadabilityScriptProvider.extractionScript(readabilitySource: readabilitySource)
                webView.evaluateJavaScript(script) { [weak self] result, error in
                    guard let self else {
                        return
                    }

                    if let error {
                        self.onCompletion(.failure(error))
                        return
                    }

                    do {
                        guard let jsonString = result as? String,
                              let data = jsonString.data(using: .utf8)
                        else {
                            throw ReadabilityExtractionError.emptyResult
                        }

                        let article = try JSONDecoder().decode(ReadabilityExtractedArticle.self, from: data)
                        guard article.normalizedContentHTML != nil else {
                            throw ReadabilityExtractionError.emptyResult
                        }

                        self.onCompletion(.success(article))
                    } catch {
                        self.onCompletion(.failure(error))
                    }
                }
            } catch {
                onCompletion(.failure(error))
            }
        }
    }
}
