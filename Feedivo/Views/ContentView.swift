import SwiftUI
import SwiftData
import Network
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(FirstRunWizardState.completionStorageKey) private var hasCompletedFirstRunWizard = false
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(sort: \Tag.name) private var tags: [Tag]

    // columnVisibility steuert ob die Sidebar sichtbar ist.
    // .all bedeutet: alle 3 Spalten beim Start anzeigen.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // sidebarSelection speichert ob ein Smart Filter oder ein Feed ausgewählt ist.
    @State private var sidebarSelection: SidebarSelection? = .smartFilter(.allArticles)

    // selectedArticle speichert welcher Artikel gerade in der Liste ausgewählt ist.
    @State private var selectedArticle: Article? = nil
    @State private var articleNavigationState = ArticleNavigationState.empty

    @State private var articleViewModel = ArticleViewModel()
    @State private var feedViewModel = FeedViewModel()
    @State private var isShowingAddFeedSheet = false
    @State private var feedPendingDeletion: Feed?
    @State private var isDeleteFeedConfirmationPresented = false
    @State private var isShowingOPMLImportReview = false
    @State private var isExportingOPML = false
    @State private var opmlExportDocument = OPMLDocument()
    @State private var opmlAlert: OPMLAlert?
    @State private var articleForRuleCreation: Article?
    @State private var isMetadataInspectorPresented = false
    @State private var isShowingFirstRunWizard = false
    @State private var isFirstRunWizardDismissedForSession = false
    @State private var networkMonitor = NetworkConnectionStatusMonitor()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {

            // SPALTE 1: Sidebar — Liste aller Feeds
            SidebarView(
                selection: $sidebarSelection,
                selectedArticle: selectedArticle,
                onRequestAddFeed: requestAddFeed,
                onRequestDeleteFeed: requestDeleteFeed,
                onRequestCreateRuleFromArticle: requestCreateRuleFromArticle
            )
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)

        } content: {

            // SPALTE 2: Artikel-Liste des ausgewählten Feeds oder Smart Filters
            if let smartFilter = selectedSmartFilter {
                ArticleListView(
                    smartFilter: smartFilter,
                    selectedArticle: $selectedArticle,
                    navigationState: $articleNavigationState,
                    onRequestCreateRuleFromArticle: requestCreateRuleFromArticle
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else if let feed = selectedFeed {
                ArticleListView(
                    feed: feed,
                    selectedArticle: $selectedArticle,
                    navigationState: $articleNavigationState,
                    onRequestCreateRuleFromArticle: requestCreateRuleFromArticle
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else if let tag = selectedTag {
                ArticleListView(
                    tag: tag,
                    selectedArticle: $selectedArticle,
                    navigationState: $articleNavigationState,
                    onRequestCreateRuleFromArticle: requestCreateRuleFromArticle
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else {
                // Platzhalter wenn kein Feed oder Smart Filter ausgewählt ist
                ContentUnavailableView(
                    L10n.contentNoFeedSelectedTitle,
                    systemImage: "newspaper",
                    description: Text(L10n.contentNoFeedSelectedDescription)
                )
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            }

        } detail: {

            // SPALTE 3: Reader — Inhalt des ausgewählten Artikels
            if let article = selectedArticle {
                ReaderView(
                    article: article,
                    isMetadataInspectorPresented: $isMetadataInspectorPresented,
                    canSelectPreviousArticle: articleNavigationState.previousArticle != nil,
                    canSelectNextArticle: articleNavigationState.nextArticle != nil,
                    selectPreviousArticle: selectPreviousArticle,
                    selectNextArticle: selectNextArticle
                )
            } else {
                ContentUnavailableView(
                    L10n.contentNoArticleSelectedTitle,
                    systemImage: "doc.text",
                    description: Text(L10n.contentNoArticleSelectedDescription)
                )
            }

        }
        .onChange(of: sidebarSelection) {
            selectedArticle = nil
            articleNavigationState = .empty
        }
        .onAppear {
            updateFirstRunWizardPresentation()
        }
        .onChange(of: feeds.count) {
            updateFirstRunWizardPresentation()
        }
        .onChange(of: hasCompletedFirstRunWizard) {
            updateFirstRunWizardPresentation()
        }
        .sheet(isPresented: $isShowingAddFeedSheet) {
            AddFeedSheet()
        }
        .sheet(isPresented: $isShowingOPMLImportReview) {
            OPMLImportReviewView(
                feeds: feeds,
                feedViewModel: feedViewModel
            )
        }
        .sheet(isPresented: $isShowingFirstRunWizard) {
            FirstRunWizardView(
                feeds: feeds,
                feedViewModel: feedViewModel,
                onSkip: skipFirstRunWizardForSession,
                onComplete: completeFirstRunWizard
            )
        }
        .sheet(item: $articleForRuleCreation) { article in
            RuleWizardView(sourceArticle: article)
        }
        .confirmationDialog(
            L10n.feedDeleteConfirmationTitle,
            isPresented: $isDeleteFeedConfirmationPresented,
            presenting: feedPendingDeletion
        ) { feed in
            Button(L10n.feedDeleteConfirmButton, role: .destructive) {
                deleteFeed(feed)
            }

            Button(L10n.commonCancel, role: .cancel) {
                feedPendingDeletion = nil
            }
        } message: { feed in
            Text(L10n.feedDeleteConfirmationMessage(feedTitle: feed.title))
        }
        .fileExporter(
            isPresented: $isExportingOPML,
            document: opmlExportDocument,
            contentType: .opml,
            defaultFilename: "Feedivo.opml"
        ) { _ in }
        .alert(item: $opmlAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.commonDone))
            )
        }
        .overlay(alignment: .bottom) {
            if let operationProgress = feedViewModel.operationProgress {
                FeedOperationProgressOverlay(progress: operationProgress)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            NetworkConnectionStatusIndicator(status: networkMonitor.status)
                .padding(.trailing, 18)
                .padding(.bottom, 16)
        }
        .animation(.snappy(duration: 0.18), value: feedViewModel.operationProgress)
        .focusedValue(
            \.articleCommandActions,
            ArticleCommandActions(
                selectedArticle: selectedArticle,
                toggleRead: {
                    articleViewModel.toggleRead(selectedArticle)
                },
                toggleStarred: {
                    articleViewModel.toggleStarred(selectedArticle)
                },
                toggleArchived: {
                    articleViewModel.toggleArchived(selectedArticle)
                },
                copyLink: {
                    _ = articleViewModel.copyLink(selectedArticle)
                },
                openOriginal: {
                    _ = articleViewModel.openOriginal(selectedArticle)
                },
                shareOriginal: {
                    _ = articleViewModel.shareOriginal(selectedArticle)
                },
                canSelectPreviousArticle: articleNavigationState.previousArticle != nil,
                canSelectNextArticle: articleNavigationState.nextArticle != nil,
                selectPreviousArticle: selectPreviousArticle,
                selectNextArticle: selectNextArticle
            )
        )
        .focusedValue(
            \.feedCommandActions,
            FeedCommandActions(
                selectedFeed: selectedFeed,
                requestAddFeed: requestAddFeed,
                requestImportOPML: requestImportOPML,
                requestExportOPML: requestExportOPML,
                refreshAllFeeds: {
                    Task {
                        await feedViewModel.refreshAllFeeds(feeds, context: modelContext)
                    }
                },
                refreshSelectedFeed: {
                    if let selectedFeed {
                        Task {
                            await feedViewModel.refreshFeed(selectedFeed, context: modelContext)
                        }
                    }
                },
                requestDelete: {
                    if let selectedFeed {
                        requestDeleteFeed(selectedFeed)
                    }
                },
                hasFeeds: !feeds.isEmpty
            )
        )
    }

    private func requestAddFeed() {
        isShowingFirstRunWizard = false
        isShowingAddFeedSheet = true
    }

    private func requestImportOPML() {
        isShowingFirstRunWizard = false
        isShowingOPMLImportReview = true
    }

    private func requestExportOPML() {
        let opmlFeeds = feedViewModel.opmlFeedsForExport(from: feeds)
        opmlExportDocument = OPMLDocument(text: OPMLService.exportFeeds(opmlFeeds))
        isExportingOPML = true
    }

    private func requestDeleteFeed(_ feed: Feed) {
        feedPendingDeletion = feed
        isDeleteFeedConfirmationPresented = true
    }

    private func requestCreateRuleFromArticle(_ article: Article) {
        articleForRuleCreation = article
    }

    private func updateFirstRunWizardPresentation() {
        if FirstRunWizardState.shouldKeepPresentedUntilUserStarts(
            isPresented: isShowingFirstRunWizard,
            wasDismissedThisSession: isFirstRunWizardDismissedForSession
        ) {
            return
        }

        let shouldShowWizard = FirstRunWizardState.shouldPresent(
            feedCount: feeds.count,
            hasCompletedWizard: hasCompletedFirstRunWizard,
            wasDismissedThisSession: isFirstRunWizardDismissedForSession
        )

        if feeds.count > 0 {
            isFirstRunWizardDismissedForSession = false
        }

        guard shouldShowWizard else {
            isShowingFirstRunWizard = false
            return
        }

        if !isShowingAddFeedSheet && !isShowingOPMLImportReview && articleForRuleCreation == nil {
            isShowingFirstRunWizard = true
        }
    }

    private func completeFirstRunWizard() {
        FirstRunWizardState.markCompleted(&hasCompletedFirstRunWizard)
        isFirstRunWizardDismissedForSession = true
        isShowingFirstRunWizard = false
    }

    private func skipFirstRunWizardForSession() {
        isFirstRunWizardDismissedForSession = true
        isShowingFirstRunWizard = false
    }

    private func deleteFeed(_ feed: Feed) {
        let shouldClearSelection = selectedFeed?.persistentModelID == feed.persistentModelID

        feedViewModel.deleteFeed(feed, context: modelContext)

        if feedViewModel.errorMessage == nil && shouldClearSelection {
            selectedArticle = nil
            sidebarSelection = .smartFilter(.allArticles)
        }

        feedPendingDeletion = nil
    }

    private func selectPreviousArticle() {
        if let previousArticle = articleNavigationState.previousArticle {
            selectedArticle = previousArticle
        }
    }

    private func selectNextArticle() {
        if let nextArticle = articleNavigationState.nextArticle {
            selectedArticle = nextArticle
        }
    }

    private var selectedFeed: Feed? {
        guard case .feed(let feedID) = sidebarSelection else {
            return nil
        }

        return feeds.first { $0.persistentModelID == feedID }
    }

    private var selectedTag: Tag? {
        guard case .tag(let tagID) = sidebarSelection else {
            return nil
        }

        return tags.first { $0.persistentModelID == tagID }
    }

    private var selectedSmartFilter: SmartFilter? {
        guard case .smartFilter(let smartFilter) = sidebarSelection else {
            return nil
        }

        return smartFilter
    }

}

enum NetworkConnectionStatus: Equatable {
    case online
    case offline

    var localizationKey: String {
        switch self {
        case .online:
            "networkStatus.online"
        case .offline:
            "networkStatus.offline"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .online:
            L10n.networkStatusOnline
        case .offline:
            L10n.networkStatusOffline
        }
    }

    var systemImageName: String {
        switch self {
        case .online:
            "wifi"
        case .offline:
            "wifi.slash"
        }
    }

    var tintColor: Color {
        switch self {
        case .online:
            .green
        case .offline:
            .red
        }
    }
}

@Observable
final class NetworkConnectionStatusMonitor {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "ch.martin.Feedivo.network-status")

    private(set) var status: NetworkConnectionStatus = .online

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        self.monitor.pathUpdateHandler = { [weak self] path in
            let status: NetworkConnectionStatus = path.status == .satisfied ? .online : .offline

            Task { @MainActor in
                self?.status = status
            }
        }
        self.monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

private struct NetworkConnectionStatusIndicator: View {
    let status: NetworkConnectionStatus
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    var body: some View {
        Label {
            Text(status.titleKey)
        } icon: {
            Image(systemName: status.systemImageName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(status.tintColor)
        }
        .font(interfaceTextSize.font(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
        .accessibilityLabel(Text(status.titleKey))
        .help(status.titleKey)
    }
}

private struct FeedOperationProgressOverlay: View {
    let progress: FeedOperationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text(progress.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer(minLength: 16)

                Text(progress.countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.linear)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
}

private struct OPMLAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
