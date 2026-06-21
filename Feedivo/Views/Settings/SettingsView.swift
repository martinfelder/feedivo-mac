import SwiftUI

struct SettingsView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true

    @AppStorage("appLanguage")
    private var appLanguageRawValue = AppLanguage.system.rawValue

    @AppStorage(InterfaceTextSize.storageKey)
    private var interfaceTextSizeRawValue = InterfaceTextSize.defaultSize.rawValue

    @AppStorage(BackgroundRefreshSettings.isEnabledKey)
    private var backgroundRefreshIsEnabled = BackgroundRefreshSettings.defaultIsEnabled

    @AppStorage(BackgroundRefreshSettings.intervalMinutesKey)
    private var backgroundRefreshIntervalMinutes = BackgroundRefreshSettings.defaultIntervalMinutes

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

    @AppStorage(ReaderDisplayMode.storageKey)
    private var readerDisplayModeRawValue = ReaderDisplayMode.defaultMode.rawValue

    var body: some View {
        Form {
            Section(L10n.settingsLanguageSection) {
                Picker(L10n.settingsLanguagePickerTitle, selection: $appLanguageRawValue) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.titleKey)
                            .tag(language.rawValue)
                    }
                }
            }

            Section(L10n.settingsAppearanceSection) {
                Picker(L10n.settingsInterfaceTextSizePicker, selection: $interfaceTextSizeRawValue) {
                    ForEach(InterfaceTextSize.allCases) { textSize in
                        Text(textSize.titleKey)
                            .tag(textSize.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(L10n.settingsRefreshSection) {
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
                    .font(interfaceTextSize.font(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section {
                RuleSettingsView()
            }

            Section(L10n.settingsReadingSection) {
                Picker(L10n.readerDisplayModePicker, selection: $readerDisplayModeRawValue) {
                    ForEach(ReaderDisplayMode.allCases) { mode in
                        Text(mode.titleKey)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

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

                Toggle(L10n.settingsMarkReadOnOpenTitle, isOn: $markArticleReadOnSelection)

                Text(L10n.settingsMarkReadOnOpenDescription)
                    .font(interfaceTextSize.font(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .font(interfaceTextSize.font(size: 13))
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
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
                    .font(interfaceTextSize.font(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: value, in: range, step: step)
        }
    }
}
