import OSLog
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
            L10n.settingsAboutSection
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
            AboutSettingsView()
        }
    }
}

struct InfoRow: View {
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

// Bold-Akzent für den Allgemein-Tab (Design B aus dem Einstellungen-Redesign-Vergleich,
// 2026-08-02). Farbcode vom Nutzer exakt vorgegeben (#3E5FED) — bewusst identisch in
// Hell/Dunkel, kein aufgehellter Dark-Wert, analog zu RuleDialogTheme.accent (0x3D5FEE),
// das dieselbe Farbfamilie ebenfalls ohne separate Dark-Variante nutzt. `Color(hex:)`
// kommt aus RuleDialogTheme.swift, hier bewusst wiederverwendet statt dupliziert.
// Nicht `private`: wird auch aus `AboutSettingsView.swift` (eigene Datei) referenziert,
// seit Design D auf alle Einstellungen-Tabs ausgerollt wurde.
extension Color {
    static let settingsBoldAccent = Color(hex: 0x3E5FED)
}

// Ersetzt den nativen `Picker(pickerStyle: .segmented)` für den Reader-Modus: das native
// NSSegmentedControl lässt sich nicht auf eine akzentgefüllte, freischwebende Pille in
// einer getönten Spur umstellen (nur System-Tinting möglich). Bewusst als eigener, kleiner
// Baustein statt Wiederverwendung von RuleSegmentedControl — dessen ausgewählter Zustand
// ist dort bewusst weiß/grau statt akzentgefüllt (anderes visuelles Muster, siehe
// RuleDialogTheme.pill), hier ist exakt die akzentgefüllte Pille aus dem abgestimmten
// Mockup verlangt.
struct GeneralSettingsSegmentedControl: View {
    let options: [(value: String, title: LocalizedStringKey)]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection

                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isSelected ? Color.settingsBoldAccent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.settingsBoldAccent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
        .animation(.easeInOut(duration: 0.12), value: selection)
    }
}

// Design D ("Formular", TablePlus-Vorbild, 2026-08-02): ein fettes Abschnittslabel links
// pro Sektion statt eines rechtsbündigen Labels pro Feld. Ersetzt seit dem vollständigen
// Rollout auf alle 11 Einstellungen-Tabs die alten `SettingsBlock`/`SettingRow`-Bausteine
// komplett (beide gelöscht, keine Verwendung mehr im Projekt). `label` ist `Text` statt
// `LocalizedStringKey`, damit Aufrufer bei Bedarf einen Doppelpunkt anhängen können
// (`Text(L10n.x) + Text(":")`), ohne neue L10n-Keys für reine Interpunktion anzulegen.
struct GeneralSettingsSection<Content: View>: View {
    let label: Text
    @ViewBuilder let content: Content

    private static var labelColumnWidth: CGFloat { 96 }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .frame(width: Self.labelColumnWidth, alignment: .trailing)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
        .padding(.vertical, 16)
    }
}

// Design D: "Label  Kontrolle" in einer Zeile statt SettingRows rechtsbündiger
// Label-Spalte — die Beschriftung steht jetzt direkt links neben ihrer Kontrolle.
struct GeneralSettingsRow<Control: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            control

            Spacer(minLength: 0)
        }
    }
}

struct GeneralSettingsHelp: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
            GeneralSettingsSection(label: Text("System:")) {
                GeneralSettingsRow(title: L10n.settingsLanguagePickerTitle) {
                    Picker("", selection: $appLanguageRawValue) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.titleKey)
                                .tag(language.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                GeneralSettingsHelp("Anzeigesprache wechseln. Ein App-Neustart wird empfohlen.")

                GeneralSettingsRow(title: L10n.readerDisplayModePicker) {
                    GeneralSettingsSegmentedControl(
                        options: ReaderDisplayMode.allCases.map { ($0.rawValue, $0.titleKey) },
                        selection: $readerDisplayModeRawValue
                    )
                }
                GeneralSettingsHelp("Standardansicht für geöffnete Artikel.")

                GeneralSettingsRow(title: "In-App Originalansicht rendern mit") {
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
                GeneralSettingsHelp("Auswahl nur für die eingebettete Web-Ansicht im Reader. Wird intern über WebKit umgesetzt.")

                GeneralSettingsRow(title: "Original öffnen mit") {
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
                GeneralSettingsHelp("Wähle, welcher Browser für den externen Aufruf von „Original öffnen“ genutzt wird.")

                Toggle(isOn: $markArticleReadOnSelection) {
                    Text(L10n.settingsMarkReadOnOpenTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsMarkReadOnOpenDescription)

                Toggle(isOn: $restoreOpenArticleWindowsOnLaunch) {
                    Text(L10n.settingsRestoreArticleWindowsTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsRestoreArticleWindowsDescription)
            }

            Divider()

            GeneralSettingsSection(label: Text(L10n.settingsSpotlightSection) + Text(":")) {
                Toggle(isOn: $spotlightIndexingIsEnabled) {
                    Text(L10n.settingsSpotlightToggleTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsSpotlightToggleDescription)
            }

            Divider()

            GeneralSettingsSection(label: Text(L10n.settingsCacheSection) + Text(":")) {
                CacheSettingsView()
            }
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
            GeneralSettingsSection(label: Text("Oberfläche:")) {
                GeneralSettingsRow(title: L10n.settingsAppearanceModePicker) {
                    GeneralSettingsSegmentedControl(
                        options: AppAppearance.allCases.map { ($0.rawValue, $0.titleKey) },
                        selection: $appAppearanceRawValue
                    )
                }
                GeneralSettingsHelp("Legt fest, ob Feedivo unabhängig von der macOS-Systemeinstellung immer hell oder immer dunkel dargestellt wird.")

                GeneralSettingsRow(title: L10n.settingsInterfaceTextSizePicker) {
                    GeneralSettingsSegmentedControl(
                        options: InterfaceTextSize.allCases.map { ($0.rawValue, $0.titleKey) },
                        selection: $interfaceTextSizeRawValue
                    )
                }
                GeneralSettingsHelp("App-weite Skalierung der Bedienoberfläche.")

                Toggle(isOn: $showsReadFeedsInSidebar) {
                    Text(L10n.settingsSidebarShowsReadFeedsTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsSidebarShowsReadFeedsDescription)

                Toggle(isOn: $showsUnreadCountInSidebar) {
                    Text(L10n.settingsSidebarShowsUnreadCountTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsSidebarShowsUnreadCountDescription)

                Toggle(isOn: $showsFaviconsInSidebar) {
                    Text(L10n.settingsSidebarShowsFaviconsTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsSidebarShowsFaviconsDescription)

                Toggle(isOn: $appIconBadgeIsEnabled) {
                    Text("Badge-Zähler am App-Icon anzeigen")
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp("Zeigt die Anzahl ungelesener Artikel im Dock.")
            }

            Divider()

            GeneralSettingsSection(label: Text(L10n.settingsReadingSection) + Text(":")) {
                GeneralSettingsRow(title: L10n.readerTitleFontPicker) {
                    Picker("", selection: $readerTitleFontPresetRawValue) {
                        ForEach(ReaderFontPreset.allCases) { preset in
                            Text(preset.title)
                                .tag(preset.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120, alignment: .leading)

                    Toggle(isOn: $readerTitleFontIsBold) {
                        Text("Fett").font(.system(size: 13))
                    }
                    .toggleStyle(.checkbox)
                    .tint(Color.settingsBoldAccent)
                }
                GeneralSettingsHelp("Schriftfamilie und Gewicht für Artikeltitel.")

                GeneralSettingsRow(title: L10n.readerBodyFontPicker) {
                    Picker("", selection: $readerBodyFontPresetRawValue) {
                        ForEach(ReaderFontPreset.allCases) { preset in
                            Text(preset.title)
                                .tag(preset.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120, alignment: .leading)

                    Toggle(isOn: $readerBodyFontIsBold) {
                        Text("Fett").font(.system(size: 13))
                    }
                    .toggleStyle(.checkbox)
                    .tint(Color.settingsBoldAccent)
                }
                GeneralSettingsHelp("Schriftfamilie und Gewicht für den Artikeltext.")

                GeneralSettingsRow(title: L10n.readerBodyFontSizeSlider) {
                    SettingsSlider(value: $readerBodyFontSize, range: ReaderTypography.bodyFontSizeRange, suffix: "px")
                }
                GeneralSettingsHelp("Größe des nativen Reader-Texts.")

                GeneralSettingsRow(title: L10n.readerLineSpacingSlider) {
                    SettingsSlider(value: $readerLineSpacing, range: ReaderTypography.lineSpacingRange, suffix: "px")
                }
                GeneralSettingsHelp("Vertikaler Abstand im Fließtext.")

                GeneralSettingsRow(title: L10n.readerContentWidthSlider) {
                    SettingsSlider(value: $readerContentWidth, range: ReaderTypography.contentWidthRange, suffix: "px")
                }
                GeneralSettingsHelp("Breite der Lesespalte im Reader.")

                Toggle(isOn: $readerShowsArticleImages) {
                    Text(L10n.readerShowsArticleImagesToggle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp("Zeigt oder verbirgt Bilder im Artikeltext, unabhängig von den Vorschaubildern in der Artikelliste.")
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

    @AppStorage(ReaderTabsSettings.restoreTabsOnLaunchKey)
    private var restoreReaderTabsOnLaunch = ReaderTabsSettings.defaultRestoreTabsOnLaunch

    @AppStorage(NativeArticleListSettings.isEnabledKey)
    private var usesNativeArticleList = NativeArticleListSettings.defaultIsEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeneralSettingsSection(label: Text("Artikelliste:")) {
                GeneralSettingsRow(title: L10n.settingsArticleListImagePositionTitle) {
                    GeneralSettingsSegmentedControl(
                        options: ArticleListImagePosition.allCases.map { ($0.rawValue, $0.titleKey) },
                        selection: $articleListImagePositionRawValue
                    )
                }
                GeneralSettingsHelp(L10n.settingsArticleListImagePositionDescription)

                Toggle(isOn: $articleListShowsFeedName) {
                    Text(L10n.settingsArticleListShowsFeedNameTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsArticleListShowsFeedNameDescription)

                GeneralSettingsRow(title: L10n.settingsArticleListFeedNamePositionTitle) {
                    GeneralSettingsSegmentedControl(
                        options: ArticleListFeedNamePosition.allCases.map { ($0.rawValue, $0.titleKey) },
                        selection: $articleListFeedNamePositionRawValue
                    )
                }
                GeneralSettingsHelp(L10n.settingsArticleListFeedNamePositionDescription)

                GeneralSettingsRow(title: L10n.settingsArticleListSummaryLineCountTitle) {
                    Stepper(
                        "\(articleListSummaryLineCount)",
                        value: $articleListSummaryLineCount,
                        in: ArticleListSummaryLineCount.allowedRange
                    )
                    .fixedSize()
                }
                GeneralSettingsHelp(L10n.settingsArticleListSummaryLineCountDescription)

                GeneralSettingsRow(title: L10n.settingsArticleListDateDisplayModeTitle) {
                    GeneralSettingsSegmentedControl(
                        options: ArticleDateDisplayMode.allCases.map { ($0.rawValue, $0.titleKey) },
                        selection: $articleDateDisplayModeRawValue
                    )
                }
                GeneralSettingsHelp(L10n.settingsArticleListDateDisplayModeDescription)

                Toggle(isOn: $feedJumpNavigationIsEnabled) {
                    Text(L10n.settingsArticleListFeedJumpNavigationTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsArticleListFeedJumpNavigationDescription)

                Toggle(isOn: $restoreReaderTabsOnLaunch) {
                    Text(L10n.settingsArticleListRestoreTabsOnLaunchTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)

                Toggle(isOn: $usesNativeArticleList) {
                    Text(L10n.settingsArticleListUsesNativeTableViewTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsArticleListUsesNativeTableViewDescription)
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
            GeneralSettingsSection(label: Text("Menubar:")) {
                Toggle(isOn: $menubarIsEnabled) {
                    Text(L10n.settingsMenubarIsEnabledTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsMenubarIsEnabledDescription)

                GeneralSettingsRow(title: L10n.settingsMenubarArticleCountTitle) {
                    Stepper(
                        "\(menubarArticleCount)",
                        value: $menubarArticleCount,
                        in: MenubarSettings.allowedArticleCountRange
                    )
                    .disabled(!menubarIsEnabled)
                    .fixedSize()
                }
                GeneralSettingsHelp(L10n.settingsMenubarArticleCountDescription)

                GeneralSettingsRow(title: L10n.settingsMenubarArticleClickBehaviorTitle) {
                    GeneralSettingsSegmentedControl(
                        options: MenubarArticleClickBehavior.allCases.map { ($0.rawValue, $0.titleKey) },
                        selection: $menubarArticleClickBehaviorRawValue
                    )
                    .disabled(!menubarIsEnabled)
                }
                GeneralSettingsHelp(L10n.settingsMenubarArticleClickBehaviorDescription)

                Toggle(isOn: $menubarHidesDockIcon) {
                    Text(L10n.settingsMenubarHidesDockIconTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                .disabled(!menubarIsEnabled)
                GeneralSettingsHelp(L10n.settingsMenubarHidesDockIconDescription)
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
                .tint(Color.settingsBoldAccent)
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
        Group {
            GeneralSettingsRow(title: L10n.settingsCacheCurrentSize) {
                Text(ImageCacheSettings.formattedByteCount(cacheSizeInBytes))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeneralSettingsHelp("Gespeicherte Bilder und Favicons.")

            GeneralSettingsRow(title: L10n.settingsCacheLimitPicker) {
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
            GeneralSettingsHelp(L10n.settingsCacheDescriptionDetail)

            HStack(spacing: 8) {
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
            GeneralSettingsSection(label: Text(L10n.settingsNotificationsSection) + Text(":")) {
                GeneralSettingsRow(title: L10n.settingsNotificationsPermissionTitle) {
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
                GeneralSettingsHelp(notificationPermissionDescription)

                Toggle(isOn: $isMasterEnabled) {
                    Text(L10n.settingsNotificationsMasterTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsNotificationsMasterDescription)

                Toggle(isOn: $isEnabledForNewFeeds) {
                    Text(L10n.settingsNotificationsNewFeedsDefaultTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsNotificationsNewFeedsDefaultDescription)

                GeneralSettingsRow(title: L10n.settingsNotificationsTestTitle) {
                    Button(L10n.settingsNotificationsTestButton) {
                        Task {
                            await FeedNotificationService.presentTest()
                        }
                    }
                }
                GeneralSettingsHelp(L10n.settingsNotificationsTestDescription)

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
            GeneralSettingsSection(label: Text(L10n.settingsRefreshSection) + Text(":")) {
                Toggle(isOn: $backgroundRefreshIsEnabled) {
                    Text(L10n.settingsAutomaticRefreshTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsAutomaticRefreshDescription)

                Toggle(isOn: $refreshOnLaunchIsEnabled) {
                    Text(L10n.settingsRefreshOnLaunchTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsRefreshOnLaunchDescription)

                GeneralSettingsRow(title: L10n.settingsAutomaticRefreshIntervalPicker) {
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
                GeneralSettingsHelp("Gilt als Standard für neue Feeds.")

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
    @Environment(CloudSyncStatus.self) private var cloudSyncStatus
    @Environment(\.cloudSyncEngine) private var cloudSyncEngine
    @Environment(\.feedivoDatabase) private var feedivoDatabase

    @AppStorage(CloudSyncSettings.isEnabledKey)
    private var cloudSyncIsEnabled = CloudSyncSettings.defaultIsEnabled

    @AppStorage(CloudSyncActivityStatus.lastRunDateKey)
    private var syncActivityLastRunTimestamp = 0.0

    @AppStorage(CloudSyncActivityStatus.statusKey)
    private var syncActivityStatusRaw = ""

    @AppStorage(CloudSyncActivityStatus.lastErrorMessageKey)
    private var syncActivityErrorMessage = ""

    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersionForSyncActivity = 0

    @State private var syncActivityPendingCounts: [String: Int] = [:]
    @State private var isSyncActivityDetailsExpanded = false

    // Feld-Ebene-Konfliktauflösung (Phase 3) — Badge + Sheet direkt neben der bestehenden
    // Sync-Status-Zeile. `pendingConflictCount` wird nach demselben Muster wie
    // `syncActivityPendingCounts` über `sqliteStatusVersionForSyncActivity` aktuell gehalten.
    @State private var pendingConflictCount = 0
    @State private var showingConflictSheet = false

    // Erst-Aktivierungs-Merge-Dialog (Phase 3, Task 14) — erscheint beim Einschalten des
    // Sync-Schalters VOR dem eigentlichen CloudSyncEngine.start(), siehe .onChange unten.
    @State private var showingFirstActivationSheet = false

    @State private var isResetting = false
    @State private var resetErrorMessage: String?
    @State private var resetSuccessMessage: String?
    @State private var isShowingSoftResetConfirmation = false
    @State private var isShowingHardResetSheet = false
    @State private var hardResetConfirmationText = ""

    private var hasDatabaseError: Bool {
        databaseLoadState.initializationError != nil
    }

    private var statusLocalizationKey: String {
        CloudSyncSettings.statusLocalizationKey(
            isEnabled: cloudSyncIsEnabled,
            syncState: cloudSyncStatus.state,
            hasDatabaseError: hasDatabaseError
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeneralSettingsSection(label: Text(L10n.settingsSyncSection) + Text(":")) {
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

                    GeneralSettingsRow(title: L10n.settingsSyncBetaTitle) {
                        Toggle("", isOn: $cloudSyncIsEnabled)
                            .toggleStyle(.switch)
                            .tint(Color.settingsBoldAccent)
                    }
                    GeneralSettingsHelp(L10n.settingsSyncBetaScopeHint)

                    InfoRow(
                        iconName: hasDatabaseError ? "exclamationmark.triangle" : "icloud",
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

                    CloudSyncActivityStatusBlock(
                        cloudSyncIsEnabled: cloudSyncIsEnabled,
                        isAccountUnavailable: cloudSyncStatus.state == .accountUnavailable,
                        lastRunTimestamp: syncActivityLastRunTimestamp,
                        statusRaw: syncActivityStatusRaw,
                        errorMessage: syncActivityErrorMessage,
                        pendingCounts: syncActivityPendingCounts,
                        isDetailsExpanded: $isSyncActivityDetailsExpanded
                    )

                    if pendingConflictCount > 0 {
                        Button(action: { showingConflictSheet = true }) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(L10n.syncConflictsBadge(pendingConflictCount))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            GeneralSettingsSection(label: Text(L10n.settingsSyncResetSection) + Text(":")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Button(L10n.settingsSyncResetSoftButton) {
                            // Verhindert, dass eine veraltete Erfolgs-/Fehlermeldung eines
                            // früheren Resets neben der (nach dem Backfill-Fix jetzt live
                            // aktualisierten) Ausstehend-Anzeige stehen bleibt, während der
                            // Nutzer einen neuen Reset erwägt.
                            resetErrorMessage = nil
                            resetSuccessMessage = nil
                            isShowingSoftResetConfirmation = true
                        }
                        .disabled(isResetting || feedivoDatabase == nil || cloudSyncEngine == nil)

                        Button(L10n.settingsSyncResetHardButton, role: .destructive) {
                            resetErrorMessage = nil
                            resetSuccessMessage = nil
                            hardResetConfirmationText = ""
                            isShowingHardResetSheet = true
                        }
                        // Zusätzlich zu den bestehenden Bedingungen: ist iCloud Sync
                        // deaktiviert, würde resetCloudZoneAndLocalState zwar die geteilte
                        // CloudKit-Zone löschen (betrifft alle anderen Geräte!), aber
                        // resetLocalState() startet die Engine anschließend NICHT neu
                        // (isEnabled-Check) — die Zone bliebe dauerhaft leer statt, wie im
                        // Warnhinweis versprochen, aus dem lokalen Stand neu aufgebaut zu
                        // werden. Der Button muss deshalb deaktiviert bleiben, solange Sync
                        // aus ist.
                        .disabled(isResetting || feedivoDatabase == nil || cloudSyncEngine == nil || !cloudSyncIsEnabled)

                        if isResetting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let resetErrorMessage {
                        Text(resetErrorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }

                    if let resetSuccessMessage {
                        Text(resetSuccessMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: cloudSyncIsEnabled) {
            if cloudSyncIsEnabled {
                // Erst-Aktivierungs-Merge-Dialog MUSS vor dem allerersten start() laufen
                // (siehe CloudSyncFirstActivationView-Kommentar) — start() selbst läuft erst
                // im onContinue-Callback des Sheets unten, nicht hier direkt. Review-Fix
                // (Task 14, Critical 2): pendingFirstActivationKey wird HIER gesetzt, im
                // selben Moment wie das Anzeigen des Dialogs, NICHT erst wenn der Dialog
                // fertig ist — FeedivoApp.init() verweigert dadurch bei einem App-Neustart
                // vor abgeschlossenem Dialog den blinden start()-Aufruf (siehe dortiger
                // Kommentar). Erst applyDecisions()/„Weiter" in CloudSyncFirstActivationView
                // setzt das Flag wieder zurück.
                CloudSyncSettings.setPendingFirstActivation(true)
                showingFirstActivationSheet = true
            } else {
                // Sync wird ausgeschaltet — eine eventuell noch offene Erst-Aktivierungs-
                // Entscheidung aus einem vorherigen Einschalt-Versuch ist damit hinfällig,
                // ein erneutes Einschalten löst ohnehin wieder eine frische Analyse aus.
                CloudSyncSettings.setPendingFirstActivation(false)
                cloudSyncEngine?.stop()
            }
        }
        .sheet(isPresented: $showingFirstActivationSheet) {
            CloudSyncFirstActivationView(onContinue: { cloudSyncEngine?.start() })
        }
        .onAppear(perform: loadSyncActivityPendingCounts)
        .onAppear(perform: loadPendingConflictCount)
        .onAppear {
            // Review-Fix (Task 14, Critical 2): deckt den Fall ab, dass die App beendet wurde,
            // während der Erst-Aktivierungs-Dialog noch offen war (Toggle bereits „an", aber
            // keine Entscheidung getroffen) — FeedivoApp.init() hat deshalb bewusst NICHT
            // gestartet. Sobald der Nutzer diesen Einstellungen-Tab erneut öffnet, erscheint
            // der Dialog automatisch wieder, statt dass Sync dauerhaft (und ohne erkennbaren
            // Grund für den Nutzer) im „an, aber nie gestartet"-Zustand hängen bleibt.
            if cloudSyncIsEnabled && CloudSyncSettings.hasPendingFirstActivation() {
                showingFirstActivationSheet = true
            }
        }
        .onChange(of: sqliteStatusVersionForSyncActivity) {
            loadSyncActivityPendingCounts()
            loadPendingConflictCount()
        }
        .sheet(isPresented: $showingConflictSheet) {
            SyncConflictResolutionView()
        }
        .onChange(of: syncActivityLastRunTimestamp) {
            // CloudSyncEngine.dequeuePendingChange löscht erledigte Pending-Change-Zeilen,
            // ruft dabei aber (bewusst, siehe Whole-Branch-Review) nicht
            // SQLiteDataInvalidation.bumpStatusVersion() auf. Ohne diesen zusätzlichen Trigger
            // würde die Ausstehend-Anzahl nach einem erfolgreichen Sync erst beim nächsten
            // Öffnen der Einstellungen aktualisiert. syncActivityLastRunTimestamp wird dagegen
            // bei JEDEM abgeschlossenen Sync-Versuch (Erfolg UND Fehler) neu geschrieben, ist
            // also ein zuverlässiger Reload-Auslöser direkt nach jedem Sync-Ereignis.
            loadSyncActivityPendingCounts()
        }
        .confirmationDialog(
            L10n.settingsSyncResetSoftConfirmTitle,
            isPresented: $isShowingSoftResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.settingsSyncResetSoftButton, role: .destructive) {
                performSoftReset()
            }
            Button(L10n.commonCancel, role: .cancel) {}
        } message: {
            Text(L10n.settingsSyncResetSoftConfirmMessage)
        }
        .sheet(isPresented: $isShowingHardResetSheet) {
            CloudSyncHardResetSheet(
                confirmationText: $hardResetConfirmationText,
                onConfirm: {
                    isShowingHardResetSheet = false
                    performHardReset()
                },
                onCancel: {
                    isShowingHardResetSheet = false
                }
            )
        }
    }

    private func loadSyncActivityPendingCounts() {
        guard let feedivoDatabase else {
            syncActivityPendingCounts = [:]
            return
        }
        do {
            syncActivityPendingCounts = try CloudSyncPendingChangeStore(database: feedivoDatabase).pendingCounts()
        } catch {
            // Ein echter Lesefehler wäre sonst von "0 ausstehende Änderungen" nicht zu
            // unterscheiden gewesen — in einem Feature, dessen einziger Zweck eine korrekte
            // Statusanzeige ist, muss das zumindest geloggt werden. UI fällt weiterhin auf
            // ein leeres Dictionary zurück (kein Absturz, kein Verhaltensunterschied).
            AppLogger.dataAccess.error("Laden der ausstehenden CloudSync-Änderungen fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            syncActivityPendingCounts = [:]
        }
    }

    private func loadPendingConflictCount() {
        guard let feedivoDatabase else {
            pendingConflictCount = 0
            return
        }
        do {
            pendingConflictCount = try PendingSyncConflictStore(database: feedivoDatabase).count()
        } catch {
            // Analog zu `loadSyncActivityPendingCounts()`: ein echter Lesefehler soll nicht
            // stillschweigend als "keine Konflikte" erscheinen, ohne dass er zumindest geloggt
            // wird. UI fällt weiterhin auf 0 zurück (kein Absturz, Badge bleibt einfach
            // ausgeblendet).
            AppLogger.dataAccess.error("Laden der ausstehenden Sync-Konflikte fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            pendingConflictCount = 0
        }
    }

    private func performSoftReset() {
        guard let cloudSyncEngine, let feedivoDatabase else { return }
        isResetting = true
        resetErrorMessage = nil
        resetSuccessMessage = nil
        cloudSyncEngine.resetLocalState(database: feedivoDatabase)
        resetSuccessMessage = L10n.settingsSyncResetSuccessMessage
        loadSyncActivityPendingCounts()
        isResetting = false
    }

    private func performHardReset() {
        guard let cloudSyncEngine, let feedivoDatabase else { return }
        isResetting = true
        resetErrorMessage = nil
        resetSuccessMessage = nil
        Task {
            do {
                try await cloudSyncEngine.resetCloudZoneAndLocalState(database: feedivoDatabase)
                resetSuccessMessage = L10n.settingsSyncResetSuccessMessage
            } catch {
                resetErrorMessage = L10n.settingsSyncResetErrorMessage(reason: error.localizedDescription)
            }
            loadSyncActivityPendingCounts()
            isResetting = false
        }
    }
}

private struct CloudSyncHardResetSheet: View {
    @Binding var confirmationText: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private static let requiredConfirmationText = "ZURÜCKSETZEN"

    private var isConfirmEnabled: Bool {
        confirmationText == Self.requiredConfirmationText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.settingsSyncResetHardSheetTitle)
                .font(.system(size: 15, weight: .semibold))

            Text(L10n.settingsSyncResetHardWarning)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.settingsSyncResetHardConfirmFieldLabel)
                    .font(.system(size: 11, weight: .medium))

                TextField(Self.requiredConfirmationText, text: $confirmationText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button(L10n.commonCancel) {
                    onCancel()
                }
                Button(L10n.settingsSyncResetHardConfirmButton, role: .destructive) {
                    onConfirm()
                }
                .disabled(!isConfirmEnabled)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct CloudSyncActivityStatusBlock: View {
    let cloudSyncIsEnabled: Bool
    let isAccountUnavailable: Bool
    let lastRunTimestamp: Double
    let statusRaw: String
    let errorMessage: String
    let pendingCounts: [String: Int]
    @Binding var isDetailsExpanded: Bool

    private var isActiveAndAvailable: Bool {
        cloudSyncIsEnabled && !isAccountUnavailable
    }

    private var totalPendingCount: Int {
        pendingCounts.values.reduce(0, +)
    }

    private var stateText: String {
        guard isActiveAndAvailable else {
            return cloudSyncIsEnabled
                ? String(localized: "settings.sync.activity.state.accountUnavailable")
                : String(localized: "settings.sync.activity.state.disabled")
        }
        if statusRaw == CloudSyncActivityStatus.statusFailed {
            return String.localizedStringWithFormat(String(localized: "settings.sync.activity.state.error"), errorMessage)
        }
        if totalPendingCount > 0 {
            return String.localizedStringWithFormat(String(localized: "settings.sync.activity.state.pending"), totalPendingCount)
        }
        return String(localized: "settings.sync.activity.state.synced")
    }

    /// Farbe für die Status-Zeile, nach EXAKT derselben Prioritätslogik wie `stateText`
    /// abgeleitet (inaktiv → Fehler → ausstehend → synchron), damit Text und Farbe nie
    /// auseinanderlaufen können. Abweichend von `stateText` verlangt der "synchron"-Fall
    /// hier zusätzlich `statusRaw == .statusSuccess` (statt nur "nicht fehlgeschlagen") —
    /// sonst hätte ein noch nie gelaufener Sync (leeres `statusRaw`, keine ausstehenden
    /// Änderungen) fälschlich die grüne Erfolgsfarbe neben "Noch nie synchronisiert"
    /// gezeigt (Whole-Branch-Review-Fund, Finding 3).
    private var stateColor: Color {
        guard isActiveAndAvailable else {
            return .secondary
        }
        if statusRaw == CloudSyncActivityStatus.statusFailed {
            return .red
        }
        if totalPendingCount > 0 {
            return .secondary
        }
        if statusRaw == CloudSyncActivityStatus.statusSuccess {
            return .green
        }
        return .secondary
    }

    /// SF-Symbol-Name für die Status-Zeile, dieselbe Prioritätslogik wie `stateColor`.
    /// `nil` bedeutet: kein Icon (inaktiv/ausstehend/nie gelaufen-und-nichts-ausstehend).
    private var stateIconName: String? {
        guard isActiveAndAvailable else {
            return nil
        }
        if statusRaw == CloudSyncActivityStatus.statusFailed {
            return "exclamationmark.triangle"
        }
        if totalPendingCount > 0 {
            return nil
        }
        if statusRaw == CloudSyncActivityStatus.statusSuccess {
            return "checkmark.circle.fill"
        }
        return nil
    }

    private var lastRunText: String {
        guard lastRunTimestamp > 0 else {
            return String(localized: "settings.sync.activity.neverRun")
        }
        return Date(timeIntervalSince1970: lastRunTimestamp).formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.settingsSyncActivityTitle)
                    .font(.system(size: 14))
                Text(L10n.settingsSyncActivityDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 5) {
                coloredStatusLine(
                    title: L10n.settingsSyncActivityStatusRow,
                    value: stateText,
                    color: stateColor,
                    iconName: stateIconName
                )
                statusLine(title: L10n.settingsSyncActivityLastRunRow, value: lastRunText)
            }
            .frame(maxWidth: .infinity)
            .opacity(isActiveAndAvailable ? 1 : 0.55)

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isDetailsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(isDetailsExpanded ? L10n.settingsSyncActivityDetailsHide : L10n.settingsSyncActivityDetailsShow)
                    Image(systemName: isDetailsExpanded ? "chevron.down" : "chevron.right")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isDetailsExpanded {
                VStack(spacing: 5) {
                    ForEach(CloudSyncActivityCategory.allCases, id: \.self) { category in
                        statusLine(title: category.localizedTitle, value: categoryValueText(for: category))
                    }
                }
                .frame(maxWidth: .infinity)
                .opacity(isActiveAndAvailable ? 1 : 0.55)
            }
        }
    }

    private func categoryValueText(for category: CloudSyncActivityCategory) -> String {
        let count = category.pendingCount(in: pendingCounts)
        guard count > 0 else {
            return String(localized: "settings.sync.activity.state.synced")
        }
        return String.localizedStringWithFormat(String(localized: "settings.sync.activity.category.pending"), count)
    }

    /// Wie `statusLine(title:value:)`, aber mit einstellbarer Farbe + optionalem Icon.
    /// Bewusst lokal auf `CloudSyncActivityStatusBlock` beschränkt (kein Umbau der geteilten
    /// `statusLine`-Helfer, die auch von anderen Settings-Bereichen neutral/grau genutzt
    /// werden) — nur die eine globale Sync-Status-Zeile bekommt laut Design-Spec eine
    /// Farbcodierung, die "Zuletzt synchronisiert"-Zeile und die Pro-Kategorie-Detailzeilen
    /// bleiben bewusst neutral.
    private func coloredStatusLine(title: LocalizedStringKey, value: String, color: Color, iconName: String?) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.tertiary)
            Spacer()
            HStack(spacing: 4) {
                if let iconName {
                    Image(systemName: iconName)
                        .foregroundStyle(color)
                }
                Text(value)
                    .fontWeight(.medium)
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            GeneralSettingsSection(label: Text("Alte Artikel:")) {
                Toggle(isOn: $articleRetentionIsEnabled) {
                    Text(L10n.settingsArticleRetentionTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsArticleRetentionDescription)

                GeneralSettingsRow(title: L10n.settingsArticleRetentionIntervalPicker) {
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
                GeneralSettingsHelp("Artikel werden nach diesem Zeitraum automatisch entfernt.")

                GeneralSettingsRow(title: "Mindestens pro Feed behalten") {
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
                GeneralSettingsHelp("So viele der neuesten Artikel bleiben pro Feed erhalten, auch wenn sie älter sind.")

                Toggle(isOn: $articleRetentionIncludesProtectedArticles) {
                    Text(L10n.settingsArticleRetentionIncludesProtectedArticles)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                .disabled(!articleRetentionIsEnabled)
                GeneralSettingsHelp("Auch markierte oder geschützte Artikel in die Bereinigung einbeziehen.")

                GeneralSettingsRow(title: L10n.settingsArticleRetentionRunNow) {
                    Button(L10n.settingsArticleRetentionRunNow) {
                        runArticleRetentionCleanup()
                    }
                    .disabled(!articleRetentionIsEnabled)
                }
                GeneralSettingsHelp("Bereinigung direkt mit den aktuellen Einstellungen starten.")

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

            GeneralSettingsSection(label: Text("Zeitplan:")) {
                GeneralSettingsRow(title: L10n.settingsCleanupScheduleTitle) {
                    Button {
                        isCleanupSchedulePopoverPresented.toggle()
                    } label: {
                        Text(cleanupScheduleSummaryText)
                    }
                    .popover(isPresented: $isCleanupSchedulePopoverPresented) {
                        cleanupSchedulePopoverContent
                    }
                }
                GeneralSettingsHelp(L10n.settingsCleanupScheduleDescription)

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

            GeneralSettingsSection(label: Text(L10n.settingsFeedLogRetentionTitle) + Text(":")) {
                GeneralSettingsRow(title: L10n.settingsFeedLogRetentionDaysTitle) {
                    Picker(L10n.settingsFeedLogRetentionDaysTitle, selection: $feedLogRetentionDays) {
                        ForEach(FeedLogRetentionSettings.allowedRetentionDays, id: \.self) { days in
                            Text("\(days) Tage")
                                .tag(days)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                GeneralSettingsHelp(L10n.settingsFeedLogRetentionDaysDescription)
            }

            GeneralSettingsSection(label: Text(L10n.cleanupHistoryTitle) + Text(":")) {
                GeneralSettingsRow(title: L10n.cleanupHistoryTitle) {
                    Button(L10n.settingsCleanupHistoryShowButton) {
                        openWindow(id: CleanupHistoryWindowView.windowID)
                    }
                }
                GeneralSettingsHelp(L10n.cleanupHistoryDescription)
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

private struct ShortcutsSettingsView: View {
    @AppStorage(KeyboardShortcutOverrides.storageKey)
    private var shortcutOverridesRawValue = KeyboardShortcutOverrides().rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ShortcutCategory.allCases, id: \.self) { category in
                GeneralSettingsSection(label: Text(category.titleKey) + Text(":")) {
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
        GeneralSettingsSection(label: Text(L10n.settingsReaderToolbarSection) + Text(":")) {
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

private struct CloudSyncEngineKey: EnvironmentKey {
    static let defaultValue: CloudSyncEngine? = nil
}

extension EnvironmentValues {
    var cloudSyncEngine: CloudSyncEngine? {
        get { self[CloudSyncEngineKey.self] }
        set { self[CloudSyncEngineKey.self] = newValue }
    }
}
