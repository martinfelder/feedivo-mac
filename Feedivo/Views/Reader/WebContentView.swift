import SwiftUI
import WebKit
import OSLog

/// Bündelt den Vor-/Zurück-Zustand der Original-Ansicht für die Reader-
/// Toolbar. Bleibt über Artikelwechsel hinweg als `@State` in
/// `SQLiteReaderView` bestehen — passend zur WKWebView, die aus
/// Performance-Gründen ebenfalls über Artikelwechsel hinweg weiterlebt
/// (siehe Commit eca556f93).
@Observable
final class WebNavigationController {
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    fileprivate weak var webView: WKWebView?

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    fileprivate func updateState(canGoBack: Bool, canGoForward: Bool) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }
}

struct WebContentView: NSViewRepresentable {
    let url: URL
    let inAppProfile: ArticleInAppWebProfile
    let navigationController: WebNavigationController
    let onLoadFailure: () -> Void

    init(
        url: URL,
        inAppProfile: ArticleInAppWebProfile = .defaultProfile,
        navigationController: WebNavigationController,
        onLoadFailure: @escaping () -> Void = {}
    ) {
        self.url = url
        self.inAppProfile = inAppProfile
        self.navigationController = navigationController
        self.onLoadFailure = onLoadFailure
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(navigationController: navigationController, onLoadFailure: onLoadFailure)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = WKUserContentController()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        navigationController.webView = webView
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

        private let navigationController: WebNavigationController
        private var pendingURL: URL?
        private var pendingProfile: ArticleInAppWebProfile?
        private var loadedProfile: ArticleInAppWebProfile = .defaultProfile
        private var loadedURL: URL?
        private var isContentBlockerReady = false
        private var loadWatchTask: Task<Void, Never>?
        private var hasLoadSucceeded = false
        private var didNotifyLoadFailure = false
        private let onLoadFailure: () -> Void

        // Wird direkt vor jedem Top-Level-`load()` gesetzt (neuer Artikel
        // oder Profilwechsel) und in `didFinish` konsumiert, um dort den
        // neuen Artikel-Grenzpunkt zu setzen. Unterscheidet einen
        // Top-Level-Load von einer In-Page-Navigation (Linkklick), die
        // `didFinish` ebenfalls auslöst, aber die Grenze nicht verschieben
        // darf.
        private var isAwaitingTopLevelLoadCompletion = false
        private var articleLoadBoundaryItem: WKBackForwardListItem?

        init(navigationController: WebNavigationController, onLoadFailure: @escaping () -> Void) {
            self.navigationController = navigationController
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
            isAwaitingTopLevelLoadCompletion = true
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

            if isAwaitingTopLevelLoadCompletion {
                isAwaitingTopLevelLoadCompletion = false
                articleLoadBoundaryItem = webView.backForwardList.currentItem
            }

            let isAtBoundary = webView.backForwardList.currentItem === articleLoadBoundaryItem
            navigationController.updateState(
                canGoBack: WebNavigationBoundary.canGoBack(
                    webViewCanGoBack: webView.canGoBack,
                    isAtBoundary: isAtBoundary
                ),
                canGoForward: webView.canGoForward
            )
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
            isAwaitingTopLevelLoadCompletion = false
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
