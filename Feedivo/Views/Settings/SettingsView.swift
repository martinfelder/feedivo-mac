import SwiftUI

struct SettingsView: View {
    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true

    @AppStorage("appLanguage")
    private var appLanguageRawValue = AppLanguage.system.rawValue

    @AppStorage("readerTitleFontPreset")
    private var readerTitleFontPresetRawValue = ReaderFontPreset.system.rawValue

    @AppStorage("readerBodyFontPreset")
    private var readerBodyFontPresetRawValue = ReaderFontPreset.system.rawValue

    @AppStorage("readerBodyFontSize")
    private var readerBodyFontSize = ReaderTypography.defaultBodyFontSize

    @AppStorage("readerLineSpacing")
    private var readerLineSpacing = ReaderTypography.defaultLineSpacing

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

            Section(L10n.settingsReadingSection) {
                Picker(L10n.readerTitleFontPicker, selection: $readerTitleFontPresetRawValue) {
                    ForEach(ReaderFontPreset.allCases) { preset in
                        Text(preset.title)
                            .tag(preset.rawValue)
                    }
                }

                Picker(L10n.readerBodyFontPicker, selection: $readerBodyFontPresetRawValue) {
                    ForEach(ReaderFontPreset.allCases) { preset in
                        Text(preset.title)
                            .tag(preset.rawValue)
                    }
                }

                typographySlider(
                    L10n.readerBodyFontSizeSlider,
                    value: $readerBodyFontSize,
                    range: ReaderTypography.bodyFontSizeRange,
                    displayedValue: ReaderTypography.clampedBodyFontSize(readerBodyFontSize)
                )

                typographySlider(
                    L10n.readerLineSpacingSlider,
                    value: $readerLineSpacing,
                    range: ReaderTypography.lineSpacingRange,
                    displayedValue: ReaderTypography.clampedLineSpacing(readerLineSpacing)
                )

                Toggle(L10n.settingsMarkReadOnOpenTitle, isOn: $markArticleReadOnSelection)

                Text(L10n.settingsMarkReadOnOpenDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
    }

    private func typographySlider(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        displayedValue: Double
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

            Slider(value: value, in: range, step: 1)
        }
    }
}
