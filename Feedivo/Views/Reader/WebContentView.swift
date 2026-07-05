import SwiftUI
import WebKit

struct WebContentView: NSViewRepresentable {
    let url: URL
    let onLoadFailure: () -> Void

    init(url: URL, onLoadFailure: @escaping () -> Void = {}) {
        self.url = url
        self.onLoadFailure = onLoadFailure
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoadFailure: onLoadFailure)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = WKUserContentController()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        ArticleWebContentBlocker.install(into: configuration.userContentController) {
            context.coordinator.contentBlockerDidFinish()
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(url: url, in: webView)
    }

    func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?

        private var pendingURL: URL?
        private var loadedURL: URL?
        private var isContentBlockerReady = false
        private var didNotifyLoadFailure = false
        private let onLoadFailure: () -> Void

        init(onLoadFailure: @escaping () -> Void) {
            self.onLoadFailure = onLoadFailure
            super.init()
        }

        func update(url: URL, in webView: WKWebView) {
            self.webView = webView
            pendingURL = url
            didNotifyLoadFailure = false
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

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let _ = error
            notifyFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let _ = error
            notifyFailure(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            notifyFailure(nil)
        }

        private func notifyFailure(_ error: Error?) {
            if didNotifyLoadFailure {
                return
            }

            didNotifyLoadFailure = true

            onLoadFailure()
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
