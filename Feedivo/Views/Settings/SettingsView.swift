import SwiftData
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case feeds
    case cache
    case offline
    case refresh
    case automation
    case sync

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general:
            L10n.settingsGeneralSection
        case .appearance:
            L10n.settingsAppearanceSection
        case .feeds:
            L10n.settingsFeedsSection
        case .cache:
            L10n.settingsCacheSection
        case .offline:
            L10n.settingsOfflineSection
        case .refresh:
            L10n.settingsRefreshSection
        case .automation:
            L10n.settingsAutomationSection
        case .sync:
            L10n.settingsSyncSection
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .appearance:
            "paintbrush"
        case .feeds:
            "list.bullet.rectangle"
        case .cache:
            "photo.stack"
        case .offline:
            "arrow.down.circle"
        case .refresh:
            "arrow.clockwise"
        case .automation:
            "tag"
        case .sync:
            "icloud"
        }
    }
}

struct SettingsView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @State private var selectedSection = SettingsSection.general

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Divider()

            ScrollView {
                selectedContent
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .font(interfaceTextSize.font(size: 13))
        .frame(width: 980, height: 720)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Feedivo")
                .font(interfaceTextSize.font(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            ForEach(SettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    Label(section.title, systemImage: section.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(SettingsSidebarButtonStyle(isSelected: selectedSection == section))
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 210)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection {
        case .general:
            GeneralSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .feeds:
            FeedManagementSettingsView()
        case .cache:
            CacheSettingsView()
        case .offline:
            OfflineReadingSettingsView()
        case .refresh:
            RefreshSettingsView()
        case .automation:
            AutomationSettingsView()
        case .sync:
            SyncSettingsView()
        }
    }
}

private struct SettingsSidebarButtonStyle: ButtonStyle {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(interfaceTextSize.font(size: 13, weight: .semibold))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor(configuration: configuration))
            }
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.13)
        }

        if configuration.isPressed {
            return Color.primary.opacity(0.06)
        }

        return .clear
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

private struct GeneralSettingsView: View {
    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true

    @AppStorage("appLanguage")
    private var appLanguageRawValue = AppLanguage.system.rawValue

    @AppStorage(ReaderDisplayMode.storageKey)
    private var readerDisplayModeRawValue = ReaderDisplayMode.defaultMode.rawValue

    var body: some View {
        Form {
            SettingsSectionHeader(
                title: L10n.settingsGeneralSection,
                description: L10n.settingsGeneralDescription
            )

            Section {
                Picker(L10n.settingsLanguagePickerTitle, selection: $appLanguageRawValue) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.titleKey)
                            .tag(language.rawValue)
                    }
                }

                Picker(L10n.readerDisplayModePicker, selection: $readerDisplayModeRawValue) {
                    ForEach(ReaderDisplayMode.allCases) { mode in
                        Text(mode.titleKey)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(L10n.settingsMarkReadOnOpenTitle, isOn: $markArticleReadOnSelection)

                Text(L10n.settingsMarkReadOnOpenDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettingsView: View {
    @AppStorage(InterfaceTextSize.storageKey)
    private var interfaceTextSizeRawValue = InterfaceTextSize.defaultSize.rawValue

    @AppStorage(SidebarFeedVisibilitySettings.showsReadFeedsKey)
    private var showsReadFeedsInSidebar = SidebarFeedVisibilitySettings.defaultShowsReadFeeds

    @AppStorage("readerTitleFontPreset")
    private var readerTitleFontPresetRawValue = ReaderFontPreset.system.rawValue

    @AppStorage("readerBodyFontPreset")
    private var readerBodyFontPresetRawValue = ReaderFontPreset.system.rawValue

    @AppStorage("readerBodyFontSize")
    private var readerBodyFontSize = ReaderTypography.defaultBodyFontSize

    @AppStorage("readerLineSpacing")
    private var readerLineSpacing = ReaderTypography.defaultLineSpacing

    @AppStorage("readerTitleLineSpacing")
    private var readerTitleLineSpacing = ReaderTypography.defaultTitleLineSpacing

    @AppStorage("readerContentWidth")
    private var readerContentWidth = ReaderTypography.defaultContentWidth

    var body: some View {
        Form {
            SettingsSectionHeader(
                title: L10n.settingsAppearanceSection,
                description: L10n.settingsAppearanceDescription
            )

            Section {
                Picker(L10n.settingsInterfaceTextSizePicker, selection: $interfaceTextSizeRawValue) {
                    ForEach(InterfaceTextSize.allCases) { textSize in
                        Text(textSize.titleKey)
                            .tag(textSize.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $showsReadFeedsInSidebar) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.settingsSidebarShowsReadFeedsTitle)
                        Text(L10n.settingsSidebarShowsReadFeedsDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(L10n.settingsReadingSection) {
                Picker(L10n.readerTitleFontPicker, selection: $readerTitleFontPresetRawValue) {
                    ForEach(ReaderFontPreset.allCases) { preset in
                        Text(preset.title)
                            .tag(preset.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Picker(L10n.readerBodyFontPicker, selection: $readerBodyFontPresetRawValue) {
                    ForEach(ReaderFontPreset.allCases) { preset in
                        Text(preset.title)
                            .tag(preset.rawValue)
                    }
                }
                .pickerStyle(.menu)

                typographySlider(
                    L10n.readerBodyFontSizeSlider,
                    value: $readerBodyFontSize,
                    range: ReaderTypography.bodyFontSizeRange,
                    displayedValue: ReaderTypography.clampedBodyFontSize(readerBodyFontSize)
                )

                typographySlider(
                    L10n.readerTitleLineSpacingSlider,
                    value: $readerTitleLineSpacing,
                    range: ReaderTypography.titleLineSpacingRange,
                    displayedValue: ReaderTypography.clampedTitleLineSpacing(readerTitleLineSpacing)
                )

                typographySlider(
                    L10n.readerLineSpacingSlider,
                    value: $readerLineSpacing,
                    range: ReaderTypography.lineSpacingRange,
                    displayedValue: ReaderTypography.clampedLineSpacing(readerLineSpacing)
                )

                typographySlider(
                    L10n.readerContentWidthSlider,
                    value: $readerContentWidth,
                    range: ReaderTypography.contentWidthRange,
                    displayedValue: ReaderTypography.clampedContentWidth(readerContentWidth),
                    step: ReaderTypography.contentWidthStep
                )
            }
        }
        .formStyle(.grouped)
    }

    private func typographySlider(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        displayedValue: Double,
        step: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(displayedValue)) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: value, in: range, step: step)
        }
    }
}

private struct CacheSettingsView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    @AppStorage(ImageCacheSettings.limitMegabytesKey)
    private var cacheLimitMegabytes = ImageCacheSettings.defaultLimitMegabytes

    @State private var cacheSizeInBytes: Int64 = 0
    @State private var errorMessage: String?

    var body: some View {
        Form {
            SettingsSectionHeader(
                title: L10n.settingsCacheSection,
                description: L10n.settingsCacheDescription
            )

            Section {
                LabeledContent(L10n.settingsCacheCurrentSize) {
                    Text(ImageCacheSettings.formattedByteCount(cacheSizeInBytes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Picker(L10n.settingsCacheLimitPicker, selection: $cacheLimitMegabytes) {
                    ForEach(ImageCacheSettings.allowedLimitMegabytes, id: \.self) { limitMegabytes in
                        Text(L10n.settingsCacheLimit(megabytes: limitMegabytes))
                            .tag(limitMegabytes)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: cacheLimitMegabytes) { _, newValue in
                    cacheLimitMegabytes = ImageCacheSettings.resolvedLimitMegabytes(newValue)
                    trimCacheToSelectedLimit()
                }

                Text(L10n.settingsCacheDescriptionDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button(L10n.settingsCacheRefreshSize) {
                        refreshCacheSize()
                    }

                    Button(L10n.settingsCacheClear, role: .destructive) {
                        clearCache()
                    }
                    .disabled(cacheSizeInBytes == 0)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(interfaceTextSize.font(size: 12))
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            refreshCacheSize()
        }
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

private struct OfflineReadingSettingsView: View {
    var body: some View {
        Form {
            SettingsSectionHeader(
                title: L10n.settingsOfflineSection,
                description: L10n.settingsOfflineDescription
            )

            Section {
                SettingsInformationRow(
                    iconName: "arrow.down.circle",
                    title: L10n.settingsOfflineManualTitle,
                    description: L10n.settingsOfflineManualDescription
                )

                SettingsInformationRow(
                    iconName: "doc.text",
                    title: L10n.settingsOfflineFeedContentTitle,
                    description: L10n.settingsOfflineFeedContentDescription
                )

                SettingsInformationRow(
                    iconName: "gearshape.2",
                    title: L10n.settingsOfflineAutomationTitle,
                    description: L10n.settingsOfflineAutomationDescription
                )
            }
        }
        .formStyle(.grouped)
    }
}

private struct SettingsInformationRow: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let iconName: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(interfaceTextSize.font(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(interfaceTextSize.font(size: 13, weight: .semibold))
                Text(description)
                    .font(interfaceTextSize.font(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
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
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .onTapGesture {
            setSelected(!isSelected)
        }
    }
}

private struct RefreshSettingsView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

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
        Form {
            SettingsSectionHeader(
                title: L10n.settingsRefreshSection,
                description: L10n.settingsRefreshDescription
            )

            Section {
                Toggle(L10n.settingsAutomaticRefreshTitle, isOn: $backgroundRefreshIsEnabled)

                Picker(L10n.settingsAutomaticRefreshIntervalPicker, selection: $backgroundRefreshIntervalMinutes) {
                    ForEach(BackgroundRefreshSettings.allowedIntervalMinutes, id: \.self) { intervalMinutes in
                        Text(L10n.settingsAutomaticRefreshInterval(minutes: intervalMinutes))
                            .tag(intervalMinutes)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!backgroundRefreshIsEnabled)

                Text(L10n.settingsAutomaticRefreshDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent(L10n.settingsAutomaticRefreshLastRun) {
                        Text(formattedRefreshDate(lastAutomaticRefreshTimestamp))
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent(L10n.settingsAutomaticRefreshStatus) {
                        Text(automaticRefreshStatusText)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent(L10n.settingsAutomaticRefreshNextRun) {
                        Text(formattedRefreshDate(nextAutomaticRefreshTimestamp))
                            .foregroundStyle(.secondary)
                    }

                    if lastAutomaticRefreshStatus == BackgroundRefreshSettings.statusFailed,
                       !lastAutomaticRefreshError.isEmpty {
                        LabeledContent(L10n.settingsAutomaticRefreshLastError) {
                            Text(lastAutomaticRefreshError)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .font(interfaceTextSize.font(size: 12))
            }
        }
        .formStyle(.grouped)
    }

    private var automaticRefreshStatusText: LocalizedStringKey {
        switch lastAutomaticRefreshStatus {
        case BackgroundRefreshSettings.statusSuccess:
            L10n.settingsAutomaticRefreshStatusSuccess
        case BackgroundRefreshSettings.statusFailed:
            L10n.settingsAutomaticRefreshStatusFailed
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

private struct AutomationSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(
                title: L10n.settingsAutomationSection,
                description: L10n.settingsAutomationDescription
            )

            RuleSettingsView()
        }
    }
}

private struct SyncSettingsView: View {
    var body: some View {
        Form {
            SettingsSectionHeader(
                title: L10n.settingsSyncSection,
                description: L10n.settingsSyncDescription
            )

            Section {
                ContentUnavailableView(L10n.settingsSyncUnavailableTitle, systemImage: "icloud")
                    .frame(maxWidth: .infinity, minHeight: 180)

                Text(L10n.settingsSyncUnavailableDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
