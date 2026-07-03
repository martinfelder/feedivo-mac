import SwiftUI
import SwiftData
import Network
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.openWindow) private var openWindow
    @Environment(DatabaseLoadState.self) private var databaseLoadState
    @AppStorage(FirstRunWizardState.completionStorageKey) private var hasCompletedFirstRunWizard = false
    @AppStorage(AppIconBadgeSettings.isEnabledKey)
    private var appIconBadgeIsEnabled = AppIconBadgeSettings.defaultIsEnabled
    @AppStorage(OfflineReadingSettings.automaticallySaveStarredArticlesKey)
    private var automaticallySaveStarredArticles = OfflineReadingSettings.defaultAutomaticallySaveStarredArticles
    @AppStorage(ArticleWindowSettings.restoreOpenArticleWindowsOnLaunchKey)
    private var restoreOpenArticleWindowsOnLaunch = ArticleWindowSettings.defaultRestoreOpenArticleWindowsOnLaunch
    @AppStorage(BackgroundRefreshSettings.refreshOnLaunchIsEnabledKey)
    private var refreshOnLaunchIsEnabled = BackgroundRefreshSettings.defaultRefreshOnLaunchIsEnabled
    @AppStorage(BackgroundRefreshSettings.intervalMinutesKey)
    private var backgroundRefreshIntervalMinutes = BackgroundRefreshSettings.defaultIntervalMinutes
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(sort: \SmartFolder.sortOrder) private var smartFolders: [SmartFolder]

    // columnVisibility steuert ob die Sidebar sichtbar ist.
    // .all bedeutet: alle 3 Spalten beim Start anzeigen.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // sidebarSelection speichert, welche Sidebar-Zeile ausgewählt ist.
    @State private var sidebarSelection: SidebarSelection?

    // selectedArticle speichert welcher Artikel gerade in der Liste ausgewählt ist.
    @State private var selectedArticle: Article? = nil
    @State private var articleNavigationState = ArticleNavigationState.empty
    @State private var selectedSQLiteArticleID: String?
    @State private var selectedSQLiteArticleSnapshot: ArticleReaderSnapshot?
    @State private var sqliteArticleNavigationState = SQLiteArticleNavigationState.empty
    @State private var articleSearchFocusRequest = 0

    @State private var articleViewModel = ArticleViewModel()
    @State private var offlineDownloadService = OfflineDownloadService()
    @State private var feedViewModel: FeedViewModel
    @State private var isShowingAddFeedSheet = false
    @State private var feedPendingDeletion: Feed?
    @State private var isDeleteFeedConfirmationPresented = false
    @State private var isShowingOPMLImportReview = false
    @State private var isShowingOPMLExportSheet = false
    @State private var articleExportRequest: ArticleExportRequest?
    @State private var opmlAlert: OPMLAlert?
    @State private var offlineArchiveError: OPMLAlert?
    @State private var articleForRuleCreation: Article?
    @State private var isMetadataInspectorPresented = false
    @State private var isShowingFirstRunWizard = false
    @State private var isFirstRunWizardDismissedForSession = false
    @State private var didRestoreArticleWindowsForLaunch = false
    @State private var didRunRefreshForLaunch = false
    @State private var isRefreshStatusExpanded = false
    @State private var networkMonitor = NetworkConnectionStatusMonitor()
    private let modelContainer: ModelContainer?

    init(feedViewModel: FeedViewModel = FeedViewModel(), modelContainer: ModelContainer? = nil) {
        _feedViewModel = State(initialValue: feedViewModel)
        self.modelContainer = modelContainer
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {

            // SPALTE 1: Sidebar — Liste aller Feeds
            SidebarView(
                selection: $sidebarSelection,
                onRequestAddFeed: requestAddFeed,
                onRequestRefreshAllFeeds: requestRefreshAllFeeds,
                onRequestDeleteFeed: requestDeleteFeed
            )
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 420)

        } content: {

            // SPALTE 2: Artikel-Liste des ausgewählten Feeds oder Smart Filters
            if let smartFolder = selectedSmartFolder {
                SQLiteFeedArticleListView(
                    smartFolder: smartFolder,
                    selectedArticleID: $selectedSQLiteArticleID,
                    navigationState: $sqliteArticleNavigationState
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else if let feed = selectedFeed {
                SQLiteFeedArticleListView(
                    feed: feed,
                    selectedArticleID: $selectedSQLiteArticleID,
                    navigationState: $sqliteArticleNavigationState
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else if let tagID = selectedTagID {
                SQLiteFeedArticleListView(
                    tagID: tagID,
                    selectedArticleID: $selectedSQLiteArticleID,
                    navigationState: $sqliteArticleNavigationState
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else if let smartFilter = selectedSmartFilter {
                SQLiteFeedArticleListView(
                    smartFilter: smartFilter,
                    selectedArticleID: $selectedSQLiteArticleID,
                    navigationState: $sqliteArticleNavigationState
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
            if let selectedSQLiteArticleID {
                SQLiteReaderView(
                    articleID: selectedSQLiteArticleID,
                    canSelectPreviousArticle: sqliteArticleNavigationState.previousArticleID != nil,
                    canSelectNextArticle: sqliteArticleNavigationState.nextArticleID != nil,
                    selectPreviousArticle: selectPreviousArticle,
                    selectNextArticle: selectNextArticle,
                    onSnapshotChange: handleSQLiteArticleSnapshotChange
                )
                .id(selectedSQLiteArticleID)
            } else if let article = selectedArticle {
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
                .id(article.id)
            } else {
                ContentUnavailableView(
                    L10n.contentNoArticleSelectedTitle,
                    systemImage: "doc.text",
                    description: Text(L10n.contentNoArticleSelectedDescription)
                )
            }

        }
        .onChange(of: sidebarSelection, handleSidebarSelectionChange)
        .onChange(of: selectedSQLiteArticleID, handleSQLiteArticleSelectionChange)
        .onAppear(perform: handleContentAppear)
        .onChange(of: smartFolders.count, handleSmartFolderCountChange)
        .onChange(of: feeds.count, handleFeedCountChange)
        .onChange(of: unreadArticleCount, handleUnreadArticleCountChange)
        .onChange(of: appIconBadgeIsEnabled, handleAppIconBadgeSettingChange)
        .onChange(of: hasCompletedFirstRunWizard, handleFirstRunCompletionChange)
        .sheet(isPresented: $isShowingAddFeedSheet) {
            AddFeedSheet()
        }
        .sheet(isPresented: $isShowingOPMLImportReview) {
            OPMLImportReviewView(
                feeds: feeds,
                feedViewModel: feedViewModel
            )
        }
        .sheet(isPresented: $isShowingOPMLExportSheet) {
            OPMLExportSheet(feeds: feeds) {
                isShowingOPMLExportSheet = false
            }
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
        .alert(item: $opmlAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.commonDone))
            )
        }
        .alert(item: $offlineArchiveError) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.commonDone))
            )
        }
        // M11: Wenn die SwiftData-Datenbank beim Start nicht geöffnet werden
        // konnte, läuft die App mit einem leeren In-Memory-Fallback. Dieser
        // Alarm erklärt das einmalig, statt die App ohne Erklärung abstürzen
        // zu lassen. Nach dem Schließen wird der Fehler verworfen.
        .alert(
            L10n.databaseInitErrorTitle,
            isPresented: Binding(
                get: { databaseLoadState.initializationError != nil },
                set: { newValue in
                    if !newValue {
                        databaseLoadState.initializationError = nil
                    }
                }
            )
        ) {
            Button(L10n.commonDone) {
                databaseLoadState.initializationError = nil
            }
        } message: {
            if let detail = databaseLoadState.initializationError {
                Text(verbatim: "\(L10n.databaseInitErrorMessage)\n\n\(detail)")
            } else {
                Text(L10n.databaseInitErrorMessage)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            BottomStatusIndicators(
                refreshProgress: feedViewModel.operationProgress,
                refreshSummary: feedViewModel.recentRefreshStatus,
                refreshItems: feedViewModel.refreshItems,
                isRefreshStatusExpanded: $isRefreshStatusExpanded,
                networkStatus: networkMonitor.status,
                dismissRefreshStatus: dismissRefreshStatus
            )
                .padding(.trailing, 18)
                .padding(.bottom, 16)
        }
        .task(id: recentRefreshStatusID) {
            await clearRecentRefreshStatusIfNeeded()
        }
        .animation(.snappy(duration: 0.18), value: feedViewModel.recentRefreshStatus)
        .animation(.snappy(duration: 0.18), value: isRefreshStatusExpanded)
        .focusedValue(
            \.articleCommandActions,
            articleCommandActions
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
                        await refreshAllFeeds()
                    }
                },
                refreshSelectedFeed: {
                    if let selectedFeed {
                        Task {
                            await feedViewModel.refreshFeed(
                                selectedFeed,
                                context: modelContext,
                                sqliteDatabase: feedivoDatabase
                            )
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

    private func handleSidebarSelectionChange() {
        selectedArticle = nil
        articleNavigationState = .empty
        selectedSQLiteArticleID = nil
        selectedSQLiteArticleSnapshot = nil
        sqliteArticleNavigationState = .empty
    }

    private func handleSQLiteArticleSelectionChange() {
        guard selectedSQLiteArticleID != nil else {
            selectedSQLiteArticleSnapshot = nil
            return
        }

        selectedSQLiteArticleSnapshot = nil
        selectedArticle = nil
        articleNavigationState = .empty
    }

    private func handleSQLiteArticleSnapshotChange(_ snapshot: ArticleReaderSnapshot?) {
        guard selectedSQLiteArticleID != nil else {
            selectedSQLiteArticleSnapshot = nil
            return
        }

        selectedSQLiteArticleSnapshot = snapshot
    }

    private func handleContentAppear() {
        updateFirstRunWizardPresentation()
        selectDefaultSmartFolderIfNeeded()
        updateAppIconBadge()
        restoreArticleWindowsIfNeeded()
        refreshFeedsOnLaunchIfNeeded()
    }

    private func handleSmartFolderCountChange() {
        selectDefaultSmartFolderIfNeeded()
    }

    private func handleFeedCountChange() {
        updateFirstRunWizardPresentation()
        updateAppIconBadge()
        refreshFeedsOnLaunchIfNeeded()
    }

    private func handleUnreadArticleCountChange() {
        updateAppIconBadge()
    }

    private func handleAppIconBadgeSettingChange() {
        updateAppIconBadge()
    }

    private func handleFirstRunCompletionChange() {
        updateFirstRunWizardPresentation()
    }

    private var recentRefreshStatusID: UUID? {
        feedViewModel.recentRefreshStatus?.id
    }

    private func clearRecentRefreshStatusIfNeeded() async {
        guard let statusID = recentRefreshStatusID else {
            return
        }

        await clearRecentRefreshStatus(after: statusID)
    }

    private func requestRefreshAllFeeds() {
        Task {
            await refreshAllFeeds()
        }
    }

    private func requestImportOPML() {
        isShowingFirstRunWizard = false
        isShowingOPMLImportReview = true
    }

    private func requestExportOPML() {
        isShowingOPMLExportSheet = true
    }

    private func requestExportArticle(_ article: Article) {
        let request = ArticleExportRequest(snapshot: ArticleExportSnapshot(article: article))

        // Der Export kommt aus einem Kontextmenü. Der nächste Main-Runloop verhindert,
        // dass das Export-Sheet noch während der Menüaktion präsentiert wird.
        DispatchQueue.main.async {
            articleExportRequest = request
        }
    }

    private func requestExportSQLiteArticle(_ snapshot: ArticleReaderSnapshot) {
        guard let database = feedivoDatabase else {
            return
        }

        do {
            let tagNames = try TagStore(database: database).exportTagNames(
                articleID: snapshot.id,
                feedID: snapshot.feedID
            )
            let request = ArticleExportRequest(
                snapshot: ArticleExportSnapshot(sqliteSnapshot: snapshot, tagNames: tagNames)
            )

            DispatchQueue.main.async {
                articleExportRequest = request
            }
        } catch {
            opmlAlert = OPMLAlert(
                title: L10n.articleExportCommand,
                message: error.localizedDescription
            )
        }
    }

    private func openArticleInWindow(_ article: Article?) {
        guard let article else {
            return
        }

        openWindow(value: ArticleWindowRequest(articleID: article.id))
    }

    private func openSQLiteArticleInWindow(articleID: String?) {
        guard
            let articleID,
            let uuid = UUID(uuidString: articleID)
        else {
            return
        }

        openWindow(value: ArticleWindowRequest(articleID: uuid))
    }

    private func restoreArticleWindowsIfNeeded() {
        guard restoreOpenArticleWindowsOnLaunch, !didRestoreArticleWindowsForLaunch else {
            return
        }

        didRestoreArticleWindowsForLaunch = true
        for articleID in ArticleWindowSettings.openArticleIDs() {
            openWindow(value: ArticleWindowRequest(articleID: articleID))
        }
    }

    private func refreshFeedsOnLaunchIfNeeded() {
        guard refreshOnLaunchIsEnabled, !didRunRefreshForLaunch, !feeds.isEmpty else {
            return
        }

        didRunRefreshForLaunch = true
        Task {
            await refreshAllFeeds()
            BackgroundRefreshService.recordRefreshOutcome(
                from: feedViewModel,
                intervalMinutes: backgroundRefreshIntervalMinutes
            )
        }
    }

    @MainActor
    private func refreshAllFeeds() async {
        if let modelContainer {
            await feedViewModel.refreshAllFeeds(
                feeds,
                modelContainer: modelContainer,
                sqliteDatabase: feedivoDatabase
            )
        } else {
            await feedViewModel.refreshAllFeeds(
                feeds,
                context: modelContext,
                sqliteDatabase: feedivoDatabase
            )
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
            let success = await offlineDownloadService.archiveForOffline(article)
            if !success {
                // Speichern fehlgeschlagen (z.B. URL nicht erreichbar) —
                // vorher blieb das lautlos: isArchived false, kein Hinweis.
                offlineArchiveError = OPMLAlert(
                    title: L10n.offlineArchiveErrorTitle,
                    message: article.offlineErrorMessage ?? L10n.offlineArchiveErrorMessage
                )
            }
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
        let deletedFeedID = feed.persistentModelID
        let shouldClearFeedSelection = selectedFeed?.persistentModelID == deletedFeedID
        // Auch bei Smart-Filtern (z.B. „Alle Artikel") kann der gerade
        // selektierte Artikel zum gelöschten Feed gehören — dann bliebe eine
        // Tombstone-Selektion zurück (potenzieller Crash beim Zugriff). Deshalb
        // VOR dem Löschen erfassen und Auswahl bereinigen.
        let selectedArticleBelongsToDeletedFeed = selectedArticle?.feed?.persistentModelID == deletedFeedID

        feedViewModel.deleteFeed(feed, context: modelContext)

        guard feedViewModel.errorMessage == nil else {
            feedPendingDeletion = nil
            return
        }

        if selectedArticleBelongsToDeletedFeed {
            selectedArticle = nil
        }

        if shouldClearFeedSelection {
            sidebarSelection = .smartFilter(.allArticles)
        }

        feedPendingDeletion = nil
    }

    private func selectPreviousArticle() {
        if selectedSQLiteArticleID != nil {
            selectedSQLiteArticleID = sqliteArticleNavigationState.previousArticleID
            return
        }

        if let previousArticle = articleNavigationState.previousArticle {
            selectedArticle = previousArticle
        }
    }

    private func selectNextArticle() {
        if selectedSQLiteArticleID != nil {
            selectedSQLiteArticleID = sqliteArticleNavigationState.nextArticleID
            return
        }

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

    private var selectedTagID: String? {
        guard case .tag(let tagID) = sidebarSelection else {
            return nil
        }

        return tagID
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

    private var articleCommandActions: ArticleCommandActions {
        if selectedSQLiteArticleID != nil {
            return sqliteArticleCommandActions
        }

        return swiftDataArticleCommandActions
    }

    private var sqliteArticleCommandActions: ArticleCommandActions {
        ArticleCommandActions(
            canPerformActions: selectedSQLiteArticleSnapshot != nil,
            canPerformLinkActions: ArticleOriginalURLResolver.hasUsableWebLink(selectedSQLiteArticleSnapshot?.link),
            toggleReadTitle: selectedSQLiteArticleSnapshot?.isRead == true ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead,
            toggleStarredTitle: selectedSQLiteArticleSnapshot?.isStarred == true ? L10n.articleRowStarRemove : L10n.articleRowStarAdd,
            toggleArchivedTitle: selectedSQLiteArticleSnapshot?.isArchived == true ? L10n.articleUnarchiveCommand : L10n.articleArchiveCommand,
            toggleRead: toggleSelectedSQLiteReadStatus,
            toggleStarred: toggleSelectedSQLiteStarredStatus,
            toggleArchived: toggleSelectedSQLiteArchivedStatus,
            copyLink: copySelectedSQLiteArticleLink,
            openOriginal: openSelectedSQLiteArticleOriginal,
            shareOriginal: shareSelectedSQLiteArticleOriginal,
            openInArticleWindow: {
                openSQLiteArticleInWindow(articleID: selectedSQLiteArticleID)
            },
            requestExport: {
                if let snapshot = selectedSQLiteArticleSnapshot {
                    requestExportSQLiteArticle(snapshot)
                }
            },
            canSelectPreviousArticle: sqliteArticleNavigationState.previousArticleID != nil,
            canSelectNextArticle: sqliteArticleNavigationState.nextArticleID != nil,
            selectPreviousArticle: selectPreviousArticle,
            selectNextArticle: selectNextArticle
        )
    }

    private var swiftDataArticleCommandActions: ArticleCommandActions {
        ArticleCommandActions(
            canPerformActions: selectedArticle != nil,
            canPerformLinkActions: ArticleOriginalURLResolver.hasUsableWebLink(selectedArticle?.link),
            toggleReadTitle: selectedArticle?.isRead == true ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead,
            toggleStarredTitle: selectedArticle?.isStarred == true ? L10n.articleRowStarRemove : L10n.articleRowStarAdd,
            toggleArchivedTitle: selectedArticle?.isArchived == true ? L10n.articleUnarchiveCommand : L10n.articleArchiveCommand,
            toggleRead: {
                articleViewModel.toggleRead(selectedArticle, context: modelContext)
                try? modelContext.save()
            },
            toggleStarred: {
                Task {
                    await articleViewModel.toggleStarred(
                        selectedArticle,
                        automaticallySaveForOffline: automaticallySaveStarredArticles,
                        context: modelContext,
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
            openInArticleWindow: {
                openArticleInWindow(selectedArticle)
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
    }

    private func toggleSelectedSQLiteReadStatus() {
        guard let snapshot = selectedSQLiteArticleSnapshot, let database = feedivoDatabase else {
            return
        }

        do {
            try ArticleStatusStore(database: database).setRead(!snapshot.isRead, articleID: snapshot.id, at: Date())
            reloadSelectedSQLiteArticleSnapshot(database: database)
        } catch {
            opmlAlert = OPMLAlert(title: L10n.databaseInitErrorTitle, message: error.localizedDescription)
        }
    }

    private func toggleSelectedSQLiteStarredStatus() {
        guard let snapshot = selectedSQLiteArticleSnapshot, let database = feedivoDatabase else {
            return
        }

        do {
            try ArticleStatusStore(database: database).setStarred(!snapshot.isStarred, articleID: snapshot.id, at: Date())
            reloadSelectedSQLiteArticleSnapshot(database: database)
        } catch {
            opmlAlert = OPMLAlert(title: L10n.databaseInitErrorTitle, message: error.localizedDescription)
        }
    }

    private func toggleSelectedSQLiteArchivedStatus() {
        guard let snapshot = selectedSQLiteArticleSnapshot, let database = feedivoDatabase else {
            return
        }

        do {
            try ArticleStatusStore(database: database).setArchived(!snapshot.isArchived, articleID: snapshot.id, at: Date())
            reloadSelectedSQLiteArticleSnapshot(database: database)
        } catch {
            opmlAlert = OPMLAlert(title: L10n.databaseInitErrorTitle, message: error.localizedDescription)
        }
    }

    private func reloadSelectedSQLiteArticleSnapshot(database: FeedivoDatabase) {
        guard let selectedSQLiteArticleID else {
            selectedSQLiteArticleSnapshot = nil
            return
        }

        selectedSQLiteArticleSnapshot = try? ArticleStore(database: database).readerArticle(id: selectedSQLiteArticleID)
    }

    private func copySelectedSQLiteArticleLink() {
        guard let url = ArticleOriginalURLResolver.url(for: selectedSQLiteArticleSnapshot?.link) else {
            return
        }

        SystemArticleLinkPasteboard().copy(url.absoluteString)
    }

    private func openSelectedSQLiteArticleOriginal() {
        guard let url = ArticleOriginalURLResolver.url(for: selectedSQLiteArticleSnapshot?.link) else {
            return
        }

        SystemArticleURLOpener().open(url)
    }

    private func shareSelectedSQLiteArticleOriginal() {
        guard let url = ArticleOriginalURLResolver.url(for: selectedSQLiteArticleSnapshot?.link) else {
            return
        }

        SystemArticleSharingPresenter().share(url)
    }

    private func updateAppIconBadge() {
        var updater = DockTileBadgeUpdater()
        AppIconBadgeService.updateBadge(
            unreadCount: unreadArticleCount,
            isEnabled: appIconBadgeIsEnabled,
            updater: &updater
        )
    }

    private func clearRecentRefreshStatus(after statusID: UUID) async {
        guard feedViewModel.recentRefreshStatus?.hasFailures == false else {
            return
        }

        try? await Task.sleep(for: .seconds(120))
        guard feedViewModel.recentRefreshStatus?.id == statusID,
              feedViewModel.recentRefreshStatus?.hasFailures == false
        else {
            return
        }

        dismissRefreshStatus()
    }

    private func dismissRefreshStatus() {
        isRefreshStatusExpanded = false
        feedViewModel.clearRecentRefreshStatus()
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

private struct BottomStatusIndicators: View {
    let refreshProgress: FeedOperationProgress?
    let refreshSummary: FeedRefreshStatusSummary?
    let refreshItems: [FeedRefreshItem]
    @Binding var isRefreshStatusExpanded: Bool
    let networkStatus: NetworkConnectionStatus
    let dismissRefreshStatus: () -> Void

    private var hasRefreshStatus: Bool {
        refreshProgress != nil || refreshSummary != nil
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if hasRefreshStatus, isRefreshStatusExpanded {
                FeedRefreshDetailPanel(
                    progress: refreshProgress,
                    summary: refreshSummary,
                    items: refreshItems,
                    dismiss: dismissRefreshStatus
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                if hasRefreshStatus {
                    FeedRefreshStatusControl(
                        progress: refreshProgress,
                        summary: refreshSummary,
                        isExpanded: $isRefreshStatusExpanded
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                NetworkConnectionStatusIndicator(status: networkStatus)
            }
        }
    }
}

private struct FeedRefreshStatusControl: View {
    let progress: FeedOperationProgress?
    let summary: FeedRefreshStatusSummary?
    @Binding var isExpanded: Bool
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    var body: some View {
        HStack(spacing: 8) {
            statusIcon

            Text(title)
                .monospacedDigit()

            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isExpanded ? L10n.refreshStatusCollapse : L10n.refreshStatusExpand)
            .accessibilityLabel(Text(isExpanded ? L10n.refreshStatusCollapse : L10n.refreshStatusExpand))
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
        .accessibilityLabel(Text(title))
        .help(title)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if progress != nil {
            ProgressView()
                .controlSize(.small)
                .frame(width: 12, height: 12)
        } else {
            Image(systemName: summarySystemImageName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(summaryTintColor)
        }
    }

    private var title: String {
        if let progress {
            return L10n.refreshStatusRunning(progress.countText)
        }

        guard let summary else {
            return ""
        }

        if summary.hasFailures {
            return L10n.refreshStatusPartial(
                newArticleCount: summary.newArticleCount,
                failedFeedCount: summary.failedFeedCount
            )
        }

        if summary.newArticleCount == 0 {
            return L10n.refreshStatusNoNewArticles
        }

        return L10n.refreshStatusNewArticles(summary.newArticleCount)
    }

    private var summarySystemImageName: String {
        if summary?.isFullFailure == true {
            return "exclamationmark.triangle.fill"
        }

        if summary?.hasFailures == true {
            return "exclamationmark.circle.fill"
        }

        return "checkmark.circle.fill"
    }

    private var summaryTintColor: Color {
        if summary?.isFullFailure == true {
            return .red
        }

        if summary?.hasFailures == true {
            return .orange
        }

        return .green
    }
}

private struct FeedRefreshDetailPanel: View {
    let progress: FeedOperationProgress?
    let summary: FeedRefreshStatusSummary?
    let items: [FeedRefreshItem]
    let dismiss: () -> Void
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    private var isRunning: Bool {
        progress != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(L10n.refreshStatusDetailsTitle)
                    .font(interfaceTextSize.font(size: 12, weight: .semibold))

                Spacer(minLength: 12)

                if let progress {
                    Text(progress.countText)
                        .font(interfaceTextSize.font(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if !isRunning {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(L10n.refreshStatusDismiss)
                    .accessibilityLabel(Text(L10n.refreshStatusDismiss))
                }
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        FeedRefreshItemRow(item: item)
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(maxHeight: 220)
        }
        .padding(12)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
}

private struct FeedRefreshItemRow: View {
    let item: FeedRefreshItem
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.feedTitle)
                    .font(interfaceTextSize.font(size: 11, weight: .medium))
                    .lineLimit(1)

                Text(statusText)
                    .font(interfaceTextSize.font(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        case .refreshing:
            ProgressView()
                .controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
        }
    }

    private var statusText: String {
        switch item.status {
        case .pending:
            L10n.refreshStatusItemPending
        case .refreshing:
            L10n.refreshStatusItemRefreshing
        case .succeeded:
            L10n.refreshStatusItemSucceeded
        case .failed:
            L10n.refreshStatusItemFailed
        }
    }
}

private struct OPMLAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
