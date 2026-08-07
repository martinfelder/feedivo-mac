import SwiftUI

/// Eigenständiges Fenster für die Versionshistorie (Info-Tab → "Versionshistorie
/// anzeigen"). Liest die im Bundle mitgelieferte Kopie von CHANGELOG.md (siehe
/// scripts/bump_version.sh, hält beide Dateien synchron) - rein dateibasiert, keine
/// Datenbankanbindung nötig, da sich der Inhalt nur mit einem neuen App-Build ändert.
struct VersionHistoryWindowView: View {
    static let windowID = "version-history-window"

    private static let maxDisplayedEntries = 15
    private static let repositoryChangelogURL = URL(string: "https://github.com/martinfelder/feedivo-mac/blob/main/CHANGELOG.md")!

    @State private var entries: [ChangelogEntry] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(displayedEntries, id: \.version) { entry in
                    versionSection(entry)
                }

                if entries.count > Self.maxDisplayedEntries {
                    Link(L10n.versionHistoryOlderVersionsLink, destination: Self.repositoryChangelogURL)
                        .font(.system(size: 11.5))
                }

                if entries.isEmpty {
                    Text(L10n.versionHistoryEmptyState)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: loadEntries)
    }

    private var displayedEntries: [ChangelogEntry] {
        Array(entries.prefix(Self.maxDisplayedEntries))
    }

    private func versionSection(_ entry: ChangelogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.version)
                    .font(.system(size: 13, weight: .semibold))
                Text(entry.date)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(entry.bullets.enumerated()), id: \.offset) { _, bullet in
                Text("•  \(bullet)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadEntries() {
        guard entries.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        entries = ChangelogParser.parse(markdown)
    }
}
