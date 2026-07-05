import SwiftUI
import WebKit
import OSLog

struct WebContentView: NSViewRepresentable {
    let url: URL
    let inAppProfile: ArticleInAppWebProfile
    let onLoadFailure: () -> Void

    init(
        url: URL,
        inAppProfile: ArticleInAppWebProfile = .defaultProfile,
        onLoadFailure: @escaping () -> Void = {}
    ) {
        self.url = url
        self.inAppProfile = inAppProfile
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
        context.coordinator.update(url: url, profile: inAppProfile, in: webView)
    }

    func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?

        private var pendingURL: URL?
        private var pendingProfile: ArticleInAppWebProfile?
        private var loadedProfile: ArticleInAppWebProfile = .defaultProfile
        private var loadedURL: URL?
        private var isContentBlockerReady = false
        private var loadWatchTask: Task<Void, Never>?
        private var hasLoadSucceeded = false
        private var didNotifyLoadFailure = false
        private let onLoadFailure: () -> Void

        init(onLoadFailure: @escaping () -> Void) {
            self.onLoadFailure = onLoadFailure
            super.init()
        }

        func update(url: URL, profile: ArticleInAppWebProfile, in webView: WKWebView) {
            self.webView = webView
            pendingURL = url
            pendingProfile = profile
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
                  let pendingProfile,
                  let webView
            else {
                return
            }

            let hasProfileChange = loadedProfile != pendingProfile
            if hasProfileChange {
                webView.customUserAgent = pendingProfile.customUserAgent
                loadedProfile = pendingProfile
            }

            guard loadedURL != pendingURL || hasProfileChange else {
                return
            }

            loadedURL = pendingURL
            hasLoadSucceeded = false
            didNotifyLoadFailure = false
            startLoadWatchdog(for: pendingURL)
            webView.load(URLRequest(url: pendingURL))
        }

        private func startLoadWatchdog(for url: URL) {
            loadWatchTask?.cancel()

            let urlInWatch = url
            loadWatchTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 18_000_000_000)

                await MainActor.run {
                    guard
                        let self,
                        self.loadedURL == urlInWatch,
                        !self.hasLoadSucceeded,
                        !self.didNotifyLoadFailure
                    else {
                        return
                    }

                    self.notifyFailure(nil)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            hasLoadSucceeded = true
            loadWatchTask?.cancel()
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
            loadWatchTask?.cancel()
            loadedURL = nil
            if didNotifyLoadFailure {
                return
            }

            didNotifyLoadFailure = true

            onLoadFailure()
        }
    }
}

enum ArticleWebContentBlocker {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ch.martin.Feedivo",
        category: "WebContentBlocker"
    )

    @MainActor
    static func install(into userContentController: WKUserContentController, completion: @escaping @MainActor () -> Void) {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: ArticleResourceURLPolicy.webContentBlockerIdentifier,
            encodedContentRuleList: ArticleResourceURLPolicy.webContentBlockerRulesJSON
        ) { ruleList, error in
            if let error {
                logger.error("Content-Rule-Kompilierung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.info("Content-Rule-Kompilierung erfolgreich abgeschlossen.")
            }

            Task { @MainActor in
                if let ruleList {
                    userContentController.add(ruleList)
                }

                completion()
            }
        }
    }
}
