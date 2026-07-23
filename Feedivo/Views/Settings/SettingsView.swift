import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case articleList
    case menubar
    case shortcuts
    case readerToolbar
    case notifications
    case refresh
    case cleanup
    case sync
    case about

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general:
            L10n.settingsGeneralSection
        case .appearance:
            "Anzeige"
        case .articleList:
            "Artikelliste"
        case .menubar:
            "Menubar"
        case .shortcuts:
            L10n.shortcutsSettingsSection
        case .readerToolbar:
            L10n.settingsReaderToolbarSection
        case .notifications:
            L10n.settingsNotificationsSection
        case .refresh:
            L10n.settingsRefreshSection
        case .cleanup:
            "Bereinigung"
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
        case .articleList:
            "list.bullet"
        case .menubar:
            "menubar.rectangle"
        case .shortcuts:
            "keyboard"
        case .readerToolbar:
            "rectangle.3.group"
        case .notifications:
            "bell.badge"
        case .refresh:
            "arrow.clockwise"
        case .cleanup:
            "trash"
        case .sync:
            "icloud"
        case .about:
            "info.circle"
        }
    }
}

struct SettingsView: View {
    static let windowID = "feedivo-settings-new"

    private enum Layout {
        // 640pt reichte nur für die 7 Tabs, die es beim Verschmälern auf diese Breite
        // (Commit 6a2015486, 2026-07-06) gab. Seither kamen Artikelliste/Menubar/
        // Shortcuts dazu (10 Tabs gesamt) — bei fixer Breite + .windowResizability(
        // .contentSize) in FeedivoApp.swift lief die Tab-Leiste über den sichtbaren
        // Bereich hinaus, wodurch Bereinigung/Sync/Über nicht mehr anklickbar waren
        // (Nutzer-Report 2026-07-12). Fix: grosszügig verbreitert, damit auch der
        // längste Tab-Titel ("Benachrichtigungen") mit den übrigen 9 Tabs Platz hat.
        // Erneut verbreitert 880→960pt für Feature 19.4 ("Toolbar anpassen",
        // 2026-07-18), das einen 11. Tab ("Toolbar") ergänzt hat (Whole-Branch-Review-
        // Fund, defensiver Fix). Diese konkrete Verbreiterung ist NICHT live verifiziert
        // (kein computer-use für native macOS-Apps in dieser Umgebung verfügbar) — falls
        // die Tab-Leiste trotzdem überläuft/Tabs abgeschnitten werden, muss der Wert
        // weiter erhöht werden.
        static let windowWidth: CGFloat = 960
    }

    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @State private var selectedSection = SettingsSection.general

    var body: some View {
        TabView(selection: $selectedSection) {
            settingsTab(.general)
            settingsTab(.appearance)
            settingsTab(.articleList)
            settingsTab(.menubar)
            settingsTab(.shortcuts)
            settingsTab(.readerToolbar)
            settingsTab(.notifications)
            settingsTab(.refresh)
            settingsTab(.cleanup)
            settingsTab(.sync)
            settingsTab(.about)
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: Layout.windowWidth)
    }

    @ViewBuilder
    private func settingsTab(_ section: SettingsSection) -> some View {
        settingsContent(for: section)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor))
            .tabItem {
                Label(section.title, systemImage: section.systemImage)
            }
            .tag(section)
    }

    @ViewBuilder
    private func settingsContent(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .articleList:
            ArticleListSettingsView()
        case .menubar:
            MenubarSettingsView()
        case .shortcuts:
            ShortcutsSettingsView()
        case .readerToolbar:
            ReaderToolbarSettingsView()
        case .notifications:
            NotificationSettingsView()
        case .refresh:
            RefreshSettingsView()
        case .cleanup:
            CleanupSettingsView()
        case .sync:
            SyncSettingsView()
        case .about:
            SettingsAboutView()
        }
    }
}

private struct SettingsBlock<Content: View>: View {
    let eyebrow: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            content
        }
        .padding(.bottom, 16)
    }
}

private struct SettingRow<Control: View>: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    @ViewBuilder let control: Control

    private static var labelColumnWidth: CGFloat { 190 }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: Self.labelColumnWidth, alignment: .trailing)

                control

                Spacer(minLength: 0)
            }

            Text(description)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Self.labelColumnWidth + 12)
        }
        .padding(.vertical, 4)
    }
}

private struct InfoRow: View {
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

private struct GeneralSettingsView: View {
    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true

    @AppStorage("appLanguage")
    private var appLanguageRawValue = AppLanguage.system.rawValue

    @AppStorage(ReaderDisplayMode.storageKey)
    private var readerDisplayModeRawValue = ReaderDisplayMode.defaultMode.rawValue

    @AppStorage(ArticleInAppWebProfile.storageKey)
    private var articleInAppWebProfileRawValue = ArticleInAppWebProfile.defaultProfile.rawValue

    @AppStorage(ArticleOriginalBrowserTarget.storageKey)
    private var articleOriginalBrowserTargetRawValue = ArticleOriginalBrowserTarget.defaultTarget.rawValue

    @AppStorage(ArticleWindowSettings.restoreOpenArticleWindowsOnLaunchKey)
    private var restoreOpenArticleWindowsOnLaunch = ArticleWindowSettings.defaultRestoreOpenArticleWindowsOnLaunch

    @AppStorage(SpotlightIndexingSettings.isEnabledKey)
    private var spotlightIndexingIsEnabled = SpotlightIndexingSettings.defaultIsEnabled

    private var availableBrowserTargets: [ArticleOriginalBrowserTarget] {
        ArticleOriginalBrowserTarget.availableTargets()
    }

    private var selectedBrowserTarget: ArticleOriginalBrowserTarget {
        let resolved = ArticleOriginalBrowserTarget.resolved(from: articleOriginalBrowserTargetRawValue)
        if !resolved.isAvailable {
            return ArticleOriginalBrowserTarget.defaultTarget
        }

        return resolved
    }

    private var selectedInAppWebProfile: ArticleInAppWebProfile {
        ArticleInAppWebProfile.resolved(from: articleInAppWebProfileRawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: "System") {
                SettingRow(
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
                }

                SettingRow(
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

                SettingRow(
                    title: "In-App Originalansicht rendern mit",
                    description: "Auswahl nur für die eingebettete Web-Ansicht im Reader. Wird intern über WebKit umgesetzt."
                ) {
                    Picker("", selection: $articleInAppWebProfileRawValue) {
                        ForEach(ArticleInAppWebProfile.allCases) { profile in
                            Text(profile.title)
                                .tag(profile.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onAppear {
                        articleInAppWebProfileRawValue = selectedInAppWebProfile.rawValue
                    }
                }

                SettingRow(
                    title: "Original öffnen mit",
                    description: "Wähle, welcher Browser für den externen Aufruf von „Original öffnen“ genutzt wird."
                ) {
                    Picker("", selection: $articleOriginalBrowserTargetRawValue) {
                        ForEach(availableBrowserTargets) { target in
                            Text(target.title)
                                .tag(target.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onAppear {
                        if !selectedBrowserTarget.isAvailable {
                            articleOriginalBrowserTargetRawValue = ArticleOriginalBrowserTarget.defaultTarget.rawValue
                        }
                    }
                }

                SettingRow(
                    title: L10n.settingsMarkReadOnOpenTitle,
                    description: L10n.settingsMarkReadOnOpenDescription
                ) {
                    Toggle("", isOn: $markArticleReadOnSelection)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.settingsRestoreArticleWindowsTitle,
                    description: L10n.settingsRestoreArticleWindowsDescription
                ) {
                    Toggle("", isOn: $restoreOpenArticleWindowsOnLaunch)
                        .labelsHidden()
                }
            }

            SettingsBlock(eyebrow: L10n.settingsSpotlightSection) {
                SettingRow(
                    title: L10n.settingsSpotlightToggleTitle,
                    description: L10n.settingsSpotlightToggleDescription
                ) {
                    Toggle("", isOn: $spotlightIndexingIsEnabled)
                        .labelsHidden()
                }
            }

            CacheSettingsView()
        }
    }
}

private struct AppearanceSettingsView: View {
    @AppStorage(InterfaceTextSize.storageKey)
    private var interfaceTextSizeRawValue = InterfaceTextSize.defaultSize.rawValue

    @AppStorage(AppAppearance.storageKey)
    private var appAppearanceRawValue = AppAppearance.defaultMode.rawValue

    @AppStorage(SidebarFeedVisibilitySettings.showsReadFeedsKey)
    private var showsReadFeedsInSidebar = SidebarFeedVisibilitySettings.defaultShowsReadFeeds

    @AppStorage(SidebarFeedVisibilitySettings.showsUnreadCountKey)
    private var showsUnreadCountInSidebar = SidebarFeedVisibilitySettings.defaultShowsUnreadCount

    @AppStorage(SidebarFeedVisibilitySettings.showsFaviconsKey)
    private var showsFaviconsInSidebar = SidebarFeedVisibilitySettings.defaultShowsFavicons

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

    @AppStorage(ReaderTypographySettings.showsArticleImagesKey)
    private var readerShowsArticleImages = ReaderTypography.defaultShowsArticleImages

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: "Oberfläche") {
                SettingRow(
                    title: L10n.settingsAppearanceModePicker,
                    description: "Legt fest, ob Feedivo unabhängig von der macOS-Systemeinstellung immer hell oder immer dunkel dargestellt wird."
                ) {
                    Picker("", selection: $appAppearanceRawValue) {
                        ForEach(AppAppearance.allCases) { mode in
                            Text(mode.titleKey)
                                .tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                }

                SettingRow(
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

                SettingRow(
                    title: L10n.settingsSidebarShowsReadFeedsTitle,
                    description: L10n.settingsSidebarShowsReadFeedsDescription
                ) {
                    Toggle("", isOn: $showsReadFeedsInSidebar)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.settingsSidebarShowsUnreadCountTitle,
                    description: L10n.settingsSidebarShowsUnreadCountDescription
                ) {
                    Toggle("", isOn: $showsUnreadCountInSidebar)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.settingsSidebarShowsFaviconsTitle,
                    description: L10n.settingsSidebarShowsFaviconsDescription
                ) {
                    Toggle("", isOn: $showsFaviconsInSidebar)
                        .labelsHidden()
                }

                SettingRow(
                    title: "Badge-Zähler am App-Icon anzeigen",
                    description: "Zeigt die Anzahl ungelesener Artikel im Dock."
                ) {
                    Toggle("", isOn: $appIconBadgeIsEnabled)
                        .labelsHidden()
                }
            }

            SettingsBlock(eyebrow: L10n.settingsReadingSection) {
                SettingRow(title: L10n.readerTitleFontPicker, description: "Schriftfamilie und Gewicht für Artikeltitel.") {
                    HStack {
                        Picker("", selection: $readerTitleFontPresetRawValue) {
                            ForEach(ReaderFontPreset.allCases) { preset in
                                Text(preset.title)
                                    .tag(preset.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 120, alignment: .leading)

                        Toggle("Fett", isOn: $readerTitleFontIsBold)
                    }
                }

                SettingRow(title: L10n.readerBodyFontPicker, description: "Schriftfamilie und Gewicht für den Artikeltext.") {
                    HStack {
                        Picker("", selection: $readerBodyFontPresetRawValue) {
                            ForEach(ReaderFontPreset.allCases) { preset in
                                Text(preset.title)
                                    .tag(preset.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 120, alignment: .leading)

                        Toggle("Fett", isOn: $readerBodyFontIsBold)
                    }
                }

                SettingRow(title: L10n.readerBodyFontSizeSlider, description: "Größe des nativen Reader-Texts.") {
                    SettingsSlider(value: $readerBodyFontSize, range: ReaderTypography.bodyFontSizeRange, suffix: "px")
                }

                SettingRow(title: L10n.readerLineSpacingSlider, description: "Vertikaler Abstand im Fließtext.") {
                    SettingsSlider(value: $readerLineSpacing, range: ReaderTypography.lineSpacingRange, suffix: "px")
                }

                SettingRow(title: L10n.readerContentWidthSlider, description: "Breite der Lesespalte im Reader.") {
                    SettingsSlider(value: $readerContentWidth, range: ReaderTypography.contentWidthRange, suffix: "px")
                }

                SettingRow(
                    title: L10n.readerShowsArticleImagesToggle,
                    description: "Zeigt oder verbirgt Bilder im Artikeltext, unabhängig von den Vorschaubildern in der Artikelliste."
                ) {
                    Toggle("", isOn: $readerShowsArticleImages)
                        .labelsHidden()
                }
            }
        }
    }
}

private struct ArticleListSettingsView: View {
    @AppStorage(ArticleListImagePosition.storageKey)
    private var articleListImagePositionRawValue = ArticleListImagePosition.defaultPosition.rawValue

    @AppStorage(ArticleListFeedNameVisibilitySettings.showsFeedNameKey)
    private var articleListShowsFeedName = ArticleListFeedNameVisibilitySettings.defaultShowsFeedName

    @AppStorage(ArticleListFeedNamePosition.storageKey)
    private var articleListFeedNamePositionRawValue = ArticleListFeedNamePosition.defaultPosition.rawValue

    @AppStorage(ArticleListSummaryLineCount.storageKey)
    private var articleListSummaryLineCount = ArticleListSummaryLineCount.defaultValue

    @AppStorage(ArticleDateDisplayMode.storageKey)
    private var articleDateDisplayModeRawValue = ArticleDateDisplayMode.defaultMode.rawValue

    @AppStorage(FeedJumpNavigationSettings.isEnabledKey)
    private var feedJumpNavigationIsEnabled = FeedJumpNavigationSettings.defaultIsEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: "Artikelliste") {
                SettingRow(
                    title: L10n.settingsArticleListImagePositionTitle,
                    description: L10n.settingsArticleListImagePositionDescription
                ) {
                    Picker("", selection: $articleListImagePositionRawValue) {
                        ForEach(ArticleListImagePosition.allCases) { position in
                            Text(position.titleKey)
                                .tag(position.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                }

                SettingRow(
                    title: L10n.settingsArticleListShowsFeedNameTitle,
                    description: L10n.settingsArticleListShowsFeedNameDescription
                ) {
                    Toggle("", isOn: $articleListShowsFeedName)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.settingsArticleListFeedNamePositionTitle,
                    description: L10n.settingsArticleListFeedNamePositionDescription
                ) {
                    Picker("", selection: $articleListFeedNamePositionRawValue) {
                        ForEach(ArticleListFeedNamePosition.allCases) { position in
                            Text(position.titleKey)
                                .tag(position.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                }

                SettingRow(
                    title: L10n.settingsArticleListSummaryLineCountTitle,
                    description: L10n.settingsArticleListSummaryLineCountDescription
                ) {
                    Stepper(
                        "\(articleListSummaryLineCount)",
                        value: $articleListSummaryLineCount,
                        in: ArticleListSummaryLineCount.allowedRange
                    )
                    .fixedSize()
                }

                SettingRow(
                    title: L10n.settingsArticleListDateDisplayModeTitle,
                    description: L10n.settingsArticleListDateDisplayModeDescription
                ) {
                    Picker("", selection: $articleDateDisplayModeRawValue) {
                        ForEach(ArticleDateDisplayMode.allCases) { mode in
                            Text(mode.titleKey)
                                .tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                }

                SettingRow(
                    title: L10n.settingsArticleListFeedJumpNavigationTitle,
                    description: L10n.settingsArticleListFeedJumpNavigationDescription
                ) {
                    Toggle("", isOn: $feedJumpNavigationIsEnabled)
                        .labelsHidden()
                }
            }
        }
    }
}

private struct MenubarSettingsView: View {
    @AppStorage(MenubarSettings.isEnabledKey)
    private var menubarIsEnabled = MenubarSettings.defaultIsEnabled

    @AppStorage(MenubarSettings.articleCountKey)
    private var menubarArticleCount = MenubarSettings.defaultArticleCount

    @AppStorage(MenubarArticleClickBehavior.storageKey)
    private var menubarArticleClickBehaviorRawValue = MenubarArticleClickBehavior.defaultBehavior.rawValue

    @AppStorage(MenubarSettings.hidesDockIconKey)
    private var menubarHidesDockIcon = MenubarSettings.defaultHidesDockIcon

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: "Menubar") {
                SettingRow(
                    title: L10n.settingsMenubarIsEnabledTitle,
                    description: L10n.settingsMenubarIsEnabledDescription
                ) {
                    Toggle("", isOn: $menubarIsEnabled)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.settingsMenubarArticleCountTitle,
                    description: L10n.settingsMenubarArticleCountDescription
                ) {
                    Stepper(
                        "\(menubarArticleCount)",
                        value: $menubarArticleCount,
                        in: MenubarSettings.allowedArticleCountRange
                    )
                    .disabled(!menubarIsEnabled)
                    .fixedSize()
                }

                SettingRow(
                    title: L10n.settingsMenubarArticleClickBehaviorTitle,
                    description: L10n.settingsMenubarArticleClickBehaviorDescription
                ) {
                    Picker("", selection: $menubarArticleClickBehaviorRawValue) {
                        ForEach(MenubarArticleClickBehavior.allCases) { behavior in
                            Text(behavior.titleKey)
                                .tag(behavior.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(!menubarIsEnabled)
                }

                SettingRow(
                    title: L10n.settingsMenubarHidesDockIconTitle,
                    description: L10n.settingsMenubarHidesDockIconDescription
                ) {
                    Toggle("", isOn: $menubarHidesDockIcon)
                        .labelsHidden()
                        .disabled(!menubarIsEnabled)
                }
            }
        }
    }
}

private struct SettingsSlider: View {
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

private struct CacheSettingsView: View {
    @AppStorage(ImageCacheSettings.limitMegabytesKey)
    private var cacheLimitMegabytes = ImageCacheSettings.defaultLimitMegabytes

    @State private var cacheSizeInBytes: Int64 = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: L10n.settingsCacheSection) {
                SettingRow(title: L10n.settingsCacheCurrentSize, description: "Gespeicherte Bilder und Favicons.") {
                    Text(ImageCacheSettings.formattedByteCount(cacheSizeInBytes))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                SettingRow(title: L10n.settingsCacheLimitPicker, description: L10n.settingsCacheDescriptionDetail) {
                    Picker("", selection: $cacheLimitMegabytes) {
                        ForEach(ImageCacheSettings.allowedLimitMegabytes, id: \.self) { limitMegabytes in
                            Text(L10n.settingsCacheLimit(megabytes: limitMegabytes))
                                .tag(limitMegabytes)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
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

private struct NotificationSettingsView: View {
    @State private var feedNotificationAuthorizationStatus: FeedNotificationAuthorizationStatus = .unknown

    @AppStorage(NotificationSettings.isMasterEnabledKey)
    private var isMasterEnabled = NotificationSettings.defaultIsMasterEnabled

    @AppStorage(NotificationSettings.defaultEnabledForNewFeedsKey)
    private var isEnabledForNewFeeds = NotificationSettings.defaultEnabledForNewFeedsDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: L10n.settingsNotificationsSection) {
                SettingRow(
                    title: L10n.settingsNotificationsPermissionTitle,
                    description: notificationPermissionDescription
                ) {
                    if feedNotificationAuthorizationStatus == .notDetermined {
                        Button(L10n.settingsNotificationsPermissionRequest) {
                            Task {
                                // Nach requestAuthorization() sofort erneut
                                // notificationSettings() abzufragen, kann kurzzeitig noch
                                // den alten Stand liefern (macOS propagiert die frisch
                                // erteilte Erlaubnis nicht synchron) — deshalb direkt aus
                                // dem bereits maßgeblichen Bool-Rückgabewert ableiten,
                                // statt erneut nachzufragen.
                                let isGranted = await FeedNotificationService.requestAuthorization()
                                feedNotificationAuthorizationStatus = isGranted ? .authorized : .denied
                            }
                        }
                    } else if feedNotificationAuthorizationStatus == .denied {
                        Button(L10n.settingsNotificationsPermissionOpenSystemSettings) {
                            NotificationSettings.openSystemNotificationSettings()
                        }
                    } else {
                        Text(permissionStatusText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                SettingRow(
                    title: L10n.settingsNotificationsMasterTitle,
                    description: L10n.settingsNotificationsMasterDescription
                ) {
                    Toggle("", isOn: $isMasterEnabled)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.settingsNotificationsNewFeedsDefaultTitle,
                    description: L10n.settingsNotificationsNewFeedsDefaultDescription
                ) {
                    Toggle("", isOn: $isEnabledForNewFeeds)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.settingsNotificationsTestTitle,
                    description: L10n.settingsNotificationsTestDescription
                ) {
                    Button(L10n.settingsNotificationsTestButton) {
                        Task {
                            await FeedNotificationService.presentTest()
                        }
                    }
                }

                InfoRow(
                    iconName: "dot.radiowaves.left.and.right",
                    title: L10n.settingsNotificationsFeedTitle,
                    description: L10n.settingsNotificationsFeedDescription
                )

                InfoRow(
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

private struct RefreshSettingsView: View {
    @AppStorage(BackgroundRefreshSettings.isEnabledKey)
    private var backgroundRefreshIsEnabled = BackgroundRefreshSettings.defaultIsEnabled

    @AppStorage(BackgroundRefreshSettings.intervalMinutesKey)
    private var backgroundRefreshIntervalMinutes = BackgroundRefreshSettings.defaultIntervalMinutes

    @AppStorage(BackgroundRefreshSettings.refreshOnLaunchIsEnabledKey)
    private var refreshOnLaunchIsEnabled = BackgroundRefreshSettings.defaultRefreshOnLaunchIsEnabled

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
            SettingsBlock(eyebrow: L10n.settingsRefreshSection) {
                SettingRow(title: L10n.settingsAutomaticRefreshTitle, description: L10n.settingsAutomaticRefreshDescription) {
                    Toggle("", isOn: $backgroundRefreshIsEnabled)
                        .labelsHidden()
                }

                SettingRow(title: L10n.settingsRefreshOnLaunchTitle, description: L10n.settingsRefreshOnLaunchDescription) {
                    Toggle("", isOn: $refreshOnLaunchIsEnabled)
                        .labelsHidden()
                }

                SettingRow(title: L10n.settingsAutomaticRefreshIntervalPicker, description: "Gilt als Standard für neue Feeds.") {
                    Picker("", selection: $backgroundRefreshIntervalMinutes) {
                        ForEach(BackgroundRefreshSettings.allowedIntervalMinutes, id: \.self) { intervalMinutes in
                            Text(L10n.settingsAutomaticRefreshInterval(minutes: intervalMinutes))
                                .tag(intervalMinutes)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
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
                        statusLine(title: L10n.settingsAutomaticRefreshLastRun, value: formattedAutomaticStatusDate(lastAutomaticRefreshTimestamp))
                        statusLine(title: L10n.settingsAutomaticRefreshStatus, value: automaticRefreshStatusText)
                        statusLine(title: L10n.settingsAutomaticRefreshNextRun, value: formattedAutomaticStatusDate(nextAutomaticRefreshTimestamp))

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

private func formattedAutomaticStatusDate(_ timestamp: Double) -> String {
    guard timestamp > 0 else {
        return String(localized: "settings.automaticRefresh.noDate")
    }

    return Date(timeIntervalSince1970: timestamp).formatted(
        date: .abbreviated,
        time: .shortened
    )
}

private struct SyncSettingsView: View {
    @Environment(DatabaseLoadState.self) private var databaseLoadState

    @AppStorage(CloudSyncSettings.isEnabledKey)
    private var cloudSyncIsEnabled = CloudSyncSettings.defaultIsEnabled

    private var hasDatabaseError: Bool {
        databaseLoadState.initializationError != nil
    }

    private var statusLocalizationKey: String {
        CloudSyncSettings.statusLocalizationKey(
            isEnabledAtLaunch: databaseLoadState.isCloudSyncEnabledAtLaunch,
            currentIsEnabled: cloudSyncIsEnabled,
            hasDatabaseError: hasDatabaseError
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: L10n.settingsSyncSection) {
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

                    SettingRow(
                        title: L10n.settingsSyncBetaTitle,
                        description: L10n.settingsSyncUnavailableHint
                    ) {
                        Toggle("", isOn: $cloudSyncIsEnabled)
                            .toggleStyle(.switch)
                            .disabled(!CloudSyncSettings.isAvailable)
                    }

                    InfoRow(
                        iconName: hasDatabaseError ? "exclamationmark.triangle" : "icloud.slash",
                        title: L10n.settingsSyncStatusTitle,
                        description: LocalizedStringKey(statusLocalizationKey)
                    )

                    if hasDatabaseError {
                        InfoRow(
                            iconName: "internaldrive",
                            title: L10n.settingsSyncDatabaseTitle,
                            description: L10n.settingsSyncDatabaseErrorHint
                        )
                    }
                }
            }
        }
        .onAppear {
            if !CloudSyncSettings.isAvailable {
                cloudSyncIsEnabled = false
            }
        }
    }
}

private struct CleanupSettingsView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase

    @AppStorage(ArticleRetentionSettings.isEnabledKey)
    private var articleRetentionIsEnabled = ArticleRetentionSettings.defaultIsEnabled

    @AppStorage(ArticleRetentionSettings.retentionDaysKey)
    private var articleRetentionDays = ArticleRetentionSettings.defaultRetentionDays

    @AppStorage(ArticleRetentionSettings.minimumArticlesPerFeedKey)
    private var articleRetentionMinimumArticlesPerFeed = ArticleRetentionSettings.defaultMinimumArticlesPerFeed

    @AppStorage(ArticleRetentionSettings.includesProtectedArticlesKey)
    private var articleRetentionIncludesProtectedArticles = ArticleRetentionSettings.defaultIncludesProtectedArticles

    @AppStorage(CleanupScheduleSettings.runOnAppStartKey)
    private var cleanupRunOnAppStart = CleanupScheduleSettings.defaultRunOnAppStart

    @AppStorage(CleanupScheduleSettings.runOnWeekdayTimeKey)
    private var cleanupRunOnWeekdayTime = CleanupScheduleSettings.defaultRunOnWeekdayTime

    @AppStorage(CleanupScheduleSettings.weekdaysKey)
    private var cleanupWeekdaysRaw = CleanupScheduleSettings.defaultWeekdaysStored

    @AppStorage(CleanupScheduleSettings.timeMinutesKey)
    private var cleanupTimeMinutes = CleanupScheduleSettings.defaultTimeMinutes

    @AppStorage(CleanupScheduleSettings.runOnQuitKey)
    private var cleanupRunOnQuit = CleanupScheduleSettings.defaultRunOnQuit

    @AppStorage(FeedLogRetentionSettings.retentionDaysKey)
    private var feedLogRetentionDays = FeedLogRetentionSettings.defaultRetentionDays

    @Environment(\.openWindow) private var openWindow

    @State private var retentionCleanupResult: String?
    @State private var retentionCleanupError: String?
    @State private var isCleanupSchedulePopoverPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: "Alte Artikel") {
                SettingRow(
                    title: L10n.settingsArticleRetentionTitle,
                    description: L10n.settingsArticleRetentionDescription
                ) {
                    Toggle("", isOn: $articleRetentionIsEnabled)
                        .labelsHidden()
                }

                SettingRow(
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
                    .disabled(!articleRetentionIsEnabled)
                    .onChange(of: articleRetentionDays) {
                        articleRetentionDays = ArticleRetentionSettings.clampedRetentionDays(articleRetentionDays)
                    }
                }

                SettingRow(
                    title: "Mindestens pro Feed behalten",
                    description: "So viele der neuesten Artikel bleiben pro Feed erhalten, auch wenn sie älter sind."
                ) {
                    Picker("Mindestens pro Feed behalten", selection: $articleRetentionMinimumArticlesPerFeed) {
                        ForEach(ArticleRetentionSettings.allowedMinimumArticlesPerFeed, id: \.self) { count in
                            Text(minimumArticlesLabel(count))
                                .tag(count)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(!articleRetentionIsEnabled)
                    .onChange(of: articleRetentionMinimumArticlesPerFeed) {
                        articleRetentionMinimumArticlesPerFeed = ArticleRetentionSettings.clampedMinimumArticlesPerFeed(
                            articleRetentionMinimumArticlesPerFeed
                        )
                    }
                }

                SettingRow(
                    title: L10n.settingsArticleRetentionIncludesProtectedArticles,
                    description: "Auch markierte oder geschützte Artikel in die Bereinigung einbeziehen."
                ) {
                    Toggle("", isOn: $articleRetentionIncludesProtectedArticles)
                        .labelsHidden()
                        .disabled(!articleRetentionIsEnabled)
                }

                SettingRow(
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

            SettingsBlock(eyebrow: "Zeitplan") {
                SettingRow(
                    title: L10n.settingsCleanupScheduleTitle,
                    description: L10n.settingsCleanupScheduleDescription
                ) {
                    Button {
                        isCleanupSchedulePopoverPresented.toggle()
                    } label: {
                        Text(cleanupScheduleSummaryText)
                    }
                    .popover(isPresented: $isCleanupSchedulePopoverPresented) {
                        cleanupSchedulePopoverContent
                    }
                }

                if cleanupRunOnWeekdayTime {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Self.weekdayRows, id: \.self) { row in
                            HStack(spacing: 12) {
                                Spacer().frame(width: 202)
                                ForEach(row, id: \.self) { weekdayNumber in
                                    Toggle(Calendar.current.weekdaySymbols[weekdayNumber - 1], isOn: Binding(
                                        get: { selectedWeekdays.contains(weekdayNumber) },
                                        set: { _ in toggleWeekday(weekdayNumber) }
                                    ))
                                    .toggleStyle(.checkbox)
                                }
                                Spacer(minLength: 0)
                            }
                        }

                        HStack(spacing: 12) {
                            Spacer().frame(width: 202)
                            DatePicker("", selection: cleanupScheduleTimeBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .datePickerStyle(.stepperField)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
            }

            SettingsBlock(eyebrow: L10n.settingsFeedLogRetentionTitle) {
                SettingRow(
                    title: L10n.settingsFeedLogRetentionDaysTitle,
                    description: L10n.settingsFeedLogRetentionDaysDescription
                ) {
                    Picker(L10n.settingsFeedLogRetentionDaysTitle, selection: $feedLogRetentionDays) {
                        ForEach(FeedLogRetentionSettings.allowedRetentionDays, id: \.self) { days in
                            Text("\(days) Tage")
                                .tag(days)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            SettingsBlock(eyebrow: L10n.cleanupHistoryTitle) {
                SettingRow(
                    title: L10n.cleanupHistoryTitle,
                    description: L10n.cleanupHistoryDescription
                ) {
                    Button(L10n.settingsCleanupHistoryShowButton) {
                        openWindow(id: CleanupHistoryWindowView.windowID)
                    }
                }
            }
        }
    }

    // Calendar.weekday-Konvention: 1 = Sonntag … 7 = Samstag. Für die Anzeige wird
    // mit Montag begonnen und zu je 3 Wochentagen pro Zeile gruppiert.
    private static let weekdayRows: [[Int]] = [
        [2, 3, 4],
        [5, 6, 7],
        [1],
    ]

    private var selectedWeekdays: Set<Int> {
        CleanupScheduleSettings.parseWeekdays(cleanupWeekdaysRaw)
    }

    private func toggleWeekday(_ weekday: Int) {
        var current = selectedWeekdays
        if current.contains(weekday) {
            guard current.count > 1 else {
                return // Mindestens ein Tag muss ausgewählt bleiben.
            }
            current.remove(weekday)
        } else {
            current.insert(weekday)
        }
        cleanupWeekdaysRaw = CleanupScheduleSettings.formatWeekdays(current)
    }

    private var cleanupSchedulePopoverContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(L10n.settingsCleanupScheduleAppStartTitle, isOn: $cleanupRunOnAppStart)
                .toggleStyle(.checkbox)
            Toggle(L10n.settingsCleanupScheduleWeekdayTimeTitle, isOn: $cleanupRunOnWeekdayTime)
                .toggleStyle(.checkbox)
            Toggle(L10n.settingsCleanupScheduleOnQuitTitle, isOn: $cleanupRunOnQuit)
                .toggleStyle(.checkbox)
        }
        .padding(12)
        .frame(minWidth: 220)
    }

    private var cleanupScheduleSummaryText: String {
        var parts: [String] = []
        if cleanupRunOnAppStart {
            parts.append(String(localized: "settings.cleanupSchedule.appStart.title"))
        }
        if cleanupRunOnWeekdayTime {
            parts.append(String(localized: "settings.cleanupSchedule.weekdayTime.title"))
        }
        if cleanupRunOnQuit {
            parts.append(String(localized: "settings.cleanupSchedule.onQuit.title"))
        }
        guard !parts.isEmpty else {
            return String(localized: "settings.cleanupSchedule.noneSelected")
        }
        return parts.joined(separator: ", ")
    }

    private var cleanupScheduleTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = cleanupTimeMinutes / 60
                components.minute = cleanupTimeMinutes % 60
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                cleanupTimeMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func runArticleRetentionCleanup() {
        guard let feedivoDatabase else {
            return
        }

        let result = ArticleRetentionCleanupService.runAutomaticCleanup(
            database: feedivoDatabase,
            isEnabled: articleRetentionIsEnabled,
            retentionDays: articleRetentionDays,
            minimumArticlesPerFeed: articleRetentionMinimumArticlesPerFeed,
            includeProtectedArticles: articleRetentionIncludesProtectedArticles,
            triggerSource: .manual
        )

        switch result {
        case .success(let removedCount):
            retentionCleanupResult = L10n.settingsArticleRetentionResult(count: removedCount)
            retentionCleanupError = nil
        case .failure(let error):
            retentionCleanupResult = nil
            retentionCleanupError = error.localizedDescription
        }
    }

    private func minimumArticlesLabel(_ count: Int) -> String {
        count == 0 ? "Keine Mindestanzahl" : "\(count) Artikel"
    }
}

private struct SettingsAboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: "Feedivo") {
                HStack(spacing: 14) {
                    Text("F")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Feedivo")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Nativer macOS RSS Reader mit Tags, Regeln und OPML.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("M4 Polish & Release")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            SettingsBlock(eyebrow: "Release") {
                InfoRow(
                    iconName: "shippingbox",
                    title: "Verteilung",
                    description: "App Store oder private Verteilung ist noch zu entscheiden."
                )

                InfoRow(
                    iconName: "globe",
                    title: "Lokalisierung",
                    description: "Deutsch, Englisch, Französisch und Italienisch sind vorbereitet."
                )
            }
        }
    }
}

private struct ShortcutsSettingsView: View {
    @AppStorage(KeyboardShortcutOverrides.storageKey)
    private var shortcutOverridesRawValue = KeyboardShortcutOverrides().rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ShortcutCategory.allCases, id: \.self) { category in
                SettingsBlock(eyebrow: category.titleKey) {
                    VStack(spacing: 0) {
                        ForEach(CustomizableShortcut.allCases.filter { $0.category == category }) { shortcut in
                            ShortcutSettingRow(shortcut: shortcut, overridesRawValue: $shortcutOverridesRawValue)
                        }
                    }
                }
            }

            Button(L10n.shortcutsResetAllButton) {
                shortcutOverridesRawValue = KeyboardShortcutOverrides().rawValue
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct ShortcutSettingRow: View {
    let shortcut: CustomizableShortcut
    @Binding var overridesRawValue: String

    @State private var conflictMessage: String?

    private static var labelColumnWidth: CGFloat { 190 }

    private var overrides: KeyboardShortcutOverrides {
        KeyboardShortcutOverrides.resolved(from: overridesRawValue)
    }

    private var spec: KeyboardShortcutSpec? {
        KeyboardShortcutsSettings.spec(for: shortcut, in: overrides)
    }

    private var isCustomized: Bool {
        overrides.values[shortcut.id] != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 12) {
                Text(shortcut.titleKey)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: Self.labelColumnWidth, alignment: .trailing)

                ShortcutRecorderView(
                    spec: spec,
                    onCapture: { capture($0) },
                    onClear: { clear() }
                )

                if isCustomized {
                    Button {
                        reset()
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.shortcutsResetButtonHelp)
                }

                Spacer(minLength: 0)
            }

            if let conflictMessage {
                Text(conflictMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .padding(.leading, Self.labelColumnWidth + 12)
            }

            if let spec, KeyboardShortcutsSettings.needsTextFieldGuard(for: spec) {
                Text(L10n.shortcutsModifierFreeWarning)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .padding(.leading, Self.labelColumnWidth + 12)
            }
        }
        .padding(.vertical, 4)
    }

    private func capture(_ newSpec: KeyboardShortcutSpec) {
        if let conflict = KeyboardShortcutsSettings.conflictingShortcut(for: newSpec, excluding: shortcut, in: overrides) {
            conflictMessage = L10n.shortcutsConflictMessage(conflict.resolvedLabel)
            return
        }

        var updated = overrides
        updated.values[shortcut.id] = .some(newSpec)
        overridesRawValue = updated.rawValue
        conflictMessage = nil
    }

    private func clear() {
        var updated = overrides
        updated.values[shortcut.id] = .some(nil)
        overridesRawValue = updated.rawValue
        conflictMessage = nil
    }

    private func reset() {
        var updated = overrides
        updated.values.removeValue(forKey: shortcut.id)
        overridesRawValue = updated.rawValue
        conflictMessage = nil
    }
}

private struct ReaderToolbarSettingsView: View {
    @AppStorage(ReaderToolbarLayout.storageKey)
    private var toolbarLayoutRawValue = ReaderToolbarLayout().rawValue

    private var layout: ReaderToolbarLayout {
        ReaderToolbarLayout.resolved(from: toolbarLayoutRawValue)
    }

    var body: some View {
        SettingsBlock(eyebrow: L10n.settingsReaderToolbarSection) {
            List {
                ForEach(layout.orderedItems) { item in
                    ReaderToolbarSettingsRow(
                        item: item,
                        isVisible: !layout.hiddenItemIDs.contains(item.rawValue),
                        onToggleVisible: { toggleVisible(item) }
                    )
                }
                .onMove(perform: moveItems)
            }
            .listStyle(.inset)
            .frame(height: 360)

            Button(L10n.readerToolbarResetButton) {
                toolbarLayoutRawValue = ReaderToolbarLayout.resetToDefault().rawValue
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var updated = layout
        updated.move(fromOffsets: source, toOffset: destination)
        toolbarLayoutRawValue = updated.rawValue
    }

    private func toggleVisible(_ item: ReaderToolbarItem) {
        var updated = layout
        updated.setHidden(!updated.hiddenItemIDs.contains(item.rawValue), for: item)
        toolbarLayoutRawValue = updated.rawValue
    }
}

private struct ReaderToolbarSettingsRow: View {
    let item: ReaderToolbarItem
    let isVisible: Bool
    let onToggleVisible: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .frame(width: 20)
                .foregroundStyle(isVisible ? Color.primary : Color.secondary)

            item.label
                .font(.system(size: 13))
                .foregroundStyle(isVisible ? Color.primary : Color.secondary)

            Spacer()

            Toggle(isOn: Binding(
                get: { isVisible },
                set: { _ in onToggleVisible() }
            )) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
