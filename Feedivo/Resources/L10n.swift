import SwiftUI

enum L10n {
    static let contentNoFeedSelectedTitle = LocalizedStringKey("content.noFeedSelected.title")
    static let contentNoFeedSelectedDescription = LocalizedStringKey("content.noFeedSelected.description")
    static let contentNoArticleSelectedTitle = LocalizedStringKey("content.noArticleSelected.title")
    static let contentNoArticleSelectedDescription = LocalizedStringKey("content.noArticleSelected.description")
    static let sidebarEmptyTitle = LocalizedStringKey("sidebar.empty.title")
    static let sidebarAddFeedButton = LocalizedStringKey("sidebar.addFeed.button")
    static let sidebarAddFeedTitle = LocalizedStringKey("sidebar.addFeed.title")
    static let sidebarAddFeedURLPlaceholder = LocalizedStringKey("sidebar.addFeed.url.placeholder")
    static let sidebarFoldersSection = LocalizedStringKey("sidebar.folders.section")
    static let sidebarAddFolderButton = LocalizedStringKey("sidebar.addFolder.button")
    static let sidebarAddFolderTitle = LocalizedStringKey("sidebar.addFolder.title")
    static let sidebarAddFolderNamePlaceholder = LocalizedStringKey("sidebar.addFolder.name.placeholder")
    static let sidebarSmartFiltersSection = LocalizedStringKey("sidebar.smartFilters.section")
    static let sidebarTagsSection = LocalizedStringKey("sidebar.tags.section")
    static let smartFilterAllArticles = LocalizedStringKey("smartFilter.allArticles")
    static let smartFilterUnread = LocalizedStringKey("smartFilter.unread")
    static let smartFilterStarred = LocalizedStringKey("smartFilter.starred")
    static let smartFilterToday = LocalizedStringKey("smartFilter.today")
    static let commonCancel = LocalizedStringKey("common.cancel")
    static let commonAdd = LocalizedStringKey("common.add")
    static let commonDone = LocalizedStringKey("common.done")
    static let articleListEmptyTitle = LocalizedStringKey("articleList.empty.title")
    static let articleListEmptyDescription = LocalizedStringKey("articleList.empty.description")
    static let articleRowUnread = LocalizedStringKey("articleRow.unread")
    static let readerOpenOriginal = LocalizedStringKey("reader.openOriginal")
    static let readerAppearanceButton = LocalizedStringKey("reader.appearance.button")
    static let readerAppearanceTitle = LocalizedStringKey("reader.appearance.title")
    static let readerTitleFontPicker = LocalizedStringKey("reader.titleFont.picker")
    static let readerBodyFontPicker = LocalizedStringKey("reader.bodyFont.picker")
    static let readerBodyFontSizeSlider = LocalizedStringKey("reader.bodyFontSize.slider")
    static let readerTitleLineSpacingSlider = LocalizedStringKey("reader.titleLineSpacing.slider")
    static let readerLineSpacingSlider = LocalizedStringKey("reader.lineSpacing.slider")
    static let readerContentWidthSlider = LocalizedStringKey("reader.contentWidth.slider")
    static let readerDisplayModePicker = LocalizedStringKey("reader.displayMode.picker")
    static let readerDisplayModeNative = LocalizedStringKey("reader.displayMode.native")
    static let readerDisplayModeWeb = LocalizedStringKey("reader.displayMode.web")
    static let readerInspectorButton = LocalizedStringKey("reader.inspector.button")
    static let readerInspectorTitle = LocalizedStringKey("reader.inspector.title")
    static let readerInspectorDescription = LocalizedStringKey("reader.inspector.description")
    static let readerInspectorFolder = LocalizedStringKey("reader.inspector.folder")
    static let readerInspectorNoFolder = LocalizedStringKey("reader.inspector.noFolder")
    static let readerInspectorTags = LocalizedStringKey("reader.inspector.tags")
    static let readerInspectorAddTagPlaceholder = LocalizedStringKey("reader.inspector.addTag.placeholder")
    static let readerInspectorNoTags = LocalizedStringKey("reader.inspector.noTags")
    static let readerFontSystem = LocalizedStringKey("reader.font.system")
    static let readerFontSerif = LocalizedStringKey("reader.font.serif")
    static let readerFontRounded = LocalizedStringKey("reader.font.rounded")
    static let readerFontMonospace = LocalizedStringKey("reader.font.monospace")
    static let tagManagerTitle = LocalizedStringKey("tagManager.title")
    static let tagManagerDescription = LocalizedStringKey("tagManager.description")
    static let tagManagerNamePlaceholder = LocalizedStringKey("tagManager.name.placeholder")
    static let tagManagerColor = LocalizedStringKey("tagManager.color")
    static let tagManagerNoTags = LocalizedStringKey("tagManager.noTags")
    static let tagManagerNewTag = LocalizedStringKey("tagManager.newTag")
    static let tagManagerDeleteTitle = LocalizedStringKey("tagManager.delete.title")
    static let tagManagerDeleteMessage = LocalizedStringKey("tagManager.delete.message")
    static let tagManagerDeleteButton = LocalizedStringKey("tagManager.delete.button")
    static let tagManagerManageButton = LocalizedStringKey("tagManager.manage.button")
    static let ruleMatchModeAll = LocalizedStringKey("rule.matchMode.all")
    static let ruleMatchModeAny = LocalizedStringKey("rule.matchMode.any")
    static let ruleConditionFieldTitle = LocalizedStringKey("rule.condition.field.title")
    static let ruleConditionFieldSummary = LocalizedStringKey("rule.condition.field.summary")
    static let ruleConditionFieldFeedTitle = LocalizedStringKey("rule.condition.field.feedTitle")
    static let ruleConditionOperatorContains = LocalizedStringKey("rule.condition.operator.contains")
    static let ruleConditionOperatorStartsWith = LocalizedStringKey("rule.condition.operator.startsWith")
    static let ruleConditionOperatorEndsWith = LocalizedStringKey("rule.condition.operator.endsWith")
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
    static let ruleWizardConditionsTitle = LocalizedStringKey("ruleWizard.conditions.title")
    static let ruleWizardTargetTitle = LocalizedStringKey("ruleWizard.target.title")
    static let ruleWizardSummaryTitle = LocalizedStringKey("ruleWizard.summary.title")
    static let ruleWizardNamePlaceholder = LocalizedStringKey("ruleWizard.name.placeholder")
    static let ruleWizardValuePlaceholder = LocalizedStringKey("ruleWizard.value.placeholder")
    static let ruleWizardAddCondition = LocalizedStringKey("ruleWizard.addCondition")
    static let ruleWizardRemoveCondition = LocalizedStringKey("ruleWizard.removeCondition")
    static let ruleWizardSave = LocalizedStringKey("ruleWizard.save")
    static let ruleWizardExistingTag = LocalizedStringKey("ruleWizard.existingTag")
    static let ruleWizardNewTag = LocalizedStringKey("ruleWizard.newTag")
    static let ruleWizardNewTagName = LocalizedStringKey("ruleWizard.newTagName")
    static let ruleWizardPreviewTitle = LocalizedStringKey("ruleWizard.preview.title")
    static let sidebarRulesSection = LocalizedStringKey("sidebar.rules.section")
    static let settingsReadingSection = LocalizedStringKey("settings.reading.section")
    static let settingsLanguageSection = LocalizedStringKey("settings.language.section")
    static let settingsLanguagePickerTitle = LocalizedStringKey("settings.language.picker.title")
    static let settingsLanguageSystem = LocalizedStringKey("settings.language.system")
    static let settingsLanguageGerman = LocalizedStringKey("settings.language.german")
    static let settingsLanguageEnglish = LocalizedStringKey("settings.language.english")
    static let settingsLanguageFrench = LocalizedStringKey("settings.language.french")
    static let settingsLanguageItalian = LocalizedStringKey("settings.language.italian")
    static let settingsAppearanceSection = LocalizedStringKey("settings.appearance.section")
    static let settingsInterfaceTextSizePicker = LocalizedStringKey("settings.interfaceTextSize.picker")
    static let settingsInterfaceTextSizeSmall = LocalizedStringKey("settings.interfaceTextSize.small")
    static let settingsInterfaceTextSizeStandard = LocalizedStringKey("settings.interfaceTextSize.standard")
    static let settingsInterfaceTextSizeLarge = LocalizedStringKey("settings.interfaceTextSize.large")
    static let settingsInterfaceTextSizeExtraLarge = LocalizedStringKey("settings.interfaceTextSize.extraLarge")
    static let settingsMarkReadOnOpenTitle = LocalizedStringKey("settings.markReadOnOpen.title")
    static let settingsMarkReadOnOpenDescription = LocalizedStringKey("settings.markReadOnOpen.description")
    static let settingsRefreshSection = LocalizedStringKey("settings.refresh.section")
    static let settingsAutomaticRefreshTitle = LocalizedStringKey("settings.automaticRefresh.title")
    static let settingsAutomaticRefreshIntervalPicker = LocalizedStringKey("settings.automaticRefresh.interval.picker")
    static let settingsAutomaticRefreshDescription = LocalizedStringKey("settings.automaticRefresh.description")
    static let settingsAutomaticRefreshLastRun = LocalizedStringKey("settings.automaticRefresh.lastRun")
    static let settingsAutomaticRefreshStatus = LocalizedStringKey("settings.automaticRefresh.status")
    static let settingsAutomaticRefreshNextRun = LocalizedStringKey("settings.automaticRefresh.nextRun")
    static let settingsAutomaticRefreshLastError = LocalizedStringKey("settings.automaticRefresh.lastError")
    static let settingsAutomaticRefreshNoDate = LocalizedStringKey("settings.automaticRefresh.noDate")
    static let settingsAutomaticRefreshStatusSuccess = LocalizedStringKey("settings.automaticRefresh.status.success")
    static let settingsAutomaticRefreshStatusFailed = LocalizedStringKey("settings.automaticRefresh.status.failed")
    static let settingsAutomaticRefreshStatusNever = LocalizedStringKey("settings.automaticRefresh.status.never")
    static let settingsGeneralSection = LocalizedStringKey("settings.general.section")
    static let settingsGeneralDescription = LocalizedStringKey("settings.general.description")
    static let settingsAppearanceDescription = LocalizedStringKey("settings.appearance.description")
    static let settingsFeedsSection = LocalizedStringKey("settings.feeds.section")
    static let settingsFeedsDescription = LocalizedStringKey("settings.feeds.description")
    static let settingsFeedsSearchPlaceholder = LocalizedStringKey("settings.feeds.search.placeholder")
    static let settingsFeedsSelectVisible = LocalizedStringKey("settings.feeds.selectVisible")
    static let settingsFeedsClearSelection = LocalizedStringKey("settings.feeds.clearSelection")
    static let settingsFeedsNoFeeds = LocalizedStringKey("settings.feeds.noFeeds")
    static let settingsFeedsNoMatches = LocalizedStringKey("settings.feeds.noMatches")
    static let settingsFeedsDeleteSelected = LocalizedStringKey("settings.feeds.deleteSelected")
    static let settingsFeedsDeleteConfirmationTitle = LocalizedStringKey("settings.feeds.deleteConfirmation.title")
    static let settingsRefreshDescription = LocalizedStringKey("settings.refresh.description")
    static let settingsAutomationSection = LocalizedStringKey("settings.automation.section")
    static let settingsAutomationDescription = LocalizedStringKey("settings.automation.description")
    static let settingsSyncSection = LocalizedStringKey("settings.sync.section")
    static let settingsSyncDescription = LocalizedStringKey("settings.sync.description")
    static let settingsSyncUnavailableTitle = LocalizedStringKey("settings.sync.unavailable.title")
    static let settingsSyncUnavailableDescription = LocalizedStringKey("settings.sync.unavailable.description")
    static let feedProgressRefreshAllTitle = String(localized: "feed.progress.refreshAll.title")
    static let feedProgressOPMLImportTitle = String(localized: "feed.progress.opmlImport.title")
    static let feedPropertiesTitle = LocalizedStringKey("feed.properties.title")
    static let feedPropertiesDetailsTitle = LocalizedStringKey("feed.properties.detailsTitle")
    static let feedPropertiesOriginalTitle = LocalizedStringKey("feed.properties.originalTitle")
    static let feedPropertiesWebsite = LocalizedStringKey("feed.properties.website")
    static let feedPropertiesXMLAddress = LocalizedStringKey("feed.properties.xmlAddress")
    static let feedPropertiesFollowedAt = LocalizedStringKey("feed.properties.followedAt")
    static let feedPropertiesFolder = LocalizedStringKey("feed.properties.folder")
    static let feedPropertiesLatestArticle = LocalizedStringKey("feed.properties.latestArticle")
    static let feedPropertiesRefreshInterval = LocalizedStringKey("feed.properties.refreshInterval")
    static let feedPropertiesNextFetch = LocalizedStringKey("feed.properties.nextFetch")
    static let feedPropertiesLastRefreshed = LocalizedStringKey("feed.properties.lastRefreshed")
    static let feedPropertiesLogTitle = LocalizedStringKey("feed.properties.logTitle")
    static let feedPropertiesLogEntries = LocalizedStringKey("feed.properties.logEntries")
    static let feedPropertiesNoLogEntries = LocalizedStringKey("feed.properties.noLogEntries")

    static var articleRowStarRemove: String { String(localized: "articleRow.star.remove") }
    static var articleRowStarAdd: String { String(localized: "articleRow.star.add") }
    static var articleRowStarredText: String { String(localized: "articleRow.starred") }
    static var articleRowUnreadText: String { String(localized: "articleRow.unread") }
    static var articleRowMarkRead: String { String(localized: "articleRow.markRead") }
    static var articleRowMarkUnread: String { String(localized: "articleRow.markUnread") }
    static var articleCommandsMenu: String { String(localized: "articleCommands.menu") }
    static var articlePreviousCommand: String { String(localized: "article.previous.command") }
    static var articleNextCommand: String { String(localized: "article.next.command") }
    static var articleCopyLinkCommand: String { String(localized: "article.copyLink.command") }
    static var articleOpenOriginalCommand: String { String(localized: "article.openOriginal.command") }
    static var readerDisplayModeToggleHelp: String { String(localized: "reader.displayMode.toggle.help") }
    static var sidebarAddFolderDuplicateError: String { String(localized: "sidebar.addFolder.duplicateError") }
    static var tagManagerEmptyNameError: String { String(localized: "tagManager.emptyName.error") }
    static var tagManagerDuplicateNameError: String { String(localized: "tagManager.duplicateName.error") }
    static var ruleValidationError: String { String(localized: "rule.validation.error") }
    static var ruleCreateFromArticle: String { String(localized: "rule.createFromArticle") }
    static var feedErrorInvalidURL: String { String(localized: "feed.error.invalidURL") }
    static var feedErrorParsingFailed: String { String(localized: "feed.error.parsingFailed") }
    static var feedErrorEmptyURL: String { String(localized: "feed.error.emptyURL") }
    static var feedErrorAddFailed: String { String(localized: "feed.error.addFailed") }
    static var feedCommandsMenu: String { String(localized: "feedCommands.menu") }
    static var feedAddCommand: String { String(localized: "feed.add.command") }
    static var feedRefreshAllCommand: String { String(localized: "feed.refreshAll.command") }
    static var feedRefreshCommand: String { String(localized: "feed.refresh.command") }
    static var feedRenameCommand: String { String(localized: "feed.rename.command") }
    static var feedRenameTitle: String { String(localized: "feed.rename.title") }
    static var feedRenameDescription: String { String(localized: "feed.rename.description") }
    static var feedRenameDisplayName: String { String(localized: "feed.rename.displayName") }
    static var feedRenameOriginalName: String { String(localized: "feed.rename.originalName") }
    static var feedRenameOriginalStored: String { String(localized: "feed.rename.originalStored") }
    static var feedRenameRestoreOriginal: String { String(localized: "feed.rename.restoreOriginal") }
    static var feedRenameSave: String { String(localized: "feed.rename.save") }
    static var feedRenameEmptyName: String { String(localized: "feed.rename.emptyName") }
    static var feedRenameNoChanges: String { String(localized: "feed.rename.noChanges") }
    static var feedRenameChanged: String { String(localized: "feed.rename.changed") }
    static var feedRenameRestored: String { String(localized: "feed.rename.restored") }
    static var feedDeleteCommand: String { String(localized: "feed.delete.command") }
    static var feedImportOPMLCommand: String { String(localized: "feed.importOPML.command") }
    static var feedExportOPMLCommand: String { String(localized: "feed.exportOPML.command") }
    static var feedPropertiesCommand: String { String(localized: "feed.properties.command") }
    static var feedPropertiesCopyXMLAddress: String { String(localized: "feed.properties.copyXMLAddress") }
    static var feedPropertiesNoFolder: String { String(localized: "feed.properties.noFolder") }
    static var feedPropertiesUnavailable: String { String(localized: "feed.properties.unavailable") }
    static var feedLogAdded: String { String(localized: "feed.log.added") }
    static var feedLogImportedFromOPML: String { String(localized: "feed.log.importedFromOPML") }
    static var opmlImportResultTitle: String { String(localized: "opml.import.result.title") }
    static var opmlImportFailedTitle: String { String(localized: "opml.import.failed.title") }
    static var feedDeleteConfirmButton: String { String(localized: "feed.delete.confirmButton") }
    static var feedDeleteConfirmationTitle: String { String(localized: "feed.delete.confirmation.title") }
    static var settingsFeedsArticleCountHelp: String { String(localized: "settings.feeds.articleCount.help") }

    static func opmlImportResultMessage(imported: Int, skippedDuplicates: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "opml.import.result.message"),
            imported,
            skippedDuplicates
        )
    }

    static func feedDeleteConfirmationMessage(feedTitle: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "feed.delete.confirmation.message"),
            feedTitle
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

    static func settingsAutomaticRefreshInterval(minutes: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "settings.automaticRefresh.interval.minutes"),
            minutes
        )
    }

    static func readerReadingTime(minutes: Int) -> String {
        String.localizedStringWithFormat(String(localized: "reader.readingTime"), minutes)
    }

    static func sidebarRulesActiveCount(count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "sidebar.rules.activeCount"), count)
    }

    static func ruleApplyExistingResult(count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "rule.applyExisting.result"), count)
    }

    static func ruleWizardPreviewMatchCount(count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "ruleWizard.preview.matchCount"), count)
    }

    static func settingsFeedsSelectedCount(count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "settings.feeds.selectedCount"), count)
    }

    static func settingsFeedsDeleteConfirmationMessage(count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "settings.feeds.deleteConfirmation.message"), count)
    }
}
