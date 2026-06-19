import SwiftUI

struct SettingsView: View {
    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true

    var body: some View {
        Form {
            Section("Lesen") {
                Toggle("Artikel beim Öffnen als gelesen markieren", isOn: $markArticleReadOnSelection)

                Text("Wenn diese Option aktiv ist, markiert Feedivo einen Artikel als gelesen, sobald du ihn in der Liste öffnest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
