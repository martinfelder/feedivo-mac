import Foundation
import Testing
@testable import Feedivo

struct FeedivoAppSceneConfigurationTests {
    @Test func settingsSceneUsesSharedModelContainer() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = projectRoot.appendingPathComponent("Feedivo/App/FeedivoApp.swift")
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)

        let settingsScene = try #require(appSource.range(of: "Settings {"))
        let settingsSource = appSource[settingsScene.lowerBound...]

        #expect(settingsSource.contains(".modelContainer(modelContainer)"))
    }

    @Test func settingsSceneUsesOnlyNewSettingsView() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = projectRoot.appendingPathComponent("Feedivo/App/FeedivoApp.swift")
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)

        #expect(appSource.contains("Settings {"))
        #expect(appSource.contains("NewSettingsView()"))
        #expect(!appSource.contains("SettingsCommands()"))
        #expect(!appSource.contains("Einstellungen alt"))
        #expect(!appSource.contains("SettingsView.oldWindowID"))
    }

    @Test func startupTaskTrimsImageCacheToSelectedLimit() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = projectRoot.appendingPathComponent("Feedivo/App/FeedivoApp.swift")
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)

        #expect(appSource.contains("trimImageCacheToSelectedLimit()"))
        #expect(appSource.contains("ImageCacheService.shared.trimCache"))
        #expect(appSource.contains("ImageCacheSettings.currentLimitInBytes"))
    }

    @Test func appSharesFeedViewModelForVisibleAndAutomaticRefresh() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let schedulerSource = try source(at: "Feedivo/Services/BackgroundRefreshService.swift", projectRoot: projectRoot)

        #expect(appSource.contains("private let feedViewModel"))
        #expect(appSource.contains("ContentView(feedViewModel: feedViewModel, modelContainer: modelContainer)"))
        #expect(appSource.contains("feedViewModel: feedViewModel"))
        #expect(compact(contentSource).contains("refreshAllFeeds(feeds,modelContainer:modelContainer,sqliteDatabase:feedivoDatabase)"))
        #expect(contentSource.contains("refreshFeedsOnLaunchIfNeeded()"))
        #expect(schedulerSource.contains("feedViewModel: FeedViewModel"))
    }

    @Test func contentViewAnimiertLaufendenRefreshFortschrittNichtGlobal() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)

        #expect(!contentSource.contains("value: feedViewModel.operationProgress"))
        #expect(contentSource.contains("value: feedViewModel.recentRefreshStatus"))
    }

    @Test func appRegistersArticleWindowGroup() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)

        #expect(appSource.contains("WindowGroup(for: ArticleWindowRequest.self)"))
        #expect(appSource.contains("ArticleWindowView(request:"))
        #expect(appSource.contains(".defaultSize(width: 900, height: 720)"))
        #expect(appSource.contains(".modelContainer(modelContainer)"))
    }

    @Test func articleCommandsOpenArticleWindowWithCommandReturn() throws {
        let projectRoot = projectRootURL()
        let commandsSource = try source(at: "Feedivo/App/ArticleCommands.swift", projectRoot: projectRoot)
        let actionsSource = try source(at: "Feedivo/App/ArticleCommandActions.swift", projectRoot: projectRoot)

        #expect(actionsSource.contains("openInArticleWindow"))
        #expect(commandsSource.contains("L10n.articleOpenInWindowCommand"))
        #expect(commandsSource.contains(".keyboardShortcut(.return, modifiers: [.command])"))
        #expect(commandsSource.contains("articleCommandActions?.openInArticleWindow()"))
    }

    @Test func articleRowsOfferOpenInWindowContextAction() throws {
        let projectRoot = projectRootURL()
        let rowSource = try source(at: "Feedivo/Views/ArticleList/ArticleRowView.swift", projectRoot: projectRoot)
        let listSource = try source(at: "Feedivo/Views/ArticleList/ArticleListView.swift", projectRoot: projectRoot)

        #expect(rowSource.contains("onOpenInWindow"))
        #expect(rowSource.contains("L10n.articleOpenInWindowCommand"))
        #expect(listSource.contains("openArticleInWindow(article"))
    }

    @Test func articleWindowRestoreSettingDefaultsToOff() throws {
        let projectRoot = projectRootURL()
        let settingsSource = try source(at: "Feedivo/Views/Settings/SettingsView.swift", projectRoot: projectRoot)
        let restoreSettingsSource = try source(
            at: "Feedivo/Services/ArticleWindowSettings.swift",
            projectRoot: projectRoot
        )

        #expect(restoreSettingsSource.contains("restoreOpenArticleWindowsOnLaunchKey"))
        #expect(restoreSettingsSource.contains("defaultRestoreOpenArticleWindowsOnLaunch = false"))
        #expect(settingsSource.contains("ArticleWindowSettings.restoreOpenArticleWindowsOnLaunchKey"))
        #expect(settingsSource.contains("L10n.settingsRestoreArticleWindowsTitle"))
    }

    @Test func articleWindowUpdatesStoredArticleIDAfterNavigation() throws {
        let projectRoot = projectRootURL()
        let articleWindowSource = try source(at: "Feedivo/Views/Reader/ArticleWindowView.swift", projectRoot: projectRoot)

        #expect(articleWindowSource.contains(".onChange(of: selectedArticleID)"))
        #expect(articleWindowSource.contains("ArticleWindowSettings.forgetOpenArticleID(oldValue)"))
        #expect(articleWindowSource.contains("ArticleWindowSettings.rememberOpenArticleID(newValue)"))
        #expect(articleWindowSource.contains("ArticleWindowSettings.forgetOpenArticleID(selectedArticleID)"))
    }

    @Test func readerScrollViewsResetWhenArticleChanges() throws {
        let projectRoot = projectRootURL()
        let readerSource = try source(at: "Feedivo/Views/Reader/ReaderView.swift", projectRoot: projectRoot)
        let articleIdentityCount = readerSource.components(separatedBy: ".id(article.persistentModelID)").count - 1

        #expect(articleIdentityCount >= 2)
    }

    @Test func readerMetadataChipsExposeInlineTagEditor() throws {
        let projectRoot = projectRootURL()
        let readerSource = try source(at: "Feedivo/Views/Reader/ReaderView.swift", projectRoot: projectRoot)

        #expect(readerSource.contains("@Query(sort: \\Tag.name) private var allTags"))
        #expect(readerSource.contains("isTagEditorPopoverPresented"))
        #expect(readerSource.contains(".popover(isPresented: $isTagEditorPopoverPresented)"))
        #expect(readerSource.contains("private var readerMetadataChipHeight: CGFloat"))
        #expect(readerSource.contains(".frame(width: readerMetadataChipHeight, height: readerMetadataChipHeight)"))
        #expect(readerSource.contains(".fill(tagColor)"))
        #expect(readerSource.contains("ArticleMetadataEditor.addTag"))
        #expect(readerSource.contains("ArticleMetadataEditor.removeTag"))
        #expect(readerSource.contains("ColorSwatchPicker(selection: $newTagColorHex)"))
    }

    @Test func articleListReaderPrefetchBleibtLeichtgewichtig() throws {
        let projectRoot = projectRootURL()
        let listSource = try source(at: "Feedivo/Views/ArticleList/ArticleListView.swift", projectRoot: projectRoot)

        #expect(listSource.contains("prefetchReaderFields"))
        #expect(!listSource.contains("_ = article.content"))
        #expect(!listSource.contains("_ = article.offlineContent"))
        #expect(!listSource.contains("_ = article.feed?.title"))
        #expect(!listSource.contains("await ImageCacheService.shared.image"))
    }

    @Test func articleRowsLesenFeednamenNichtUeberRelationship() throws {
        let projectRoot = projectRootURL()
        let rowSource = try source(at: "Feedivo/Views/ArticleList/ArticleRowView.swift", projectRoot: projectRoot)
        let listSource = try source(at: "Feedivo/Views/ArticleList/ArticleListView.swift", projectRoot: projectRoot)

        #expect(rowSource.contains("let snapshot: ArticleListItemSnapshot"))
        #expect(rowSource.contains("snapshot.feedTitle"))
        #expect(!rowSource.contains("let article: Article"))
        #expect(!rowSource.contains("article.feed?.title"))
        #expect(listSource.contains("feedTitleByFeedID"))
        #expect(listSource.contains("snapshot: ArticleListItemSnapshot("))
        #expect(listSource.contains("feedTitle: feedTitle(for: article, in: feedTitleByFeedID)"))
    }

    @Test func readerRendertContentBloeckeLazy() throws {
        let projectRoot = projectRootURL()
        let readerSource = try source(at: "Feedivo/Views/Reader/ReaderView.swift", projectRoot: projectRoot)

        #expect(readerSource.contains("LazyVStack(alignment: .leading, spacing: contentBlockSpacing)"))
        #expect(!readerSource.contains("\n            VStack(alignment: .leading, spacing: contentBlockSpacing)"))
    }

    @Test func readerLaedtVolltextUeberBackgroundLoader() throws {
        let projectRoot = projectRootURL()
        let readerSource = try source(at: "Feedivo/Views/Reader/ReaderView.swift", projectRoot: projectRoot)

        #expect(readerSource.contains("ReaderArticleContentLoader.loadInput"))
        #expect(!readerSource.contains("ReaderArticleInput.make(from: article)"))
    }

    @Test func readerCacheKeySpeichertKeineVolltexte() throws {
        let projectRoot = projectRootURL()
        let preparedSource = try source(at: "Feedivo/Views/Reader/ReaderPreparedArticle.swift", projectRoot: projectRoot)
        let keyStart = try #require(preparedSource.range(of: "struct ReaderArticleCacheKey"))
        let cacheStart = try #require(preparedSource.range(of: "@MainActor\nfinal class ReaderPreparedArticleCache"))
        let cacheKeySource = preparedSource[keyStart.lowerBound ..< cacheStart.lowerBound]

        #expect(cacheKeySource.contains("contentFingerprint"))
        #expect(cacheKeySource.contains("offlineContentFingerprint"))
        #expect(!cacheKeySource.contains("let content: String?"))
        #expect(!cacheKeySource.contains("let offlineContent: String?"))
    }

    @Test func readerDetailbilderNutzenZielgroesse() throws {
        let projectRoot = projectRootURL()
        let readerSource = try source(at: "Feedivo/Views/Reader/ReaderView.swift", projectRoot: projectRoot)

        #expect(readerSource.contains("private var readerImageTargetPixelSize: CGSize"))
        #expect(readerSource.contains("CachedRemoteImageView(url: url, targetPixelSize: readerImageTargetPixelSize)"))
    }

    @Test func lesestatusZaehlerVermeidetDirektenFeedRelationshipFault() throws {
        let projectRoot = projectRootURL()
        let viewModelSource = try source(at: "Feedivo/ViewModels/ArticleViewModel.swift", projectRoot: projectRoot)
        let methodStart = try #require(viewModelSource.range(of: "private func feed(for article: Article"))
        let methodEnd = try #require(viewModelSource.range(of: "@MainActor\n    func synchronizeUnreadCounts"))
        let methodSource = viewModelSource[methodStart.lowerBound ..< methodEnd.lowerBound]

        #expect(methodSource.contains("guard let feedID = article.feedID else"))
        #expect(!methodSource.contains("if let feed = article.feed"))
    }

    @Test func artikelAuswahlVerzoegertFeedZaehlerBisZumDebouncedFlush() throws {
        let projectRoot = projectRootURL()
        let articleListSource = try source(at: "Feedivo/Views/ArticleList/ArticleListView.swift", projectRoot: projectRoot)
        let compactArticleListSource = articleListSource.filter { !$0.isWhitespace }

        #expect(compactArticleListSource.contains("updatesUnreadCount:false"))
        #expect(compactArticleListSource.contains("rememberPendingUnreadCountSyncFeedID(for:"))
        #expect(compactArticleListSource.contains("viewModel.synchronizeUnreadCounts(forFeedIDs:"))
    }

    @Test func nachladeZeileWechseltIdentitaetMitFetchLimit() throws {
        let projectRoot = projectRootURL()
        let articleListSource = try source(at: "Feedivo/Views/ArticleList/ArticleListView.swift", projectRoot: projectRoot)
        let compactArticleListSource = articleListSource.filter { !$0.isWhitespace }

        #expect(compactArticleListSource.contains("loadMoreArticlesTriggerID:fetchLimit"))
        #expect(compactArticleListSource.contains(".id(loadMoreArticlesTriggerID)"))
    }

    @Test func appUsesCloudSyncSettingsForModelContainer() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)

        #expect(appSource.contains("CloudSyncSettings.isEnabled()"))
        #expect(appSource.contains("FeedivoModelContainerFactory.makePersistentContainer"))
        #expect(appSource.contains("FeedivoModelContainerFactory.makeInMemoryFallbackContainer"))
        #expect(appSource.contains("databaseLoadState.isCloudSyncEnabledAtLaunch"))
    }

    @Test func settingsSceneReceivesDatabaseLoadState() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)

        let settingsScene = try #require(appSource.range(of: "Settings {"))
        let settingsSource = appSource[settingsScene.lowerBound...]

        #expect(settingsSource.contains(".environment(databaseLoadState)"))
    }

    @Test func entitlementsDeclareCloudKitContainer() throws {
        let projectRoot = projectRootURL()
        let entitlementsSource = try source(at: "Feedivo/Feedivo.entitlements", projectRoot: projectRoot)

        #expect(entitlementsSource.contains("com.apple.developer.icloud-services"))
        #expect(entitlementsSource.contains("<string>CloudKit</string>"))
        #expect(entitlementsSource.contains("com.apple.developer.icloud-container-identifiers"))
        #expect(entitlementsSource.contains("<string>iCloud.ch.martin.Feedivo</string>"))
    }

    @Test func syncSettingsExposeBetaToggleAndRestartHint() throws {
        let projectRoot = projectRootURL()
        let settingsSource = try source(at: "Feedivo/Views/Settings/SettingsView.swift", projectRoot: projectRoot)

        #expect(settingsSource.contains("@Environment(DatabaseLoadState.self)"))
        #expect(settingsSource.contains("@AppStorage(CloudSyncSettings.isEnabledKey)"))
        #expect(settingsSource.contains("L10n.settingsSyncBetaTitle"))
        #expect(settingsSource.contains("L10n.settingsSyncRestartHint"))
        #expect(settingsSource.contains("CloudSyncSettings.statusLocalizationKey"))
        #expect(settingsSource.contains("L10n.settingsSyncDatabaseTitle"))
        #expect(settingsSource.contains("Toggle(\"\", isOn: $cloudSyncIsEnabled)"))
    }

    @Test func cloudKitSyncedRelationshipsAreOptional() throws {
        let projectRoot = projectRootURL()

        let expectedRelationships: [(path: String, declaration: String)] = [
            ("Feedivo/Models/Article.swift", "var tags: [Tag]?"),
            ("Feedivo/Models/Feed.swift", "var articles: [Article]?"),
            ("Feedivo/Models/Feed.swift", "var logEntries: [FeedLogEntry]?"),
            ("Feedivo/Models/Feed.swift", "var tags: [Tag]?"),
            ("Feedivo/Models/Rule.swift", "var conditions: [RuleCondition]?"),
            ("Feedivo/Models/SmartFolder.swift", "var conditions: [SmartFolderCondition]?"),
            ("Feedivo/Models/Tag.swift", "var articles: [Article]?"),
            ("Feedivo/Models/Tag.swift", "var feeds: [Feed]?"),
            ("Feedivo/Models/Tag.swift", "var rules: [Rule]?")
        ]

        for expectedRelationship in expectedRelationships {
            let modelSource = try source(at: expectedRelationship.path, projectRoot: projectRoot)
            #expect(modelSource.contains(expectedRelationship.declaration))
        }
    }

    @Test func appOpensAndInjectsSQLiteDatabase() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)

        #expect(appSource.contains("private let feedivoDatabase"))
        #expect(appSource.contains("FeedivoDatabase.open"))
        #expect(appSource.contains(".environment(\\.feedivoDatabase, feedivoDatabase)"))
    }

    @Test func appStartBackfillSpiegeltFeedTagsNachSQLite() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)
        let compactAppSource = compact(appSource)

        #expect(compactAppSource.contains("FeedTagBackfillService.backfillFeedTags(in:modelContainer.mainContext,database:feedivoDatabase)"))
    }

    @Test func sqliteDatabaseLocationUsesApplicationSupport() throws {
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/feedivo-tests/Application Support")

        let databaseURL = FeedivoDatabaseLocation.databaseURL(
            applicationSupportDirectory: applicationSupportURL,
            bundleIdentifier: "ch.martin.FeedivoTests"
        )

        #expect(databaseURL.pathComponents.suffix(3) == ["ch.martin.FeedivoTests", "Feedivo", "feedivo.sqlite"])
    }

    @Test func contentViewHaeltSeparateSQLiteArtikelAuswahl() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)

        #expect(contentSource.contains("@State private var selectedSQLiteArticleID: String?"))
        #expect(contentSource.contains("@State private var sqliteArticleNavigationState = SQLiteArticleNavigationState.empty"))
    }

    @Test func contentViewNutztSQLiteFeedArticleListFuerSelectedFeed() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)

        #expect(contentSource.contains("SQLiteFeedArticleListView("))
        #expect(contentSource.contains("selectedArticleID: $selectedSQLiteArticleID"))
        #expect(contentSource.contains("navigationState: $sqliteArticleNavigationState"))
    }

    @Test func contentViewNutztSQLiteFeedArticleListFuerSelectedTag() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let compactContentSource = compact(contentSource)

        #expect(compactContentSource.contains("SQLiteFeedArticleListView(tag:tag,selectedArticleID:$selectedSQLiteArticleID,navigationState:$sqliteArticleNavigationState)"))
        #expect(!compactContentSource.contains("ArticleListView(tag:tag,selectedArticle:$selectedArticle"))
    }

    @Test func contentViewNutztSQLiteReaderFuerSQLiteAuswahl() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)

        #expect(contentSource.contains("if let selectedSQLiteArticleID"))
        #expect(contentSource.contains("SQLiteReaderView("))
        #expect(contentSource.contains("articleID: selectedSQLiteArticleID"))
    }

    @Test func contentViewUebergibtSQLiteDatabaseAnFeedRefreshes() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let compactContentSource = compact(contentSource)

        #expect(contentSource.contains("@Environment(\\.feedivoDatabase) private var feedivoDatabase"))
        #expect(compactContentSource.contains("refreshFeed(selectedFeed,context:modelContext,sqliteDatabase:feedivoDatabase)"))
        #expect(compactContentSource.contains("refreshAllFeeds(feeds,modelContainer:modelContainer,sqliteDatabase:feedivoDatabase)"))
        #expect(compactContentSource.contains("refreshAllFeeds(feeds,context:modelContext,sqliteDatabase:feedivoDatabase)"))
    }

    @Test func addFeedSheetUebergibtSQLiteDatabaseAnFeedViewModel() throws {
        let projectRoot = projectRootURL()
        let sidebarSource = try source(at: "Feedivo/Views/Sidebar/SidebarView.swift", projectRoot: projectRoot)
        let compactSidebarSource = compact(sidebarSource)

        #expect(sidebarSource.contains("@Environment(\\.feedivoDatabase) private var feedivoDatabase"))
        #expect(compactSidebarSource.contains("viewModel.addFeed(urlString:urlString,context:modelContext,sqliteDatabase:feedivoDatabase)"))
    }

    @Test func sidebarViewLaedtSQLiteSidebarState() throws {
        let projectRoot = projectRootURL()
        let sidebarSource = try source(at: "Feedivo/Views/Sidebar/SidebarView.swift", projectRoot: projectRoot)
        let compactSidebarSource = compact(sidebarSource)

        #expect(sidebarSource.contains("@Environment(\\.feedivoDatabase) private var feedivoDatabase"))
        #expect(sidebarSource.contains("@AppStorage(SQLiteDataInvalidation.statusVersionKey)"))
        #expect(sidebarSource.contains("@State private var sqliteSidebarState = SQLiteSidebarState()"))
        #expect(compactSidebarSource.contains("sqliteSidebarState.load(database:feedivoDatabase,showsReadFeeds:showsReadFeedsInSidebar)"))
        #expect(compactSidebarSource.contains("sqliteSidebarState.visibleFeeds(from:feeds,showsReadFeeds:showsReadFeedsInSidebar)"))
        #expect(compactSidebarSource.contains("sqliteSnapshot:sqliteSidebarState.snapshot(for:feed)"))
        #expect(compactSidebarSource.contains("\\(sqliteStatusVersion)#\\(directTagVersion)#\\(showsReadFeedsInSidebar)#\\(feedIDs)#\\(tagIDs)"))
    }

    @Test func sidebarTagBadgesNutzenSQLiteSnapshots() throws {
        let projectRoot = projectRootURL()
        let sidebarSource = try source(at: "Feedivo/Views/Sidebar/SidebarView.swift", projectRoot: projectRoot)
        let compactSidebarSource = compact(sidebarSource)

        #expect(compactSidebarSource.contains("sqliteSidebarState.tagSnapshot(id:tag.id.uuidString)?.articleCount"))
        #expect(!sidebarSource.contains("SidebarTagCount.articleCount(for: tag, context: modelContext)"))
    }

    @Test func feedRowViewBevorzugtSQLiteSnapshotWerte() throws {
        let projectRoot = projectRootURL()
        let rowSource = try source(at: "Feedivo/Views/Sidebar/FeedRowView.swift", projectRoot: projectRoot)

        #expect(rowSource.contains("let sqliteSnapshot: FeedSidebarSnapshot?"))
        #expect(rowSource.contains("sqliteSnapshot?.unreadCount"))
        #expect(rowSource.contains("sqliteSnapshot?.title"))
        #expect(rowSource.contains("sqliteSnapshot?.faviconURL"))
    }

    @Test func feedPropertiesViewSpiegeltFeedTagsNachSQLite() throws {
        let projectRoot = projectRootURL()
        let source = try source(at: "Feedivo/Views/Sidebar/FeedPropertiesView.swift", projectRoot: projectRoot)

        #expect(source.contains("@Environment(\\.feedivoDatabase) private var feedivoDatabase"))
        #expect(source.contains("let store = TagStore(database: database)"))
        #expect(source.contains("try store.save"))
        #expect(source.contains("assignTag(tagID: tag.id.uuidString, toFeedID: feed.id.uuidString"))
        #expect(source.contains("try TagStore(database: database).removeTag"))
        #expect(source.contains("tagID: tag.id.uuidString"))
        #expect(source.contains("fromFeedID: feed.id.uuidString"))
        #expect(source.contains("SidebarBadgeInvalidation.bumpDirectTagVersion()"))
    }

    private func projectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(at relativePath: String, projectRoot: URL) throws -> String {
        let sourceURL = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func compact(_ source: String) -> String {
        source.filter { !$0.isWhitespace }
    }
}
