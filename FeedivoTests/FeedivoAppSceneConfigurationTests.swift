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

        #expect(!settingsSource.contains(".modelContainer(modelContainer)"))
    }

    @Test func appStartWirdOhneModelContainerGestartet() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = projectRoot.appendingPathComponent("Feedivo/App/FeedivoApp.swift")
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)

        #expect(!appSource.contains("ModelContainer"))
        #expect(!appSource.contains("modelContainer"))
        #expect(!appSource.contains("FeedivoModelContainerFactory"))
        #expect(appSource.contains("FeedivoDatabase.open(at: FeedivoDatabaseLocation.databaseURL())"))
        #expect(appSource.contains("ContentView(feedViewModel: feedViewModel)"))
    }

    @Test func settingsSceneUsesOnlySettingsView() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = projectRoot.appendingPathComponent("Feedivo/App/FeedivoApp.swift")
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)

        #expect(appSource.contains("Settings {"))
        #expect(appSource.contains("SettingsView()"))
        #expect(!appSource.contains("SettingsCommands()"))
        #expect(!appSource.contains("Einstellungen alt"))
        #expect(!appSource.contains("SettingsView.oldWindowID"))
    }

    @Test func appRegistriertEigenesOrganizerFensterFuerVerwaltungsaufgaben() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)
        let organizerSource = try source(at: "Feedivo/Views/Organizer/OrganizerWindowView.swift", projectRoot: projectRoot)
        let commandSource = try source(at: "Feedivo/App/FeedCommands.swift", projectRoot: projectRoot)

        #expect(appSource.contains("Window(OrganizerWindowView.windowTitle, id: OrganizerWindowView.windowID)"))
        #expect(appSource.contains("OrganizerWindowView()"))
        #expect(appSource.contains(".defaultSize(width: 920, height: 620)"))
        #expect(commandSource.contains("@Environment(\\.openWindow)"))
        #expect(commandSource.contains("openWindow(id: OrganizerWindowView.windowID)"))
        #expect(organizerSource.contains("FeedManagementOrganizerView()"))
        #expect(organizerSource.contains("TagManagerView(showsDoneButton: false)"))
        #expect(organizerSource.contains("SmartFolderSettingsView()"))
        #expect(organizerSource.contains("RuleSettingsView()"))
    }

    @Test func settingsFensterBleibtAufGlobalePreferencesReduziert() throws {
        let projectRoot = projectRootURL()
        let settingsSource = try source(at: "Feedivo/Views/Settings/SettingsView.swift", projectRoot: projectRoot)
        let compactSettingsSource = compact(settingsSource)

        #expect(settingsSource.contains("case general"))
        #expect(settingsSource.contains("case appearance"))
        #expect(settingsSource.contains("case notifications"))
        #expect(settingsSource.contains("case refresh"))
        #expect(settingsSource.contains("case cleanup"))
        #expect(settingsSource.contains("case sync"))
        #expect(settingsSource.contains("case about"))
        #expect(!settingsSource.contains("case feeds"))
        #expect(!settingsSource.contains("case folders"))
        #expect(!settingsSource.contains("case rules"))
        #expect(!settingsSource.contains("FeedManagementSettingsView()"))
        #expect(!settingsSource.contains("SmartFolderSettingsView()"))
        #expect(!settingsSource.contains("RuleSettingsView()"))
        #expect(compactSettingsSource.contains("staticletwindowWidth:CGFloat=680"))
        #expect(compactSettingsSource.contains("staticletcontentWidth:CGFloat=520"))
    }

    @Test func feedRenameViewMutiertSQLiteStattSwiftData() throws {
        let projectRoot = projectRootURL()
        let renameSource = try source(at: "Feedivo/Views/Sidebar/FeedRenameView.swift", projectRoot: projectRoot)

        #expect(renameSource.contains("@Environment(\\.feedivoDatabase)"))
        #expect(renameSource.contains("FeedStore(database: database).renameFeed"))
        #expect(renameSource.contains("FeedStore(database: database).restoreOriginalTitle"))
        #expect(!renameSource.contains("@Environment(\\.modelContext)"))
        #expect(!renameSource.contains("FeedViewModel()"))
        #expect(!renameSource.contains("viewModel.renameFeed"))
    }

    @Test func feedPropertiesViewMutiertFeedVerwaltungSQLiteFirst() throws {
        let projectRoot = projectRootURL()
        let propertiesSource = try source(at: "Feedivo/Views/Sidebar/FeedPropertiesView.swift", projectRoot: projectRoot)

        #expect(propertiesSource.contains("@Environment(\\.feedivoDatabase)"))
        #expect(propertiesSource.contains("FeedStore(database: database).updateRefreshInterval"))
        #expect(propertiesSource.contains("FeedStore(database: database).updateFolderName"))
        #expect(propertiesSource.contains("FeedStore(database: database).updateNotificationEnabled"))
        #expect(propertiesSource.contains("FeedStore(database: database).updateRetentionSettings"))
        #expect(propertiesSource.contains("TagStore(database: database).tags(feedID:"))
        #expect(propertiesSource.contains("TagStore(database: database).assignTag"))
        #expect(propertiesSource.contains("TagStore(database: database).removeTag"))
        #expect(!propertiesSource.contains("@Query(sort: \\Tag.name)"))
        #expect(!propertiesSource.contains("TagViewModel()"))
        #expect(!propertiesSource.contains("modelContext.save()"))
    }

    @Test func feedManagementOrganizerViewListetSQLiteFeedsUndLoeschtMitSwiftDataBridgeCleanup() throws {
        let projectRoot = projectRootURL()
        let organizerSource = try source(at: "Feedivo/Views/Organizer/FeedManagementOrganizerView.swift", projectRoot: projectRoot)
        let stateSource = try source(at: "Feedivo/Views/Settings/FeedManagementSettingsState.swift", projectRoot: projectRoot)

        let viewStart = try #require(organizerSource.range(of: "struct FeedManagementOrganizerView"))
        let rowStart = try #require(organizerSource.range(of: "private struct FeedManagementOrganizerRow"))
        let viewSource = organizerSource[viewStart.lowerBound ..< rowStart.lowerBound]
        let deleteStart = try #require(viewSource.range(of: "private func deleteSelectedFeeds()"))
        let loadStart = try #require(viewSource.range(of: "private func loadFeeds()"))
        let deleteSource = viewSource[deleteStart.lowerBound ..< loadStart.lowerBound]

        #expect(viewSource.contains("@State private var feeds: [FeedRecord]"))
        #expect(viewSource.contains("FeedStore(database: database).feeds()"))
        #expect(!viewSource.contains("@Environment(\\.modelContext)"))
        #expect(!viewSource.contains("FeedViewModel()"))
        #expect(!deleteSource.contains("feedViewModel.deleteFeed("))
        #expect(viewSource.contains("OPMLExportSheet(opmlFeeds:"))
        #expect(!viewSource.contains("@Query(sort: \\Feed.title)"))
        #expect(deleteSource.contains("FeedStore(database: database).delete(id: feed.id)"))
        #expect(stateSource.contains("filteredFeeds(_ feeds: [FeedRecord]"))
        #expect(stateSource.contains("selectedFeedIDs: inout Set<String>"))
    }

    @Test func sqliteArticleListBleibtOptischNahAnMainArticleList() throws {
        let projectRoot = projectRootURL()
        let listSource = try source(at: "Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift", projectRoot: projectRoot)

        #expect(listSource.contains("List(selection: $selectedArticleID)"))
        #expect(listSource.contains(".tag(row.id)"))
        #expect(listSource.contains(".toolbar"))
        #expect(listSource.contains("markReadMenu(visibleRows:"))
        #expect(listSource.contains("filterMenu"))
        #expect(listSource.contains("sortMenu"))
        #expect(!listSource.contains("ScrollViewReader"))
    }

    @Test func sqliteArtikellisteZeigtFeedTitelMitUngelesenZaehler() throws {
        let projectRoot = projectRootURL()
        let listSource = try source(at: "Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift", projectRoot: projectRoot)
        let compactListSource = compact(listSource)

        #expect(listSource.contains("@Environment(\\.interfaceTextSize) private var interfaceTextSize"))
        #expect(listSource.contains("private var articleListHeader: some View"))
        #expect(compactListSource.contains("Text(navigationTitle)"))
        #expect(compactListSource.contains("Text(unreadArticleCountText)"))
        #expect(compactListSource.contains("interfaceTextSize.font(size:13,weight:.medium)"))
        #expect(compactListSource.contains("interfaceTextSize.font(size:13)"))
        #expect(compactListSource.contains("privatevarunreadArticleCount:Int{state.totalUnreadCount}"))
        #expect(compactListSource.contains(".navigationTitle(\"\")"))
    }

    @Test func sqliteReaderBleibtOptischNahAnMainReaderToolbar() throws {
        let projectRoot = projectRootURL()
        let readerSource = try source(at: "Feedivo/Views/Reader/SQLiteReaderView.swift", projectRoot: projectRoot)

        #expect(readerSource.contains("@AppStorage(ReaderDisplayMode.storageKey)"))
        #expect(readerSource.contains("Picker(L10n.readerDisplayModePicker"))
        #expect(readerSource.contains("readerAppearancePopover"))
        #expect(readerSource.contains("@Environment(\\.openWindow) private var openWindow"))
        #expect(readerSource.contains("openWindow(id: ArticleSearchWindowView.windowID)"))
        #expect(readerSource.contains("Image(systemName: \"magnifyingglass\")"))
        #expect(readerSource.contains("Image(systemName: \"safari\")"))
        #expect(readerSource.contains("Image(systemName: \"square.and.arrow.up\")"))
        #expect(readerSource.contains("Label(L10n.readerInspectorButton, systemImage: \"sidebar.right\")"))
        #expect(readerSource.contains("Label(L10n.articleCreateRuleCommand"))
        #expect(readerSource.contains("Label(L10n.articleCopyLinkCommand"))
    }

    @Test func artikelsucheIstNurNochReaderToolbarButtonZumSuchfenster() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let readerSource = try source(at: "Feedivo/Views/Reader/SQLiteReaderView.swift", projectRoot: projectRoot)
        let listSource = try source(at: "Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift", projectRoot: projectRoot)

        #expect(!contentSource.contains("ArticleSearchToolbarInstaller("))
        #expect(!contentSource.contains("struct ArticleSearchToolbarInstaller: NSViewRepresentable"))
        #expect(!contentSource.contains("NSSearchToolbarItem"))
        #expect(!contentSource.contains("NSToolbarDelegate"))
        #expect(!contentSource.contains("onSearchTextChanged:"))
        #expect(!contentSource.contains("ToolbarItem(placement: .primaryAction)"))
        #expect(!contentSource.contains("ToolbarItem(placement: .principal)"))
        #expect(!contentSource.contains("articleSearchToolbarField"))
        #expect(!contentSource.contains("private var hasActiveArticleList: Bool"))
        #expect(!contentSource.contains("ArticleToolbarSearchField(text: $articleSearchText)"))
        #expect(!contentSource.contains("struct ArticleToolbarSearchField: NSViewRepresentable"))
        #expect(!contentSource.contains("TextField(L10n.articleSearchPlaceholder, text: $articleSearchText)"))
        #expect(!contentSource.contains("isEnabled: hasActiveArticleList"))
        #expect(!contentSource.contains("articleSearchSection"))
        #expect(!contentSource.contains("@State private var articleSearchText"))
        #expect(contentSource.contains("searchText: .constant(\"\")"))
        #expect(!readerSource.contains("articleSearchText"))
        #expect(!readerSource.contains("toolbarSearchField"))
        #expect(readerSource.contains("openWindow(id: ArticleSearchWindowView.windowID)"))
        #expect(readerSource.contains("Image(systemName: \"magnifyingglass\")"))
        #expect(listSource.contains("@Binding var searchText: String"))
    }

    @Test func produktiverArtikelInspectorPortiertLegacyLayoutOhneSwiftData() throws {
        let projectRoot = projectRootURL()
        let inspectorSource = try source(at: "Feedivo/Views/Reader/ArticleMetadataInspectorView.swift", projectRoot: projectRoot)
        let compactInspectorSource = compact(inspectorSource)

        #expect(!inspectorSource.contains("import SwiftData"))
        #expect(!inspectorSource.contains("@Environment(\\.modelContext)"))
        #expect(!inspectorSource.contains("@Query"))
        #expect(inspectorSource.contains("struct ArticleMetadataInspectorView"))
        #expect(compactInspectorSource.contains("primaryActionSection"))
        #expect(compactInspectorSource.contains("feedFolderSection"))
        #expect(compactInspectorSource.contains("contextSection"))
        #expect(compactInspectorSource.contains("sourceSection"))
        #expect(compactInspectorSource.contains("FeedStore(database:database).updateFolderName"))
        #expect(compactInspectorSource.contains("TagStore(database:database).assignTag"))
        #expect(compactInspectorSource.contains("removeTag(tagID:tag.id,fromArticleID:currentSnapshot.id)"))
    }

    @Test func offlineArtikelKopienSindNichtMehrImProduktivenUIPfadVerdrahtet() throws {
        let projectRoot = projectRootURL()
        let settingsSource = try source(at: "Feedivo/Views/Settings/SettingsView.swift", projectRoot: projectRoot)
        let sqliteReaderSource = try source(at: "Feedivo/Views/Reader/SQLiteReaderView.swift", projectRoot: projectRoot)
        let rowSource = try source(at: "Feedivo/Views/ArticleList/ArticleRowView.swift", projectRoot: projectRoot)
        let listSource = try source(at: "Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift", projectRoot: projectRoot)
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let preparedSource = try source(at: "Feedivo/Views/Reader/ReaderPreparedArticle.swift", projectRoot: projectRoot)

        #expect(!settingsSource.contains("case offline"))
        #expect(!settingsSource.contains("NewOfflineSettingsView"))
        #expect(!settingsSource.contains("OfflineArticleStorageSummary"))
        #expect(!sqliteReaderSource.contains("SQLiteOfflineDownloadService"))
        #expect(!sqliteReaderSource.contains("toggleOffline"))
        #expect(!rowSource.contains("onSaveOrRemoveOffline"))
        #expect(!rowSource.contains("offlineIndicator"))
        #expect(!listSource.contains("SQLiteOfflineDownloadService"))
        #expect(!listSource.contains("saveOrRemoveOffline"))
        #expect(!contentSource.contains("automaticallySaveStarredArticles"))
        #expect(!preparedSource.contains("offlineContent"))
    }

    @Test func sqliteReaderVerdrahtetRegelErstellenMitRuleWizard() throws {
        let projectRoot = projectRootURL()
        let readerSource = try source(at: "Feedivo/Views/Reader/SQLiteReaderView.swift", projectRoot: projectRoot)
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let compactReaderSource = compact(readerSource)
        let compactContentSource = compact(contentSource)

        #expect(readerSource.contains("let onCreateRule: (ArticleReaderSnapshot) -> Void"))
        #expect(compactReaderSource.contains("onCreateRule(snapshot)"))
        #expect(!compactReaderSource.contains(".disabled(true)Button{ }label:{Label(L10n.articleCreateRuleCommand"))
        #expect(contentSource.contains("@State private var ruleCreationRequest: RuleCreationRequest?"))
        #expect(compactContentSource.contains("onCreateRule:requestRuleCreation"))
        #expect(compactContentSource.contains(".sheet(item:$ruleCreationRequest)"))
        #expect(compactContentSource.contains("RuleWizardView(existingRules:"))
    }

    @Test func sqliteArtikellisteVerdrahtetRegelErstellenAusKontextmenue() throws {
        let projectRoot = projectRootURL()
        let listSource = try source(at: "Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift", projectRoot: projectRoot)
        let compactListSource = compact(listSource)

        #expect(listSource.contains("@State private var ruleCreationRequest: ArticleListRuleCreationRequest?"))
        #expect(compactListSource.contains(".sheet(item:$ruleCreationRequest)"))
        #expect(compactListSource.contains("RuleWizardView(existingRules:"))
        #expect(compactListSource.contains("onCreateRule:{requestRuleCreation(from:row)}"))
        #expect(!compactListSource.contains("onCreateRule:{},"))
    }

    @Test func sqliteArtikellisteVerdrahtetTagUndFensterKontextaktionen() throws {
        let projectRoot = projectRootURL()
        let listSource = try source(at: "Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift", projectRoot: projectRoot)
        let compactListSource = compact(listSource)

        #expect(listSource.contains("@Environment(\\.openWindow) private var openWindow"))
        #expect(listSource.contains("@State private var tagAssignmentRequest: ArticleTagAssignmentRequest?"))
        #expect(compactListSource.contains("ArticleTagAssignmentView(articleID:request.articleID,snapshotTags:[])"))
        #expect(compactListSource.contains("onRequestAssignTag:{tagAssignmentRequest=ArticleTagAssignmentRequest(articleID:row.id)}"))
        #expect(compactListSource.contains("openWindow(value:ArticleWindowRequest(articleID:articleID))"))
        #expect(!compactListSource.contains("onRequestAssignTag:{}"))
        #expect(!compactListSource.contains("onOpenInWindow:{}"))
    }

    @Test func sqliteArtikellisteMarkiertAuswahlBeimOeffnenAlsGelesen() throws {
        let projectRoot = projectRootURL()
        let listSource = try source(at: "Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift", projectRoot: projectRoot)
        let compactListSource = compact(listSource)

        #expect(listSource.contains("@AppStorage(\"markArticleReadOnSelection\")"))
        #expect(compactListSource.contains("markSelectedArticleReadIfNeeded()"))
        #expect(compactListSource.contains("state.markReadIfNeeded(articleID:articleID,database:database,isEnabled:markArticleReadOnSelection)"))
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
        #expect(appSource.contains("ContentView(feedViewModel: feedViewModel)"))
        #expect(appSource.contains("feedViewModel: feedViewModel"))
        #expect(compact(contentSource).contains("refreshAllFeeds(sqliteDatabase:database)"))
        #expect(contentSource.contains("refreshFeedsOnLaunchIfNeeded()"))
        #expect(schedulerSource.contains("feedViewModel: FeedViewModel"))
    }

    @Test func feedMenuActionsBleibenAlsSceneValueOhneFeedAuswahlVerfuegbar() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let commandSource = try source(at: "Feedivo/App/FeedCommands.swift", projectRoot: projectRoot)
        let actionSource = try source(at: "Feedivo/App/FeedCommandActions.swift", projectRoot: projectRoot)

        #expect(contentSource.contains(".focusedSceneValue("))
        #expect(contentSource.contains("\\.feedCommandActions"))
        #expect(commandSource.contains(".disabled(feedCommandActions?.canImportOPML != true)"))
        #expect(actionSource.contains("var canImportOPML: Bool"))
        #expect(actionSource.contains("true"))
    }

    @Test func contentViewPraesentiertFirstRunWizardNichtAutomatischBeiLeererApp() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let updateStart = try #require(contentSource.range(of: "private func updateFirstRunWizardPresentation()"))
        let completeStart = try #require(contentSource.range(of: "private func completeFirstRunWizard()"))
        let updateSource = contentSource[updateStart.lowerBound ..< completeStart.lowerBound]

        #expect(updateSource.contains("isShowingFirstRunWizard = false"))
        #expect(!updateSource.contains("isShowingFirstRunWizard = true"))
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
        #expect(!appSource.contains(".modelContainer(modelContainer)"))
    }

    @Test func produktiveSettingsRefreshEditorEntkoppelnVonModelContext() throws {
        let projectRoot = projectRootURL()
        let propertiesSource = try source(at: "Feedivo/Views/Sidebar/FeedPropertiesView.swift", projectRoot: projectRoot)
        let renameSource = try source(at: "Feedivo/Views/Sidebar/FeedRenameView.swift", projectRoot: projectRoot)
        let opmlReviewSource = try source(
            at: "Feedivo/Views/OPMLImport/OPMLImportReviewView.swift",
            projectRoot: projectRoot
        )
        let settingsSource = try source(at: "Feedivo/Views/Settings/SettingsView.swift", projectRoot: projectRoot)
        let refreshSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let listSource = try source(at: "Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift", projectRoot: projectRoot)
        let readerSource = try source(at: "Feedivo/Views/Reader/SQLiteReaderView.swift", projectRoot: projectRoot)

        #expect(!propertiesSource.contains("@Environment(\\.modelContext)"))
        #expect(!renameSource.contains("@Environment(\\.modelContext)"))
        #expect(!opmlReviewSource.contains("ModelContext"))
        #expect(!settingsSource.contains("@Environment(\\.modelContext)"))
        #expect(!settingsSource.contains("ModelContext("))
        #expect(!refreshSource.contains("ModelContext"))
        #expect(!listSource.contains("ModelContext"))
        #expect(!readerSource.contains("ModelContext"))
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
        #expect(articleWindowSource.contains("forgetArticleID(oldValue)"))
        #expect(articleWindowSource.contains("rememberSelectedArticleID()"))
        #expect(articleWindowSource.contains("forgetArticleID(selectedArticleID)"))
        #expect(articleWindowSource.contains("ArticleWindowSettings.forgetOpenArticleID(uuid)"))
        #expect(articleWindowSource.contains("ArticleWindowSettings.rememberOpenArticleID(uuid)"))
    }

    @Test func readerCacheKeySpeichertKeineVolltexte() throws {
        let projectRoot = projectRootURL()
        let preparedSource = try source(at: "Feedivo/Views/Reader/ReaderPreparedArticle.swift", projectRoot: projectRoot)
        let keyStart = try #require(preparedSource.range(of: "struct ReaderArticleCacheKey"))
        let cacheStart = try #require(preparedSource.range(of: "@MainActor\nfinal class ReaderPreparedArticleCache"))
        let cacheKeySource = preparedSource[keyStart.lowerBound ..< cacheStart.lowerBound]

        #expect(cacheKeySource.contains("contentFingerprint"))
        #expect(!cacheKeySource.contains("let content: String?"))
        #expect(!cacheKeySource.contains("offlineContent"))
        #expect(!cacheKeySource.contains("offlineState"))
    }

    @Test func produktiveTagOberflaechenNutzenSQLiteTagStore() throws {
        let projectRoot = projectRootURL()
        let searchSource = try source(at: "Feedivo/Views/ArticleList/ArticleSearchWindowView.swift", projectRoot: projectRoot)
        let inspectorSource = try source(at: "Feedivo/Views/Reader/ArticleMetadataInspectorView.swift", projectRoot: projectRoot)
        let sqliteReaderSource = try source(at: "Feedivo/Views/Reader/SQLiteReaderView.swift", projectRoot: projectRoot)
        let compactSearchSource = compact(searchSource)
        let compactInspectorSource = compact(inspectorSource)

        #expect(!searchSource.contains("@Query(sort: \\Tag.name)"))
        #expect(searchSource.contains("@State private var tags: [TagRecord] = []"))
        #expect(searchSource.contains("TagStore(database: database).tags()"))
        #expect(searchSource.contains("ForEach(tags) { tag in"))
        #expect(compactSearchSource.contains("Text(tag.name).tag(UUID(uuidString:tag.id))"))

        #expect(!inspectorSource.contains("@Query(sort: \\Tag.name)"))
        #expect(inspectorSource.contains("TagStore(database: database).tags()"))
        #expect(inspectorSource.contains("loadTags()"))
        #expect(compactInspectorSource.contains("TagStore(database:database).tags(articleID:snapshot.id)"))

        #expect(sqliteReaderSource.contains("ArticleMetadataInspectorView("))
        #expect(sqliteReaderSource.contains("TagStore(database: database)"))
    }

    @Test func appBlocksMainContentWhenSQLiteCannotBeOpened() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)

        #expect(appSource.contains("databaseOpenResult.errorDescription"))
        #expect(appSource.contains("if let initializationError = databaseLoadState.initializationError"))
        #expect(appSource.contains("ContentUnavailableView"))
        #expect(!appSource.contains("FeedivoModelContainerFactory.makePersistentContainer"))
        #expect(!appSource.contains("FeedivoModelContainerFactory.makeInMemoryFallbackContainer"))
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
        #expect(settingsSource.contains("L10n.settingsSyncUnavailableHint"))
        #expect(settingsSource.contains("CloudSyncSettings.statusLocalizationKey"))
        #expect(settingsSource.contains("L10n.settingsSyncDatabaseTitle"))
        #expect(settingsSource.contains("Toggle(\"\", isOn: $cloudSyncIsEnabled)"))
        #expect(settingsSource.contains(".disabled(!CloudSyncSettings.isAvailable)"))
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

        #expect(!compactAppSource.contains("FeedTagBackfillService.backfillFeedTags"))
    }

    @Test func opmlImportUndFirstRunPreviewNutzenSQLiteDatabase() throws {
        let projectRoot = projectRootURL()
        let opmlImportSource = try source(
            at: "Feedivo/Views/OPMLImport/OPMLImportReviewView.swift",
            projectRoot: projectRoot
        )
        let firstRunSource = try source(
            at: "Feedivo/Views/FirstRun/FirstRunWizardView.swift",
            projectRoot: projectRoot
        )

        #expect(opmlImportSource.contains("sqliteDatabase: feedivoDatabase"))
        #expect(firstRunSource.contains("sqliteDatabase: feedivoDatabase"))
    }

    @Test func feedViewModelLeitetAddUndImportAnSQLiteSubscriptionServiceWeiter() throws {
        let projectRoot = projectRootURL()
        let viewModelSource = try source(at: "Feedivo/ViewModels/FeedViewModel.swift", projectRoot: projectRoot)
        let compactViewModelSource = compact(viewModelSource)

        #expect(viewModelSource.contains("SQLiteFeedSubscriptionService"))
        #expect(compactViewModelSource.contains("service.importOPMLFeeds("))
        #expect(compactViewModelSource.contains("service.addFeed("))
        #expect(viewModelSource.contains("SQLiteDataInvalidation.bumpStatusVersion()"))
    }

    @Test func feedViewModelDelegiertOPMLPreviewAnSQLiteSubscriptionService() throws {
        // Phase-6-Schutz: Die OPML-Importvorschau darf nicht wieder inline im
        // `FeedViewModel` landen. Der ViewModel muss die Vorschau an den
        // `SQLiteFeedSubscriptionService.previewOPMLFeeds` delegieren und darf
        // selbst keinen `fetchFeed`-Abruf mehr für die Vorschau ausführen.
        let projectRoot = projectRootURL()
        let viewModelSource = try source(at: "Feedivo/ViewModels/FeedViewModel.swift", projectRoot: projectRoot)
        let serviceSource = try source(at: "Feedivo/Services/SQLiteFeedSubscriptionService.swift", projectRoot: projectRoot)

        #expect(viewModelSource.contains("service.previewOPMLFeeds("))
        #expect(serviceSource.contains("func previewOPMLFeeds("))
        // Die Vorschau-Typen liegen jetzt beim produzierenden Service, nicht mehr
        // im ViewModel.
        #expect(serviceSource.contains("struct OPMLImportPreviewRow"))
        #expect(serviceSource.contains("struct OPMLImportPreviewProgress"))
        #expect(!viewModelSource.contains("struct OPMLImportPreviewRow"))
        #expect(!viewModelSource.contains("struct OPMLImportPreviewProgress"))
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

    @Test func produktiveFeedArtikelNavigationBleibtSQLiteOnly() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let compactContentSource = compact(contentSource)

        #expect(!contentSource.contains("@Query(sort: \\Feed.title)"))
        #expect(!contentSource.contains("@State private var selectedArticle: Article?"))
        let hasLegacyArticleListViewCall = contentSource
            .components(separatedBy: .newlines)
            .contains { line in
                line.contains("ArticleListView(") &&
                !line.contains("SQLiteFeedArticleListView(")
            }
        #expect(!hasLegacyArticleListViewCall)
        #expect(contentSource.contains("@State private var feedSnapshots: [FeedSidebarSnapshot] = []"))
        #expect(contentSource.contains("FeedStore(database: database).sidebarFeeds()"))
        #expect(contentSource.contains("SQLiteFeedArticleListView("))
        #expect(contentSource.contains("SQLiteReaderView("))
        #expect(contentSource.contains("selectedSQLiteArticleID"))
        #expect(contentSource.contains("handleSQLiteArticleSnapshotChange"))
        #expect(compactContentSource.contains("refreshAllFeeds(sqliteDatabase:database)"))
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

        #expect(compactContentSource.contains("SQLiteFeedArticleListView(tagID:tagID,selectedArticleID:$selectedSQLiteArticleID,navigationState:$sqliteArticleNavigationState,searchText:.constant(\"\"))"))
        #expect(!compactContentSource.contains("ArticleListView(tag:tag,selectedArticle:$selectedArticle"))
    }

    @Test func contentViewNutztSQLiteFeedArticleListFuerSelectedSmartFilter() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let compactContentSource = compact(contentSource)

        #expect(compactContentSource.contains("SQLiteFeedArticleListView(smartFilter:smartFilter,selectedArticleID:$selectedSQLiteArticleID,navigationState:$sqliteArticleNavigationState,searchText:.constant(\"\"))"))
        #expect(!compactContentSource.contains("ArticleListView(smartFilter:smartFilter,selectedArticle:$selectedArticle"))
    }

    @Test func contentViewNutztSQLiteFeedArticleListFuerSelectedSmartFolder() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let compactContentSource = compact(contentSource)

        #expect(compactContentSource.contains("SQLiteFeedArticleListView(smartFolder:smartFolder,selectedArticleID:$selectedSQLiteArticleID,navigationState:$sqliteArticleNavigationState,searchText:.constant(\"\"))"))
        #expect(!compactContentSource.contains("ArticleListView(smartFolder:smartFolder,selectedArticle:$selectedArticle"))
    }

    @Test func smartFolderVerwaltungUndPreviewZaehlenUeberSQLite() throws {
        let projectRoot = projectRootURL()
        let settingsSource = try source(at: "Feedivo/Views/SmartFolders/SmartFolderSettingsView.swift", projectRoot: projectRoot)
        let editorSource = try source(at: "Feedivo/Views/SmartFolders/SmartFolderEditorView.swift", projectRoot: projectRoot)
        let compactSettingsSource = compact(settingsSource)
        let compactEditorSource = compact(editorSource)

        #expect(settingsSource.contains("@Environment(\\.feedivoDatabase) private var feedivoDatabase"))
        #expect(!settingsSource.contains("@Query(sort: \\Article.publishedAt"))
        #expect(!settingsSource.contains("SmartFolderEngine.matchingArticleCounts"))
        #expect(compactSettingsSource.contains("TimelineStore(database:database).count(scope:.smartFolder(snapshot),includeRead:true,includeHidden:"))
        #expect(editorSource.contains("@Environment(\\.feedivoDatabase) private var feedivoDatabase"))
        #expect(!editorSource.contains("@Query(sort: \\Article.publishedAt"))
        #expect(!editorSource.contains("SmartFolderEngine.matchingArticleCount"))
        #expect(compactEditorSource.contains("TimelineStore(database:database).count(scope:.smartFolder(snapshot),includeRead:true,includeHidden:"))
        #expect(compactEditorSource.contains("FeedFolderStore(database:database).folders()"))
    }

    @Test func smartFolderEditorVerwendetFeedFolderStoreFuerFeedFolderBedingung() throws {
        let projectRoot = projectRootURL()
        let editorSource = try source(at: "Feedivo/Views/SmartFolders/SmartFolderEditorView.swift", projectRoot: projectRoot)

        #expect(editorSource.contains("ForEach(feedFolders,"))
        #expect(editorSource.contains("normalizedFeedFolderBinding(for: draft)"))
        #expect(editorSource.contains("if feedFolders.isEmpty || normalizedFeedFolderValue(for: trimmedValue) == nil"))
        #expect(editorSource.contains("FeedFolderStore(database: database).folders()"))
    }

    @Test func regelPreviewUndRueckwirkendesAnwendenNutzenSQLite() throws {
        let projectRoot = projectRootURL()
        let settingsSource = try source(at: "Feedivo/Views/Rules/RuleSettingsView.swift", projectRoot: projectRoot)
        let wizardSource = try source(at: "Feedivo/Views/Rules/RuleWizardView.swift", projectRoot: projectRoot)
        let compactSettingsSource = compact(settingsSource)
        let compactWizardSource = compact(wizardSource)

        #expect(settingsSource.contains("@Environment(\\.feedivoDatabase) private var feedivoDatabase"))
        #expect(wizardSource.contains("@Environment(\\.feedivoDatabase) private var feedivoDatabase"))
        #expect(!settingsSource.contains("@Query private var articles"))
        #expect(!wizardSource.contains("@Query private var articles"))
        #expect(!settingsSource.contains("RuleSettingsFormatter.matchingCounts(for: orderedRules, articles: articles)"))
        #expect(!wizardSource.contains("RuleEngine.matchingArticleCount("))
        #expect(compactSettingsSource.contains("letsnapshots=trySQLiteRuleStore(database:database).ruleSnapshots()"))
        #expect(compactSettingsSource.contains("SQLiteRuleEvaluationStore(database:database).applyRulesToExistingArticles(snapshots)"))
        #expect(compactWizardSource.contains("SQLiteRuleEvaluationStore(database:database).matchingArticleCount(conditionDrafts:activeConditionDrafts,matchMode:activeMatchMode)"))
    }

    @Test func sqliteArticleListSearchLaedtUeberSQLiteState() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let listSource = try source(at: "Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift", projectRoot: projectRoot)
        let compactContentSource = compact(contentSource)
        let compactListSource = compact(listSource)

        #expect(!contentSource.contains("@State private var articleSearchText = \"\""))
        #expect(!contentSource.contains("ArticleSearchToolbarInstaller("))
        #expect(!contentSource.contains("onSearchTextChanged: updateArticleSearchTextFromToolbar"))
        #expect(compactContentSource.contains("searchText:.constant(\"\")"))
        #expect(listSource.contains("@Binding var searchText: String"))
        #expect(listSource.contains("@State private var debouncedSearchText = \"\""))
        #expect(compactListSource.contains(".task(id:searchText)"))
        #expect(compactListSource.contains("searchText:debouncedSearchText"))
        #expect(!listSource.contains("TextField(L10n.articleSearchPlaceholder"))
        #expect(!listSource.contains("ArticleSearchQuery("))
    }

    @Test func sqliteArtikelStatesNutzenArticleDatabaseFassade() throws {
        let projectRoot = projectRootURL()
        let listStateSource = try source(at: "Feedivo/ViewModels/SQLiteFeedArticleListState.swift", projectRoot: projectRoot)
        let readerStateSource = try source(at: "Feedivo/ViewModels/SQLiteReaderState.swift", projectRoot: projectRoot)

        #expect(listStateSource.contains("ArticleDatabase(database: database)"))
        #expect(listStateSource.contains("articleDatabase.timelineArticlesAsync("))
        #expect(!listStateSource.contains("TimelineStore(database: database).articles("))
        #expect(!listStateSource.contains("ArticleStatusStore(database: database)"))

        #expect(readerStateSource.contains("ArticleDatabase(database: database).readerArticle"))
        #expect(!readerStateSource.contains("ArticleStore(database: database).readerArticle"))
        #expect(!readerStateSource.contains("ArticleStatusStore(database: database)"))
    }

    @Test func articleSearchWindowLaedtErgebnisseAusSQLite() throws {
        let projectRoot = projectRootURL()
        let searchSource = try source(at: "Feedivo/Views/ArticleList/ArticleSearchWindowView.swift", projectRoot: projectRoot)
        let compactSearchSource = compact(searchSource)

        #expect(searchSource.contains("@Environment(\\.feedivoDatabase) private var database"))
        #expect(searchSource.contains("@State private var snapshots: [ArticleListSnapshot] = []"))
        #expect(compactSearchSource.contains("ArticleStore(database:database).searchArticles(state:committedState,limit:200)"))
        #expect(searchSource.contains("ArticleSearchResultRow(snapshot: snapshot)"))
        #expect(!searchSource.contains("@Query(sort: \\Article.publishedAt"))
        #expect(!searchSource.contains("private var articles: [Article]"))
        #expect(!searchSource.contains("filteredArticles(from: articles)"))
    }

    @Test func contentViewNutztSQLiteReaderFuerSQLiteAuswahl() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)

        #expect(contentSource.contains("if let selectedSQLiteArticleID"))
        #expect(contentSource.contains("SQLiteReaderView("))
        #expect(contentSource.contains("articleID: selectedSQLiteArticleID"))
    }

    @Test func contentViewVerdrahtetArtikelCommandsFuerSQLiteAuswahl() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let compactContentSource = compact(contentSource)

        #expect(contentSource.contains("@State private var selectedSQLiteArticleSnapshot: ArticleReaderSnapshot?"))
        #expect(compactContentSource.contains("canPerformActions:selectedSQLiteArticleSnapshot!=nil"))
        #expect(compactContentSource.contains("toggleReadTitle:selectedSQLiteArticleSnapshot?.isRead==true"))
        #expect(compactContentSource.contains("ArticleStatusStore(database:database).setRead"))
        #expect(compactContentSource.contains("ArticleStatusStore(database:database).setStarred"))
        #expect(compactContentSource.contains("ArticleStatusStore(database:database).setArchived"))
        #expect(compactContentSource.contains("openWindow(value:ArticleWindowRequest(articleID:articleID))"))
        #expect(compactContentSource.contains("ArticleExportSnapshot(sqliteSnapshot:snapshot,tagNames:tagNames)"))
    }

    @Test func contentViewHatKeineSwiftDataArtikelAuswahlMehr() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)

        #expect(!contentSource.contains("@State private var selectedArticle: Article?"))
        #expect(!contentSource.contains("@State private var articleNavigationState"))
        #expect(!contentSource.contains("@State private var articleViewModel"))
        #expect(!contentSource.contains("@State private var offlineDownloadService = OfflineDownloadService()"))
        #expect(!contentSource.contains("\n                ReaderView("))
        #expect(!contentSource.contains("swiftDataArticleCommandActions"))
        #expect(!contentSource.contains("requestExportArticle(_ article: Article)"))
        #expect(!contentSource.contains("archiveOrRemoveArchive(_ article: Article?)"))
    }

    @Test func swiftDataVerwaltungseditorenSindBewussteUebergangsschicht() throws {
        let projectRoot = projectRootURL()
        let ruleSettingsSource = try source(at: "Feedivo/Views/Rules/RuleSettingsView.swift", projectRoot: projectRoot)
        let ruleWizardSource = try source(at: "Feedivo/Views/Rules/RuleWizardView.swift", projectRoot: projectRoot)
        let smartFolderSettingsSource = try source(at: "Feedivo/Views/SmartFolders/SmartFolderSettingsView.swift", projectRoot: projectRoot)
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)

        #expect(!ruleSettingsSource.contains("@Query(sort: \\Rule.sortOrder) private var rules: [Rule]"))
        #expect(!ruleWizardSource.contains("@Query(sort: \\Rule.sortOrder) private var existingRules: [Rule]"))
        #expect(!smartFolderSettingsSource.contains("@Query(sort: \\SmartFolder.sortOrder) private var folders: [SmartFolder]"))
        #expect(contentSource.contains("SQLiteFeedArticleListView("))
        #expect(contentSource.contains("SQLiteReaderView("))
    }

    @Test func tagManagerIstSQLiteFirst() throws {
        let projectRoot = projectRootURL()
        let source = try source(at: "Feedivo/Views/Tags/TagManagerView.swift", projectRoot: projectRoot)

        #expect(!source.contains("@Query(sort: \\Tag.name)"))
        #expect(!source.contains("@Environment(\\.modelContext)"))
        #expect(source.contains("@State private var tags: [TagRecord] = []"))
        #expect(source.contains("TagStore(database: database).tags()"))
        #expect(source.contains("TagStore(database: database).save"))
        #expect(source.contains("TagStore(database: database).renameTag"))
        #expect(source.contains("TagStore(database: database).updateColor"))
        #expect(source.contains("TagStore(database: database).deleteTag"))
    }

    @Test func sqliteReaderMeldetGeladenenSnapshotAnCommandEbene() throws {
        let projectRoot = projectRootURL()
        let readerSource = try source(at: "Feedivo/Views/Reader/SQLiteReaderView.swift", projectRoot: projectRoot)
        let compactReaderSource = compact(readerSource)

        #expect(readerSource.contains("let onSnapshotChange: (ArticleReaderSnapshot?) -> Void"))
        #expect(compactReaderSource.contains(".onChange(of:state.snapshot){_,snapshotinonSnapshotChange(snapshot)}"))
        #expect(compactReaderSource.contains(".onDisappear{onSnapshotChange(nil)}"))
    }

    @Test func articleWindowViewNutztSQLiteReaderStattSwiftDataArticleQuery() throws {
        let projectRoot = projectRootURL()
        let articleWindowSource = try source(at: "Feedivo/Views/Reader/ArticleWindowView.swift", projectRoot: projectRoot)

        #expect(articleWindowSource.contains("@Environment(\\.feedivoDatabase) private var database"))
        #expect(articleWindowSource.contains("SQLiteReaderView("))
        #expect(articleWindowSource.contains("ArticleStore(database: database)"))
        #expect(!articleWindowSource.contains("@Query private var articles"))
        #expect(!articleWindowSource.contains("\n                ReaderView("))
        #expect(!articleWindowSource.contains("ArticleExportSnapshot(article:"))
    }

    @Test func contentViewUebergibtSQLiteDatabaseAnFeedRefreshes() throws {
        let projectRoot = projectRootURL()
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
        let compactContentSource = compact(contentSource)

        #expect(contentSource.contains("@Environment(\\.feedivoDatabase) private var feedivoDatabase"))
        #expect(compactContentSource.contains("refreshFeed(feedID:feedID,sqliteDatabase:feedivoDatabase)"))
        #expect(compactContentSource.contains("guardletdatabase=feedivoDatabaseelse{return}"))
        #expect(compactContentSource.contains("refreshAllFeeds(sqliteDatabase:database)"))
    }

    @Test func addFeedSheetUebergibtSQLiteDatabaseAnFeedViewModel() throws {
        let projectRoot = projectRootURL()
        let sidebarSource = try source(at: "Feedivo/Views/Sidebar/SidebarView.swift", projectRoot: projectRoot)
        let compactSidebarSource = compact(sidebarSource)

        #expect(sidebarSource.contains("@Environment(\\.feedivoDatabase) private var feedivoDatabase"))
        #expect(compactSidebarSource.contains("viewModel.addFeed(urlString:urlString,sqliteDatabase:feedivoDatabase)"))
    }

    @Test func sidebarViewLaedtSQLiteSidebarState() throws {
        let projectRoot = projectRootURL()
        let sidebarSource = try source(at: "Feedivo/Views/Sidebar/SidebarView.swift", projectRoot: projectRoot)
        let compactSidebarSource = compact(sidebarSource)

        #expect(sidebarSource.contains("@Environment(\\.feedivoDatabase) private var feedivoDatabase"))
        #expect(sidebarSource.contains("@AppStorage(SQLiteDataInvalidation.statusVersionKey)"))
        #expect(sidebarSource.contains("@State private var sqliteSidebarState = SQLiteSidebarState()"))
        #expect(compactSidebarSource.contains("sqliteSidebarState.load(database:feedivoDatabase,showsReadFeeds:showsReadFeedsInSidebar)"))
        // Sidebar ist SQLite-only: Feeds werden direkt aus den Snapshots gerendert,
        // ohne SwiftData-@Query oder Feed-Bridge-Helfer.
        #expect(compactSidebarSource.contains("letvisibleSnapshots=sqliteSidebarState.snapshots"))
        #expect(compactSidebarSource.contains("FeedRowView(snapshot:snapshot,"))
        #expect(!sidebarSource.contains("@Query(sort: \\Feed.title) private var feeds: [Feed]"))
        #expect(compactSidebarSource.contains("\\(sqliteStatusVersion)#\\(directTagVersion)#\\(showsReadFeedsInSidebar)#\\(sidebarDefinitionVersion)#\\(sqliteSidebarState.snapshots.count)"))
    }

    @Test func sidebarTagBadgesNutzenSQLiteSnapshots() throws {
        let projectRoot = projectRootURL()
        let sidebarSource = try source(at: "Feedivo/Views/Sidebar/SidebarView.swift", projectRoot: projectRoot)
        let compactSidebarSource = compact(sidebarSource)

        #expect(compactSidebarSource.contains("tagRows(sqliteSidebarState.tagSnapshots)"))
        #expect(compactSidebarSource.contains("selection=.tag(tag.id)"))
        #expect(!sidebarSource.contains("@Query(sort: \\Tag.name) private var tags"))
        #expect(!sidebarSource.contains("SidebarTagCount.articleCount(for: tag, context: modelContext)"))
    }

    @Test func sidebarSmartFolderBadgesNutzenSQLiteSnapshots() throws {
        let projectRoot = projectRootURL()
        let sidebarSource = try source(at: "Feedivo/Views/Sidebar/SidebarView.swift", projectRoot: projectRoot)
        let compactSidebarSource = compact(sidebarSource)

        #expect(compactSidebarSource.contains("smartFoldersSection(badgeSnapshot:sqliteSidebarState.smartFolderBadgeSnapshot)"))
        #expect(compactSidebarSource.contains("SmartFolderSidebarBadge.badgeText(for:smartFolder,snapshot:badgeSnapshot)"))
        #expect(!sidebarSource.contains("statusBadgeArticles"))
    }

    @Test func sidebarAktionenStehenOberhalbDerIntelligentenOrdner() throws {
        let projectRoot = projectRootURL()
        let sidebarSource = try source(at: "Feedivo/Views/Sidebar/SidebarView.swift", projectRoot: projectRoot)
        let compactSidebarSource = compact(sidebarSource)

        #expect(sidebarSource.contains("private var sidebarActionRow: some View"))
        #expect(compactSidebarSource.contains("sidebarActionRowsmartFoldersSection(badgeSnapshot:sqliteSidebarState.smartFolderBadgeSnapshot)"))
        #expect(compactSidebarSource.contains("Button{onRequestRefreshAllFeeds()}label:{Image(systemName:\"arrow.clockwise\")"))
        #expect(compactSidebarSource.contains(".font(.system(size:15,weight:.semibold)).frame(width:24,height:24)"))
        #expect(compactSidebarSource.contains("createSidebarItemMenu.buttonStyle(.borderless).font(.system(size:15,weight:.semibold)).frame(width:24,height:24)"))
        #expect(!sidebarSource.contains("ToolbarItemGroup(placement: .navigation)"))
    }

    @Test func sidebarOrdnerUndSmartFolderQuellenSindSQLiteFirst() throws {
        let projectRoot = projectRootURL()
        let sidebarSource = try source(at: "Feedivo/Views/Sidebar/SidebarView.swift", projectRoot: projectRoot)
        let selectionSource = try source(at: "Feedivo/Views/Sidebar/SidebarSelection.swift", projectRoot: projectRoot)
        let stateSource = try source(at: "Feedivo/ViewModels/SQLiteSidebarState.swift", projectRoot: projectRoot)
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)

        #expect(!sidebarSource.contains("@Query(sort: \\FeedFolder.name)"))
        #expect(!sidebarSource.contains("@Query(sort: \\SmartFolder.sortOrder)"))
        #expect(sidebarSource.contains("sqliteSidebarState.feedFolders"))
        #expect(sidebarSource.contains("sqliteSidebarState.smartFolderSnapshots"))
        #expect(selectionSource.contains("case smartFolder(String)"))
        #expect(stateSource.contains("private(set) var feedFolders: [FeedFolderRecord] = []"))
        #expect(stateSource.contains("private(set) var smartFolderSnapshots: [SQLiteSmartFolderSnapshot] = []"))
        #expect(contentSource.contains("SQLiteSmartFolderStore(database: database).sidebarSnapshots()"))
    }

    @Test func leereSQLiteFeedOrdnerSindAusDerSidebarLoeschbar() throws {
        let projectRoot = projectRootURL()
        let sidebarSource = try source(at: "Feedivo/Views/Sidebar/SidebarView.swift", projectRoot: projectRoot)
        let compactSidebarSource = compact(sidebarSource)

        #expect(sidebarSource.contains("@State private var feedFolderPendingDeletion: FeedFolderRecord?"))
        #expect(sidebarSource.contains("entry.snapshots.isEmpty && explicitFolder != nil"))
        #expect(sidebarSource.contains("FeedFolderStore(database: database).delete(id: folder.id)"))
        #expect(compactSidebarSource.contains(".contextMenu{ifletdeleteEmptyFolder"))
    }

    @Test func smartFolderVerwaltungIstSQLiteFirst() throws {
        let projectRoot = projectRootURL()
        let settingsSource = try source(at: "Feedivo/Views/SmartFolders/SmartFolderSettingsView.swift", projectRoot: projectRoot)
        let editorSource = try source(at: "Feedivo/Views/SmartFolders/SmartFolderEditorView.swift", projectRoot: projectRoot)
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)

        #expect(!settingsSource.contains("@Query(sort: \\SmartFolder.sortOrder)"))
        #expect(!settingsSource.contains("@Environment(\\.modelContext)"))
        #expect(settingsSource.contains("@State private var folders: [SmartFolderRecord]"))
        #expect(settingsSource.contains("let store = SQLiteSmartFolderStore(database: database)"))
        #expect(settingsSource.contains("store.folders()"))
        #expect(settingsSource.contains("SQLiteSmartFolderStore(database: database).restoreDefaultFolders()"))

        #expect(!editorSource.contains("@Environment(\\.modelContext)"))
        #expect(!editorSource.contains("SmartFolderViewModel()"))
        #expect(editorSource.contains("let folder: SmartFolderRecord?"))
        #expect(editorSource.contains("SQLiteSmartFolderStore(database: database).save("))

        #expect(!contentSource.contains("@Query(sort: \\SmartFolder.sortOrder)"))
    }

    @Test func ruleVerwaltungIstSQLiteFirst() throws {
        let projectRoot = projectRootURL()
        let settingsSource = try source(at: "Feedivo/Views/Rules/RuleSettingsView.swift", projectRoot: projectRoot)
        let wizardSource = try source(at: "Feedivo/Views/Rules/RuleWizardView.swift", projectRoot: projectRoot)

        #expect(!settingsSource.contains("@Query(sort: \\Rule.sortOrder)"))
        #expect(!settingsSource.contains("@Environment(\\.modelContext)"))
        #expect(!settingsSource.contains("RuleViewModel()"))
        #expect(settingsSource.contains("@State private var rules: [RuleRecord]"))
        #expect(settingsSource.contains("let ruleStore = SQLiteRuleStore(database: database)"))
        #expect(settingsSource.contains("SQLiteRuleStore(database: database).ruleSnapshots()"))

        #expect(!wizardSource.contains("@Environment(\\.modelContext)"))
        #expect(!wizardSource.contains("@Query(sort: \\Rule.sortOrder)"))
        #expect(!wizardSource.contains("@Query(sort: \\Tag.name)"))
        #expect(!wizardSource.contains("RuleViewModel()"))
        #expect(!wizardSource.contains("TagViewModel()"))
        #expect(wizardSource.contains("let rule: RuleRecord?"))
        #expect(wizardSource.contains("SQLiteRuleStore(database: database).save("))
        #expect(wizardSource.contains("TagStore(database: database).save("))
    }

    @Test func refreshPfadNutztRegelnAusSQLiteStore() throws {
        let projectRoot = projectRootURL()
        let viewModelSource = try source(at: "Feedivo/ViewModels/FeedViewModel.swift", projectRoot: projectRoot)
        let compactViewModelSource = compact(viewModelSource)

        #expect(compactViewModelSource.contains("funcrefreshFeed(feedID:String,sqliteDatabase:FeedivoDatabase?)async"))
        #expect(compactViewModelSource.contains("funcsqliteRuleSnapshots(fromdatabase:FeedivoDatabase)->[RuleEngine.RuleSnapshot]"))
        #expect(viewModelSource.contains("let ruleSnapshots = sqliteRuleSnapshots(from: sqliteDatabase)"))
        #expect(viewModelSource.contains("refreshAllFeeds("))
        #expect(viewModelSource.contains("sqliteDatabase: FeedivoDatabase"))
        #expect(!viewModelSource.contains("modelContainer _: ModelContainer?"))
        #expect(compactViewModelSource.contains("SQLiteRuleStore(database:database).ruleSnapshots()"))
    }

    @Test func feedRowViewBevorzugtSQLiteSnapshotWerte() throws {
        let projectRoot = projectRootURL()
        let rowSource = try source(at: "Feedivo/Views/Sidebar/FeedRowView.swift", projectRoot: projectRoot)

        #expect(rowSource.contains("let snapshot: FeedSidebarSnapshot"))
        #expect(rowSource.contains("snapshot.unreadCount"))
        #expect(rowSource.contains("snapshot.title"))
        #expect(rowSource.contains("snapshot.faviconURL"))
    }

    @Test func feedPropertiesViewSpiegeltFeedTagsNachSQLite() throws {
        let projectRoot = projectRootURL()
        let source = try source(at: "Feedivo/Views/Sidebar/FeedPropertiesView.swift", projectRoot: projectRoot)

        #expect(source.contains("@Environment(\\.feedivoDatabase) private var feedivoDatabase"))
        #expect(source.contains("let store = TagStore(database: database)"))
        #expect(source.contains("try TagStore(database: database).save(tag)"))
        #expect(source.contains("assignTag(tagID: tag.id, toFeedID: feedID"))
        #expect(source.contains("try TagStore(database: database).removeTag"))
        #expect(source.contains("tagID: tag.id"))
        #expect(source.contains("fromFeedID: feedID"))
        #expect(source.contains("SidebarBadgeInvalidation.bumpDirectTagVersion()"))
    }

    @Test func feedPropertiesViewLaedtFeedLogsAusSQLite() throws {
        let projectRoot = projectRootURL()
        let source = try source(at: "Feedivo/Views/Sidebar/FeedPropertiesView.swift", projectRoot: projectRoot)
        let compactSource = compact(source)

        #expect(source.contains("@State private var sqliteLogEntries: [FeedLogRecord] = []"))
        #expect(compactSource.contains("FeedLogStore(database:database).logs(feedID:feedID,limit:20)"))
        #expect(compactSource.contains("ForEach(Array(sqliteLogEntries.enumerated()),id:\\.element.id)"))
        #expect(!source.contains("FeedPropertiesQuery.latestLogEntries(in: modelContext, for: feed)"))
    }

    @Test func feedPropertiesMetrikenLaufenUeberSQLite() throws {
        let projectRoot = projectRootURL()
        let propertiesSource = try source(at: "Feedivo/Views/Sidebar/FeedPropertiesView.swift", projectRoot: projectRoot)
        let organizerSource = try source(at: "Feedivo/Views/Organizer/FeedManagementOrganizerView.swift", projectRoot: projectRoot)
        let compactPropertiesSource = compact(propertiesSource)
        let compactOrganizerSource = compact(organizerSource)

        #expect(propertiesSource.contains("@State private var sqliteArticleMetrics = FeedPropertiesArticleMetricsSnapshot.empty"))
        #expect(compactPropertiesSource.contains("ArticleStore(database:database).feedPropertiesMetrics(feedID:feedID,recentCutoffDate:"))
        #expect(compactOrganizerSource.contains("FeedManagementOrganizerRow(feed:feed,isSelected:selectedFeedIDs.contains(feed.id),sqliteDatabase:feedivoDatabase"))
        #expect(compactOrganizerSource.contains("ArticleStore(database:database).feedPropertiesMetrics(feedID:feed.id,recentCutoffDate:"))
        #expect(!propertiesSource.contains("FeedPropertiesQuery.latestArticle(in: modelContext, for: feed)"))
        #expect(!propertiesSource.contains("FeedPropertiesQuery.recentArticleCount("))
        #expect(!organizerSource.contains("FeedPropertiesQuery.recentArticleCount("))
    }

    @Test func tagManagerViewSpiegeltTagAenderungenNachSQLite() throws {
        let projectRoot = projectRootURL()
        let source = try source(at: "Feedivo/Views/Tags/TagManagerView.swift", projectRoot: projectRoot)

        #expect(source.contains("@Environment(\\.feedivoDatabase) private var feedivoDatabase"))
        #expect(source.contains("TagStore(database: database).save"))
        #expect(source.contains("TagStore(database: database).renameTag"))
        #expect(source.contains("TagStore(database: database).updateColor"))
        #expect(source.contains("TagStore(database: database).deleteTag"))
        #expect(!source.contains("sqliteDatabase: feedivoDatabase"))
        #expect(!source.contains("viewModel.createTag("))
    }

    @Test func modelContainerFactoryIstNichtMehrTeilDesProduktcodes() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)

        #expect(!appSource.contains("FeedivoModelContainerFactory"))
        #expect(!appSource.contains("ModelContainer"))
        #expect(!appSource.contains(".modelContainer("))

        let factoryURL = projectRoot.appendingPathComponent("Feedivo/App/FeedivoModelContainerFactory.swift")
        #expect(!FileManager.default.fileExists(atPath: factoryURL.path))
    }

    @Test func produktiverAppStartVerwendetKeineLegacySwiftDataBackfills() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)

        #expect(!appSource.contains("ArticleFeedIDBackfillService"))
        #expect(!appSource.contains("FeedTagBackfillService"))
        #expect(!appSource.contains("FeedUnreadCountBackfillService"))
        #expect(!appSource.contains("SmartFolderDefaultKeyBackfillService"))
        #expect(!appSource.contains("SQLiteAdminDefinitionBackfillService"))
        #expect(!appSource.contains("FeedBackgroundRefreshService"))
    }

    @Test func feedViewModelProduktiveMethodenDelegierenAnSQLiteServices() throws {
        let projectRoot = projectRootURL()
        let source = try source(at: "Feedivo/ViewModels/FeedViewModel.swift", projectRoot: projectRoot)
        let compactSource = compact(source)

        // Produktive Feed-Aktionen delegieren an SQLite-Services statt selbst
        // SwiftData zu mutieren.
        #expect(source.contains("SQLiteFeedActionService"))
        #expect(source.contains("SQLiteFeedSubscriptionService"))
        #expect(source.contains("SQLiteFeedRefreshCoordinator"))
        // Die SQLite-Aktionen bleiben in einer klar markierten Region
        // abgegrenzt. Die frühere "Legacy SwiftData Compatibility"-Region
        // wurde im Zuge der vollständigen SwiftData-Entfernung gelöscht,
        // nicht nur markiert — es gibt keinen Marker mehr zu prüfen.
        #expect(compactSource.contains("MARK:-SQLiteFeedActions"))
    }

    @Test func startupBereinigungLaeuftVorDemStartRefreshOhneRace() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)

        let taskStart = try #require(appSource.range(of: ".task {"))
        let onChangeStart = try #require(appSource.range(of: ".onChange(of: backgroundRefreshIsEnabled)"))
        let taskBlockSource = appSource[taskStart.lowerBound..<onChangeStart.lowerBound]
        #expect(!taskBlockSource.contains("cleanupExpiredArticlesIfNeeded()"))

        let handleContentAppearStart = try #require(contentSource.range(of: "private func handleContentAppear()"))
        let nextFunctionStart = try #require(contentSource.range(of: "private func reloadFeedSnapshots"))
        let handleContentAppearSource = contentSource[handleContentAppearStart.lowerBound..<nextFunctionStart.lowerBound]

        #expect(handleContentAppearSource.contains("BackgroundRefreshService.cleanupExpiredArticlesIfNeeded(database: feedivoDatabase)"))

        let cleanupCallRange = try #require(handleContentAppearSource.range(of: "cleanupExpiredArticlesIfNeeded(database: feedivoDatabase)"))
        let refreshCallRange = try #require(handleContentAppearSource.range(of: "refreshFeedsOnLaunchIfNeeded()"))
        #expect(cleanupCallRange.lowerBound < refreshCallRange.lowerBound)
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
