import SwiftData
import SwiftUI

private enum NewSettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case feeds
    case folders
    case offline
    case notifications
    case refresh
    case cleanup
    case rules
    case sync
    case about

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general:
            L10n.settingsGeneralSection
        case .appearance:
            "Anzeige"
        case .feeds:
            L10n.settingsFeedsSection
        case .folders:
            "Ordner"
        case .offline:
            L10n.settingsOfflineSection
        case .notifications:
            L10n.settingsNotificationsSection
        case .refresh:
            L10n.settingsRefreshSection
        case .cleanup:
            "Bereinigung"
        case .rules:
            "Regeln"
        case .sync:
            L10n.settingsSyncSection
        case .about:
            "Über"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "slider.horizontal.3"
        case .appearance:
            "eye"
        case .feeds:
            "square.grid.2x2"
        case .folders:
            "folder.badge.gearshape"
        case .offline:
            "arrow.down.circle"
        case .notifications:
            "bell.badge"
        case .refresh:
            "arrow.clockwise"
        case .cleanup:
            "trash"
        case .rules:
            "sparkles"
        case .sync:
            "icloud"
        case .about:
            "info.circle"
        }
    }
}

struct NewSettingsView: View {
    static let windowID = "feedivo-settings-new"

    private enum Layout {
        static let windowWidth: CGFloat = 1040
        static let windowHeight: CGFloat = 640
        static let contentWidth: CGFloat = 760
    }

    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @State private var selectedSection = NewSettingsSection.general

    var body: some View {
        TabView(selection: $selectedSection) {
            settingsTab(.general)
            settingsTab(.appearance)
            settingsTab(.feeds)
            settingsTab(.folders)
            settingsTab(.offline)
            settingsTab(.notifications)
            settingsTab(.refresh)
            settingsTab(.cleanup)
            settingsTab(.rules)
            settingsTab(.sync)
            settingsTab(.about)
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .frame(
            minWidth: Layout.windowWidth,
            idealWidth: Layout.windowWidth,
            minHeight: Layout.windowHeight,
            idealHeight: Layout.windowHeight
        )
    }

    @ViewBuilder
    private func settingsTab(_ section: NewSettingsSection) -> some View {
        ScrollView {
            settingsContent(for: section)
                .frame(maxWidth: Layout.contentWidth, alignment: .topLeading)
                .padding(.horizontal, 64)
                .padding(.vertical, 34)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .tabItem {
            Label(section.title, systemImage: section.systemImage)
        }
        .tag(section)
    }

    @ViewBuilder
    private func settingsContent(for section: NewSettingsSection) -> some View {
        switch section {
        case .general:
            NewGeneralSettingsView()
        case .appearance:
            NewAppearanceSettingsView()
        case .feeds:
            FeedManagementSettingsView()
        case .folders:
            VStack(alignment: .leading, spacing: 18) {
                SettingsSectionHeader(
                    title: "Ordner",
                    description: "Intelligente Ordner, Reihenfolge und Sichtbarkeit in der Seitenleiste verwalten."
                )
                SmartFolderSettingsView()
            }
        case .offline:
            NewOfflineSettingsView()
        case .notifications:
            NewNotificationSettingsView()
        case .refresh:
            NewRefreshSettingsView()
        case .cleanup:
            NewCleanupSettingsView()
        case .rules:
            NewRuleSettingsView()
        case .sync:
            NewSyncSettingsView()
        case .about:
            NewSettingsAboutView()
        }
    }
}

private struct NewSettingsBlock<Content: View>: View {
    let eyebrow: LocalizedStringKey
    var showsBottomDivider = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.7)

            content
        }
        .padding(.bottom, 22)
        .overlay(alignment: .bottom) {
            if showsBottomDivider {
                Divider()
            }
        }
        .padding(.bottom, 24)
    }
}

private struct NewSettingRow<Control: View>: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer(minLength: 0)
                control
            }
            .frame(width: 310, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NewInfoRow: View {
    let iconName: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(description)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct NewGeneralSettingsView: View {
    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true

    @AppStorage("appLanguage")
    private var appLanguageRawValue = AppLanguage.system.rawValue

    @AppStorage(ReaderDisplayMode.storageKey)
    private var readerDisplayModeRawValue = ReaderDisplayMode.defaultMode.rawValue

    @AppStorage(ArticleWindowSettings.restoreOpenArticleWindowsOnLaunchKey)
    private var restoreOpenArticleWindowsOnLaunch = ArticleWindowSettings.defaultRestoreOpenArticleWindowsOnLaunch

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewSettingsBlock(eyebrow: "System") {
                NewSettingRow(
                    title: L10n.settingsLanguagePickerTitle,
                    description: "Anzeigesprache wechseln. Ein App-Neustart wird empfohlen."
                ) {
                    Picker("", selection: $appLanguageRawValue) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.titleKey)
                                .tag(language.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170, alignment: .trailing)
                }

                NewSettingRow(
                    title: L10n.readerDisplayModePicker,
                    description: "Standardansicht für geöffnete Artikel."
                ) {
                    Picker("", selection: $readerDisplayModeRawValue) {
                        ForEach(ReaderDisplayMode.allCases) { mode in
                            Text(mode.titleKey)
                                .tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                }

                NewSettingRow(
                    title: L10n.settingsMarkReadOnOpenTitle,
                    description: L10n.settingsMarkReadOnOpenDescription
                ) {
                    Toggle("", isOn: $markArticleReadOnSelection)
                        .labelsHidden()
                }

                NewSettingRow(
                    title: L10n.settingsRestoreArticleWindowsTitle,
                    description: L10n.settingsRestoreArticleWindowsDescription
                ) {
                    Toggle("", isOn: $restoreOpenArticleWindowsOnLaunch)
                        .labelsHidden()
                }
            }

            NewCacheSettingsView()
        }
    }
}

private struct NewAppearanceSettingsView: View {
    @AppStorage(InterfaceTextSize.storageKey)
    private var interfaceTextSizeRawValue = InterfaceTextSize.defaultSize.rawValue

    @AppStorage(SidebarFeedVisibilitySettings.showsReadFeedsKey)
    private var showsReadFeedsInSidebar = SidebarFeedVisibilitySettings.defaultShowsReadFeeds

    @AppStorage(AppIconBadgeSettings.isEnabledKey)
    private var appIconBadgeIsEnabled = AppIconBadgeSettings.defaultIsEnabled

    @AppStorage(ReaderTypographySettings.titleFontPresetKey)
    private var readerTitleFontPresetRawValue = ReaderFontPreset.system.rawValue

    @AppStorage(ReaderTypographySettings.bodyFontPresetKey)
    private var readerBodyFontPresetRawValue = ReaderFontPreset.system.rawValue

    @AppStorage(ReaderTypographySettings.titleFontIsBoldKey)
    private var readerTitleFontIsBold = ReaderTypography.defaultTitleFontIsBold

    @AppStorage(ReaderTypographySettings.bodyFontIsBoldKey)
    private var readerBodyFontIsBold = ReaderTypography.defaultBodyFontIsBold

    @AppStorage(ReaderTypographySettings.bodyFontSizeKey)
    private var readerBodyFontSize = ReaderTypography.defaultBodyFontSize

    @AppStorage(ReaderTypographySettings.lineSpacingKey)
    private var readerLineSpacing = ReaderTypography.defaultLineSpacing

    @AppStorage(ReaderTypographySettings.contentWidthKey)
    private var readerContentWidth = ReaderTypography.defaultContentWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewSettingsBlock(eyebrow: "Oberfläche") {
                NewSettingRow(
                    title: L10n.settingsInterfaceTextSizePicker,
                    description: "App-weite Skalierung der Bedienoberfläche."
                ) {
                    Picker("", selection: $interfaceTextSizeRawValue) {
                        ForEach(InterfaceTextSize.allCases) { textSize in
                            Text(textSize.titleKey)
                                .tag(textSize.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                }

                NewSettingRow(
                    title: L10n.settingsSidebarShowsReadFeedsTitle,
                    description: L10n.settingsSidebarShowsReadFeedsDescription
                ) {
                    Toggle("", isOn: $showsReadFeedsInSidebar)
                        .labelsHidden()
                }

                NewSettingRow(
                    title: "Badge-Zähler am App-Icon anzeigen",
                    description: "Zeigt die Anzahl ungelesener Artikel im Dock."
                ) {
                    Toggle("", isOn: $appIconBadgeIsEnabled)
                        .labelsHidden()
                }
            }

            NewSettingsBlock(eyebrow: L10n.settingsReadingSection, showsBottomDivider: false) {
                NewSettingRow(title: L10n.readerTitleFontPicker, description: "Schriftfamilie und Gewicht für Artikeltitel.") {
                    HStack {
                        Picker("", selection: $readerTitleFontPresetRawValue) {
                            ForEach(ReaderFontPreset.allCases) { preset in
                                Text(preset.title)
                                    .tag(preset.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 120, alignment: .trailing)

                        Toggle("Fett", isOn: $readerTitleFontIsBold)
                    }
                }

                NewSettingRow(title: L10n.readerBodyFontPicker, description: "Schriftfamilie und Gewicht für den Artikeltext.") {
                    HStack {
                        Picker("", selection: $readerBodyFontPresetRawValue) {
                            ForEach(ReaderFontPreset.allCases) { preset in
                                Text(preset.title)
                                    .tag(preset.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 120, alignment: .trailing)

                        Toggle("Fett", isOn: $readerBodyFontIsBold)
                    }
                }

                NewSettingRow(title: L10n.readerBodyFontSizeSlider, description: "Größe des nativen Reader-Texts.") {
                    NewSlider(value: $readerBodyFontSize, range: ReaderTypography.bodyFontSizeRange, suffix: "px")
                }

                NewSettingRow(title: L10n.readerLineSpacingSlider, description: "Vertikaler Abstand im Fließtext.") {
                    NewSlider(value: $readerLineSpacing, range: ReaderTypography.lineSpacingRange, suffix: "px")
                }

                NewSettingRow(title: L10n.readerContentWidthSlider, description: "Breite der Lesespalte im Reader.") {
                    NewSlider(value: $readerContentWidth, range: ReaderTypography.contentWidthRange, suffix: "px")
                }
            }
        }
    }
}

private struct NewSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $value, in: range)
                .frame(width: 110)
            Text("\(Int(value)) \(suffix)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
        }
    }
}

private struct NewCacheSettingsView: View {
    @Environment(\.modelContext)
    private var modelContext

    @Query(filter: #Predicate<Article> { article in
        article.offlineStateRaw == "feedContent" || article.offlineStateRaw == "fullText"
    })
    private var offlineArticles: [Article]

    @AppStorage(ImageCacheSettings.limitMegabytesKey)
    private var cacheLimitMegabytes = ImageCacheSettings.defaultLimitMegabytes

    @State private var cacheSizeInBytes: Int64 = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewSettingsBlock(eyebrow: L10n.settingsCacheSection, showsBottomDivider: false) {
                NewSettingRow(title: L10n.settingsCacheCurrentSize, description: "Gespeicherte Bilder und Favicons.") {
                    Text(ImageCacheSettings.formattedByteCount(cacheSizeInBytes))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                NewSettingRow(title: "Offline-Artikel", description: "Bewusst offline gespeicherte Artikelinhalte.") {
                    Text(offlineArticleSummaryText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                NewSettingRow(title: L10n.settingsCacheLimitPicker, description: L10n.settingsCacheDescriptionDetail) {
                    Picker("", selection: $cacheLimitMegabytes) {
                        ForEach(ImageCacheSettings.allowedLimitMegabytes, id: \.self) { limitMegabytes in
                            Text(L10n.settingsCacheLimit(megabytes: limitMegabytes))
                                .tag(limitMegabytes)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170, alignment: .trailing)
                    .onChange(of: cacheLimitMegabytes) { _, newValue in
                        cacheLimitMegabytes = ImageCacheSettings.resolvedLimitMegabytes(newValue)
                        trimCacheToSelectedLimit()
                    }
                }

                HStack {
                    Spacer()
                    Button(L10n.settingsCacheRefreshSize) {
                        refreshCacheSize()
                    }
                    Button(L10n.settingsCacheClear, role: .destructive) {
                        clearCache()
                    }
                    .disabled(cacheSizeInBytes == 0)
                    Button("Offline-Kopien löschen", role: .destructive) {
                        clearOfflineCopies()
                    }
                    .disabled(offlineArticleSummary.articleCount == 0)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .task {
            refreshCacheSize()
        }
    }

    private var offlineArticleSummary: OfflineArticleStorageSummary {
        OfflineArticleStorage.summary(for: offlineArticles)
    }

    private var offlineArticleSummaryText: String {
        let summary = offlineArticleSummary
        let articleText = summary.articleCount == 1 ? "1 Artikel" : "\(summary.articleCount) Artikel"
        return "\(articleText) · \(ImageCacheSettings.formattedByteCount(summary.sizeInBytes))"
    }

    private func refreshCacheSize() {
        do {
            cacheSizeInBytes = try ImageCacheService.shared.cacheSizeInBytes()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearCache() {
        do {
            try ImageCacheService.shared.clearCache()
            refreshCacheSize()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearOfflineCopies() {
        let removedCount = OfflineArticleStorage.removeOfflineCopies(from: offlineArticles)
        guard removedCount > 0 else {
            return
        }

        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func trimCacheToSelectedLimit() {
        do {
            try ImageCacheService.shared.trimCache(
                toLimitInBytes: ImageCacheSettings.bytes(forMegabytes: cacheLimitMegabytes)
            )
            refreshCacheSize()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NewOfflineSettingsView: View {
    @AppStorage(OfflineReadingSettings.automaticallySaveStarredArticlesKey)
    private var automaticallySaveStarredArticles = OfflineReadingSettings.defaultAutomaticallySaveStarredArticles

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewSettingsBlock(eyebrow: L10n.settingsOfflineSection) {
                NewInfoRow(
                    iconName: "arrow.down.circle",
                    title: L10n.settingsOfflineManualTitle,
                    description: L10n.settingsOfflineManualDescription
                )

                NewInfoRow(
                    iconName: "doc.text",
                    title: L10n.settingsOfflineFeedContentTitle,
                    description: L10n.settingsOfflineFeedContentDescription
                )

                NewSettingRow(
                    title: L10n.settingsOfflineAutoSaveStarredTitle,
                    description: L10n.settingsOfflineAutoSaveStarredDescription
                ) {
                    Toggle("", isOn: $automaticallySaveStarredArticles)
                        .labelsHidden()
                }
            }
        }
    }
}

private struct NewNotificationSettingsView: View {
    @State private var feedNotificationAuthorizationStatus: FeedNotificationAuthorizationStatus = .unknown

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewSettingsBlock(eyebrow: L10n.settingsNotificationsSection) {
                NewSettingRow(
                    title: L10n.settingsNotificationsPermissionTitle,
                    description: notificationPermissionDescription
                ) {
                    if feedNotificationAuthorizationStatus == .notDetermined {
                        Button(L10n.settingsNotificationsPermissionRequest) {
                            Task {
                                _ = await FeedNotificationService.requestAuthorization()
                                await refreshNotificationAuthorizationStatus()
                            }
                        }
                    } else {
                        Text(permissionStatusText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                NewInfoRow(
                    iconName: "dot.radiowaves.left.and.right",
                    title: L10n.settingsNotificationsFeedTitle,
                    description: L10n.settingsNotificationsFeedDescription
                )

                NewInfoRow(
                    iconName: "slider.horizontal.3",
                    title: L10n.settingsNotificationsRulesTitle,
                    description: L10n.settingsNotificationsRulesDescription
                )
            }
        }
        .task {
            await refreshNotificationAuthorizationStatus()
        }
    }

    private var notificationPermissionDescription: LocalizedStringKey {
        switch feedNotificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            L10n.settingsNotificationsPermissionAllowed
        case .denied:
            L10n.settingsNotificationsPermissionDenied
        case .notDetermined:
            L10n.settingsNotificationsPermissionNotDetermined
        case .unknown:
            L10n.settingsNotificationsPermissionUnknown
        }
    }

    private var permissionStatusText: LocalizedStringKey {
        switch feedNotificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            L10n.settingsNotificationsPermissionAllowed
        case .denied:
            L10n.settingsNotificationsPermissionDenied
        case .notDetermined:
            L10n.settingsNotificationsPermissionNotDetermined
        case .unknown:
            L10n.settingsNotificationsPermissionUnknown
        }
    }

    private func refreshNotificationAuthorizationStatus() async {
        feedNotificationAuthorizationStatus = await FeedNotificationService.authorizationStatus()
    }
}

private struct NewRefreshSettingsView: View {
    @AppStorage(BackgroundRefreshSettings.isEnabledKey)
    private var backgroundRefreshIsEnabled = BackgroundRefreshSettings.defaultIsEnabled

    @AppStorage(BackgroundRefreshSettings.intervalMinutesKey)
    private var backgroundRefreshIntervalMinutes = BackgroundRefreshSettings.defaultIntervalMinutes

    @AppStorage(BackgroundRefreshSettings.lastAutomaticRefreshDateKey)
    private var lastAutomaticRefreshTimestamp = 0.0

    @AppStorage(BackgroundRefreshSettings.lastAutomaticRefreshStatusKey)
    private var lastAutomaticRefreshStatus = ""

    @AppStorage(BackgroundRefreshSettings.lastAutomaticRefreshErrorKey)
    private var lastAutomaticRefreshError = ""

    @AppStorage(BackgroundRefreshSettings.nextAutomaticRefreshDateKey)
    private var nextAutomaticRefreshTimestamp = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewSettingsBlock(eyebrow: L10n.settingsRefreshSection) {
                NewSettingRow(title: L10n.settingsAutomaticRefreshTitle, description: L10n.settingsAutomaticRefreshDescription) {
                    Toggle("", isOn: $backgroundRefreshIsEnabled)
                        .labelsHidden()
                }

                NewSettingRow(title: L10n.settingsAutomaticRefreshIntervalPicker, description: "Gilt als Standard für neue Feeds.") {
                    Picker("", selection: $backgroundRefreshIntervalMinutes) {
                        ForEach(BackgroundRefreshSettings.allowedIntervalMinutes, id: \.self) { intervalMinutes in
                            Text(L10n.settingsAutomaticRefreshInterval(minutes: intervalMinutes))
                                .tag(intervalMinutes)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140, alignment: .trailing)
                    .disabled(!backgroundRefreshIsEnabled)
                }

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aktualisierungsstatus")
                            .font(.system(size: 14))
                        Text("Letzter automatischer Lauf und nächste geplante Aktualisierung.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    VStack(spacing: 5) {
                        statusLine(title: L10n.settingsAutomaticRefreshLastRun, value: formattedRefreshDate(lastAutomaticRefreshTimestamp))
                        statusLine(title: L10n.settingsAutomaticRefreshStatus, value: automaticRefreshStatusText)
                        statusLine(title: L10n.settingsAutomaticRefreshNextRun, value: formattedRefreshDate(nextAutomaticRefreshTimestamp))

                        if (lastAutomaticRefreshStatus == BackgroundRefreshSettings.statusFailed
                            || lastAutomaticRefreshStatus == BackgroundRefreshSettings.statusPartial),
                           !lastAutomaticRefreshError.isEmpty {
                            statusLine(title: L10n.settingsAutomaticRefreshLastError, value: lastAutomaticRefreshError)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func statusLine(title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statusLine(title: LocalizedStringKey, value: LocalizedStringKey) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var automaticRefreshStatusText: LocalizedStringKey {
        switch lastAutomaticRefreshStatus {
        case BackgroundRefreshSettings.statusSuccess:
            L10n.settingsAutomaticRefreshStatusSuccess
        case BackgroundRefreshSettings.statusFailed:
            L10n.settingsAutomaticRefreshStatusFailed
        case BackgroundRefreshSettings.statusPartial:
            L10n.settingsAutomaticRefreshStatusPartial
        default:
            L10n.settingsAutomaticRefreshStatusNever
        }
    }

    private func formattedRefreshDate(_ timestamp: Double) -> String {
        guard timestamp > 0 else {
            return String(localized: "settings.automaticRefresh.noDate")
        }

        return Date(timeIntervalSince1970: timestamp).formatted(
            date: .abbreviated,
            time: .shortened
        )
    }
}

private struct NewSyncSettingsView: View {
    @Environment(DatabaseLoadState.self) private var databaseLoadState

    @AppStorage(CloudSyncSettings.isEnabledKey)
    private var cloudSyncIsEnabled = CloudSyncSettings.defaultIsEnabled

    private var hasDatabaseError: Bool {
        databaseLoadState.initializationError != nil
    }

    private var statusText: String {
        CloudSyncSettings.statusText(
            isEnabledAtLaunch: databaseLoadState.isCloudSyncEnabledAtLaunch,
            currentIsEnabled: cloudSyncIsEnabled,
            hasDatabaseError: hasDatabaseError
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewSettingsBlock(eyebrow: L10n.settingsSyncSection) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "icloud")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.settingsSyncBetaTitle)
                                .font(.system(size: 14, weight: .semibold))
                            Text(L10n.settingsSyncBetaDescription)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    NewSettingRow(
                        title: L10n.settingsSyncBetaTitle,
                        description: L10n.settingsSyncRestartHint
                    ) {
                        Toggle("", isOn: $cloudSyncIsEnabled)
                            .toggleStyle(.switch)
                    }

                    NewInfoRow(
                        iconName: hasDatabaseError ? "exclamationmark.triangle" : "checkmark.icloud",
                        title: L10n.settingsSyncStatusTitle,
                        description: LocalizedStringKey(statusText)
                    )

                    if hasDatabaseError {
                        NewInfoRow(
                            iconName: "internaldrive",
                            title: L10n.settingsSyncStatusTitle,
                            description: L10n.settingsSyncDatabaseErrorHint
                        )
                    }
                }
            }
        }
    }
}

private struct NewCleanupSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(ArticleRetentionSettings.isEnabledKey)
    private var articleRetentionIsEnabled = ArticleRetentionSettings.defaultIsEnabled

    @AppStorage(ArticleRetentionSettings.retentionDaysKey)
    private var articleRetentionDays = ArticleRetentionSettings.defaultRetentionDays

    @AppStorage(ArticleRetentionSettings.includesProtectedArticlesKey)
    private var articleRetentionIncludesProtectedArticles = ArticleRetentionSettings.defaultIncludesProtectedArticles

    @State private var retentionCleanupResult: String?
    @State private var retentionCleanupError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewSettingsBlock(eyebrow: "Alte Artikel", showsBottomDivider: false) {
                NewSettingRow(
                    title: L10n.settingsArticleRetentionTitle,
                    description: L10n.settingsArticleRetentionDescription
                ) {
                    Toggle("", isOn: $articleRetentionIsEnabled)
                        .labelsHidden()
                }

                NewSettingRow(
                    title: L10n.settingsArticleRetentionIntervalPicker,
                    description: "Artikel werden nach diesem Zeitraum automatisch entfernt."
                ) {
                    Picker(L10n.settingsArticleRetentionIntervalPicker, selection: $articleRetentionDays) {
                        ForEach(ArticleRetentionSettings.allowedRetentionDays, id: \.self) { days in
                            Text(L10n.settingsArticleRetentionInterval(days: days))
                                .tag(days)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160, alignment: .trailing)
                    .disabled(!articleRetentionIsEnabled)
                    .onChange(of: articleRetentionDays) {
                        articleRetentionDays = ArticleRetentionSettings.clampedRetentionDays(articleRetentionDays)
                    }
                }

                NewSettingRow(
                    title: L10n.settingsArticleRetentionIncludesProtectedArticles,
                    description: "Auch markierte oder geschützte Artikel in die Bereinigung einbeziehen."
                ) {
                    Toggle("", isOn: $articleRetentionIncludesProtectedArticles)
                        .labelsHidden()
                        .disabled(!articleRetentionIsEnabled)
                }

                NewSettingRow(
                    title: L10n.settingsArticleRetentionRunNow,
                    description: "Bereinigung direkt mit den aktuellen Einstellungen starten."
                ) {
                    Button(L10n.settingsArticleRetentionRunNow) {
                        runArticleRetentionCleanup()
                    }
                    .disabled(!articleRetentionIsEnabled)
                }

                if let retentionCleanupResult {
                    Text(retentionCleanupResult)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let retentionCleanupError {
                    Text(retentionCleanupError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private func runArticleRetentionCleanup() {
        do {
            let removedCount = try ArticleRetentionCleanupService.removeExpiredArticles(
                in: modelContext,
                isEnabled: articleRetentionIsEnabled,
                retentionDays: articleRetentionDays,
                includeProtectedArticles: articleRetentionIncludesProtectedArticles
            )
            retentionCleanupResult = L10n.settingsArticleRetentionResult(count: removedCount)
            retentionCleanupError = nil
        } catch {
            retentionCleanupResult = nil
            retentionCleanupError = error.localizedDescription
        }
    }
}

private struct NewRuleSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewSettingsBlock(eyebrow: L10n.settingsRulesSection, showsBottomDivider: false) {
                RuleSettingsView()
            }
        }
    }
}

private struct NewSettingsAboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewSettingsBlock(eyebrow: "Feedivo") {
                HStack(spacing: 14) {
                    Text("F")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Feedivo")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Nativer macOS RSS Reader mit Tags, Regeln, Offline-Lesen und OPML.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("M4 Polish & Release")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            NewSettingsBlock(eyebrow: "Release") {
                NewInfoRow(
                    iconName: "shippingbox",
                    title: "Verteilung",
                    description: "App Store oder private Verteilung ist noch zu entscheiden."
                )

                NewInfoRow(
                    iconName: "globe",
                    title: "Lokalisierung",
                    description: "Deutsch, Englisch, Französisch und Italienisch sind vorbereitet."
                )
            }
        }
    }
}

private struct SettingsSectionHeader: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }
}

private struct FeedManagementSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @Query(sort: \Feed.title) private var feeds: [Feed]

    @State private var viewModel = FeedViewModel()
    @State private var searchText = ""
    @State private var selectedFeedIDs: Set<UUID> = []
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingOPMLExportSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(
                title: L10n.settingsFeedsSection,
                description: L10n.settingsFeedsDescription
            )

            HStack(spacing: 10) {
                TextField(L10n.settingsFeedsSearchPlaceholder, text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Button(L10n.settingsFeedsSelectVisible) {
                    FeedManagementSettingsState.selectVisibleFeeds(
                        visibleFeeds,
                        selectedFeedIDs: &selectedFeedIDs
                    )
                }
                .disabled(visibleFeeds.isEmpty)

                Button(L10n.settingsFeedsClearSelection) {
                    FeedManagementSettingsState.clearSelection(&selectedFeedIDs)
                }
                .disabled(selectedFeedIDs.isEmpty)

                Button(L10n.feedExportOPMLCommand) {
                    isShowingOPMLExportSheet = true
                }
                .disabled(feeds.isEmpty)
            }

            if feeds.isEmpty {
                ContentUnavailableView(L10n.settingsFeedsNoFeeds, systemImage: "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if visibleFeeds.isEmpty {
                ContentUnavailableView(L10n.settingsFeedsNoMatches, systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleFeeds) { feed in
                        FeedManagementRow(
                            feed: feed,
                            isSelected: selectedFeedIDs.contains(feed.id)
                        ) { isSelected in
                            if isSelected {
                                selectedFeedIDs.insert(feed.id)
                            } else {
                                selectedFeedIDs.remove(feed.id)
                            }
                        }

                        if feed.persistentModelID != visibleFeeds.last?.persistentModelID {
                            Divider()
                                .padding(.leading, 36)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }

            HStack {
                Text(L10n.settingsFeedsSelectedCount(count: selectedFeeds.count))
                    .font(interfaceTextSize.font(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(L10n.settingsFeedsDeleteSelected, role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                .disabled(selectedFeeds.isEmpty)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog(
            L10n.settingsFeedsDeleteConfirmationTitle,
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.settingsFeedsDeleteSelected, role: .destructive) {
                deleteSelectedFeeds()
            }

            Button(L10n.commonCancel, role: .cancel) {}
        } message: {
            Text(L10n.settingsFeedsDeleteConfirmationMessage(count: selectedFeeds.count))
        }
        .sheet(isPresented: $isShowingOPMLExportSheet) {
            OPMLExportSheet(feeds: feeds) {
                isShowingOPMLExportSheet = false
            }
        }
    }

    private var visibleFeeds: [Feed] {
        FeedManagementSettingsState.filteredFeeds(feeds, searchText: searchText)
    }

    private var selectedFeeds: [Feed] {
        feeds.filter { feed in
            selectedFeedIDs.contains(feed.id)
        }
    }

    private func deleteSelectedFeeds() {
        let feedsToDelete = selectedFeeds
        for feed in feedsToDelete {
            viewModel.deleteFeed(feed, context: modelContext)
        }

        selectedFeedIDs.subtract(feedsToDelete.map(\.id))
    }
}

private struct FeedManagementRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let feed: Feed
    let isSelected: Bool
    let setSelected: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: setSelected
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(feed.title)
                    .font(interfaceTextSize.font(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(feed.url)
                    .font(interfaceTextSize.font(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(feedActivitySummary)
                    .font(interfaceTextSize.font(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
        .onTapGesture {
            setSelected(!isSelected)
        }
    }

    private var feedActivitySummary: String {
        let articlesLastWeek = FeedPropertiesQuery.recentArticleCount(
            in: modelContext,
            for: feed,
            since: Date().addingTimeInterval(-7 * 24 * 60 * 60)
        )
        let articleText = L10n.feedPropertiesArticlesLastWeekCount(articlesLastWeek)
        let lastRefreshed = feed.lastRefreshed?.formatted(date: .abbreviated, time: .shortened)
            ?? L10n.feedPropertiesUnavailable

        return "\(articleText) · \(String(localized: "feed.properties.lastRefreshed")): \(lastRefreshed)"
    }
}
