import SwiftUI

struct SettingsView: View {
    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true

    var body: some View {
        Form {
            Section(L10n.settingsReadingSection) {
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
