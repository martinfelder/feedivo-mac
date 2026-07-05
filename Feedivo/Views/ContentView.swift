import SwiftUI
import Network
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.openWindow) private var openWindow
    @Environment(DatabaseLoadState.self) private var databaseLoadState
    @AppStorage(FirstRunWizardState.completionStorageKey) private var hasCompletedFirstRunWizard = false
    @AppStorage(FirstRunWizardState.presentationStorageKey) private var hasPresentedFirstRunWizard = false
    @AppStorage(FirstRunWizardState.hadFeedsStorageKey) private var hasHadFeedsForFirstRunWizard = false
    @AppStorage(AppIconBadgeSettings.isEnabledKey)
    private var appIconBadgeIsEnabled = AppIconBadgeSettings.defaultIsEnabled
    @AppStorage(ArticleWindowSettings.restoreOpenArticleWindowsOnLaunchKey)
    private var restoreOpenArticleWindowsOnLaunch = ArticleWindowSettings.defaultRestoreOpenArticleWindowsOnLaunch
    @AppStorage(BackgroundRefreshSettings.refreshOnLaunchIsEnabledKey)
    private var refreshOnLaunchIsEnabled = BackgroundRefreshSettings.defaultRefreshOnLaunchIsEnabled
    @AppStorage(BackgroundRefreshSettings.intervalMinutesKey)
    private var backgroundRefreshIntervalMinutes = BackgroundRefreshSettings.defaultIntervalMinutes
    // SQLite-only Feed-Identität: Statt @Query [Feed] (SwiftData) hält
    // ContentView Sidebar-Snapshots aus `FeedStore.sidebarFeeds()` vor. Die
    // Liste wird beim Erscheinen und bei Status-Version-Bumps (Feed-Anlage/
    // -Löschung/-Refresh) neu geladen. SwiftData `Feed` ist nur noch
    // Aktionsbackend für den Brücken-Löschpfad (siehe deleteFeed/feedID).
    @State private var feedSnapshots: [FeedSidebarSnapshot] = []
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0

    // columnVisibility steuert ob die Sidebar sichtbar ist.
    // .all bedeutet: alle 3 Spalten beim Start anzeigen.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // sidebarSelection speichert, welche Sidebar-Zeile ausgewählt ist.
    @State private var sidebarSelection: SidebarSelection?

    @State private var selectedSQLiteArticleID: String?
    @State private var selectedSQLiteArticleSnapshot: ArticleReaderSnapshot?
    @State private var sqliteArticleNavigationState = SQLiteArticleNavigationState.empty
    @State private var articleSearchText = ""
    @State private var articleSearchFocusRequest = 0

    @State private var feedViewModel: FeedViewModel
    @State private var isShowingAddFeedSheet = false
    // SQLite-Identität: Lösch-Bestätigung arbeitet auf dem Sidebar-Snapshot
    // (String-ID) statt auf einem SwiftData-`Feed`-Objekt.
    @State private var feedPendingDeletion: FeedSidebarSnapshot?
    @State private var isDeleteFeedConfirmationPresented = false
    @State private var isShowingOPMLImportReview = false
    @State private var isShowingOPMLExportSheet = false
    @State private var articleExportRequest: ArticleExportRequest?
    @State private var ruleCreationRequest: RuleCreationRequest?
    @State private var opmlAlert: OPMLAlert?
    @State private var isMetadataInspectorPresented = false
    @State private var isShowingFirstRunWizard = false
    @State private var isFirstRunWizardDismissedForSession = false
    @State private var didRestoreArticleWindowsForLaunch = false
    @State private var didRunRefreshForLaunch = false
    @State private var isRefreshStatusExpanded = false
    @State private var networkMonitor = NetworkConnectionStatusMonitor()
    

    init(feedViewModel: FeedViewModel = FeedViewModel()) {
        _feedViewModel = State(initialValue: feedViewModel)
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
                    navigationState: $sqliteArticleNavigationState,
                    searchText: $articleSearchText
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else if let feedID = selectedFeedID {
                SQLiteFeedArticleListView(
                    feedID: feedID,
                    title: selectedFeed?.title ?? "",
                    selectedArticleID: $selectedSQLiteArticleID,
                    navigationState: $sqliteArticleNavigationState,
                    searchText: $articleSearchText
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else if let tagID = selectedTagID {
                SQLiteFeedArticleListView(
                    tagID: tagID,
                    selectedArticleID: $selectedSQLiteArticleID,
                    navigationState: $sqliteArticleNavigationState,
                    searchText: $articleSearchText
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else if let smartFilter = selectedSmartFilter {
                SQLiteFeedArticleListView(
                    smartFilter: smartFilter,
                    selectedArticleID: $selectedSQLiteArticleID,
                    navigationState: $sqliteArticleNavigationState,
                    searchText: $articleSearchText
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
                    articleSearchText: $articleSearchText,
                    onSnapshotChange: handleSQLiteArticleSnapshotChange,
                    onCreateRule: requestRuleCreation
                )
                .id(selectedSQLiteArticleID)
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
        .task {
            // SQLite-Sidebar-Snapshots beim Erscheinen laden (ersetzt @Query).
            await reloadFeedSnapshots()
        }
        .onChange(of: sqliteStatusVersion) {
            // Bei Anlage/Löschung/Refresh (Status-Version-Bump) Snapshots neu
            // laden, damit First-Run, Badge und Feed-Menü aktuell bleiben.
            Task { await reloadFeedSnapshots() }
        }
        .onChange(of: feedSnapshots.count, handleFeedCountChange)
        .onChange(of: unreadArticleCount, handleUnreadArticleCountChange)
        .onChange(of: appIconBadgeIsEnabled, handleAppIconBadgeSettingChange)
        .onChange(of: hasCompletedFirstRunWizard, handleFirstRunCompletionChange)
        .sheet(isPresented: $isShowingAddFeedSheet) {
            AddFeedSheet()
        }
        .sheet(isPresented: $isShowingOPMLImportReview) {
            OPMLImportReviewView(
                feedViewModel: feedViewModel
            )
        }
        .sheet(isPresented: $isShowingOPMLExportSheet) {
            OPMLExportSheet {
                isShowingOPMLExportSheet = false
            }
        }
        .sheet(
            isPresented: $isShowingFirstRunWizard,
            onDismiss: handleFirstRunWizardDismiss
        ) {
            FirstRunWizardView(
                feedViewModel: feedViewModel,
                onSkip: skipFirstRunWizardForSession,
                onComplete: completeFirstRunWizard
            )
        }
        .sheet(item: $articleExportRequest) { request in
            ArticleExportSheet(request: request) {
                articleExportRequest = nil
            }
        }
        .sheet(item: $ruleCreationRequest) { request in
            RuleWizardView(
                existingRules: sqliteRulesForRuleCreation(),
                seed: request.seed
            )
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
        .focusedSceneValue(
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
                    if let feedID = selectedFeedID {
                        Task {
                            await feedViewModel.refreshFeed(
                                feedID: feedID,
                                sqliteDatabase: feedivoDatabase
                            )
                        }
                    }
                },
                requestDelete: {
                    if let feedID = selectedFeedID {
                        requestDeleteFeed(feedID)
                    }
                },
                hasFeeds: !feedSnapshots.isEmpty
            )
        )
    }

    private func requestAddFeed() {
        isShowingFirstRunWizard = false
        isShowingAddFeedSheet = true
    }

    private func handleSidebarSelectionChange() {
        selectedSQLiteArticleID = nil
        selectedSQLiteArticleSnapshot = nil
        sqliteArticleNavigationState = .empty
        articleSearchText = ""
    }

    private func handleSQLiteArticleSelectionChange() {
        guard selectedSQLiteArticleID != nil else {
            selectedSQLiteArticleSnapshot = nil
            return
        }

        selectedSQLiteArticleSnapshot = nil
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

    /// Lädt die SQLite-Sidebar-Snapshots aus `FeedStore.sidebarFeeds()` und
    /// aktualisiert `feedSnapshots`. Ersetzt das frühere `@Query [Feed]`. Wird
    /// beim Erscheinen und bei Status-Version-Bumps aufgerufen; treibt First-
    /// Run-Entscheidung, Dock-Badge und `hasFeeds` des Feed-Menüs.
    @MainActor
    private func reloadFeedSnapshots() async {
        guard let database = feedivoDatabase else {
            feedSnapshots = []
            return
        }
        feedSnapshots = (try? FeedStore(database: database).sidebarFeeds()) ?? []
        if !feedSnapshots.isEmpty {
            FirstRunWizardState.markHadFeeds(&hasHadFeedsForFirstRunWizard)
        }
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
        guard refreshOnLaunchIsEnabled, !didRunRefreshForLaunch, !feedSnapshots.isEmpty else {
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
        // SQLite-first: Snapshots lädt FeedViewModel aus FeedStore.feeds(). Der
        // optionale Container wird für den Regel-Kontext (Rule-Snapshots)
        // benötigt; ohne Datenbank wird der Refresh übersprungen.
        guard let database = feedivoDatabase else {
            return
        }
        await feedViewModel.refreshAllFeeds(
            sqliteDatabase: database
        )
    }

    private func requestDeleteFeed(_ feedID: String) {
        feedPendingDeletion = feedSnapshots.first { $0.id == feedID }
        isDeleteFeedConfirmationPresented = true
    }

    private func updateFirstRunWizardPresentation() {
        if feedSnapshots.count > 0 {
            FirstRunWizardState.markHadFeeds(&hasHadFeedsForFirstRunWizard)
        }

        // Der Wizard darf den leeren Arbeitsbereich nicht blockieren. Feedivo
        // bietet die produktiven Einstiege über Toolbar und Feed-Menü an.
        isShowingFirstRunWizard = false
    }

    private func completeFirstRunWizard() {
        FirstRunWizardState.markCompleted(&hasCompletedFirstRunWizard)
        isFirstRunWizardDismissedForSession = true
        isShowingFirstRunWizard = false
    }

    private func skipFirstRunWizardForSession() {
        FirstRunWizardState.markCompleted(&hasCompletedFirstRunWizard)
        isFirstRunWizardDismissedForSession = true
        isShowingFirstRunWizard = false
    }

    private func handleFirstRunWizardDismiss() {
        FirstRunWizardState.markPresented(&hasPresentedFirstRunWizard)
        isFirstRunWizardDismissedForSession = true
    }

    private func deleteFeed(_ snapshot: FeedSidebarSnapshot) {
        let feedID = snapshot.id
        let shouldClearFeedSelection = selectedFeedID == feedID
        // SQLite-first: FeedViewModel.deleteFeed(feedID:)) löscht den
        // SQLite-FeedRecord per FeedStore und räumt zusätzlich den
        // die produktive Datenquelle bereinigt. Die Status-Version wird gebumpt,
        // damit Sidebar und Listener neu laden.
        feedViewModel.deleteFeed(feedID: feedID, sqliteDatabase: feedivoDatabase)

        guard feedViewModel.errorMessage == nil else {
            feedPendingDeletion = nil
            return
        }

        if shouldClearFeedSelection {
            sidebarSelection = .smartFilter(.allArticles)
        }

        feedPendingDeletion = nil
    }

    private func selectPreviousArticle() {
        if selectedSQLiteArticleID != nil {
            selectedSQLiteArticleID = sqliteArticleNavigationState.previousArticleID
        }
    }

    private func selectNextArticle() {
        if selectedSQLiteArticleID != nil {
            selectedSQLiteArticleID = sqliteArticleNavigationState.nextArticleID
        }
    }

    private var selectedFeedID: String? {
        guard case .feed(let feedID) = sidebarSelection else {
            return nil
        }

        return feedID
    }

    // SQLite-Identität: ausgewählter Feed als Sidebar-Snapshot (String-ID)
    // statt als SwiftData-`Feed`. Wird für FeedCommandActions und den
    // Spalten-2-Titel verwendet.
    private var selectedFeed: FeedSidebarSnapshot? {
        guard let feedID = selectedFeedID else {
            return nil
        }

        return feedSnapshots.first { $0.id == feedID }
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

    private var selectedSmartFolder: SQLiteSmartFolderSnapshot? {
        guard case .smartFolder(let smartFolderID) = sidebarSelection,
              let database = feedivoDatabase
        else {
            return nil
        }

        return (try? SQLiteSmartFolderStore(database: database).sidebarSnapshots())?
            .first { $0.id == smartFolderID }
    }

    private func selectDefaultSmartFolderIfNeeded() {
        guard sidebarSelection == nil || selectedSmartFilter != nil else {
            return
        }

        guard let database = feedivoDatabase,
              let defaultFolder = (try? SQLiteSmartFolderStore(database: database).sidebarSnapshots())?.first
        else {
            return
        }

        sidebarSelection = .smartFolder(defaultFolder.id)
    }

    private var unreadArticleCount: Int {
        AppIconBadgeService.unreadCount(in: feedSnapshots)
    }

    private var articleCommandActions: ArticleCommandActions {
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

    private func requestRuleCreation(from snapshot: ArticleReaderSnapshot) {
        ruleCreationRequest = RuleCreationRequest(snapshot: snapshot)
    }

    private func sqliteRulesForRuleCreation() -> [RuleRecord] {
        guard let database = feedivoDatabase else {
            return []
        }

        return (try? SQLiteRuleStore(database: database).rules()) ?? []
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

private struct RuleCreationRequest: Identifiable {
    let id = UUID()
    let seed: RuleWizardSeed

    init(snapshot: ArticleReaderSnapshot) {
        self.seed = RuleWizardSeed(snapshot: snapshot)
    }
}
