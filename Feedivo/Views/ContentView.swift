import SwiftUI
import SwiftData
import Network
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(FirstRunWizardState.completionStorageKey) private var hasCompletedFirstRunWizard = false
    @AppStorage(AppIconBadgeSettings.isEnabledKey)
    private var appIconBadgeIsEnabled = AppIconBadgeSettings.defaultIsEnabled
    @AppStorage(OfflineReadingSettings.automaticallySaveStarredArticlesKey)
    private var automaticallySaveStarredArticles = OfflineReadingSettings.defaultAutomaticallySaveStarredArticles
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \SmartFolder.sortOrder) private var smartFolders: [SmartFolder]

    // columnVisibility steuert ob die Sidebar sichtbar ist.
    // .all bedeutet: alle 3 Spalten beim Start anzeigen.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // sidebarSelection speichert, welche Sidebar-Zeile ausgewählt ist.
    @State private var sidebarSelection: SidebarSelection?

    // selectedArticle speichert welcher Artikel gerade in der Liste ausgewählt ist.
    @State private var selectedArticle: Article? = nil
    @State private var articleNavigationState = ArticleNavigationState.empty

    @State private var articleViewModel = ArticleViewModel()
    @State private var offlineDownloadService = OfflineDownloadService()
    @State private var feedViewModel = FeedViewModel()
    @State private var isShowingAddFeedSheet = false
    @State private var feedPendingDeletion: Feed?
    @State private var isDeleteFeedConfirmationPresented = false
    @State private var isShowingOPMLImportReview = false
    @State private var isExportingOPML = false
    @State private var opmlExportDocument = OPMLDocument()
    @State private var articleExportRequest: ArticleExportRequest?
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
                onRequestAddFeed: requestAddFeed,
                onRequestDeleteFeed: requestDeleteFeed
            )
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 420)

        } content: {

            // SPALTE 2: Artikel-Liste des ausgewählten Feeds oder Smart Filters
            if let smartFolder = selectedSmartFolder {
                ArticleListView(
                    smartFolder: smartFolder,
                    selectedArticle: $selectedArticle,
                    navigationState: $articleNavigationState,
                    onRequestCreateRuleFromArticle: requestCreateRuleFromArticle,
                    onRequestExportArticle: requestExportArticle
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else if let feed = selectedFeed {
                ArticleListView(
                    feed: feed,
                    selectedArticle: $selectedArticle,
                    navigationState: $articleNavigationState,
                    onRequestCreateRuleFromArticle: requestCreateRuleFromArticle,
                    onRequestExportArticle: requestExportArticle
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else if let tag = selectedTag {
                ArticleListView(
                    tag: tag,
                    selectedArticle: $selectedArticle,
                    navigationState: $articleNavigationState,
                    onRequestCreateRuleFromArticle: requestCreateRuleFromArticle,
                    onRequestExportArticle: requestExportArticle
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else if let smartFilter = selectedSmartFilter {
                ArticleListView(
                    smartFilter: smartFilter,
                    selectedArticle: $selectedArticle,
                    navigationState: $articleNavigationState,
                    onRequestCreateRuleFromArticle: requestCreateRuleFromArticle,
                    onRequestExportArticle: requestExportArticle
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
                    selectNextArticle: selectNextArticle,
                    onRequestCreateRuleFromArticle: requestCreateRuleFromArticle,
                    onRequestExportArticle: requestExportArticle
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
            selectDefaultSmartFolderIfNeeded()
            updateAppIconBadge()
        }
        .onChange(of: smartFolders.count) {
            selectDefaultSmartFolderIfNeeded()
        }
        .onChange(of: feeds.count) {
            updateFirstRunWizardPresentation()
            updateAppIconBadge()
        }
        .onChange(of: unreadArticleCount) {
            updateAppIconBadge()
        }
        .onChange(of: appIconBadgeIsEnabled) {
            updateAppIconBadge()
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
        .sheet(item: $articleExportRequest) { request in
            ArticleExportSheet(request: request) {
                articleExportRequest = nil
            }
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
                    articleViewModel.toggleRead(selectedArticle, context: modelContext)
                    try? modelContext.save()
                },
                toggleStarred: {
                    Task {
                        await articleViewModel.toggleStarred(
                            selectedArticle,
                            automaticallySaveForOffline: automaticallySaveStarredArticles,
                            offlineSaver: offlineDownloadService
                        )
                    }
                },
                toggleArchived: {
                    Task {
                        await archiveOrRemoveArchive(selectedArticle)
                    }
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
                requestExport: {
                    if let selectedArticle {
                        requestExportArticle(selectedArticle)
                    }
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

    private func requestExportArticle(_ article: Article) {
        let request = ArticleExportRequest(snapshot: ArticleExportSnapshot(article: article))

        // Der Export kommt aus einem Kontextmenü. Der nächste Main-Runloop verhindert,
        // dass das Export-Sheet noch während der Menüaktion präsentiert wird.
        DispatchQueue.main.async {
            articleExportRequest = request
        }
    }

    private func requestDeleteFeed(_ feed: Feed) {
        feedPendingDeletion = feed
        isDeleteFeedConfirmationPresented = true
    }

    private func requestCreateRuleFromArticle(_ article: Article) {
        articleForRuleCreation = article
    }

    @MainActor
    private func archiveOrRemoveArchive(_ article: Article?) async {
        guard let article else {
            return
        }

        if article.isArchived {
            offlineDownloadService.removeArchive(from: article)
        } else {
            await offlineDownloadService.archiveForOffline(article)
        }

        try? modelContext.save()
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

    private var selectedSmartFolder: SmartFolder? {
        guard case .smartFolder(let smartFolderID) = sidebarSelection else {
            return nil
        }

        return smartFolders.first { $0.persistentModelID == smartFolderID }
    }

    private func selectDefaultSmartFolderIfNeeded() {
        guard sidebarSelection == nil || selectedSmartFilter != nil else {
            return
        }

        guard let defaultFolder = SmartFolderViewModel.sortedFolders(smartFolders)
            .first(where: \.isShownInSidebar)
        else {
            return
        }

        sidebarSelection = .smartFolder(defaultFolder.persistentModelID)
    }

    private var unreadArticleCount: Int {
        AppIconBadgeService.unreadCount(in: feeds)
    }

    private func updateAppIconBadge() {
        var updater = DockTileBadgeUpdater()
        AppIconBadgeService.updateBadge(
            unreadCount: unreadArticleCount,
            isEnabled: appIconBadgeIsEnabled,
            updater: &updater
        )
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
