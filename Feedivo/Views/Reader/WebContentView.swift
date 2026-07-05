import SwiftUI
import WebKit

struct WebContentView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = WKUserContentController()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        ArticleWebContentBlocker.install(into: configuration.userContentController) {
            context.coordinator.contentBlockerDidFinish()
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(url: url, in: webView)
    }

    @MainActor
    final class Coordinator {
        weak var webView: WKWebView?

        private var pendingURL: URL?
        private var loadedURL: URL?
        private var isContentBlockerReady = false

        func update(url: URL, in webView: WKWebView) {
            self.webView = webView
            pendingURL = url
            loadIfReady()
        }

        func contentBlockerDidFinish() {
            isContentBlockerReady = true
            loadIfReady()
        }

        private func loadIfReady() {
            guard isContentBlockerReady,
                  let pendingURL,
                  loadedURL != pendingURL,
                  let webView
            else {
                return
            }

            loadedURL = pendingURL
            webView.load(URLRequest(url: pendingURL))
        }
    }
}

enum ArticleWebContentBlocker {
    @MainActor
    static func install(into userContentController: WKUserContentController, completion: @escaping @MainActor () -> Void) {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: ArticleResourceURLPolicy.webContentBlockerIdentifier,
            encodedContentRuleList: ArticleResourceURLPolicy.webContentBlockerRulesJSON
        ) { ruleList, _ in
            Task { @MainActor in
                if let ruleList {
                    userContentController.add(ruleList)
                }

                completion()
            }
        }
    }
}
