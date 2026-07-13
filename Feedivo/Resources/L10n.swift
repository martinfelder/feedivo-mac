import SwiftUI

enum L10n {
    static let contentNoFeedSelectedTitle = LocalizedStringKey("content.noFeedSelected.title")
    static let contentNoFeedSelectedDescription = LocalizedStringKey("content.noFeedSelected.description")
    static let contentNoArticleSelectedTitle = LocalizedStringKey("content.noArticleSelected.title")
    static let contentNoArticleSelectedDescription = LocalizedStringKey("content.noArticleSelected.description")
    static let sidebarEmptyTitle = LocalizedStringKey("sidebar.empty.title")
    static let sidebarAddFeedButton = LocalizedStringKey("sidebar.addFeed.button")
    static let sidebarAddFeedTitle = LocalizedStringKey("sidebar.addFeed.title")
    static let sidebarAddFeedDescription = LocalizedStringKey("sidebar.addFeed.description")
    static let sidebarAddFeedURLPlaceholder = LocalizedStringKey("sidebar.addFeed.url.placeholder")
    static let sidebarAddFeedNewFolder = LocalizedStringKey("sidebar.addFeed.newFolder")
    static let feedDiscoveryResultsTitle = LocalizedStringKey("feedDiscovery.results.title")
    static let feedDiscoverySearchButton = LocalizedStringKey("feedDiscovery.search.button")
    static let sidebarFoldersSection = LocalizedStringKey("sidebar.folders.section")
    static let sidebarAddFolderButton = LocalizedStringKey("sidebar.addFolder.button")
    static let sidebarAddFolderTitle = LocalizedStringKey("sidebar.addFolder.title")
    static let sidebarAddFolderNamePlaceholder = LocalizedStringKey("sidebar.addFolder.name.placeholder")
    static let sidebarFolderRenameCommand = String(localized: "sidebar.folder.rename.command")
    static let sidebarSmartFiltersSection = LocalizedStringKey("sidebar.smartFilters.section")
    // Parallele Keys für die Smart-Folder-Sektion. Der alte Key
    // `sidebar.smartFilters.section` bleibt erhalten, wird aber nach diesem
    // Task nirgends mehr referenziert. Neue View-Stellen nutzen den
    // sprachlich konsistenteren Key `sidebar.smartFolders.section`.
    static let sidebarSmartFoldersSection = LocalizedStringKey("sidebar.smartFolders.section")
    static let sidebarSmartFoldersEmpty = LocalizedStringKey("sidebar.smartFolders.empty")
    static let sidebarSmartFoldersCustomSection = LocalizedStringKey("sidebar.smartFolders.custom.section")
    static let sidebarSmartFoldersCustomEmpty = LocalizedStringKey("sidebar.smartFolders.custom.empty")
    static let sidebarSmartFolderDelete = LocalizedStringKey("sidebar.smartFolder.delete")
    static let sidebarFeedPreviewEmpty = LocalizedStringKey("sidebar.feedPreview.empty")
    static let sidebarFeedPreviewRecent = LocalizedStringKey("sidebar.feedPreview.recent")
    static let sidebarSubscribe = LocalizedStringKey("sidebar.subscribe")
    static let commonDelete = LocalizedStringKey("common.delete")
    static let commonDuplicate = LocalizedStringKey("common.duplicate")
    static let sidebarTagsSection = LocalizedStringKey("sidebar.tags.section")
    static let smartFilterAllArticles = LocalizedStringKey("smartFilter.allArticles")
    static let smartFilterUnread = LocalizedStringKey("smartFilter.unread")
    static let smartFilterStarred = LocalizedStringKey("smartFilter.starred")
    static let smartFilterToday = LocalizedStringKey("smartFilter.today")
    static let smartFilterHidden = LocalizedStringKey("smartFilter.hidden")
    static let smartFolderErrorNameRequired = String(localized: "smartFolder.error.nameRequired")
    static let commonCancel = LocalizedStringKey("common.cancel")
    static let commonAdd = LocalizedStringKey("common.add")
    static let commonDone = LocalizedStringKey("common.done")
    static let commonNext = String(localized: "common.next")
    static let commonBack = String(localized: "common.back")
    static let commonOn = String(localized: "common.on")
    static let commonOff = String(localized: "common.off")
    static let articleListEmptyTitle = String(localized: "articleList.empty.title")
    static let articleListEmptyDescription = LocalizedStringKey("articleList.empty.description")
    static let articleListEmptyDescriptionFeed = String(localized: "articleList.empty.description.feed")
    static let articleListEmptyDescriptionTag = String(localized: "articleList.empty.description.tag")
    static let articleListEmptyDescriptionSmartFilter = String(localized: "articleList.empty.description.smartFilter")
    static let articleListEmptyDescriptionSmartFolder = String(localized: "articleList.empty.description.smartFolder")
    static let articleListLoadFailedTitle = String(localized: "articleList.loadFailed.title")

    static func articleListLastRefreshed(_ date: String) -> String {
        String.localizedStringWithFormat(String(localized: "articleList.header.lastRefreshed"), date)
    }

    static func articleListRefreshFailed(_ reason: String) -> String {
        String.localizedStringWithFormat(String(localized: "articleList.header.refreshFailed"), reason)
    }
    static let dbUnavailableTitle = String(localized: "db.unavailable.title")
    static let dbUnavailableDescription = String(localized: "db.unavailable.description")
    static let feedNotInSQLiteTitle = String(localized: "feed.notInSQLite.title")
    static let feedNotInSQLiteDescription = String(localized: "feed.notInSQLite.description")
    static let readerInspectorNoArticleLoaded = String(localized: "reader.inspector.noArticleLoaded")
    static let readerArticleNotFoundTitle = String(localized: "reader.articleNotFound.title")
    static let readerArticleNotFoundDescription = String(localized: "reader.articleNotFound.description")
    static let articleListImagePositionLeft = LocalizedStringKey("articleList.imagePosition.left")
    static let articleListImagePositionRight = LocalizedStringKey("articleList.imagePosition.right")
    static let articleListImagePositionHidden = LocalizedStringKey("articleList.imagePosition.hidden")
    static let articleListFeedNamePositionBeforeTitle = LocalizedStringKey("articleList.feedNamePosition.beforeTitle")
    static let articleListFeedNamePositionAfterTitle = LocalizedStringKey("articleList.feedNamePosition.afterTitle")
    static let articleDateDisplayModeRelative = LocalizedStringKey("articleDateDisplayMode.relative")
    static let articleDateDisplayModeAbsolute = LocalizedStringKey("articleDateDisplayMode.absolute")
    static let menubarArticleClickBehaviorInFeedivo = LocalizedStringKey("menubar.articleClickBehavior.inFeedivo")
    static let menubarArticleClickBehaviorInBrowser = LocalizedStringKey("menubar.articleClickBehavior.inBrowser")
    static let menubarOpenFeedivoButton = LocalizedStringKey("menubar.openFeedivo.button")
    static let menubarRefreshButton = LocalizedStringKey("menubar.refresh.button")
    static let menubarMarkAllReadButton = LocalizedStringKey("menubar.markAllRead.button")
    static let menubarEmptyStateTitle = LocalizedStringKey("menubar.emptyState.title")
    static let settingsMenubarIsEnabledTitle = LocalizedStringKey("settings.menubar.isEnabled.title")
    static let settingsMenubarIsEnabledDescription = LocalizedStringKey("settings.menubar.isEnabled.description")
    static let settingsMenubarArticleCountTitle = LocalizedStringKey("settings.menubar.articleCount.title")
    static let settingsMenubarArticleCountDescription = LocalizedStringKey("settings.menubar.articleCount.description")
    static let settingsMenubarArticleClickBehaviorTitle = LocalizedStringKey("settings.menubar.articleClickBehavior.title")
    static let settingsMenubarArticleClickBehaviorDescription = LocalizedStringKey("settings.menubar.articleClickBehavior.description")
    static let settingsMenubarHidesDockIconTitle = LocalizedStringKey("settings.menubar.hidesDockIcon.title")
    static let settingsMenubarHidesDockIconDescription = LocalizedStringKey("settings.menubar.hidesDockIcon.description")
    static let articleRowUnread = LocalizedStringKey("articleRow.unread")
    static let readerOpenOriginal = LocalizedStringKey("reader.openOriginal")
    static let readerAppearanceButton = LocalizedStringKey("reader.appearance.button")
    static let readerAppearanceTitle = LocalizedStringKey("reader.appearance.title")
    static let readerTitleFontPicker = LocalizedStringKey("reader.titleFont.picker")
    static let readerTitleFontBoldToggle = LocalizedStringKey("reader.titleFont.bold.toggle")
    static let readerBodyFontPicker = LocalizedStringKey("reader.bodyFont.picker")
    static let readerBodyFontBoldToggle = LocalizedStringKey("reader.bodyFont.bold.toggle")
    static let readerBodyFontSizeSlider = LocalizedStringKey("reader.bodyFontSize.slider")
    static let readerTitleLineSpacingSlider = LocalizedStringKey("reader.titleLineSpacing.slider")
    static let readerLineSpacingSlider = LocalizedStringKey("reader.lineSpacing.slider")
    static let readerContentWidthSlider = LocalizedStringKey("reader.contentWidth.slider")
    static let readerShowsArticleImagesToggle = LocalizedStringKey("reader.showsArticleImages.toggle")
    static let readerDisplayModePicker = LocalizedStringKey("reader.displayMode.picker")
    static let readerDisplayModeNative = LocalizedStringKey("reader.displayMode.native")
    static let readerDisplayModeWeb = LocalizedStringKey("reader.displayMode.web")
    static let statisticsTimeRangeLast7Days = LocalizedStringKey("statistics.timeRange.last7Days")
    static let statisticsTimeRangeLast30Days = LocalizedStringKey("statistics.timeRange.last30Days")
    static let statisticsTimeRangeAll = LocalizedStringKey("statistics.timeRange.all")
    static let statisticsCommand = String(localized: "statistics.command")
    static let statisticsWindowTitle = String(localized: "statistics.window.title")
    static let statisticsSubtitle = LocalizedStringKey("statistics.subtitle")
    static let statisticsSummaryToday = LocalizedStringKey("statistics.summary.today")
    static let statisticsSummaryThisWeek = LocalizedStringKey("statistics.summary.thisWeek")
    static let statisticsSummaryTotal = LocalizedStringKey("statistics.summary.total")
    static let statisticsSummaryAverageReadingTime = LocalizedStringKey("statistics.summary.averageReadingTime")
    static let statisticsHeatmapTitle = LocalizedStringKey("statistics.heatmap.title")
    static let statisticsTopFeedsTitle = LocalizedStringKey("statistics.topFeeds.title")
    static let statisticsTopFeedsEmpty = LocalizedStringKey("statistics.topFeeds.empty")
    static let statisticsTopTagsTitle = LocalizedStringKey("statistics.topTags.title")
    static let statisticsTopTagsEmpty = LocalizedStringKey("statistics.topTags.empty")
    static let statisticsExportButton = LocalizedStringKey("statistics.export.button")
    static let statisticsHeatmapLegendLess = LocalizedStringKey("statistics.heatmap.legend.less")
    static let statisticsHeatmapLegendMore = LocalizedStringKey("statistics.heatmap.legend.more")
    static let statisticsSummaryTotalReadingTime = LocalizedStringKey("statistics.summary.totalReadingTime")
    static let statisticsSummarySelectedRangeCount = LocalizedStringKey("statistics.summary.selectedRangeCount")
    static let shortcutsSettingsSection = LocalizedStringKey("shortcuts.settings.section")
    static let shortcutsCategoryFeed = LocalizedStringKey("shortcuts.category.feed")
    static let shortcutsCategoryArticle = LocalizedStringKey("shortcuts.category.article")
    static let shortcutsCategoryReader = LocalizedStringKey("shortcuts.category.reader")
    static let shortcutsResetAllButton = LocalizedStringKey("shortcuts.resetAll.button")
    static let shortcutsResetButtonHelp = String(localized: "shortcuts.reset.button.help")
    static let shortcutsClearButtonHelp = String(localized: "shortcuts.clear.button.help")
    static let shortcutsLabelFeedAdd = LocalizedStringKey("shortcuts.label.feedAdd")
    static let shortcutsLabelStatisticsOpen = LocalizedStringKey("shortcuts.label.statisticsOpen")
    static let shortcutsLabelFeedRefreshAll = LocalizedStringKey("shortcuts.label.feedRefreshAll")
    static let shortcutsLabelFeedRefresh = LocalizedStringKey("shortcuts.label.feedRefresh")
    static let shortcutsLabelArticleSelectPrevious = LocalizedStringKey("shortcuts.label.articleSelectPrevious")
    static let shortcutsLabelArticleSelectNext = LocalizedStringKey("shortcuts.label.articleSelectNext")
    static let shortcutsLabelArticleSearch = LocalizedStringKey("shortcuts.label.articleSearch")
    static let shortcutsLabelArticleToggleRead = LocalizedStringKey("shortcuts.label.articleToggleRead")
    static let shortcutsLabelArticleToggleStarred = LocalizedStringKey("shortcuts.label.articleToggleStarred")
    static let shortcutsLabelArticleOpenInWindow = LocalizedStringKey("shortcuts.label.articleOpenInWindow")
    static let shortcutsLabelReaderWebBack = LocalizedStringKey("shortcuts.label.readerWebBack")
    static let shortcutsLabelReaderWebForward = LocalizedStringKey("shortcuts.label.readerWebForward")

    static func shortcutsConflictMessage(_ conflictingLabel: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "shortcuts.conflict.message"),
            conflictingLabel
        )
    }

    static func statisticsTrendIncrease(_ percentage: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "statistics.trend.increase"),
            percentage
        )
    }

    static func statisticsTrendDecrease(_ percentage: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "statistics.trend.decrease"),
            percentage
        )
    }

    static func statisticsHeatmapDayTooltip(_ date: String, _ count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "statistics.heatmap.day.tooltip"),
            date,
            count
        )
    }

    static func statisticsStreakText(current: Int, longest: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "statistics.streak.text"),
            current,
            longest
        )
    }

    static func statisticsMinutesPerDay(_ minutes: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "statistics.minutesPerDay"),
            minutes
        )
    }
    static let networkStatusOnline = LocalizedStringKey("networkStatus.online")
    static let networkStatusOffline = LocalizedStringKey("networkStatus.offline")
    static let refreshStatusDetailsTitle = String(localized: "refreshStatus.details.title")
    static let refreshStatusExpand = String(localized: "refreshStatus.expand")
    static let refreshStatusCollapse = String(localized: "refreshStatus.collapse")
    static let refreshStatusDismiss = String(localized: "refreshStatus.dismiss")
    static let refreshStatusItemPending = String(localized: "refreshStatus.item.pending")
    static let refreshStatusItemRefreshing = String(localized: "refreshStatus.item.refreshing")
    static let refreshStatusItemSucceeded = String(localized: "refreshStatus.item.succeeded")
    static let refreshStatusItemFailed = String(localized: "refreshStatus.item.failed")
    static let refreshStatusNoNewArticles = String(localized: "refreshStatus.noNewArticles")
    static let readerOfflineSave = LocalizedStringKey("reader.offline.save")
    static let readerOfflineRemove = LocalizedStringKey("reader.offline.remove")
    static let readerOfflineSaving = LocalizedStringKey("reader.offline.saving")
    static let readerOfflineFullTextAvailable = LocalizedStringKey("reader.offline.fullTextAvailable")
    static let readerOfflineFeedContentAvailable = LocalizedStringKey("reader.offline.feedContentAvailable")
    static let readerOfflineFailed = LocalizedStringKey("reader.offline.failed")
    static let readerOfflineNotSaved = LocalizedStringKey("reader.offline.notSaved")
    static let readerInspectorButton = LocalizedStringKey("reader.inspector.button")
    static let readerInspectorTitle = LocalizedStringKey("reader.inspector.title")
    static let readerInspectorFeed = LocalizedStringKey("reader.inspector.feed")
    static let readerInspectorPublished = LocalizedStringKey("reader.inspector.published")
    static let readerInspectorReadingTime = LocalizedStringKey("reader.inspector.readingTime")
    static let readerInspectorReadStatus = LocalizedStringKey("reader.inspector.readStatus")
    static let readerInspectorStarStatus = LocalizedStringKey("reader.inspector.starStatus")
    static let readerInspectorFolder = LocalizedStringKey("reader.inspector.folder")
    static let readerInspectorFeedFolder = LocalizedStringKey("reader.inspector.feedFolder")
    static let readerInspectorFeedFolderHint = LocalizedStringKey("reader.inspector.feedFolder.hint")
    static let readerInspectorNewFeedFolder = LocalizedStringKey("reader.inspector.newFeedFolder")
    static let readerInspectorNewFeedFolderPlaceholder = LocalizedStringKey("reader.inspector.newFeedFolder.placeholder")
    static let readerInspectorNoFolder = LocalizedStringKey("reader.inspector.noFolder")
    static let readerInspectorTags = LocalizedStringKey("reader.inspector.tags")
    static let readerInspectorNewTag = LocalizedStringKey("reader.inspector.newTag")
    static let readerInspectorAddTagPlaceholder = LocalizedStringKey("reader.inspector.addTag.placeholder")
    static let readerInspectorNoTags = LocalizedStringKey("reader.inspector.noTags")
    static let readerInspectorOfflineAndContentSection = LocalizedStringKey("reader.inspector.offlineAndContentSection")
    static let readerInspectorContextSection = LocalizedStringKey("reader.inspector.contextSection")
    static let readerInspectorOfflineStatus = LocalizedStringKey("reader.inspector.offlineStatus")
    static let readerInspectorOfflineDetail = LocalizedStringKey("reader.inspector.offlineDetail")
    static let readerInspectorSourceSection = LocalizedStringKey("reader.inspector.sourceSection")
    static let readerInspectorOriginalLink = LocalizedStringKey("reader.inspector.originalLink")
    static let readerInspectorUnavailable = LocalizedStringKey("reader.inspector.unavailable")
    static let articleWindowMissingTitle = LocalizedStringKey("article.window.missing.title")
    static let articleWindowMissingDescription = LocalizedStringKey("article.window.missing.description")
    static let tagManagerTitle = LocalizedStringKey("tagManager.title")
    static let tagManagerDescription = LocalizedStringKey("tagManager.description")
    static let tagManagerNamePlaceholder = LocalizedStringKey("tagManager.name.placeholder")
    static let tagManagerColor = LocalizedStringKey("tagManager.color")
    static let tagManagerNoTags = LocalizedStringKey("tagManager.noTags")
    static let tagManagerNewTag = LocalizedStringKey("tagManager.newTag")
    static let tagManagerDeleteTitle = LocalizedStringKey("tagManager.delete.title")
    static let tagManagerDeleteMessage = LocalizedStringKey("tagManager.delete.message")
    static let tagManagerDeleteButton = LocalizedStringKey("tagManager.delete.button")
    static let ruleMatchModeAll = LocalizedStringKey("rule.matchMode.all")
    static let ruleMatchModeAny = LocalizedStringKey("rule.matchMode.any")
    static let ruleConditionFieldTitle = LocalizedStringKey("rule.condition.field.title")
    static let ruleConditionFieldSummary = LocalizedStringKey("rule.condition.field.summary")
    static let ruleConditionFieldAuthor = LocalizedStringKey("rule.condition.field.author")
    static let ruleConditionFieldLink = LocalizedStringKey("rule.condition.field.link")
    static let ruleConditionFieldFeedTitle = LocalizedStringKey("rule.condition.field.feedTitle")
    static let ruleConditionOperatorContains = LocalizedStringKey("rule.condition.operator.contains")
    static let ruleConditionOperatorNotContains = LocalizedStringKey("rule.condition.operator.notContains")
    static let ruleConditionOperatorEquals = LocalizedStringKey("rule.condition.operator.equals")
    static let ruleConditionOperatorStartsWith = LocalizedStringKey("rule.condition.operator.startsWith")
    static let ruleConditionOperatorEndsWith = LocalizedStringKey("rule.condition.operator.endsWith")
    static let ruleConditionOperatorRegex = LocalizedStringKey("rule.condition.operator.regex")
    static let settingsRulesSection = LocalizedStringKey("settings.rules.section")
    static let ruleApplyExistingButton = LocalizedStringKey("rule.applyExisting.button")
    static let ruleCreateButton = LocalizedStringKey("rule.create.button")
    static let ruleEditButton = LocalizedStringKey("rule.edit.button")
    static let ruleDeleteButton = LocalizedStringKey("rule.delete.button")
    static let ruleNoRules = LocalizedStringKey("rule.noRules")
    static let ruleEnabled = LocalizedStringKey("rule.enabled")
    static let ruleWizardCreateTitle = LocalizedStringKey("ruleWizard.title.create")
    static let ruleWizardEditTitle = LocalizedStringKey("ruleWizard.title.edit")
    static let ruleWizardModeTitle = LocalizedStringKey("ruleWizard.mode.title")
    static let ruleWizardModeSimple = LocalizedStringKey("ruleWizard.mode.simple")
    static let ruleWizardModePower = LocalizedStringKey("ruleWizard.mode.power")
    static let ruleWizardTargetTitle = LocalizedStringKey("ruleWizard.target.title")
    static let ruleWizardSummaryTitle = LocalizedStringKey("ruleWizard.summary.title")
    static let ruleWizardNamePlaceholder = LocalizedStringKey("ruleWizard.name.placeholder")
    static let ruleWizardValuePlaceholder = LocalizedStringKey("ruleWizard.value.placeholder")
    static let ruleWizardAddCondition = LocalizedStringKey("ruleWizard.addCondition")
    static let ruleWizardRemoveCondition = LocalizedStringKey("ruleWizard.removeCondition")
    static let ruleWizardSave = LocalizedStringKey("ruleWizard.save")
    static let ruleWizardNewTag = LocalizedStringKey("ruleWizard.newTag")
    static let ruleWizardNewTagName = LocalizedStringKey("ruleWizard.newTagName")
    static let ruleWizardNameLabel = LocalizedStringKey("ruleWizard.name.label")
    static let ruleWizardMatchModeLabel = LocalizedStringKey("ruleWizard.matchMode.label")
    static let ruleWizardIfBadge = LocalizedStringKey("ruleWizard.if.badge")
    static let ruleWizardIfDescription = LocalizedStringKey("ruleWizard.if.description")
    static let ruleWizardThenBadge = LocalizedStringKey("ruleWizard.then.badge")
    static let ruleWizardThenDescription = LocalizedStringKey("ruleWizard.then.description")
    static let ruleWizardNewTagButton = LocalizedStringKey("ruleWizard.newTagButton")
    static let ruleWizardCreateTagButton = LocalizedStringKey("ruleWizard.createTagButton")
    static let ruleWizardHideActionHint = LocalizedStringKey("ruleWizard.hideAction.hint")
    static let ruleWizardNotifyActionHint = LocalizedStringKey("ruleWizard.notifyAction.hint")
    static let ruleActionAssignTag = LocalizedStringKey("rule.action.assignTag")
    static let ruleActionHideArticle = LocalizedStringKey("rule.action.hideArticle")
    static let ruleActionNotify = LocalizedStringKey("rule.action.notify")
    static let ruleNotificationPriorityNormal = LocalizedStringKey("rule.notification.priority.normal")
    static let ruleNotificationPriorityCritical = LocalizedStringKey("rule.notification.priority.critical")
    static let settingsReadingSection = LocalizedStringKey("settings.reading.section")
    static let settingsLanguagePickerTitle = LocalizedStringKey("settings.language.picker.title")
    static let settingsLanguageSystem = LocalizedStringKey("settings.language.system")
    static let settingsLanguageGerman = LocalizedStringKey("settings.language.german")
    static let settingsLanguageEnglish = LocalizedStringKey("settings.language.english")
    static let settingsLanguageFrench = LocalizedStringKey("settings.language.french")
    static let settingsLanguageItalian = LocalizedStringKey("settings.language.italian")
    static let settingsAppearanceModePicker = LocalizedStringKey("settings.appearanceMode.picker")
    static let settingsAppearanceModeSystem = LocalizedStringKey("settings.appearanceMode.system")
    static let settingsAppearanceModeLight = LocalizedStringKey("settings.appearanceMode.light")
    static let settingsAppearanceModeDark = LocalizedStringKey("settings.appearanceMode.dark")
    static let settingsInterfaceTextSizePicker = LocalizedStringKey("settings.interfaceTextSize.picker")
    static let settingsInterfaceTextSizeSmall = LocalizedStringKey("settings.interfaceTextSize.small")
    static let settingsInterfaceTextSizeStandard = LocalizedStringKey("settings.interfaceTextSize.standard")
    static let settingsInterfaceTextSizeLarge = LocalizedStringKey("settings.interfaceTextSize.large")
    static let settingsInterfaceTextSizeExtraLarge = LocalizedStringKey("settings.interfaceTextSize.extraLarge")
    static let settingsSidebarShowsReadFeedsTitle = LocalizedStringKey("settings.sidebar.showsReadFeeds.title")
    static let settingsSidebarShowsReadFeedsDescription = LocalizedStringKey("settings.sidebar.showsReadFeeds.description")
    static let settingsSidebarShowsUnreadCountTitle = LocalizedStringKey("settings.sidebar.showsUnreadCount.title")
    static let settingsSidebarShowsUnreadCountDescription = LocalizedStringKey("settings.sidebar.showsUnreadCount.description")
    static let settingsSidebarShowsFaviconsTitle = LocalizedStringKey("settings.sidebar.showsFavicons.title")
    static let settingsSidebarShowsFaviconsDescription = LocalizedStringKey("settings.sidebar.showsFavicons.description")
    static let settingsArticleListImagePositionTitle = LocalizedStringKey("settings.articleList.imagePosition.title")
    static let settingsArticleListImagePositionDescription = LocalizedStringKey("settings.articleList.imagePosition.description")
    static let settingsArticleListShowsFeedNameTitle = LocalizedStringKey("settings.articleList.showsFeedName.title")
    static let settingsArticleListShowsFeedNameDescription = LocalizedStringKey("settings.articleList.showsFeedName.description")
    static let settingsArticleListFeedNamePositionTitle = LocalizedStringKey("settings.articleList.feedNamePosition.title")
    static let settingsArticleListFeedNamePositionDescription = LocalizedStringKey("settings.articleList.feedNamePosition.description")
    static let settingsArticleListSummaryLineCountTitle = LocalizedStringKey("settings.articleList.summaryLineCount.title")
    static let settingsArticleListSummaryLineCountDescription = LocalizedStringKey("settings.articleList.summaryLineCount.description")
    static let settingsArticleListDateDisplayModeTitle = LocalizedStringKey("settings.articleList.dateDisplayMode.title")
    static let settingsArticleListDateDisplayModeDescription = LocalizedStringKey("settings.articleList.dateDisplayMode.description")
    static let settingsMarkReadOnOpenTitle = LocalizedStringKey("settings.markReadOnOpen.title")
    static let settingsMarkReadOnOpenDescription = LocalizedStringKey("settings.markReadOnOpen.description")
    static let settingsRestoreArticleWindowsTitle = LocalizedStringKey("settings.restoreArticleWindows.title")
    static let settingsRestoreArticleWindowsDescription = LocalizedStringKey("settings.restoreArticleWindows.description")
    static let settingsRefreshSection = LocalizedStringKey("settings.refresh.section")
    static let settingsAutomaticRefreshTitle = LocalizedStringKey("settings.automaticRefresh.title")
    static let settingsRefreshOnLaunchTitle = LocalizedStringKey("settings.refreshOnLaunch.title")
    static let settingsRefreshOnLaunchDescription = LocalizedStringKey("settings.refreshOnLaunch.description")
    static let settingsAutomaticRefreshIntervalPicker = LocalizedStringKey("settings.automaticRefresh.interval.picker")
    static let settingsAutomaticRefreshDescription = LocalizedStringKey("settings.automaticRefresh.description")
    static let settingsAutomaticRefreshLastRun = LocalizedStringKey("settings.automaticRefresh.lastRun")
    static let settingsAutomaticRefreshStatus = LocalizedStringKey("settings.automaticRefresh.status")
    static let settingsAutomaticRefreshNextRun = LocalizedStringKey("settings.automaticRefresh.nextRun")
    static let settingsAutomaticRefreshLastError = LocalizedStringKey("settings.automaticRefresh.lastError")
    static let settingsAutomaticRefreshStatusSuccess = LocalizedStringKey("settings.automaticRefresh.status.success")
    static let settingsAutomaticRefreshStatusFailed = LocalizedStringKey("settings.automaticRefresh.status.failed")
    static let settingsAutomaticRefreshStatusPartial = LocalizedStringKey("settings.automaticRefresh.status.partial")
    static let settingsAutomaticRefreshStatusNever = LocalizedStringKey("settings.automaticRefresh.status.never")
    static let settingsGeneralSection = LocalizedStringKey("settings.general.section")
    static let settingsFeedsSection = LocalizedStringKey("settings.feeds.section")
    static let settingsFeedsDescription = LocalizedStringKey("settings.feeds.description")
    static let settingsFeedsSearchPlaceholder = LocalizedStringKey("settings.feeds.search.placeholder")
    static let settingsFeedsSelectVisible = LocalizedStringKey("settings.feeds.selectVisible")
    static let settingsFeedsClearSelection = LocalizedStringKey("settings.feeds.clearSelection")
    static let settingsFeedsNoFeeds = LocalizedStringKey("settings.feeds.noFeeds")
    static let settingsFeedsNoMatches = LocalizedStringKey("settings.feeds.noMatches")
    static let settingsFeedsDeleteSelected = LocalizedStringKey("settings.feeds.deleteSelected")
    static let settingsFeedsDeleteConfirmationTitle = LocalizedStringKey("settings.feeds.deleteConfirmation.title")
    static let settingsCacheSection = LocalizedStringKey("settings.cache.section")
    static let settingsCacheDescription = LocalizedStringKey("settings.cache.description")
    static let settingsCacheCurrentSize = LocalizedStringKey("settings.cache.currentSize")
    static let settingsCacheLimitPicker = LocalizedStringKey("settings.cache.limit.picker")
    static let settingsCacheDescriptionDetail = LocalizedStringKey("settings.cache.description.detail")
    static let settingsCacheRefreshSize = LocalizedStringKey("settings.cache.refreshSize")
    static let settingsCacheClear = LocalizedStringKey("settings.cache.clear")
    static let settingsOfflineSection = LocalizedStringKey("settings.offline.section")
    static let settingsOfflineDescription = LocalizedStringKey("settings.offline.description")
    static let settingsOfflineManualTitle = LocalizedStringKey("settings.offline.manual.title")
    static let settingsOfflineManualDescription = LocalizedStringKey("settings.offline.manual.description")
    static let settingsOfflineFeedContentTitle = LocalizedStringKey("settings.offline.feedContent.title")
    static let settingsOfflineFeedContentDescription = LocalizedStringKey("settings.offline.feedContent.description")
    static let settingsOfflineAutomationTitle = LocalizedStringKey("settings.offline.automation.title")
    static let settingsOfflineAutomationDescription = LocalizedStringKey("settings.offline.automation.description")
    static let settingsOfflineAutoSaveStarredTitle = LocalizedStringKey("settings.offline.autoSaveStarred.title")
    static let settingsOfflineAutoSaveStarredDescription = LocalizedStringKey("settings.offline.autoSaveStarred.description")
    static let settingsNotificationsSection = LocalizedStringKey("settings.notifications.section")
    static let settingsNotificationsFeedTitle = LocalizedStringKey("settings.notifications.feed.title")
    static let settingsNotificationsFeedDescription = LocalizedStringKey("settings.notifications.feed.description")
    static let settingsNotificationsPermissionTitle = LocalizedStringKey("settings.notifications.permission.title")
    static let settingsNotificationsPermissionRequest = LocalizedStringKey("settings.notifications.permission.request")
    static let settingsNotificationsPermissionAllowed = LocalizedStringKey("settings.notifications.permission.allowed")
    static let settingsNotificationsPermissionDenied = LocalizedStringKey("settings.notifications.permission.denied")
    static let settingsNotificationsPermissionNotDetermined = LocalizedStringKey("settings.notifications.permission.notDetermined")
    static let settingsNotificationsPermissionUnknown = LocalizedStringKey("settings.notifications.permission.unknown")
    static let settingsNotificationsRulesTitle = LocalizedStringKey("settings.notifications.rules.title")
    static let settingsNotificationsRulesDescription = LocalizedStringKey("settings.notifications.rules.description")
    static let settingsArticleRetentionTitle = LocalizedStringKey("settings.articleRetention.title")
    static let settingsArticleRetentionIntervalPicker = LocalizedStringKey("settings.articleRetention.interval.picker")
    static let settingsArticleRetentionIncludesProtectedArticles = LocalizedStringKey("settings.articleRetention.includesProtectedArticles")
    static let settingsArticleRetentionDescription = LocalizedStringKey("settings.articleRetention.description")
    static let settingsArticleRetentionRunNow = LocalizedStringKey("settings.articleRetention.runNow")
    static let settingsSyncSection = LocalizedStringKey("settings.sync.section")
    static let settingsSyncBetaTitle = LocalizedStringKey("settings.sync.beta.title")
    static let settingsSyncBetaDescription = LocalizedStringKey("settings.sync.beta.description")
    static let settingsSyncStatusTitle = LocalizedStringKey("settings.sync.status.title")
    static let settingsSyncRestartHint = LocalizedStringKey("settings.sync.restart.hint")
    static let settingsSyncDatabaseTitle = LocalizedStringKey("settings.sync.database.title")
    static let settingsSyncDatabaseErrorHint = LocalizedStringKey("settings.sync.databaseError.hint")
    static let feedProgressRefreshAllTitle = String(localized: "feed.progress.refreshAll.title")
    static let feedPropertiesDetailsTitle = LocalizedStringKey("feed.properties.detailsTitle")
    static let feedPropertiesOriginalTitle = LocalizedStringKey("feed.properties.originalTitle")
    static let feedPropertiesWebsite = LocalizedStringKey("feed.properties.website")
    static let feedPropertiesXMLAddress = LocalizedStringKey("feed.properties.xmlAddress")
    static let feedPropertiesFollowedAt = LocalizedStringKey("feed.properties.followedAt")
    static let feedPropertiesFolder = LocalizedStringKey("feed.properties.folder")
    static let feedPropertiesLatestArticle = LocalizedStringKey("feed.properties.latestArticle")
    static let feedPropertiesActivityTitle = LocalizedStringKey("feed.properties.activityTitle")
    static let feedPropertiesArticlesLastWeek = LocalizedStringKey("feed.properties.articlesLastWeek")
    static let feedPropertiesAverageArticlesPerWeek = LocalizedStringKey("feed.properties.averageArticlesPerWeek")
    static let feedPropertiesReadPercentage = LocalizedStringKey("feed.properties.readPercentage")
    static let feedPropertiesAverageReadingMinutes = LocalizedStringKey("feed.properties.averageReadingMinutes")
    static let feedPropertiesRefreshInterval = LocalizedStringKey("feed.properties.refreshInterval")
    static let feedPropertiesNextFetch = LocalizedStringKey("feed.properties.nextFetch")
    static let feedPropertiesLastRefreshed = LocalizedStringKey("feed.properties.lastRefreshed")
    static let feedPropertiesLogTitle = LocalizedStringKey("feed.properties.logTitle")
    static let feedPropertiesLogEntries = LocalizedStringKey("feed.properties.logEntries")
    static let feedPropertiesNoLogEntries = LocalizedStringKey("feed.properties.noLogEntries")
    static let feedPropertiesNotificationsEnabled = LocalizedStringKey("feed.properties.notifications.enabled")
    static let feedPropertiesNotificationsDescription = LocalizedStringKey("feed.properties.notifications.description")
    static let feedPropertiesArticleRetention = LocalizedStringKey("feed.properties.articleRetention")
    static let feedPropertiesArticleRetentionOverride = LocalizedStringKey("feed.properties.articleRetention.override")
    static let feedPropertiesArticleRetentionInherited = LocalizedStringKey("feed.properties.articleRetention.inherited")
    static let feedPropertiesArticleRetentionEnabled = LocalizedStringKey("feed.properties.articleRetention.enabled")

    static let articleRowStarRemove = String(localized: "articleRow.star.remove")
    static let articleRowStarAdd = String(localized: "articleRow.star.add")
    static let articleRowStarredText = String(localized: "articleRow.starred")
    static let articleRowUnreadText = String(localized: "articleRow.unread")
    static let articleRowOfflineAvailable = String(localized: "articleRow.offline.available")
    static let articleRowOfflineFailed = String(localized: "articleRow.offline.failed")
    static let articleRowMarkRead = String(localized: "articleRow.markRead")
    static let articleRowMarkUnread = String(localized: "articleRow.markUnread")
    static let articleListShowReadButtonFormat = String(localized: "articleList.showRead.button")
    static let articleListReadDisplayTitle = String(localized: "articleList.readDisplay.title")
    static let articleListReadDisplayUnreadOnly = String(localized: "articleList.readDisplay.unreadOnly")
    static let articleListReadDisplayAll = String(localized: "articleList.readDisplay.all")
    static let articleSearchPlaceholder = String(localized: "article.search.placeholder")
    static let articleSearchClear = String(localized: "article.search.clear")
    static let articleSearchFieldAll = String(localized: "article.search.field.all")
    static let articleSearchFieldTitle = String(localized: "article.search.field.title")
    static let articleSearchFieldSummary = String(localized: "article.search.field.summary")
    static let articleSearchFieldContent = String(localized: "article.search.field.content")
    static let articleSearchFeedAll = String(localized: "article.search.feed.all")
    static let articleSearchTagAll = String(localized: "article.search.tag.all")
    static let articleSearchDateAnytime = String(localized: "article.search.date.anytime")
    static let articleSearchDateToday = String(localized: "article.search.date.today")
    static let articleSearchDateThisWeek = String(localized: "article.search.date.thisWeek")
    static let articleSearchStatusAll = String(localized: "article.search.status.all")
    static let articleSearchStatusUnread = String(localized: "article.search.status.unread")
    static let articleSearchStatusRead = String(localized: "article.search.status.read")
    static let articleSearchStatusStarred = String(localized: "article.search.status.starred")
    static let articleSearchStatusArchived = String(localized: "article.search.status.archived")
    static let articleSearchNoResultsTitle = String(localized: "article.search.noResults.title")
    static let articleSearchOpenInReader = String(localized: "article.search.openInReader")
    static let articleSearchPreviewEmptyTitle = String(localized: "article.search.preview.emptyTitle")
    static let articleSearchPreviewEmptyDescription = String(localized: "article.search.preview.emptyDescription")
    static let articleCommandsMenu = String(localized: "articleCommands.menu")
    static let articlePreviousCommand = String(localized: "article.previous.command")
    static let articleNextCommand = String(localized: "article.next.command")
    static let articleSearchCommand = String(localized: "article.search.command")
    static let articleOpenInWindowCommand = String(localized: "article.openInWindow.command")
    static let articleCopyLinkCommand = String(localized: "article.copyLink.command")
    static let articleOpenOriginalCommand = String(localized: "article.openOriginal.command")
    static let articleArchiveCommand = String(localized: "article.archive.command")
    static let articleUnarchiveCommand = String(localized: "article.unarchive.command")
    static let articleExportCommand = String(localized: "article.export.command")
    static let articleExportSaveButton = String(localized: "article.export.save.button")
    static let articleExportPrepareTitle = String(localized: "article.export.prepare.title")
    static let articleExportPrepareMessage = String(localized: "article.export.prepare.message")
    static let articleExportPreviewTitle = String(localized: "article.export.preview.title")
    static let articleExportPreviewMessage = String(localized: "article.export.preview.message")
    static let articleExportStepOne = String(localized: "article.export.step.one")
    static let articleExportStepTwo = String(localized: "article.export.step.two")
    static let articleExportFormatMarkdown = String(localized: "article.export.format.markdown")
    static let articleExportFormatMarkdownDescription = String(localized: "article.export.format.markdown.description")
    static let articleExportMarkdownPreview = String(localized: "article.export.preview.markdown")
    static let articleExportFormatPlainText = String(localized: "article.export.format.plainText")
    static let articleExportFormatPlainTextDescription = String(localized: "article.export.format.plainText.description")
    static let articleExportPlainTextPreview = String(localized: "article.export.preview.plainText")
    static let articleExportFormatHTML = String(localized: "article.export.format.html")
    static let articleExportFormatHTMLDescription = String(localized: "article.export.format.html.description")
    static let articleExportHTMLPreview = String(localized: "article.export.preview.html")
    static let articleExportFormatPDF = String(localized: "article.export.format.pdf")
    static let articleExportFormatPDFDescription = String(localized: "article.export.format.pdf.description")
    static let articleExportPDFPreview = String(localized: "article.export.preview.pdf")
    static let articleExportFormatDOCX = String(localized: "article.export.format.docx")
    static let articleExportFormatDOCXDescription = String(localized: "article.export.format.docx.description")
    static let articleExportDOCXPreview = String(localized: "article.export.preview.docx")
    static let articleExportMetadataToggle = String(localized: "article.export.metadata.toggle")
    static let articleExportMetadataDescription = String(localized: "article.export.metadata.description")
    static let articleExportOfflineImagesToggle = String(localized: "article.export.offlineImages.toggle")
    static let articleExportOfflineImagesDescription = String(localized: "article.export.offlineImages.description")
    static let articleExportOfflineImagesLoading = String(localized: "article.export.offlineImages.loading")
    static let articleExportStatusPreparingDocument = String(localized: "article.export.status.preparingDocument")
    static let articleExportStatusDownloadingImage = String(localized: "article.export.status.downloadingImage")
    static let articleExportStatusCreatingArchive = String(localized: "article.export.status.creatingArchive")
    static let articleExportStatusOpeningSaveDialog = String(localized: "article.export.status.openingSaveDialog")
    static let articleExportSummaryFormat = String(localized: "article.export.summary.format")
    static let articleExportSummaryMetadata = String(localized: "article.export.summary.metadata")
    static let articleExportSummarySource = String(localized: "article.export.summary.source")
    static let articleExportSummaryImages = String(localized: "article.export.summary.images")
    static let articleExportSummaryImagesSaved = String(localized: "article.export.summary.images.saved")
    static let articleExportSummaryImagesPartial = String(localized: "article.export.summary.images.partial")
    static let articleExportSourceOffline = String(localized: "article.export.source.offline")
    static let articleExportSourceFeedContent = String(localized: "article.export.source.feedContent")
    static let articleExportSourceSummary = String(localized: "article.export.source.summary")
    static let articleAssignTagCommand = String(localized: "article.assignTag.command")
    static let articleCreateRuleCommand = String(localized: "article.createRule.command")
    static let articleShareCommand = String(localized: "article.share.command")
    static let articleDeleteCommand = String(localized: "article.delete.command")
    static let articleDeleteConfirmationTitle = String(localized: "article.delete.confirmation.title")
    static let articleMarkAllReadCommand = String(localized: "article.markAllRead.command")
    static let articleMarkReadMenuTitle = String(localized: "article.markRead.menu.title")
    static let articleMarkReadOlderThanOneDay = String(localized: "article.markRead.olderThanOneDay")
    static let articleMarkReadOlderThanTwoDays = String(localized: "article.markRead.olderThanTwoDays")
    static let articleMarkReadOlderThanThreeDays = String(localized: "article.markRead.olderThanThreeDays")
    static let articleMarkReadOlderThanFourDays = String(localized: "article.markRead.olderThanFourDays")
    static let articleMarkReadOlderThanOneWeek = String(localized: "article.markRead.olderThanOneWeek")
    static let articleMarkReadOlderThanTwoWeeks = String(localized: "article.markRead.olderThanTwoWeeks")
    static let viewCommandsMenu = String(localized: "viewCommands.menu")
    static let articleSortMenuTitle = String(localized: "articleSort.menu.title")
    static let articleSortNewestFirst = String(localized: "articleSort.newestFirst")
    static let articleSortOldestFirst = String(localized: "articleSort.oldestFirst")
    static let articleSortFeed = String(localized: "articleSort.feed")
    static let articleSortTitle = String(localized: "articleSort.title")
    static let articleSortShortReadingTimeFirst = String(localized: "articleSort.shortReadingTimeFirst")
    static let articleFilterMenuTitle = String(localized: "articleFilter.menu.title")
    static let articleFilterAll = String(localized: "articleFilter.all")
    static let articleFilterUnread = String(localized: "articleFilter.unread")
    static let articleFilterStarred = String(localized: "articleFilter.starred")
    static let articleFilterArchived = String(localized: "articleFilter.archived")
    static let articleFilterToday = String(localized: "articleFilter.today")
    static let readerDisplayModeToggleHelp = String(localized: "reader.displayMode.toggle.help")
    static let readerWebBackCommand = String(localized: "reader.web.back.command")
    static let readerWebForwardCommand = String(localized: "reader.web.forward.command")
    static let sidebarAddFolderDuplicateError = String(localized: "sidebar.addFolder.duplicateError")
    static let tagManagerEmptyNameError = String(localized: "tagManager.emptyName.error")
    static let tagManagerDuplicateNameError = String(localized: "tagManager.duplicateName.error")
    static let ruleValidationError = String(localized: "rule.validation.error")
    static func ruleRegexInvalidError(pattern: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "rule.regex.invalidError"),
            pattern
        )
    }
    static let feedErrorInvalidURL = String(localized: "feed.error.invalidURL")
    static let feedErrorParsingFailed = String(localized: "feed.error.parsingFailed")

    /// HTTP-Statuscode einer fehlgeschlagenen Feed-Abrufantwort (M6).
    static func feedErrorHTTPStatus(_ statusCode: Int) -> String {
        String.localizedStringWithFormat(String(localized: "feed.error.httpError"), statusCode)
    }
    static let feedErrorEmptyURL = String(localized: "feed.error.emptyURL")
    static let feedErrorAddFailed = String(localized: "feed.error.addFailed")
    static let feedErrorAlertTitle = String(localized: "feed.error.alertTitle")
    static var feedErrorDuplicate: String {
        String(localized: "feed.error.duplicate", defaultValue: "Dieser Feed wird bereits abonniert.")
    }
    static var offlineArchiveErrorTitle: String {
        String(localized: "offline.archive.error.title", defaultValue: "Archivieren fehlgeschlagen")
    }
    static var offlineArchiveErrorMessage: String {
        String(localized: "offline.archive.error.message", defaultValue: "Die Offline-Kopie konnte nicht gespeichert werden.")
    }
    /// Titel des Alarms, wenn die SQLite-Datenbank beim Start nicht geöffnet
    /// werden konnte und auf den In-Memory-Fallback ausgewichen wurde (M11).
    static var databaseInitErrorTitle: String {
        String(localized: "database.init.error.title", defaultValue: "Datenbank konnte nicht geladen werden")
    }
    /// Erläuterungstext zum Datenbank-Ladefehler im In-Memory-Fallback (M11).
    /// Im Alert wird die technische Fehlermeldung des Frameworks angehängt.
    static var databaseInitErrorMessage: String {
        String(localized: "database.init.error.message", defaultValue: "Deine gespeicherten Feeds sind vorerst nicht verfügbar. Die App läuft mit einer leeren, temporären Datenbank. Bitte starte die App neu.")
    }
    static var feedErrorAlreadyRunning: String {
        String(localized: "feed.error.alreadyRunning", defaultValue: "Eine Aktualisierung läuft bereits. Bitte warte, bis sie abgeschlossen ist.")
    }
    static var feedImportAlreadyRunning: String {
        String(localized: "feed.import.alreadyRunning", defaultValue: "Ein Import läuft bereits. Bitte warte, bis er abgeschlossen ist.")
    }
    static let feedDiscoveryErrorNoFeedsFound = String(localized: "feedDiscovery.error.noFeedsFound")
    static let feedCommandsMenu = String(localized: "feedCommands.menu")
    static let feedAddCommand = String(localized: "feed.add.command")
    static let feedRefreshAllCommand = String(localized: "feed.refreshAll.command")
    static let feedRefreshCommand = String(localized: "feed.refresh.command")
    static let feedErrorBadgeTooltip = String(localized: "feed.error.badge.tooltip")
    static let feedErrorRetryButton = String(localized: "feed.error.retry.button")
    static let feedErrorBannerMessage = String(localized: "feed.error.banner.message")
    static let feedRenameCommand = String(localized: "feed.rename.command")
    static let feedRenameDatabaseUnavailable = String(localized: "feed.rename.databaseUnavailable")
    static let feedRenameTitle = String(localized: "feed.rename.title")
    static let feedRenameDescription = String(localized: "feed.rename.description")
    static let feedRenameDisplayName = String(localized: "feed.rename.displayName")
    static let feedRenameOriginalName = String(localized: "feed.rename.originalName")
    static let feedRenameOriginalStored = String(localized: "feed.rename.originalStored")
    static let feedRenameRestoreOriginal = String(localized: "feed.rename.restoreOriginal")
    static let feedRenameSave = String(localized: "feed.rename.save")
    static let feedRenameEmptyName = String(localized: "feed.rename.emptyName")
    static let feedRenameNoChanges = String(localized: "feed.rename.noChanges")
    static let feedRenameChanged = String(localized: "feed.rename.changed")
    static let feedRenameRestored = String(localized: "feed.rename.restored")
    static let feedDeleteCommand = String(localized: "feed.delete.command")
    static let feedImportOPMLCommand = String(localized: "feed.importOPML.command")
    static let feedExportOPMLCommand = String(localized: "feed.exportOPML.command")
    static let opmlExportTitle = String(localized: "opml.export.title")
    static let opmlExportDescription = String(localized: "opml.export.description")
    static let opmlExportFeedsAndTitles = String(localized: "opml.export.feedsAndTitles")
    static let opmlExportFeedsAndTitlesDescription = String(localized: "opml.export.feedsAndTitles.description")
    static let opmlExportFolders = String(localized: "opml.export.folders")
    static let opmlExportFoldersDescription = String(localized: "opml.export.folders.description")
    static let opmlExportTags = String(localized: "opml.export.tags")
    static let opmlExportTagsDescription = String(localized: "opml.export.tags.description")
    static let opmlExportDescriptions = String(localized: "opml.export.descriptions")
    static let opmlExportDescriptionsDescription = String(localized: "opml.export.descriptions.description")
    static let opmlExportSummaryTitle = String(localized: "opml.export.summary.title")
    static let opmlExportSummaryFeeds = String(localized: "opml.export.summary.feeds")
    static let opmlExportSummaryFolders = String(localized: "opml.export.summary.folders")
    static let opmlExportSummaryTags = String(localized: "opml.export.summary.tags")
    static let opmlExportSummaryDescriptions = String(localized: "opml.export.summary.descriptions")
    static let opmlExportFooterNote = String(localized: "opml.export.footerNote")
    static let opmlExportSaveButton = String(localized: "opml.export.saveButton")
    static let feedPropertiesCommand = String(localized: "feed.properties.command")
    static let feedPropertiesCopyXMLAddress = String(localized: "feed.properties.copyXMLAddress")
    static let feedPropertiesNoFolder = String(localized: "feed.properties.noFolder")
    static let feedPropertiesUnavailable = String(localized: "feed.properties.unavailable")
    static func feedNotificationSummaryTitle(_ newArticleCount: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "notification.feedRefresh.summary.title"),
            newArticleCount
        )
    }
    static let ruleNotificationFallbackRuleName = String(localized: "notification.rule.fallbackRuleName")
    static func ruleNotificationSummaryTitle(count: Int, ruleName: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "notification.rule.summary.title"),
            count,
            ruleName
        )
    }
    static let feedLogAdded = String(localized: "feed.log.added")
    static let feedLogImportedFromOPML = String(localized: "feed.log.importedFromOPML")

    // MARK: OPML-Import-Preview-Controller (Plain-Strings)
    // Diese Strings sind Plain-String-Zuweisungen an Controller-Properties
    // (keine `Text(...)`-Views) und werden von Xcode deshalb nicht auto-
    // extrahiert. Zugriff hier über `String(localized:)`.
    // Plural-Keys (feedsRecognized/checkStart/feedsChecked) liegen als
    // `variations.plural` in der xcstrings; Aufruf via
    // `String.localizedStringWithFormat(String(localized:), count)`.
    static let opmlImportFilterAll = String(localized: "opml.import.filter.all")
    static let opmlImportFilterAvailable = String(localized: "opml.import.filter.available")
    static let opmlImportFilterDuplicates = String(localized: "opml.import.filter.duplicates")
    static let opmlImportFilterUnreachable = String(localized: "opml.import.filter.unreachable")
    static let opmlImportSheetSourceDescription = String(localized: "opml.import.sheet.sourceDescription")
    static let opmlImportSheetProgressEmpty = String(localized: "opml.import.sheet.progressEmpty")
    static let opmlImportSheetNoFileName = String(localized: "opml.import.sheet.noFileName")
    static let opmlImportFirstRunSourceDescription = String(localized: "opml.import.firstRun.sourceDescription")
    static let opmlImportFirstRunProgressEmpty = String(localized: "opml.import.firstRun.progressEmpty")
    static let opmlImportProgressReadingFile = String(localized: "opml.import.progress.readingFile")
    static let opmlImportProgressPreparing = String(localized: "opml.import.progress.preparing")
    static let opmlImportProgressCheckDone = String(localized: "opml.import.progress.checkDone")
    static let opmlImportErrorUnreadable = String(localized: "opml.import.error.unreadable")
    static let opmlImportErrorDropFormat = String(localized: "opml.import.error.dropFormat")
    static let opmlImportSummaryFeedsChecked = String(localized: "opml.import.summary.feedsChecked")
    static let opmlImportSummaryDuplicates = String(localized: "opml.import.summary.duplicates")
    static let opmlImportSummaryUnreachable = String(localized: "opml.import.summary.unreachable")
    static let opmlImportSummarySelected = String(localized: "opml.import.summary.selected")
    static let opmlImportNewFolder = String(localized: "opml.import.newFolder")
    static let opmlImportCreateFolder = String(localized: "opml.import.createFolder")
    static let opmlImportSelectAll = String(localized: "opml.import.selectAll")
    static let opmlImportDeselectAll = String(localized: "opml.import.deselectAll")

    /// Zusammengesetzte Source-Description für die fertige Vorschau-Zeile
    /// (`%lld Feeds · %lld Ordner · Dateiname`). Eigener Plain-Key vermeidet
    /// String-Zerlegung via `components(separatedBy:)`.

    // MARK: OPMLImportReview-Cluster (Task 8): Header, Status, Drop-Overlay,
    // FilePicker, Toolbar, TableHeader, Empty/EmptyFilter, Preparing, Footer
    // Toggles, Cancel, Selection-Summary, Result-Bausteine.
    // `opmlImportSelectAll`/`DeselectAll`/`NewFolder`/`CreateFolder` kommen aus
    // Task 9 (oben). Die drei Plural-Strings `opml.import.status.duplicate`,
    // `opml.import.status.unreachable`, `opml.import.button.import` werden
    // inline via `String.localizedStringWithFormat(String(localized:), count)`
    // aufgerufen und haben bewusst keinen Accessor.
    static let opmlImportAllowDuplicates = String(localized: "opml.import.allowDuplicates")
    static let opmlImportAllowUnreachable = String(localized: "opml.import.allowUnreachable")
    static let opmlImportButtonImporting = String(localized: "opml.import.button.importing")
    static let opmlImportCancel = String(localized: "opml.import.cancel")
    static let opmlImportChooseFile = String(localized: "opml.import.chooseFile")
    static let opmlImportDescription = String(localized: "opml.import.description")
    static let opmlImportDropOverlayHint = String(localized: "opml.import.dropOverlay.hint")
    static let opmlImportDropOverlayTitle = String(localized: "opml.import.dropOverlay.title")
    static let opmlImportEmptyFilterSubtitle = String(localized: "opml.import.emptyFilter.subtitle")
    static let opmlImportEmptyFilterTitle = String(localized: "opml.import.emptyFilter.title")
    static let opmlImportEmptySubtitle = String(localized: "opml.import.empty.subtitle")
    static let opmlImportEmptyTitle = String(localized: "opml.import.empty.title")
    static let opmlImportPreparing = String(localized: "opml.import.preparing")
    static let opmlImportRefreshAfter = String(localized: "opml.import.refreshAfter")
    static let opmlImportRemoveFile = String(localized: "opml.import.removeFile")
    static let opmlImportResultComplete = String(localized: "opml.import.result.complete")
    static let opmlImportResultDuplicatesImported = String(localized: "opml.import.result.duplicatesImported")
    static let opmlImportResultDuplicatesSkipped = String(localized: "opml.import.result.duplicatesSkipped")
    static let opmlImportResultFoldersUsed = String(localized: "opml.import.result.foldersUsed")
    static let opmlImportResultRefreshOff = String(localized: "opml.import.result.refreshOff")
    static let opmlImportResultRefreshOn = String(localized: "opml.import.result.refreshOn")
    static let opmlImportResultUnreachableImported = String(localized: "opml.import.result.unreachableImported")
    static let opmlImportResultUnreachableSkipped = String(localized: "opml.import.result.unreachableSkipped")
    static let opmlImportSelectionAll = String(localized: "opml.import.selection.all")
    static let opmlImportSelectionVisible = String(localized: "opml.import.selection.visible")
    static let opmlImportStatusLabel = String(localized: "opml.import.statusLabel")
    static let opmlImportStatusNoFile = String(localized: "opml.import.status.noFile")
    static let opmlImportStatusReady = String(localized: "opml.import.status.ready")
    static let opmlImportTableHeaderFeed = String(localized: "opml.import.tableHeader.feed")
    static let opmlImportTableHeaderFolder = String(localized: "opml.import.tableHeader.folder")
    static let opmlImportTableHeaderStatus = String(localized: "opml.import.tableHeader.status")
    static let opmlImportTableHeaderWebsite = String(localized: "opml.import.tableHeader.website")
    static let opmlImportTitle = String(localized: "opml.import.title")

    static let feedDeleteConfirmButton = String(localized: "feed.delete.confirmButton")
    static let feedDeleteConfirmationTitle = String(localized: "feed.delete.confirmation.title")

    static func opmlImportResultMessage(imported: Int, skippedDuplicates: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "opml.import.result.message"),
            imported,
            skippedDuplicates
        )
    }

    static func opmlExportFeedCount(_ count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "opml.export.feedCount"),
            count
        )
    }

    static func opmlExportFolderCount(_ count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "opml.export.folderCount"),
            count
        )
    }

    static func opmlExportTagCount(_ count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "opml.export.tagCount"),
            count
        )
    }

    static func feedDeleteConfirmationMessage(feedTitle: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "feed.delete.confirmation.message"),
            feedTitle
        )
    }

    static func articleDeleteConfirmationMessage(articleTitle: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "article.delete.confirmation.message"),
            articleTitle
        )
    }

    static func feedErrorRefreshAllPartial(_ count: Int, feedTitles: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "feed.error.refreshAllPartial"),
            count,
            feedTitles
        )
    }

    static func feedLogRefreshed(newArticleCount: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "feed.log.refreshed"),
            newArticleCount
        )
    }

    static func refreshStatusRunning(_ countText: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "refreshStatus.running"),
            countText
        )
    }

    static func refreshStatusNewArticles(_ count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "refreshStatus.newArticles"),
            count
        )
    }

    static func refreshStatusPartial(newArticleCount: Int, failedFeedCount: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "refreshStatus.partial"),
            newArticleCount,
            failedFeedCount
        )
    }

    static func settingsAutomaticRefreshInterval(minutes: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "settings.automaticRefresh.interval.minutes"),
            minutes
        )
    }

    static func settingsArticleRetentionInterval(days: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "settings.articleRetention.interval.days"),
            days
        )
    }

    static func settingsArticleRetentionResult(count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "settings.articleRetention.result"),
            count
        )
    }

    static func settingsCacheLimit(megabytes: Int) -> String {
        if megabytes >= 1_024, megabytes.isMultiple(of: 1_024) {
            return String.localizedStringWithFormat(
                String(localized: "settings.cache.limit.gigabytes"),
                megabytes / 1_024
            )
        }

        return String.localizedStringWithFormat(
            String(localized: "settings.cache.limit.megabytes"),
            megabytes
        )
    }

    static func readerReadingTime(minutes: Int) -> String {
        String.localizedStringWithFormat(String(localized: "reader.readingTime"), minutes)
    }

    static func ruleApplyExistingResult(count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "rule.applyExisting.result"), count)
    }

    static let ruleWizardPreviewError = String(localized: "ruleWizard.preview.error")

    static func ruleWizardPreviewMatchCount(count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "ruleWizard.preview.matchCount"), count)
    }

    static func smartFolderPreviewMatchCount(count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "smartFolder.preview.matches"), count)
    }

    static func settingsFeedsSelectedCount(count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "settings.feeds.selectedCount"), count)
    }

    static func feedPropertiesArticlesLastWeekCount(_ count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "feed.properties.articlesLastWeek.count"), count)
    }

    static func articleSearchNoResultsDescription(_ query: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "article.search.noResults.description"),
            query
        )
    }

    /// Trefferanzahl im Suchfenster (`%lld Treffer` / `%lld matches`) — Plural-Key.
    static func articleSearchMatchCount(_ count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "article.search.matchCount"), count)
    }

    static func settingsFeedsDeleteConfirmationMessage(count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "settings.feeds.deleteConfirmation.message"), count)
    }

    // SmartFolder-Condition-Felder/Operatoren/Werte (berechnete Enum-Titel,
    // nicht auto-extrahiert) sowie Formatter-Kleber. Als `String(localized:)`,
    // weil sie z. T. in zusammengesetzten Summaries genutzt werden.
    static let smartFolderFieldTag = String(localized: "smartfolder.field.tag")
    static let smartFolderFieldFeed = String(localized: "smartfolder.field.feed")
    static let smartFolderFieldFeedFolder = String(localized: "smartfolder.field.feedFolder")
    static let smartFolderFieldDate = String(localized: "smartfolder.field.date")
    static let smartFolderFieldStatus = String(localized: "smartfolder.field.status")
    static let smartFolderFieldTitle = String(localized: "smartfolder.field.title")
    static let smartFolderFieldText = String(localized: "smartfolder.field.text")
    static let smartFolderFieldAuthor = String(localized: "smartfolder.field.author")
    static let smartFolderOperatorIs = String(localized: "smartfolder.operator.is")
    static let smartFolderOperatorIsNot = String(localized: "smartfolder.operator.isNot")
    static let smartFolderOperatorContains = String(localized: "smartfolder.operator.contains")
    static let smartFolderOperatorNotContains = String(localized: "smartfolder.operator.notContains")
    static let smartFolderOperatorStartsWith = String(localized: "smartfolder.operator.startsWith")
    static let smartFolderOperatorEndsWith = String(localized: "smartfolder.operator.endsWith")
    static let smartFolderOperatorOlderThanDays = String(localized: "smartfolder.operator.olderThanDays")
    static let smartFolderStatusUnread = String(localized: "smartfolder.status.unread")
    static let smartFolderStatusRead = String(localized: "smartfolder.status.read")
    static let smartFolderStatusStarred = String(localized: "smartfolder.status.starred")
    static let smartFolderStatusArchived = String(localized: "smartfolder.status.archived")
    static let smartFolderStatusHidden = String(localized: "smartfolder.status.hidden")
    static let smartFolderDateToday = String(localized: "smartfolder.date.today")
    static let smartFolderDateThisWeek = String(localized: "smartfolder.date.thisWeek")
    static let smartFolderSummaryAllArticles = String(localized: "smartfolder.summary.allArticles")
    static let smartFolderSummaryAll = String(localized: "smartfolder.summary.all")
    static let smartFolderSummaryAny = String(localized: "smartfolder.summary.any")
    static let smartFolderPlaceholderTag = String(localized: "smartfolder.placeholder.tag")
    static let smartFolderPlaceholderFeed = String(localized: "smartfolder.placeholder.feed")
    static let smartFolderPlaceholderFeedFolder = String(localized: "smartfolder.placeholder.feedFolder")
    static let smartFolderPlaceholderDate = String(localized: "smartfolder.placeholder.date")
    static let smartFolderPlaceholderStatus = String(localized: "smartfolder.placeholder.status")
    static let smartFolderPlaceholderTitle = String(localized: "smartfolder.placeholder.title")
    static let smartFolderPlaceholderText = String(localized: "smartfolder.placeholder.text")
    static let smartFolderPlaceholderAuthor = String(localized: "smartfolder.placeholder.author")

    // RuleSettingsFormatter: berechnete Feld/Operator-Titel + Summary-Kleber.
    static let ruleFieldTitle = String(localized: "rule.field.title")
    static let ruleFieldSummary = String(localized: "rule.field.summary")
    static let ruleFieldAuthor = String(localized: "rule.field.author")
    static let ruleFieldLink = String(localized: "rule.field.link")
    static let ruleFieldFeedTitle = String(localized: "rule.field.feedTitle")
    static let ruleOperatorContains = String(localized: "rule.operator.contains")
    static let ruleOperatorNotContains = String(localized: "rule.operator.notContains")
    static let ruleOperatorEquals = String(localized: "rule.operator.equals")
    static let ruleOperatorStartsWith = String(localized: "rule.operator.startsWith")
    static let ruleOperatorEndsWith = String(localized: "rule.operator.endsWith")
    static let ruleOperatorRegex = String(localized: "rule.operator.regex")
    static let ruleSummaryNoCondition = String(localized: "rule.summary.noCondition")
    static let ruleSummaryAll = String(localized: "rule.summary.all")
    static let ruleSummaryAny = String(localized: "rule.summary.any")

    // SmartFolderSettings-Cluster (Task 4): Titel, Beschreibung, Aktionen,
    // ListHeader, Standard-/Eigener Ordner, Drag-Help.
    static let smartFolderSettingsTitle = LocalizedStringKey("smartFolder.settings.title")
    static let smartFolderSettingsDescription = LocalizedStringKey("smartFolder.settings.description")
    static let smartFolderRestoreDefaults = LocalizedStringKey("smartFolder.restoreDefaults")
    static let smartFolderNewFolder = LocalizedStringKey("smartFolder.newFolder")
    static let smartFolderListHeaderOrder = LocalizedStringKey("smartFolder.listHeader.order")
    static let smartFolderListHeaderSidebar = LocalizedStringKey("smartFolder.listHeader.sidebar")
    static let smartFolderListHeaderName = LocalizedStringKey("smartFolder.listHeader.name")
    static let smartFolderListHeaderConditions = LocalizedStringKey("smartFolder.listHeader.conditions")
    static let smartFolderListHeaderMatches = LocalizedStringKey("smartFolder.listHeader.matches")
    static let smartFolderShowInSidebar = LocalizedStringKey("smartFolder.showInSidebar")
    static let smartFolderStandardFolder = LocalizedStringKey("smartFolder.standardFolder")
    static let smartFolderCustomFolder = LocalizedStringKey("smartFolder.customFolder")
    static let smartFolderDragToSort = LocalizedStringKey("smartFolder.dragToSort")

    // SmartFolderEditor-Cluster (Task 5): Editor-Titel, Beschreibung,
    // Name-Placeholder, Appearance, Match-Mode-Operator, Bedingungen,
    // UND/ODER, Live-Vorschau, Speichern. `smartFolder.preview.matches`
    // ist ein Plural-Key (Aufruf via `String.localizedStringWithFormat`).
    static let smartFolderEditorCreate = LocalizedStringKey("smartFolder.editor.create")
    static let smartFolderEditorEdit = LocalizedStringKey("smartFolder.editor.edit")
    static let smartFolderEditorDescription = LocalizedStringKey("smartFolder.editor.description")
    static let smartFolderFieldName = LocalizedStringKey("smartFolder.field.name")
    static let smartFolderFieldNamePlaceholder = LocalizedStringKey("smartFolder.field.namePlaceholder")
    static let smartFolderAppearance = LocalizedStringKey("smartFolder.appearance")
    static let smartFolderAppearanceIcon = LocalizedStringKey("smartFolder.appearance.icon")
    static let smartFolderAppearanceColor = LocalizedStringKey("smartFolder.appearance.color")
    static let smartFolderMatchModeOperator = LocalizedStringKey("smartFolder.matchMode.operator")
    static let smartFolderMatchModeAll = LocalizedStringKey("smartFolder.matchMode.all")
    static let smartFolderMatchModeAny = LocalizedStringKey("smartFolder.matchMode.any")
    static let smartFolderConditions = LocalizedStringKey("smartFolder.conditions")
    static let smartFolderConditionsAdd = LocalizedStringKey("smartFolder.conditions.add")
    static let smartFolderConditionsRemove = LocalizedStringKey("smartFolder.conditions.remove")
    static let smartFolderPreview = LocalizedStringKey("smartFolder.preview")
    static let smartFolderSave = LocalizedStringKey("smartFolder.save")

    // RuleSettings-Cluster (Task 6): Beschreibung, ListHeader (Reihenfolge,
    // Aktiv, Regel, Aktion, Treffer), fehlendes Tag, Nach-oben/Nach-unten-Help.
    // `common.duplicate` für den Duplizieren-Button wird aus Task 3 weiterverwendet.
    static let ruleSettingsDescription = LocalizedStringKey("rule.settings.description")
    static let ruleListHeaderOrder = LocalizedStringKey("rule.listHeader.order")
    static let ruleListHeaderActive = LocalizedStringKey("rule.listHeader.active")
    static let ruleListHeaderRule = LocalizedStringKey("rule.listHeader.rule")
    static let ruleListHeaderAction = LocalizedStringKey("rule.listHeader.action")
    static let ruleListHeaderMatches = LocalizedStringKey("rule.listHeader.matches")
    static let ruleActionMissingTag = LocalizedStringKey("rule.action.missingTag")
    static let ruleMoveUp = LocalizedStringKey("rule.moveUp")
    static let ruleMoveDown = LocalizedStringKey("rule.moveDown")

    // MARK: FirstRun-Cluster (Task 7): Titel, Leads, Rail, Karten, Drop-Zone,
    // Settings-Lines, Refresh-After, Toolbar, Summary-Metrics, Finish-Card,
    // Hints, Empty/EmptyFilter, Preparing, Footer, Primary-Button, Filter,
    // Problem-Meldungen. Alle als Plain-`String(localized:)` angelegt, da sie
    // teilweise in zusammengesetzten Strings/Kontrollern genutzt werden.
    // `firstRun.selectedCount`/`intervalMinutes`/`problem.skippedDuplicates`
    // sind Plural-Keys (Aufruf via `String.localizedStringWithFormat`).
    static let firstRunBack = String(localized: "firstRun.back")
    static let firstRunCardAddFeedSubtitle = String(localized: "firstRun.card.addFeed.subtitle")
    static let firstRunCardAddFeedTitle = String(localized: "firstRun.card.addFeed.title")
    static let firstRunCardImportOPMLSubtitle = String(localized: "firstRun.card.importOPML.subtitle")
    static let firstRunCardImportOPMLTitle = String(localized: "firstRun.card.importOPML.title")
    static let firstRunCardLaterSubtitle = String(localized: "firstRun.card.later.subtitle")
    static let firstRunCardLaterTitle = String(localized: "firstRun.card.later.title")
    static let firstRunCreateFolder = String(localized: "firstRun.createFolder")
    static let firstRunDeselectAll = String(localized: "firstRun.deselectAll")
    static let firstRunDropHere = String(localized: "firstRun.dropHere")
    static let firstRunDropHint = String(localized: "firstRun.dropHint")
    static let firstRunDropOverlayHint = String(localized: "firstRun.dropOverlay.hint")
    static let firstRunDropOverlayTitle = String(localized: "firstRun.dropOverlay.title")
    static let firstRunEditSelection = String(localized: "firstRun.editSelection")
    static let firstRunEmptyFilterSubtitle = String(localized: "firstRun.emptyFilter.subtitle")
    static let firstRunEmptyFilterTitle = String(localized: "firstRun.emptyFilter.title")
    static let firstRunEmptyPreviewSubtitle = String(localized: "firstRun.emptyPreview.subtitle")
    static let firstRunEmptyPreviewTitle = String(localized: "firstRun.emptyPreview.title")
    static let firstRunFeedAddressChecking = String(localized: "firstRun.feedAddress.checking")
    static let firstRunFeedCheck = String(localized: "firstRun.feedCheck")
    static let firstRunFilterAll = String(localized: "firstRun.filter.all")
    static let firstRunFilterDuplicates = String(localized: "firstRun.filter.duplicates")
    static let firstRunFilterNew = String(localized: "firstRun.filter.new")
    static let firstRunFilterUnreachable = String(localized: "firstRun.filter.unreachable")
    static let firstRunFinishDescription = String(localized: "firstRun.finish.description")
    static let firstRunFinishOkTitle = String(localized: "firstRun.finish.ok.title")
    static let firstRunFinishProblemsTitle = String(localized: "firstRun.finish.problems.title")
    static let firstRunHintsTitle = String(localized: "firstRun.hints.title")
    static let firstRunImportSummaryDescription = String(localized: "firstRun.importSummary.description")
    static let firstRunImportSummaryTitle = String(localized: "firstRun.importSummary.title")
    static let firstRunLater = String(localized: "firstRun.later")
    static let firstRunMetricDuplicates = String(localized: "firstRun.metric.duplicates")
    static let firstRunMetricDuplicatesImported = String(localized: "firstRun.metric.duplicatesImported")
    static let firstRunMetricFolders = String(localized: "firstRun.metric.folders")
    static let firstRunMetricFoldersUsed = String(localized: "firstRun.metric.foldersUsed")
    static let firstRunMetricFeedsImported = String(localized: "firstRun.metric.feedsImported")
    static let firstRunMetricSelectedFeeds = String(localized: "firstRun.metric.selectedFeeds")
    static let firstRunMetricUnreachable = String(localized: "firstRun.metric.unreachable")
    static let firstRunMetricUnreachableImported = String(localized: "firstRun.metric.unreachableImported")
    static let firstRunNoImportSubtitle = String(localized: "firstRun.noImport.subtitle")
    static let firstRunNoImportTitle = String(localized: "firstRun.noImport.title")
    static let firstRunOtherOPML = String(localized: "firstRun.otherOPML")
    static let firstRunPreparingTitle = String(localized: "firstRun.preparing.title")
    static let firstRunPrimaryCheck = String(localized: "firstRun.primary.check")
    static let firstRunPrimaryFinishShow = String(localized: "firstRun.primary.finishShow")
    static let firstRunPrimaryImport = String(localized: "firstRun.primary.import")
    static let firstRunPrimarySettings = String(localized: "firstRun.primary.settings")
    static let firstRunPrimaryStart = String(localized: "firstRun.primary.start")
    static let firstRunPrimaryWelcome = String(localized: "firstRun.primary.welcome")
    static let firstRunProblemNotRefreshed = String(localized: "firstRun.problem.notRefreshed")
    static let firstRunProblemSkippedDuplicates = String(localized: "firstRun.problem.skippedDuplicates")
    static let firstRunRailDefaultsSubtitle = String(localized: "firstRun.rail.defaults.subtitle")
    static let firstRunRailDefaultsTitle = String(localized: "firstRun.rail.defaults.title")
    static let firstRunRailFeedSubtitle = String(localized: "firstRun.rail.feed.subtitle")
    static let firstRunRailFeedTitle = String(localized: "firstRun.rail.feed.title")
    static let firstRunRailFinishSubtitle = String(localized: "firstRun.rail.finish.subtitle")
    static let firstRunRailFinishTitle = String(localized: "firstRun.rail.finish.title")
    static let firstRunRailOPMLSubtitle = String(localized: "firstRun.rail.opml.subtitle")
    static let firstRunRailOPMLTitle = String(localized: "firstRun.rail.opml.title")
    static let firstRunRailReviewSubtitle = String(localized: "firstRun.rail.review.subtitle")
    static let firstRunRailReviewTitle = String(localized: "firstRun.rail.review.title")
    static let firstRunRailStartSubtitle = String(localized: "firstRun.rail.start.subtitle")
    static let firstRunRailStartTitle = String(localized: "firstRun.rail.start.title")
    static let firstRunRefreshAfterSubtitle = String(localized: "firstRun.refreshAfter.subtitle")
    static let firstRunRefreshAfterTitle = String(localized: "firstRun.refreshAfter.title")
    static let firstRunSelectAll = String(localized: "firstRun.selectAll")
    static let firstRunSettingsAutoRefreshSubtitle = String(localized: "firstRun.settings.autoRefresh.subtitle")
    static let firstRunSettingsAutoRefreshTitle = String(localized: "firstRun.settings.autoRefresh.title")
    static let firstRunSettingsIntervalSubtitle = String(localized: "firstRun.settings.interval.subtitle")
    static let firstRunSettingsIntervalTitle = String(localized: "firstRun.settings.interval.title")
    static let firstRunSettingsMarkReadSubtitle = String(localized: "firstRun.settings.markRead.subtitle")
    static let firstRunSettingsMarkReadTitle = String(localized: "firstRun.settings.markRead.title")
    static let firstRunStatusfilter = String(localized: "firstRun.statusfilter")
    static let firstRunStepAddFeedLead = String(localized: "firstRun.step.addFeed.lead")
    static let firstRunStepAddFeedTitle = String(localized: "firstRun.step.addFeed.title")
    static let firstRunStepDefaultsLead = String(localized: "firstRun.step.defaults.lead")
    static let firstRunStepDefaultsTitle = String(localized: "firstRun.step.defaults.title")
    static let firstRunStepFinishLead = String(localized: "firstRun.step.finish.lead")
    static let firstRunStepFinishTitle = String(localized: "firstRun.step.finish.title")
    static let firstRunStepImportOPMLLead = String(localized: "firstRun.step.importOPML.lead")
    static let firstRunStepImportOPMLTitle = String(localized: "firstRun.step.importOPML.title")
    static let firstRunStepReviewLead = String(localized: "firstRun.step.review.lead")
    static let firstRunStepReviewTitle = String(localized: "firstRun.step.review.title")
    static let firstRunStepWelcomeLead = String(localized: "firstRun.step.welcome.lead")
    static let firstRunStepWelcomeTitle = String(localized: "firstRun.step.welcome.title")
    static let firstRunTableHeaderFeed = String(localized: "firstRun.tableHeader.feed")
    static let firstRunTableHeaderFolder = String(localized: "firstRun.tableHeader.folder")
    static let firstRunTableHeaderStatus = String(localized: "firstRun.tableHeader.status")
    static let firstRunTitlebarTitle = String(localized: "firstRun.titlebar.title")
}
