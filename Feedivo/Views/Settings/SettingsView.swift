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
                        Text(preset.titleKey)
                            .tag(preset.rawValue)
                    }
                }

                Picker(L10n.readerBodyFontPicker, selection: $readerBodyFontPresetRawValue) {
                    ForEach(ReaderFontPreset.allCases) { preset in
                        Text(preset.titleKey)
                            .tag(preset.rawValue)
                    }
                }

                Toggle(L10n.settingsMarkReadOnOpenTitle, isOn: $markArticleReadOnSelection)

                Text(L10n.settingsMarkReadOnOpenDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
