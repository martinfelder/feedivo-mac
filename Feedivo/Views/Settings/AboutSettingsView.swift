// Feedivo/Views/Settings/AboutSettingsView.swift
import AppKit
import SwiftUI

/// Settings-Tab "Über": App-Icon, Version, manueller Update-Check-Button, ein Schalter
/// für den automatischen Sparkle-Check, ein Link zum GitHub-Repository sowie die
/// Versionshistorie (direkt eingebettet, kein separates Fenster - Nutzerwunsch nach dem
/// ersten Live-Eindruck). Seit der Umstellung auf Sparkles eigenen `SPUStandardUserDriver`
/// (2026-08-02, analog NetNewsWire) zeigt Sparkle Fortschritt/Ergebnis eines Checks in
/// seinen EIGENEN nativen Fenstern - diese View hält deshalb bewusst keinen lokalen
/// "wird gerade geprüft"/"Update gefunden"-Zustand mehr (kein Spinner, kein Badge).
struct AboutSettingsView: View {
    private static let repositoryURL = URL(string: "https://github.com/martinfelder/feedivo-mac")!
    private static let changelogURL = URL(string: "https://github.com/martinfelder/feedivo-mac/blob/main/CHANGELOG.md")!
    private static let maxDisplayedVersions = 15
    private static let historyScrollHeight: CGFloat = 300

    @Environment(\.sparkleUpdateCoordinator) private var coordinator

    @AppStorage(UpdateCheckSettings.isAutomaticCheckEnabledKey)
    private var isAutomaticCheckEnabled = UpdateCheckSettings.defaultIsAutomaticCheckEnabled

    @State private var changelogEntries: [ChangelogEntry] = []

    private var displayedChangelogEntries: [ChangelogEntry] {
        Array(changelogEntries.prefix(Self.maxDisplayedVersions))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeneralSettingsSection(label: Text(L10n.settingsAboutSection) + Text(":")) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Feedivo")
                            .font(.system(size: 15, weight: .semibold))
                        Text(L10n.updateCheckVersionLabel(
                            marketingVersion: AppVersionInfo.marketingVersion,
                            buildNumber: AppVersionInfo.buildNumber
                        ))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)

                Toggle(isOn: $isAutomaticCheckEnabled) {
                    Text(L10n.updateCheckAutomaticCheckTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                .onChange(of: isAutomaticCheckEnabled) { _, newValue in
                    coordinator?.setAutomaticChecksEnabled(newValue)
                }
                GeneralSettingsHelp(L10n.updateCheckAutomaticCheckDescription)

                if coordinator?.isHomebrewInstall == true {
                    // Bei Homebrew-Installationen bleibt SPUUpdater komplett inaktiv
                    // (siehe SparkleUpdateCoordinator.start()) - ein Such-Button hätte
                    // hier keine Wirkung, Updates laufen ausschließlich über
                    // `brew upgrade --cask feedivo`.
                    Text(L10n.updateCheckHomebrewHint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    Button(L10n.updateCheckMenuItem) {
                        coordinator?.checkForUpdatesManually()
                    }
                    .padding(.top, 4)
                }

                Link(destination: Self.repositoryURL) {
                    Text(L10n.settingsAboutGitHubLink)
                        .font(.system(size: 13))
                }
                .padding(.top, 12)

                versionHistorySection
                    .padding(.top, 16)
            }
        }
        .onAppear(perform: loadChangelogEntriesIfNeeded)
    }

    private var versionHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.versionHistorySectionTitle)
                .font(.system(size: 13, weight: .semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(displayedChangelogEntries, id: \.version) { entry in
                        changelogEntryView(entry)
                    }

                    if changelogEntries.count > Self.maxDisplayedVersions {
                        Link(L10n.versionHistoryOlderVersionsLink, destination: Self.changelogURL)
                            .font(.system(size: 11.5))
                    }

                    if changelogEntries.isEmpty {
                        Text(L10n.versionHistoryEmptyState)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Self.historyScrollHeight)
        }
    }

    private func changelogEntryView(_ entry: ChangelogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.version)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(entry.date)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(categorizedGroups(for: entry).enumerated()), id: \.offset) { _, group in
                categorySection(group.category, bullets: group.bullets)
            }
        }
    }

    private func categorySection(_ category: UpdateReleaseNoteCategory, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(category.titleKey)
                    .font(.system(size: 11, weight: .semibold))
            } icon: {
                Image(systemName: category.systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.secondary)

            ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                Text("•  \(bullet)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 4)
    }

    /// Gruppiert die Bullets einer Version per `UpdateReleaseNoteCategorizer` - exakt
    /// dieselbe Kategorisierung, die (vor der Umstellung auf Sparkles eigenen
    /// SPUStandardUserDriver, ADR-010) im "Update gefunden"-Dialog verwendet wurde. Nur
    /// Kategorien mit mindestens einem Eintrag werden gerendert, in fester Reihenfolge
    /// (`UpdateReleaseNoteCategory.allCases`: Neu -> Design -> Fehlerbehebungen -> ... ->
    /// Sonstiges).
    private func categorizedGroups(for entry: ChangelogEntry) -> [(category: UpdateReleaseNoteCategory, bullets: [String])] {
        var bulletsByCategory: [UpdateReleaseNoteCategory: [String]] = [:]
        for bullet in entry.bullets {
            let (category, displayText) = UpdateReleaseNoteCategorizer.categorize(bullet)
            bulletsByCategory[category, default: []].append(displayText)
        }

        return UpdateReleaseNoteCategory.allCases.compactMap { category in
            guard let bullets = bulletsByCategory[category], !bullets.isEmpty else { return nil }
            return (category, bullets)
        }
    }

    private func loadChangelogEntriesIfNeeded() {
        guard changelogEntries.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        changelogEntries = ChangelogParser.parse(markdown)
    }
}
